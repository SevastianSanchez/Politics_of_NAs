# ==============================================================================
# build_country_covariates.R
#
# The country-level variables the index is compared against, pulled from their
# original public sources. Replaces the frozen copy of the Politics of NAs
# panel the repo used to borrow, so the index owns its inputs.
#
#   income_level                 World Bank historical income classification
#                                (OGHIST.xlsx), by the calendar year the data
#                                cover; income codes expanded to labels
#   country_name                 the UN's names, from the cleaned SDG data
#   gdp_pc                       GDP per capita, current US$ (WDI NY.GDP.PCAP.CD),
#                                from the World Bank Data360 API
#   spi_overall, spi_overall_mod World Bank Statistical Performance Indicators,
#                                from the SPI snapshot already in the repo.
#                                spi_overall is the published index (mean of all
#                                5 pillars); spi_overall_mod drops pillar 3, which
#                                scores SDG availability from the same UN database
#                                as the index, and averages pillars 1, 2, 4, 5
#
# SNAPSHOTS (the technique from the paper repo's build_predictor_panel.R):
# each live source is written once to 01_data/raw/snapshots/<name>__<date>.csv
# with a row in _manifest.csv, and read from the newest snapshot after that, so
# a rebuild is reproducible. REFRESH=1 re-pulls and writes a new dated snapshot.
#
# OUTPUT  01_data/processed/country_covariates.csv
#         one row per iso3 x year for the index's 197 countries, 2015-2023
# RUN     Rscript 02_processing/build_country_covariates.R     (REFRESH=1 to re-pull)
# ==============================================================================
suppressPackageStartupMessages({library(data.table); library(here); library(jsonlite)})

REFRESH <- identical(Sys.getenv("REFRESH"), "1")
snap_dir <- here("01_data/raw/snapshots")
manifest <- file.path(snap_dir, "_manifest.csv")
years    <- 2015:2023
say <- function(...) cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), ..., "\n", sep = "")

# Read the newest dated snapshot of `name`, or pull it with `pull_fn` and save one.
snap <- function(name, pull_fn) {
  have <- sort(list.files(snap_dir, pattern = paste0("^", name, "__\\d{4}-\\d{2}-\\d{2}\\.csv$"),
                          full.names = TRUE), decreasing = TRUE)
  if (!REFRESH && length(have)) { say("[snapshot] ", name, " <- ", basename(have[1])); return(fread(have[1])) }
  say("[snapshot] ", name, ": pulling live")
  d   <- as.data.table(pull_fn())
  out <- file.path(snap_dir, paste0(name, "__", format(Sys.Date()), ".csv"))
  fwrite(d, out)
  row <- data.table(source = name, file = basename(out), pulled = format(Sys.Date()),
                    rows = nrow(d), cols = ncol(d))
  m <- if (file.exists(manifest)) fread(manifest, colClasses = "character") else NULL
  fwrite(rbind(m, row[, lapply(.SD, as.character)], fill = TRUE), manifest)
  say("[snapshot] wrote ", basename(out), " (", nrow(d), " rows)")
  d
}

# ---- income classification and names: World Bank OGHIST.xlsx --------------------
pull_income <- function() {
  url <- "https://datacatalogfiles.worldbank.org/ddh-published/0037712/DR0090754/OGHIST.xlsx"
  tf  <- tempfile(fileext = ".xlsx"); download.file(url, tf, mode = "wb", quiet = TRUE)
  x   <- readxl::read_excel(tf, sheet = "Country Analytical History", col_names = FALSE, .name_repair = "minimal")
  yr_row <- which(x[[2]] == "Data for calendar year :")
  yrs <- suppressWarnings(as.integer(unlist(x[yr_row, ])))
  body <- x[grepl("^[A-Z]{3}$", x[[1]]), ]
  keep <- which(!is.na(yrs))
  rbindlist(lapply(keep, function(j) data.table(iso3 = body[[1]], country_name = body[[2]],
                                                 year = yrs[j], income_code = body[[j]])))
}
inc <- snap("income", pull_income)

# ---- GDP per capita, current US$: World Bank Data360 API -----------------------
pull_gdp <- function() {
  base <- paste0("https://data360api.worldbank.org/data360/data?DATABASE_ID=WB_WDI",
                 "&INDICATOR=WB_WDI_NY_GDP_PCAP_CD&timePeriodFrom=", min(years),
                 "&timePeriodTo=", max(years))
  out <- list(); skip <- 0
  repeat {
    r <- fromJSON(paste0(base, "&skip=", skip))
    if (!length(r$value)) break
    out[[length(out) + 1]] <- as.data.table(r$value)[, .(iso3 = REF_AREA, year = as.integer(TIME_PERIOD),
                                                          gdp_pc = as.numeric(OBS_VALUE))]
    skip <- skip + nrow(r$value)
    if (skip >= r$count) break
  }
  rbindlist(out)
}
gdp <- snap("gdp_pc", pull_gdp)

# ---- SPI: newest snapshot already in the repo ----------------------------------
spi_file <- sort(list.files(snap_dir, pattern = "^spi__\\d{4}-\\d{2}-\\d{2}\\.csv$", full.names = TRUE),
                 decreasing = TRUE)[1]
say("[snapshot] spi <- ", basename(spi_file))
spi <- fread(spi_file)[, .(iso3 = iso3c, year = as.integer(date),
                           spi_overall = SPI.INDEX,
                           spi_overall_mod = rowMeans(cbind(SPI.INDEX.PIL1, SPI.INDEX.PIL2,
                                                            SPI.INDEX.PIL4, SPI.INDEX.PIL5)))]

# ---- assemble on the index's own country-years -----------------------------------
cy  <- unique(fread(here("01_data/vsi_scores/vsi/irt_vsi_scores.csv"))[, .(iso3, year)])
lab <- c(L = "Low income", LM = "Lower-middle income", UM = "Upper-middle income", H = "High income")
inc[, income_level := unname(lab[income_code])]
# Names: the UN's own (geo_area_name in the cleaned SDG data), so they match the
# source the index is built from; World Bank names only where the UN has none.
un  <- unique(fread(here("01_data/processed/raw_data.csv.gz"),
                    select = c("iso3", "geo_area_name"))[!is.na(iso3)])[, .SD[1], by = iso3]
wb  <- inc[, .(wb_name = country_name[!is.na(country_name)][1]), by = iso3]
nm  <- merge(un[, .(iso3, country_name = geo_area_name)], wb, by = "iso3", all = TRUE)
nm[is.na(country_name), country_name := wb_name][, wb_name := NULL]

cov <- merge(cy, nm, by = "iso3", all.x = TRUE)
cov <- merge(cov, inc[, .(iso3, year, income_level)], by = c("iso3", "year"), all.x = TRUE)
cov <- merge(cov, gdp, by = c("iso3", "year"), all.x = TRUE)
cov <- merge(cov, spi, by = c("iso3", "year"), all.x = TRUE)
cov[is.na(country_name), country_name := countrycode::countrycode(iso3, "iso3c", "country.name", warn = FALSE)]
cov[is.na(country_name), country_name := iso3]
cov[is.na(income_level), income_level := "Unclassified"]
setcolorder(cov, c("iso3", "year", "country_name", "income_level", "gdp_pc", "spi_overall", "spi_overall_mod"))
fwrite(cov[order(iso3, year)], here("01_data/processed/country_covariates.csv"))

say("wrote 01_data/processed/country_covariates.csv | ", nrow(cov), " country-years | ",
    "unclassified ", cov[income_level == "Unclassified", .N], " | gdp missing ", cov[is.na(gdp_pc), .N],
    " | spi missing ", cov[is.na(spi_overall), .N])
