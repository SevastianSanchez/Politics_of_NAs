# ==============================================================================
# build_variant_map.R
#
# Identifies groups of SDG series that are the SAME MEASUREMENT RECORDED MORE
# THAN ONCE -- e.g. SH_STA_STNT (children stunted, %) and SH_STA_STNTN
# (children stunted, thousands) -- so the IRT fits can count each reporting
# decision once instead of once per variant.
#
# WHY THIS MATTERS
#   A country should not score higher because one measurement it reported was
#   written into the database as three series codes, while another country's
#   single-variant series earns one point. That is a fairness-of-weighting
#   problem, and it is the reason this file exists. (Conditional independence
#   in the IRT model is a second, technical reason, but the weighting argument
#   is the one that belongs in the paper.)
#
# WHAT IS *NOT* DONE HERE
#   Series are NOT aggregated up to the UN indicator level. An indicator can
#   contain a variant family plus series that measure genuinely different
#   things, and collapsing the whole indicator would erase the latter. The
#   index is deliberately at goal x series granularity; only provably redundant
#   series are merged.
#
# THE RULE -- BOTH CONDITIONS MUST HOLD
#   (1) STRUCTURAL. The series' reported/not patterns are byte-identical across
#       every country-year in the panel. No country has ever reported one
#       without the other, so no reporting choice is visible between them.
#   (2) SEMANTIC. They actually measure the same thing another way: their
#       descriptions share a stem once unit words are stripped. Same indicator
#       and differing units are corroborating evidence, NOT requirements --
#       genuine rate/count pairs such as SH_DYN_IMRT and SH_DYN_IMRTN span two
#       indicators (3.2.1 and 3.2.2).
#
#   Condition (1) alone is not sufficient and must never be used alone. Series
#   reported by nearly every country-year have almost no variation, so unrelated
#   ones coincide trivially: forest certification, electricity access, GDP per
#   capita and refugee counts all share one pattern at 99.5% reported. A purely
#   structural rule would merge those eight into one.
#
#   Comparison is PAIRWISE WITHIN each identical-pattern group, not group-wide.
#   {forest %, forest hectares, total land area} share a pattern, but only the
#   first two are variants; pairwise clustering collapses those and leaves land
#   area standing.
#
# OUTPUT  data/02_measure/series_variant_map.csv
#           one row per series in scope: its cluster id, the representative
#           series the cluster collapses to, the verdict, and the evidence.
#           irt_prep.R reads this and applies it. Every decision is auditable
#           and any row can be overridden by editing `verdict`.
#
# Groups that pass (1) but fail (2) are recorded as "keep_separate" -- never
# merged silently. Borderline similarity is recorded as "review" and NOT
# merged, so the conservative choice is the default.
#
# Run this whenever the UN export is refreshed, BEFORE the IRT fits.
# irt_prep.R re-asserts condition (1) at fit time and halts if it has broken.
# ==============================================================================

source(here::here("code/packages.R"))
library(here)
suppressPackageStartupMessages(library(data.table))

msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), ..., "\n", sep = "")

item_lo <- 0.02   # must match irt_prep.R: only series that survive the
item_hi <- 0.98   # prevalence filter are ever fitted, so judge the rule on those
sim_confirm <- 0.34   # description similarity at/above this = same measurement
sim_review  <- 0.20   # between the two = flagged for review, left separate

# ---- A. THE SERIES IN SCOPE --------------------------------------------------

msg("building the response patterns")

depth <- as.data.table(readRDS(here("data/02_measure/agg_series_depth.rds")))
depth <- depth[, .(reported = any(reported)), by = .(iso3, series_code, year)]
grid  <- CJ(iso3        = sort(unique(depth$iso3)),
            series_code = sort(unique(depth$series_code)),
            year        = sort(unique(depth$year)), unique = TRUE)
cells <- merge(grid, depth, by = c("iso3", "series_code", "year"), all.x = TRUE)
cells[, y := as.integer(!is.na(reported) & reported)]
wide  <- dcast(cells, iso3 + year ~ series_code, value.var = "y")
M     <- as.matrix(wide[, -(1:2)])

p_rep <- colMeans(M)
M <- M[, which(p_rep > item_lo & p_rep < item_hi), drop = FALSE]
msg("   series in scope after the ", item_lo * 100, "-", item_hi * 100,
    "% filter: ", ncol(M))

# ---- B. SERIES METADATA -----------------------------------------------------

sl <- unique(fread(here("data/02_measure/series_list.csv"))[
  , .(series_code, indicator)])
sl <- sl[, .(indicator = paste(sort(unique(indicator)), collapse = ",")),
         by = series_code]
meta <- unique(fread(here("data/02_measure/raw_data.csv.gz"),
                     select = c("series_code", "series_description", "units")))
meta <- meta[, .SD[1], by = series_code]
info <- merge(data.table(series_code = colnames(M)), sl,   by = "series_code", all.x = TRUE)
info <- merge(info,                                 meta, by = "series_code", all.x = TRUE)

# Strip unit and quantifier words so only the phenomenon is compared. Without
# this, "Proportion of children stunted (%)" and "Children stunted (thousands)"
# look less alike than they are.
norm_desc <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("\\(.*?\\)", " ", x)
  x <- gsub(paste0("\\b(proportion|percentage|percent|number|total|share|rate|",
                   "per|of|the|in|and|capita|thousands|millions|index)\\b"), " ", x)
  x <- gsub("[^a-z ]", " ", x)
  trimws(gsub("\\s+", " ", x))
}
info[, ndesc := norm_desc(series_description)]

jacc <- function(a, b) {
  A <- unique(strsplit(a, " ")[[1]]); B <- unique(strsplit(b, " ")[[1]])
  A <- A[nchar(A) > 2]; B <- B[nchar(B) > 2]
  if (!length(A) || !length(B)) return(0)
  length(intersect(A, B)) / length(union(A, B))
}

# ---- C. CONDITION (1): IDENTICAL PRESENCE PATTERNS --------------------------

pat <- apply(M, 2, paste0, collapse = "")
info[, pattern := pat[series_code]]
info[, pgid := .GRP, by = pattern]
cand <- info[, .N, by = pgid][N > 1]$pgid
msg("   groups with identical presence patterns: ", length(cand),
    " covering ", nrow(info[pgid %in% cand]), " series")

# ---- D. CONDITION (2): PAIRWISE SEMANTIC CLUSTERING WITHIN EACH GROUP -------
# Build a graph per group (edge = descriptions similar enough), take connected
# components. A component with >1 member is a variant cluster; singletons stay
# separate even though they share the pattern.

info[, `:=`(cluster = series_code, verdict = "single", evidence = "")]

for (g in cand) {
  idx <- which(info$pgid == g)
  s   <- info[idx]
  n   <- nrow(s)
  adj <- matrix(FALSE, n, n)
  sim <- matrix(0, n, n)
  for (i in 1:(n - 1)) for (j in (i + 1):n) {
    v <- jacc(s$ndesc[i], s$ndesc[j]); sim[i, j] <- sim[j, i] <- v
    adj[i, j] <- adj[j, i] <- v >= sim_confirm
  }
  comp <- rep(NA_integer_, n); k <- 0L
  for (i in 1:n) {
    if (!is.na(comp[i])) next
    k <- k + 1L; stack <- i
    while (length(stack)) {
      v <- stack[1]; stack <- stack[-1]
      if (!is.na(comp[v])) next
      comp[v] <- k
      stack <- c(stack, which(adj[v, ] & is.na(comp)))
    }
  }
  for (cc in unique(comp)) {
    mem <- which(comp == cc)
    rows <- idx[mem]
    if (length(mem) > 1) {
      # representative: the alphabetically first code, so the choice is stable
      rep_code <- sort(info$series_code[rows])[1]
      info[rows, `:=`(cluster = rep_code, verdict = "collapse",
        evidence = sprintf("identical pattern; min desc similarity %.2f; indicators %s; units %s",
          min(sim[mem, mem][upper.tri(sim[mem, mem])]),
          paste(unique(info$indicator[rows]), collapse = "/"),
          paste(unique(info$units[rows]), collapse = "/")))]
    } else {
      others <- setdiff(seq_len(n), mem)
      best <- if (length(others)) max(sim[mem, others]) else 0
      info[rows, `:=`(verdict = if (best >= sim_review) "review" else "keep_separate",
        evidence = sprintf("identical pattern with %d other series but best desc similarity only %.2f",
                           length(others), best))]
    }
  }
}

# ---- E. UNIT TEST: RE-ASSERT CONDITION (1) ----------------------------------
# Every cluster marked "collapse" must move as one unit in every country-year.
# If a refreshed export breaks this, the map is wrong and must not be used.

msg("unit test: asserting every collapse cluster moves as one unit")
fails <- info[verdict == "collapse", {
  sub <- M[, series_code, drop = FALSE]
  .(disagreeing_country_years =
      sum(apply(sub, 1, function(z) length(unique(z[!is.na(z)])) > 1)))
}, by = cluster][disagreeing_country_years > 0]

if (nrow(fails)) {
  print(fails)
  stop("variant map FAILED its own test: the clusters above contain series that ",
       "do NOT always move together. Re-run after inspecting them; do not ",
       "collapse these.", call. = FALSE)
}
msg("   PASS -- ", uniqueN(info[verdict == "collapse"]$cluster),
    " clusters, 0 failures")

# ---- F. WRITE ----------------------------------------------------------------

out <- info[, .(series_code, indicator, units, series_description,
                pattern_group = pgid, cluster, verdict, evidence)]
setorder(out, verdict, cluster, series_code)
fwrite(out, here("data/02_measure/series_variant_map.csv"))

tally <- out[, .(series = .N), by = verdict][order(-series)]
print(tally)
msg("series in scope: ", nrow(out),
    " -> ", uniqueN(out$cluster), " after collapsing")
msg("wrote data/02_measure/series_variant_map.csv")
msg("done.")
