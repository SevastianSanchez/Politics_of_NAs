# ==============================================================================
# build_hrv_snapshot.R
#
# Turns the HRV2 transparency index release into a small tracked snapshot.
#
# WHY A SCRIPT  The authors publish HRV2 only as a 360 MB .RData holding the
#   full JAGS posterior (the `results` object alone is 280 MB). That file is far
#   too large to track, and all this project needs from it is 5,052 country-year
#   rows. This script does the extraction so the snapshot is reproducible
#   without keeping the download.
#
# SOURCE  https://hrvtransparency.org/wp-content/uploads/HRV2/HRV2ExpandedCntriesExtracted.RData
#   Download it yourself and pass the path, or set HRV2_RDATA. It is NOT
#   downloaded automatically and NOT committed.
#   Do not confuse it with HRV2013.dta / TransparencyIndex2013.RData on the same
#   page: those are the ORIGINAL index, 125 countries, 1980-2010.
#
# CITE  Hollyer, Ge, Rosendorff & Vreeland (2024), "Measuring Transparency,
#   Again: Updating and Extending the HRV Transparency Index."
#   Original: Hollyer, Rosendorff & Vreeland (2014), Political Analysis 22(1).
#
# COVERAGE WARNING  HRV2 ends in 2015 and this project's panel starts in 2015,
#   so exactly ONE year overlaps. It supports a cross-sectional check at 2015
#   and nothing longitudinal.
#
# OUTPUT  data/01_source/snapshots/hrv__<date>.csv  (iso3, year, hrv, hrv_lb,
#         hrv_ub, hrv_sd, country) and a row appended to _manifest.csv
# ==============================================================================
suppressPackageStartupMessages({library(data.table); library(here)})

rdata <- Sys.getenv("HRV2_RDATA", unset = NA_character_)
if (is.na(rdata)) {
  args <- commandArgs(trailingOnly = TRUE)
  rdata <- if (length(args)) args[1] else NA_character_
}
if (is.na(rdata) || !file.exists(rdata))
  stop("Pass the path to HRV2ExpandedCntriesExtracted.RData as the first ",
       "argument or in HRV2_RDATA. See the header for the download URL.",
       call. = FALSE)

# loaded into its own environment: the file also carries a 280 MB rjags object
# and several loose loop variables (j, k, n) that would clobber the session
e <- new.env()
load(rdata, envir = e)
if (!"TransparencyData" %in% ls(e))
  stop("TransparencyData not found in ", basename(rdata),
       " -- is this the HRV2 release?", call. = FALSE)

td <- as.data.table(get("TransparencyData", envir = e))
rm(e); invisible(gc())

# `ccode` is already ISO3 despite the name; `Country` is a factor
hrv <- td[, .(iso3    = as.character(ccode),
              year    = as.integer(year),
              hrv     = transparencyindex,
              hrv_lb  = transparencyindexlb,
              hrv_ub  = transparencyindexub,
              hrv_sd  = transparencyindexsd,
              country = as.character(Country))]
setorder(hrv, iso3, year)

stopifnot(!anyNA(hrv$iso3), all(nchar(hrv$iso3) == 3), !anyNA(hrv$hrv),
          hrv[, all(hrv_lb <= hrv & hrv <= hrv_ub)])
cat("HRV2: ", nrow(hrv), " country-years | ", uniqueN(hrv$iso3), " countries | ",
    paste(range(hrv$year), collapse = "-"), "\n", sep = "")

stamp <- format(Sys.Date())
out   <- here(paste0("data/01_source/snapshots/hrv__", stamp, ".csv"))
fwrite(hrv, out)
cat("wrote ", basename(out), "\n", sep = "")

# a stable filename for downstream code, so nothing has to track the date
fwrite(hrv, here("data/01_source/snapshots/hrv.csv"))
cat("wrote hrv.csv (stable alias)\n")

man <- here("data/01_source/snapshots/_manifest.csv")
m <- fread(man)
# fread types the existing `pulled` column as IDate, so a character stamp
# would be coerced to NA -- match the column's type instead
m <- rbind(m[source != "hrv"], data.table(source = "hrv", file = basename(out),
  pulled = if (inherits(m$pulled, "IDate")) data.table::as.IDate(Sys.Date()) else stamp,
  rows = nrow(hrv), cols = ncol(hrv)))
fwrite(m, man)
cat("manifest updated\n")
