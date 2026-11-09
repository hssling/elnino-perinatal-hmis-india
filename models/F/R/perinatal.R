# Paper F: Model L (local climate) and Model T (El Nino timing) helpers. Sourced after common_f.R. They call the
# common nb_spec / spec_formula / fit_nb and Paper E's t_spec / fit_time_chain / lin_comb unchanged.

L_HEAT <- c("tmax_t3", "tmax_t2", "tmax_t1")                     # trimester-mean Tmax, gestation strata
L_DRY <- c("spi3_dry_l0", "spi3_dry_l3", "spi3_dry_l6")          # SPI-3 deficit (dry part) at lags 0, 3 and 6
L_LEADS <- c("tmax_lead12", "spi3_dry_lead3")                    # negative-control leads
L_RE <- "(1 | state_ym)"                                         # state-month random effect, added by the fitter

# Model L (spec §5): <outcome> ~ heat strata + dry strata + leads + ym_f + offset + (1 + t_c | unit_id); the state-month
# random effect L_RE is added by the fitter (nb_fitter_with(L_RE)). No spline trend (year-month fixed effects).
l_spec <- function(outcome, heat = L_HEAT, extra = character(), offset = DENOM[[outcome]], slopes = "t_c",
                   re = "us") {
  nb_spec(outcome, fixed = c(heat, L_DRY, L_LEADS, "ym_f", extra), slopes = slopes, offset = offset, trend_df = 0L,
          re = re)
}

# Model T (spec §5): Paper E's Model T on the gestation-mean El Nino / La Nina exposures with the outcome's denominator.
t_spec_f <- function(outcome, exposure = c("en_gest", "ln_gest"), extra = character()) {
  t_spec(outcome, exposure, extra, offset = DENOM[[outcome]])
}

# Sustained-exposure summaries: RR = exp(sign * sum(beta[terms])): per +1 deg C sustained over the strata, or per SPI -1
# (a deficit of one unit) sustained, with the matching negative-control lead.
SUMMARIES <- list(
  heat_t3 = list(terms = "tmax_t3", sign = 1, lead = "tmax_lead12"),
  heat_gest = list(terms = L_HEAT, sign = 1, lead = "tmax_lead12"),
  dry_gest = list(terms = L_DRY, sign = -1, lead = "spi3_dry_lead3"))

.rr_from <- function(est, V, terms, sign) {
  lc <- lin_comb(est, V, terms)
  z <- stats::qnorm(0.975)
  b <- sign * lc$est
  ci <- sort(exp(c(b - z * lc$se, b + z * lc$se)))
  data.table::data.table(rr = exp(b), lo = ci[1], hi = ci[2], p = lc$p)
}
# On a coefficient vector and its covariance matrix (the arithmetic; unit-tested without a fit).
summary_rr_from <- function(est, V, s) .rr_from(est, V, s$terms, s$sign)
lead_rr_from <- function(est, V, s) .rr_from(est, V, s$lead, s$sign)
# On a fitted nbfit: the conditional-model fixed effects and their joint covariance.
summary_rr <- function(fit, s) {
  summary_rr_from(glmmTMB::fixef(fit$model)$cond, stats::vcov(fit$model)$cond, s)
}
lead_rr <- function(fit, s) {
  lead_rr_from(glmmTMB::fixef(fit$model)$cond, stats::vcov(fit$model)$cond, s)
}

# The six pre-registered tests (H10 stillbirth, H11 low birth weight): model L or T and the summary tested.
TESTS <- data.table::data.table(
  test_id = c("h10a", "h10b", "h10c", "h11a", "h11b", "h11c"),
  outcome = c("sb", "sb", "sb", "lbw", "lbw", "lbw"),
  model = c("L", "L", "T", "L", "L", "T"),
  summary = c("heat_t3", "dry_gest", "en", "heat_gest", "dry_gest", "en"))

# Simplified simulation models (R6, the power simulation): unit intercepts only, no slopes. Model L without L_RE;
# Model T is fitted with the iid time effect TIME_RE[["iid"]] (fit_time_chain(chain = "iid")).
sim_spec_l <- function(outcome) l_spec(outcome, slopes = character(), re = "int")
sim_spec_t <- function(outcome) {
  s <- t_spec_f(outcome)
  s$slopes <- character()
  s$re <- "int"
  s
}

# Timing data (R6): each column of `cols` permuted within unit_id (seeded; the caller's RNG state is restored).
# Outcomes, offsets and every other column are untouched, so a fit to these data carries no exposure information.
timing_data <- function(d, cols, seed = SEED_F) {
  d <- data.table::copy(d)
  absent <- setdiff(cols, names(d))
  if (length(absent)) stop("timing_data: missing column(s): ", paste(absent, collapse = ", "), call. = FALSE)
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  on.exit(if (is.null(old)) rm(list = ".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv()))
  set.seed(seed)
  for (cl in cols) d[, (cl) := .SD[[1L]][sample.int(.N)], by = unit_id, .SDcols = cl]
  d[]
}
