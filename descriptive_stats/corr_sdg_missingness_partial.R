# =============================================================================
# PLACEHOLDER — partial correlations: SDG missingness x democracy levels
# =============================================================================
#
# PURPOSE (not yet written)
# ------------------------
# The partial-effects counterpart to corr_sdg_missingness.R. That script
# correlates goal-level missingness against democracy indices directly; this
# one is meant to do the same NET of the structural covariates (income,
# log_gdppc, log_pop, rural_pop_pct, statistical capacity), so the remaining
# association is not just development level operating through both sides.
#
# SOURCED BY
# ----------
#   descriptive_stats/descriptive_analysis.Rmd  (chunk is eval=FALSE for now)
#
# STATUS
# ------
# Intentionally empty. It parses and sources cleanly, so the caller does not
# break while this is unwritten. Replace this file when the analysis is built;
# do not delete it without also removing the source() call above.
#
# NOTE ON INPUTS
# --------------
# The sibling script reads data/panels/predictor_panel.rds and the
# SDR-derived prop_miss_SDG*_sdr columns. Those outcomes are superseded by
# data/clean/goal_lvl_dv_data.rds, so point this at the new measure when you
# write it rather than reproducing the old one.
# =============================================================================
