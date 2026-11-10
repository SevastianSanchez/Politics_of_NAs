# Visible States Index (VSI) — version 1.3.0

Released 10 November 2026. Concept DOI 10.5281/zenodo.23997606 resolves to the
latest version; this release has its own version DOI, shown on its Zenodo page.

## What changed: the name, and nothing else

This measure was published through version 1.2.1 as **The World on Record
Index (TWR)**. From this release it is the **Visible States Index (VSI)**,
published by the **Visible States Project**. The old name collided with an
unrelated domain.

**No number in this release differs from 1.2.1.** The score files are
byte-identical: `irt_composite_scores.csv`, `irt_goal_level_scores.csv` and
both item-parameter files compare equal to their 1.2.1 counterparts. Nothing
was refitted, no setting changed, and the 524-series set is unchanged. If you
have already analysed 1.2.1, your results stand.

## Breaking change: column and file names

| 1.2.1 | 1.3.0 |
|---|---|
| `twr` | `vsi` |
| `twr_se` | `vsi_se` |
| `twr_external_validity.csv` | `vsi_external_validity.csv` |
| `twr_scores.csv` / `.json` (site) | `vsi_scores.csv` / `.json` |
| `validate_twr_external.R` | `validate_vsi_external.R` |

No aliases are shipped. Carrying both spellings would have left two names for
one column in every file from here on, and 1.2.1 was four days old with seven
downloads when this was decided — the cheapest moment to make a clean break.

`goal_level`, `goal_relative`, `goal_level_se` and the internal `composite`
column are descriptive rather than branded and are unchanged.

## Why 1.3.0 and not 2.0.0

Renaming a column is a breaking change, so semantic versioning would call this
2.0.0. This project's version line tracks **measurement scope** instead —
domain, then provenance, then depth — and the roadmap has always reserved
**v2 for the provenance split**, which separates data withheld by choice from
data absent through incapacity. Spending 2.0.0 on a rename would have made the
published roadmap wrong. A rename inside the domain layer is a minor release
on the scheme this project actually uses.

## What is not renamed

Versions 1.0.0 through 1.2.1 keep the titles they were published under. A
published version is the record of what existed at that date, and anyone
citing *The World on Record (v1.2.0)* must be able to follow that citation to a
record bearing that title. Those versions carry a note pointing forward to this
one instead.

The concept DOI is unchanged. This is the same work under a new name, not a new
deposit, and minting a second concept DOI would split the version history.

## Also fixed

The abstract in `CITATION.cff` and the repository README described the measure
as covering **607 statistical series**. The fitted set is **524**; 607 is the
intermediate count after the 2–98% filter and before redundant variants are
merged. Both now say 524. This affected descriptive metadata only, never a
score.

## Files

| File | What it is |
|---|---|
| `irt_composite_scores.csv` | **The overall index.** iso3 × year, with `vsi` and `vsi_se`. 1,773 rows |
| `irt_goal_level_scores.csv` | **The sector layer.** iso3 × year × goal, with `goal_level` and `goal_level_se`. 28,368 rows |
| `irt_goal_level_health.csv` | Per-goal diagnostics: series count, cycles, reliability, SEs, concentration, agency weight, release status |
| `irt_goal_level_item_params.csv` | Per-series discrimination, intercept and weight within its goal |
| `irt_goal_level_run_log.csv` | Settings, versions and timings of the goal-level run |
| `irt_composite_item_params.csv` | Per-series difficulty and discrimination for the overall fit |
| `irt_composite_run_log.csv` | Settings and timings of the composite run |
| `irt_response_matrix.rds` | The 1,773 × 665 reported/not matrix everything is built from |
| `irt_series_goal_assignment.csv` | Which goal each multi-goal series was assigned to |
| `series_variant_map.csv` | Every variant-collapse decision, with its evidence |
| `series_provenance_nature.csv` | Per series, the share of observations that are country-produced vs agency-produced |
| `vsi_external_validity.csv` | Agreement with the World Bank SPI and with HRV2 |
| `code/` | Everything needed to rebuild both layers from the UN export |

## Reproducing

Run in order: `build_variant_map.R`, then `build_irt_composite.R` and
`build_irt_goals.R` (independent of each other), then
`build_series_provenance.R`. Both fits source `irt_prep.R`, which halts if the
variant map is missing or stale. Settings are fixed in the scripts and
documented in `METHODS_LOG.md` in the repository.

Fitted with mirt 1.48 on R 4.5.3. The composite converges in 187 cycles
(0.4 min); all sixteen goal fits together take under 20 seconds.

## Citation

Sanchez, S. (2026). *Visible States: statistical reporting across countries,
policy sectors, and time* (Version 1.3.0) [Data set]. Zenodo.
https://doi.org/10.5281/zenodo.23997606

Previously published as *The World on Record* (versions 1.0.0–1.2.1).

Contact: ss7257@columbia.edu
