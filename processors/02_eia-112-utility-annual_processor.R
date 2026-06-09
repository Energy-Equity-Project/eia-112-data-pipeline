# 02_eia-112-utility-annual_processor.R
# Aggregates monthly utility-level EIA-112 shutoff data to annual summaries,
# joins EIA-861 ownership classifications, and computes disconnection-intensity rates.
# Output: Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-annual.csv

library(tidyverse)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Pick the latest dated CSV matching a filename pattern from a directory.
# Expected filename format: dd-mm-yyyy-<suffix>.csv
resolve_latest_csv <- function(dir, pattern) {
  files <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(files) == 0) stop(paste("No files matching", pattern, "in", dir))
  # Extract dates and pick the most recent
  dates <- as.Date(
    regmatches(basename(files), regexpr("\\d{2}-\\d{2}-\\d{4}", basename(files))),
    format = "%d-%m-%Y"
  )
  files[which.max(dates)]
}

# Normalize utility names for fuzzy joining:
# lowercase → strip trailing state suffix → replace punctuation with space → collapse whitespace
normalize_name <- function(x) {
  x %>%
    str_to_lower() %>%
    str_remove("\\s+-\\s+[a-z]{2}$") %>%          # trailing " - XX"
    str_remove("\\s+-\\s+\\([a-z]{2}\\)$") %>%    # trailing " - (XX)"
    str_remove("\\s+\\([a-z]{2}\\)$") %>%          # trailing " (XX)"
    str_replace_all("[.,&'\"]", " ") %>%
    str_squish()
}

# ---------------------------------------------------------------------------
# Resolve inputs
# ---------------------------------------------------------------------------

base_112 <- "../../../Cleaned_Data/eia/112"
base_861 <- "../../../Cleaned_Data/eia/861"

utility_monthly_path <- resolve_latest_csv(base_112, "\\d{2}-\\d{2}-\\d{4}-eia-112-utility-shutoffs\\.csv")
sales_861_path       <- resolve_latest_csv(base_861, "\\d{2}-\\d{2}-\\d{4}-eia-861-sales\\.csv")

message("Using utility monthly: ", basename(utility_monthly_path))
message("Using EIA-861 sales:   ", basename(sales_861_path))

# ---------------------------------------------------------------------------
# Build ownership lookup from EIA-861 (2024 only; electric-only source)
# ---------------------------------------------------------------------------

ownership_lut <- read.csv(sales_861_path) %>%
  filter(year == 2024) %>%
  select(state, utility_name, ownership) %>%
  distinct() %>%
  mutate(norm_name = normalize_name(utility_name)) %>%
  select(state, norm_name, ownership) %>%
  distinct()

# ---------------------------------------------------------------------------
# Load and prepare utility monthly data
# ---------------------------------------------------------------------------

utility_monthly <- read.csv(utility_monthly_path) %>%
  # Exclude State Adjustment reconciliation rows (not real utilities)
  filter(utility_name != "State Adjustment")

# ---------------------------------------------------------------------------
# Aggregate monthly → annual
# ---------------------------------------------------------------------------

utility_annual <- utility_monthly %>%
  group_by(state, utility_name, energy_type, year) %>%
  summarise(
    customer_count = mean(customer_count, na.rm = TRUE),
    shutoffs       = sum(shutoffs,        na.rm = TRUE),
    reconnections  = sum(reconnections,   na.rm = TRUE),
    final_notices  = sum(final_notices,   na.rm = TRUE)
  ) %>%
  ungroup()

# ---------------------------------------------------------------------------
# Join ownership
# ---------------------------------------------------------------------------

utility_annual <- utility_annual %>%
  mutate(norm_name = normalize_name(utility_name)) %>%
  left_join(ownership_lut, by = c("state", "norm_name")) %>%
  select(-norm_name)

# ---------------------------------------------------------------------------
# Derived disconnection-intensity rates (guarded against divide-by-zero)
# ---------------------------------------------------------------------------

utility_annual <- utility_annual %>%
  mutate(
    shutoff_rate = case_when(
      customer_count > 0 ~ shutoffs / customer_count,
      TRUE               ~ NA_real_
    ),
    reconnection_rate = case_when(
      shutoffs > 0 ~ reconnections / shutoffs,
      TRUE         ~ NA_real_
    ),
    final_notice_rate = case_when(
      customer_count > 0 ~ final_notices / customer_count,
      TRUE               ~ NA_real_
    )
  )

# ---------------------------------------------------------------------------
# Percentile rankings of shutoff_rate (ascending: higher rate = higher percentile)
# ---------------------------------------------------------------------------

utility_annual <- utility_annual %>%
  group_by(energy_type) %>%
  mutate(shutoff_rate_national_percentile = percent_rank(shutoff_rate)) %>%
  ungroup() %>%
  group_by(energy_type, state) %>%
  mutate(shutoff_rate_state_percentile = percent_rank(shutoff_rate)) %>%
  ungroup() %>%
  group_by(energy_type, ownership) %>%       # NA ownership = its own group (intended)
  mutate(shutoff_rate_ownership_percentile = percent_rank(shutoff_rate)) %>%
  ungroup() %>%
  # percent_rank() returns NaN for single-member groups; NA is the honest value
  mutate(across(ends_with("_percentile"), ~ if_else(is.nan(.), NA_real_, .)))

# Reorder columns to match documented output schema
utility_annual <- utility_annual %>%
  select(
    state, utility_name, energy_type, year,
    ownership, customer_count,
    shutoffs, reconnections, final_notices,
    shutoff_rate, reconnection_rate, final_notice_rate,
    shutoff_rate_national_percentile,
    shutoff_rate_state_percentile,
    shutoff_rate_ownership_percentile
  )

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------

out_filename <- paste0(format(Sys.Date(), "%d-%m-%Y"), "-eia-112-utility-annual.csv")
out_path     <- file.path(base_112, out_filename)

write.csv(utility_annual, out_path, row.names = FALSE)
message("Wrote: ", out_path)

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

cat("\n--- Sanity checks ---\n")
cat("Total rows:", nrow(utility_annual), "\n")

cat("\nRows per energy_type:\n")
print(utility_annual %>% count(energy_type))

cat("\nOwnership non-NA rate by energy_type:\n")
utility_annual %>%
  group_by(energy_type) %>%
  summarise(
    n         = n(),
    n_with_ownership = sum(!is.na(ownership)),
    pct_with_ownership = round(100 * mean(!is.na(ownership)), 1)
  ) %>%
  ungroup() %>%
  print()

cat("\nOwnership values (electric only):\n")
utility_annual %>%
  filter(energy_type == "electric", !is.na(ownership)) %>%
  count(ownership, sort = TRUE) %>%
  print()

cat("\nNA rate counts:\n")
utility_annual %>%
  summarise(
    shutoff_rate_na    = sum(is.na(shutoff_rate)),
    reconnection_rate_na = sum(is.na(reconnection_rate)),
    final_notice_rate_na = sum(is.na(final_notice_rate))
  ) %>%
  print()

cat("\nPercentile ranges (should span ~0 to 1 within each energy_type):\n")
utility_annual %>%
  group_by(energy_type) %>%
  summarise(
    natl_min = min(shutoff_rate_national_percentile, na.rm = TRUE),
    natl_max = max(shutoff_rate_national_percentile, na.rm = TRUE),
    state_na = sum(is.na(shutoff_rate_state_percentile)),
    own_na   = sum(is.na(shutoff_rate_ownership_percentile))
  ) %>%
  ungroup() %>%
  print()
