# Paper F: Heat, rainfall deficit and El Niño and perinatal outcomes in India's routine health information system (design)

**Status:** builder check done; the controller's rulings R1–R8 of 2026-10-26 are applied (§12). Choices the author did not make are marked *(drafter's call)* or *(controller's call, 2026-10-26)*. The builder may refine them with a dated note, and the author may override them, without re-opening the design.

**Sources.** House format and conventions: `docs/superpowers/specs/2026-10-24-paper-e-hmis-services-design.md` (Paper E spec, including §10–§12) and `papers/E/results_keys.md` (rulings F33–F61 and amendments 1–4). Feasibility numbers in §3.2 come from a read-only extraction run on 2026-10-26 over the cached portal files with `pipeline/hmis/parse.py` (`iter_members`, `parse_member`), under `python -I`, reading zips in place (scratch outputs in the session scratchpad, not committed). The builder check of 2026-10-26 raised five questions; the controller's rulings on them and on the drafter's three open questions are in §12.

**Author decisions (binding, 2026-10-26).**
- Paper F is about the **outcomes of births** (stillbirth, low birth weight, deaths within 24 hours), at **district-month**, FY2012-13 to FY2020-21, in the public HMIS.
- Exposures: local heat (heatwave days and Tmax anomaly), rainfall deficit (SPI-3) and El Niño phase (ONI, as in Paper E), over gestation (lags 0–8 months), with pre-specified summaries for the third trimester (lags 0–2) and full gestation (lags 0–8).
- Primary outcomes: H10 stillbirth rate (stillbirths per 1,000 total births, total = live + still); H11 low-birth-weight (LBW) share (LBW / newborns weighed). Secondary, descriptive only: deaths within 24 hours per 1,000 live births (reporting known to be incomplete).
- Models: count GLMMs with an offset of log(denominator), district random effects, calendar-month fixed effects, the 2017 era break and a trend; Paper E's random-effect fallback chain and optimiser handling.
- Selection threat (heat lowers institutional deliveries, Paper E): denominators from total reported births where HMIS reports both facility and home births; a sensitivity adjusting for the institutional-delivery share; a negative-control outcome or exposure.
- One Holm family over the primary hypotheses; two-sided Wald tests with direction rules; MDE by simulation; results contract `papers/F/results_keys.md` committed before any model.
- FY2020-21 values are used in analysis but never released. District outputs need a small-number rule.
- [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]
- Sole author: Dr Siddalingaiah H S.

**How the rulings read these decisions** *(controller's call, 2026-10-26)*. FY2020-21 is analysed, but as a sensitivity analysis; the primary analysis is FY2012-13 to 2019-20 (R1). "Never released" covers every public output, including the paper (R2). Deaths within 24 hours are described at national and state level only (R4).

**Working title:** *Heat, rainfall deficit and El Niño and perinatal outcomes in India's routine health information system: stillbirths and low birth weight, district-month, FY2012-13 to 2019-20, with FY2020-21 as a sensitivity analysis* *(controller's call, 2026-10-26)* [R1].

## 1. Intent and why

**Gap.** A systematic review and meta-analysis links heat exposure in pregnancy to stillbirth, preterm birth and low birth weight (Chersich et al., BMJ 2020; doi:10.1136/bmj.m3811). Indian evidence is thin:
- a temperature–stillbirth panel for one state, Bihar (Yadav & Ranjan, BMC Pregnancy and Childbirth 2026; doi:10.1186/s12884-025-08620-x);
- an NFHS-5 study of self-reported maternal complications (Chaudhary et al., iScience 2026; doi:10.1016/j.isci.2026.117349).
There is no all-India study on facility records, and none on El Niño.

**Policy hook.** The NCDC/NPCCHH "Guidance Note for States/UTs: Public Health Preparedness for El Nino Conditions" (2026; https://ncdc.mohfw.gov.in/uploads/pdf/3.%20Guidance%20note%20on%20El-Nino%20for%20States%20and%20UTs.pdf) names pregnant women and infants as priority groups but cites no Indian outcome evidence (author-verified; the drafter could not extract the PDF text, so the builder re-checks the wording before it is quoted). Heat Action Plans, LaQshya (labour-room quality, from December 2017) and PMSMA (antenatal care, from June 2016) are the programmes the findings speak to.

**What is new versus the programme's earlier papers.**
- Paper B used NFHS survey birth weight and growth with prenatal exposure (mother-reported or card weight, children alive at the survey). Paper F uses facility-and-community **reported outcomes of births**, including stillbirths, which surveys of living children cannot see.
- Paper E studied **service volumes** at **state-month**. Paper F studies **birth outcomes** at **district-month** (about 20 times more units), which is what makes a within-month, across-district contrast of local heat possible.
- Exposure is **gestational**: births in month *m* were exposed over months *m*−8 to *m*.

**Honest expectation.** Heat–stillbirth associations elsewhere are small per °C (a few per cent). Local climate varies across about 640 districts every month, so Model L (§5.3) should be well powered. The El Niño total association rests on two episodes (2014–16 and 2018–19, plus the weak 2019–20 event) and will be MDE-bounded, as in Paper E.

## 2. Goals, non-goals, anti-goals

**Goals**
1. A validated **district-month perinatal panel** on a stable district unit (§3.4), with an item crosswalk across the 2017 break, flags and completeness per cell, and the Paper E gates adapted to rates. The primary analysis uses birth months April 2012 to February 2020 (95 months). March 2020 to March 2021 are built for the FY2020-21 sensitivity analysis only *(controller's call, 2026-10-26)* [R1].
2. **Local-climate associations** (Model L) of third-trimester and full-gestation heat and rainfall deficit with stillbirth (H10) and LBW (H11), within calendar month across districts.
3. **Total El Niño association** (Model T) with the same outcomes, with inference that respects a national exposure.
4. A **selection audit**: how heat and El Niño move the denominators (total births, newborns weighed, institutional share), reported next to every outcome estimate.
5. A journal package and, on the author's go-ahead, a public code-and-aggregates release under the small-number rule (§8).

**Non-goals**
- Neonatal deaths after 24 hours, infant deaths and maternal deaths: the items change definition at the 2017 break (§3.3) and are badly under-reported; not analysed. Deaths within 24 hours are descriptive only, at national and state level *(controller's call, 2026-10-26)* [R4].
- Preterm birth as a verdict outcome: the item exists only from FY2017-18 (§3.3). It is a secondary, era-E2-only outcome with no verdict *(drafter's call)*, on April 2017 to February 2020 in the primary window [R1].
- Data that need a login, registration or API key; FY2021-22 onward; the 2023–24 El Niño (as Paper E).
- District effect maps, rankings or a vulnerability atlas (Paper D is the programme's atlas).
- Forecast models A/B/C, index comparison (ONI/RONI/Niño-3.4) as a verdict aim, and mediation of the ENSO total by local climate *(drafter's call: Papers A, C and E already cover predictive skill and mediation; Paper F keeps one total and one local estimand to stay within a 3,000–3,500-word journal limit)*. RONI appears only as a sensitivity.
- Any analysis of COVID-19 effects. COVID indicators enter only the FY2020-21 sensitivity analysis (§5.1) *(controller's call, 2026-10-26)* [R1].

**Anti-goals** (failure even if the code works)
- Reading a reporting artefact (non-reporting, catch-up, an item renumbering, a change in who gets weighed) as a change in perinatal risk. Missing is never zero.
- Treating the LBW share among **weighed** newborns as population LBW prevalence. It is a share among recorded weights, mostly facility births.
- Causal over-claiming or attributable-burden numbers ("El Niño caused N stillbirths").
- District-specific effect claims.
- Mentioning any prior paper of the author that the programme's standing disclosure rule excludes.
- Any FY2020-21 descriptive value (rate, count or completeness) in a public output (R2, §8).

## 3. Data

### 3.1 Sources (all already cached; no new acquisition)

| Window | Source (folder in `data/raw/hmis/`) | Layout | Parser |
|---|---|---|---|
| FY2012-13 to 2016-17 (E1) | `hmis_c2_3_states_months/<FY>.zip`, one SAS-HTML `.xls` per state plus `All_India.xls` | Rows = district × item; columns = the 12 months April–March plus an FY Total; **monthly values** | `parse_e1` |
| FY2017-18 to 2019-20 (E2) | same folder | As E1 with 5 splits per month (Total, Public, Private, Urban, Rural); Total kept | `parse_e2` |
| FY2020-21 (E3), sensitivity analysis only [R1] | `hmis_c2_2_states_districts_fy2021/` (456 state-month `.xlsx`, acquired for Paper E) | One month per file; column groups = the state aggregate, then each district | `parse_e3` |
| National cross-check | `hmis_c2_1_all_india/` and `hmis_c2_1_all_india_fy2021/` | State rows per month | `parse_national` |

- `hmis_c2_4_subdistricts` (Deflate64, 36.5 GB) is not used.
- Everything is read in place with `iter_members` (path-traversal guard, no extraction), under `python -I`. Raw files are untrusted data and nothing in them is executed.
- Licence and attribution exactly as Paper E (`papers/E/sources.md`): FY2012-13 to 2019-20 under the Government Open Data License – India (GODL-India); FY2020-21 portal-only, no explicit licence stated.
- The only new reference input is the GADM 4.1 India district layer already used by Paper B (local copy named in the programme memory) and the existing district climate (`data/derived/climate_district_month.csv.gz`, 666 GADM districts, 1981–2025, IMD source).

### 3.2 Feasibility results (2026-10-26)

**FY2020-21 values are withheld from this section** *(controller's call, 2026-10-26)* [R2]. This spec is part of the public release (§8), and no FY2020-21 rate, count or completeness value may be public. The withheld values stay in the private history (commit e1c03ce). District names and name counts are not values and stay.

**District-month is available directly. No fallback is needed.**
- Every member of every FY was parsed (E1: FY2012-13 to 2016-17; E2: FY2017-18 to 2019-20; item lists inspected by hand in Kerala FY2012-13 and FY2014-15 and A&N FY2018-19). Each state workbook has one row per district × item and one column per month (April–March) plus an FY Total, so the values are **monthly by district**. Nothing is cumulative and nothing is differenced (this is Paper E's §12 correction; the "upto"/cumulative layout of the spike does not occur in the files acquired).
- FY2020-21 (E3): the folder-2 state-month files carry one column group per district after the state group, so FY2020-21 is also district-month.
- Paper E already parsed every member of every FY into district-month values (`data/derived/hmis/_parts/district_month.csv.gz`, its own indicators); the same parser yields the perinatal items with no new code beyond the crosswalk rows.

**Districts in the files** (distinct state × district names with a value, M/O Defence and M/O Railways excluded):

| FY | Era | State/UT rows | Districts with data | Names new vs previous FY | Names gone |
|---|---|---|---|---|---|
| 2012-13 | E1 | 35 | 674 | – | – |
| 2013-14 | E1 | 35 | 674 | 0 | 0 |
| 2014-15 | E1 | 36 | 675 | 1 | 0 |
| 2015-16 | E1 | 36 | 697 | 32 | 10 |
| 2016-17 | E1 | 36 | 703 | 8 | 2 |
| 2017-18 | E2 | 36 | 704 | 3 | 2 |
| 2018-19 | E2 | 36 | 704 | 0 | 0 |
| 2019-20 | E2 | 36 | 704 | 0 | 0 |

The FY2020-21 (E3) files list 782 district names in 38 state/UT groups: 194 names are new and 118 have gone against FY2019-20. "New" and "gone" compare state × normalised name, so they include renames and spelling changes as well as new districts. Across the nine FYs there are 905 distinct state × normalised names.

**National totals and rates from the files** (sum of the official state rows of `All_India.xls`):

| FY | Live births (million) | Stillbirths | Stillbirths per 1,000 total births | LBW births (million) | LBW share of weighed | Weighed / live births | Institutional share of deliveries | Total births / deliveries | Deaths < 24 h per 1,000 live births | Preterm share of live births |
|---|---|---|---|---|---|---|---|---|---|---|
| 2012-13 | 20.98 | 349,566 | 16.4 | 3.14 | 0.168 | 0.89 | 0.83 | 1.06 | 1.16 | – |
| 2013-14 | 21.21 | 333,182 | 15.5 | 2.79 | 0.144 | 0.91 | 0.86 | 1.05 | 0.64 | – |
| 2014-15 | 20.77 | 316,309 | 15.0 | 2.46 | 0.128 | 0.93 | 0.87 | 1.04 | 0.64 | – |
| 2015-16 | 21.19 | 302,935 | 14.1 | 2.45 | 0.124 | 0.93 | 0.89 | 1.02 | 0.69 | – |
| 2016-17 | 20.66 | 291,860 | 13.9 | 2.33 | 0.119 | 0.95 | 0.90 | 1.01 | 0.63 | – |
| 2017-18 | 20.78 | 277,942 | 13.2 | 2.36 | 0.119 | 0.95 | 0.92 | 1.01 | 2.29 | 0.031 |
| 2018-19 | 20.89 | 272,693 | 12.9 | 2.46 | 0.123 | 0.95 | 0.93 | 1.00 | 2.33 | 0.036 |
| 2019-20 | 21.23 | 263,342 | 12.3 | 2.52 | 0.124 | 0.96 | 0.95 | 1.00 | 2.20 | 0.036 |

About 21 million live births a year are reported, with 263,000–350,000 stillbirths and 2.3–3.1 million LBW births a year; about 2.4 million stillbirths over FY2012-13 to 2019-20.

**District-month event sizes:**

| FY | Median stillbirths per district-month (IQR) | Share of district-months with 0 stillbirths | Median total births | Median LBW births |
|---|---|---|---|---|
| 2012-13 | 31 (12–57) | 3.2% | 2,162 | 219 |
| 2014-15 | 29 (12–53) | 3.7% | 2,151 | 204 |
| 2016-17 | 25 (9–49) | 5.0% | 1,972 | 205 |
| 2018-19 | 23 (7–46) | 5.4% | 1,955 | 214 |
| All nine FYs, pooled (75,804 district-months) | 25 (9–49); 10th–90th centile 2–79 | – | 2,018 | 208 |

Further facts from the same run:
- **Internal consistency.** For stillbirths, the sum of district values equals the `All_India.xls` state rows in every FY (ratio 1.000).
- **Era break in rates.** National March → April ratios: in 2017 (the format change) stillbirth rate 1.005, LBW share 1.013, weighing coverage 1.006; in the same transition of 2015, 2016 and 2018 the stillbirth-rate ratios were 1.048, 1.019 and 1.012 and the LBW-share ratios 1.038, 0.954 and 1.023. The rates show no visible step at April 2017. Total births fall to 0.81–0.86 of March every April, every year (a recurring March excess at the financial-year end); calendar-month effects absorb it, and the gate report states it.
- **Deaths within 24 h.** E1 cells are blank (not 0) in 62.5% of district-months (FY2012-13 to 2014-15) and never 0; later cells are 0 in about a quarter of district-months. The national rate jumps from 0.6–1.2 to 2.2–2.3 per 1,000 live births at the 2017 break (FY2017-18 to 2019-20), far below any plausible early-neonatal mortality. Descriptive only, at national and state level *(controller's call, 2026-10-26)* [R4].
- **Small cells** (pooled over the nine FYs). 10.9% of district-months have 1–4 stillbirths, 4.2% have 1–4 LBW births and 30.2% have 1–4 deaths within 24 h; 0.76% have fewer than 20 total births.
- **Non-state members.** The FY2019-20 "M O Defence" and "M O Railways" workbooks have no item rows and do not parse; they are excluded by name in every FY anyway (Paper E F30).
- **FY2020-21 uses later district lists.** The FY2020-21 files were regenerated by the portal (status 1 October 2024) and, judging by the names, use district lists of about 2024: 782 districts, including districts created after March 2021 (Andhra Pradesh and Telangana 44 → 59, Rajasthan 33 → 50, Chhattisgarh 27 → 33, Assam 27 → 35, Tamil Nadu 32 → 38, and the 2023 renames in Maharashtra, e.g. Chhatrapati Sambhajinagar, Dharashiv). The portal has apparently re-allocated FY2020-21 values to boundaries that did not exist in that year (§3.4 handles this).

### 3.3 Item crosswalk (`pipeline/reference/hmis_item_crosswalk.csv`, new rows)

Rows follow the Paper E format (`indicator, era, item_codes, combine, text_pattern, definition_note, verified_in_file`): a code matches only if its normalised text matches the regex, and a mismatch fails the build. Texts below are as read on 2026-10-26.

| Variable | E1 (FY2012-13 to 2016-17) | E2/E3 (FY2017-18 to 2020-21) | Harmonisation and traps |
|---|---|---|---|
| `lb` live births | 4.1.1.a "Number of male live births" + 4.1.1.b "female" (4.1.1.c is their printed total) | 4.1.1.a "Live Birth - Male" + 4.1.1.b "Live Birth - Female" | Sum a + b in both eras (additive components; F37 partial-component rule applies). 4.1.1.c is used only as an internal check in E1 |
| `sb` stillbirths | **4.1.2** "Number of still births" | **4.1.3** "Still Birth" | **Double trap: from FY2017-18 code 4.1.2 means "Pre term newborns (< 37 weeks of pregnancy)", and in E1 code 4.1.3 means "Number of Abortions (spontaneous or induced)".** Read by code alone, E1 would give abortions and E2 preterm births. The text-regex gate stops a silent swap; unit tests on an E1 and an E2 fixture assert it |
| `wt` newborns weighed | 4.2.1 "Number of Newborns weighed at birth" | 4.4.1 "Number of newborns weighed at birth" | Renumbered, same wording |
| `lbw` weight < 2.5 kg | 4.2.2 "Number of Newborns having weight less than 2.5 kg" | 4.4.2 "Number of newborns having weight less than 2.5 kg" | Renumbered, same wording |
| `d24` deaths within 24 h | 17.1 "Number of cases of Infant deaths within 24 hrs of birth" | 16.1 "Infant deaths within 24 hrs (1 to 23 Hrs) of birth" (FY2020-21: "within 24 hours (1 to 23 hours)") | E2 wording excludes the first hour explicitly. In FY2012-13 to 2014-15 the cell is blank in 62.5% of district-months and never 0, so a zero cannot be told from a missing report: descriptive only, national and state level, FY2012-13 to 2019-20. No link-unit aggregation, flags, gates, models or release *(controller's call, 2026-10-26)* [R4] |
| `home` home deliveries | 2.1.1.a (SBA) + 2.1.1.b (non-SBA) (2.1.1.c printed total) | 2.1.1.a + 2.1.1.b | Sum a + b (additive) |
| `inst` institutional deliveries | 2.2 public + 2.3 private | 2.2 "Number of Institutional Deliveries conducted (Including C-Sections)" | As Paper E `inst_del` |
| `preterm` (E2/E3 only) | not collected | 4.1.2 "Number of Pre term newborns ( < 37 weeks of pregnancy)" | Secondary, no verdict; April 2017 to February 2020 in the primary window [R1] |
| Neonatal deaths 1–4 weeks | 17.2.1–17.2.4, "24 hours to 4 weeks" by cause, with types "Up to 1 Week", "1 week & 4 weeks", "Total" | 16.2.1–16.2.3, "up to 4 weeks" by cause (sepsis, asphyxia, other; no LBW cause) | **Not harmonisable** (age window and cause list change). Not used |

Every crosswalk row must name a real cached file in `verified_in_file` before the panel is built. The national March 2017 → April 2017 ratio of each variable and of each rate is reported (as Paper E's `break_ratio_2017.csv`); a jump in a **rate** above 15% is discussed *(drafter's call; Paper E used 25% on counts)* but does not by itself exclude the outcome, because the era step (§5.1) absorbs a level shift.

### 3.4 District unit: stable GADM link units *(drafter's call)*

**Problem.** HMIS district names are free text, and districts were carved out over the window: 674 districts in FY2012-13, 704 in FY2017-18 to 2019-20 and 782 in FY2020-21 (§3.2). Changes inside FY2012-13 to 2019-20: Longding (Arunachal, 2014-15); the 21 new Telangana districts of the October 2016 reorganisation, which already appear in the FY2015-16 file and cut across the 10 old districts; West Bengal renames (2015-16) and splits (Jhargram, Kalimpong, Paschim and Purba Barddhaman, 2016-17); Kra Daadi, Namsai and Siang (Arunachal); Charkhi Dadri (Haryana, 2017-18); and renames (Gurgaon → Gurugram, Pakaur → Pakur, North Cachar Hills → Dima Hasao). FY2020-21 is on about-2024 lists (§3.2).

**Match rates (2026-10-26, state-constrained, normalised exact names against GADM 4.1 and the Paper B NFHS crosswalk):** 91.4% of district names in FY2012-13, 92.2% in FY2015-16 to 2019-20 and 80.7% in FY2020-21. Of the 199 distinct unmatched names, 81 have a within-state fuzzy match (ratio ≥ 0.75) and 118 need a manual parent assignment, most of them districts created between 2016 and 2024.

**Unit.** A **link unit** is the smallest set of GADM 4.1 districts and HMIS districts that is closed under every FY's name mapping:
1. Normalise names (case, punctuation, "district", common spelling variants) and match each HMIS state × district × FY to GADM 4.1 `region_id` (state-constrained).
2. Reuse the NFHS → GADM crosswalk of Paper B (`pipeline/reference/nfhs_district_crosswalk.csv`, NFHS-4 640 and NFHS-5 707 districts; exact 1,211, normalised 60, split 35, fuzzy 21, manual 20). NFHS-5 district names are close to the HMIS FY2019-20 list, so its `split`/`remnant` decisions carry over.
3. A district carved out after GADM's vintage (its name is not in GADM) is mapped to the GADM parent(s) it came from; the remaining names go to `pipeline/reference/hmis_district_review.csv` with a source (Census 2011 district list, LGD notification or state gazette) and a disposition.
4. Link units are the connected components of the bipartite graph of HMIS district-FYs and GADM districts. Child districts are aggregated back to the component; GADM polygons that only appear together are pooled.
5. Delhi is one GADM polygon (Paper B finding) and is one link unit. Telangana and Andhra Pradesh are separate states from June 2014 in HMIS but their districts are linked within each new state, so no state pooling is needed at district level.

**Expected size.** GADM 4.1 boundaries are of about 2014–16 vintage (Telangana 10 districts, Andhra Pradesh 13, West Bengal 20, Rajasthan 33, Chhattisgarh 27, Assam 27; 666 in all). For FY2012-13 to 2019-20 the drafter expects roughly 630–660 link units (never more than 666). Telangana will collapse into a few large units, because its 2016 districts cut across the old ones; Delhi is 1 unit, and Brihan Mumbai joins GADM's Mumbai City and Mumbai Suburban. The exact count is a contract key (`F.units.n_link`); if it falls below 600 the builder reports to the author before modelling.

**Manual-review guard** *(controller's call, 2026-10-26)* [R3]. The guard counts the FY2012-13 to 2019-20 state × name combinations that need a hand-assigned parent, out of all FY2012-13 to 2019-20 state × name combinations. Fuzzy matches accepted by the documented rule (within-state, ratio ≥ 0.75) do not count; they are listed in a review table. If that share is over 10%, the build stops and reports. The FY2020-21 manual load is reported separately and never stops the build, because FY2020-21 serves only a sensitivity analysis.

**FY2020-21 rule** *(drafter's call)*. Link units are built on FY2012-13 to 2019-20 only. This rule applies to the FY2020-21 sensitivity analysis only *(controller's call, 2026-10-26)* [R1]. A FY2020-21 district is mapped only if it lies wholly inside one link unit (same name, or a documented carve-out of a single parent district). Where a FY2020-21 district was formed from parts of two or more link units (expected in Andhra Pradesh 2022 and Rajasthan 2023), the FY2020-21 months of every link unit it touches are set to missing, not pooled, and counted in the gate report. This keeps the 2012–2020 resolution instead of coarsening nine years to fit one.

**Why not a Census-2011 district crosswalk.** It would need a Census polygon layer that the programme does not hold, and the climate layer is already on GADM 4.1 (666 districts). The link-unit rule gives the same "aggregate children back to parents" result on the boundaries the climate uses. Sensitivity: restrict to link units that are a single GADM district and a single HMIS district in every FY (no splits).

**Climate per link unit.** Area-weighted mean over member GADM districts with a non-NaN value (Paper E's `climate_units.aggregate` pattern, renormalised weights), after the reviewed QC masks (`climate_annual.apply_qc_to_month` at district level). A&N rainfall is masked (Phase 1 R19/R20): A&N enters heat terms only.

### 3.5 Flags, completeness and gates (reuse `pipeline/hmis/flags.py` and `gates.py`)

**District-month flags** per variable, unchanged from Paper E §3.6/§12.3: `negative`, `nofile`, `nonreport` (a zero where the district's FY median is ≥ 20), `catchup` (> 3× that median right after a `nonreport` month). A flagged cell is NaN, never 0. Stillbirths have a district-month median of 25 (20–31 by FY; §3.2), so the `nonreport` rule bites on them in mid-size and large districts and leaves genuine zeros in small ones.

**Rate-level plausibility** (new; *drafter's call*). On the link-unit-month after aggregation:
- `sb > lb`, `lbw > wt`, or `wt > 1.10 × lb` → mask the affected outcome (an impossible or implausible ratio);
- stillbirth rate > 100 per 1,000 total births with total births ≥ 50 → mask `sb`;
- LBW share outside its link unit's same-calendar-month within-era median ± 0.20 (absolute) with `wt` ≥ 50 → mask `lbw` *(drafter's call; a share does not scale like a count, so Paper E's 3× rule is applied to the counts and this absolute band to the share)*.

**Count plausibility (Paper E F41/F42).** A link-unit-month count above 3× its same-calendar-month within-era median (E1 = FY2012-13 to 2016-17; E2 = FY2017-18 to 2019-20; FY2020-21 compared with E2; median ≥ 20) is masked. A low below 0.33× is kept and logged (`default_keep_low`) and masked only in the `masklow` sensitivity, except that lows covering every available month (≥ 10) of a unit-FY are masked by default (`default_mask_fy_level`).

**Partial components (Paper E F37).** `lb`, `home` and E1 `inst` are additive sums: a link-unit-month where a component is missing while it is non-zero elsewhere in the same FY is masked if that happens in more than 5% of the variable's link-unit-months (otherwise reported). The `allcomp` sensitivity requires every component.

**Completeness of a link-unit-month.** The share of its member HMIS districts with a valid value for the variable. Primary: kept only if complete (all member districts valid) *(drafter's call; link units are small, so partial sums would mix coverage changes into rates)*. Sensitivity: ≥ 0.5 and scaled up.

**The 20% rule (Paper E §10.2).** An outcome with more than 20% of its primary link-unit-months (April 2012 to February 2020) gate-masked is dropped from the primary analysis and reported descriptively. A link unit with more than 20% of its months masked for an outcome is excluded from that outcome's primary model and listed *(drafter's call)*. The build halts and reports to the author if either primary outcome (`sb`, `lbw`) is dropped or if any FY of FY2012-13 to 2019-20 is wholly unusable. An unusable FY2020-21 makes the FY2020-21 sensitivity analysis `not estimable` and does not halt the build *(controller's call, 2026-10-26)* [R1].

**Gates (internal consistency, never independent validation; Paper E F35).**
- District sum vs the state row of `All_India.xls` (FY2020-21: the state column group): within 2% (counts ≥ 100) or ±5, on months with every district valid.
- The 12 months vs the FY Total column within 1% (E1/E2).
- E1 only: 4.1.1.a + 4.1.1.b = 4.1.1.c and 2.1.1.a + 2.1.1.b = 2.1.1.c within ±1.
- National total vs folder 1 within 1%.
Failures are masked, never replaced, and logged in `pipeline/reference/hmis_reviewed.csv` (new rows tagged `paper=F`).

### 3.6 Denominators and the selection problem

**Denominators.**
- Stillbirth rate: `tb = lb + sb`. HMIS items 4.1.1 and 4.1.2/4.1.3 count births reported by facilities **and** by ANMs for home births, so `tb` covers both. The ratio of `tb` to deliveries (`inst + home`) is reported per FY (§3.2) as the check that births are not facility-only.
- LBW share: `wt` (newborns weighed). Weighing is near-universal in facilities and partial at home, so this denominator is facility-weighted. Weighing coverage `wt / lb` is reported per FY and is a model covariate in a sensitivity.
- Deaths within 24 h: `lb`, at national and state level only [R4].

**Selection pathway.** Paper E found that heat and El Niño move service volumes; if hot months shift births from facilities to home, the facility-heavy LBW denominator changes composition. Pre-specified guards:
1. **Denominator models** (selection audit, no verdict): Model L and Model T with `tb`, `wt` and `inst / (inst + home)` as outcomes (NB for counts with the offset below; beta-binomial for the share). Reported beside every outcome estimate.
2. **Institutional-share adjustment** (sensitivity): add the link-unit-month institutional share (and, for LBW, weighing coverage) as covariates.
3. **Restriction** (sensitivity): link units with institutional share ≥ 0.90 in every FY, where selection by place of birth has little room.
4. **Negative-control exposure** (primary guard, part of the verdict rule, §5.5): heat and rainfall deficit in the **two months after** the birth month (leads +1 and +2) cannot cause a birth outcome in month *m*. They are entered in the same Model L.
5. **Negative-control outcome** (secondary, no verdict): male-to-female live-birth ratio (`4.1.1.a / 4.1.1.b`). Its association with third-trimester heat is expected to be null or very small (some studies report male-biased fetal loss under stress, so it is an imperfect control); a clear non-null result flags reporting or selection artefacts and is discussed *(drafter's call; the builder may replace it if the author knows a better reporting-only item)*.

**Offset for the denominator models.** No district population is on disk (the cached Census table `data/raw/outcomes/census_a02/00_A2_India.xls` is state-level only). The denominator-count models therefore use `offset(log(days_in_month))` with link-unit random intercepts and trends, and year-month fixed effects in Model L; their estimates read as relative changes in a unit's own birth counts *(drafter's call)*. A public Census 2011 district population table would allow a population offset; fetching one is the builder's call (one small file, polite rules of Paper E §3.1), not a precondition.

### 3.7 Climate and ENSO inputs

- **Local climate:** `climate_district_month.csv.gz` (columns `rain_mm`, `tmax_mean`, `heatwave_days`, `tmax_ge40_days`), aggregated to link units (§3.4). Derived per link unit: `tmax_anom` (against the unit's 1981–2010 calendar-month mean), SPI-3 (`climate_annual.spi(…, 3)`, base 1981–2010, R22 masking), `spi3_dry = min(SPI-3, 0)`.
- Lags reach back to August 2011 (lag 8 of April 2012). Leads reach forward to May 2020 in the primary window (SPI-3 at lead +3 of February 2020) and to June 2021 in the FY2020-21 sensitivity (lead +3 of March 2021). The climate file covers 1981–2025.
- **ENSO:** `data/derived/enso_monthly.csv` through `pipeline/hmis/exposure.enso_exposures` (ONI for the season ending in month *t*; `en_t = max(ONI, 0)`, `ln_t = min(ONI, 0)`; RONI likewise).
- Heatwave days are zero in 93.2% of district-months in the window (6.8% non-zero; 2026-10-26 check over 666 GADM districts, August 2011 to March 2021). That is why `tmax_anom` is the primary heat metric and heatwave days a secondary one *(drafter's call)*.

### 3.8 Output tables

- `data/derived/hmis/perinatal_unit_month.csv.gz` (git-ignored; holds FY2020-21): `link_id, state_id, fy, year, month, ym, era`, then per variable the value, completeness, flags and status dates.
- `data/derived/hmis/perinatal_model.csv.gz` (git-ignored): the above joined to exposures (lags and leads built by merging on `ym ± k`, never by `shift()`), offsets and indicators.
- `pipeline/reference/hmis_link_units.csv` (tracked): HMIS state × district × FY → `link_id`, and GADM `region_id` → `link_id`, with match type and source. Names only, no values.
- Counts and shares only in tracked reports (`data/derived/hmis/perinatal_gate_summary.csv`, `perinatal_break_ratio_2017.csv`). Their FY2020-21 rows are stripped by the release exporter (§8) [R2].
- Deaths within 24 h: a tracked national and state × FY table for FY2012-13 to 2019-20 only (`data/derived/hmis/perinatal_d24_state_fy.csv`) [R4].
- The release panel (§8): link-unit-month, FY2012-13 to 2019-20, small-number rule applied [R7].

## 4. Exposure over gestation

Births reported in month *m* were conceived around *m*−9 and exposed over months *m*−8 to *m*. Lag *k* means month *m*−*k*.

**Lag structure** *(drafter's call)*. A distributed lag over *k* = 0–8 with a **trimester-strata lag basis** (constant within lags 0–2, 3–5 and 6–8; `dlnm` `strata` basis with breaks at 3 and 6). Each exposure gets three coefficients, read as third, second and first trimester. Pre-specified summaries:
- **third trimester** = the lag 0–2 stratum, per +1 unit sustained over those three months;
- **full gestation** = the sum of the three strata, per +1 unit sustained over all nine months.
Sensitivity: a natural-spline lag basis with 4 df over lags 0–8 for `tmax_anom` (summaries computed from the same lag windows).

**Exposures.**
| Exposure | Monthly series | Gestational form |
|---|---|---|
| Heat, primary | `tmax_anom` (°C) | trimester strata, lags 0–8 |
| Heat, secondary | `heatwave_days` (days per month) | trimester strata, lags 0–8; replaces `tmax_anom`, never entered with it |
| Rainfall deficit | `spi3_dry` | SPI-3 at lags 0, 3 and 6 (non-overlapping 3-month windows covering *m*−8 to *m*: third, second and first trimester). Reported per 1 unit of deficit (SPI −1), so the effect is exp(−β) |
| El Niño phase | `en_t`, `ln_t` | mean over lags 0–8 (gestation-mean El Niño-phase ONI and La Niña-phase ONI), per +1 °C |
| Negative control | `tmax_anom`, `spi3_dry` | mean `tmax_anom` over leads +1 and +2; `spi3_dry` at lead +3 (the 3-month window *m*+1 to *m*+3) |

The ENSO exposure in the primary window, birth months April 2012 to February 2020 (gestation from August 2011), covers the same episodes as Paper E (2014–16, 2018–19, weak 2019–20). The FY2020-21 sensitivity analysis adds birth months March 2020 to March 2021 and, through `ln_t`, the La Niña of 2020–21 *(controller's call, 2026-10-26)* [R1]. Exposure descriptives (SD of each gestational term across link-unit-months, and within year-month) are contract keys.

## 5. Models (R, `models/F/`, reusing `models/common/R/` and `models/E/R/monthly.R`)

All count models are NB2 GLMMs in `glmmTMB` through `nb_spec`/`fit_nb` with the fallback chain (`us` → `diag` → `int`) and `complete_rows`, and **every fit uses Paper E's F61 optimiser limits from the start**: `glmmTMBControl(optCtrl = list(iter.max = 1e4, eval.max = 1e4))`. Convergence (positive-definite Hessian, maximum absolute gradient) is recorded per fit.

**Outcome form** *(drafter's call)*. Primary: NB2 on the count with `offset(log(denominator))` (`sb` with `log(tb)`, `lbw` with `log(wt)`), giving rate ratios (RR). Stillbirth is rare (1.2–1.6% of total births), so RR ≈ OR. Sensitivity: beta-binomial logit (`glmmTMB::betabinomial`, `cbind(y, denom − y)`), which respects the bound for the LBW share (12–17% nationally). Rows with a denominator < 20 (0.76% of district-months) are dropped from rate models and counted *(drafter's call)*.

### 5.1 Programme and period indicators

| Indicator | Months | Applies to |
|---|---|---|
| `hmis_format2017` | step from April 2017 | all (the era break) |
| `demonet` | pulse, November 2016 to January 2017 | all |
| `laqshya` | step from December 2017 | sensitivity only (facility quality) |
| `pmsma` | step from June 2016 | sensitivity only |
| `covid_mar2020` | March 2020 | FY2020-21 sensitivity model only *(controller's call, 2026-10-26)* [R1] |
| `covid_lockdown` | pulse, April–June 2020 | FY2020-21 sensitivity model only *(drafter's call; controller's call, 2026-10-26)* [R1] |
| `covid_fy2021` | step, April 2020 to March 2021 | FY2020-21 sensitivity model only *(controller's call, 2026-10-26)* [R1] |

In Model L, year-month fixed effects absorb all of these; they enter Model T only.

**Primary window** *(controller's call, 2026-10-26)* [R1]: birth months April 2012 to February 2020 (FY2012-13 to 2019-20, 95 months), as in Paper E. March 2020 is left out because of the lockdown of 25 March 2020. COVID disrupted delivery care and reporting, so it would confound a perinatal outcome. **FY2020-21 sensitivity analysis:** April 2012 to March 2021 (108 months), adding March 2020 to March 2021 with the three COVID indicators, as in Paper E's design.

### 5.2 Model T: total El Niño association (H10c, H11c)

`y_dt ~ en_gest + ln_gest + factor(moy) + t_c + hmis_format2017 + demonet + offset(log(denom_dt)) + (1 + t_c | link_id) + (1 | ym)`, plus the COVID indicators in the FY2020-21 sensitivity only [R1].

- `en_gest`, `ln_gest`: gestation means of `en_t`, `ln_t` (§4).
- The `(1 | ym)` crossed random effect is mandatory: ENSO is national, so without it about 640 units would be treated as independent replicates of each month (Paper E §5.2). Upgrade to AR(1) over `ym` if it converges; fallback iid `(1 | ym)`; final fallback a moving-block bootstrap over months (block 12, refits on the random-effect structure selected on the original rows; Paper E F57). The bootstrap uses B = 500, falling to B = 200 if its projected run exceeds 12 hours; the B used is a contract key *(controller's call, 2026-10-26)* [R6].
- Calendar-month fixed effects, a linear trend with district-level random slopes and the era step, as the author decided. No time spline (it would absorb the episodes).
- **Episode check** (part of the verdict, as Paper E H7): refit with the episode terms `en_ep1415 = en_gest × I(ep1415)`, `en_ep1819 = en_gest × I(ep1819)` and `en_other = en_gest × I(neither)` in one model, as Paper E. The indicators are set on **birth month**. Each window is Paper E's calendar window, extended to 8 months past the episode's last El Niño month (ONI ≥ 0.5 for the season ending in that month), so that it covers births whose gestation overlapped the episode *(controller's call, 2026-10-26)* [R5]:
  - `ep1415` (2014–16): birth months **October 2014 to February 2017** (last El Niño month June 2016);
  - `ep1819` (2018–20, the 2018–19 and weak 2019–20 events merged as in Paper E): birth months **September 2018 to February 2020**. Its last El Niño month is April 2020, so the extension would run to December 2020, but it stops at February 2020 under R1;
  - every other birth month goes to `en_other`, in the primary model and in the FY2020-21 sensitivity (March 2020 onward included).
  The contract writes these exact months, and a test checks them against `enso_monthly.csv`.
- Model T carries no local-climate terms (it is the total association).

### 5.3 Model L: local-climate association (H10a–b, H11a–b)

`y_dt ~ cb(tmax_anom) + cb(spi3_dry) + lead(tmax_anom) + lead(spi3_dry) + factor(ym) + offset(log(denom_dt)) + (1 + t_c | link_id) + (1 | state:ym)`

- `cb()` is the trimester-strata distributed lag (§4); heat and deficit are mutually adjusted.
- **Year-month fixed effects** replace calendar-month effects, trend and programme indicators *(drafter's call; the Paper E Model L form)*: they absorb every national shock, including El Niño itself and the 2017 break, so the contrast is between districts in the same month.
- **`(1 | state:ym)`** *(drafter's call)*: heat anomalies are spatially smooth, so neighbouring districts share errors; a state × month random effect stops 30–75 districts per state being counted as independent within a month. Fallback if it does not converge: drop it and use a cluster bootstrap by state (resampling states, refits on the selected structure). The bootstrap uses B = 200, falling to B = 100 if its projected run exceeds 12 hours; the B used is a contract key *(controller's call, 2026-10-26)* [R6]. The contract records which was used.
- Sensitivity: state × calendar-month fixed effects (region-specific seasonality) added.

### 5.4 Secondary models (no verdict)

1. **Preterm** (April 2017 to February 2020 in the primary window [R1]; per live birth): Model L only (three years cannot support Model T).
2. **Denominator and selection models** (§3.6).
3. **Heatwave days** in place of `tmax_anom`.
4. **Per-trimester coefficients** (all three strata) for every exposure, shown as a figure.

Deaths within 24 h are not modelled. They are described at national and state level for FY2012-13 to 2019-20, showing the 2017 step, and the paper states the national rate (§3.2) against external early-neonatal estimates, so the reader sees the under-reporting *(controller's call, 2026-10-26)* [R4].

### 5.5 Hypotheses and verdict rules (fixed in `papers/F/results_keys.md` before any model runs)

Programme numbering continues from Paper E (H7–H9).

**H10 (stillbirth).** Stillbirth rates are higher after (a) third-trimester heat, (b) full-gestation rainfall deficit, and (c) a gestation spent in the El Niño phase.

**H11 (low birth weight).** The LBW share among weighed newborns is higher after (a) full-gestation heat, (b) full-gestation rainfall deficit, and (c) a gestation spent in the El Niño phase.

*(Drafter's call on windows: the stillbirth–heat association in the review is strongest close to delivery, so H10a uses the third trimester; birth weight integrates growth over the pregnancy, so H11a uses full gestation. Deficit acts through food, water and infection over months, so both use full gestation. The other window of each pair is reported with no verdict.)*

**One Holm family of six tests:** H10a, H10b, H10c, H11a, H11b, H11c. All p-values are two-sided Wald p-values. Hypothesised direction: RR > 1 per +1 °C (`tmax_anom`), per SPI −1 (deficit) and per +1 °C (`en_gest`).

**Per test, `consistent with` if and only if:**
- (i) Holm-adjusted p < 0.05 and the estimate is in the hypothesised direction; **and**
- (ii) for the local tests (a, b): the matching negative-control lead in the same model does **not** have a 95% CI excluding 1 in the same direction (a lead "signal" means residual confounding, and the test reads `not consistent with (negative control failed)`); **and**
- (iii) for the El Niño tests (c): both episode-specific RRs (`ep1415`, `ep1819`, on the birth-month windows of §5.2 [R5]) are in the hypothesised direction (point estimates).

Otherwise `not consistent with`. **H10** and **H11** overall are `consistent with` if at least one of their tests is, and the verdict text names which. A failed fit gives `not estimable (<reason>)`, which counts as not consistent (Paper E F56 scope: only genuine estimation failures).

**Reading rules (fixed in the contract; no verdict).**
- If a local-heat result is `consistent with` but the selection audit shows heat lowering `wt` or the institutional share **and** the institutional-share-adjusted estimate moves more than halfway to 1, the Discussion must say selection may explain part of it.
- If H10c/H11c is `consistent with` but the local-climate associations are null, the Discussion says the total may reflect coincident national events (Paper E reading rule for Model S).
- Deaths within 24 h, preterm and every sensitivity carry no verdict.

**Fixed vocabulary:** `consistent with` / `not consistent with`; null displays `not estimable (…)`, `not estimated (…)`, `not applicable (…)`, `not available (…)` as in Paper E.

### 5.6 Power and MDE (by simulation; after the contract commit, before any exposure model is read)

Everything in this section is fixed in the contract before any exposure model is read *(controller's call, 2026-10-26)* [R6].

**Step 1: timing.** Before the power design is written into the contract, the builder times one primary Model L fit and one primary Model T fit, and the simplified simulation fits below. The timings go into the contract's disclosure paragraph. The timing fits produce no exposure estimate: only the wall time, the random-effect step reached and convergence are kept.

**Simulation design** (Paper E §7, F47 pattern): fit each simulation model without the tested exposure, redraw the random time effects where the model has them, inject RRs, draw NB2 counts, refit, and count rejections (two-sided p < 0.05 and the hypothesised sign). The simulation uses a **simplified model**:
- link-unit random intercepts only (no random slopes);
- no `(1 | state:ym)`;
- time effects as in Paper E's iid fallback: iid `(1 | ym)`, redrawn per simulation, in Model T; Model L keeps its year-month fixed effects.

The MDE is therefore labelled "optimistic: simulated on a simplified model".

**Grid and size.** 200 simulations per test × RR grid point, in parallel:
- Model L, heat (per +1 °C sustained): RR 1.01, 1.02, 1.03, 1.05.
- Model L, deficit (per SPI −1 sustained): RR 1.01, 1.02, 1.03, 1.05.
- Model T, El Niño (per +1 °C gestation mean): RR 1.02, 1.05, 1.10, 1.20.

**If the projected run is over 24 hours,** the builder applies these in order:
1. drop to 100 simulations;
2. reduce every test's grid to RR {1.03, 1.05, 1.10}. (R6 gives {0.90, 0.95, 0.97} for a hypothesised RR < 1; all six Paper F tests hypothesise RR > 1, so that grid is not used.)

Tests are never dropped from the simulation. If the projection is still over 24 hours after both steps, the builder stops and reports before running. The number of simulations and the grid used are contract keys.

**MDE** = the RR closest to 1 with power ≥ 0.80; otherwise `not reached at RR <largest>`. Per test at α = 0.05, not Holm-adjusted (optimistic for a six-test family; stated).

Event sizes for orientation are in §3.2 (about 263,000–350,000 stillbirths and 2.3–3.1 million LBW births a year nationally; median 25 (IQR 9–49) stillbirths per district-month).

### 5.7 Sensitivity analyses (no verdicts)

1. FY2020-21: April 2012 to March 2021 with the COVID indicators and the §3.4 FY2020-21 unit rule *(controller's call, 2026-10-26)* [R1]. Only its model estimates (RRs, CIs, p-values) are public [R2].
2. Beta-binomial outcome model.
3. Institutional-share (and, for LBW, weighing-coverage) adjustment.
4. Restriction to link units with institutional share ≥ 0.90 in every FY.
5. Completeness ≥ 0.5 with scaling; `masklow`; `allcomp`.
6. Single-district link units only.
7. Natural-spline lag basis (4 df) for heat.
8. Heatwave days in place of Tmax anomaly.
9. State × calendar-month fixed effects (Model L).
10. Era-specific link-unit intercepts in place of the single era step (Model T).
11. `laqshya` and `pmsma` added (Model T).
12. RONI in place of ONI (Model T).
13. Dropping each El Niño episode window (§5.2) in turn (Model T).
14. Excluding the small UTs (LD, AN, DNH_DD, CH, PY) and link units with median total births < 100 a month.

## 6. Results contract, traceability, outputs

- **Contract first.** `papers/F/results_keys.md` is committed **before** any script under `models/F/` fits an exposure term, in Paper E's format: conventions, `fmt_*` displays, key table (meaning, unit, producer, display, target section), verdict rules verbatim, sentence templates, and a disclosure paragraph listing what was known (the panel, gate tables, denominator descriptives, and the timings of the §5.6 timing fits; no exposure estimates) [R6].
- The contract fixes the power design, the fallback steps and the bootstrap sizes of §5.2, §5.3 and §5.6, and the exact episode birth months of §5.2 [R5, R6].
- Later changes are dated amendments, committed before the producing step, and add no verdicts (Paper E amendments 1–4 pattern).
- **Keys** use the namespace `F.`, for example `F.panel.n_unit_months`, `F.units.n_link`, `F.national.sbr.<fy>`, `F.l.<out>.heat_t3.rr`, `F.l.<out>.heat_t3.lead_rr`, `F.t.<out>.en.rr`, `F.t.<out>.en.ep1415`, `F.h10.verdict`, `F.h10a.verdict`, `F.sel.<denom>.heat_t3.rr`, `F.power.<test>.mde`, `F.sens.<out>.<name>`.
- **FY2020-21 in the keys** *(controller's call, 2026-10-26)* [R2]. `F.national.*` and `F.panel.*` keys cover FY2012-13 to 2019-20 only and end at February 2020; the FY2019-20 values cover April 2019 to February 2020 and say so. The FY2020-21 sensitivity gives model estimates only (RR, CI, p). No key holds a FY2020-21 rate, count or completeness value.
- **Compute keys** [R6]: the timing of each timing fit, the number of simulations and the RR grid used, and the bootstrap B used per model and outcome.
- `models/F/*_results.R` writes `papers/F/results.json` via `res_entry()`/`write_results()`; `tools/build_manuscript.py` fails on a missing key; `papers/F/check_results_keys.py` cross-checks.
- **Figures.**
  1. National monthly stillbirth rate and LBW share, April 2012 to February 2020 (it may end at March 2020), El Niño months shaded, April 2017 line, and a note that FY2020-21 was analysed as a sensitivity analysis *(controller's call, 2026-10-26)* [R2].
  2. Per-trimester RR curves (heat, deficit) for both outcomes, with the negative-control leads.
  3. Forest plot: the six primary tests, plus the selection-audit estimates beside them.
  4. Completeness heatmap, link unit × month, April 2012 to February 2020, with the same note (supplement) [R2].
- **Tables.**
  1. Item crosswalk and definitions.
  2. Panel description by FY, FY2012-13 to 2019-20 (FY2019-20 to February 2020), with the same note [R2]: districts, link units, births, stillbirths, rates, weighing coverage, institutional share.
  3. Primary estimates and verdicts.
- **Supplement:** sensitivities; the denominator models; deaths within 24 h (national and state, FY2012-13 to 2019-20, descriptive [R4]) and preterm; link-unit crosswalk summary; gate report (FY2012-13 to 2019-20 [R2]); MDE simulation; RECORD checklist.

## 7. Reporting

RECORD (STROBE extension for routinely collected data), ecological time-series design stated as such; the programme's "Not applicable" ethics wording for aggregated public data; AI-use disclosure as in Papers A–E. Related manuscripts (Papers B and E) disclosed as the journal requires.

## 8. Release and data governance

- **FY2020-21 is never public** *(controller's call, 2026-10-26)* [R2]. No FY2020-21 HMIS descriptive value (rate, count or completeness, at national, state or unit level) appears in the manuscript, the supplement, the figures, the figure or table data, `results.json` or the release. Only model estimates from the FY2020-21 sensitivity analysis appear (RRs, CIs and p-values), as in Paper E v1.0.1. The exporter follows Paper E's `FY2021_STRIP` pattern: it strips every FY2020-21 row from every released CSV, and its guard reads every released file. A test covers the guard.
- **Raw HMIS files** are not redistributed; the repository gives URLs, retrieval dates, SHA-256 and scripts (already in `data/MANIFEST.csv`).
- **Link-unit-month counts, FY2012-13 to 2019-20** *(drafter's call; kept as the controller's call, 2026-10-26)* [R7]. The counts are already public under GODL-India, so release is lawful. They are aggregate counts with no person-level information, Paper E released at state-month level, and the unit-month panel is what makes the paper reproducible. But stillbirths are sensitive, and small cells in small districts can point to individual families (10.9% of district-months have 1–4 stillbirths, §3.2). Rule for the released link-unit-month panel:
  - `sb`, `lbw` and `preterm` counts of 1–4 are shown as `<5`; zeros are shown *(controller's call, 2026-10-26)* [R9]. Under R4 no unit-month `d24` is released.
  - Complementary suppression: if exactly one link unit in a state-month is suppressed for a variable, the next-smallest non-zero cell of that variable in the same state-month is also shown as `<5`, so the cell cannot be recovered from the state total.
  - Rates are not released for suppressed cells or for cells with a denominator < 20.
  - Denominators (`lb`, `wt`, `inst`, `home`) are released unsuppressed. `tb` is not released, because `tb − lb` would give `sb` back *(planner's fix, 2026-10-26)*.
  - The suppression is applied by the exporter and checked by a test (no released cell 1–4 in the three variables; no state-month with exactly one suppressed cell).
- **Release** only on the author's go-ahead: public repository `hssling/elnino-perinatal-hmis-india` *(drafter's call on the name)*, history-collapsed single commit and blob scan (`tools/export_release_e.py` pattern), GODL-India attribution and a Zenodo DOI.

## 9. [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]

Excluded: [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]

| # | Journal | Fee evidence (read without logging in) | Fit and format |
|---|---|---|---|
| 1 | [journal-selection or submission note redacted from the public copy; not part of the analysis protocol] | | |
| 2 | [journal-selection or submission note redacted from the public copy; not part of the analysis protocol] | | |
| 3 | [journal-selection or submission note redacted from the public copy; not part of the analysis protocol] | | |

[journal-selection or submission note redacted from the public copy; not part of the analysis protocol]

**Order** [journal-selection or submission note redacted from the public copy; not part of the analysis protocol]

## 10. Limitations to state; risks

**Limitations:** public-sector-dominated, provisional data; facility-weighted LBW denominator; stillbirths under-reported for home births and possibly misclassified with early neonatal deaths; deaths within 24 h grossly incomplete; gestational age unknown, so the lag window assumes term births (preterm births had shorter exposure; preterm is E2-only); ecological exposure at district level; two El Niño episodes; GADM boundaries and child-district aggregation; the COVID year only as a sensitivity analysis; no 2023–24 data.

| Risk | Mitigation |
|---|---|
| Item 4.1.2 silently read as stillbirths in E2 | Code + text-regex gate; unit test on a FY2018-19 fixture |
| District name matching takes too long | Reuse Paper B's NFHS crosswalk; normalised exact match first; review file with sources; stop and report if more than 10% of FY2012-13 to 2019-20 state × name combinations need a hand-assigned parent (§3.4) [R3] |
| Model size (≈ 61,000 rows, ~640 random intercepts, 94 year-month FE in the primary window) | F61 limits from the start; `state:ym` fallback to cluster bootstrap; timing fits before the contract [R6] |
| Selection by place of birth | Denominator audit, adjustment, restriction, negative controls (§3.6) |
| Residual seasonal confounding of heat | Year-month FE; state × calendar-month FE sensitivity; negative-control leads in the verdict |
| Power simulation runtime | Simplified simulation model; 200 sims, then 100, then a 3-point grid if projected > 24 h; never fewer tests (§5.6) [R6] |
| A FY2020-21 value leaks into a public output | Exporter `FY2021_STRIP` guard on every released file, with a test (§8) [R2] |
| Disk (D: has about 7 GB free) | Stream from zips; derived CSVs only; the panel is small |

## 11. Timeline (from 27 October 2026; the ASO 2026 refreshes of Papers A and D in early November take priority)

| Week | Work |
|---|---|
| 1 | Crosswalk rows with fixtures; district link units; flags, gates, panel; climate per link unit |
| 2 | Timing fits; contract commit; power simulation; Model L and Model T; selection audit |
| 3 | Sensitivities; manuscript, figures, supplement; journal check; package; final review |

## 12. Decisions made without the author

The author asked the team to skip questions. The controller decided each item below on 2026-10-26, after the builder check. The author can overturn any of them.

- **R1. Primary window.** Births April 2012 to February 2020 (FY2012-13 to 2019-20) are primary; FY2020-21 with the COVID indicators is a sensitivity analysis, as in Paper E.
- **R2. FY2020-21 never public.** No FY2020-21 rate, count or completeness value appears in any public output; only its model estimates do, and the exporter strips and guards FY2020-21 rows.
- **R3. Manual-review guard.** The 10% stop counts FY2012-13 to 2019-20 state × name combinations that need a hand-assigned parent; fuzzy matches and the FY2020-21 load do not count.
- **R4. Deaths within 24 h.** National and state level only, descriptive, FY2012-13 to 2019-20; no unit-month models, gates or release.
- **R5. Episode windows.** Set on birth month and extended 8 months past each episode's last El Niño month: October 2014 to February 2017 and September 2018 to February 2020; all other months are `en_other`.
- **R6. Compute budget.** Time the fits first; simulate on a simplified model (200 sims, then 100, then a 3-point grid; never fewer tests); bootstraps B = 500 → 200 (Model T) and 200 → 100 (Model L), all fixed in the contract.
- **R7. Release.** Release the FY2012-13 to 2019-20 link-unit-month panel with `<5` and complementary suppression of stillbirths and LBW.
- **R8. Journal order.** [journal-selection or submission note redacted from the public copy; not part of the analysis protocol].
- **R9. Preterm in the release; title.** Preterm counts (from April 2017) take the same `<5` and complementary suppression as stillbirths and LBW. The working title drops "early newborn deaths", which are now national and state descriptives only (R4).
- **Planning rulings (2026-10-26).**
  - If the power projection is still over 24 hours after both R6 reductions, stop and report to the author.
  - The Model L bootstrap uses the same 12-hour projection trigger as Model T.
  - Single-unit state-months are exempt from complementary suppression and listed, and no output releases state-month `sb`, `lbw` or `preterm` totals.
  - FY2020-21 district-name counts are metadata, not values.
  - Programme-event months stay provisional until the author confirms them (AUTHOR_ACTIONS).

## 13. Left to the builder

The fixture cuts; name-normalisation rules and the review file; whether to fetch a Census 2011 district population table (§3.6); the AR(1) vs iid time effect in the primary Model T fit; the exact `nonreport` behaviour for small link units; compute budgeting within R6; the plan's task split (expected: crosswalk and fixtures → link units → panel and gates → timing → contract → power → models → sensitivities → manuscript → package and release).
