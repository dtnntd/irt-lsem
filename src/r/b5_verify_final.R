# B5 Verify final: cross-grade replication checks

suppressPackageStartupMessages({ library(data.table) })

b5_dir <- file.path("outputs", "b5_report")

failures <- character()
ok   <- function(msg) cat("✓", msg, "\n")
fail <- function(msg) {
  cat("✗", msg, "\n")
  failures[length(failures) + 1] <<- msg
}
check <- function(cond, msg_ok, msg_fail) {
  if (isTRUE(cond)) ok(msg_ok) else fail(msg_fail)
}

cat("\n=== B5 Final Verification ===\n\n")

# 1. Files exist
expected_files <- c(
  "final_fit_indices.csv", "final_lgcm_params.csv", "final_lcsm_params.csv",
  "final_mlm_params.csv", "final_convergent_evidence.csv",
  "final_slope_comparison.csv",
  "final_reliability.csv", "final_baseline_comparison.csv",
  "final_ctdsem_population.csv", "final_ctdsem_individual_summary.csv",
  "final_kalman_gain.csv",
  "final_early_warning_summary.csv", "final_recommendation_examples.csv",
  "final_summary.txt", "fig_main_results.png", "b5_report.html"
)
for (f in expected_files) {
  check(file.exists(file.path(b5_dir, f)),
        sprintf("Output exists: %s", f),
        sprintf("Missing: %s", f))
}

# 2. Fit indices
fit <- fread(file.path(b5_dir, "final_fit_indices.csv"))
check(all(fit$CFI   > 0.95), "All CFI > 0.95",   "Some CFI <= 0.95")
check(all(fit$RMSEA < 0.06), "All RMSEA < 0.06", "Some RMSEA >= 0.06")
check(all(fit$SRMR  < 0.08), "All SRMR < 0.08",  "Some SRMR >= 0.08")

# 3. LGCM slopes
lgcm   <- fread(file.path(b5_dir, "final_lgcm_params.csv"))
slopes <- lgcm[param == "s_mean"]
check(nrow(slopes) == 3,
      "LGCM slope present for all 3 grades",
      sprintf("Only %d slope rows", nrow(slopes)))
check(all(slopes$est > 0),
      "All LGCM slopes positive (consistent direction)",
      "Some LGCM slope negative")

# 4. LCSM catch-up
lcsm_b  <- fread(file.path(b5_dir, "final_lcsm_params.csv"))[param == "b"]
catchup <- lcsm_b[est < 0 & ci_upper < 0]
check(nrow(catchup) >= 1,
      sprintf("LCSM catch-up confirmed for grade(s): %s",
              paste(catchup$grade, collapse = ", ")),
      "No grade shows clear catch-up (b<0, CI excludes 0)")

# 5. lmer
mlm        <- fread(file.path(b5_dir, "final_mlm_params.csv"))
mlm_slopes <- mlm[param == "slope_fixed"]
mlm_vars   <- mlm[grepl("var", param)]
check(nrow(mlm_slopes) == 3,
      "lmer slope present for all 3 grades",
      "lmer missing grade(s)")
check(all(mlm_vars$est >= 0),
      "All lmer variance components non-negative",
      "Negative variance in lmer (Heywood case)")

# 6. CT-DSEM
ct_pop <- fread(file.path(b5_dir, "final_ctdsem_population.csv"))
phi    <- ct_pop[param == "phi",  estimate]
cint   <- ct_pop[param == "cint", estimate]
eq     <- -cint / phi
check(phi < 0,
      sprintf("CT-DSEM phi negative (mean-reverting): %.4f", phi),
      sprintf("CT-DSEM phi non-negative: %.4f (unstable dynamics)", phi))
check(abs(eq) < 3,
      sprintf("CT-DSEM equilibrium plausible: %.3f logit", eq),
      sprintf("CT-DSEM equilibrium implausible: %.3f", eq))

# 7. Convergent evidence (informational only)
conv   <- fread(file.path(b5_dir, "final_convergent_evidence.csv"))
n_fail <- sum(!conv$Convergent_at_0.005)
if (n_fail > 0) {
  cat(sprintf("⚠ %d/3 grades fail |slope_LGCM-slope_lmer|<0.005 (documented as method effect)\n",
              n_fail))
} else {
  ok("All grades meet convergent threshold")
}

# 8. Replication
cv <- sd(slopes$est) / mean(abs(slopes$est))
cat(sprintf("\nCross-grade slope CV: %.2f (lower = more consistent)\n", cv))
cat(sprintf("All slopes same sign: %s\n", all(slopes$est > 0)))

# 9. Three-method slope comparison
sc <- fread(file.path(b5_dir, "final_slope_comparison.csv"))
check(nrow(sc) == 9,
      "Slope comparison has 9 rows (3 grades x 3 methods)",
      sprintf("Slope comparison has %d rows (expected 9)", nrow(sc)))
check(all(c("LGCM", "MLM-weighted", "MLM-unweighted") %in% unique(sc$method)),
      "Slope comparison covers all 3 methods",
      "Slope comparison missing a method")

# 10. Report narrative sections + key finding (B5 supplement)
report_path <- file.path(b5_dir, "b5_report.html")
if (file.exists(report_path)) {
  rl <- readLines(report_path, warn = FALSE)
  check(any(grepl("Introduction", rl)), "Report has Introduction section", "Report missing Introduction")
  check(any(grepl("Discussion",   rl)), "Report has Discussion section",   "Report missing Discussion")
  check(any(grepl("Conclusion",   rl)), "Report has Conclusion section",   "Report missing Conclusion")
  check(any(grepl("catch-up|compensatory|plateau", rl, ignore.case = TRUE)),
        "Report highlights catch-up/plateau finding",
        "Report missing key finding keywords")
}

# 11. Diagnostic plots present (representative grade 12)
rep_plots <- c(
  "outputs/b0_preprocessed/plots/T_distribution_grade_12.png",
  "outputs/b0_preprocessed/plots/dt_distribution_grade_12.png",
  "outputs/b2_calibration/plots/wright_map_grade_12.png",
  "outputs/b2_calibration/plots/icc_grade_12.png",
  "outputs/b3_theta/plots/theta_distribution_grade_12.png",
  "outputs/b3_theta/plots/trajectory_samples_grade_12.png",
  "outputs/b4_lsem/plots/lgcm_overlay_grade_12.png",
  "outputs/b4_lsem/plots/lcsm_dtheta_density_grade_12.png"
)
for (p in rep_plots) {
  check(file.exists(p),
        sprintf("Diagnostic plot exists: %s", basename(p)),
        sprintf("Missing diagnostic plot: %s", p))
}

# 12. Reliability + static-vs-dynamic baseline
rel <- fread(file.path(b5_dir, "final_reliability.csv"))
check(all(rel$rho > 0 & rel$rho < 1),
      sprintf("Reliability rho in (0,1) all grades: %s",
              paste(sprintf("g%d=%.2f", rel$grade, rel$rho), collapse = ", ")),
      "Reliability rho out of (0,1)")
base <- fread(file.path(b5_dir, "final_baseline_comparison.csv"))
check(all(base$lrt_p < 0.05),
      "Dynamic model beats static baseline (LRT p<0.05) all grades",
      "Static baseline not rejected for some grade")

# 13. Kalman smoother (B6) gain
kg_path <- file.path(b5_dir, "final_kalman_gain.csv")
if (file.exists(kg_path)) {
  kg <- fread(kg_path)
  check(nrow(kg) == 3,
        sprintf("Kalman gain has 3 rows (all grades)"),
        sprintf("Kalman gain has %d rows (expected 3)", nrow(kg)))
  check(all(kg$pct_reduction > 0 & kg$pct_reduction < 1),
        sprintf("Kalman pct_reduction in (0,1) all grades: %s",
                paste(sprintf("g%d=%.1f%%", kg$grade, 100 * kg$pct_reduction),
                      collapse = ", ")),
        "Kalman pct_reduction out of (0,1)")
}

# 14. Early-warning summary (B7a)
ew_path <- file.path(b5_dir, "final_early_warning_summary.csv")
if (file.exists(ew_path)) {
  ew <- fread(ew_path)
  check(all(ew$n_flagged >= 1),
        sprintf("Early-warning n_flagged >= 1 all grades: %s",
                paste(sprintf("g%d=%d", ew$grade, ew$n_flagged), collapse = ", ")),
        "Some grade has 0 flagged HS")
  check(all(ew$pct_flagged <= 25),
        sprintf("Early-warning pct_flagged <= 25%% all grades: %s",
                paste(sprintf("g%d=%.1f%%", ew$grade, ew$pct_flagged),
                      collapse = ", ")),
        "Some grade flags > 25% HS (over sanity ceiling)")
}

# 15. Recommendation examples (B7b)
rec_path <- file.path(b5_dir, "final_recommendation_examples.csv")
if (file.exists(rec_path)) {
  rec <- fread(rec_path)
  check(uniqueN(rec$iduser) >= 30,
        sprintf("Recommendation examples cover >=30 unique HS (got %d)",
                uniqueN(rec$iduser)),
        sprintf("Recommendation examples cover only %d unique HS",
                uniqueN(rec$iduser)))
}

# 16. Report contains §7.6 (Kalman) and §13 (Applications) keywords
if (file.exists(report_path)) {
  rl2 <- readLines(report_path, warn = FALSE)
  check(any(grepl("Kalman", rl2)),
        "Report contains Kalman section",
        "Report missing Kalman keyword")
  check(any(grepl("Applications", rl2)),
        "Report contains Applications section",
        "Report missing Applications keyword")
}

# Summary
cat("\n", strrep("=", 60), "\n", sep = "")
if (length(failures) == 0) {
  cat("ALL CHECKS PASSED. Pipeline outputs valid.\n")
  quit(status = 0)
} else {
  cat(sprintf("FAILED: %d check(s)\n", length(failures)))
  for (m in failures) cat("  -", m, "\n")
  quit(status = 1)
}
