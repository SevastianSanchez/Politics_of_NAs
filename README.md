# The Politics of NAs: Mapping Data Loss During Autocratization

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23997606.svg)](https://doi.org/10.5281/zenodo.23997606)

**Status: work in progress.** Code and results change as the analysis develops.

Which development data disappear when democracies backslide, and which disappear first? This project treats missing values in the UN Sustainable Development Goal (SDG) database as an outcome in their own right: a measure of how much a government reports, not a nuisance to impute away. It asks whether autocratization episodes reduce SDG reporting, and whether the losses concentrate in particular goals.

Author: Sevastian Sanchez, Columbia University (SIPA and QMSS)

## The index

**[Visible States Project &rarr; sevastiansanchez.github.io/Politics_of_NAs](https://sevastiansanchez.github.io/Politics_of_NAs/)**

*Statistical reporting across countries, policy sectors, and time.*

The first transparency measure covering the SDG era: latent reporting behaviour across 524 statistical series and 197 countries, 2015–2023, with uncertainty quantified for every country-year. Existing transparency indices stop in 2015; this one begins there, and resolves reporting by policy domain rather than returning a single national score.

The headline measure is the **Visible States Index (VSI)**: one overall score per country-year, with sector-level scores to follow. The site carries the rankings, the yearly trend, the sector panel, a version roadmap and the downloadable scores. It is a preliminary release and not yet citable.

### How to cite

> Sanchez, S. (2026). *Visible States: statistical reporting across countries, policy sectors, and time* (v1.3.0) [Data set]. Zenodo. https://doi.org/10.5281/zenodo.23997606

Use the **concept DOI** above when referring to the dataset generally — it always resolves to the newest version. Cite the **version DOI** for the release your analysis actually used, so your results stay reproducible after later versions change the scores:

| Release | Version DOI | Published as |
|---|---|---|
| v1.3.0 | [10.5281/zenodo.24100866](https://doi.org/10.5281/zenodo.24100866) | Visible States |
| v1.2.1 | [10.5281/zenodo.24094834](https://doi.org/10.5281/zenodo.24094834) | The World on Record |
| v1.2.0 | [10.5281/zenodo.24091914](https://doi.org/10.5281/zenodo.24091914) | The World on Record |
| v1.0.0 | [10.5281/zenodo.23997607](https://doi.org/10.5281/zenodo.23997607) | The World on Record |

Versions 1.0.0 to 1.2.1 were deposited under the name **The World on Record**
and keep that title, so earlier citations still resolve. The scores in 1.2.1
and 1.3.0 are identical; only the names changed. From 1.3.0 the columns are
`vsi` and `vsi_se`, previously `twr` and `twr_se`.

Machine-readable metadata is in [CITATION.cff](CITATION.cff). Code is MIT-licensed ([LICENSE](LICENSE)); the data are CC BY 4.0 ([LICENSE-DATA](LICENSE-DATA)).

## Data

| Source | Use |
|---|---|
| UN SDG Global Database, 2015–2023 (665 series, 197 geographies, ~1.3M observations) | The measure: reported vs. missing observations by country, year and series |
| World Bank Statistical Performance Indicators (SPI); HRV Transparency Index | External validation (dated snapshots in `data/01_source/snapshots/`) |

The cleaned outcome tables, their grain, keys and every column are documented in the **[interactive data dictionary](https://sevastiansanchez.github.io/Politics_of_NAs/data_dictionary.html)** (also available as [markdown](data/02_measure/README.md)).

## The Politics of NAs paper

The analysis that uses the index — whether autocratization episodes reduce SDG
reporting, and which goals lose data first (TWFE and Callaway–Sant'Anna) — lives
in its own repository, `politics-of-nas-paper`, which reads a pinned release of
the VSI scores. This repository builds, validates and releases the index.

## Repository layout

The top level reads in run order: data → processing → measures → publish.

```
01_data/        raw/ (never edited) · processed/ (written by 02) · vsi_scores/ (written by 03)
02_processing/  UN exports → the 524-series response matrix
03_measures/    vsi/ · vsi_goal/ · vsi_goal_relative/ — each score's build script and its checks/
04_publish/     the site's data files and the measurement paper's numbers
functions/      sourced by other scripts, never run alone
```

**Data lives only in `01_data/`.** Scripts that validate something sit in a `checks/`
folder beside what they validate, and write what they find to `checks/output/`.
**Nothing in a `checks/output/` folder is ever read as an input.** Open a measure's
folder and you see how it is built, how it is tested, and what the tests found.

| Folder | What | Run order |
|---|---|---|
| `01_data/raw/` | The UN SDG goal exports (310 MB, untracked; see Reproducing), `sdg_update_info.xlsx`, dated SPI and HRV snapshots for validation, and `analysis_data__2026-11-15.{csv,rds}`, a frozen copy of the Politics of NAs panel that `paper_numbers.R` and `build_docs_data.R` read for income groups, GDP and country names | |
| `01_data/processed/` | Cleaned UN data, series list, variant map, stability, provenance. Data dictionary in its `README.md` | |
| `01_data/vsi_scores/` | Scores, fits and series parameters: `vsi/`, `vsi_goal/` (currently `goal_level`), `vsi_goal_relative/` (currently `goal_relative`, not part of v1.3.0) | |
| `02_processing/` | | 1 `extract_SDG_series_data_2015_2023.R` · 2 `build_variant_map.R` (**must run before any fit**) · 3 `build_series_provenance.R` · `build_series_stability.R`, `build_hrv_snapshot.R` as needed · checks: `check_series_coverage.R`, `collinear_series_report.R` |
| `03_measures/vsi/` | The overall index | 4 `build_irt_composite.R` · check: `validate_vsi_external.R` |
| `03_measures/vsi_goal/` | One score per goal | 5 `build_irt_goals.R` · checks: `validate_goal_level_heldout.R` (~13 min), `validate_goal_level_bootstrap.R` (~98 min on 8 cores) |
| `03_measures/vsi_goal_relative/` | A goal net of the country's own overall level | `build_irt_bifactor.R` (long, checkpointed, resumes) · checks: `validate_goal_relative_heldout.R` (~2.5 h), `validate_goal_relative_bootstrap.R` (~4.7 h, checkpointed) |
| `04_publish/` | | `build_docs_data.R` → `docs/` · `paper_numbers.R` → `paper_numbers.txt`, every figure the measurement paper quotes |
| `functions/` | `packages.R`, `irt_prep.R` (builds the one 524-series response matrix every fit uses, and halts if the variant map is missing or stale), `bifactor_scorer.R` | |
| `superseded/` | Old fits. **Do not run.** See `superseded/README.md` and `METHODS_LOG.md` | |
| `docs/` | The published site: [Visible States Project](https://sevastiansanchez.github.io/Politics_of_NAs/), the interactive data dictionary, and the published copy of the scores. GitHub Pages builds it from `main` | |
| `releases/` | What was deposited at Zenodo, one folder per version. Never edited | |

`run_all.R` runs the quick stages in order; refits and checks only on request.

Steps 4 and 5 are independent of each other; both read only `01_data/processed/`.
Every fit setting comes from `METHODS_LOG.md`: **read it before changing one.**
One script writes each file. All paths go through `here()`, so any script runs
whatever the working directory is.

**What is running right now:** `bash runs.sh` lists every R process, how long it
has run, and the last line of recent logs, and flags `ORPHAN` workers (whose
parent died) and `STALE` runs (over six hours). `bash runs.sh --kill` stops those,
after asking. Parallel workers do not die with their parent, so check before
launching anything and again after stopping anything.

## Reproducing

Dependencies are handled by `functions/packages.R`, which installs anything
missing and then loads everything. Scripts source it directly.

**Everything runs from a fresh clone except the extract.** Every input the other
scripts need is tracked, including the cleaned UN data
(`01_data/processed/raw_data.csv.gz`), so you do not have to rebuild it to run
anything downstream.

The UN SDG goal exports are 310 MB, too large to track. To rebuild from source,
download them from the [UN SDG Global Database](https://unstats.un.org/sdgs/dataportal)
into `01_data/raw/un_sdg_exports/`, then run
`02_processing/extract_SDG_series_data_2015_2023.R`. Nothing else requires that
download.

## Related work

Di Gennaro Splendore, L., and Sanchez, S. (2025). *Untangling the relationship between democracy, data, and development: A dynamic two-stage analysis of the Sustainable Development Goals* (Preprint). SSRN. https://doi.org/10.2139/ssrn.6998939

## License

Code is MIT; see [LICENSE](LICENSE). The data this code produces — `data/02_measure/` and the files published in `docs/` — are CC BY 4.0; see [LICENSE-DATA](LICENSE-DATA). Third-party source data in `data/01_source/` remains under its own terms.
