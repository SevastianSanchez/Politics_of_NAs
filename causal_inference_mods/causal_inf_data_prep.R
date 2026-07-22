# ============================================================================
# DATA PREP SCRIPT — Politics of NAs Project
# Consolidates all data loading, merging, cleaning, and variable creation
# steps required by the following Rmd files:
#   - overall_twfe_analysis.Rmd
#   - goal_level_twfe_analysis.Rmd
#   - event_study_stag_twfe.Rmd
#   - cs_did_analysis_v2.Rmd
#
# Each Rmd should replace its own data-loading/prep chunks with:
#   source("data_prep.R")
# ============================================================================

library(tidyverse)
library(devtools)
library(fixest)      # for TWFE
library(did)          # for Callaway-Sant'Anna DiD
library(car)
library(readr)
library(janitor)
library(vdemdata) # call vdem package 
library(WDI) # call WDI package for Vars
library(flextable)
library(modelsummary)
library(gt)
library(purrr)
library(broom)

# ============================================================================
# SECTION 1: overall_twfe_analysis.Rmd — Loading & Merging Data
# ============================================================================

# Load data (adjust path if needed)
# df <- read_csv("sdg_democracy_paneldata.csv")
df <- readRDS("data/output/sdg_democracy_paneldata.rds")

# Quickly Adding merge of SPI data
url <-
  "https://raw.githubusercontent.com/worldbank/SPI/refs/heads/master/03_output_data/SPI_index.csv"
spi <- read_csv(url) %>%
  dplyr::select(country, date, SPI.INDEX, iso3c) %>%
  rename(country_name = country, country_code = iso3c, year = date, spi_overall = SPI.INDEX)

# merging spi into main panel dataset
panel <- df %>% left_join(spi, by = c("country_code", "year"))

# Quickly Adding Luminosity Data (for potential future use)
luminosity <- read_csv("data/input/csvs_other_indicators/nightlight_1992_2023_complete.csv") %>%
  filter(year >= 2015) %>%
  rename(country_code = iso, luminosity = nlsum)

# merging luminosity into main panel dataset
panel <- panel %>% left_join(luminosity, by = c("country_code", "year"))
      #**Source for Luminosity data**: Beyer, R.C., Hu, Y. and Yao, J., 2026. The Bright Side of Heteroskedasticity: Measuring Quarterly Economic Growth from Outer Space.
      #(link)[https://sites.google.com/site/jiaxiongyao16/nighttime-lights-data?authuser=0] 

# Quickly adding ACLED political violence counts (country-year) as conflict control
violence_counts <- readxl::read_excel("data/input/political_violence_counts.xlsx",
  col_names = c("country_name_acled", "year", "acled_events"),
  skip = 1)

violence_counts <- violence_counts %>%
  rename(country_name = country_name_acled, poly_vio_events = acled_events) %>%
  mutate(
    country_name.x = as.character(country_name),
    year = as.integer(year),
    any_political_violence = if_else(!is.na(poly_vio_events) & poly_vio_events > 0, 1L, 0L))
  
panel <- panel %>% left_join(violence_counts, by = c("country_name.x", "year"))

# Quickly Adding episode id for autocratization and democratization
ert <- read.csv("data/input/ert.csv") %>%
  filter(year >= 2000) %>%
  dplyr::select(country_text_id, year, dem_ep_id, aut_ep_id) %>%
  rename(country_code = country_text_id)

# merging episode id into main panel dataset
panel <- panel %>% left_join(ert, by = c("country_code", "year"))

# Quickly Adding V-Dem Liberal Democracy Index (v2x_liberal) [vdemdata]
vdem_for_v2x_liberal <- vdemdata::vdem %>%
  filter(year >= 2000) %>%
  dplyr::select(country_text_id, year, v2x_liberal) %>% 
  rename(country_code = country_text_id)

# merging vdem liberal democracy index into main panel dataset
panel <- panel %>% left_join(vdem_for_v2x_liberal, by = c("country_code", "year"))

# Quickly Adding tax revenue data (for potential future use) [WDI]
tax_rev_gdp <- WDI(country = "all", indicator = "GC.TAX.TOTL.GD.ZS", start = 2000, end = NULL)

# merging tax revenue data into main panel dataset
panel <- panel %>% left_join(tax_rev_gdp %>%
  rename(country_code = iso3c, tax_rev_gdp = GC.TAX.TOTL.GD.ZS),
  by = c("country_code", "year"))

# ----------------------------------------------------------------------------
# SECTION 1a: overall_twfe_analysis.Rmd — Data Cleaning and Variable Setup
# ----------------------------------------------------------------------------

# Basic cleaning / type setting -----------------------------------------------
panel <- panel %>%
  filter(year >= 2015) %>%
  mutate(
    # Treatment cohort: first year of autocratization (0 if never treated)
    aut_cohort = if_else(aut_ep == 1, aut_ep_start_yr, 0L),
    log_luminosity = log(luminosity + 1),
    # Numeric ID required by did::att_gt()
    country_id = as.numeric(as.factor(country_code)))

panel <- panel %>% mutate(across(
  c(country_code, year, regime_type_2, regime_type_4, regime_type_10,
    aut_ep, dem_ep, regch_event, regch_genuine, aut_cohort), as.factor))

panel$regime_type_4 <- factor(panel$regime_type_4, levels = c("0", "1", "2", "3"))
panel$income_level <- factor(panel$income_level, levels = c("L", "LM", "UM", "H"))

# **total_pop** has the most missing values, specifically across all countries 
# in 2023, which is likely due to the fact that the World Bank's population data 
# for 2023 may not have been fully updated or released at the time of data collection. 

# Strategy: Population data for 2023 was unavailable from the World Bank at the 
# time of data collection; 2022 values were carried forward for this variable. 
# Given the low year-over-year volatility of (log) population, this is unlikely 
# to meaningfully affect estimates. 

# Given the largely skewed distribution of population, the log of population is 
# used in all models. We also use the log of luminosity and log of GDP per capita 
# (variable applied as necessary) to reduce skewness in these variables.

# ----------------------------------------------------------------------------
# SECTION 1b: overall_twfe_analysis.Rmd — Addressing NA values in key covariates
# ----------------------------------------------------------------------------

# IMPUTE missing values for log_pop with previous year values (carry forward)
panel <- panel %>% group_by(country_code) %>%
  mutate(log_pop = if_else(year == 2023 & is.na(log_pop), 
                           log_pop[year == 2022], log_pop)) %>% 
  ungroup()

# NOTES ABOUT VARIABLES:
# - Took out R&D expenditure because it has a lot of NAs and is highly correlated with GDP per capita.
# - SPI is missing all of 2015, but is kept in the dataset for now because it is a key control variable.
#   Models are run with and without it to check robustness.

# Save as rds
write_rds(panel, "data/output/MAIN_panel_data.rds") 
# save as csv for AI
write_csv(panel, "data/output/MAIN_panel_data.csv")

# ============================================================================
# SECTION 3: event_study_stag_twfe.Rmd — Setup & Event-Time Variable Creation
# ============================================================================

# load data
panel <- readRDS("data/output/MAIN_panel_data.rds")

# # convert year to integer for event time calculations
# panel <- panel %>%
# mutate(year = as.integer(year))

# table(panel$year)
# n_distinct(panel$year)

# ----------------------------------------------------------------------------
# SECTION 3a: event_study_stag_twfe.Rmd — APPROACH 1C: Event Time Variables
# ----------------------------------------------------------------------------

# Step 1. Create event_time variable for all treated countries (NA for never-treated)
panel_es <- panel %>%
  mutate(year = as.numeric(as.character(year))) %>%
  group_by(country_code) %>%
  mutate(
    # Fill the episode start year for ALL rows of treated countries
    aut_start_filled = min(aut_ep_start_yr[aut_ep == 1], na.rm = TRUE),
    aut_start_filled = ifelse(is.infinite(aut_start_filled), NA_real_, aut_start_filled),

    # Event time for all years of treated countries, NA for never-treated
    event_time = year - aut_start_filled) %>%
  ungroup()

# Step 2. Capped event_time indicators
panel_es <- panel_es %>%
  mutate(
    treated = ifelse(!is.na(event_time), 1, 0),
    event_time_cap = case_when(
      treated == 1 & event_time < -4 ~ -4,
      treated == 1 & event_time > 5 ~ 5,
      treated == 1 ~ event_time,
      TRUE ~ 0)) # never-treated

# ----------------------------------------------------------------------------
# SECTION 3b: event_study_stag_twfe.Rmd — Save panel_es as csv (for CS DiD script)
# ----------------------------------------------------------------------------

# saving panel_es as csv
write_csv(panel_es, "data/output/panel_es_data.csv")

# ============================================================================
# SECTION 4: cs_did_analysis_v2.Rmd — Build CS Panel
# ============================================================================
# NOTE: cs_did_analysis_v2.Rmd reads panel_es_data.csv (produced in Section 3b)
# rather than the .rds panel directly, then applies its own additional
# cohort/censoring/SPI-moderator variable construction below.

panel <- read_csv("data/output/panel_es_data.csv")

# ----------------------------------------------------------------------------
# SECTION 4a: cs_did_analysis_v2.Rmd — Left-Censoring Flag & CS Panel Build
# ----------------------------------------------------------------------------
# Key decisions encoded here:
# - Left-censored countries (autocratization episode starts before 2015) are
#   excluded because we cannot observe their pre-treatment trajectory in this panel.
# - gname = first autocratization start year (aut_cohort), or 0 for never-treated.
#   This is held constant across all rows for each country (CS requirement).
# - Cohort restriction: only cohorts 2016-2020 are retained as treated units,
#   plus all never-treated (gname == 0). Cohorts 2015 (treated at panel start, no
#   pre-period), and 2021-2023 (too few treated units and almost no post-period)
#   are excluded as they cannot be identified in the CS framework.
# - idname = country_id (numeric).
# - tname = year (integer).

# Step 1: Flag left-censored countries
panel <- panel %>%
  mutate(
    left_censored = (!is.na(aut_start_filled) & aut_start_filled < 2015))

cat("Left-censored countries (episode starts before 2015):",
    n_distinct(panel$country_code[panel$left_censored]), "\n")

# Step 2: Build CS panel
panel_cs <- panel %>%
  filter(!left_censored) %>%
  mutate(year = as.integer(year)) %>%
  rename(idname = country_id,
         tname = year)

# Step 3: Assign constant gname per country (first episode start year; 0 = never-treated)
g_by_country <- panel_cs %>%
  group_by(idname) %>%
  summarise(
    gname = ifelse(
      any(aut_cohort > 0, na.rm = TRUE),
      min(aut_cohort[aut_cohort > 0], na.rm = TRUE),
      0L
    ),
    .groups = "drop")

panel_cs <- panel_cs %>%
  select(-any_of("gname")) %>%
  left_join(g_by_country, by = "idname")

# Step 4: Restrict to identifiable cohorts only
panel_cs <- panel_cs %>%
  filter(
    gname == 0 | gname %in% 2016:2020)

# ----------------------------------------------------------------------------
# SECTION 4b: cs_did_analysis_v2.Rmd — Cohort Consistency Check
# ----------------------------------------------------------------------------

# Verify gname is constant per country
n_multi_g <- panel_cs %>%
  distinct(idname, gname) %>%
  count(idname) %>%
  filter(n > 1) %>%
  nrow()

cat("Countries with inconsistent gname (should be 0):", n_multi_g, "\n")

# Cohort distribution
panel_cs %>%
  distinct(idname, gname) %>%
  count(gname, name = "n_countries") %>%
  arrange(gname) %>%
  print()

# ----------------------------------------------------------------------------
# SECTION 4c: cs_did_analysis_v2.Rmd — SPI Moderator Variable
# ----------------------------------------------------------------------------

# Compute baseline SPI per country (first non-missing observation)
spi_baseline <- panel_cs %>%
  arrange(idname, tname) %>%
  group_by(idname) %>%
  summarise(spi_base = first(na.omit(spi_overall)), .groups = "drop")

# Median-split into High/Low SPI
spi_median <- median(spi_baseline$spi_base, na.rm = TRUE)

panel_cs <- panel_cs %>%
  left_join(spi_baseline, by = "idname") %>%
  mutate(
    spi_hilow = case_when(
      spi_base >= spi_median ~ "High SPI",
      spi_base < spi_median ~ "Low SPI",
      TRUE ~ NA_character_
    ))

cat("SPI median (baseline):", round(spi_median, 2), "\n")

# ----------------------------------------------------------------------------
# SECTION 4d: cs_did_analysis_v2.Rmd — Outcome Variables
# ----------------------------------------------------------------------------

# Overall outcome
outcome_overall <- "prop_sdg_missing"

# Goal-level outcomes
sdg_goals <- paste0("prop_miss_SDG", 1:17)

# ============================================================================
# END OF DATA PREP
# ============================================================================
# At this point, the following objects are available for use in each Rmd:
#   - panel            : cleaned MAIN panel (from Section 1/2), factor-typed
#   - panel_es         : panel with event_time / treated / event_time_cap vars
#   - panel_cs         : CS-ready panel (idname, tname, gname, spi_hilow, etc.)
#   - outcome_overall  : "prop_sdg_missing"
#   - sdg_goals        : vector of 17 goal-level outcome variable names
#
# Each Rmd should now begin with:
#   source("data_prep.R")
# and skip directly to its model-building chunks.
# ============================================================================

