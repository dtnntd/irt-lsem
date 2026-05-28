# Shared configuration for R scripts
# Source this at the top of every R script: source("src/r/utils/config.R")

library(here)

# === PATHS ===
project_root <- here::here()  # research/irt_lsem/
data_root <- file.path(project_root, "..", "..", "data")  # olm_irt/data/
output_dir <- file.path(project_root, "outputs")
log_dir <- file.path(project_root, "logs")

phase_d_dir <- file.path(data_root, "phase_d")
phase_c_dir <- file.path(data_root, "phase_c")

# === CONFIG ===
SEED <- 42
GRADES <- c(10, 11, 12)

irt_config <- list(
  min_resp_1pl = 50,
  min_resp_2pl = 200,
  eap_prior_mean = 0,
  eap_prior_sd = 1
)

lsem_config <- list(
  lgcm_max_T = 8,
  dsem_min_T = 15,
  estimator = "MLR"
)

# === HELPERS ===
ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE)
  invisible(path)
}

log_msg <- function(...) {
  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "—", ..., "\n")
}
