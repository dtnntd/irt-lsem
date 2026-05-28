# B4c Visualization: CT-DSEM dynamics for Grade 12
#
# Reads outputs from b4c_ctdsem.R and produces 4 plots:
#   1. Distribution of individual phi_i (mean-reversion rate)
#   2. Distribution of individual cint_i (intercept)
#   3. Distribution of individual theta_eq (equilibrium)
#   4. Predicted population trajectories (1-year horizon, multiple θ_0)
#
# Output: outputs/b4_lsem/plots/

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

b4_dir   <- Sys.getenv("B4_DIR", file.path("outputs", "b4_lsem"))
plot_dir <- file.path(b4_dir, "plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

cat("Loading individual rates...\n")
ind <- fread(file.path(b4_dir, "ctdsem_individual_rates.csv"))
cat(sprintf("  %d HS\n", nrow(ind)))

# Filter outliers in theta_eq (some HS with phi near 0 → eq → ±∞)
ind_clean <- ind[is.finite(theta_eq) & abs(theta_eq) < 5]
cat(sprintf("  After removing |theta_eq|>5: %d HS\n", nrow(ind_clean)))

theme_minimal_research <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "gray40"))

# ============================================================
# Plot 1: phi distribution (mean-reversion rate)
# ============================================================
p1 <- ggplot(ind, aes(x = phi)) +
  geom_histogram(bins = 50, fill = "steelblue", color = "white", alpha = 0.8) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "red") +
  geom_vline(xintercept = mean(ind$phi), color = "darkblue", linetype = "dotted") +
  labs(
    title = "Distribution of individual φ (CT-DSEM Grade 12)",
    subtitle = sprintf("Mean=%.4f | Median=%.4f | N=%d HS\nNegative φ = mean-reverting; |φ| larger = faster convergence",
                       mean(ind$phi), median(ind$phi), nrow(ind)),
    x = "φ (drift rate, per day)", y = "# HS"
  ) +
  theme_minimal_research
ggsave(file.path(plot_dir, "ctdsem_phi_distribution.png"), p1, width = 8, height = 5, dpi = 110)
cat("Saved: ctdsem_phi_distribution.png\n")

# ============================================================
# Plot 2: cint distribution (continuous intercept)
# ============================================================
p2 <- ggplot(ind, aes(x = cint)) +
  geom_histogram(bins = 50, fill = "darkorange", color = "white", alpha = 0.8) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "red") +
  geom_vline(xintercept = mean(ind$cint), color = "darkorange4", linetype = "dotted") +
  labs(
    title = "Distribution of individual c (continuous intercept)",
    subtitle = sprintf("Mean=%.4f | Median=%.4f\nPositive c = baseline pull upward each day",
                       mean(ind$cint), median(ind$cint)),
    x = "c (intercept, logit/day)", y = "# HS"
  ) +
  theme_minimal_research
ggsave(file.path(plot_dir, "ctdsem_cint_distribution.png"), p2, width = 8, height = 5, dpi = 110)
cat("Saved: ctdsem_cint_distribution.png\n")

# ============================================================
# Plot 3: theta_eq distribution (asymptotic ability per HS)
# ============================================================
p3 <- ggplot(ind_clean, aes(x = theta_eq)) +
  geom_histogram(bins = 50, fill = "forestgreen", color = "white", alpha = 0.8) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
  geom_vline(xintercept = median(ind_clean$theta_eq), color = "darkgreen", linetype = "dotted") +
  labs(
    title = "Distribution of individual θ_eq (asymptotic ability)",
    subtitle = sprintf("Median=%.2f | IQR=[%.2f, %.2f]\nθ_eq = -c/φ: long-run ability if dynamics continue",
                       median(ind_clean$theta_eq),
                       quantile(ind_clean$theta_eq, 0.25),
                       quantile(ind_clean$theta_eq, 0.75)),
    x = "θ_eq (logit)", y = "# HS"
  ) +
  theme_minimal_research
ggsave(file.path(plot_dir, "ctdsem_theta_eq_distribution.png"), p3, width = 8, height = 5, dpi = 110)
cat("Saved: ctdsem_theta_eq_distribution.png\n")

# ============================================================
# Plot 4: Predicted population trajectories
# ============================================================
traj_path <- file.path(b4_dir, "ctdsem_predicted_trajectories.csv")
if (file.exists(traj_path)) {
  traj <- fread(traj_path)
  traj[, theta_0_lab := factor(sprintf("θ₀ = %+.1f", theta_0),
                               levels = sort(sprintf("θ₀ = %+.1f", unique(theta_0))))]

  eq_pop <- median(traj[days == max(days), theta_t])

  p4 <- ggplot(traj, aes(x = days, y = theta_t, color = theta_0_lab, group = theta_0_lab)) +
    geom_line(linewidth = 1.1) +
    geom_hline(yintercept = eq_pop, linetype = "dashed", color = "gray50") +
    annotate("text", x = max(traj$days) * 0.85, y = eq_pop + 0.08,
             label = sprintf("Equilibrium ≈ %.2f", eq_pop), color = "gray30") +
    scale_color_brewer(palette = "RdYlBu", direction = -1, name = "Initial θ₀") +
    labs(
      title = "Predicted θ trajectories (CT-DSEM, population-mean params)",
      subtitle = "1-year horizon. All trajectories converge to common equilibrium.",
      x = "Days", y = "Predicted θ"
    ) +
    theme_minimal_research +
    theme(legend.position = "right")
  ggsave(file.path(plot_dir, "ctdsem_predicted_trajectories.png"), p4, width = 9, height = 5.5, dpi = 110)
  cat("Saved: ctdsem_predicted_trajectories.png\n")
}

# ============================================================
# Plot 5: Per-day rate by current theta (catch-up vs Matthew)
# ============================================================
# For each HS, compute rate_at_theta = phi*theta + cint at multiple theta
theta_grid <- seq(-2, 2, by = 0.05)
rate_dt <- rbindlist(lapply(theta_grid, function(t) {
  ind[, .(theta = t, rate = phi * t + cint, subject_id)]
}))

# Sample 50 HS for individual lines
set.seed(42)
sample_hs <- sample(unique(rate_dt$subject_id), 50)

p5 <- ggplot() +
  geom_line(data = rate_dt[subject_id %in% sample_hs],
            aes(x = theta, y = rate, group = subject_id),
            alpha = 0.15, color = "steelblue") +
  geom_line(data = rate_dt[, .(rate = mean(rate)), by = theta],
            aes(x = theta, y = rate),
            color = "darkred", linewidth = 1.3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray60") +
  geom_vline(xintercept = 0, linetype = "dotted", color = "gray70") +
  labs(
    title = "Per-day θ change rate vs current θ",
    subtitle = "Each blue line = 1 HS (sample 50). Red = population mean.\nAbove 0: improving; below 0: declining. Crossing 0 = personal equilibrium.",
    x = "Current θ", y = "dθ/dt (logit per day)"
  ) +
  theme_minimal_research
ggsave(file.path(plot_dir, "ctdsem_rate_vs_theta.png"), p5, width = 9, height = 5.5, dpi = 110)
cat("Saved: ctdsem_rate_vs_theta.png\n")

cat("\nAll plots saved to:", plot_dir, "\n")
