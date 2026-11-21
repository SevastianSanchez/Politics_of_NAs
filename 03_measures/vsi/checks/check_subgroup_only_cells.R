# ==============================================================================
# check_subgroup_only_cells.R
#
# How often is a series "reported" for a country-year only through subgroup
# values (female only, urban only, ...) with no headline total?
#
# WHY IT MATTERS
#   A cell counts as reported when at least one published value exists under
#   any breakdown (functions/irt_prep.R, via agg_series_depth$reported). This
#   check sizes what a stricter "headline total required" rule would change,
#   and is the source of the figures in the measurement paper's Appendix A
#   notes (cited 20 Nov 2026).
#
# DEFINITION OF A HEADLINE ROW
#   sex is BOTHSEX or not applicable (NA), AND location is ALLAREA or NA.
#   Age is ignored: each series has its own headline age (under-5 for
#   stunting, 15+ for literacy), and ALLAGE is rare. Breakdowns other than
#   sex, age, location and units are not kept at extraction, so they cannot
#   be checked here.
#
# RESULT (20 Nov 2026)
#   450,521 reported cells; 23,137 (5.1%) have no headline row, across 92
#   series. 39 series never have one (single-group series by design, e.g.
#   maternal mortality, women in parliament). The other 53 series have a
#   headline for some countries and only subgroups for others: 3,087 cells
#   (0.7%). Hardest hit: ARG 69, PER 59, MKD 55.
#
# INPUT   01_data/processed/raw_data.csv.gz
# OUTPUT  03_measures/vsi/checks/output/subgroup_only_series.csv
#           one row per affected series: cells reported, cells with no
#           headline row, and whether the series ever has a headline
#         03_measures/vsi/checks/output/subgroup_only_summary.csv
# ==============================================================================
library(here)
library(data.table)

out_dir <- here("03_measures/vsi/checks/output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

raw <- fread(here("01_data/processed/raw_data.csv.gz"))[!is.na(value)]
raw[, headline := (is.na(sex) | sex == "BOTHSEX") &
                  (is.na(location) | location == "ALLAREA")]

cells <- raw[, .(has_headline = any(headline)),
             by = .(iso3, series_code, year)]

series <- cells[, .(cells_reported    = .N,
                    cells_no_headline = sum(!has_headline)),
                by = series_code][cells_no_headline > 0]
series[, never_has_headline := cells_no_headline == cells_reported]
series <- merge(series,
                unique(raw[, .(series_code, series_description)],
                       by = "series_code"),
                by = "series_code")
setorder(series, -cells_no_headline)

partial <- series[!(never_has_headline)]$series_code
summary <- data.table(
  measure = c("cells_reported", "cells_no_headline", "series_affected",
              "series_never_headline", "series_partial",
              "cells_no_headline_partial_series"),
  value   = c(nrow(cells), sum(!cells$has_headline), nrow(series),
              sum(series$never_has_headline), length(partial),
              cells[series_code %in% partial, sum(!has_headline)]))

fwrite(series,  file.path(out_dir, "subgroup_only_series.csv"))
fwrite(summary, file.path(out_dir, "subgroup_only_summary.csv"))
print(summary)
