# ==============================================================================
# build_release_bundle.R
#
# Builds the files uploaded to Zenodo for a release, in _release/v<VERSION>/
# (gitignored: nothing here is committed, so the repo keeps one copy of
# everything). Two parts, as in releases/README.md:
#
#   1. The VSI bundle -- what most people download:
#        vsi_scores.csv, vsi_goal_scores.csv, vsi_goal_relative_scores.csv,
#        goal_diagnostics.csv, DATA_DICTIONARY.md, RELEASE_NOTES.md
#   2. A zip of the full repository at the release's git tag, for anyone who
#      wants to check or rerun the work. Built with `git archive`, the same way
#      GitHub builds its "Source code (zip)", so it holds exactly what is
#      committed at the tag and nothing local.
#
# Scores are copied at full precision from 01_data/vsi_scores/; country names
# and income groups are joined from docs/vsi_scores.csv, the published copy.
#
# RUN     VERSION=1.4.0 Rscript 04_publish/build_release_bundle.R
#         The zip step needs the tag v<VERSION> to exist; without it the bundle
#         is still written and the script says the zip was skipped.
# ==============================================================================
suppressPackageStartupMessages({library(data.table); library(here)})

VERSION <- Sys.getenv("VERSION", "1.4.0")
TAG     <- paste0("v", VERSION)
out     <- here("_release", TAG)
dir.create(out, recursive = TRUE, showWarnings = FALSE)
say <- function(...) cat(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), ..., "\n", sep = "")

lab <- unique(fread(here("docs/vsi_scores.csv"))[, .(iso3, country_name, income_level)])
SDG <- unique(fread(here("docs/goal_scores.csv"))[, .(goal, goal_name)])

# ---- scores ------------------------------------------------------------------
v <- merge(fread(here("01_data/vsi_scores/vsi/irt_vsi_scores.csv")), lab, by = "iso3", all.x = TRUE)
setcolorder(v, c("iso3", "country_name", "income_level", "year", "vsi", "vsi_se"))
fwrite(v[order(iso3, year)], file.path(out, "vsi_scores.csv"))

layer <- function(scores, health, val, se) {
  s <- fread(here(scores)); h <- fread(here(health))
  s <- merge(s, lab, by = "iso3", all.x = TRUE)
  s <- merge(s, SDG, by = "goal", all.x = TRUE)
  s <- merge(s, h[, .(goal, status = release)], by = "goal", all.x = TRUE)
  setcolorder(s, c("iso3", "country_name", "income_level", "year", "goal", "goal_name", val, se, "status"))
  s[order(iso3, year, goal)]
}
fwrite(layer("01_data/vsi_scores/vsi_goal/irt_vsi_goal_scores.csv",
             "01_data/vsi_scores/vsi_goal/irt_vsi_goal_health.csv",
             "vsi_goal", "vsi_goal_se"),
       file.path(out, "vsi_goal_scores.csv"))
fwrite(layer("01_data/vsi_scores/vsi_goal_relative/irt_vsi_goal_relative_scores.csv",
             "01_data/vsi_scores/vsi_goal_relative/irt_vsi_goal_relative_health.csv",
             "vsi_goal_relative", "vsi_goal_relative_se"),
       file.path(out, "vsi_goal_relative_scores.csv"))

# ---- per-goal diagnostics, both layers, one table ------------------------------
dcols <- c("goal", "series", "reliability", "se_median", "weight_top5_pct", "weight_agency_pct", "release")
d <- rbind(
  data.table(layer = "vsi_goal",
             fread(here("01_data/vsi_scores/vsi_goal/irt_vsi_goal_health.csv"))[, ..dcols]),
  data.table(layer = "vsi_goal_relative",
             fread(here("01_data/vsi_scores/vsi_goal_relative/irt_vsi_goal_relative_health.csv"))[, ..dcols]))
d <- merge(d, SDG, by = "goal", all.x = TRUE)
setnames(d, "release", "status")
setcolorder(d, c("layer", "goal", "goal_name"))
fwrite(d[order(layer, goal)], file.path(out, "goal_diagnostics.csv"))

# ---- documents -----------------------------------------------------------------
file.copy(here("04_publish/DATA_DICTIONARY.md"), file.path(out, "DATA_DICTIONARY.md"), overwrite = TRUE)
file.copy(here("04_publish/RELEASE_NOTES.md"),   file.path(out, "RELEASE_NOTES.md"),   overwrite = TRUE)
say("bundle written to _release/", TAG, "/")

# ---- full-repository zip at the tag ----------------------------------------------
zipf <- file.path(out, paste0("visible-states-project-", TAG, ".zip"))
has_tag <- system2("git", c("-C", here(), "rev-parse", "-q", "--verify", paste0("refs/tags/", TAG)),
                   stdout = FALSE, stderr = FALSE) == 0
if (has_tag) {
  system2("git", c("-C", here(), "archive", "--format=zip",
                   paste0("--prefix=visible-states-project-", TAG, "/"), "-o", zipf, TAG))
  say("zip written: ", basename(zipf), " (", round(file.size(zipf) / 1e6, 1), " MB)")
} else {
  say("tag ", TAG, " does not exist yet -- zip skipped; re-run after tagging")
}
print(data.table(file = list.files(out), MB = round(file.size(list.files(out, full.names = TRUE)) / 1e6, 2)))
