# Paper F Task 11: selection audit, secondary models (preterm, sex-ratio negative control), trimester rows and the 17
# sensitivity analyses (contract papers/F/results_keys.md sections 8, 10 and 11). Sourced after common_f.R, perinatal.R,
# power_f.R, verdicts_f.R and primary_f.R. models/common/R and Paper E's models/E/R are frozen and are called unchanged
# (fit_nb, nb_fitter_with, fit_time_chain, block_bootstrap_irr, extra_fitter, bootstrap_carriers, dlm_basis, lin_comb).
#
# Every case is one or two "arms": Model L (the primary structure, `(1 | state_ym)` or the state-cluster bootstrap, via
# fit_model_l) and Model T (the primary time chain ar1 -> iid -> block bootstrap, via .t_part). No case carries a verdict.
# Under any bootstrap step the p is the two-sided Wald p from the bootstrap SE and the CI is percentile (primary_f.R).

SENS_IDS_F <- c("fy2021", "betabin", "inst_adj", "inst090", "comp050", "masklow", "allcomp", "single", "ns4", "heatwave",
                "state_moy", "era_int", "extra_prog", "roni", "drop_ep1415", "drop_ep1819", "nosmall")
SECONDARY_SCRIPT_F <- "models/F/03_secondary.R"
SEC_CACHE <- file.path(F_CACHE, "sec")
SEL_DENOMS <- c("tb", "wt", "inst_share")
ALLCOMP_IDENTICAL_NA <- "not applicable (identical to the primary analysis: no crosswalk component missing)"

# Birth-month windows (ym = year * 12 + month - 1) of the episode terms (R5); March 2020 onward stays in en_other.
EP_WINDOWS_F <- list(ep1415 = c(2014L * 12L + 9L, 2017L * 12L + 1L), ep1819 = c(2018L * 12L + 8L, 2020L * 12L + 1L))
PRETERM_WINDOW_F <- c(2017L * 12L + 3L, 2020L * 12L + 1L)        # April 2017 to February 2020
FY2021_FIRST_YM <- 2020L * 12L + 2L                               # March 2020

SENS_TEXT_F <- c(
  fy2021 = "birth months through March 2021 (FY2020-21 unit rule); Model T adds covid_mar2020, covid_lockdown, covid_fy2021",
  betabin = "beta-binomial logit, cbind(y, denominator - y), no offset (odds ratio)",
  inst_adj = "link-unit-month institutional share added (and weighing coverage for lbw)",
  inst090 = "link units with institutional share >= 0.90 in every primary FY",
  comp050 = "outcome and denominator from the _scaled columns (completeness >= 0.5, scaled up)",
  masklow = "outcome and denominator from the _masklow columns",
  allcomp = "outcome and denominator from the _allcomp columns",
  single = "single-district link units only",
  ns4 = "natural-spline lag basis (4 df over lags 0-8) for tmax_anom in place of the heat strata",
  heatwave = "heatwave days hw_t3, hw_t2, hw_t1 in place of the Tmax strata (per +1 heatwave day sustained)",
  state_moy = "state x calendar-month fixed effects added",
  era_int = "(1 | unit_era) random intercept added; the hmis_format2017 step is kept",
  extra_prog = "laqshya and pmsma added",
  roni = "RONI gestation terms (en_roni_gest, ln_roni_gest) in place of the ONI terms",
  drop_ep1415 = "birth months October 2014 to February 2017 dropped",
  drop_ep1819 = "birth months September 2018 to February 2020 dropped",
  nosmall = "small link units dropped")

# ---- applicability -----------------------------------------------------------------------------------------------

# The `not applicable (<reason>)` display of an arm of a case ("L" or "T"), or NULL when the arm is fitted. `allcomp`
# is not here: its rule depends on the data (allcomp_identical()).
sens_na_reason <- function(id, arm) {
  if (!id %in% SENS_IDS_F) stop("sens_na_reason: unknown sensitivity: ", id, call. = FALSE)
  l_only <- c(ns4 = "not applicable (Model L heat lag basis)", heatwave = "not applicable (Model L heat metric)",
              state_moy = "not applicable (Model L only)")
  t_only <- c(era_int = "not applicable (Model T only)",
              extra_prog = "not applicable (Model T only; year-month fixed effects absorb programme indicators)",
              roni = "not applicable (Model T only)", drop_ep1415 = "not applicable (Model T only)",
              drop_ep1819 = "not applicable (Model T only)")
  if (arm == "T" && id %in% names(l_only)) return(l_only[[id]])
  if (arm == "L" && id %in% names(t_only)) return(t_only[[id]])
  NULL
}

# TRUE if <O> and its denominator equal their _allcomp columns on every primary-window row, the missing pattern
# included (contract: allcomp row of the sensitivity table).
allcomp_identical <- function(d, outcome) {
  d <- data.table::as.data.table(d)
  if ("in_primary" %in% names(d)) d <- d[in_primary == 1L]
  same <- function(a, b) all((is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b))
  den <- sub("^log_", "", DENOM[[outcome]])
  cols <- c(outcome, den, paste0(outcome, "_allcomp"), paste0(den, "_allcomp"))
  absent <- setdiff(cols, names(d))
  if (length(absent)) stop("allcomp_identical: missing column(s): ", paste(absent, collapse = ", "), call. = FALSE)
  same(d[[outcome]], d[[cols[3]]]) && same(d[[den]], d[[cols[4]]])
}

# ---- lag basis and beta-binomial helpers -------------------------------------------------------------------------

# <prefix>_cb1..cb<k> = as.matrix(d[, <prefix>_l0..l<L>]) %*% basis (a copy of d).
ns_cross_basis <- function(d, prefix, basis) {
  cols <- paste0(prefix, "_l", seq_len(nrow(basis)) - 1L)
  absent <- setdiff(cols, names(d))
  if (length(absent)) stop("ns_cross_basis: missing lag column(s): ", paste(absent, collapse = ", "), call. = FALSE)
  d <- data.table::copy(data.table::as.data.table(d))
  cb <- as.matrix(d[, cols, with = FALSE]) %*% basis
  for (k in seq_len(ncol(basis))) data.table::set(d, j = paste0(prefix, "_cb", k), value = unname(cb[, k]))
  d[]
}

# Weights of the ns4 summaries over tmax_cb1..cb<k>: the sum over lags of the lag-specific coefficients (basis %*% beta)
# is colSums(basis[lags, ]) %*% beta.
ns_lag_weights <- function(basis, lags) {
  w <- colSums(basis[lags + 1L, , drop = FALSE])
  stats::setNames(as.numeric(w), paste0("tmax_cb", seq_along(w)))
}

# Contrasts of the ns4 case: heat_t3 over lags 0-2, heat_gest over lags 0-8, the dry summary unchanged.
ns4_contrasts <- function(basis) {
  cb <- paste0("tmax_cb", seq_len(ncol(basis)))
  list(heat_t3 = list(terms = cb, sign = 1, lead = "tmax_lead12", weights = ns_lag_weights(basis, 0:2)),
       heat_gest = list(terms = cb, sign = 1, lead = "tmax_lead12", weights = ns_lag_weights(basis, 0:8)),
       dry_gest = SUMMARIES[["dry_gest"]])
}
# Heatwave-day contrasts: hw_t3 for the third-trimester summary, the three strata for gestation.
hw_contrasts <- function() {
  list(heat_t3 = list(terms = "hw_t3", sign = 1, lead = "tmax_lead12"),
       heat_gest = list(terms = c("hw_t3", "hw_t2", "hw_t1"), sign = 1, lead = "tmax_lead12"),
       dry_gest = SUMMARIES[["dry_gest"]])
}
L_SUMMARY_CONTRASTS <- SUMMARIES[c("heat_t3", "heat_gest", "dry_gest")]

# A glmmTMB fitter for the beta-binomial logit: the response y becomes cbind(y, <denom_col> - y), the offset(...) term is
# dropped, `extra` terms are appended and the model is fitted by fit_fun with glmmTMB::betabinomial().
betabin_fitter <- function(denom_col, extra = character(), fit_fun = e_glmmTMB_fit) {
  force(denom_col)
  extra <- as.character(extra)
  fit_fun <- e_fitter(fit_fun)
  function(formula, data, family = NULL) {
    lhs <- deparse1(formula[[2L]])
    rhs <- deparse1(formula[[3L]], width.cutoff = 500L)
    rhs <- gsub("\\s*\\+\\s*offset\\([^()]*\\)", "", rhs)
    if (grepl("offset(", rhs, fixed = TRUE)) stop("betabin_fitter: offset not removed: ", rhs, call. = FALSE)
    if (length(extra)) rhs <- paste(rhs, "+", paste(extra, collapse = " + "))
    f <- stats::as.formula(sprintf("cbind(%s, %s - %s) ~ %s", lhs, denom_col, lhs, rhs), env = environment(formula))
    fit_fun(f, data, family = glmmTMB::betabinomial())
  }
}

# ---- cases -----------------------------------------------------------------------------------------------------

.den_of <- function(outcome) sub("^log_", "", DENOM[[outcome]])

# Rows of the outcome's primary analysis (outcome_rows) in the table `d`.
.base_rows <- function(d, outcome) outcome_rows(data.table::as.data.table(d), outcome)

# The data and spec of an outcome/denominator swap (suffix "scaled", "masklow", "allcomp"): y = <O>_<suffix>, offset =
# log(<den>_<suffix>), rows without a gate exclusion (excluded_<O>) and with the swapped denominator >= 20.
.swap_case <- function(d, outcome, suffix) {
  d <- data.table::copy(data.table::as.data.table(d))
  den <- .den_of(outcome)
  y <- paste0(outcome, "_", suffix)
  dn <- paste0(den, "_", suffix)
  off <- paste0("log_", dn)
  absent <- setdiff(c(y, dn), names(d))
  if (length(absent)) stop("sens_case_f: missing column(s): ", paste(absent, collapse = ", "), call. = FALSE)
  d[, (off) := log(get(dn))]
  ex <- paste0("excluded_", outcome)
  d <- d[!(d[[ex]] %in% 1L) & d[[dn]] >= 20 & !is.na(d[[dn]])]
  list(data = d, spec = l_spec(y, offset = off), spec_t = t_spec(y, c("en_gest", "ln_gest"), offset = off),
       denom_col = dn)
}

# One sensitivity case of an outcome. `d` is the primary-window model table (read_perinatal_model("primary"), unfiltered:
# the outcome's rows are selected here), `d_fy2021` the 108-month table (read_perinatal_model("fy2021")). Returns
# list(id, data, l_spec, t_spec, l_extra, t_extra, l_reason, t_reason, l_contrasts, l_terms, fitter, denom_col, skip,
# text). A NULL spec is a not-applicable arm and its `*_reason` is the display; `skip` is the bare reason (the key displays `not estimable (<reason>)`) of a
# whole case (an unusable FY2020-21), else NA.
sens_case_f <- function(id, d, d_fy2021 = NULL, outcome) {
  if (length(id) != 1L || !id %in% SENS_IDS_F)
    stop("sens_case_f: unknown sensitivity: ", paste(id, collapse = ", "), call. = FALSE)
  if (length(outcome) != 1L || !outcome %in% OUTS) stop("sens_case_f: unknown outcome: ", outcome, call. = FALSE)
  data <- .base_rows(d, outcome)
  ls <- l_spec(outcome)
  ts <- t_spec_f(outcome)
  l_extra <- character(); t_extra <- character()
  l_con <- L_SUMMARY_CONTRASTS
  fitter <- "nb"; denom_col <- NA_character_; skip <- NA_character_
  if (id == "allcomp" && allcomp_identical(d, outcome))
    return(list(id = id, data = data, l_spec = NULL, t_spec = NULL, l_extra = l_extra, t_extra = t_extra,
                l_reason = ALLCOMP_IDENTICAL_NA, t_reason = ALLCOMP_IDENTICAL_NA, l_contrasts = l_con,
                l_terms = NULL, fitter = fitter, denom_col = denom_col, skip = NA_character_, text = SENS_TEXT_F[[id]]))
  switch(id,
    fy2021 = {
      if (is.null(d_fy2021)) stop("sens_case_f: fy2021 needs d_fy2021", call. = FALSE)
      data <- .base_rows(d_fy2021, outcome)
      ts <- t_spec_f(outcome, extra = c("covid_mar2020", "covid_lockdown", "covid_fy2021"))
      fy <- data[ym >= FY2021_FIRST_YM & is.finite(data[[outcome]]) & is.finite(data[[DENOM[[outcome]]]])]
      if (!nrow(fy)) skip <- "FY2020-21 has no usable link-unit-months"        # bare reason; the key wraps it once
    },
    betabin = { fitter <- "betabin"; denom_col <- .den_of(outcome) },
    inst_adj = {
      ex <- c("inst_share", if (outcome == "lbw") "wt_cov")
      ls <- l_spec(outcome, extra = ex); ts <- t_spec_f(outcome, extra = ex)
    },
    inst090 = data <- data[inst090_all_fy == 1L],
    comp050 = , masklow = , allcomp = {
      sw <- .swap_case(d, outcome, c(comp050 = "scaled", masklow = "masklow", allcomp = "allcomp")[[id]])
      data <- sw$data; ls <- sw$spec; ts <- sw$spec_t
    },
    single = data <- data[single_district == 1L],
    nosmall = data <- data[small_unit == 0L],
    ns4 = {
      basis <- dlm_basis(lags = 0:8, df = 4L)
      data <- ns_cross_basis(data, "tmax", basis)
      ls <- l_spec(outcome, heat = paste0("tmax_cb", 1:4))
      l_con <- ns4_contrasts(basis)
    },
    heatwave = {
      ls <- l_spec(outcome, heat = c("hw_t3", "hw_t2", "hw_t1"))
      l_con <- hw_contrasts()
    },
    state_moy = l_extra <- "state_unit:moy",
    era_int = t_extra <- "(1 | unit_era)",
    extra_prog = ts <- t_spec_f(outcome, extra = c("laqshya", "pmsma")),
    roni = ts <- t_spec_f(outcome, exposure = c("en_roni_gest", "ln_roni_gest")),
    drop_ep1415 = data <- data[!(ym >= EP_WINDOWS_F$ep1415[1] & ym <= EP_WINDOWS_F$ep1415[2])],
    drop_ep1819 = data <- data[!(ym >= EP_WINDOWS_F$ep1819[1] & ym <= EP_WINDOWS_F$ep1819[2])])
  lr <- sens_na_reason(id, "L")
  tr <- sens_na_reason(id, "T")
  if (!is.null(lr)) { ls <- NULL; l_extra <- character() }
  if (!is.null(tr)) { ts <- NULL; t_extra <- character() }
  list(id = id, data = data, l_spec = ls, t_spec = ts, l_extra = l_extra, t_extra = t_extra, l_reason = lr,
       t_reason = tr, l_contrasts = l_con, l_terms = unique(c(.contrast_terms(l_con), L_DRY, L_LEADS)),
       fitter = fitter, denom_col = denom_col, skip = skip, text = SENS_TEXT_F[[id]])
}

# ---- fitting one arm -----------------------------------------------------------------------------------------------

# Measured minutes of the primary fit of an outcome ("l" or "t", from the cached primary run), else the permuted-exposure
# timing: the basis of a bootstrap size under the 12-hour rule (boot_plan) when a fallback fires.
real_minutes <- function(arm, outcome, cache = F_CACHE) {
  f <- file.path(cache, sprintf("%s_%s.rds", tolower(arm), outcome))
  m <- if (file.exists(f)) readRDS(f)$minutes else NULL
  if (is.null(m) || !is.finite(m)) m <- timing_minutes(if (arm == "L") "model_l_primary" else "model_t_primary")
  m
}

# The fit function of an arm: the base fitter (NB2 or beta-binomial), wrapped by extra_fitter() when `extra` terms or
# carrier columns are needed (so the same function serves the original fit and every bootstrap refit). Returns
# list(spec (carriers appended to the fixed terms), fit_fun).
.arm_fitter <- function(spec, extra, fitter, denom_col, inner = e_glmmTMB_fit) {
  carriers <- unique(c(if (identical(fitter, "betabin")) setdiff(denom_col, c(spec_vars(spec), "unit_id", "ym", "ym_f")),
                       if (length(extra)) bootstrap_carriers(spec, extra)))
  base <- if (identical(fitter, "betabin")) betabin_fitter(denom_col, fit_fun = inner) else inner
  spec$fixed <- c(spec$fixed, carriers)
  list(spec = spec, fit_fun = if (length(extra) || length(carriers)) extra_fitter(extra, base, carriers) else base)
}

# Pre-flight of the formula path, outside fit_nb (which reads every fitter error as non-convergence): the final formula
# of the first fit (unit structure of the spec, plus the state-month effect for Model L or the ar1 time effect for Model
# T) is built through the same fitter layers with a capturing base fitter. A programming error in extra_fitter or the
# beta-binomial rewrite, a column the formula needs that `data` lacks, or an offset left in a beta-binomial formula
# stops the run here.
.preflight_arm <- function(arm, spec, data, extra, fitter, denom_col) {
  got <- NULL
  cap <- function(formula, data, family = NULL) { got <<- formula; invisible(NULL) }
  af <- .arm_fitter(spec, extra, fitter, denom_col, inner = cap)
  f0 <- spec_formula(af$spec, af$spec$re)
  tail <- if (arm == "L") L_RE else TIME_RE[["ar1"]]
  f0 <- stats::as.formula(paste(deparse1(f0, width.cutoff = 500L), "+", tail), env = environment(f0))
  af$fit_fun(f0, data)
  if (!inherits(got, "formula")) stop("preflight: the fitter did not receive a formula", call. = FALSE)
  txt <- deparse1(got, width.cutoff = 500L)
  vars <- all.vars(got)
  absent <- setdiff(vars[!vapply(vars, exists, NA, envir = baseenv())], names(data))
  if (length(absent)) stop("preflight: column(s) missing from the data: ", paste(absent, collapse = ", "), call. = FALSE)
  if (identical(fitter, "betabin") && (grepl("offset(", txt, fixed = TRUE) || !startsWith(txt, "cbind(")))
    stop("preflight: beta-binomial formula not rewritten: ", txt, call. = FALSE)
  invisible(got)
}

# Fit one arm and return its rows (primary-table schema) and the structure used. arm "L": fit_model_l with the contrasts;
# arm "T": the primary time chain for the exposure `term`. `label` goes in the outcome column.
fit_arm <- function(arm, spec, data, label, extra = character(), fitter = "nb", denom_col = NA_character_,
                    contrasts = L_SUMMARY_CONTRASTS, l_terms = NULL, term = "en_gest", cores = 1L, B = NULL,
                    minutes = NULL, progress = NULL, fit_fun = NULL, boot_fun = NULL) {
  af <- .arm_fitter(spec, extra, fitter, denom_col)
  if (is.null(fit_fun)) .preflight_arm(arm, spec, data, extra, fitter, denom_col)
  ff <- if (is.null(fit_fun)) af$fit_fun else fit_fun
  if (arm == "L") {
    if (is.null(B)) B <- boot_plan(if (is.null(minutes)) timing_minutes("model_l_primary") else minutes, B_L, B_L_REDUCED, cores)
    bf <- if (is.null(boot_fun)) function(spec, d, B, seed, cores, fit_fun, fit0, progress)
      cluster_bootstrap_state(spec, d, B = B, seed = seed, cores = cores, fit_fun = fit_fun, fit0 = fit0,
                              progress = progress, terms = l_terms) else boot_fun
    r <- fit_model_l(data, label, spec = af$spec, fit_fun = ff, B = B, cores = cores, boot_fun = bf,
                     progress = progress, contrasts = contrasts)
    return(list(rows = r$rows, structure = if (r$state_ym) "state_ym" else "cluster_bootstrap", boot_B = r$boot_B,
                B_ok = r$B_ok, n = r$n, n_units = r$n_units, re_used = r$re_used))
  }
  if (is.null(B)) B <- boot_plan(if (is.null(minutes)) timing_minutes("model_t_primary") else minutes, B_T, B_T_REDUCED, cores)
  bt <- if (is.null(boot_fun)) block_bootstrap_irr else boot_fun
  part <- .t_part(af$spec, data, term, c("ar1", "iid"), ff, bt, B, 12L, SEED_F, cores, progress)
  rows <- .t_rows(part, label, "T", term, B)
  list(rows = rows, structure = part$step,
       boot_B = if (identical(part$step, "block_bootstrap")) as.integer(B) else NA_integer_,
       B_ok = rows$B_ok[1], n = rows$n[1], n_units = rows$n_units[1], re_used = rows$re_used[1])
}

.tag_rows <- function(rows, ...) {
  rows <- data.table::copy(data.table::as.data.table(rows))
  a <- list(...)
  for (k in names(a)) data.table::set(rows, j = k, value = a[[k]])
  data.table::setcolorder(rows, c(names(a), setdiff(names(rows), names(a))))
  rows[]
}

# Rows of an arm that does not apply or whose case is not estimable (no fit): `display` is the key's display.
.sens_na_rows <- function(outcome, id, arm, terms, display, status = "not_applicable") {
  .tag_rows(.rows_na(outcome, arm, terms, status, display), case = id, arm = arm, note = SENS_TEXT_F[[id]])
}
SENS_TERMS_F <- list(L = c("heat_t3", "heat_gest", "dry_gest"), T = "en")

# One arm of one sensitivity case (a "sens" task): rows tagged with case, arm and note.
sens_arm_rows <- function(id, outcome, arm, d, d_fy2021 = NULL, cores = 1L, progress = NULL, case = NULL,
                          fit_arm_fun = fit_arm) {
  if (is.null(case)) case <- sens_case_f(id, d, d_fy2021, outcome)
  reason <- if (arm == "L") case$l_reason else case$t_reason
  if (!is.null(reason)) return(.sens_na_rows(outcome, id, arm, SENS_TERMS_F[[arm]], reason))
  if (!is.na(case$skip)) return(.sens_na_rows(outcome, id, arm, SENS_TERMS_F[[arm]], case$skip, status = "error"))
  spec <- if (arm == "L") case$l_spec else case$t_spec
  extra <- if (arm == "L") case$l_extra else case$t_extra
  term <- if (arm == "T") spec$fixed[1] else NULL
  r <- fit_arm_fun(arm, spec, case$data, outcome, extra = extra, fitter = case$fitter, denom_col = case$denom_col,
                   contrasts = case$l_contrasts, l_terms = case$l_terms, term = if (arm == "T") term else "en_gest",
                   cores = cores, minutes = real_minutes(arm, outcome), progress = progress)
  .tag_rows(r$rows, case = id, arm = arm, note = case$text)
}

# ---- selection audit ----------------------------------------------------------------------------------------------

# Rows of one denominator model and its spec: tb and wt as NB2 counts with offset log_days, inst as a beta-binomial
# cbind(inst, home) (response inst, denominator deliveries = inst + home; the offset is dropped by the fitter). Rows are
# the denominator's own gate exclusions only (no size rule: truncating the response would select on it).
selection_case <- function(d, den) {
  d <- data.table::copy(data.table::as.data.table(d))
  if (!den %in% SEL_DENOMS) stop("selection_case: unknown denominator: ", den, call. = FALSE)
  if (den == "inst_share") {
    d[, deliveries := inst + home]
    d <- d[!(excluded_inst %in% 1L) & !(excluded_home %in% 1L) & is.finite(deliveries) & deliveries >= 1]
    return(list(data = d, l_spec = l_spec("inst", offset = "log_days"),
                t_spec = t_spec("inst", c("en_gest", "ln_gest"), offset = "log_days"), fitter = "betabin",
                denom_col = "deliveries", outcome = "inst"))
  }
  ex <- paste0("excluded_", den)
  d <- d[!(d[[ex]] %in% 1L)]
  list(data = d, l_spec = l_spec(den, offset = "log_days"), t_spec = t_spec(den, c("en_gest", "ln_gest"), offset = "log_days"),
       fitter = "nb", denom_col = NA_character_, outcome = den)
}

# One arm of the selection audit for a denominator: rows with outcome = the denominator name.
selection_arm_rows <- function(den, arm, d, cores = 1L, progress = NULL, fit_arm_fun = fit_arm) {
  sc <- selection_case(d, den)
  spec <- if (arm == "L") sc$l_spec else sc$t_spec
  r <- fit_arm_fun(arm, spec, sc$data, den, fitter = sc$fitter, denom_col = sc$denom_col,
                   contrasts = L_SUMMARY_CONTRASTS, l_terms = NULL, term = "en_gest", cores = cores,
                   minutes = real_minutes(arm, "sb"), progress = progress)
  .tag_rows(r$rows, case = "selection", arm = arm,
            note = if (den == "inst_share") "beta-binomial logit of inst / (inst + home); odds ratio" else "NB2 count, offset log_days")
}

# The six audit fits (Model L and Model T for tb, wt and inst_share), one data.table.
selection_models <- function(d, cores = 1L, fit_arm_fun = fit_arm) {
  data.table::rbindlist(lapply(SEL_DENOMS, function(den) data.table::rbindlist(lapply(c("L", "T"), function(arm)
    selection_arm_rows(den, arm, d, cores = cores, fit_arm_fun = fit_arm_fun)))), fill = TRUE)
}

# ---- preterm and the sex-ratio negative control --------------------------------------------------------------------

# Preterm: birth months April 2017 to February 2020, rows without a gate exclusion and with the denominator >= 20.
preterm_data <- function(d) {
  d <- data.table::as.data.table(d)
  d[ym >= PRETERM_WINDOW_F[1] & ym <= PRETERM_WINDOW_F[2] & !(excluded_preterm %in% 1L) & !(small_denom_preterm %in% 1L)]
}
sexratio_data <- function(d) {
  d <- data.table::as.data.table(d)
  d[!(excluded_lb_m %in% 1L) & !(excluded_lb_f %in% 1L) & is.finite(lb_f) & lb_f >= 20]
}

secondary_arm_rows <- function(name, d, cores = 1L, progress = NULL, fit_arm_fun = fit_arm) {
  sp <- switch(name,
    preterm = list(data = preterm_data(d), spec = l_spec("preterm", offset = "log_lb"), label = "preterm",
                   note = "Model L, preterm per live birth (offset log_lb), April 2017 to February 2020"),
    sexratio = list(data = sexratio_data(d), spec = l_spec("lb_m", offset = "log_lb_f"), label = "lb_m",
                    note = "Model L, male live births with female live births as the offset (negative control)"),
    stop("secondary_arm_rows: unknown analysis: ", name, call. = FALSE))
  r <- fit_arm_fun("L", sp$spec, sp$data, sp$label, contrasts = L_SUMMARY_CONTRASTS, cores = cores,
                   minutes = real_minutes("L", "sb"), progress = progress)
  .tag_rows(r$rows, case = name, arm = "L", note = sp$note)
}
preterm_model <- function(d, cores = 1L, fit_arm_fun = fit_arm) secondary_arm_rows("preterm", d, cores, fit_arm_fun = fit_arm_fun)
sexratio_model <- function(d, cores = 1L, fit_arm_fun = fit_arm) secondary_arm_rows("sexratio", d, cores, fit_arm_fun = fit_arm_fun)

# ---- trimester rows (Figure 2) --------------------------------------------------------------------------------------

# The six stratum RRs of a Model L result (a fit_model_l() list or its rows table): exposure heat or dry, stratum tri1
# (first trimester) to tri3 (third), RR with its CI.
trimester_rows <- function(fit) {
  tab <- data.table::as.data.table(if (is.data.frame(fit)) fit else fit$rows)
  want <- as.vector(t(outer(c("heat", "dry"), paste0("tri", 1:3), paste, sep = "_")))
  r <- tab[term %in% want]
  if (!setequal(r$term, want) || anyDuplicated(r$term) > 0L)
    stop("trimester_rows: the six heat and dry strata are needed (one row each)", call. = FALSE)
  r <- r[match(want, term)]
  data.table::data.table(exposure = sub("_tri[0-9]$", "", r$term), stratum = sub("^[a-z]+_", "", r$term),
                         rr = r$rr, lo = r$lo, hi = r$hi)
}

# ---- tasks ---------------------------------------------------------------------------------------------------------

# Every fit of the run as a task list(kind, id, outcome, arm, name); not-applicable arms are not tasks. Order = rough
# expected duration, longest first, so that the workers finish together.
sec_task_id <- function(t) paste(c(t$kind, t$name, t$outcome, t$arm)[nzchar(c(t$kind, t$name, t$outcome, t$arm))], collapse = "_")
sec_tasks <- function(d, d_fy2021) {
  tasks <- list()
  for (o in OUTS) for (id in SENS_IDS_F) {
    cs <- sens_case_f(id, d, d_fy2021, o)
    for (arm in c("L", "T")) {
      if (!is.null(if (arm == "L") cs$l_reason else cs$t_reason) || !is.na(cs$skip)) next
      tasks[[length(tasks) + 1L]] <- list(kind = "sens", name = id, outcome = o, arm = arm)
    }
  }
  for (den in SEL_DENOMS) for (arm in c("L", "T"))
    tasks[[length(tasks) + 1L]] <- list(kind = "sel", name = den, outcome = "", arm = arm)
  for (nm in c("preterm", "sexratio")) tasks[[length(tasks) + 1L]] <- list(kind = "sec", name = nm, outcome = "", arm = "L")
  heavy <- c("betabin", "state_moy", "fy2021", "era_int", "inst_share", "ns4")
  pr <- vapply(tasks, function(t) if (t$name %in% heavy) match(t$name, heavy) else 99L, 0L)
  tasks[order(pr, vapply(tasks, function(t) t$arm == "T", NA))]
}

run_task <- function(t, d, d_fy2021, cores = 1L, progress = NULL) {
  switch(t$kind,
    sens = sens_arm_rows(t$name, t$outcome, t$arm, d, d_fy2021, cores = cores, progress = progress),
    sel = selection_arm_rows(t$name, t$arm, d, cores = cores, progress = progress),
    sec = secondary_arm_rows(t$name, d, cores = cores, progress = progress),
    stop("run_task: unknown task kind ", t$kind, call. = FALSE))
}

# A worker: claims tasks (an atomic dir.create of <id>.lock), runs them, and writes the rows (with minutes) to
# <cache>/<id>.rds; a failure other than an estimation failure writes <id>.err and the worker moves on. Stops when no
# unclaimed task remains.
run_worker <- function(tasks, d, d_fy2021, cache = SEC_CACHE, cores = 1L, log_file = "03_secondary.log",
                       worker = Sys.getpid()) {
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  lg <- function(...) flog(sprintf("[w%s] ", worker), ..., file = log_file)
  repeat {
    todo <- Filter(function(t) !file.exists(file.path(cache, paste0(sec_task_id(t), ".rds"))) &&
                     !file.exists(file.path(cache, paste0(sec_task_id(t), ".err"))), tasks)
    claimed <- NULL
    for (t in todo) if (dir.create(file.path(cache, paste0(sec_task_id(t), ".lock")), showWarnings = FALSE)) { claimed <- t; break }
    if (is.null(claimed)) { lg("no unclaimed task left"); break }
    id <- sec_task_id(claimed)
    lg(id, ": start")
    t0 <- proc.time()[["elapsed"]]
    last <- 0L
    prog <- function(k, n) { if (k %/% 10L > last %/% 10L || k == n) { lg(id, ": bootstrap ", k, " of ", n, " refits"); last <<- k }; invisible(NULL) }
    res <- tryCatch(run_task(claimed, d, d_fy2021, cores = cores, progress = prog), error = function(e) e)
    if (inherits(res, "error")) {
      writeLines(conditionMessage(res), file.path(cache, paste0(id, ".err")))
      lg(id, ": ERROR ", first_line(conditionMessage(res)))
      next
    }
    minutes <- (proc.time()[["elapsed"]] - t0) / 60
    data.table::set(res, j = "minutes", value = minutes)
    saveRDS(res, file.path(cache, paste0(id, ".rds")))
    r1 <- res[1]
    lg(id, ": done in ", sprintf("%.1f", minutes), " min; step ", r1$step, ", re ", r1$re_used, ", status ", r1$status,
       "; n ", r1$n, ", pd_hess ", r1$pd_hess, ", max_grad ", sprintf("%.3g", r1$max_grad))
  }
  invisible(TRUE)
}

# Remove the lock of every task that has no result (after a crash; run only while no worker is alive).
clear_stale_locks <- function(tasks, cache = SEC_CACHE) {
  n <- 0L
  for (t in tasks) {
    id <- sec_task_id(t)
    lk <- file.path(cache, paste0(id, ".lock"))
    if (dir.exists(lk) && !file.exists(file.path(cache, paste0(id, ".rds")))) { unlink(lk, recursive = TRUE); n <- n + 1L }
  }
  n
}

# ---- assembly --------------------------------------------------------------------------------------------------------

# The case-level n and n_units of a FY2020-21 row are not published (R2: row counts through March 2021 would give
# the FY2020-21 usable link-unit-months by difference).
.redact_fy2021 <- function(tab) {
  tab <- data.table::copy(tab)
  if ("case" %in% names(tab)) tab[case == "fy2021", `:=`(n = NA_integer_, n_units = NA_integer_)]
  tab[]
}

# Read the cached rows of every task and add the not-applicable rows; returns list(selection, secondary, sensitivity,
# minutes). Stops on a missing task or a recorded error.
assemble_secondary <- function(tasks, d, d_fy2021, cache = SEC_CACHE) {
  miss <- Filter(function(t) !file.exists(file.path(cache, paste0(sec_task_id(t), ".rds"))), tasks)
  if (length(miss)) {
    errs <- vapply(miss, function(t) {
      f <- file.path(cache, paste0(sec_task_id(t), ".err"))
      if (file.exists(f)) paste0(sec_task_id(t), ": ", first_line(readLines(f, n = 1L, warn = FALSE))) else paste0(sec_task_id(t), ": not run")
    }, "")
    stop("assemble_secondary: ", length(miss), " task(s) without a result:\n", paste(errs, collapse = "\n"), call. = FALSE)
  }
  got <- lapply(tasks, function(t) data.table::as.data.table(readRDS(file.path(cache, paste0(sec_task_id(t), ".rds")))))
  kind <- vapply(tasks, `[[`, "", "kind")
  sens <- data.table::rbindlist(got[kind == "sens"], fill = TRUE)
  na_rows <- list()
  for (o in OUTS) for (id in SENS_IDS_F) {
    cs <- sens_case_f(id, d, d_fy2021, o)
    for (arm in c("L", "T")) {
      reason <- if (arm == "L") cs$l_reason else cs$t_reason
      if (!is.null(reason)) na_rows[[length(na_rows) + 1L]] <- .sens_na_rows(o, id, arm, SENS_TERMS_F[[arm]], reason)
      else if (!is.na(cs$skip)) na_rows[[length(na_rows) + 1L]] <- .sens_na_rows(o, id, arm, SENS_TERMS_F[[arm]], cs$skip, "error")
    }
  }
  sens <- data.table::rbindlist(c(list(sens), na_rows), fill = TRUE)
  ord <- match(sens$case, SENS_IDS_F)
  sens <- sens[order(outcome, ord, arm)]
  list(selection = data.table::rbindlist(got[kind == "sel"], fill = TRUE),
       secondary = data.table::rbindlist(got[kind == "sec"], fill = TRUE), sensitivity = sens)
}

# ---- contract keys (sections 8 selection part, 10 and 11) ----------------------------------------------------------------

.fmt_row_rr <- function(r) fmt_rr_ci(r$rr, r$lo, r$hi)
.s6f <- function(x) if (is.null(x) || is.na(x)) "NA" else format(signif(x, 6), scientific = FALSE, trim = TRUE)

.step_text_f <- function(r) {
  if (is.na(r$step)) return("no structure selected")
  if (r$model == "L") {
    if (identical(r$step, "state_ym")) "state error: (1 | state_ym) random effect"
    else sprintf("state error: state-cluster bootstrap (B = %s, B_ok = %s)", r$boot_B, r$B_ok)
  } else if (identical(r$step, "block_bootstrap")) {
    sprintf("time effect: moving-block bootstrap over months (block 12, B = %s, B_ok = %s)", r$boot_B, r$B_ok)
  } else sprintf("time effect: %s", c(ar1 = "ar1(ym_f + 0 | national)", iid = "(1 | ym_f)")[[r$step]])
}

.est_text_f <- function(r, scale = c("RR", "OR")) {
  scale <- match.arg(scale)
  boot <- identical(r$p_kind, "bootstrap")
  nn <- if (is.na(r$n)) "unit-months and link units not reported (FY2020-21 row counts are withheld)" else
    sprintf("%s unit-months, %s link units", fmt_int(r$n), r$n_units)
  sprintf("%s; %s; unit random effect %s; log-scale coefficient %s, SE %s%s; %s %s (%s %s to %s); p %s (%s); seed SEED_F = %d",
          .step_text_f(r), nn, r$re_used, .s6f(r$est), .s6f(r$se), if (boot) " (bootstrap SD)" else "", scale, .s6f(r$rr),
          if (boot) sprintf("percentile 95%% CI over %s successful resamples", r$B_ok) else "Wald 95% CI",
          .s6f(r$lo), .s6f(r$hi), .s6f(r$p), if (boot) "two-sided Wald p from the bootstrap SE, no floor" else "two-sided Wald",
          SEED_F)
}

# One key from a rows table row `r` (a one-row table): the RR (or OR) display, or the null display of a not-applicable
# or not-estimable row.
.entry_from_row <- function(r, what, scale = "RR", script = SECONDARY_SCRIPT_F) {
  if (nrow(r) != 1L) stop(sprintf("secondary_entries: %d rows for %s", nrow(r), what), call. = FALSE)
  if (identical(r$status, "not_applicable"))
    return(res_entry(NA, r$error, script, sprintf("%s: %s", what, r$error)))
  if (!identical(r$status, "ok") || is.na(r$rr)) {
    why <- not_estimable(if (!is.na(r$error)) r$error else "estimate missing")
    return(res_entry(NA, why, script, sprintf("%s: %s", what, why)))
  }
  res_entry(r$rr, .fmt_row_rr(r), script, sprintf("%s. %s", what, .est_text_f(r, scale)))
}

# The 118 keys of contract section 8 (F.sel.*), section 10 (F.pre.*, F.nc.*) and section 11 (F.sens.*) from the three
# tables of assemble_secondary().
secondary_entries <- function(selection, secondary, sensitivity, script = SECONDARY_SCRIPT_F) {
  selection <- data.table::as.data.table(selection); secondary <- data.table::as.data.table(secondary)
  sensitivity <- data.table::as.data.table(sensitivity)
  E <- list()
  pick <- function(tab, ...) { f <- list(...); tab[Reduce(`&`, lapply(names(f), function(k) tab[[k]] == f[[k]]))] }
  S_TEXT <- c(heat_t3 = "per +1 deg C sustained over the third trimester", heat_gest = "per +1 deg C sustained over gestation",
              dry_gest = "per SPI -1 sustained over gestation", en = "per +1 deg C of the gestation-mean El Nino term en_gest")
  for (den in SEL_DENOMS) for (s in c("heat_t3", "heat_gest", "dry_gest", "en")) {
    r <- if (s == "en") pick(selection, outcome = den, model = "T", term = "en") else pick(selection, outcome = den, model = "L", term = s)
    sc <- if (den == "inst_share") "OR" else "RR"
    E[[sprintf("F.sel.%s.%s.rr", den, s)]] <- .entry_from_row(r, sprintf("Selection audit, %s: %s of %s %s (%s)", den,
      if (sc == "OR") "odds ratio" else "RR", s, S_TEXT[[s]],
      if (den == "inst_share") "beta-binomial logit of inst / (inst + home); no verdict" else "NB2 count, offset log_days; no verdict"),
      sc, script)
  }
  for (s in c("heat_t3", "heat_gest", "dry_gest"))
    E[[sprintf("F.pre.%s.rr", s)]] <- .entry_from_row(pick(secondary, case = "preterm", term = s),
      sprintf("Preterm births per live birth (offset log_lb), Model L, birth months April 2017 to February 2020, RR of %s (%s); no verdict", s, S_TEXT[[s]]),
      "RR", script)
  E[["F.nc.sexratio.heat_t3.rr"]] <- .entry_from_row(pick(secondary, case = "sexratio", term = "heat_t3"),
    "Negative-control outcome: male live births with female live births as the offset, Model L, RR of heat_t3 (per +1 deg C sustained over the third trimester); expected null or very small; no verdict",
    "RR", script)
  for (o in OUTS) for (id in SENS_IDS_F) for (k in c("heat", "dry", "en")) {
    row <- switch(k, heat = pick(sensitivity, outcome = o, case = id, arm = "L", term = if (o == "sb") "heat_t3" else "heat_gest"),
                  dry = pick(sensitivity, outcome = o, case = id, arm = "L", term = "dry_gest"),
                  en = pick(sensitivity, outcome = o, case = id, arm = "T", term = "en"))
    what <- sprintf("Sensitivity %s, %s: %s of the %s (%s); change from the primary model: %s. No verdict",
                    id, o, if (id == "betabin") "odds ratio (beta-binomial logit)" else "RR",
                    switch(k, heat = if (id == "heatwave") (if (o == "sb") "heat_t3 summary on heatwave days (per +1 heatwave day sustained over the third trimester)" else "heat_gest summary on heatwave days (per +1 heatwave day sustained over gestation)")
                                     else if (o == "sb") "heat_t3 summary (per +1 deg C sustained over the third trimester)" else "heat_gest summary (per +1 deg C sustained over gestation)",
                           dry = "dry_gest summary (per SPI -1 sustained over gestation)",
                           en = "Model T El Nino term (per +1 deg C of the gestation mean)"),
                    if (k == "en") "Model T" else "Model L", SENS_TEXT_F[[id]])
    E[[sprintf("F.sens.%s.%s.%s", o, id, k)]] <- .entry_from_row(row, what, if (id == "betabin") "OR" else "RR", script)
  }
  E
}
