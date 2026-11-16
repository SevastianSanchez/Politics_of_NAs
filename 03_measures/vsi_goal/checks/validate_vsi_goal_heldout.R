# ==============================================================================
# validate_vsi_goal_heldout.R
#
# Held-out-series validity for the goal scores.
#
# THE CLAIM BEING TESTED  "vsi_goal for goal g measures this country's
# reporting on goal g." Not "it resembles the overall index" -- a goal score
# diverging from the overall index is this project's hypothesis, not a fault
# (see CLAUDE.md), so leave-one-goal-out correlation is the wrong test.
#
# THE TEST  Split a goal's series 70/30. Fit on the 70, score countries, then
# ask how well that score predicts whether the held-out 30% were reported --
# series the model never saw. A score that tracks reporting in its own domain
# will predict them. A score that is model noise will not.
#
# THE NULL  The same thing with the country-year labels shuffled. That is what
# "no signal" scores on this scale, and it is what any threshold has to beat.
# Without it a number like 0.6 means nothing.
#
# REPORTED  AUC, the probability that a randomly chosen reported held-out cell
# came from a higher-scoring country-year than a randomly chosen unreported
# one. 0.5 is chance. Reported per goal, averaged over splits, against the null.
#
# OUTPUT  03_measures/vsi_goal/checks/output/vsi_goal_heldout_raw.csv (one row per goal x
#         split x real/null) and vsi_goal_heldout_validity.csv (per goal).
#
# RUN     SPLITS=20 CORES=4 Rscript 03_measures/vsi_goal/checks/validate_vsi_goal_heldout.R   (~13 min)
#
# PROVENANCE  Recovered 14 Nov 2026 from the session that ran it (9 Nov 2026, 20 splits on 4 cores, 12.8 min; results in METHODS_LOG.md).
# The logic is exactly as run. Changed for the repo: file paths only. Its raw output survived and reproduces the logged
#             median AUC 0.725 and null 0.500.
# ==============================================================================
suppressMessages({library(mirt); library(data.table); library(here); library(parallel)})
SPLITS <- as.integer(Sys.getenv("SPLITS", "20"))
CORES  <- as.integer(Sys.getenv("CORES", "8"))
ONEGOAL<- Sys.getenv("ONEGOAL", "")
source(here("functions/irt_prep.R"))
set.seed(20261109)

auc <- function(score, y) {               # rank-based, ties handled
  y <- as.integer(y); if (length(unique(y)) < 2) return(NA_real_)
  r <- rank(score); n1 <- sum(y == 1); n0 <- sum(y == 0)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

prior_pars <- function(M) { v <- mirt(M, 1, itemtype = "2PL", pars = "values")
  i <- grepl("^a1$", v$name) & v$est
  v$prior.type[i] <- "norm"; v$prior_1[i] <- 0; v$prior_2[i] <- 2; v }

score_on <- function(M) {
  f <- try(suppressWarnings(mirt(M, 1, itemtype = "2PL", pars = prior_pars(M),
           verbose = FALSE, accelerate = "squarem", TOL = 1e-3,
           technical = list(NCYCLES = 5000, warn = FALSE))), silent = TRUE)
  if (inherits(f, "try-error")) return(NULL)
  s <- fscores(f, method = "EAP")[, "F1"]
  s * sign(cor(s, rowSums(M)))
}

one_split <- function(g, k) {
  cs <- colnames(resp)[item_goal == g]
  M  <- resp[, cs, drop = FALSE]; p <- colMeans(M)
  M  <- M[, p > 0.02 & p < 0.98, drop = FALSE]
  if (ncol(M) < 10) return(NULL)
  n_tr <- max(5L, floor(0.7 * ncol(M)))
  tr   <- sample(ncol(M), n_tr); te <- setdiff(seq_len(ncol(M)), tr)
  if (!length(te)) return(NULL)
  s <- score_on(M[, tr, drop = FALSE]); if (is.null(s)) return(NULL)
  # AUC is computed WITHIN each held-out series and then averaged, not over all
  # held-out cells pooled. Pooling mixes in the between-series difference in how
  # commonly each is reported, which is much larger than the between-country
  # signal and drags the pooled AUC to 0.5 however good the score is. Per series,
  # the only thing that varies is the country, which is the question being asked.
  H  <- as.matrix(M[, te, drop = FALSE])
  # A FRESH permutation per held-out series. Reusing one permutation across all
  # series in a split correlates their null AUCs: if that single shuffle leans
  # positive, every series does, and the null comes out at 72% instead of ~50%.
  per <- vapply(seq_len(ncol(H)), function(j)
           c(auc(s, H[, j]), auc(sample(s), H[, j])), numeric(2))
  # MEDIAN, not mean, and the share of held-out series predicted the right way.
  # Some goals contain series that genuinely run backwards -- 23 of goal 17's 75
  # are donor-side aid series, which a recipient country's reporting score
  # should NOT predict positively. A mean over a bimodal set of AUCs (+0.8 and
  # -0.3) nets to 0.5 and hides that; the median plus the share does not.
  mk <- function(kind, v) data.table(goal = g, split = k, kind = kind,
          train = n_tr, test = length(te),
          auc = median(v, na.rm = TRUE), auc_mean = mean(v, na.rm = TRUE),
          pct_right_way = mean(v > 0.5, na.rm = TRUE))
  rbindlist(list(mk("real", per[1, ]), mk("null", per[2, ])))
}

goals <- if (nzchar(ONEGOAL)) as.integer(ONEGOAL) else sort(unique(item_goal))
jobs  <- CJ(goal = goals, k = seq_len(SPLITS))
msg("held-out validity: ", length(goals), " goals x ", SPLITS, " splits on ", CORES, " cores")
t0 <- Sys.time()
res <- rbindlist(mclapply(seq_len(nrow(jobs)),
        function(i) one_split(jobs$goal[i], jobs$k[i]), mc.cores = CORES))
msg("done in ", round(as.numeric(difftime(Sys.time(), t0, units="mins")),1), " min")

# data.table::dcast named explicitly: packages.R attaches reshape2, which masks
# dcast and returns a plain data.frame, so the := calls below would fail. Same
# trap documented in irt_prep.R.
tab <- data.table::dcast(res, goal + train + test ~ kind, value.var = "auc",
                         fun.aggregate = mean)
tab[, lift := round(real - null, 3)][, `:=`(real = round(real,3), null = round(null,3))]
share <- data.table::dcast(res, goal ~ kind, value.var = "pct_right_way",
                           fun.aggregate = mean)
setnames(share, c("real","null"), c("pct_right_real","pct_right_null"))
tab <- merge(tab, share, by = "goal")
tab[, `:=`(pct_right_real = round(100*pct_right_real), pct_right_null = round(100*pct_right_null))]
setorder(tab, -real)
print(tab)
cat("\nAUC 0.5 = chance. 'null' is the same test with country labels shuffled.\n")
cat("median real:", round(median(tab$real, na.rm=TRUE),3),
    "| median null:", round(median(tab$null, na.rm=TRUE),3), "\n")
fwrite(res, here("03_measures/vsi_goal/checks/output/vsi_goal_heldout_raw.csv"))
fwrite(tab, here("03_measures/vsi_goal/checks/output/vsi_goal_heldout_validity.csv"))
msg("done.")
