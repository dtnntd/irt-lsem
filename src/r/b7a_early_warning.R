# B7a: Early-warning — flag at-risk HS
#
# Per scope refinement 2026-05-28 (de-cuong MT4(a) "phát hiện sớm HS giảm năng lực"):
#   Combine two signals on B3 trajectory + B4a lmer random slopes:
#     (a) slope_i = fixef(day_idx) + ranef$iduser$day_idx
#         flag_slope := slope_i  < quantile(slope, 0.10)     (relative)
#     (b) max_neg_dtheta_i = min(diff(theta_i, day_idx order))
#         flag_drop  := max_neg_dtheta_i < -0.5              (absolute, ~1 SE)
#   Restrict to HS with T >= 3 (slope identifiable).
#
# Output is a candidate list for human review — NOT a deterministic classifier.
# See §13.1 of report.
#
# Input:  outputs/b3_theta/theta_trajectory_1pl_grade_{N}.csv
#         outputs/b4_lsem/mlm_grade_{N}.rds          (lme4 fit, with weights=1/se²)
# Output: outputs/b7_applications/early_warning_grade_{N}.csv
#         outputs/b7_applications/b7a_run.log

# ----- Auto-install -----
required <- c("data.table", "lme4")
missing  <- required[!sapply(required, requireNamespace, quietly = TRUE)]
if (length(missing) > 0) {
  cat("Installing missing packages:", paste(missing, collapse = ", "), "\n")
  install.packages(missing, repos = "https://cloud.r-project.org",
                   Ncpus = max(1, parallel::detectCores() - 1))
}

suppressPackageStartupMessages({
  library(data.table)
  library(lme4)
  library(bit64)
})

# ----- Config -----
b3_dir <- Sys.getenv("B3_DIR", file.path("outputs", "b3_theta"))
b4_dir <- Sys.getenv("B4_DIR", file.path("outputs", "b4_lsem"))
b6_dir <- Sys.getenv("B6_DIR", file.path("outputs", "b6_kalman"))
b7_dir <- Sys.getenv("B7_DIR", file.path("outputs", "b7_applications"))
dir.create(b7_dir, showWarnings = FALSE, recursive = TRUE)

GRADES <- as.integer(strsplit(Sys.getenv("GRADES", "10,11,12"), ",")[[1]])
MIN_T  <- 3L
# Drop signal computed on Kalman-smoothed θ (B6) when available, raw EAP otherwise.
# Smoothed mean SE ≈ 0.40 logit, so |Δθ_smooth| > 1.0 logit ≈ 2.5 SE — meaningful drop, not noise.
DROP_THRESHOLD <- -1.0
SLOPE_TAIL_Q   <- 0.10

log_path <- file.path(b7_dir, "b7a_run.log")
log_msg <- function(...) {
  msg <- paste0(format(Sys.time(), "%H:%M:%S"), " — ",
                paste(..., collapse = " "), "\n")
  cat(msg); flush.console()
  cat(msg, file = log_path, append = TRUE)
}
cat("", file = log_path)

# ----- Helper: extract per-HS slopes (with fallback refit) -----
extract_slopes <- function(grade) {
  rds_path <- file.path(b4_dir, sprintf("mlm_grade_%d.rds", grade))
  theta_path <- file.path(b3_dir, sprintf("theta_trajectory_1pl_grade_%d.csv", grade))
  d <- fread(theta_path)
  d <- d[!is.na(theta) & se > 0]

  fit <- NULL
  if (file.exists(rds_path)) {
    fit <- tryCatch(readRDS(rds_path), error = function(e) {
      log_msg(sprintf("readRDS(%s) failed: %s — refitting", rds_path,
                      conditionMessage(e)))
      NULL
    })
  } else {
    log_msg(sprintf("RDS missing for grade %d — refitting", grade))
  }

  if (is.null(fit)) {
    log_msg(sprintf("Refitting lmer for grade %d ...", grade))
    fit <- lmer(theta ~ day_idx + (1 + day_idx | iduser),
                data = d, weights = 1 / se^2, REML = TRUE,
                control = lmerControl(optimizer = "bobyqa"))
  }

  fix_slope <- fixef(fit)["day_idx"]
  ran <- ranef(fit)$iduser
  # iduser is int64 in B3 → use bit64::as.integer64 to round-trip via rownames safely.
  out <- data.table(
    iduser = bit64::as.integer64(rownames(ran)),
    slope_random = ran$day_idx
  )
  out[, slope := slope_random + fix_slope]
  rm(fit); gc(verbose = FALSE)
  list(slopes = out, fix_slope = unname(fix_slope))
}

# ----- Per-grade flagging -----
summary_rows <- list()

for (grade in GRADES) {
  log_msg(sprintf("==================== Grade %d ====================", grade))

  s <- extract_slopes(grade)
  slopes <- s$slopes
  log_msg(sprintf("Fixed slope=%.5f, %d HS with random slope", s$fix_slope, nrow(slopes)))

  # Use Kalman-smoothed θ for drop signal (lower SE → "drop" is meaningful).
  # Fall back to raw B3 θ̂ if B6 outputs not yet generated.
  b6_path <- file.path(b6_dir, sprintf("kalman_smoothed_grade_%d.csv", grade))
  if (file.exists(b6_path)) {
    log_msg("Using Kalman-smoothed θ from B6 for drop signal")
    d <- fread(b6_path)
    d[, theta_for_drop := theta_smooth]
  } else {
    log_msg("B6 output not found — using raw B3 θ̂ for drop signal")
    d <- fread(file.path(b3_dir, sprintf("theta_trajectory_1pl_grade_%d.csv", grade)))
    d[, theta_for_drop := theta]
  }
  setorder(d, iduser, day_idx)
  d[, dtheta := theta_for_drop - shift(theta_for_drop), by = iduser]
  d[, n_obs  := .N, by = iduser]
  dt_per_hs <- d[!is.na(dtheta), .(max_neg_dtheta = min(dtheta, na.rm = TRUE)),
                 by = iduser]
  n_obs_per_hs <- unique(d[, .(iduser, n_obs)])

  full <- merge(slopes, n_obs_per_hs, by = "iduser", all.x = TRUE)
  full <- merge(full, dt_per_hs, by = "iduser", all.x = TRUE)

  # Restrict to HS with T >= 3 for stable slope-based flagging
  elig <- full[n_obs >= MIN_T]
  log_msg(sprintf("Eligible (T>=%d): %d / %d HS", MIN_T, nrow(elig), nrow(full)))

  slope_cut <- quantile(elig$slope, SLOPE_TAIL_Q, na.rm = TRUE)
  elig[, flag_slope := slope < slope_cut]
  elig[, flag_drop  := !is.na(max_neg_dtheta) & max_neg_dtheta < DROP_THRESHOLD]
  elig[, flag       := flag_slope | flag_drop]
  elig[, flag_strict := flag_slope & flag_drop]
  elig[, flag_reason := fifelse(flag_slope & flag_drop, "both",
                          fifelse(flag_slope,           "slope_bottom_10pct",
                            fifelse(flag_drop,          "large_single_step_drop",
                                                        "none")))]

  out <- elig[, .(iduser, n_obs, slope, max_neg_dtheta,
                  flag_slope, flag_drop, flag, flag_strict, flag_reason)]
  setorder(out, -flag, slope)

  out_path <- file.path(b7_dir, sprintf("early_warning_grade_%d.csv", grade))
  fwrite(out, out_path)
  log_msg(sprintf("Wrote %s (%d rows, %d flagged, %.1f%%)",
                  out_path, nrow(out), sum(out$flag),
                  100 * mean(out$flag)))

  summary_rows[[as.character(grade)]] <- data.table(
    grade           = grade,
    n_total         = nrow(out),
    n_flagged       = sum(out$flag),
    pct_flagged     = round(100 * mean(out$flag), 2),
    n_slope_only    = sum(out$flag_slope & !out$flag_drop),
    n_drop_only     = sum(!out$flag_slope & out$flag_drop),
    n_both          = sum(out$flag_strict),
    slope_cutoff    = slope_cut,
    drop_threshold  = DROP_THRESHOLD
  )
}

summary_dt <- rbindlist(summary_rows)
log_msg("Per-grade summary:")
print(summary_dt)

# Don't write a separate summary CSV here — that's consolidated in b5_consolidate.R.
# But keep a text log of the picks.
sink(file.path(b7_dir, "b7a_summary.txt"))
cat("B7a Early-warning — Summary\n")
cat("Date:", format(Sys.time()), "\n")
cat(sprintf("Criteria: slope < quantile(slope, %.2f) OR min(Δθ) < %.2f, T >= %d\n",
            SLOPE_TAIL_Q, DROP_THRESHOLD, MIN_T))
cat("\n")
print(summary_dt)
sink()

log_msg("B7a complete.")
