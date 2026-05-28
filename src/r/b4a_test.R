# B4a sensitivity: lmer capped at T=4 + subset HS with ≥4 measurements
#
# Purpose: isolate "method" vs "data" effect in LGCM vs lmer slope difference.
#   - LGCM uses wide-format with FIML, all HS, capped at t<4.
#   - Original lmer uses long-format with all HS, NO cap.
#   - This script: lmer on subset (HS with T≥4) AND cap at t<4.
#
# If slope_lmer_capped ≈ slope_LGCM → difference is from data (HS coverage, late
# measurements). If slope_lmer_capped ≠ slope_LGCM → difference is from method.

suppressPackageStartupMessages({
  library(data.table)
  library(lme4)
  library(lmerTest)
})

GRADES <- c(10, 11, 12)
MAX_T  <- 4

cat(sprintf("%-7s %-15s %-15s %-15s %-15s %-15s\n",
            "Grade", "n_HS_subset", "n_obs_subset",
            "lmer_capped", "lmer_capped_SE", "compare"))
cat(strrep("-", 80), "\n")

for (g in GRADES) {
  d <- fread(paste0("outputs/b3_theta/theta_trajectory_1pl_grade_", g, ".csv"))

  # HS có ≥4 measurements
  hs_with_T4 <- d[, .N, by = iduser][N >= 4, iduser]

  # Cap day_idx < 4 trên subset này
  d_capped <- d[iduser %in% hs_with_T4 & day_idx < MAX_T & !is.na(theta) & se > 0]

  fit <- tryCatch(
    # lmer(theta ~ day_idx + (1 + day_idx | iduser),
    #      data = d_capped, weights = 1 / se^2,
    #      control = lmerControl(optimizer = "bobyqa")),
    fit_no_w <- lmer(theta ~ day_idx + (1 + day_idx | iduser),
                 data = d_capped,
                 control = lmerControl(optimizer = "bobyqa")),
    error = function(e) { cat("Grade", g, "failed:", conditionMessage(e), "\n"); NULL }
  )

  if (!is.null(fit)) {
    coef_tab <- summary(fit)$coefficients
    slope    <- coef_tab["day_idx", "Estimate"]
    slope_se <- coef_tab["day_idx", "Std. Error"]

    # Load original LGCM slope cho comparison
    lgcm_csv <- file.path("outputs", "b4_lsem",
                          paste0("lgcm_params_grade_", g, ".csv"))
    if (file.exists(lgcm_csv)) {
      lgcm_p <- fread(lgcm_csv)
      lgcm_slope <- lgcm_p[param == "s_mean", est]
      diff_lgcm  <- abs(slope - lgcm_slope)
      cmp <- sprintf("|Δ LGCM|=%.4f", diff_lgcm)
    } else {
      cmp <- "(LGCM file not found)"
    }

    cat(sprintf("%-7d %-15d %-15d %-15.4f %-15.4f %-15s\n",
                g, length(hs_with_T4), nrow(d_capped),
                slope, slope_se, cmp))
  }
}
