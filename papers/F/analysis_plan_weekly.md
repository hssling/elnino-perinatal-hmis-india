# Paper F: analysis plan for the weekly-exposure analysis (weekly gestational exposures, season, bias analyses)

Written 23 November 2026, before any model with a weekly exposure was fitted to an HMIS outcome (original committed as d903e46; this copy omits only the editorial context). It sets the outcome (stillbirth only), weekly exposures across gestation, season-specific estimates and the reporting rules (no tests, p-values or multiple-comparison corrections; risk ratios with 95% CIs; AIC for model choice; RERI with a bootstrap CI for effect modification; E-values; selection-bias analysis; DAG; flow chart). Every analysis below is reported whatever its result.

## 1. Population and outcome (unchanged data, fewer outcomes)

- Unit-months: the 657 HMIS link units (stable district groups), birth months April 2012 to February 2020 (primary
  window as before; March 2020 and FY2020-21 excluded from the primary analysis).
- Outcome: stillbirths, with total births (live + still) as the offset, i.e. the stillbirth risk per total birth.
  Validity gates, masks and the minimum denominator (20) are unchanged. Low birth weight is dropped entirely.
- Missing data: the share of unit-months missing for each model variable is reported. If the complete-case loss in
  the primary model is below 5% (it was 3.2% in the earlier model), complete-case analysis is used and multiple
  imputation is not required; otherwise multiple imputation with 50 imputations (mice) is used.

## 2. Weekly exposures

- Daily district Tmax (IMD 1° grid, `weights_t100_district`) and rainfall (IMD 0.25° grid,
  `weights_r025_district`) with the Phase 1 quality-control masks (zero-filled cell-years and reviewed
  district-month masks), pooled to link units by area as in `pipeline/hmis/perinatal_climate.py`.
- Heat: the daily Tmax anomaly against the unit's 1981–2010 mean for that day of the year (31-day centred window),
  averaged within each week.
- Rainfall deficit: a 28-day standardised precipitation index (SPI-28: the 28-day rainfall total ending on each day,
  transformed through a gamma distribution with a probability mass at zero, fitted per unit and calendar week of the
  year on 1981–2010), truncated at 0: deficit = min(SPI-28, 0) at the end of each gestational week. Reported per one
  SPI unit more deficit.
- Gestational alignment: gestational age is not recorded, so every birth is treated as a term birth at 40 weeks.
  For births in month m, the exposure in gestational week w (1–40) is the mean over all days d of month m (equal
  weights) of the weekly value for days d − 280 + 7(w − 1) to d − 280 + 7w − 1.
- Negative-control exposures (cannot affect births already reported): mean heat anomaly over the 8 weeks after
  birth and SPI-28 deficit 8 weeks after birth.

## 3. Primary model

- Poisson regression with fixed effects (fixest::fepois): stillbirths ~ weekly heat cross-basis + weekly deficit
  cross-basis + both negative controls | link unit + year-month + state × calendar month, offset log(total births).
  Year-month fixed effects absorb every national shock (including El Niño); state × calendar-month fixed effects
  absorb regional seasonality. Standard errors are cluster-robust by link unit. Effect measure: risk ratio (RR),
  since the outcome is stillbirths per total birth.
- Distributed lag: week-specific coefficients β_w = B γ with B a natural cubic spline basis over w = 1..40 (intercept
  included). The degrees of freedom (3, 4, 5 or 6, the same for both exposures) are chosen by AIC. No dlnm package:
  the basis is built by hand (Z = X B).
- Reported: week-specific RRs per +1 °C (and per one SPI unit more deficit) in that week; cumulative RRs per +1 °C
  sustained over weeks 1–13, 14–27, 28–40 and 1–40 (sums of β_w), with 95% CIs from the cluster-robust covariance.

## 4. Season

- Season of birth: winter (December–February), pre-monsoon summer (March–May), monsoon (June–September) and
  post-monsoon (October–November).
- Season-specific lag curves: the cross-bases interacted with season of birth; compared with the pooled model by
  AIC; season-specific week curves and cumulative RRs reported.
- Additive scale: RERI for summer birth (March–May vs other months) × third-trimester heat (+1 °C sustained over
  weeks 28–40). RR01 (summer vs other births at no anomaly) needs a season main effect, so the RERI model replaces
  the year-month and state × calendar-month fixed effects with link unit + financial year fixed effects and a summer
  indicator, with the heat and deficit cross-bases interacted with summer. RERI = RR11 − RR10 − RR01 + 1. 95% CI
  from a cluster bootstrap of link units (500 resamples, seed 20261123, percentile interval).

## 5. Bias analyses

- Selection: flow chart of districts, link units and unit-months with every exclusion; included vs excluded
  unit-months compared (institutional share of deliveries, births per month, state, year); inverse probability
  weighting for inclusion (logistic model of inclusion on state, financial year, log births and institutional
  share; stabilised weights) as a sensitivity analysis.
- Unmeasured confounding: E-values (VanderWeele and Ding) for the cumulative third-trimester and whole-gestation heat
  RRs per +1 °C, for the estimate and the CI limit nearer 1.

## 6. Sensitivity analyses (no verdicts)

1. Negative binomial (fixest::fenegbin) instead of Poisson.
2. Link-unit-specific linear trends added.
3. Units with near-universal institutional delivery (institutional share ≥ 90%).
4. Gestational alignment at 39 weeks instead of 40.
5. Standard errors clustered two-way by link unit and year-month.
6. Inverse probability weighting (Section 5).

## 7. El Niño (secondary)

El Niño acts nationally, so it cannot be separated from the year-month effects of the primary model. As a brief
secondary analysis: the El Niño part of the traditional ONI, max(ONI, 0), averaged over the 40 gestational weeks
(monthly ONI of the season ending in each month, apportioned by week), with the La Niña part, in a model with link
unit and state × calendar-month fixed effects and a linear trend (no year-month effects), standard errors clustered
by year-month. Two El Niño episodes fall in the window, which the text states.

## 8. Reporting

- No p-values, no statistical tests, no "significant", no statements about intervals covering 1; model choice by
  AIC only; no multiple-comparison corrections; the former Holm family, H10/H11 labels and verdict rules are not
  used. RRs to two decimals (week-specific curves are shown in figures), CIs as "(lower, upper)", reference rows "1.00 (Reference)".
- New results keys use the prefix `F.w.` under a dated amendment of `papers/F/results_keys.md`; existing keys are
  untouched.
