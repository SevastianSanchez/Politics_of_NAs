# ==============================================================================
# validate_vsi_external.R
#
# Convergent validity for the overall index (vsi): does it agree with
# independent measures of statistical capacity built by other people from
# other data?
#
# WHAT IT USES
#   SPI  -- World Bank Statistical Performance Indicators, in the repo at
#           data/01_source/snapshots/spi__2026-11-04.csv, and already merged
#           into analysis_data as spi_overall.
#   HRV  -- Hollyer/Rosendorff/Vreeland transparency index. NOT in the repo.
#           If you add it, drop it at data/01_source/snapshots/hrv.csv with
#           columns iso3, year, hrv, and this script picks it up automatically.
#           Coverage warning: the published HRV runs 1980-2010, so it may not
#           overlap the 2015-2023 panel at all. Check before drawing anything.
#
# WHAT IT DELIBERATELY DOES NOT USE
#   V-Dem. Autocratization is the TREATMENT in this project's causal design.
#   Correlating vsi with V-Dem is the hypothesis, not a validity check, and
#   reporting it as one would be circular.
#
# CIRCULARITY WARNING on SPI pillar 3 (data products): part of it scores SDG
#   indicator availability drawn from the same UN SDG database this index is
#   built from. Treat pillar 3 agreement as partly mechanical. Pillars 4
#   (data sources: censuses, surveys, admin records) and 5 (data
#   infrastructure) are the independent comparators.
#
# OUTPUT  output/measure/tables/vsi_external_validity.csv
#         output/measure/tables/vsi_spi_disagreements.csv
#         docs/validity_spi.json   (read by the landing page)
# ==============================================================================
source(here::here("code/packages.R"))
library(here)
suppressPackageStartupMessages(library(data.table))

msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), ..., "\n", sep = "")

# ---- A. THE INDEX -----------------------------------------------------------
vsi <- fread(here("data/02_measure/irt_composite_scores.csv"))
setnames(vsi, c("composite", "composite_se"), c("vsi", "vsi_se"), skip_absent = TRUE)
msg("vsi: ", nrow(vsi), " country-years, ",
    paste(range(vsi$year), collapse = "-"))

# ---- B. SPI, OVERALL AND BY PILLAR ------------------------------------------
spi <- fread(here("data/01_source/snapshots/spi__2026-11-04.csv"))
spi[, year := as.integer(substr(as.character(date), 1, 4))]
pill <- c(spi_overall = "SPI.INDEX",
          spi_p1_use = "SPI.INDEX.PIL1", spi_p2_services = "SPI.INDEX.PIL2",
          spi_p3_products = "SPI.INDEX.PIL3", spi_p4_sources = "SPI.INDEX.PIL4",
          spi_p5_infra = "SPI.INDEX.PIL5")
pill <- pill[pill %in% names(spi)]
spi <- spi[, c("iso3c", "year", unname(pill)), with = FALSE]
setnames(spi, c("iso3c", "year", names(pill)))
setnames(spi, "iso3c", "iso3", skip_absent = TRUE)
if (!"iso3" %in% names(spi)) setnames(spi, 1, "iso3")

d <- merge(vsi, spi, by = c("iso3", "year"))
msg("merged with SPI: ", nrow(d), " country-years")

# ---- C. HRV, IF PRESENT -----------------------------------------------------
hrv_path <- here("data/01_source/snapshots/hrv.csv")
has_hrv <- file.exists(hrv_path)
if (has_hrv) {
  hrv <- fread(hrv_path)[, .(iso3, year, hrv)]
  d <- merge(d, hrv, by = c("iso3", "year"), all.x = TRUE)
  msg("HRV merged: ", sum(!is.na(d$hrv)), " overlapping country-years")
  if (sum(!is.na(d$hrv)) == 0)
    msg("   WARNING: zero overlap. HRV ends before this panel begins.")
} else {
  msg("HRV absent -- skipping. See the header for where to put it.")
}

# ---- D. CORRELATIONS --------------------------------------------------------
# Spearman as well as Pearson: vsi is a latent scale with no claim to
# linearity against someone else's index, so rank agreement is the fairer test.
benchmarks <- intersect(c(names(pill), if (has_hrv) "hrv"), names(d))

cor_row <- function(v, lab, dat) {
  ok <- complete.cases(dat$vsi, dat[[v]])
  if (sum(ok) < 30) return(NULL)
  data.table(benchmark = v, scope = lab, n = sum(ok),
             pearson  = round(cor(dat$vsi[ok], dat[[v]][ok]), 3),
             spearman = round(cor(dat$vsi[ok], dat[[v]][ok], method = "spearman"), 3))
}
res <- rbindlist(c(
  lapply(benchmarks, cor_row, lab = "all years", dat = d),
  unlist(lapply(sort(unique(d$year)), function(y)
    lapply(benchmarks, cor_row, lab = paste("year", y), dat = d[year == y])),
    recursive = FALSE)
), use.names = TRUE)

# within-country: does vsi track SPI over time inside a country, not just
# across countries? Cross-sectional agreement can be entirely a rich/poor split.
wc <- d[, {
  ok <- complete.cases(vsi, spi_overall)
  if (sum(ok) >= 4) .(r = cor(vsi[ok], spi_overall[ok])) else .(r = NA_real_)
}, by = iso3]
msg("within-country vsi~SPI: median r = ", round(median(wc$r, na.rm = TRUE), 3),
    " over ", sum(!is.na(wc$r)), " countries")

res <- rbind(res, data.table(benchmark = "spi_overall",
  scope = "within-country median", n = sum(!is.na(wc$r)),
  pearson = round(median(wc$r, na.rm = TRUE), 3), spearman = NA_real_))

print(res[scope == "all years"])
fwrite(res, here("output/measure/tables/vsi_external_validity.csv"))

# ---- E. WHERE THEY DISAGREE -------------------------------------------------
# The substantively interesting cases, and a good figure: countries SPI rates
# well that this index rates badly, and the reverse. Disagreement is not
# automatically a failure -- SPI scores statistical SYSTEMS, this index scores
# what was actually reported -- but a country at the extreme of both needs an
# explanation before publication.
dis <- d[complete.cases(vsi, spi_overall)]
dis[, `:=`(z_vsi = scale(vsi)[, 1], z_spi = scale(spi_overall)[, 1])]
dis[, gap := z_vsi - z_spi]
setorder(dis, -gap)
disag <- rbind(head(dis[, .(iso3, year, vsi, spi_overall, z_vsi, z_spi, gap)], 15),
               tail(dis[, .(iso3, year, vsi, spi_overall, z_vsi, z_spi, gap)], 15))
disag[, (c("vsi","spi_overall","z_vsi","z_spi","gap")) :=
        lapply(.SD, round, 2), .SDcols = c("vsi","spi_overall","z_vsi","z_spi","gap")]
cat("\n--- reports MORE than its statistical system predicts (top) / LESS (bottom) ---\n")
print(disag)
fwrite(disag, here("output/measure/tables/vsi_spi_disagreements.csv"))
# ---- F. FEED THE PUBLIC PAGE ------------------------------------------------
# docs/index.html fetches this, the same pattern build_docs_data.R uses for
# vsi_scores.json. The `overlaps_source` flag is the point of the figure:
# SPI pillar 3 partly scores SDG indicator availability drawn from the same UN
# database this index is built from, so its agreement is partly mechanical --
# and it is the pillar that agrees LEAST, which is the evidence that the
# overall 0.83 is not an artifact of shared inputs.
labels <- c(spi_overall = "SPI overall",
            spi_p5_infra = "Pillar 5 — data infrastructure",
            spi_p4_sources = "Pillar 4 — data sources",
            spi_p2_services = "Pillar 2 — data services",
            spi_p1_use = "Pillar 1 — data use",
            spi_p3_products = "Pillar 3 — data products")
pub <- res[scope == "all years"][match(names(labels), benchmark), ]
pub <- pub[!is.na(benchmark)]
pub[, `:=`(label = labels[benchmark],
           overlaps_source = benchmark == "spi_p3_products",
           is_total = benchmark == "spi_overall",
           note = "")]

# HRV sits apart from the SPI pillars: it is the direct methodological ancestor
# of this index (a Bayesian latent-variable measure of reporting), and it
# overlaps this panel in 2015 only, so its row carries that caveat with it.
if (has_hrv) {
  hr <- res[benchmark == "hrv" & scope == "all years"]
  if (nrow(hr))
    pub <- rbind(pub, data.table(benchmark = "hrv", scope = "all years",
      n = hr$n, pearson = hr$pearson, spearman = hr$spearman,
      label = "HRV transparency index", overlaps_source = FALSE,
      is_total = FALSE, note = "2015 only"), fill = TRUE)
}

jsonlite::write_json(list(
  pillars = pub[, .(key = benchmark, label, n, pearson, spearman,
                    overlaps_source, is_total, note)],
  within_country_median = round(median(wc$r, na.rm = TRUE), 3),
  within_country_n      = sum(!is.na(wc$r)),
  hrv_available         = has_hrv,
  years                 = paste(range(d$year), collapse = "-"),
  generated             = format(Sys.Date())
), here("docs/validity_spi.json"), auto_unbox = TRUE, digits = NA)
cat("wrote docs/validity_spi.json\n")

msg("done. tables in output/measure/tables/, page data in docs/")
