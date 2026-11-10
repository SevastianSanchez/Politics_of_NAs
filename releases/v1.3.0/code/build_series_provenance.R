# ==============================================================================
# build_series_provenance.R
#
# Who produced each series: the country, or the custodian agency?
#
# The UN Global Database carries a `Nature` code on every observation:
#   C  country data          CA country data, adjusted
#   E  estimated             M  modelled        G  global monitoring
#   N  non-relevant
# C and CA are the country's own figure. The rest are produced by the custodian
# agency, sometimes with imputation for missing values -- FAO's indicator 2.a.1
# series say so in the Source field outright.
#
# This matters because "reported" means something different in each case. For a
# country-produced series it records a country's choice. For an agency-estimated
# one it largely records whether the agency published, which is the reason goals
# 6 and 15 are held out on content grounds (see CLAUDE.md).
#
# FOR DISCLOSURE, NOT FILTERING. Nothing is dropped on provenance. The share is
# printed alongside each goal score so a reader can weigh it. Modelling
# provenance properly is the v2 design, not a v1 gate.
#
# OUTPUT  output/measure/tables/series_provenance_nature.csv
#           one row per series: how many non-missing observations it has and
#           what share carry each Nature code.
# ==============================================================================
suppressMessages({library(readxl); library(data.table); library(here)})
msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), ..., "\n", sep = "")

f <- list.files(here("data/01_source/un_sdg_exports"),
                pattern = "^Goal.*\\.xlsx$", full.names = TRUE)
if (!length(f)) stop("no UN goal exports found in data/01_source/un_sdg_exports")
msg("reading ", length(f), " goal exports")

nat <- rbindlist(lapply(f, function(x) {
  d <- as.data.table(read_excel(x, col_types = "text"))
  if (!all(c("SeriesCode", "Value") %in% names(d))) return(NULL)
  if (!"Nature" %in% names(d)) d[, Nature := NA_character_]
  d[!is.na(Value) & Value != "", .(SeriesCode, Nature)]
}), fill = TRUE)
nat[is.na(Nature) | Nature == "", Nature := "(blank)"]

per <- nat[, .(obs    = .N,
               pct_C  = round(100 * mean(Nature %in% c("C", "CA")), 1),
               pct_E  = round(100 * mean(Nature == "E"), 1),
               pct_M  = round(100 * mean(Nature == "M"), 1),
               pct_G  = round(100 * mean(Nature == "G"), 1),
               pct_other = round(100 * mean(!Nature %in% c("C","CA","E","M","G")), 1)),
           by = SeriesCode]
per[, mostly_country := pct_C >= 50]
setorder(per, -pct_C)

out <- here("output/measure/tables")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
fwrite(per, file.path(out, "series_provenance_nature.csv"))

msg("series: ", nrow(per), " | mostly country-produced: ", sum(per$mostly_country),
    " (", round(100 * mean(per$mostly_country), 1), "%)")
print(nat[, .(share_of_obs = round(100 * .N / nrow(nat), 1)), by = Nature][order(-share_of_obs)])
msg("done.")
