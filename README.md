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

The cleaned outcome tables, their grain, keys and every column are documented in the **[interactive data dictionary](https://sevastiansanchez.github.io/Politics_of_NAs/data_dictionary.html)** (also available as [markdown](data/02_measure/README.md)).

## Methods

1. **Two-way fixed effects** (country and year), with statistical capacity (SPI) and economic controls, estimated for overall and goal-level missingness.
2. **Staggered difference-in-differences** (Callaway and Sant'Anna, 2021) to handle autocratization episodes that begin in different years, with event-study plots of dynamic effects.
3. Robustness checks on alternative outcome definitions: series counts vs. observation counts, country-produced vs. agency-produced data, and a framework-stable core of 409 series.

## Repository layout

| Folder | Contents |
|---|---|
| `code/data_prep/` | The whole pipeline: extraction and cleaning of the UN SDG exports (`extract_SDG_series_data_2015_2023.R`), series stability, predictor sourcing (`build_predictor_panel.R`), panel construction (`causal_inf_data_prep.R`), and the merge (`build_analysis_frame.Rmd`) |
| `data/01_source/` | Nothing here is ours. The UN SDG goal exports (310 MB, untracked — see Reproducing), the covariate sources, and `snapshots/` holding the dated V-Dem and WDI pulls the pipeline is pinned to |
| `data/02_measure/` | Computed from `01_source/` alone — the measure (see data dictionary) |
| `data/03_panels/` | Assembled from `01` and `02` — what the models read: `predictor_panel`, `MAIN_panel_data`, `panel_es_data`, `analysis_data` |
| `descriptive_stats/` | Descriptive analysis code (RQ1–RQ4) |
| `causal_inference_mods/` | TWFE (`overall_twfe_analysis.Rmd`), Callaway–Sant'Anna DiD (`cs_did_analysis_v2.Rmd`), event studies, robustness checks |
| `output/` | Everything the analysis produces, grouped by track then kind: `descriptive/{figures,tables,results}/` and `causal/{figures,tables,results}/`. See `output/README.md` for the rules |
| `docs/` | Source for the interactive data dictionary |

Code folders hold code; `data/` holds sources and built tables; `output/` holds
results. The numbers on the `data/` folders are the direction of travel: one
rule places every file, and nothing in `02` ever reads from `03`.

```
01_source ──→ 02_measure ──→ 03_panels
     └──────────────────────────↗
```

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
| `build_predictor_panel.R` | runs — V-Dem and WDI read from the pinned snapshots; set `refresh_sources <- TRUE` to re-pull |
| `causal_inf_data_prep.R` | runs, needs network — pulls the World Bank SPI index live |
| `build_analysis_frame.Rmd` | runs |
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

MIT. See [LICENSE](LICENSE).
