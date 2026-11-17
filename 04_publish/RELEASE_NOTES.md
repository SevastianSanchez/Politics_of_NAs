# Visible States Index (VSI) — version 1.4.0

Released [DATE]. Version DOI [VERSION DOI]. Concept DOI
[10.5281/zenodo.23997606](https://doi.org/10.5281/zenodo.23997606) resolves to the
latest version.

## What is new

- **`vsi_goal_relative`: each goal's reporting relative to the country's own
  overall level.** From a bifactor model (one general factor plus 16 goal
  factors). Where `vsi_goal` asks *how much does this country report on this
  goal?*, `vsi_goal_relative` asks *more or less than its overall level
  predicts?*
  - Reliability 0.675–0.916. Goals 5 (0.675) and 9 (0.692) fall under the 0.70
    reference point and are disclosed, not dropped.
  - Held-out validity: fitted on 70% of each goal's series, it predicts reporting
    on the other 30% at median AUC 0.649 against a 0.501 null; all 16 goals clear
    their null.
  - Bootstrap (B = 100, 0 failures): the bootstrap SD is 9–89% of the posterior
    SE, median 22% across goals; goal 17 is highest.
- **Both goal layers now publish the same diagnostics**, including two disclosure
  columns: how much of a goal's weight sits in its five heaviest series, and how
  much comes from agency-produced series (`goal_diagnostics.csv`).
- **The `vsi_goal` bootstrap was re-run** with a kept, reproducible output
  (B = 500, 0 failures): bootstrap SD 7–44% of the posterior SE, median 13.5%.

## No score changed

`vsi` and `vsi_goal` are identical to 1.3.0, value for value. Only names changed.

## Breaking change: names

| 1.3.0 | 1.4.0 |
|---|---|
| `irt_composite_scores.csv`: `composite`, `composite_se` | `vsi_scores.csv`: `vsi`, `vsi_se` |
| `irt_goal_level_scores.csv` | `vsi_goal_scores.csv` |
| `goal_level`, `goal_level_se` | `vsi_goal`, `vsi_goal_se` |
| — | `vsi_goal_relative_scores.csv`: `vsi_goal_relative`, `vsi_goal_relative_se` |
| `irt_goal_level_health.csv` | `goal_diagnostics.csv` (both goal layers) |

Score files now also carry `country_name` and `income_level`.

## Decisions recorded in this release

- **Goal 7 is not scored** in either goal layer: 3 series, all UN agency
  estimates. This replaces an earlier decision to publish it with a wide
  interval.
- **Goal 17 uses the same one-factor model as every other goal**, as it did in
  1.3.0. An earlier two-factor exception is retired; no score changes.
- Goals 6 and 15 remain held on content grounds.

## Known limitations

- **Every blank counts as "not reported"**, including blanks where a series does
  not apply to a country (for example, aid flows that only exist for donors or
  recipients). Handling non-applicable series is planned for version 2.
- **Choice and incapacity are not separated:** a blank may mean a government chose
  not to report or could not. Separating them is the aim of version 2.
- **Some goal scores rest heavily on agency-produced series**: goals 2, 3 and 14
  in both layers (over 70% of their weight), and goal 1 in `vsi_goal_relative`
  (72%). See `goal_diagnostics.csv`.
- **14 series flagged as possible near-duplicates were kept separate**, as in
  1.3.0, pending review in version 2.

## Why 1.4.0 and not 2.0.0

Renaming columns is a breaking change, which semantic versioning would call
2.0.0. This project's versions track **measurement scope** instead, and version 2
is reserved for the provenance split, which separates data withheld by choice
from data absent through incapacity. A new goal layer and renamed columns are a
minor release on that scheme.

## Files

| File | What it is |
|---|---|
| `vsi_scores.csv` | The overall index, one row per country–year (1,773 rows) |
| `vsi_goal_scores.csv` | Reporting on each goal (28,368 rows) |
| `vsi_goal_relative_scores.csv` | Each goal relative to the country's overall level (28,368 rows) |
| `goal_diagnostics.csv` | Per goal and layer: series, reliability, SE, weight concentration, agency share, status |
| `DATA_DICTIONARY.md` | Every column of every file |
| `RELEASE_NOTES.md` | This file |
| `visible-states-project-v1.4.0.zip` | The full repository at tag `v1.4.0`, to rerun everything |

## How releases are packaged

From v1.4.0, each release contains this bundle plus a zip of the full repository.
Earlier releases were packaged differently; the full code for any earlier version
is available from its GitHub tag
([github.com/SevastianSanchez/visible-states-project/tags](https://github.com/SevastianSanchez/visible-states-project/tags)).

## Reproducing

Unzip the repository and see its README. `run_all.R` runs the quick stages; the
fits and checks are listed there with their run times. Every fit setting, and every
configuration that failed, is recorded in `METHODS_LOG.md`.

The repository is now `github.com/SevastianSanchez/visible-states-project`, and the
site is at
[sevastiansanchez.github.io/visible-states-project](https://sevastiansanchez.github.io/visible-states-project/).

## Citation

Sanchez, S. (2026). *Visible States: statistical reporting across countries,
policy sectors, and time* (Version 1.4.0) [Data set]. Zenodo.
[VERSION DOI]

Previously published as *The World on Record* (versions 1.0.0–1.2.1).
