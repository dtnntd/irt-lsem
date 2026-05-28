# Verify B6 Kalman outputs before B5 final consolidation.
# Pattern mirrors b5_verify_final.R: check/ok/fail + accumulator + quit(status=).

suppressPackageStartupMessages({ library(data.table) })

# Self-contained — relies on cwd being research/irt_lsem/ (set by run_pipeline.sh).
output_dir <- file.path("outputs")
GRADES     <- c(10L, 11L, 12L)
b3_dir <- file.path(output_dir, "b3_theta")
b6_dir <- file.path(output_dir, "b6_kalman")

failures <- character()
ok   <- function(msg) cat("✓", msg, "\n")
fail <- function(msg) {
  cat("✗", msg, "\n")
  failures[length(failures) + 1] <<- msg
}
check <- function(cond, msg_ok, msg_fail) {
  if (isTRUE(cond)) ok(msg_ok) else fail(msg_fail)
}

cat("\n=== B6 Kalman Verification ===\n\n")

# 1. pop_metrics CSV exists and has 3 rows
pop_path <- file.path(b6_dir, "kalman_pop_metrics.csv")
check(file.exists(pop_path),
      sprintf("pop metrics exists: %s", basename(pop_path)),
      sprintf("missing: %s", pop_path))
if (file.exists(pop_path)) {
  pop <- fread(pop_path)
  check(nrow(pop) == length(GRADES),
        sprintf("pop_metrics has %d rows (expected %d)", nrow(pop), length(GRADES)),
        sprintf("pop_metrics has %d rows (expected %d)", nrow(pop), length(GRADES)))
  check(all(pop$mean_smoothing_gain > 0 & pop$mean_smoothing_gain < 1),
        sprintf("smoothing_gain in (0,1) all grades: %s",
                paste(sprintf("g%d=%.1f%%", pop$grade,
                              100 * pop$mean_smoothing_gain), collapse = ", ")),
        "smoothing_gain out of (0,1)")
  check(all(pop$q_state_variance > 0),
        sprintf("q_state_variance positive all grades: %s",
                paste(sprintf("g%d=%.4f", pop$grade, pop$q_state_variance),
                      collapse = ", ")),
        "q non-positive")
}

# 2. Per-grade smoothed CSV
for (grade in GRADES) {
  cat(sprintf("\n--- Grade %d ---\n", grade))
  out_path <- file.path(b6_dir, sprintf("kalman_smoothed_grade_%d.csv", grade))
  b3_path  <- file.path(b3_dir, sprintf("theta_trajectory_1pl_grade_%d.csv", grade))
  if (!file.exists(out_path)) {
    fail(sprintf("missing: %s", out_path)); next
  }
  s <- fread(out_path)
  b3 <- fread(b3_path)
  check(nrow(s) == nrow(b3),
        sprintf("row count matches B3: %d", nrow(s)),
        sprintf("row count mismatch: B6=%d B3=%d", nrow(s), nrow(b3)))
  check(all(c("theta_raw", "se_raw", "theta_smooth", "se_smooth") %in% names(s)),
        "expected columns present",
        sprintf("missing columns: %s",
                paste(setdiff(c("theta_raw","se_raw","theta_smooth","se_smooth"),
                              names(s)), collapse=",")))
  check(sum(is.na(s$theta_smooth)) == 0,
        "no NA in theta_smooth",
        sprintf("%d NA in theta_smooth", sum(is.na(s$theta_smooth))))
  check(all(abs(s$theta_smooth) < 6, na.rm = TRUE),
        "|theta_smooth| < 6 all rows",
        "extreme theta_smooth (|θ| >= 6) present")
  check(all(s$se_smooth > 0, na.rm = TRUE),
        "se_smooth > 0 all rows",
        sprintf("%d non-positive se_smooth", sum(s$se_smooth <= 0, na.rm = TRUE)))
  m_raw    <- mean(s$se_raw,    na.rm = TRUE)
  m_smooth <- mean(s$se_smooth, na.rm = TRUE)
  check(m_smooth <= m_raw,
        sprintf("mean(SE_smooth)=%.3f <= mean(SE_raw)=%.3f", m_smooth, m_raw),
        sprintf("smoother increased SE: %.3f > %.3f", m_smooth, m_raw))
}

# 3. At least one plot per grade
for (grade in GRADES) {
  any_plot <- list.files(file.path(b6_dir, "plots"),
                         pattern = sprintf("grade_%d", grade),
                         full.names = FALSE)
  check(length(any_plot) >= 1,
        sprintf("≥1 plot present for grade %d (%d files)", grade, length(any_plot)),
        sprintf("no plot for grade %d", grade))
}

# 4. Cross-grade gain plot
check(file.exists(file.path(b6_dir, "plots", "kalman_pop_gain.png")),
      "cross-grade pop_gain plot exists",
      "missing kalman_pop_gain.png")

# Summary
cat("\n", strrep("=", 60), "\n", sep = "")
if (length(failures) == 0) {
  cat("B6 ALL CHECKS PASSED.\n")
  quit(status = 0)
} else {
  cat(sprintf("B6 FAILED: %d check(s)\n", length(failures)))
  for (m in failures) cat("  -", m, "\n")
  quit(status = 1)
}
