# =============================================================================
# Politics of NAs — UN SDG Global Database export prep
# =============================================================================
#
# WHAT THIS DOES
# Reads the 17 goal-level Excel exports of the UN SDG database, cleans them to
# a 2015-2023 country panel, and writes the datasets used to study how
# democratic backsliding affects a country's SDG data reporting.
#
# WHY 2015-2023 (not 2025): the exports run to 2025, but 2024-2025 are still
# being filled in by the UN (2025 has ~20% of a normal year). Keeping them would
# look like every country collapsing at once. See Section A2.
#
# INPUTS: data/raw/un_sdg_goal_exports/Goal1.xlsx ... Goal17.xlsx
# OUTPUTS: data/clean/ (each file's basename == its R object name)
#
# -----------------------------------------------------------------------------
# raw_data.csv.gz — SOURCE OF TRUTH. One row per observation (country x series x
#   year x disaggregation). Every dataset below is derived from it.
#     value          the reported number; NA means the cell was empty ("NaN" in
#                    the export, converted in C1)
#     missing_reason why an empty cell is empty: structural / suppressed /
#                    unknown. NA when value is present. (is.na(value) and
#                    is.na(missing_reason) are opposites on every row.)
#     nature         who produced the value (country vs agency); see C1
#     iso3           merge key to MAIN_panel_data (added in C4)
#
# goal_lvl_dv_data.csv (+ .rds twin with column labels) — PRIMARY OUTCOME.
#   One row per country x year x goal. Outcome columns, side by side:
#     n_observations           count of reported observations
#     n_observations_country   of those, produced by the country (nature C/CA)
#     n_observations_agency    of those, produced by an agency (nature E/M/G)
#     n_observations_stable    of those, in framework-stable series (see D0)
#     n_declared_missing       empty cells the UN opened here (split into
#                              n_missing_structural / _suppressed / _unknown)
#     the same count as a share of a denominator, for cross-goal comparison:
#     _pct_baseline   / this country's own 2015-17 mean (NA if that is 0)
#     _pct_goalbase   / the all-country 2015-17 mean for the goal (always defined)
#     _pct_frontier   / the most any country reported that goal-year
#     (_stable_pct_baseline and _stable_pct_goalbase: same, stable-core only)
#
# series_list.csv — one row per goal-target-indicator-series, with the stability
#   labels (from series_stability.csv) and per-series observation counts joined on.
#
# series_stability.csv — one row per series: its lifespan and the flags that
#   define the framework-stable core. Built by build_series_stability.R (D0).
#
# geo_exclusions.csv — one row per geography that left its own code, either
#   dropped (A3) or rolled up into a parent state (A4). The `disposition` column
#   says which. A report of what the config did, not a hand-kept list.
#
# agg_series_counts_rc.csv — ROBUSTNESS. Availability measured by counting
#   SERIES CODES present (each counts once, regardless of disaggregation depth),
#   not observations. Two scopes stacked: scope == "goal" (per country-year-goal)
#   and scope == "overall" (per country-year, goal is NA).
#
# agg_series_depth.csv.gz (+ .rds twin) — SUPPLEMENTARY. One row per country x
#   series x year. n_disagg_rows is how many disaggregations the country reported;
#   dv_depth_pct_frontier / dv_depth_pct_union express it as a share of a per-series
#   ceiling, so depth is comparable across countries.
#
# -----------------------------------------------------------------------------
# The exports are a fixed snapshot. Downloaded Aug 16, 2026; DB last updated
# July 7, 2026.


# =============================================================================
# A. SETUP =====================================================================
# =============================================================================

# ---- A1. Packages ------------------------------------------------------------
required_packages <- c("readxl", "dplyr", "purrr", "readr", "tidyr", "stringr",
                       "janitor", "countrycode")
missing_packages <- required_packages[!required_packages %in% rownames(installed.packages())]
if (length(missing_packages) > 0) install.packages(missing_packages)

library(readxl)
library(dplyr)
library(purrr)
library(readr)
library(tidyr)
library(stringr)
library(janitor)
library(countrycode)


# ---- A2. Configuration -------------------------------------------------------
# Analysis window. Ends at 2023, not 2025, because the UN has not finished
# filling in the recent years (2024 has ~85% of a normal year's observations,
# 2025 only ~20%). Everything downstream reads start_year:end_year, so extend
# this once the UN backfills. build_series_stability.R checks its own window
# fits inside this one.
start_year <- 2015L
end_year   <- 2023L

# Baseline window for the _pct_baseline / _pct_goalbase measures (Section E1):
# the first three SDG years, before most autocratization episodes begin. To use
# a single year instead, e.g. baseline_years <- 2017L — nothing else changes.
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
  "Age", "Location", "Nature", "Sex", "Units",
  "Observation Status"
)
# NOT kept, though present in the export schema — both carry no information:
#   Freq            100% empty in all 17 files (the UN never populates it)
#   Reporting Type  a single constant value, "G", on every row

# GeoAreaName values that are aggregates, not country/territory reporting units.
# GeoAreaCode is the safer merge key; this list is a belt-and-braces filter.
aggregate_geographies <- c(
  "World", "Africa", "Asia", "Europe", "Oceania",
  "Northern Africa and Western Asia", "Central Asia and Southern Asia",
  "Eastern Asia and South-eastern Asia", "Latin America and the Caribbean",
  "Sub-Saharan Africa", "Europe and Northern America"
)

# ---- A3. Excluded geographies -------------------------------------------------
# M49 codes dropped from the country panel, grouped by reason. This one list
# drives both the filter (C3) and the audit table (geo_exclusions.csv), so the
# record of what was removed cannot drift from what was actually removed.
#
# TO CHANGE THE PANEL: edit only this list. Each entry is "Geography name" = code;
# the group name becomes the `exclusion_reason`. The name is checked against the
# UN's published name in C3, so a mistyped code is caught rather than silently
# dropping the wrong country.
#
# Excluded: places with no permanent population, "other areas" buckets, and
# states that no longer exist — none has a government or statistics office, so a
# reporting score for them says nothing about politics.
#
# NOT excluded on purpose:
#   - UK devolved jurisdictions (827/828/829): rolled up into the UK (A4).
#   - Four non-members kept because they have real data and a democracy score
#     exists (or may): 275 Palestine, 344 Hong Kong, 412 Kosovo, 446 Macao.
#     None is in MAIN_panel_data yet, so each must be added there before it can
#     enter a model.
excluded_geographies <- list(
  "uninhabited or residual bucket" = c(
    "Antarctica"                                   =  10,
    "Bouvet Island"                                =  74,
    "British Indian Ocean Territory"               =  86,
    "Other non-specified areas in Eastern Asia"    = 158,
    "Christmas Island"                             = 162,
    "Cocos (Keeling) Islands"                      = 166,
    "South Georgia and the South Sandwich Islands" = 239,
    "French Southern Territories"                  = 260,
    "Heard Island and McDonald Islands"            = 334,
    "Norfolk Island"                               = 574,
    "United States Minor Outlying Islands"         = 581,
    "Pitcairn"                                     = 612,
    "Ascension"                                    = 655,
    "Sark"                                         = 680,
    "Svalbard and Jan Mayen Islands"               = 744
  ),

  # States that dissolved before the SDG era. M49 never retires a code — it
  # keeps them flagged "[former]" - Every row they carry in 2015-2023 is UNEP
  # material-flows model output (nature "E"), and 420 of the 421 values are
  # structural zeros. Successor states are all separately in the panel.
  "defunct entity" = c(
    "Yugoslavia [former]"            = 890,  # country no longer exists — SFRY dissolved 1992
    "Serbia and Montenegro [former]" = 891,  # country no longer exists — union dissolved June 2006
    "Netherlands Antilles  [former]" = 530   # country no longer exists — dissolved October 2010
  ),

  # Sub-national reporting strata whose parent state is separately in the panel.
  # THE RULE: the unit of analysis is the sovereign state, because the treatment
  # (autocratization episodes from ERT / V-Dem) is coded only at that level.
  # These units have no V-Dem or ERT score, so they can carry an outcome but can
  # never be treated. Their parents are fully present — Tanzania (834) with 496
  # series, Iraq (368) with 442 — so nothing is lost from the panel.
  #
  # Corroborating, but NOT the criterion: both would also manufacture false data
  # loss if kept. A unit with 1-5 series scores near-zero availability because it
  # was never a reporting unit for 16 of 17 goals, not because reporting fell.
  # Zanzibar's 120 rows are 100% UNEP material-flows model zero-fill (nature E,
  # no country-reported observation at all); Central Iraq is a 5-series criminal
  # justice collection stratum with no Kurdistan counterpart to complete it.
  "sub-national reporting stratum" = c(
    "United Republic of Tanzania (Zanzibar)" = 836,  # region of Tanzania, not a state
    "Iraq (Central Iraq)"                    = 369   # survey stratum, not a state
  ),

  # Dependent territories and non-member entities. Same rule as the strata above:
  # the unit of analysis is the sovereign state, because the treatment
  # (autocratization episodes from ERT / V-Dem) is coded only at that level.
  # Verified: NONE of these 40 appears in MAIN_panel_data, so every one would
  # drop silently at the democracy-measure merge. Excluding them here makes that
  # explicit and keeps the panel's N honest.
  #
  # NOT in this list, deliberately retained — see the note above the list:
  #   275 State of Palestine, 344 Hong Kong SAR, 446 Macao SAR, 412 Kosovo.
  "dependent territory or non-member" = c(
    "American Samoa"                   =  16,  # United States
    "Bermuda"                          =  60,  # United Kingdom
    "British Virgin Islands"           =  92,  # United Kingdom
    "Cayman Islands"                   = 136,  # United Kingdom
    "Mayotte"                          = 175,  # France
    "Cook Islands"                     = 184,  # New Zealand free association
    "Faroe Islands"                    = 234,  # Denmark
    "Falkland Islands (Malvinas)"      = 238,  # United Kingdom / disputed
    "Åland Islands"                    = 248,  # Finland
    "French Guiana"                    = 254,  # France
    "French Polynesia"                 = 258,  # France
    "Gibraltar"                        = 292,  # United Kingdom
    "Greenland"                        = 304,  # Denmark
    "Guadeloupe"                       = 312,  # France
    "Guam"                             = 316,  # United States
    "Holy See"                         = 336,  # UN observer, not a member
    "Martinique"                       = 474,  # France
    "Montserrat"                       = 500,  # United Kingdom
    "Curaçao"                          = 531,  # Netherlands
    "Aruba"                            = 533,  # Netherlands
    "Sint Maarten (Dutch part)"        = 534,  # Netherlands
    "Bonaire, Sint Eustatius and Saba" = 535,  # Netherlands
    "New Caledonia"                    = 540,  # France
    "Niue"                             = 570,  # New Zealand free association
    "Northern Mariana Islands"         = 580,  # United States
    "Puerto Rico"                      = 630,  # United States
    "Réunion"                          = 638,  # France
    "Saint Barthélemy"                 = 652,  # France
    "Saint Helena"                     = 654,  # United Kingdom
    "Anguilla"                         = 660,  # United Kingdom
    "Saint Martin (French Part)"       = 663,  # France
    "Saint Pierre and Miquelon"        = 666,  # France
    "Western Sahara"                   = 732,  # disputed territory
    "Tokelau"                          = 772,  # New Zealand
    "Turks and Caicos Islands"         = 796,  # United Kingdom
    "Guernsey"                         = 831,  # UK crown dependency
    "Jersey"                           = 832,  # UK crown dependency
    "Isle of Man"                      = 833,  # UK crown dependency
    "United States Virgin Islands"     = 850,  # United States
    "Wallis and Futuna Islands"        = 876   # France
  )
)

# Flatten to one row per excluded geography. geo_area_code is character in
# raw_data, so the codes are coerced here once rather than at every comparison.
# `geo_area_name_expected` is the name as configured above; C3 checks it against
# the name the UN actually publishes for that code.
excluded_geo_reasons <- imap_dfr(excluded_geographies, function(codes, reason) {
  tibble(
    geo_area_code          = as.character(codes),
    geo_area_name_expected = names(codes),
    exclusion_reason       = reason)
})

excluded_geo_codes <- excluded_geo_reasons$geo_area_code

# Config integrity: every entry needs a name, and no code may appear twice.
.unnamed <- is.na(excluded_geo_reasons$geo_area_name_expected) |
            excluded_geo_reasons$geo_area_name_expected == ""
if (any(.unnamed)) {
  stop("Every entry in excluded_geographies must be written as ",
       "\"Geography name\" = code. Unnamed code(s): ",
       paste(excluded_geo_codes[.unnamed], collapse = ", "), call. = FALSE)
}
rm(.unnamed)

if (anyDuplicated(excluded_geo_codes) > 0) {
  stop("excluded_geographies lists the same geo_area_code more than once: ",
       paste(unique(excluded_geo_codes[duplicated(excluded_geo_codes)]),
             collapse = ", "), call. = FALSE)
}


# ---- A4. Sub-national roll-ups ------------------------------------------------
# Some countries report certain SDG series only at a sub-national jurisdiction,
# because the underlying institution is devolved. The UK is the case here: it
# has three separate legal systems, so UNODC publishes crime statistics per
# jurisdiction (England & Wales, Scotland, Northern Ireland) instead of one
# UK-wide figure. Those jurisdictions are not sovereign states and carry no
# V-Dem / ERT score, so they cannot be their own panel unit — but the data is
# real, country-produced reporting (nature "C") that the UK genuinely did, and
# 12 of the 14 series appear under no other UK code. Excluding them (as with the
# strata above) would understate UK Goal 16 reporting, so instead their rows are
# reassigned to the parent state and counted there. Section C2b does the move.
#
# Each entry is "Child name" = child_code; `= <parent_code>` names the target.
# To roll a different country's sub-units up, add a block with its parent code.
rollup_to_parent <- list(
  "826" = c(  # -> United Kingdom of Great Britain and Northern Ireland
    "United Kingdom (England and Wales)" = 827,
    "United Kingdom (Northern Ireland)"  = 828,
    "United Kingdom (Scotland)"          = 829))

# Flatten to a child_code -> parent_code lookup used by C2b.
rollup_map <- imap_dfr(rollup_to_parent, function(children, parent) {
  tibble(
    child_code  = as.character(children),
    child_name  = names(children),
    parent_code = parent)
})

if (any(is.na(rollup_map$child_name) | rollup_map$child_name == "")) {
  stop("Every entry in rollup_to_parent must be written as ",
       "\"Child name\" = code.", call. = FALSE)
}
if (anyDuplicated(rollup_map$child_code) > 0) {
  stop("rollup_to_parent lists the same child code more than once: ",
       paste(unique(rollup_map$child_code[duplicated(rollup_map$child_code)]),
             collapse = ", "), call. = FALSE)
}
# A child cannot be both rolled up and excluded — that is a config contradiction.
.rollup_excluded <- intersect(rollup_map$child_code, excluded_geo_codes)
if (length(.rollup_excluded) > 0) {
  stop("These codes are in BOTH excluded_geographies and rollup_to_parent: ",
       paste(.rollup_excluded, collapse = ", "),
       ". A geography is either dropped or rolled up, not both.", call. = FALSE)
}
rm(.rollup_excluded)


# ---- A5. ISO3 merge key overrides ---------------------------------------------
# Section C4 maps M49 geo_area_code -> ISO3 with countrycode(origin = "un"),
# which resolves 196 of the 197 retained geographies on its own. This list
# supplies ISO3 for the ones it cannot, and would also be the place to force a
# different code if the analysis needed one.
#
# ISO3 is the merge key because MAIN_panel_data keys on it (`country_code`:
# 172 values, no NAs, 1:1 with country name). Its `iso2c` column has 9 NAs and
# `country_id` is a local 1-172 index, so neither travels.
#
# Entries are "M49 code" = "ISO3".
iso3_overrides <- c(
  "412" = "XKX"   # Kosovo — no official M49 or ISO3 code exists; XKX is the
                  # de facto standard (World Bank, IMF, Eurostat).
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
    # Filter on the RAW Value string, before the NaN conversion below. A truly
    # blank cell is dropped; a "NaN" cell (the UN saying it opened this slot and
    # found nothing) is KEPT — that empty cell is part of the outcome.
    filter(
      TimePeriod >= start_year,
      TimePeriod <= end_year,
      !is.na(Value),
      Value != "",
      !is.na(GeoAreaCode),
      str_detect(GeoAreaCode, "^[0-9]+$"),
      !GeoAreaName %in% aggregate_geographies
    ) %>%
    mutate(
      # WHY an empty cell is empty, from the UN's Nature and Observation Status
      # fields. Set only where the value is "NaN" (NA on cells that have a value),
      # so is.na(Value) and is.na(missing_reason) are opposites — no separate flag.
      #   structural  Nature "N" or Observation Status "M": the indicator does not
      #               apply here. NOT data loss. Nature "N" is the test because it
      #               is the complete marker (some agencies tag only Nature).
      #   suppressed  Observation Status "Q": withheld, usually confidential.
      #   unknown     no reason given — Observation Status "O", or neither field
      #               populated (some agencies fill neither).
      missing_reason = case_when(
        Value != "NaN"                                       ~ NA_character_,
        coalesce(Nature, "") == "N" |
          coalesce(`Observation Status`, "") == "M"          ~ "structural",
        coalesce(`Observation Status`, "") == "Q"            ~ "suppressed",
        TRUE                                                 ~ "unknown"
      ),
      # "NaN" means "no value", so convert it to a real NA. Reversible: Value is
      # NA exactly where missing_reason is set.
      Value = na_if(Value, "NaN")
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
#
# TWO KINDS OF ROW live here (see C1):
#   value present — a published observation. Every availability count uses these.
#   value is NA   — the UN opened this slot and left it empty; `missing_reason`
#                   says why.
# Because every count below is a ROW count, each one tests !is.na(value).
# Counting without that test would treat declared-missing as reported data.
raw_data <- map_dfr(file_manifest$file_path, read_one_goal_file) %>%
  clean_names() %>%
  rename(year = time_period) %>%
  arrange(goal, geo_area_name, series_code, year, value, nature, observation_status)

# Variable labels documenting what an NA in `value` means, so the convention
# travels with the data instead of living only in this comment. (write_csv drops
# attributes, so these survive in-session and in any .rds twin.)
attr(raw_data$value, "label") <-
  "Published value. NA = declared missing (\"NaN\" in the export); see missing_reason"
attr(raw_data$missing_reason, "label") <-
  "Why value is NA: structural / suppressed / unknown. NA where a value exists"

message("\nDeclared-missing rows (value was \"NaN\" in the export):")
message("  ", format(sum(is.na(raw_data$value)), big.mark = ","),
        " of ", format(nrow(raw_data), big.mark = ","),
        sprintf(" (%.1f%%)", 100 * mean(is.na(raw_data$value))))
message("  by missing_reason (see C1):")
print(raw_data %>% filter(is.na(value)) %>%
        count(missing_reason, name = "rows") %>%
        mutate(pct = round(100 * rows / sum(rows), 1)) %>%
        arrange(desc(rows)))


# ---- C2b. Sub-national roll-ups → raw_data ----------------------------------
# Reassign the sub-national jurisdictions configured in A4 to their parent
# state, so their reporting counts under the sovereign unit the analysis uses.
# Runs before everything downstream (stability, panels) so they all see the
# rolled-up parent. See A4 for the rationale.
#
# Collision handling: a child observation whose full disaggregation key already
# exists under the REAL parent is a component of a figure the parent already
# publishes as an aggregate (e.g. UNODC's UK homicide total = sum of the three
# legal jurisdictions). Keeping both would double-count, so the parent's own row
# wins and the child component is dropped. Child observations with no matching
# parent key are series the parent does not otherwise report; they move across
# and become the parent's data. The comparison key deliberately EXCLUDES
# geo_area_code, so it is parent-vs-child on the same series/year/disaggregation
# — NOT against other countries that report the same series.
if (nrow(rollup_map) > 0) {

  # Identifying key: everything that distinguishes an observation except the
  # geography, the value, and provenance (source / footnote). The separator is
  # a string that cannot occur inside these plain-text fields.
  .sep      <- "|~|"
  .key_cols <- setdiff(names(raw_data),
                       c("geo_area_code", "geo_area_name", "value",
                         "source", "foot_note"))
  .key      <- do.call(paste, c(raw_data[.key_cols], sep = .sep))

  .child_of  <- setNames(rollup_map$parent_code, rollup_map$child_code)
  .is_child  <- raw_data$geo_area_code %in% rollup_map$child_code
  .parents   <- unique(rollup_map$parent_code)

  # Keys each parent already carries, tagged by parent code, and the key each
  # child would land on under its parent. A child collides iff its target is in
  # the parent set.
  .is_parent      <- raw_data$geo_area_code %in% .parents
  .parent_key_set <- unique(paste(raw_data$geo_area_code[.is_parent],
                                  .key[.is_parent], sep = .sep))
  .child_target   <- paste(.child_of[raw_data$geo_area_code[.is_child]],
                           .key[.is_child], sep = .sep)

  .drop_row            <- logical(nrow(raw_data))
  .drop_row[.is_child] <- .child_target %in% .parent_key_set

  # A configured child code absent from the data does nothing silently — warn,
  # the same way C3 warns about an unmatched exclusion code.
  .child_missing <- setdiff(rollup_map$child_code, raw_data$geo_area_code)
  if (length(.child_missing) > 0) {
    warning("rollup_to_parent lists ", length(.child_missing),
            " child code(s) not present in the data: ",
            paste(.child_missing, collapse = ", "),
            "\nCheck for a typo, or drop them from the list in Section A4.")
  }

  # Per-child audit (captured BEFORE the move). Same schema as the exclusion
  # audit in C3, so the two stack into one geo_exclusions.csv there.
  #   n_observations : rows the child contributed
  #   n_obs_retained : of those, how many were reassigned to the parent
  #                    (n_observations - n_obs_retained = duplicate components
  #                    dropped because the parent already published the aggregate)
  geo_rollup_audit <- raw_data %>%
    filter(.is_child) %>%
    mutate(.dropped = .drop_row[.is_child]) %>%
    group_by(geo_area_code, geo_area_name) %>%
    summarise(
      n_observations = n(),
      n_obs_retained = sum(!.dropped),
      n_series       = n_distinct(series_code),
      n_years        = n_distinct(year),
      first_year     = min(year),
      last_year      = max(year),
      .groups = "drop"
    ) %>%
    left_join(rollup_map, by = c("geo_area_code" = "child_code")) %>%
    transmute(
      geo_area_code, geo_area_name,
      disposition = "rolled up",
      reason      = paste0("devolved jurisdiction -> parent ", parent_code),
      parent_code,
      n_observations, n_obs_retained, n_series, n_years, first_year, last_year
    )

  # Names for the reassigned rows: pull each parent's canonical name from its
  # own rows in the data.
  .parent_names <- raw_data %>%
    filter(geo_area_code %in% .parents) %>%
    distinct(geo_area_code, geo_area_name) %>%
    { setNames(.$geo_area_name, .$geo_area_code) }

  .uk_series_before <- n_distinct(
    raw_data$series_code[raw_data$geo_area_code %in% .parents])

  # Drop colliding components, then reassign the survivors to their parent.
  raw_data  <- raw_data[!.drop_row, ]
  .moved    <- raw_data$geo_area_code %in% rollup_map$child_code
  .new_par  <- unname(.child_of[raw_data$geo_area_code[.moved]])
  raw_data$geo_area_name[.moved] <- .parent_names[.new_par]
  raw_data$geo_area_code[.moved] <- .new_par

  .uk_series_after <- n_distinct(
    raw_data$series_code[raw_data$geo_area_code %in% .parents])

  message("\nSub-national roll-ups (see Section A4; logged in geo_exclusions.csv):")
  message("  children rolled up: ", nrow(geo_rollup_audit),
          " into ", length(.parents), " parent(s)")
  message("  rows moved: ", sum(geo_rollup_audit$n_obs_retained),
          " | rows dropped as duplicate components: ",
          sum(geo_rollup_audit$n_observations - geo_rollup_audit$n_obs_retained))
  message("  parent series before -> after: ",
          .uk_series_before, " -> ", .uk_series_after,
          " (+", .uk_series_after - .uk_series_before, ")")

  rm(.sep, .key_cols, .key, .child_of, .is_child, .parents, .is_parent,
     .parent_key_set, .child_target, .drop_row, .child_missing, .parent_names,
     .moved, .new_par, .uk_series_before, .uk_series_after)
}


# ---- C3. Geography exclusions → geo_exclusions ------------------------------
# Drop the geographies configured in A3, and write ONE audit table (also
# carrying the C2b roll-ups) of every geography that left its own code — whether
# excluded outright or reassigned to a parent. The `disposition` column says
# which. Driven by the same config that drives the actions, so the CSV is a
# report of what happened, not a hand-maintained list that can fall out of sync.
#
# Built BEFORE the exclusion filter runs, so it carries the real observation and
# series counts each excluded geography contributed. Schema matches the C2b
# roll-up audit so the two stack:
#   disposition    "excluded" | "rolled up"
#   reason         exclusion reason group, or the roll-up target
#   parent_code    the parent a rolled-up child went to (NA for excluded)
#   n_observations rows the geography contributed
#   n_obs_retained rows kept (0 for excluded; reassigned rows for rolled up)
excluded_audit <- raw_data %>%
  filter(geo_area_code %in% excluded_geo_codes) %>%
  group_by(geo_area_code, geo_area_name) %>%
  summarise(
    n_observations = n(),
    n_series       = n_distinct(series_code),
    n_years        = n_distinct(year),
    first_year     = min(year),
    last_year      = max(year),
    .groups = "drop"
  ) %>%
  right_join(excluded_geo_reasons, by = "geo_area_code") %>%
  mutate(across(c(n_observations, n_series, n_years), ~ coalesce(.x, 0L)),
    # `geo_area_name` is authoritative when the code matched; fall back to the
    # configured name so an unmatched code is still readable in the report.
    name_matches_config = !is.na(geo_area_name) &
                          geo_area_name == geo_area_name_expected,
    geo_area_name       = coalesce(geo_area_name, geo_area_name_expected))

# A configured code that matched nothing is worth knowing about: it is either a
# typo, or a geography the UN no longer publishes. Not fatal — just reported.
unmatched_geo <- excluded_audit %>% filter(n_observations == 0)
if (nrow(unmatched_geo) > 0) {
  warning("excluded_geographies lists ", nrow(unmatched_geo),
          " code(s) not present in the data: ",
          paste0(unmatched_geo$geo_area_code, " (",
                 unmatched_geo$geo_area_name_expected, ")", collapse = ", "),
          "\nCheck for a typo, or drop them from the list in Section A3.")
}

# A code that matched a DIFFERENT geography than the config claims means the
# wrong country is being excluded. That is worth shouting about.
mismatched_geo <- excluded_audit %>%
  filter(n_observations > 0, !name_matches_config)
if (nrow(mismatched_geo) > 0) {
  warning("excluded_geographies names do not match the UN's published names ",
          "for these codes — the WRONG geography may be excluded:\n",
          paste0("  code ", mismatched_geo$geo_area_code,
                 ": configured as '", mismatched_geo$geo_area_name_expected,
                 "', data says '", mismatched_geo$geo_area_name, "'",
                 collapse = "\n"))
}

# One audit table: exclusions + roll-ups (C2b), in the shared schema.
geo_exclusions <- bind_rows(
  excluded_audit %>%
    transmute(
      geo_area_code, geo_area_name,
      disposition = "excluded",
      reason      = exclusion_reason,
      parent_code = NA_character_,
      n_observations, n_obs_retained = 0L,
      n_series, n_years, first_year, last_year),
    if (exists("geo_rollup_audit")) geo_rollup_audit) %>%
  arrange(disposition, reason, as.integer(geo_area_code))

write_csv(geo_exclusions, file.path(output_folder, "geo_exclusions.csv"))

n_before   <- nrow(raw_data)
raw_data   <- raw_data %>% filter(!geo_area_code %in% excluded_geo_codes)
n_excluded <- n_before - nrow(raw_data)

message("\nGeography exclusions (see Section A3; logged in geo_exclusions.csv):")
message("  configured codes: ", length(excluded_geo_codes),
        " across ", length(excluded_geographies), " reason group(s)")
message("  matched in data:  ", sum(excluded_audit$n_observations > 0))
message("  observations removed: ", format(n_excluded, big.mark = ","),
        sprintf(" (%.2f%% of %s)", 100 * n_excluded / n_before,
                format(n_before, big.mark = ",")))
message("  geographies retained: ", n_distinct(raw_data$geo_area_code))
print(geo_exclusions %>% select(geo_area_code, geo_area_name, disposition,
                               reason, n_observations, n_obs_retained, n_series))


# ---- C4. ISO3 merge key → raw_data$iso3 -------------------------------------
# Attach the analysis merge key here, at the point where the geography set is
# FINAL — after the roll-ups (C2b) and the exclusions (C3), before raw_data is
# written. Everything downstream inherits it, and the mapping is validated in
# the same place the geography decisions are reported.
#
# The SDG exports carry M49 numeric codes only; MAIN_panel_data keys on ISO3.
# countrycode(origin = "un") is a direct code-to-code lookup, so this avoids
# name matching entirely — no "Türkiye" vs "Turkey" or "Viet Nam" vs "Vietnam".
# Section A5 supplies ISO3 for codes the lookup cannot resolve.
raw_data <- raw_data %>%
  mutate(
    iso3 = suppressWarnings(
      countrycode(as.integer(geo_area_code), origin = "un", destination = "iso3c")),
    iso3 = coalesce(unname(iso3_overrides[geo_area_code]), iso3)
  )

.geo_iso <- raw_data %>% distinct(geo_area_code, geo_area_name, iso3)

# Any geography left without an ISO3 cannot be merged to the treatment data.
.iso_missing <- .geo_iso %>% filter(is.na(iso3))
if (nrow(.iso_missing) > 0) {
  warning("No ISO3 for ", nrow(.iso_missing), " geography(ies): ",
          paste0(.iso_missing$geo_area_code, " (", .iso_missing$geo_area_name, ")",
                 collapse = ", "),
          "\nAdd them to iso3_overrides in Section A5.")
}

# Two geographies sharing an ISO3 would fan out rows on the join.
.iso_dupes <- .geo_iso %>% filter(!is.na(iso3)) %>% count(iso3) %>% filter(n > 1)
if (nrow(.iso_dupes) > 0) {
  stop("Duplicate ISO3 across geographies: ",
       paste(.iso_dupes$iso3, collapse = ", "),
       ". The merge would duplicate rows.", call. = FALSE)
}

message("\nISO3 merge key (see Sections A5 / C4):")
message("  geographies: ", nrow(.geo_iso),
        " | resolved: ", sum(!is.na(.geo_iso$iso3)),
        " | via override: ", sum(.geo_iso$geo_area_code %in% names(iso3_overrides)),
        " | unresolved: ", nrow(.iso_missing))
rm(.geo_iso, .iso_missing, .iso_dupes)

write_csv(raw_data, file.path(output_folder, "raw_data.csv.gz"))


# =============================================================================
# D. DERIVED REFERENCE TABLES ==================================================
# =============================================================================
# All of the following are computed once from raw_data and reused by the
# outcome panels in Sections E and F.

# ---- D0. Series stability → series_stability --------------------------------
# The SDG framework grew inside the study window (483 series with country data
# in 2015 -> 565 in 2022), so a raw observation count drifts upward for reasons
# that have nothing to do with country behaviour. The sourced script flags the
# series present in every year of its core window; that stable core is used in
# Section E to build a framework-invariant version of the outcome. See
# build_series_stability.R for the full rationale.

# Input = raw_data already in memory 
# Output (objects) = `series_stability` and `stable_codes` — and writes
# data/clean/series_stability.csv. 
source("code/data_prep/build_series_stability.R")


# ---- D1. Country lookup → countries -----------------------------------------
# Carries iso3 (Section C4), so every panel built from this scaffold ships with
# the merge key to MAIN_panel_data already attached.
countries <- raw_data %>% distinct(geo_area_code, geo_area_name, iso3)


# ---- D2. Series list (goal-target-indicator-series crosswalk) ---------------
# A series may occur under more than one goal in the official framework. Since
# these are goal-specific exports, preserve each unique goal-series link.
# Stability labels are joined on so this reference table doubles as the
# lookup for which series are framework-stable. See D0 / build_series_stability.R.
series_list <- raw_data %>%
  distinct(goal, target, indicator, series_code, series_description) %>%
  left_join(series_stability %>%
              select(series_code, first_year, last_year, n_years_live,
             is_stable_core, starts_late, ends_early, status),
    by = "series_code") %>%
  # One pass, same pattern as E1: each column counts the rows meeting its own
  # condition. pct_country_produced says how much of a series is the country's
  # own reporting versus a custodian agency's estimate — it varies from 2% to
  # 100% across series, so it matters which ones a result is driven by.
  left_join(
    raw_data %>%
      group_by(series_code) %>%
      summarise(
        n_observations      = sum(!is.na(value)),
        n_observations_country = sum(!is.na(value) & nature %in% c("C", "CA")),
        n_observations_agency  = sum(!is.na(value) & nature %in% c("E", "M", "G")),
        n_declared_missing  = sum(is.na(value)),
        # Split by missing_reason (C1). A series with a large structural share
        # is one that simply does not apply to many countries.
        n_missing_structural = sum(is.na(value) & missing_reason == "structural"),
        n_missing_suppressed = sum(is.na(value) & missing_reason == "suppressed"),
        .groups = "drop"
      ) %>%
      mutate(pct_country_produced = if_else(n_observations > 0,
               round(100 * n_observations_country / n_observations, 1), NA_real_)),
    by = "series_code") %>%
  mutate(across(c(n_observations, n_observations_country, n_observations_agency,
                  n_declared_missing, n_missing_structural, n_missing_suppressed),
                ~ coalesce(.x, 0L))) %>%
  arrange(goal, target, indicator, series_code)

write_csv(series_list, file.path(output_folder, "series_list.csv"))


# ---- D3. All-goals vector → goals -------------------------------------------
# Precomputed once and reused by every downstream expand_grid.
goals <- sort(unique(series_list$goal))


# ---- D4. Per-goal totals → goal_totals ------------------------------
# n_series_in_goal    : distinct series codes per goal (denominator for the
#                       series-count availability shares in Section F2).
# n_observations_in_goal : total disaggregated observations per goal (one row
#                       of raw_data = one observation), i.e. the size of each
#                       goal's data universe below the series-code level.
# obs_per_series      : mean observations per series code — how deep the
#                       disaggregation runs for a typical series in the goal.
goal_totals <- series_list %>%
  distinct(goal, series_code) %>%
  count(goal, name = "n_series_in_goal") %>%
  left_join(raw_data %>% filter(!is.na(value)) %>%
              count(goal, name = "n_observations_in_goal"),
    by = "goal") %>%
  mutate(obs_per_series = n_observations_in_goal / n_series_in_goal)


# ---- D5. Framework-wide series total → agg_series_total ---------------------
# Unique series codes across all goal exports (a series in two goals counted
# once). Denominator for the framework-wide availability share in Section F3.
agg_series_total <- n_distinct(series_list$series_code)


# ---- D6. Country-goal baseline mean → baseline ------------------------------
# Mean raw observation count per country-goal across baseline_years. Missing
# country-goal-years in the baseline window are treated as real zeros (not
# unobserved), so a country that reported nothing in a baseline year does not
# inflate its own baseline by being averaged over observed years only.
# Helper so the all-series and stable-core baselines are computed identically.
make_baseline <- function(dat) {
  expand_grid(
      countries,
      year = baseline_years,
      goal = goals
    ) %>%
    left_join(
      dat %>% filter(!is.na(value)) %>%
        count(geo_area_code, year, goal, name = "n_observations"),
      by = c("geo_area_code", "year", "goal")
    ) %>%
    mutate(n_observations = coalesce(n_observations, 0L)) %>%
    group_by(geo_area_code, goal) %>%
    summarise(baseline_mean = mean(n_observations), .groups = "drop")
}

# One table, one row per country-goal, with BOTH baseline means side by side.
# They share the country-goal grain, so they belong in a single object
# The two columns differ only in which series feed them:
#   baseline_mean_all    — all series (see agg_series_total for the count)
#   baseline_mean_stable — stable-core series only (see length(stable_codes))
# The series counts are printed in the Section G report rather than baked into
# the column names, since they change if the core window or the pull changes.
baseline <- make_baseline(raw_data) %>%
  rename(baseline_mean_all = baseline_mean) %>%
  left_join(
    make_baseline(raw_data %>% filter(series_code %in% stable_codes)) %>%
      rename(baseline_mean_stable = baseline_mean),
    by = c("geo_area_code", "goal")) %>%
  left_join(distinct(raw_data, geo_area_code, geo_area_name),
    by = "geo_area_code")

# Adding labels to the baseline means
attr(baseline$baseline_mean_all, "label") <-
  sprintf("Obs count — all %d series", agg_series_total)
attr(baseline$baseline_mean_stable, "label") <-
  sprintf("Obs count — %d framework-stable series", length(stable_codes))


# ---- D6b. Goal-level baseline mean → goal_baseline --------------------------
# Average of the country-goal baselines across ALL countries within each goal —
# i.e. what a typical country reported for this goal in baseline_years. Derived
# from `baseline`
# (D6), so it uses the identical window and definitions; because the baseline
# panel is balanced (every country has all baseline years), the mean of the
# country means equals the goal's overall baseline mean.
#
# WHY IT EXISTS: the country-own baseline in D6 is undefined (0) for ~90
# country-goals that had not begun reporting a goal by 2017, forcing NA in
# dv_n_observations_pct_baseline. This goal-level denominator is never 0 (some
# country always reports), so it gives a cross-goal-comparable outcome defined
# for every country-goal-year — see the *_pct_goalbase columns in E1.
goal_baseline <- baseline %>%
  group_by(goal) %>%
  summarise(goal_baseline_all    = mean(baseline_mean_all),
            goal_baseline_stable = mean(baseline_mean_stable),
            .groups = "drop")


# ---- D7. Goal-year frontier max → frontier ----------------------------------
# Max country-goal-year observation count within each goal-year. Descriptive-
# companion denominator ("share of the top reporter") for
# dv_n_observations_pct_frontier.
frontier <- raw_data %>%
  filter(!is.na(value)) %>%
  count(geo_area_code, year, goal, name = "n_observations") %>%
  group_by(year, goal) %>%
  summarise(frontier_max = max(n_observations), .groups = "drop")


# =============================================================================
# E. PRIMARY OUTCOME PANEL (observation counts within goals) ==================
# =============================================================================
# Each observation is one data point: a country reporting national + urban +
# rural rows contributes 3 to that goal's count, not 1. Section F has the
# coarser series-code views for robustness.

# ---- E1. Goal-level DV panel: goal_lvl_dv_data ------------------------------
# Grain: one row per country x year x goal. Built on a full scaffold, so a
# country-goal-year that reported nothing shows a genuine 0, not a missing row.
#
# All counts come from ONE pass over raw_data (.dv_counts): each column counts
# the rows meeting its own condition, so they all come from the same rows and a
# new breakdown is one more line, not another join. No rows are removed.
#
#   n_observations          reported observations (empty cells not counted)
#   n_observations_country  of those, the country produced it (nature C/CA)
#   n_observations_agency   of those, an agency produced it   (nature E/M/G)
#   n_observations_stable   of those, in the framework-stable core (D0)
#   n_declared_missing      empty cells the UN opened here (split by reason)
#
# The country/agency split is the key test: if backsliding cuts a country's own
# reporting while agencies backfill it, n_observations can stay flat while
# n_observations_country falls. (They need not sum to n_observations — 0.05% of
# rows carry no nature code.)
#
# The _pct_* columns (added after the join below) put each goal on a comparable
# scale by dividing by a denominator. See D6 / D6b / D7 for the three choices.
.dv_counts <- raw_data %>%
  group_by(geo_area_code, geo_area_name, year, goal) %>%
  summarise(
    n_observations         = sum(!is.na(value)),
    n_observations_country = sum(!is.na(value) & nature %in% c("C", "CA")),
    n_observations_agency  = sum(!is.na(value) & nature %in% c("E", "M", "G")),
    n_observations_stable  = sum(!is.na(value) & series_code %in% stable_codes),
    n_declared_missing     = sum(is.na(value)),
    # The declared-missing total split by WHY (missing_reason, derived in C1).
    # These four sum to n_declared_missing. `structural` is the one to watch:
    # it is non-applicability, not data loss, so it arguably belongs out of the
    # denominator. `suppressed` is the sharpest form of the outcome.
    n_missing_structural   = sum(is.na(value) & missing_reason == "structural"),
    n_missing_suppressed   = sum(is.na(value) & missing_reason == "suppressed"),
    n_missing_unknown      = sum(is.na(value) & missing_reason == "unknown"),
    .groups = "drop"
  )

goal_lvl_dv_data <- expand_grid(
    countries,
    year = start_year:end_year,
    goal = goals
  ) %>%
  left_join(.dv_counts, by = c("geo_area_code", "geo_area_name", "year", "goal")) %>%
  # A country-goal-year with no rows at all is a genuine zero, not unknown.
  mutate(across(c(n_observations, n_observations_country, n_observations_agency,
                  n_observations_stable, n_declared_missing,
                  n_missing_structural, n_missing_suppressed, n_missing_unknown),
                ~ coalesce(.x, 0L))) %>%
  left_join(baseline, by = c("geo_area_code", "geo_area_name", "goal")) %>%
  left_join(goal_baseline, by = "goal") %>%
  left_join(frontier, by = c("year", "goal")) %>%
  mutate(
    # Divided by THIS country's own 2015-17 mean for the goal. NA for the ~90
    # country-goals that reported nothing at baseline (denominator 0).
    dv_n_observations_pct_baseline = if_else(baseline_mean_all > 0,
                                          n_observations / baseline_mean_all,
                                          NA_real_),
    dv_n_observations_stable_pct_baseline = if_else(baseline_mean_stable > 0,
                                          n_observations_stable / baseline_mean_stable,
                                          NA_real_),
    # Divided by the mean across ALL countries for the goal in 2015-17 (D6b).
    # Denominator never 0, so defined for every country-goal-year — the companion
    # that keeps late-starting reporters in the analysis.
    dv_n_observations_pct_goalbase = if_else(goal_baseline_all > 0,
                                          n_observations / goal_baseline_all,
                                          NA_real_),
    dv_n_observations_stable_pct_goalbase = if_else(goal_baseline_stable > 0,
                                          n_observations_stable / goal_baseline_stable,
                                          NA_real_),
    # "vs the top reporter that year": descriptive companion; denominator moves
    # year to year, so weaker for causal identification.
    dv_n_observations_pct_frontier = if_else(frontier_max > 0,
                                          n_observations / frontier_max,
                                          NA_real_)
  ) %>%
  select(-baseline_mean_all, -baseline_mean_stable,
         -goal_baseline_all, -goal_baseline_stable, -frontier_max) %>%
  arrange(geo_area_name, year, goal)

# Variable labels (attr "label") documenting the series universe behind each
# outcome column — in particular the series COUNT feeding the all-series vs
# stable-core columns, computed live so they never go stale. readr::write_csv
# drops attributes, so these survive only in the .rds twin written below (and
# in-session, e.g. RStudio's viewer / Hmisc / labelled / gtsummary).
attr(goal_lvl_dv_data$n_observations, "label") <-
  sprintf("Observation count — all %d series", agg_series_total)
attr(goal_lvl_dv_data$n_observations_country, "label") <-
  "Observation count — country-produced only (nature C/CA)"
attr(goal_lvl_dv_data$n_observations_agency, "label") <-
  "Observation count — agency-produced only (nature E/M/G)"
attr(goal_lvl_dv_data$n_declared_missing, "label") <-
  "Rows the UN opened for this country-goal-year and left empty (value was NaN)"
attr(goal_lvl_dv_data$n_missing_structural, "label") <-
  "Declared-missing: indicator not applicable (Nature N / Obs Status M)"
attr(goal_lvl_dv_data$n_missing_suppressed, "label") <-
  "Declared-missing: withheld (Obs Status Q)"
attr(goal_lvl_dv_data$n_missing_unknown, "label") <-
  "Declared-missing: reason not recoverable (Obs Status O, or neither field populated)"
attr(goal_lvl_dv_data$n_observations_stable, "label") <-
  sprintf("Observation count — %d framework-stable series", length(stable_codes))
attr(goal_lvl_dv_data$dv_n_observations_pct_baseline, "label") <-
  "n_observations / THIS country's own mean for this goal in 2015-17 (all series). NA if that baseline is 0"
attr(goal_lvl_dv_data$dv_n_observations_stable_pct_baseline, "label") <-
  "n_observations_stable / THIS country's own mean for this goal in 2015-17 (stable core). NA if that baseline is 0"
attr(goal_lvl_dv_data$dv_n_observations_pct_goalbase, "label") <-
  "n_observations / mean across ALL countries for this goal in 2015-17 (all series). Defined for every country-goal-year"
attr(goal_lvl_dv_data$dv_n_observations_stable_pct_goalbase, "label") <-
  "n_observations_stable / mean across ALL countries for this goal in 2015-17 (stable core). Defined for every country-goal-year"
attr(goal_lvl_dv_data$dv_n_observations_pct_frontier, "label") <-
  "vs TOP reporter: n_observations / goal-year max (all series). Denominator moves yearly"

write_csv(
  goal_lvl_dv_data,
  file.path(output_folder, "goal_lvl_dv_data.csv")
)
# .rds twin preserves the variable labels above (CSV cannot).
saveRDS(goal_lvl_dv_data, file.path(output_folder, "goal_lvl_dv_data.rds"))


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
#   n_declared_missing — slots the UN opened here and left empty.
#   reported           — TRUE if at least one published value exists. A cell
#                        that is ALL declared-missing is NOT reported, and F2
#                        must not count it as an available series.
agg_series_depth <- raw_data %>%
  group_by(goal, geo_area_code, geo_area_name, iso3, year, series_code) %>%
  summarise(
    nature_codes       = na_if(paste(sort(unique(nature[!is.na(value)])),
                                     collapse = "/"), ""),
    n_disagg_rows      = sum(!is.na(value)),
    n_country_rows     = sum(!is.na(value) & nature %in% c("C", "CA")),
    n_agency_rows      = sum(!is.na(value) & nature %in% c("E", "M", "G")),
    n_declared_missing = sum(is.na(value)),
    # Split of n_declared_missing by missing_reason (C1). `applicable` is the
    # useful one: TRUE unless every empty row here is structural non-relevance,
    # i.e. the series genuinely does not apply to this country-year.
    n_missing_structural  = sum(is.na(value) & missing_reason == "structural"),
    n_missing_suppressed  = sum(is.na(value) & missing_reason == "suppressed"),
    reported           = any(!is.na(value)),
    reported_country   = any(!is.na(value) & nature %in% c("C", "CA")),
    applicable         = any(!is.na(value) | missing_reason != "structural"),
    .groups = "drop"
  ) %>%
  arrange(goal, geo_area_name, year, series_code)

# ---- F1b. Disaggregation-depth denominators ---------------------------------
# n_disagg_rows says HOW MANY disaggregation combos a country reported for a
# series in a year. To compare that across countries it needs a per-series
# ceiling. Two are provided (identical for ~96% of series):
#
#   depth_frontier — the most any single country-year reported for the series.
#                    Demonstrably attainable (a real country hit it), so it is
#                    the PRIMARY denominator. dv_depth_pct_frontier is in [0, 1].
#   depth_union    — every distinct disaggregation combo (age x sex x location x
#                    units) ever seen for the series, pooled across all country-
#                    years. Wider, because it pools mutually exclusive survey
#                    designs (e.g. incompatible age bands), so no single country
#                    can reach it — a ROBUSTNESS ceiling only.
#
# Both are per-series constants. depth_union is floored at depth_frontier so it
# is never smaller than the largest single realization; this also handles series
# whose depth lives in a DROPPED specialty column (e.g. EN_REF_WASCOL is one row
# per city), where the age/sex/location/units combo count is 1 but n_disagg_rows
# is large — there, union falls back to the frontier.
depth_frontier <- agg_series_depth %>%
  group_by(series_code) %>%
  summarise(depth_frontier = max(n_disagg_rows), .groups = "drop")

depth_union <- raw_data %>%
  filter(!is.na(value)) %>%
  distinct(series_code, age, sex, location, units) %>%
  count(series_code, name = "depth_union_combos") %>%
  left_join(depth_frontier, by = "series_code") %>%
  transmute(series_code,
            depth_union = pmax(depth_union_combos, depth_frontier))

agg_series_depth <- agg_series_depth %>%
  left_join(depth_frontier, by = "series_code") %>%
  left_join(depth_union,    by = "series_code") %>%
  mutate(
    # Share of the series' demonstrated maximum depth this country reached here.
    dv_depth_pct_frontier = if_else(depth_frontier > 0,
                                 n_disagg_rows / depth_frontier, NA_real_),
    # Same, against the wider union ceiling (robustness).
    dv_depth_pct_union    = if_else(depth_union > 0,
                                 n_disagg_rows / depth_union, NA_real_)
  )

write_csv(
  agg_series_depth,
  file.path(output_folder, "agg_series_depth.csv.gz")
)
# .rds twin carries the column labels below (write_csv drops attributes).
attr(agg_series_depth$n_disagg_rows, "label") <-
  "Disaggregation combos this country reported for the series-year (published rows)"
attr(agg_series_depth$depth_frontier, "label") <-
  "Per-series ceiling: most any single country-year reported (attainable)"
attr(agg_series_depth$depth_union, "label") <-
  "Per-series ceiling: all combos ever seen for the series, pooled (robustness)"
attr(agg_series_depth$dv_depth_pct_frontier, "label") <-
  "n_disagg_rows / depth_frontier — share of attainable depth reached, in [0,1]"
attr(agg_series_depth$dv_depth_pct_union, "label") <-
  "n_disagg_rows / depth_union — share of the union ceiling reached, in [0,1]"
saveRDS(agg_series_depth, file.path(output_folder, "agg_series_depth.rds"))


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
        group_by(geo_area_code, year, goal) %>%
        summarise(n_available_series         = sum(reported),
                  n_available_series_country = sum(reported_country),
                  # Series the UN treats as applicable here (F1 `applicable`),
                  # i.e. excluding those flagged structurally non-relevant. An
                  # alternative, country-specific denominator.
                  n_applicable_series        = sum(applicable),
                  .groups = "drop"),
      by = c("geo_area_code", "year", "goal")
    ) %>%
    left_join(goal_totals, by = "goal") %>%
    transmute(
      geo_area_code, geo_area_name, iso3, year,
      scope = "goal",
      goal,
      n_available_series         = coalesce(n_available_series, 0L),
      n_available_series_country = coalesce(n_available_series_country, 0L),
      n_applicable_series        = coalesce(n_applicable_series, 0L),
      n_series_in_framework      = n_series_in_goal
    ),

  # -- overall scope --
  expand_grid(countries, year = start_year:end_year) %>%
    left_join(
      agg_series_depth %>%
        group_by(geo_area_code, geo_area_name, year, series_code) %>%
        summarise(rep = any(reported), rep_c = any(reported_country),
                  appl = any(applicable), .groups = "drop") %>%
        group_by(geo_area_code, geo_area_name, year) %>%
        summarise(n_available_series         = sum(rep),
                  n_available_series_country = sum(rep_c),
                  n_applicable_series        = sum(appl),
                  .groups = "drop"),
      by = c("geo_area_code", "geo_area_name", "year")
    ) %>%
    transmute(
      geo_area_code, geo_area_name, iso3, year,
      scope = "overall",
      goal  = NA_integer_,
      n_available_series         = coalesce(n_available_series, 0L),
      n_available_series_country = coalesce(n_available_series_country, 0L),
      n_applicable_series        = coalesce(n_applicable_series, 0L),
      n_series_in_framework      = agg_series_total
    )) %>%
  mutate(
    missing_series_count = n_series_in_framework - n_available_series,
    dv_availability_share   = n_available_series / n_series_in_framework,
    dv_missingness_share    = 1 - dv_availability_share
  ) %>%
  arrange(geo_area_name, year, scope, goal)

write_csv(
  agg_series_counts_rc,
  file.path(output_folder, "agg_series_counts_rc.csv"))


# =============================================================================
# G. QUALITY CHECKS ===========================================================
# =============================================================================
message("\nFinished.")
message("Retained rows: ", nrow(raw_data),
        " (published values: ", sum(!is.na(raw_data$value)),
        " | declared missing: ", sum(is.na(raw_data$value)), ")")
message("Unique countries/territories retained: ", n_distinct(countries$geo_area_code))
message("  (after excluding ",
        sum(geo_exclusions$disposition == "excluded" & geo_exclusions$n_observations > 0),
        " and rolling up ", sum(geo_exclusions$disposition == "rolled up"),
        " geographies; see geo_exclusions.csv)")
message("Unique series across all exports: ", agg_series_total)

message("\nSeries per goal in downloaded files:")
print(goal_totals)

message("\nSeries stability (see D0):")
message("  stable-core series: ", length(stable_codes), " of ", nrow(series_stability),
        " (", round(100 * length(stable_codes) / nrow(series_stability)), "%)")
message("  observation mass in stable core: ",
        round(100 * sum(raw_data$series_code[!is.na(raw_data$value)] %in% stable_codes) /
                sum(!is.na(raw_data$value)), 1), "%")

message("\nPanel row counts:")
message("  goal_lvl_dv_data (PRIMARY): ", nrow(goal_lvl_dv_data))
message("  agg_series_counts_rc (robustness, both scopes): ", nrow(agg_series_counts_rc))
message("    of which scope == 'goal': ", sum(agg_series_counts_rc$scope == "goal"))
message("    of which scope == 'overall': ", sum(agg_series_counts_rc$scope == "overall"))
message("  agg_series_depth (supplementary): ", nrow(agg_series_depth))

message("\nBaseline window for pct_baseline: ",paste(range(baseline_years), collapse = "-"))

