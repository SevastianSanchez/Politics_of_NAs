if (!require("pacman")) install.packages("pacman")
library(pacman)
# load necessary packages
pacman::p_load(tidyverse, countrycode)

#calls sources
source("data/data_sources_dataloss_proj.R")

#function to extract data from specified years 
years_filter <- function(start_yr = 2005, end_yr = 2024, 
                          df1=vdem, #vdem data ONLY
                          df2=spi, #spi data ONLY
                          df3=sdg, #sdg data ONLY
                          df4=sdg_raw, #sdg composite data ONLY
                          df5=ert, #ert data ONLY
                          df6=gdppc_df, #gdppc_dta data ONLY
                          df7=info_cap, #info_cap data ONLY
                          df8=gni_class, #gni_class data ONLY
                          df9=electric, #electric data ONLY
                          df10=rural, #rural data ONLY
                          df11=r_and_d, #r_and_d data ONLY
                          df12=total_population #total_population data ONLY
                          #df10=odin, odin_yr=yr1 #odin data ONLY
                          ){ 
  
  #VDEM DATASET - DEMOCRACY INDICES
  name1 <- df1 %>%
    dplyr::select(country_name, country_text_id, year, v2x_regime, 
                  v2x_regime_amb, v2x_polyarchy, v2x_libdem, v2x_partipdem, 
                  v2x_delibdem, v2x_egaldem, v2xel_frefair, v2x_accountability, 
                  v2x_veracc, v2x_horacc, v2x_diagacc, v2xca_academ, 
                  v2x_freexp_altinf, e_wb_pop) %>%
    rename(#country_code = country_text_id, #renaming country code (new_name = old_name)
           regime_type_4 = v2x_regime, # MAIN RoW Regime Type Variable 
           regime_type_10 = v2x_regime_amb,
           elect_dem = v2x_polyarchy, # Electoral Democracy Index
           lib_dem = v2x_libdem, # Liberal Democracy Index
           part_dem = v2x_partipdem, # Participatory Democracy Index
           delib_dem = v2x_delibdem, # Deliberative Democracy Index
           egal_dem = v2x_egaldem, # Egalitarian Democracy Index
           freefair = v2xel_frefair,
           accountability = v2x_accountability,
           vt_account = v2x_veracc, 
           hz_account = v2x_horacc,
           diag_account = v2x_diagacc,
           academ_free = v2xca_academ, 
           freexp_altinfo = v2x_freexp_altinf,
           population = e_wb_pop) %>% 
    dplyr::mutate(log_pop = log(population)) %>% 
    dplyr::filter(year >= start_yr, year <= end_yr)
  
  #SPI DATASET - COMPOSITE SCORES
  name2 <- df2 %>% 
    dplyr::select(country, iso3c, date, SPI.INDEX, SPI.INDEX.PIL1, SPI.INDEX.PIL2, 
                  SPI.INDEX.PIL3, SPI.INDEX.PIL4, SPI.INDEX.PIL5, income, region, weights) %>% 
    rename(year = date,
           spi_comp = SPI.INDEX,
           p1_use = SPI.INDEX.PIL1, 
           p2_services = SPI.INDEX.PIL2,
           p3_products = SPI.INDEX.PIL3,
           p4_sources = SPI.INDEX.PIL4,
           p5_infra = SPI.INDEX.PIL5,
           region_spi = region) %>% 
    dplyr::filter(year >= start_yr, year <= end_yr)
  
  #SDG DATASET - COMPOSITE SCORES
  name3 <- df3 %>% 
    dplyr::select(Country, id, year, sdgi_s, goal1, goal2, 
                  goal3, goal4, goal5, goal6, goal7, goal8, goal9, goal10, 
                  goal11, goal12, goal13, goal14, goal15, goal16, goal17) %>% 
    rename(country_name = Country, 
           country_code = id,
           sdg_overall = sdgi_s) %>%
    dplyr::filter(year >= start_yr, year <= end_yr)

  #SDG RAW DATASET - MISSINGNESS DATA [DEPENDENT VARIABLE]
  name4 <- df4 %>% 
    dplyr::select(Country, id, year, everything()) %>%
    dplyr::select(-indexreg) %>%
    rename(country_name = Country, 
           country_code = id) %>%
    dplyr::filter(year >= start_yr, year <= end_yr)
  
  # ERT DATASET - REGIME CHANGE VARIABLES
  name5 <- df5 %>%
    dplyr::select(country_name, country_text_id, country_id, year, reg_type, 
                  v2x_polyarchy, row_regch_event, reg_trans, dem_ep, 
                  dem_pre_ep_year, dem_ep_start_year, dem_ep_end_year, aut_ep, 
                  aut_pre_ep_year, aut_ep_start_year, aut_ep_end_year) %>%
    dplyr::filter(year >= start_yr, year <= end_yr) %>% 
    rename(regime_type_2 = reg_type,
           elect_dem_ert = v2x_polyarchy, 
           regch_event = row_regch_event,
           regch_genuine = reg_trans,
           dem_ep_pre_yr = dem_pre_ep_year,
           dem_ep_start_yr = dem_ep_start_year,
           dem_ep_end_yr = dem_ep_end_year,
           aut_ep_pre_yr = aut_pre_ep_year,
           aut_ep_start_yr = aut_ep_start_year,
           aut_ep_end_yr = aut_ep_end_year)
  
  # GDP PER CAPITA
  name6 <- df6 %>% 
    dplyr::select(country_name, country_code, year, gdp_pc) %>% 
    dplyr::mutate(log_gdppc = log(gdp_pc)) %>% 
    dplyr::filter(year >= start_yr, year <= end_yr)
   
  # INFO CAPACITY
  name7 <- df7 %>% 
    dplyr::select(country_id, ccodecow, year, infcap_irt, infcap_pca, everything()) %>% 
    dplyr::mutate(
      ccodecow = as.numeric(ccodecow),
      ccodecow = case_when(
        ccodecow == 817 ~ 816,  # Remap South Vietnam code to unified Vietnam
        ccodecow == 345 ~ NA_real_,  # Excluding Yugoslavia 
        TRUE ~ ccodecow
      )
    ) %>%
    # Convert COW code to ISO3 using countrycode
    dplyr::mutate(
      iso3c = countrycode::countrycode(ccodecow, origin = "cown", destination = "iso3c",
                                       custom_match = c("817" = "VNM"))
    ) %>%
    #dplyr::select(-ccodecow, -country_id) %>%  # Remove conflicting columns
    dplyr::filter(year >= start_yr, year <= end_yr)
  
 # WB INCOME CLASSIFICATIONS 
  name8 <- df8 %>% 
    dplyr::mutate(income_level = na_if(income_level, "..")) %>% 
    dplyr::mutate(income_level_lab = factor(income_level, 
      levels = c("H", "UM", "LM", "L"),  # H (higher income) as the reference category # Desired order
      labels = c("High Income Countries", 
                 "Upper-Middle Income Countries", 
                 "Lower-Middle Income Countries", 
                 "Low Income Countries") # Full descriptive labels
    )) %>% 
    dplyr::rename(iso3c = country_code) %>%
    dplyr::mutate(iso3c = as.character(iso3c)) %>% 
    dplyr::filter(year >= start_yr, year <= end_yr)
  
  # ELECTRICITY ACCESS
  name9 <- df9 %>%
    dplyr::select(country, iso3c, year, EG.ELC.ACCS.ZS) %>%
    rename(electric_access = EG.ELC.ACCS.ZS) %>% 
    dplyr::filter(year >= start_yr, year <= end_yr)
  
  # RURAL POPULATION %
  name10 <- df10 %>%
    dplyr::select(country, iso3c, year, SP.RUR.TOTL.ZS) %>%
    rename(rural_pop_pct = SP.RUR.TOTL.ZS) %>%
    dplyr::filter(year >= start_yr, year <= end_yr)
  
  # R&D EXPENDITURE %
  name11 <- df11 %>%
    dplyr::select(country, iso3c, year, GB.XPD.RSDV.GD.ZS) %>%
    rename(rd_expenditure_pct = GB.XPD.RSDV.GD.ZS) %>%
    dplyr::filter(year >= start_yr, year <= end_yr)
  
  # TOTAL POPULATION
  name12 <- df12 %>% 
    dplyr::select(country, iso3c, year, SP.POP.TOTL) %>%
    rename(total_pop = SP.POP.TOTL) %>%
    dplyr::filter(year >= start_yr, year <= end_yr)
  
  return(list(vdem = name1, 
              spi = name2, 
              sdg = name3, 
              sdg_raw = name4,
              ert = name5, 
              gdppc_df = name6, 
              info_cap = name7, 
              gni_class = name8, 
              electric = name9,
              rural = name10,
              r_and_d = name11,
              total_population = name12))
  
} 

#testing_years_filter <- years_filter(start_yr = 2014, end_yr = 2015) # Example usage to test the function
