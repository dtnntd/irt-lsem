# B2: Per-grade IRT Calibration (1PL + 2PL)
#
# Runs both locally and on Google Colab.
#
# === USAGE ===
# Local:
#   cd research/irt_lsem
#   R_PROFILE_USER=/dev/null Rscript src/r/b2_calibration.R
#
# === RECOMMENDED COLAB USAGE (live mirt iterations in current cell) ===
# In a Python cell:
#
#   import subprocess, os
#   os.chdir('/content/drive/MyDrive/irt_lsem')
#
#   proc = subprocess.Popen(
#       ['Rscript', 'src/r/b2_calibration.R'],
#       stdout=subprocess.PIPE,
#       stderr=subprocess.STDOUT,
#       bufsize=1, text=True,
#       env={**os.environ, 'R_PROFILE_USER': '/dev/null'}
#   )
#   for line in proc.stdout:
#       print(line, end='', flush=True)
#   proc.wait()
#
# This streams every line (including mirt "Iteration: X, Log-Lik: ...") live.
#
# === ALTERNATIVE: %%R magic cell ===
# Output is buffered until cell finishes; you won't see iterations real-time.
# Only use this if you don't need live progress.
#
# === ENV VARS ===
#   B0_DIR        path to B0 outputs    (default: outputs/b0_preprocessed)
#   B2_DIR        path to B2 outputs    (default: outputs/b2_calibration)
#   FORCE_RERUN   "TRUE" to ignore existing outputs and recalibrate
#
# === OUTPUT ===
# outputs/b2_calibration/
#   - irt_{1pl,2pl}_grade_{10,11,12}.csv
#   - item_fit_{1pl,2pl}_grade_{10,11,12}.csv
#   - mirt_{1pl,2pl}_grade_{10,11,12}.rds
#   - irt_comparison_grade_{10,11,12}.txt
#   - b2_decision.txt
#   - b2_run.log

# ====================================================================
# 1. ENVIRONMENT DETECTION & PACKAGE SETUP
# ====================================================================

is_colab <- file.exists("/content") && Sys.getenv("COLAB_GPU") != "" ||
            grepl("colab", tolower(Sys.getenv("HOSTNAME")), fixed = TRUE) ||
            file.exists("/content/sample_data")

cat("Environment:", if (is_colab) "Google Colab" else "Local", "\n")

required_pkgs <- c("data.table", "mirt")
missing_pkgs <- required_pkgs[!sapply(required_pkgs, requireNamespace, quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  cat("Installing missing packages:", paste(missing_pkgs, collapse = ", "), "\n")
  install.packages(missing_pkgs, repos = "https://cloud.r-project.org",
                   Ncpus = max(1, parallel::detectCores() - 1))
}

suppressPackageStartupMessages({
  library(data.table)
  library(mirt)
})

set.seed(42)

# ====================================================================
# 2. PATHS (configurable via env vars for Colab/cloud)
# ====================================================================

default_b0 <- if (is_colab) {
  "/content/drive/MyDrive/irt_lsem/outputs/b0_preprocessed"
} else {
  file.path("outputs", "b0_preprocessed")
}
default_b2 <- if (is_colab) {
  "/content/drive/MyDrive/irt_lsem/outputs/b2_calibration"
} else {
  file.path("outputs", "b2_calibration")
}

b0_dir <- Sys.getenv("B0_DIR", unset = default_b0)
b2_dir <- Sys.getenv("B2_DIR", unset = default_b2)

dir.create(b2_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(b2_dir, "plots"), showWarnings = FALSE, recursive = TRUE)

cat("B0 input dir :", b0_dir, "\n")
cat("B2 output dir:", b2_dir, "\n")

if (!dir.exists(b0_dir)) {
  stop("B0 input directory not found: ", b0_dir,
       "\nSet B0_DIR env var to the correct path.")
}

# ====================================================================
# 3. CONFIG
# ====================================================================

GRADES         <- c(10, 11, 12)
MIN_RESP_1PL   <- 50
MIN_RESP_2PL   <- 200
FORCE_RERUN    <- as.logical(Sys.getenv("FORCE_RERUN", "FALSE"))

# RAM-aware parallel: detect available RAM and choose safe core count
get_safe_cores <- function() {
  total_cores <- parallel::detectCores(logical = FALSE)
  # On Linux, read available RAM from /proc/meminfo
  ram_gb <- tryCatch({
    if (file.exists("/proc/meminfo")) {
      mem <- readLines("/proc/meminfo", n = 5)
      avail_kb <- as.numeric(gsub("[^0-9]", "",
        grep("MemAvailable", mem, value = TRUE)))
      avail_kb / 1024 / 1024
    } else NA_real_
  }, error = function(e) NA_real_)

  if (is.na(ram_gb)) return(min(2, total_cores))

  # Conservative: 1 core per ~3GB available RAM, max 4
  safe <- min(4, total_cores - 1, max(1, floor(ram_gb / 3)))
  cat("  Detected RAM available:", round(ram_gb, 1), "GB → safe cores:", safe, "\n")
  safe
}

# Wrapper for mirt() with stage marker.
# For Colab: stdout streaming requires the script to be launched via Python
# subprocess.Popen(..., bufsize=1, text=True) — see docstring above.
# We force-flush after key prints so output reaches the parent process promptly.
mirt_with_stream <- function(..., stage = "") {
  cat(sprintf("\n==== %s @ %s ====\n", stage, format(Sys.time(), "%H:%M:%S")))
  flush.console()
  res <- mirt(...)
  flush.console()
  res
}

# ====================================================================
# 4. PROGRESS / LOGGING HELPERS
# ====================================================================

LOG_FILE <- file.path(b2_dir, "b2_run.log")
SCRIPT_START <- Sys.time()

log_msg <- function(..., level = "INFO") {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  msg <- paste(...)
  line <- sprintf("[%s] [%s] %s", ts, level, msg)
  cat(line, "\n")
  cat(line, "\n", file = LOG_FILE, append = TRUE)
  flush.console()
}

elapsed <- function(start) {
  secs <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  if (secs < 60) sprintf("%.1fs", secs)
  else if (secs < 3600) sprintf("%.1fm", secs / 60)
  else sprintf("%.2fh", secs / 3600)
}

progress_banner <- function(text, char = "=", width = 70) {
  bar <- paste(rep(char, width), collapse = "")
  cat("\n", bar, "\n", sep = "")
  cat("  ", text, " | total elapsed: ", elapsed(SCRIPT_START), "\n", sep = "")
  cat(bar, "\n", sep = "")
  cat(bar, "\n", file = LOG_FILE, append = TRUE)
  cat("  ", text, " | total elapsed: ", elapsed(SCRIPT_START), "\n",
      sep = "", file = LOG_FILE, append = TRUE)
  cat(bar, "\n", file = LOG_FILE, append = TRUE)
}

# Reset log
cat("# B2 run log — started ", as.character(SCRIPT_START), "\n",
    sep = "", file = LOG_FILE)
cat("# Environment: ", if (is_colab) "Colab" else "Local", "\n",
    sep = "", file = LOG_FILE, append = TRUE)

# ====================================================================
# 5. IDEMPOTENCY CHECK
# ====================================================================

grade_already_done <- function(grade) {
  required <- c(
    paste0("irt_1pl_grade_", grade, ".csv"),
    paste0("irt_2pl_grade_", grade, ".csv"),
    paste0("mirt_1pl_grade_", grade, ".rds"),
    paste0("mirt_2pl_grade_", grade, ".rds"),
    paste0("irt_comparison_grade_", grade, ".txt")
  )
  all(file.exists(file.path(b2_dir, required)))
}

read_existing_decision <- function(grade) {
  txt <- readLines(file.path(b2_dir, paste0("irt_comparison_grade_", grade, ".txt")))
  rec_line <- grep("Recommended", txt, value = TRUE)
  if (length(rec_line) > 0) {
    gsub(".*Recommended:\\s*([12]PL).*", "\\1", rec_line[1])
  } else "UNKNOWN"
}

# ====================================================================
# 6. CALIBRATE ONE GRADE
# ====================================================================

calibrate_grade <- function(grade) {
  grade_start <- Sys.time()
  progress_banner(sprintf("B2 GRADE %d — START", grade))

  # --- Skip if done ---
  if (!FORCE_RERUN && grade_already_done(grade)) {
    log_msg(sprintf("Grade %d already calibrated — SKIPPING", grade))
    log_msg("(set FORCE_RERUN=TRUE env var to override)")
    return(read_existing_decision(grade))
  }

  # --- Load ---
  log_msg(sprintf("[%d.1] Loading response data...", grade))
  t0 <- Sys.time()
  fpath <- file.path(b0_dir, paste0("response_long_grade_", grade, "_exam.csv"))
  if (!file.exists(fpath)) stop("Missing input: ", fpath)
  dt <- fread(fpath)
  log_msg(sprintf("       Loaded %s rows in %s", format(nrow(dt), big.mark=","), elapsed(t0)))

  # --- Filter items ---
  log_msg(sprintf("[%d.2] Filtering items by response count...", grade))
  item_counts <- dt[, .(n_resp = .N), by = question_id]
  items_50  <- item_counts[n_resp >= MIN_RESP_1PL,  question_id]
  items_200 <- item_counts[n_resp >= MIN_RESP_2PL, question_id]
  log_msg(sprintf("       items >=%d: %d | items >=%d: %d",
                  MIN_RESP_1PL, length(items_50), MIN_RESP_2PL, length(items_200)))

  # --- Dedup ---
  dt_dedup <- dt[, .(is_correct = is_correct[1]), by = .(iduser, question_id)]

  # --- Drop single-category items ---
  item_var <- dt_dedup[question_id %in% items_50,
                       .(has_both = uniqueN(is_correct) > 1), by = question_id]
  bad_items <- item_var[has_both == FALSE, question_id]
  if (length(bad_items) > 0) {
    log_msg(sprintf("       Dropping %d items with single response category", length(bad_items)))
    items_50  <- setdiff(items_50, bad_items)
    items_200 <- setdiff(items_200, bad_items)
  }

  # --- Wide matrices ---
  log_msg(sprintf("[%d.3] Building wide matrices...", grade))
  t0 <- Sys.time()
  dt_1pl <- dt_dedup[question_id %in% items_50]
  wide_1pl <- dcast(dt_1pl, iduser ~ question_id, value.var = "is_correct")
  mat_1pl <- as.matrix(wide_1pl[, -1, with = FALSE])

  dt_2pl <- dt_dedup[question_id %in% items_200]
  wide_2pl <- dcast(dt_2pl, iduser ~ question_id, value.var = "is_correct")
  mat_2pl <- as.matrix(wide_2pl[, -1, with = FALSE])
  log_msg(sprintf("       1PL matrix: %d × %d | 2PL matrix: %d × %d (built in %s)",
                  nrow(mat_1pl), ncol(mat_1pl), nrow(mat_2pl), ncol(mat_2pl), elapsed(t0)))

  rm(dt, dt_dedup, dt_1pl, dt_2pl, wide_1pl, wide_2pl); gc(verbose = FALSE)

  # --- Quadpts (lower for grade 12 to speed EM) ---
  quad_pts <- if (grade == 12) 41 else 61
  log_msg(sprintf("[%d.4] EM config: TOL=1e-4, accelerate=squarem, quadpts=%d", grade, quad_pts))

  # === 1PL ===
  log_msg(sprintf("[%d.5] Fitting 1PL (Rasch)...", grade))
  t0 <- Sys.time()
  m1pl <- mirt_with_stream(mat_1pl, model = 1, itemtype = "Rasch",
                           TOL = 1e-4, verbose = TRUE,
                           accelerate = "squarem",
                           quadpts = quad_pts,
                           technical = list(NCYCLES = 5000),
                           stage = sprintf("GRADE %d - 1PL fit", grade))
  log_msg(sprintf("       1PL converged in %s", elapsed(t0)))

  # === 2PL ===
  log_msg(sprintf("[%d.6] Fitting 2PL...", grade))
  t0 <- Sys.time()
  m2pl <- mirt_with_stream(mat_2pl, model = 1, itemtype = "2PL",
                           TOL = 1e-4, verbose = TRUE,
                           accelerate = "squarem",
                           quadpts = quad_pts,
                           technical = list(NCYCLES = 5000),
                           stage = sprintf("GRADE %d - 2PL fit", grade))
  log_msg(sprintf("       2PL converged in %s", elapsed(t0)))

  # === Comparison model ===
  log_msg(sprintf("[%d.7] Fitting 1PL on items_200 for LRT...", grade))
  t0 <- Sys.time()
  m1pl_on_200 <- mirt_with_stream(mat_2pl, model = 1, itemtype = "Rasch",
                                  TOL = 1e-4, verbose = TRUE,
                                  accelerate = "squarem",
                                  quadpts = quad_pts,
                                  technical = list(NCYCLES = 5000),
                                  stage = sprintf("GRADE %d - 1PL on 2PL items (LRT)", grade))
  log_msg(sprintf("       Done in %s", elapsed(t0)))

  comp <- anova(m1pl_on_200, m2pl)

  # --- Extract params ---
  coef_1pl_raw <- coef(m1pl, simplify = TRUE)$items
  coef_1pl_df <- data.table(
    question_id = colnames(mat_1pl),
    b = -coef_1pl_raw[, "d"]
  )
  coef_2pl_raw <- coef(m2pl, simplify = TRUE)$items
  coef_2pl_df <- data.table(
    question_id = colnames(mat_2pl),
    a = coef_2pl_raw[, "a1"],
    b = -coef_2pl_raw[, "d"] / coef_2pl_raw[, "a1"]
  )
  log_msg(sprintf("       1PL b range: [%.2f, %.2f] | 2PL a range: [%.2f, %.2f] | b range: [%.2f, %.2f]",
                  min(coef_1pl_df$b), max(coef_1pl_df$b),
                  min(coef_2pl_df$a), max(coef_2pl_df$a),
                  min(coef_2pl_df$b), max(coef_2pl_df$b)))

  # === Item fit (with parallel cluster, started ONLY here) ===
  log_msg(sprintf("[%d.8] Computing item fit (S-X2)...", grade))
  t0 <- Sys.time()
  n_cores <- get_safe_cores()
  cluster_started <- tryCatch({
    if (n_cores > 1) { mirtCluster(n_cores); TRUE } else FALSE
  }, error = function(e) {
    log_msg("mirtCluster failed:", conditionMessage(e), level = "WARN")
    FALSE
  })

  fit_1pl <- tryCatch(
    as.data.table(itemfit(m1pl, fit_stats = "S_X2", na.rm = TRUE)),
    error = function(e) { log_msg("1PL itemfit failed:", conditionMessage(e), level = "WARN"); NULL }
  )
  fit_2pl <- tryCatch(
    as.data.table(itemfit(m2pl, fit_stats = "S_X2", na.rm = TRUE)),
    error = function(e) { log_msg("2PL itemfit failed:", conditionMessage(e), level = "WARN"); NULL }
  )

  if (cluster_started) {
    mirtCluster(remove = TRUE)
    log_msg("       mirtCluster stopped, RAM freed")
  }
  log_msg(sprintf("       Itemfit done in %s", elapsed(t0)))

  if (!is.null(fit_1pl)) {
    fit_1pl[, question_id := colnames(mat_1pl)]
    pct <- round(mean(fit_1pl$p.S_X2 < 0.01, na.rm = TRUE) * 100, 1)
    log_msg(sprintf("       1PL misfit (p<0.01): %.1f%%", pct))
  }
  if (!is.null(fit_2pl)) {
    fit_2pl[, question_id := colnames(mat_2pl)]
    pct <- round(mean(fit_2pl$p.S_X2 < 0.01, na.rm = TRUE) * 100, 1)
    log_msg(sprintf("       2PL misfit (p<0.01): %.1f%%", pct))
  }

  # === Decision ===
  p_val      <- comp[2, "p"]
  bic_1pl    <- extract.mirt(m1pl_on_200, "BIC")
  bic_2pl    <- extract.mirt(m2pl, "BIC")
  aic_1pl    <- extract.mirt(m1pl_on_200, "AIC")
  aic_2pl    <- extract.mirt(m2pl, "AIC")
  delta_bic  <- bic_1pl - bic_2pl
  decision   <- if (!is.na(p_val) && p_val < 0.01 && delta_bic > 10) "2PL" else "1PL"

  log_msg(sprintf("[%d.9] Decision: %s (ΔBIC=%.1f, p=%.3g)",
                  grade, decision, delta_bic, p_val))

  # === Save outputs ===
  log_msg(sprintf("[%d.10] Saving outputs...", grade))
  fwrite(coef_1pl_df, file.path(b2_dir, paste0("irt_1pl_grade_", grade, ".csv")))
  fwrite(coef_2pl_df, file.path(b2_dir, paste0("irt_2pl_grade_", grade, ".csv")))
  if (!is.null(fit_1pl)) fwrite(fit_1pl, file.path(b2_dir, paste0("item_fit_1pl_grade_", grade, ".csv")))
  if (!is.null(fit_2pl)) fwrite(fit_2pl, file.path(b2_dir, paste0("item_fit_2pl_grade_", grade, ".csv")))
  saveRDS(m1pl, file.path(b2_dir, paste0("mirt_1pl_grade_", grade, ".rds")))
  saveRDS(m2pl, file.path(b2_dir, paste0("mirt_2pl_grade_", grade, ".rds")))

  comp_text <- capture.output(print(comp))
  writeLines(c(
    paste("Grade", grade, "— 1PL vs 2PL comparison (on items_200):"),
    "", comp_text, "",
    paste("AIC 1PL:",  round(aic_1pl, 2)),
    paste("AIC 2PL:",  round(aic_2pl, 2)),
    paste("BIC 1PL:",  round(bic_1pl, 2)),
    paste("BIC 2PL:",  round(bic_2pl, 2)),
    paste("ΔBIC (1PL - 2PL):", round(delta_bic, 2)),
    paste("LRT p-value:", format(p_val, digits = 4)),
    paste("Mean a_j (2PL):", round(mean(coef_2pl_df$a), 3)),
    paste("Var(a_j) (2PL):", round(var(coef_2pl_df$a), 3)),
    paste("Range a_j:", round(min(coef_2pl_df$a), 3), "—", round(max(coef_2pl_df$a), 3)),
    paste("Quadpts used:", quad_pts),
    "", paste("*** Recommended:", decision, "***")
  ), file.path(b2_dir, paste0("irt_comparison_grade_", grade, ".txt")))

  log_msg(sprintf("Grade %d complete in %s. Decision: %s",
                  grade, elapsed(grade_start), decision))

  rm(m1pl, m2pl, m1pl_on_200, mat_1pl, mat_2pl); gc(verbose = FALSE)
  return(decision)
}

# ====================================================================
# 7. RUN ALL GRADES
# ====================================================================

progress_banner("B2 IRT CALIBRATION (1PL + 2PL per grade)", char = "#")
log_msg(sprintf("Grades: %s | FORCE_RERUN: %s",
                paste(GRADES, collapse = ","), FORCE_RERUN))

decisions <- character(length(GRADES))
for (i in seq_along(GRADES)) {
  decisions[i] <- calibrate_grade(GRADES[i])
}

# Final summary
progress_banner("B2 COMPLETE — SUMMARY", char = "#")
writeLines(c(
  "B2 Calibration Summary",
  paste("Date:", Sys.time()),
  paste("Total elapsed:", elapsed(SCRIPT_START)), "",
  paste("Grade 10:", decisions[1]),
  paste("Grade 11:", decisions[2]),
  paste("Grade 12:", decisions[3])
), file.path(b2_dir, "b2_decision.txt"))

cat("\n")
for (i in seq_along(GRADES)) {
  log_msg(sprintf("Grade %d: %s", GRADES[i], decisions[i]))
}
log_msg(sprintf("Total runtime: %s", elapsed(SCRIPT_START)))
log_msg("Log saved to: ", LOG_FILE)
