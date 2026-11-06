# ==============================================================================
# build_irt_goals_strict.R
#
# The goal-level bifactor model at FULL precision, using the one setting that
# turned out to matter.
#
# WHY THIS EXISTS
#   Three settings separated the fast variant from mirt's defaults: SQUAREM
#   acceleration, a looser convergence tolerance, and a coarser quadrature
#   grid. Only the first was free. SQUAREM and the default Ramsay scheme are
#   accelerators for the same EM algorithm and converge to the same fixed
#   point, so SQUAREM costs nothing in accuracy -- it reached convergence in
#   288 cycles where the default was still running after twenty hours. The
#   other two are genuine compromises: TOL = 1e-3 stops marginally short of
#   the maximum (mirt warned the log-likelihood was still rising, by 0.005 on
#   a total of -308,761), and 31 quadrature points integrate the likelihood
#   more coarsely than the default, which could matter in the tails where few
#   countries sit.
#
#   Those compromises were a hedge against the model never converging at all.
#   Once SQUAREM showed that it converges in 288 cycles, the hedge became
#   unnecessary: strict settings are now affordable. This script therefore
#   keeps the acceleration and drops both approximations.
#
# WHAT TO DO WITH THE RESULT
#   Compare against irt_goal_fast_scores.rds. Agreement to two decimals means
#   the fast settings did no harm, and that agreement is worth reporting in
#   the measurement paper. Disagreement means the quadrature mattered, and the
#   strict scores are the ones to publish.
#
# OUTPUT  data/02_measure/irt_goal_strict_*  -- distinct from both the fast
#         variant and build_irt_goals.R, so all three can coexist.
#
# INPUT   via code/data_prep/irt_prep.R  (identical matrix to every other fit)
# ==============================================================================

source(here::here("code/data_prep/irt_prep.R"))

msg("strict settings: mirt default TOL and quadpts, accelerate=squarem, NCYCLES=",
    max_cycles)

# ---- FIT ---------------------------------------------------------------------

msg("fitting bifactor (1 general + ", length(spec_levels),
    " goal factors), full precision")
t0 <- Sys.time()
fit <- bfactor(resp, spec_idx,
               accelerate = "squarem",
               verbose    = TRUE,
               technical  = list(NCYCLES = max_cycles))
conv   <- extract.mirt(fit, "converged")
cycles <- extract.mirt(fit, "iterations")
mins   <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
msg("   ", mins, " min | converged: ", conv, " | cycles: ", cycles)
if (!conv)
  warning("STRICT BIFACTOR FIT DID NOT CONVERGE - do not publish these scores")

# Save before scoring. A converged fit must never be lost to a failure in the
# step that follows it.
out <- here("data/02_measure")
saveRDS(fit, file.path(out, "irt_goal_strict_fit.rds"))
msg("   fit saved before scoring")

# QMC rather than a full quadrature grid: exact integration over 17 dimensions
# exhausted a 16 GB vector limit. This is the scoring step, not the likelihood,
# so it does not undo the strict quadrature used in fitting above.
Theta <- fscores(fit, method = "EAP", full.scores.SE = TRUE, QMC = TRUE)
nf <- 1L + length(spec_levels)
th <- Theta[, 1:nf, drop = FALSE]
se <- Theta[, (nf + 1):(2 * nf), drop = FALSE]

# ---- SCORES ------------------------------------------------------------------

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

scores_general <- data.table(keys, twr_bifactor = th[, 1], twr_bifactor_se = se[, 1])
setorder(scores_general, iso3, year)

co <- as.data.table(coef(fit, simplify = TRUE)$items, keep.rownames = "series_code")
co[, goal := item_goal[match(series_code, colnames(resp))]]
co[, p_reported := as.numeric(p_rep[keep][match(series_code, names(p_rep[keep]))])]

# ---- WRITE -------------------------------------------------------------------

msg("writing")

fwrite(scores_goal,    file.path(out, "irt_goal_strict_scores.csv"))
saveRDS(scores_goal,   file.path(out, "irt_goal_strict_scores.rds"))
fwrite(scores_general, file.path(out, "irt_goal_strict_general.csv"))
fwrite(co,             file.path(out, "irt_goal_strict_item_params.csv"))

fwrite(data.table(
  run_date        = as.character(Sys.Date()),
  fit             = "bifactor, strict precision, squarem",
  n_country_years = nrow(resp),
  n_items         = ncol(resp),
  goal_factors    = length(spec_levels),
  tol             = "mirt default",
  quadpts         = "mirt default",
  accelerate      = "squarem",
  max_cycles      = max_cycles,
  converged       = conv,
  cycles          = cycles,
  minutes         = mins,
  final_loglik    = round(extract.mirt(fit, "logLik"), 3)),
  file.path(out, "irt_goal_strict_run_log.csv"))

# ---- COMPARE AGAINST THE FAST VARIANT ----------------------------------------
# The point of running both. If these agree, the fast settings cost nothing and
# that is worth stating in the paper; if they do not, the quadrature mattered.

fast_path <- file.path(out, "irt_goal_fast_scores.rds")
if (file.exists(fast_path)) {
  fast <- as.data.table(readRDS(fast_path))
  cmp  <- merge(scores_goal, fast, by = c("iso3", "year", "goal"),
                suffixes = c("_strict", "_fast"))
  agree <- data.table(
    n                = nrow(cmp),
    cor_sector_tilt  = round(cor(cmp$sector_tilt_strict,  cmp$sector_tilt_fast), 5),
    cor_sector_score = round(cor(cmp$sector_score_strict, cmp$sector_score_fast), 5),
    max_abs_diff_tilt = round(max(abs(cmp$sector_tilt_strict - cmp$sector_tilt_fast)), 4),
    mean_abs_diff_tilt = round(mean(abs(cmp$sector_tilt_strict - cmp$sector_tilt_fast)), 4))
  print(agree)
  fwrite(agree, file.path(out, "irt_goal_strict_vs_fast.csv"))
} else {
  msg("fast scores not found - skipping the comparison")
}

msg("done. sector rows: ", nrow(scores_goal))
