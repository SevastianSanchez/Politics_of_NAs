# =============================================================================
# Politics of NAs — Series stability / framework-drift table
# =============================================================================
#
# HOW THIS IS USED
# ----------------
#   (a) Sourced from extract_SDG_series_data_2015_2025.r (section D0), where
#       raw_data is already in memory. It is used as-is — no re-read.
#   (b) Run directly (Rscript code/data_prep/build_series_stability.R) to
#       rebuild the table without re-running the extract. In that case
#       raw_data is loaded from data/clean/raw_data.csv.gz.
#
# The input guard in section 0 decides which case applies and validates the
# shape of raw_data before anything else runs.
#
# CREATES (the contract with the extract script — do not rename):
#   series_stability : one row per series_code
#   stable_codes     : character vector of framework-stable series codes
# WRITES:
#   data/clean/series_stability.csv
#
# WHY THIS EXISTS
# ---------------
# The SDG framework and the UN database both changed over 2015-2025: series
# were added, replaced, and retired. Counting raw observations without
# accounting for that means a country's data mass rises simply because the
# framework grew — not because the country reported more. Measured directly:
#
#   series with any country data, 2015: 483  ->  2022: 565
#
# That is +82 series of pure framework growth inside the study window.
#
# WHY NOT USE sdg_update_info.xlsx TEXT MATCHING
# ----------------------------------------------
# Classifying the "Action/Notes" column of that file cannot solve this:
#   1. The update log only starts 2018-06-20, three years into the panel, so
#      it says nothing at all about 2015-2017.
#   2. 82% of its rows (4,746 of 5,759) say "Data updated." — routine data
#      refreshes, not structural change.
#   3. It logs database maintenance alongside genuine framework change and the
#      text does not separate them. Decisive evidence: 254 series are labelled
#      "added" but have data going back to 2015. Those entries record when the
#      UN *database* ingested the series (SDMX migration, 2021 platform
#      relaunch), not when the *framework* gained it.
#
# THE FIX: derive stability empirically from the data. A series is
# "structurally available" in year Y if at least one country reported it that
# year. That is observable, needs no text matching, and covers every year.
# =============================================================================

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr)
  library(stringr); library(readxl); library(janitor)
})


# ---- 0. Input guard ----------------------------------------------------------
# Use raw_data from the environment when it is there (sourced case), otherwise
# load it from disk (standalone case). Then validate, so a wrong or missing
# input fails loudly here instead of silently producing a bad table.
if (exists("raw_data", inherits = TRUE) && is.data.frame(raw_data)) {
  message("build_series_stability: using raw_data already in the environment (",
          format(nrow(raw_data), big.mark = ","), " rows)")
} else {
  .raw_path <- "data/clean/raw_data.csv.gz"
  if (!file.exists(.raw_path)) {
    stop("raw_data is not in the environment and ", .raw_path, " does not exist.\n",
         "Run extract_SDG_series_data_2015_2025.r first.", call. = FALSE)
  }
  message("build_series_stability: loading ", .raw_path)
  raw_data <- read_csv(.raw_path, col_types = cols(.default = col_character()),
                       progress = FALSE) %>%
    mutate(year = as.integer(year), goal = as.integer(goal))
}

# Contract checks on raw_data.
local({
  need <- c("series_code", "geo_area_code", "year")
  miss <- setdiff(need, names(raw_data))
  if (length(miss) > 0)
    stop("raw_data is missing required column(s): ", paste(miss, collapse = ", "),
         call. = FALSE)
  if (nrow(raw_data) == 0)
    stop("raw_data has zero rows.", call. = FALSE)
  if (!is.numeric(raw_data$year))
    stop("raw_data$year must be numeric/integer, got ", class(raw_data$year)[1],
         ". Coerce it before sourcing this script.", call. = FALSE)
})


# ---- 1. Configuration --------------------------------------------------------
# Years used to define the stable core. Ends at 2023 because later years are
# still filling in — 2025 in particular is badly incomplete (232 live series
# and ~29k observations, against ~150k in a typical year). That is reporting
# lag, not data loss, and it must not be read as a collapse in the outcome.
core_window <- 2015:2023

stability_updates_path <- "data/raw/sdg_update_info.xlsx"
stability_output_path  <- "data/clean/series_stability.csv"


# ---- 2. Empirical series lifespan -------------------------------------------
series_year <- raw_data %>%
  group_by(series_code, year) %>%
  summarise(n_countries = n_distinct(geo_area_code), n_obs = n(), .groups = "drop")

lifespan <- series_year %>%
  group_by(series_code) %>%
  summarise(
    first_year    = min(year),
    last_year     = max(year),
    n_years_live  = n_distinct(year),
    total_obs     = sum(n_obs),
    max_countries = max(n_countries),
    .groups = "drop"
  )

# Series present (>= 1 reporting country) in EVERY year of the core window.
stable_codes <- series_year %>%
  filter(year %in% core_window) %>%
  distinct(series_code, year) %>%
  count(series_code) %>%
  filter(n == length(core_window)) %>%
  pull(series_code)


# ---- 3. Classify -------------------------------------------------------------
# Two independent boolean flags, because a series can do BOTH (start after the
# window opens AND stop before it closes). Filter on these, not on `status`:
#   starts_late — first observed after the window opens
#   ends_early  — last observed before the window closes (DISCONTINUED)
#
# `status` is a convenience summary only. It is mutually exclusive, so a series
# that both starts late and ends early is filed under "entered_late" and will
# NOT appear under "exited_early". To count every discontinued series use
# `ends_early`, which is unambiguous.
series_stability <- lifespan %>%
  mutate(
    is_stable_core = series_code %in% stable_codes,
    starts_late    = first_year > min(core_window),
    ends_early     = last_year  < max(core_window),
    status = case_when(
      is_stable_core ~ "stable",
      starts_late    ~ "entered_late",
      ends_early     ~ "exited_early",
      TRUE           ~ "intermittent"
    )
  )


# ---- 4. Supporting dates from the update log --------------------------------
# Only the DATES of structural events, never the text classification, since the
# text cannot separate framework change from database maintenance (see header).
# Treat these as supporting evidence, not as the basis for status.
if (file.exists(stability_updates_path)) {
  series_stability <- series_stability %>%
    left_join(
      read_excel(stability_updates_path, sheet = "Data Updates") %>%
        clean_names() %>%
        filter(!is.na(series_code)) %>%
        mutate(date = as.Date(date), note = str_to_lower(as.character(action_notes))) %>%
        group_by(series_code = as.character(series_code)) %>%
        summarise(
          log_first_seen   = min(date, na.rm = TRUE),
          log_added_date   = suppressWarnings(min(date[str_detect(note, "series added|added to the database")], na.rm = TRUE)),
          log_removed_date = suppressWarnings(max(date[str_detect(note, "series deleted|series removed")], na.rm = TRUE)),
          n_log_events     = n(),
          .groups = "drop"
        ) %>%
        mutate(across(c(log_added_date, log_removed_date),
                      ~ if_else(is.infinite(as.numeric(.x)), as.Date(NA), .x))),
      by = "series_code"
    )
} else {
  warning("Update log not found at ", stability_updates_path,
          " — stability table written without log columns.")
}

write_csv(series_stability, stability_output_path)


# ---- 5. Report ---------------------------------------------------------------
cat("\n=== Series stability summary ===\n")
print(as.data.frame(series_stability %>% count(status, name = "n_series") %>%
                      arrange(desc(n_series))))

cat("\nStable core: ", length(stable_codes), " of ", nrow(series_stability), " series ",
    sprintf("(%.0f%%)\n", 100 * length(stable_codes) / nrow(series_stability)), sep = "")
cat("Observation mass in stable core: ",
    sprintf("%.1f%%\n", 100 * sum(raw_data$series_code %in% stable_codes) / nrow(raw_data)))

cat("\n=== Framework drift: series with ANY country data, by year ===\n")
cat("(a rising count means the framework grew, not that countries reported more)\n")
print(as.data.frame(series_year %>% distinct(series_code, year) %>%
                      count(year, name = "n_series_live") %>% arrange(year)))

cat("\n=== Discontinued series (ends_early) ===\n")
cat(sum(series_stability$ends_early), " series stop before ", max(core_window),
    ". Filter on ends_early (NOT status == 'exited_early', which omits the ",
    sum(series_stability$ends_early & series_stability$starts_late),
    " that also started late).\n", sep = "")

cat("\nWrote: ", stability_output_path, " (", nrow(series_stability), " rows)\n", sep = "")
cat("Core window: ", min(core_window), "-", max(core_window),
    ". Later years are still filling in; 2025 is badly incomplete.\n", sep = "")
