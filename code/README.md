# Code

Run order. Anything not listed here is a helper or a one-off.

| # | Script | Writes |
|---|---|---|
| 1 | `data_prep/extract_SDG_series_data_2015_2023.R` | `data/02_measure/agg_series_depth.rds` and friends |
| 2 | `data_prep/build_variant_map.R` | `data/02_measure/series_variant_map.csv` — **must run before any fit** |
| 3 | `data_prep/irt_prep.R` | nothing. **Shared by every fit, composite and goal-level alike** — it is sourced, never run. It builds the one 524-series response matrix both fits use, so their scores stay comparable, and halts if the variant map is missing or stale. |
| 4 | `data_prep/build_irt_composite.R` | `data/02_measure/irt_composite_*` — the published index |
| 5 | `data_prep/build_irt_goals.R` | `data/02_measure/irt_goal_level_*` — the sector layer, one score per goal. Independent of step 4; either can run first. |
| 6 | `data_prep/build_series_provenance.R` | `output/measure/tables/series_provenance_nature.csv` — who produced each series (country vs custodian agency). Read by step 5 for a disclosure column; absent is not fatal. |
| 7 | `build_docs_data.R` | `docs/twr_scores.{json,csv}`, `docs/goal_scores.{json,csv}` |
| 8 | `validate_twr_external.R` | `output/measure/tables/twr_external_validity.csv`, `docs/validity_spi.json` |
| 9 | `paper_numbers.R` | `output/measure/results/paper_numbers.txt` — every figure the paper quotes |

Supporting: `packages.R` · `data_prep/build_hrv_snapshot.R` (HRV2 snapshot) ·
`data_prep/build_predictor_panel.R` · `data_prep/build_series_stability.R` ·
`data_prep/causal_inf_data_prep.R` · `build_docs_goal_preview.R` ·
`SDGCountryTrends_Function.R`

**`superseded/` must not be run.** See `superseded/README.md` and `METHODS_LOG.md`.

## The two fits

`build_irt_composite.R` (step 4) and `build_irt_goals.R` (step 5) both source
`irt_prep.R`, so they score the same 524 series and their scores are
comparable. Neither can delay or break the other. Step 4 owns
`irt_response_matrix.rds` and `irt_series_goal_assignment.csv`; step 5 writes
neither.

Every setting in both fits comes from `METHODS_LOG.md`. **Read that file before
changing one.** Each cost hours to establish, and the log records which
configurations already failed.
