# 03_eia-112-build-workbook.R
# Assembles the three utility-level EIA-112 pipeline CSVs into a single formatted
# Excel workbook with five sheets: Documentation, Utility Annual, Utility Monthly,
# State Adjustments, Bad Data Flags.
# Output: Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-workbook.xlsx

library(tidyverse)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Pick the latest dated CSV matching a filename pattern from a directory.
# Expected filename format: dd-mm-yyyy-<suffix>.csv
resolve_latest_csv <- function(dir, pattern) {
  files <- list.files(dir, pattern = pattern, full.names = TRUE)
  if (length(files) == 0) stop(paste("No files matching", pattern, "in", dir))
  dates <- as.Date(
    regmatches(basename(files), regexpr("\\d{2}-\\d{2}-\\d{4}", basename(files))),
    format = "%d-%m-%Y"
  )
  files[which.max(dates)]
}

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

base_112 <- "../../../Cleaned_Data/eia/112"

monthly_path <- resolve_latest_csv(base_112, "eia-112-utility-shutoffs\\.csv$")
annual_path  <- resolve_latest_csv(base_112, "eia-112-utility-annual\\.csv$")
baddata_path <- resolve_latest_csv(base_112, "eia-112-utility-bad-data\\.csv$")

message("Reading: ", basename(monthly_path))
message("Reading: ", basename(annual_path))
message("Reading: ", basename(baddata_path))

monthly_raw <- read.csv(monthly_path, stringsAsFactors = FALSE)
annual      <- read.csv(annual_path,  stringsAsFactors = FALSE)
baddata     <- read.csv(baddata_path, stringsAsFactors = FALSE)

utility_monthly <- monthly_raw %>% filter(utility_name != "State Adjustment")
state_adj       <- monthly_raw %>% filter(utility_name == "State Adjustment")

message(sprintf(
  "Utility Monthly: %d rows | State Adjustments: %d rows | Utility Annual: %d rows | Bad Data Flags: %d rows",
  nrow(utility_monthly), nrow(state_adj), nrow(annual), nrow(baddata)
))

# ---------------------------------------------------------------------------
# Assemble workbook
# ---------------------------------------------------------------------------

wb <- openxlsx::createWorkbook()

# Shared header style applied to data sheet header rows
hdr_style  <- openxlsx::createStyle(textDecoration = "bold", fgFill = "#D9E1F2", border = "TopBottom")
bold_style <- openxlsx::createStyle(textDecoration = "bold")
wrap_style <- openxlsx::createStyle(wrapText = TRUE, valign = "top")

# Add a standard data sheet: write data, freeze header, size columns from header width
add_data_sheet <- function(sheet_name, df) {
  openxlsx::addWorksheet(wb, sheet_name)
  openxlsx::writeData(wb, sheet_name, df, headerStyle = hdr_style)
  openxlsx::freezePane(wb, sheet_name, firstActiveRow = 2)
  col_widths <- pmax(nchar(names(df)) + 2, 10)
  openxlsx::setColWidths(wb, sheet_name, cols = seq_len(ncol(df)), widths = col_widths)
}

# ---------------------------------------------------------------------------
# 1. Documentation sheet
# ---------------------------------------------------------------------------

openxlsx::addWorksheet(wb, "Documentation")

# cur_row tracks the next empty row on the Documentation sheet
cur_row <- 1L

# Write a character vector — one element per row, no column header.
wv <- function(vec) {
  openxlsx::writeData(wb, "Documentation", vec, startRow = cur_row)
  cur_row <<- cur_row + length(vec)
}

# Write a data frame with a bold shaded header row.
wt <- function(df) {
  openxlsx::writeData(wb, "Documentation", df, startRow = cur_row,
                      headerStyle = openxlsx::createStyle(
                        textDecoration = "bold", fgFill = "#D9E1F2", border = "TopBottom"
                      ))
  cur_row <<- cur_row + nrow(df) + 1L
}

# Bold a specific absolute row on the Documentation sheet.
bold_doc <- function(row) {
  openxlsx::addStyle(wb, "Documentation", bold_style, rows = row, cols = 1, stack = TRUE)
}

# -- Title block --
wv(c(
  "2024 EIA-112 Utility-Level Residential Disconnections — Consolidated Workbook",
  "Energy Equity Project",
  paste0("Generated: ", format(Sys.Date(), "%B %d, %Y")),
  "",
  paste(
    "Single-workbook consolidation of all utility-level EIA Form 112 pipeline outputs.",
    "Each data sheet is a complete, analysis-ready dataset. The three source CSVs written to",
    "Cleaned_Data/eia/112/ remain the machine-readable source of truth and continue to be synced to S3.",
    "This workbook does not replace them."
  ),
  ""
))
openxlsx::addStyle(wb, "Documentation",
                   openxlsx::createStyle(textDecoration = "bold", fontSize = 14),
                   rows = 1, cols = 1, stack = TRUE)
bold_doc(2)

# -- Sheet index --
wv(c("SHEET INDEX", ""))
bold_doc(cur_row - 2L)

wt(data.frame(
  `Sheet Name`     = c("Utility Annual", "Utility Monthly", "State Adjustments", "Bad Data Flags"),
  `Rows (approx.)` = c("~2,148", "~25,956", "~1,224", "145"),
  `Description`    = c(
    "Annual utility-level summary for 2024, enriched with ownership, disconnection-intensity rates, and percentile rankings. 19 columns.",
    "Monthly utility-level disconnection activity for 2024 (long format: one row per utility x fuel x month). Excludes State Adjustment rows. 9 columns.",
    "Monthly State Adjustment rows isolated from the monthly output. EIA estimation values accounting for nonresponse and data-quality resolutions. Not real utilities. 9 columns.",
    "Rows EEP flagged as having bad or incomplete 2024 reporting. Retained in the annual output but excluded from percentile benchmarks. Same 19-column schema as Utility Annual."
  ),
  check.names = FALSE
))
wv("")

# -- Data sources --
wv(c("DATA SOURCES & CITATIONS", ""))
bold_doc(cur_row - 2L)

wv(c(
  "1. EIA Form 112 — Residential Utility Disconnections Survey, 2024 (primary input)",
  "   First reporting year. OMB approval October 2024; data collection February–December 2025;",
  "   EIA processing completed February 2026. Two utility-level workbooks (electric + gas),",
  "   each with five metric sheets (Final notices, Disconnections, Reconnections, Number of",
  "   customers, About). Utility-level files carry no Q/R quality flags.",
  "   URL: https://www.eia.gov/analysis/requests/residential/utility/",
  "",
  "2. EIA Form 861 — Annual Electric Power Industry Report (ownership lookup)",
  "   Source: Cleaned_Data/eia/861/DD-MM-YYYY-eia-861-sales.csv (2024 data, electric service only).",
  "   Provides ownership classification for the ownership / ownership_source columns.",
  "   Covers ~89% of electric utilities; ~7% of gas utilities (combined-service utilities only).",
  "",
  "3. EEP manual ownership overrides (data/eia-112-manual-ownership-overrides.csv)",
  "   EEP-determined ownership classifications for ~988 utilities (134 electric + 854 gas)",
  "   that EIA-861 could not classify. Assigned by EEP team manual research, May 2026.",
  "   Recorded in the output as ownership_source = 'eep_determined'.",
  "",
  "4. EEP bad-data flags (data/eia-112-manual-bad-data-flags.csv)",
  "   145 utility-year rows EEP identified as having bad or incomplete 2024 reporting.",
  "   Flagged rows are retained in the annual output but receive NA for all three",
  "   shutoff_rate_*_percentile columns so bad reporting does not distort benchmarks.",
  "",
  "5. EIA 2024 Residential Utility Disconnections Report (April 2026)",
  "   National and state aggregate report. Cleaned separately in eep-pipeline-core;",
  "   not included in this workbook.",
  ""
))

# -- Column dictionaries --
wv(c("COLUMN DICTIONARIES", ""))
bold_doc(cur_row - 2L)

# Utility Annual
wv(c("Utility Annual — DD-MM-YYYY-eia-112-utility-annual.csv (19 columns)", ""))
bold_doc(cur_row - 2L)

wt(data.frame(
  Column = c(
    "state", "utility_name", "energy_type", "year", "ownership", "ownership_source",
    "parent", "customer_count", "shutoffs", "reconnections", "final_notices",
    "shutoff_rate", "reconnection_rate", "final_notice_rate",
    "shutoff_rate_national_percentile", "shutoff_rate_state_percentile",
    "shutoff_rate_ownership_percentile", "bad_data_flag", "data_quality_note"
  ),
  Type = c(
    "character", "character", "character", "integer", "character", "character",
    "character", "numeric", "numeric", "numeric", "numeric",
    "numeric", "numeric", "numeric",
    "numeric", "numeric", "numeric", "character", "character"
  ),
  Description = c(
    "2-character state abbreviation",
    "EIA-reported utility name (as-is from source)",
    "'electric' or 'gas'",
    "Reporting year (2024)",
    "Ownership class (EIA-861 or EEP-determined); NA only if both sources lack a classification",
    "'eia_861' where ownership came from EIA-861 join; 'eep_determined' where filled by EEP manual review; NA if unassigned",
    "EEP-identified parent company name (~136 utilities); NA otherwise",
    "12-month average residential customer count (rate denominator, not a cumulative sum)",
    "Annual sum of residential disconnections",
    "Annual sum of residential reconnections",
    "Annual sum of final notices sent",
    "shutoffs / customer_count; NA when customer_count <= 0",
    "reconnections / shutoffs; NA when shutoffs <= 0 (not Inf)",
    "final_notices / customer_count; NA when customer_count <= 0",
    "percent_rank(shutoff_rate) within energy_type; 0-1 fraction; NA for bad_data_flag='Y', NA shutoff_rate, or n=1 peer group",
    "percent_rank(shutoff_rate) within (energy_type, state); 0-1 fraction; NA for bad_data_flag='Y', NA shutoff_rate, or n=1 peer group",
    "percent_rank(shutoff_rate) within (energy_type, ownership); 0-1 fraction; NA for bad_data_flag='Y', NA shutoff_rate, or n=1 peer group",
    "'Y' for 145 EEP-flagged rows (bad/incomplete reporting); NA otherwise",
    "Algorithmically derived note: 'customer_count missing'; 'all activity metrics zero'; 'shutoff_rate exceeds 1 (shutoffs > customers)'; 'final notices but zero shutoffs'; NA where no rule applies"
  ),
  stringsAsFactors = FALSE
))
wv("")

# Utility Monthly and State Adjustments share the same 9-column schema
monthly_dict <- data.frame(
  Column = c("state", "utility_name", "energy_type", "year", "month",
             "shutoffs", "reconnections", "final_notices", "customer_count"),
  Type   = c("character", "character", "character", "integer", "integer",
             "numeric", "numeric", "numeric", "numeric"),
  Description = c(
    "2-character state abbreviation",
    "EIA-reported utility name (as-is from source)",
    "'electric' or 'gas'",
    "Reporting year (2024)",
    "Month number (1-12)",
    "Residential disconnections (Disconnections sheet)",
    "Residential reconnections (Reconnections sheet)",
    "Final notices sent to residential customers (Final notices sheet)",
    "Total residential customers (Number of customers sheet)"
  ),
  stringsAsFactors = FALSE
)

wv(c(
  "Utility Monthly — DD-MM-YYYY-eia-112-utility-shutoffs.csv filtered to utility_name != 'State Adjustment' (9 columns)",
  ""
))
bold_doc(cur_row - 2L)
wt(monthly_dict)
wv("")

wv(c(
  "State Adjustments — DD-MM-YYYY-eia-112-utility-shutoffs.csv filtered to utility_name == 'State Adjustment' (9 columns)",
  ""
))
bold_doc(cur_row - 2L)
wt(monthly_dict)
wv("")

wv(c(
  "Bad Data Flags — DD-MM-YYYY-eia-112-utility-bad-data.csv (19 columns, same schema as Utility Annual)",
  ""
))
bold_doc(cur_row - 2L)
wv(c(
  "Contains only the 145 rows where bad_data_flag = 'Y'. All 19 columns are identical to the Utility Annual sheet.",
  "These rows are also present in the Utility Annual sheet; this sheet isolates them for convenient review.",
  ""
))

# -- Key limitations --
wv(c("KEY LIMITATIONS", ""))
bold_doc(cur_row - 2L)

wv(c(
  "1. Gas and electric disconnections must NOT be summed. Combined-service customers are counted once per",
  "   fuel; there is significant population overlap between the gas and electric figures.",
  "",
  "2. Counts are events, not unique customers. A single account may receive multiple final notices,",
  "   disconnections, and reconnections within the same year.",
  "",
  "3. Census survey (no sampling error) but subject to non-sampling error. EIA handles nonresponse via",
  "   regression imputation; customer counts are substituted from EIA-861 / EIA-176 frame data.",
  "",
  "4. Pay-in-advance service lapses are excluded from disconnections and imputed if misreported.",
  "",
  "5. State Adjustment rows (isolated on the State Adjustments sheet) are EIA estimation values accounting",
  "   for nonresponse and data-quality resolutions. They are not real utilities. State Totals =",
  "   utilities + State Adjustment. They are excluded from Utility Monthly and Utility Annual.",
  "",
  "6. Utility-level files carry no Q/R quality flags (unlike the state/national report workbook).",
  "",
  "7. customer_count is a 12-month mean (rate denominator), not a cumulative sum. Utilities that joined",
  "   or left service mid-year have averages reflecting fewer than 12 active months.",
  "",
  "8. 2024 is the first reporting year. No prior-year trend baseline exists.",
  "",
  "9. Flagged rows (bad_data_flag = 'Y') receive NA for all three shutoff_rate_*_percentile columns",
  "   so bad reporting does not distort benchmark comparisons among utilities."
))

# -- Format Documentation sheet --
openxlsx::setColWidths(wb, "Documentation", cols = 1:3, widths = c(55, 18, 80))
openxlsx::addStyle(wb, "Documentation", wrap_style,
                   rows = 1:(cur_row - 1L), cols = 1:3, gridExpand = TRUE, stack = TRUE)

# ---------------------------------------------------------------------------
# 2-5. Data sheets (Documentation is already sheet 1)
# ---------------------------------------------------------------------------

add_data_sheet("Utility Annual",    annual)
add_data_sheet("Utility Monthly",   utility_monthly)
add_data_sheet("State Adjustments", state_adj)
add_data_sheet("Bad Data Flags",    baddata)

# ---------------------------------------------------------------------------
# Write workbook — dual-write to Cleaned_Data and repo outputs/
# ---------------------------------------------------------------------------

date_stamp   <- format(Sys.Date(), "%d-%m-%Y")
fname        <- paste0(date_stamp, "-eia-112-utility-workbook.xlsx")
output_bases <- c(base_112, "outputs")

for (base in output_bases) {
  path <- file.path(base, fname)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  message("Workbook written to: ", path)
}

message("\nSheet order: Documentation, Utility Annual, Utility Monthly, State Adjustments, Bad Data Flags")
message(sprintf("Row counts: Annual=%d, Monthly=%d, State Adjustments=%d, Bad Data Flags=%d",
                nrow(annual), nrow(utility_monthly), nrow(state_adj), nrow(baddata)))
