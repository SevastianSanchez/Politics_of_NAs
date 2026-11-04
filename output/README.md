# output/

Everything the analysis produces. Grouped by **analysis track first**, then by
kind, so that regenerating one track means clearing one folder:

```
output/
  descriptive/      descriptive_stats/descriptive_analysis.Rmd
    figures/        19 PNGs
    tables/         PNG for the draft + CSV of the same numbers
    results/        findings as data
  causal/           causal_inference_mods/*.Rmd
    figures/        6 knitted CS DiD plots (PDF), names mirroring results/
    tables/         PNG + CSV, four regression/diagnostic tables
    results/        Callaway-Sant'Anna ATTs (4 CSVs), multi-series event counts
```

**Rules, so this does not drift again.**

1. **Nothing here is an input.** Scripts read from `data/`, and write here.
   If a script needs something another script produced, that belongs in
   `data/panels/` or `data/clean/`, not in `output/`.
2. **One writer per file.** The script that creates a file owns it. Two scripts
   writing the same path is the bug that cost us `MAIN_panel_data` once already.
3. **Every table gets a CSV next to its PNG.** A table saved only as an image
   cannot be checked, re-used by the dashboard, or diffed when the measure
   changes. `save_kable`/`gtsave` for the image, `write_csv` for the numbers,
   same basename.
4. **Paths go through `here()`.** `here("output/descriptive/figures/x.png")`,
   never `"descriptive_stats/figures/x.png"`. `here()` resolves from the
   `.Rproj` root whatever the working directory is, which is what lets these
   Rmds knit — knitr sets the working directory to the Rmd's own folder, so
   bare relative paths silently resolve to the wrong place.
5. **`figures/` means plots; `tables/` means tables.** Four causal tables used
   to live in a folder called `figures/`. They are tables.

Figures and tables are tracked in git on purpose: they are small, they are the
figures in the paper draft, and a reviewer opening the repo should see results
without running anything.

Knitted output does not stay beside the Rmd. The CS DiD figures were sitting in
`causal_inference_mods/cs_did_analysis_v2_files/figure-latex/` with knitr's own
names (`plot-group-att-1.pdf`); they are now in `causal/figures/` named after
the results they go with. `*_files/` and `*_cache/` are gitignored, so anything
left there is lost on the next clean -- write figures here explicitly.
