#Set Directory
#setwd("~/Documents/GitHub/QMSS_Thesis_Sanchez/data/misc")

#vdem = country_text_id, country_name, [COWcode]
#spi = iso3c
#sdg = country_code, country_name
#ert = country_text_id, country_name, country_id,
#gdppc = country_code
#infocap = country_id
#income class = country_code
#gini = Code

### THIS A RECREATED VERSION OF df_years2.0 AS OF 10/27/2025, 
### SPECIFICALLY FOR PURPOSES OF POLICY R PROJECT

if (!require("pacman")) install.packages("pacman")
library(pacman)
# load necessary packages
pacman::p_load(dplyr, countrycode)

# More descriptive display names mapping (optional)
## default to df list name if not provided (e.g. "ert")
DATASET_DISPLAY_NAMES <- c(
  "vdem" = "Varieties of Democracy (V-Dem)",
  "spi" = "Statistical Performance Indicators (SPI)",
  "sdg" = "Sustainable Development Goals (SDG)",
  "sdg_raw" = "Sustainable Development Goals (Raw Indicators)",
  "ert" = "Episodes of Regime Transition (ERT-VDem)",
  "gdppc_df" = "GDP per capita",
  "info_cap" = "Information Capacity",
  "gni_class" = "GNI Classification",
  "electric" = "Access to Electricity",
  "rural" = "Rural Population %",
  "r_and_d" = "Research and Development Expenditure"
)

country_colnames <- c(
  "country", "Country", "country_code", "COWcode", "cowcode", "iso3", "iso3c", 
  "country_name", "country_id", "countryname", "Entity", "Code", "country_text_id", 
  "countryid"
)

# Define non-countries to exclude (regions, groups, etc.)
non_countries <- c(
  "_AFRICA", "_BRICS", "_BRICSPLUS", "_E_EURO_ASIA", "_E_S_ASIA", "_HIC", "_LAC", 
  "_LIC", "_LMIC", "_MENA", "_OCEANIA", "_OECD", "_SIDS", "_UMIC", "_WORLD",
  "EAP", "ECA", "IBD", "IBT", "IDA", "LAC", "MNA", "SAS", "SSA", 
  "AFE", "AFW", "ARB", "CEB", "CSS", "EAR", "EAS", "ECS", "EMU", "EUU", "FCS", 
  "HIC", "HPC", "IDB", "IDX", "INX", "LCN", "LDC", "LIC", "LMC", "LMY", "LTE", 
  "MEA", "MIC", "NAC", "OED", "OSS", "PRE", "PSS", "PST", "TSA", "TSS", "UMC", 
  "WLD", "TEA", "TEC", "TLA", "TMN", "SST", "SSF", "OWID_WRL",
  "ANT", "CSK", "SUN", "YUG", "YUGF"
)

# Define forward mapping (country names/aliases to ISO3 codes)
custom_match_forward <- c(
  "Kosovo" = "XKX",
  "Somaliland" = "SOL",
  "Zanzibar" = "ZNZ",
  "Channel Islands" = "CHI",
  "Saint Martin (French part)" = "MAF",
  "Curaçao" = "CUW",
  "West Bank and Gaza" = "PSE",
  "Congo (Kinshasa)" = "COD",
  "Myanmar (Burma)" = "MMR",
  "Iran, Islamic Rep." = "IRN",
  "Kyrgyz Republic" = "KGZ",
  "Bahamas" = "BHS",
  "Belize" = "BLZ",
  "Brunei" = "BRN",
  "South Sudan" = "SSD"
)

# Define reverse mapping (ISO3 codes to country names)
custom_match_reverse <- c(
  "XKX" = "Kosovo",
  "SOL" = "Somaliland",
  "ZNZ" = "Zanzibar",
  "CHI" = "Channel Islands",
  "MAF" = "Saint Martin (French part)",
  "CUW" = "Curaçao",
  "PSE" = "West Bank and Gaza",
  "COD" = "Congo (Kinshasa)",
  "MMR" = "Myanmar (Burma)",
  "IRN" = "Iran, Islamic Rep.",
  "KGZ" = "Kyrgyz Republic", 
  "BHS" = "Bahamas",
  "BLZ" = "Belize",
  "BRN" = "Brunei",
  "SSD" = "South Sudan"
)

# Create a country code-to-name reference dataset
create_country_reference <- function() {
  # Get all ISO3 codes that countrycode knows about
  all_iso3 <- countrycode::codelist$iso3c
  all_iso3 <- all_iso3[!is.na(all_iso3)]
  
  # Map them to country names
  country_names <- suppressWarnings(countrycode::countrycode(
    all_iso3, 
    origin = "iso3c",
    destination = "country.name"
  ))
  
  # Add custom matches
  for (code in names(custom_match_reverse)) {
    idx <- which(all_iso3 == code)
    if (length(idx) > 0) {
      country_names[idx] <- custom_match_reverse[code]
    } else {
      all_iso3 <- c(all_iso3, code)
      country_names <- c(country_names, custom_match_reverse[code])
    }
  }
  
  # Create reference dataframe
  ref_df <- data.frame(
    country_code = all_iso3,
    country_name = country_names,
    stringsAsFactors = FALSE
  )
  
  return(ref_df)
}

# Helper function to check if a name is in our custom mappings
is_custom_name <- function(name) {
  return(!is.na(name) && name %in% names(custom_match_forward))
}

# Global country reference 
COUNTRY_REFERENCE <- create_country_reference()

# Function to standardize country codes and track matches/non-matches
standardize_country_codes <- function(df, dataset_id = 1, dataset_name = NULL) {
  # Initialize log containers for this dataset
  matched_countries <- data.frame(
    dataset_id = integer(),
    dataset_name = character(),
    original_code = character(),
    original_name = character(),
    standardized_code = character(),
    standardized_name = character(),
    stringsAsFactors = FALSE
  )
  
  unmatched_countries <- data.frame(
    dataset_id = integer(),
    dataset_name = character(),
    original_code = character(),
    original_name = character(),
    reason = character(),
    stringsAsFactors = FALSE
  )
  
  # Use dataset name if provided, otherwise use index
  ds_label <- if (!is.null(dataset_name)) {
    paste0("Dataset ", dataset_id, " (", dataset_name, ")")
  } else {
    paste0("Dataset ", dataset_id)
  }
  ds_name <- if (!is.null(dataset_name)) dataset_name else paste("Dataset", dataset_id)
  
  # Identify country columns
  country_cols <- names(df)[tolower(names(df)) %in% tolower(country_colnames)]
  
  # Add debugging info
  message(paste(ds_label, "- Found country columns:", paste(country_cols, collapse=", ")))
  
  # Track if we've successfully standardized
  success <- FALSE
  
  # Identify name and code columns for logging
  name_col <- NULL
  code_col <- NULL
  
  # Save original country name if available
  country_name_col <- country_cols[tolower(country_cols) %in% 
                                  c("country", "country_name", "countryname", "entity")]
  if(length(country_name_col) > 0) {
    df$original_country_name <- df[[country_name_col[1]]]
    name_col <- country_name_col[1]
  }
  
  # Filter out non-countries if there's a country name column
  if(length(country_name_col) > 0) {
    non_country_rows <- df[[country_name_col[1]]] %in% non_countries
    if(any(non_country_rows, na.rm = TRUE)) {
      message(paste(ds_label, "- Removing", sum(non_country_rows, na.rm = TRUE), 
                   "non-country entries (regions, groups, etc.)"))
      
      # Log non-countries in unmatched log
      for(i in which(non_country_rows)) {
        if(!is.na(df[[country_name_col[1]]][i])) {
          unmatched_countries <- rbind(unmatched_countries, data.frame(
            dataset_id = dataset_id,
            dataset_name = ds_name,
            original_code = NA_character_,
            original_name = df[[country_name_col[1]]][i],
            reason = "Non-country entity (region/group)",
            stringsAsFactors = FALSE
          ))
        }
      }
    }
  }
  
  # First try ISO3C codes if they exist
  iso3_cols <- country_cols[tolower(country_cols) %in% 
                           c("iso3", "iso3c", "country_code", "code")]
  
  if(length(iso3_cols) > 0) {
    for(col in iso3_cols) {
      tryCatch({
        # Pre-process the codes to handle custom codes directly
        # This is a key fix for Kosovo and similar cases
        custom_codes <- df[[col]]
        
        # Track which rows have custom codes for later
        has_custom_code <- sapply(custom_codes, is_custom_code)
        
        # Try standardization with countrycode
        codes <- suppressWarnings(countrycode(
          df[[col]],
          origin = "iso3c",
          destination = "iso3c",
          custom_match = custom_match_forward
        ))
        
        # Fix: Directly use custom codes where applicable
        for(i in which(has_custom_code)) {
          if(is.na(codes[i])) {
            codes[i] <- df[[col]][i]  # Use the original custom code
            message(paste(ds_label, "- Directly preserved custom code:", df[[col]][i]))
          }
        }
        
        # Log unmatched country codes - with FIXED logic for custom codes
        for(i in seq_along(df[[col]])) {
          original_code <- df[[col]][i]
          
          # Skip NA or non-country codes
          if(is.na(original_code) || original_code %in% non_countries) {
            next
          }
          
          # Only log as unmatched if:
          # 1. The code couldn't be standardized (codes[i] is NA)
          # 2. AND it's not one of our custom codes
          if(is.na(codes[i]) && !is_custom_code(original_code)) {
            unmatched_countries <- rbind(unmatched_countries, data.frame(
              dataset_id = dataset_id,
              dataset_name = ds_name,
              original_code = original_code,
              original_name = if(!is.null(name_col) && !is.na(df[[name_col]][i])) df[[name_col]][i] else NA_character_,
              reason = "Invalid country code",
              stringsAsFactors = FALSE
            ))
          }
        }
        
        # Check if conversion was mostly successful (>70%)
        success_rate <- sum(!is.na(codes)) / length(codes)
        message(paste(ds_label, "- ISO3 column", col, "match rate:", 
                     round(success_rate * 100, 1), "%"))
        
        if(success_rate > 0.7) {
          df$iso3_standardized <- codes
          message(paste(ds_label, "- Successfully standardized using ISO3 column:", col))
          code_col <- col
          success <- TRUE
          break
        }
      }, error = function(e) {
        message(paste(ds_label, "- Error converting column", col, ":", e$message))
      })
    }
  }
  
  # If ISO3 conversion failed, try country names
  if(!success && length(country_name_col) > 0) {
    for(col in country_name_col) {
      tryCatch({
        # Pre-process names to directly handle custom names
        # Track which rows have custom names for later
        has_custom_name <- sapply(df[[col]], is_custom_name)
        
        # Try standardization
        codes <- suppressWarnings(countrycode(
          df[[col]],
          origin = "country.name",
          destination = "iso3c",
          custom_match = custom_match_forward
        ))
        
        # Fix: Directly use custom mappings for known names
        for(i in which(has_custom_name)) {
          if(is.na(codes[i]) && !is.na(df[[col]][i])) {
            # Get the code from custom mapping
            custom_code <- custom_match_forward[df[[col]][i]]
            if(!is.na(custom_code)) {
              codes[i] <- custom_code
              message(paste(ds_label, "- Directly mapped custom name:", df[[col]][i], "to", custom_code))
            }
          }
        }
        
        # Log unmatched country names - with fixed logic for custom names
        for(i in seq_along(df[[col]])) {
          if(!is.na(df[[col]][i]) && is.na(codes[i]) && 
             !(df[[col]][i] %in% non_countries) && 
             !is_custom_name(df[[col]][i])) {
            unmatched_countries <- rbind(unmatched_countries, data.frame(
              dataset_id = dataset_id,
              dataset_name = ds_name,
              original_code = if(!is.null(code_col) && !is.na(df[[code_col]][i])) df[[code_col]][i] else NA_character_,
              original_name = df[[col]][i],
              reason = "Could not map country name to standard code",
              stringsAsFactors = FALSE
            ))
          }
        }
        
        # Check if conversion was mostly successful (>50% of valid entries)
        valid_entries <- !df[[col]] %in% non_countries
        valid_count <- sum(valid_entries, na.rm = TRUE)
        success_rate <- if(valid_count > 0) {
          sum(!is.na(codes)[valid_entries]) / valid_count
        } else {
          0
        }
        
        message(paste(ds_label, "- Country name column", col, "match rate:", 
                     round(success_rate * 100, 1), "%"))
        
        if(success_rate > 0.5) {
          df$iso3_standardized <- codes
          message(paste(ds_label, "- Successfully standardized using country name column:", col))
          name_col <- col
          success <- TRUE
          break
        }
      }, error = function(e) {
        message(paste(ds_label, "- Error converting column", col, ":", e$message))
      })
    }
  }
  
  # Try any remaining columns as a last resort
  if(!success && length(country_cols) > 0) {
    remaining_cols <- setdiff(country_cols, c(iso3_cols, country_name_col))
    for(col in remaining_cols) {
      tryCatch({
        # Try to guess the origin
        origin_type <- if(tolower(col) == "cowcode" || grepl("cow", tolower(col))) {
          "cown"
        } else if(grepl("id", tolower(col))) {
          "country.name"
        } else {
          "country.name"
        }
        
        # Try standardization
        codes <- suppressWarnings(countrycode(
          df[[col]],
          origin = origin_type,
          destination = "iso3c",
          custom_match = custom_match_forward
        ))
        
        # Handle custom codes/names directly if needed
        for(i in seq_along(df[[col]])) {
          if(is.na(codes[i]) && !is.na(df[[col]][i])) {
            # If it's a country name in our custom mappings
            if(origin_type != "cown" && is_custom_name(df[[col]][i])) {
              codes[i] <- custom_match_forward[df[[col]][i]]
              message(paste(ds_label, "- Directly mapped custom name from column", col, ":", 
                           df[[col]][i], "to", codes[i]))
            }
            # If it's a country code in our custom mappings
            else if(origin_type == "cown" && is_custom_code(df[[col]][i])) {
              codes[i] <- df[[col]][i]  # Just use the code directly
              message(paste(ds_label, "- Directly preserved custom code from column", col, ":", codes[i]))
            }
          }
        }
        
        # Log unmatched entries with better logic
        for(i in seq_along(df[[col]])) {
          if(!is.na(df[[col]][i]) && is.na(codes[i]) && 
             !(df[[col]][i] %in% non_countries)) {
            
            # Check if this is a custom code/name before marking as unmatched
            is_custom <- FALSE
            if(origin_type != "cown") {
              is_custom <- is_custom_name(df[[col]][i])
            } else {
              is_custom <- is_custom_code(df[[col]][i])
            }
            
            if(!is_custom) {
              unmatched_countries <- rbind(unmatched_countries, data.frame(
                dataset_id = dataset_id,
                dataset_name = ds_name,
                original_code = if(origin_type == "cown") df[[col]][i] else NA_character_,
                original_name = if(origin_type != "cown") df[[col]][i] else NA_character_,
                reason = paste0("Failed to match using column ", col, " as ", origin_type),
                stringsAsFactors = FALSE
              ))
            }
          }
        }
        
        # Check success rate
        success_rate <- sum(!is.na(codes)) / length(codes)
        message(paste(ds_label, "- Column", col, "match rate:", 
                     round(success_rate * 100, 1), "%"))
        
        if(success_rate > 0.5) {
          df$iso3_standardized <- codes
          message(paste(ds_label, "- Successfully standardized using column:", 
                       col, "as type:", origin_type))
          if(origin_type == "cown") {
            code_col <- col
          } else {
            name_col <- col
          }
          success <- TRUE
          break
        }
      }, error = function(e) {
        message(paste(ds_label, "- Error converting column", col, ":", e$message))
      })
    }
  }
  
  # Make sure iso3_standardized exists
  if(!"iso3_standardized" %in% names(df)) {
    df$iso3_standardized <- NA_character_
    message(paste(ds_label, "- Adding placeholder iso3_standardized column"))
  }
  
  # Generate country names from ISO3 codes - use our reference dataframe for this
  if("iso3_standardized" %in% names(df)) {
    # Use a safer join approach that doesn't rely on column renaming
    country_names_df <- COUNTRY_REFERENCE %>%
      select(
        iso3_standardized = country_code,
        country_name_standardized = country_name
      )
    
    # Join with the explicit column mappings
    df <- df %>%
      left_join(country_names_df, by = "iso3_standardized")
    
    message(paste(ds_label, "- Added country names based on ISO3 codes"))
  } else {
    # Create empty country name column if no ISO codes
    df$country_name_standardized <- NA_character_
    message(paste(ds_label, "- No ISO3 codes found, adding empty country name column"))
  }
  
  # Use original country name if standardized is NA but original exists
  if("original_country_name" %in% names(df)) {
    df$country_name_standardized <- ifelse(
      is.na(df$country_name_standardized) & !is.na(df$original_country_name),
      df$original_country_name,
      df$country_name_standardized
    )
  }
  
  if(!success) {
    warning(paste(ds_label, "- Could not standardize country codes"))
  }
  
  # Log successfully matched countries
  if("iso3_standardized" %in% names(df)) {
    # Get unique country codes
    unique_codes <- unique(na.omit(df$iso3_standardized))
    
    for(code in unique_codes) {
      # Get first row with this code
      idx <- which(df$iso3_standardized == code)[1]
      
      # Get original code and name
      orig_code <- if(!is.null(code_col) && !is.na(df[[code_col]][idx])) {
        df[[code_col]][idx]
      } else {
        code  # Use standardized if original not available
      }
      
      orig_name <- if(!is.null(name_col) && !is.na(df[[name_col]][idx])) {
        df[[name_col]][idx]
      } else if("country_name_standardized" %in% names(df) && !is.na(df$country_name_standardized[idx])) {
        df$country_name_standardized[idx]  # Use standardized if original not available
      } else {
        NA_character_
      }
      
      matched_countries <- rbind(matched_countries, data.frame(
        dataset_id = dataset_id,
        dataset_name = ds_name,
        original_code = orig_code,
        original_name = orig_name,
        standardized_code = code,
        standardized_name = df$country_name_standardized[idx],
        stringsAsFactors = FALSE
      ))
    }
  }
  
  # Return dataframe with logs as attributes
  attr(df, "matched_countries") <- matched_countries
  attr(df, "unmatched_countries") <- unmatched_countries
  
  return(df)
}

process_datasets <- function(df_lists, dataset_names = NULL) {
  # Initialize the consolidated logs
  all_matched <- data.frame(
    dataset_id = integer(),
    dataset_name = character(),
    original_code = character(),
    original_name = character(),
    standardized_code = character(),
    standardized_name = character(),
    stringsAsFactors = FALSE
  )
  
  all_unmatched <- data.frame(
    dataset_id = integer(),
    dataset_name = character(),
    original_code = character(),
    original_name = character(),
    reason = character(),
    stringsAsFactors = FALSE
  )
  
  # Process each dataset
  processed_data <- list()
  
  # Store original column names for later use
  original_colnames <- list()
  
  for(i in seq_along(df_lists)) {
    df <- df_lists[[i]]
    
    # Get dataset name if available
    dataset_name <- if (!is.null(dataset_names) && i <= length(dataset_names)) {
      dataset_names[i]
    } else {
      NULL
    }
    
    # Save original column names for this dataset
    original_colnames[[i]] <- names(df)
    
    # Standardize year column naming
    year_col <- names(df)[tolower(names(df)) %in% c("year")]
    if (length(year_col) == 0) {
      year_col <- names(df)[grepl("year", tolower(names(df)))]
    }
    if (length(year_col) > 0 && year_col[1] != "year") {
      names(df)[names(df) == year_col[1]] <- "year"
    }
    if ("year" %in% names(df)) {
      df <- df %>%
        mutate(year = suppressWarnings(as.integer(year))) %>%
        filter(!is.na(year))
    }
    
    # Apply improved country code standardization
    df <- standardize_country_codes(df, i, dataset_name)
    
    # Extract logs from this dataset
    this_matched <- attr(df, "matched_countries")
    this_unmatched <- attr(df, "unmatched_countries")
    
    # Add to consolidated logs
    if(nrow(this_matched) > 0) {
      all_matched <- rbind(all_matched, this_matched)
    }
    if(nrow(this_unmatched) > 0) {
      all_unmatched <- rbind(all_unmatched, this_unmatched)
    }
    
    # Always ensure key columns exist
    if(!"iso3_standardized" %in% names(df)) df$iso3_standardized <- NA_character_
    if(!"country_name_standardized" %in% names(df)) df$country_name_standardized <- NA_character_
    if(!"year" %in% names(df)) df$year <- NA_integer_
    
    # Add dataset suffix to non-key columns
    # These columns should remain as is for joining
    key_cols <- c("iso3_standardized", "year", "country_name_standardized", "original_country_name")
    key_cols <- key_cols[key_cols %in% names(df)]
    
    # Add dataset suffix to all other columns
    data_cols <- setdiff(names(df), key_cols)
    if(length(data_cols) > 0) {
      new_names <- paste0(data_cols, "_ds", i)
      names(df)[match(data_cols, names(df))] <- new_names
    }
    
    # Deduplicate by iso3 and year (keep the first occurrence)
    df <- df %>%
      group_by(iso3_standardized, year) %>%
      slice(1) %>%
      ungroup()
    
    processed_data[[i]] <- df
  }
  
  # Only proceed if we have processed datasets
  if(length(processed_data) == 0) {
    stop("No datasets could be processed. Check country code columns.")
  }
  
  # Create a unified dataset with all countries and years from all datasets
  # FIX: Be more careful about collecting all countries
  all_countries <- character(0)
  
  # Collect all standardized country codes from all datasets
  for(df in processed_data) {
    if("iso3_standardized" %in% names(df)) {
      country_codes <- unique(df$iso3_standardized)
      country_codes <- country_codes[!is.na(country_codes)]
      all_countries <- union(all_countries, country_codes)
    }
  }
  
  # Make sure we didn't miss any countries from the matched log
  matched_countries <- unique(all_matched$standardized_code)
  matched_countries <- matched_countries[!is.na(matched_countries)]
  all_countries <- union(all_countries, matched_countries)
  
  # Get all years
  all_years <- unique(unlist(lapply(processed_data, function(df) df$year)))
  all_years <- all_years[!is.na(all_years)]
  
  message(paste("Found", length(all_countries), "unique countries across all datasets"))
  
  # Create a reference grid of all country-year combinations
  reference_grid <- expand.grid(
    iso3_standardized = all_countries,
    year = all_years,
    stringsAsFactors = FALSE
  )
  
  # Add country names from our reference - with better error handling
  reference_grid <- reference_grid %>%
    left_join(
      COUNTRY_REFERENCE %>% 
        select(
          iso3_standardized = country_code,
          country_name_standardized = country_name
        ), 
      by = "iso3_standardized"
    )
  
  # Handle any missing country names in the reference grid
  missing_names <- is.na(reference_grid$country_name_standardized)
  if(any(missing_names)) {
    missing_codes <- unique(reference_grid$iso3_standardized[missing_names])
    message(paste("Warning: Missing country names for codes:", paste(missing_codes, collapse=", ")))
    
    # Try to fill in missing names from our matched log
    for(code in missing_codes) {
      # Find this code in our matched log
      idx <- which(all_matched$standardized_code == code & !is.na(all_matched$standardized_name))
      if(length(idx) > 0) {
        # Use the first available name
        name_to_use <- all_matched$standardized_name[idx[1]]
        message(paste("  - Using name from matched log for", code, ":", name_to_use))
        reference_grid$country_name_standardized[reference_grid$iso3_standardized == code] <- name_to_use
      } else {
        # As a last resort, use the code as the name
        message(paste("  - Using code as name for", code))
        reference_grid$country_name_standardized[reference_grid$iso3_standardized == code] <- code
      }
    }
  }
  
  # Now join each dataset to this reference grid
  final_df <- reference_grid
  for(i in seq_along(processed_data)) {
    df <- processed_data[[i]]
    if(nrow(df) == 0) next
    
    # Make sure we're joining on common columns
    join_cols <- c("iso3_standardized", "year")
    
    # Perform the join
    final_df <- left_join(final_df, df, by = join_cols)
    
    # If there are multiple country_name_standardized columns, combine them
    name_cols <- grep("country_name_standardized", names(final_df), value = TRUE)
    if(length(name_cols) > 1) {
      final_df$country_name_standardized <- final_df[[name_cols[1]]]
      for(col in name_cols[-1]) {
        final_df$country_name_standardized <- ifelse(
          is.na(final_df$country_name_standardized),
          final_df[[col]],
          final_df$country_name_standardized
        )
        final_df <- final_df %>% select(-all_of(col))
      }
    }
  }
  
  # Rename final columns
  final_df <- final_df %>% 
    rename(
      country_code = iso3_standardized,
      country_name = country_name_standardized
    )
  
  # Ensure no NAs in the matched log by replacing with appropriate placeholders
  if(nrow(all_matched) > 0) {
    # Use standardized values when original is NA
    all_matched$original_code[is.na(all_matched$original_code)] <- 
      all_matched$standardized_code[is.na(all_matched$original_code)]
    
    all_matched$original_name[is.na(all_matched$original_name)] <- 
      all_matched$standardized_name[is.na(all_matched$original_name)]
  }
  
  # Create matching summary
  matching_summary <- data.frame(
    dataset_id = integer(),
    dataset_name = character(),
    total_countries = integer(),
    matched_countries = integer(),
    unmatched_countries = integer(),
    match_rate = numeric(),
    stringsAsFactors = FALSE
  )
  
  if(!is.null(dataset_names)) {
    for(i in seq_along(dataset_names)) {
      ds_name <- dataset_names[i]
      
      # Count matches for this dataset
      matched_count <- sum(all_matched$dataset_id == i)
      unmatched_count <- sum(all_unmatched$dataset_id == i)
      total_count <- matched_count + unmatched_count
      
      matching_summary <- rbind(matching_summary, data.frame(
        dataset_id = i,
        dataset_name = ds_name,
        total_countries = total_count,
        matched_countries = matched_count,
        unmatched_countries = unmatched_count,
        match_rate = if(total_count > 0) matched_count / total_count * 100 else 0,
        stringsAsFactors = FALSE
      ))
    }
  }
  
  # Print summary information
  message("Country matching statistics:")
  message(paste("Total matched countries:", nrow(all_matched)))
  message(paste("Total unmatched countries:", nrow(all_unmatched)))
  
  # Write logs to CSV files - do this AFTER all processing is complete
  write.csv(all_matched, "wrangling/df_years2.0_diagnostics/country_matches.csv", row.names = FALSE)
  write.csv(all_unmatched, "wrangling/df_years2.0_diagnostics/country_unmatched.csv", row.names = FALSE)
  write.csv(matching_summary, "wrangling/df_years2.0_diagnostics/country_matching_summary.csv", row.names = FALSE)
  
  message("Created country matching logs:")
  message("  - country_matches.csv")
  message("  - country_unmatched.csv")
  message("  - country_matching_summary.csv")
  
  # Add logs as attributes to the final dataframe
  attr(final_df, "matched_countries") <- all_matched
  attr(final_df, "unmatched_countries") <- all_unmatched
  attr(final_df, "matching_summary") <- matching_summary
  
  # NEW: Clean up the column names by removing the _ds# suffixes
  message("Cleaning up column names...")
  
  # Create a list to store the original variable name mapping
  var_name_mapping <- list()
  
  # Build mapping of suffixed columns to original names
  for (i in seq_along(df_lists)) {
    # Get original column names for this dataset
    orig_cols <- original_colnames[[i]]
    
    # Skip country columns that will be standardized
    orig_cols <- orig_cols[!tolower(orig_cols) %in% tolower(country_colnames)]
    
    # For each original column, create a mapping to the suffixed version
    for (col in orig_cols) {
      suffixed_col <- paste0(col, "_ds", i)
      if (suffixed_col %in% names(final_df)) {
        var_name_mapping[[suffixed_col]] <- col
      }
    }
  }
  
  # Identify duplicate target names to handle
  duplicated_targets <- duplicated(unlist(var_name_mapping)) | 
                       duplicated(unlist(var_name_mapping), fromLast = TRUE)
  
  if (any(duplicated_targets)) {
    dup_names <- unique(unlist(var_name_mapping)[duplicated_targets])
    message(paste("Found duplicated variable names:", paste(dup_names, collapse=", ")))
    
    # For duplicates, keep the dataset suffix to distinguish them
    for (name in dup_names) {
      # Find all columns that would map to this name
      cols_to_this_name <- names(var_name_mapping)[unlist(var_name_mapping) == name]
      
      # Update the mapping to keep dataset identifier
      for (col in cols_to_this_name) {
        # Extract dataset number from the suffix
        ds_num <- gsub(".*_ds([0-9]+)$", "\\1", col)
        # Create a new name with dataset identifier
        var_name_mapping[[col]] <- paste0(name, "_ds", ds_num)
      }
    }
  }
  
  # Rename columns using the mapping
  old_names <- names(var_name_mapping)
  new_names <- unlist(var_name_mapping)
  
  # Only try to rename columns that actually exist
  old_names <- old_names[old_names %in% names(final_df)]
  new_names <- new_names[1:length(old_names)]
  
  if (length(old_names) > 0) {
    # Create a named vector for renaming
    rename_vec <- setNames(old_names, new_names)
    
    # Rename columns
    final_df <- final_df %>% rename(!!!rename_vec)
    
    message(paste("Renamed", length(old_names), "columns to their original names"))
  }
  
  # Remove redundant country columns
  country_cols_to_keep <- c("country_code", "country_name", "year", "year_fct")
  redundant_cols <- grep("country|Country|iso3|ISO3|original_country", 
                        names(final_df), value = TRUE)
  redundant_cols <- setdiff(redundant_cols, country_cols_to_keep)
  
  if (length(redundant_cols) > 0) {
    final_df <- final_df %>% select(-all_of(redundant_cols))
    message(paste("Removed", length(redundant_cols), "redundant country columns"))
  }
  
  # Ensure core columns are present
  if (!"year_fct" %in% names(final_df) && "year" %in% names(final_df)) {
    final_df$year_fct <- as.factor(final_df$year)
    message("Added year_fct column")
  }
  
  return(final_df)
}

#importing data function 
import_data <- function(year1, year2) {
  source("wrangling/years_filter_dataloss_proj.R")
  new_list_df <- years_filter(start_yr = year1, end_yr = year2)
  return(new_list_df)
}

#Loading Necessary Data 
df_years2.0 <- function(x, y) {
  list_for_dfs <- import_data(x, y)
  
  # Get the actual dataset names from the list
  dataset_names <- names(list_for_dfs)
  
  # Create more readable display names
  display_names <- dataset_names
  for(i in seq_along(dataset_names)) {
    if(dataset_names[i] %in% names(DATASET_DISPLAY_NAMES)) {
      display_names[i] <- DATASET_DISPLAY_NAMES[dataset_names[i]]
    }
  }
  
  # Add diagnostic information
  message(paste("Processing", length(list_for_dfs), "datasets"))
  
  for(i in seq_along(list_for_dfs)) {
    message(paste("Dataset", i, "(", display_names[i], ") has", 
                  nrow(list_for_dfs[[i]]), "rows and", 
                  ncol(list_for_dfs[[i]]), "columns"))
  }
  
  processed <- process_datasets(list_for_dfs, display_names)
  
  # Check for NAs in key columns
  na_countries <- sum(is.na(processed$country_name))
  na_codes <- sum(is.na(processed$country_code))
  if(na_countries > 0 || na_codes > 0) {
    warning(paste("Final dataset has", na_countries, "missing country names and", 
                  na_codes, "missing country codes"))
  }
  
  # Check if we have data before proceeding
  if(nrow(processed) == 0) {
    stop("No data found after processing")
  }
  
  # More robust column selection for mutate operations
  cols_to_factor <- c("income_level", "regime_type_2", "regime_type_4", 
                      "regime_type_10", "region_spi")
  cols_to_numeric <- c("log_gdppc", "log_pop", "gini_score", 
                       "sdg_overall", "spi_comp", "elect_dem", 
                       "lib_dem","part_dem", "delib_dem", "egal_dem")
  
  # Only try to convert columns that actually exist
  factor_cols_exist <- cols_to_factor[cols_to_factor %in% names(processed)]
  numeric_cols_exist <- cols_to_numeric[cols_to_numeric %in% names(processed)]
  
  data <- processed %>% 
    dplyr::mutate(year_fct = as.factor(year))
  
  # Only apply transformations to columns that exist
  if(length(factor_cols_exist) > 0) {
    data <- data %>% dplyr::mutate(across(all_of(factor_cols_exist), ~as.factor(.x)))
  }
  
  if(length(numeric_cols_exist) > 0) {
    data <- data %>% dplyr::mutate(across(all_of(numeric_cols_exist), ~as.numeric(.x)))
  }
  
  # Set a select order that puts the key columns first, then everything else
  select_cols <- c("country_name", "country_code", "year", "year_fct")
  # Identify which of these columns actually exist
  select_cols <- select_cols[select_cols %in% names(data)]
  
  # For the remaining columns, try to maintain a sensible order
  priority_cols <- c("income_level", "sdg_overall", "spi_comp", "elect_dem", 
                     "lib_dem","part_dem", "delib_dem", "egal_dem", 
                     "di_reg_type_2", "log_gdppc", "log_pop", "gini_score")
  
  # Find which priority columns exist
  priority_exist <- priority_cols[priority_cols %in% names(data)]
  
  # Add everything else
  other_cols <- setdiff(names(data), c(select_cols, priority_exist))
  
  # Create the final selection
  final_cols <- c(select_cols, priority_exist, other_cols)
  
  # Select columns in the desired order
  data <- data %>% dplyr::select(all_of(final_cols))
  
  # Copy matching logs from processed to final data
  attr(data, "matched_countries") <- attr(processed, "matched_countries")
  attr(data, "unmatched_countries") <- attr(processed, "unmatched_countries")
  attr(data, "matching_summary") <- attr(processed, "matching_summary")
  
  return(data)
}

# Helper function to get logs from processed data
get_country_matching_logs <- function(data) {
  return(list(
    matched = attr(data, "matched_countries"),
    unmatched = attr(data, "unmatched_countries"),
    summary = attr(data, "matching_summary")
  ))
}

# Example usage | NEWEST VERSION OF df_years2.0 AS OF 8/19/2025
merged_df <- df_years2.0(2015, 2024)

## TEMPORARY FIX [INCLUDING GNI CLASS]
merged_df <- merged_df %>%
  select(-income_level) %>% 
  left_join(gni_class %>% select(country_code, year, income_level),
            by = c("country_code", "year"))

# save testing_df_years2.0
write_csv(merged_df, "data/output/merged_df.csv")
