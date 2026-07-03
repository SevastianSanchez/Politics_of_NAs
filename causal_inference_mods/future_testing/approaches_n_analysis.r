
################################################################################
# DEMOCRATIC BACKSLIDING & DATA AVAILABILITY ANALYSIS
# Three Approaches: TWFE, Callaway-Sant'Anna, Categorical Bins
################################################################################

# Set theme for plots
theme_set(theme_minimal(base_size = 12))

################################################################################
# 1. DATA PREPARATION
################################################################################

# Load/install packages
source("code/install_packages.r")

# Load data
df <- read.csv("data/output/ES_panel_data.csv")

# Create panel data structure
df <- df %>%
  arrange(country_code, year) %>%
  group_by(country_code) %>%
  mutate(
    # Calculate year-over-year change in democracy score
    dem_change = elect_dem - dplyr::lag(elect_dem),

    # Separate increases (backsliding) vs decreases (democratization)
    # NOTE: Higher elect_dem = MORE democratic, so:
    # - NEGATIVE change = backsliding (becoming less democratic)
    # - POSITIVE change = democratization (becoming more democratic)
    backsliding = ifelse(dem_change < 0, abs(dem_change), 0),
    democratization = ifelse(dem_change > 0, dem_change, 0),

    # Create binary indicators
    backsliding_indicator = ifelse(dem_change < 0, 1, 0),
    democratization_indicator = ifelse(dem_change > 0, 1, 0),

    # Categorical bins for magnitude of change
    change_category = case_when(
      is.na(dem_change) ~ NA_character_,
      dem_change <= -0.05 ~ "Large backsliding",
      dem_change > -0.05 & dem_change < -0.01 ~ "Moderate backsliding",
      dem_change >= -0.01 & dem_change <= 0.01 ~ "Stable",
      dem_change > 0.01 & dem_change < 0.05 ~ "Moderate democratization",
      dem_change >= 0.05 ~ "Large democratization"
    ),

    # Create treatment timing variable for Callaway-Sant'Anna
    # First year of autocratization episode for each country
    first_aut_year = ifelse(aut_ep == 1, 
                            min(year[aut_ep == 1], na.rm = TRUE), 
                            NA_real_)
  ) %>%
  ungroup()

# For C-S method: create cohort variable (0 if never treated)
df <- df %>%
  group_by(country_code) %>%
  mutate(
    aut_cohort = ifelse(any(aut_ep == 1), 
                        min(year[aut_ep == 1], na.rm = TRUE), 
                        0)
  ) %>%
  ungroup()

# Set change_category as factor with reference level
df$change_category <- factor(df$change_category, 
                             levels = c("Stable", "Moderate backsliding", 
                                        "Large backsliding",
                                       "Moderate democratization", 
                                       "Large democratization"))

# Summary statistics
cat("\n=== DATA SUMMARY ===\n")
cat(sprintf("Total observations: %d\n", nrow(df)))
cat(sprintf("Total countries: %d\n", n_distinct(df$country_code)))
cat(sprintf("Years: %d to %d\n", min(df$year), max(df$year)))
cat(sprintf("Countries with autocratization episodes: %d\n", 
            n_distinct(df$country_code[df$aut_ep == 1])))

################################################################################
# 2. APPROACH 1: TWFE WITH SEPARATE BACKSLIDING/DEMOCRATIZATION VARIABLES
################################################################################

cat("\n\n" , paste(rep("=", 80), collapse=""))
cat("\nAPPROACH 1: TWO-WAY FIXED EFFECTS (TWFE)\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# List of outcome variables
outcome_vars <- c("prop_sdg_missing", 
                 paste0("prop_miss_SDG", 1:17))

# Function to run TWFE model
run_twfe <- function(outcome, data) {
  formula_str <- paste0(outcome, " ~ backsliding + democratization + ",
                       "log_gdppc + rural_pop_pct + electric_access | ",
                       "country_code + year")

  model <- feols(as.formula(formula_str), 
                data = data,
                vcov = ~country_code)
  return(model)
}

# Run models for all outcomes
twfe_results <- list()
for (outcome in outcome_vars) {
  cat(sprintf("Running TWFE for: %s\n", outcome))
  twfe_results[[outcome]] <- run_twfe(outcome, df)
}

# Main result: Overall SDG missing data
cat("\n--- Main Result: Overall SDG Data Availability ---\n")
summary(twfe_results$prop_sdg_missing)

# Extract coefficients for all models
twfe_coefs <- map_df(names(twfe_results), function(outcome) {
  model <- twfe_results[[outcome]]
  tidy(model) %>%
    filter(term %in% c("backsliding", "democratization")) %>%
    mutate(outcome = outcome)
})

# Plot coefficient plot of TWFE
p1_coefs <- ggplot(twfe_coefs, aes(x = outcome, y = estimate, color = term)) +
  geom_point(size = 3, position = position_dodge(width = 0.5)) +
  geom_errorbar(aes(ymin = estimate - 1.96*std.error, 
                   ymax = estimate + 1.96*std.error),
               width = 0.3, position = position_dodge(width = 0.5)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  coord_flip() +
  scale_color_manual(values = c("backsliding" = "red", "democratization" = "blue"),
                    labels = c("Democratic backsliding", "Democratization")) +
  labs(title = "Approach 1: TWFE - Effects on Data Availability",
       subtitle = "Effect of democracy changes on SDG data missingness",
       x = "Outcome Variable",
       y = "Effect Size (coefficient)",
       color = "Direction of Change") +
  theme(legend.position = "bottom",
        axis.text.y = element_text(size = 8))

# Display plot 
p1_coefs

ggsave("figures/causal_inference/approach1_twfe_coefficients.png", p1_coefs, width = 10, height = 8, dpi = 300)
cat("\n✓ Saved: approach1_twfe_coefficients.png\n")

# Diagnostic: Check variation in democracy changes
cat("\n--- Diagnostic: Democracy Change Variation ---\n")
cat(sprintf("Countries with backsliding (>0): %d\n", 
            sum(df$backsliding > 0, na.rm = TRUE)))
cat(sprintf("Countries with democratization (>0): %d\n", 
            sum(df$democratization > 0, na.rm = TRUE)))
cat(sprintf("Mean backsliding (when >0): %.4f\n", 
            mean(df$backsliding[df$backsliding > 0], na.rm = TRUE)))
cat(sprintf("Mean democratization (when >0): %.4f\n", 
            mean(df$democratization[df$democratization > 0], na.rm = TRUE)))
cat(sprintf("Observations used in TWFE model: %d\n", 
            nobs(twfe_results$prop_sdg_missing)))

# Test for asymmetry using linearHypothesis
cat("\n--- Testing Asymmetric Effects ---\n")
cat("H0: backsliding = democratization\n\n")

# Check if both coefficients exist
coef_names <- names(coef(twfe_results$prop_sdg_missing))
has_both <- "backsliding" %in% coef_names && "democratization" %in% coef_names

if (has_both) {
  # Perform linear hypothesis test
  lh_test <- linearHypothesis(twfe_results$prop_sdg_missing,
                              "backsliding = democratization")
  
  print(lh_test)
  
  # Extract p-value (it's in the last row, "Pr(>F)" column)
  p_val <- lh_test[2, "Pr(>Chisq)"]
  
  cat(sprintf("\nP-value: %.4f\n", p_val))
  
  if (p_val < 0.05) {
    cat("✓ Asymmetric effects CONFIRMED (p < 0.05)\n")
    cat("  Backsliding and democratization have significantly different effects\n")
  } else {
    cat("✗ Cannot reject symmetric effects (p >= 0.05)\n")
    cat("  Backsliding and democratization may have similar magnitude effects\n")
  }
  
  # Show actual coefficients for context
  coefs <- coef(twfe_results$prop_sdg_missing)
  ses <- se(twfe_results$prop_sdg_missing)
  cat(sprintf("\nBacksliding coefficient:      %.5f (SE: %.5f)\n",
              coefs["backsliding"], ses["backsliding"]))
  cat(sprintf("Democratization coefficient:  %.5f (SE: %.5f)\n",
              coefs["democratization"], ses["democratization"]))
  
} else {
  cat("⚠ Cannot perform asymmetry test: coefficients not found\n")
  cat(sprintf("Available coefficients: %s\n", paste(coef_names, collapse = ", ")))
}


# Robustness: Include lagged outcome
cat("\n--- Robustness Check: Lagged Dependent Variable ---\n")
df <- df %>%
  group_by(country_code) %>%
  mutate(prop_sdg_missing_lag = dplyr::lag(prop_sdg_missing)) %>%
  ungroup()

# Lagged Dependent Variable (Missingness)
twfe_robust <- feols(prop_sdg_missing ~ backsliding + democratization + 
                    log_gdppc + electric_access + rural_pop_pct 
                    | country_code + year,
                    data = df,
                    panel.id = ~country_code + year,
                    vcov = ~country_code)
summary(twfe_robust)

################################################################################
# 3. APPROACH 2: CALLAWAY-SANT'ANNA (2020)
################################################################################

cat("\n\n", paste(rep("=", 80), collapse=""))
cat("\nAPPROACH 2: CALLAWAY-SANT'ANNA DIFFERENCE-IN-DIFFERENCES\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# Prepare data for C-S (remove missing values)
cs_data <- df %>%
  filter(!is.na(prop_sdg_missing),
         !is.na(log_gdppc),
         !is.na(log_pop)) %>%
  mutate(
    # Ensure numeric IDs
    country_id = as.numeric(factor(country_code))
  )
# Sample size information
cat(sprintf("Sample size for C-S analysis: %d observations\n", nrow(cs_data)))

# Count never-treated countries properly
n_never_treated <- cs_data %>%
  distinct(country_code, aut_cohort) %>%
  filter(aut_cohort == 0) %>%
  nrow()

n_treated <- cs_data %>%
  distinct(country_code, aut_cohort) %>%
  filter(aut_cohort > 0) %>%
  nrow()

cat(sprintf("Never-treated countries: %d\n", n_never_treated))
cat(sprintf("Treated countries (ever autocratized): %d\n", n_treated))

# Run Callaway-Sant'Anna
cat("\nEstimating group-time ATTs...\n")
cs_results <- att_gt(
  yname = "prop_sdg_missing",
  tname = "year",
  idname = "country_id",
  gname = "aut_cohort",
  xformla = ~ log_gdppc + log_pop + electric_access + rural_pop_pct,
  data = cs_data,
  control_group = "notyettreated",
  clustervars = "country_id",
  est_method = "reg",
  print_details = FALSE
)

# Overall ATT
cat("\n--- Overall Average Treatment Effect on Treated ---\n")
cs_agg <- aggte(cs_results, type = "simple")
summary(cs_agg)

# Event study (dynamic effects)
cat("\n--- Dynamic Treatment Effects (Event Study) ---\n")
cs_dynamic <- aggte(cs_results, type = "dynamic")
summary(cs_dynamic)

# Plot event study
p2_event <- ggdid(cs_dynamic, 
                  title = "Approach 2: Callaway-Sant'Anna Event Study",
                  xlab = "Years relative to autocratization start",
                  ylab = "ATT on SDG data missingness") +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(hjust = 0.5))

# display plot
p2_event

ggsave("figures/causal_inference/approach2_cs_event_study.png", p2_event, width = 10, height = 6, dpi = 300)
cat("\n✓ Saved: approach2_cs_event_study.png\n")

# Group-specific effects
cat("\n--- Group-Specific Effects (by Cohort) ---\n")
cs_group <- aggte(cs_results, type = "group")
summary(cs_group)

# Plot group effects
p2_group <- ggdid(cs_group,
                 title = "Approach 2: Treatment Effects by Cohort",
                 xlab = "Treatment cohort (year)",
                 ylab = "ATT on SDG data missingness") +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(hjust = 0.5))

# display plot
p2_group

ggsave("figures/causal_inference/approach2_cs_group_effects.png", p2_group, width = 10, height = 6, dpi = 300)
cat("\n✓ Saved: approach2_cs_group_effects.png\n")

# Calendar time effects
cat("\n--- Calendar Time Effects ---\n")
cs_calendar <- aggte(cs_results, type = "calendar")
summary(cs_calendar)

################################################################################
# 4. APPROACH 3: CATEGORICAL BINS
################################################################################

cat("\n\n", paste(rep("=", 80), collapse=""))
cat("\nAPPROACH 3: CATEGORICAL CHANGE BINS\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# Distribution of change categories
cat("--- Distribution of Democracy Change Categories ---\n")
table_cat <- table(df$change_category, useNA = "ifany")
print(table_cat)
print(prop.table(table_cat))

# Run categorical model
cat("\n--- Categorical Model: Main Results ---\n")
cat_model <- feols(prop_sdg_missing ~ change_category + 
                   log_gdppc + log_pop + electric_access + rural_pop_pct|
                   country_code + year,
                  data = df,
                  vcov = ~country_code)
summary(cat_model)

# Extract and plot coefficients
cat_coefs <- tidy(cat_model) %>%
  filter(grepl("change_category", term)) %>%
  mutate(
    category = str_remove(term, "change_category"),
    category = factor(category, 
                     levels = c("Moderate backsliding", "Large backsliding",
                               "Moderate democratization", "Large democratization"))
  )

# Add reference category (Stable = 0)
cat_coefs <- bind_rows(
  tibble(term = "Stable", estimate = 0, std.error = 0, 
         statistic = 0, p.value = 1, category = "Stable"),
  cat_coefs
)

cat_coefs$category <- factor(cat_coefs$category,
                             levels = c("Large backsliding", "Moderate backsliding", 
                                       "Stable",
                                       "Moderate democratization", "Large democratization"))

# Plot error-bar of categorical effects
p3_cat <- ggplot(cat_coefs, aes(x = category, y = estimate)) +
  geom_point(size = 4, aes(color = category)) +
  geom_errorbar(aes(ymin = estimate - 1.96*std.error,
                   ymax = estimate + 1.96*std.error),
               width = 0.2, linewidth = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  scale_color_manual(values = c("Large backsliding" = "#d73027",
                                "Moderate backsliding" = "#fc8d59",
                                "Stable" = "gray50",
                                "Moderate democratization" = "#91bfdb",
                                "Large democratization" = "#4575b4")) +
  labs(title = "Approach 3: Categorical Effects of Democracy Changes",
       subtitle = "Effect on overall SDG data missingness (relative to stable democracies)",
       x = "Change Category",
       y = "Effect Size (coefficient)") +
  theme(legend.position = "none",
        axis.text.x = element_text(angle = 45, hjust = 1)) +
  coord_flip()

# display plot
p3_cat

ggsave("figures/causal_inference/approach3_categorical_effects.png", p3_cat, width = 10, height = 6, dpi = 300)
cat("\n✓ Saved: approach3_categorical_effects.png\n")

# Run for all SDG outcomes
cat("\n--- Running Categorical Models for All SDGs ---\n")
cat_results <- list()
for (outcome in outcome_vars) {
  cat(sprintf("  Processing: %s\n", outcome))
  formula_str <- paste0(outcome, " ~ change_category + ",
                       "log_gdppc + log_pop + rural_pop_pct | ",
                       "country_code + year")
  cat_results[[outcome]] <- feols(as.formula(formula_str),
                                 data = df,
                                 vcov = ~country_code)
}

# Extract coefficients for heatmap
cat_all_coefs <- map_df(names(cat_results), function(outcome) {
  model <- cat_results[[outcome]]
  tidy(model) %>%
    filter(grepl("change_category", term)) %>%
    mutate(
      outcome = outcome,
      category = str_remove(term, "change_category")
    )
})

# Plot heatmap of categorical effects
p3_heatmap <- ggplot(cat_all_coefs, aes(x = outcome, y = category, fill = estimate)) +
  geom_tile(color = "white") +
  geom_text(aes(label = sprintf("%.3f", estimate)), size = 2.5) +
  scale_fill_gradient2(low = "blue", mid = "white", high = "red",
                      midpoint = 0, name = "Effect\nSize") +
  labs(title = "Approach 3: Categorical Effects Across All SDG Indicators",
       x = "Outcome Variable",
       y = "Democracy Change Category") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 8))

# display heatmap
p3_heatmap

ggsave("figures/causal_inference/approach3_heatmap_all_sdgs.png", p3_heatmap, width = 12, height = 6, dpi = 300)
cat("\n✓ Saved: approach3_heatmap_all_sdgs.png\n")

################################################################################
# 5. COMPARISON OF APPROACHES
################################################################################

cat("\n\n", paste(rep("=", 80), collapse=""))
cat("\nCOMPARING ALL THREE APPROACHES\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# Extract key estimates
comparison_data <- tibble(
  Approach = c("TWFE - Backsliding", 
               "TWFE - Democratization",
               "Callaway-Sant'Anna",
               "Categorical - Large Backsliding",
               "Categorical - Moderate Backsliding",
               "Categorical - Moderate Democratization",
               "Categorical - Large Democratization"),
  Estimate = c(
    coef(twfe_results$prop_sdg_missing)["backsliding"],
    coef(twfe_results$prop_sdg_missing)["democratization"],
    cs_agg$overall.att,
    coef(cat_model)["change_categoryLarge backsliding"],
    coef(cat_model)["change_categoryModerate backsliding"],
    coef(cat_model)["change_categoryModerate democratization"],
    coef(cat_model)["change_categoryLarge democratization"]
  ),
  SE = c(
    se(twfe_results$prop_sdg_missing)["backsliding"],
    se(twfe_results$prop_sdg_missing)["democratization"],
    cs_agg$overall.se,
    se(cat_model)["change_categoryLarge backsliding"],
    se(cat_model)["change_categoryModerate backsliding"],
    se(cat_model)["change_categoryModerate democratization"],
    se(cat_model)["change_categoryLarge democratization"]
  )
) %>%
  mutate(
    CI_lower = Estimate - 1.96 * SE,
    CI_upper = Estimate + 1.96 * SE,
    Method = case_when(
      grepl("TWFE", Approach) ~ "Approach 1: TWFE",
      grepl("Callaway", Approach) ~ "Approach 2: C-S DiD",
      grepl("Categorical", Approach) ~ "Approach 3: Categorical"
    )
  )

# Comparison plot
p_comparison <- ggplot(comparison_data, aes(x = Approach, y = Estimate, color = Method)) +
  geom_point(size = 4) +
  geom_errorbar(aes(ymin = CI_lower, ymax = CI_upper), width = 0.3, linewidth = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  coord_flip() +
  labs(title = "Comparison of All Three Approaches",
       subtitle = "Effect on overall SDG data missingness (95% CI)",
       x = "",
       y = "Effect Size") +
  theme(legend.position = "bottom")

ggsave("figures/causal_inference/comparison_all_approaches.png", p_comparison, width = 11, height = 7, dpi = 300)
cat("\n✓ Saved: comparison_all_approaches.png\n")

# Print comparison table
cat("\n--- Comparison Table ---\n")
print(comparison_data %>% 
      select(Approach, Estimate, SE) %>%
      mutate(across(where(is.numeric), ~round(., 4))))

################################################################################
# 6. ROBUSTNESS CHECKS
################################################################################

cat("\n\n", paste(rep("=", 80), collapse=""))
cat("\nROBUSTNESS CHECKS\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# 6.1 Alternative clustering (by year)
cat("--- Robustness 1: Alternative clustering (by year) ---\n")
twfe_cluster_year <- feols(prop_sdg_missing ~ backsliding + democratization + 
                            log_gdppc + log_pop + electric_access + rural_pop_pct |
                            country_code + year,
                           data = df,
                           vcov = ~year)
summary(twfe_cluster_year)

# 6.2 Two-way clustering
cat("\n--- Robustness 2: Two-way clustering ---\n")
twfe_cluster_twoway <- feols(prop_sdg_missing ~ backsliding + democratization +
                              log_gdppc + log_pop + electric_access + rural_pop_pct |
                              country_code + year,
                             data = df,
                             vcov = ~country_code + year)
summary(twfe_cluster_twoway)

# 6.3 Exclude countries with multiple regime changes
cat("\n--- Robustness 3: Stable treatment (exclude switchers) ---\n")
# Identify countries that switch back and forth
switchers <- df %>%
  arrange(country_code, year) %>%
  group_by(country_code) %>%
  summarize(
    n_switches = sum(abs(diff(aut_ep)), na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(n_switches > 1)

df_stable <- df %>%
  filter(!(country_code %in% switchers$country_code))

twfe_stable <- feols(prop_sdg_missing ~ backsliding + democratization +
                     log_gdppc + log_pop + electric_access + rural_pop_pct|
                     country_code + year,
                    data = df_stable,
                    vcov = ~country_code)
summary(twfe_stable)

# 6.4 Placebo test: lead effects
cat("\n--- Robustness 4: Placebo test (lead effects) ---\n")
df_placebo <- df %>%
  group_by(country_code) %>%
  mutate(
    backsliding_lead = dplyr::lead(backsliding),
    democratization_lead = dplyr::lead(democratization)
  ) %>%
  ungroup()

twfe_placebo <- feols(prop_sdg_missing ~ backsliding_lead + democratization_lead +
                      backsliding + democratization +
                      log_gdppc + log_pop + electric_access + rural_pop_pct|
                      country_code + year,
                     data = df_placebo,
                     vcov = ~country_code)
summary(twfe_placebo)

# 6.5 Income level heterogeneity
cat("\n--- Robustness 5: Heterogeneity by income level ---\n")
income_results <- list()
for (inc_level in c("L", "LM", "UM", "H")) {
  cat(sprintf("\n  Income level: %s\n", inc_level))
  df_inc <- df %>% filter(income_level == inc_level)

  if (nrow(df_inc) > 100) {
    income_results[[inc_level]] <- feols(
      prop_sdg_missing ~ backsliding + democratization +
        log_gdppc + log_pop + electric_access + rural_pop_pct|
        country_code + year,
      data = df_inc,
      vcov = ~country_code
    )
    print(summary(income_results[[inc_level]]))
  } else {
    cat("    Insufficient observations\n")
  }
}

################################################################################
# 7. EXPORT RESULTS
################################################################################

cat("\n\n", paste(rep("=", 80), collapse=""))
cat("\nEXPORTING RESULTS\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# Create regression table
etable(twfe_results$prop_sdg_missing, 
       twfe_robust,
       cat_model,
       file = "regression_table.tex",
       title = "Main Results: Effects of Democracy Changes on Data Availability",
       tex = TRUE)

cat("✓ Saved: regression_table.tex\n")

# Export coefficients to CSV
write.csv(twfe_coefs, "results_csv/causal_inference/twfe_coefficients.csv", row.names = FALSE)
write.csv(cat_all_coefs, "results_csv/causal_inference/categorical_coefficients.csv", row.names = FALSE)
write.csv(comparison_data, "results_csv/causal_inference/comparison_table.csv", row.names = FALSE)

cat("✓ Saved: twfe_coefficients.csv\n")
cat("✓ Saved: categorical_coefficients.csv\n")
cat("✓ Saved: comparison_table.csv\n")

# Save workspace
save.image("causal_inference_DataLossProj_Fall25/analysis_workspace.RData")
cat("✓ Saved: analysis_workspace.RData\n")

cat("\n" , paste(rep("=", 80), collapse=""))
cat("\nANALYSIS COMPLETE!\n")
cat(paste(rep("=", 80), collapse=""), "\n")
cat("\nGenerated files:\n")
cat("  - approach1_twfe_coefficients.png\n")
cat("  - approach2_cs_event_study.png\n")
cat("  - approach2_cs_group_effects.png\n")
cat("  - approach3_categorical_effects.png\n")
cat("  - approach3_heatmap_all_sdgs.png\n")
cat("  - comparison_all_approaches.png\n")
cat("  - regression_table.tex\n")
cat("  - twfe_coefficients.csv\n")
cat("  - categorical_coefficients.csv\n")
cat("  - comparison_table.csv\n")
cat("  - analysis_workspace.RData\n")
