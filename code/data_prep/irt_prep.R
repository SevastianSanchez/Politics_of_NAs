# ==============================================================================
# irt_prep.R
#
# Shared preparation for the two IRT fits. SOURCED, never run on its own, and
# it writes nothing -- the fit scripts own their output files.
#
# WHY THIS FILE EXISTS
#   build_irt_composite.R and build_irt_goals.R must be fed the IDENTICAL
#   response matrix, or their scores are not comparable and the model
#   comparison between them is meaningless. Keeping the matrix build and the
#   item filter in one shared file is what guarantees that. The alternative --
#   pasting the same 100 lines into both scripts -- would let them drift apart
#   silently.
#
# WHAT IT LEAVES IN THE CALLING ENVIRONMENT
#   resp         data.frame, one row per country-year, one 0/1 column per series
#   keys         data.table of iso3 + year, row-aligned with resp
#   wide         resp with the keys still attached (the publishable matrix)
#   p_rep        share of country-years reporting each series, BEFORE filtering
#   keep         logical, which series survived the filter
#   item_goal    the SDG goal assigned to each surviving series
#   spec_levels  the goals that get their own factor
#   spec_idx     per-item factor index for bfactor(); NA = general factor only
#   shared_log   audit trail for series that sit under several goals
#
# INPUT  data/02_measure/agg_series_depth.rds   (reported flag per cell)
#        data/02_measure/series_list.csv        (series -> goal mapping)
# ==============================================================================

source(here::here("code/packages.R"))
library(here)
suppressPackageStartupMessages({
  library(data.table)   # not loaded by packages.R
  library(mirt)
})

set.seed(20261105)

# Tunables live here, NOT in the fit scripts, so both fits are guaranteed to
# see the same matrix. Each fit script copies them into its own run log.
item_lo     <- 0.02    # drop series reported in <2% or >98% of country-years:
item_hi     <- 0.98    #   near-constant items carry no information and slow EM
max_cycles  <- 30000   # EM cycle cap. The composite fit needed 13,561.
goal_general_only <- 7L  # SDG 7 has only 3 usable series -- too few to support
                         # its own factor. Its series still feed the general
                         # factor; it simply gets no sub-score. Set to NA to
                         # give every goal a factor and accept wide intervals.
                         # Do NOT pool SDG 7 into another goal's factor: they
                         # are different sectors and merging them would make
                         # the sub-score uninterpretable.

msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), ..., "\n", sep = "")

# ---- A. RESPONSE MATRIX ------------------------------------------------------
# One row per country-year, one column per series, 1 = reported that year.
# agg_series_depth holds only cells that exist in the UN export, and 96% of
# those were reported -- so almost all the signal is in the cells that are
# ABSENT from it. The grid therefore has to be completed before anything else.

msg("prep: building response matrix")

depth <- as.data.table(readRDS(here("data/02_measure/agg_series_depth.rds")))
depth <- depth[, .(iso3, series_code, year, reported)]
# a series can sit under several goals, which duplicates its rows here
depth <- depth[, .(reported = any(reported)), by = .(iso3, series_code, year)]

grid <- CJ(iso3        = sort(unique(depth$iso3)),
           series_code = sort(unique(depth$series_code)),
           year        = sort(unique(depth$year)), unique = TRUE)

cells <- merge(grid, depth, by = c("iso3", "series_code", "year"), all.x = TRUE)
cells[, y := as.integer(!is.na(reported) & reported)]

msg("   completed grid: ", format(nrow(cells), big.mark = ","), " cells, ",
    sprintf("%.1f%%", 100 * mean(cells$y)), " reported")

wide <- dcast(cells, iso3 + year ~ series_code, value.var = "y")
keys <- wide[, .(iso3, year)]
resp <- as.data.frame(wide[, -(1:2)])

# ---- B. ITEM FILTER AND GOAL ASSIGNMENT --------------------------------------

p_rep <- colMeans(resp)
keep  <- p_rep > item_lo & p_rep < item_hi
msg("   items: ", ncol(resp), " -> ", sum(keep),
    " after the ", item_lo * 100, "-", item_hi * 100, "% filter")
resp  <- resp[, keep]

# The goal assignment is only USED by the goal-level fit, but it is built here
# so that both scripts report the same item set and the audit trail is
# identical whichever script you run.
#
# Bifactor needs exactly one specific factor per item, but 31 surviving series
# sit under several goals -- the disaster-risk series (VC_DSR_*), for instance,
# genuinely belong to goals 1, 11 and 13 at once.
#
# Tie-break rule: a shared series goes to whichever of ITS OWN goals currently
# has the fewest series, so that no goal factor is starved by an arbitrary
# choice. Taking the lowest goal number instead would strip goal 13 (climate
# action) from 24 items to 2, because every VC_DSR_* series would land in
# goal 1. The reassignments are written out so the choice is auditable.
series_goal <- unique(fread(here("data/02_measure/series_list.csv"))[
  , .(series_code, goal)])
series_goal <- series_goal[series_code %in% colnames(resp)]

n_by_series <- series_goal[, .N, by = series_code]
solo        <- n_by_series[N == 1]$series_code
shared      <- n_by_series[N > 1]$series_code

counts <- setNames(integer(17), as.character(1:17))
tb <- series_goal[series_code %in% solo][, .N, by = goal]
counts[as.character(tb$goal)] <- tb$N

assign_list <- series_goal[series_code %in% solo, .(series_code, goal)]
shared_log  <- vector("list", length(shared))
for (j in seq_along(shared)) {
  sc   <- shared[j]
  opts <- sort(series_goal[series_code == sc]$goal)
  pick <- opts[which.min(counts[as.character(opts)])]
  counts[as.character(pick)] <- counts[as.character(pick)] + 1L
  assign_list <- rbind(assign_list, data.table(series_code = sc, goal = pick))
  shared_log[[j]] <- data.table(series_code = sc,
                                goals_listed = paste(opts, collapse = "/"),
                                goal_assigned = pick)
}
shared_log <- rbindlist(shared_log)
msg("   ", length(shared), " series span several goals; each assigned to its ",
    "thinnest goal")

item_goal <- assign_list[match(colnames(resp), series_code), goal]
stopifnot(!any(is.na(item_goal)))

# specific-factor index: NA = loads on the general factor only
spec <- item_goal
if (!is.na(goal_general_only)) spec[spec == goal_general_only] <- NA_integer_
spec_levels <- sort(unique(spec[!is.na(spec)]))
spec_idx    <- match(spec, spec_levels)   # mirt wants 1..K, NA allowed

msg("   country-years: ", nrow(resp), " | items: ", ncol(resp),
    " | goal factors available: ", length(spec_levels))
