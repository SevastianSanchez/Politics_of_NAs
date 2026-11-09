# ==============================================================================
# build_irt_bifactor.R
#
# Fit 3 of 3: `goal_relative` — reporting on a goal RELATIVE to the country's
# own overall level. The companion to `goal_level`, which leaves the overall
# level in. Both are wanted; they answer different questions.
#
#   goal_level     "how much did this country report on goal g"
#   goal_relative  "did it report MORE or LESS on goal g than its own overall
#                   level would lead you to expect"
#
# WHY A BIFACTOR
#   One general factor (a country's overall reporting) plus one factor per
#   goal. Every SERIES loads on exactly two: the general factor and its own
#   goal's. "bi" counts the loadings per series, not the factors in the model
#   — there are 17 here. The specific factors are orthogonal to the general
#   one by construction, which is exactly what "net of the country's overall
#   level" means.
#
# WHY THIS IS THE SLOW ONE
#   The composite converges in 187 cycles and all 16 goal fits take 20 seconds
#   together. This one has 1,569 parameters and took hundreds of cycles to
#   settle. Hence the chunking below.
#
# SETTINGS — from METHODS_LOG.md, not chosen here. Read that file before
# changing any of them; each cost hours to establish.
#
#   accelerate = "squarem"   mirt's default Ramsay accelerator ran this model
#                            past 19 HOURS without returning. squarem reaches
#                            the same fixed point ~20x faster.
#   prior norm(0, 2) on a    Without it the fit CANNOT converge. A few series
#                            are near-perfectly collinear inside their goal,
#                            so that goal's specific factor becomes a copy of
#                            them and their slope has no finite best value:
#                            the likelihood went flat at cycle ~500 and sat
#                            there to 900 while slopes climbed past 80.
#                            NOT lognormal — 172 of 1,045 loadings are
#                            negative, and a lognormal gives those zero
#                            density, forcing sign flips.
#   TOL = 1e-3               mirt's 1e-4 is unreachable: 13 of 1,569
#                            parameters sit on a flat ridge and drift below
#                            1e-3 forever. Shown to change no score by more
#                            than 0.0065 against SEs of 0.3-0.5.
#   chunked + checkpointed   mirt writes NOTHING until it converges. Two runs
#                            of two hours each were lost to a sleeping laptop.
#                            This script saves every chunk and resumes.
#
# SCORING — by the exact scorer at the bottom, not mirt::fscores.
#   mirt FITS a bifactor cheaply by exploiting the bifactor property, but
#   fscores() does not reuse it for the specific factors: it builds the full
#   quadpts^17 grid (5^17 asks for 16 GB; 31^17 overflows), leaving only
#   quasi-Monte Carlo, which converges far too slowly in 17 dimensions.
#   The scorer here exploits the property directly, so no integral exceeds
#   two dimensions and nothing is approximated beyond the quadrature. It is
#   checked against mirt's own EAP_general, the one case mirt can do exactly.
#
# RESUMING   safe to re-run. Picks up from the checkpoint and keeps going.
#
# INPUT   via code/data_prep/irt_prep.R
# OUTPUT  data/02_measure/irt_goal_relative_{scores.csv,scores.rds,
#         item_params.csv,health.csv,run_log.csv,fit.rds}
#         plus irt_goal_relative_ckpt.rds, the resume point.
# ==============================================================================

suppressMessages({library(mirt); library(data.table); library(here)})
source(here("code/data_prep/irt_prep.R"))

CHUNK     <- 50L      # cycles per checkpoint
MAX_TOTAL <- 3000L    # ceiling; stop rather than run forever
PRIOR_SD  <- 2
TOL       <- 1e-3
K         <- 61L      # quadrature nodes per dimension, as mirt uses for 2 factors
LIM       <- 6

out  <- here("data/02_measure")
ckpt <- file.path(out, "irt_goal_relative_ckpt.rds")

# ---- FIT ---------------------------------------------------------------------
set_prior <- function(v) {
  v <- as.data.frame(v)
  i <- grepl("^a[0-9]+$", v$name) & v$est
  v$prior.type[i] <- "norm"; v$prior_1[i] <- 0; v$prior_2[i] <- PRIOR_SD
  v
}

if (file.exists(ckpt)) {
  state <- readRDS(ckpt)
  msg("resuming from checkpoint at cycle ", state$done)
} else {
  msg("cold start — no checkpoint found")
  state <- list(pars = set_prior(bfactor(resp, spec_idx, pars = "values")),
                done = 0L)
}
msg("bifactor | ", ncol(resp), " series | ", length(spec_levels), " goal factors | ",
    "squarem | prior norm(0,", PRIOR_SD, ") | TOL ", TOL, " | chunk ", CHUNK)

fit <- NULL
repeat {
  t0  <- Sys.time()
  fit <- bfactor(resp, spec_idx, pars = state$pars, verbose = FALSE,
                 accelerate = "squarem", TOL = TOL,
                 technical = list(NCYCLES = CHUNK, warn = FALSE))
  state$done <- state$done + extract.mirt(fit, "iterations")
  state$pars <- mod2values(fit)
  conv <- extract.mirt(fit, "converged")
  a <- state$pars$value[grepl("^a[0-9]+$", state$pars$name) & state$pars$est]
  saveRDS(state, ckpt)
  msg(sprintf("  cycles %4d | loglik %.1f | max|a| %5.1f | |a|>10: %3d | %.1f min | converged=%s",
      state$done, extract.mirt(fit, "logLik"), max(abs(a)), sum(abs(a) > 10),
      as.numeric(difftime(Sys.time(), t0, units = "mins")), conv))
  if (conv) { msg("CONVERGED at ", state$done, " cycles."); break }
  if (state$done >= MAX_TOTAL) {
    stop("ceiling of ", MAX_TOTAL, " cycles reached without converging. ",
         "Nothing written. Read METHODS_LOG.md before changing a setting.",
         call. = FALSE)
  }
}
saveRDS(fit, file.path(out, "irt_goal_relative_fit.rds"))

# ---- EXACT SCORER ------------------------------------------------------------
# Given the general factor, a series depends on only ONE goal factor, so
#   L_g(theta_G) = INT P(x_g | theta_G, theta_g) phi(theta_g) d theta_g
# is one-dimensional, and the full likelihood is the product of the 16. A goal
# factor's posterior is therefore a two-dimensional integral; the other 15
# goals enter only through their L_h(theta_G).

msg("scoring (exact, <=2 dimensions per integral)")
X    <- as.matrix(fit@Data$data)
cf   <- coef(fit, simplify = TRUE)$items
# mirt files the general-only series (goal 7) under specific index 1. That is
# correct for scoring: their specific loading is zero, so their contribution to
# goal 1's integral does not vary with theta_1 and cancels in the posterior,
# while the total likelihood still counts them exactly once. It is wrong only
# as a SERIES COUNT -- see n_by_goal below.
spec <- fit@Internals$bfactor$specific
N <- nrow(X); J <- ncol(X); G <- max(spec)

aG <- cf[, "a1"]
aS <- vapply(seq_len(J), function(j) cf[j, paste0("a", spec[j] + 1L)], numeric(1))
dd <- cf[, "d"]
stopifnot(all(cf[, "g"] == 0), all(cf[, "u"] == 1))   # plain 2PL, no asymptotes

tt <- seq(-LIM, LIM, length.out = K)
lw <- dnorm(tt, log = TRUE); lw <- lw - log(sum(exp(lw)))

lse <- function(M) { mx <- apply(M, 1, max); mx[!is.finite(mx)] <- 0
                     mx + log(rowSums(exp(M - mx))) }

goal_LL <- function(g) {
  idx <- which(spec == g); Xg <- X[, idx, drop = FALSE]
  A <- array(0, c(N, K, K))
  for (k in seq_len(K)) {
    lp <- matrix(0, N, K)
    for (m in seq_len(K)) {
      z <- aG[idx] * tt[k] + aS[idx] * tt[m] + dd[idx]
      # plogis(., log.p=TRUE), NOT -log1p(exp(-z)): slopes reach the tens, so
      # the logit hits +-770 at theta=6, exp(-z) overflows to Inf, and BOTH
      # log p and log(1-p) collapse to -Inf, poisoning every country-year with
      # NaN. Three such series are enough: each enters every row's product.
      lp[, m] <- Xg %*% plogis(z, log.p = TRUE) +
                 (1 - Xg) %*% plogis(-z, log.p = TRUE)
    }
    A[, k, ] <- lp
  }
  A
}

post_moments <- function(logp, nodes) {
  logp <- logp - apply(logp, 1, max)
  w <- exp(logp); w <- w / rowSums(w)
  m <- as.numeric(w %*% nodes)
  v <- as.numeric(w %*% (nodes^2)) - m^2
  list(ev = m, sd = sqrt(pmax(v, 0)))
}

logLg <- array(0, c(N, K, G))
for (g in seq_len(G)) {
  A <- goal_LL(g)
  for (k in seq_len(K)) logLg[, k, g] <- lse(sweep(A[, k, ], 2, lw, "+"))
}
S <- apply(logLg, c(1, 2), sum)
if (any(!is.finite(S)))
  stop("non-finite log-likelihood for ", sum(rowSums(!is.finite(S)) > 0),
       " country-years -- quadrature or log-probability problem", call. = FALSE)
mG <- post_moments(sweep(S, 2, lw, "+"), tt)

scores <- data.table(iso3 = keys$iso3, year = keys$year)
rel <- vector("list", G)
for (g in seq_len(G)) {
  A   <- goal_LL(g)
  off <- S - logLg[, , g]
  jm  <- matrix(-Inf, N, K)
  for (k in seq_len(K)) {
    term <- sweep(A[, k, ], 2, lw, "+") + lw[k] + off[, k]
    mx <- pmax(jm, term)
    jm <- mx + log(exp(jm - mx) + exp(term - mx))
  }
  mg <- post_moments(jm, tt)
  rel[[g]] <- data.table(iso3 = keys$iso3, year = keys$year,
                         goal = spec_levels[g],
                         goal_relative    = round(mg$ev, 4),
                         goal_relative_se = round(mg$sd, 4))
}
rel <- rbindlist(rel)
setorder(rel, iso3, year, goal)

# ---- VALIDATE THE SCORER against mirt's own general-factor route -------------
ref <- fscores(fit, method = "EAP_general", full.scores.SE = TRUE)
val_cor  <- cor(mG$ev, ref[, 1])
val_diff <- max(abs(mG$ev - ref[, 1]))
msg(sprintf("scorer check vs mirt EAP_general: cor %.6f | max abs diff %.6f",
            val_cor, val_diff))
if (val_cor < 0.9999 || val_diff > 0.01)
  stop("the exact scorer disagrees with mirt's EAP_general -- not writing scores",
       call. = FALSE)

# ---- HEALTH, and the guard ---------------------------------------------------
# Series counts come from irt_prep's own spec, NOT from
# fit@Internals$bfactor$specific. mirt stores the general-only series (goal 7,
# passed as NA) under specific index 1 for its own bookkeeping, so reading the
# count from there credits them to goal 1 and reports 35 series instead of 32.
# It is only a count: those series have zero loading on every specific factor,
# so they do not enter any goal factor's posterior.
n_by_goal <- table(item_goal[!is.na(spec_idx)])

health <- rel[, .(series = as.integer(n_by_goal[as.character(goal[1])]),
                  sd_score    = round(sd(goal_relative), 3),
                  se_median   = round(median(goal_relative_se), 3),
                  reliability = round(var(goal_relative) /
                                (var(goal_relative) + mean(goal_relative_se^2)), 3),
                  pct_nan = round(100 * mean(!is.finite(goal_relative)), 2)),
                by = goal]
setorder(health, goal)
HOLD_CONTENT <- c(6L, 15L)
health[, release := fifelse(goal %in% HOLD_CONTENT, "hold_content", "release")]

stopifnot(nrow(rel) == N * G, !any(is.na(rel$goal_relative)),
          !any(is.na(rel$goal_relative_se)), all(health$pct_nan == 0))

# ---- WRITE -------------------------------------------------------------------
msg("writing")
fwrite(rel,  file.path(out, "irt_goal_relative_scores.csv"))
saveRDS(rel, file.path(out, "irt_goal_relative_scores.rds"))
fwrite(health, file.path(out, "irt_goal_relative_health.csv"))

ip <- as.data.table(cf, keep.rownames = "series_code")
ip[, goal := spec_levels[spec]]
fwrite(ip, file.path(out, "irt_goal_relative_item_params.csv"))

# the bifactor's own general factor, kept for comparison with the published
# 1-factor index: they answer the same question two ways
fwrite(data.table(iso3 = keys$iso3, year = keys$year,
                  twr_bifactor = round(mG$ev, 4),
                  twr_bifactor_se = round(mG$sd, 4)),
       file.path(out, "irt_goal_relative_general.csv"))

fwrite(data.table(
  run_date       = as.character(Sys.Date()),
  fit            = "bifactor 2PL, 1 general + 16 goal factors",
  n_country_years = N, n_series = J, n_goal_factors = G,
  cycles         = state$done,
  accelerate     = "squarem",
  prior          = paste0("norm(0,", PRIOR_SD, ") on all estimated a"),
  tol            = TOL,
  scorer         = "exact, bifactor property, 61 nodes",
  scorer_cor_vs_mirt_eap_general = round(val_cor, 6),
  scorer_max_abs_diff            = round(val_diff, 6),
  median_se      = round(median(rel$goal_relative_se), 4),
  median_reliability = median(health$reliability),
  mirt_version   = as.character(packageVersion("mirt")),
  r_version      = paste(R.version$major, R.version$minor, sep = ".")),
  file.path(out, "irt_goal_relative_run_log.csv"))

cat("\n"); print(health)
msg("done. rows: ", nrow(rel))
