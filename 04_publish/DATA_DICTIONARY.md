# Visible States — data dictionary (v1.4.0)

Every file in the VSI bundle, and every column in it. Country–years run
2015–2023 for 197 countries (1,773 country–years). Every table keys on `iso3` +
`year`, plus `goal` for the goal files.

**What the scores measure.** How much a government reports to the UN Sustainable
Development Goal (SDG) database, estimated from 524 statistical series. A blank
cell counts as not reported. Scores come from item response theory (2PL) models:
each is an estimate of a country–year's position on a latent scale, centred near
0 with a standard deviation near 1. **Higher means more reporting.** Every score
has a standard error (`_se`); a 95% interval is roughly the score ± 2 SE.

## `vsi_scores.csv` — the overall index

One row per country–year (1,773 rows).

| Column | Meaning |
|---|---|
| `iso3` | ISO 3166-1 alpha-3 country code |
| `country_name` | Country name |
| `income_level` | World Bank income group; `Unclassified` where none is given |
| `year` | 2015–2023 |
| `vsi` | **Visible States Index**: overall reporting, one factor over all 524 series |
| `vsi_se` | Standard error of `vsi` (posterior standard deviation) |

## `vsi_goal_scores.csv` — reporting on each goal

One row per country–year–goal (28,368 rows: 16 goals). Each goal is its own
one-factor model, fitted on that goal's series only, so a score answers *how much
does this country report on this goal?* The country's overall reporting level is
**included**.

| Column | Meaning |
|---|---|
| `iso3`, `country_name`, `income_level`, `year` | as above |
| `goal` | SDG number, 1–17 (goal 7 is not scored; see below) |
| `goal_name` | SDG name |
| `vsi_goal` | Reporting on this goal |
| `vsi_goal_se` | Standard error of `vsi_goal` |
| `status` | `release`, or `hold_content` for goals 6 and 15 (see below) |

## `vsi_goal_relative_scores.csv` — each goal relative to the country's own level

Same shape as `vsi_goal_scores.csv`. From one bifactor model: a general factor
(overall reporting) plus one factor per goal. The goal factor answers *does this
country report more or less on this goal than its own overall level would
predict?* Positive means more than expected, negative less. New in v1.4.0.

| Column | Meaning |
|---|---|
| `iso3`, `country_name`, `income_level`, `year`, `goal`, `goal_name`, `status` | as above |
| `vsi_goal_relative` | Reporting on this goal, net of the country's overall level |
| `vsi_goal_relative_se` | Standard error of `vsi_goal_relative` |

## `goal_diagnostics.csv` — how much to trust each goal score

One row per goal per layer (32 rows). Published so readers can weigh each goal;
nothing is excluded for imprecision.

| Column | Meaning |
|---|---|
| `layer` | `vsi_goal` or `vsi_goal_relative` |
| `goal`, `goal_name` | as above |
| `series` | Number of series the goal score is built from |
| `reliability` | Share of score variance that is signal: var(score) / (var(score) + mean SE²). **0.70** is the conventional reference point (Nunnally), not a cut |
| `se_median` | Median standard error across country–years |
| `weight_top5_pct` | Share of the goal's total weight carried by its 5 most influential series. High = the score rests on a few series |
| `weight_agency_pct` | Share of the goal's weight from series produced by international agencies rather than countries. High = the score partly records agency publishing, not government reporting |
| `status` | `release` or `hold_content` |

## Goals not scored, or held

- **Goal 7 (energy) is not scored** in either goal layer. Only 3 of its series
  remain after filtering, too few to fit, and all three are UN agency estimates
  rather than country data.
- **Goals 6 (water) and 15 (land) are held** (`status = hold_content`) on content
  grounds, for different reasons. Goal 6's series are mostly satellite
  measurements, so "reported" largely records whether an agency published a
  dataset. A third of goal 15's series are treaty and policy instruments, which may
  track commitment status rather than reporting. Their scores are included but
  should not be read as reporting effort.
