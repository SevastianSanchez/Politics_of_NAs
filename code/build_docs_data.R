# ==============================================================================
# build_docs_data.R
#
# Emits the JSON and CSV that the GitHub Pages landing page (docs/index.html)
# reads. Run after the overall fit; the page is static otherwise.
#
# The published measure is the World on Record Index (TWR): one overall score
# per country-year. Column names here are the PUBLIC ones and should match the
# data dictionary -- `twr` and `twr_se`, not the internal `theta` / `se`.
#
# INPUT   data/02_measure/irt_scores_1d.rds   (composite scores)
#         data/03_panels/analysis_data.rds    (country names, income groups)
# OUTPUT  docs/twr_scores.json, docs/twr_scores.csv
# ==============================================================================

suppressPackageStartupMessages({library(data.table); library(here); library(jsonlite)})

s <- as.data.table(readRDS(here("data/02_measure/irt_scores_1d.rds")))
a <- as.data.table(readRDS(here("data/03_panels/analysis_data.rds")))

meta <- unique(a[, .(iso3, country_name, income_level)])
meta <- meta[!is.na(iso3)][, .SD[1], by = iso3]

s <- merge(s, meta, by = "iso3", all.x = TRUE)
s[is.na(country_name), country_name := iso3]
s[is.na(income_level) | income_level == "", income_level := "Unclassified"]

# expand World Bank codes into labels a reader can scan
inc_lab <- c(H = "High income", UM = "Upper-middle income",
             LM = "Lower-middle income", L = "Low income")
s[income_level %in% names(inc_lab), income_level := inc_lab[income_level]]

rows <- s[, .(iso = iso3, name = country_name, inc = income_level, yr = year,
              sc = round(theta, 3), se = round(se, 3))]
setorder(rows, iso, yr)

yearly <- s[, .(yr = year[1], mean = round(mean(theta), 4), n = .N), by = year][, -1]
setorder(yearly, yr)

log1 <- fread(here("data/02_measure/irt_run_log_1d.csv"))

out <- list(
  generated   = format(Sys.time(), "%Y-%m-%d"),
  n_countries = uniqueN(s$iso3),
  years       = range(s$year),
  n_items     = log1$n_items[1],
  n_rows      = nrow(s),
  converged   = log1$converged[1],
  cycles      = log1$cycles[1],
  median_se   = log1$median_se[1],
  yearly      = yearly,
  rows        = rows)

writeLines(toJSON(out, auto_unbox = TRUE, dataframe = "rows", digits = NA),
           here("docs/twr_scores.json"))
cat("wrote docs/twr_scores.json |", nrow(rows), "rows |",
    uniqueN(s$iso3), "countries\n")

# the downloadable copy the page links to, so docs/ is self-contained
fwrite(s[, .(iso3, country_name, income_level, year,
             twr = round(theta, 4), twr_se = round(se, 4))][
         order(iso3, year)],
       here("docs/twr_scores.csv"))
cat("wrote docs/twr_scores.csv\n")
