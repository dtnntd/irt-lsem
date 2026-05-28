# B0 Plots: data-shape diagnostics.
#
# Input:  outputs/b0_preprocessed/day_mapping_grade_{N}_exam.csv
# Output: outputs/b0_preprocessed/plots/
#   - T_distribution_grade_{N}.png    histogram of T_i (occasions per HS)
#   - dt_distribution_grade_{N}.png   day-level Delta t between consecutive occasions

suppressPackageStartupMessages({ library(data.table); library(ggplot2) })

b0_dir   <- file.path("outputs", "b0_preprocessed")
plot_dir <- file.path(b0_dir, "plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

theme_minimal_research <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold"),
        plot.subtitle = element_text(color = "gray40"))

log_msg <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "—", ..., "\n")

for (g in c(10, 11, 12)) {
  dm <- fread(file.path(b0_dir, sprintf("day_mapping_grade_%d_exam.csv", g)))
  dm[, date := as.Date(date)]

  # --- T_i per HS ---
  Ti <- dm[, .(T = .N), by = iduser]
  pT <- ggplot(Ti, aes(x = T)) +
    geom_histogram(binwidth = 1, fill = "steelblue", color = "white", alpha = 0.85) +
    geom_vline(xintercept = median(Ti$T), linetype = "dashed", color = "darkred") +
    labs(title = sprintf("Grade %d — distribution of T_i (occasions per HS)", g),
         subtitle = sprintf("N = %d HS | median T = %d | max T = %d",
                            nrow(Ti), median(Ti$T), max(Ti$T)),
         x = "T_i (number of measurement days)", y = "# HS") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("T_distribution_grade_%d.png", g)), pT,
         width = 7, height = 4.5, dpi = 130)

  # --- day-level Delta t ---
  setorder(dm, iduser, day_idx)
  dts <- dm[, .(dt = as.numeric(diff(date))), by = iduser]
  dts <- dts[is.finite(dt) & dt > 0]
  pdt <- ggplot(dts, aes(x = dt)) +
    geom_histogram(bins = 50, fill = "darkorange", color = "white", alpha = 0.85) +
    scale_x_log10() +
    labs(title = sprintf("Grade %d — day-level Δt between occasions", g),
         subtitle = sprintf("median = %.0f d | P95 = %.0f d | max = %.0f d (log x-axis)",
                            median(dts$dt), quantile(dts$dt, 0.95), max(dts$dt)),
         x = "Δt (days, log scale)", y = "# intervals") +
    theme_minimal_research
  ggsave(file.path(plot_dir, sprintf("dt_distribution_grade_%d.png", g)), pdt,
         width = 7, height = 4.5, dpi = 130)

  log_msg(sprintf("Grade %d: saved T_i + Δt plots", g))
}
cat("B0 plots done →", plot_dir, "\n")
