# ==============================================================================
# validate_goal_relative_bootstrap.R
#
# Bootstrap for goal_relative, second attempt.
#
# The first attempt failed on every replicate and could not say why: the handler
# was `error = function(e) NULL`, and a non-converged fit returned NULL too, so a
# crash and a cycle cap looked identical. This one records the message, the
# convergence flag and the cycle count separately.
#
# It also checkpoints: each replicate writes its own file as it finishes, so a
# sleeping laptop costs one replicate instead of the whole run, and a re-run
# picks up where it stopped.
#
# OUTPUT  03_measures/vsi_goal_relative/checks/output/goal_relative_bootstrap.csv (per goal). Per-
#         replicate checkpoints go to 01_data/vsi_scores/vsi_goal_relative/boot_ck/,
#         which is not tracked.
#
# RUN     B=100 DIAG_N=4 C_DIAG=4 C_FULL=10 Rscript 03_measures/vsi_goal_relative/checks/validate_goal_relative_bootstrap.R  (~4.7 h)
#
# PROVENANCE  Recovered 14 Nov 2026 from the session that ran it (10 Nov 2026, attempt 3, B = 100 on 10 cores, 282.8 min; results in METHODS_LOG.md).
# The logic is exactly as run. Changed for the repo: file paths only.
# ==============================================================================
suppressMessages({library(mirt); library(data.table); library(here); library(parallel)})
msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), ..., "\n", sep = "")
source(here("functions/irt_prep.R"))
source(here("functions/bifactor_scorer.R"))
CK <- here("01_data/vsi_scores/vsi_goal_relative/boot_ck"); dir.create(CK, showWarnings = FALSE)

B      <- as.integer(Sys.getenv("B", "100"))
DIAG_N <- as.integer(Sys.getenv("DIAG_N", "4"))
C_DIAG <- as.integer(Sys.getenv("C_DIAG", "4"))
C_FULL <- as.integer(Sys.getenv("C_FULL", "10"))

full  <- readRDS(here("01_data/vsi_scores/vsi_goal_relative/irt_goal_relative_fit.rds"))
start <- as.data.frame(mod2values(full))

one <- function(b) {
  fo <- file.path(CK, sprintf("rep_%03d.rds", b))
  if (file.exists(fo)) { cat(sprintf("  rep %3d  cached\n", b)); return(invisible(TRUE)) }
  set.seed(1000 + b)
  i  <- sample(nrow(resp), nrow(resp), replace = TRUE)
  M  <- resp[i, , drop = FALSE]
  t0 <- Sys.time()
  r <- tryCatch({
    v <- warm_pars(M, spec_idx, start)
    f <- suppressWarnings(bfactor(M, spec_idx, pars = v, verbose = FALSE,
           accelerate = "squarem", TOL = 1e-3,
           technical = list(NCYCLES = 500, warn = FALSE)))
    cyc  <- tryCatch(extract.mirt(f, "iterations"), error = function(e) NA_integer_)
    conv <- isTRUE(extract.mirt(f, "converged"))
    if (!conv) {
      list(ok = FALSE, why = sprintf("did not converge (%s cycles, cap 500)", cyc), cyc = cyc)
    } else {
      s <- score_bifactor(f, X = resp)            # score the ORIGINAL rows
      if (is.null(s)) list(ok = FALSE, why = "scorer returned NULL", cyc = cyc)
      else            list(ok = TRUE,  score = s$score, cyc = cyc)
    }
  }, error = function(e) list(ok = FALSE, cyc = NA_integer_,
                              why = paste("ERROR:", conditionMessage(e))))
  r$mins <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
  saveRDS(r, fo)
  cat(sprintf("[%s]   rep %3d  %-46s %4.1f min\n", format(Sys.time(), "%H:%M:%S"), b,
              if (isTRUE(r$ok)) sprintf("ok, %s cycles", r$cyc) else paste("FAILED --", r$why),
              r$mins))
  flush.console(); invisible(isTRUE(r$ok))
}

read_ck <- function(ids) {
  fs <- file.path(CK, sprintf("rep_%03d.rds", ids)); fs <- fs[file.exists(fs)]
  lapply(fs, readRDS)
}

msg("PHASE 1: ", DIAG_N, " diagnostic replicates on ", C_DIAG, " cores")
invisible(mclapply(seq_len(DIAG_N), one, mc.cores = C_DIAG))
d  <- read_ck(seq_len(DIAG_N))
nok <- sum(vapply(d, function(x) isTRUE(x$ok), logical(1)))
msg("   ", nok, " of ", DIAG_N, " usable")
if (nok < 3) {
  msg("STOPPING. The failures were:")
  for (x in d) if (!isTRUE(x$ok)) msg("   ", x$why)
  msg("done.")
  quit(save = "no")
}

msg("PHASE 2: replicates ", DIAG_N + 1, "-", B, " on ", C_FULL, " cores")
t0 <- Sys.time()
invisible(mclapply(seq.int(DIAG_N + 1, B), one, mc.cores = C_FULL))
all <- read_ck(seq_len(B))
ok  <- Filter(function(x) isTRUE(x$ok), all)
msg("replicates done in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1),
    " min | ", length(ok), " of ", B, " usable")
bad <- Filter(function(x) !isTRUE(x$ok), all)
if (length(bad)) {
  msg("failure reasons seen:")
  tb <- sort(table(vapply(bad, function(x) x$why, character(1))), decreasing = TRUE)
  for (i in seq_along(tb)) msg("   ", tb[i], "x  ", names(tb)[i])
}
if (length(ok) < 20) { msg("too few usable replicates to estimate a spread"); quit(save = "no") }

A  <- simplify2array(lapply(ok, function(x) x$score))   # rows x goals x reps
bs <- apply(A, c(1, 2), sd)
pub <- as.data.table(readRDS(here("01_data/vsi_scores/vsi_goal_relative/irt_goal_relative_scores.rds")))
setorder(pub, iso3, year, goal)
goals <- sort(unique(pub$goal))
out <- rbindlist(lapply(seq_along(goals), function(k)
  data.table(goal = goals[k], boot_sd = bs[, k],
             se = pub[goal == goals[k]][order(iso3, year)]$goal_relative_se)))
tab <- out[, .(boot_sd = round(median(boot_sd), 4), se = round(median(se), 4),
               ratio_pct = round(100 * median(boot_sd / se))), by = goal][order(goal)]
print(tab)
msg("ratio of bootstrap SD to posterior SE: median ", round(100 * median(out$boot_sd / out$se)),
    "% | range ", round(100 * min(tab$ratio_pct / 100 * 100) / 100), "-", max(tab$ratio_pct), "%")
fwrite(tab, here("03_measures/vsi_goal_relative/checks/output/goal_relative_bootstrap.csv"))
msg("done. wrote 03_measures/vsi_goal_relative/checks/output/goal_relative_bootstrap.csv")
