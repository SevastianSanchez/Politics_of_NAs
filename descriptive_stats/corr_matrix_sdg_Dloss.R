library(ggplot2)
library(dplyr)
library(tidyr)
library(purrr)

load("data/output/sdg_democracy_paneldata.RData") # updated 

# Extract the data 
corr_data <- df2 %>%
  dplyr::select(country_name, country_code, year, matches("^prop_miss_sdg\\d+"), 
                elect_dem, log_gdppc, log_pop, income_level, rural_pop_pct, 
                rd_expenditure_pct)

# Matrix: (R) correlations for each SDG against elect_dem by year
correlation_data <- corr_data %>%
  select(year, matches("^prop_miss_sdg\\d+"), elect_dem) %>%
  group_by(year) %>%
  summarise(
    across(
      matches("^prop_miss_sdg\\d+"),
      ~cor(.x, elect_dem, use = "pairwise.complete.obs"),
      .names = "{.col}"
    )
  ) %>%
  pivot_longer(
    cols = matches("^prop_miss_sdg\\d+"),
    names_to = "SDG",
    values_to = "correlation"
  ) %>%
  mutate(
    # Extract SDG number for better labeling
    SDG_number = as.numeric(str_extract(SDG, "\\d+")),
    SDG_label = paste("SDG", SDG_number)
  )

# Create the heatmap
ggplot(correlation_data, aes(x = factor(year), 
                             y = fct_reorder(SDG_label, SDG_number, .desc = TRUE), 
                             fill = correlation)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = round(correlation, 2)), size = 3, color = "black") +
  scale_fill_gradient2(
    low = "#2166ac",
    mid = "white",
    high = "#b2182b",
    midpoint = 0,
    limits = c(-1, 1),
    name = "Pearson R"
  ) +
  labs(
    title = "Correlation between SDG Missingness and Democracy Levels",
    subtitle = "Years 2015 - 2023",
    y = "SDG Goal",
    x = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(
    axis.text.x = element_text(angle = 0, hjust = 0.5),
    axis.text.y = element_text(size = 10),
    panel.grid = element_blank(),
    plot.title = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5),
    legend.position = "right"
  )

