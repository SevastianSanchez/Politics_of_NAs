# =========================================================
# Event-time plot:
# Count of countries with increased SDG missingness
# relative to the immediately previous calendar year
# =========================================================

# 1) Load packages and data ----
source("code/packages.R")

panel <- read_csv("data/output/MAIN_panel_data.csv")
  
ts_data <- panel %>%
  group_by(country_code) %>%
  # 1) mark candidate episode start years
  mutate(
    first_treat_raw = if_else(
      aut_ep == 1 &
        !is.na(aut_ep_start_yr) &
        aut_ep_start_yr >= 2015 &
        aut_ep_start_yr <= 2023,
      aut_ep_start_yr,
      NA_real_
    )
  ) %>%
  # 2) keep only countries that ever have a valid first_treat
  filter(any(!is.na(first_treat_raw))) %>%
  # 3) collapse to ONE first_treat per country
  mutate(
    first_treat = min(first_treat_raw, na.rm = TRUE),
    event_time  = year - first_treat    # compute AFTER we fix first_treat
  ) %>%
  ungroup()

  
# 2) Keep needed variables and restrict sample ----
ts_data <- ts_data %>%
  dplyr::select(
    country_name.x,
    country_code,
    year,
    aut_ep,
    first_treat,
    #episode_group,
    #episode_number,
    event_time,
    aut_ep_start_yr, 
    aut_ep_end_yr,
    n_sdg_indicators,
    n_sdg_missing,
    prop_sdg_missing,
    prop_missing_pct,
    starts_with("n_miss_SDG"),
    starts_with("prop_miss_SDG")
  ) %>%
  group_by(country_code) %>%
  arrange(year, .by_group = TRUE) %>%
  filter(sum(aut_ep, na.rm = TRUE) > 0) %>%
  ungroup()

# 3) Create marginal-change indicators (overall n_sdg_missing) ----
ts_overall_changes <- ts_data %>%
  group_by(country_code) %>%
  arrange(year, .by_group = TRUE) %>%
  mutate(
    prev_year        = dplyr::lag(year),
    prev_n_sdg_missing = dplyr::lag(n_sdg_missing),
    
    # only compare to the *immediately previous calendar year*
    has_valid_prev = !is.na(prev_n_sdg_missing) &
      (year - prev_year == 1),
    
    increased = has_valid_prev & (n_sdg_missing > prev_n_sdg_missing),
    decreased = has_valid_prev & (n_sdg_missing < prev_n_sdg_missing),
    same      = has_valid_prev & (n_sdg_missing == prev_n_sdg_missing),
    
    # an observation is "usable" for margins if both years are observed
    observed_pair = has_valid_prev
  ) %>%
  ungroup()


# 4) Aggregate to event-time window −8 to +8 ----
plot_df_overall <- ts_overall_changes %>%
  # limit to the event-time window of interest
  filter(event_time >= -8, event_time <= 8) %>%
  group_by(event_time) %>%
  summarise(
    # number of countries with observed n_sdg_missing in this year
    n_countries_obs = dplyr::n_distinct(country_code[!is.na(n_sdg_missing)]),
    
    # among those with valid previous year, counts of margin types
    n_increase = dplyr::n_distinct(country_code[increased]),
    n_decrease = dplyr::n_distinct(country_code[decreased]),
    n_same     = dplyr::n_distinct(country_code[same]),
    avg_n_missing    = mean(n_sdg_missing, na.rm = TRUE),
    med_n_missing    = median(n_sdg_missing, na.rm = TRUE),
    sd_n_missing     = sd(n_sdg_missing, na.rm = TRUE),
    # total with a valid year-to-year comparison
    n_pairs = dplyr::n_distinct(country_code[observed_pair]),
    
    # proportion of *pairs* that increased and decreased vs previous year
    prop_n_increase = if_else(
      n_pairs > 0, (n_increase / n_pairs) * 100, NA_real_),
    prop_n_decrease = if_else(
      n_pairs > 0, (n_decrease / n_pairs) * 100, NA_real_),
    prop_n_same = if_else(
      n_pairs > 0, (n_same / n_pairs) * 100, NA_real_),
    # placeholder for future metrics; easy to extend
    avg_prop_missing = mean(prop_sdg_missing, na.rm = TRUE) * 100,
    med_prop_missing = median(prop_sdg_missing, na.rm = TRUE) * 100,
    sd_prop_missing  = sd(prop_sdg_missing, na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  mutate(SDG_goal = "Overall") %>%   # tag as overall
  arrange(event_time)

# 5) Goal-specific marginal-change indicators ----
ts_goal_changes <- ts_data %>%
  dplyr::select(
    country_code,
    year,
    event_time,
    starts_with("n_miss_SDG"), 
    starts_with("prop_miss_SDG")
  ) %>%
  tidyr::pivot_longer(
    cols = c(starts_with("n_miss_SDG"), starts_with("prop_miss_SDG")),
    names_to    = c(".value", "SDG_goal"),
    names_pattern = "(n_miss|prop_miss)_SDG(\\d+)"
  ) %>%
  group_by(country_code, SDG_goal) %>%
  arrange(year, .by_group = TRUE) %>%
  mutate(
    prev_year = dplyr::lag(year),
    prev_n    = dplyr::lag(n_miss),
    
    has_valid_prev = !is.na(prev_n) &
      (year - prev_year == 1),
    
    increased = has_valid_prev & (n_miss > prev_n),
    decreased = has_valid_prev & (n_miss < prev_n),
    same      = has_valid_prev & (n_miss == prev_n),
    observed_pair = has_valid_prev
  ) %>%
  ungroup()

# 6) Aggregate to event-time window −8 to +8 (BY GOAL) ----
plot_df_goals <- ts_goal_changes %>%
  filter(event_time >= -8, event_time <= 8) %>%
  group_by(event_time, SDG_goal) %>%
  summarise(
    n_countries_obs = dplyr::n_distinct(country_code[!is.na(n_miss)]),
    n_increase      = dplyr::n_distinct(country_code[increased]),
    n_decrease      = dplyr::n_distinct(country_code[decreased]),
    n_same          = dplyr::n_distinct(country_code[same]),
    n_pairs         = dplyr::n_distinct(country_code[observed_pair]),
    avg_n_missing    = mean(n_miss, na.rm = TRUE),
    med_n_missing    = median(n_miss, na.rm = TRUE),
    sd_n_missing     = sd(n_miss, na.rm = TRUE),
    prop_n_increase   = if_else(n_pairs > 0, (n_increase / n_pairs) * 100, NA_real_),
    prop_n_decrease   = if_else(n_pairs > 0, (n_decrease / n_pairs) * 100, NA_real_),
    prop_n_same   = if_else(n_pairs > 0, (n_same / n_pairs) * 100, NA_real_),
    avg_prop_missing = mean(prop_miss, na.rm = TRUE) * 100,
    med_prop_missing = median(prop_miss, na.rm = TRUE) * 100,
    sd_prop_missing  = sd(prop_miss, na.rm = TRUE) * 100,
    .groups = "drop"
  ) %>%
  arrange(SDG_goal, event_time)

# 7) combining overall and goal-specific dataframes for plotting
plot_df_all <- bind_rows(plot_df_overall, plot_df_goals) %>% 
  dplyr::select(SDG_goal, event_time, n_countries_obs, n_pairs, n_increase,
    n_decrease, n_same, prop_n_increase, prop_n_decrease, prop_n_same, dplyr::everything())

# 8) saving 
write_csv(plot_df_all, "data/output/multi-series_df.csv")

# Plot 1:  --------------------------------------------------------------------

plt1_bar_overall <- plot_df_all %>%
  filter(SDG_goal == "Overall") %>%
  select(event_time, n_countries_obs, n_increase, n_decrease, n_same, 
         prop_n_increase, prop_n_decrease, prop_n_same) %>%
  pivot_longer(cols = c(n_increase, n_decrease, n_same),
               names_to = "change_type",
               values_to = "n_countries") %>%
  # proportions: pick the matching prop_* for each change_type
  mutate(
    prop_countries = case_when(
      change_type == "n_increase" ~ prop_n_increase,
      change_type == "n_decrease" ~ prop_n_decrease,
      change_type == "n_same"     ~ prop_n_same
    ),
    change_type = case_when(
      change_type == "n_increase" ~ "Increase",
      change_type == "n_decrease" ~ "Decrease",
      change_type == "n_same"     ~ "Unchanged"),
    
    # reordering factor levels for plotting (bottom → top)
    change_type = factor(
      change_type,
      levels = c("Decrease", "Unchanged", "Increase")  
    ),
    
    # pre/post averages of Increase share
    pre_avg_increase  = mean(prop_n_increase[event_time >= -5 & event_time <= -1], na.rm = TRUE),
    post_avg_increase = mean(prop_n_increase[event_time >= 0 & event_time <= 8],  na.rm = TRUE), 
    x_lab = paste0(event_time, "\n(n = ", n_countries_obs, ")"))

# for pre and post average lines:
plt1_avg_lines <- tibble::tibble(
  period = c("Pre-episode Avg", "Post-episode Avg"),
  y = c(unique(plt1_bar_overall$pre_avg_increase),
        unique(plt1_bar_overall$post_avg_increase)))

# Plotting 1.2
ggplot(plt1_bar_overall, aes(x = event_time, y = prop_countries, fill = change_type)) +
  geom_col(width = 0.6) +
  geom_vline(xintercept = -0.5, linetype = "solid", 
             linewidth = 0.6, color = "grey50") +
  # pre & post -treatment average
  geom_hline(
    data = plt1_avg_lines,
    aes(yintercept = y, linetype = period),
    color = "black", linewidth = 0.35
  ) +
  geom_text(
    data = plt1_avg_lines,
    inherit.aes = FALSE,
    aes(x = -5.75, y = y, label = sprintf("%.1f", y)),
    hjust = 1, vjust = -0.3, size = 3, fontface = c("italic", "bold.italic"), color = "grey30"
  ) +
  scale_linetype_manual(values = c("dashed", "dotted"),
                        labels = c(
                          expression(bar(x)[post]),
                          expression(bar(x)[pre]))) +
  scale_fill_manual(values = c(
    "Increase" = "#d95f02",
    "Decrease" = "#1b9e77",
    "Unchanged"     = "#7570b3")) +
  scale_x_continuous(
    limits = c(-6, 8),
    breaks = plt1_bar_overall$event_time,
    labels = plt1_bar_overall$x_lab
  ) +
  scale_y_continuous(limits = c(0, 100)) +
  labs(
    title     = "Trajectory of overall data missingness around autocratization",
    subtitle  = "All backsliding cases between 2015–2023",
    x = "\nEvent time (years relative to first autocratization episode)",
    y        = "Share of countries (%)",
    fill     = "Type of change",
    linetype = "Average share with increases",
    caption = "\nNote. Event-times with N ≥ 10; Horizontal lines indicating averages of the share of countries with increases in missingness, calculated for event-times −5 to −1 (pre) and 0 to 8 (post) periods.",
  ) + 
  theme_minimal() + 
  theme(
    plot.title = element_text(size = 15, face = "bold"),
    plot.subtitle = element_text(size = 13),
    axis.title.x = element_text(size = 10),
    axis.title.y = element_text(size = 10),
    axis.text.x = element_text(size = 6.5, lineheight = 0.9, angle = 30), 
    axis.text.y = element_text(size = 9, lineheight = 0.9),
    legend.title = element_text(size = 10), 
    legend.text  = element_text(size = 9),
    panel.background = element_rect(fill = "gray95", colour = NA),
    plot.background = element_rect(fill = "gray98", colour = NA), 
    plot.caption = element_text(hjust = 1, size = 6.5)
  )  


# Plotting 1.1
ggplot(plt1_bar_overall, aes(x = event_time, y = n_countries, fill = change_type)) +
  geom_col() +
  geom_vline(xintercept = 0, linetype = "dashed") +
  scale_fill_manual(values = c(
    "Increase" = "#d95f02",
    "Decrease" = "#1b9e77",
    "Unchanged"     = "#7570b3")) +
  labs() +
  theme_minimal()


# Plot 2: Overall mean and median proportion of missing indicators ------------
plt2_line_overall <- plot_df_all %>%
  filter(SDG_goal == "Overall", n_countries_obs >= 10) %>%
  mutate(
    # relative N: how big is N at this event_time compared to the max N
    rel_N = n_countries_obs / max(n_countries_obs, na.rm = TRUE),
    
    # N-aware mean: blend mean and median using relative N
    # when N is large → closer to mean; when N is smaller → closer to median
    weighted_avg_prop_missing = avg_prop_missing * rel_N +
      med_prop_missing * (1 - rel_N), 
    x_lab = paste0(event_time, "\n(n = ", n_countries_obs, ")"))

ggplot(plt2_line_overall, aes(x = event_time)) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
  # Unweighted mean
  geom_line(aes(y = avg_prop_missing, color = "Unweighted mean"),
            linewidth = 0.9) +
  geom_ribbon(aes(ymin = avg_prop_missing - sd_prop_missing,
                  ymax = avg_prop_missing + sd_prop_missing), 
              fill = "grey80", alpha = 0.3
              ) +
  # N-aware mean
  geom_line(aes(y = weighted_avg_prop_missing, color = "N-aware mean"),
            linewidth = 0.9, linetype = "dotdash") +
  # Median
  geom_line(aes(y = med_prop_missing, color = "Median"),
            linewidth = 0.9, linetype = "dotted") +
  scale_color_manual(values = c(
    "Unweighted mean" = "#1b9e77",
    "N-aware mean"    = "#7570b3",
    "Median"          = "#d95f02")) +
  scale_x_continuous(
    breaks = plt2_line_overall$event_time,
    labels = plt2_line_overall$x_lab
  ) +
  scale_y_continuous(
    limits = c(20, 80),
    breaks = seq(0, 100, by = 10)
  ) +
  labs(
    title = "Average SDG Missingness Around Democratic Backsliding",
    subtitle = "Unweighted mean, N-aware mean, and median proportion missing",
    x = "Event time (years relative to first autocratic episode)",
    y = "SDG indicators missing (%)",
    color = "Statistic",
    caption = "Event-times with N ≥ 10; N-aware mean blends mean and median using relative N"
  ) +
  theme_minimal() +
  theme(plot.caption = element_text(hjust = 1), 
        axis.text.x = element_text(size = 6.5, lineheight = 0.9, angle = 30))   # bottom-right caption


# Plot 3: plotting all missingness for all backsliding countries relative to event time 
plt3_traj_df <- ts_data %>%
  # keep only 2015–2023 first episodes
  filter(first_treat >= 2016, first_treat <= 2021) %>%
  # drop 2023 due to reporting lags
  filter(year <= 2022) %>%
  # event-time window
  filter(event_time >= -8, event_time <= 8) %>%
  mutate(
    # episode length in years (inclusive)
    ep_length_years = aut_ep_end_yr - aut_ep_start_yr + 1,
    # flag: is this row inside the autocratization episode?
    
    # where the episode ends in event time
    ep_end_event_time = aut_ep_end_yr - first_treat, 
    in_episode = if_else(event_time >= 0 & !is.na(ep_end_event_time) &
                           event_time <= ep_end_event_time, 1L, 0L), 
    
    # FIGURE OUT LATER 
    # # number of distinct episodes for this country
    # nepisodes = n_distinct(episode_number[!is.na(episode_number)]),
    # 
    # # text listing the lengths of all episodes for this country
    # episode_lengths = paste(
    #   sort(unique(ep_length_years[!is.na(episode_number) & !is.na(ep_length_years)])),
    #   collapse = ", ")
    )

plt3_traj_df <- plt3_traj_df %>%
  group_by(country_code) %>%
  arrange(event_time, .by_group = TRUE) %>%
  mutate(
    # start flag: first row per country
    is_start = row_number() == 1,
    # end flag: last row per country
    is_end   = row_number() == n()   # last observed year for that country
  ) %>%
  ungroup()

plot3 <- ggplot(plt3_traj_df, 
                aes(x = event_time, 
                    y = prop_missing_pct, 
                    group = country_code, 
                    text = paste0(
                      "Country: ", country_code,
                      #"<br>Episodes: ", nepisodes,
                      "<br>Episode length: ", ep_length_years, " years",
                      "<br>Event time: ", event_time,
                      "<br>Missingness: ", round(prop_missing_pct, 1), "%"))) +
  geom_line(
    data = subset(plt3_traj_df, in_episode == 1),  # <- uses the in_episode flag
    colour = "#D95F02",
    alpha  = 0.7) +
  geom_line(alpha = 0.35, colour = "grey40") +
  geom_vline(xintercept = 0, linetype = "dashed", linewidth = 0.6) +
  # starting points
  geom_point(
    data = subset(plt3_traj_df, is_start),
    aes(x = event_time, y = prop_missing_pct),
    colour = "black",
    size   = 0.8,
    alpha  = 0.5
  ) +
  # ending points
  geom_point(
    data = subset(plt3_traj_df, is_end),
    aes(x = event_time, y = prop_missing_pct),
    colour = "black",
    size   = 0.8,
    alpha  = 0.5
  ) +
  scale_x_continuous(breaks = -8:8, limits = c(-8, 8)) +
  scale_y_continuous(limits = c(20, 70), name = "Percent of SDG indicators missing") +
  labs(
    title    = "Trajectories of SDG data missingness around autocratization",
    subtitle = "Backsliding countries in the panel (2015–2023 first episodes)",
    x        = "Event time (years relative to first autocratization episode)"
  ) +
  theme_minimal()

ggplotly(plot3, tooltip = "text")


# Plot 4: Non-backsliding countries ----
ts_data_nobackslide <- panel %>%
  group_by(country_code) %>%
  filter(
    all(aut_ep          %in% c(0, NA)),
    all(aut_ep_id       %in% c(0, NA)),
    all(aut_cohort      %in% c(0, NA))
  ) %>%
  ungroup()

ts_data_nobackslide <- ts_data_nobackslide %>% 
  filter(year <= 2022) 

ggplot(ts_data_nobackslide,
  aes(x = year, y = prop_missing_pct, group = country_code)) +     # overall SDG missingness
  geom_line(alpha = 0.4, colour = "grey40") +
  geom_point(alpha = 0.4, size = 0.7, colour = "grey40") +
  scale_x_continuous(breaks = 2015:2023) +
  labs(
    title = "SDG data missingness, non‑backsliding countries",
    subtitle = "Countries with no autocratization episodes, 2015–2023",
    x = "Year") +
  theme_minimal()

# Summary statistics for non-backsliding countries
ts_nonbackslide_summary <- ts_data_nobackslide %>%
  group_by(year) %>%  
  # time axis for them
  summarise(
    mean_missing = mean(prop_missing_pct, na.rm = TRUE),
    median_missing = median(prop_missing_pct, na.rm = TRUE),
    sd_missing = sd(prop_missing_pct, na.rm = TRUE),
    n_countries = n_distinct(country_code),
    .groups = "drop"
  )

# Plot of mean and median missingness for non-backsliding countries
ggplot(ts_nonbackslide_summary, aes(x = year)) +
  geom_line(aes(y = mean_missing, color = "Mean"), linewidth = 0.8) +
  geom_line(aes(y = median_missing, color = "Median"), linewidth = 0.8, linetype = "dashed") +
  scale_color_manual(values = c("Mean" = "#1b9e77", "Median" = "#d95f02")) +
  scale_x_continuous(breaks = 2015:2022) +
  labs(
    title = "Mean and Median SDG Missingness, Non-Backsliding Countries",
    subtitle = "Countries with no autocratization episodes, 2015–2022",
    x = "Year",
    color = "Statistic"
  ) +
  theme_minimal()




# pulling backslider country codes
backslider_codes <- ts_data %>%
  distinct(country_code)

ts_all <- panel %>% # flagging backsliders in full data
  mutate(is_backslider = country_code %in% backslider_codes$country_code) %>% 
  left_join(ts_data %>% dplyr::select(country_code, year, event_time),
  by = c("country_code", "year")) %>% 
  filter(year <= 2022)

# function to set the SDG variable for plotting
set_sdg_var <- function(data, g = NULL) data %>%
  mutate(y_sdg = if (is.null(g)) prop_missing_pct
         else .data[[paste0("prop_miss_SDG", g)]] * 100)

ts_all <- set_sdg_var(ts_all, g = 17)

plot_all <- ggplot(
  ts_all,
  aes(
    x = year,
    y = y_sdg,
    group = country_code
  )
) +
  # 1) All countries' trajectories (baseline)
  geom_line(
    data   = subset(ts_all, !is_backslider),
    colour = "grey80", 
   alpha  = 0.35, 
   linewidth = 0.45
  ) +
  # 2) Backsliders' full trajectories (orange-yellow)
  geom_line(
    data   = subset(ts_all, is_backslider),
    colour = "#E69F00",
    alpha  = 0.4,
    linewidth = 0.9
  ) +
  # 3) Within-episode segments (red overlay)
  geom_line(
    data   = subset(ts_all, is_backslider & aut_ep == 1),
    colour = "#B22222",
    alpha  = 0.45,
    linewidth = 1.2
  ) +
  scale_x_continuous(
    breaks = 2015:2023
  ) +
  scale_y_continuous(
    limits = c(0, 100),
    name   = "Percent of SDG indicators missing"
  ) +
  labs(
    title    = "SDG data missingness, all countries",
    subtitle = "Backsliding countries in orange; red segments show autocratization episodes",
    x        = "Year"
  ) +
  theme_minimal()
plot_all
