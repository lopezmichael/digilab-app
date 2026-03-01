# scripts/analysis/visualize_comparison.R
# Visualizations for rating algorithm comparison
# Generates histograms and rank change analysis
#
# Usage: source("scripts/analysis/visualize_comparison.R")

library(ggplot2)
library(dplyr)
library(tidyr)

# Try to load atomtemplates for theming (optional)
has_atomtemplates <- requireNamespace("atomtemplates", quietly = TRUE)
if (has_atomtemplates) {
  library(atomtemplates)
  message("Using atomtemplates theming")
}

OUTPUT_DIR <- "scripts/analysis/snapshots"

# -----------------------------------------------------------------------------
# Custom theme (Atom-inspired clean look)
# -----------------------------------------------------------------------------

theme_atom_analysis <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold", size = 14, color = "#1a1a2e"),
      plot.subtitle = element_text(size = 11, color = "#4a4a6a"),
      plot.caption = element_text(size = 9, color = "#6a6a8a", hjust = 0),
      axis.title = element_text(size = 11, color = "#2a2a4a"),
      axis.text = element_text(size = 10, color = "#4a4a6a"),
      panel.grid.major = element_line(color = "#e0e0e8", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      legend.position = "top",
      legend.title = element_text(size = 10, face = "bold"),
      legend.text = element_text(size = 9),
      plot.background = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA)
    )
}

# Color palette
COLORS <- list(
  old = "#e74c3c",      # Red for old algorithm
  new = "#3498db",      # Blue for new algorithm
  gain = "#27ae60",     # Green for gains
  loss = "#c0392b",     # Dark red for losses
  neutral = "#95a5a6"   # Gray for neutral
)

# -----------------------------------------------------------------------------
# Load comparison data
# -----------------------------------------------------------------------------

load_comparison_data <- function() {
  # Find the most recent comparison file
  files <- list.files(OUTPUT_DIR, pattern = "^algorithm_comparison_.*\\.csv$", full.names = TRUE)
  if (length(files) == 0) {
    stop("No comparison data found. Run compare_algorithms_readonly.R first.")
  }
  latest_file <- files[which.max(file.info(files)$mtime)]
  message(sprintf("Loading: %s", latest_file))
  read.csv(latest_file, stringsAsFactors = FALSE)
}

# -----------------------------------------------------------------------------
# 1. Rating Distribution Histograms (Before/After)
# -----------------------------------------------------------------------------

plot_rating_histograms <- function(data) {
  # Prepare data for faceted plot
  plot_data <- data %>%
    select(player_id, competitive_rating_old, competitive_rating_new) %>%
    pivot_longer(
      cols = c(competitive_rating_old, competitive_rating_new),
      names_to = "algorithm",
      values_to = "rating"
    ) %>%
    mutate(algorithm = ifelse(algorithm == "competitive_rating_old",
                              "OLD (5-pass, decay)", "NEW (1-pass, no decay)"))

  p <- ggplot(plot_data, aes(x = rating, fill = algorithm)) +
    geom_histogram(binwidth = 10, alpha = 0.8, color = "white", linewidth = 0.2) +
    facet_wrap(~algorithm, ncol = 1) +
    scale_fill_manual(values = c("OLD (5-pass, decay)" = COLORS$old,
                                  "NEW (1-pass, no decay)" = COLORS$new)) +
    labs(
      title = "Rating Distribution: Before vs After",
      subtitle = "New algorithm compresses the rating spread significantly",
      x = "Competitive Rating",
      y = "Number of Players",
      caption = sprintf("n = %d players", nrow(data))
    ) +
    theme_atom_analysis() +
    theme(legend.position = "none")

  ggsave(file.path(OUTPUT_DIR, "histogram_before_after.png"), p,
         width = 10, height = 8, dpi = 150, bg = "white")
  message("Saved: histogram_before_after.png")
  p
}

# -----------------------------------------------------------------------------
# 2. Overlayed Rating Distribution
# -----------------------------------------------------------------------------

plot_rating_overlay <- function(data) {
  plot_data <- data %>%
    select(player_id, competitive_rating_old, competitive_rating_new) %>%
    pivot_longer(
      cols = c(competitive_rating_old, competitive_rating_new),
      names_to = "algorithm",
      values_to = "rating"
    ) %>%
    mutate(algorithm = ifelse(algorithm == "competitive_rating_old",
                              "OLD (5-pass, decay)", "NEW (1-pass, no decay)"))

  p <- ggplot(plot_data, aes(x = rating, fill = algorithm)) +
    geom_histogram(binwidth = 10, alpha = 0.5, position = "identity",
                   color = NA) +
    geom_density(aes(y = after_stat(count) * 10, color = algorithm),
                 linewidth = 1, fill = NA) +
    scale_fill_manual(values = c("OLD (5-pass, decay)" = COLORS$old,
                                  "NEW (1-pass, no decay)" = COLORS$new)) +
    scale_color_manual(values = c("OLD (5-pass, decay)" = COLORS$old,
                                   "NEW (1-pass, no decay)" = COLORS$new)) +
    labs(
      title = "Rating Distribution Comparison (Overlayed)",
      subtitle = "OLD has wider spread (1245-1760) vs NEW (1364-1645)",
      x = "Competitive Rating",
      y = "Number of Players",
      fill = "Algorithm",
      color = "Algorithm",
      caption = sprintf("n = %d players | OLD range: %d | NEW range: %d",
                        nrow(data),
                        max(data$competitive_rating_old) - min(data$competitive_rating_old),
                        max(data$competitive_rating_new) - min(data$competitive_rating_new))
    ) +
    theme_atom_analysis() +
    theme(legend.position = "top")

  ggsave(file.path(OUTPUT_DIR, "histogram_overlay.png"), p,
         width = 10, height = 6, dpi = 150, bg = "white")
  message("Saved: histogram_overlay.png")
  p
}

# -----------------------------------------------------------------------------
# 3. Rating Change Distribution
# -----------------------------------------------------------------------------

plot_rating_change <- function(data) {
  p <- ggplot(data, aes(x = rating_change)) +
    geom_histogram(binwidth = 10, fill = COLORS$new, alpha = 0.7,
                   color = "white", linewidth = 0.2) +
    geom_vline(xintercept = 0, color = COLORS$neutral, linewidth = 1, linetype = "dashed") +
    geom_vline(xintercept = mean(data$rating_change), color = COLORS$old,
               linewidth = 1, linetype = "solid") +
    annotate("text", x = mean(data$rating_change) + 5, y = Inf,
             label = sprintf("Mean: %+.1f", mean(data$rating_change)),
             hjust = 0, vjust = 2, size = 3.5, color = COLORS$old) +
    labs(
      title = "Distribution of Rating Changes (NEW - OLD)",
      subtitle = "Most players within +/- 100 points; roughly symmetric distribution",
      x = "Rating Change",
      y = "Number of Players",
      caption = sprintf("Mean: %+.1f | Median: %+.1f | SD: %.1f",
                        mean(data$rating_change),
                        median(data$rating_change),
                        sd(data$rating_change))
    ) +
    theme_atom_analysis()

  ggsave(file.path(OUTPUT_DIR, "histogram_rating_change.png"), p,
         width = 10, height = 6, dpi = 150, bg = "white")
  message("Saved: histogram_rating_change.png")
  p
}

# -----------------------------------------------------------------------------
# 4. Rank Change Distribution
# -----------------------------------------------------------------------------

plot_rank_change <- function(data) {
  p <- ggplot(data, aes(x = rank_change)) +
    geom_histogram(binwidth = 20, fill = COLORS$new, alpha = 0.7,
                   color = "white", linewidth = 0.2) +
    geom_vline(xintercept = 0, color = COLORS$neutral, linewidth = 1, linetype = "dashed") +
    labs(
      title = "Distribution of Rank Changes",
      subtitle = "Positive = moved UP in rankings, Negative = moved DOWN",
      x = "Rank Change (positions)",
      y = "Number of Players",
      caption = sprintf("Mean: %+.1f | Median: %+.1f | SD: %.1f positions",
                        mean(data$rank_change),
                        median(data$rank_change),
                        sd(data$rank_change))
    ) +
    theme_atom_analysis()

  ggsave(file.path(OUTPUT_DIR, "histogram_rank_change.png"), p,
         width = 10, height = 6, dpi = 150, bg = "white")
  message("Saved: histogram_rank_change.png")
  p
}

# -----------------------------------------------------------------------------
# 5. Rank Change vs Events Played (scatter)
# -----------------------------------------------------------------------------

plot_rank_vs_events <- function(data) {
  p <- ggplot(data, aes(x = events_played, y = rank_change)) +
    geom_hline(yintercept = 0, color = COLORS$neutral, linewidth = 0.5) +
    geom_point(aes(color = rank_change), alpha = 0.6, size = 2) +
    geom_smooth(method = "loess", se = TRUE, color = COLORS$old, fill = COLORS$old, alpha = 0.2) +
    scale_color_gradient2(low = COLORS$loss, mid = COLORS$neutral, high = COLORS$gain,
                          midpoint = 0, name = "Rank\nChange") +
    labs(
      title = "Rank Change vs Events Played",
      subtitle = "Do experienced players gain or lose rank?",
      x = "Events Played",
      y = "Rank Change (positive = improved)",
      caption = "Trend line shows LOESS smoothing"
    ) +
    theme_atom_analysis()

  ggsave(file.path(OUTPUT_DIR, "scatter_rank_vs_events.png"), p,
         width = 10, height = 6, dpi = 150, bg = "white")
  message("Saved: scatter_rank_vs_events.png")
  p
}

# -----------------------------------------------------------------------------
# 6. Old vs New Rating (scatter with 1:1 line)
# -----------------------------------------------------------------------------

plot_old_vs_new <- function(data) {
  p <- ggplot(data, aes(x = competitive_rating_old, y = competitive_rating_new)) +
    geom_abline(intercept = 0, slope = 1, color = COLORS$neutral,
                linewidth = 1, linetype = "dashed") +
    geom_point(aes(color = rating_change), alpha = 0.5, size = 2) +
    scale_color_gradient2(low = COLORS$loss, mid = COLORS$neutral, high = COLORS$gain,
                          midpoint = 0, name = "Rating\nChange") +
    labs(
      title = "Old Rating vs New Rating",
      subtitle = "Points above dashed line gained rating; below lost rating",
      x = "OLD Rating (5-pass, decay)",
      y = "NEW Rating (1-pass, no decay)",
      caption = "Dashed line = no change (y = x)"
    ) +
    coord_fixed() +
    theme_atom_analysis()

  ggsave(file.path(OUTPUT_DIR, "scatter_old_vs_new.png"), p,
         width = 8, height = 8, dpi = 150, bg = "white")
  message("Saved: scatter_old_vs_new.png")
  p
}

# -----------------------------------------------------------------------------
# 7. Rank Change Summary Table
# -----------------------------------------------------------------------------

print_rank_summary <- function(data) {
  message("\n========================================")
  message("RANK CHANGE ANALYSIS")
  message("========================================\n")

  # Overall stats
  message("Overall Rank Changes:")
  message(sprintf("  Mean change: %+.1f positions", mean(data$rank_change)))
  message(sprintf("  Median change: %+.1f positions", median(data$rank_change)))
  message(sprintf("  Std deviation: %.1f positions", sd(data$rank_change)))
  message(sprintf("  Max improvement: %+d positions", max(data$rank_change)))
  message(sprintf("  Max decline: %+d positions", min(data$rank_change)))

  # Distribution buckets
  message("\nRank Change Distribution:")
  message(sprintf("  Improved 50+ positions: %d players (%.1f%%)",
                  sum(data$rank_change >= 50),
                  100 * sum(data$rank_change >= 50) / nrow(data)))
  message(sprintf("  Improved 10-49 positions: %d players (%.1f%%)",
                  sum(data$rank_change >= 10 & data$rank_change < 50),
                  100 * sum(data$rank_change >= 10 & data$rank_change < 50) / nrow(data)))
  message(sprintf("  Changed <10 positions: %d players (%.1f%%)",
                  sum(abs(data$rank_change) < 10),
                  100 * sum(abs(data$rank_change) < 10) / nrow(data)))
  message(sprintf("  Dropped 10-49 positions: %d players (%.1f%%)",
                  sum(data$rank_change <= -10 & data$rank_change > -50),
                  100 * sum(data$rank_change <= -10 & data$rank_change > -50) / nrow(data)))
  message(sprintf("  Dropped 50+ positions: %d players (%.1f%%)",
                  sum(data$rank_change <= -50),
                  100 * sum(data$rank_change <= -50) / nrow(data)))

  # Top 10 rank improvers
  message("\n----------------------------------------")
  message("TOP 10 RANK IMPROVEMENTS")
  message("----------------------------------------")
  top_improvers <- head(data[order(-data$rank_change), ], 10)
  for (i in 1:nrow(top_improvers)) {
    r <- top_improvers[i, ]
    message(sprintf("%2d. %-20s Rank: %4d -> %4d (%+4d) | Rating: %d -> %d",
                    i, substr(r$display_name, 1, 20),
                    as.integer(r$rank_old), as.integer(r$rank_new), as.integer(r$rank_change),
                    as.integer(r$competitive_rating_old), as.integer(r$competitive_rating_new)))
  }

  # Top 10 rank declines
  message("\n----------------------------------------")
  message("TOP 10 RANK DECLINES")
  message("----------------------------------------")
  top_decliners <- head(data[order(data$rank_change), ], 10)
  for (i in 1:nrow(top_decliners)) {
    r <- top_decliners[i, ]
    message(sprintf("%2d. %-20s Rank: %4d -> %4d (%+4d) | Rating: %d -> %d",
                    i, substr(r$display_name, 1, 20),
                    as.integer(r$rank_old), as.integer(r$rank_new), as.integer(r$rank_change),
                    as.integer(r$competitive_rating_old), as.integer(r$competitive_rating_new)))
  }

  # Top 20 (current top 20 and their changes)
  message("\n----------------------------------------")
  message("CURRENT TOP 20 - HOW THEY CHANGE")
  message("----------------------------------------")
  top20_old <- head(data[order(data$rank_old), ], 20)
  for (i in 1:nrow(top20_old)) {
    r <- top20_old[i, ]
    direction <- if (r$rank_change > 0) "UP" else if (r$rank_change < 0) "DOWN" else "SAME"
    message(sprintf("%2d. %-20s OLD #%d -> NEW #%d (%s %d)",
                    i, substr(r$display_name, 1, 20),
                    as.integer(r$rank_old), as.integer(r$rank_new),
                    direction, abs(as.integer(r$rank_change))))
  }
}

# -----------------------------------------------------------------------------
# Main: Generate all visualizations
# -----------------------------------------------------------------------------

generate_all_visualizations <- function() {
  message("\n========================================")
  message("GENERATING VISUALIZATIONS")
  message("========================================\n")

  data <- load_comparison_data()

  # Generate all plots
  plot_rating_histograms(data)
  plot_rating_overlay(data)
  plot_rating_change(data)
  plot_rank_change(data)
  plot_rank_vs_events(data)
  plot_old_vs_new(data)

  # Print rank analysis
  print_rank_summary(data)

  message("\n========================================")
  message(sprintf("All visualizations saved to: %s", OUTPUT_DIR))
  message("========================================")

  invisible(data)
}

# Run if sourced
if (interactive()) {
  message("Visualization tool loaded. Run: generate_all_visualizations()")
}
