# Data licence

The results, aggregate data, derived tables and figure data in this repository, and any figures drawn from them, are licensed under the Creative Commons Attribution 4.0 International licence (CC BY 4.0), https://creativecommons.org/licenses/by/4.0/, subject to the third-party terms below.

Copyright (c) 2026 Siddalingaiah H S.

This covers:

- `papers/F/results.json`, `papers/F/traceability.csv`, `papers/F/output/`, `papers/F/figures/data/` and `papers/F/tables/` (results, aggregate tables, figure and table data);
- `data/derived/hmis/` (the small-count-suppressed release panel, the link-unit climate table, and the gate, flag, break and d24 reports);
- `pipeline/reference/hmis_link_units.csv`, `hmis_sources.csv`, `hmis_perinatal_crosswalk.csv`, `hmis_perinatal_reviewed.csv` and `state_frame.csv` (the link units, portal file list, perinatal item crosswalk, reviewed dispositions and the state frame);
- `data/derived/enso_monthly.csv` (the ENSO indices).

Attribution: cite the paper (see README.md) or this repository (CITATION.cff), and the original sources below.

## HMIS (Government Open Data License – India)

The HMIS-derived values (`data/derived/hmis/perinatal_release_panel.csv.gz`, the gate, flag, break and d24 reports, the figure data and every HMIS-based result) are derived from data published under the Government Open Data License – India (GODL-India, https://data.gov.in/government-open-data-license-india), which requires this attribution, reproduced verbatim:

Health Management Information System (HMIS), Ministry of Health and Family Welfare, Government of India; via data.gov.in / hmis.mohfw.gov.in; Government Open Data License – India

The raw HMIS workbooks are not redistributed; `pipeline/reference/hmis_sources.csv` lists the portal files with their URLs. The FY2020-21 files were downloaded from the HMIS portal only, which states no explicit licence, so no FY2020-21 value is released (see README.md). The release panel suppresses counts of 1 to 4 (shown "<5") with complementary suppression, so that no state-month total can be recovered. HMIS values are provisional as of the status dates recorded in the panel.

## Third-party sources

CC BY 4.0 applies to the aggregation and processing in this repository. The original data remain subject to their producers' terms, and users must also attribute them.

| Source | Producer | Terms |
|---|---|---|
| Oceanic Niño Index (traditional), Relative ONI, Niño-3.4 anomaly (`data/derived/enso_monthly.csv`) | NOAA Climate Prediction Center (https://www.cpc.ncep.noaa.gov/data/indices/) | US Government work, in the public domain in the United States; attribute NOAA CPC |
| Gridded daily rainfall (0.25°) and maximum temperature (1°), as link-unit aggregates (`data/derived/hmis/climate_link_unit_month.csv.gz`) | India Meteorological Department (IMD), Pune | Unit-level aggregates are redistributed with source citations, as in the author's companion releases (confirmed by the author, 26 October 2026); the raw grids are not redistributed. Cite Pai DS et al. 2014, MAUSAM 65(1):1–18 and Srivastava AK et al. 2009, Atmos Sci Lett 10:249–254 |
| Link-unit identifiers (`region_id` in `pipeline/reference/hmis_link_units.csv`, `gid1_members` in `pipeline/reference/state_frame.csv`) | GADM 4.1 (https://gadm.org) | GADM licence (free for academic and other non-commercial use; redistribution or commercial use needs GADM's permission, https://gadm.org/license.html); no boundaries are included |
