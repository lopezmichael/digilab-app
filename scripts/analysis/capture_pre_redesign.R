# Run this to capture the pre-redesign rating snapshot
# Usage: source("scripts/analysis/capture_pre_redesign.R")

source("scripts/analysis/rating_comparison.R")

message("\n=== Capturing pre-redesign snapshot ===\n")
capture_rating_snapshot("pre_redesign")

message("\n=== Looking up specific players ===\n")
lookup_players(c("nudes", "photon", "atomshell"))

message("\n=== Done ===")
