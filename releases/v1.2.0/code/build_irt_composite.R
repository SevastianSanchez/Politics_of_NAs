# ==============================================================================
# build_irt_composite.R
#
# Fit 1 of 2: the COMPOSITE index. One reporting-transparency score per
# country-year. Runs in roughly half an hour and is independent of the
# goal-level fit -- neither script can delay or break the other.
#
# WHAT THIS IS
#   The UN Global Database records, for every country-series-year, whether a
#   value was reported. Treat each series as a test item and each country-year
#   as a test-taker: a country's latent "reporting transparency" is estimated
#   jointly with each series' difficulty. This is the Hollyer, Rosendorff &
#   Vreeland (2014) design applied to SDG data instead of the WDI.
#
#   Why it matters for this project: the difficulty parameters replace the
#   denominator choice. Earlier measures had to pick a denominator by hand --
#   all 665 series (too wide, it assumes Chad should report what Germany does)
#   or only the series the UN opened a cell for (endogenous to reporting
#   itself). IRT learns how hard each series is instead of assuming it.
#
#   Unidimensional means ONE latent trait: a single number per country-year.
#   The goal-level breakdown is a separate model in build_irt_goals.R.
#
# ESTIMATION
#   Marginal maximum likelihood (mirt, EM) for the item parameters; Bayesian
#   EAP for the scores, so the reported SEs are posterior standard deviations.
#   Dynamic smoothing across years (HRV's year-to-year prior, which needs full
#   MCMC) is deliberately NOT done here -- deferred to a later release. Nine
#   years is short for a random walk to earn its place.
#
# RUNTIME   ~25-30 min, converging in about 13,561 EM cycles on 607 items x
#           1,773 country-years. An unconverged fit is not publishable, so the
#           script says so loudly rather than writing quietly.
#
# INPUT   via code/data_prep/irt_prep.R
# OUTPUT  data/02_measure/irt_composite_*  plus the two shared provenance
#         artifacts this script owns (response matrix, goal assignment)
# ==============================================================================

source(here::here("code/data_prep/irt_prep.R"))

# ---- FIT ---------------------------------------------------------------------

msg("fitting unidimensional 2PL (composite)")
t0 <- Sys.time()
fit <- mirt(resp, 1, itemtype = "2PL", verbose = FALSE,
            technical = list(NCYCLES = max_cycles))
conv   <- extract.mirt(fit, "converged")
cycles <- extract.mirt(fit, "iterations")
mins   <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
msg("   ", mins, " min | converged: ", conv, " | cycles: ", cycles)
if (!conv)
  warning("COMPOSITE FIT DID NOT CONVERGE - do not publish these scores")

# ---- SCORES ------------------------------------------------------------------
# EAP posterior means, with posterior SDs as the error bars.

th     <- fscores(fit, method = "EAP", full.scores.SE = TRUE)
scores <- data.table(keys, composite = th[, 1], composite_se = th[, 2])
setorder(scores, iso3, year)

# ---- ITEM PARAMETERS ---------------------------------------------------------
# The difficulty estimates ARE the answer to the denominator problem, so they
# are a published output, not a diagnostic. a = discrimination (how sharply the
# series separates countries), d = intercept (easiness).

co <- as.data.table(coef(fit, simplify = TRUE)$items, keep.rownames = "series_code")
co[, goal := item_goal[match(series_code, colnames(resp))]]
co[, p_reported := as.numeric(p_rep[keep][match(series_code, names(p_rep[keep]))])]

# ---- WRITE -------------------------------------------------------------------
# This script owns irt_response_matrix.rds and irt_series_goal_assignment.csv:
# both are produced by the shared prep step, and having a single writer keeps
# to the repo's one-writer-per-file rule. build_irt_goals.R writes neither.

msg("writing")
out <- here("data/02_measure")

saveRDS(wide, file.path(out, "irt_response_matrix.rds"))
fwrite(shared_log, file.path(out, "irt_series_goal_assignment.csv"))

saveRDS(fit,    file.path(out, "irt_composite_fit.rds"))
fwrite(scores,  file.path(out, "irt_composite_scores.csv"))
saveRDS(scores, file.path(out, "irt_composite_scores.rds"))
fwrite(co,      file.path(out, "irt_composite_item_params.csv"))

fwrite(data.table(
  run_date        = as.character(Sys.Date()),
  fit             = "unidimensional 2PL",
  n_country_years = nrow(resp),
  n_items         = ncol(resp),
  item_filter     = paste0(item_lo, "-", item_hi),
  max_cycles      = max_cycles,
  converged       = conv,
  cycles          = cycles,
  minutes         = mins,
  median_se       = round(median(scores$composite_se), 4)),
  file.path(out, "irt_composite_run_log.csv"))

msg("done. rows: ", nrow(scores))

cat("\n--- 2023 extremes ---\n")
print(scores[year == 2023][order(-composite)][1:6,
      .(iso3, composite = round(composite, 2), se = round(composite_se, 3))])
print(scores[year == 2023][order(composite)][1:6,
      .(iso3, composite = round(composite, 2), se = round(composite_se, 3))])
