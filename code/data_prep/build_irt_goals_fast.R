# ==============================================================================
# build_irt_goals_fast.R
#
# A CHEAPER ESTIMATOR for the same goal-level bifactor model as
# build_irt_goals.R. Same data, same items, same factor structure -- only the
# numerical settings differ.
#
# WHY THIS EXISTS
#   The default-settings bifactor fit ran past 19 hours without returning. It
#   may simply be slow, or it may be heading for the 30,000-cycle cap, which
#   would end in a NON-CONVERGED fit after roughly two days. There is no way to
#   tell from outside, because that run was started with verbose = FALSE and
#   mirt prints nothing until it returns.
#
#   Rather than choose between waiting and restarting, this runs ALONGSIDE the
#   original on a spare core. Whichever converges first is usable; if both
#   finish, their scores should agree closely and that agreement is itself
#   evidence the settings below did no harm.
#
# WHAT IS TRADED FOR SPEED -- all three are numerical, none change the model
#   accelerate = "squarem"  A more aggressive EM accelerator than mirt's
#                           default Ramsay scheme. Same fixed point, fewer
#                           steps to reach it. No approximation.
#   TOL = 1e-3              Stop when parameters move less than this between
#                           cycles, instead of the 1e-4 default. Looser, so it
#                           stops sooner; the cost is precision in the last
#                           decimal of the item parameters, which is far below
#                           the posterior SDs (~0.115) attached to the scores.
#   quadpts = 31            Fewer quadrature nodes for the numerical
#                           integration. Coarser, and the one setting that
#                           genuinely approximates. If the two runs disagree,
#                           suspect this first.
#
#   verbose = TRUE, unlike the original, so the cycle counter is visible in the
#   log and we can see whether it is converging or heading for the cap.
#
# OUTPUT  data/02_measure/irt_goal_fast_*   -- deliberately distinct filenames,
#         so this cannot overwrite either the running job's output or the
#         canonical outputs of build_irt_goals.R.
#
# INPUT   via code/data_prep/irt_prep.R  (identical matrix to every other fit)
# ==============================================================================

source(here::here("code/data_prep/irt_prep.R"))

fast_tol      <- 1e-3
fast_quadpts  <- 31L
fast_accel    <- "squarem"

msg("items per goal factor: ",
    paste(as.integer(table(factor(spec_idx, levels = seq_along(spec_levels)))),
          collapse = " "))
msg("fast settings: TOL=", fast_tol, " quadpts=", fast_quadpts,
    " accelerate=", fast_accel, " NCYCLES=", max_cycles)

# ---- FIT ---------------------------------------------------------------------

msg("fitting bifactor (1 general + ", length(spec_levels),
    " goal factors), cheaper estimator")
t0 <- Sys.time()
# TOL is a top-level argument in this mirt version, not a technical option
fit <- bfactor(resp, spec_idx,
               quadpts    = fast_quadpts,
               accelerate = fast_accel,
               TOL        = fast_tol,
               verbose    = TRUE,
               technical  = list(NCYCLES = max_cycles))
conv   <- extract.mirt(fit, "converged")
cycles <- extract.mirt(fit, "iterations")
mins   <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
msg("   ", mins, " min | converged: ", conv, " | cycles: ", cycles)
if (!conv)
  warning("FAST BIFACTOR FIT DID NOT CONVERGE - do not publish these scores")

Theta <- fscores(fit, method = "EAP", full.scores.SE = TRUE)
nf <- 1L + length(spec_levels)
th <- Theta[, 1:nf, drop = FALSE]
se <- Theta[, (nf + 1):(2 * nf), drop = FALSE]

# ---- SCORES ------------------------------------------------------------------
# sector_tilt    the goal-specific factor: given this country's overall level,
#                does it report more or less than expected on this goal
# sector_score   general + specific, the absolute position
# reporting_rate model-implied share of the goal's series reported, on [0,1]

msg("deriving sector scores")

goal_rows <- vector("list", length(spec_levels))
for (k in seq_along(spec_levels)) {
  g     <- spec_levels[k]
  items <- which(spec_idx == k)
  pr <- vapply(items, function(i)
    probtrace(extract.item(fit, i), th)[, 2], numeric(nrow(th)))
  goal_rows[[k]] <- data.table(
    keys,
    goal           = g,
    n_items        = length(items),
    sector_tilt    = th[, k + 1],
    sector_tilt_se = se[, k + 1],
    sector_score   = th[, 1] + th[, k + 1],
    reporting_rate = rowMeans(pr))
}
scores_goal <- rbindlist(goal_rows)
setorder(scores_goal, iso3, year, goal)

# the general factor from this model -- should track the published TWR closely
scores_general <- data.table(keys, twr_bifactor = th[, 1], twr_bifactor_se = se[, 1])
setorder(scores_general, iso3, year)

co <- as.data.table(coef(fit, simplify = TRUE)$items, keep.rownames = "series_code")
co[, goal := item_goal[match(series_code, colnames(resp))]]
co[, p_reported := as.numeric(p_rep[keep][match(series_code, names(p_rep[keep]))])]

# ---- WRITE -------------------------------------------------------------------

msg("writing")
out <- here("data/02_measure")

saveRDS(fit,           file.path(out, "irt_goal_fast_fit.rds"))
fwrite(scores_goal,    file.path(out, "irt_goal_fast_scores.csv"))
saveRDS(scores_goal,   file.path(out, "irt_goal_fast_scores.rds"))
fwrite(scores_general, file.path(out, "irt_goal_fast_general.csv"))
fwrite(co,             file.path(out, "irt_goal_fast_item_params.csv"))

fwrite(data.table(
  run_date        = as.character(Sys.Date()),
  fit             = "bifactor, cheaper estimator",
  n_country_years = nrow(resp),
  n_items         = ncol(resp),
  goal_factors    = length(spec_levels),
  tol             = fast_tol,
  quadpts         = fast_quadpts,
  accelerate      = fast_accel,
  max_cycles      = max_cycles,
  converged       = conv,
  cycles          = cycles,
  minutes         = mins),
  file.path(out, "irt_goal_fast_run_log.csv"))

# agreement with the published overall score, as a sanity check
twr <- as.data.table(readRDS(file.path(out, "irt_scores_1d.rds")))
chk <- merge(scores_general, twr, by = c("iso3", "year"))
msg("correlation of this fit's general factor with the published TWR: ",
    sprintf("%.4f", cor(chk$twr_bifactor, chk$theta)))

msg("done. sector rows: ", nrow(scores_goal))
