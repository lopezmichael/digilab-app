# Regenerate histograms with smaller bins
source("scripts/analysis/visualize_comparison.R")
data <- load_comparison_data()
plot_rating_histograms(data)
plot_rating_overlay(data)
message("Done!")
