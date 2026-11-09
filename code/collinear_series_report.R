# ==============================================================================
# collinear_series_report.R
#
# Which surviving series are so nearly collinear that the model cannot give
# them a finite discrimination, what they actually measure, and why the variant
# rule did not collapse them.
#
# The variant rule collapses a cluster only when its series are reported and
# not reported together in EVERY country-year AND their descriptions show they
# measure the same thing. Two things slip through:
#   - series that are identical but semantically different (kept on purpose);
#   - series that agree 99-point-something percent but not 100% (never
#     clustered, because the rule requires exact identity).
# Both produce the same numerical symptom: a discrimination running to infinity.
#
# OUTPUT  output/measure/tables/collinear_series.csv
# ==============================================================================
source(here::here("code/packages.R"))
library(here); suppressPackageStartupMessages(library(data.table))

THRESH <- 0.98   # report any pair agreeing on at least this share of country-years

sl <- unique(fread(here("data/02_measure/series_list.csv"))[
  , .(series_code, series_description, goal, indicator)])
sl <- sl[, .(goal = paste(sort(unique(goal)), collapse = "/"),
             indicator = indicator[1],
             series_description = series_description[1]), by = series_code]
vm <- fread(here("data/02_measure/series_variant_map.csv"))[
  , .(series_code, units, verdict, cluster)]

x <- as.data.table(readRDS(here("data/02_measure/agg_series_depth.rds")))
x <- x[, .(r = any(reported)), by = .(iso3, series_code, year)]
g <- CJ(iso3 = sort(unique(x$iso3)), series_code = sort(unique(x$series_code)),
        year = sort(unique(x$year)), unique = TRUE)
g <- merge(g, x, by = c("iso3", "series_code", "year"), all.x = TRUE)
g[, y := as.integer(!is.na(r) & r)]
w <- dcast(g, iso3 + year ~ series_code, value.var = "y")
M <- as.matrix(w[, -(1:2)])

# restrict to the 524 the model actually fits
p <- colMeans(M); M <- M[, p > 0.02 & p < 0.98, drop = FALSE]
reps <- fread(here("data/02_measure/series_variant_map.csv"))[
  series_code == cluster | verdict != "collapse"]$series_code
M <- M[, colnames(M) %in% reps, drop = FALSE]
N <- nrow(M); J <- ncol(M)
cat("screening", J, "series over", N, "country-years\n")

# agreement = share of country-years where two series take the same value
agree <- 1 - as.matrix(dist(t(M), method = "manhattan")) / N
diag(agree) <- 0
hits <- which(agree >= THRESH, arr.ind = TRUE)
hits <- hits[hits[, 1] < hits[, 2], , drop = FALSE]
cat(nrow(hits), "pairs agree on >=", sprintf("%.0f%%", 100 * THRESH),
    "of country-years\n")

# connected components, so a trio is reported as one group
grp <- seq_len(J); names(grp) <- colnames(M)
for (k in seq_len(nrow(hits))) {
  a <- grp[hits[k, 1]]; b <- grp[hits[k, 2]]
  if (a != b) grp[grp == b] <- a
}
inv <- table(grp); keep <- names(inv)[inv > 1]
out <- rbindlist(lapply(keep, function(k) {
  cs <- colnames(M)[grp == as.integer(k)]
  sub <- M[, cs, drop = FALSE]
  pw  <- agree[cs, cs, drop = FALSE]
  data.table(group = paste0("G", match(k, keep)),
             series_code = cs,
             min_pair_agreement = round(min(pw[upper.tri(pw) | lower.tri(pw)]), 4),
             disagreeing_country_years =
               sum(apply(sub, 1, function(z) length(unique(z)) > 1)),
             pct_reported = round(100 * colMeans(sub), 1))
}))
out <- merge(out, sl, by = "series_code", all.x = TRUE)
out <- merge(out, vm, by = "series_code", all.x = TRUE)
out[, why_not_collapsed := fifelse(
  disagreeing_country_years > 0,
  "patterns NOT identical -- rule requires exact identity, so no cluster formed",
  fifelse(verdict == "keep_separate",
          "identical patterns, but descriptions differ: kept on purpose",
    fifelse(verdict == "review",
            "identical patterns, flagged REVIEW -- never adjudicated",
            paste0("identical patterns, verdict '", verdict, "'"))))]
setorder(out, group, series_code)
print(out[, .(group, series_code, goal, pct_reported, disagree = disagreeing_country_years,
              verdict, units)], nrows = 200)
cat("\n--- descriptions ---\n")
for (gg in unique(out$group)) {
  s <- out[group == gg]
  cat("\n", gg, "  (", s$why_not_collapsed[1], ")\n", sep = "")
  for (i in seq_len(nrow(s)))
    cat("   ", s$series_code[i], " [", s$units[i], "] ", s$series_description[i], "\n", sep = "")
}
fwrite(out, here("output/measure/tables/collinear_series.csv"))
cat("\nwrote output/measure/tables/collinear_series.csv |", uniqueN(out$group),
    "groups,", nrow(out), "series\n")
