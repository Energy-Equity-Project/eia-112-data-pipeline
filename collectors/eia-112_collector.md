# EIA Form 112 — Utility-Level Workbooks (manual collection)

*EIA releases Form 112 data annually; 2024 is the first reporting year.*

## Method

1. Navigate to https://www.eia.gov/analysis/requests/residential/utility/
2. Download the three workbooks published there into `../../../Data/eia/112/`:
   | File | Used by this pipeline |
   |------|-----------------------|
   | `eia_112_electric_utility_level_data_2024.xlsx` | **Yes** — Stage 1 input (electric) |
   | `eia_112_natural_gas_utility_level_data_2024.xlsx` | **Yes** — Stage 1 input (gas) |
   | `eia_112_national_shutoffs_report_2024.xlsx` | No — state/national report; cleaned separately by `eep-pipeline-core/processors/eia-112_processor.R` |
3. Keep the EIA filenames as-is (the Stage 1 processor references them literally).
4. Update `../../../Data/eia/112/SOURCE.md` (download date, version table) and
   `../../../Data/CATALOG.md` if a new annual release is added.

This repo's Stage 1 processor (`processors/01_eia-112-utility_processor.R`) uses the two
utility-level workbooks. The ownership lookup for Stage 2 comes from the already-cleaned
EIA-861 sales data and requires no separate collection here.

## Notes

- Each utility-level workbook has 5 sheets (About, Final notices, Disconnections,
  Reconnections, Number of customers); the real header is on row 5.
- New form: OMB approval October 2024. For future years, repeat the steps above with the
  corresponding annual files and bump the `year` constant in
  `processors/01_eia-112-utility_processor.R`.
- See `../METHODOLOGY.md` and `../../../Data/eia/112/SOURCE.md` for full source detail.
