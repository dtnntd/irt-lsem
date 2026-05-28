# B5 Plots: 4 main paper figures + composite.
#
# Input:  outputs/b5_report/final_*.csv  (produced by b5_consolidate.R)
# Output: outputs/b5_report/
#   - fig_lgcm_trajectories.png   Population growth trajectories, 3 grades
#   - fig_lcsm_coupling.png       LCSM coupling b (catch-up -> plateau)  KEY FINDING
#   - fig_slope_comparison.png    LGCM / MLM-weighted / MLM-unweighted x grade
#   - fig_dtheta_vs_theta.png     CT-DSEM dynamics regime (grade 12)
#   - fig_main_results.png        2x2 composite for the paper
#
# Run AFTER b5_consolidate.R (needs final_slope_comparison.csv + final_*.csv).

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(gridExtra)   # patchwork/cowplot not installed in this env
  library(grid)
})

b5_dir <- file.path("outputs", "b5_report")

log_msg <- function(...) { cat(format(Sys.time(), "%H:%M:%S"), "—", ..., "\n"); flush.console() }

# Shared theme (same look as b4c_viz.R)
theme_minimal_research <- theme_minimal(base_size = 13) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "gray40"))

grade_pal <- c("10" = "#1b9e77", "11" = "#d95f02", "12" = "#7570b3")

# ============================================================
# Plot 1: Population trajectories LGCM cross-grade
# ============================================================
plot_lgcm_trajectories <- function() {
  lgcm <- fread(file.path(b5_dir, "final_lgcm_params.csv"))
  wide <- dcast(lgcm[param %in% c("i_mean", "s_mean")], grade ~ param, value.var = "est")
  traj <- wide[, .(t = seq(0, 3, 0.1)), by = grade]
  traj <- merge(traj, wide, by = "grade")
  traj[, theta := i_mean + s_mean * t]

  ggplot(traj, aes(x = t, y = theta, color = factor(grade))) +
    geom_line(linewidth = 1.2) +
    scale_color_manual(values = grade_pal, name = "Grade") +
    labs(title = "Population growth trajectories by grade",
         subtitle = "LGCM linear, max_T = 4",
         x = "Occasion (capped t)", y = expression(hat(theta))) +
    theme_minimal_research
}

# ============================================================
# Plot 2: LCSM coupling cross-grade (KEY FINDING)
# ============================================================
plot_lcsm_coupling <- function() {
  lcsm <- fread(file.path(b5_dir, "final_lcsm_params.csv"))[param == "b"]
  ggplot(lcsm, aes(x = factor(grade), y = est)) +
    geom_col(fill = "steelblue", alpha = 0.75, width = 0.6) +
    geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper), width = 0.18) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
    annotate("text", x = 1, y = min(lcsm$ci_lower) - 0.012, label = "Catch-up",
             size = 4.3, color = "gray25") +
    annotate("text", x = 3, y = max(lcsm$ci_upper) + 0.012, label = "Plateau",
             size = 4.3, color = "gray25") +
    labs(title = "LCSM coupling b — catch-up to plateau shift",
         subtitle = "b < 0: low-ability students gain more; b > 0: Matthew effect",
         x = "Grade", y = "Coupling parameter b") +
    theme_minimal_research
}

# ============================================================
# Plot 3: Slope comparison across methods
# ============================================================
plot_slope_comparison <- function() {
  slopes <- fread(file.path(b5_dir, "final_slope_comparison.csv"))
  slopes[, method := factor(method,
                            levels = c("LGCM", "MLM-weighted", "MLM-unweighted"))]
  ggplot(slopes, aes(x = factor(grade), y = slope, color = method, group = method)) +
    geom_point(position = position_dodge(width = 0.4), size = 3) +
    geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper), width = 0.15,
                  position = position_dodge(width = 0.4)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    scale_color_brewer(palette = "Set1", name = "Method") +
    labs(title = "Growth slope estimates by method",
         subtitle = "Direction agreement across LGCM, MLM-weighted, MLM-unweighted",
         x = "Grade", y = "Slope (logit / occasion)") +
    theme_minimal_research
}

# ============================================================
# Plot 4: dtheta/dt vs current theta (CT-DSEM dynamics regime)
# ============================================================
plot_dtheta_vs_theta <- function() {
  pop  <- fread(file.path(b5_dir, "final_ctdsem_population.csv"))
  phi  <- pop[param == "phi",  estimate]
  cint <- pop[param == "cint", estimate]
  theta_eq <- -cint / phi
  d <- data.table(theta = seq(-2, 2, 0.05))
  d[, rate := cint + phi * theta]

  ggplot(d, aes(x = theta, y = rate)) +
    geom_line(linewidth = 1.2, color = "darkblue") +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
    geom_vline(xintercept = theta_eq, linetype = "dotted", color = "darkgreen") +
    annotate("text", x = theta_eq + 0.06, y = max(d$rate) * 0.6,
             label = sprintf("theta[eq] == %.2f", theta_eq), parse = TRUE,
             color = "darkgreen", hjust = 0, size = 4.2) +
    labs(title = "Continuous-time learning rate vs current ability",
         subtitle = "Grade 12, CT-DSEM: low-ability gain, high-ability regress",
         x = expression("Current " * theta),
         y = expression(d * theta / dt ~ "(logit/day)")) +
    theme_minimal_research
}

# ============================================================
# Build & save
# ============================================================
log_msg("Building B5 figures...")
p1 <- plot_lgcm_trajectories()
p2 <- plot_lcsm_coupling()
p3 <- plot_slope_comparison()
p4 <- plot_dtheta_vs_theta()

ggsave(file.path(b5_dir, "fig_lgcm_trajectories.png"), p1, width = 7, height = 5, dpi = 150)
ggsave(file.path(b5_dir, "fig_lcsm_coupling.png"),     p2, width = 7, height = 5, dpi = 150)
ggsave(file.path(b5_dir, "fig_slope_comparison.png"),  p3, width = 7, height = 5, dpi = 150)
ggsave(file.path(b5_dir, "fig_dtheta_vs_theta.png"),   p4, width = 7, height = 5, dpi = 150)
log_msg("  Saved 4 individual panels")

png(file.path(b5_dir, "fig_main_results.png"),
    width = 14, height = 10, units = "in", res = 300)
grid.arrange(p1, p2, p3, p4, ncol = 2,
             top = textGrob("IRT-LSEM Phase 1 — Main results",
                            gp = gpar(fontface = "bold", fontsize = 16)))
invisible(dev.off())
log_msg("  Saved fig_main_results.png (composite 4-panel)")

cat("\n", strrep("=", 60), "\n", sep = "")
cat("B5 plots done. Outputs in:", b5_dir, "\n")
cat(strrep("=", 60), "\n", sep = "")
