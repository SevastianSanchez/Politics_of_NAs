
# Summary Stats of elect_dem and lib_dem variables
source("packages.R")

cat("\n=== SUMMARY STATISTICS ===\n")
summary(panel_data[, c("elect_dem", "lib_dem")])

# Detailed descriptive statistics
cat("\n=== DETAILED DESCRIPTIVE STATISTICS ===\n")
describe(panel_data[, c("elect_dem", "lib_dem")])

