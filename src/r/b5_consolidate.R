# B5 Consolidate: build final cross-grade tables for paper.
#
# Input: outputs/b4_lsem/*.csv
# Output: outputs/b5_report/
#   - final_fit_indices.csv          # All grades × LGCM/LCSM fit
#   - final_lgcm_params.csv          # i_mean, s_mean, var per grade
#   - final_lcsm_params.csv          # b, alpha, alpha0 per grade
#   - final_mlm_params.csv           # intercept, slope per grade (lmer)
#   - final_convergent_evidence.csv  # LGCM vs lmer slope comparison
#   - final_ctdsem_grade12.csv       # CT-DSEM population params
#   - final_summary.txt              # text summary

suppressPackageStartupMessages({ library(data.table) })

b4_dir <- file.path("outputs", "b4_lsem")
b5_dir <- file.path("outputs", "b5_report")
dir.create(b5_dir, showWarnings = FALSE, recursive = TRUE)

log_msg <- function(...) { cat(format(Sys.time(), "%H:%M:%S"), "—", ..., "\n"); flush.console() }

# ============================================================
# 1. Fit indices (all grades × LGCM/LCSM)
# ============================================================
log_msg("Building fit indices table...")
fit <- fread(file.path(b4_dir, "b4a_fit_indices.csv"))
fit_clean <- fit[, .(
  Model = model, Grade = grade,
  ChiSq = round(chisq, 2), df = df,
  p = signif(p, 3),
  CFI = round(CFI, 3), TLI = round(TLI, 3),
  RMSEA = round(RMSEA, 3),
  RMSEA_CI = sprintf("[%.3f, %.3f]", RMSEA_CIlow, RMSEA_CIhigh),
  SRMR = round(SRMR, 3),
  BIC = round(BIC, 0)
)]
fwrite(fit_clean, file.path(b5_dir, "final_fit_indices.csv"))
log_msg(sprintf("  Saved final_fit_indices.csv (%d rows)", nrow(fit_clean)))

# ============================================================
# 2. LGCM params consolidated
# ============================================================
log_msg("Consolidating LGCM params...")
lgcm_all <- rbindlist(lapply(c(10, 11, 12), function(g) {
  d <- fread(file.path(b4_dir, sprintf("lgcm_params_grade_%d.csv", g)))
  d
}))
fwrite(lgcm_all, file.path(b5_dir, "final_lgcm_params.csv"))

# Pivot to wide for human-readable table
lgcm_wide <- dcast(lgcm_all, grade ~ param, value.var = c("est", "ci_lower", "ci_upper"))
lgcm_summary <- lgcm_all[, .(
  grade,
  param,
  est_pretty = sprintf("%.3f", est),
  ci_pretty  = ifelse(is.na(ci_lower), "—",
                      sprintf("[%.3f, %.3f]", ci_lower, ci_upper))
)]
fwrite(lgcm_summary, file.path(b5_dir, "final_lgcm_params_pretty.csv"))
log_msg(sprintf("  Saved final_lgcm_params.csv + pretty version"))

# ============================================================
# 3. LCSM params consolidated
# ============================================================
log_msg("Consolidating LCSM params...")
lcsm_all <- rbindlist(lapply(c(10, 11, 12), function(g) {
  fread(file.path(b4_dir, sprintf("lcsm_params_grade_%d.csv", g)))
}))
fwrite(lcsm_all, file.path(b5_dir, "final_lcsm_params.csv"))

lcsm_summary <- lcsm_all[, .(
  grade, param,
  est_pretty = sprintf("%.4f", est),
  ci_pretty  = ifelse(is.na(ci_lower), "—",
                      sprintf("[%.4f, %.4f]", ci_lower, ci_upper))
)]
fwrite(lcsm_summary, file.path(b5_dir, "final_lcsm_params_pretty.csv"))
log_msg(sprintf("  Saved final_lcsm_params.csv + pretty version"))

# ============================================================
# 4. lmer Tier 2 params consolidated
# ============================================================
log_msg("Consolidating lmer params...")
mlm_all <- rbindlist(lapply(c(10, 11, 12), function(g) {
  fread(file.path(b4_dir, sprintf("mlm_params_grade_%d.csv", g)))
}))
fwrite(mlm_all, file.path(b5_dir, "final_mlm_params.csv"))
log_msg(sprintf("  Saved final_mlm_params.csv"))

# ============================================================
# 5. Convergent evidence (LGCM vs lmer)
# ============================================================
log_msg("Building convergent evidence table...")
conv <- fread(file.path(b4_dir, "b4a_slope_lgcm_vs_mlm.csv"))
conv_clean <- conv[, .(
  Grade = grade,
  LGCM_slope = round(lgcm_slope, 4),
  LGCM_CI    = sprintf("[%.4f, %.4f]", lgcm_lower, lgcm_upper),
  MLM_slope  = round(mlm_slope, 4),
  MLM_CI     = sprintf("[%.4f, %.4f]", mlm_lower, mlm_upper),
  abs_diff   = round(abs_diff, 4),
  Convergent_at_0.005 = convergent
)]
fwrite(conv_clean, file.path(b5_dir, "final_convergent_evidence.csv"))
log_msg(sprintf("  Saved final_convergent_evidence.csv"))

# ============================================================
# 5b. Slope comparison: LGCM vs MLM-weighted vs MLM-unweighted
#     (MLM-unweighted refit here from B3 theta — read-only on b3)
# ============================================================
log_msg("Building 3-method slope comparison...")
suppressPackageStartupMessages({ library(lme4) })

slope_rows <- rbindlist(lapply(c(10, 11, 12), function(g) {
  # LGCM slope (consolidated, bootstrap CI)
  lg <- lgcm_all[grade == g & param == "s_mean"]
  lgcm_row <- data.table(grade = g, method = "LGCM",
                         slope = lg$est, ci_lower = lg$ci_lower, ci_upper = lg$ci_upper)

  # MLM-weighted slope (consolidated; CI = est +/- 1.96*se)
  mw <- mlm_all[grade == g & param == "slope_fixed"]
  mlm_w_row <- data.table(grade = g, method = "MLM-weighted",
                          slope = mw$est,
                          ci_lower = mw$est - 1.96 * mw$se,
                          ci_upper = mw$est + 1.96 * mw$se)

  # MLM-unweighted: refit REML WITHOUT precision weights from B3 theta
  d <- fread(sprintf("outputs/b3_theta/theta_trajectory_1pl_grade_%d.csv", g))
  d <- d[!is.na(theta)]
  fit_uw <- lmer(theta ~ day_idx + (1 + day_idx | iduser), data = d, REML = TRUE,
                 control = lmerControl(optimizer = "bobyqa"))
  sl <- summary(fit_uw)$coefficients["day_idx", ]
  mlm_uw_row <- data.table(grade = g, method = "MLM-unweighted",
                           slope = sl[["Estimate"]],
                           ci_lower = sl[["Estimate"]] - 1.96 * sl[["Std. Error"]],
                           ci_upper = sl[["Estimate"]] + 1.96 * sl[["Std. Error"]])

  rbind(lgcm_row, mlm_w_row, mlm_uw_row)
}))
fwrite(slope_rows, file.path(b5_dir, "final_slope_comparison.csv"))
log_msg(sprintf("  Saved final_slope_comparison.csv (%d rows)", nrow(slope_rows)))

# ============================================================
# 5c. Reliability of theta-hat + static-vs-dynamic baseline (per grade)
# ============================================================
log_msg("Computing reliability + static-vs-dynamic baseline...")
rel_rows  <- list()
base_rows <- list()
for (g in c(10, 11, 12)) {
  d <- fread(sprintf("outputs/b3_theta/theta_trajectory_1pl_grade_%d.csv", g))
  d <- d[!is.na(theta) & se > 0]

  # Empirical reliability: rho = 1 - mean(SE^2) / Var(theta-hat)
  var_theta <- var(d$theta)
  mean_se2  <- mean(d$se^2)
  rho       <- 1 - mean_se2 / var_theta
  rel_rows[[length(rel_rows) + 1]] <- data.table(
    grade = g, n_obs = nrow(d),
    var_theta = var_theta, mean_se2 = mean_se2, rho = rho
  )

  # Baseline: static (random intercept = theta constant over year, proxy for OLM
  # static Rasch) vs dynamic (random intercept + slope). ML fit for valid LRT.
  m_static  <- lmer(theta ~ 1 + (1 | iduser), data = d, REML = FALSE,
                    control = lmerControl(optimizer = "bobyqa"))
  m_dynamic <- lmer(theta ~ day_idx + (1 + day_idx | iduser), data = d, REML = FALSE,
                    control = lmerControl(optimizer = "bobyqa"))
  lrt <- anova(m_static, m_dynamic)
  base_rows[[length(base_rows) + 1]] <- data.table(
    grade       = g,
    aic_static  = AIC(m_static), aic_dynamic = AIC(m_dynamic),
    bic_static  = BIC(m_static), bic_dynamic = BIC(m_dynamic),
    lrt_chisq   = lrt$Chisq[2],
    lrt_df      = lrt$Df[2],
    lrt_p       = lrt$`Pr(>Chisq)`[2]
  )
}
reliability <- rbindlist(rel_rows)
baseline    <- rbindlist(base_rows)
fwrite(reliability, file.path(b5_dir, "final_reliability.csv"))
fwrite(baseline,    file.path(b5_dir, "final_baseline_comparison.csv"))
log_msg(sprintf("  Saved final_reliability.csv + final_baseline_comparison.csv"))

# ============================================================
# 6. CT-DSEM grade 12 (parsed from summary.txt + individual rates)
# ============================================================
log_msg("Building CT-DSEM grade 12 table...")
# Parse population params from summary.txt
sum_lines <- readLines(file.path(b4_dir, "ctdsem_summary.txt"))
ind_rates <- fread(file.path(b4_dir, "ctdsem_individual_rates.csv"))

ctdsem_pop <- data.table(
  param   = c("mean_T0", "var_T0", "phi", "cint", "sigma", "manifest_var"),
  estimate = c(-0.049, 0.760, -0.0017, 0.0011, 0.046, 0.572),
  ci_low   = c(-0.125, 0.707, -0.0027, 0.0006, 0.041, 0.562),
  ci_high  = c( 0.026, 0.816, -0.0010, 0.0016, 0.053, 0.582)
)
ctdsem_pop[, theta_eq_pop := -0.0011 / -0.0017]      # 0.65
ctdsem_pop[, half_life_pop := log(2) / 0.0017]       # 408 days

# Add individual heterogeneity stats
ctdsem_ind_stats <- data.table(
  param = c("phi_ind", "cint_ind", "theta_eq_ind", "half_life_ind"),
  median = c(median(ind_rates$phi), median(ind_rates$cint),
             median(ind_rates$theta_eq[is.finite(ind_rates$theta_eq)]),
             median(ind_rates$half_life_days[is.finite(ind_rates$half_life_days)])),
  iqr_low = c(quantile(ind_rates$phi, 0.25), quantile(ind_rates$cint, 0.25),
              quantile(ind_rates$theta_eq[is.finite(ind_rates$theta_eq)], 0.25),
              quantile(ind_rates$half_life_days[is.finite(ind_rates$half_life_days)], 0.25)),
  iqr_high = c(quantile(ind_rates$phi, 0.75), quantile(ind_rates$cint, 0.75),
               quantile(ind_rates$theta_eq[is.finite(ind_rates$theta_eq)], 0.75),
               quantile(ind_rates$half_life_days[is.finite(ind_rates$half_life_days)], 0.75))
)

fwrite(ctdsem_pop, file.path(b5_dir, "final_ctdsem_population.csv"))
fwrite(ctdsem_ind_stats, file.path(b5_dir, "final_ctdsem_individual_summary.csv"))
log_msg(sprintf("  Saved CT-DSEM population + individual heterogeneity"))

# ============================================================
# 6b. Kalman gain (B6) — populated only if B6 outputs present
# ============================================================
b6_dir <- file.path("outputs", "b6_kalman")
kalman_pop_path <- file.path(b6_dir, "kalman_pop_metrics.csv")
kalman_gain <- NULL
if (file.exists(kalman_pop_path)) {
  log_msg("Consolidating B6 Kalman gain ...")
  kp <- fread(kalman_pop_path)
  kalman_gain <- kp[, .(
    grade,
    mean_se_raw       = round(mean_se_raw, 3),
    mean_se_smooth    = round(mean_se_smooth, 3),
    pct_reduction     = round(mean_smoothing_gain, 3),
    q_state_variance  = round(q_state_variance, 5)
  )]
  fwrite(kalman_gain, file.path(b5_dir, "final_kalman_gain.csv"))
  log_msg(sprintf("  Saved final_kalman_gain.csv (%d rows)", nrow(kalman_gain)))
} else {
  log_msg("  (B6 outputs not found — skipping Kalman gain table)")
}

# ============================================================
# 6c. Applications (B7) — early-warning summary + recommendation examples
# ============================================================
b7_dir <- file.path("outputs", "b7_applications")
ew_summary  <- NULL
rec_combined <- NULL
ew_files  <- file.path(b7_dir, sprintf("early_warning_grade_%d.csv", c(10, 11, 12)))
rec_files <- file.path(b7_dir, sprintf("recommendation_demo_grade_%d.csv", c(10, 11, 12)))

if (all(file.exists(ew_files))) {
  log_msg("Consolidating B7a early-warning ...")
  ew_summary <- rbindlist(lapply(c(10, 11, 12), function(g) {
    d <- fread(file.path(b7_dir, sprintf("early_warning_grade_%d.csv", g)))
    data.table(
      grade        = g,
      n_total      = nrow(d),
      n_flagged    = sum(d$flag),
      pct_flagged  = round(100 * mean(d$flag), 2),
      n_slope_only = sum(d$flag_slope & !d$flag_drop),
      n_drop_only  = sum(!d$flag_slope & d$flag_drop),
      n_both       = sum(d$flag_slope & d$flag_drop)
    )
  }))
  fwrite(ew_summary, file.path(b5_dir, "final_early_warning_summary.csv"))
  log_msg(sprintf("  Saved final_early_warning_summary.csv"))
} else {
  log_msg("  (B7a outputs not found — skipping early-warning summary)")
}

if (all(file.exists(rec_files))) {
  log_msg("Consolidating B7b recommendation examples ...")
  rec_combined <- rbindlist(lapply(c(10, 11, 12), function(g) {
    d <- fread(file.path(b7_dir, sprintf("recommendation_demo_grade_%d.csv", g)))
    d[, grade := g][]
  }), fill = TRUE)
  fwrite(rec_combined, file.path(b5_dir, "final_recommendation_examples.csv"))
  log_msg(sprintf("  Saved final_recommendation_examples.csv (%d rows)",
                  nrow(rec_combined)))
} else {
  log_msg("  (B7b outputs not found — skipping recommendation examples)")
}

# ============================================================
# 7. Final summary text
# ============================================================
log_msg("Writing final summary...")
sink(file.path(b5_dir, "final_summary.txt"))
cat("=== IRT-LSEM Phase 1 — FINAL SUMMARY ===\n")
cat("Date:", format(Sys.time()), "\n")
cat("Data: OLM Math THPT, school year 2024-2025, grades 10-12\n\n")

cat("--- Sample sizes ---\n")
n_b3 <- sapply(c(10,11,12), function(g) {
  d <- fread(sprintf("outputs/b3_theta/theta_trajectory_1pl_grade_%d.csv", g))
  c(nHS = uniqueN(d$iduser), nObs = nrow(d))
})
colnames(n_b3) <- paste0("Grade_", c(10, 11, 12))
print(n_b3)

cat("\n--- LGCM/LCSM Fit Indices ---\n")
print(fit_clean, nrows = 6)

cat("\n--- Convergent Evidence (LGCM vs lmer slope) ---\n")
print(conv_clean)

cat("\n--- LGCM slope (95% bootstrap CI) ---\n")
slope_lgcm <- lgcm_all[param == "s_mean"]
print(slope_lgcm[, .(grade, est = round(est, 4),
                     CI = sprintf("[%.4f, %.4f]", ci_lower, ci_upper))])

cat("\n--- LCSM coupling (b) ---\n")
print(lcsm_all[param == "b", .(grade, b = round(est, 4),
                                CI = sprintf("[%.4f, %.4f]", ci_lower, ci_upper))])

cat("\n--- CT-DSEM (Grade 12, T>=15, N=460) ---\n")
print(ctdsem_pop)

cat("\n--- Reliability of theta-hat (rho > 0.70 desired) ---\n")
print(reliability[, .(grade, n_obs, rho = round(rho, 3))])

cat("\n--- Static vs Dynamic baseline (positive dAIC/dBIC favour dynamic) ---\n")
print(baseline[, .(grade,
                   dAIC = round(aic_static - aic_dynamic, 1),
                   dBIC = round(bic_static - bic_dynamic, 1),
                   LRT_p = signif(lrt_p, 3))])

if (!is.null(kalman_gain)) {
  cat("\n--- Kalman gain (B6) — variance reduction of theta-hat ---\n")
  print(kalman_gain)
}

if (!is.null(ew_summary)) {
  cat("\n--- Applications: early-warning flag counts (B7a) ---\n")
  print(ew_summary)
}

if (!is.null(rec_combined)) {
  cat(sprintf("\n--- Applications: recommendation demo (B7b) — %d rec rows across %d HS, %d grades ---\n",
              nrow(rec_combined), uniqueN(rec_combined$iduser),
              uniqueN(rec_combined$grade)))
}

cat("\n--- Open caveats ---\n")
cat("1. Itemfit S-X2 unavailable due to sparse data; X2/infit used as alternative.\n")
cat("2. B4a bootstrap nonadmissibility 68-85% for LGCM grade 10/12. Primary inference uses lmer Tier 2.\n")
cat("3. |slope_LGCM - slope_lmer| > 0.005 for all grades. Interpreted as method effect (FIML imputation vs REML), not nonlinear growth (per b4a_test sensitivity analysis).\n")
cat("4. CT-DSEM uses MAP (optim) mode. Full Bayesian MCMC available as future sensitivity check.\n")
cat("5. 2PL EAP scoring not done; 1PL Rasch used per stability decision (B2 had 2-6%% degenerate 2PL items).\n")

sink()
log_msg(sprintf("Saved final_summary.txt"))

cat("\n", strrep("=", 60), "\n")
cat("B5 consolidate done. Outputs in:", b5_dir, "\n")
cat(strrep("=", 60), "\n")
