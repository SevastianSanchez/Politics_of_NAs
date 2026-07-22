library(did)
library(dplyr)
library(purrr)
library(tibble)
library(ggplot2)


# Load data (adjust path if needed)
panel <- readRDS("data/output/MAIN_panel_data.rds")

# One row per country with its autocratization start year
aut_cohorts <- panel %>%
  filter(!is.na(aut_ep_start_yr)) %>% # treated countries only
  distinct(country_code, country_name.x, aut_ep_start_yr)

# 1) How many treated countries total?
aut_cohorts %>%
  summarise(n_treated_total = n())

# 2) How many have start years in 2015–2023?
aut_cohorts_1513 <- aut_cohorts %>%
  filter(aut_ep_start_yr >= 2015, aut_ep_start_yr <= 2023)

aut_cohorts_1513 %>%
  summarise(
    n_treated_1513 = n(),
    share_1513     = n() / nrow(aut_cohorts)
  )

# 3) How many would you lose by excluding pre‑2015 starts?
aut_cohorts_pre2015 <- aut_cohorts %>%
  filter(aut_ep_start_yr < 2015)

aut_cohorts_pre2015 %>%
  summarise(
    n_lost   = n(),
    share_lost = n() / nrow(aut_cohorts)
  )

# Optional: see which countries they are
aut_cohorts_pre2015 %>%
  arrange(aut_ep_start_yr)





