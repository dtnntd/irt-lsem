# Verify B2 output before proceeding to B3
source("src/r/utils/config.R")
library(tidyverse)

cat("B2 verification: checking calibration outputs...\n")

all_pass <- TRUE
for (grade in GRADES) {
  for (model in c("1pl", "2pl")) {
    csv_path <- file.path(output_dir, "b2_calibration", paste0("irt_", model, "_grade_", grade, ".csv"))
    if (!file.exists(csv_path)) {
      cat("  ❌ Grade", grade, model, "— file missing\n")
      all_pass <- FALSE
      next
    }
    params <- read_csv(csv_path, show_col_types = FALSE)
    checks <- c(
      n_items_ok = nrow(params) > 1000,
      b_in_range = all(abs(params$b) < 6, na.rm = TRUE)
    )
    if (model == "2pl") {
      checks["a_positive"] <- all(params$a > 0, na.rm = TRUE)
      checks["a_reasonable"] <- all(params$a < 5, na.rm = TRUE)
    }
    status <- if (all(checks)) "✅" else "❌"
    cat("  ", status, "Grade", grade, model, "\n")
    if (!all(checks)) all_pass <- FALSE
  }
}

if (!all_pass) quit(status = 1)
