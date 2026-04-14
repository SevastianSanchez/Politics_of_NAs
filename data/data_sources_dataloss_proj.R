if (!requireNamespace("tidyverse", quietly = TRUE)) library(tidyverse)
library(readxl)
library(devtools)
library(vdemdata) # call vdem package 
library(ERT) # call ERT package
library(WDI) # call WDI package for GINI coefficient

# Set working directory 
setwd("~/Desktop/SIPA/Fall 25' - SIPA/Policy Data Analysis Using R/DataLoss_Proj")

# Calls all other packages 
source("packages.R")
##### SOURCES #####

# V-dem package from github [API]
vdem <- vdemdata::vdem %>% 
  filter(year >= 2000)

# ERT package
ert <- read.csv("data/input_data/ert.csv") %>% 
  filter(year >= 2000)

# SPI csv from github [API]
url <- "https://raw.githubusercontent.com/worldbank/SPI/refs/heads/master/03_output_data/SPI_index.csv"
spi <- read_csv(url) 

# SDG Excel from directory (Raw indicators)
sdg_raw <- read_excel("data/input_data/SDR2025-data.xlsx", sheet = "All Raw Data") %>% 
  filter(year >= 2000)

# SDG Excel from directory (composite scores)
sdg <- read_excel("data/input_data/SDR2025-data.xlsx", sheet = "Backdated SDG Index") %>% 
  filter(year >= 2000)

#GDP per capita
gdppc_df <- read_csv("data/input_data/gdppc_df_long.csv") %>% 
  filter(year >= 2000)

#Information Capacity 
info_cap <- read_csv("data/input_data/information_capacity.csv") %>% 
  filter(year >= 2000)

# WB GNI Classifications 
gni_class <- read_csv("data/input_data/world_bank_income_classifications.csv") %>% 
  filter(year >= 2000)

# WDI Access to electricity
electric <- WDI(country = "all", indicator = "EG.ELC.ACCS.ZS", start = 2000, end = NULL)
#electric <- WDI(country = "all", indicator = "1.1_ACCESS.ELECTRICITY.TOT", start = 2000, end = NULL)

# WDI % rural population
rural <- WDI(country = "all", indicator = "SP.RUR.TOTL.ZS", start = 2000, end = NULL)

# WDI Research and development expenditure (% of GDP)
r_and_d <- WDI(country = "all", indicator = "GB.XPD.RSDV.GD.ZS", start = 2000, end = NULL)

# WDI Total population (country-level)
total_population <- WDI(country = "all", indicator = "SP.POP.TOTL", start = 2000, end = NULL)

