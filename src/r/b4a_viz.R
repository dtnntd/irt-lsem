# B4a Visualization: LGCM/LCSM diagnostics.
#
# Input:  outputs/b3_theta/theta_trajectory_1pl_grade_{N}.csv
#         outputs/b4_lsem/lgcm_params_grade_{N}.csv  (i_mean, s_mean, ...)
# Output: outputs/b4_lsem/plots/
#   - lgcm_overlay_grade_{N}.png         population line over 50 sample HS
#   - lcsm_dtheta_density_grade_{N}.png  change-score density by initial-ability tercile

suppressPackageStartupMessages({ library(data.table); library(ggplot2) })

b3_dir   <- file.path("outputs", "b3_theta")
b4_dir   <- file.path("outputs", "b4_lsem")
plot_dir <- file.path(b4_dir, "plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

theme_minimal_research <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "gray40"))

log_msg <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "—", ..., "\n")

for (g in c(10, 11, 12)) {
  d  <- fread(file.path(b3_dir, sprintf("theta_trajectory_1pl_grade_%d.csv", g)))
  lg <- fread(file.path(b4_dir, sprintf("lgcm_params_grade_%d.csv", g)))
  i_mean <- lg[param == "i_mean", est]
  s_mean <- lg[param == "s_mean", est]

  # --- LGCM overlay: 50 sample HS observed (t<4) + population line ---
  dc <- d[day_idx < 4]
  set.seed(42)
  hs <- sample(unique(dc$iduser), min(50, uniqueN(dc$iduser)))
  pov <- ggplot() +
    geom_line(data = dc[iduser %in% hs], aes(x = day_idx, y = theta, group = iduser),
              alpha = 0.18, color = "gray40") +
    geom_abline(intercept = i_mean, slope = s_mean, color = "red", linewidth = 1.4) +
    labs(title = sprintf("Grade %d — LGCM population vs 50 sample HS", g),
         subtitle = sprintf("Population line: i = %.3f, s = %.4f (red); gray = observed",
                            i_mean, s_mean),
         x = "Occasion (capped t < 4)", y = "theta-hat") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("lgcm_overlay_grade_%d.png", g)), pov,
         width = 7, height = 5, dpi = 130)

  # --- LCSM change-score density by initial-ability tercile ---
  setorder(d, iduser, day_idx)
  d[, dtheta := theta - shift(theta), by = iduser]
  init <- d[day_idx == 0, .(iduser, theta0 = theta)]
  d2 <- merge(d[!is.na(dtheta)], init, by = "iduser")
  qs <- quantile(d2$theta0, c(0, 1/3, 2/3, 1), na.rm = TRUE)
  d2[, terc := cut(theta0, breaks = qs,
                   labels = c("Low theta0", "Mid theta0", "High theta0"),
                   include.lowest = TRUE)]
  pden <- ggplot(d2[!is.na(terc)], aes(x = dtheta, fill = terc, color = terc)) +
    geom_density(alpha = 0.25) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "gray40") +
    labs(title = sprintf("Grade %d — change score by initial-ability tercile", g),
         subtitle = "Catch-up: Low theta0 mass shifted right (gains more) vs High theta0",
         x = "delta-theta (consecutive occasions)", y = "Density",
         fill = "Initial", color = "Initial") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("lcsm_dtheta_density_grade_%d.png", g)), pden,
         width = 7, height = 5, dpi = 130)

  log_msg(sprintf("Grade %d: saved B4a diagnostics (LGCM overlay, LCSM density)", g))
}
cat("B4a viz done →", plot_dir, "\n")
