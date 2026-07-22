# Install once (if needed)
library(did)
library(dplyr)
library(ggplot2)

# Read your panel
panel <- readRDS("data/output/MAIN_panel_data.rds")

panel <- panel %>%
  mutate(
    country_code = as.character(country_code),
    country_id = as.numeric(factor(country_code)),
    year         = as.integer(year),
    aut_ep       = as.integer(aut_ep),
    elect_access = as.numeric(electric_access),
    elect_access_sq = electric_access^2,
    rural_pop_pct   = as.numeric(rural_pop_pct),
    prop_sdg_missing = as.numeric(prop_sdg_missing))

# Creating the “first treatment year” variable
panel <- panel %>%
  arrange(country_code, year) %>% 
  group_by(country_code) %>%
  
  # 1. First treatment year per country (your original logic)
  mutate(first_treat = ifelse(any(aut_ep == 1), min(year[aut_ep == 1]), 0L)
  ) %>%
  
  # 2. Episode IDs: runs of consecutive aut_ep values (0s and 1s)
  mutate(episode_group = consecutive_id(aut_ep) # increments when aut_ep changes
  ) %>%
  
  # 3. Within each country, map 1-groups to episode numbers
  mutate(episode_number = case_when(
    aut_ep == 0 ~ 0L,  # never in an episode
    aut_ep == 1 ~ as.integer(
      match(episode_group, sort(unique(episode_group[aut_ep == 1])))))) %>% 
  mutate(n_episodes = max(episode_number, na.rm = TRUE)) %>% 
  ungroup()

panel %>% select(country_code, year, aut_ep, first_treat, episode_group, episode_number) %>%
  head(50)

table(panel$first_treat)        # 0 = never treated; other values = first backsliding year
summary(panel$prop_sdg_missing) # check for missing/outliers

###### FILTERING FOR HETEROGENEITY ANALYSIS
#sub_panel <- subset(panel, income_level %in% c("LM", "L"))
#sub_panel <- subset(panel, regime_type_4 %in% c("3", "2"))
#sub_panel <- subset(panel, n_episodes %in% c("0", "2"))
#sub_panel <- sub_panel %>% filter(first_treat <= 2020)
sub_panel <- panel

###### COMPARING EFFECT ACROSS GOALS 
#y_var <- "prop_sdg_missing"
y_var <- "prop_miss_SDG4"

# NO COVARIATES YET 
cs_out_basic <- att_gt(
  yname   = y_var,  # outcome
  gname   = "first_treat",       # first year of aut_ep = 1 (0 = never-treated)
  idname  = "country_id",      # country identifier
  tname   = "year",              # time variable
  xformla = ~ 1,                 # ~1 = no covariates
  data    = sub_panel,
  est_method = "dr",            # regression-based estimator for ATT(g,t)
  panel   = TRUE                 # you have panel data, not repeated cross-sections
)
summary(cs_out_basic)

cs_out_basic_dyn <- aggte(
  cs_out_basic,
  type = "dynamic"   # event time: years relative to first backsliding
)
summary(cs_out_basic_dyn)
ggdid(cs_out_basic_dyn)

# STRUCTURAL COVARIATES 
cs_m2 <- att_gt(
  yname   = y_var,
  gname   = "first_treat",
  idname  = "country_id",
  tname   = "year",
  xformla = ~ elect_access + elect_access_sq + rural_pop_pct,
  data = sub_panel,
  est_method = "dr",   # regression-based ATT estimator
  panel   = TRUE
)
summary(cs_m2)

cs_m2_dyn <- aggte(
  cs_out_cov,
  type = "dynamic"   # event time: years relative to first backsliding
)
summary(cs_m2_dyn)
ggdid(cs_m2_dyn)

# + ECONOMIC PERFORMANCE 
cs_m3 <- att_gt(
  yname   = y_var,
  gname   = "first_treat",
  idname  = "country_id",
  tname   = "year",
  xformla = ~ dem_ep + elect_access + elect_access_sq + rural_pop_pct +
    log_gdppc + spi_overall + log_luminosity,
  clustervars   = "country_id",
  control_group = "notyettreated",
  data          = sub_panel,
  est_method    = "reg",
  panel         = TRUE
)
summary(cs_m3)

cs_m3_dyn <- aggte(
  cs_m3,
  type = "dynamic"   # event time: years relative to first backsliding
)
summary(cs_m3_dyn)
ggdid(cs_m3_dyn)




# Grab event times and ATT estimates
# Keep only event times between -4 and +6 (change if you want)
keep <- cs_m3_dyn$egt >= -4 & cs_m3_dyn$egt <= 6

e_short   <- cs_m3_dyn$egt[keep]
att_short <- cs_m3_dyn$att.egt[keep]
lower_short <- cs_m3_dyn$band.egt[keep, 1]
upper_short <- cs_m3_dyn$band.egt[keep, 2]

# Very simple base R plot
plot(
  e_short, att_short,
  type = "p",
  xlab = "Event time (years relative to first backsliding)",
  ylab = "ATT on prop_sdg_missing",
  main = "Dynamic ATT (restricted to -4 to +6)",
  ylim = range(c(lower_short, upper_short))
)

abline(h = 0, lty = 2)  # dashed zero line

arrows(
  x0 = e_short, y0 = lower_short,
  x1 = e_short, y1 = upper_short,
  angle = 90, code = 3, length = 0.05
)
