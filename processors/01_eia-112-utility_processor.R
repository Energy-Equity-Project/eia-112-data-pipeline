# EIA Form 112 — Utility-Level Shutoffs Processor
# Reads 4 metric sheets from each of the two EIA-112 utility-level workbooks
# (electric and natural gas), pivots each from wide (one row per utility,
# 12 month columns) to long, joins metrics within each fuel, then stacks
# both fuels into a single long-format analysis-ready CSV.
#
# --- INPUTS ---
# ../../../Data/eia/112/eia_112_electric_utility_level_data_2024.xlsx
# ../../../Data/eia/112/eia_112_natural_gas_utility_level_data_2024.xlsx
# Both files share the same 5-sheet structure: About (skipped), Final notices,
# Disconnections, Reconnections, Number of customers.
# Real column header is on row 5 (rows 1-4 are title/blank); first two columns
# are State abbreviation and Utility name. Values are clean numeric — no
# thousands commas, no Q/R flags.
#
# --- OUTPUT SCHEMA ---
# state          (2-char abbreviation)
# utility_name
# energy_type    ("electric" or "gas")
# year           (2024L)
# month          (1-12)
# shutoffs       (Disconnections sheet)
# reconnections  (Reconnections sheet)
# final_notices  (Final notices sheet)
# customer_count (Number of customers sheet)

library(tidyverse)
library(readxl)

# --- Paths ---
raw_base    <- "../../../Data/eia/112"
# Outputs are written to both the shared Cleaned_Data store (single source of
# truth) and the repo-local outputs/ folder (gitignored) for convenient access.
output_bases <- c("../../../Cleaned_Data/eia/112", "outputs")

for (b in output_bases) dir.create(b, recursive = TRUE, showWarnings = FALSE)

electric_file <- file.path(raw_base, "eia_112_electric_utility_level_data_2024.xlsx")
gas_file      <- file.path(raw_base, "eia_112_natural_gas_utility_level_data_2024.xlsx")

# --- Helper: Read one metric sheet and pivot to long format ---
# Layout: rows 1-4 are title/blank; row 5 is the real header
# (State abbreviation | Utility name | January | ... | December).
# Foot rows are filtered by requiring a valid 2-char state code.
read_metric <- function(file, sheet, value_name) {
  read_excel(file, sheet = sheet, skip = 4, col_types = "text") %>%
    rename(state = 1, utility_name = 2) %>%
    select(state, utility_name, all_of(month.name)) %>%
    # Keep only data rows: valid 2-char state code and non-missing utility name
    filter(str_length(state) == 2, !is.na(utility_name)) %>%
    pivot_longer(
      cols      = all_of(month.name),
      names_to  = "month_name",
      values_to = value_name
    ) %>%
    mutate(
      month       = match(month_name, month.name),
      !!value_name := as.numeric(str_trim(str_remove_all(.data[[value_name]], ",")))
    ) %>%
    select(state, utility_name, month, all_of(value_name))
}

# --- Helper: Read all 4 metric sheets for one fuel and join them ---
read_fuel <- function(file, energy_type) {
  cat(sprintf("\nReading %s file...\n", energy_type))

  notices        <- read_metric(file, "Final notices",        "final_notices")
  shutoffs       <- read_metric(file, "Disconnections",       "shutoffs")
  reconnections  <- read_metric(file, "Reconnections",        "reconnections")
  customer_count <- read_metric(file, "Number of customers",  "customer_count")

  cat(sprintf(
    "  %s: %s utility-month rows | %d utilities | %d states\n",
    energy_type,
    format(nrow(shutoffs), big.mark = ","),
    n_distinct(shutoffs$utility_name),
    n_distinct(shutoffs$state)
  ))

  reduce(
    list(notices, shutoffs, reconnections, customer_count),
    full_join, by = c("state", "utility_name", "month")
  ) %>%
    mutate(energy_type = energy_type)
}

# --- Main Execution ---
electric <- read_fuel(electric_file, "electric")
gas      <- read_fuel(gas_file,      "gas")

# Stack both fuels — energy_type is a row dimension, not a column set
combined <- bind_rows(electric, gas)

# Drop State Total rows (State Adjustment rows retained per design)
combined <- combined %>%
  filter(utility_name != "State Total")

# Add year and put columns in final order
combined <- combined %>%
  mutate(year = 2024L) %>%
  select(
    state, utility_name, energy_type, year, month,
    shutoffs, reconnections, final_notices, customer_count
  ) %>%
  arrange(state, utility_name, energy_type, month)

# --- Output ---
output_filename <- paste0(format(Sys.Date(), "%d-%m-%Y"), "-eia-112-utility-shutoffs.csv")

for (b in output_bases) {
  output_file <- file.path(b, output_filename)
  write.csv(combined, output_file, row.names = FALSE)
  cat(sprintf("\nOutput written to: %s\n", output_file))
}

# --- Sanity Checks ---
cat(sprintf(
  "\nTotal rows: %s\n",
  format(nrow(combined), big.mark = ",")
))

cat("\nRows and distinct utilities per energy_type:\n")
combined %>%
  group_by(energy_type) %>%
  summarise(
    rows      = n(),
    utilities = n_distinct(utility_name),
    .groups = "drop"
  ) %>%
  ungroup() %>%
  print()

cat("\nNA counts per metric column:\n")
combined %>%
  summarise(across(c(shutoffs, reconnections, final_notices, customer_count), ~ sum(is.na(.)))) %>%
  print()

# Spot-check: for a sample state/month/fuel, verify that
# sum(utility shutoffs) + State Adjustment ≈ dropped State Total
# (uses CA electric for month 6 as a concrete example)
sample_state <- "CA"
sample_month <- 6L
sample_fuel  <- "electric"

state_adj <- combined %>%
  filter(
    state == sample_state, month == sample_month, energy_type == sample_fuel,
    utility_name == "State Adjustment"
  ) %>%
  pull(shutoffs)

utility_sum <- combined %>%
  filter(
    state == sample_state, month == sample_month, energy_type == sample_fuel,
    utility_name != "State Adjustment"
  ) %>%
  summarise(total = sum(shutoffs, na.rm = TRUE)) %>%
  pull(total)

cat(sprintf(
  "\nSpot-check (%s %s month %d): utility sum = %s | State Adjustment = %s | implied total = %s\n",
  sample_state, sample_fuel, sample_month,
  format(utility_sum, big.mark = ","),
  ifelse(length(state_adj) == 0 || is.na(state_adj), "NA", format(state_adj, big.mark = ",")),
  format(utility_sum + ifelse(length(state_adj) == 0 || is.na(state_adj), 0, state_adj), big.mark = ",")
))

cat("\nDone.\n")
