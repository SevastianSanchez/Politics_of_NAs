# output/

Everything that checks the index. The descriptive and causal outputs moved to
the `politics-of-nas-paper` repo on 15 Nov 2026.

```
output/
  measure/          code/ -- building and checking the index itself
    tables/         external validity, SPI disagreements, collinear series,
                    series provenance
    results/        paper_numbers.txt, every figure the measurement paper quotes
    figures/        (empty)
```

**The scores themselves are not here.** `vsi` and `goal_level` live in
`data/02_measure/`, because they are inputs (rule 1 below). `output/measure/` holds only what *checks* them.

**Rules, so this does not drift again.**

1. **Nothing here is an input.** Scripts read from `data/`, and write here.
   If a script needs something another script produced, that belongs in
   `data/02_measure/`, not in `output/`.
2. **One writer per file.** The script that creates a file owns it. Two scripts
   writing the same path is the bug that cost us `MAIN_panel_data` once already.
3. **Every table gets a CSV next to its PNG.** A table saved only as an image
   cannot be checked, re-used by the dashboard, or diffed when the measure
   changes. `save_kable`/`gtsave` for the image, `write_csv` for the numbers,
   same basename.
4. **Paths go through `here()`.** `here("output/measure/figures/x.png")`,
   never a bare relative path. `here()` resolves from the
   `.Rproj` root whatever the working directory is, which is what lets these
   Rmds knit — knitr sets the working directory to the Rmd's own folder, so
   bare relative paths silently resolve to the wrong place.
5. **`figures/` means plots; `tables/` means tables.** Four causal tables used
   to live in a folder called `figures/`. They are tables.

Figures and tables are tracked in git on purpose: they are small, they are the
figures in the paper draft, and a reviewer opening the repo should see results
without running anything.

6. **Every file here must be regenerable by a script in `code/`.** Tracking
   results only works if a reader can tell which build produced them. On
   9 Nov 2026, thirteen CSVs and three PNGs were removed from
   `output/measure/` to `_private_archive/validation_607_pre_rebuild/`: they
   were computed on the 607-series index, the script that wrote them had since
   been replaced, and nothing could bring them up to date in place. One of them
   reported a median posterior SD of 0.1151 against the released index's
   0.1138. An orphaned result does not stay neutral; it quietly contradicts the
   measure.
