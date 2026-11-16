# ==============================================================================
# validate_goal_level_bootstrap.R
#
# Bootstrap stability of goal_level.
#
# The model's posterior SE says how uncertain a score is GIVEN the estimated
# item parameters. It does not account for the item parameters themselves being
# estimates. The bootstrap does: resample country-years with replacement, refit
# the goal, then score the ORIGINAL 1,773 country-years with the resampled
# item parameters. The spread of a country-year's score across replicates is
# the part of its uncertainty the posterior SE leaves out.
#
# Scoring the original rows, not the resampled ones, is what makes replicates
# comparable: the same 1,773 people are scored every time, by different rulers.
#
# Settings per METHODS_LOG.md: squarem, prior norm(0,2) on slopes, TOL 1e-3.
# OUTPUT  output/measure/tables/goal_level_bootstrap.csv -- per country-year per
#         goal: bootstrap SD, and the model SE beside it.
#
# RUN     B=500 CORES=8 Rscript code/validate_goal_level_bootstrap.R   (~98 min)
#
# PROVENANCE  Recovered 14 Nov 2026 from the session that ran it (9 Nov 2026, B = 500 on 8 cores, 98.1 min; results in METHODS_LOG.md).
# The logic is exactly as run. Changed for the repo: file paths only, and the default B set from 400 to the 500 actually run.
# CHECKPOINTING, added 14 Nov 2026 for the re-run (CLAUDE.md: long fits run
#   chunked and checkpointed). Each replicate writes its own file to
#   data/02_measure/goal_level_boot_ck/ as it finishes and is skipped on a
#   re-run, so an interruption costs one replicate, not the run. Each replicate
#   now sets its own seed (20261109 + b), so the result reproduces exactly; the
#   9 Nov run used one seed and parallel streams, which cannot be replayed.
#   Model, settings, resampling and scoring are unchanged.
# ==============================================================================
suppressMessages({library(mirt); library(data.table); library(here); library(parallel)})
B      <- as.integer(Sys.getenv("B", "500"))
CORES  <- as.integer(Sys.getenv("CORES", "8"))
source(here("code/data_prep/irt_prep.R"))
set.seed(20261109)

goals <- sort(unique(item_goal))
cols  <- lapply(goals, function(g) {
  cs <- colnames(resp)[item_goal == g]; M <- resp[, cs, drop = FALSE]
  p <- colMeans(M); cs[p > 0.02 & p < 0.98] })
names(cols) <- goals
goals <- goals[sapply(cols, length) >= 10]
msg("bootstrap: ", B, " replicates x ", length(goals), " goals on ", CORES, " cores")

prior_pars <- function(M) { v <- mirt(M, 1, itemtype = "2PL", pars = "values")
  i <- grepl("^a1$", v$name) & v$est
  v$prior.type[i] <- "norm"; v$prior_1[i] <- 0; v$prior_2[i] <- 2; v }

CK <- here("data/02_measure/goal_level_boot_ck"); dir.create(CK, showWarnings = FALSE)

one_rep <- function(b) {
  fo <- file.path(CK, sprintf("rep_%03d.rds", b))
  if (file.exists(fo)) return(readRDS(fo))
  set.seed(20261109 + b)
  idx <- sample.int(nrow(resp), nrow(resp), replace = TRUE)
  out <- lapply(goals, function(g) {
    M0 <- resp[, cols[[as.character(g)]], drop = FALSE]
    Mb <- M0[idx, , drop = FALSE]
    f <- try(suppressWarnings(mirt(Mb, 1, itemtype = "2PL", pars = prior_pars(Mb),
             verbose = FALSE, accelerate = "squarem", TOL = 1e-3,
             technical = list(NCYCLES = 5000, warn = FALSE))), silent = TRUE)
    if (inherits(f, "try-error")) return(rep(NA_real_, nrow(resp)))
    # score the ORIGINAL rows with this replicate's item parameters
    s <- fscores(f, method = "EAP", response.pattern = M0)[, "F1"]
    s * sign(cor(s, rowSums(M0), use = "complete.obs"))
  })
  names(out) <- goals
  saveRDS(out, fo)
  cat(sprintf("[%s]   rep %3d done\n", format(Sys.time(), "%H:%M:%S"), b))
  out
}

t0 <- Sys.time()
reps <- mclapply(seq_len(B), one_rep, mc.cores = CORES)
msg("replicates done in ", round(as.numeric(difftime(Sys.time(), t0, units="mins")),1), " min")

base <- as.data.table(readRDS(here("data/02_measure/irt_goal_level_scores.rds")))
res <- rbindlist(lapply(as.character(goals), function(g) {
  Mx <- do.call(cbind, lapply(reps, function(r) r[[g]]))
  data.table(iso3 = keys$iso3, year = keys$year, goal = as.integer(g),
             boot_sd = round(apply(Mx, 1, sd, na.rm = TRUE), 4),
             n_ok = rowSums(!is.na(Mx))) }))
res <- merge(base, res, by = c("iso3", "year", "goal"))
fwrite(res, here("output/measure/tables/goal_level_bootstrap.csv"))

cat("\n=== bootstrap SD vs the model's posterior SE, by goal ===\n")
print(res[, .(boot_sd_median = round(median(boot_sd, na.rm=TRUE), 3),
              model_se_median = round(median(goal_level_se), 3),
              ratio = round(median(boot_sd, na.rm=TRUE)/median(goal_level_se), 2),
              failed_reps = B - min(n_ok)), by = goal][order(-ratio)])
cat("\nA ratio near or below 1 means the published SE already covers the\n")
cat("parameter uncertainty. Well above 1 means the SE is optimistic.\n")
msg("done.")
