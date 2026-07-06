# EIA Form 112 Utility-Level Disconnections — Methodology

This is the authoritative methodology for the **utility-level** EIA Form 112 pipeline:
the two-stage cleaning that turns the raw EIA-112 utility workbooks into a monthly
long-format table and then an annual, ownership-enriched summary with
disconnection-intensity rates and peer percentiles. It backs the **2024 Residential
Utility Disconnections Report**.

> **Scope note.** This pipeline is utility-level only. The separate *state/national*
> EIA-112 report (`Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-shutoffs.csv`) is produced
> by `eep-pipeline-core/processors/eia-112_processor.R` from a different raw workbook
> (`eia_112_national_shutoffs_report_2024.xlsx`) and is **not** part of this repo.

---

## 1. Overview

The pipeline produces two cleaned datasets, run in order:

| Stage | Script | Input | Output |
|-------|--------|-------|--------|
| 1 | `processors/01_eia-112-utility_processor.R` | Two raw EIA-112 utility workbooks (electric + gas) | `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-shutoffs.csv` (monthly, long) |
| 2 | `processors/02_eia-112-utility-annual_processor.R` | Stage 1 output + EIA-861 sales (ownership) + EEP bad-data flags | `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-annual.csv` (annual, enriched); `DD-MM-YYYY-eia-112-utility-bad-data.csv` (flagged rows only) |
| 3 | `processors/03_eia-112-build-workbook.R` | All three CSVs from Stages 1 and 2 (auto-detected from `Cleaned_Data/eia/112/`) | `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-workbook.xlsx` (consolidated workbook) |

Stage 1 reshapes the raw workbooks into one analysis-ready row per **utility × fuel ×
month**. Stage 2 collapses that to one row per **utility × fuel × year**, attaches an
ownership classification from EIA Form 861, derives disconnection-intensity rates, and
ranks each utility's shutoff rate against national, state, and ownership peer groups.
Stage 3 is a pure assembler — it reads the three CSVs produced by Stages 1 and 2 and
packages them into a single formatted Excel workbook for distribution.

The goal is to support utility-level analysis of residential disconnections: which
utilities disconnect most relative to their customer base, how that varies by ownership
type and geography, and how individual utilities compare to their peers.

---

## 2. Data sources

### 2.1 EIA Form 112 — utility-level workbooks (primary input, Stage 1)

- **Publisher:** U.S. Energy Information Administration (EIA)
- **URL:** https://www.eia.gov/analysis/requests/residential/utility/
- **Form instructions:** https://www.eia.gov/survey/form/eia_112/portal_instructions.pdf
- **Form status:** New survey. OMB approval October 2024; **2024 is the first reporting
  year.** Data collection ran Feb–Dec 2025; EIA processing completed Feb 2026.
- **Update frequency:** Annual.
- **Download date (2024 release):** 2026-04-16 (utility-level files added to `Data/` 2026-05-29).
- **Sector:** Residential only.

Two workbooks, one per fuel, sharing an identical 5-sheet structure:

| File | Fuel | Utilities | Sheets |
|------|------|-----------|--------|
| `eia_112_electric_utility_level_data_2024.xlsx` | Electric | ~1,333 | About, Final notices, Disconnections, Reconnections, Number of customers |
| `eia_112_natural_gas_utility_level_data_2024.xlsx` | Natural gas | ~1,028 | (same five) |

Within each metric sheet: rows 1–4 are title/blank, the real header is on **row 5**, the
first two columns are *State abbreviation* and *Utility name*, and columns *January–December*
hold the monthly values. Values are clean numeric — no thousands commas, no Q/R quality
flags (unlike the state/national report workbook).

These two utility-level files are the granular source EIA itself aggregated to produce the
national/state report (`eia_112_national_shutoffs_report_2024.xlsx`). See
`Data/eia/112/SOURCE.md` for full provenance.

**Headline 2024 figures (EIA release):** ~27.1M final notices to residential gas
customers; ~13.4M residential electric disconnections; ~11.4M residential electric
reconnections; ~1.2M residential gas reconnections.

### 2.2 EIA Form 861 — sales (ownership lookup, Stage 2)

- **Source:** `Cleaned_Data/eia/861/DD-MM-YYYY-eia-861-sales.csv` (latest auto-detected;
  produced by `eep-pipeline-core/processors/eia-861-sales_processor.R`).
- **Role:** Ownership classification only. Stage 2 reads just `state`, `utility_name`,
  and `ownership`, filtered to `year == 2024`.
- **Coverage caveat:** EIA-861 is **electric service only**. It supplies ownership for
  ~89% of electric utilities but only ~7% of gas utilities (the gas matches are combined
  electric+gas utilities such as Ameren that also appear in EIA-861). The remaining ~988
  NA utilities are filled by the EEP-determined overrides (§2.3).

### 2.3 EEP-determined ownership (manual review, Stage 2)

- **Source:** `data/eia-112-manual-ownership-overrides.csv` — committed reference CSV
  extracted from the "Assigning Ownership to NAs" sheet of
  `temp/29-05-2026-eia-112-utility-annual.xlsx`.
- **Coverage:** 988 utilities — exactly the post-861 NA set (134 electric + 854 gas).
  Zero collisions with 861-matched utilities; 861 always takes precedence.
- **Method:** EEP team manually researched each utility and assigned an ownership class.
  The four classes used are all existing EIA-861 vocabulary:

  | Class | Count |
  |-------|-------|
  | `Municipal` | 688 |
  | `Investor Owned` | 224 |
  | `Political Subdivision` | 43 |
  | `Cooperative` | 33 |

- **Parent annotation:** A `parent` column captures the parent company for ~136 utilities
  (e.g., Sempra Energy for Southern California Gas Company and Oncor Electric Delivery).
- **Provenance:** Research conducted May 2026 against the 2024 EIA-112 annual data.
  The committed CSV is maintained by hand — extend it to add/revise assignments for
  future release years.

### 2.4 EEP bad-data flags (manual review, Stage 2)

- **Source:** `data/eia-112-manual-bad-data-flags.csv` — committed reference CSV
  extracted from the "Bad or Missing Data" sheet of
  `temp/29-05-2026-eia-112-utility-annual.xlsx`, column `"BAD  / MISSING DATA FLAG"`.
- **Coverage:** 145 of 2,148 utility-year rows flagged as bad or incomplete reporting.
  All 145 join cleanly to the annual output on `(state, utility_name, energy_type)`.
- **Method:** EEP team reviewed the initial cleaned annual output and flagged rows where
  reported data was missing, anomalous, or otherwise unreliable. The `flag_reason` column
  is reserved for future annotation (currently blank).
- **Effect:** Flagged rows are retained in the annual output (all metrics intact) but
  excluded from the three `*_percentile` peer-ranking columns so bad reporting does not
  distort benchmark comparisons. A companion `data_quality_note` column is derived
  algorithmically for all rows to surface additional quality candidates.

---

## 3. Stage 1 — raw workbooks → monthly long format

Script: `processors/01_eia-112-utility_processor.R`. Run from the repo root; reads
`../../../Data/eia/112/` and writes `../../../Cleaned_Data/eia/112/`.

For each fuel, the same four metric sheets are read and joined; the About sheet is skipped.

1. **Read each metric sheet** (`read_metric()`): `read_excel(skip = 4, col_types = "text")`
   discards the four title/blank rows so row 5 becomes the header. The first two columns are
   renamed `state` and `utility_name`; only those plus the twelve `month.name` columns are kept.
2. **Drop footer/metadata rows:** keep only rows where `state` is a valid 2-character code
   (`str_length(state) == 2`) and `utility_name` is non-missing.
3. **Wide → long:** `pivot_longer()` over the twelve month columns; `month_name` is mapped to
   an integer `month` (1–12) via `match(month_name, month.name)`.
4. **Numeric coercion:** values were read as text; strip any stray commas and whitespace, then
   `as.numeric()`. (No Q/R flag handling — the utility-level files carry none.)
5. **Join the four metrics within each fuel:** `purrr::reduce(full_join, by = c("state",
   "utility_name", "month"))` over Final notices, Disconnections, Reconnections, and Number of
   customers.
6. **Stack the two fuels:** `bind_rows(electric, gas)` with `energy_type` (`"electric"` /
   `"gas"`) as a **row dimension** — avoiding duplicated `electric_*`/`gas_*` column sets.
7. **Drop `State Total` pseudo-utilities;** **retain `State Adjustment`** rows (EIA
   reconciliation rows usable to tie utility sums back to the state-level report).
8. **Add `year = 2024L`,** order columns, and `arrange(state, utility_name, energy_type, month)`.

**Cross-fuel sparsity is by design:** a utility appears in the electric file, the gas file,
or both. The stacked table is naturally sparse across fuels — not a data-quality issue.

### Stage 1 output schema (`DD-MM-YYYY-eia-112-utility-shutoffs.csv`, 9 columns)

| Column | Type | Description |
|--------|------|-------------|
| `state` | character | 2-character state abbreviation |
| `utility_name` | character | EIA-reported utility name (as-is) |
| `energy_type` | character | `"electric"` or `"gas"` |
| `year` | integer | 2024 |
| `month` | integer | 1–12 |
| `shutoffs` | numeric | Residential disconnections (Disconnections sheet) |
| `reconnections` | numeric | Residential reconnections (Reconnections sheet) |
| `final_notices` | numeric | Final notices sent (Final notices sheet) |
| `customer_count` | numeric | Residential customers (Number of customers sheet) |

Approximately 27,000 rows (utilities × present fuels × 12 months).

---

## 4. Stage 2 — monthly → annual summary with ownership & rates

Script: `processors/02_eia-112-utility-annual_processor.R`. Run from the repo root; reads
`../../../Cleaned_Data/eia/112/` and `../../../Cleaned_Data/eia/861/`. Both inputs are
auto-detected by `resolve_latest_csv()`, which scans for the `DD-MM-YYYY-<suffix>.csv`
naming convention, parses the embedded date, and selects the most recent file — no arguments
needed.

1. **Drop `State Adjustment` rows** — reconciliation pseudo-utilities, removed before any
   aggregation (`filter(utility_name != "State Adjustment")`).
2. **Monthly → annual aggregation** by `(state, utility_name, energy_type, year)`:
   - `customer_count` = `mean(na.rm = TRUE)` — the customer base is a **rate denominator**,
     not a cumulative count. A sum would inflate partial-year utilities and deflate their
     rates. Partial-year utilities keep their mean rather than being dropped.
   - `shutoffs`, `reconnections`, `final_notices` = `sum(na.rm = TRUE)` — annual totals;
     partial-year utilities keep their partial sums.
3. **Ownership join via normalized-name matching.** EIA-112 and EIA-861 utility names are not
   identical strings, so `normalize_name()` is applied to both sides before joining:
   lowercase → strip trailing state suffix (` - XX`, ` - (XX)`, ` (XX)`) → replace punctuation
   `[.,&'"]` with a space → `str_squish()` to collapse whitespace. Then
   `left_join(ownership_lut, by = c("state", "norm_name"))`; unmatched rows get
   `ownership = NA`. The lookup is built distinct so no normalized `(state, name)` key maps to
   more than one ownership value (zero collisions). Expected match: **~89% electric / ~7% gas**
   (gas is low because EIA-861 is electric-only — this is expected, not a gap).

3.5. **EEP-determined ownership fill** (`apply_eep_ownership()`). After the 861 join, 988
   utilities still have `ownership = NA`. The committed reference file
   `data/eia-112-manual-ownership-overrides.csv` (§2.3) is joined on the exact key
   `(state, utility_name, energy_type)` — no name normalization needed because the override
   keys were copied directly from the pipeline output strings. 861 takes precedence: the
   coalesce only fills rows where `ownership` is still `NA` after step 3.
   - `ownership_source` records provenance: `"eia_861"` for 861-matched utilities (~1,160),
     `"eep_determined"` for EEP-filled utilities (988), and `NA` for any remaining gaps
     (expected: ~0 after a successful override load).
   - `parent` carries the EEP parent-company annotation for ~136 utilities.
   - This step runs *before* percentile ranking (step 5) so EEP-classified utilities rank
     within their true ownership peer group rather than in the NA catch-all group.
   - A post-join anti-join warns at runtime if any override key fails to match a utility in
     the annual data (guards against name drift in future release years).

4. **Derived disconnection-intensity rates** (all guarded with `case_when` to return
   `NA_real_`, never `Inf`/`NaN`, on a zero denominator; all are fractions, not percentages):
   - `shutoff_rate = shutoffs / customer_count` — NA when `customer_count <= 0`
   - `reconnection_rate = reconnections / shutoffs` — NA when `shutoffs <= 0`
   - `final_notice_rate = final_notices / customer_count` — NA when `customer_count <= 0`

4.5. **Bad-data flags and data quality notes** (`apply_bad_data_flags()`). After rates are
   computed, the committed reference file `data/eia-112-manual-bad-data-flags.csv` (§2.4)
   is joined on the exact key `(state, utility_name, energy_type)` to add `bad_data_flag`
   (`"Y"` for 145 flagged rows; `NA` for the remaining ~2,003). Then `data_quality_note` is
   derived algorithmically for all rows:
   - `"customer_count missing"` — `customer_count` is NA
   - `"all activity metrics zero"` — shutoffs, reconnections, and final_notices are all 0
   - `"shutoff_rate exceeds 1 (shutoffs > customers)"` — shutoff_rate > 1
   - `"final notices but zero shutoffs"` — final_notices > 0 and shutoffs == 0
   - `NA` — no rule applies
   Note: the note is descriptive only — it does not override the manual `bad_data_flag`.
   A runtime anti-join warns if any flag key fails to match a row in the annual data.

5. **Percentile rankings of `shutoff_rate`** via `dplyr::percent_rank()` — ascending, so a
   higher shutoff rate yields a higher percentile (0.82 ⇒ higher than 82% of the peer group);
   0–1 scale, matching the `*_rate` columns. Three peer groups:
   - `shutoff_rate_national_percentile` — within `energy_type`
   - `shutoff_rate_state_percentile` — within `(energy_type, state)`
   - `shutoff_rate_ownership_percentile` — within `(energy_type, ownership)`; NA-ownership
     utilities (mostly gas) form their own peer group and are ranked against each other.
   Flagged rows (`bad_data_flag == "Y"`) are masked to `NA` before ranking so they are
   excluded from the peer denominator — bad reporting does not distort benchmark comparisons.
   NA-rate rows also receive NA percentiles and are excluded. Single-member groups make
   `percent_rank()` return `NaN` (0/0); these are coerced to `NA` — a percentile is
   meaningless without peers.
6. **Column reorder** to the documented 19-column schema, then write the annual CSV and a
   dedicated bad-data CSV (flagged rows only).

### Stage 2 output schema (`DD-MM-YYYY-eia-112-utility-annual.csv`, 19 columns)

| Column | Type | Description |
|--------|------|-------------|
| `state` | character | 2-character state abbreviation |
| `utility_name` | character | EIA-reported utility name (as-is) |
| `energy_type` | character | `"electric"` or `"gas"` |
| `year` | integer | 2024 |
| `ownership` | character | EIA-861 ownership class, or EEP-determined where 861 found no match; `NA` only if both sources lack a classification |
| `ownership_source` | character | `"eia_861"` / `"eep_determined"` / `NA` |
| `parent` | character | EEP-identified parent company (~136 utilities); `NA` otherwise |
| `customer_count` | numeric | 12-month mean residential customer count (rate denominator) |
| `shutoffs` | numeric | Annual sum of disconnections |
| `reconnections` | numeric | Annual sum of reconnections |
| `final_notices` | numeric | Annual sum of final notices sent |
| `shutoff_rate` | numeric | `shutoffs / customer_count`; NA when `customer_count <= 0` |
| `reconnection_rate` | numeric | `reconnections / shutoffs`; NA when `shutoffs <= 0` |
| `final_notice_rate` | numeric | `final_notices / customer_count`; NA when `customer_count <= 0` |
| `shutoff_rate_national_percentile` | numeric | `percent_rank` within `energy_type`; 0–1; NA for NA rate, n=1 group, or bad_data_flag = "Y" |
| `shutoff_rate_state_percentile` | numeric | `percent_rank` within `(energy_type, state)`; 0–1; NA for NA rate, n=1 group, or bad_data_flag = "Y" |
| `shutoff_rate_ownership_percentile` | numeric | `percent_rank` within `(energy_type, ownership)`; 0–1; NA for NA rate, n=1 group, or bad_data_flag = "Y" |
| `bad_data_flag` | character | `"Y"` for 145 EEP-flagged rows (bad/incomplete reporting); `NA` otherwise |
| `data_quality_note` | character | Algorithmically derived note for any row matching a quality rule (see §4.5); `NA` where no rule applies |

Approximately 2,148 rows (utility × fuel combinations for 2024). Ownership coverage ~100%
for both fuels after the EEP supplement.

**Ownership values:** `Investor Owned`, `Cooperative`, `Municipal`, `Political Subdivision`,
`State`, `Federal`, `Community Choice Aggregator`, `Retail Power Marketer`,
`Behind the Meter`. All values are standard EIA-861 vocabulary.

---

## 5. Stage 3 — consolidated workbook assembler

Script: `processors/03_eia-112-build-workbook.R`. Run from the repo root after Stages 1 and
2 (or independently if the three CSVs are already current — Stage 3 only reads them).
Stage 3 does not modify the CSVs; it is a pure assembler.

1. **Auto-detect inputs** — `resolve_latest_csv()` locates the latest of each:
   `*-eia-112-utility-shutoffs.csv`, `*-eia-112-utility-annual.csv`, and
   `*-eia-112-utility-bad-data.csv` from `Cleaned_Data/eia/112/`. No manual path edits needed.
2. **Split the monthly CSV** — rows where `utility_name == "State Adjustment"` go to the
   State Adjustments sheet; all other rows go to the Utility Monthly sheet.
3. **Assemble five sheets** in order: Documentation, Utility Annual, Utility Monthly,
   State Adjustments, Bad Data Flags.
4. **Documentation sheet** — a single formatted text tab (wrapped text, 55/18/80 column
   widths) containing: title block and generation date; sheet index; data sources and
   citations; per-sheet column dictionaries (sourced from this document's schemas); and
   key limitations from the EIA report methodology.
5. **Data sheets** — each receives a bold/shaded header row (`fgFill = "#D9E1F2"`), a
   frozen header row (`firstActiveRow = 2`), and auto-sized column widths.
6. **Dual-write** to `Cleaned_Data/eia/112/` and the repo-local `outputs/` folder, same
   pattern as Stages 1 and 2. The `.xlsx` is gitignored; only the `Cleaned_Data/` copy
   is synced to S3.

## 6. Output files & locations

All outputs are written to the shared `Cleaned_Data/eia/112/` directory (never committed to
this repo) with a `Sys.Date()` stamp in `DD-MM-YYYY` format:

- `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-shutoffs.csv` (Stage 1)
- `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-annual.csv` (Stage 2, all rows, 19 cols)
- `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-bad-data.csv` (Stage 2, flagged rows only, 19 cols)
- `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-workbook.xlsx` (Stage 3, consolidated workbook)

CSV schemas and per-dataset notes are mirrored in `Cleaned_Data/eia/112/CLEANED.md`. The
workbook's Documentation sheet is the in-workbook authoritative copy of the schema and is
suitable for inclusion in report appendices or data deliveries.

---

## 7. Quality flags & known caveats

- **No Q/R flags at the utility level.** The state/national report workbook carries EIA
  quality flags (`Q` = response rate < 50%; `R` = RSE > 50%), but the utility-level
  workbooks do not, so Stage 1 performs no flag extraction.
- **Gas ownership is now supplied by EEP manual review.** EIA-861 covers electric service
  only, so gas-only utilities do not match in step 3. Step 3.5 fills these via the committed
  override CSV. The `ownership_source` flag distinguishes EEP-assigned values
  (`"eep_determined"`) from 861-matched values (`"eia_861"`). EEP values are manual research
  judgments — they carry no formal verification beyond the team's review.
- **`customer_count` is a 12-month mean, not a sum.** It is a rate denominator. Utilities that
  joined or left service mid-year reflect averages over fewer than 12 active months.
- **`State Adjustment` rows** are retained in the monthly output (non-integer, possibly
  negative reconciliation values) but **dropped** in the annual summary. Filter them out for
  any utility-level analysis of the monthly file.
- **First reporting year.** 2024 is the inaugural EIA-112 year — no prior-year data exists for
  trend comparison yet.
- **Territory coverage** (PR, GU, VI) depends on EIA response rates.
- **`normalize_name()` does not strip corporate tokens** (Co, Inc, LLC, Coop). The marginal
  match gain is low and the false-match risk from stripping shared tokens is higher.
- **Reconnections may reflect prior-month disconnections**, so reconnection counts are an
  accounting-level flow, not strictly "this month's disconnections reversed."

---

## 8. Reproduction

**Requirements:** R (≥ 4.0) with `tidyverse`, `readxl`, and `openxlsx`. Raw workbooks present
in `Data/eia/112/`; a cleaned EIA-861 sales CSV present in `Cleaned_Data/eia/861/`;
`data/eia-112-manual-ownership-overrides.csv` and `data/eia-112-manual-bad-data-flags.csv`
present in the repo (both committed).

Run **from the repo root**, in order (each stage auto-detects its upstream inputs):

```bash
Rscript processors/01_eia-112-utility_processor.R
Rscript processors/02_eia-112-utility-annual_processor.R
Rscript processors/03_eia-112-build-workbook.R
```

Each script prints sanity output. Expected values for the 2024 data:

| Check | Expected |
|-------|----------|
| Stage 1 — electric utility-month rows / utilities | ~15,948 rows / ~1,145 utilities |
| Stage 1 — gas utility-month rows / utilities | ~12,288 rows / ~897 utilities |
| Stage 1 — CA electric month 6 spot-check | utility sum ≈ 33,017 + State Adjustment ≈ 586 |
| Stage 2 — total rows | ~2,148 |
| Stage 2 — columns | 19 |
| Stage 2 — rows per energy_type | ~1,226 electric / ~922 gas |
| Stage 2 — ownership non-NA rate | ~100% both fuels (after EEP supplement) |
| Stage 2 — ownership_source counts | ~1,160 `eia_861` / 988 `eep_determined` / ~0 `NA` |
| Stage 2 — ownership (electric) order | Cooperative > Municipal > Investor Owned > Political Subdivision > State > Federal |
| Stage 2 — rate NAs | `shutoff_rate` ~3, `reconnection_rate` ~77, `final_notice_rate` ~3 |
| Stage 2 — bad_data_flag counts | 145 `"Y"` / 2003 `NA` |
| Stage 2 — all bad-data flag keys matched | Console prints "All 145 bad-data flag keys matched successfully." |
| Stage 2 — bad-data CSV rows | 145 rows (146 lines incl. header) |
| Stage 2 — national percentile range | min 0, max 1 for both fuels (excludes flagged rows) |

Re-running on a later date writes new `DD-MM-YYYY-*.csv` files alongside any existing ones;
content is deterministic given identical inputs.
