# ==============================================================================
# build_docs_goal_preview.R
#
# PLACEHOLDER generator for the goal-level section of docs/index.html.
#
# Emits RAW reporting shares per country-goal-year -- the fraction of that
# goal's series the country published. These are NOT the released measure.
# When the bifactor fit lands, this file is replaced by goal_deviation /
# goal_level from irt_goal_scores.rds and the page's "preview" banner comes
# off. The layout and the interaction are built against this so the swap is a
# data change, not a rewrite.
#
# Uses the same 607-item matrix and the same thinnest-goal assignment as the
# model, via irt_prep.R, so the preview cannot drift from the real thing.
#
# OUTPUT  docs/goal_preview.json
# ==============================================================================

suppressMessages(source(here::here("code/data_prep/irt_prep.R")))
suppressPackageStartupMessages(library(jsonlite))

lab <- c("No poverty","Zero hunger","Good health","Quality education",
         "Gender equality","Clean water","Decent work","Industry & innovation",
         "Reduced inequalities","Sustainable cities","Responsible consumption",
         "Climate action","Life below water","Life on land",
         "Peace & justice","Partnerships")
names(lab) <- as.character(spec_levels)

gl <- rbindlist(lapply(seq_along(spec_levels), function(k) {
  it <- which(spec_idx == k)
  data.table(keys, goal = spec_levels[k], n_items = length(it),
             share = round(rowMeans(resp[, it, drop = FALSE]), 4))
}))

a <- as.data.table(readRDS(here("data/03_panels/analysis_data.rds")))
meta <- unique(a[, .(iso3, country_name)])[!is.na(iso3)][, .SD[1], by = iso3]
gl <- merge(gl, meta, by = "iso3", all.x = TRUE)
gl[is.na(country_name), country_name := iso3]

yrs <- sort(unique(gl$year))
setorder(gl, iso3, goal, year)

# nested: country -> goal -> one value per year, which keeps the file small
countries <- gl[, .(name = country_name[1]), by = iso3][order(iso3)]
series <- gl[, .(v = list(share)), by = .(iso3, goal)]
wide <- dcast(series, iso3 ~ goal, value.var = "v")

out <- list(
  preview   = TRUE,
  generated = format(Sys.Date()),
  years     = yrs,
  goals     = lapply(as.character(spec_levels), function(g) list(
                 g = as.integer(g), label = unname(lab[g]),
                 n_items = gl[goal == as.integer(g), n_items[1]])),
  countries = lapply(seq_len(nrow(countries)), function(i) {
                 iso <- countries$iso3[i]
                 list(iso = iso, name = countries$name[i],
                      s = lapply(as.character(spec_levels),
                                 function(g) wide[iso3 == iso][[g]][[1]]))
               }))

writeLines(toJSON(out, auto_unbox = TRUE, digits = NA),
           here("docs/goal_preview.json"))
cat("wrote docs/goal_preview.json |", nrow(countries), "countries x",
    length(spec_levels), "goals x", length(yrs), "years\n")
