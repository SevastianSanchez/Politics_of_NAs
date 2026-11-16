# Superseded scripts

**Nothing in this folder should be run.** Each file is kept only for the
evidence it records. The finding each one established is summarised below and
in `METHODS_LOG.md`; the file itself is the provenance a reviewer can check.

| File | What it established | Why it is not used |
|---|---|---|
| `build_irt_goals_defaults.R` | the bifactor specification, and the definitions of `goal_relative`, `goal_level` and `expected_share` | scores with `fscores(..., QMC = TRUE)`, which collapsed 36% of posterior SDs below 1e-6. A ladder from 2,000 to 128,000 QMC points showed the cause is sampling, but convergence needs on the order of 10⁹ points. |
| `build_irt_goals_fast.R` | **that `accelerate = "squarem"` is what makes this model tractable** — 288 cycles against mirt's default running past 19 hours without returning | also scores by QMC. Its two other speedups, `TOL = 1e-3` and `quadpts = 31`, were unnecessary hedges. |
| `build_irt_goals_strict.R` | that the loose tolerance and coarse quadrature were the settings that actually approximated, while squarem costs no accuracy | reads `irt_goal_fast_scores.rds`, which has been retired, so it no longer runs. |
| `build_docs_goal_preview.R` | the shape of the goal panel on the landing page, while the goal model was still estimating | wrote `docs/goal_preview.json`, **raw reporting shares** shown as a placeholder. The page now reads `docs/goal_scores.json`, the released `goal_level` scores, so both the script and its output were retired on 9 Nov 2026. Running it would put placeholder figures back into `docs/`. |

## What replaces them

The bifactor fit uses `accelerate = "squarem"`, runs in checkpointed chunks,
and is scored by a **hand-written exact bifactor scorer** that exploits the
property mirt's `fscores` does not: given the general factor, each series
depends on only one goal factor, so every integral is at most two-dimensional.
That scorer reproduces mirt's own `method = "EAP_general"` at correlation 1,
max absolute difference 0, and scores all 17 factors in 54 seconds with no
zero or NaN standard errors.

`code/data_prep/build_irt_goals.R` is now that production script, and
`code/data_prep/build_irt_bifactor.R` builds `goal_relative` from a cold start.
The file that once held the `build_irt_goals.R` name is here as
`build_irt_goals_defaults.R` — renamed so the canonical name can only ever mean
the working script. The three goal-fit names here describe the numerical
settings that distinguish them: `_defaults`, `_fast`, `_strict`.
