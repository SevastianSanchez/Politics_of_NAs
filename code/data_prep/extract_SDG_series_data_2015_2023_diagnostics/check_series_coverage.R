# =============================================================================
# DIAGNOSTIC: Series coverage check
# Companion to code/data_prep/extract_SDG_series_data_2015_2023.r
# =============================================================================
#
# WHY THIS EXISTS
# ---------------
# The cleaned data has fewer unique series codes than the UN SDG series registry
# (currently 665 in raw_data vs ~713 in the registry). This script confirms that
# the gap is expected, not a broken or truncated download.
#
# THE ANSWER (first verified 2026-08-20; re-run for current figures)
# ------------------------------------------------------------------
# The "missing" series are published ONLY as global totals, regional groupings,
# or non-country spatial units (e.g. Large Marine Ecosystems). They have no
# country-level observations, so they cannot appear in a country x series x year
# panel. Examples:
#   - Goal 13 climate finance (DC_FIN_*) and Paris reporting -> World totals
#   - Goal 6 water governance (ER_H2O_*) -> "proportion of countries" globals
#   - Goal 14 coastal eutrophication (EN_MAR_*) -> per marine ecosystem
#   - Goal 12 material footprint / food loss -> regional aggregates
#
# So the country-reportable count is correct; nothing was accidentally dropped.
#
# READ-ONLY: reads the cleaned output and the UN API, prints a report, writes
# nothing. Requires internet (queries the official UN SDG API).
# =============================================================================

suppressPackageStartupMessages({
  library(readr); library(dplyr); library(jsonlite)
})

# ---- Paths -------------------------------------------------------------------
# Run from the project root. raw_data.csv.gz is written by the extract script.
raw_data_path <- "data/clean/raw_data.csv.gz"
stopifnot(file.exists(raw_data_path))


# ---- 1. Series codes and country codes we actually have ---------------------
our_data <- read_csv(raw_data_path,
                     col_types = cols(.default = col_character()),
                     progress = FALSE)

have_codes <- sort(unique(our_data$series_code))

# The set of geographies that survived cleaning as real reporting units. Used
# in step 5 as the reference for "is this a country our panel would include?"
our_geo_codes <- unique(our_data$geo_area_code)


# ---- 2. Authoritative UN series registry ------------------------------------
# Small helper: fetch JSON with a longer timeout and a clear message if the
# UN API is unreachable, rather than a raw connection-error stack trace.
fetch_json <- function(url, seconds = 120) {
  old <- options(timeout = seconds); on.exit(options(old))
  tryCatch(fromJSON(url), error = function(e) {
    stop("Could not reach the UN SDG API (", conditionMessage(e), ").\n",
         "This is usually a transient network issue — try again in a moment.",
         call. = FALSE)
  })
}

un <- fetch_json("https://unstats.un.org/sdgapi/v1/sdg/Series/List")

# `goal` is a list-column: a series can map to more than one goal. Take the
# first goal for grouping purposes.
un$goal_first <- as.integer(vapply(un$goal, function(x) x[[1]], character(1)))
un_codes <- sort(unique(un$code))


# ---- 3. The diff -------------------------------------------------------------
missing <- setdiff(un_codes, have_codes)   # UN registry has, our data lacks
extra   <- setdiff(have_codes, un_codes)   # our data has, registry does not list

cat("UN registry series:", length(un_codes), "\n")
cat("Series in our data:", length(have_codes), "\n")
cat("Missing from our data:", length(missing), "\n")
cat("Extra in our data (should be 0):", length(extra), "\n\n")


# ---- 4. Missing series, grouped by goal -------------------------------------
missing_tbl <- un[un$code %in% missing, c("goal_first", "code", "description")]
missing_tbl <- missing_tbl[order(missing_tbl$goal_first, missing_tbl$code), ]

cat("=== Missing series count by goal ===\n")
print(as.data.frame(
  missing_tbl %>% count(goal_first, name = "n_missing") %>% arrange(goal_first)
))

cat("\n=== All missing series (goal, code, description) ===\n")
missing_tbl$description <- substr(missing_tbl$description, 1, 70)
print(missing_tbl, row.names = FALSE)


# ---- 5. Spot-check: confirm the missing series are non-country ---------------
# For a few representative missing series, count how many of their observations
# fall on a geography our panel actually includes (our_geo_codes). This is the
# honest test: if that count is 0, the series simply has no country data and
# correctly cannot appear in our panel. (A naive "M49 code < 900" test would be
# wrong here, because regional aggregates like World=1 or Africa=2 also have
# small codes.)
cat("\n=== Spot-check: do sample missing series report for any of our countries? ===\n")
spot_check <- function(code) {
  url <- paste0("https://unstats.un.org/sdgapi/v1/sdg/Series/Data",
                "?seriesCode=", code, "&pageSize=2000")
  d <- tryCatch(fetch_json(url), error = function(e) NULL)
  if (is.null(d) || is.null(d$data) || length(d$data) == 0) {
    cat(sprintf("%-16s no data returned\n", code)); return(invisible())
  }
  on_our_countries <- sum(as.character(d$data$geoAreaCode) %in% our_geo_codes)
  cat(sprintf("%-16s obs=%-5d obs on our countries=%-4d sample geos: %s\n",
              code, nrow(d$data), on_our_countries,
              paste(head(unique(d$data$geoAreaName), 3), collapse = "; ")))
}
for (code in c("ER_H2O_IWRMP", "DC_FIN_TOT", "EN_MAR_TN", "AG_FLS_PCT", "EN_ADAP_COM")) {
  spot_check(code)
}

cat("\n'obs on our countries' = 0 confirms the gap is structural: these series\n")
cat("have no country-level data and correctly do not appear in the panel.\n")
