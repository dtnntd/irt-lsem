# B2 Post-processing: clean degenerate 2PL items + recompute item fit
#
# Problem 1: Some 2PL items have degenerate params (a ~ 0 → b explodes)
#   - 4.2% in grade 12, 6.0% in grade 11, 2.3% in grade 10
#   - Cause: items with extreme p (very easy/hard) or low correlation with θ
#
# Problem 2: itemfit S-X2 failed in B2 with "Sample size after row-wise
#   response data removal: 0" because matrix is too sparse (each student
#   answers <10% of items → no complete cases).
#
# Solution:
#   1. Flag bad items: a <= 0, a > 4, |b| > 5
#   2. Save clean version of 2PL params for B3
#   3. Recompute itemfit with impute=TRUE (Bayesian imputation for missing)
#
# Outputs:
#   - irt_2pl_grade_{N}_clean.csv     (filtered 2PL params)
#   - irt_2pl_grade_{N}_flagged.csv   (full + bad_flag column)
#   - item_fit_2pl_grade_{N}.csv      (S-X2 with imputation)
#   - b2_postprocess_summary.txt

suppressPackageStartupMessages({
  library(data.table)
  library(mirt)
})

set.seed(42)

# ---- Paths ----
b2_dir <- Sys.getenv("B2_DIR", file.path("outputs", "b2_calibration"))
GRADES <- c(10, 11, 12)

# ---- Thresholds for flagging "bad" items ----
A_MIN <- 0.1   # a too low → no discrimination, b unstable
A_MAX <- 4.0   # a unrealistically high
B_ABS_MAX <- 5 # |b| > 5 logits → extreme/degenerate

cat(strrep("=", 60), "\n")
cat("B2 POSTPROCESS: clean degenerate 2PL items + fix itemfit\n")
cat(strrep("=", 60), "\n")
cat("Thresholds:\n")
cat("  a in [", A_MIN, ",", A_MAX, "]\n")
cat("  |b| <=", B_ABS_MAX, "\n\n")

summary_lines <- c(
  "B2 Post-processing Summary",
  paste("Date:", Sys.time()),
  paste("Thresholds: a in [", A_MIN, ",", A_MAX, "], |b| <=", B_ABS_MAX),
  ""
)

postprocess_grade <- function(grade) {
  cat(strrep("-", 60), "\n")
  cat("GRADE", grade, "\n")
  cat(strrep("-", 60), "\n")

  # ---- Load 2PL params + mirt object ----
  csv_path <- file.path(b2_dir, paste0("irt_2pl_grade_", grade, ".csv"))
  rds_path <- file.path(b2_dir, paste0("mirt_2pl_grade_", grade, ".rds"))

  d <- fread(csv_path)
  cat("Loaded", nrow(d), "items\n")

  # ---- Flag bad items ----
  d[, bad_flag := ifelse(a < A_MIN, "low_a",
                  ifelse(a > A_MAX, "high_a",
                  ifelse(abs(b) > B_ABS_MAX, "extreme_b", "ok")))]
  bad_count <- sum(d$bad_flag != "ok")
  cat("Bad items:", bad_count, "/", nrow(d),
      "(", round(100 * bad_count / nrow(d), 2), "%)\n")
  cat("  low_a (a <", A_MIN, "):", sum(d$bad_flag == "low_a"), "\n")
  cat("  high_a (a >", A_MAX, "):", sum(d$bad_flag == "high_a"), "\n")
  cat("  extreme_b (|b| >", B_ABS_MAX, "):", sum(d$bad_flag == "extreme_b"), "\n")

  # ---- Save flagged + clean versions ----
  fwrite(d, file.path(b2_dir, paste0("irt_2pl_grade_", grade, "_flagged.csv")))
  d_clean <- d[bad_flag == "ok"]
  fwrite(d_clean[, .(question_id, a, b)],
         file.path(b2_dir, paste0("irt_2pl_grade_", grade, "_clean.csv")))
  cat("Saved", nrow(d_clean), "clean items to irt_2pl_grade_", grade, "_clean.csv\n", sep = "")

  # ---- Recompute itemfit with statistic that handles missing data ----
  # mirt error: "Only X2, G2, PV_Q1, PV_Q1*, infit, X2*, X2*_df can be computed
  # with missing data." Use X2 (Pearson chi-square) and infit (Rasch-style) which
  # accommodate sparse matrices.
  cat("\nRecomputing 2PL item fit (X2 + infit)...\n")
  if (file.exists(rds_path)) {
    m2pl <- readRDS(rds_path)
    fit <- tryCatch({
      itemfit(m2pl, fit_stats = c("X2", "infit"))
    }, error = function(e) {
      cat("  ⚠️ X2+infit failed:", conditionMessage(e), "\n")
      tryCatch(itemfit(m2pl, fit_stats = "X2"),
               error = function(e2) NULL)
    })

    if (!is.null(fit)) {
      fit_dt <- as.data.table(fit)
      cat("  Fit columns:", paste(names(fit_dt), collapse = ", "), "\n")
      fwrite(fit_dt, file.path(b2_dir, paste0("item_fit_2pl_grade_", grade, ".csv")))

      if ("p.X2" %in% names(fit_dt)) {
        pct_misfit <- mean(fit_dt$p.X2 < 0.01, na.rm = TRUE)
        cat("  X2 misfit (p<0.01):", round(pct_misfit * 100, 1), "%\n")
      }
      if ("infit" %in% names(fit_dt)) {
        # Conventional thresholds: infit outside [0.7, 1.3] = misfit
        pct_infit <- mean(fit_dt$infit < 0.7 | fit_dt$infit > 1.3, na.rm = TRUE)
        cat("  Infit outside [0.7, 1.3]:", round(pct_infit * 100, 1), "%\n")
      }
    }
  } else {
    cat("  ⚠️ mirt RDS not found, skipping itemfit\n")
  }

  # ---- Same for 1PL ----
  cat("\nRecomputing 1PL item fit (X2 + infit)...\n")
  rds_1pl <- file.path(b2_dir, paste0("mirt_1pl_grade_", grade, ".rds"))
  if (file.exists(rds_1pl)) {
    m1pl <- readRDS(rds_1pl)
    fit_1pl <- tryCatch({
      itemfit(m1pl, fit_stats = c("X2", "infit"))
    }, error = function(e) {
      cat("  ⚠️ failed:", conditionMessage(e), "\n")
      tryCatch(itemfit(m1pl, fit_stats = "X2"), error = function(e2) NULL)
    })

    if (!is.null(fit_1pl)) {
      fit_1pl_dt <- as.data.table(fit_1pl)
      fwrite(fit_1pl_dt, file.path(b2_dir, paste0("item_fit_1pl_grade_", grade, ".csv")))
      if ("p.X2" %in% names(fit_1pl_dt)) {
        pct <- mean(fit_1pl_dt$p.X2 < 0.01, na.rm = TRUE)
        cat("  1PL X2 misfit (p<0.01):", round(pct * 100, 1), "%\n")
      }
      if ("infit" %in% names(fit_1pl_dt)) {
        pct <- mean(fit_1pl_dt$infit < 0.7 | fit_1pl_dt$infit > 1.3, na.rm = TRUE)
        cat("  1PL infit outside [0.7, 1.3]:", round(pct * 100, 1), "%\n")
      }
    }
  }

  # ---- Append to summary ----
  list(
    grade = grade,
    n_total = nrow(d),
    n_bad = bad_count,
    pct_bad = round(100 * bad_count / nrow(d), 2),
    n_clean = nrow(d_clean),
    breakdown = c(low_a = sum(d$bad_flag == "low_a"),
                  high_a = sum(d$bad_flag == "high_a"),
                  extreme_b = sum(d$bad_flag == "extreme_b"))
  )
}

results <- list()
for (g in GRADES) {
  results[[as.character(g)]] <- postprocess_grade(g)
}

# ---- Write summary ----
cat("\n", strrep("=", 60), "\n", sep = "")
cat("FINAL SUMMARY\n")
cat(strrep("=", 60), "\n")

summary_lines <- c(summary_lines,
  sprintf("%-7s %-10s %-10s %-10s %-10s %-10s %-10s",
          "Grade", "Total", "Bad", "Bad%", "low_a", "high_a", "extreme_b"))
for (g in GRADES) {
  r <- results[[as.character(g)]]
  line <- sprintf("%-7d %-10d %-10d %-10s %-10d %-10d %-10d",
                  r$grade, r$n_total, r$n_bad, paste0(r$pct_bad, "%"),
                  r$breakdown["low_a"], r$breakdown["high_a"], r$breakdown["extreme_b"])
  cat(line, "\n")
  summary_lines <- c(summary_lines, line)
}

writeLines(summary_lines, file.path(b2_dir, "b2_postprocess_summary.txt"))
cat("\nSummary saved to b2_postprocess_summary.txt\n")
cat("\nNext step: B3 will use *_clean.csv for EAP scoring.\n")
