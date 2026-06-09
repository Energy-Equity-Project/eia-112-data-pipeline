# eia-112-861-match-diagnostic.R
# Recomputes the EIA-112 × EIA-861 ownership match independently of Stage 2.
# Reports match rates by energy_type and writes the unmatched-electric CSV.
# Run from the repo root: Rscript diagnostics/eia-112-861-match-diagnostic.R

library(tidyverse)

# ---------------------------------------------------------------------------
# Helpers (copied verbatim from 02_eia-112-utility-annual_processor.R)
# ---------------------------------------------------------------------------

resolve_latest_csv <- function(dir, pattern) {
  files <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(files) == 0) stop(paste("No files matching", pattern, "in", dir))
  dates <- as.Date(
    regmatches(basename(files), regexpr("\\d{2}-\\d{2}-\\d{4}", basename(files))),
    format = "%d-%m-%Y"
  )
  files[which.max(dates)]
}

normalize_name <- function(x) {
  x %>%
    str_to_lower() %>%
    str_remove("\\s+-\\s+[a-z]{2}$") %>%
    str_remove("\\s+-\\s+\\([a-z]{2}\\)$") %>%
    str_remove("\\s+\\([a-z]{2}\\)$") %>%
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
# Build ownership lookup (exact replica of Stage 2)
# ---------------------------------------------------------------------------

ownership_lut <- read.csv(sales_861_path) %>%
  filter(year == 2024) %>%
  select(state, utility_name, ownership) %>%
  distinct() %>%
  mutate(norm_name = normalize_name(utility_name)) %>%
  select(state, norm_name, ownership) %>%
  distinct()

# ---------------------------------------------------------------------------
# Aggregate monthly → one row per (state, utility_name, energy_type)
# Drop State Adjustment rows; keep customer_count (mean) and shutoffs (sum)
# for prioritization in the output CSV.
# ---------------------------------------------------------------------------

utility_summary <- read.csv(utility_monthly_path) %>%
  filter(utility_name != "State Adjustment") %>%
  group_by(state, utility_name, energy_type) %>%
  summarise(
    customer_count = mean(customer_count, na.rm = TRUE),
    shutoffs       = sum(shutoffs,        na.rm = TRUE)
  ) %>%
  ungroup() %>%
  mutate(norm_name = normalize_name(utility_name)) %>%
  left_join(ownership_lut, by = c("state", "norm_name"))

# ---------------------------------------------------------------------------
# Match-rate report
# ---------------------------------------------------------------------------

match_stats <- utility_summary %>%
  group_by(energy_type) %>%
  summarise(
    total_utilities = n(),
    matched         = sum(!is.na(ownership)),
    unmatched       = sum(is.na(ownership)),
    pct_matched     = round(100 * mean(!is.na(ownership)), 1)
  ) %>%
  ungroup()

overall <- utility_summary %>%
  summarise(
    energy_type     = "overall",
    total_utilities = n(),
    matched         = sum(!is.na(ownership)),
    unmatched       = sum(is.na(ownership)),
    pct_matched     = round(100 * mean(!is.na(ownership)), 1)
  )

cat("\n--- EIA-112 × EIA-861 match rates ---\n")
print(bind_rows(match_stats, overall))

# ---------------------------------------------------------------------------
# Write unmatched-electric CSV
# ---------------------------------------------------------------------------

unmatched_electric <- utility_summary %>%
  filter(energy_type == "electric", is.na(ownership)) %>%
  select(state, utility_name, norm_name, customer_count, shutoffs) %>%
  arrange(desc(customer_count))

out_filename <- paste0(format(Sys.Date(), "%d-%m-%Y"), "-eia-112-861-unmatched-electric-utilities.csv")
out_path     <- file.path("outputs", out_filename)

write.csv(unmatched_electric, out_path, row.names = FALSE)
message("\nWrote: ", out_path)
message("Unmatched electric utilities: ", nrow(unmatched_electric))

# Integrity check: matched + unmatched == total electric
total_electric   <- nrow(filter(utility_summary, energy_type == "electric"))
matched_electric <- sum(!is.na(filter(utility_summary, energy_type == "electric")$ownership))
stopifnot(nrow(unmatched_electric) + matched_electric == total_electric)
message("Integrity check passed: ", nrow(unmatched_electric), " unmatched + ",
        matched_electric, " matched = ", total_electric, " total electric")
