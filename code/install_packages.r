
################################################################################
# PACKAGE INSTALLATION SCRIPT
# Run this FIRST before running the main analysis
################################################################################

# Install required packages if not already installed
packages <- c(
  "tidyverse",    # Data manipulation and visualization
  "plm",          # Panel data models
  "lmtest",       # Hypothesis testing
  "sandwich",     # Robust standard errors
  "did",          # Callaway-Sant'Anna method
  "fixest",       # Fast fixed effects
  "ggplot2",      # Plotting
  "gridExtra",    # Multiple plots
  "stargazer",    # Regression tables
  "broom",        # Tidy model outputs
  "scales",        # Plot scales
  "car"          # Companion to Applied Regression
)

# Function to install and load packages
install_if_missing <- function(pkg) {
  if (!require(pkg, character.only = TRUE)) {
    cat(sprintf("Installing %s...\n", pkg))
    install.packages(pkg, dependencies = TRUE, 
                    repos = "https://cloud.r-project.org/")
    library(pkg, character.only = TRUE)
  } else {
    cat(sprintf("✓ %s already installed\n", pkg))
  }
}

# Install all packages
cat("\n=== INSTALLING REQUIRED PACKAGES ===\n\n")
for (pkg in packages) {
  install_if_missing(pkg)
}

cat("\n=== ALL PACKAGES INSTALLED SUCCESSFULLY ===\n")
# Load all packages
library(tidyverse)
library(plm)
library(lmtest)
library(sandwich)
library(did)
library(fixest)
library(ggplot2)
library(gridExtra)
library(stargazer)
library(broom)
library(scales)
library(car)
cat("\n=== ALL RELEVANT PACKAGES LOADED SUCCESSFULLY ===\n")
cat("\nYou can now run: source('democracy_data_analysis.R')\n")
