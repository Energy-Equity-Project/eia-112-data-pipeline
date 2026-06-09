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
| 2 | `processors/02_eia-112-utility-annual_processor.R` | Stage 1 output + EIA-861 sales (ownership) | `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-annual.csv` (annual, enriched) |

Stage 1 reshapes the raw workbooks into one analysis-ready row per **utility × fuel ×
month**. Stage 2 collapses that to one row per **utility × fuel × year**, attaches an
ownership classification from EIA Form 861, derives disconnection-intensity rates, and
ranks each utility's shutoff rate against national, state, and ownership peer groups.

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
  electric+gas utilities such as Ameren that also appear in EIA-861).

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
4. **Derived disconnection-intensity rates** (all guarded with `case_when` to return
   `NA_real_`, never `Inf`/`NaN`, on a zero denominator; all are fractions, not percentages):
   - `shutoff_rate = shutoffs / customer_count` — NA when `customer_count <= 0`
   - `reconnection_rate = reconnections / shutoffs` — NA when `shutoffs <= 0`
   - `final_notice_rate = final_notices / customer_count` — NA when `customer_count <= 0`
5. **Percentile rankings of `shutoff_rate`** via `dplyr::percent_rank()` — ascending, so a
   higher shutoff rate yields a higher percentile (0.82 ⇒ higher than 82% of the peer group);
   0–1 scale, matching the `*_rate` columns. Three peer groups:
   - `shutoff_rate_national_percentile` — within `energy_type`
   - `shutoff_rate_state_percentile` — within `(energy_type, state)`
   - `shutoff_rate_ownership_percentile` — within `(energy_type, ownership)`; NA-ownership
     utilities (mostly gas) form their own peer group and are ranked against each other.
   NA-rate rows receive NA percentiles and are excluded from the denominator. Single-member
   groups make `percent_rank()` return `NaN` (0/0); these are coerced to `NA` — a percentile
   is meaningless without peers.
6. **Column reorder** to the documented schema, then write.

### Stage 2 output schema (`DD-MM-YYYY-eia-112-utility-annual.csv`, 15 columns)

| Column | Type | Description |
|--------|------|-------------|
| `state` | character | 2-character state abbreviation |
| `utility_name` | character | EIA-reported utility name (as-is) |
| `energy_type` | character | `"electric"` or `"gas"` |
| `year` | integer | 2024 |
| `ownership` | character | EIA-861 ownership class, or `NA` if unmatched |
| `customer_count` | numeric | 12-month mean residential customer count (rate denominator) |
| `shutoffs` | numeric | Annual sum of disconnections |
| `reconnections` | numeric | Annual sum of reconnections |
| `final_notices` | numeric | Annual sum of final notices sent |
| `shutoff_rate` | numeric | `shutoffs / customer_count`; NA when `customer_count <= 0` |
| `reconnection_rate` | numeric | `reconnections / shutoffs`; NA when `shutoffs <= 0` |
| `final_notice_rate` | numeric | `final_notices / customer_count`; NA when `customer_count <= 0` |
| `shutoff_rate_national_percentile` | numeric | `percent_rank` within `energy_type`; 0–1; NA for NA rate or n=1 group |
| `shutoff_rate_state_percentile` | numeric | `percent_rank` within `(energy_type, state)`; 0–1; NA for NA rate or n=1 group |
| `shutoff_rate_ownership_percentile` | numeric | `percent_rank` within `(energy_type, ownership)`; 0–1; NA for NA rate or n=1 group |

Approximately 2,148 rows (utility × fuel combinations for 2024).

**Ownership values (EIA-861 2024):** `Investor Owned`, `Cooperative`, `Municipal`,
`Political Subdivision`, `State`, `Federal`, `Community Choice Aggregator`,
`Retail Power Marketer`, `Behind the Meter`, or `NA`. Electric utilities in 2024 are
predominantly Cooperative and Municipal; gas utilities are almost entirely `NA`.

---

## 5. Output files & locations

Both outputs are written to the shared `Cleaned_Data/eia/112/` directory (never committed to
this repo) with a `Sys.Date()` stamp in `DD-MM-YYYY` format:

- `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-shutoffs.csv` (Stage 1)
- `Cleaned_Data/eia/112/DD-MM-YYYY-eia-112-utility-annual.csv` (Stage 2)

Schemas and per-dataset notes are mirrored in `Cleaned_Data/eia/112/CLEANED.md`.

---

## 6. Quality flags & known caveats

- **No Q/R flags at the utility level.** The state/national report workbook carries EIA
  quality flags (`Q` = response rate < 50%; `R` = RSE > 50%), but the utility-level
  workbooks do not, so Stage 1 performs no flag extraction.
- **Gas ownership is mostly `NA` — by design.** EIA-861 covers electric service only; gas-only
  utilities cannot match. `NA` is the honest representation, not a data-quality gap.
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

## 7. Reproduction

**Requirements:** R (≥ 4.0) with `tidyverse` and `readxl`. Raw workbooks present in
`Data/eia/112/`; a cleaned EIA-861 sales CSV present in `Cleaned_Data/eia/861/`.

Run **from the repo root**, in order (Stage 2 auto-detects Stage 1's latest output):

```bash
Rscript processors/01_eia-112-utility_processor.R
Rscript processors/02_eia-112-utility-annual_processor.R
```

Each script prints sanity output. Expected values for the 2024 data:

| Check | Expected |
|-------|----------|
| Stage 1 — electric utility-month rows / utilities | ~15,948 rows / ~1,145 utilities |
| Stage 1 — gas utility-month rows / utilities | ~12,288 rows / ~897 utilities |
| Stage 1 — CA electric month 6 spot-check | utility sum ≈ 33,017 + State Adjustment ≈ 586 |
| Stage 2 — total rows | ~2,148 |
| Stage 2 — rows per energy_type | ~1,226 electric / ~922 gas |
| Stage 2 — ownership non-NA rate | ~89% electric / ~7% gas |
| Stage 2 — ownership (electric) order | Cooperative > Municipal > Investor Owned > Political Subdivision > State > Federal |
| Stage 2 — rate NAs | `shutoff_rate` ~3, `reconnection_rate` ~77, `final_notice_rate` ~3 |
| Stage 2 — national percentile range | min 0, max 1 for both fuels |

Re-running on a later date writes new `DD-MM-YYYY-*.csv` files alongside any existing ones;
content is deterministic given identical inputs.
