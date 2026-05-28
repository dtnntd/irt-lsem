# Verify B3 output before proceeding to B4
source("src/r/utils/config.R")
library(tidyverse)

cat("B3 verification: checking theta trajectories...\n")

all_pass <- TRUE
for (grade in GRADES) {
  csv_path <- file.path(output_dir, "b3_theta", paste0("theta_trajectory_2pl_grade_", grade, ".csv"))
  if (!file.exists(csv_path)) {
    cat("  ❌ Grade", grade, "— file missing\n")
    all_pass <- FALSE
    next
  }
  data <- read_csv(csv_path, show_col_types = FALSE)
  checks <- c(
    no_missing_theta = sum(is.na(data$theta_hat)) == 0,
    theta_in_range = all(abs(data$theta_hat) < 6, na.rm = TRUE),
    se_positive = all(data$se_theta > 0, na.rm = TRUE),
    min_T_ok = data %>% count(iduser) %>% pull(n) %>% min() >= 3
  )
  status <- if (all(checks)) "✅" else "❌"
  cat("  ", status, "Grade", grade, ":", paste(names(checks), checks, collapse = ", "), "\n")
  if (!all(checks)) all_pass <- FALSE
}

if (!all_pass) quit(status = 1)
