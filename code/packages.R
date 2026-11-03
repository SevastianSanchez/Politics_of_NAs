# =============================================================================
# Politics of NAs — package setup
# =============================================================================
#
# Source this at the top of any script:  source("code/packages.R")
#
# It installs anything missing, then loads everything. Safe to run repeatedly:
# already-installed packages are not reinstalled, and nothing is printed unless
# an install actually happens. Replaces the old split between packages.R
# (which loaded) and install_packages.R (which installed a smaller, different
# set, so a fresh machine still hit missing-package errors).
#
# TWO PACKAGES ARE NOT ON CRAN. vdemdata and ERT are published only on the
# V-Dem Institute's GitHub, so install.packages() cannot fetch them — the old
# install script would have failed on both. They are installed from source here.
#
# To add a package: put it in cran_packages (or github_packages with its repo),
# and it is installed and loaded on the next source().
# =============================================================================

cran_packages <- c(
  # core
  "tidyverse",      # dplyr, tidyr, readr, purrr, stringr, tibble, ggplot2, forcats
  "here",           # project-root-relative paths
  "devtools", "remotes",

  # reading data
  "readxl", "jsonlite", "janitor", "WDI", "rsdmx", "countrycode",

  # modelling
  "fixest",         # fast fixed effects (TWFE)
  "did",            # Callaway-Sant'Anna staggered DiD
  "plm",            # panel models
  "lmtest", "sandwich",   # hypothesis tests, robust SEs
  "car",            # VIF and regression diagnostics
  "mice",           # multiple imputation
  "mediation",      # mediation analysis
  "ppcor", "corpcor",     # partial correlations
  "broom",          # tidy model output

  # tables and reporting
  "modelsummary", "stargazer", "kableExtra", "flextable", "gt", "knitr", "DT",

  # plotting
  "scales", "patchwork", "gridExtra", "reshape2",
  "ggcorrplot", "plotly", "ggdag", "dagitty"
)

# name = GitHub repo. Not on CRAN.
github_packages <- c(
  vdemdata = "vdeminstitute/vdemdata",   # V-Dem indices
  ERT      = "vdeminstitute/ERT"         # Episodes of Regime Transformation
)


# ---- install anything missing -----------------------------------------------
.have <- function(p) requireNamespace(p, quietly = TRUE)

.missing_cran <- cran_packages[!vapply(cran_packages, .have, logical(1))]
if (length(.missing_cran) > 0) {
  message("Installing ", length(.missing_cran), " missing CRAN package(s): ",
          paste(.missing_cran, collapse = ", "))
  install.packages(.missing_cran, dependencies = TRUE,
                   repos = "https://cloud.r-project.org/")
}

.missing_gh <- github_packages[!vapply(names(github_packages), .have, logical(1))]
if (length(.missing_gh) > 0) {
  message("Installing ", length(.missing_gh), " package(s) from GitHub: ",
          paste(names(.missing_gh), collapse = ", "))
  # remotes is lighter than devtools and is in cran_packages above, so by this
  # point it is installed.
  for (i in seq_along(.missing_gh)) {
    remotes::install_github(.missing_gh[[i]], upgrade = "never")
  }
}


# ---- load -------------------------------------------------------------------
# tidyverse attaches dplyr/tidyr/readr/purrr/stringr/tibble/ggplot2, so those
# are not listed again. Conflict messages are suppressed: the masking is
# expected (dplyr::filter over stats::filter) and scripts qualify with :: where
# it matters.
.to_load <- c(cran_packages, names(github_packages))
.to_load <- setdiff(.to_load, "remotes")   # used above, no need to attach

invisible(lapply(.to_load, function(p) {
  suppressPackageStartupMessages(
    library(p, character.only = TRUE, warn.conflicts = FALSE))
}))

.failed <- .to_load[!vapply(.to_load, function(p)
  p %in% loadedNamespaces(), logical(1))]
if (length(.failed) > 0) {
  warning("Could not load: ", paste(.failed, collapse = ", "),
          "\nInstall them manually, then source this file again.", call. = FALSE)
}

rm(.have, .missing_cran, .missing_gh, .to_load, .failed)
