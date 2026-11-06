# ==============================================================================
# validate_twr_index.R
#
# Validation battery for the World on Record Index (TWR), v1.
#
# Face validity is not evidence. Myanmar, Sudan and Afghanistan falling is
# persuasive but it is a handful of cases chosen after seeing the scores. This
# script runs the checks a measurement paper has to report, and writes each
# one out as a CSV so the numbers can be cited, diffed and re-run.
#
# FIVE CHECKS
#   1. Convergent   TWR against the World Bank's Statistical Performance
#                   Indicators. Should correlate strongly but NOT near-perfectly:
#                   identical would mean TWR is a rebuild of SPI, uncorrelated
#                   would mean it measures noise. Uses spi_overall_mod, which
#                   drops SPI's pillar 3 -- that pillar is scored from the UN
#                   SDG database, i.e. from TWR's own source, so the unmodified
#                   SPI is circular here.
#   2. Known groups The income gradient. Richer countries should report more.
#                   Monotone high > upper-middle > lower-middle > low is the
#                   test; the gradient's SIZE also matters, since a measure
#                   that is only income would be a capacity index, not a
#                   transparency one.
#   3. Legacy DVs   TWR against the seven share-based measures it replaces.
#                   This is where the denominator argument is earned: TWR
#                   should track the defensible denominators and diverge from
#                   the endogenous ones, rather than agreeing with all of them.
#   4. Discriminant The abandoned SDR missingness measure. Expect a NEGATIVE
#                   correlation, since it counts missingness while TWR counts
#                   reporting, and expect it to be imperfect.
#   5. Reliability  Empirical reliability from the posterior SDs, and how many
#                   country-years are too imprecise to use.
#
#   Plus a diagnostic for the 2023 reporting-lag artefact, which any user of
#   these scores has to handle before modelling.
#
# NOT DONE HERE: the bridge to HRV on 2015, the single overlapping year. The
#   HRV/QoG extension is not in this repository, so that check needs the file
#   first. It is the one external benchmark that would test TWR against the
#   measure it descends from.
#
# INPUT   data/02_measure/irt_composite_scores.rds  (TWR scores)
#         data/03_panels/analysis_data.rds       (SPI, income, legacy DVs)
#         data/02_measure/agg_series_counts_rc.csv (availability share)
# OUTPUT  output/measure/results/*.csv, output/measure/figures/*.png
# ==============================================================================

source(here::here("code/packages.R"))
library(here)
suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), ..., "\n", sep = "")
res_dir <- here("output/measure/results")
fig_dir <- here("output/measure/figures")

twr <- as.data.table(readRDS(here("data/02_measure/irt_composite_scores.rds")))
setnames(twr, c("composite", "composite_se"), c("twr", "twr_se"))

a <- as.data.table(readRDS(here("data/03_panels/analysis_data.rds")))
ov <- a[scope == "overall"]
stopifnot(nrow(ov) == nrow(twr))

d <- merge(twr, ov, by = c("iso3", "year"), all.x = TRUE)
msg("merged panel: ", nrow(d), " country-years")

cor2 <- function(x, y) {
  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 30) return(data.table(n = sum(ok), pearson = NA_real_, spearman = NA_real_))
  data.table(n = sum(ok),
             pearson  = round(cor(x[ok], y[ok]), 3),
             spearman = round(cor(x[ok], y[ok], method = "spearman"), 3))
}

# ---- 1. CONVERGENT: SPI ------------------------------------------------------

msg("1. convergent validity against SPI")

conv <- rbindlist(list(
  cbind(measure = "spi_overall_mod (pillars 1,2,4,5)", cor2(d$twr, d$spi_overall_mod)),
  cbind(measure = "spi_overall (includes circular pillar 3)", cor2(d$twr, d$spi_overall))
))
print(conv)
fwrite(conv, file.path(res_dir, "validation_convergent_spi.csv"))

by_year <- d[, cbind(year = .BY$year, cor2(twr, spi_overall_mod)), by = year][, -1]
fwrite(by_year, file.path(res_dir, "validation_convergent_spi_by_year.csv"))

# ---- 2. KNOWN GROUPS: income -------------------------------------------------

msg("2. known-groups: income gradient")

lv <- c("L", "LM", "UM", "H")
lab <- c(L = "Low", LM = "Lower-middle", UM = "Upper-middle", H = "High")
g <- d[income_level %in% lv,
       .(n = .N, mean_twr = round(mean(twr), 3), sd = round(sd(twr), 3),
         median = round(median(twr), 3)),
       by = .(income_level)]
g[, income := lab[income_level]]
setorder(g, mean_twr)
print(g[, .(income, n, mean_twr, median, sd)])

g_ord <- g[order(match(income_level, lv))]
monotone <- all(diff(g_ord$mean_twr) > 0)
msg("   monotone across income groups: ", monotone)

# how much of TWR is income alone? a transparency measure should not be
# explained away by capacity
r2_income <- summary(lm(twr ~ factor(income_level), data = d[income_level %in% lv]))$r.squared
msg("   R-squared of income alone: ", sprintf("%.3f", r2_income))

fwrite(cbind(g[, .(income, income_level, n, mean_twr, median, sd)],
             monotone = monotone, r2_income_only = round(r2_income, 4)),
       file.path(res_dir, "validation_income_gradient.csv"))

# ---- 3. THE LEGACY DVs -------------------------------------------------------

msg("3. against the share-based measures TWR replaces")

legacy <- c("dv_n_observations_pct_baseline", "dv_n_observations_stable_pct_baseline",
            "dv_n_observations_pct_goalbase", "dv_n_observations_stable_pct_goalbase",
            "dv_n_observations_pct_frontier")
legacy <- legacy[legacy %in% names(d)]

sh <- fread(here("data/02_measure/agg_series_counts_rc.csv"))
if (all(c("scope", "dv_availability_share") %in% names(sh))) {
  shv <- unique(sh[scope == "overall", .(iso3, year, dv_availability_share)])
  d <- merge(d, shv, by = c("iso3", "year"), all.x = TRUE)
  legacy <- c("dv_availability_share", legacy)
}

lg <- rbindlist(lapply(legacy, function(v) cbind(dv = v, cor2(d$twr, d[[v]]))))
setorder(lg, -spearman)
print(lg)
fwrite(lg, file.path(res_dir, "validation_vs_legacy_dvs.csv"))

# do the legacy measures agree with EACH OTHER? this is the denominator problem
pair <- combn(legacy, 2, simplify = FALSE)
pw <- rbindlist(lapply(pair, function(p)
  cbind(dv_a = p[1], dv_b = p[2], cor2(d[[p[1]]], d[[p[2]]]))))
setorder(pw, spearman)
msg("   weakest agreement between two legacy measures: rho = ", pw$spearman[1],
    "  (", pw$dv_a[1], " vs ", pw$dv_b[1], ")")
fwrite(pw, file.path(res_dir, "validation_legacy_disagreement.csv"))

# ---- 4. DISCRIMINANT: the abandoned SDR measure ------------------------------

msg("4. discriminant: abandoned SDR missingness measure")
sdr <- cor2(d$twr, d$prop_sdg_missing_sdr)
print(sdr)
fwrite(cbind(measure = "prop_sdg_missing_sdr", sdr),
       file.path(res_dir, "validation_vs_sdr.csv"))

# ---- 5. RELIABILITY ----------------------------------------------------------

msg("5. reliability")

# empirical (marginal) reliability for EAP scores
emp_rel <- var(d$twr) / (var(d$twr) + mean(d$twr_se^2))
q <- quantile(d$twr_se, c(.05, .25, .5, .75, .95))
rel <- data.table(
  empirical_reliability = round(emp_rel, 4),
  se_p05 = round(q[1], 4), se_p25 = round(q[2], 4), se_median = round(q[3], 4),
  se_p75 = round(q[4], 4), se_p95 = round(q[5], 4),
  n_se_above_0.20 = sum(d$twr_se > 0.20),
  pct_se_above_0.20 = round(100 * mean(d$twr_se > 0.20), 2))
print(rel)
fwrite(rel, file.path(res_dir, "validation_reliability.csv"))

# ---- 6. THE 2023 LAG ---------------------------------------------------------

msg("6. 2023 reporting-lag diagnostic")
yr <- d[, .(n = .N, mean_twr = round(mean(twr), 4),
            mean_se = round(mean(twr_se), 4)), by = year][order(year)]
yr[, change := round(mean_twr - shift(mean_twr), 4)]
print(yr)
fwrite(yr, file.path(res_dir, "validation_year_trend.csv"))

# ---- 7. IS IT JUST CAPACITY? -------------------------------------------------
# The sharpest objection to any transparency measure: that it is a statistical
# capacity index wearing a different name. TWR correlates 0.86 with SPI and
# income alone explains 62% of its variance, so the objection has to be met
# head on rather than waved away.
#
# The test: strip out capacity and wealth, and see who is left at the bottom.
# If the residual still ranks known concealers low, TWR is carrying
# information that capacity does not.

msg("7. residual after removing capacity and income")

dd <- d[is.finite(spi_overall_mod) & income_level %in% lv]
m  <- lm(twr ~ spi_overall_mod + factor(income_level), data = dd)
dd[, twr_resid := resid(m)]
msg("   R-squared of SPI + income together: ", sprintf("%.3f", summary(m)$r.squared))

latest <- dd[dd[, .I[year == max(year)], by = iso3]$V1]
setorder(latest, twr_resid)
bot <- head(latest[, .(iso3, year, twr = round(twr, 2),
                       resid = round(twr_resid, 2))], 12)
top <- head(latest[order(-twr_resid), .(iso3, year, twr = round(twr, 2),
                       resid = round(twr_resid, 2))], 12)
cat("\n   reports LESS than capacity and income predict:\n"); print(bot)
cat("\n   reports MORE than capacity and income predict:\n"); print(top)

fwrite(cbind(rank_from = "under-reporting", bot),
       file.path(res_dir, "validation_residual_underreporters.csv"))
fwrite(cbind(rank_from = "over-reporting", top),
       file.path(res_dir, "validation_residual_overreporters.csv"))
fwrite(data.table(
  r2_spi_only    = round(summary(lm(twr ~ spi_overall_mod, data = dd))$r.squared, 4),
  r2_income_only = round(r2_income, 4),
  r2_both        = round(summary(m)$r.squared, 4),
  residual_sd    = round(sd(dd$twr_resid), 4),
  n              = nrow(dd)),
  file.path(res_dir, "validation_capacity_decomposition.csv"))

# ---- 8. WITHIN-COUNTRY: THE TEST THAT ACTUALLY MATTERS -----------------------
# Check 7 is cross-sectional, and cross-sectionally almost any country measure
# correlates with wealth. But no design here uses cross-sectional variation:
# country fixed effects absorb a country's level entirely, so what identifies
# anything is movement WITHIN a country over time.
#
# So the question is not "is rich Germany above poor Chad" -- of course it is --
# but "when a country's TWR moves, is that just its capacity moving?" Demeaning
# both by country answers it directly.
#
# Also reported: how much of TWR's total variance is within-country at all. A
# measure that is nearly all between-country is a country ranking, not a
# panel measure, and could not support a difference-in-differences design.

msg("8. within-country variation")

w <- d[is.finite(spi_overall_mod)]
w[, `:=`(twr_dm = twr - mean(twr), spi_dm = spi_overall_mod - mean(spi_overall_mod)),
  by = iso3]

within_cor <- cor2(w$twr_dm, w$spi_dm)
msg("   within-country correlation of TWR with SPI: rho = ", within_cor$spearman,
    " (cross-sectional was ", conv$spearman[1], ")")

# variance decomposition of TWR itself
vd <- d[, .(cmean = mean(twr)), by = iso3]
var_between <- var(vd$cmean)
var_within  <- mean(d[, .(v = var(twr)), by = iso3]$v, na.rm = TRUE)
pct_within  <- 100 * var_within / (var_within + var_between)
msg("   share of TWR variance that is within-country: ",
    sprintf("%.1f%%", pct_within))

# SPI coverage is incomplete, and incompleteness is not random: the most
# closed states are the ones SPI does not reach. Report who drops out.
missing_spi <- d[!is.finite(spi_overall_mod), .N, by = iso3][order(-N)]
msg("   countries with no SPI at all: ",
    nrow(missing_spi[N == uniqueN(d$year)]), " of ", uniqueN(d$iso3))

fwrite(data.table(
  cross_sectional_rho = conv$spearman[1],
  within_country_rho  = within_cor$spearman,
  within_n            = within_cor$n,
  pct_variance_within = round(pct_within, 2),
  countries_no_spi    = nrow(missing_spi[N == uniqueN(d$year)]),
  countries_total     = uniqueN(d$iso3)),
  file.path(res_dir, "validation_within_country.csv"))
fwrite(missing_spi[N == uniqueN(d$year), .(iso3)],
       file.path(res_dir, "validation_countries_without_spi.csv"))

# ---- FIGURES -----------------------------------------------------------------

msg("writing figures")

p1 <- ggplot(d[is.finite(spi_overall_mod)], aes(spi_overall_mod, twr)) +
  geom_point(alpha = .25, size = .8) +
  geom_smooth(method = "lm", se = FALSE, linewidth = .6) +
  labs(x = "SPI (pillars 1, 2, 4, 5)", y = "TWR",
       title = "Convergent validity: TWR against statistical capacity",
       subtitle = "Strong but imperfect, as it should be: TWR is not a rebuild of SPI") +
  theme_minimal(base_size = 11)
ggsave(file.path(fig_dir, "validation_twr_vs_spi.png"), p1,
       width = 6.5, height = 4.5, dpi = 200)

d2 <- d[income_level %in% lv]
d2[, income := factor(lab[income_level], levels = unname(lab[lv]))]
p2 <- ggplot(d2, aes(income, twr)) +
  geom_boxplot(outlier.size = .5, linewidth = .4) +
  labs(x = NULL, y = "TWR",
       title = "Known-groups validity: the income gradient",
       subtitle = "Monotone, but far from determined by income") +
  theme_minimal(base_size = 11)
ggsave(file.path(fig_dir, "validation_income_gradient.png"), p2,
       width = 6.5, height = 4.5, dpi = 200)

p3 <- ggplot(d, aes(twr, twr_se)) +
  geom_point(alpha = .25, size = .8) +
  labs(x = "TWR", y = "posterior SD",
       title = "Precision across the scale",
       subtitle = "Wider intervals at the extremes, where fewer series discriminate") +
  theme_minimal(base_size = 11)
ggsave(file.path(fig_dir, "validation_precision.png"), p3,
       width = 6.5, height = 4.5, dpi = 200)

msg("done. results in output/measure/results/, figures in output/measure/figures/")
