# data/

This directory holds pipeline-specific reference inputs that are not shared raw data
and therefore live here rather than in the workspace-level `Data/` folder.

---

## `eia-112-manual-ownership-overrides.csv`

**Purpose:** EEP-determined ownership classifications for the 988 utilities that
EIA Form 861 could not classify (EIA-861 is electric-only; gas-only utilities and
electric utilities whose names don't normalize-match get `ownership = NA` from the
861 join).

**Source:** Manual research conducted by the EEP team, recorded in the
"Assigning Ownership to NAs" sheet of `temp/29-05-2026-eia-112-utility-annual.xlsx`.
All 988 post-861 NA utilities were individually researched and assigned an ownership
class. A parent-company annotation (`parent`) was added for 136 utilities.

**Schema (5 columns, 988 rows):**

| Column | Type | Description |
|--------|------|-------------|
| `state` | character | 2-character state abbreviation |
| `utility_name` | character | EIA-reported utility name (exact match to pipeline output) |
| `energy_type` | character | `"electric"` or `"gas"` |
| `ownership_eep_determined` | character | EEP-assigned ownership class (see values below) |
| `parent` | character | Parent company name, where identified (~136 utilities); `NA` otherwise |

**Ownership values used:**

| Value | Count |
|-------|-------|
| `Municipal` | 688 |
| `Investor Owned` | 224 |
| `Political Subdivision` | 43 |
| `Cooperative` | 33 |

All four values are existing EIA-861 categories — no new vocabulary introduced.

**Join key:** `(state, utility_name, energy_type)` — exact string match; no normalization
needed because these were copied directly from the pipeline output strings.

**How it is used:** `processors/02_eia-112-utility-annual_processor.R` calls
`apply_eep_ownership()` after the EIA-861 join. EIA-861 takes precedence; EEP fills only
where `ownership` is still `NA`. The result is recorded in `ownership_source`
(`"eia_861"` / `"eep_determined"`).

**Maintenance:** If a future release year adds new utilities that remain unclassified
after the 861 join, extend this CSV by appending rows (same 5-column schema). The join
key must match the exact strings in the pipeline's annual output.

---

## `eia-112-manual-bad-data-flags.csv`

**Purpose:** EEP-determined "bad / missing data" flags for 145 utility-year rows whose
reported data is incomplete or otherwise unreliable for analysis. Flagged rows are carried
through to the annual output but excluded from percentile peer benchmarks so that bad
reporting does not distort comparisons.

**Source:** Manual review by the EEP team, recorded in the "Bad or Missing Data" sheet of
`temp/29-05-2026-eia-112-utility-annual.xlsx`, column `"BAD  / MISSING DATA FLAG"` (double
space), value `"Y"`. Extracted once using the run-once script described in the repo plan
documentation.

**Schema (5 columns, 145 rows):**

| Column | Type | Description |
|--------|------|-------------|
| `state` | character | 2-character state abbreviation |
| `utility_name` | character | EIA-reported utility name (exact match to pipeline output) |
| `energy_type` | character | `"electric"` or `"gas"` |
| `bad_data_flag` | character | Always `"Y"` — only flagged rows are stored |
| `flag_reason` | character | Reserved for future manual annotation; blank (`NA`) for all current rows |

**Join key:** `(state, utility_name, energy_type)` — exact string match; no normalization
needed because keys were copied directly from the pipeline output strings.

**How it is used:** `processors/02_eia-112-utility-annual_processor.R` calls
`apply_bad_data_flags()` after the EEP ownership step and before percentile ranking.
The join adds `bad_data_flag` (`"Y"` / `NA`) to every row in the annual output. Flagged
rows receive `NA` for all three `*_percentile` columns and are excluded from the peer
denominators. A companion `data_quality_note` column is computed independently for all
rows (including unflagged ones) to surface candidates the team may have missed. A runtime
anti-join warns if any flag key fails to match a row in the annual data (guards against
name drift in future release years).

**Maintenance:** To flag additional utilities in a future review, append rows to this CSV
(same 5-column schema). Fill `flag_reason` to record why a row was flagged. The join key
must match the exact strings in the pipeline's annual output.
