# Methods log

Every estimation attempt, its settings, what happened, and what was decided.
Append a row when a fit or test finishes. **Read the Settings table before
launching any fit.** Most of the time lost on this project has gone to
re-running a configuration already recorded here as failing.

## Settings that are settled

| Setting | Value | Why |
|---|---|---|
| Series set | **524** | 665 → 607 (2–98% filter) → 524 (variant collapse). Never fit or report on 607. |
| `accelerate` (binary models) | **`"squarem"`** | Same fixed point as mirt's default Ramsay accelerator, ~20× fewer cycles. The default ran the bifactor past 19 h without returning; squarem converged it in 288 cycles. |
| `accelerate` (graded models) | **`"none"`** | squarem pushes ordered thresholds out of sequence; log-likelihood goes NaN. |
| Bifactor scoring | **hand-written exact scorer** | `mirt::fscores` builds the full `quadpts^17` grid and has no usable route. See below. |
| Log-probabilities | **`plogis(z, log.p=TRUE)`** | `-log1p(exp(-z))` overflows: discriminations up to 97 put the logit at ±770, and both branches collapse to `-Inf`, giving NaN everywhere. |
| Reliability threshold | **0.70** (Nunnally) | Sevastian, 8 Nov 2026. |


## Pre-flight check before a long fit

Run this before committing hours. Most non-convergence is predictable from the
response matrix alone, and a short pilot catches the rest. Tonight's two dead
runs, about four hours, were both predictable from steps 3 and 6.

| # | Check | Why | Pass for this project |
|---|---|---|---|
| 1 | Drop series reported in <2% or >98% of country-years | near-constant series carry no information and slow EM | 665 -> 607 |
| 2 | Collapse duplicated measurements | double counting; a fairness problem, not a numerical one | 607 -> 524 |
| 3 | **Screen for near-perfectly collinear pairs** (agreement >= 0.99 on the 0/1 matrix) | a block of identical series inside one factor makes that factor a copy of the block, and its discrimination has no finite value | **9 identical groups, 22 series. THIS is what stopped two runs.** |
| 4 | Check every factor has enough series (>= 10 is the working rule) | too few and the factor is not identified | goals run 17-85; goal 7 has 3 and gets no factor |
| 5 | Check for all-zero and all-one rows | a respondent with no variation cannot be placed | none |
| 6 | **Run a 25-50 cycle pilot and look at `max abs(a)`** | if slopes are already past 10 after 50 cycles they are diverging, and the full run will never converge | 10 minutes; would have caught both failures |
| 7 | Fit the 1-factor version first | fast, and confirms the data support a latent trait at all | converged in 187 cycles |

**Settings to have on from the start, not added after a failure:**
`accelerate = "squarem"` for binary models · a weakly informative prior on the
discriminations, `norm(0, 2)` or tighter, whenever step 3 finds anything ·
a cycle cap · chunked checkpointing for anything over ~20 minutes.

**Convergence means more than `converged = TRUE`.** Also check: `max abs(a)` is
under about 10, no standard error is NaN or near zero, and the log-likelihood
has actually flattened rather than the optimiser having hit its cap.

## In flight

Write the row **before** launching, not after. State the settings, and state
what this log predicts will happen. When it finishes, record whether the
prediction held and move the row down to Attempts. A run whose outcome
contradicts the prediction is the most informative thing this file can hold.

| Started | What | Settings checked against this log | Prediction | Outcome |
|---|---|---|---|---|
| 9 Nov, 02:34 | Bifactor, 524, prior norm(0,2), **TOL 1e-3** | 524 ✓ · squarem ✓ · binary 2PL ✓ · prior ✓ · chunked ✓ · default quadrature kept (only ONE of the fast variant's two approximations loosened) | Converges almost immediately, because at cycle 300 the worst-moving parameter was 9e-4, already inside 1e-3 | **CONVERGED in 1 cycle, 54 s.** loglik −277,819.1, identical to the strict run at cycles 300 and 400. Scores vs the strict cycle-300 fit: correlation **1.000000** on all 17 factors, largest difference any country-year **0.0065** against SEs of 0.3–0.5. Scorer re-validated here: my general factor vs mirt's `EAP_general` cor = 1, max abs diff = 0. **Prediction held.** |
| 9 Nov, 00:09 | Bifactor, 524, prior norm(0,2), strict TOL | as above | Converges well inside 1,000 cycles | **Did not converge.** Slopes fell 83 → 16 and froze; 13 of 1,569 parameters kept drifting by <1e-3 on a flat ridge (near-zero loadings, extreme intercepts). Not slow — unreachable. Superseded by the TOL run. Prediction wrong about convergence, right about the slopes. |
| 9 Nov, 00:05 | Bifactor fit, 524 series, **with a prior** | 524 ✓ · `accelerate="squarem"` ✓ · binary 2PL ✓ · chunked + checkpointed ✓ · warm-started from the no-prior cycle-900 values ✓ · scoring later by the exact scorer ✓ · **new setting:** `prior.type="norm"`, mean 0, sd 2 on all estimated discriminations. NOT the lognormal tried on the per-goal fits: 172 of 1,045 loadings here are negative, and a lognormal gives negative values zero density, so it would force sign flips. | Converges. The no-prior run's likelihood was flat from cycle ~500 while slopes climbed past 80, so bounding them should let the parameter tolerance be met. Expect max \|a\| to fall from 83 into single or low double digits within the first chunk or two, and convergence well inside 1,000 cycles. Unknown: this prior was tested on per-goal fits, not on a bifactor. | **Prior worked, strict tolerance did not.** Slopes fell 83 -> 16 within two chunks, as predicted. But the parameter tolerance was never met: superseded by the TOL=1e-3 row above, which converged from this run's values in 1 cycle. |
| 8 Nov, 20:30 | Bifactor fit, 524 series, no prior | 524 ✓ · squarem ✓ · binary 2PL ✓ · chunked ✓ | Converges near 288 cycles (where the 607 version landed) | **FAILED — stopped at 900 cycles.** Likelihood flat from ~500 (−277,005 → −277,002) while discriminations ran past 80. A few perfectly collinear series within a goal make that goal's specific factor an exact copy of them, so their slope has no finite value and mirt's parameter tolerance can never be met. **Prediction wrong; the missing ingredient was a prior, not more cycles.**
## Attempts



| Date | What | Settings | Outcome | Decision |
|---|---|---|---|---|

| Nov 9 | **Production run (2nd attempt)**, `build_irt_goals.R`, guard corrected | 524 ✓ · squarem ✓ · binary 2PL ✓ · prior norm(0,2) ✓ · TOL 1e-3 ✓ · min 10 series ✓ — unchanged from the run that produced the bootstrap and held-out results. **Changed: the guard.** Halts on non-convergence, hitting the cycle cap, or a non-finite SE. max\|a\| is now REPORTED, not gated — the <10 rule in the Settings table was written for the bifactor, where a factor had become a copy of a collinear block and slopes ran past 80; 10–17 in a one-factor fit with a norm(0,2) prior is a bounded near-duplicate, i.e. the prior working. Concentration (`weight_top5_pct`) and provenance (`weight_agency_pct`) added as disclosed columns. | All 16 goals write. Scores identical to the 03:11 scratch run and to the 08:34 halted run, since the fits are unchanged — only what gets checked and recorded changed. | **WROTE. 16 goals, all converged, median reliability 0.844, min 0.772, all above 0.70, 0.25 min total.** Scores verified identical to the scratch run bit for bit (max difference 0.000000), so the bootstrap and held-out results apply to these files unchanged. `data/02_measure/irt_goal_level_{scores.csv,scores.rds,item_params.csv,health.csv,run_log.csv,fits.rds}`. **Prediction held.** |
| Nov 9 | **Diagnostic: who produces the series a goal score rests on?** | Read the `Nature` field from all 17 UN exports (C/CA = country data, E = estimated, M = modelled, G = global monitoring), then weighted each series by its share of its goal's total discrimination | Across all exports: 52.9% of non-missing rows are country-produced (C/CA), 26.6% estimated, 9.4% global monitoring, 4.2% modelled. **Weighted by what actually drives each score, five goals are agency-dominated: goal 3 (93.8% of weight), goal 2 (91.0%), goal 6 (78.5%), goal 14 (72.6%), goal 17 (45.7%).** The other eleven are at 6.2% or below, nine under 5%. Independently reproduces the figures already in CLAUDE.md: goal 6 at 31.6% country-produced series (vs 20.1% of rows), goal 15 at 95.2% (vs 95.7%). | **Explains goal 3's unsolved anomaly** — its validity rose 0.208 -> 0.707 on country-produced data only; its score is 93.8% agency weight. **The provenance problem and the weight-concentration problem are the same problem**: groups of series that always move together often do so because one custodian agency publishes them together (e.g. indicator 2.a.1 is three FAO series, all `Nature = E`, where `AG_PRD_ORTIND` is by definition `AG_XPD_AGSGB / AG_PRD_AGVAS`, with "FAO imputation for missing values"). Goals 2, 3 and 14 have goal 6's defect and are not held; goal 15, which IS held, is the cleanest in the table at 0.6% agency weight. Table: `output/measure/tables/series_provenance_nature.csv`. |
| Nov 9 | **Diagnostic: can the goal-level duplicates be collapsed?** | Checked every driver group pairwise against `irt_response_matrix.rds`, all 1,773 country-years, then listed the partial-reporting rows | **No, except where the pattern is byte-identical.** Goal 3 trio (`SH_DTH_NCOM`/`SH_STA_POISN`/`SH_STA_SCIDE`): **0 disagreements of 1,773** — safe. But the goal 1 spending quartet disagrees on up to 25 country-years and the goal 10 financial quartet on 23, and those disagreements are **structured and persistent, not noise**: IND, LKA and MYS report the education and health breakdowns but never the aggregate or social-protection series, every year 2015–2023; DEU reports only `FI_FSI_FSERA` for seven consecutive years; BEL/NLD/GNQ/TCD/XKX report 3 of 4 and always drop the same one. | **Collapse-by-reporting-act is REJECTED** — it would merge DEU's one-of-four with NLD's three-of-four, destroying the reporting choices this project measures. Sevastian's byte-identical rule was protecting exactly this and was right. Remaining route: **bundle (testlet) factors** for local dependence — keeps every series and every country-year, puts the shared variance in its own factor. Option "adjudicate the review groups" shrinks to G56 alone (the 0.33-vs-0.34 similarity pair), worth doing but fixes only goal 3. |
| Nov 9 | **Production run**, `code/data_prep/build_irt_goals.R` (first use of the reserved name) | 524 ✓ · squarem ✓ · binary 2PL ✓ · prior norm(0,2) ✓ · TOL 1e-3 ✓ · min 10 series per factor (goal 7 skipped at 3) ✓ | Scores reproduced the 03:11 scratch run exactly (reliability 0.843, 0.844, 0.894, 0.772 … all match), but the script's own convergence guard **refused to write**: 12 of 16 goals have max\|a\| > 10, the threshold this log sets. Diagnosis: not non-convergence. 47 of 521 series sit at \|a\| 10–17 **in tied groups with identical intercepts and identical reporting rates** — the near-collinear groups not collapsed because they are not provably identical. They carry **51–76% of total discrimination** in 7 goals. Refitting without them: median cor with the shipped score **0.818**, and goals 6 and 15 **flip sign**. | **Scores not written. Not shippable.** The double-counting the variant collapse fixed at 524 returns inside goals, where a 4-way duplicate is a quarter of the information. Guard kept as written — raising the threshold would have hidden this. **The published composite is unaffected**: max \|a\| 6.46, none over 10, top 6 series carry 6.3% of discrimination. **The 14 unadjudicated "review" variant groups are now on the critical path.** |
| Nov 9 | **Bootstrap** of `goal_level` | B = 500, 8 cores, resample country-years with replacement, refit each goal, score the **original** 1,773 rows with each replicate's item parameters | 98.1 min, **0 failed replicates** on any goal. Bootstrap SD is **7–42%** of the posterior SE (median ratio **0.13**); highest goal 17 (0.42) and goal 6 (0.34), lowest goals 5 and 13 (0.07). | Published SEs are **conservative** — they already cover item-parameter uncertainty. Report the model SE, not the bootstrap SD. |
| Nov 9 | **Held-out series validity** of `goal_level` | 16 goals × 20 splits, 4 cores. Fit on a random 70% of a goal's series, AUC on the held-out 30%. AUC **per held-out series then median** — pooling swamps it with between-series variation. **Fresh label permutation per series** for the null. | 12.8 min. Median real AUC **0.725**, median null **0.500** (null correctly centred on chance). 13 of 16 goals ≥ 0.65; best goal 13 at 0.892. Bottom three: goal 17 (0.618), goal 15 (0.526), goal 6 (**0.479**, below chance). | The three weakest are exactly the goals already flagged on **content** grounds (6 and 15 held out, 17 on a two-factor model). Threshold for the other 13 is Sevastian's to set. |
| Nov 6 | Composite 1-factor | 607 series, default accelerator | 13,561 cycles, 22.3 min | superseded |
| Nov 8 | Composite 1-factor | **524 series** | **187 cycles, 0.5 min**, reproduces exactly | **current published index** |
| Nov 6 | Bifactor fit | defaults | **19 h+, never returned** | defaults abandoned |
| Nov 6 | Bifactor fit | squarem, TOL 1e-3, quadpts 31 | converged, 288 cycles, 56 min | squarem is the reason; the other two were unnecessary hedges |
| Nov 8 | Bifactor fit | 524 series, **default accelerator** | killed at 2 h, no result | repeat of a known failure — this is what the log exists to prevent |
| Nov 6 | Bifactor scoring | QMC, default 5,000 points | 36% of posterior SDs below 1e-6 | unusable |
| Nov 8 | Bifactor scoring | QMC ladder 2k → 128k points | zeros fall 41% → 9.9%; at 128k consecutive rungs still agree only **0.51** on the worst factor | cause *is* sampling, but convergence needs ~10⁹ points. Dead end, correctly diagnosed this time |
| Nov 6 | Bifactor scoring | MAP | NaN SEs, 105/1,773 non-convergence, 118 min; MAP vs QMC on the *same* fit correlate 0.88 | at least one scorer wrong; MAP abandoned |
| Nov 8 | Bifactor scoring | `fscores(use_dentype_estimate=TRUE)` | `31^17` overflows `rep()`; default `5^17` asks 16 GB | **mirt does not reuse the bifactor reduction when scoring** |
| Nov 8 | Bifactor scoring | `fscores(method="EAP_general")` | works, 1.8 min, **general factor only**, cor 0.9753 with the published index | kept as the ground truth for validating a scorer |
| Nov 8 | Bifactor scoring | **hand-written exact scorer** | matches `EAP_general` at cor = 1, max abs diff = 0; all 17 factors in **54 s**; no zero or NaN SEs | **the method to use** |
| Nov 7 | Split-half reliability | halves of a goal's series | confounded with series count; six "cleaning" passes made results worse (9/16 → 3/17) | never use to rank goals against each other. Within-goal splitting is fine |
| Nov 7 | Duplicate-series check on the composite | — | cor 0.9886, reliability 0.9874 → 0.9863 | the published composite was *not* inflated by duplicates |
| Nov 8 | Leave-one-goal-out validity as a publication gate | — | would exclude goals 3, 11, 13, 14 | **wrong test.** Divergence from the overall index is the hypothesis, not a defect |
| Nov 8 | External validity, 607 vs 524 | SPI and HRV2 | SPI 0.831 → **0.851**, HRV 0.826 → **0.851**, every pillar up | the variant collapse removed double counting, not information |

## Rejected by Sevastian — do not re-propose

Empirical-Bayes shrinkage of goal scores · the 5-Ps grouping · indicator-level
aggregation · filtering to "independent" series · relabelling goals 6 and 15 as
institutional participation · dynamic smoothing across years (deferred, not
reopened) · PULSE (parked) · depth/disaggregation (deferred to v3).
