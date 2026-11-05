# ==============================================================================
# build_irt_goals.R
#
# Fit 2 of 2: the GOAL-LEVEL disaggregation. A bifactor model -- one general
# factor plus one factor per SDG goal -- giving every country-year a score for
# each goal on top of its overall level.
#
# Independent of build_irt_composite.R by design. This fit is far slower (the
# EM step integrates over 17 dimensions instead of 1), so coupling the two
# would hold the composite index hostage to this one. Nothing here is required
# for the composite index to be built, published or cited.
#
# WHAT A GOAL SCORE MEANS
#   Each series loads on the general factor AND on exactly one goal's factor,
#   so the goal factor captures what is left over once overall reporting level
#   is accounted for:
#
#   goal_deviation  "Given this country's overall level, does it report more or
#                   less than expected on this goal?" This is the quantity the
#                   research question asks about -- which goals go dark
#                   disproportionately, rather than which countries are quiet
#                   overall.
#   goal_level      general + specific. The absolute position, which is what
#                   outside users of the index usually want.
#   expected_share  the model-implied probability that a series in this goal is
#                   reported, averaged over that goal's items. On [0,1], so it
#                   is the version a non-technical reader can interpret
#                   directly.
#
#   SDG 7 gets no sub-score: it has only 3 usable series, too few to identify
#   its own factor. Its series still inform the general factor. It is NOT
#   pooled into another goal -- different sectors, and merging them would make
#   the sub-score uninterpretable. See goal_general_only in irt_prep.R.
#
# ESTIMATION
#   Marginal maximum likelihood (mirt's bfactor, EM with dimension reduction);
#   Bayesian EAP for the scores, so the SEs are posterior standard deviations.
#
# RUNTIME   HOURS, not minutes, and it may exhaust the cycle cap without
#           converging. An unconverged fit is not publishable; the script says
#           so loudly. If it does hit the cap, the fix is a cheaper estimator
#           (QMCEM, a looser TOL, or fewer quadrature points) rather than a
#           longer wait.
#
# INPUT   via code/data_prep/irt_prep.R
#         data/02_measure/irt_composite_fit.rds  (OPTIONAL -- only to compare
#         the two models; absence just skips that comparison)
# OUTPUT  data/02_measure/irt_goal_*
# ==============================================================================

source(here::here("code/data_prep/irt_prep.R"))

msg("items per goal factor: ",
    paste(as.integer(table(factor(spec_idx, levels = seq_along(spec_levels)))),
          collapse = " "))
if (!is.na(goal_general_only))
  msg("SDG ", goal_general_only, ": ", sum(item_goal == goal_general_only),
      " items, general factor only (no sub-score)")

# ---- FIT ---------------------------------------------------------------------

msg("fitting bifactor (1 general + ", length(spec_levels), " goal factors)")
t0 <- Sys.time()
fit <- bfactor(resp, spec_idx, verbose = FALSE,
               technical = list(NCYCLES = max_cycles))
conv   <- extract.mirt(fit, "converged")
cycles <- extract.mirt(fit, "iterations")
mins   <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
msg("   ", mins, " min | converged: ", conv, " | cycles: ", cycles)
if (!conv)
  warning("BIFACTOR FIT DID NOT CONVERGE - do not publish these scores")

Theta <- fscores(fit, method = "EAP", full.scores.SE = TRUE)
# columns: G, S1..SK, then the matching SEs
nf <- 1L + length(spec_levels)
th <- Theta[, 1:nf, drop = FALSE]
se <- Theta[, (nf + 1):(2 * nf), drop = FALSE]

# ---- SCORES ------------------------------------------------------------------

msg("deriving goal-level scores")

goal_rows <- vector("list", length(spec_levels))
for (k in seq_along(spec_levels)) {
  g     <- spec_levels[k]
  items <- which(spec_idx == k)

  pr <- vapply(items, function(i)
    probtrace(extract.item(fit, i), th)[, 2], numeric(nrow(th)))

  goal_rows[[k]] <- data.table(
    keys,
    goal              = g,
    n_items           = length(items),
    goal_deviation    = th[, k + 1],
    goal_deviation_se = se[, k + 1],
    goal_level        = th[, 1] + th[, k + 1],
    expected_share    = rowMeans(pr))
}
scores_goal <- rbindlist(goal_rows)
setorder(scores_goal, iso3, year, goal)

# the general factor from THIS model, kept for comparison against the
# standalone composite fit -- they should agree closely
scores_general <- data.table(keys, general = th[, 1], general_se = se[, 1])
setorder(scores_general, iso3, year)

co <- as.data.table(coef(fit, simplify = TRUE)$items, keep.rownames = "series_code")
co[, goal := item_goal[match(series_code, colnames(resp))]]
co[, p_reported := as.numeric(p_rep[keep][match(series_code, names(p_rep[keep]))])]

# ---- DOES THE DISAGGREGATION EARN ITS PLACE? ---------------------------------
# Optional: only if the composite fit has already been built.

out <- here("data/02_measure")
comp_path <- file.path(out, "irt_composite_fit.rds")
if (file.exists(comp_path)) {
  fit_1d <- readRDS(comp_path)
  cmp <- anova(fit_1d, fit, verbose = FALSE)
  fwrite(as.data.table(cmp, keep.rownames = "model"),
         file.path(out, "irt_model_comparison.csv"))
  msg("composite vs goal-level: ",
      paste(capture.output(print(cmp)), collapse = " | "))
} else {
  msg("composite fit not found - skipping the model comparison")
}

# ---- WRITE -------------------------------------------------------------------
# The response matrix and the goal assignment are written by
# build_irt_composite.R, not here: one writer per file.

msg("writing")

saveRDS(fit,            file.path(out, "irt_goal_fit.rds"))
fwrite(scores_goal,     file.path(out, "irt_goal_scores.csv"))
saveRDS(scores_goal,    file.path(out, "irt_goal_scores.rds"))
fwrite(scores_general,  file.path(out, "irt_goal_general_factor.csv"))
fwrite(co,              file.path(out, "irt_goal_item_params.csv"))

fwrite(data.table(
  run_date          = as.character(Sys.Date()),
  fit               = "bifactor (1 general + goal factors)",
  n_country_years   = nrow(resp),
  n_items           = ncol(resp),
  item_filter       = paste0(item_lo, "-", item_hi),
  goal_factors      = length(spec_levels),
  goal_general_only = goal_general_only,
  max_cycles        = max_cycles,
  converged         = conv,
  cycles            = cycles,
  minutes           = mins),
  file.path(out, "irt_goal_run_log.csv"))

msg("done. goal rows: ", nrow(scores_goal))
