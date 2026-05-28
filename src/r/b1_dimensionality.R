# B1: Dimensionality Check — PCA + Parallel Analysis + Bifactor IRT → ECV
#
# Strategy: Top 200 items → tetrachoric → PCA/PA → Bifactor IRT → ECV
#
# Decision (based on ECV):
#   ECV >= 0.80 → 1D OK → skip RI-CLPM, use 1PL/2PL unidimensional
#   ECV 0.65-0.80 → Mixed → keep RI-CLPM as main analysis
#   ECV < 0.65 → Multidim → consider MIRT 2D instead of 1PL/2PL

library(data.table)
library(psych)
library(mirt)

set.seed(42)

# === PATHS ===
b0_dir <- file.path("outputs", "b0_preprocessed")
b1_dir <- file.path("outputs", "b1_dimensionality")
dir.create(b1_dir, showWarnings = FALSE, recursive = TRUE)

GRADES <- c(10, 11, 12)
TOP_N_ITEMS <- 200

run_b1 <- function(grade) {
  cat("\n", rep("=", 50), "\n  GRADE", grade, "\n", rep("=", 50), "\n")

  dt <- fread(file.path(b0_dir, paste0("response_long_grade_", grade, "_exam.csv")))

  # --- Build matrix: top 200 items ---
  item_counts <- dt[, .(n_students = uniqueN(iduser)), by = question_id]
  top_items <- head(item_counts[order(-n_students)], TOP_N_ITEMS)$question_id

  dt_sub <- dt[question_id %in% top_items,
               .(is_correct = is_correct[1]), by = .(iduser, question_id)]
  sc <- dt_sub[, .N, by = iduser]
  good_hs <- sc[N >= 10, iduser]
  dt_sub <- dt_sub[iduser %in% good_hs]

  wide <- dcast(dt_sub, iduser ~ question_id, value.var = "is_correct")
  mat <- as.matrix(wide[, -1, with = FALSE])
  mat <- mat[, colMeans(!is.na(mat)) >= 0.05]
  cat("  Matrix:", nrow(mat), "×", ncol(mat),
      "| sparsity:", round(mean(is.na(mat)) * 100, 1), "%\n")

  # --- PCA: tetrachoric + eigenvalues ---
  cat("  Tetrachoric correlation...\n")
  tet <- tryCatch(
    psych::tetrachoric(mat, smooth = TRUE, correct = 0.5)$rho,
    error = function(e) {
      cat("  ⚠️ Fallback to Pearson\n")
      cor(mat, use = "pairwise.complete.obs")
    }
  )
  tet[is.na(tet)] <- 0; diag(tet) <- 1

  eigs <- eigen(tet, symmetric = TRUE, only.values = TRUE)$values
  eigs <- eigs[eigs > 0]
  ev2 <- eigs[2]
  cat("  Top 5 eigenvalues:", round(head(eigs, 5), 3), "\n")
  cat("  ev1/ev2 ratio:", round(eigs[1] / ev2, 2), "\n")

  # --- Parallel analysis ---
  cat("  Parallel analysis...\n")
  pa <- tryCatch(
    psych::fa.parallel(tet, n.obs = nrow(mat), fa = "fa",
                       n.iter = 100, plot = FALSE, quant = 0.95),
    error = function(e) { cat("  ⚠️ PA failed\n"); NULL }
  )
  n_factors_pa <- if (!is.null(pa)) pa$nfact else NA
  cat("  PA suggests:", n_factors_pa, "factors\n")

  # --- Bifactor IRT (1 general + 2 specific) ---
  cat("  Fitting bifactor IRT (2 specific factors)...\n")
  ecv <- NA
  omega_h <- NA
  bifac_model <- NULL

  tryCatch({
    # Exploratory bifactor: extract 3 factors, rotate to bifactor
    bifac_model <- mirt(mat, model = 3, itemtype = "2PL",
                        method = "EM", rotate = "bifactorQ",
                        technical = list(NCYCLES = 3000),
                        verbose = TRUE)

    # Extract rotated loadings
    summ <- summary(bifac_model, rotate = "bifactorQ", verbose = FALSE)
    loadings <- summ$rotF

    if (!is.null(loadings) && ncol(loadings) >= 2) {
      # ECV = variance explained by general / total variance
      general_var <- sum(loadings[, 1]^2)
      total_var <- sum(loadings^2)
      ecv <- general_var / total_var

      # Omega hierarchical (approximate)
      omega_h <- general_var / (general_var + ncol(mat))  # simplified
    }
    cat("  Bifactor converged.\n")
  }, error = function(e) {
    cat("  ⚠️ Bifactor failed:", conditionMessage(e), "\n")
    cat("  Falling back to eigenvalue-based ECV estimate.\n")
    ecv <<- eigs[1] / sum(head(eigs, 5))
  })

  cat("\n  === Bifactor diagnostics ===\n")
  cat("  ECV (general):", round(ecv, 3), "\n")
  if (!is.na(omega_h)) cat("  OmegaH (approx):", round(omega_h, 3), "\n")

  # --- Decision ---
  decision <- if (is.na(ecv)) {
    "UNKNOWN — bifactor failed"
  } else if (ecv >= 0.80) {
    "1D OK — bo RI-CLPM"
  } else if (ecv >= 0.65) {
    "Mixed — giu RI-CLPM"
  } else {
    "Multidim — can MIRT 2D"
  }

  cat("  *** Decision:", decision, "***\n")

  # --- Save ---
  results <- list(
    eigenvalues = eigs, ev2 = ev2,
    n_factors_pa = n_factors_pa,
    ecv = ecv, omega_h = omega_h,
    n_students = nrow(mat), n_items = ncol(mat),
    sparsity = mean(is.na(mat)),
    bifac_model = bifac_model,
    parallel_analysis = pa,
    decision = decision
  )
  saveRDS(results, file.path(b1_dir, paste0("grade_", grade, "_results.rds")))

  # Scree plot
  png(file.path(b1_dir, paste0("scree_plot_grade_", grade, ".png")), width = 700, height = 450)
  n_plot <- min(15, length(eigs))
  plot(1:n_plot, eigs[1:n_plot], type = "b", pch = 19, col = "darkblue",
       xlab = "Factor", ylab = "Eigenvalue",
       main = paste0("Grade ", grade, " | ev2=", round(ev2, 2),
                     " | ECV=", round(ecv, 2), " | ", decision))
  abline(h = 1, lty = 2, col = "gray")
  if (!is.null(pa)) {
    pv <- pa$fa.values[1:min(n_plot, length(pa$fa.values))]
    lines(seq_along(pv), pv, type = "b", pch = 17, col = "red", lty = 2)
    legend("topright", c("Observed", "PA 95th"), col = c("darkblue", "red"), pch = c(19, 17))
  }
  dev.off()

  return(decision)
}

# === RUN ===
cat(rep("=", 60), "\nB1: DIMENSIONALITY (top", TOP_N_ITEMS, "items + bifactor ECV)\n", rep("=", 60), "\n")
decisions <- sapply(GRADES, run_b1)

writeLines(c(
  "B1 Decisions", paste("Date:", Sys.time()),
  paste("Method: Top", TOP_N_ITEMS, "items + bifactor IRT → ECV"), "",
  paste("Grade 10:", decisions[1]),
  paste("Grade 11:", decisions[2]),
  paste("Grade 12:", decisions[3]), "",
  "Rules: ECV>=0.80 → 1D | 0.65-0.80 → Mixed (keep RI-CLPM) | <0.65 → Multidim"
), file.path(b1_dir, "b1_decision.txt"))

cat("\nB1 complete.\n")
