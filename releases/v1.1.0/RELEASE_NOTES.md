# The World on Record Index (TWR) — version 1.1.0

Released 8 November 2026. Supersedes 1.0.0 (DOI 10.5281/zenodo.23997607).
Concept DOI 10.5281/zenodo.23997606 resolves to the latest version.

## What changed

**The series set is 524, not 607.** Redundant variants of the same measurement
are now collapsed to one series each. `SH_STA_STNT` (children stunted, percent)
and `SH_STA_STNTN` (the same children, in thousands) are one reporting decision,
not two; counting both credited a country twice while a country whose series has
no twin was credited once. 59 clusters met the test, removing 83 series.

A cluster is collapsed only when **both** conditions hold:

1. its series are reported, and not reported, together in every one of the 1,773
   country-years; and
2. their descriptions show they measure the same thing a different way.

Condition 1 alone is not sufficient. At these reporting rates unrelated series
coincide by chance: forest certification, electricity access and refugee counts
move together in 99.5% of country-years without measuring anything in common.
Series that merely resemble one another are kept apart, because a country
publishing one and withholding the other has made a real reporting choice. The
rule is implemented in `code/build_variant_map.R` and re-tested inside
`code/irt_prep.R` on every fit, which halts if a later data release breaks it.

## What this did to the scores

| | 1.0.0 (607 series) | 1.1.0 (524 series) |
|---|---|---|
| EM cycles to converge | 13,561 | **187** |
| Fit time | 22.3 min | **0.5 min** |
| Empirical reliability | 0.987 | 0.987 |
| Median posterior SD | 0.1151 | 0.1138 |
| Correlation with World Bank SPI | 0.831 | **0.851** |
| Correlation with HRV2 (2015) | 0.826 | **0.851** |

Scores correlate 0.981 with 1.0.0 (Spearman 0.972); median absolute change 0.116.
Agreement with both external benchmarks improved, and with every SPI pillar
individually, which is the evidence that the collapse removed double counting
rather than information. The fit reproduces exactly on an independent re-run.

**Known issue.** Several micro-states moved a long way, Liechtenstein furthest
(+0.50 to -0.89 in 2022, about 1,000 rank positions of 1,773). The obvious
explanation does not account for it: 18.3% of Liechtenstein's reported series
were collapsed duplicates against a 15.6% median. The new value is more
consistent with its raw reporting volume, which is well below the median, but
this is unexplained rather than resolved. Treat micro-state scores with caution.

## Contents

| File | What it is |
|---|---|
| `irt_composite_scores.csv` | the index: `iso3, year, composite, composite_se`, 1,773 rows |
| `irt_composite_item_params.csv` | per-series difficulty and discrimination |
| `irt_composite_run_log.csv` | the fit's settings and convergence record |
| `irt_response_matrix.rds` | the 1,773 x 524 reported/not matrix the model was fitted on |
| `irt_series_goal_assignment.csv` | audit trail for series sitting under several goals |
| `series_variant_map.csv` | every series, its cluster, and the collapse verdict |
| `twr_external_validity.csv` | correlations with SPI, by pillar, and with HRV2 |
| `code/` | everything needed to reproduce the above from the UN export |

## Not in this release

Goal-level (sector) scores. Still in estimation; see the project roadmap.

## Citation

Sanchez, S. (2026). The World on Record Index (TWR), version 1.1.0. Zenodo.
https://doi.org/10.5281/zenodo.23997606

Data CC BY 4.0, code MIT.
