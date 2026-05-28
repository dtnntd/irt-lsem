# B3 Plots: EAP scoring diagnostics.
#
# Input:  outputs/b3_theta/theta_trajectory_1pl_grade_{N}.csv
#         (iduser, day_idx, date, n_items, theta, se)
# Output: outputs/b3_theta/plots/
#   - trajectory_samples_grade_{N}.png   9 random HS, theta-hat +/- SE
#   - theta_distribution_grade_{N}.png   distribution of theta-hat
#   - se_distribution_grade_{N}.png      distribution of SE(theta-hat)

suppressPackageStartupMessages({ library(data.table); library(ggplot2) })

b3_dir   <- file.path("outputs", "b3_theta")
plot_dir <- file.path(b3_dir, "plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

theme_minimal_research <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "gray40"))

log_msg <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "—", ..., "\n")

for (g in c(10, 11, 12)) {
  d <- fread(file.path(b3_dir, sprintf("theta_trajectory_1pl_grade_%d.csv", g)))

  # --- 9 random HS trajectories ---
  set.seed(42)
  hs <- sample(unique(d$iduser), 9)
  ds <- d[iduser %in% hs]
  ptraj <- ggplot(ds, aes(x = day_idx, y = theta)) +
    geom_ribbon(aes(ymin = theta - se, ymax = theta + se), alpha = 0.2, fill = "steelblue") +
    geom_line(color = "steelblue") +
    geom_point(size = 1.3, color = "steelblue") +
    facet_wrap(~ iduser, scales = "free_x") +
    labs(title = sprintf("Grade %d — sample theta-hat trajectories (9 HS, +/- SE)", g),
         x = "Day index", y = "theta-hat") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("trajectory_samples_grade_%d.png", g)), ptraj,
         width = 10, height = 7, dpi = 130)

  # --- theta distribution ---
  pth <- ggplot(d, aes(x = theta)) +
    geom_histogram(bins = 60, fill = "steelblue", color = "white", alpha = 0.85) +
    labs(title = sprintf("Grade %d — distribution of theta-hat", g),
         subtitle = sprintf("N obs = %d | mean = %.3f | sd = %.3f",
                            nrow(d), mean(d$theta), sd(d$theta)),
         x = "theta-hat", y = "# measurements") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("theta_distribution_grade_%d.png", g)), pth,
         width = 7, height = 4.5, dpi = 130)

  # --- SE distribution ---
  pse <- ggplot(d, aes(x = se)) +
    geom_histogram(bins = 60, fill = "tomato", color = "white", alpha = 0.85) +
    geom_vline(xintercept = median(d$se), linetype = "dashed", color = "darkred") +
    labs(title = sprintf("Grade %d — distribution of SE(theta-hat)", g),
         subtitle = sprintf("median SE = %.3f | %% SE < 0.7 = %.0f%%",
                            median(d$se), 100 * mean(d$se < 0.7)),
         x = "SE(theta-hat)", y = "# measurements") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("se_distribution_grade_%d.png", g)), pse,
         width = 7, height = 4.5, dpi = 130)

  log_msg(sprintf("Grade %d: saved B3 diagnostics (trajectory, theta, SE)", g))
}
cat("B3 plots done →", plot_dir, "\n")
