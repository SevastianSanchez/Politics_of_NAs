# The Politics of NAs: Mapping Data Loss During Autocratization

**Status: work in progress.** Code and results change as the analysis develops.

Which development data disappear when democracies backslide, and which disappear first? This project treats missing values in the UN Sustainable Development Goal (SDG) database as an outcome in their own right: a measure of how much a government reports, not a nuisance to impute away. It asks whether autocratization episodes reduce SDG reporting, and whether the losses concentrate in particular goals.

Author: Sevastian Sanchez, Columbia University (SIPA and QMSS)

## Data

| Source | Use |
|---|---|
| UN SDG Global Database, 2015–2023 (665 series, 197 geographies, ~1.3M observations) | Outcome: reported vs. missing observations by country, year and goal |
| V-Dem and Episodes of Regime Transformation (ERT) | Democracy measures and autocratization episodes (treatment) |
| World Bank Statistical Performance Indicators (SPI) | Statistical capacity control |
| Sustainable Development Report 2025 (SDSN) | SDG Index scores |
| World Development Indicators; nighttime lights (Beyer, Hu and Yao, 2026) | Controls: population, rural share, electricity access, GDP per capita, luminosity |

The cleaned outcome tables, their grain, keys and every column are documented in the **[interactive data dictionary](https://sevastiansanchez.github.io/Politics_of_NAs/data_dictionary.html)** (also available as [markdown](data/clean/README.md)).

## Methods

1. **Two-way fixed effects** (country and year), with statistical capacity (SPI) and economic controls, estimated for overall and goal-level missingness.
2. **Staggered difference-in-differences** (Callaway and Sant'Anna, 2021) to handle autocratization episodes that begin in different years, with event-study plots of dynamic effects.
3. Robustness checks on alternative outcome definitions: series counts vs. observation counts, country-produced vs. agency-produced data, and a framework-stable core of 409 series.

## Repository layout

| Folder | Contents |
|---|---|
| `code/data_prep/` | Extraction and cleaning of the UN SDG exports (`extract_SDG_series_data_2015_2023.r`), series stability, panel construction |
| `data/clean/` | Analysis-ready outcome tables (see data dictionary) |
| `data/input/`, `data/output/` | Covariate inputs and the merged country-year panel |
| `causal_inference_mods/` | TWFE (`overall_twfe_analysis.Rmd`), Callaway–Sant'Anna DiD (`cs_did_analysis_v2.Rmd`), event studies, robustness checks |
| `descriptive_stats/` | Descriptive analysis and summary tables |
| `figures/`, `results_csv/` | Exported figures and model results |
| `gis_related/` | QGIS project and country geometries for mapping |
| `misc/compIndexBuilder/` | R package with a Shiny app for building composite indices |
| `docs/` | Source for the interactive data dictionary |

## Reproducing

Install dependencies with `code/install_packages.r` (loaded in scripts via `code/packages.R`). The raw UN SDG goal exports are not tracked because of their size; download them from the [UN SDG Global Database](https://unstats.un.org/sdgs/dataportal) into `data/raw/un_sdg_goal_exports/`, then run `code/data_prep/extract_SDG_series_data_2015_2023.r` to rebuild `data/clean/`.

## Related work

Di Gennaro Splendore, L., and Sanchez, S. (2025). *Untangling the relationship between democracy, data, and development: A dynamic two-stage analysis of the Sustainable Development Goals* (Preprint). SSRN. https://doi.org/10.2139/ssrn.6998939

## License

MIT. See [LICENSE](LICENSE).
