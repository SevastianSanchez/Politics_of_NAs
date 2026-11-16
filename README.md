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

| Folder | Contents |
|---|---|
| `code/data_prep/` | Building the index: extraction and cleaning of the UN SDG exports (`extract_SDG_series_data_2015_2023.R`), series stability, and the fits — `irt_prep.R` (shared response matrix, sourced by every fit), `build_irt_composite.R`, `build_irt_goals.R` and `build_irt_bifactor.R` |
| `code/` | Validation (`validate_*.R`), site data (`build_docs_data.R`), the measurement paper's figures (`paper_numbers.R`). Run order in `code/README.md` |
| `data/01_source/` | Nothing here is ours. The UN SDG goal exports (310 MB, untracked — see Reproducing), `sdg_update_info.xlsx`, the dated SPI and HRV snapshots used for validation, and `analysis_data__2026-11-15.{csv,rds}`, a frozen copy of the paper's panel that `paper_numbers.R` and `build_docs_data.R` read for income groups, GDP and country names |
| `data/02_measure/` | Computed from `01_source/` alone — the measure, including the fitted index scores and series parameters (`irt_*`). See the data dictionary |
| `output/measure/` | Everything that checks the index. See `output/README.md` |
| `docs/` | The published site — [Visible States Project](https://sevastiansanchez.github.io/Politics_of_NAs/), the interactive data dictionary, and the VSI score files they serve. GitHub Pages builds this folder from `main`; `code/build_docs_data.R` regenerates its data |

Code folders hold code; `data/` holds sources and built tables; `output/` holds
results. The numbers on the `data/` folders are the direction of travel:
`01_source ──→ 02_measure`.

All paths in the scripts go through `here()`, so any file runs whatever the
working directory is.

## Reproducing

Dependencies are handled by `code/packages.R`, which installs anything missing
(including `vdemdata` and `ERT` from GitHub, which are not on CRAN) and then
loads everything. Scripts source it directly.

**Everything runs from a fresh clone except the extract.** Every input the
other scripts need is tracked, including the built measure itself
(`data/02_measure/raw_data.csv.gz`), so you do not have to rebuild the measure
to use it or to run anything downstream of it:

| Script | From a clone |
|---|---|
| `build_series_stability.R` | runs |
| `..._diagnostics/check_series_coverage.R` | runs |
| `extract_SDG_series_data_2015_2023.R` | **needs the download below** |

The UN SDG goal exports are 310 MB, too large to track. To rebuild the measure
from source, download them from the
[UN SDG Global Database](https://unstats.un.org/sdgs/dataportal) into
`data/01_source/un_sdg_exports/`, then run
`code/data_prep/extract_SDG_series_data_2015_2023.R` to regenerate
`data/02_measure/`. Nothing else requires that download.

## Related work

Di Gennaro Splendore, L., and Sanchez, S. (2025). *Untangling the relationship between democracy, data, and development: A dynamic two-stage analysis of the Sustainable Development Goals* (Preprint). SSRN. https://doi.org/10.2139/ssrn.6998939

## License

Code is MIT; see [LICENSE](LICENSE). The data this code produces — `data/02_measure/` and the files published in `docs/` — are CC BY 4.0; see [LICENSE-DATA](LICENSE-DATA). Third-party source data in `data/01_source/` remains under its own terms.
