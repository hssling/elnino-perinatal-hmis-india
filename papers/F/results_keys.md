# Paper F: results contract (`papers/F/results.json`)

This contract lists every key that the Paper F scripts write to `papers/F/results.json` (297 keys). The design is `docs/superpowers/specs/2026-10-26-paper-f-perinatal-hmis-design.md` (§5.5 hypotheses and verdicts, §5.6 power, §12 rulings R1–R9 and the planning rulings are binding); the plan is `docs/superpowers/plans/2026-10-26-paper-f-perinatal-hmis.md`; the controller rulings are in the Paper F SDD ledger (`progress.md`). Entries use the Paper 0 schema `{"<key>": {"value", "display", "script", "description"}}`, written with `res_entry()` / `write_results()` (`models/common/R/results.R`). The producing scripts are `models/F/01_power.R` (§9, run first), `models/F/02_primary.R` (§5–§7), `models/F/03_secondary.R` (§8, §10, §11), `models/F/00_timing.R` (§4, already run) and `models/F/04_results.R` (§1–§3, §12, and the assembly through `models/F/R/results_f.R`). `04_results.R` stops unless the keys written equal `contract_keys("../papers/F/results_keys.md", prefix = "F")`. `tools/build_manuscript.py` fails on a missing key or a null display, and `papers/F/check_results_keys.py` cross-checks the manuscript placeholders against this file.

**What was known when this contract was written (disclosure; resolution (plan, 2026-10-26); R6).** This file was committed alone, before any exposure model existed under `models/F/` and before any model with a climate or ENSO term was fitted to an HMIS outcome. The following were known:
- **The panel and the link units** (`data/derived/hmis/perinatal_unit_month.csv.gz`, `perinatal_model.csv.gz`, `pipeline/reference/hmis_link_units.csv`): 657 stable GADM link units covering all 666 GADM districts, six of them with more than one GADM district (largest: five); R3 manual-review share 52 of 716 state × name combinations (0.0726; limit 0.10); 67 accepted fuzzy matches in `perinatal_fuzzy_matches.csv`, 36 of them in FY2012-13 to 2019-20; Delhi is one link unit.
- **The gate and flag reports** (`perinatal_gate_summary.csv`, `perinatal_flag_report.csv`, `perinatal_ghost_members.csv`, the Paper F section of `data/derived/validation_report.md`): no primary outcome dropped (stillbirth `sb` masked share 0.41%, LBW `lbw` 2.48% over the 95-month window); 0 link units excluded for `sb` and 7 for `lbw`; 36 ghost district-FYs excluded from completeness; no FY of FY2012-13 to 2019-20 unusable. Status dates 19 September 2015 to 6 November 2020 in the primary window.
- **The national March→April 2017 ratios** (`perinatal_break_ratio_2017.csv`): stillbirth rate 1.005, LBW share 1.014, weighing coverage 1.006; none beyond the 15% rate band.
- **The release panel** (`perinatal_release_panel.csv.gz`), its suppression counts, and **the denominator descriptives** (national rates by FY, institutional share, total births per delivery, deaths within 24 h at national and state level), all from the HMIS files alone.
- **The exposure descriptives** (Task 6): the SD of each model-table gestational term across link-unit-months and its within-year-month SD (the derived `tmax_gest` and `spi3_dry_gest` SDs were not computed; zero for the ENSO terms, which are national series). They are keys (§3); no exposure coefficient is involved.
- **The Task 7 timings** (`papers/F/output/timing.csv`; one fit each, outcome `sb`, exposures permuted within link unit, so no coefficient carries exposure information and none was read): primary Model L 17.4 minutes (unit random effect `us`, state-month random effect converged); primary Model T 6.0 minutes (`ar1` time effect, `us`); simulation Model L 12.8 minutes (`int`); simulation Model T 5.4 minutes (`int`, `iid`). All four converged. `lbw` was not timed; the simulation projection uses the `sb` timings for both outcomes (§4).
- **The power-simulation design** (spec §5.6, fixed below) and the published results of Papers A–E on other outcomes.

No climate or ENSO estimate on an HMIS outcome was computed, plotted or seen: no model containing `tmax_*`, `spi3_*`, `hw_*`, a lead, `en_gest`, `ln_gest` or an ENSO or local-climate term had been fitted to an HMIS outcome, and Tasks 1–7 computed no such association.

Later additions are dated amendments, committed before the step that produces them runs, and add no verdict.

**Key notation and parsing (resolution (plan, 2026-10-26), as Paper E F20).** In the key tables, `{a,b,c}` expands shell-style to one key per alternative. There is no nesting; two or more consecutive brace groups expand as a product. In prose, `<O>`, `<S>`, `<D>`, `<H>` and `<FY>` stand for one member of:
- `<O>` = `{sb,lbw}` (the two outcomes: stillbirth, low birth weight);
- `<S>` = `{heat_t3,heat_gest,dry_gest}` (the three Model L summaries);
- `<D>` = `{tb,wt,inst_share}` (the three selection-audit denominators);
- `<H>` = `{h10a,h10b,h10c,h11a,h11b,h11c}` (the six tests);
- `<FY>` = `{fy1213,fy1314,fy1415,fy1516,fy1617,fy1718,fy1819,fy1920}` (financial years, `fy1213` = FY2012-13; the form has no hyphen because `tools/build_manuscript.STRICT_KEY` allows none).

`04_results.R` reads this file with `contract_keys(path, prefix = "F")` from `models/D/R/contract.R` (sourced read-only). Every backticked `F.` token in the first cell of a table row that starts with `` | `F. `` is a key, after brace expansion. Only key tables have such rows. The number of keys in each section is stated in its heading, and the sections sum to the 297 keys above.

## Conventions

| Format | Display example | Rule |
|---|---|---|
| `rr_ci` | `1.02 (95% CI 0.98–1.06)` | `fmt_ci(est, lo, hi, digits = 2)`. En dash between bounds. Ratios are never negative. |
| `p` | `0.012`, `<0.001` | `fmt_p(p)`: three decimals, `<0.001` below 0.001, no "P=". The p of a bootstrap step is a Wald p from the bootstrap SE (rule below) and has no floor. |
| `int` | `62,952` | `fmt_int(x)`. |
| `num2`, `num3` | `1.05`, `0.555` | `fmt_num(x, 2)`, `fmt_num(x, 3)`; U+2212 for minus. |
| `pct0`, `pct1`, `pct2` | `85%`, `98.5%`, `0.41%` | `fmt_pct(x, digits)`; `x` is a proportion. |
| `date` | `19 September 2015` | Day, full month name, year. |
| text | as given per key | Fixed vocabulary only, as listed. |

**Value, description and not-estimable displays.**
- `value` is the point estimate on the display scale (an RR, not a log coefficient), the count, the proportion or the text token. `description` carries the model, the rows, the random-effect step used, the full-precision estimate, its bounds, the log-scale coefficient and SE to 6 significant digits, and the seed where relevant. `script` is the producing R script.
- **The fixed vocabulary** (spec §5.5): verdict keys hold only `consistent with`, `not consistent with` or, for a local test whose negative control failed, `not consistent with (negative control failed)`. An estimate or p key that cannot be produced holds `not estimable (<reason>)`. Other null displays are `not estimated (<reason>)`, `not applicable (<reason>)` and `not available (<reason>)`, each with `value` null.
- **Not-estimable tests (spec §5.5; Paper E F18, F56).** For a not-estimable test, the estimate and p keys read `not estimable (<reason>)` and the verdict key reads `not consistent with`. Only a genuine estimation failure (no unit random-effect structure converges, a term is not estimated, or a bootstrap fails the 10% rule) makes a test not estimable; any other error (a missing column, no complete rows, a programming error) stops the run. `<reason>` is the first line of the error or `no converged time random effect`.
- **Climate precision.** Link-unit climate values in `climate_link_unit_month.csv.gz` are written at `%.5g` (about 1e-4 relative rounding); every exposure built from them inherits that rounding, and no key depends on it beyond the fifth significant digit.

## Common definitions

- **Data.** `data/derived/hmis/perinatal_model.csv.gz` (git-ignored), read by `read_perinatal_model()` with factors `unit_id` (= `link_id`), `state_unit`, `moy`, `ym_f` (every `ym` of the window in time order), `national` (constant), `state_ym` and `unit_era` (= `unit_id` × `era_e2`, used only by the `era_int` sensitivity). The **primary window** is the 95 birth months April 2012 to February 2020 (`in_primary == 1`). March 2020 lies outside it (lockdown of 25 March 2020; R1). FY2020-21 (March 2020 to March 2021 births) enters only the `fy2021` sensitivity.
- **Link units.** The 657 connected components of the bipartite graph of HMIS district-FYs (FY2012-13 to 2019-20) and GADM 4.1 districts (spec §3.4). Units leave a model only through `outcome_rows()` and the NA rule, never by hand, except where a sensitivity says so. Missing is never zero.
- **Outcomes.** `sb` (stillbirths; denominator total births `tb` = `lb` + `sb`; offset `log_tb`) for H10; `lbw` (newborns weighing < 2.5 kg; denominator newborns weighed `wt`; offset `log_wt`; the share is among weighed newborns) for H11. Model rows are the unit-months with a non-missing outcome, `excluded_<O> == 0` (gate exclusion, including link units with more than 20% of months masked) and `small_denom_<O> == 0` (denominator ≥ 20).
- **Exposures (spec §4).** Birth month *m* is exposed over months *m*−8 to *m*; lag *k* is month *m*−*k* and a lead +*j* is month *m*+*j*, all built by merging on `ym ± k`, never by `shift()`; a term with any missing month is NaN.
  - `tmax_t3`, `tmax_t2`, `tmax_t1`: means of `tmax_anom` (°C, against the unit's 1981–2010 calendar-month mean) over lags 0–2, 3–5 and 6–8 (third, second, first trimester strata).
  - `spi3_dry_l0`, `spi3_dry_l3`, `spi3_dry_l6`: `spi3_dry = min(SPI-3, 0)` at lags 0, 3, 6 (non-overlapping 3-month windows: third, second, first trimester).
  - Negative controls: `tmax_lead12` (mean `tmax_anom` over leads +1 and +2) and `spi3_dry_lead3` (`spi3_dry` at lead +3).
  - `en_gest`, `ln_gest`: means over lags 0–8 of `en_t = max(ONI, 0)` and `ln_t = min(ONI, 0)` (traditional ONI for the season ending in the month; per +1 °C).
  - Derived for the SD keys: `tmax_gest` = mean of `tmax_t3`, `tmax_t2`, `tmax_t1`; `spi3_dry_gest` = mean of `spi3_dry_l0`, `spi3_dry_l3`, `spi3_dry_l6`; built by `exposure_keys()` as row means, NaN if any stratum is NaN.
- **Sustained-exposure summaries (`SUMMARIES` in `models/F/R/perinatal.R`).** `heat_t3` = `exp(β[tmax_t3])`, per +1 °C sustained over the third-trimester months; `heat_gest` = `exp(Σβ)` over the three heat strata, per +1 °C sustained over all nine months; `dry_gest` = `exp(−Σβ)` over the three SPI terms, **per SPI −1 (one unit more deficit) sustained over gestation**, with the bounds swapped, so that β > 0 of the deficit terms reads RR > 1, the same direction as heat. Each carries its matching negative-control lead (`tmax_lead12` for the heat summaries, `spi3_dry_lead3` for `dry_gest`, oriented the same way). CIs are Wald (`lin_comb`), or percentile under a bootstrap step.
- **The six tests (`TESTS` in `perinatal.R`).** H10a: `sb`, Model L, `heat_t3`. H10b: `sb`, Model L, `dry_gest`. H10c: `sb`, Model T, `en`. H11a: `lbw`, Model L, `heat_gest`. H11b: `lbw`, Model L, `dry_gest`. H11c: `lbw`, Model T, `en`. The other summary of each Model L pair is reported without a verdict.
- **Model L (spec §5.3; `l_spec()`).** `<O> ~ tmax_t3 + tmax_t2 + tmax_t1 + spi3_dry_l0 + spi3_dry_l3 + spi3_dry_l6 + tmax_lead12 + spi3_dry_lead3 + ym_f + offset(log denom) + (1 + t_c | unit_id) + (1 | state_ym)`, NB2 in glmmTMB through `fit_nb()` with the unit random-effect fallback chain `us` → `diag` → `int`, on the primary window. Year-month fixed effects replace calendar-month effects, the trend and the programme indicators. If the `state_ym` random effect does not converge, it is dropped and the fit is refitted on the selected structure inside a **state-cluster bootstrap** (resampling states). The key `F.l.<O>.state_ym` records which was used.
- **Model T (spec §5.2; `t_spec_f()`).** Paper E's `t_spec()`: `<O> ~ en_gest + ln_gest + moy + t_c + hmis_format2017 + demonet + offset(log denom) + (1 + t_c | unit_id) + <time RE>`, NB2, on the primary window. `t_c = (t_months − 47) / 12`. It carries no local-climate term (it is the total association).
- **The Model T time chain.** `ar1(ym_f + 0 | national)`, then `(1 | ym_f)` (`iid`), then a **moving-block bootstrap over months (block 12)** that refits the model without a time random effect on each resample; the step used is `F.t.<O>.time_re`. Under the bootstrap step the CI is the percentile interval and the p is the two-sided Wald p from the bootstrap SE of the log-scale summary, z = β̂ / SD_boot(β̂*), p = 2 × (1 − Φ(|z|)) (resolution (controller, 2026-11-08): spec §5.5 "All p-values are two-sided Wald p-values" binds over the plan's bootstrap p; the plan's bootstrap p and its 2/B_ok floor are not used). The same rule applies to Model L's state-cluster bootstrap.
- **Bootstrap refits (Paper E F57).** Every resample is refitted with the random-effect structure selected on the original rows, with no per-resample fallback. If more than 10% of the refits fail, the estimates of that step read `not estimable (bootstrap: more than 10% of refits failed)`; B_ok (successful refits) is recorded in the `description`.
- **Programme indicators (spec §5.1).** `hmis_format2017` (step from April 2017) and `demonet` (November 2016 to January 2017) enter Model T. `laqshya` (step from December 2017) and `pmsma` (step from June 2016) enter only the `extra_prog` sensitivity. `covid_mar2020`, `covid_lockdown` (April to June 2020) and `covid_fy2021` enter only the Model T arm of the `fy2021` sensitivity; in Model L the year-month fixed effects absorb them. Programme-event months stay provisional until the author confirms them.
- **Optimiser.** Every glmmTMB fit uses `glmmTMBControl(optCtrl = list(iter.max = 1e4, eval.max = 1e4))` from the start (Paper E F61). Convergence (positive-definite Hessian, maximum absolute gradient) is recorded per fit.
- **Seed.** `SEED_F = 20261026L` (`models/F/R/common_f.R`); resample or simulation *i* of any bootstrap or simulation uses `SEED_F + i − 1`.
- **Frozen code.** `models/common/R` and `models/E/R` are not edited; Paper F calls them (`nb_spec`, `fit_nb`, `t_spec`, `fit_time_chain`, `lin_comb`, `mde`).

## Data rules stated in Methods (spec §3; plan and controller rulings, Tasks 1–7)

1. **Item crosswalk (plan decision, Task 1).** The perinatal item rows live in a separate file, `pipeline/reference/hmis_perinatal_crosswalk.csv`, and the author-reviewed gate dispositions in `pipeline/reference/hmis_perinatal_reviewed.csv`; Paper E's `hmis_item_crosswalk.csv` and `hmis_reviewed.csv` are not edited. A code matches only if its normalised text matches the regex, so item 4.1.2 ("Pre term newborns" from FY2017-18) is never read as stillbirths and, in E1, 4.1.3 ("Abortions") never as stillbirths (stillbirths are 4.1.2 in E1 and 4.1.3 in E2/E3). Deaths within 24 h (`d24`) is a state-only variable (R4).
2. **Link units (plan decision, Task 3).** Names are matched inside the GADM states of the HMIS state unit in the tiers review, exact, normalised, NFHS crosswalk (Paper B, names only), fuzzy, unmatched. A **fuzzy match** is accepted only when its best within-state `difflib` ratio is ≥ 0.75 and no other candidate lies within 0.05 of it; every accepted match is listed in `perinatal_fuzzy_matches.csv` with its runner-up. A district carved out after GADM's vintage is mapped to its GADM parent(s) through `pipeline/reference/hmis_district_review.csv` (source and disposition `assign`, `carve_out` or `exclude`). The same district name in two states maps within its own state. Link units are the components of the graph, so a split that chains across years (Telangana 2016, West Bengal 2016-17) ends in one component. Delhi is one GADM polygon and one link unit.
3. **Manual-review guard (R3).** Over the FY2012-13 to 2019-20 state × name combinations, those needing a hand-assigned parent (`manual`, `carve_out`, `unmatched`) number `F.units.n_manual` and their share is `F.units.manual_share`; fuzzy matches do not count. A share above 0.10 stops the build; the FY2020-21 manual load is reported separately and never stops it. The build also stops if there are fewer than 600 link units (`F.units.n_link`).
4. **Completeness of a link-unit-month (plan decision, Task 4).** The share of its member HMIS districts with a valid value. The primary value is kept only when it is 1; otherwise NaN, never the partial sum. **Ghost districts**: a district listed in an FY's state file whose every panel variable is `nofile` in all 12 months of that FY and whose first valid month in FY2012-13 to 2020-21 is in a later FY is not a member of its link unit for that FY, in the numerator and the denominator of completeness (36 district-FYs, `perinatal_ghost_members.csv`); every other `nofile` district counts and makes completeness < 1. Cells with 0.5 ≤ completeness < 1 are gated on the scaled value (value ÷ completeness) with the same count and rate rules (for the `comp050` and `allcomp` columns); cells with completeness < 0.5 stay ungated in `<v>_raw` and are documented as such.
5. **Gates and dispositions (spec §3.5).** A failing cell is NaN, never replaced. Rate plausibility: `sb > lb`, `lbw > wt` or `wt > 1.10 × lb` masks the outcome; an `sb` rate above 100 per 1,000 total births with `tb` ≥ 50 masks `sb`; an LBW share outside its unit's same-calendar-month within-era median ± 0.20 with `wt` ≥ 50 masks `lbw`. Count plausibility: above 3× the same-calendar-month within-era median (median ≥ 20) is masked; lows below 0.33× are kept and logged and masked only in `masklow`, except lows covering every available month (≥ 10) of a unit-FY. Partial components (`lb`, `home`, E1 `inst`): masked if the pattern occurs in more than 5% of the variable's unit-months. District sum versus state row within 2% (counts ≥ 100) or ±5, 12 months versus FY total within 1%, E1 component sums within ±1, national total within 1%. These are internal-consistency checks, never independent validation. An outcome with more than 20% of its primary unit-months gate-masked is dropped; a link unit with more than 20% of its months masked for an outcome is excluded from that outcome's primary model and listed (`F.panel.<O>.n_units_excluded`). **Masked shares and excluded-unit counts count only cells that had a value before masking.** The build halts if either outcome is dropped or an FY of FY2012-13 to 2019-20 is wholly unusable.
6. **FY2020-21 (R1, R2; resolution (controller, Task 4)).** FY2020-21 is a sensitivity analysis only. A FY2020-21 district is mapped only if it lies wholly inside one link unit; a district spanning several units sets those units' FY2020-21 months to NaN (14 units, `fy2021_split`), and an **unmatched or excluded FY2020-21 district sets every link unit of its state to NaN for FY2020-21** (flag `fy2021_unmatched`; 2 state units). **No key holds a FY2020-21 rate, count or completeness value**: only `F.sens.<O>.fy2021.{heat,dry,en}` (RR, CI, p) exist for that year. `F.national.*`, `F.d24.national.*`, `F.panel.*`, `F.units.*` and `F.break2017.*` end at February 2020 (FY2019-20 = April 2019 to February 2020) or describe FY2012-13 to 2019-20 names and carry a note that FY2020-21 was analysed as a sensitivity analysis.
7. **National series (resolution (controller, 2026-11-08); deviation from plan Task 12, which summed the link-unit panel; spec §3.2 defines national totals as the sum of the official state rows of `All_India.xls`; the M/O rule is Paper E F39 as ruled for Task 2).** `F.national.*` and `F.d24.national.*` are computed from the national month table (`data/derived/hmis/_parts_f/national_month.csv.gz`): the official state rows of each FY's `All_India.xls` net of the M/O Defence and M/O Railways workbooks; in that series only, a blank M/O cell counts as zero. Each FY rate is a ratio of sums over the FY's months (to February 2020) in which every count of that rate is non-missing; the months used are in the `description`. Missing is never zero in the panel counts. Task 12's "national keys use the primary window only" test must use this source. Rates: `sbr` stillbirths per 1,000 total births (`sb / (lb + sb)` × 1,000); `lbw_share` = `lbw / wt`; `wt_cov` = `wt / lb`; `inst_share` = `inst / (inst + home)`; `tb_per_delivery` = `(lb + sb) / (inst + home)`. Deaths within 24 h per 1,000 live births sum `d24` and the live births of the same national months only over months in which `d24` is reported (blank E1 cells are NaN and the month is not counted); about 60–65% of E1 district-months are blank, the rate jumps at the 2017 format break and is far below any plausible early-neonatal mortality, so it is descriptive only (R4): no link-unit aggregation, flags, models or release. The state × FY table is `perinatal_d24_state_fy.csv` (its FY2019-20 row includes March 2020, so it is not a key source); no state key is in this contract.
8. **Denominators and rates (spec §3.6).** Total births `tb = lb + sb`; `lb = lb_m + lb_f`. The LBW share is among weighed newborns, a facility-weighted denominator; weighing coverage `wt / lb` and the institutional share `inst / (inst + home)` are per link-unit-month. No district population is on disk, so the denominator models use `offset(log_days)`.
9. **Format break (spec §3.3).** The `hmis_format2017` step is in Model T. The national March→April 2017 ratios are descriptive (`F.break2017.*`); a rate ratio beyond 15% is discussed but excludes nothing.
10. **Small-number release panel (R7, R9; plan decision, Task 5).** In the released link-unit-month panel (FY2012-13 to 2019-20 only), `sb`, `lbw` and `preterm` values 1–4 display as `<5`; zeros and blanks stay as they are, and a blank is never `<5`. **Complementary suppression:** if exactly one link unit of a state-month is suppressed for a variable, the smallest non-zero unsuppressed cell of that variable in the state-month (ties by `link_id`) is also shown `<5`; if no non-zero cell remains, the smallest zero cell (by `link_id`) is used, which is a true statement; rounds repeat until no state-month has exactly one suppressed cell. A state-month with a single link unit that has a value cannot be complemented: it is exempt and listed. Rates (`sbr`, `lbw_share`) are blank for every suppressed cell and for a denominator < 20; `tb` and `d24` are not released; no state-month `sb`, `lbw` or `preterm` total is released; no FY2020-21 row is released.

## Rules fixed before results (stated verbatim)

**Episode birth months (R5; spec §5.2).** The episode terms are set on **birth month**, each window extended to 8 months past the episode's last El Niño month (ONI ≥ 0.5 for the season ending in that month) so that it covers births whose gestation overlapped the episode:
- `ep1415` (2014–16): birth months **October 2014 to February 2017**;
- `ep1819` (2018–20; the 2018–19 and weak 2019–20 events merged as in Paper E): birth months **September 2018 to February 2020** (the extension would run to December 2020 but stops at February 2020 under R1);
- every other birth month goes to `en_other`, in the primary model and in the FY2020-21 sensitivity (March 2020 onward included).

The episode model is Model T with `en_ep1415 = en_gest × I(ep1415)`, `en_ep1819 = en_gest × I(ep1819)`, `en_other = en_gest × I(neither)` and `ln_gest`, fitted with the same time chain as the primary Model T (the step recorded in the `description`). The three terms partition `en_gest`. A test checks these months against `enso_monthly.csv`.

**Primary window and FY2020-21 (R1, R2).** The primary window is birth months April 2012 to February 2020 (FY2012-13 to 2019-20, 95 months). March 2020 is left out. The **FY2020-21 sensitivity** runs April 2012 to March 2021 (108 months) with `covid_mar2020`, `covid_lockdown` and `covid_fy2021` in Model T, the link-unit rule of Data rule 6, and `ln_gest` carrying the 2020–21 La Niña. Only its model estimates (RR, CI, p) are public: the keys `F.sens.<O>.fy2021.{heat,dry,en}`. No key holds a FY2020-21 descriptive value.

**Hypotheses (spec §5.5).**
- **H10 (stillbirth).** Stillbirth rates are higher after (a) third-trimester heat, (b) full-gestation rainfall deficit, and (c) a gestation spent in the El Niño phase.
- **H11 (low birth weight).** The LBW share among weighed newborns is higher after (a) full-gestation heat, (b) full-gestation rainfall deficit, and (c) a gestation spent in the El Niño phase.
- *Windows:* the stillbirth–heat association is strongest close to delivery, so H10a uses the third trimester; birth weight integrates growth over the pregnancy, so H11a uses full gestation; deficit acts over months, so both use full gestation. The other window of each pair is reported with no verdict.

**One Holm family of six tests (spec §5.5).** H10a, H10b, H10c, H11a, H11b, H11c. All p-values are two-sided Wald p-values (where the Model T time chain reaches its bootstrap step or Model L uses the state-cluster bootstrap, the Wald p from the bootstrap SE of the log-scale summary, z = β̂ / SD_boot(β̂*); resolution (controller, 2026-11-08): spec §5.5 binds over the plan's bootstrap p, so there is no 2/B_ok floor). Hypothesised direction: RR > 1 per +1 °C (`tmax_t3`, the heat strata sum, and `en_gest`) and per SPI −1 (deficit). The family is `stats::p.adjust(method = "holm")` over the non-NA p of the six tests; a not-estimable test has `p_holm` NA, leaves the family and counts as `not consistent with`.

**Per test, `consistent with` if and only if:**
- (i) the Holm-adjusted p < 0.05 and the estimate is in the hypothesised direction (RR > 1); **and**
- (ii) for the local tests (a, b): the matching negative-control lead in the same model does **not** have a 95% CI excluding 1 in the same direction (a lead "signal" means residual confounding, and the test reads `not consistent with (negative control failed)`); **and**
- (iii) for the El Niño tests (c): both episode-specific RRs (`ep1415`, `ep1819`, on the birth-month windows above) are in the hypothesised direction (point estimates, RR > 1).

Otherwise `not consistent with`. **H10** and **H11** overall are `consistent with` if at least one of their tests is, and `F.<h>.verdict_text` names which. A failed fit gives `not estimable (<reason>)`, which counts as not consistent (the scope of "not estimable" is as in Conventions). If the episode model is not estimable, condition (iii) fails and the `en` test still counts in the family if it was performed (resolution (contract, 2026-11-08), as Paper E).

**Negative-control wording (resolution (contract, 2026-11-08)).** `not consistent with (negative control failed)` is written only when condition (i) held and condition (ii) failed; if (i) failed the verdict is plain `not consistent with`, whatever the lead. The lead RR is displayed whatever the verdict. Task 10's `verdict_local()` implements this narrower rule; its tests add rr 1.01, p_holm 0.30, lead CI (1.01, 1.08) → `not consistent with`.

**Reading rules (spec §5.5; no verdict).**
- **Selection.** If a local-heat test is `consistent with` but the selection audit shows heat lowering `wt` or the institutional share **and** the institutional-share-adjusted estimate moves more than halfway to 1, the Discussion must say selection may explain part of it. Operational form (resolution (contract, 2026-11-08)), per outcome with its primary heat summary (`heat_t3` for `sb`, `heat_gest` for `lbw`): the outcome's heat test is `consistent with`; **and** for `wt` or `inst_share` the audit RR for that summary has a 95% CI wholly below 1; **and** `ln(RR_adj) / ln(RR_primary) < 0.5`, where `RR_adj` is `F.sens.<O>.inst_adj.heat` and `RR_primary` the primary heat RR (a sign change satisfies it; for `lbw` the adjusted estimate also includes weighing coverage, spec §5.7.3). `F.read.<O>.selection` reads `selection may explain part of the association` when all three hold, `selection not indicated` when the heat test is `consistent with` and they do not, and `not applicable (heat test not consistent with)` otherwise. If the heat test is `consistent with` and any other input of the rule is not estimable, the key reads `not estimable (<input>: <reason>)`, and the Discussion takes the cautious branch (`selection may explain part of the association`) (resolution (contract, 2026-11-08), as Paper E amendment 2026-10-25).
- **National events.** If H10c or H11c is `consistent with` but the local-climate associations are null, the Discussion says the total may reflect coincident national events. Operational form (resolution (contract, 2026-11-08)): the outcome's `en` test (H10c or H11c) is `consistent with`; the local associations are null or opposite (as Paper E's Model S rule) when the 95% CI of neither the outcome's primary heat summary nor its `dry_gest` lies wholly above 1. `F.read.<O>.national` reads `total may reflect coincident national events` when `en` is consistent and the local associations are null, `local-climate associations also present` when `en` is consistent and they are not, and `not applicable (El Niño test not consistent with)` otherwise. If the El Niño test is `consistent with` and any other input of the rule is not estimable, the key reads `not estimable (<input>: <reason>)`, and the Discussion takes the cautious branch (`total may reflect coincident national events`) (resolution (contract, 2026-11-08), as Paper E amendment 2026-10-25).
- Deaths within 24 h, preterm, the sex-ratio negative-control outcome and every sensitivity carry no verdict.

**Fixed vocabulary.** `consistent with` / `not consistent with` / `not consistent with (negative control failed)`; null displays `not estimable (…)`, `not estimated (…)`, `not applicable (…)`, `not available (…)`.

**Compute budget and power, written before any exposure model (R6; spec §5.6).** Everything in this block is fixed before any exposure model is read.
- **Timing.** The four Task 7 timing fits (permuted exposures; wall time, random-effect step and convergence only) are `F.timing.*.minutes` and are the basis of every projection.
- **Simplified simulation model.** Link-unit random intercepts only (no random slopes, `sim_spec_l()`, `sim_spec_t()`); no `(1 | state_ym)`; Model T with the iid `(1 | ym_f)` time effect, redrawn per simulation; Model L keeps its year-month fixed effects. Per simulation: fit the model without the tested exposure terms, redraw the random time effects where the model has them, inject the RR, draw NB2 counts, refit with the tested terms, and count a rejection when the two-sided p < 0.05 and the estimate is in the hypothesised direction (RR > 1).
- **Size and grids.** 200 simulations per test × grid point, in parallel. Grids: Model L heat (per +1 °C sustained) 1.01, 1.02, 1.03, 1.05; Model L deficit (per SPI −1 sustained) 1.01, 1.02, 1.03, 1.05; Model T El Niño (per +1 °C gestation mean) 1.02, 1.05, 1.10, 1.20.
- **If the projected run exceeds 24 hours,** apply in order: (1) 100 simulations; (2) the grid {1.03, 1.05, 1.10} for **every** test ({0.90, 0.95, 0.97} is unused: all six tests hypothesise RR > 1). **Tests are never dropped: never fewer than the six tests.** If the projection still exceeds 24 hours after both steps, **stop and report to the author before running**; nothing is run. The number of simulations, the grid used, the projected hours and the step reached are keys (`F.power.{n_sim,grid,hours,step}`), `step` being `200`, `100`, `100 with reduced grid` or `stop`.
- **If `step` is `stop`,** no simulation runs: `F.power.n_sim`, `F.power.grid` and `F.power.hours` give the fully reduced plan that was projected, and every `F.power.<H>.mde` and `F.power.<H>.power_at_grid_max` reads `not estimated (power simulation stopped: projected run over 24 hours after both R6 reductions)`. Any later power run is a dated amendment committed before it runs and before any exposure estimate is read.
- **Projection.** Hours = Σ over the six tests of (simulations × grid points × minutes of one simulation fit of that test's model, from `F.timing.l_sim.minutes` or `F.timing.t_sim.minutes`) ÷ 60 ÷ the number of parallel workers; the workers used are in the `description`. `lbw` was not timed, so the `sb` timings stand for both outcomes.
- **MDE.** The MDE is the RR closest to 1 in the grid used with power ≥ 0.80 (two-sided p < 0.05 and RR > 1). If none reaches it, the display is `not reached at RR <largest>`, where `<largest>` is the largest RR of the grid used. Every MDE display carries the label **`(optimistic: simulated on a simplified model)`**. It is per test at α = 0.05, not Holm-adjusted, so it is also optimistic for the six-test family (stated in the Discussion).
- **Bootstrap sizes.** The Model T block bootstrap (block 12) uses B = 500, falling to B = 200 when the run time projected from the primary Model T timing (B × minutes per refit ÷ 60 ÷ workers) exceeds 12 hours. **Resolution (plan, 2026-10-26): the 12-hour test also applies to Model L**: its state-cluster bootstrap uses B = 200, falling to B = 100 when the projection exceeds 12 hours, projected using `F.timing.l_primary.minutes` (an upper bound; refits omit `(1 \| state_ym)`). The B used is a key (`F.t.<O>.boot_B`, `F.l.<O>.boot_B`).

**Model T time chain (spec §5.2).** `ar1`, then `iid`, then the block bootstrap (block 12), as in Conventions. **Model L state-month fallback (spec §5.3):** if `(1 | state_ym)` does not converge, the model is refitted without it inside the state-cluster bootstrap; `F.l.<O>.state_ym` records which was used.

**Sensitivity analyses and secondary models** carry no verdict (spec §5.7). The selection audit, preterm and the sex-ratio negative control are secondary models without verdict.

## 1. Panel and link units (19 keys)

Producer: `panel_keys()` in `models/F/R/results_f.R`, called by `04_results.R`. Inputs: `perinatal_model.csv.gz` (primary window unless stated), `perinatal_gate_summary.csv` (scope `primary`, FY2012-13 to 2019-20 including March 2020: 96 months; the window share `masked_share_window` is over the 95 primary months), `pipeline/reference/hmis_link_units.csv`, `perinatal_units_report.md` and `perinatal_fuzzy_matches.csv`. All keys end at February 2020 and carry the FY2020-21 note.

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.panel.{n_link_units,n_unit_months,n_months,n_states}` | Link units in the panel; link-unit-months in the primary window (rows, whatever the outcome values); primary months (95); state units with at least one link unit | n | `panel_keys()` | `int` | Abstract, Results ¶1, Table 2 |
| `F.panel.{sb,lbw}.{n_valid,n_units_excluded}` | Primary-window unit-months entering the `<O>` model (non-missing outcome, not excluded, denominator ≥ 20), computed with `outcome_rows()` on the 95-month model table (not the gate summary's `entering_models`, which counts 96 months); link units excluded from `<O>` for more than 20% of months masked | n | `panel_keys()`, `outcome_rows()`, `perinatal_gate_summary.csv` | `int` | Results ¶1, Table 2 |
| `F.panel.{sb,lbw}.share_masked` | Gate-masked share of the `<O>` unit-months that had a value, over the 95-month primary window (`masked_share_window`) | proportion | `panel_keys()` | `pct2` | Results ¶1, Supplement |
| `F.units.{n_link,n_single,n_hmis_names,n_gadm,n_fuzzy,n_manual}` | Link units; link units with exactly one GADM district and one HMIS district in every primary FY (`single_district`); distinct FY2012-13 to 2019-20 state × normalised HMIS names; GADM districts in link units; accepted fuzzy matches among the FY2012-13 to 2019-20 state × name combinations (rows of `perinatal_fuzzy_matches.csv` whose `fys` include a primary FY); hand-assigned names counted by the R3 guard | n | `panel_keys()`, `hmis_link_units.csv`, `perinatal_units_report.md` | `int` | Methods, Results ¶1, Supplement (crosswalk summary) |
| `F.units.manual_share` | R3 guard share: `n_manual` / `n_hmis_names` (limit 0.10) | proportion | `panel_keys()` | `pct1` | Methods |
| `F.status_date.{min,max}` | Earliest `status_date_min` and latest `status_date_max` over the primary window (all HMIS values are provisional as of these dates) | date | `panel_keys()` | `date` | Methods, Table 2 |

## 2. National descriptives and the 2017 break (51 keys)

Producer: `national_keys()` in `results_f.R`, called by `04_results.R`. Inputs: the national month table of `perinatal_parts.py` (`data/derived/hmis/_parts_f/national_month.csv.gz`, Data rule 7), `perinatal_break_ratio_2017.csv`. `F.d24.national.<FY>` sums `d24` and the live births of the same national months over the months of April 2012 to February 2020 in which `d24` is reported; the `TOTAL` rows of `perinatal_d24_state_fy.csv` equal it for FY2012-13 to 2018-19 only, because that table's FY2019-20 row includes March 2020. FY2012-13 to 2019-20 only; FY2019-20 is April 2019 to February 2020 and the `description` says so; no FY2020-21 value exists (R2).

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.national.sbr.{fy1213,fy1314,fy1415,fy1516,fy1617,fy1718,fy1819,fy1920}` | Stillbirths per 1,000 total births, national, FY `<FY>` | per 1,000 | `national_keys()` | `fmt_num(x, 1)` | Results ¶1, Table 2, Figure 1 |
| `F.national.lbw_share.{fy1213,fy1314,fy1415,fy1516,fy1617,fy1718,fy1819,fy1920}` | LBW share of newborns weighed, national | proportion | `national_keys()` | `pct1` | Results ¶1, Table 2, Figure 1 |
| `F.national.wt_cov.{fy1213,fy1314,fy1415,fy1516,fy1617,fy1718,fy1819,fy1920}` | Weighing coverage: newborns weighed per live birth, national | proportion | `national_keys()` | `pct0` | Results ¶1, Table 2 |
| `F.national.inst_share.{fy1213,fy1314,fy1415,fy1516,fy1617,fy1718,fy1819,fy1920}` | Institutional share of deliveries `inst / (inst + home)`, national | proportion | `national_keys()` | `pct0` | Results ¶1, Table 2 |
| `F.national.tb_per_delivery.{fy1213,fy1314,fy1415,fy1516,fy1617,fy1718,fy1819,fy1920}` | Total births per delivery `(lb + sb) / (inst + home)`, national (the check that births are not facility-only) | ratio | `national_keys()` | `num2` | Methods, Table 2 |
| `F.d24.national.{fy1213,fy1314,fy1415,fy1516,fy1617,fy1718,fy1819,fy1920}` | Deaths within 24 h per 1,000 live births, national, over the national months with a reported `d24` (R4: descriptive only; the 2017 step is described, the rate is far below plausible early-neonatal mortality) | per 1,000 | `national_keys()` | `fmt_num(x, 2)` | Results ¶1, Supplement |
| `F.break2017.{sbr,lbw_share,wt_cov}.ratio` | National April 2017 / March 2017 ratio of the rate, over link units with a complete value for both months (descriptive; a rate ratio beyond 15% would be discussed) | ratio | `national_keys()`, `perinatal_break_ratio_2017.csv` | `num3` | Methods, Table 1 |

## 3. Exposure descriptives (12 keys)

Producer: `exposure_keys()` in `results_f.R`. Over the unit-months of the primary window with the term non-missing; no outcome is involved.

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.exposure.{tmax_t3,tmax_gest,spi3_dry_gest,en_gest,ln_gest}.sd` | SD (n − 1) of the term across link-unit-months (`tmax_t3` °C anomaly, third-trimester mean; `tmax_gest` and `spi3_dry_gest`, the nine-month means of Common definitions; `en_gest`, `ln_gest` °C) | °C or SPI | `exposure_keys()` | `num3` | Methods, Supplement (power) |
| `F.exposure.{tmax_t3,tmax_gest,spi3_dry_gest,en_gest,ln_gest}.sd_within` | SD of the term after removing its year-month mean (within-month, across link units; 0 for the national ENSO terms) | °C or SPI | `exposure_keys()` | `num3` | Methods, Supplement (power) |
| `F.exposure.{n_months,n_en_months}` | Primary birth months with a gestation-mean ONI term; primary birth months with `en_gest` > 0 | n | `exposure_keys()` | `int` | Results ¶1 |

## 4. Compute and timing (8 keys)

Producers: `models/F/00_timing.R` (timings, already run before this contract; `papers/F/output/timing.csv`) and `01_power.R` (`F.power.{n_sim,grid,hours,step}`, from `papers/F/output/power.csv` and `power_plan()`). The timing fits use exposures permuted within link unit and keep only wall time and convergence.

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.timing.{l_primary,t_primary,l_sim,t_sim}.minutes` | Wall time of one primary Model L fit, one primary Model T fit, one simulation Model L fit and one simulation Model T fit (outcome `sb`, permuted exposures; rows 59,627 / 61,357 / 59,627 / 61,357) | minutes | `00_timing.R` | `fmt_num(x, 1)` | Methods, Supplement (power) |
| `F.power.n_sim` | Simulations per test × grid point actually used (200, or 100 after step 1) | n | `01_power.R` | `int` | Methods |
| `F.power.grid` | RR grid used: `Model L 1.01, 1.02, 1.03, 1.05; Model T 1.02, 1.05, 1.10, 1.20`, or `1.03, 1.05, 1.10 (every test)` after step 2 | text | `01_power.R` | text | Methods, Supplement |
| `F.power.hours` | Projected hours of the plan used (the projection of the step reached) | hours | `01_power.R`, `power_plan()` | `fmt_num(x, 1)` | Methods |
| `F.power.step` | Step of the R6 order reached | text | `01_power.R` | `200`, `100`, `100 with reduced grid` or `stop` | Methods |

## 5. Model L: local-climate association (38 keys)

Producer: `fit_model_l()` in `models/F/R/primary_f.R`, run by `02_primary.R`. `<S>` summaries are defined in Common definitions; the negative-control lead is in the same model. `F.l.<O>.heat` and `F.l.<O>.dry` give the three trimester strata (`tri1` first, `tri2` second, `tri3` third trimester), each per +1 °C or per SPI −1 within that stratum, as the exploratory figure of per-trimester RR curves.

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.l.{sb,lbw}.{heat_t3,heat_gest,dry_gest}.rr` | RR of the `<S>` summary (`heat_t3`: per +1 °C sustained over the third trimester; `heat_gest`: per +1 °C sustained over gestation; `dry_gest`: per SPI −1 sustained over gestation) | RR | `02_primary.R` | `rr_ci` | Abstract, Results ¶2, Table 3, Figure 3 |
| `F.l.{sb,lbw}.{heat_t3,heat_gest,dry_gest}.p` | Two-sided p of the `<S>` summary (Wald, or Wald from the bootstrap SE under the state-cluster bootstrap), unadjusted | p | `02_primary.R` | `p` | Table 3 |
| `F.l.{sb,lbw}.{heat_t3,heat_gest,dry_gest}.lead_rr` | RR of the matching negative-control lead in the same model (`tmax_lead12` per +1 °C for the heat summaries; `spi3_dry_lead3` per SPI −1 for `dry_gest`) | RR | `02_primary.R` | `rr_ci` | Results ¶2, Table 3, Figure 2 |
| `F.l.{sb,lbw}.{heat,dry}.{tri1,tri2,tri3}` | RR of one trimester stratum (heat: `tmax_t1`, `tmax_t2`, `tmax_t3`, per +1 °C; deficit: `spi3_dry_l6`, `spi3_dry_l3`, `spi3_dry_l0`, per SPI −1) | RR | `02_primary.R` | `rr_ci` | Figure 2, Supplement |
| `F.l.{sb,lbw}.state_ym` | Structure used for the state error: the `(1 \| state_ym)` random effect, or the state-cluster bootstrap | text | `02_primary.R` | `state-month random effect` or `state-cluster bootstrap (B = <B>)` | Methods, Table 3 |
| `F.l.{sb,lbw}.boot_B` | Bootstrap resamples requested (200, or 100 after the 12-hour projection); `description` gives B_ok | n | `02_primary.R`, `boot_plan()` | `int`, or `not applicable (state-month random effect converged)` | Methods, Supplement |
| `F.l.{sb,lbw}.{n,n_units}` | Unit-months and link units in the primary Model L fit | n | `fit$n` | `int` | Table 3 |

## 6. Model T: total El Niño association (18 keys)

Producer: `fit_model_t()` in `primary_f.R`, run by `02_primary.R`. The primary fit gives `en_gest` and `ln_gest`; the episode fit gives `ep1415` and `ep1819`.

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.t.{sb,lbw}.en.rr` | RR per +1 °C of the gestation-mean El Niño term `en_gest` | RR per °C | `02_primary.R` | `rr_ci` | Abstract, Results ¶2, Table 3, Figure 3 |
| `F.t.{sb,lbw}.en.p` | Two-sided p of `en_gest` (Wald, or Wald from the bootstrap SE under a bootstrap step), unadjusted | p | `02_primary.R` | `p` | Table 3 |
| `F.t.{sb,lbw}.en.{ep1415,ep1819}` | RR per +1 °C of `en_ep1415` and `en_ep1819` (episode model, birth-month windows of R5) | RR per °C | `02_primary.R` | `rr_ci` | Results ¶2, Table 3, Figure 3 |
| `F.t.{sb,lbw}.ln.rr` | RR per 1 °C **cooler** La Niña term: `exp(−β_ln)` with the bounds swapped; `description` says the term is weakly identified | RR per °C | `02_primary.R` | `rr_ci` | Table 3 |
| `F.t.{sb,lbw}.time_re` | Time random-effect step used (`fit_time_chain()`) | text | `02_primary.R` | `ar1` → `AR(1) year-month random effect`; `iid` → `independent year-month random effect`; `block_bootstrap` → `moving-block bootstrap over months (block 12, B = <B>)` | Methods, Table 3 |
| `F.t.{sb,lbw}.boot_B` | Block-bootstrap resamples requested (500, or 200 after the 12-hour projection); `description` gives B_ok | n | `02_primary.R`, `boot_plan()` | `int`, or `not applicable (no bootstrap step)` | Methods, Supplement |
| `F.t.{sb,lbw}.{n,n_units}` | Unit-months and link units in the primary Model T fit | n | `fit$n` | `int` | Table 3 |

## 7. Verdicts H10 and H11 (16 keys)

Producer: `models/F/R/verdicts_f.R` (`holm_family_f()`, `verdict_test()`, `overall_verdict_f()`), called by `02_primary.R`.

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.{h10a,h10b,h10c,h11a,h11b,h11c}.verdict` | Verdict of one test (rule above) | text | `verdict_test()` | `consistent with`, `not consistent with` or `not consistent with (negative control failed)` | Abstract, Results ¶2, Table 3 |
| `F.{h10a,h10b,h10c,h11a,h11b,h11c}.p_holm` | Holm-adjusted p of the test in the six-test family; `not estimable (<reason>)` for a test that left the family | p | `holm_family_f()` | `p` | Results ¶2, Table 3 |
| `F.{h10,h11}.verdict` | Overall H10 or H11 verdict: `consistent with` if at least one of its tests is | text | `overall_verdict_f()` | `consistent with` or `not consistent with` | Abstract, Discussion |
| `F.{h10,h11}.verdict_text` | Overall verdict naming the consistent tests (template below) | text | `overall_verdict_f()` | text | Results ¶2, Discussion |

**Verdict-sentence templates.** `{LIST}` joins the labels of the tests of that hypothesis whose per-test verdict is `consistent with`, in the order a, b, c, separated by ", " with " and " before the last label (one label stands alone). Labels: H10a "third-trimester heat"; H10b "full-gestation rainfall deficit"; H10c "an El Niño gestation"; H11a "full-gestation heat"; H11b "full-gestation rainfall deficit"; H11c "an El Niño gestation".
- `F.h10.verdict_text` = `consistent with H10 for {LIST}` when `F.h10.verdict` is `consistent with`, for example `consistent with H10 for third-trimester heat and an El Niño gestation`; otherwise `not consistent with H10`. `F.h11.verdict_text` likewise with H11.
- In the manuscript: "These results were {{F.h10.verdict_text}}."; per test, "H10a (third-trimester heat and stillbirth): {{F.h10a.verdict}}." No template places a list between a verdict and the hypothesis label.

## 8. Selection audit and reading rules (16 keys)

Producer: `selection_models()` in `models/F/R/secondary_f.R`, run by `03_secondary.R`, and `reading_rules_f()` in `verdicts_f.R`. The denominator models are Model L and Model T with `tb` and `wt` as NB2 counts (offset `log_days`, unit random intercepts and trends, year-month fixed effects in Model L) and the institutional share `inst / (inst + home)` as a beta-binomial (`cbind(inst, home)`); the three audit models carry no verdict. For `inst_share` the key is an odds ratio (logit scale), stated in the `description`.

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.sel.{tb,wt,inst_share}.{heat_t3,heat_gest,dry_gest,en}.rr` | Association of the `<D>` denominator with each Model L summary and with `en_gest` (Model T): RR for counts `tb`, `wt`; odds ratio for `inst_share` | RR or OR | `selection_models()` | `rr_ci` | Results ¶3, Figure 3, Supplement |
| `F.read.{sb,lbw}.selection` | Selection reading rule for the outcome's primary heat test (rule above) | text | `reading_rules_f()` | `selection may explain part of the association`, `selection not indicated`, `not applicable (heat test not consistent with)` or `not estimable (<input>: <reason>)` | Discussion |
| `F.read.{sb,lbw}.national` | National-events reading rule for the outcome's El Niño test (rule above) | text | `reading_rules_f()` | `total may reflect coincident national events`, `local-climate associations also present`, `not applicable (El Niño test not consistent with)` or `not estimable (<input>: <reason>)` | Discussion |

## 9. Power (12 keys)

Producer: `simulate_power_f()` and `mde_f()` in `models/F/R/power_f.R`, run by `01_power.R` after this contract is committed and before any exposure estimate is read (R6). Design, grids, steps and the MDE rule are in the rules above; the run-level keys `F.power.{n_sim,grid,hours,step}` are in §4.

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.power.{h10a,h10b,h10c,h11a,h11b,h11c}.mde` | Minimum detectable RR of the test (the MDE rule), in the grid used | RR | `mde_f()` | `num2 (optimistic: simulated on a simplified model)`, e.g. `1.05 (optimistic: simulated on a simplified model)`, `not reached at RR <largest> (optimistic: simulated on a simplified model)`, or `not estimated (power simulation stopped: projected run over 24 hours after both R6 reductions)` | Abstract, Results ¶2, Discussion |
| `F.power.{h10a,h10b,h10c,h11a,h11b,h11c}.power_at_grid_max` | Simulated power at the largest RR of the grid used: rejections / successful refits (`n_ok` in the `description`) | proportion | `simulate_power_f()` | `pct0`, or `not estimated (power simulation stopped: projected run over 24 hours after both R6 reductions)` | Supplement (MDE simulation) |

## 10. Secondary models (4 keys)

Producer: `preterm_model()` and `sexratio_model()` in `secondary_f.R`, run by `03_secondary.R`. No verdict.

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.pre.{heat_t3,heat_gest,dry_gest}.rr` | Preterm births per live birth (offset `log_lb`), Model L, birth months April 2017 to February 2020 (E2 only, three years), per `<S>` summary | RR | `preterm_model()` | `rr_ci` | Results ¶3, Supplement |
| `F.nc.sexratio.heat_t3.rr` | Negative-control outcome: male live births with female live births as the offset (`lb_m` with `log_lb_f`), Model L, third-trimester heat summary; expected null or very small | RR | `sexratio_model()` | `rr_ci` | Results ¶3, Supplement |

## 11. Sensitivity analyses (102 keys)

Producer: `sens_case_f()` in `models/F/R/secondary_f.R`, run by `03_secondary.R`. Each key is an RR (or, for `betabin`, an odds ratio) under the change listed. `heat` is the outcome's primary heat summary (H10a `heat_t3` for `sb`, H11a `heat_gest` for `lbw`, from Model L), `dry` is `dry_gest` (Model L) and `en` the Model T El Niño RR. A sensitivity that does not apply to a model displays `not applicable (<reason>)`. The Model T arms use the same time chain as the primary Model T (the step used is in the `description`), Model L arms the same state-month structure. No verdict. `SENS_IDS_F` equals the suffixes below.

| Suffix | Change from the primary model |
|---|---|
| `fy2021` | Through March 2021 (108 months): FY2020-21 unit rule of Data rule 6; Model T adds `covid_mar2020`, `covid_lockdown`, `covid_fy2021`; the episode terms keep March 2020 onward in `en_other`; Model L unchanged in form. Only the model estimates are keys (R2). `not estimable (FY2020-21 <reason>)` if FY2020-21 is unusable |
| `betabin` | Beta-binomial logit, `cbind(y, denom − y)`, no offset (respects the bound for the LBW share); an odds ratio, noted in the `description` |
| `inst_adj` | Link-unit-month institutional share added (and weighing coverage `wt_cov` for `lbw`) |
| `inst090` | Link units with institutional share ≥ 0.90 in every primary FY (`inst090_all_fy`) |
| `comp050` | Outcome and denominator from the `_scaled` columns (completeness ≥ 0.5, scaled up) |
| `masklow` | Outcome and denominator from the `_masklow` columns (default-kept plausibility lows also masked) |
| `allcomp` | Outcome and denominator from the `_allcomp` columns (every crosswalk component present). If `<O>` and its denominator equal their `_allcomp` columns on every primary-window row (missing pattern included), all three keys read `not applicable (identical to the primary analysis: no crosswalk component missing)` |
| `single` | Link units that are a single GADM district and a single HMIS district in every primary FY (`single_district`) |
| `ns4` | Model L with a natural-spline lag basis (4 df over lags 0–8) for `tmax_anom` in place of the heat strata; `heat_t3` = sum of the lag-specific coefficients over lags 0–2, `heat_gest` over lags 0–8; `en`: `not applicable (Model L heat lag basis)` |
| `heatwave` | `hw_t3`, `hw_t2`, `hw_t1` (heatwave days) in place of the `tmax_*` strata, never both; per +1 heatwave day sustained; `en`: `not applicable (Model L heat metric)` |
| `state_moy` | Model L with state × calendar-month fixed effects added; `en`: `not applicable (Model L only)` |
| `era_int` | Model T with a `(1 \| unit_era)` random intercept added (link unit × format era); the `hmis_format2017` step is **kept**, a deliberate deviation from spec §5.7.10 ("in place of"): the `(1 \| unit_era)` intercepts are zero-mean, so the fixed step must carry the national format shift (resolution (contract, 2026-11-08), following Paper E F28 (controller, 2026-10-24); confirmed by the controller, 2026-11-08); `heat`, `dry`: `not applicable (Model T only)` |
| `extra_prog` | Model T with `laqshya` and `pmsma` added; `heat`, `dry`: `not applicable (Model T only; year-month fixed effects absorb programme indicators)` |
| `roni` | Model T with `en_roni_gest`, `ln_roni_gest` (CPC's official RONI since February 2026) in place of the ONI terms; `heat`, `dry`: `not applicable (Model T only)` |
| `drop_ep1415`, `drop_ep1819` | Model T with that episode's birth months (R5 windows) dropped; `heat`, `dry`: `not applicable (Model T only)` |
| `nosmall` | Small units dropped (`small_unit`: LD, AN, DNH_DD, CH, PY and link units with median total births below 100 a month) |

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.sens.{sb,lbw}.{fy2021,betabin,inst_adj,inst090,comp050,masklow,allcomp,single,ns4,heatwave,state_moy,era_int,extra_prog,roni,drop_ep1415,drop_ep1819,nosmall}.{heat,dry,en}` | Primary heat summary RR (`heat`), `dry_gest` RR (`dry`) and Model T El Niño RR (`en`) under each sensitivity (table above) | RR | `03_secondary.R`, `sens_case_f()` | `rr_ci`, or the fixed null displays | Results ¶4, Supplement (sensitivity table), Figure 3 |

## 12. Generated text (1 key)

Producer: `conclusion_sentence_f()` in `results_f.R`, called by `04_results.R`. A fixed template filled by code, so the manuscript states the verdicts exactly as `results.json` holds them.
- **No causal wording:** the sentence contains no "cause", "effect of", "impact", "led to", "reduce" or "kills".
- **No paper labels:** it never says "Paper A/B/C/D/E".
- **Stops:** `04_results.R` stops if an input key is missing, if an overall verdict is outside `consistent with` / `not consistent with`, or if a null display would be inserted.

| Key | Meaning | Unit | Produced by | Display | Feeds |
|---|---|---|---|---|---|
| `F.abstract.conclusion_sentence` | One-sentence conclusion (template below) | text | `conclusion_sentence_f()` | text | Abstract |

`sentence = "In this link-unit-month analysis of routine HMIS data from India, April 2012 to February 2020, the results were " + H10 + "; and " + H11 + "."`, where:
- `H10 = {F.h10.verdict} + " higher stillbirth rates after third-trimester heat, full-gestation rainfall deficit or an El Niño gestation" + FOR10`, with `FOR10 = " (" + {LIST10} + ")"` when `F.h10.verdict` is `consistent with`, else empty;
- `H11 = {F.h11.verdict} + " a higher low birth weight share among weighed newborns after full-gestation heat, rainfall deficit or an El Niño gestation" + FOR11`, with `FOR11` built as `FOR10`;
- `{LIST10}`, `{LIST11}`: the `{LIST}` of §7.

## 13. Resolutions recorded in this contract

**Plan (resolution (plan, 2026-10-26)).** FY keys in the `fy1213` form; the 12-hour bootstrap test applies to Model L as well as Model T (`F.l.<O>.boot_B`); separate perinatal crosswalk and reviewed files; the fuzzy rule (ratio ≥ 0.75, no rival within 0.05); the complementary-suppression rule; single-unit state-months exempt from complementary suppression and listed; the simulation projection using the `sb` timings for both outcomes; power steps `200`, `100`, `100 with reduced grid`, `stop`.

**Controller (Paper F ledger, `progress.md`).** National series use Paper E's F39 rule (a blank M/O cell counts as zero in the reconciliation series only); ghost districts excluded from completeness numerator and denominator; FY2020-21 unmatched or excluded districts set every unit of their state to NaN (`fy2021_unmatched`); cells with 0.5 ≤ completeness < 1 gated on the scaled value and cells below 0.5 ungated and documented; masked shares count only cells present before masking; d24 flagged in about 60–65% of E1 district-months is acceptable for a state-only descriptive; R3 review sources may be pages that cite the notification; Delhi is one link unit (one GADM polygon); the release panel's child-row allowlist; Paper E is never re-exported from a Paper F branch.

**Spec rulings R1–R9 (2026-10-26)** as stated in the rules above: primary window and FY2020-21 as a sensitivity (R1); FY2020-21 never public (R2); the manual-review guard (R3); deaths within 24 h descriptive only (R4); the episode birth months (R5); the compute budget (R6); the suppressed release panel (R7); preterm in the release (R9). R8 (journal order) is not a contract matter.

**Contract (resolution (contract, 2026-11-08)), written blind to any exposure estimate.** The `(negative control failed)` wording only when condition (i) held; the operational forms of the two reading rules; the per-trimester keys' orientation; the label `(optimistic: simulated on a simplified model)` on every MDE display; `not applicable` displays of sensitivities that do not fit a model; an odds-ratio reading for the beta-binomial keys; `era_int` keeps the `hmis_format2017` step, a deviation from spec §5.7.10 (confirmed by the controller, 2026-11-08); under any bootstrap step the p is the Wald p from the bootstrap SE, spec §5.5 binding over the plan's bootstrap p (controller, 2026-11-08); the national-series source (controller, 2026-11-08); the not-estimable branches of the reading rules; the `stop` displays of the power keys; the `allcomp` not-applicable reason.

## 14. Key index by location

- **Abstract:** F.panel.{n_link_units,n_unit_months,n_months}, F.l.<O>.heat_t3.rr, F.l.<O>.heat_gest.rr, F.l.<O>.dry_gest.rr, F.t.<O>.en.rr, F.power.<H>.mde, F.<H>.verdict, F.{h10,h11}.verdict, F.abstract.conclusion_sentence
- **Methods:** F.units.*, F.status_date.*, F.timing.*, F.power.{n_sim,grid,hours,step}, F.exposure.*, F.break2017.*, F.l.<O>.{state_ym,boot_B}, F.t.<O>.{time_re,boot_B}
- **Results:** §1–§3 and §5–§11 keys
- **Discussion:** F.{h10,h11}.verdict_text, F.read.<O>.{selection,national}, F.power.<H>.mde
- **Table 1:** item crosswalk (`pipeline/reference/hmis_perinatal_crosswalk.csv`), F.break2017.*
- **Table 2:** F.panel.*, F.national.*, F.units.*
- **Table 3:** F.l.*, F.t.*, F.<H>.*, F.{h10,h11}.*
- **Figures:** 1 (F.national.sbr.<FY>, F.national.lbw_share.<FY>), 2 (F.l.<O>.{heat,dry}.tri*, F.l.<O>.<S>.lead_rr), 3 (F.l.*, F.t.*, F.sel.*), 4 (completeness heatmap from the panel, supplement)
- **Supplement:** F.sens.*, F.sel.*, F.pre.*, F.nc.*, F.d24.national.<FY>, F.power.<H>.power_at_grid_max, F.exposure.*

## Display amendment (2026-11-09, after results)

Written after the primary, secondary and sensitivity estimates of Tasks 10 and 11 had been computed and read. It changes a display only; no estimate, interval, p value, verdict or reading rule changes.

- **`rr_ci` is displayed to 3 decimals** for every RR and OR display (point estimate and both bounds): `fmt_ci(est, lo, hi, digits = 3)`, for example `1.011 (95% CI 1.004–1.019)`. This replaces the 2 decimals of the `rr_ci` row of the Conventions table for every key whose display is `rr_ci` (`F.l.*`, `F.t.*`, `F.sel.*`, `F.pre.*`, `F.nc.*`, `F.sens.*`). The `num2` display of the MDE keys (grid points) is unchanged.
- **It is display-only and was decided after results were seen.** The `description` of each key still carries the full-precision estimate, bounds, log-scale coefficient and SE; the values in `results.json` are unchanged.
- **Reason.** At 2 decimals the H10a estimate and interval displayed as `1.01 (95% CI 1.00–1.02)`, although its interval excludes 1 (the lower bound is above 1.003); two decimals hid that the interval excludes 1 and made small associations look like point nulls. Three decimals show the bounds' side of 1 for the effect sizes of this paper (a few tenths of a percent per °C).
- Applied through the Paper F wrapper `fmt_rr_ci()` in `models/F/R/common_f.R`; the common formatter `fmt_ci()` and Paper E's output are not changed.
