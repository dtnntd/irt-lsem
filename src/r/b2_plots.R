# B2 Plots: IRT calibration diagnostics.
#
# Input:  outputs/b2_calibration/irt_1pl_grade_{N}.csv         (question_id, b)
#         outputs/b2_calibration/irt_2pl_grade_{N}_clean.csv   (question_id, a, b)
#         outputs/b3_theta/theta_trajectory_1pl_grade_{N}.csv  (for Wright map)
# Output: outputs/b2_calibration/plots/
#   - difficulty_dist_grade_{N}.png       b distribution (1PL vs 2PL)
#   - discrimination_dist_grade_{N}.png   a distribution (2PL clean)
#   - wright_map_grade_{N}.png            HS ability vs item difficulty
#   - icc_grade_{N}.png                   ICC of 9 representative items (analytic)

suppressPackageStartupMessages({ library(data.table); library(ggplot2) })

b2_dir   <- file.path("outputs", "b2_calibration")
b3_dir   <- file.path("outputs", "b3_theta")
plot_dir <- file.path(b2_dir, "plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

theme_minimal_research <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "gray40"))

log_msg <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "—", ..., "\n")

for (g in c(10, 11, 12)) {
  d1 <- fread(file.path(b2_dir, sprintf("irt_1pl_grade_%d.csv", g)))        # question_id, b
  d2 <- fread(file.path(b2_dir, sprintf("irt_2pl_grade_%d_clean.csv", g)))  # question_id, a, b

  # --- difficulty distribution (1PL vs 2PL) ---
  bdat <- rbind(data.table(b = d1$b, model = "1PL"),
                data.table(b = d2$b, model = "2PL"))
  pdif <- ggplot(bdat, aes(x = b, fill = model)) +
    geom_histogram(bins = 50, position = "identity", alpha = 0.5) +
    labs(title = sprintf("Grade %d — item difficulty b", g),
         subtitle = sprintf("1PL: %d items | 2PL clean: %d items", nrow(d1), nrow(d2)),
         x = "Difficulty b (logit)", y = "# items", fill = "Model") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("difficulty_dist_grade_%d.png", g)), pdif,
         width = 7, height = 4.5, dpi = 130)

  # --- discrimination distribution (2PL) ---
  pa <- ggplot(d2, aes(x = a)) +
    geom_histogram(bins = 50, fill = "purple4", color = "white", alpha = 0.8) +
    geom_vline(xintercept = 1, linetype = "dashed", color = "red") +
    geom_vline(xintercept = median(d2$a), linetype = "dotted", color = "purple4") +
    labs(title = sprintf("Grade %d — item discrimination a (2PL)", g),
         subtitle = sprintf("median a = %.2f | IQR = [%.2f, %.2f]; dashed = 1.0 (Rasch)",
                            median(d2$a), quantile(d2$a, .25), quantile(d2$a, .75)),
         x = "Discrimination a", y = "# items") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("discrimination_dist_grade_%d.png", g)), pa,
         width = 7, height = 4.5, dpi = 130)

  # --- Wright map: HS ability (theta) vs item difficulty (b) ---
  th <- fread(file.path(b3_dir, sprintf("theta_trajectory_1pl_grade_%d.csv", g)))
  wm <- rbind(data.table(value = th$theta, type = "HS ability (theta-hat)"),
              data.table(value = d1$b,     type = "Item difficulty (b)"))
  pwm <- ggplot(wm, aes(x = value, fill = type)) +
    geom_histogram(bins = 50, alpha = 0.7) +
    facet_wrap(~ type, ncol = 1, scales = "free_y") +
    labs(title = sprintf("Grade %d — Wright map (ability vs difficulty)", g),
         x = "Logit scale", y = "Count") +
    theme_minimal_research + theme(legend.position = "none")
  ggsave(file.path(plot_dir, sprintf("wright_map_grade_%d.png", g)), pwm,
         width = 7, height = 5.5, dpi = 130)

  # --- ICC of 9 representative items (analytic, 2PL) ---
  setorder(d2, b)
  n <- nrow(d2)
  idx <- unique(c(1:3, floor(n/2) + (-1:1), (n-2):n))
  sel <- d2[idx]
  theta_grid <- seq(-4, 4, 0.1)
  icc <- sel[, .(theta = theta_grid, p = plogis(a * (theta_grid - b))), by = question_id]
  icc <- merge(icc, sel[, .(question_id, b)], by = "question_id")
  icc[, lab := sprintf("item %s (b=%.1f)", question_id, b)]
  picc <- ggplot(icc, aes(x = theta, y = p, group = question_id)) +
    geom_line(color = "darkblue", linewidth = 0.9) +
    facet_wrap(~ reorder(lab, b)) +
    labs(title = sprintf("Grade %d — ICC of 9 representative items (2PL)", g),
         subtitle = "3 easy / 3 medium / 3 hard by difficulty b",
         x = "theta", y = "P(correct)") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("icc_grade_%d.png", g)), picc,
         width = 9, height = 7, dpi = 130)

  log_msg(sprintf("Grade %d: saved B2 diagnostics (difficulty, discrimination, Wright, ICC)", g))
}
cat("B2 plots done →", plot_dir, "\n")
