# B7b: Item recommendation — 1PL information-max policy
#
# Per scope refinement 2026-05-28 (de-cuong MT4(b) "cá nhân hóa lộ trình"):
#   Under the 1PL Rasch model, Fisher information at ability θ for item j with
#   difficulty b_j is
#       I(θ, b_j) = P_j(θ) * (1 - P_j(θ)),  P_j(θ) = σ(θ - b_j),
#   maximised at b_j = θ (info peak = 0.25, halving at |θ - b| ≈ 1.32).
#
#   Recommender = top-k items with smallest |b_j - θ_current|, subject to
#   |b_j - θ_current| < δ (default 0.5 → I >= 0.235 → near-optimal).
#
# Demo design (10 HS per grade):
#     3 from θ ≤ Q10  (low),  4 from Q40 < θ < Q60  (mid),  3 from θ ≥ Q90  (high)
#   θ_current = θ̂ at the most recent occasion in B3 trajectory.
#   Deterministic with set.seed(42).
#
# Input:  outputs/b2_calibration/irt_1pl_grade_{N}.csv     (question_id, b)
#         outputs/b3_theta/theta_trajectory_1pl_grade_{N}.csv
# Output: outputs/b7_applications/recommendation_demo_grade_{N}.csv
#         outputs/b7_applications/b7b_run.log

suppressPackageStartupMessages({ library(data.table) })

# ----- Config -----
b2_dir <- Sys.getenv("B2_DIR", file.path("outputs", "b2_calibration"))
b3_dir <- Sys.getenv("B3_DIR", file.path("outputs", "b3_theta"))
b7_dir <- Sys.getenv("B7_DIR", file.path("outputs", "b7_applications"))
dir.create(b7_dir, showWarnings = FALSE, recursive = TRUE)

GRADES <- as.integer(strsplit(Sys.getenv("GRADES", "10,11,12"), ",")[[1]])
K      <- 5L      # top-k recommendations
DELTA  <- 0.5     # max |b - θ|
SEED   <- 42

log_path <- file.path(b7_dir, "b7b_run.log")
log_msg <- function(...) {
  msg <- paste0(format(Sys.time(), "%H:%M:%S"), " — ",
                paste(..., collapse = " "), "\n")
  cat(msg); flush.console()
  cat(msg, file = log_path, append = TRUE)
}
cat("", file = log_path)

# ----- Reusable recommender -----
#' Recommend k items maximising Fisher information at θ (1PL).
#' @param theta numeric current ability estimate (logit).
#' @param items data.table with columns (question_id, b).
#' @param k     top-k to return.
#' @param delta max |b - θ| to consider (cut for poor matches).
#' @return data.table sorted by abs_diff: rec_rank, question_id, b, abs_diff, info_at_theta
recommend_items <- function(theta, items, k = 5L, delta = 0.5) {
  it <- copy(items)
  it[, abs_diff := abs(b - theta)]
  cand <- it[abs_diff < delta]
  setorder(cand, abs_diff)
  cand <- head(cand, k)
  cand[, p_correct := plogis(theta - b)]
  cand[, info_at_theta := p_correct * (1 - p_correct)]
  cand[, rec_rank := seq_len(.N)]
  cand[, .(rec_rank, question_id, b, abs_diff, info_at_theta)]
}

# ----- Per-grade demo -----
all_recs <- list()

for (grade in GRADES) {
  log_msg(sprintf("==================== Grade %d ====================", grade))

  items <- fread(file.path(b2_dir, sprintf("irt_1pl_grade_%d.csv", grade)))
  setnames(items, names(items), tolower(names(items)))
  stopifnot(all(c("question_id", "b") %in% names(items)))
  log_msg(sprintf("Item bank: %d items, b range [%.2f, %.2f]",
                  nrow(items), min(items$b), max(items$b)))

  traj <- fread(file.path(b3_dir, sprintf("theta_trajectory_1pl_grade_%d.csv", grade)))
  setorder(traj, iduser, day_idx)
  # most recent occasion per HS
  current <- traj[, .SD[.N], by = iduser, .SDcols = c("day_idx", "theta", "se")]
  setnames(current, "theta", "theta_current")
  current <- current[!is.na(theta_current)]
  log_msg(sprintf("Current θ̂ for %d HS, range [%.2f, %.2f]",
                  nrow(current), min(current$theta_current), max(current$theta_current)))

  q10 <- quantile(current$theta_current, 0.10)
  q40 <- quantile(current$theta_current, 0.40)
  q60 <- quantile(current$theta_current, 0.60)
  q90 <- quantile(current$theta_current, 0.90)

  set.seed(SEED + grade)
  low_pool  <- current[theta_current <= q10]
  mid_pool  <- current[theta_current >  q40 & theta_current < q60]
  high_pool <- current[theta_current >= q90]

  pick_low  <- low_pool [sample(.N, min(3L, .N))]
  pick_mid  <- mid_pool [sample(.N, min(4L, .N))]
  pick_high <- high_pool[sample(.N, min(3L, .N))]
  picks <- rbindlist(list(
    cbind(pick_low,  profile = "low"),
    cbind(pick_mid,  profile = "mid"),
    cbind(pick_high, profile = "high")
  ))
  log_msg(sprintf("Demo HS selected: %d (low=%d mid=%d high=%d)",
                  nrow(picks), nrow(pick_low), nrow(pick_mid), nrow(pick_high)))

  rec_rows <- lapply(seq_len(nrow(picks)), function(i) {
    rec <- recommend_items(picks$theta_current[i], items, k = K, delta = DELTA)
    if (nrow(rec) == 0L) {
      log_msg(sprintf("  HS %d (θ=%.3f, profile=%s): NO items within |b-θ|<%.2f",
                      picks$iduser[i], picks$theta_current[i],
                      picks$profile[i], DELTA))
      return(NULL)
    }
    rec[, iduser := picks$iduser[i]]
    rec[, theta_current := picks$theta_current[i]]
    rec[, profile := picks$profile[i]]
    rec[]
  })
  recs <- rbindlist(rec_rows, use.names = TRUE)
  if (nrow(recs) > 0L) {
    setcolorder(recs, c("iduser", "theta_current", "profile",
                        "rec_rank", "question_id", "b",
                        "abs_diff", "info_at_theta"))
  }
  out_path <- file.path(b7_dir, sprintf("recommendation_demo_grade_%d.csv", grade))
  fwrite(recs, out_path)
  log_msg(sprintf("Wrote %s (%d rec rows, %d unique HS)",
                  out_path, nrow(recs), uniqueN(recs$iduser)))

  recs[, grade := grade]
  all_recs[[as.character(grade)]] <- recs
}

# ----- Summary -----
sink(file.path(b7_dir, "b7b_summary.txt"))
cat("B7b Item recommendation (1PL info-max) — Summary\n")
cat("Date:", format(Sys.time()), "\n")
cat(sprintf("Policy: top-%d items minimizing |b - θ̂|, capped at δ=%.2f.\n", K, DELTA))
cat("Per grade demo: 3 low (θ≤Q10) + 4 mid (Q40<θ<Q60) + 3 high (θ≥Q90).\n\n")
combined <- rbindlist(all_recs, fill = TRUE)
if (nrow(combined) > 0L) {
  cat(sprintf("Total rec rows: %d across %d unique HS\n",
              nrow(combined), uniqueN(combined$iduser)))
  cat(sprintf("abs_diff: median=%.3f, 90th pct=%.3f, max=%.3f\n",
              median(combined$abs_diff),
              quantile(combined$abs_diff, 0.90),
              max(combined$abs_diff)))
  cat(sprintf("info_at_theta: median=%.4f (max possible = 0.25)\n",
              median(combined$info_at_theta)))
}
sink()

log_msg("B7b complete.")
