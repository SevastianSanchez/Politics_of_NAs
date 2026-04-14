# Libraries
library(tidyverse)
library(readxl)
library(devtools)
library(WDI) # Call WDI package for GINI coefficient

# WDI Indicators 
electr_access <- WDI(country = "all", indicator = "1.1_ACCESS.ELECTRICITY.TOT", start = 2015, end = 2025)
secondary_edu <- WDI(country = "all", indicator = "CC.SE.CAT3.ZS", start = 2015, end = 2025)
post_secondary_edu <- WDI(country = "all", indicator = "CC.SE.CAT4.ZS", start = 2015, end = 2025)
rd_expenditure <- WDI(country = "all", indicator = "GB.XPD.RSDV.GD.ZS", start = 2015, end = 2025)

### OTHER INTERESTING/RELATED WDI VARIABLES ###
# Access to electricity
#WDIsearch(string='1.1_ACCESS.ELECTRICITY.TOT', field='indicator')

# % rural population
#WDIsearch(string='SP.RUR.TOTL.ZS', field='indicator')

# % urban population
#WDIsearch(string='SP.URB.TOTL.IN.ZS', field='indicator')

# % total population 
#WDIsearch(string='SP.POP.TOTL', field='indicator')

# % population with secondary education
#WDIsearch(string='CC.SE.CAT3.ZS', field='indicator')

# % population with post-secondary education
#WDIsearch(string='CC.SE.CAT4.ZS', field='indicator')

# Research and development expenditure (% of GDP)
#WDIsearch(string='GB.XPD.RSDV.GD.ZS', field='indicator')

# GNI total (in USD)
#WDIsearch(string='C1.7', field='indicator')

# GNI per capita 
#WDIsearch(string='C1.8', field='indicator')

# GINI Coefficient
#WDIsearch(string='3.0.Gini', field='indicator')
# GINI Coefficient - Index?
#WDIsearch(string='SI.POV.GINI', field='indicator')

### Example code to pull any of the above indicators
# x <- WDI(country = "all", indicator = "var", start = 2000, end = NULL)