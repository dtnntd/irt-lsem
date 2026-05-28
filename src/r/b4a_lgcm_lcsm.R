# B4a: LGCM + LCSM (Tier 1) + Multilevel growth (Tier 2)
#
# Per updated plan_thuc_hien.md §B4a:
#   Tier 1 (primary):    lavaan LGCM + LCSM, max_T = 4, bootstrap CI (1000 reps)
#   Tier 2 (robustness): lme4::lmer multilevel growth, no T cap, precision weights
#   Convergent evidence: |slope_LGCM - slope_mlm| < 0.005
#
# Input:
#   outputs/b3_theta/theta_trajectory_1pl_grade_{N}.csv
#   columns: iduser, day_idx, date, n_items, theta, se
#
# Output:
#   outputs/b4_lsem/
#     lgcm_grade_{N}.rds              Tier 1
#     lcsm_grade_{N}.rds              Tier 1
#     mlm_grade_{N}.rds               Tier 2
#     lgcm_params_grade_{N}.csv
#     lcsm_params_grade_{N}.csv
#     mlm_params_grade_{N}.csv
#     b4a_fit_indices.csv
#     b4a_slope_lgcm_vs_mlm.csv       KEY OUTPUT: convergent evidence

suppressPackageStartupMessages({
  library(data.table)
  library(lavaan)
  library(lme4)
  library(lmerTest)
})

# ---- Paths & config ----
b3_dir <- Sys.getenv("B3_DIR", file.path("outputs", "b3_theta"))
b4_dir <- Sys.getenv("B4_DIR", file.path("outputs", "b4_lsem"))
dir.create(b4_dir, showWarnings = FALSE, recursive = TRUE)

GRADES        <- c(10, 11, 12)
MAX_T         <- 4
BOOTSTRAP_N   <- as.integer(Sys.getenv("BOOTSTRAP_N", "1000"))
SEED          <- 42
FORCE_RERUN   <- as.logical(Sys.getenv("FORCE_RERUN", "FALSE"))

set.seed(SEED)

log_msg <- function(...) {
  cat(format(Sys.time(), "%H:%M:%S"), "—", ..., "\n"); flush.console()
}

# ---- LGCM spec (T = 4) ----
lgcm_spec <- "
  i =~ 1*theta_t0 + 1*theta_t1 + 1*theta_t2 + 1*theta_t3
  s =~ 0*theta_t0 + 1*theta_t1 + 2*theta_t2 + 3*theta_t3
  i ~~ s
"

# ---- LCSM spec (T = 4, with Heywood-preventing constraints) ----
lcsm_spec <- "
  # True score factors
  eta1 =~ 1*theta_t0
  eta2 =~ 1*theta_t1
  eta3 =~ 1*theta_t2
  eta4 =~ 1*theta_t3

  # Equality-constrained measurement error variance
  theta_t0 ~~ varY*theta_t0
  theta_t1 ~~ varY*theta_t1
  theta_t2 ~~ varY*theta_t2
  theta_t3 ~~ varY*theta_t3

  # Change factors
  d2 =~ 1*eta2
  d3 =~ 1*eta3
  d4 =~ 1*eta4

  # Force eta_t residual variance = 0 (change captured by d_t)
  eta2 ~~ 0*eta2
  eta3 ~~ 0*eta3
  eta4 ~~ 0*eta4

  # Carry-forward
  eta2 ~ 1*eta1
  eta3 ~ 1*eta2
  eta4 ~ 1*eta3

  # Proportional change (b shared)
  d2 ~ b*eta1
  d3 ~ b*eta2
  d4 ~ b*eta3

  # Equality-constrained d variance (Heywood prevention, vd shared)
  d2 ~~ vd*d2
  d3 ~~ vd*d3
  d4 ~~ vd*d4

  # Means
  eta1 ~ alpha0*1
  d2 ~ alpha*1
  d3 ~ alpha*1
  d4 ~ alpha*1
"

# ---- Build wide format ----
build_wide <- function(d_long) {
  d_capped <- d_long[day_idx < MAX_T]
  wide <- dcast(d_capped, iduser ~ day_idx, value.var = "theta")
  setnames(wide, old = setdiff(names(wide), "iduser"),
           new = paste0("theta_t", setdiff(names(wide), "iduser")))
  for (t in 0:(MAX_T - 1)) {
    col <- paste0("theta_t", t)
    if (!col %in% names(wide)) wide[[col]] <- NA_real_
  }
  setcolorder(wide, c("iduser", paste0("theta_t", 0:(MAX_T - 1))))
  as.data.frame(wide)
}

# ---- Fit one grade ----
fit_grade <- function(grade) {
  cat("\n", strrep("=", 65), "\n", sep = "")
  log_msg(sprintf("B4a GRADE %d", grade))
  cat(strrep("=", 65), "\n", sep = "")

  out_lgcm <- file.path(b4_dir, paste0("lgcm_grade_", grade, ".rds"))
  out_lcsm <- file.path(b4_dir, paste0("lcsm_grade_", grade, ".rds"))
  out_mlm  <- file.path(b4_dir, paste0("mlm_grade_",  grade, ".rds"))

  if (!FORCE_RERUN && file.exists(out_lgcm) && file.exists(out_lcsm) && file.exists(out_mlm)) {
    log_msg("All outputs exist, loading.")
    return(list(
      lgcm = readRDS(out_lgcm),
      lcsm = readRDS(out_lcsm),
      mlm  = readRDS(out_mlm)
    ))
  }

  # ---- Load ----
  d_long <- fread(file.path(b3_dir, paste0("theta_trajectory_1pl_grade_", grade, ".csv")))
  log_msg(sprintf("Loaded long format: %d rows, %d HS",
                  nrow(d_long), uniqueN(d_long$iduser)))

  # ============================================================
  # TIER 1 — LGCM + LCSM (lavaan, max_T = 4, bootstrap CI)
  # ============================================================
  wide <- build_wide(d_long)
  log_msg(sprintf("Tier 1 wide: N_HS=%d | NA per t:", nrow(wide)))
  na_pct <- sapply(paste0("theta_t", 0:(MAX_T-1)),
                   function(c) round(100 * mean(is.na(wide[[c]])), 1))
  cat("   ", paste0(names(na_pct), "=", na_pct, "%"), "\n")

  # ---- LGCM with bootstrap ----
  log_msg(sprintf("Fitting LGCM (bootstrap N=%d)...", BOOTSTRAP_N))
  set.seed(SEED)
  t0 <- Sys.time()
  fit_lgcm <- tryCatch(
    growth(lgcm_spec, data = wide,
           missing = "fiml", estimator = "ML",
           se = "bootstrap", bootstrap = BOOTSTRAP_N),
    error = function(e) { log_msg("LGCM failed:", conditionMessage(e)); NULL }
  )

  if (!is.null(fit_lgcm)) {
    saveRDS(fit_lgcm, out_lgcm)
    fm <- fitMeasures(fit_lgcm, c("chisq", "df", "cfi", "rmsea", "srmr"))
    log_msg(sprintf("  LGCM: χ²=%.1f df=%d CFI=%.3f RMSEA=%.3f SRMR=%.3f (took %.1fm)",
                    fm["chisq"], fm["df"], fm["cfi"], fm["rmsea"], fm["srmr"],
                    as.numeric(difftime(Sys.time(), t0, units = "mins"))))

    pe <- parameterEstimates(fit_lgcm, ci = TRUE)
    i_mean <- pe[pe$lhs == "i" & pe$op == "~1", c("est", "ci.lower", "ci.upper")]
    s_mean <- pe[pe$lhs == "s" & pe$op == "~1", c("est", "ci.lower", "ci.upper")]
    i_var  <- pe[pe$lhs == "i" & pe$op == "~~" & pe$rhs == "i", "est"]
    s_var  <- pe[pe$lhs == "s" & pe$op == "~~" & pe$rhs == "s", "est"]
    log_msg(sprintf("  Intercept μ=%.3f [%.3f, %.3f] | Slope μ=%.4f [%.4f, %.4f]",
                    i_mean$est, i_mean$ci.lower, i_mean$ci.upper,
                    s_mean$est, s_mean$ci.lower, s_mean$ci.upper))
    fwrite(data.table(
      grade = grade,
      param = c("i_mean", "s_mean", "i_var", "s_var"),
      est   = c(i_mean$est, s_mean$est, i_var, s_var),
      ci_lower = c(i_mean$ci.lower, s_mean$ci.lower, NA_real_, NA_real_),
      ci_upper = c(i_mean$ci.upper, s_mean$ci.upper, NA_real_, NA_real_)
    ), file.path(b4_dir, paste0("lgcm_params_grade_", grade, ".csv")))
  }

  # ---- LCSM with bootstrap ----
  log_msg(sprintf("Fitting LCSM (bootstrap N=%d)...", BOOTSTRAP_N))
  set.seed(SEED)
  t0 <- Sys.time()
  fit_lcsm <- tryCatch(
    growth(lcsm_spec, data = wide,
           missing = "fiml", estimator = "ML",
           se = "bootstrap", bootstrap = BOOTSTRAP_N),
    error = function(e) { log_msg("LCSM failed:", conditionMessage(e)); NULL }
  )

  if (!is.null(fit_lcsm)) {
    saveRDS(fit_lcsm, out_lcsm)
    fm <- fitMeasures(fit_lcsm, c("chisq", "df", "cfi", "rmsea", "srmr"))
    log_msg(sprintf("  LCSM: χ²=%.1f df=%d CFI=%.3f RMSEA=%.3f SRMR=%.3f (took %.1fm)",
                    fm["chisq"], fm["df"], fm["cfi"], fm["rmsea"], fm["srmr"],
                    as.numeric(difftime(Sys.time(), t0, units = "mins"))))

    pe <- parameterEstimates(fit_lcsm, ci = TRUE)
    b_row     <- pe[pe$label == "b", c("est", "ci.lower", "ci.upper")][1, ]
    alpha_row <- pe[pe$label == "alpha", c("est", "ci.lower", "ci.upper")][1, ]
    alpha0_row <- pe[pe$label == "alpha0", c("est", "ci.lower", "ci.upper")][1, ]
    log_msg(sprintf("  b=%.4f [%.4f, %.4f] | alpha=%.4f | alpha0=%.4f",
                    b_row$est, b_row$ci.lower, b_row$ci.upper,
                    alpha_row$est, alpha0_row$est))
    fwrite(data.table(
      grade = grade,
      param = c("b", "alpha", "alpha0"),
      est   = c(b_row$est, alpha_row$est, alpha0_row$est),
      ci_lower = c(b_row$ci.lower, alpha_row$ci.lower, alpha0_row$ci.lower),
      ci_upper = c(b_row$ci.upper, alpha_row$ci.upper, alpha0_row$ci.upper)
    ), file.path(b4_dir, paste0("lcsm_params_grade_", grade, ".csv")))
  }

  # ============================================================
  # TIER 2 — Multilevel growth (lmer, no cap, precision weights)
  # ============================================================
  log_msg("Fitting lmer (multilevel, all data, precision weights)...")
  d_lmer <- d_long[!is.na(theta) & se > 0]
  log_msg(sprintf("  Tier 2 input: %d rows, %d HS, weights = 1/SE²",
                  nrow(d_lmer), uniqueN(d_lmer$iduser)))

  fit_mlm <- tryCatch(
    lmer(theta ~ day_idx + (1 + day_idx | iduser),
         data = d_lmer, weights = 1 / se^2,
         REML = TRUE,
         control = lmerControl(optimizer = "bobyqa")),
    error = function(e) { log_msg("lmer failed:", conditionMessage(e)); NULL }
  )

  if (!is.null(fit_mlm)) {
    saveRDS(fit_mlm, out_mlm)
    fix <- fixef(fit_mlm)
    se_fix <- sqrt(diag(vcov(fit_mlm)))
    log_msg(sprintf("  lmer fixed: intercept=%.3f (SE=%.3f) | slope=%.4f (SE=%.4f)",
                    fix["(Intercept)"], se_fix["(Intercept)"],
                    fix["day_idx"], se_fix["day_idx"]))
    fwrite(data.table(
      grade = grade,
      param = c("intercept_fixed", "slope_fixed",
                "intercept_var", "slope_var", "intercept_slope_cov", "residual_var"),
      est = c(fix["(Intercept)"], fix["day_idx"],
              VarCorr(fit_mlm)$iduser[1, 1], VarCorr(fit_mlm)$iduser[2, 2],
              VarCorr(fit_mlm)$iduser[1, 2], sigma(fit_mlm)^2),
      se = c(se_fix["(Intercept)"], se_fix["day_idx"], NA, NA, NA, NA)
    ), file.path(b4_dir, paste0("mlm_params_grade_", grade, ".csv")))
  }

  list(lgcm = fit_lgcm, lcsm = fit_lcsm, mlm = fit_mlm)
}

# ============================================================
# MAIN
# ============================================================
cat(strrep("#", 65), "\n", sep = "")
cat("B4a: LGCM + LCSM (Tier 1) + lmer (Tier 2)\n")
cat(sprintf("max_T=%d | bootstrap=%d | FORCE_RERUN=%s\n",
            MAX_T, BOOTSTRAP_N, FORCE_RERUN))
cat(strrep("#", 65), "\n", sep = "")

all_fits <- list()
for (g in GRADES) all_fits[[as.character(g)]] <- fit_grade(g)

# ---- Aggregate fit indices ----
log_msg("Aggregating fit indices...")
fit_rows <- list()
for (g in GRADES) {
  for (m in c("lgcm", "lcsm")) {
    fit <- all_fits[[as.character(g)]][[m]]
    if (is.null(fit)) next
    fm <- fitMeasures(fit, c("chisq", "df", "pvalue", "cfi", "tli",
                             "rmsea", "rmsea.ci.lower", "rmsea.ci.upper",
                             "srmr", "aic", "bic"))
    fit_rows[[length(fit_rows) + 1]] <- data.table(
      model = toupper(m), grade = g,
      chisq = fm["chisq"], df = fm["df"], p = fm["pvalue"],
      CFI = fm["cfi"], TLI = fm["tli"],
      RMSEA = fm["rmsea"],
      RMSEA_CIlow = fm["rmsea.ci.lower"], RMSEA_CIhigh = fm["rmsea.ci.upper"],
      SRMR = fm["srmr"], AIC = fm["aic"], BIC = fm["bic"]
    )
  }
}
fit_summary <- rbindlist(fit_rows)
fwrite(fit_summary, file.path(b4_dir, "b4a_fit_indices.csv"))
print(fit_summary)

# ---- KEY OUTPUT: Slope LGCM vs lmer convergent evidence ----
log_msg("Computing convergent evidence (LGCM vs lmer slopes)...")
slope_rows <- list()
for (g in GRADES) {
  fits <- all_fits[[as.character(g)]]
  if (is.null(fits$lgcm) || is.null(fits$mlm)) next

  pe_lgcm <- parameterEstimates(fits$lgcm, ci = TRUE)
  s_lgcm  <- pe_lgcm[pe_lgcm$lhs == "s" & pe_lgcm$op == "~1", ]

  fix_mlm <- fixef(fits$mlm)
  se_mlm  <- sqrt(diag(vcov(fits$mlm)))
  s_mlm_est   <- fix_mlm["day_idx"]
  s_mlm_lower <- s_mlm_est - 1.96 * se_mlm["day_idx"]
  s_mlm_upper <- s_mlm_est + 1.96 * se_mlm["day_idx"]

  diff <- abs(s_lgcm$est - s_mlm_est)
  convergent <- diff < 0.005

  slope_rows[[length(slope_rows) + 1]] <- data.table(
    grade        = g,
    lgcm_slope   = s_lgcm$est,
    lgcm_lower   = s_lgcm$ci.lower,
    lgcm_upper   = s_lgcm$ci.upper,
    mlm_slope    = s_mlm_est,
    mlm_lower    = s_mlm_lower,
    mlm_upper    = s_mlm_upper,
    abs_diff     = diff,
    convergent   = convergent
  )
}
slope_compare <- rbindlist(slope_rows)
fwrite(slope_compare, file.path(b4_dir, "b4a_slope_lgcm_vs_mlm.csv"))
cat("\n=== CONVERGENT EVIDENCE: LGCM slope vs lmer slope ===\n")
print(slope_compare)

log_msg("B4a complete.")
