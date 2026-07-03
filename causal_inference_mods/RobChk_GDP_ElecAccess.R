library(dplyr)
library(fixest)
library(purrr)
library(tibble)

# Vector of SDG goal outcomes
sdg_vars <- paste0("prop_miss_SDG", 1:17)

# Sample A: full sample for main model (no GDP required)
panel_A <- panel %>%
  filter(
    !is.na(aut_ep),                 # treatment
    !is.na(log_pop),
    !is.na(electric_access),
    !is.na(rural_pop_pct),
    !is.na(luminosity)
  )

# Sample B/C: GDP-available sample (all of the above + non-missing log_gdppc)
panel_BC <- panel_A %>%
  filter(!is.na(log_gdppc))

# Model A: main spec, full sample, no GDP
mA <- feols(
  prop_sdg_missing ~ aut_ep + log_pop + electric_access + rural_pop_pct + luminosity |
    country_code + year,
  data    = panel_A,
  cluster = ~ country_code
)

# Model B: same spec, GDP-available sample, no GDP
mB <- feols(
  prop_sdg_missing ~ aut_ep + log_pop + electric_access + rural_pop_pct + luminosity |
    country_code + year,
  data    = panel_BC,
  cluster = ~ country_code
)

# Model C: GDP-available sample, with GDP
mC <- feols(
  prop_sdg_missing ~ aut_ep + log_pop + electric_access + rural_pop_pct + luminosity + log_gdppc |
    country_code + year,
  data    = panel_BC,
  cluster = ~ country_code
)

# =============================================================================
run_models_for_goal <- function(y_var) {
  # A: full sample, no GDP
  mA <- feols(
    as.formula(paste0(y_var, " ~ aut_ep + log_pop + electric_access + rural_pop_pct + luminosity | country_code + year")),
    data    = panel_A,
    cluster = ~ country_code
  )
  
  # B: GDP-available sample, no GDP
  mB <- feols(
    as.formula(paste0(y_var, " ~ aut_ep + log_pop + electric_access + rural_pop_pct + luminosity | country_code + year")),
    data    = panel_BC,
    cluster = ~ country_code
  )
  
  # C: GDP-available sample, with GDP
  mC <- feols(
    as.formula(paste0(y_var, " ~ aut_ep + log_pop + electric_access + rural_pop_pct + luminosity + log_gdppc | country_code + year")),
    data    = panel_BC,
    cluster = ~ country_code
  )
  
  list(A = mA, B = mB, C = mC)
}

# Run for all 17 SDG goals
twfe_ABC <- map(sdg_vars, run_models_for_goal)
names(twfe_ABC) <- sdg_vars

get_autep_coef <- function(m) {
  nm <- grep("^aut_ep", names(coef(m)), value = TRUE)
  if (length(nm) == 0) return(NA_real_)
  coef(m)[[nm[1]]]
}

coef_ABC <- map_dfr(
  sdg_vars,
  ~ {
    mods <- twfe_ABC[[.x]]
    tibble(
      sdg    = .x,
      beta_A = get_autep_coef(mods$A),
      beta_B = get_autep_coef(mods$B),
      beta_C = get_autep_coef(mods$C)
    )
  }
)
