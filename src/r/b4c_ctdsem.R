# B4c: CT-DSEM (Continuous-Time Dynamic SEM) for Grade 12
#
# Per plan_thuc_hien.md §B4c:
#   - Subsample: HS with T >= 15 measurements
#   - Continuous-time AR(1) with random effects on (phi, cint)
#   - Random effects per HS: drift rate phi_i + asymptotic level cint_i
#
# Input:  outputs/b3_theta/theta_trajectory_1pl_grade_12.csv
# Output: outputs/b4_lsem/
#   - ctdsem_grade_12.rds              (full ctsem fit)
#   - ctdsem_individual_params.csv     (phi_i, cint_i per HS)
#   - ctdsem_population_params.csv     (drift, diffusion, etc.)
#   - ctdsem_summary.txt               (text summary)
#
# Modes (env var CTDSEM_MODE):
#   "optim"        : ML optimization only, no priors (Wald CI), ~2-3 min
#   "map_laplace"  : MAP + Hessian-based posterior (Laplace approx), ~3-5 min
#   "mcmc"         : TRUE HMC sampling (4 chains × 2000 iter), ~15-30 min
#                    Full Bayesian inference, recommended for publication.
#
# Usage on Colab:
#   Sys.setenv(B3_DIR='/content/drive/MyDrive/irt_lsem/outputs/b3_theta')
#   Sys.setenv(B4_DIR='/content/drive/MyDrive/irt_lsem/outputs/b4_lsem')
#   Sys.setenv(CTDSEM_MODE='optim')
#   source('b4c_ctdsem.R')

# ----- Auto-install -----
required <- c("data.table", "ctsem", "rstan")
missing  <- required[!sapply(required, requireNamespace, quietly = TRUE)]
if (length(missing) > 0) {
  cat("Installing missing packages:", paste(missing, collapse = ", "), "\n")
  install.packages(missing, repos = "https://cloud.r-project.org",
                   Ncpus = max(1, parallel::detectCores() - 1))
}

suppressPackageStartupMessages({
  library(data.table)
  library(ctsem)
  library(rstan)
})

# ----- Config -----
b3_dir <- Sys.getenv("B3_DIR", file.path("outputs", "b3_theta"))
b4_dir <- Sys.getenv("B4_DIR", file.path("outputs", "b4_lsem"))
dir.create(b4_dir, showWarnings = FALSE, recursive = TRUE)

GRADE     <- 12
MIN_T     <- as.integer(Sys.getenv("MIN_T", "15"))
MODE      <- Sys.getenv("CTDSEM_MODE", "optim")  # "optim" or "mcmc"
N_CORES   <- as.integer(Sys.getenv("N_CORES", "4"))
SEED      <- 42

set.seed(SEED)
options(mc.cores = N_CORES)
rstan_options(auto_write = TRUE)

log_msg <- function(...) {
  cat(format(Sys.time(), "%H:%M:%S"), "—", ..., "\n"); flush.console()
}

# ----- Load data -----
log_msg(sprintf("B4c CT-DSEM grade %d, MIN_T=%d, MODE=%s", GRADE, MIN_T, MODE))
d <- fread(file.path(b3_dir, paste0("theta_trajectory_1pl_grade_", GRADE, ".csv")))
log_msg(sprintf("Loaded: %d rows, %d HS", nrow(d), uniqueN(d$iduser)))

# ----- Subsample T >= MIN_T -----
T_per_hs   <- d[, .N, by = iduser]
qualifying <- T_per_hs[N >= MIN_T, iduser]
d_sub      <- d[iduser %in% qualifying]
log_msg(sprintf("After T>=%d: %d HS, %d observations",
                MIN_T, length(qualifying), nrow(d_sub)))

# ----- Format for ctsem -----
# ctsem requires: id, time (numeric, continuous), Y1 (manifest variable)
# Use date as continuous time (days from earliest observation)
d_sub[, time := as.numeric(as.Date(date) - min(as.Date(date))) ]
ct_data <- d_sub[, .(id = iduser, time = time, Y1 = theta)]
ct_data <- as.data.frame(ct_data)

log_msg(sprintf("Time range: [%.0f, %.0f] days, n_unique_times=%d",
                min(ct_data$time), max(ct_data$time), uniqueN(ct_data$time)))

# ----- Define CT-DSEM model -----
log_msg("Building ctsem model spec...")
ct_model <- ctModel(
  type = "ct",
  n.latent = 1, n.manifest = 1,
  manifestNames = "Y1",
  latentNames = "eta1",
  LAMBDA = matrix(1),                          # loading fixed at 1
  MANIFESTMEANS = matrix(0),                   # mean fixed at 0
  MANIFESTVAR = matrix("manifest_var"),        # measurement error variance
  DRIFT = matrix("phi"),                       # autoregressive (mean-reverting) rate
  DIFFUSION = matrix("sigma"),                 # diffusion (innovation) variance
  T0VAR = matrix("var_T0"),                    # initial state variance
  T0MEANS = matrix("mean_T0"),                 # initial state mean
  CINT = matrix("cint")                        # continuous intercept (asymptote)
)

# Random effects on phi and cint (individual-level dynamics)
ct_model$pars$indvarying <- ct_model$pars$param %in% c("phi", "cint")
log_msg(sprintf("Indvarying params: %s",
                paste(ct_model$pars$param[ct_model$pars$indvarying], collapse = ", ")))

# ----- Fit -----
log_msg(sprintf("Fitting ctsem (mode=%s)...", MODE))
t0 <- Sys.time()

if (MODE == "optim") {
  fit_ctdsem <- ctStanFit(
    ctstanmodel = ct_model,
    datalong    = ct_data,
    optimize    = TRUE,
    priors      = FALSE,             # no priors for ML-like point estimates
    cores       = N_CORES,
    optimcontrol = list(carefulfit = FALSE)  # fast convergence
  )
} else if (MODE == "mcmc") {
  # TRUE Hamilton Monte Carlo — full Bayesian inference.
  # NOTE: optimize=FALSE is critical — optimize=TRUE gives MAP+Laplace, not HMC.
  # Default: 4 chains × 2000 iter (1000 warmup + 1000 sampling)
  # Expected runtime: ~15-30 min on 4 cores for this dataset (460 HS).
  fit_ctdsem <- ctStanFit(
    ctstanmodel = ct_model,
    datalong    = ct_data,
    optimize    = FALSE,             # FALSE = full HMC sampling
    priors      = TRUE,
    chains      = 4,
    iter        = 2000,              # 1000 warmup + 1000 sampling per chain
    cores       = N_CORES
  )
} else if (MODE == "map_laplace") {
  # MAP + Hessian-based posterior approximation (faster than HMC, less rigorous).
  # This is what the previous "mcmc" mode actually did.
  fit_ctdsem <- ctStanFit(
    ctstanmodel = ct_model,
    datalong    = ct_data,
    optimize    = TRUE,
    priors      = TRUE,
    cores       = N_CORES
  )
} else {
  stop("Unknown MODE: ", MODE, " (use 'optim', 'mcmc', or 'map_laplace')")
}

elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
log_msg(sprintf("Fit completed in %.1f minutes", elapsed))

# ----- Save full fit -----
saveRDS(fit_ctdsem, file.path(b4_dir, "ctdsem_grade_12.rds"))
log_msg("Saved ctdsem_grade_12.rds")

# ----- Extract population (fixed) parameters -----
log_msg("Extracting population parameters...")
pop_summary <- tryCatch(summary(fit_ctdsem), error = function(e) NULL)
if (!is.null(pop_summary)) {
  cat("\n=== POPULATION PARAMETERS ===\n")
  print(pop_summary$popmeans)
  if (MODE == "mcmc") {
    fwrite(as.data.table(pop_summary$popmeans, keep.rownames = "param"),
           file.path(b4_dir, "ctdsem_population_params.csv"))
  }
}

# ----- Extract individual phi_i, cint_i -----
log_msg("Extracting individual parameters (phi_i, cint_i)...")
ind_params <- tryCatch({
  ip <- ctStanSubjectPars(fit_ctdsem)
  if (is.list(ip) && "indParamsState" %in% names(ip)) {
    as.data.table(ip$indParamsState)
  } else if (is.matrix(ip)) {
    as.data.table(ip, keep.rownames = "iduser")
  } else {
    as.data.table(ip)
  }
}, error = function(e) {
  log_msg(sprintf("Failed to extract individual params: %s", conditionMessage(e)))
  NULL
})

if (!is.null(ind_params) && nrow(ind_params) > 0) {
  fwrite(ind_params, file.path(b4_dir, "ctdsem_individual_params.csv"))
  log_msg(sprintf("Saved %d individual parameter rows", nrow(ind_params)))
  cat("\n=== INDIVIDUAL PARAMS SUMMARY ===\n")
  print(summary(ind_params))

  # ---- Per-HS wide format + per-day rate calculations ----
  log_msg("Computing per-day rate statistics per HS...")
  ind_wide <- dcast(ind_params, subject ~ param, value.var = "value")
  setnames(ind_wide, "subject", "subject_id")

  # Population means (for context)
  pop_means <- if (!is.null(pop_summary)) pop_summary$popmeans else NULL
  pop_phi   <- if (!is.null(pop_means) && "phi"  %in% rownames(pop_means)) pop_means["phi",  "mean"]  else NA
  pop_cint  <- if (!is.null(pop_means) && "cint" %in% rownames(pop_means)) pop_means["cint", "mean"]  else NA

  # Per-individual: equilibrium θ_eq_i = -cint_i/phi_i, half-life h_i = ln(2)/|phi_i|
  ind_wide[, theta_eq := -cint / phi]
  ind_wide[, half_life_days := log(2) / abs(phi)]

  # Per-day expected rate at θ = current_eq (equals 0 by definition) and at θ = 0
  # dθ/dt = phi*θ + cint
  ind_wide[, rate_at_theta_neg1 := phi * (-1) + cint]
  ind_wide[, rate_at_theta_0    := phi * 0   + cint]
  ind_wide[, rate_at_theta_pos1 := phi * 1   + cint]

  # Save wide individual params with derived metrics
  fwrite(ind_wide, file.path(b4_dir, "ctdsem_individual_rates.csv"))
  log_msg(sprintf("Saved per-HS rates to ctdsem_individual_rates.csv (%d HS)", nrow(ind_wide)))

  cat("\n=== PER-DAY RATES SUMMARY (population of HS) ===\n")
  cat(sprintf("phi:       mean=%.4f  median=%.4f  range=[%.4f, %.4f]\n",
              mean(ind_wide$phi), median(ind_wide$phi),
              min(ind_wide$phi), max(ind_wide$phi)))
  cat(sprintf("cint:      mean=%.4f  median=%.4f  range=[%.4f, %.4f]\n",
              mean(ind_wide$cint), median(ind_wide$cint),
              min(ind_wide$cint), max(ind_wide$cint)))
  cat(sprintf("θ_eq_i:    mean=%.3f  median=%.3f  IQR=[%.3f, %.3f]\n",
              mean(ind_wide$theta_eq, na.rm = TRUE),
              median(ind_wide$theta_eq, na.rm = TRUE),
              quantile(ind_wide$theta_eq, 0.25, na.rm = TRUE),
              quantile(ind_wide$theta_eq, 0.75, na.rm = TRUE)))
  cat(sprintf("Half-life: median=%.0f days  IQR=[%.0f, %.0f]\n",
              median(ind_wide$half_life_days, na.rm = TRUE),
              quantile(ind_wide$half_life_days, 0.25, na.rm = TRUE),
              quantile(ind_wide$half_life_days, 0.75, na.rm = TRUE)))
  cat(sprintf("Rate at θ=-1: median=%.4f  (low ability → expected daily change)\n",
              median(ind_wide$rate_at_theta_neg1)))
  cat(sprintf("Rate at θ=0:  median=%.4f\n", median(ind_wide$rate_at_theta_0)))
  cat(sprintf("Rate at θ=+1: median=%.4f  (high ability)\n",
              median(ind_wide$rate_at_theta_pos1)))

  # ---- Population trajectory predictions ----
  log_msg("Computing population trajectory predictions...")
  if (!is.na(pop_phi) && !is.na(pop_cint)) {
    days <- seq(0, 365, by = 7)  # weekly, 1 year
    eq <- -pop_cint / pop_phi

    # Closed-form solution: θ(t) = (θ_0 - eq) * exp(phi*t) + eq
    traj_dt <- rbindlist(lapply(c(-1.5, -0.5, 0, 0.5, 1.5), function(t0) {
      data.table(
        days = days,
        theta_0 = t0,
        theta_t = (t0 - eq) * exp(pop_phi * days) + eq
      )
    }))
    fwrite(traj_dt, file.path(b4_dir, "ctdsem_predicted_trajectories.csv"))
    log_msg(sprintf("Saved 1-year predicted trajectories from θ_0 ∈ {-1.5, -0.5, 0, 0.5, 1.5}"))
  }
}

# ----- Text summary -----
log_msg("Writing summary...")
sink(file.path(b4_dir, "ctdsem_summary.txt"))
cat("CT-DSEM Grade 12 — Summary\n")
cat("Date:", format(Sys.time()), "\n")
cat("Mode:", MODE, "\n")
cat("Subsample: T>=", MIN_T, " (", length(qualifying), " HS, ",
    nrow(ct_data), " obs)\n", sep = "")
cat("Time elapsed:", round(elapsed, 1), "min\n\n")
if (!is.null(pop_summary)) {
  cat("=== Population means ===\n")
  print(pop_summary$popmeans)
  if ("popsd" %in% names(pop_summary)) {
    cat("\n=== Population SD (random effects) ===\n")
    print(pop_summary$popsd)
  }
}
sink()

log_msg("B4c complete.")
log_msg(sprintf("Total elapsed: %.1f minutes", elapsed))
