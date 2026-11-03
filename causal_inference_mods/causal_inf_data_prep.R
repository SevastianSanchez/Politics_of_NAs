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

# Load the predictor panel, built by code/data_prep/build_predictor_panel.R.
# That script reads V-Dem and WDI from dated snapshots in data/input/snapshots/
# rather than pulling live, so this chain is reproducible. Rerun it (with
# refresh_sources <- TRUE) to take new source vintages.
#
# It replaced sdg_democracy_paneldata.rds, which had no builder. The SDR-derived
# columns here now carry an _sdr suffix: they are the SUPERSEDED outcome, kept
# only for comparison against the UN Global Database measure in data/clean/.
df <- readRDS("data/output/predictor_panel.rds")

# ---- SPI: statistical capacity ----------------------------------------------
# spi_overall     World Bank published composite, UNTOUCHED (mean of all 5
#                 pillars; verified equal to rowMeans(PIL1:PIL5) exactly, i.e.
#                 20% each). Keeps its original meaning for traceability.
# spi_overall_mod Modified copy: pillar 3 dropped, remaining four at 25% each,
#                 per Landau, Jütting & MacFeely (2025), PARIS21 DP 18, p.17.
#                 USE THIS IN MODELS. Pillar 3 (Data Products) scores SDG
#                 reporting drawn from the UN Global SDG database — this
#                 study's own outcome — so controlling for the published
#                 composite partly controls for the dependent variable.
#                 We depart from Landau et al. only on vintage: they use the
#                 2020 snapshot for a cross-sectional design; a panel with
#                 country FE needs the annual series or the control is absorbed.
# Pillars kept for robustness. na.rm = FALSE throughout, matching the World
# Bank: a country-year scores only when every contributing pillar is present.
url <- "https://raw.githubusercontent.com/worldbank/SPI/refs/heads/master/03_output_data/SPI_index.csv"
spi <- read_csv(url) %>%
  # SPI's own `country` column is dropped: predictor_panel already carries the
  # authoritative country_name, and keeping this one collided into
  # country_name.x / .y. Join on country_code + year only.
  dplyr::select(date, iso3c, SPI.INDEX,
                SPI.INDEX.PIL1, SPI.INDEX.PIL2, SPI.INDEX.PIL3,
                SPI.INDEX.PIL4, SPI.INDEX.PIL5) %>%
  rename(country_code = iso3c, year = date,
         spi_overall = SPI.INDEX,                       # original, as published
         spi_p1_use = SPI.INDEX.PIL1, spi_p2_services = SPI.INDEX.PIL2,
         spi_p3_products = SPI.INDEX.PIL3, spi_p4_sources = SPI.INDEX.PIL4,
         spi_p5_infra = SPI.INDEX.PIL5) %>%
  mutate(spi_overall_mod = rowMeans(                    # modified copy
    cbind(spi_p1_use, spi_p2_services, spi_p4_sources, spi_p5_infra),
    na.rm = FALSE))

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

# ACLED ships country names only, no ISO3, so it is matched to ISO3 here and
# joined on the code — the same key every other source uses. The old version
# joined on `country_name.x`, a leftover join suffix, which then produced
# country_name.x / .y in the output and forced downstream scripts to reference
# the artifact instead of a real column name.
violence_counts <- violence_counts %>%
  transmute(
    country_code = countrycode::countrycode(as.character(country_name_acled),
                                            origin = "country.name",
                                            destination = "iso3c",
                                            warn = FALSE),
    year = as.integer(year),
    poly_vio_events = acled_events,
    any_political_violence = if_else(!is.na(acled_events) & acled_events > 0, 1L, 0L)) %>%
  filter(!is.na(country_code)) %>%
  distinct(country_code, year, .keep_all = TRUE)

panel <- panel %>% left_join(violence_counts, by = c("country_code", "year"))

# Three joins used to sit here and have been removed, because predictor_panel
# now supplies all of them:
#   dem_ep_id / aut_ep_id  — re-read from ert.csv; collided into .x/.y suffixes
#   v2x_liberal            — pulled live from vdemdata
#   tax_rev_gdp            — pulled live from WDI
# Beyond the collisions, the two live pulls reintroduced unsnapshotted sources
# that change between runs, which is what build_predictor_panel.R exists to stop.

# ----------------------------------------------------------------------------
# SECTION 1a: overall_twfe_analysis.Rmd — Data Cleaning and Variable Setup
# ----------------------------------------------------------------------------

# Basic cleaning / type setting -----------------------------------------------
panel <- panel %>%
  filter(year >= 2015) %>%
  mutate(
    # Treatment cohort: first year of autocratization (0 if never treated)
    aut_cohort = if_else(aut_ep == 1, aut_ep_start_yr, 0L),
    #left_censored_aut_ep = (!is.na(aut_start_filled) & aut_start_filled < 2015),
    country_id = as.numeric(as.factor(country_code)), # Numeric ID required by did::att_gt()
    log_luminosity = log(luminosity + 1),
    prop_missing_pct = prop_sdg_missing_sdr * 100)

panel <- panel %>% mutate(across(
  c(country_code, year, regime_type_2, regime_type_4, regime_type_10, aut_ep, 
    dem_ep, regch_event, regch_genuine, aut_cohort), as.factor))
panel$regime_type_4 <- factor(panel$regime_type_4, 
                              levels = c("0", "1", "2", "3"))
panel$income_level <- factor(panel$income_level, 
                             levels = c("L", "LM", "UM", "H"))

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
panel <- panel %>% 
  group_by(country_code) %>%
  mutate(log_pop = if_else(year == 2023 & is.na(log_pop), log_pop[year == 2022], log_pop)) %>% 
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
panel_es <- panel_es %>%
  mutate(
    left_censored = (!is.na(aut_start_filled) & aut_start_filled < 2015))

cat("Left-censored countries (episode starts before 2015):",
    n_distinct(panel_es$country_code[panel_es$left_censored]), "\n")

# Step 2: Build CS panel
panel_cs <- panel_es %>%
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
outcome_overall <- "prop_sdg_missing_sdr"

# Goal-level outcomes
sdg_goals <- paste0("prop_miss_SDG", 1:17, "_sdr")

# ============================================================================
# END OF DATA PREP
# ============================================================================
# At this point, the following objects are available for use in each Rmd:
#   - panel            : cleaned MAIN panel (from Section 1/2), factor-typed
#   - panel_es         : panel with event_time / treated / event_time_cap vars
#   - panel_cs         : CS-ready panel (idname, tname, gname, spi_hilow, etc.)
#   - outcome_overall  : "prop_sdg_missing_sdr" (SUPERSEDED measure)
#   - sdg_goals        : vector of 17 goal-level outcome variable names
#
# Each Rmd should now begin with:
#   source("data_prep.R")
# and skip directly to its model-building chunks.
# ============================================================================

