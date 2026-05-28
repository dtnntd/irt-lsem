# Verify B1 output before proceeding to B2
source("src/r/utils/config.R")

cat("B1 verification: checking outputs...\n")

all_pass <- TRUE
for (grade in GRADES) {
  rds_path <- file.path(output_dir, "b1_dimensionality", paste0("grade_", grade, "_results.rds"))
  if (!file.exists(rds_path)) {
    cat("  ❌ Grade", grade, "— results file missing\n")
    all_pass <- FALSE
    next
  }
  results <- readRDS(rds_path)
  checks <- c(
    ev1_dominant = results$eigenvalues[1] > 2 * results$eigenvalues[2],
    decision_recorded = !is.null(results$decision)
  )
  status <- if (all(checks)) "✅" else "❌"
  cat("  ", status, "Grade", grade, ":", paste(names(checks), checks, collapse = ", "), "\n")
  if (!all(checks)) all_pass <- FALSE
}

if (!all_pass) quit(status = 1)
