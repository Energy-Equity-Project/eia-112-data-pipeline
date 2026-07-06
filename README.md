# eia-112-data-pipeline

Standalone pipeline that cleans the **utility-level** EIA Form 112 residential
disconnection workbooks into analysis-ready CSVs. This repo is the single source of truth
for the utility-level EIA-112 cleaning behind the **2024 Residential Utility Disconnections
Report**.

It produces data — writing each output to the shared `Cleaned_Data/eia/112/` folder (the
single source of truth) and to a repo-local `outputs/` copy for convenient access. Both
copies are gitignored; data is never committed here, and only the `Cleaned_Data/` copy is
synced to S3.

> Not in scope: the *state/national* EIA-112 report cleaning, which lives in
> `eep-pipeline-core/processors/eia-112_processor.R` and consumes a different workbook.

## Data flow

```
Data/eia/112/*.xlsx
   └─ 01_eia-112-utility_processor.R ──▶ Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-shutoffs.csv  (monthly, long)
                                              └─ 02_eia-112-utility-annual_processor.R
                                                 + Cleaned_Data/eia/861/DD-MM-YYYY-eia-861-sales.csv (ownership)
                                                     ──▶ Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-annual.csv  (annual, enriched)
                                                     ──▶ Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-bad-data.csv (flagged rows only)
                                                              └─ 03_eia-112-build-workbook.R  (reads all three CSVs)
                                                                     ──▶ Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-workbook.xlsx
```

- **Stage 1** reshapes the two raw workbooks (electric + gas) into one row per utility ×
  fuel × month.
- **Stage 2** aggregates to annual, joins EIA-861 ownership, and adds disconnection-intensity
  rates and national/state/ownership percentile rankings.
- **Stage 3** reads the three CSVs produced by Stages 1 and 2 and assembles them into a
  single formatted Excel workbook with a Documentation sheet and four data sheets.

Each stage writes every output CSV to **both** `Cleaned_Data/eia/112/` and the repo-local
`outputs/` folder. Inputs are still resolved only from `Cleaned_Data/`, so the local copies
never feed back into the pipeline.

## Repository structure

```
eia-112-data-pipeline/
├── README.md                                    # this file
├── METHODOLOGY.md                               # full source + transform methodology
├── CLAUDE.md                                     # per-repo context (gitignored; local only)
├── collectors/
│   └── eia-112_collector.md                      # manual download instructions
├── processors/
│   ├── 01_eia-112-utility_processor.R            # Stage 1: raw workbooks → monthly long
│   ├── 02_eia-112-utility-annual_processor.R     # Stage 2: monthly → annual + ownership + rates
│   └── 03_eia-112-build-workbook.R               # Stage 3: assemble CSVs into formatted .xlsx
├── outputs/                                      # repo-local copy of generated files (gitignored)
└── temp/                                         # scratch (gitignored)
```

## Setup

**Prerequisites:** R (≥ 4.0) with `tidyverse`, `readxl`, and `openxlsx`.

```r
install.packages(c("tidyverse", "readxl", "openxlsx"))
```

**Inputs** (referenced via relative paths to the shared data folders — do not copy into this repo):
- `../../../Data/eia/112/eia_112_electric_utility_level_data_2024.xlsx`
- `../../../Data/eia/112/eia_112_natural_gas_utility_level_data_2024.xlsx`
- `../../../Cleaned_Data/eia/861/DD-MM-YYYY-eia-861-sales.csv` (latest; ownership lookup)

To obtain the raw workbooks, see `collectors/eia-112_collector.md`.

## Running

Run **from the repo root**, in order (each stage auto-detects its upstream inputs):

```bash
Rscript processors/01_eia-112-utility_processor.R
Rscript processors/02_eia-112-utility-annual_processor.R
Rscript processors/03_eia-112-build-workbook.R
```

Stages 1 and 2 print sanity checks. Expected 2024 values are tabulated in `METHODOLOGY.md`
(§7) — notably ~2,148 annual rows, ~1,226 electric / ~922 gas, ~89% / ~7% ownership match,
and percentiles spanning 0–1. Stage 3 can be run alone if the CSVs from Stages 1 and 2 are
already current — it only reads them.

## Outputs

| File | Stage | Rows | Description |
|------|-------|------|-------------|
| `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-shutoffs.csv` | 1 | ~27,000 | Monthly utility-level shutoffs (long: utility × fuel × month) |
| `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-annual.csv` | 2 | ~2,148 | Annual summary with ownership, rates, and peer percentiles (19 cols) |
| `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-bad-data.csv` | 2 | 145 | Flagged-rows-only extract from the annual output (same 19 cols) |
| `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-workbook.xlsx` | 3 | — | Consolidated workbook: Documentation + 4 data sheets |

Each file is written to both `Cleaned_Data/eia/112/` and the repo-local `outputs/` folder.
CSV schemas are documented in both `METHODOLOGY.md` and `Cleaned_Data/eia/112/CLEANED.md`.
The workbook's Documentation sheet is the in-workbook authoritative copy of the schema.

## Documentation

- **`METHODOLOGY.md`** — full methodology: data sources, both stages' transforms, schemas,
  caveats, and reproduction values.
- **`collectors/eia-112_collector.md`** — how to download the raw workbooks.
- **`../../../Data/eia/112/SOURCE.md`** — raw source provenance.
- **`../../../Cleaned_Data/eia/112/CLEANED.md`** — cleaned-dataset schemas and notes.

## Conventions

R / tidyverse, snake_case, `%>%`, `write.csv`/`read.csv`, dated `DD-MM-YYYY-*.csv` outputs.
Shared data lives in `Data/` and `Cleaned_Data/`; outputs are additionally mirrored to the
gitignored `outputs/` folder, and data is never committed here. Commit messages in present tense.
