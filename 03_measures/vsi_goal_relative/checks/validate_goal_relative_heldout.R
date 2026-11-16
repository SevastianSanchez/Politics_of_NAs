# ==============================================================================
# validate_goal_relative_heldout.R
#
# HELD-OUT VALIDITY for goal_relative. Fit the bifactor on a random 70% of each
# goal's series, score, then ask whether that score predicts reporting on the
# 30% the model never saw. AUC is computed PER HELD-OUT SERIES and then median:
# pooling swamps it with between-series variation in base rates. The null gets a
# FRESH permutation per series -- reusing one permutation across series leaves
# structure that makes the null look non-random.
#
# OUTPUT  03_measures/vsi_goal_relative/checks/output/goal_relative_heldout_raw.csv (one row per
#         held-out series per split) and goal_relative_heldout_validity.csv.
#
# RUN     SPLITS=20 CORES=4 Rscript 03_measures/vsi_goal_relative/checks/validate_goal_relative_heldout.R  (~2.5 h)
#
# PROVENANCE  Recovered 14 Nov 2026 from the session that ran it (9 Nov 2026, 20 splits on 4 cores, 156.9 min; results in METHODS_LOG.md).
# The logic is exactly as run. Changed for the repo: file paths only.
# ==============================================================================
suppressMessages({library(mirt); library(data.table); library(here); library(parallel)})
source(here("functions/irt_prep.R"))
source(here("functions/bifactor_scorer.R"))

SPLITS <- as.integer(Sys.getenv("SPLITS", "20"))
CORES  <- as.integer(Sys.getenv("CORES", "4"))
full   <- readRDS(here("01_data/vsi_scores/vsi_goal_relative/irt_goal_relative_fit.rds"))
start  <- as.data.frame(mod2values(full))
msg("held-out validity for goal_relative: ", SPLITS, " splits on ", CORES, " cores")

auc <- function(score, y) {
  if (length(unique(y)) < 2) return(NA_real_)
  r <- rank(score); n1 <- sum(y == 1); n0 <- sum(y == 0)
  (sum(r[y == 1]) - n1*(n1+1)/2) / (n1*n0)
}

one <- function(s) {
  set.seed(2000 + s)
  tryCatch({
    idx  <- which(!is.na(spec_idx))
    train <- unlist(lapply(split(idx, spec_idx[idx]),
                           function(ix) sample(ix, ceiling(0.7*length(ix)))))
    test  <- setdiff(idx, train)
    keep  <- sort(c(train, which(is.na(spec_idx))))
    M  <- resp[, keep, drop = FALSE]
    sp <- spec_idx[keep]; lv <- sort(unique(sp[!is.na(sp)])); sp2 <- match(sp, lv)
    v  <- warm_pars(M, sp2, start)
    f  <- suppressWarnings(bfactor(M, sp2, pars = v, verbose = FALSE,
            accelerate = "squarem", TOL = 1e-3,
            technical = list(NCYCLES = 500, warn = FALSE)))
    if (!extract.mirt(f, "converged")) return(NULL)
    sc <- score_bifactor(f); if (is.null(sc)) return(NULL)

    rbindlist(lapply(test, function(j) {
      g  <- spec_idx[j]; gi <- match(g, lv); if (is.na(gi)) return(NULL)
      th <- sc$score[, gi]; y <- resp[, j]
      a  <- auc(th, y)
      an <- auc(th, sample(y))                      # fresh permutation, per series
      if (is.na(a)) return(NULL)
      data.table(split = s, goal = spec_levels[g], series = colnames(resp)[j],
                 n_rep = sum(y), auc = a, auc_null = an)
    }))
  }, error = function(e) NULL)
}

t0  <- Sys.time()
res <- rbindlist(Filter(Negate(is.null), mclapply(seq_len(SPLITS), one, mc.cores = CORES)))
msg("done in ", round(as.numeric(difftime(Sys.time(), t0, units="mins")),1), " min | ",
    nrow(res), " series-splits from ", uniqueN(res$split), " splits")
if (!nrow(res)) stop("no usable splits")
fwrite(res, here("03_measures/vsi_goal_relative/checks/output/goal_relative_heldout_raw.csv"))

# median across series within a goal, then report
tab <- res[, .(train = NA_integer_, test = uniqueN(series),
               null = round(median(auc_null),3), real = round(median(auc),3),
               pct_right_way = round(100*mean(auc > 0.5))), by = goal]
tab[, lift := round(real - null, 3)]
setorder(tab, -real)
fwrite(tab, here("03_measures/vsi_goal_relative/checks/output/goal_relative_heldout_validity.csv"))
print(tab)
cat("\nAUC 0.5 = chance. 'null' is the same test with country labels shuffled.\n")
cat("median real:", median(tab$real), "| median null:", median(tab$null), "\n")
msg("done.")
