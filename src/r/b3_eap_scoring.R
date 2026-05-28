# B3: EAP Scoring per (student, day) using 1PL Rasch
#
# Input:
#   - outputs/b2_calibration/mirt_1pl_grade_{N}.rds        (calibrated mirt model)
#   - outputs/b0_preprocessed/response_long_grade_{N}_exam.csv
# Output:
#   - outputs/b3_theta/theta_trajectory_1pl_grade_{N}.csv
#     columns: iduser, day_idx, date, n_items, theta, se
#
# Method:
#   For each (student, day_idx), build a response vector aligned to calibrated
#   items, fill 0/1 where answered, NA elsewhere, then fscores(method="EAP").
#   Process in batches of students to limit memory use.
#
# Decision:
#   Only 1PL used (per decisions_log 2026-05-26).
#   2PL skipped due to ~3-6% degenerate items; can run later as supplementary.
#
# Usage:
#   Rscript src/r/b3_eap_scoring.R
# Override:
#   B0_DIR, B2_DIR, B3_DIR env vars
#   FORCE_RERUN=TRUE to recompute even if outputs exist
#   BATCH_SIZE=500 to control memory (default 500 students/batch)

suppressPackageStartupMessages({
  library(data.table)
  library(mirt)
})

set.seed(42)

# ---- Paths ----
b0_dir <- Sys.getenv("B0_DIR", file.path("outputs", "b0_preprocessed"))
b2_dir <- Sys.getenv("B2_DIR", file.path("outputs", "b2_calibration"))
b3_dir <- Sys.getenv("B3_DIR", file.path("outputs", "b3_theta"))
dir.create(b3_dir, showWarnings = FALSE, recursive = TRUE)

GRADES      <- c(10, 11, 12)
BATCH_SIZE  <- as.integer(Sys.getenv("BATCH_SIZE", "500"))
FORCE_RERUN <- as.logical(Sys.getenv("FORCE_RERUN", "FALSE"))

# ---- Logging ----
log_msg <- function(...) {
  cat(format(Sys.time(), "%H:%M:%S"), "—", ..., "\n")
  flush.console()
}

# ---- Score one batch of (HS, day) measurements ----
score_batch <- function(rl_batch, calibrated_items, mirt_obj) {
  # Dedup per (iduser, day_idx, item)
  rl_dedup <- rl_batch[
    question_id %in% calibrated_items,
    .(is_correct = is_correct[1]),
    by = .(iduser, day_idx, question_id)
  ]

  # Pivot wide: rows = (iduser, day_idx), cols = item
  wide <- dcast(rl_dedup, iduser + day_idx ~ question_id, value.var = "is_correct")

  meta <- wide[, .(iduser, day_idx)]
  resp_cols <- setdiff(names(wide), c("iduser", "day_idx"))

  # Build response matrix aligned to calibration items
  M <- matrix(NA_integer_, nrow = nrow(wide), ncol = length(calibrated_items))
  colnames(M) <- calibrated_items
  if (length(resp_cols) > 0) {
    cols_in_cal <- intersect(resp_cols, calibrated_items)
    if (length(cols_in_cal) > 0) {
      M[, cols_in_cal] <- as.matrix(wide[, cols_in_cal, with = FALSE])
    }
  }

  # n_items answered per row (for diagnostic)
  n_items_per_row <- rowSums(!is.na(M))

  # EAP scoring
  eap <- fscores(mirt_obj, response.pattern = M, method = "EAP")

  data.table(
    iduser  = meta$iduser,
    day_idx = meta$day_idx,
    n_items = n_items_per_row,
    theta   = eap[, 1],
    se      = eap[, 2]
  )
}

# ---- Score one grade ----
score_grade <- function(grade) {
  cat("\n", strrep("=", 60), "\n", sep = "")
  log_msg(sprintf("B3 GRADE %d — START", grade))
  cat(strrep("=", 60), "\n", sep = "")

  out_path <- file.path(b3_dir, paste0("theta_trajectory_1pl_grade_", grade, ".csv"))
  if (!FORCE_RERUN && file.exists(out_path)) {
    log_msg(sprintf("Output exists, skipping: %s", out_path))
    return(invisible(NULL))
  }

  # ---- Load mirt object ----
  rds_path <- file.path(b2_dir, paste0("mirt_1pl_grade_", grade, ".rds"))
  log_msg(sprintf("Loading mirt 1PL: %s", rds_path))
  m1pl <- readRDS(rds_path)
  calibrated_items <- colnames(m1pl@Data$data)
  log_msg(sprintf("Calibrated items: %d", length(calibrated_items)))

  # ---- Load response long + day mapping ----
  log_msg("Loading response data...")
  rl <- fread(file.path(b0_dir, paste0("response_long_grade_", grade, "_exam.csv")))
  log_msg(sprintf("Responses: %s rows", format(nrow(rl), big.mark = ",")))

  # Date lookup per (iduser, day_idx)
  date_lookup <- unique(rl[, .(iduser, day_idx, date)])

  # ---- Filter to calibrated items ----
  n_before <- nrow(rl)
  rl <- rl[question_id %in% calibrated_items]
  log_msg(sprintf("After filtering to calibrated items: %s rows (%.1f%% kept)",
                  format(nrow(rl), big.mark = ","), 100 * nrow(rl) / n_before))

  # ---- Batch over students ----
  hs_list <- unique(rl$iduser)
  n_hs <- length(hs_list)
  n_batches <- ceiling(n_hs / BATCH_SIZE)
  log_msg(sprintf("Scoring %d students in %d batches of %d",
                  n_hs, n_batches, BATCH_SIZE))

  results <- vector("list", n_batches)
  t_start <- Sys.time()

  for (i in seq_len(n_batches)) {
    idx_start <- (i - 1) * BATCH_SIZE + 1
    idx_end   <- min(i * BATCH_SIZE, n_hs)
    batch_hs  <- hs_list[idx_start:idx_end]
    rl_batch  <- rl[iduser %in% batch_hs]

    results[[i]] <- score_batch(rl_batch, calibrated_items, m1pl)

    # Progress
    if (i %% max(1, floor(n_batches / 10)) == 0 || i == n_batches) {
      elapsed_min <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
      eta_min <- elapsed_min / i * (n_batches - i)
      log_msg(sprintf("  batch %d/%d (%.1f%%) | elapsed %.1fm | ETA %.1fm",
                      i, n_batches, 100 * i / n_batches, elapsed_min, eta_min))
    }
  }

  combined <- rbindlist(results)

  # ---- Add date ----
  combined <- merge(combined, date_lookup, by = c("iduser", "day_idx"), all.x = TRUE)
  setcolorder(combined, c("iduser", "day_idx", "date", "n_items", "theta", "se"))

  # ---- Save ----
  fwrite(combined, out_path)
  log_msg(sprintf("Saved: %s (%d rows)", out_path, nrow(combined)))

  # ---- Quick diagnostics ----
  log_msg(sprintf("θ summary: mean=%.3f sd=%.3f min=%.3f max=%.3f",
                  mean(combined$theta, na.rm = TRUE),
                  sd(combined$theta, na.rm = TRUE),
                  min(combined$theta, na.rm = TRUE),
                  max(combined$theta, na.rm = TRUE)))
  log_msg(sprintf("SE summary: median=%.3f mean=%.3f",
                  median(combined$se, na.rm = TRUE),
                  mean(combined$se, na.rm = TRUE)))

  rm(m1pl, rl, results, combined); gc(verbose = FALSE)
}

# ---- Main ----
cat(strrep("#", 60), "\n", sep = "")
cat("B3: EAP SCORING per (HS, day) — 1PL only\n")
cat(strrep("#", 60), "\n", sep = "")
log_msg(sprintf("BATCH_SIZE=%d | FORCE_RERUN=%s", BATCH_SIZE, FORCE_RERUN))

for (g in GRADES) {
  score_grade(g)
}

log_msg("B3 complete.")
