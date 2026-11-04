Notes written alongside the 2026 causal-inference work.
Was "Guides_Info/"; renamed 4 Nov 2026 because these are notes, not guides to
the current pipeline. Read them as a record of the earlier analysis, not as
instructions.

ANALYSIS_OVERVIEW.txt       Still accurate. The research question and the three
                            complementary approaches (TWFE, event study,
                            Callaway-Sant'Anna). Nothing in it has gone stale.

INTERPRETATION_GUIDE.txt    PARTLY STALE. The variable definitions and the
                            guidance on reading coefficients are still useful,
                            but it defines the outcome as prop_sdg_missing --
                            the SDSN/SDR measure, which is abandoned. The
                            current outcomes are the dv_* measures built in
                            data/clean/goal_lvl_dv_data.rds.

QUICK_START_GUIDE.txt       STALE INSTRUCTIONS. Tells you to put ES_panel_data.csv
                            and install_packages.R in a directory. Neither
                            exists: ES_panel_data.csv was an orphan with no
                            builder and was removed, and install_packages.R was
                            merged into code/packages.R. The current entry point
                            is code/packages.R, and the panels are built by
                            code/data_prep/.

Summary.docx                Written-up summary from the same period. Same SDR
                            caveat as the interpretation guide.
