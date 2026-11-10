# ==============================================================================
# paper_numbers.R
#
# Every figure the measurement paper quotes, recomputed from the current build,
# in the order the paper uses them. Run this after any rebuild of the index and
# reconcile the draft against the output; a number in the paper that this script
# does not produce is one nobody is checking.
#
# OUTPUT  output/measure/results/paper_numbers.txt (and the console)
# ==============================================================================
source(here::here("code/packages.R"))
library(here); suppressPackageStartupMessages(library(data.table))

con <- file(here("output/measure/results/paper_numbers.txt"), open = "wt")
say <- function(...) { cat(..., "\n", sep = ""); cat(..., "\n", sep = "", file = con) }

tw  <- fread(here("data/02_measure/irt_composite_scores.csv"))
lg  <- fread(here("data/02_measure/irt_composite_run_log.csv"))
ad  <- fread(here("data/03_panels/analysis_data.csv"))
ov  <- unique(ad[scope == "overall", .(iso3, year, income_level, gdp_pc, spi_overall,
                                       spi_overall_mod, prop_sdg_missing_sdr,
                                       dv_n_observations_pct_baseline,
                                       dv_n_observations_stable_pct_baseline,
                                       dv_n_observations_pct_goalbase,
                                       dv_n_observations_stable_pct_goalbase,
                                       dv_n_observations_pct_frontier,
                                       n_observations)])
d <- merge(tw, ov, by = c("iso3", "year"), all.x = TRUE)
nm <- unique(fread(here("docs/vsi_scores.csv"))[, .(iso3, country_name)])
d  <- merge(d, nm, by = "iso3", all.x = TRUE)

r <- function(x, y, m = "pearson") {
  ok <- complete.cases(x, y); if (sum(ok) < 30) return(NA_real_)
  round(cor(x[ok], y[ok], method = m), 3) }

say("=== SECTION 5: model and estimation ===")
say("series after the 2-98% filter : 607 of 665")
say("series after variant collapse : ", lg$n_items[1])
say("EM cycles to converge         : ", format(lg$cycles[1], big.mark = ","),
    "   (minutes ", lg$minutes[1], ")")
say("converged                     : ", lg$converged[1])

say("\n=== SECTION 6: the index ===")
top <- d[year == 2023][order(-composite)][1:6]
bot <- d[year == 2023][order(composite)][1:6]
say("2023 highest: ", paste0(top$country_name, " (", sprintf("%.2f", top$composite), ")",
                             collapse = ", "))
say("2023 lowest : ", paste0(bot$country_name, " (", sprintf("%.2f", bot$composite), ")",
                             collapse = ", "))
ch <- dcast(d[year %in% c(2015, 2023)], iso3 + country_name ~ year,
            value.var = "composite")
setnames(ch, c("2015", "2023"), c("y15", "y23"))
ch <- ch[!is.na(y15) & !is.na(y23)][, delta := y23 - y15]
say("steepest declines: ", paste0(head(ch[order(delta)], 7)$country_name, " (",
      sprintf("%+.2f", head(ch[order(delta)], 7)$delta), ")", collapse = ", "))
say("largest increases: ", paste0(head(ch[order(-delta)], 5)$country_name, " (",
      sprintf("%+.2f", head(ch[order(-delta)], 5)$delta), ")", collapse = ", "))

say("\n=== SECTION 7.1: convergent validity ===")
say("modified SPI (pillars 1,2,4,5)  spearman ", r(d$composite, d$spi_overall_mod, "spearman"),
    " | pearson ", r(d$composite, d$spi_overall_mod),
    " | n ", sum(complete.cases(d$composite, d$spi_overall_mod)))
say("unmodified SPI                  pearson  ", r(d$composite, d$spi_overall),
    " | n ", sum(complete.cases(d$composite, d$spi_overall)))
say("(the by-pillar table and HRV come from validate_vsi_external.R ->")
say(" output/measure/tables/vsi_external_validity.csv)")

say("\n=== SECTION 7.2: known-groups ===")
inc <- d[!is.na(income_level), .(mean = round(mean(composite), 2), n = .N), by = income_level]
for (i in seq_len(nrow(inc))) say("  ", inc$income_level[i], ": ", inc$mean[i],
                                  " (n ", inc$n[i], ")")

say("\n=== SECTION 7.3: against the share-based measures ===")
d[, framework_share := n_observations]   # raw count; the share needs its denominator
for (v in c("dv_n_observations_pct_frontier", "dv_n_observations_pct_goalbase",
            "dv_n_observations_stable_pct_goalbase", "dv_n_observations_pct_baseline",
            "dv_n_observations_stable_pct_baseline"))
  say("  ", sub("dv_n_observations_", "", v), ": ", r(d$composite, d[[v]]),
      " (n ", sum(complete.cases(d$composite, d[[v]])), ")")
say("  raw reported count            : ", r(d$composite, d$n_observations))

# The old 7.4, a discriminant check against the Sustainable Development Report
# missingness measure, was cut from the paper on 8 Nov 2026: the SDR source was
# set aside as biased, and a discriminant test against a biased comparator
# cannot come out informative either way. The discriminant argument now rests
# on 7.3, where the index tracks the defensible denominators at 0.61-0.68 and
# the endogenous ones at 0.04-0.05. Sections renumbered: old 7.5 -> 7.4,
# old 7.6 -> 7.5.

say("\n=== SECTION 7.4: reliability and precision ===")
say("empirical reliability : ",
    round(var(tw$composite) / (var(tw$composite) + mean(tw$composite_se^2)), 3))
say("median SE             : ", round(median(tw$composite_se), 4))
say("95th percentile SE    : ", round(quantile(tw$composite_se, .95), 4))
say("maximum SE            : ", round(max(tw$composite_se), 4))

say("\n=== SECTION 7.5: is it a capacity index? ===")
m <- lm(composite ~ spi_overall_mod + log(gdp_pc), data = d)
say("R2 of SPI(mod) + log GDP pc : ", round(summary(m)$r.squared, 3),
    " (n ", nobs(m), ")")
dm <- d[!is.na(spi_overall_mod)]
dm[, `:=`(c_dm = composite - mean(composite), s_dm = spi_overall_mod - mean(spi_overall_mod)),
   by = iso3]
say("within-country corr with SPI(mod), demeaned : ", round(cor(dm$c_dm, dm$s_dm), 3))
wv <- d[, .(v = var(composite)), by = iso3]
say("share of total variance that is within-country : ",
    round(100 * mean(wv$v, na.rm = TRUE) / var(d$composite), 1), "%")
say("countries with no SPI at all : ",
    d[, .(any = any(!is.na(spi_overall_mod))), by = iso3][any == FALSE, .N])

say("\n=== SECTION 9: the sector layer ===")
gp <- here("data/02_measure/irt_goal_level_scores.rds")
hp <- here("data/02_measure/irt_goal_level_health.csv")
if (file.exists(gp) && file.exists(hp)) {
  gl <- as.data.table(readRDS(gp)); gh <- fread(hp)
  say("goals scored            : ", nrow(gh), " of 17 (goal 7 has 3 series, too few)")
  say("country-year-goal rows  : ", format(nrow(gl), big.mark = ","))
  say("all converged           : ", all(gh$converged))
  say("reliability  median     : ", round(median(gh$reliability), 3),
      "  min ", round(min(gh$reliability), 3),
      "  max ", round(max(gh$reliability), 3))
  say("goals at or above 0.70  : ", sum(gh$reliability >= 0.70), " of ", nrow(gh),
      "   (reference point, not a cut)")
  say("median SE               : ", round(median(gl$goal_level_se), 4),
      "  (overall index: ", round(median(tw$composite_se), 4), ")")
  say("held on content grounds : ", paste(gh[release != "release"]$goal, collapse = ", "))

  # the reason the layer exists: goals are not a restatement of the index
  gm <- merge(gl, tw[, .(iso3, year, composite)], by = c("iso3", "year"))
  r2 <- gm[, .(r2 = summary(lm(goal_level ~ composite))$r.squared), by = goal]
  say("variation NOT explained by the overall index, median : ",
      round(100 * median(1 - r2$r2), 1), "%")
  say("  least independent : goal ", r2[which.min(1 - r2)]$goal, " at ",
      round(100 * min(1 - r2$r2), 1), "%")
  say("  most independent  : goal ", r2[which.max(1 - r2)]$goal, " at ",
      round(100 * max(1 - r2$r2), 1), "%")

  say("concentration, share of weight in the 5 heaviest series :")
  for (i in order(-gh$weight_top5_pct))
    say("  goal ", gh$goal[i], ": ", round(gh$weight_top5_pct[i], 1), "%",
        "   agency-produced weight ", round(gh$weight_agency_pct[i], 1), "%")
} else {
  say("sector layer not built -- run code/data_prep/build_irt_goals.R")
}

say("\n=== SECTION 8: limitations ===")
yr <- tw[, .(mean = round(mean(composite), 2), med_se = round(median(composite_se), 3)),
         by = year][order(year)]
for (i in seq_len(nrow(yr))) say("  ", yr$year[i], ": mean ", yr$mean[i],
                                 " | median SE ", yr$med_se[i])
say("  2022->2023 change: ", round(yr[year == 2023]$mean - yr[year == 2022]$mean, 2))

close(con)
cat("\nwritten to output/measure/results/paper_numbers.txt\n")
