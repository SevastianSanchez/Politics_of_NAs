# =============================================================================
# Politics of NAs — predictor panel builder
# =============================================================================
#
# WHAT THIS DOES
# Builds the country-year panel of treatment and control variables from its
# sources, so the predictor side of the analysis is reproducible. Replaces
# data/03_panels/sdg_democracy_paneldata.rds, which had no builder: it existed on
# disk, four scripts read it, and nothing could regenerate it.
#
# OUTPUT: data/03_panels/predictor_panel.{rds,csv}  — one row per country x year
#   Written under a NEW name on purpose. The old orphan file stays in place as
#   a comparison reference (Section G). Once you trust this, point
#   causal_inf_data_prep.R reads it (the switch has been made).
#
# WHY SNAPSHOTS (Section C)
# V-Dem and WDI revise their back-history between releases. Measured against
# the April 2026 orphan: V-Dem lib_dem matched on only 203 of 1,548
# country-years (correlation 0.9998 — same construct, revised values). So a
# builder that pulls live produces a different panel every run, and published
# results would not be reproducible. Each live source is therefore written to
# data/01_source/snapshots/ with its pull date and read from there by default.
# Set refresh_sources <- TRUE to re-pull and write a new snapshot.
#
# THE SDR COLUMNS CARRY AN _sdr SUFFIX
# prop_sdg_missing_sdr and prop_miss_SDG1-17_sdr are the OLD outcome, computed
# from the Sustainable Development Report workbook. They are kept only so the
# superseded measure can be compared against the UN Global Database measure in
# data/02_measure/. They are not predictors and must not be used as controls.
# The 126 raw sdg* achievement scores are read, counted, and discarded — they
# were carried in the orphan but referenced nowhere in the codebase.
#
# PROVENANCE OF THE LOOKUPS IN SECTION B
# The country-alias and non-country tables are lifted from
# df_years2.0_Function_dataloss_proj.R (the QMSS-era script). They encode
# accumulated knowledge about which names countrycode() cannot resolve, which
# is not recoverable from anywhere else.
# =============================================================================

suppressPackageStartupMessages({
# here::here() resolves from the .Rproj root whatever the working directory is,
# so this file works when sourced, run line-by-line, or knitted.
library(here)
  library(readxl); library(readr); library(dplyr); library(tidyr)
  library(stringr); library(countrycode); library(purrr)
})


# =============================================================================
# A. CONFIGURATION
# =============================================================================
start_year <- 2015L
end_year   <- 2023L

# TRUE re-pulls V-Dem and WDI and writes new dated snapshots.
# FALSE (default) reads the newest snapshot on disk — reproducible.
refresh_sources <- FALSE

snapshot_dir <- here("data/01_source/snapshots")
output_dir   <- here("data/03_panels")
dir.create(snapshot_dir, recursive = TRUE, showWarnings = FALSE)

# Frozen inputs: files on disk, so they cannot drift between runs.
path_sdr        <- here("data/01_source/SDR2025-data.xlsx")
sheet_sdr       <- "All Raw Data"
path_ert        <- here("data/01_source/ert.csv")
path_gdppc      <- here("data/01_source/gdppc_df_long.csv")
path_income     <- here("data/01_source/world_bank_income_classifications.csv")
path_orphan     <- here("data/03_panels/sdg_democracy_paneldata.rds")   # reference only


# =============================================================================
# B. HARVESTED LOOKUPS
# =============================================================================
# Names countrycode() resolves wrongly or not at all. Source:
# df_years2.0_Function_dataloss_proj.R, custom_match_forward.
country_alias_to_iso3 <- c(
  "Kosovo"                     = "XKX",
  "Somaliland"                 = "SOL",
  "Zanzibar"                   = "ZNZ",
  "Channel Islands"            = "CHI",
  "Saint Martin (French part)" = "MAF",
  "Curaçao"                    = "CUW",
  "West Bank and Gaza"         = "PSE",
  "Congo (Kinshasa)"           = "COD",
  "Myanmar (Burma)"            = "MMR",
  "Iran, Islamic Rep."         = "IRN",
  "Kyrgyz Republic"            = "KGZ",
  "Bahamas"                    = "BHS",
  "Belize"                     = "BLZ",
  "Brunei"                     = "BRN",
  "South Sudan"                = "SSD"
)

# Aggregate / regional / defunct codes that must never become panel units.
# Source: same script, non_countries.
non_country_codes <- c(
  "_AFRICA","_BRICS","_BRICSPLUS","_E_EURO_ASIA","_E_S_ASIA","_HIC","_LAC",
  "_LIC","_LMIC","_MENA","_OCEANIA","_OECD","_SIDS","_UMIC","_WORLD",
  "EAP","ECA","IBD","IBT","IDA","LAC","MNA","SAS","SSA",
  "AFE","AFW","ARB","CEB","CSS","EAR","EAS","ECS","EMU","EUU","FCS",
  "HIC","HPC","IDB","IDX","INX","LCN","LDC","LIC","LMC","LMY","LTE",
  "MEA","MIC","NAC","OED","OSS","PRE","PSS","PST","TSA","TSS","UMC",
  "WLD","TEA","TEC","TLA","TMN","SST","SSF","OWID_WRL",
  "ANT","CSK","SUN","YUG","YUGF"
)

# Drop aggregates, then keep only the analysis window.
trim_panel <- function(df, code_col = "country_code") {
  df %>%
    filter(!.data[[code_col]] %in% non_country_codes,
           !is.na(.data[[code_col]]),
           year >= start_year, year <= end_year)
}


# =============================================================================
# C. SNAPSHOT LAYER
# =============================================================================
# snap() is the only way a live source enters the panel. It reads the newest
# dated snapshot unless refresh_sources is TRUE, in which case it calls pull_fn
# and writes a new one. Every write also appends to a manifest, so the paper can
# state exactly which vintage the results rest on.
manifest_path <- file.path(snapshot_dir, "_manifest.csv")

snap <- function(name, pull_fn) {
  existing <- sort(list.files(snapshot_dir, pattern = paste0("^", name, "__\\d{4}-\\d{2}-\\d{2}\\.csv$"),
                              full.names = TRUE), decreasing = TRUE)

  if (!refresh_sources && length(existing) > 0) {
    message("  [snapshot] ", name, " <- ", basename(existing[1]))
    return(read_csv(existing[1], show_col_types = FALSE, progress = FALSE))
  }

  if (!refresh_sources && length(existing) == 0) {
    message("  [snapshot] ", name, ": none on disk — pulling live and creating the first one")
  } else {
    message("  [snapshot] ", name, ": refresh_sources = TRUE — pulling live")
  }

  d    <- pull_fn()
  stamp <- format(Sys.Date(), "%Y-%m-%d")
  out  <- file.path(snapshot_dir, paste0(name, "__", stamp, ".csv"))
  write_csv(d, out)

  row <- tibble(source = name, file = basename(out), pulled = stamp,
                rows = nrow(d), cols = ncol(d))
  # Read the manifest as all-character so `pulled` is not inferred as a Date,
  # which would fail to bind against the character stamp above.
  if (file.exists(manifest_path)) {
    prev <- read_csv(manifest_path, col_types = cols(.default = col_character()),
                     progress = FALSE)
    write_csv(bind_rows(prev, mutate(row, across(everything(), as.character))),
              manifest_path)
  } else {
    write_csv(row, manifest_path)
  }
  message("  [snapshot] wrote ", basename(out), " (", nrow(d), " rows)")
  d
}


# =============================================================================
# D. SOURCES
# =============================================================================
message("\nLoading sources")

# ---- D1. V-Dem (live package, snapshotted) ----------------------------------
# Only the columns the analysis uses, so the snapshot stays small.
vdem <- snap("vdem", function() {
  vdemdata::vdem %>%
    filter(year >= start_year, year <= end_year) %>%
    transmute(country_code = country_text_id, year = as.integer(year),
              elect_dem      = v2x_polyarchy,
              lib_dem        = v2x_libdem,
              part_dem       = v2x_partipdem,
              egal_dem       = v2x_egaldem,
              delib_dem      = v2x_delibdem,
              v2x_liberal    = v2x_liberal,
              regime_type_4  = v2x_regime,
              regime_type_10 = v2x_regime_amb)
}) %>% trim_panel()

# ---- D2. ERT episodes (frozen file) -----------------------------------------
# ERT also carries its own v2x_polyarchy; it is kept as elect_dem_ert because
# the ERT release is frozen while the V-Dem package revises, so the two differ.
# regch_genuine is the signed regime-change event, zeroed where ERT marks the
# observation censored. G_aut / D_aut are the Callaway-Sant'Anna group and
# treatment indicators: G_aut is the episode start year for treated units and
# NA for never-treated; D_aut flags country-years inside an episode.
ert <- read_csv(path_ert, show_col_types = FALSE, progress = FALSE) %>%
  transmute(
    country_code    = country_text_id,
    year            = as.integer(year),
    elect_dem_ert   = v2x_polyarchy,
    regime_type_2   = reg_type,
    regch_event     = row_regch_event,
    regch_genuine   = if_else(row_regch_censored == 0, row_regch_event, 0),
    dem_ep, dem_ep_id,
    dem_ep_pre_yr   = dem_pre_ep_year,
    dem_ep_start_yr = dem_ep_start_year,
    dem_ep_end_yr   = dem_ep_end_year,
    aut_ep, aut_ep_id,
    aut_ep_pre_yr   = aut_pre_ep_year,
    aut_ep_start_yr = aut_ep_start_year,
    aut_ep_end_yr   = aut_ep_end_year,
    G_aut           = if_else(aut_ep == 1, aut_ep_start_year, NA_real_),
    D_aut           = if_else(aut_ep == 1, 1L, 0L)
  ) %>% trim_panel()

# ---- D3. SDR missingness (frozen workbook) ----------------------------------
# The superseded outcome. Verified to reproduce the orphan's values exactly
# (max |difference| 0.00000000 on all 18 columns, all 17 goals).
# The 126 raw achievement columns are counted and then dropped.
message("  [frozen]   SDR missingness <- ", basename(path_sdr))
sdr_raw  <- read_excel(path_sdr, sheet = sheet_sdr)
sdr_cols <- grep("^sdg", names(sdr_raw), value = TRUE)
sdr_goal <- as.integer(str_extract(sdr_cols, "(?<=^sdg)[0-9]{1,2}"))

sdr_num <- sdr_raw %>%
  transmute(country_code = id, year = as.integer(year)) %>%
  bind_cols(as_tibble(lapply(sdr_raw[sdr_cols], function(x) suppressWarnings(as.numeric(x)))))

# Overall, then one column per goal, each the NA share of that goal's indicators.
sdr <- sdr_num %>%
  transmute(country_code, year,
            n_sdg_indicators_sdr = length(sdr_cols),
            n_sdg_missing_sdr    = rowSums(is.na(across(all_of(sdr_cols)))),
            prop_sdg_missing_sdr = n_sdg_missing_sdr / n_sdg_indicators_sdr)

for (g in 1:17) {
  gc <- sdr_cols[sdr_goal == g]
  sdr[[paste0("prop_miss_SDG", g, "_sdr")]] <-
    rowSums(is.na(sdr_num[gc])) / length(gc)
}
sdr <- trim_panel(sdr)

# ---- D4. WDI controls (live API, snapshotted) -------------------------------
wdi_indicators <- c(electric_access     = "EG.ELC.ACCS.ZS",
                    rural_pop_pct       = "SP.RUR.TOTL.ZS",
                    rd_expenditure_pct  = "GB.XPD.RSDV.GD.ZS",
                    total_pop           = "SP.POP.TOTL",
                    tax_rev_gdp         = "GC.TAX.TOTL.GD.ZS")

wdi <- snap("wdi", function() {
  imap(wdi_indicators, function(code, nm) {
    WDI::WDI(country = "all", indicator = code,
             start = start_year, end = end_year) %>%
      transmute(country_code = iso3c, year = as.integer(year),
                !!nm := .data[[code]])
  }) %>% reduce(full_join, by = c("country_code", "year"))
}) %>% trim_panel()

# ---- D5. GDP per capita and income classification (frozen files) ------------
message("  [frozen]   GDP per capita <- ", basename(path_gdppc))
gdppc <- read_csv(path_gdppc, show_col_types = FALSE, progress = FALSE) %>%
  transmute(country_code, year = as.integer(year), gdp_pc) %>% trim_panel()

message("  [frozen]   income classification <- ", basename(path_income))
income <- read_csv(path_income, show_col_types = FALSE, progress = FALSE) %>%
  transmute(country_code, year = as.integer(year), income_level) %>% trim_panel()


# =============================================================================
# E. COUNTRY HARMONISATION
# =============================================================================
# Every source above already keys on an ISO3-shaped code, so this validates
# rather than converts: anything countrycode cannot recognise, and that the
# harvested alias table does not cover, is reported instead of dropped
# silently. That reporting is the behaviour worth keeping from
# df_years2.0_Function_dataloss_proj.R.
known_iso3 <- unique(na.omit(countrycode::codelist$iso3c))

check_codes <- function(df, label) {
  bad <- setdiff(unique(df$country_code),
                 c(known_iso3, unname(country_alias_to_iso3)))
  if (length(bad) > 0) {
    message("  [codes] ", label, ": ", length(bad),
            " unrecognised code(s) dropped: ", paste(head(bad, 12), collapse = ", "))
  }
  df %>% filter(country_code %in% c(known_iso3, unname(country_alias_to_iso3)))
}

message("\nHarmonising country codes")
vdem   <- check_codes(vdem,   "vdem")
ert    <- check_codes(ert,    "ert")
sdr    <- check_codes(sdr,    "sdr")
wdi    <- check_codes(wdi,    "wdi")
gdppc  <- check_codes(gdppc,  "gdppc")
income <- check_codes(income, "income")


# =============================================================================
# F. ASSEMBLE
# =============================================================================
# V-Dem defines the panel frame: a country-year needs a democracy score to be
# usable, since that is the treatment. Everything else joins onto it, so a
# source missing a country-year yields NA rather than dropping the row.
message("\nAssembling")

predictor_panel <- vdem %>%
  left_join(ert,    by = c("country_code", "year")) %>%
  left_join(sdr,    by = c("country_code", "year")) %>%
  left_join(wdi,    by = c("country_code", "year")) %>%
  left_join(gdppc,  by = c("country_code", "year")) %>%
  left_join(income, by = c("country_code", "year")) %>%
  mutate(
    # countrycode cannot name XKX (Kosovo has no official ISO3), so the
    # harvested alias table supplies it — same reason it exists in Section B.
    country_name = coalesce(
      suppressWarnings(countrycode(country_code, "iso3c", "country.name")),
      setNames(names(country_alias_to_iso3),
               unname(country_alias_to_iso3))[country_code]),
    # Computed here, from the same pull as their inputs. In the orphan these
    # drifted apart: total_pop had no NAs while log_pop had 179 and differed
    # by up to 0.218 in logs, because the two came from different WDI vintages.
    log_gdppc = log(gdp_pc),
    log_pop   = log(total_pop)
  ) %>%
  select(country_name, country_code, year, everything()) %>%
  arrange(country_code, year)

# A country-year must appear once, or every downstream join fans out.
stopifnot(nrow(predictor_panel) ==
          nrow(distinct(predictor_panel, country_code, year)))

message("  predictor_panel: ", nrow(predictor_panel), " rows x ",
        ncol(predictor_panel), " cols | ",
        n_distinct(predictor_panel$country_code), " countries x ",
        n_distinct(predictor_panel$year), " years")


# =============================================================================
# G. VALIDATION AGAINST THE ORPHAN
# =============================================================================
# The orphan is a sanity reference, NOT ground truth — it is a April 2026
# snapshot and is internally inconsistent (see the log_pop note in Section F).
# So the test differs by source type:
#   frozen sources  -> must match EXACTLY; any difference is a real defect
#   live sources    -> expected to differ by vintage; check correlation and
#                      shape instead, and report the drift rather than hide it
if (file.exists(path_orphan)) {
  message("\nValidation against ", basename(path_orphan))
  orph <- readRDS(path_orphan) %>% mutate(year = as.integer(year))
  j <- predictor_panel %>%
    inner_join(orph, by = c("country_code", "year"), suffix = c(".new", ".old"))
  message("  overlapping country-years: ", nrow(j))

  compare <- function(col, kind) {
    a <- paste0(col, ".new"); b <- paste0(col, ".old")
    if (!all(c(a, b) %in% names(j))) {
      if (col %in% names(orph) && col %in% names(predictor_panel)) { a <- col; b <- col }
      else return(tibble(column = col, kind = kind, verdict = "not in both"))
    }
    x <- suppressWarnings(as.numeric(j[[a]])); y <- suppressWarnings(as.numeric(j[[b]]))
    both <- !is.na(x) & !is.na(y)
    if (!any(both)) return(tibble(column = col, kind = kind, verdict = "no overlap"))
    md <- max(abs(x[both] - y[both]))
    cr <- if (sd(x[both]) > 0 && sd(y[both]) > 0) cor(x[both], y[both]) else NA_real_
    tibble(column = col, kind = kind,
           n = sum(both), exact = sum(abs(x[both] - y[both]) < 1e-9),
           max_diff = round(md, 6), cor = round(cr, 6),
           verdict = dplyr::case_when(
             md < 1e-9                        ~ "exact",
             kind == "frozen"                 ~ "MISMATCH — investigate",
             !is.na(cr) && cr > 0.99          ~ "vintage drift (expected)",
             TRUE                             ~ "DIVERGENT — investigate"))
  }

  frozen_cols <- c("prop_sdg_missing_sdr", paste0("prop_miss_SDG", 1:17, "_sdr"),
                   "gdp_pc", "elect_dem_ert", "regime_type_2",
                   "aut_ep", "dem_ep", "aut_ep_start_yr")
  live_cols   <- c("elect_dem", "lib_dem", "part_dem", "egal_dem", "delib_dem",
                   "regime_type_4", "regime_type_10",
                   "electric_access", "rural_pop_pct", "total_pop")

  # The SDR columns were renamed, so compare the new _sdr name to the old one.
  rn <- c(prop_sdg_missing_sdr = "prop_sdg_missing",
          setNames(paste0("prop_miss_SDG", 1:17), paste0("prop_miss_SDG", 1:17, "_sdr")))
  for (newn in names(rn)) {
    oldn <- rn[[newn]]
    if (newn %in% names(predictor_panel) && oldn %in% names(orph)) {
      j[[paste0(newn, ".new")]] <- predictor_panel[[newn]][
        match(paste(j$country_code, j$year),
              paste(predictor_panel$country_code, predictor_panel$year))]
      j[[paste0(newn, ".old")]] <- orph[[oldn]][
        match(paste(j$country_code, j$year), paste(orph$country_code, orph$year))]
    }
  }

  res <- bind_rows(
    map_dfr(frozen_cols, compare, kind = "frozen"),
    map_dfr(live_cols,   compare, kind = "live"))
  print(as.data.frame(res), row.names = FALSE)

  bad <- res %>% filter(grepl("investigate", verdict))
  if (nrow(bad) > 0) {
    warning(nrow(bad), " column(s) need investigation: ",
            paste(bad$column, collapse = ", "))
  } else {
    message("  All frozen columns reproduce exactly; live columns within vintage drift.")
  }
} else {
  message("\nNo orphan file at ", path_orphan, " — skipping validation.")
}


# =============================================================================
# H. WRITE
# =============================================================================
saveRDS(predictor_panel, file.path(output_dir, "predictor_panel.rds"))
write_csv(predictor_panel, file.path(output_dir, "predictor_panel.csv"))

message("\nWrote data/03_panels/predictor_panel.{rds,csv}")
if (file.exists(manifest_path)) {
  message("Source vintages (data/01_source/snapshots/_manifest.csv):")
  print(as.data.frame(read_csv(manifest_path, show_col_types = FALSE)), row.names = FALSE)
}
message("\nRead by code/data_prep/causal_inf_data_prep.R -> MAIN_panel_data.")
