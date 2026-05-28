# run_b2_with_progress.R
# Helper for R-only environments (e.g. Colab R kernel) where stdout buffering
# hides mirt EM iterations until convergence.
#
# Strategy: launch b2_calibration.R as a background OS process with stdout
# redirected to a log file, then poll the file from the current R session
# and print new content periodically.
#
# === USAGE (copy into a single Colab R cell) ===
#   setwd('/content/drive/MyDrive/irt_lsem')
#   source('src/r/run_b2_with_progress.R')
#
# Override defaults via env vars:
#   Sys.setenv(B2_SCRIPT='src/r/b2_calibration.R')
#   Sys.setenv(B2_LIVE_LOG='outputs/b2_calibration/b2_live.log')
#   Sys.setenv(POLL_INTERVAL='3')   # seconds

# ---- Config ----
SCRIPT      <- Sys.getenv("B2_SCRIPT",     "src/r/b2_calibration.R")
LIVE_LOG    <- Sys.getenv("B2_LIVE_LOG",   "outputs/b2_calibration/b2_live.log")
POLL_SEC    <- as.numeric(Sys.getenv("POLL_INTERVAL", "3"))
PROCESS_TAG <- "b2_calibration.R"  # for pgrep

# ---- Prep ----
dir.create(dirname(LIVE_LOG), recursive = TRUE, showWarnings = FALSE)
if (file.exists(LIVE_LOG)) file.remove(LIVE_LOG)
file.create(LIVE_LOG)

cat("=== Launching b2_calibration.R in background ===\n")
cat("Script  :", SCRIPT, "\n")
cat("Log file:", LIVE_LOG, "\n")
cat("Poll    : every", POLL_SEC, "s\n\n")

# ---- Verify no existing instance ----
existing <- system(sprintf("pgrep -af '%s'", PROCESS_TAG), intern = TRUE)
if (length(existing) > 0) {
  cat("⚠️ Existing process(es) detected:\n")
  cat(paste(" ", existing), sep = "\n")
  cat("\nKill them first if you want a fresh run, or wait for them to finish.\n")
  cat("To kill:   system(\"pkill -f '", PROCESS_TAG, "'\")\n", sep = "")
  stop("Aborting to avoid duplicate runs.")
}

# ---- Launch Rscript in background ----
# Use stdbuf to disable stdio buffering at OS level for line-by-line streaming
launch_cmd <- sprintf(
  "nohup stdbuf -oL -eL R_PROFILE_USER=/dev/null Rscript %s > %s 2>&1 &",
  SCRIPT, LIVE_LOG
)
system(launch_cmd, wait = FALSE)
Sys.sleep(2)

# Get the PID
pid_lines <- system(sprintf("pgrep -f '%s'", PROCESS_TAG), intern = TRUE)
if (length(pid_lines) == 0) {
  stop("Failed to launch Rscript. Check the path: ", SCRIPT)
}
PID <- pid_lines[1]
cat(">>> Launched PID:", PID, "\n")
cat(">>> Streaming output below (poll every", POLL_SEC, "s)\n")
cat(strrep("=", 70), "\n", sep = "")

# ---- Poll loop ----
last_pos <- 0
silent_polls <- 0
MAX_SILENT <- 600 / POLL_SEC  # warn if no output for 10 minutes

while (TRUE) {
  Sys.sleep(POLL_SEC)

  # Read new bytes
  size <- tryCatch(file.info(LIVE_LOG)$size, error = function(e) NA_integer_)
  if (!is.na(size) && size > last_pos) {
    con <- file(LIVE_LOG, "rb")
    seek(con, last_pos)
    chunk <- readChar(con, size - last_pos, useBytes = TRUE)
    close(con)

    # Convert \r to \n so mirt iterations show as separate lines (not overwriting)
    chunk <- gsub("\r\n?", "\n", chunk)

    cat(chunk)
    flush.console()
    last_pos <- size
    silent_polls <- 0
  } else {
    silent_polls <- silent_polls + 1
    if (silent_polls %% (60 / POLL_SEC) == 0) {
      cat(sprintf("[%s] (no new output for %.0fs — process still working)\n",
                  format(Sys.time(), "%H:%M:%S"),
                  silent_polls * POLL_SEC))
      flush.console()
    }
  }

  # Check process status
  alive <- length(system(sprintf("pgrep -f '%s'", PROCESS_TAG), intern = TRUE)) > 0
  if (!alive) {
    Sys.sleep(2)  # final flush window

    size <- tryCatch(file.info(LIVE_LOG)$size, error = function(e) NA_integer_)
    if (!is.na(size) && size > last_pos) {
      con <- file(LIVE_LOG, "rb"); seek(con, last_pos)
      chunk <- readChar(con, size - last_pos, useBytes = TRUE); close(con)
      chunk <- gsub("\r\n?", "\n", chunk)
      cat(chunk)
    }
    cat("\n", strrep("=", 70), "\n=== Process ", PID, " completed ===\n", sep = "")
    break
  }
}

cat("\nFull log saved to:", LIVE_LOG, "\n")
