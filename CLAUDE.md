# The Politics of NAs / The World on Record

## Before running any model fit — mandatory, no exceptions

**Read `METHODS_LOG.md` before launching any fit, every time.** Not when it
seems warranted; always. Re-running a configuration already recorded there as
failing is the single largest source of wasted time on this project, and it has
happened after the failure was written down and read.

The rule has three parts, and the third is what makes it checkable:

1. **Read the Settings table** in `METHODS_LOG.md` before writing the command.
2. **State in your reply, before the fit runs,** which settled settings apply
   and that the command matches them. If something differs, say what and why
   before launching, not after.
3. **Write the row BEFORE launching**, in the `In flight` section: the
   settings, and what this log predicts will happen. Record the outcome when
   it finishes and move the row down to `Attempts`. A diary written after the
   fact cannot catch a repeat; a prediction written before it can. A failed
   run gets a row too, and those are the valuable ones.

A hook at `.claude/hooks/methods_log_gate.sh` prints the settled settings
before any Bash command containing `Rscript`, `mirt`, `bfactor` or
`build_irt`. It is a reminder, not a substitute for reading the log.

## Hard constraints

- **The series set is 524.** 665 → 607 (2–98% filter) → 524 (variant collapse).
  Never fit, score or report on 607. `irt_prep.R` enforces this and halts if the
  variant map is missing or stale.
- **Binary IRT fits use `accelerate = "squarem"`.** Graded fits must use
  `accelerate = "none"` — squarem breaks ordered thresholds.
- **Long fits run chunked and checkpointed.** Two runs of two hours each were
  lost to a sleeping laptop because mirt writes nothing until it converges.
- **Say series, not items. Say factor, not dial.** After the collapse the 524
  are still series; the redundant ones were dropped, not merged.
- **Never put sev.sanchez02@gmail.com in a public file.** Use ss7257@columbia.edu.
- **Do not kill a long-running process without asking.**
- **Account for every running process.** Run `bash code/runs.sh` before
  launching a fit and again after killing one, and say in the reply what it
  found. Two superseded bifactor fits were found still running after 26 hours
  on 9 Nov, pinning two cores while the fit that replaced them had long since
  finished. `mclapply` workers are reparented to `init` when the parent dies,
  so killing a parent is not killing the run. When a fit is superseded, stop
  it then — not when a slow laptop finally gives it away.
- **Goal scores diverging from the overall index is the research hypothesis**,
  not a validity failure. Never gate the sector layer on correlation with the
  overall index.

## Release standard for the sector layer

**Disclose, do not gate.** Every goal score ships, each printed with its
reliability and standard error. Nothing is excluded for imprecision; 0.70
(Nunnally) is reported as a reference point, not applied as a cut. Goals 6 and
15 are the exception and are held out on CONTENT grounds, not precision, and
for DIFFERENT reasons. Goal 6 is 80% agency-produced: its series are satellite
measurements of lakes, wetlands and river flow, so "reported" largely records
whether an agency published a dataset, not a country's choice. Goal 15 is 95.7%
country-produced but a third of its series are treaty and policy instruments
(Nagoya Protocol, Aichi targets, NBSAP), which may track commitment status
rather than reporting effort. An error bar cannot warn a reader about either.

## Scores and their names

| Column | Meaning |
|---|---|
| `twr` | overall index: one factor, all 524 series |
| `goal_level` | reporting on that goal, overall level included |
| `goal_relative` | that goal relative to the country's own overall level (bifactor specific factor) |

Each has a matching `_se`. `sector_tilt` is retired.

## Layout

`code/data_prep/` builds · `data/01_source` → `data/02_measure` → `data/03_panels`
· `output/{measure,descriptive,causal}/{figures,results,tables}` · `docs/` is the
public site · `releases/<version>/` is what gets deposited at Zenodo.
One writer per file; paths via `here()`.
