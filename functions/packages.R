# =============================================================================
# Visible States — package setup
# =============================================================================
#
# Source this at the top of any script:  source(here::here("functions/packages.R"))
#
# Installs anything missing, then loads everything. Safe to run repeatedly:
# installed packages are not reinstalled, and nothing prints unless an install
# happens.
#
# Only what the index's scripts use. The Politics of NAs paper's packages
# (fixest, did, vdemdata, ERT, ...) live in that repo's own packages.R.
#
# To add a package: put it in `packages` and it is installed and loaded on the
# next source().
# =============================================================================

packages <- c(
  "tidyverse",      # dplyr, tidyr, readr, purrr, stringr, tibble, ggplot2
  "here",           # project-root-relative paths
  "data.table",     # fread/fwrite, dcast; loaded after tidyverse on purpose
  "mirt",           # the IRT fits
  "readxl",         # UN exports, SDG update log
  "janitor",        # clean_names
  "countrycode",    # M49 -> ISO3
  "jsonlite"        # site data files
)

.have <- function(p) requireNamespace(p, quietly = TRUE)
.missing <- packages[!vapply(packages, .have, logical(1))]
if (length(.missing) > 0) {
  message("Installing ", length(.missing), " missing package(s): ",
          paste(.missing, collapse = ", "))
  install.packages(.missing, dependencies = TRUE,
                   repos = "https://cloud.r-project.org/")
}

# Conflict messages are suppressed: the masking is expected (dplyr::filter over
# stats::filter) and scripts qualify with :: where it matters.
invisible(lapply(packages, function(p) {
  suppressPackageStartupMessages(
    library(p, character.only = TRUE, warn.conflicts = FALSE))
}))

.failed <- packages[!vapply(packages, function(p) p %in% loadedNamespaces(), logical(1))]
if (length(.failed) > 0) {
  warning("Could not load: ", paste(.failed, collapse = ", "),
          "\nInstall them manually, then source this file again.", call. = FALSE)
}

rm(.have, .missing, .failed)
