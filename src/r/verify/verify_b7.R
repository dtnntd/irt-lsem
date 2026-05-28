# Verify B7 applications before B5 final consolidation.

suppressPackageStartupMessages({ library(data.table) })

# Self-contained — relies on cwd being research/irt_lsem/ (set by run_pipeline.sh).
output_dir <- file.path("outputs")
GRADES     <- c(10L, 11L, 12L)
b2_dir <- file.path(output_dir, "b2_calibration")
b7_dir <- file.path(output_dir, "b7_applications")

failures <- character()
ok   <- function(msg) cat("✓", msg, "\n")
fail <- function(msg) {
  cat("✗", msg, "\n")
  failures[length(failures) + 1] <<- msg
}
check <- function(cond, msg_ok, msg_fail) {
  if (isTRUE(cond)) ok(msg_ok) else fail(msg_fail)
}

cat("\n=== B7 Applications Verification ===\n\n")

valid_reasons <- c("none", "slope_bottom_10pct",
                   "large_single_step_drop", "both")

for (grade in GRADES) {
  cat(sprintf("\n--- Grade %d ---\n", grade))

  # ----- B7a early-warning -----
  ew_path <- file.path(b7_dir, sprintf("early_warning_grade_%d.csv", grade))
  if (!file.exists(ew_path)) {
    fail(sprintf("missing: %s", ew_path))
  } else {
    ew <- fread(ew_path)
    needed <- c("iduser", "slope", "max_neg_dtheta",
                "flag_slope", "flag_drop", "flag", "flag_reason")
    check(all(needed %in% names(ew)),
          "early-warning columns present",
          sprintf("missing: %s",
                  paste(setdiff(needed, names(ew)), collapse = ",")))
    n_flagged <- sum(ew$flag, na.rm = TRUE)
    pct_flagged <- 100 * mean(ew$flag, na.rm = TRUE)
    check(n_flagged >= 1,
          sprintf("n_flagged=%d (>=1)", n_flagged),
          "no HS flagged")
    check(pct_flagged <= 25,
          sprintf("pct_flagged=%.1f%% (<=25%% sanity ceiling)", pct_flagged),
          sprintf("pct_flagged=%.1f%% over 25%% ceiling", pct_flagged))
    check(all(ew$flag_reason %in% valid_reasons),
          "flag_reason values valid (4-set)",
          sprintf("invalid flag_reason: %s",
                  paste(setdiff(unique(ew$flag_reason), valid_reasons),
                        collapse = ",")))
  }

  # ----- B7b recommendation demo -----
  rec_path <- file.path(b7_dir, sprintf("recommendation_demo_grade_%d.csv", grade))
  if (!file.exists(rec_path)) {
    fail(sprintf("missing: %s", rec_path))
  } else {
    rec <- fread(rec_path)
    items <- fread(file.path(b2_dir, sprintf("irt_1pl_grade_%d.csv", grade)))
    setnames(items, names(items), tolower(names(items)))

    n_uniq <- uniqueN(rec$iduser)
    check(n_uniq == 10,
          sprintf("recommendation demo has 10 unique HS (got %d)", n_uniq),
          sprintf("recommendation demo has %d unique HS (expected 10)", n_uniq))
    # referential integrity
    bad_qids <- setdiff(unique(rec$question_id), unique(items$question_id))
    check(length(bad_qids) == 0,
          "all question_id ∈ item bank (referential integrity)",
          sprintf("%d unknown question_id in recs", length(bad_qids)))
    if ("abs_diff" %in% names(rec)) {
      pct_ok <- 100 * mean(rec$abs_diff < 0.5, na.rm = TRUE)
      check(pct_ok >= 80,
            sprintf("%.0f%% of recs have abs_diff<0.5 (>=80%%)", pct_ok),
            sprintf("only %.0f%% of recs have abs_diff<0.5", pct_ok))
    }
  }
}

# Summary
cat("\n", strrep("=", 60), "\n", sep = "")
if (length(failures) == 0) {
  cat("B7 ALL CHECKS PASSED.\n")
  quit(status = 0)
} else {
  cat(sprintf("B7 FAILED: %d check(s)\n", length(failures)))
  for (m in failures) cat("  -", m, "\n")
  quit(status = 1)
}
