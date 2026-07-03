# load libraries/packages
source("code/packages.R")

# load data [Cleaned SPI & SDG Datasets]
selected_df <- read_csv("data/output/merged_exclusive.csv") 

# used for sensitivity analysis (different datasets)
#selected_df <- read_csv(file.choose())

# REFERENCE FOR COVERAGE OF COUNTRIES IN DATASETS
COUNTRIES_BY_DF_REFERENCE <- read_csv("wrangling/adjust_outputs_diagnostics/all_countries_studied_comparison.csv")

# Main data transformation pipeline
panel_data <- selected_df %>% 
  arrange(country_code, year) %>%
  
  # Creating all transformations in a single grouped operation
  group_by(country_code) %>%
  arrange(year) %>%
  mutate(
    # Basic lag variables #
    # Lag & lead DI vars
    di_score_lag1 = dplyr::lag(di_score, n = 1),
    di_score_lag2 = dplyr::lag(di_score, n = 2),
    di_score_lag3 = dplyr::lag(di_score, n = 3),
    di_score_lead1 = dplyr::lead(di_score, n = 1),  # For potential future use
    di_score_lead2 = dplyr::lead(di_score, n = 2),  # For potential future use
    di_score_lead3 = dplyr::lead(di_score, n = 3),  # For potential future use
    # Lag & lead SPI vars
    spi_comp_lag1 = dplyr::lag(spi_comp, n = 1),
    spi_comp_lag2 = dplyr::lag(spi_comp, n = 2),
    spi_comp_lag3 = dplyr::lag(spi_comp, n = 3),
    spi_comp_lead1 = dplyr::lead(spi_comp, n = 1),  # For potential future use
    spi_comp_lead2 = dplyr::lead(spi_comp, n = 2),  # For potential future use
    spi_comp_lead3 = dplyr::lead(spi_comp, n = 3),  # For potential future use
    # Lag & lead log GDP vars
    log_gdppc_lag1 = dplyr::lag(log_gdppc, n = 1),
    log_gdppc_lag2 = dplyr::lag(log_gdppc, n = 2),
    log_gdppc_lead1 = dplyr::lead(log_gdppc, n = 1),  # For potential future use
    log_gdppc_lead2 = dplyr::lead(log_gdppc, n = 2),  # For potential future use
    
    # Centered variables (country-specific means)
    cen_spi_comp = spi_comp - mean(spi_comp, na.rm = TRUE),
    cen_di_score = di_score - mean(di_score, na.rm = TRUE),
    cen_log_gdppc = log_gdppc - mean(log_gdppc, na.rm = TRUE),
    
    # Lagged centered variables
    cen_spi_comp_lag1 = dplyr::lag(cen_spi_comp, n = 1),
    cen_spi_comp_lag2 = dplyr::lag(cen_spi_comp, n = 2),
    cen_di_score_lag1 = dplyr::lag(cen_di_score, n = 1),
    cen_di_score_lag2 = dplyr::lag(cen_di_score, n = 2),
    
    # Polynomial terms for lagged centered variables
    cen_spi_comp_lag1_sq = cen_spi_comp_lag1^2,
    cen_spi_comp_lag1_cub = cen_spi_comp_lag1^3,
    cen_spi_comp_lag2_sq = cen_spi_comp_lag2^2,
    cen_spi_comp_lag2_cub = cen_spi_comp_lag2^3,
    cen_di_score_lag1_sq = cen_di_score_lag1^2,
    cen_di_score_lag1_cub = cen_di_score_lag1^3,
    cen_di_score_lag2_sq = cen_di_score_lag2^2,
    cen_di_score_lag2_cub = cen_di_score_lag2^3,
    
    # Polynomial terms for current centered log GDP
    cen_log_gdppc_sq = cen_log_gdppc^2,
    cen_log_gdppc_cub = cen_log_gdppc^3
  ) %>%
  ungroup()

#===============================================================================
# Income level & regime type variables
#===============================================================================
panel_data <- panel_data %>% 
  mutate(
    # Income level recoding
    income_level_recoded = case_when(
      income_level == "L" ~ 0,   # Low-Income
      income_level == "LM" ~ 1,  # Lower-Middle-Income
      income_level == "UM" ~ 2,  # Upper-Middle-Income
      income_level == "H" ~ 3,   # High-Income
      TRUE ~ NA_integer_
    ),
    income_level_recoded = as.factor(income_level_recoded),
    
    # Regime Type (EUI): regime type classifications based on EIU Methodology
    di_reg_cat = case_when(
      #[DECIDE TO MAYBE CHANGE TO NUMBERS 0-3]
      di_score >= 8.0 ~ 3,                   # Full democracy
      di_score >= 6.0 & di_score < 8.0 ~ 2,  # Flawed democracy
      di_score >= 4.0 & di_score < 6.0 ~ 1,  # Hybrid regime
      di_score < 4.0 ~ 0,                    # Authoritarian
      TRUE ~ NA_integer_
    ),
    di_reg_cat = as.factor(di_reg_cat),
    # 'di_reg_cat' created here because it is used in panel analysis.
    # It's also needed to create regime change variables for future event-history analysis.
    
    # Regime type variables (ERT)
    regime_type_4 = as.factor(regime_type_4),
    ert_autocracy = as.factor(ifelse(regime_type_4 %in% c(0, 1), 1, 0)),
    ert_democracy = as.factor(ifelse(regime_type_4 %in% c(2, 3), 1, 0)),
    ert_aut_ep = as.factor(aut_ep),
    ert_dem_ep = as.factor(dem_ep),
    ert_regch_event = as.factor(regch_event),
    
  ) %>%
  
  # Country-level episode indicators (ERT)
  group_by(country_code) %>%
  mutate(
    ert_has_aut_ep = as.factor(ifelse(any(ert_aut_ep == 1, na.rm = TRUE), 1, 0)),
    ert_has_dem_ep = as.factor(ifelse(any(ert_dem_ep == 1, na.rm = TRUE), 1, 0)),
    ert_has_both = ifelse(any(ert_aut_ep == 1 & ert_dem_ep == 1, na.rm = TRUE), 1, 0),
    ert_has_neither = as.factor(ifelse(!any(ert_aut_ep == 1 | dem_ep == 1, na.rm = TRUE), 1, 0)),
    ert_total_aut_ep = sum(as.numeric(as.character(ert_aut_ep)), na.rm = TRUE),
    ert_total_dem_ep = sum(as.numeric(as.character(ert_dem_ep)), na.rm = TRUE),
    ert_democratized = as.factor(ifelse(any(regch_event == 1, na.rm = TRUE), 1, 0)),
    ert_autocratized = as.factor(ifelse(any(regch_event == -1, na.rm = TRUE), 1, 0)),
    ert_stable = as.factor(ifelse(!any(regch_event == 1 | regch_event == -1, na.rm = TRUE), 1, 0))
  ) %>% 
  ungroup()

# Panel Analysis Dataset 
# re-arranging columns to have key variables first for easier viewing
panel_data <- panel_data %>%
  filter(year >= 2016) %>%
  select(country_name, country_code, year, sdg_overall, spi_comp, di_score,
         di_reg_cat, log_gdppc, income_level_recoded, p1_use:p5_infra, 
         goal1:goal17, everything())

# Optional: Save to CSV (uncommented when needed)
# write_csv(panel_data, "data/Main CSV Outputs/panel_data.csv")

# remove selected_df to free up memory
rm(selected_df)