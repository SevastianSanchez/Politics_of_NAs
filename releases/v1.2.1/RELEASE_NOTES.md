# The World on Record Index (TWR) — version 1.2.1

Released 9 November 2026. Concept DOI 10.5281/zenodo.23997606 resolves to the
latest version.

## What changed from 1.2.0

**A label fix in one supplementary file. No score changes.**

In 1.2.0, `irt_goal_level_item_params.csv` carried `goal = 0` for all 521
series instead of the goal each series belongs to. A 2PL coefficient matrix has
a column named `g` — the guessing parameter, fixed at 0 — and the build script's
loop variable was also `g`, so the column was written from the wrong one.

Every other column in that file was correct, and **no score, standard error,
reliability or diagnostic was affected**: the column is written out and never
read back. `irt_goal_level_scores.csv` is byte-identical to 1.2.0.

1.2.0 remains citable and its scores remain correct. Cite 1.2.1 if you want the
series-to-goal mapping from that file rather than from `series_list.csv`.

Everything below is unchanged from 1.2.0.

## What is new: the sector layer

1.0.0 and 1.1.0 published one score per country-year. This release adds
**`goal_level`** — one score per country-year **per SDG goal** — so the measure
can say *what* a government stopped reporting, not only that it reported less.

Sixteen goals are scored. **Goal 7 is not**: it has three series, too few to
identify a factor. That is a structural fact about the goal, not a judgement
on it.

Each goal is a **separate** unidimensional 2PL fit on that goal's own series,
drawn from the same 524 that build the overall index. A goal's score therefore
owes nothing to the other fifteen, and both layers sit on the same scale.

The layer is not a restatement of the overall index. Across the sixteen goals a
median of **64%** of the variation in goal-level reporting is not explained by a
country's overall level — from 18% for goal 17 to 99.9% for goal 15.

## What it is checked against

| Check | Result |
|---|---|
| Convergence | 16 of 16 goals, 19–73 EM cycles each |
| Reliability | 0.772–0.953, median **0.844**; every goal above 0.70 |
| Median posterior SD | 0.338 (overall index: 0.114) |
| Bootstrap, 500 replicates | **0 failed replicates**; sampling SD is 7–42% of the posterior SE, median 13% |
| Held-out series | Fit on 70% of a goal's series, predict the held-out 30%: median AUC **0.725** against a per-series permutation null at **0.500** |

The bootstrap result means the published standard errors are **conservative** —
they already cover item-parameter uncertainty with room to spare. Report the
posterior SE, not the bootstrap SD.

The held-out test is the first direct check that a goal score predicts reporting
it was not fitted on. Thirteen of sixteen goals score 0.649 or better. The three
weakest — goal 17 (0.618), goal 15 (0.526) and goal 6 (0.479) — are precisely the
three already set apart on content grounds, which the test did not know.

## Disclose, do not gate

**Every goal fitted is published.** Nothing is excluded for imprecision, and
0.70 (Nunnally) is reported as a reference point, not applied as a cut. Each
goal ships with four numbers a reader can weigh it by:

- `reliability` — 0.772 to 0.953
- `se_median` — the typical error bar on that goal's scores
- `weight_top5_pct` — how concentrated the score is in its five heaviest series
- `weight_agency_pct` — how much of the score rests on series the custodian
  agency produces rather than the country

Two goals carry `release = hold_content`. The hold is on **content** grounds and
for **different reasons**, never on precision:

- **Goal 6** is largely satellite measurement of lakes, wetlands and river flow.
  "Reported" there mostly records whether an agency published a dataset, not a
  country's choice.
- **Goal 15** is overwhelmingly country-produced, but a third of its series are
  treaty and policy instruments (Nagoya Protocol, Aichi targets, NBSAP), which
  may track commitment status rather than reporting effort.

An error bar cannot warn a reader about either, so the flag travels with the
data. Both goals are published in full.

## Known limitations

**Weight concentration.** Within a goal, small groups of series that are always
reported together can carry much of the score — in goal 10 the five heaviest
series carry 80%, in goal 1 75%. These groups are near-duplicates that the
variant rule does not collapse, because they are not reported identically: in
goal 1, India, Sri Lanka and Malaysia report the education and health breakdowns
but never the aggregate, every year from 2015 to 2023. Collapsing them would
erase those reporting choices, so they are disclosed in `weight_top5_pct`
instead. Modelling the dependence directly is deferred.

**Provenance.** `weight_agency_pct` records how much of each goal's score rests
on series the custodian agency produces rather than the country. It is high for
goals 3 (93.8%), 2 (91.0%), 6 (78.5%), 14 (72.6%) and 17 (45.7%). Of the other
eleven, goal 1 is 14.0% and the remaining ten are at or below 6.2%. Modelling
provenance rather than disclosing it is the v2 design.

**Dynamic smoothing** across years is deliberately not done. Nine years is short
for a random walk to earn its place.

## Files

| File | What it is |
|---|---|
| `irt_goal_level_scores.csv` | **The sector layer.** iso3 × year × goal, with `goal_level` and `goal_level_se`. 28,368 rows |
| `irt_goal_level_health.csv` | Per-goal diagnostics: series count, cycles, reliability, SEs, concentration, agency weight, release status |
| `irt_goal_level_item_params.csv` | Per-series discrimination, intercept and weight within its goal |
| `irt_goal_level_run_log.csv` | Settings, versions and timings of the goal-level run |
| `irt_composite_scores.csv` | The overall index, unchanged from 1.1.0 |
| `irt_composite_item_params.csv` | Per-series difficulty and discrimination for the overall fit |
| `irt_composite_run_log.csv` | Settings and timings of the composite run |
| `irt_response_matrix.rds` | The 1,773 × 665 reported/not matrix everything is built from |
| `irt_series_goal_assignment.csv` | Which goal each multi-goal series was assigned to |
| `series_variant_map.csv` | Every variant-collapse decision, with its evidence |
| `series_provenance_nature.csv` | Per series, the share of observations that are country-produced vs agency-produced |
| `twr_external_validity.csv` | Agreement with the World Bank SPI and with HRV2 |
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

Sanchez, S. (2026). *The World on Record Index* (Version 1.2.1) [Data set].
Zenodo. https://doi.org/10.5281/zenodo.23997606

(Replace the concept DOI above with 1.2.1's own version DOI once deposited.
v1.2.0 is 10.5281/zenodo.24091914.)

Contact: ss7257@columbia.edu
