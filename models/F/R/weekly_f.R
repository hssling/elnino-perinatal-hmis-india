# Paper F (2026-11): weekly distributed-lag exposures across gestation, season-specific curves, RERI,
# E-values, selection and sensitivity analyses. The analysis plan is papers/F/analysis_plan_weekly.md
# (fixed 23 November 2026 before any weekly-exposure model); the keys are section 15 of papers/F/results_keys.md.
# Sourced from <repo>/models after common/R/load.R and F/R/common_f.R. Uses fixest (fepois, fenegbin); no dlnm: the
# lag basis is built by hand (Z = X B). No p-value and no test is computed anywhere in this file.

W_SEED <- 20261123L                       # bootstrap seed (analysis plan section 4)
W_B <- 500L                               # bootstrap resamples
W_DFS <- 3:6                              # candidate spline df (the same for heat and deficit), chosen by AIC
W_NW <- 40L                               # gestational weeks (term birth at 40 weeks)
W_NW39 <- 39L                             # sensitivity 4: alignment at 39 weeks
W_BLOCKS <- list(t1 = 1:13, t2 = 14:27, t3 = 28:40, gest = 1:40)
W_BLOCKS39 <- list(t1 = 1:13, t2 = 14:27, t3 = 28:39, gest = 1:39)
W_BLOCK_TEXT <- c(t1 = "weeks 1-13", t2 = "weeks 14-27", t3 = "weeks 28-40", gest = "weeks 1-40")
W_BLOCK_TEXT39 <- c(t1 = "weeks 1-13", t2 = "weeks 14-27", t3 = "weeks 28-39", gest = "weeks 1-39")
W_SEASONS <- c("winter", "summer", "monsoon", "postmonsoon")
W_SEASON_TEXT <- c(winter = "winter (December-February)", summer = "pre-monsoon summer (March-May)",
                   monsoon = "monsoon (June-September)", postmonsoon = "post-monsoon (October-November)")
W_EXPOSURES <- c(heat = 1, dry = -1)      # sign: heat per +1 deg C; deficit per one SPI unit more deficit (min(SPI, 0) - 1)
W_FE <- "unit_id + ym_f + state_unit^moy"
W_FE_RERI <- "unit_id + fy_f"
W_FE_TREND <- "unit_id[t_c] + ym_f + state_unit^moy"
W_SENS <- c("negbin", "trend", "inst090", "align39", "cluster2", "ipw")
W_SENS_TEXT <- c(negbin = "negative binomial (fixest::fenegbin) instead of Poisson",
                 trend = "link-unit-specific linear trends added",
                 inst090 = "link units with institutional share >= 0.90 in every primary financial year",
                 align39 = "gestational alignment at 39 weeks (weeks 1-39; the third block is weeks 28-39)",
                 cluster2 = "standard errors clustered two-way by link unit and year-month",
                 ipw = "inverse probability of inclusion weights (stabilised)")
W_SCRIPT <- "models/F/05_weekly.R"
W_LOG <- "05_weekly.log"
W_OUT <- file.path(F_DIR, "output")
W_CACHE <- F_CACHE
W_EXPOSURE_CSV <- file.path(REPO_ROOT, "data", "derived", "hmis", "perinatal_weekly_exposure.csv.gz")
W_ONI_CSV <- file.path(REPO_ROOT, "data", "derived", "hmis", "perinatal_weekly_oni.csv.gz")
W_LINK_UNITS_CSV <- file.path(REPO_ROOT, "pipeline", "reference", "hmis_link_units.csv")
W_MI_THRESHOLD <- 0.05
W_Z <- stats::qnorm(0.975)

# ------------------------------------------------------------------ formatting (reporting style)

# "1.04 (95% CI 1.01, 1.07)": two decimals, a comma inside the CI; U+2212 for a negative value.
fmt_w_ci <- function(est, lo, hi, digits = 2L) {
  out <- paste0(fmt_num(est, digits), " (95% CI ", fmt_num(lo, digits), ", ", fmt_num(hi, digits), ")")
  out[is.na(est) | is.na(lo) | is.na(hi)] <- NA_character_
  enc2utf8(out)
}
fmt_w_pct <- function(x) fmt_pct(x, 1L)
.sig6 <- function(x) formatC(x, digits = 6L, format = "g")

# ------------------------------------------------------------------ reading

.w_fread <- function(path) {
  con <- gzfile(path)
  lines <- tryCatch(readLines(con, warn = FALSE), finally = close(con))
  data.table::fread(text = lines, na.strings = c("", "NA", "NaN"))
}
read_weekly_exposure <- function(path = W_EXPOSURE_CSV) .w_fread(path)
read_weekly_oni <- function(path = W_ONI_CSV) .w_fread(path)

w_week_cols <- function(prefix, n = W_NW) sprintf("%s_w%02d", prefix, seq_len(n))
w_cb_names <- function(name, df) paste0(name, "_cb", seq_len(df))

season_of <- function(moy) {
  m <- as.integer(as.character(moy))
  out <- ifelse(m %in% c(12L, 1L, 2L), "winter", ifelse(m %in% 3:5, "summer", ifelse(m %in% 6:9, "monsoon", "postmonsoon")))
  factor(out, levels = W_SEASONS)
}

# ------------------------------------------------------------------ lag basis and cross-basis

# Natural cubic spline basis over weeks 1..n with an intercept (n x df): beta_w = B gamma.
w_basis <- function(n = W_NW, df = 4L) {
  b <- splines::ns(seq_len(n), df = df, intercept = TRUE)
  matrix(unclass(b)[, seq_len(df)], nrow = n, ncol = df, dimnames = list(paste0("w", seq_len(n)), NULL))
}

# Adds <name>_cb1..cb<k> = X B to a copy of d, X = the weekly columns <prefix>_w01..w<n>.
w_add_cb <- function(d, prefix, basis, name = prefix) {
  cols <- w_week_cols(prefix, nrow(basis))
  absent <- setdiff(cols, names(d))
  if (length(absent)) stop("w_add_cb: missing column(s): ", paste(head(absent, 5), collapse = ", "), call. = FALSE)
  d <- data.table::copy(data.table::as.data.table(d))
  cb <- as.matrix(d[, cols, with = FALSE]) %*% basis
  for (k in seq_len(ncol(basis))) data.table::set(d, j = paste0(name, "_cb", k), value = unname(cb[, k]))
  d[]
}

# Interaction columns <col>_<suffix> = <col> * indicator, for each col.
w_interact <- function(d, cols, indicator, suffix) {
  for (cl in cols) data.table::set(d, j = paste0(cl, "_", suffix), value = d[[cl]] * as.numeric(indicator))
  d
}

# ------------------------------------------------------------------ arithmetic (unit-tested without a fit)

# Week-specific estimates on the log scale: beta = B gamma, Var = B V B'. sign -1 turns the deficit into "one SPI unit
# more deficit". Returns week, est, se (of the signed log RR), rr, lo, hi.
w_curve_from <- function(gamma, V, basis, sign = 1) {
  b <- as.numeric(basis %*% gamma) * sign
  se <- unname(sqrt(pmax(diag(basis %*% V %*% t(basis)), 0)))
  data.table::data.table(week = seq_len(nrow(basis)), est = b, se = se, rr = exp(b), lo = exp(b - W_Z * se),
                         hi = exp(b + W_Z * se))
}

# Cumulative log RR over `weeks` (per +1 unit sustained over those weeks): a'gamma with a = colSums(B[weeks, ]); its SE
# sqrt(a' V a) equals the SE of the sum of the week-specific coefficients.
w_cum_from <- function(gamma, V, basis, weeks, sign = 1) {
  a <- colSums(basis[weeks, , drop = FALSE])
  est <- sign * sum(a * gamma)
  se <- sqrt(max(as.numeric(t(a) %*% V %*% a), 0))
  data.table::data.table(est = est, se = se, rr = exp(est), lo = exp(est - W_Z * se), hi = exp(est + W_Z * se))
}

# RERI = RR11 - RR10 - RR01 + 1.
reri_arith <- function(rr11, rr10, rr01) rr11 - rr10 - rr01 + 1

# From the RERI model's coefficients: RR10 = heat (sustained over `weeks`) in non-summer births; RR01 = summer birth at no
# anomaly; RR11 = both (the heat curve of summer births is the base curve plus the interaction).
reri_from <- function(coef, basis, weeks = W_BLOCKS$t3, heat = "heat", inter = "sm", summer = "summer") {
  a <- colSums(basis[weeks, , drop = FALSE])
  g0 <- coef[w_cb_names(heat, ncol(basis))]
  g1 <- coef[paste0(w_cb_names(heat, ncol(basis)), "_", inter)]
  if (anyNA(g0) || anyNA(g1) || is.na(coef[summer])) return(c(rr10 = NA_real_, rr01 = NA_real_, rr11 = NA_real_, reri = NA_real_))
  h0 <- sum(a * g0); h1 <- h0 + sum(a * g1); s <- unname(coef[summer])
  rr10 <- exp(h0); rr01 <- exp(s); rr11 <- exp(s + h1)
  c(rr10 = rr10, rr01 = rr01, rr11 = rr11, reri = reri_arith(rr11, rr10, rr01))
}

# E-value (VanderWeele and Ding 2017) for a risk ratio: RR + sqrt(RR (RR - 1)), with RR inverted below 1.
evalue_rr <- function(rr) {
  r <- ifelse(rr < 1, 1 / rr, rr)
  r + sqrt(r * (r - 1))
}
# E-value of the CI limit nearer 1: 1 when the interval contains 1.
evalue_ci <- function(rr, lo, hi) {
  ifelse(lo <= 1 & hi >= 1, 1, ifelse(rr > 1, evalue_rr(lo), evalue_rr(hi)))
}

# Stabilised inverse-probability-of-inclusion weights: P(included) / p_i for the included rows.
stabilised_weights <- function(included, p_hat) {
  w <- mean(included) / p_hat
  w[!included] <- NA_real_
  w
}

# Cluster bootstrap draws: row i = the link-unit indices (1..n_units, with replacement) of resample i. Drawn once from the
# seed, so the result does not depend on the number of workers.
w_boot_draws <- function(n_units, B = W_B, seed = W_SEED) {
  old <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  on.exit(if (is.null(old)) rm(list = ".Random.seed", envir = globalenv()) else assign(".Random.seed", old, envir = globalenv()))
  set.seed(seed)
  matrix(sample.int(n_units, n_units * B, replace = TRUE), nrow = B, byrow = TRUE)
}

# ------------------------------------------------------------------ data

# The primary-window model table joined to the weekly exposures and ONI terms, with the analysis flags:
# gate (excluded_sb == 0), outcome (sb and tb present), denom (tb >= 20), exposure (every weekly term and both negative
# controls present), included = all four.
w_prepare <- function(d, ex, oni) {
  d <- data.table::copy(data.table::as.data.table(d))
  if (any(d$in_primary != 1L)) stop("w_prepare: rows outside the primary window", call. = FALSE)
  ex <- data.table::as.data.table(ex)
  if (any(ex$ym > 2020L * 12L + 1L)) stop("w_prepare: exposure rows after February 2020", call. = FALSE)
  ex <- ex[, !c("year", "month"), with = FALSE]
  m <- merge(d, ex, by = c("link_id", "ym"), all.x = TRUE, sort = FALSE)
  m <- merge(m, data.table::as.data.table(oni)[, .(ym, en_gest_w, ln_gest_w)], by = "ym", all.x = TRUE, sort = FALSE)
  m[, season := season_of(moy)]
  m[, summer := as.integer(season == "summer")]
  m[, fy_f := factor(fy)]
  wcols <- c(w_week_cols("heat"), w_week_cols("dry"), "heat_nc8", "dry_nc8")
  w39 <- c(w_week_cols("heat39", W_NW39), w_week_cols("dry39", W_NW39), "heat_nc8", "dry_nc8")
  m[, ok_gate := !(excluded_sb %in% 1L)]
  m[, ok_outcome := !is.na(sb) & !is.na(tb) & is.finite(log_tb)]
  m[, ok_denom := !(small_denom_sb %in% 1L) & !is.na(tb) & tb >= 20]
  m[, ok_heat := stats::complete.cases(m[, c(w_week_cols("heat"), "heat_nc8"), with = FALSE])]
  m[, ok_dry := stats::complete.cases(m[, c(w_week_cols("dry"), "dry_nc8"), with = FALSE])]
  m[, ok_exposure := stats::complete.cases(m[, wcols, with = FALSE])]
  m[, ok_exposure39 := stats::complete.cases(m[, w39, with = FALSE])]
  m[, eligible := ok_gate & ok_outcome & ok_denom]
  m[, included := eligible & ok_exposure]
  data.table::setorder(m, unit_id, ym)
  m[]
}

# Analysis rows with the cross-bases of df `df` (and the 39-week ones when asked).
w_analysis <- function(m, df, align39 = FALSE) {
  rows <- if (align39) m[eligible == TRUE & ok_exposure39 == TRUE] else m[included == TRUE]
  if (align39) {
    b <- w_basis(W_NW39, df)
    rows <- w_add_cb(rows, "heat39", b, "heat"); rows <- w_add_cb(rows, "dry39", b, "dry")
  } else {
    b <- w_basis(W_NW, df)
    rows <- w_add_cb(rows, "heat", b, "heat"); rows <- w_add_cb(rows, "dry", b, "dry")
  }
  rows[]
}

# ------------------------------------------------------------------ fitting

W_THREADS <- 1L

# One fixest fit, kept compact: coefficients, cluster-robust covariance(s), AIC, the fitted sample.
w_fit <- function(d, rhs, fe = W_FE, family = c("poisson", "negbin"), weights = NULL, cluster = ~unit_id,
                  extra_vcov = list(), id = "fit") {
  family <- match.arg(family)
  f <- stats::as.formula(paste("sb ~", paste(rhs, collapse = " + "), "|", fe))
  t0 <- Sys.time()
  args <- list(fml = f, data = d, offset = ~log_tb, vcov = cluster, nthreads = W_THREADS, notes = FALSE)
  if (!is.null(weights)) args$weights <- weights
  fit <- if (family == "poisson") do.call(fixest::fepois, args) else do.call(fixest::fenegbin, args)
  cf <- stats::coef(fit)
  if (anyNA(cf[rhs])) stop("w_fit ", id, ": term(s) not estimated: ", paste(rhs[is.na(cf[rhs])], collapse = ", "), call. = FALSE)
  vx <- lapply(extra_vcov, function(cl) stats::vcov(fit, vcov = cl))
  list(id = id, family = family, fe = fe, rhs = rhs, coef = cf, vcov = stats::vcov(fit), extra_vcov = vx,
       aic = stats::AIC(fit), loglik = as.numeric(stats::logLik(fit)), nobs = stats::nobs(fit),
       n_units = unname(fit$fixef_sizes[["unit_id"]] %||% NA_integer_), n_removed = length(fit$obs_selection$obsRemoved),
       converged = isTRUE(fit$convStatus), theta = if (family == "negbin") as.numeric(fit$theta %||% NA) else NA,
       seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")))
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

w_rhs <- function(df, nc = TRUE) c(w_cb_names("heat", df), w_cb_names("dry", df), if (nc) c("heat_nc8", "dry_nc8"))

# Season model: each cross-basis interacted with the four seasons of birth (season main effects are absorbed by the
# state x calendar-month fixed effects).
w_season_data <- function(rows, df) {
  rows <- data.table::copy(rows)
  for (s in W_SEASONS) w_interact(rows, w_rhs(df, nc = FALSE), rows$season == s, s)
  rows[]
}
w_season_rhs <- function(df) c(unlist(lapply(W_SEASONS, function(s) paste0(w_rhs(df, nc = FALSE), "_", s))), "heat_nc8", "dry_nc8")

# RERI model data: cross-bases plus their interaction with summer; link unit + financial-year fixed effects.
w_reri_data <- function(rows, df) {
  rows <- data.table::copy(rows)
  w_interact(rows, w_rhs(df, nc = FALSE), rows$summer == 1L, "sm")
  rows[]
}
w_reri_rhs <- function(df) c(w_rhs(df, nc = FALSE), paste0(w_rhs(df, nc = FALSE), "_sm"), "heat_nc8", "dry_nc8", "summer")

# ------------------------------------------------------------------ summaries of a compact fit

w_gv <- function(fit, name, df, suffix = "", vc = NULL) {
  nm <- paste0(w_cb_names(name, df), suffix)
  V <- if (is.null(vc)) fit$vcov else vc
  list(g = fit$coef[nm], V = V[nm, nm, drop = FALSE])
}

w_curves <- function(fit, df, n = W_NW, suffix = "", vc = NULL) {
  b <- w_basis(n, df)
  data.table::rbindlist(lapply(names(W_EXPOSURES), function(e) {
    gv <- w_gv(fit, e, df, suffix, vc)
    r <- w_curve_from(gv$g, gv$V, b, W_EXPOSURES[[e]])
    data.table::data.table(exposure = e, r)
  }))
}

w_cums <- function(fit, df, n = W_NW, blocks = W_BLOCKS, suffix = "", vc = NULL) {
  b <- w_basis(n, df)
  data.table::rbindlist(lapply(names(W_EXPOSURES), function(e) {
    gv <- w_gv(fit, e, df, suffix, vc)
    data.table::rbindlist(lapply(names(blocks), function(k)
      data.table::data.table(exposure = e, block = k, w_cum_from(gv$g, gv$V, b, blocks[[k]], W_EXPOSURES[[e]]))))
  }))
}

w_nc <- function(fit, vc = NULL) {
  V <- if (is.null(vc)) fit$vcov else vc
  data.table::rbindlist(lapply(c(heat = "heat_nc8", dry = "dry_nc8"), function(t) {
    s <- if (t == "heat_nc8") 1 else -1
    est <- s * fit$coef[[t]]; se <- sqrt(V[t, t])
    data.table::data.table(term = t, est = est, se = se, rr = exp(est), lo = exp(est - W_Z * se), hi = exp(est + W_Z * se))
  }))
}

# ------------------------------------------------------------------ bootstrap (RERI)

w_boot_one <- function(i, draws, d, idx, rhs, df) {
  ids <- draws[i, ]
  rows <- unlist(idx[ids], use.names = FALSE)
  dd <- d[rows]
  dd[, unit_id := rep.int(seq_along(ids), lengths(idx[ids]))]
  f <- stats::as.formula(paste("sb ~", paste(rhs, collapse = " + "), "|", W_FE_RERI))
  out <- tryCatch({
    fit <- fixest::fepois(f, data = dd, offset = ~log_tb, vcov = "iid", nthreads = 1L, notes = FALSE, warn = FALSE)
    cf <- stats::coef(fit)
    c(reri_from(cf, w_basis(W_NW, df)), ok = as.numeric(isTRUE(fit$convStatus)))
  }, error = function(e) c(rr10 = NA_real_, rr01 = NA_real_, rr11 = NA_real_, reri = NA_real_, ok = 0))
  c(replicate = i, out)
}

w_bootstrap <- function(rr, df, B = W_B, seed = W_SEED, workers = 1L, log_file = W_LOG) {
  rhs <- w_reri_rhs(df)
  d <- rr[, c("unit_id", "sb", "log_tb", "fy_f", rhs), with = FALSE]
  d[, unit_id := as.integer(droplevels(unit_id))]
  data.table::setorder(d, unit_id)
  n_units <- max(d$unit_id)
  idx <- split(seq_len(nrow(d)), d$unit_id)
  draws <- w_boot_draws(n_units, B, seed)
  t0 <- Sys.time()
  if (workers > 1L) {
    cl <- parallel::makeCluster(workers)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterCall(cl, function(lp) { .libPaths(lp); suppressMessages({ library(data.table); library(fixest) }); NULL }, .libPaths())
    parallel::clusterExport(cl, c("w_boot_one", "reri_from", "reri_arith", "w_basis", "w_cb_names", "W_NW", "W_FE_RERI",
                                  "W_BLOCKS"), envir = globalenv())
    res <- parallel::parLapplyLB(cl, seq_len(B), w_boot_one, draws = draws, d = d, idx = idx, rhs = rhs, df = df)
  } else {
    res <- lapply(seq_len(B), w_boot_one, draws = draws, d = d, idx = idx, rhs = rhs, df = df)
  }
  out <- data.table::as.data.table(do.call(rbind, res))
  out[, replicate := as.integer(replicate)]
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  flog(sprintf("bootstrap: %d resamples, %d workers, %.1f min", B, workers, secs / 60), file = log_file)
  list(replicates = out, seconds = secs, workers = workers, B = B, seed = seed, n_units = n_units)
}

# ------------------------------------------------------------------ selection and IPW

# Inclusion model (logistic): included ~ state + financial year + log live births + institutional share, each covariate
# with a missing indicator (value set to the mean of the observed values), on every primary-window unit-month.
w_ipw <- function(m) {
  x <- m[, .(included = as.integer(included), state_unit = factor(state_unit), fy_f = factor(fy),
             lb_log = ifelse(!is.na(lb) & lb > 0, log(lb), NA_real_), inst = inst_share)]
  x[, lb_miss := as.integer(is.na(lb_log))]; x[is.na(lb_log), lb_log := mean(x$lb_log, na.rm = TRUE)]
  x[, inst_miss := as.integer(is.na(inst))]; x[is.na(inst), inst := mean(x$inst, na.rm = TRUE)]
  g <- stats::glm(included ~ state_unit + fy_f + lb_log + lb_miss + inst + inst_miss, data = x, family = stats::binomial())
  p <- stats::fitted(g)
  sw <- stabilised_weights(x$included == 1L, p)
  list(sw = sw, p = p, model = list(coef = stats::coef(g), aic = stats::AIC(g), n = nrow(x)))
}

w_selection_table <- function(m) {
  grp <- function(sel, label) {
    x <- m[sel]
    data.table::data.table(group = label, n = nrow(x), n_units = data.table::uniqueN(x$link_id),
      inst_share_mean = mean(x$inst_share, na.rm = TRUE), inst_share_n = sum(!is.na(x$inst_share)),
      lb_median = stats::median(x$lb, na.rm = TRUE), lb_n = sum(!is.na(x$lb)),
      tb_median = stats::median(x$tb, na.rm = TRUE), tb_n = sum(!is.na(x$tb)))
  }
  main <- data.table::rbindlist(list(grp(m$included, "included"), grp(!m$included, "excluded")))
  st <- m[, .N, by = .(state_unit, group = ifelse(included, "included", "excluded"))]
  st[, share := N / sum(N), by = group]
  yr <- m[, .N, by = .(year, group = ifelse(included, "included", "excluded"))]
  yr[, share := N / sum(N), by = group]
  list(main = main,
       state = data.table::dcast(st, state_unit ~ group, value.var = c("N", "share"), fill = 0),
       year = data.table::dcast(yr, year ~ group, value.var = c("N", "share"), fill = 0))
}

w_flow <- function(m, units_csv = W_LINK_UNITS_CSV, fit = NULL) {
  u <- data.table::fread(units_csv, colClasses = "character", na.strings = character())
  g <- u[kind == "gadm"]
  s0 <- rep(TRUE, nrow(m))
  s1 <- s0 & m$ok_gate; s2 <- s1 & m$ok_outcome; s3 <- s2 & m$ok_denom; s4 <- s3 & m$ok_exposure
  heat_only <- s3 & !m$ok_heat; dry_only <- s3 & m$ok_heat & !m$ok_dry
  data.table::data.table(
    step = c("n_districts", "n_link_units", "n_unit_months", "excl_gate", "excl_outcome", "excl_denom", "excl_exposure",
             "excl_exposure_heat", "excl_exposure_dry", "n_analysed", "n_units_analysed", "n_fit_dropped", "n_fit", "n_units_fit"),
    n = c(data.table::uniqueN(g$region_id), data.table::uniqueN(m$link_id), nrow(m), sum(s0 & !s1), sum(s1 & !s2),
          sum(s2 & !s3), sum(s3 & !s4), sum(heat_only), sum(dry_only), sum(s4), data.table::uniqueN(m$link_id[s4]),
          if (is.null(fit)) NA else fit$n_removed, if (is.null(fit)) NA else fit$nobs, if (is.null(fit)) NA else fit$n_units),
    text = c("GADM districts in the link units", "link units", "link-unit-months, April 2012 to February 2020",
             "unit-months of link units excluded by the stillbirth gates", "stillbirths or total births missing (masked or not reported)",
             "total births below 20", "a weekly exposure or negative control missing",
             "of which heat or its negative control missing", "of which only the deficit or its negative control missing",
             "unit-months analysed (complete cases)", "link units analysed",
             "unit-months dropped by the Poisson fit (link units or fixed-effect groups with no stillbirth)",
             "unit-months in the fitted primary model", "link units in the fitted primary model"))
}

w_missing <- function(m) {
  any_na <- function(cols) !stats::complete.cases(m[, cols, with = FALSE])
  v <- list(sb = is.na(m$sb), tb = is.na(m$tb), heat = any_na(w_week_cols("heat")), dry = any_na(w_week_cols("dry")),
            heat_nc8 = is.na(m$heat_nc8), dry_nc8 = is.na(m$dry_nc8), oni = is.na(m$en_gest_w) | is.na(m$ln_gest_w),
            inst_share = is.na(m$inst_share), lb = is.na(m$lb))
  tab <- data.table::data.table(variable = names(v), n = nrow(m), n_missing = vapply(v, sum, 0), share = vapply(v, mean, 0))
  n_incl <- sum(m$included); n_el <- sum(m$eligible)
  loss <- data.table::data.table(variable = c("cc_loss_panel", "cc_loss_eligible"), n = c(nrow(m), n_el),
                                 n_missing = c(nrow(m) - n_incl, n_el - n_incl), share = c(1 - n_incl / nrow(m), 1 - n_incl / n_el))
  data.table::rbindlist(list(tab, loss))
}

# ------------------------------------------------------------------ results: tables, entries, results.json

.w_round <- function(dt) {
  dt <- data.table::copy(dt)
  for (cl in names(dt)) if (is.double(dt[[cl]])) data.table::set(dt, j = cl, value = signif(dt[[cl]], 7))
  dt
}
.w_write <- function(dt, name, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(.w_round(dt), file.path(out_dir, name), eol = "\n")
}

w_percentile <- function(x) {
  x <- x[is.finite(x)]
  if (!length(x)) return(c(NA_real_, NA_real_))
  unname(stats::quantile(x, c(0.025, 0.975), type = 7))
}

.w_addl <- function(dt, ...) {
  a <- list(...)
  for (k in names(a)) data.table::set(dt, j = k, value = a[[k]])
  dt
}

# All tables of the results step, from the cached fits (no model is fitted here).
w_tables <- function(cache = W_CACHE) {
  info <- readRDS(file.path(cache, "w_fits.rds"))
  df <- info$df
  rd <- function(id) readRDS(file.path(cache, paste0("w_fit_", id, ".rds")))
  prim <- rd(paste0("pooled_df", df)); season <- rd(paste0("season_df", df)); reri <- rd(paste0("reri_df", df))
  sens_fit <- list(negbin = rd(paste0("sens_negbin_df", df)), trend = rd(paste0("sens_trend_df", df)),
                   inst090 = rd(paste0("sens_inst090_df", df)), align39 = rd(paste0("sens_align39_df", df)),
                   ipw = rd(paste0("sens_ipw_df", df)))
  enso <- rd("enso")
  boot <- readRDS(file.path(cache, "w_boot.rds"))
  curves <- data.table::rbindlist(c(list(.w_addl(w_curves(prim, df), model = "pooled", season = "all")),
    lapply(W_SEASONS, function(s) .w_addl(w_curves(season, df, suffix = paste0("_", s)), model = "season", season = s))), use.names = TRUE)
  cum <- data.table::rbindlist(c(list(.w_addl(w_cums(prim, df), model = "pooled", season = "all")),
    lapply(W_SEASONS, function(s) .w_addl(w_cums(season, df, suffix = paste0("_", s)), model = "season", season = s))), use.names = TRUE)
  cum[, display := fmt_w_ci(rr, lo, hi)]
  nc <- w_nc(prim)[, display := fmt_w_ci(rr, lo, hi)]
  aic <- data.table::copy(info$aic)[, `:=`(chosen = df == info$df, delta = aic - min(aic))]
  aic_season <- data.table::copy(info$aic_season)[, delta := aic - min(aic)]
  # RERI: point estimate from the full data, percentile interval from the bootstrap
  pt <- reri_from(reri$coef, w_basis(W_NW, df))
  reps <- boot$replicates
  ok <- reps[is.finite(reri) & ok == 1]
  reri_tab <- data.table::data.table(quantity = c("rr10", "rr01", "rr11", "reri"), est = unname(pt[c("rr10", "rr01", "rr11", "reri")]))
  ci <- t(vapply(reri_tab$quantity, function(q) w_percentile(ok[[q]]), c(0, 0)))
  reri_tab[, `:=`(lo = ci[, 1], hi = ci[, 2], n_boot = nrow(ok), B = boot$B, seed = boot$seed, workers = boot$workers,
                  boot_minutes = boot$seconds / 60)]
  reri_tab[, display := fmt_w_ci(est, lo, hi)]
  # E-values of the cumulative third-trimester and whole-gestation heat RRs
  ev <- cum[model == "pooled" & exposure == "heat" & block %in% c("t3", "gest")]
  evalues <- ev[, .(exposure, block, rr, lo, hi, evalue_est = evalue_rr(rr), evalue_ci = evalue_ci(rr, lo, hi))]
  # sensitivity analyses
  sens <- data.table::rbindlist(lapply(W_SENS, function(s) {
    if (s == "cluster2") {
      f <- prim; r <- w_cums(prim, df, vc = prim$extra_vcov$cluster2)
    } else if (s == "align39") {
      f <- sens_fit[[s]]; r <- w_cums(f, df, n = W_NW39, blocks = W_BLOCKS39)
    } else {
      f <- sens_fit[[s]]; r <- w_cums(f, df)
    }
    r[, `:=`(analysis = s, n = f$nobs, n_units = f$n_units, text = W_SENS_TEXT[[s]])]
    r
  }))
  sens[, display := fmt_w_ci(rr, lo, hi)]
  # ENSO: El Nino part per +1 deg C; La Nina part per 1 deg C stronger La Nina (ONI 1 deg C lower)
  en <- data.table::rbindlist(lapply(c(en = "en_gest_w", ln = "ln_gest_w"), function(t) {
    s <- if (t == "en_gest_w") 1 else -1
    est <- s * enso$coef[[t]]; se <- sqrt(enso$vcov[t, t])
    data.table::data.table(term = t, est = est, se = se, rr = exp(est), lo = exp(est - W_Z * se), hi = exp(est + W_Z * se),
                           n = enso$nobs, n_units = enso$n_units)
  }))
  en[, display := fmt_w_ci(rr, lo, hi)]
  list(info = info, df = df, prim = prim, season = season, reri_fit = reri, enso_fit = enso, curves = curves, cum = cum,
       nc = nc, aic = aic, aic_season = aic_season, reri = reri_tab, boot = reps, evalues = evalues, sens = sens, enso = en,
       flow = info$flow, missing = info$missing, selection = info$selection, ipw = info$ipw)
}

w_write_tables <- function(R, out_dir = W_OUT) {
  .w_write(R$curves[, .(model, season, exposure, week, est, se, rr, lo, hi)], "w_curves.csv", out_dir)
  .w_write(R$cum[, .(model, season, exposure, block, est, se, rr, lo, hi, display)], "w_cumulative.csv", out_dir)
  .w_write(R$nc[, .(term, est, se, rr, lo, hi, display)], "w_negative_controls.csv", out_dir)
  .w_write(R$aic, "w_aic_df.csv", out_dir)
  .w_write(R$aic_season, "w_aic_season.csv", out_dir)
  .w_write(R$reri, "w_reri.csv", out_dir)
  .w_write(R$boot, "w_reri_boot.csv", out_dir)
  .w_write(R$evalues, "w_evalues.csv", out_dir)
  .w_write(R$selection$main, "w_selection.csv", out_dir)
  .w_write(R$selection$state, "w_selection_state.csv", out_dir)
  .w_write(R$selection$year, "w_selection_year.csv", out_dir)
  .w_write(R$flow, "w_flow.csv", out_dir)
  .w_write(R$sens[, .(analysis, exposure, block, est, se, rr, lo, hi, display, n, n_units, text)], "w_sensitivity.csv", out_dir)
  .w_write(R$enso, "w_enso.csv", out_dir)
  .w_write(R$missing, "w_missing.csv", out_dir)
  invisible(out_dir)
}

.w_ent <- function(value, display, description) res_entry(value, enc2utf8(display), W_SCRIPT, enc2utf8(description))

# The F.w.* entries (contract section 15).
w_entries <- function(R) {
  E <- list()
  put <- function(k, value, display, description) E[[k]] <<- .w_ent(value, display, description)
  df <- R$df
  src <- "fixest::fepois, offset log total births, fixed effects link unit + year-month + state x calendar month, SEs clustered by link unit"
  rrdesc <- function(r, what, n = R$prim$nobs, nu = R$prim$n_units)
    sprintf("%s. RR %s (95%% CI %s, %s); log RR %s, SE %s. %s; n = %d unit-months in %d link units; spline df %d (AIC)",
            what, .sig6(r$rr), .sig6(r$lo), .sig6(r$hi), .sig6(r$est), .sig6(r$se), src, n, nu, df)
  put("F.w.df", df, as.character(df), "Degrees of freedom of the natural cubic spline lag basis over weeks 1-40 (intercept included), the same for heat and deficit, chosen by the lowest AIC among 3, 4, 5 and 6 in the pooled primary model")
  for (k in W_DFS) {
    a <- R$aic[df == k]
    put(sprintf("F.w.aic.df%d", k), a$aic, fmt_num(a$aic, 1),
        sprintf("AIC of the pooled primary model with spline df %d (n = %d); difference from the lowest %.2f", k, a$nobs, a$delta))
  }
  for (k in c("pooled", "season")) {
    a <- R$aic_season[model == k]
    put(sprintf("F.w.aic.%s", k), a$aic, fmt_num(a$aic, 1),
        sprintf("AIC of the %s model at df %d (n = %d); difference from the lower of the two %.2f",
                if (k == "pooled") "pooled" else "season-specific (cross-bases interacted with season of birth)", df, a$nobs, a$delta))
  }
  put("F.w.n", R$prim$nobs, fmt_int(R$prim$nobs), "Unit-months in the fitted primary model (complete cases; link units or fixed-effect groups with no stillbirth dropped by fixest)")
  put("F.w.n_units", R$prim$n_units, fmt_int(R$prim$n_units), "Link units in the fitted primary model")
  for (e in names(W_EXPOSURES)) for (b in names(W_BLOCKS)) {
    r <- R$cum[model == "pooled" & exposure == e & block == b]
    what <- if (e == "heat") sprintf("Cumulative RR per +1 deg C Tmax anomaly sustained over %s of gestation", W_BLOCK_TEXT[[b]]) else
      sprintf("Cumulative RR per one SPI-28 unit more deficit sustained over %s of gestation", W_BLOCK_TEXT[[b]])
    put(sprintf("F.w.%s.%s", e, b), r$rr, fmt_w_ci(r$rr, r$lo, r$hi), rrdesc(r, what))
  }
  for (t in c("heat", "dry")) {
    r <- R$nc[term == paste0(t, "_nc8")]
    what <- if (t == "heat") "Negative control: RR per +1 deg C mean Tmax anomaly over the 8 weeks after birth" else
      "Negative control: RR per one SPI-28 unit more deficit at the end of the 8th week after birth"
    put(sprintf("F.w.nc.%s", t), r$rr, fmt_w_ci(r$rr, r$lo, r$hi), rrdesc(r, what))
  }
  for (s in W_SEASONS) for (e in names(W_EXPOSURES)) for (b in names(W_BLOCKS)) {
    r <- R$cum[model == "season" & season == s & exposure == e & block == b]
    what <- sprintf("Season-specific model, births in %s: cumulative RR per %s sustained over %s", W_SEASON_TEXT[[s]],
                    if (e == "heat") "+1 deg C Tmax anomaly" else "one SPI-28 unit more deficit", W_BLOCK_TEXT[[b]])
    put(sprintf("F.w.season.%s.%s.%s", s, e, b), r$rr, fmt_w_ci(r$rr, r$lo, r$hi), rrdesc(r, what, R$season$nobs, R$season$n_units))
  }
  rr <- R$reri
  rtext <- c(rr10 = "RR10: +1 deg C sustained over weeks 28-40 in births outside March-May, against no anomaly",
             rr01 = "RR01: summer (March-May) birth against other months, at no anomaly",
             rr11 = "RR11: summer birth with +1 deg C sustained over weeks 28-40, against non-summer births with no anomaly",
             reri = "RERI = RR11 - RR10 - RR01 + 1 (summer birth x third-trimester heat)")
  for (q in rr$quantity) {
    r <- rr[quantity == q]
    put(sprintf("F.w.reri.%s", q), r$est, fmt_w_ci(r$est, r$lo, r$hi),
        sprintf("%s. Estimate %s; 95%% CI %s, %s: percentile interval of %d successful link-unit cluster bootstrap resamples of %d (seed %d). Model: fepois with link unit + financial year fixed effects, a summer indicator, heat and deficit cross-bases (df %d) and their interaction with summer, both negative controls; n = %d",
                rtext[[q]], .sig6(r$est), .sig6(r$lo), .sig6(r$hi), r$n_boot, r$B, r$seed, df, R$reri_fit$nobs))
  }
  put("F.w.reri.n_boot", rr$n_boot[1], fmt_int(rr$n_boot[1]), sprintf("Bootstrap resamples (of %d) with a converged RERI model fit", rr$B[1]))
  for (b in c("t3", "gest")) {
    r <- R$evalues[block == b]
    put(sprintf("F.w.evalue.heat_%s.est", b), r$evalue_est, fmt_num(r$evalue_est, 2),
        sprintf("E-value (VanderWeele and Ding) of the cumulative heat RR over %s, %s", W_BLOCK_TEXT[[b]], .sig6(r$rr)))
    put(sprintf("F.w.evalue.heat_%s.ci", b), r$evalue_ci, fmt_num(r$evalue_ci, 2),
        sprintf("E-value of the 95%% CI limit nearer 1 of the cumulative heat RR over %s (CI %s, %s; 1 when the interval contains 1)",
                W_BLOCK_TEXT[[b]], .sig6(r$lo), .sig6(r$hi)))
  }
  sm <- R$selection$main
  for (g in c("included", "excluded")) {
    x <- sm[group == g]; k <- if (g == "included") "incl" else "excl"
    put(sprintf("F.w.sel.%s.n", k), x$n, fmt_int(x$n), sprintf("Unit-months %s in the primary model (primary window)", g))
    put(sprintf("F.w.sel.%s.inst_share", k), x$inst_share_mean, fmt_w_pct(x$inst_share_mean),
        sprintf("Mean institutional share of deliveries (inst / (inst + home)) over the %s unit-months with it (n = %d)", g, x$inst_share_n))
    put(sprintf("F.w.sel.%s.births", k), x$lb_median, fmt_num(x$lb_median, 0),
        sprintf("Median live births per unit-month over the %s unit-months with it (n = %d); median total births %s (n = %d)", g, x$lb_n,
                .sig6(x$tb_median), x$tb_n))
  }
  put("F.w.ipw.sw_min", R$ipw$sw_min, fmt_num(R$ipw$sw_min, 2), "Smallest stabilised inclusion weight among analysed unit-months (logistic inclusion model: state, financial year, log live births and institutional share, each with a missing indicator)")
  put("F.w.ipw.sw_max", R$ipw$sw_max, fmt_num(R$ipw$sw_max, 2), sprintf("Largest stabilised inclusion weight among analysed unit-months (mean %s)", .sig6(R$ipw$sw_mean)))
  for (s in W_SENS) for (e in names(W_EXPOSURES)) for (b in names(W_BLOCKS)) {
    r <- R$sens[analysis == s & exposure == e & block == b]
    bt <- if (s == "align39") W_BLOCK_TEXT39[[b]] else W_BLOCK_TEXT[[b]]
    put(sprintf("F.w.sens.%s.%s.%s", s, e, b), r$rr, fmt_w_ci(r$rr, r$lo, r$hi),
        sprintf("Sensitivity %s (%s): cumulative RR per %s sustained over %s. RR %s (95%% CI %s, %s); log RR %s, SE %s; n = %d unit-months in %d link units",
                s, W_SENS_TEXT[[s]], if (e == "heat") "+1 deg C Tmax anomaly" else "one SPI-28 unit more deficit", bt,
                .sig6(r$rr), .sig6(r$lo), .sig6(r$hi), .sig6(r$est), .sig6(r$se), r$n, r$n_units))
  }
  for (t in c("en", "ln")) {
    r <- R$enso[term == paste0(t, "_gest_w")]
    what <- if (t == "en") "RR per +1 deg C of the El Nino part max(ONI, 0) averaged over the 40 gestational weeks" else
      "RR per 1 deg C stronger La Nina (the La Nina part min(ONI, 0) averaged over the 40 gestational weeks, 1 deg C lower)"
    put(sprintf("F.w.enso.%s", t), r$rr, fmt_w_ci(r$rr, r$lo, r$hi),
        sprintf("%s. RR %s (95%% CI %s, %s); log RR %s, SE %s. fepois with link unit + state x calendar-month fixed effects and a linear trend (no year-month effects), SEs clustered by year-month; n = %d unit-months in %d link units; two El Nino episodes fall in the window",
                what, .sig6(r$rr), .sig6(r$lo), .sig6(r$hi), .sig6(r$est), .sig6(r$se), r$n, r$n_units))
  }
  put("F.w.enso.n", R$enso_fit$nobs, fmt_int(R$enso_fit$nobs), "Unit-months in the El Nino secondary model")
  mi <- R$missing
  mtext <- c(sb = "stillbirths", tb = "total births", heat = "any weekly heat exposure (weeks 1-40)",
             dry = "any weekly deficit exposure (weeks 1-40)", heat_nc8 = "the heat negative control", dry_nc8 = "the deficit negative control")
  for (v in names(mtext)) {
    x <- mi[variable == v]
    put(sprintf("F.w.missing.%s", v), x$share, fmt_w_pct(x$share),
        sprintf("Share of the %d primary-window unit-months missing %s (%d)", x$n, mtext[[v]], x$n_missing))
  }
  x <- mi[variable == "cc_loss_panel"]
  put("F.w.missing.cc_loss_panel", x$share, fmt_w_pct(x$share),
      sprintf("Complete-case loss of the primary model: share of the %d primary-window unit-months not analysed (%d), the measure of the 5%% rule", x$n, x$n_missing))
  x <- mi[variable == "cc_loss_eligible"]
  put("F.w.missing.cc_loss_eligible", x$share, fmt_w_pct(x$share),
      sprintf("Share of the %d unit-months with a valid outcome and denominator dropped for a missing exposure (%d)", x$n, x$n_missing))
  meth <- if (mi[variable == "cc_loss_panel"]$share < W_MI_THRESHOLD) "complete-case analysis" else "multiple imputation"
  put("F.w.missing.method", meth, meth, "Missing-data method under the plan's rule (complete-case analysis when the complete-case loss is below 5%)")
  fl <- R$flow
  for (s in c("n_districts", "n_link_units", "n_unit_months", "excl_gate", "excl_outcome", "excl_denom", "excl_exposure",
              "n_analysed", "n_units_analysed", "n_fit_dropped")) {
    x <- fl[step == s]
    put(sprintf("F.w.flow.%s", s), x$n, fmt_int(x$n), paste0("Flow chart: ", x$text))
  }
  E[order(names(E), method = "radix")]
}

# Appends the F.w.* entries to results.json as text: every existing entry keeps its bytes (the F.w keys sort after every
# existing key); earlier F.w entries are replaced. The file's line ending is kept.
w_splice_results <- function(entries, path = file.path(PAPER_F, "results.json")) {
  if (!all(startsWith(names(entries), "F.w."))) stop("w_splice_results: only F.w keys", call. = FALSE)
  raw <- readChar(path, file.info(path)$size, useBytes = TRUE)
  eol <- if (grepl("\r\n", raw, fixed = TRUE)) "\r\n" else "\n"
  old_keys <- names(jsonlite::fromJSON(path, simplifyVector = FALSE))
  base_keys <- old_keys[!startsWith(old_keys, "F.w.")]
  all_keys <- c(base_keys, names(entries))
  if (!identical(all_keys, all_keys[order(all_keys, method = "radix")]))
    stop("w_splice_results: the F.w keys do not sort after the existing keys", call. = FALSE)
  cut <- regexpr(paste0(",", eol, "  \"F.w."), raw, fixed = TRUE)
  body <- if (cut > 0) substr(raw, 1L, cut - 1L) else sub(paste0(eol, "\\}(", eol, ")?$"), "", raw)
  tmp <- tempfile(fileext = ".json")
  write_results(entries, tmp)
  new <- readChar(tmp, file.info(tmp)$size, useBytes = TRUE)
  new <- gsub("\r\n", "\n", new, fixed = TRUE)
  new <- sub("^\\{\n", "", sub("\n\\}\n?$", "", new))
  new <- gsub("\n", eol, new, fixed = TRUE)
  tail_eol <- if (grepl(paste0("\\}", eol, "$"), raw)) eol else ""
  out <- paste0(body, ",", eol, new, eol, "}", tail_eol)
  chk <- jsonlite::fromJSON(out, simplifyVector = FALSE)
  if (!identical(names(chk), all_keys)) stop("w_splice_results: key order check failed", call. = FALSE)
  con <- file(path, open = "wb"); on.exit(close(con))
  writeBin(charToRaw(out), con)
  invisible(length(chk))
}

w_results <- function(out_dir = W_OUT, cache = W_CACHE, results_json = file.path(PAPER_F, "results.json")) {
  t0 <- Sys.time()
  R <- w_tables(cache)
  w_write_tables(R, out_dir)
  E <- w_entries(R)
  disp <- vapply(E, function(e) e$display, "")
  if (any(grepl("p.?value|significan|verdict|consistent with|^p ", disp, ignore.case = TRUE)))
    stop("w_results: a display carries a p-value or verdict wording", call. = FALSE)
  saveRDS(E, file.path(cache, "w_entries.rds"))
  n <- w_splice_results(E, results_json)
  flog(sprintf("results: %d F.w entries; results.json now %d keys; %.1f s", length(E), n,
               as.numeric(difftime(Sys.time(), t0, units = "secs"))), file = W_LOG)
  invisible(list(R = R, E = E))
}
