# run_all.R -- runs the Visible States pipeline in stage order.
#
# Quick stages run by default. The long fits and checks are off unless asked:
#   Rscript run_all.R                 quick stages only (~minutes)
#   FITS=1   Rscript run_all.R        also refit vsi and vsi_goal (read METHODS_LOG.md first)
#   CHECKS=1 Rscript run_all.R        also run the held-out checks
#
# Never run with FITS=1 without reading METHODS_LOG.md: every fit setting is
# recorded there, along with the configurations that already failed.
# The extract (02_prepare/extract_SDG_series_data_2015_2023.R) needs the UN
# exports in 01_sources/un_sdg_exports/ and is not run here.
# The bifactor (05_vsi_goal_relative) and both bootstraps take hours and are
# never run from here; run them on their own, chunked, after `bash runs.sh`.

library(here)
step <- function(f) {
  cat(sprintf("\n[%s] %s\n", format(Sys.time(), "%H:%M:%S"), f))
  status <- system2("Rscript", here(f))
  if (status != 0) stop("failed: ", f, call. = FALSE)
}
on <- function(v) identical(Sys.getenv(v), "1")

if (on("FITS")) {
  step("02_prepare/build_variant_map.R")
  step("03_vsi/build_irt_composite.R")
  step("04_vsi_goal/build_irt_goals.R")
}
step("03_vsi/checks/validate_vsi_external.R")
if (on("CHECKS")) step("04_vsi_goal/checks/validate_goal_level_heldout.R")
step("02_prepare/checks/collinear_series_report.R")
step("06_publish/build_docs_data.R")
step("06_publish/paper_numbers.R")
cat("\ndone.\n")
