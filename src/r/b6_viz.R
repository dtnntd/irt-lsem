# B6 Visualization: Kalman smoothing diagnostics.
#
# Input:  outputs/b6_kalman/kalman_smoothed_grade_{N}.csv
#         outputs/b6_kalman/kalman_pop_metrics.csv
# Output: outputs/b6_kalman/plots/
#   - kalman_overlay_grade_{N}.png         9 HS facet: raw θ̂±SE_raw vs smoothed line+ribbon
#   - kalman_se_reduction_grade_{N}.png    density SE_raw vs SE_smooth + mean lines
#   - kalman_pop_gain.png                  cross-grade bar of mean variance smoothing gain

suppressPackageStartupMessages({ library(data.table); library(ggplot2) })

b6_dir   <- Sys.getenv("B6_DIR", file.path("outputs", "b6_kalman"))
plot_dir <- file.path(b6_dir, "plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

GRADES <- as.integer(strsplit(Sys.getenv("GRADES", "10,11,12"), ",")[[1]])
SEED <- 42

theme_minimal_research <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "gray40"))

grade_pal <- c("10" = "#1b9e77", "11" = "#d95f02", "12" = "#7570b3")

log_msg <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "—", ..., "\n")

# Per-grade plots ----------------------------------------------------------
for (g in GRADES) {
  in_path <- file.path(b6_dir, sprintf("kalman_smoothed_grade_%d.csv", g))
  if (!file.exists(in_path)) { log_msg("missing", in_path, "— skip"); next }
  d <- fread(in_path)

  # ----- 9-HS facet: 3 short (T<10), 3 mid (10..20), 3 long (>=20) -----
  T_per <- d[, .(T_i = .N), by = iduser]
  set.seed(SEED)
  pick_short <- sample(T_per[T_i < 10, iduser], min(3, sum(T_per$T_i < 10)))
  pick_mid   <- sample(T_per[T_i >= 10 & T_i < 20, iduser],
                       min(3, sum(T_per$T_i >= 10 & T_per$T_i < 20)))
  pick_long  <- sample(T_per[T_i >= 20, iduser], min(3, sum(T_per$T_i >= 20)))
  pick <- c(pick_short, pick_mid, pick_long)
  if (length(pick) > 0) {
    sub <- d[iduser %in% pick]
    sub[, hs_lab := factor(iduser, levels = pick,
                           labels = paste0("HS ", seq_along(pick),
                                           " (T=", T_per[match(pick, iduser), T_i], ")"))]
    p1 <- ggplot(sub, aes(x = day_idx)) +
      geom_errorbar(aes(ymin = theta_raw - 1.96 * se_raw,
                        ymax = theta_raw + 1.96 * se_raw),
                    color = "gray60", width = 0.3, alpha = 0.7) +
      geom_point(aes(y = theta_raw), color = "gray40", size = 1.6) +
      geom_ribbon(aes(ymin = theta_smooth - 1.96 * se_smooth,
                      ymax = theta_smooth + 1.96 * se_smooth),
                  fill = grade_pal[as.character(g)], alpha = 0.25) +
      geom_line(aes(y = theta_smooth),
                color = grade_pal[as.character(g)], linewidth = 1) +
      facet_wrap(~ hs_lab, scales = "free_x") +
      labs(title = sprintf("Grade %d — Kalman smoothing on 9 sample HS", g),
           subtitle = "Gray = raw EAP θ̂ ± 1.96·SE_raw   |   colored line+ribbon = smoothed",
           x = "day_idx", y = "theta") +
      theme_minimal_research
    ggsave(file.path(plot_dir, sprintf("kalman_overlay_grade_%d.png", g)), p1,
           width = 9, height = 6, dpi = 130)
  }

  # ----- SE reduction density -----
  se_long <- rbind(
    data.table(stage = "SE_raw",    se = d$se_raw),
    data.table(stage = "SE_smooth", se = d$se_smooth)
  )
  mean_raw    <- mean(d$se_raw, na.rm = TRUE)
  mean_smooth <- mean(d$se_smooth, na.rm = TRUE)
  p2 <- ggplot(se_long, aes(x = se, fill = stage, color = stage)) +
    geom_density(alpha = 0.35) +
    geom_vline(xintercept = c(mean_raw, mean_smooth),
               linetype = "dashed",
               color    = c("gray40", grade_pal[as.character(g)])) +
    scale_fill_manual(values = c("SE_raw" = "gray50",
                                 "SE_smooth" = grade_pal[as.character(g)])) +
    scale_color_manual(values = c("SE_raw" = "gray40",
                                  "SE_smooth" = grade_pal[as.character(g)])) +
    labs(title = sprintf("Grade %d — SE reduction by Kalman smoothing", g),
         subtitle = sprintf("Mean SE_raw = %.3f, mean SE_smooth = %.3f (%.0f%% var-gain)",
                            mean_raw, mean_smooth,
                            100 * (1 - mean(d$se_smooth^2, na.rm = TRUE) /
                                       mean(d$se_raw^2, na.rm = TRUE))),
         x = "SE(θ̂)", y = "Density") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("kalman_se_reduction_grade_%d.png", g)), p2,
         width = 7, height = 5, dpi = 130)

  log_msg(sprintf("Grade %d: saved overlay + SE reduction plots", g))
}

# Cross-grade pop gain -----------------------------------------------------
pop_path <- file.path(b6_dir, "kalman_pop_metrics.csv")
if (file.exists(pop_path)) {
  pop <- fread(pop_path)
  pop[, grade_lab := factor(grade, levels = GRADES,
                            labels = paste0("Grade ", GRADES))]
  p3 <- ggplot(pop, aes(x = grade_lab, y = mean_smoothing_gain,
                        fill = factor(grade))) +
    geom_col(alpha = 0.85, width = 0.6) +
    geom_text(aes(label = sprintf("%.1f%%", 100 * mean_smoothing_gain)),
              vjust = -0.5, size = 4) +
    scale_fill_manual(values = grade_pal) +
    scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                       expand = expansion(mult = c(0, 0.12))) +
    guides(fill = "none") +
    labs(title = "Cross-grade smoothing gain (variance reduction)",
         subtitle = "gain = 1 − mean(SE_smooth²) / mean(SE_raw²)",
         x = NULL, y = "Mean smoothing gain") +
    theme_minimal_research
  ggsave(file.path(plot_dir, "kalman_pop_gain.png"), p3,
         width = 7, height = 5, dpi = 130)
  log_msg("Saved kalman_pop_gain.png")
}

cat("B6 viz done →", plot_dir, "\n")
