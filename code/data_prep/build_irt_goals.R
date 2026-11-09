# ==============================================================================
# build_irt_goals.R
#
# Fit 2 of 2: the SECTOR layer. One reporting score per country-year PER GOAL.
# Independent of build_irt_composite.R -- neither can delay or break the other.
#
# WHAT THIS IS
#   The composite answers "how much did this country report". This answers
#   "how much did it report ON GOAL g". One separate unidimensional 2PL per
#   goal, fitted on that goal's own series only.
#
#   The column is `goal_level`: reporting on that goal with the country's
#   overall level INCLUDED. Its companion `goal_relative` -- the same quantity
#   with the overall level stripped out -- comes from a bifactor model and is
#   built by its own script, because that fit takes hours and must not be able
#   to hold this one up.
#
#   Why separate fits and not one 17-factor model? Both are wanted and they
#   answer different questions. A separate fit per goal is also what makes the
#   held-out test below possible: a goal's score owes nothing to the other 16.
#
# WHY THESE SETTINGS
#   Taken from METHODS_LOG.md, not chosen here. Do not change one without
#   reading that file; each of these cost hours to establish.
#
#   accelerate = "squarem"   Binary model. mirt's default Ramsay accelerator
#                            reaches the same fixed point ~20x slower; it ran
#                            the bifactor past 19 h without returning.
#   prior norm(0, 2) on a1   The pre-flight screen finds 9 groups of perfectly
#                            collinear series. Inside a single factor those
#                            make the factor a copy of the block, and the
#                            block's discrimination has no finite value. The
#                            prior bounds it without deleting the series.
#                            NOT lognormal: 172 of 1,045 loadings are negative
#                            and lognormal gives those zero density, which
#                            would force sign flips.
#   TOL = 1e-3               mirt's 1e-4 is unreachable here: a handful of
#                            near-zero loadings and extreme intercepts sit on
#                            a flat ridge and drift below 1e-3 forever. Shown
#                            to change no score by more than 0.0065 against
#                            SEs of 0.3-0.5.
#
# WHAT IS AND IS NOT RELEASED
#   Every goal fitted here ships, each printed with its reliability and SE.
#   Nothing is dropped for imprecision; 0.70 (Nunnally) is a reference point,
#   not a cut. Goals 6 and 15 are fitted and written but flagged `hold`, on
#   CONTENT grounds and for different reasons -- see CLAUDE.md. An error bar
#   cannot warn a reader about either, so the flag travels with the data.
#
#   Goal 7 gets no score. It has 3 series, below the >=10 needed to identify a
#   factor. That is a structural fact about the goal, not a judgement on it.
#
# EVIDENCE THESE SCORES CARRY (9 Nov 2026, see METHODS_LOG.md)
#   Reliability  0.772 - 0.953, median 0.844; every goal above 0.70.
#   Bootstrap    B = 500, 0 failed replicates. Bootstrap SD is 7-42% of the
#                posterior SE, median 13% -- the published SEs are
#                conservative, so report the SE, not the bootstrap SD.
#   Held-out     Fit on 70% of a goal's series, predict the held-out 30%.
#                Median AUC 0.725 against a per-series permutation null that
#                sits on 0.500. 13 of 16 goals at 0.649 or better. The three
#                weakest -- 17 (0.618), 15 (0.526), 6 (0.479) -- are exactly
#                the three already flagged on content grounds.
#
# RUNTIME  under a minute for all 16 goals. No checkpointing needed.
#
# INPUT   via code/data_prep/irt_prep.R
# OUTPUT  data/02_measure/irt_goal_level_{scores.csv,scores.rds,
#         item_params.csv,health.csv,run_log.csv,fits.rds}
#         This script writes no file that build_irt_composite.R writes.
# ==============================================================================

source(here::here("code/data_prep/irt_prep.R"))

suppressMessages({library(mirt); library(data.table); library(here)})

# Provenance, for disclosure only. `Nature` in the UN exports marks whether a
# value is country-produced (C/CA) or produced by the custodian agency (E/M/G).
# Built by code/data_prep/build_series_provenance.R; absent is not fatal.
prov_path <- here::here("output/measure/tables/series_provenance_nature.csv")
prov <- if (file.exists(prov_path)) data.table::fread(prov_path) else NULL

MIN_SERIES   <- 10L      # below this a factor is not identified
TOL          <- 1e-3
PRIOR_SD     <- 2
MAX_CYCLES   <- 5000L
REL_REF      <- 0.70     # reported as a reference point, never applied as a cut
HOLD_CONTENT <- c(6L, 15L)   # withheld on content grounds; see CLAUDE.md

# ---- ONE GOAL ----------------------------------------------------------------
fit_goal <- function(g) {
  cs <- colnames(resp)[item_goal == g]
  M  <- resp[, cs, drop = FALSE]

  # Guard, not a filter: the 2-98% screen already ran globally in irt_prep.R.
  # If it ever bites here, say so rather than dropping series silently.
  p  <- colMeans(M)
  drop <- !(p > 0.02 & p < 0.98)
  if (any(drop)) {
    msg("  goal ", g, ": ", sum(drop), " series near-constant within goal, dropped")
    M <- M[, !drop, drop = FALSE]
  }

  if (ncol(M) < MIN_SERIES) {
    msg(sprintf("  goal %-2d  series %3d  -- SKIPPED, under %d, factor not identified",
                g, ncol(M), MIN_SERIES))
    return(NULL)
  }

  v <- mirt(M, 1, itemtype = "2PL", pars = "values")
  i <- grepl("^a1$", v$name) & v$est
  v$prior.type[i] <- "norm"; v$prior_1[i] <- 0; v$prior_2[i] <- PRIOR_SD

  t0 <- Sys.time()
  f  <- suppressWarnings(mirt(M, 1, itemtype = "2PL", pars = v, verbose = FALSE,
          accelerate = "squarem", TOL = TOL,
          technical = list(NCYCLES = MAX_CYCLES, warn = FALSE)))
  mins <- as.numeric(difftime(Sys.time(), t0, units = "mins"))

  th <- fscores(f, method = "EAP", full.scores.SE = TRUE)

  # Orient the factor so that MORE reporting is a HIGHER score. A 2PL is
  # identified only up to sign, and the sign mirt lands on is arbitrary, so
  # without this a goal could silently flip between runs.
  s <- th[, 1] * sign(cor(th[, 1], rowSums(M)))

  rel  <- var(s) / (var(s) + mean(th[, 2]^2))
  conv <- extract.mirt(f, "converged")
  cyc  <- extract.mirt(f, "iterations")
  amax <- max(abs(coef(f, simplify = TRUE)$items[, "a1"]))

  # Publishable means: the optimiser converged, it did not simply hit the cap,
  # and every score has a finite standard error. max|a| is REPORTED, not gated:
  # a slope of 10-17 here is a near-duplicate series bounded by the prior, which
  # is the prior working, not divergence. The bifactor's max|a| < 10 rule in
  # METHODS_LOG.md was written for a model where a factor became a copy of a
  # collinear block and slopes ran past 80. See the Nov 9 diagnostic rows.
  ok <- conv && cyc < MAX_CYCLES && !any(is.na(th[, 2])) && all(th[, 2] > 0)

  msg(sprintf("  goal %-2d  series %3d  cycles %5d  conv=%-5s  max|a| %5.2f  rel %.3f  medSE %.3f  %.1f min%s",
      g, ncol(M), cyc, conv, amax, rel, median(th[, 2]), mins,
      if (!ok) "   <-- CHECK" else ""))

  co <- as.data.table(coef(f, simplify = TRUE)$items, keep.rownames = "series_code")
  # `g` is BOTH this function's argument and a column of a 2PL coefficient
  # matrix (the guessing parameter, fixed at 0). Inside `[`, data.table resolves
  # the column, so `goal := g` silently wrote 0 for every series. Use the
  # argument explicitly.
  goal_number <- g
  co[, goal := goal_number][, p_reported := round(colMeans(M)[series_code], 4)]
  co[, weight_pct := round(100 * abs(a1) / sum(abs(a1)), 2)]

  # concentration: share of the score's weight in its five heaviest series
  top5 <- sum(sort(co$weight_pct, decreasing = TRUE)[1:min(5, nrow(co))])
  # provenance: share of weight from series that are mostly NOT country-produced
  agency_w <- if (!is.null(prov)) {
    pc <- prov$pct_C[match(co$series_code, prov$SeriesCode)]
    sum(co$weight_pct[!is.na(pc) & pc < 50])
  } else NA_real_

  list(
    goal   = g,
    scores = data.table(iso3 = keys$iso3, year = keys$year, goal = g,
                        goal_level    = round(s, 4),
                        goal_level_se = round(th[, 2], 4)),
    params = co,
    health = data.table(goal = g, series = ncol(M), cycles = cyc,
                        converged = conv, clean = ok,
                        max_abs_a   = round(amax, 3),
                        # disclosure, not gates: how concentrated the score is,
                        # and how much of its weight rests on series the
                        # custodian agency produces rather than the country
                        weight_top5_pct  = round(top5, 1),
                        weight_agency_pct = round(agency_w, 1),
                        reliability = round(rel, 3),
                        above_ref   = rel >= REL_REF,
                        se_median   = round(median(th[, 2]), 3),
                        se_max      = round(max(th[, 2]), 3),
                        release     = if (g %in% HOLD_CONTENT) "hold_content" else "release",
                        minutes     = round(mins, 2)),
    fit    = f)
}

# ---- ALL GOALS ---------------------------------------------------------------
msg("goal_level: one 1-factor 2PL per goal | squarem | prior norm(0, ", PRIOR_SD,
    ") | TOL ", TOL)

t_all <- Sys.time()
res   <- Filter(Negate(is.null), lapply(sort(unique(item_goal)), fit_goal))
mins  <- as.numeric(difftime(Sys.time(), t_all, units = "mins"))

scores <- rbindlist(lapply(res, `[[`, "scores"))
params <- rbindlist(lapply(res, `[[`, "params"))
health <- rbindlist(lapply(res, `[[`, "health"))
setorder(scores, iso3, year, goal)
setorder(health, goal)

# ---- GUARDS ------------------------------------------------------------------
# An unconverged or degenerate fit is not publishable. Halt loudly rather than
# writing quietly; a bad score that reaches data/ is worse than no score.
stopifnot(
  nrow(health) >= 15L,
  nrow(scores) == nrow(health) * nrow(resp),
  !any(is.na(scores$goal_level)),
  !any(is.na(scores$goal_level_se))
)
if (!all(health$clean)) {
  print(health[clean == FALSE])
  stop("one or more goals is not publishable (did not converge, hit the cycle ",
       "cap, or has a non-finite standard error) -- nothing written. ",
       "Read METHODS_LOG.md before changing a setting.")
}

# ---- WRITE -------------------------------------------------------------------
msg("writing")
out <- here("data/02_measure")

saveRDS(setNames(lapply(res, `[[`, "fit"), sapply(res, `[[`, "goal")),
        file.path(out, "irt_goal_level_fits.rds"))
fwrite(scores,  file.path(out, "irt_goal_level_scores.csv"))
saveRDS(scores, file.path(out, "irt_goal_level_scores.rds"))
fwrite(params,  file.path(out, "irt_goal_level_item_params.csv"))
fwrite(health,  file.path(out, "irt_goal_level_health.csv"))

fwrite(data.table(
  run_date        = as.character(Sys.Date()),
  fit             = "unidimensional 2PL, one per goal",
  n_country_years = nrow(resp),
  n_series_total  = ncol(resp),
  goals_fitted    = nrow(health),
  goals_skipped   = paste(setdiff(sort(unique(item_goal)), health$goal), collapse = "/"),
  goals_held      = paste(HOLD_CONTENT, collapse = "/"),
  accelerate      = "squarem",
  prior           = paste0("norm(0,", PRIOR_SD, ") on a1"),
  tol             = TOL,
  max_cycles      = MAX_CYCLES,
  all_converged   = all(health$converged),
  median_reliability = median(health$reliability),
  min_reliability    = min(health$reliability),
  median_se       = round(median(scores$goal_level_se), 4),
  minutes         = round(mins, 2),
  mirt_version    = as.character(packageVersion("mirt")),
  r_version       = paste(R.version$major, R.version$minor, sep = ".")),
  file.path(out, "irt_goal_level_run_log.csv"))

cat("\n"); print(health)
cat("\ngoals fitted:", nrow(health),
    "| all converged:", all(health$converged),
    "| median reliability:", median(health$reliability),
    "| all above", REL_REF, ":", all(health$above_ref), "\n")
msg("done. rows: ", nrow(scores))
