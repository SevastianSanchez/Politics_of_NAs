# =============================================================================
# Politics of NAs — UN SDG Global Database export prep
# =============================================================================
#
# Purpose
# -------
# Reads the 17 goal-level Excel exports of the UN SDG Global Database, filters
# to 2015-2025, keeps only fields needed for an auditable series-availability
# analysis, and writes a family of downstream panels for descriptive and
# causal work on how democratic backsliding affects data reporting.
#
# Input files (place all 17 in data/raw/un_sdg_goal_exports/):
#   Goal1.xlsx, Goal2.xlsx, ..., Goal17.xlsx
#
# Outputs (all written to data/clean/; file basename == R object name):
#
#   Raw + reference
#   ---------------
#   raw_data.csv.gz
#       One row per published observation (country x series x year x
#       disaggregation). Source of truth — every panel below derives from it.
#       Carries `nature` as a column, so any provenance subset (state-reported
#       only, modelled only, etc.) is a filter on this table before counting.
#   series_list.csv
#       Goal-target-indicator-series crosswalk from the downloaded files.
#
#   PRIMARY outcome panel (observation counts within goals)
#   -------------------------------------------------------
#   goal_lvl_dv_data.csv
#       One row per country x year x goal, carrying three outcome columns
#       side by side —
#         n_observations                — raw observation count
#         n_observations_pct_baseline   — normalized to country-goal baseline
#                                          mean (default: 2015-2017)
#         n_observations_pct_frontier   — normalized to the max any country
#                                          reported for that goal-year
#       so the analysis can switch measures without switching datasets.
#
#   ROBUSTNESS-ONLY panels (series-code counts, not observation counts)
#   ------------------------------------------------------------------
#   agg_series_counts_rc.csv
#       Availability/missingness measured by counting SERIES CODES present,
#       not observations — so a series code counts once regardless of how many
#       disaggregated observations sit under it. Both scopes in one table:
#         scope == "goal"    — one row per country x year x goal (goal filled)
#         scope == "overall" — one row per country x year      (goal is NA)
#       Robustness check only; the primary outcome is goal_lvl_dv_data.
#   agg_series_depth.csv.gz
#       One row per country x series-code x year, with nature_codes and
#       n_disagg_rows — how deep the disaggregation goes under each series
#       code. Supplementary view for the reporting-detail angle.
#
# --------------------------
# Excel files are a fixed, archivable snapshot of the UN Global Database.
# Download date: August 16, 2026
# Database release date: July 7, 2026 (last update)


# =============================================================================
# A. SETUP =====================================================================
# =============================================================================

# ---- A1. Packages ------------------------------------------------------------
required_packages <- c("readxl", "dplyr", "purrr", "readr", "tidyr", "stringr", "janitor")
missing_packages <- required_packages[!required_packages %in% rownames(installed.packages())]
if (length(missing_packages) > 0) install.packages(missing_packages)

library(readxl)
library(dplyr)
library(purrr)
library(readr)
library(tidyr)
library(stringr)
library(janitor)


# ---- A2. Configuration -------------------------------------------------------
# Year window covered by this pull.
start_year <- 2015L
end_year   <- 2025L

# Baseline reference window for n_observations_pct_baseline in Section E1.
# Default: the earliest three years of the SDG framework, before most ERT
# autocratization episodes begin. To use a single-year baseline (e.g., 2017)
# change to `baseline_years <- 2017L` — nothing else needs to move.
baseline_years <- 2015:2017

# Filesystem locations.
input_folder  <- "data/raw/un_sdg_goal_exports"
output_folder <- "data/clean"
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)

# Only retain fields needed for an auditable series-availability analysis.
keep_columns <- c(
  "Goal", "Target", "Indicator",
  "SeriesCode", "SeriesDescription",
  "GeoAreaCode", "GeoAreaName",
  "TimePeriod", "Value",
  "Source", "FootNote",
  "Age", "Freq", "Location", "Nature", "Sex", "Units",
  "Reporting Type", "Observation Status"
)

# GeoAreaName values that are aggregates, not country/territory reporting units.
# GeoAreaCode is the safer merge key; this list is a belt-and-braces filter.
aggregate_geographies <- c(
  "World", "Africa", "Asia", "Europe", "Oceania",
  "Northern Africa and Western Asia", "Central Asia and Southern Asia",
  "Eastern Asia and South-eastern Asia", "Latin America and the Caribbean",
  "Sub-Saharan Africa", "Europe and Northern America"
)


# =============================================================================
# B. INPUT DISCOVERY ===========================================================
# =============================================================================

# ---- B1. Locate and validate the 17 Excel exports ---------------------------

# ensures directory exists
if (!dir.exists(input_folder)) {
  stop("Input folder not found: ", input_folder,
       "\nCreate it and place Goal1.xlsx through Goal17.xlsx inside it.")
}

# creates character vector of excel file names to identofy
excel_files <- list.files(
  input_folder,
  pattern = "^Goal(0?[1-9]|1[0-7])\\.xlsx$",
  full.names = TRUE,
  ignore.case = TRUE)

# ensures all files are present
if (length(excel_files) == 0) {
  stop("No files matching Goal1.xlsx ... Goal17.xlsx were found in ", input_folder)
}

# Extract the goal number from the filename and order files numerically so the
# reading log prints Goal1 ... Goal17 in numeric order, not lexicographic.
file_manifest <- tibble(file_path = excel_files) %>%
  mutate(file_name = basename(file_path),
         goal_from_file = as.integer(str_extract(file_name, "(?<=Goal)0?[0-9]+"))
  ) %>%
  arrange(goal_from_file)

message("Found ", nrow(file_manifest), " goal export files:")
print(file_manifest %>% select(file_name, goal_from_file))

if (nrow(file_manifest) != 17) {
  warning("Expected 17 files but found ", nrow(file_manifest),
          ". The script will run, but confirm no goal export is missing.")
}


# =============================================================================
# C. RAW OBSERVATION INGESTION =================================================
# =============================================================================

# ---- C1. Single-file reader --------------------------------------------------
read_one_goal_file <- function(file_path) {
  message("Reading: ", basename(file_path))

  # Read column names first so the script fails loudly if an export's schema
  # has drifted, instead of silently dropping variables.
  file_columns    <- names(read_excel(file_path, n_max = 0))
  missing_columns <- setdiff(keep_columns, file_columns)

  if (length(missing_columns) > 0) {
    warning(basename(file_path), " is missing: ",
            paste(missing_columns, collapse = ", "),
            "\nThose fields will be created as NA.")
  }

  # Type each kept column as "text" and skip the rest, so the ~53 unneeded
  # columns are never parsed. Everything comes in as string; TimePeriod is
  # coerced to integer below.
  columns_to_read  <- intersect(keep_columns, file_columns)
  col_types_vector <- ifelse(file_columns %in% columns_to_read, "text", "skip")
  goal_data        <- readxl::read_excel(file_path, col_types = col_types_vector)

  # Backfill absent requested columns as NA, then enforce a consistent order.
  for (column_name in setdiff(keep_columns, names(goal_data))) {
    goal_data[[column_name]] <- NA
  }

  goal_data <- goal_data %>%
    select(all_of(keep_columns)) %>%
    mutate(
      TimePeriod = suppressWarnings(as.integer(TimePeriod)),
      Goal       = suppressWarnings(as.integer(Goal))
    ) %>%
    filter(
      TimePeriod >= start_year,
      TimePeriod <= end_year,
      !is.na(Value),
      Value != "",
      !is.na(GeoAreaCode),
      str_detect(GeoAreaCode, "^[0-9]+$"),
      !GeoAreaName %in% aggregate_geographies
    )

  # Sanity check: warn if two rows share every kept column. In well-formed
  # UN exports this is zero (any apparent duplicates come from dropped
  # specialty dimensions like Disability status, Cause of death, Type of
  # product, etc., which is exactly why C2 does NOT call distinct()).
  n_dup <- sum(duplicated(goal_data))
  if (n_dup > 0) {
    warning(basename(file_path), " contains ", n_dup,
            " row(s) that duplicate on the kept columns after filtering — ",
            "these are legitimate observations distinguished by dropped ",
            "specialty disaggregation columns; inspect before trusting.")
  }

  goal_data
}


# ---- C2. Read and combine → raw_data ----------------------------------------
# The raw observation frame: one row per published country x series x year x
# disaggregation. This is the source of truth — every panel below is derived
# from it, and any subset (by nature, by year, by geography) is a filter on
# this table applied before counting.
#
# NOTE: no distinct() here. The raw UN exports have no true duplicates at the
# full-dimension level, and calling distinct() on the ~19 kept columns would
# collapse observations that differ only in dropped specialty dimensions
# (Disability status, Cause of death, Type of product, etc.), silently
# undercounting sector-mass observations by ~5-10% on high-disaggregation
# goals (SDG-3, 4, 5, 12). C1 warns if a file has actual kept-column
# duplicates.
raw_data <- map_dfr(file_manifest$file_path, read_one_goal_file) %>%
  clean_names() %>%
  rename(year = time_period) %>%
  arrange(goal, geo_area_name, series_code, year)

write_csv(
  raw_data,
  file.path(output_folder, "raw_data.csv.gz")
)


# ---- C3. Merge post-2017 series-update classification -----------------------
# Source: data/raw/sdg_update_info.xlsx, sheet "Data Updates".
# Classifies only structural updates relevant to the series universe: added,
# revised/refined, and replacement. Ordinary "Data updated" records remain
# unchanged_or_routine.
updates_crosswalk <- read_excel("data/raw/sdg_update_info.xlsx",
  sheet = "Data Updates") %>%
  clean_names() %>%
  mutate(
    date         = as.Date(date),
    series_code  = as.character(series_code),
    action_notes = as.character(action_notes),
    series_update_type_post17

    # MODIFICATIONS NEEDED TO MATCHING RULES ==================================
    = case_when(
      str_detect(str_to_lower(action_notes), "replac|consolidat|restructur") ~ "replacement",
      str_detect(str_to_lower(action_notes), "data series added|data added to the database|data series was added") ~ "added",
      str_detect(str_to_lower(action_notes),
        "series label updated|unit updated|unit was changed|base year was updated|\
         indicator was revised|indicator was refined|indicator description was updated|\
         data modelling was updated|methodology") ~ "revised_refined",
      TRUE ~ "unchanged_or_routine")
    # =========================================================================

  # NOT SURE I NEED THIS
  # ) %>%
  # filter(
  #   !is.na(series_code),
  #   series_code != "",
  #   date > as.Date("2017-12-31"),
  #   series_update_type_post17 != "unchanged_or_routine"
  ) %>%
  mutate(
    series_update_type_post17 = factor(
      series_update_type_post17,
      levels = c("unchanged_or_routine", "added", "revised_refined", "replacement"))
  ) %>%
  arrange(series_code, desc(series_update_type_post17), desc(date)) %>%
  distinct(series_code, .keep_all = TRUE) %>%
  transmute(
    series_code,
    series_update_type_post17 = as.character(series_update_type_post17),
    action_notes,
    update_date = date)

# Attach the classification to the raw observations. Series missing from the
# crosswalk (never updated post-2017) fall through to unchanged_or_routine.
raw_data <- raw_data %>%
  left_join(updates_crosswalk, by = "series_code") %>%
  mutate(series_update_type_post17 = coalesce(
    series_update_type_post17, "unchanged_or_routine"))


# =============================================================================
# D. DERIVED REFERENCE TABLES ==================================================
# =============================================================================
# All of the following are computed once from raw_data and reused by the
# outcome panels in Sections E and F.

# ---- D1. Country lookup → countries -----------------------------------------
countries <- raw_data %>%
  distinct(geo_area_code, geo_area_name)


# ---- D2. Series list (goal-target-indicator-series crosswalk) ---------------
# A series may occur under more than one goal in the official framework. Since
# these are goal-specific exports, preserve each unique goal-series link.
series_list <- raw_data %>%
  distinct(goal, target, indicator, series_code, series_description) %>%
  arrange(goal, target, indicator, series_code)

write_csv(
  series_list,
  file.path(output_folder, "series_list.csv")
)


# ---- D3. All-goals vector → goals -------------------------------------------
# Precomputed once and reused by every downstream expand_grid.
goals <- sort(unique(series_list$goal))


# ---- D4. Series-per-goal denominator → agg_series_per_goal ------------------
# Distinct series codes per goal in the downloaded export. Denominator for the
# series-count availability shares in Section F2.
agg_series_per_goal <- series_list %>%
  distinct(goal, series_code) %>%
  count(goal, name = "n_series_in_goal")


# ---- D5. Framework-wide series total → agg_series_total ---------------------
# Unique series codes across all goal exports (a series in two goals counted
# once). Denominator for the framework-wide availability share in Section F3.
agg_series_total <- n_distinct(series_list$series_code)


# ---- D6. Country-goal baseline mean → baseline ------------------------------
# Mean raw observation count per country-goal across baseline_years. Missing
# country-goal-years in the baseline window are treated as real zeros (not
# unobserved), so a country that reported nothing in a baseline year does not
# inflate its own baseline by being averaged over observed years only.
baseline <- expand_grid(
    countries,
    year = baseline_years,
    goal = goals
  ) %>%
  left_join(
    raw_data %>%
      count(geo_area_code, year, goal, name = "n_observations"),
    by = c("geo_area_code", "year", "goal")
  ) %>%
  mutate(n_observations = coalesce(n_observations, 0L)) %>%
  group_by(geo_area_code, goal) %>%
  summarise(baseline_mean = mean(n_observations), .groups = "drop")


# ---- D7. Goal-year frontier max → frontier ----------------------------------
# Max country-goal-year observation count within each goal-year. Descriptive-
# companion denominator ("share of the top reporter") for
# n_observations_pct_frontier.
frontier <- raw_data %>%
  count(geo_area_code, year, goal, name = "n_observations") %>%
  group_by(year, goal) %>%
  summarise(frontier_max = max(n_observations), .groups = "drop")


# =============================================================================
# E. PRIMARY OUTCOME PANEL (sector-level, raw observation counts) =============
# =============================================================================
# Each raw observation is one data point. A country reporting national + urban
# + rural rows contributes 3 units of that goal's data mass, not 1.
# Series-level views live in Section F as robustness.
#
# There is deliberately no pre-aggregated by-nature panel here. `nature` is a
# column on raw_data, so a provenance-restricted outcome is built by filtering
# raw_data first and then counting, e.g.:
#
#   raw_data %>%
#     filter(nature %in% c("C", "CA")) %>%
#     count(geo_area_code, geo_area_name, year, goal, name = "n_observations")

# ---- E1. Goal-level DV panel: goal_lvl_dv_data ------------------------------
# Grain: country x year x goal, one row each. Built on a full scaffold so
# country-goal-years with zero reported observations appear as genuine 0
# rather than as missing rows.
#
# Three outcome columns are written side by side so the analysis code can
# switch between them without switching datasets:
#
#   n_observations                — raw count of observations.
#                                    Preferred outcome for within-country DiD /
#                                    event study; country + goal fixed effects
#                                    absorb the level, leaving change to be
#                                    explained.
#   n_observations_pct_baseline   — n_observations / country-goal baseline mean.
#                                    Cross-goal comparable (SDG-3 vs SDG-16 on
#                                    the same 0-to-1-ish scale).
#                                    NA where baseline_mean is 0.
#   n_observations_pct_frontier   — n_observations / max any country reported
#                                    for that goal-year. Descriptive companion
#                                    only — denominator moves year to year, so
#                                    weaker for causal identification.
goal_lvl_dv_data <- expand_grid(
    countries,
    year = start_year:end_year,
    goal = goals
  ) %>%
  left_join(
    raw_data %>%
      count(geo_area_code, geo_area_name, year, goal, name = "n_observations"),
    by = c("geo_area_code", "geo_area_name", "year", "goal")
  ) %>%
  mutate(n_observations = coalesce(n_observations, 0L)) %>%
  left_join(baseline, by = c("geo_area_code", "goal")) %>%
  left_join(frontier, by = c("year", "goal")) %>%
  mutate(
    n_observations_pct_baseline = if_else(baseline_mean > 0,
                                          n_observations / baseline_mean,
                                          NA_real_),
    n_observations_pct_frontier = if_else(frontier_max > 0,
                                          n_observations / frontier_max,
                                          NA_real_)
  ) %>%
  select(-baseline_mean, -frontier_max) %>%
  arrange(geo_area_name, year, goal)

write_csv(
  goal_lvl_dv_data,
  file.path(output_folder, "goal_lvl_dv_data.csv")
)


# =============================================================================
# F. ROBUSTNESS PANELS (series-level) =========================================
# =============================================================================
# Series-based views that answer "was this series code reported at all?"
# rather than "how many observations were reported?". Kept as robustness /
# triangulation for the sector-level primary outcome in Section E.

# ---- F1. Series-code presence and depth: agg_series_depth -------------------
# One row per country x series-code x year with any published value. Two
# summary columns preserve the disaggregation shape for later analysis:
#   nature_codes   — "/"-joined sorted unique natures (e.g., "C/M"), so shifts
#                    in provenance mix under backsliding remain observable.
#   n_disagg_rows  — count of raw observations feeding this row, so drops in
#                    disaggregation depth are visible even when presence is
#                    unchanged.
# Also the input to F2's series-code counts.
agg_series_depth <- raw_data %>%
  group_by(goal, geo_area_code, geo_area_name, year, series_code) %>%
  summarise(
    nature_codes  = na_if(paste(sort(unique(nature)), collapse = "/"), ""),
    n_disagg_rows = n(),
    .groups = "drop"
  ) %>%
  arrange(goal, geo_area_name, year, series_code)

write_csv(
  agg_series_depth,
  file.path(output_folder, "agg_series_depth.csv.gz")
)


# ---- F2. Series-code availability, both scopes: agg_series_counts_rc --------
# Counts SERIES CODES present, not observations: a series code counts once for
# a country-year no matter how many disaggregated observations sit under it.
# This is the coarser, SDR-style measure — robustness check only.
#
# Two scopes stacked in one table, distinguished by `scope`:
#   scope == "goal"    — per country x year x goal; `goal` is filled, and the
#                        denominator is that goal's distinct series count.
#   scope == "overall" — per country x year; `goal` is NA, and the denominator
#                        is the framework-wide unique series count.
#
# The overall rows are NOT the sum of the goal rows: a series code appearing
# under two goals is counted once framework-wide but once per goal above, so
# both scopes are computed separately and stacked.
agg_series_counts_rc <- bind_rows(
  # -- goal scope --
  expand_grid(
      countries,
      year = start_year:end_year,
      goal = goals
    ) %>%
    left_join(
      agg_series_depth %>%
        count(geo_area_code, year, goal, name = "n_available_series"),
      by = c("geo_area_code", "year", "goal")
    ) %>%
    left_join(agg_series_per_goal, by = "goal") %>%
    transmute(
      geo_area_code, geo_area_name, year,
      scope = "goal",
      goal,
      n_available_series    = coalesce(n_available_series, 0L),
      n_series_in_framework = n_series_in_goal
    ),

  # -- overall scope --
  expand_grid(countries, year = start_year:end_year) %>%
    left_join(
      agg_series_depth %>%
        distinct(geo_area_code, geo_area_name, year, series_code) %>%
        count(geo_area_code, geo_area_name, year, name = "n_available_series"),
      by = c("geo_area_code", "geo_area_name", "year")
    ) %>%
    transmute(
      geo_area_code, geo_area_name, year,
      scope = "overall",
      goal  = NA_integer_,
      n_available_series    = coalesce(n_available_series, 0L),
      n_series_in_framework = agg_series_total
    )
) %>%
  mutate(
    missing_series_count = n_series_in_framework - n_available_series,
    availability_share   = n_available_series / n_series_in_framework,
    missingness_share    = 1 - availability_share
  ) %>%
  arrange(geo_area_name, year, scope, goal)

write_csv(
  agg_series_counts_rc,
  file.path(output_folder, "agg_series_counts_rc.csv")
)


# =============================================================================
# G. QUALITY CHECKS ===========================================================
# =============================================================================
message("\nFinished.")
message("Retained published observations: ", nrow(raw_data))
message("Unique countries/territories retained: ", n_distinct(countries$geo_area_code))
message("Unique series across all exports: ", agg_series_total)

message("\nSeries per goal in downloaded files:")
print(agg_series_per_goal)

message("\nPanel row counts:")
message("  goal_lvl_dv_data (PRIMARY): ", nrow(goal_lvl_dv_data))
message("  agg_series_counts_rc (robustness, both scopes): ", nrow(agg_series_counts_rc))
message("    of which scope == 'goal': ", sum(agg_series_counts_rc$scope == "goal"))
message("    of which scope == 'overall': ", sum(agg_series_counts_rc$scope == "overall"))
message("  agg_series_depth (supplementary): ", nrow(agg_series_depth))

message("\nBaseline window for pct_baseline: ",
        paste(range(baseline_years), collapse = "-"))
