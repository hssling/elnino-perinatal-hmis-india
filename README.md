# El Niño and perinatal outcomes in India: HMIS link-unit-month panel, code, results contract and aggregate data

Code, every reported number and the aggregate data of a pre-specified link-unit-month analysis of local heat, rainfall deficit and El Niño in pregnancy and reported stillbirths (rate per 1,000 total births) and low birth weight (share of weighed newborns) in India, from routine Health Management Information System (HMIS) district reports linked to stable district units, April 2012 to February 2020. Six pre-specified tests (H10a to H10c, stillbirth; H11a to H11c, low birth weight) are fitted as negative binomial models with year-month fixed effects, with negative-control exposures after birth and a selection audit.

Repository: https://github.com/hssling/elnino-perinatal-hmis-india

**Paper (manuscript; the citation will be added on publication):**
Siddalingaiah H S. Heat, rainfall deficit and El Niño in pregnancy and stillbirth and low birth weight in India: a district-level analysis of routine health information system data, 2012–2020.

Please cite the paper once it is published, and this repository through `CITATION.cff`.

## Pre-specified analysis

A results contract (`papers/F/results_keys.md`) listing every reported quantity with its definition, source, display and the verdict rules was committed before any exposure model was fitted; later changes are dated amendments in the same file. The study was not registered in an external registry. The design specification is included (the implementation plan, an internal working document, is not):

- `docs/superpowers/specs/2026-10-26-paper-f-perinatal-hmis-design.md`: design specification.
- `papers/F/results_keys.md`: the results contract and its amendments (297 keys).

Timeline, from the history of the author's working repository (first commit of each file; times are IST, UTC+05:30):

| Step | File | First commit (IST) |
|---|---|---|
| Design specification | `docs/superpowers/specs/2026-10-26-paper-f-perinatal-hmis-design.md` | 2026-10-26 16:17 (`e1c03ce`) |
| Results contract (`papers/F/results_keys.md`) | `papers/F/results_keys.md` | 2026-11-08 20:23 (`b18ec29`) |
| Release panel (`data/derived/hmis/perinatal_release_panel.csv.gz`) | `data/derived/hmis/perinatal_release_panel.csv.gz` | 2026-11-08 16:29 (`f5dbd4f`) |
| Power simulation design (`models/F/01_power.R`) | `models/F/01_power.R` | 2026-11-08 23:17 (`a50832e`) |
| First exposure model (`models/F/02_primary.R`) | `models/F/02_primary.R` | 2026-11-09 02:48 (`812f251`) |
| First results file (`papers/F/results.json`) | `papers/F/results.json` | 2026-11-09 17:17 (`5581bab`) |

**Differences from the author's working copies.** The copies here differ from the committed originals only in these ways:
- local drive paths are replaced by repository-relative ones (`<repo>`);
- e-mail addresses are removed from documents;
- notes about journal selection and submission in the design specification are replaced by the marked text "[journal-selection or submission note redacted from the public copy; not part of the analysis protocol]";
- No FY2020-21 (April 2020 to March 2021) HMIS value is included: those months come from the HMIS portal's FY2020-21 files, which state no explicit licence, so their rows were **removed** from every released table (removed from: `data/derived/hmis/perinatal_flag_report.csv` (10 rows); `data/derived/hmis/perinatal_gate_summary.csv` (9 rows)). They are used in the paper only in a sensitivity analysis; its estimates (model results, not HMIS values) are in `papers/F/output/sensitivity.csv` and `papers/F/results.json`.

Internal decision identifiers (for example "ruling", "R7" or "Task 8") refer to the author's analysis log; the decisions that affect the analysis are described in the documents themselves.

## Contents

```
./                                 11 files
data/derived/                      enso_monthly.csv
data/derived/hmis/                 6 files
                                   # release panel (small counts suppressed), climate by link unit and month, gate, flag, break and d24 reports
docs/superpowers/specs/            2026-10-26-paper-f-perinatal-hmis-design.md
models/                            .Rprofile, DESCRIPTION, renv.lock, setup.R
models/D/R/                        contract.R
models/E/R/                        common_e.R, monthly.R, power.R, secondary.R, verdicts.R
models/F/                          7 files
                                   # R analysis: run_all.R and steps 00-04
models/F/R/                        7 files
                                   # helpers: perinatal panel, power, primary and secondary fits, verdicts, results
models/common/R/                   8 files
models/common/tests/               run.R
models/common/tests/testthat/      8 files
                                   # testthat suite (Paper F tests and helpers)
models/renv/                       .gitignore, activate.R, settings.json
papers/F/                          check_results_keys.py, results.json, results_keys.md, traceability.csv
                                   # results.json, results contract, traceability table, key check
papers/F/figures/                  make_figures.py
papers/F/figures/data/             figure_1.csv, figure_2.csv, figure_3.csv, figure_4.csv
                                   # figure data
papers/F/output/                   9 files
                                   # aggregate outputs of models/F
papers/F/tables/                   make_tables.py, table1_crosswalk.md, table2_panel.md
                                   # descriptive tables and their data
papers/F/tables/data/              table2.csv
pipeline/                          14 files
pipeline/hmis/                     23 files
                                   # HMIS download, parsing, crosswalk, flags, panel, gates and the Paper F perinatal modules
pipeline/outcomes/                 __init__.py, fetch.py, gates.py, states.py
pipeline/reference/                hmis_link_units.csv, hmis_perinatal_crosswalk.csv, hmis_perinatal_reviewed.csv, hmis_sources.csv, state_frame.csv
                                   # link units, portal file list, perinatal item crosswalk and reviewed dispositions, state frame
tests/                             __init__.py
tests/hmis/                        11 files
                                   # pytest suite for the perinatal pipeline, synthetic fixtures only
tests/hmis/fixtures/               13 files
tools/                             __init__.py, build_manuscript.py
```

No manuscript text is included.

## Data

**HMIS attribution (verbatim, as the licence requires):** Health Management Information System (HMIS), Ministry of Health and Family Welfare, Government of India; via data.gov.in / hmis.mohfw.gov.in; Government Open Data License – India

The raw HMIS workbooks (Standard Reports, financial years 2012-13 to 2019-20) are **not redistributed**. They are public on the HMIS portal, https://hmis.mohfw.gov.in/ (Standard Reports); `pipeline/reference/hmis_sources.csv` lists the portal files and their URLs. The derived tables are included:

- `data/derived/hmis/perinatal_release_panel.csv.gz`: the link-unit-month panel for the analysis period, with stillbirths (`sb`), low birth weight (`lbw`) and preterm births with counts of 1 to 4 shown as "<5", **complementary suppression** (a state-month with exactly one suppressed cell also suppresses the smallest other cell, so the suppressed cell cannot be recovered from a state-month total) and rates left blank where a numerator is suppressed or a denominator is below 20. There is no total-births (`tb`) or deaths-within-24-hours (`d24`) column. Missing is an empty cell, never 0.
- `data/derived/hmis/climate_link_unit_month.csv.gz`: IMD gridded rainfall and maximum temperature aggregated to link units by month (SPI-3, heatwave days, Tmax anomaly).
- `data/derived/hmis/perinatal_gate_summary.csv`, `perinatal_flag_report.csv`, `perinatal_break_ratio_2017.csv`, `perinatal_d24_state_fy.csv`: gate, completeness, format-break and state-level deaths-within-24-hours reports.
- `pipeline/reference/hmis_link_units.csv`, `hmis_perinatal_crosswalk.csv`, `hmis_perinatal_reviewed.csv`, `hmis_sources.csv`: the link units (portal district labels mapped to stable units), the perinatal item crosswalk across the April 2017 format change, reviewed gate dispositions and the portal file list.
- `data/derived/enso_monthly.csv`: the ENSO indices.

No district-level HMIS value is included, and no FY2020-21 value (see above).

## Results

All tables are UTF-8 CSV; missing is an empty cell, never 0.

- `papers/F/results.json`: every number reported in the paper, as `{"<key>": {"value", "display", "script", "description"}}` (297 keys); `papers/F/traceability.csv` lists them with the script that wrote each; `python papers/F/check_results_keys.py` cross-checks the keys against the contract.
- `papers/F/output/`: primary estimates, trimester and timing analyses, selection audit, sensitivity analyses, secondary outcomes, power and `provenance.csv`.
- `papers/F/figures/data/`, `papers/F/tables/`: the data behind each figure and table; `make_figures.py` and `make_tables.py` draw them.

## Reproduction

This is a release copy: it has no history of the author's working repository, none of the model caches or logs, and none of the district-level model tables (`perinatal_unit_month.csv.gz`, `perinatal_model.csv.gz`) from which the models were fitted. Those tables are rebuilt from the portal files, which are not included: `python -I pipeline/hmis/run.py fetch` downloads them and the steps of `pipeline/hmis/run_f.py` (see its docstring) parse and assemble them. Requirements: Python 3.10 or later with `pip install -r requirements.txt`; R 4.5.3 with the packages of `models/renv.lock` (`cd models`, then `Rscript setup.R`).

1. **Python tests.** `python -m pytest` runs the tests of the perinatal pipeline on synthetic fixtures.
2. **Key check.** `python papers/F/check_results_keys.py` checks that `papers/F/results.json` holds exactly the 297 keys of the contract.
3. **Figures and tables.** `python papers/F/figures/make_figures.py` and `python papers/F/tables/make_tables.py` redraw them from the included data (the FY2020-21 months are not in the data).
