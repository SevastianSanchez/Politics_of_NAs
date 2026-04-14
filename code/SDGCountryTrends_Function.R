# Function that creates the SDG Country Trends plot for a given country and SDG. 
# The function takes in the country name, SDG numbers, the data frame containing 
# the SDG indicators, and the dataframe lists each SDG and a corresponding color. 
# It returns a ggplot object that can be displayed or saved as an images.

create_sdg_trends_plot <- function(country_name, sdg_numbers, data, sdg_colors) {
  # Filter data for the specified country and SDGs
  plot_data <- data %>%
    filter(country_name == !!country_name) %>%
    select(year, all_of(sdg_numbers)) %>%
    pivot_longer(cols = -year, names_to = "sdg", values_to = "value") %>%
    left_join(sdg_colors, by = c("sdg" = "sdg_number")) %>%
    mutate(sdg_label = paste("SDG", sdg))
  # Check if data exists for the specified country and SDGs
  if (nrow(plot_data) == 0) {
    stop("No data available for the specified country and SDGs.")
  }
  # Create the plot
  ggplot(plot_data, aes(x = year, y = value, color = sdg_label)) +
    geom_line(size = 1) +
    scale_color_manual(values = setNames(sdg_colors$color, paste("SDG", sdg_colors$sdg_number))) +
    labs(title = paste("Trends in SDG Indicators for", country_name),
         x = "Year",
         y = "Indicator Value",
         color = "SDG") +
    theme_minimal() +
    theme(legend.position = "bottom")
}
