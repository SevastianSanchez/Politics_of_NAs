# ==============================================================================
# build_docs_data.R
#
# Emits the JSON and CSV that the GitHub Pages landing page (docs/index.html)
# reads. Run after the overall fit; the page is static otherwise.
#
# The published measure is the Visible States Index (VSI): one overall score
# per country-year, as `vsi` and `vsi_se`. Column names here should match the
# data dictionary.
#
# The sector layer is also emitted here: `vsi_goal`, one score per country-
# year per goal, with its standard error. Each goal additionally carries the
# three numbers a reader needs to weigh it -- reliability, how concentrated the
# score is in its heaviest series, and how much of its weight rests on series
# the custodian agency produces rather than the country. Nothing is excluded for
# imprecision: 0.70 (Nunnally & Bernstein 1994) is printed as a reference point, not applied as a
# cut. Goals 6 and 15 are marked `hold_content` and goal 7 has no score at all
# (3 series, too few to identify a factor, and all three agency estimates;
# Sevastian, 17 Nov 2026: unscored in both goal layers). See METHODS_LOG.md.
#
# INPUT   01_data/vsi_scores/vsi/irt_vsi_scores.rds   (the VSI scores)
#         01_data/vsi_scores/vsi_goal/irt_vsi_goal_scores.rds  (the sector layer)
#         01_data/vsi_scores/vsi_goal/irt_vsi_goal_health.csv  (per-goal diagnostics)
#         01_data/processed/country_covariates.csv  (country names, income groups)
# OUTPUT  docs/vsi_scores.json, docs/vsi_scores.csv
#         docs/goal_scores.json, docs/goal_scores.csv
# ==============================================================================

suppressPackageStartupMessages({library(data.table); library(here); library(jsonlite)})

s <- as.data.table(readRDS(here("01_data/vsi_scores/vsi/irt_vsi_scores.rds")))
# Country names and income groups: built from their original sources by
# 02_processing/build_country_covariates.R. Income group is that year's World
# Bank classification, so each country-year row carries its own.
cv   <- fread(here("01_data/processed/country_covariates.csv"))
meta <- cv[, .(iso3, year, country_name, income_level)]

s <- merge(s, meta, by = c("iso3", "year"), all.x = TRUE)
s[is.na(country_name), country_name := iso3]
s[is.na(income_level) | income_level == "", income_level := "Unclassified"]

# expand World Bank codes into labels a reader can scan
inc_lab <- c(H = "High income", UM = "Upper-middle income",
             LM = "Lower-middle income", L = "Low income")
s[income_level %in% names(inc_lab), income_level := inc_lab[income_level]]

rows <- s[, .(iso = iso3, name = country_name, inc = income_level, yr = year,
              sc = round(vsi, 3), se = round(vsi_se, 3))]
setorder(rows, iso, yr)

yearly <- s[, .(yr = year[1], mean = round(mean(vsi), 4), n = .N), by = year][, -1]
setorder(yearly, yr)

log1 <- fread(here("01_data/vsi_scores/vsi/irt_vsi_run_log.csv"))

out <- list(
  generated   = format(Sys.time(), "%Y-%m-%d"),
  n_countries = uniqueN(s$iso3),
  years       = range(s$year),
  n_items     = log1$n_items[1],
  n_rows      = nrow(s),
  converged   = log1$converged[1],
  cycles      = log1$cycles[1],
  median_se   = log1$median_se[1],
  yearly      = yearly,
  rows        = rows)

writeLines(toJSON(out, auto_unbox = TRUE, dataframe = "rows", digits = NA),
           here("docs/vsi_scores.json"))
cat("wrote docs/vsi_scores.json |", nrow(rows), "rows |",
    uniqueN(s$iso3), "countries\n")

# the downloadable copy the page links to, so docs/ is self-contained
fwrite(s[, .(iso3, country_name, income_level, year,
             vsi = round(vsi, 4), vsi_se = round(vsi_se, 4))][
         order(iso3, year)],
       here("docs/vsi_scores.csv"))
cat("wrote docs/vsi_scores.csv\n")


# ---- SECTOR LAYER ------------------------------------------------------------
# Written only if the goal-level fit has been run; the overall index does not
# depend on it, so a missing sector layer is not an error here.

gp <- here("01_data/vsi_scores/vsi_goal/irt_vsi_goal_scores.rds")
hp <- here("01_data/vsi_scores/vsi_goal/irt_vsi_goal_health.csv")

if (file.exists(gp) && file.exists(hp)) {
  g <- as.data.table(readRDS(gp))
  h <- fread(hp)

  # vsi_goal_relative (added in v1.4.0): the goal score net of the country's own
  # overall level. Joined on so the site can switch between the two; optional,
  # so the page still builds if the bifactor has not been run.
  rp  <- here("01_data/vsi_scores/vsi_goal_relative/irt_vsi_goal_relative_scores.rds")
  rhp <- here("01_data/vsi_scores/vsi_goal_relative/irt_vsi_goal_relative_health.csv")
  HAS_REL <- file.exists(rp) && file.exists(rhp)
  if (HAS_REL) {
    g  <- merge(g, as.data.table(readRDS(rp)), by = c("iso3", "year", "goal"), all.x = TRUE)
    rh <- fread(rhp)
  }

  SDG_NAME <- c(
    "1" = "No poverty", "2" = "Zero hunger", "3" = "Good health and well-being",
    "4" = "Quality education", "5" = "Gender equality",
    "6" = "Clean water and sanitation", "7" = "Affordable and clean energy",
    "8" = "Decent work and economic growth",
    "9" = "Industry, innovation and infrastructure",
    "10" = "Reduced inequalities", "11" = "Sustainable cities and communities",
    "12" = "Responsible consumption and production", "13" = "Climate action",
    "14" = "Life below water", "15" = "Life on land",
    "16" = "Peace, justice and strong institutions",
    "17" = "Partnerships for the goals")

  h[, goal_name := SDG_NAME[as.character(goal)]]

  # How many series each goal actually has, taken from the shared prep, so a
  # goal that is not fitted can still state its size. MIN_SERIES_DOC mirrors
  # MIN_SERIES in build_irt_vsi_goal.R.
  MIN_SERIES_DOC <- 10L
  if (!exists("item_goal")) source(here("functions/irt_prep.R"))
  N_SERIES_BY_GOAL <- table(item_goal)

  g <- merge(g, meta, by = c("iso3", "year"), all.x = TRUE)
  g[is.na(country_name), country_name := iso3]
  g[is.na(income_level) | income_level == "", income_level := "Unclassified"]
  g[income_level %in% names(inc_lab), income_level := inc_lab[income_level]]

  # Compact shape, so the landing page downloads ~0.4 MB instead of ~2 MB: one
  # entry per country holding a goal x year grid, rather than 28,368 objects
  # repeating their own keys. The long form is in goal_scores.csv for download.
  gyears <- sort(unique(g$year))
  ggoals <- sort(unique(g$goal))
  setorder(g, iso3, goal, year)
  gcountries <- g[, {
    sc <- matrix(round(vsi_goal, 3), nrow = length(ggoals), byrow = TRUE)
    se <- matrix(round(vsi_goal_se, 3), nrow = length(ggoals), byrow = TRUE)
    out <- list(name = country_name[1],
      s  = list(lapply(seq_len(nrow(sc)), function(i) sc[i, ])),
      se = list(lapply(seq_len(nrow(se)), function(i) se[i, ])))
    if (HAS_REL) {
      rs  <- matrix(round(vsi_goal_relative, 3),    nrow = length(ggoals), byrow = TRUE)
      rse <- matrix(round(vsi_goal_relative_se, 3), nrow = length(ggoals), byrow = TRUE)
      out$r   <- list(lapply(seq_len(nrow(rs)),  function(i) rs[i, ]))
      out$rse <- list(lapply(seq_len(nrow(rse)), function(i) rse[i, ]))
    }
    out
  }, by = .(iso = iso3)]

  gmeta <- h[, .(g = goal, name = goal_name, series,
                 rel = reliability, se_med = se_median,
                 conc = weight_top5_pct, agency = weight_agency_pct,
                 status = release)]
  setorder(gmeta, g)
  if (HAS_REL) gmeta <- merge(gmeta, rh[, .(g = goal, rrel = reliability)], by = "g", all.x = TRUE)

  # Goals that exist in the framework but carry too few series to identify a
  # factor are DECLARED, not omitted. An absent goal reads as an abandoned goal;
  # the site renders these as rows with no bar and the reason printed.
  scored   <- sort(unique(h$goal))
  unscored <- setdiff(1:17, scored)
  umeta <- if (length(unscored)) {
    data.table::data.table(
      g      = unscored,
      name   = SDG_NAME[as.character(unscored)],
      series = N_SERIES_BY_GOAL[as.character(unscored)],
      status = "not_scored",
      reason = paste0(N_SERIES_BY_GOAL[as.character(unscored)],
                      " series clear the 2\u201398% filter \u2014 a factor needs ",
                      MIN_SERIES_DOC,
                      ifelse(unscored == 7L, "; all 3 are UN agency estimates, not country data", "")))
  } else NULL

  gout <- list(
    generated = format(Sys.time(), "%Y-%m-%d"),
    note      = paste("One score per country-year per goal, on the same scale",
                      "as the overall index. Every goal fitted is published,",
                      "each with its reliability and standard error; 0.70 is a",
                      "reference point, not a cut. Goals 6 and 15 are held on",
                      "content grounds. Goal 7 has too few series to score."),
    reliability_reference = 0.70,
    n_goals   = nrow(gmeta),
    n_unscored = if (is.null(umeta)) 0L else nrow(umeta),
    years     = gyears,
    goals     = gmeta,
    unscored  = umeta,
    countries = gcountries)

  writeLines(toJSON(gout, auto_unbox = TRUE, dataframe = "rows", digits = NA),
             here("docs/goal_scores.json"))
  cat("wrote docs/goal_scores.json |", nrow(gcountries), "countries x",
      nrow(gmeta), "goals x", length(gyears), "years\n")

  dl <- merge(g[, .(iso3, country_name, income_level, year, goal,
                    vsi_goal = round(vsi_goal, 4),
                    vsi_goal_se = round(vsi_goal_se, 4))],
              h[, .(goal, goal_name, goal_reliability = reliability,
                    goal_status = release)],
              by = "goal", all.x = TRUE)
  cols <- c("iso3","country_name","income_level","year","goal","goal_name",
            "vsi_goal","vsi_goal_se","goal_reliability","goal_status")
  if (HAS_REL) {
    dl <- merge(dl, g[, .(iso3, year, goal,
                          vsi_goal_relative    = round(vsi_goal_relative, 4),
                          vsi_goal_relative_se = round(vsi_goal_relative_se, 4))],
                by = c("iso3", "year", "goal"), all.x = TRUE)
    cols <- c(cols, "vsi_goal_relative", "vsi_goal_relative_se")
  }
  setcolorder(dl, cols)
  fwrite(dl[order(iso3, year, goal)], here("docs/goal_scores.csv"))
  cat("wrote docs/goal_scores.csv\n")
} else {
  cat("sector layer not found -- run 03_measures/vsi_goal/build_irt_vsi_goal.R first\n")
}
