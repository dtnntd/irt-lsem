# B6: Kalman Smoother — real-time / online estimation layer
#
# Per scope refinement 2026-05-28 (de-cuong MT2 "Kalman/cập nhật đệ quy"):
#   Local-level state-space per HS:
#     state:        θ_it = θ_i,t-1 + u_it,   u_it ~ N(0, q_g)
#     observation:  θ̂_it = θ_it + ε_it,    ε_it ~ N(0, se_it²)  [time-varying H from B3]
#
# Two-pass design:
#   (1) Estimate pooled state-innovation variance q_g per grade by method of moments:
#         Var(Δθ̂) = q + se_t² + se_{t-1}²  →  q̂ = mean(Δθ̂²) - mean(se_t² + se_{t-1}²)
#       (lower-bounded at 1e-6; robust to short series; closed-form, no optim per grade)
#   (2) Given q̂_g, run KFAS::KFS() per HS with time-varying H[,,t] = se_it²
#         → filtered (a, P) + smoothed (alphahat, V) per occasion
#
# Input:  outputs/b3_theta/theta_trajectory_1pl_grade_{10,11,12}.csv
# Output: outputs/b6_kalman/
#   - kalman_smoothed_grade_{N}.csv  per HS×occasion smoothed θ + SE
#   - kalman_pop_metrics.csv         per grade: q, mean SE, smoothing gain
#   - b6_run.log                     timestamped progress log
#   - b6_summary.txt                 text summary

# ----- Auto-install -----
required <- c("data.table", "KFAS")
missing  <- required[!sapply(required, requireNamespace, quietly = TRUE)]
if (length(missing) > 0) {
  cat("Installing missing packages:", paste(missing, collapse = ", "), "\n")
  install.packages(missing, repos = "https://cloud.r-project.org",
                   Ncpus = max(1, parallel::detectCores() - 1))
}

suppressPackageStartupMessages({
  library(data.table)
  library(KFAS)
})

# ----- Config -----
b3_dir <- Sys.getenv("B3_DIR", file.path("outputs", "b3_theta"))
b6_dir <- Sys.getenv("B6_DIR", file.path("outputs", "b6_kalman"))
dir.create(b6_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(b6_dir, "plots"), showWarnings = FALSE, recursive = TRUE)

GRADES <- as.integer(strsplit(Sys.getenv("GRADES", "10,11,12"), ",")[[1]])
SEED   <- 42
set.seed(SEED)

log_path <- file.path(b6_dir, "b6_run.log")
log_msg <- function(...) {
  msg <- paste0(format(Sys.time(), "%H:%M:%S"), " — ",
                paste(..., collapse = " "), "\n")
  cat(msg); flush.console()
  cat(msg, file = log_path, append = TRUE)
}
cat("", file = log_path)  # truncate

# ----- Per-grade Kalman -----
pop_metrics <- list()

for (grade in GRADES) {
  log_msg(sprintf("==================== Grade %d ====================", grade))
  in_path <- file.path(b3_dir, sprintf("theta_trajectory_1pl_grade_%d.csv", grade))
  if (!file.exists(in_path)) {
    log_msg(sprintf("MISSING input: %s — skip grade %d", in_path, grade))
    next
  }
  d <- fread(in_path)
  setorder(d, iduser, day_idx)
  log_msg(sprintf("Loaded %d rows, %d HS", nrow(d), uniqueN(d$iduser)))

  # ----- Step 1: pooled q_g via method of moments on consecutive Δθ̂ -----
  d[, theta_lag := shift(theta, 1, type = "lag"), by = iduser]
  d[, se_lag    := shift(se,    1, type = "lag"), by = iduser]
  d[, dtheta    := theta - theta_lag]
  d[, h_sum     := se^2 + se_lag^2]

  diffs <- d[!is.na(dtheta)]
  mean_dtheta2 <- mean(diffs$dtheta^2, na.rm = TRUE)
  mean_h_sum   <- mean(diffs$h_sum,    na.rm = TRUE)
  q_g <- max(mean_dtheta2 - mean_h_sum, 1e-6)
  log_msg(sprintf("Step 1 (pool q): mean(Δθ̂²)=%.4f, mean(se_t²+se_{t-1}²)=%.4f → q̂=%.5f",
                  mean_dtheta2, mean_h_sum, q_g))

  # clear lag/diff helper cols
  d[, c("theta_lag", "se_lag", "dtheta", "h_sum") := NULL]

  # ----- Step 2: KFS per HS with time-varying H -----
  log_msg("Step 2: running KFS per HS …")
  t0 <- Sys.time()
  user_ids <- unique(d$iduser)
  n_hs <- length(user_ids)

  # pre-allocate result columns
  d[, theta_filtered := NA_real_]
  d[, se_filtered    := NA_real_]
  d[, theta_smooth   := NA_real_]
  d[, se_smooth      := NA_real_]

  n_skip_T1 <- 0L
  n_fail <- 0L
  report_every <- max(1L, n_hs %/% 20L)

  for (idx in seq_along(user_ids)) {
    uid <- user_ids[idx]
    rows <- which(d$iduser == uid)
    Ti <- length(rows)
    if (Ti < 2L) {
      # T=1 case: smoothing == observation; just copy through
      d[rows, theta_filtered := theta]
      d[rows, se_filtered    := se]
      d[rows, theta_smooth   := theta]
      d[rows, se_smooth      := se]
      n_skip_T1 <- n_skip_T1 + 1L
      next
    }
    y_vec <- d$theta[rows]
    h_vec <- d$se[rows]^2          # time-varying observation variance
    H_arr <- array(h_vec, dim = c(1, 1, Ti))

    mod <- tryCatch(
      SSModel(y_vec ~ SSMtrend(degree = 1, Q = list(matrix(q_g))) - 1,
              H = H_arr),
      error = function(e) NULL
    )
    if (is.null(mod)) { n_fail <- n_fail + 1L; next }

    kfs <- tryCatch(KFS(mod, smoothing = c("state", "mean")),
                    error = function(e) NULL)
    if (is.null(kfs)) { n_fail <- n_fail + 1L; next }

    # filtered: a_t (1-step-ahead prediction of state); KFAS stores [1..T+1]
    a_t <- as.numeric(kfs$a[1:Ti])
    P_t <- as.numeric(kfs$P[1, 1, 1:Ti])
    # smoothed
    alpha_hat <- as.numeric(kfs$alphahat)
    V_hat     <- as.numeric(kfs$V[1, 1, 1:Ti])

    d[rows, theta_filtered := a_t]
    d[rows, se_filtered    := sqrt(pmax(P_t, 0))]
    d[rows, theta_smooth   := alpha_hat]
    d[rows, se_smooth      := sqrt(pmax(V_hat, 0))]

    if (idx %% report_every == 0L) {
      log_msg(sprintf("  ... %d / %d HS (%.0f%%)",
                      idx, n_hs, 100 * idx / n_hs))
    }
  }
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  log_msg(sprintf("KFS done in %.2f min. T=1 skipped: %d, failed: %d",
                  elapsed, n_skip_T1, n_fail))

  # ----- Save smoothed CSV -----
  out_cols <- c("iduser", "day_idx", "theta", "se",
                "theta_filtered", "se_filtered",
                "theta_smooth", "se_smooth")
  out <- d[, ..out_cols]
  setnames(out, c("theta", "se"), c("theta_raw", "se_raw"))
  out_path <- file.path(b6_dir, sprintf("kalman_smoothed_grade_%d.csv", grade))
  fwrite(out, out_path)
  log_msg(sprintf("Wrote %s (%d rows)", out_path, nrow(out)))

  # ----- Population metrics -----
  mean_se_raw    <- mean(out$se_raw, na.rm = TRUE)
  mean_se_smooth <- mean(out$se_smooth, na.rm = TRUE)
  # gain in *variance* (more interpretable than SE):
  mean_var_raw    <- mean(out$se_raw^2, na.rm = TRUE)
  mean_var_smooth <- mean(out$se_smooth^2, na.rm = TRUE)
  smoothing_gain  <- 1 - mean_var_smooth / mean_var_raw

  pop_metrics[[as.character(grade)]] <- data.table(
    grade               = grade,
    n_hs                = n_hs,
    n_obs               = nrow(out),
    q_state_variance    = q_g,
    mean_se_raw         = mean_se_raw,
    mean_se_smooth      = mean_se_smooth,
    mean_var_raw        = mean_var_raw,
    mean_var_smooth     = mean_var_smooth,
    mean_smoothing_gain = smoothing_gain,
    n_skip_T1           = n_skip_T1,
    n_fail              = n_fail,
    elapsed_min         = elapsed
  )
  log_msg(sprintf("Grade %d: mean SE %.3f→%.3f (var gain %.1f%%)",
                  grade, mean_se_raw, mean_se_smooth, 100 * smoothing_gain))
}

# ----- Consolidate pop metrics -----
pop_dt <- rbindlist(pop_metrics, fill = TRUE)
pop_path <- file.path(b6_dir, "kalman_pop_metrics.csv")
fwrite(pop_dt, pop_path)
log_msg(sprintf("Wrote %s", pop_path))

# ----- Text summary -----
sink(file.path(b6_dir, "b6_summary.txt"))
cat("B6 Kalman Smoother — Summary\n")
cat("Date:", format(Sys.time()), "\n\n")
cat("Model: local-level state-space, time-varying H_t = se_t² from B3\n")
cat("Pool: q̂_g per grade via method of moments on consecutive Δθ̂.\n\n")
cat("=== Population metrics ===\n")
print(pop_dt)
sink()
log_msg("B6 complete.")
