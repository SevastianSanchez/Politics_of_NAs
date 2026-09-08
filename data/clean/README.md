# `data/clean/` — data dictionary

Outputs of [`code/data_prep/extract_SDG_series_data_2015_2023.r`](../../code/data_prep/extract_SDG_series_data_2015_2023.r).
One source table, six derived. UN SDG Global Database, **2015–2023**, **197 geographies**,
**665 series**. Downloaded Aug 16 2026.

**Merge to the treatment panel (`MAIN_panel_data`) on `iso3` + `year`.**

## Lineage

```
raw_data  (1 row = 1 observation)
   │
   ├── goal_lvl_dv_data       primary outcome
   ├── agg_series_counts_rc   robustness
   ├── agg_series_depth       supplementary
   ├── series_list            reference
   ├── series_stability       reference
   └── geo_exclusions         reference (audit)
```

## Files at a glance

| Dataset | Role | Grain | Key | Rows | File |
|---|---|---|---|---|---|
| `goal_lvl_dv_data` | **primary** | country × year × goal | `iso3` + year + goal | 30,141 | `.csv` + `.rds` |
| `agg_series_counts_rc` | robustness | country × year × scope | `iso3` + year + scope + goal | 31,914 | `.csv` |
| `agg_series_depth` | supplementary | country × series × year | geo_area_code + series_code + year + goal | 508,432 | `.csv.gz` + `.rds` |
| `raw_data` | source | one observation | — | 1,307,990 | `.csv.gz` |
| `series_list` | reference | goal-target-indicator-series | series_code (+ path) | 726 | `.csv` |
| `series_stability` | reference | one series | series_code | 665 | `.csv` |
| `geo_exclusions` | reference (audit) | one geography | geo_area_code | 63 | `.csv` |

> **`.rds` twins** (`goal_lvl_dv_data`, `agg_series_depth`) preserve exact column
> types and the `attr()` labels. Reading a `.csv` guesses types, and drops the labels.

---

## `goal_lvl_dv_data` — primary outcome

The dependent variable. One row per country-year-goal, every outcome measure side by
side. Use **raw counts with fixed effects** for causal work; the `_pct_` columns for
cross-goal descriptive comparison.

**Grain:** country × year × goal &nbsp;·&nbsp; **Key:** `iso3` + `year` + `goal` &nbsp;·&nbsp; **Rows:** 30,141

### Identity & keys
| Column | Type | Description |
|---|---|---|
| `geo_area_code` | chr | UN M49 numeric code. **KEY** |
| `geo_area_name` | chr | Country / territory name |
| `iso3` | chr | ISO-3166 alpha-3. Joins to `MAIN_panel_data`. **MERGE** |
| `year` | int | 2015–2023. **KEY** |
| `goal` | int | SDG 1–17. **KEY** |

### Counts — reported observations
| Column | Type | Description |
|---|---|---|
| `n_observations` | int | Reported observations, all 665 series. Headline outcome. |
| `n_observations_country` | int | Of those, the **country** produced it (nature `C`/`CA`). The sharper test. |
| `n_observations_agency` | int | Of those, an **agency** produced it (nature `E`/`M`/`G`). |
| `n_observations_stable` | int | Of those, in the 409 framework-stable series. Guards against framework drift. |

### Missingness — empty cells the UN opened here
| Column | Type | Description |
|---|---|---|
| `n_declared_missing` | int | Cells present but empty (`value = NA`). Splits into the three below. |
| `n_missing_structural` | int | Indicator does not apply here — *not* data loss. |
| `n_missing_suppressed` | int | Withheld. Sharpest signal of deliberate non-reporting. |
| `n_missing_unknown` | int | No reason given. |

### Normalized — comparable across goals (share of a denominator)
| Column | Type | Description |
|---|---|---|
| `n_observations_pct_baseline` | dbl | ÷ this country's own 2015–17 mean. **NA (×810)** where that baseline is 0. |
| `n_observations_pct_goalbase` | dbl | ÷ the mean across **all countries** for this goal in 2015–17. Defined for every row — keeps late starters in. |
| `n_observations_pct_frontier` | dbl | ÷ the most any country reported that goal-year. Denominator moves yearly. |
| `n_observations_stable_pct_baseline` | dbl | Stable-core version of `pct_baseline`. **NA (×855)**. |
| `n_observations_stable_pct_goalbase` | dbl | Stable-core version of `pct_goalbase`. |

---

## `agg_series_counts_rc` — robustness

Availability by counting **series codes present** — each counts once regardless of
disaggregation depth. Rerun the main result here; if it holds, it is not an artifact of
how you counted. Two scopes stacked.

**Grain:** country × year × scope &nbsp;·&nbsp; **Key:** `iso3` + `year` + `scope` + `goal` &nbsp;·&nbsp; **Rows:** 31,914

| Column | Type | Description |
|---|---|---|
| `geo_area_code` | dbl | UN M49 code. **KEY** |
| `geo_area_name` | chr | Country / territory name |
| `iso3` | chr | Merge key. **MERGE** |
| `year` | int | 2015–2023. **KEY** |
| `scope` | chr | `goal` = per country-year-goal · `overall` = per country-year. **KEY** |
| `goal` | int | SDG 1–17; **NA (×1,773)** on the overall-scope rows. **KEY** |
| `n_available_series` | int | Series the country reported at all here. |
| `n_available_series_country` | int | Of those, with country-produced data (nature C/CA). |
| `n_applicable_series` | int | Series that apply here (excludes structurally non-relevant). Country-specific denominator. |
| `n_series_in_framework` | int | Universal denominator: series in the goal (or all 665, overall scope). |
| `missing_series_count` | int | framework − available. |
| `availability_share` | dbl | available ÷ framework, in [0,1]. |
| `missingness_share` | dbl | 1 − availability_share. |

---

## `agg_series_depth` — supplementary

Disaggregation depth — did a country keep a series but drop its breakdowns? A separate,
optional outcome. `depth_pct_frontier` expresses depth as a share of a per-series
ceiling, so it is comparable across countries.

**Grain:** country × series × year &nbsp;·&nbsp; **Key:** `geo_area_code` + `series_code` + `year` + `goal` &nbsp;·&nbsp; **Rows:** 508,432

| Column | Type | Description |
|---|---|---|
| `goal` `geo_area_code` `geo_area_name` `iso3` `year` `series_code` | mixed | Grain keys. `iso3` merges out. **KEY / MERGE** |
| `n_disagg_rows` | int | Disaggregation combos the country reported (published rows). |
| `n_country_rows` / `n_agency_rows` | int | Of those, by producer (C/CA vs E/M/G). |
| `nature_codes` | chr | "/"-joined natures present, e.g. `C/E`. NA where the cell is all-missing. |
| `n_declared_missing` | int | Empty cells here. |
| `n_missing_structural` / `n_missing_suppressed` | int | Split of the above by reason. |
| `reported` | lgl | Any published value here. |
| `reported_country` | lgl | Any country-produced value. |
| `applicable` | lgl | Series applies here (not purely structural non-relevance). |
| `depth_frontier` | int | Per-series ceiling: most any country-year reached (attainable). Primary. |
| `depth_union` | int | Per-series ceiling: all combos ever seen, pooled. Robustness. |
| `depth_pct_frontier` | dbl | `n_disagg_rows` ÷ `depth_frontier`, in [0,1]. |
| `depth_pct_union` | dbl | `n_disagg_rows` ÷ `depth_union`, in [0,1]. |

---

## `raw_data` — source of truth

One row per observation (country × series × year × disaggregation). Every dataset above
derives from it. Filter it to build custom cuts; don't model on it directly.

**Grain:** one observation &nbsp;·&nbsp; **Rows:** 1,307,990 &nbsp;·&nbsp; **Columns:** 19

### Identity
| Column | Type | Description |
|---|---|---|
| `goal` `target` `indicator` | mixed | SDG hierarchy, e.g. `1` / `1.2` / `1.2.1`. |
| `series_code` `series_description` | chr | The indicator series (665 distinct). |
| `geo_area_code` `geo_area_name` `iso3` | chr | Geography; `iso3` is the merge key. **MERGE** |
| `year` | int | 2015–2023. |

### The value, and why it may be absent
| Column | Type | Description |
|---|---|---|
| `value` | chr | The reported number, as text. `NA` = declared missing. A few rows carry censored bounds like `<0.1`. |
| `missing_reason` | chr | `structural` / `suppressed` / `unknown`. `NA` when value present. (Opposite of `is.na(value)` on every row.) |

### Disaggregation
| Column | Type | Description |
|---|---|---|
| `age` `sex` `location` `units` | chr | Breakdown dimensions; blank where the series has none. |

### Provenance
| Column | Type | Description |
|---|---|---|
| `nature` | chr | Who produced the number: `C`/`CA` country · `E`/`M`/`G` agency · `N` non-relevant. |
| `observation_status` | chr | SDMX status flag (`A` normal, `M`/`O`/`Q` missing kinds, …). |
| `source` `foot_note` | chr | Free-text provenance from the UN export. |

---

## `series_list` — reference

What each series *is*. One row per goal-target-indicator-series path — 726 rows for 665
series, since a series can sit under more than one path. Join from here to label series
or filter to the stable core.

**Grain:** goal-target-indicator-series &nbsp;·&nbsp; **Key:** `series_code` (+ path) &nbsp;·&nbsp; **Rows:** 726

| Column | Type | Description |
|---|---|---|
| `goal` `target` `indicator` `series_code` `series_description` | mixed | The SDG path and series identity. **KEY** |
| `first_year` `last_year` `n_years_live` | int | Empirical lifespan. |
| `is_stable_core` | lgl | Live in every year 2015–2023 (409 series). The framework-drift filter. |
| `starts_late` `ends_early` `status` | lgl/chr | Lifespan flags; `status` summarises them. |
| `n_observations` `n_observations_country` `n_observations_agency` | int | Series total, split by producer. |
| `n_declared_missing` `n_missing_structural` `n_missing_suppressed` | int | Missing cells for the series, by reason. |
| `pct_country_produced` | dbl | Share country-produced — 2% to 100% across series. |

---

## `series_stability` — reference

The evidence behind the stable core: each series' lifespan and the flags that define it.
Built by [`build_series_stability.R`](../../code/data_prep/build_series_stability.R).
`series_list` joins its flags in.

**Grain:** one series &nbsp;·&nbsp; **Key:** `series_code` &nbsp;·&nbsp; **Rows:** 665

| Column | Type | Description |
|---|---|---|
| `series_code` | chr | One row each. **KEY** |
| `first_year` `last_year` `n_years_live` | int | Lifespan. `n_years_live` counts years present, so gaps show here. |
| `total_obs` `max_countries` | int | Reach: total observations and peak reporting countries. |
| `is_stable_core` `starts_late` `ends_early` `status` | lgl/chr | Stability classification. |
| `log_first_seen` `log_added_date` `log_removed_date` `n_log_events` | Date/int | Supporting dates from the UN update log. |

---

## `geo_exclusions` — reference (audit)

Every geography that left its own code, and why. Generated from the same config that
drives the filter, so it can't drift from what actually happened. 197 geographies survive
into the panel.

**Grain:** one geography &nbsp;·&nbsp; **Key:** `geo_area_code` &nbsp;·&nbsp; **Rows:** 63

| Column | Type | Description |
|---|---|---|
| `geo_area_code` `geo_area_name` | chr | The geography removed. **KEY** |
| `disposition` | chr | `excluded` (dropped) or `rolled up` (merged into a parent). |
| `reason` | chr | defunct entity · uninhabited · sub-national stratum · dependent territory · devolved jurisdiction. |
| `parent_code` | int | Roll-up target (e.g. UK = 826). NA for excluded rows. |
| `n_observations` `n_obs_retained` `n_series` `n_years` `first_year` `last_year` | int | What the geography contributed, and how much survived a roll-up. |

---

*Interactive version: the schema is also published as an Artifact.*
