# Paper F Task 10: the primary Model L and Model T fits, the episode refit, the state-cluster bootstrap and the block
# bootstrap fallback, and run_primary() (contract papers/F/results_keys.md, sections 5-7 and the rules before them).
# Sourced after common_f.R, perinatal.R, power_f.R (boot_plan) and verdicts_f.R. models/common/R and Paper E's models/E/R
# are frozen and are called unchanged (fit_nb, nb_fitter_with, fit_time_chain, block_bootstrap_irr, term_row, lin_comb).
#
# P-values under any bootstrap step (Model L state-cluster bootstrap, Model T block bootstrap): two-sided Wald p from the
# bootstrap SE of the log-scale summary, z = beta / SD_boot(beta*), p = 2 * (1 - Phi(|z|)); CI = percentile; no bootstrap
# p, no 2 / B_ok floor (contract, controller ruling 2026-11-08). Paper E's block_bootstrap_irr returns the betas; the
# Wald p is computed here.

DROPPED_REASON <- "dropped: more than 20% of link-unit-months masked"
GATE_SUMMARY_F <- file.path(REPO_ROOT, "data", "derived", "hmis", "perinatal_gate_summary.csv")
POWER_CSV_REL <- "papers/F/output/power.csv"
CONTRACT_REL <- "papers/F/results_keys.md"
B_T <- 500L; B_T_REDUCED <- 200L        # Model T block bootstrap
B_L <- 200L; B_L_REDUCED <- 100L        # Model L state-cluster bootstrap
PRIMARY_SCRIPT_F <- "models/F/02_primary.R"

# Contrasts of Model L reported per fit: the three summaries and the six trimester strata. RR = exp(sign * sum(beta)).
# The stratum "tri1" is the first trimester (tmax_t1, spi3_dry_l6), "tri3" the third (tmax_t3, spi3_dry_l0).
L_CONTRASTS <- c(
  SUMMARIES[c("heat_t3", "heat_gest", "dry_gest")],
  list(heat_tri1 = list(terms = "tmax_t1", sign = 1), heat_tri2 = list(terms = "tmax_t2", sign = 1),
       heat_tri3 = list(terms = "tmax_t3", sign = 1),
       dry_tri1 = list(terms = "spi3_dry_l6", sign = -1), dry_tri2 = list(terms = "spi3_dry_l3", sign = -1),
       dry_tri3 = list(terms = "spi3_dry_l0", sign = -1)))
L_TERMS_ALL <- c(L_HEAT, L_DRY, L_LEADS)
T_TERM_NAMES <- c(en_gest = "en", ln_gest = "ln", en_ep1415 = "ep1415", en_ep1819 = "ep1819", en_other = "en_other",
                  en_roni_gest = "en")   # the roni sensitivity (Task 11) reports its RONI term as "en"
EP_EXPOSURE_F <- c("en_ep1415", "en_ep1819", "en_other", "ln_gest")

# ---- failures -----------------------------------------------------------------------------------------------------

# Genuine estimation failures (Paper E F56 scope: is_estimation_failure) plus the state-cluster bootstrap's own.
is_estimation_failure_f <- function(msg) {
  m <- first_line(if (inherits(msg, "condition")) conditionMessage(msg) else msg)
  is_estimation_failure(m) || grepl("^cluster bootstrap: (more than 10% of refits failed|term\\(s\\) not estimated)", m)
}

# ---- result rows --------------------------------------------------------------------------------------------------

.nz <- function(x) if (is.null(x) || !length(x)) NA_real_ else as.numeric(x)

# One row of a primary table. `c` and `lead` are contrast lists (est, se, rr, lo, hi, p) or NULL.
.mk_row <- function(outcome, model, term, c = NULL, lead = NULL, p_kind = NA_character_, step = NA_character_,
                    boot_B = NA_integer_, B_ok = NA_integer_, re_used = NA_character_, n = NA_integer_,
                    n_units = NA_integer_, pd_hess = NA, max_grad = NA_real_, status = "ok", error = NA_character_,
                    grad_par = NA_character_, newton_se = NA_real_) {
  data.table::data.table(outcome = outcome, model = model, term = term, rr = .nz(c$rr), lo = .nz(c$lo), hi = .nz(c$hi),
                         p = .nz(c$p), est = .nz(c$est), se = .nz(c$se), lead_rr = .nz(lead$rr),
                         lead_lo = .nz(lead$lo), lead_hi = .nz(lead$hi), lead_p = .nz(lead$p), p_kind = p_kind,
                         step = step, boot_B = as.integer(boot_B), B_ok = as.integer(B_ok), re_used = re_used,
                         n = as.integer(n), n_units = as.integer(n_units), pd_hess = pd_hess,
                         max_grad = as.numeric(max_grad), status = status, error = error,
                         lead_est = .nz(lead$est), lead_se = .nz(lead$se), grad_par = as.character(grad_par),
                         newton_se = as.numeric(newton_se))
}

# Rows cached before the lead log-scale columns and the convergence diagnostics existed: lead_est = log(lead_rr) and
# lead_se from the lead's Wald CI (every cached lead is a Wald contrast); the diagnostics were not stored (NA).
.upgrade_rows <- function(rows) {
  rows <- data.table::copy(data.table::as.data.table(rows))
  if (!"lead_est" %in% names(rows)) {
    rows[, lead_est := ifelse(is.na(lead_rr), NA_real_, log(lead_rr))]
    rows[, lead_se := ifelse(is.na(lead_rr), NA_real_, (log(lead_hi) - log(lead_lo)) / (2 * 1.959964))]
  }
  if (!"grad_par" %in% names(rows)) rows[, grad_par := NA_character_]
  if (!"newton_se" %in% names(rows)) rows[, newton_se := NA_real_]
  data.table::setcolorder(rows, names(.mk_row("x", "L", "x")))
  rows[]
}

.rows_na <- function(outcome, model, terms, status, error, step = NA_character_, boot_B = NA_integer_,
                     B_ok = NA_integer_) {
  data.table::rbindlist(lapply(terms, function(tm)
    .mk_row(outcome, model, tm, step = step, boot_B = boot_B, B_ok = B_ok, status = status, error = error)))
}

.fit_meta <- function(f, terms = c(L_TERMS_ALL, "en_gest", "ln_gest", EP_EXPOSURE_F)) {
  sdr <- f$model$sdr
  g <- sdr$gradient.fixed
  V <- sdr$cov.fixed
  grad_par <- NA_character_
  newton <- NA_real_
  if (!is.null(g) && length(g)) {
    grad_par <- names(sdr$par.fixed)[which.max(abs(g))]
    # Newton step on the exposure coefficients, in SE units: (cov.fixed %*% gradient)[k] / SE_k
    bn <- tryCatch(names(glmmTMB::fixef(f$model)$cond), error = function(e) NULL)
    idx <- which(names(sdr$par.fixed) == "beta")
    if (!is.null(V) && nrow(V) == length(g) && length(idx) == length(bn)) {
      step <- as.numeric(V %*% g)
      e <- idx[bn %in% terms]
      if (length(e)) newton <- max(abs(step[e]) / sqrt(diag(V)[e]))
    }
  }
  list(re_used = f$re_used, n = as.integer(f$n), n_units = nlevels(f$data$unit_id), pd_hess = isTRUE(sdr$pdHess),
       max_grad = if (is.null(g)) NA_real_ else max(abs(g)), grad_par = grad_par, newton_se = newton)
}

# Row and unit counts of a spec's complete rows (known even when a fit or its bootstrap fails).
.n_info <- function(spec, d) {
  cr <- complete_rows(data.table::as.data.table(d), unique(c(spec_vars(spec), "unit_id")))$data
  list(n = nrow(cr), n_units = length(unique(cr$unit_id)))
}

.need_terms <- function(est, terms) {
  if (anyNA(est[terms]))
    stop("term_row: term(s) not in model: ", paste(terms[is.na(est[terms])], collapse = ", "), call. = FALSE)
}

# Wald contrast exp(sign * sum(beta[terms])) from the coefficient vector and its covariance.
# `w` (named weights over `terms`, Task 11 lag-basis contrasts) replaces the unit weights: b = sign * sum(w * beta).
.wald_contrast <- function(est, V, terms, sign, w = NULL) {
  .need_terms(est, terms)
  lc <- if (is.null(w)) lin_comb(est, V, terms) else {
    w <- w[terms]
    s <- sum(w * est[terms])
    se <- sqrt(as.numeric(t(w) %*% V[terms, terms, drop = FALSE] %*% w))
    list(est = s, se = se, p = 2 * stats::pnorm(-abs(s / se)))
  }
  b <- sign * lc$est
  ci <- sort(exp(c(b - stats::qnorm(0.975) * lc$se, b + stats::qnorm(0.975) * lc$se)))
  list(est = b, se = lc$se, rr = exp(b), lo = ci[1], hi = ci[2], p = lc$p)
}

# Contrast under a bootstrap: the point estimate of the fit on the original rows, SE = SD over the successful resamples,
# two-sided Wald p from that SE (no floor), percentile 95% CI of exp(sign * sum(beta*)).
.boot_contrast <- function(est, betas, ok, terms, sign, w = NULL) {
  .need_terms(est, terms)
  if (is.null(w)) w <- stats::setNames(rep(1, length(terms)), terms)
  w <- w[terms]
  b <- sign * sum(w * est[terms])
  xb <- sign * as.vector(betas[ok, terms, drop = FALSE] %*% w)
  se <- stats::sd(xb)
  ci <- stats::quantile(xb, c(0.025, 0.975), names = FALSE)
  list(est = b, se = se, rr = exp(b), lo = exp(ci[1]), hi = exp(ci[2]), p = 2 * stats::pnorm(-abs(b / se)))
}

# Every coefficient a set of contrasts uses (terms and leads): the exposure terms whose Newton step is reported.
.contrast_terms <- function(contrasts) unique(unlist(lapply(contrasts, function(s) c(s$terms, s$lead))))

# Model L rows (one per L_CONTRASTS entry, with the matching lead for the three summaries) from a Wald fit.
rows_from_fit_l <- function(f, outcome, step = "state_ym", boot_B = NA_integer_, contrasts = L_CONTRASTS) {
  est <- glmmTMB::fixef(f$model)$cond
  V <- as.matrix(stats::vcov(f$model)$cond)
  m <- .fit_meta(f, .contrast_terms(contrasts))
  data.table::rbindlist(lapply(names(contrasts), function(k) {
    s <- contrasts[[k]]
    lead <- if (!is.null(s$lead)) .wald_contrast(est, V, s$lead, s$sign)
    .mk_row(outcome, "L", k, .wald_contrast(est, V, s$terms, s$sign, s$weights), lead, p_kind = "wald", step = step,
            boot_B = boot_B, re_used = m$re_used, n = m$n, n_units = m$n_units, pd_hess = m$pd_hess,
            max_grad = m$max_grad, grad_par = m$grad_par, newton_se = m$newton_se)
  }))
}

# Model L rows from a state-cluster bootstrap result (cluster_bootstrap_state()).
rows_from_bootstrap <- function(bb, outcome, contrasts = L_CONTRASTS) {
  data.table::rbindlist(lapply(names(contrasts), function(k) {
    s <- contrasts[[k]]
    lead <- if (!is.null(s$lead)) .boot_contrast(bb$est, bb$betas, bb$ok, s$lead, s$sign)
    .mk_row(outcome, "L", k, .boot_contrast(bb$est, bb$betas, bb$ok, s$terms, s$sign, s$weights), lead, p_kind = "bootstrap",
            step = "cluster_bootstrap", boot_B = bb$B, B_ok = bb$B_ok, re_used = bb$re_used, n = bb$n,
            n_units = bb$n_units, pd_hess = bb$pd_hess, max_grad = bb$max_grad, grad_par = bb$grad_par,
            newton_se = bb$newton_se)
  }))
}

# Model T rows for `terms` (glmmTMB names; renamed through T_TERM_NAMES); ln_gest is shown as exp(-beta) with the bounds
# swapped. From a Wald fit (E's term_row) or a block-bootstrap result.
.t_contrast <- function(term, est, se, lo, hi, p) {
  if (term == "ln_gest") list(est = -est, se = se, rr = exp(-est), lo = 1 / hi, hi = 1 / lo, p = p)
  else list(est = est, se = se, rr = exp(est), lo = lo, hi = hi, p = p)
}
rows_t_wald <- function(f, outcome, model, terms) {
  r <- term_row(f, terms)
  if (anyNA(r$est) || anyNA(r$se))
    stop("term_row: term(s) not in model: ", paste(terms[is.na(r$est) | is.na(r$se)], collapse = ", "), call. = FALSE)
  m <- .fit_meta(f, unique(c(terms, L_TERMS_ALL, "en_gest", "ln_gest", EP_EXPOSURE_F)))
  data.table::rbindlist(lapply(seq_along(terms), function(i) {
    .mk_row(outcome, model, unname(T_TERM_NAMES[terms[i]]),
            .t_contrast(terms[i], r$est[i], r$se[i], r$lo[i], r$hi[i], r$p[i]), p_kind = "wald", step = f$time_re,
            re_used = m$re_used, n = m$n, n_units = m$n_units, pd_hess = m$pd_hess, max_grad = m$max_grad,
            grad_par = m$grad_par, newton_se = m$newton_se)
  }))
}
rows_t_boot <- function(bb, outcome, model, terms, boot_B) {
  ok <- apply(is.finite(bb$betas), 1, all)
  data.table::rbindlist(lapply(terms, function(tm) {
    b <- bb$est[[tm]]
    x <- bb$betas[ok, tm]
    se <- stats::sd(x)
    ci <- stats::quantile(x, c(0.025, 0.975), names = FALSE)
    .mk_row(outcome, model, unname(T_TERM_NAMES[tm]),
            .t_contrast(tm, b, se, exp(ci[1]), exp(ci[2]), 2 * stats::pnorm(-abs(b / se))), p_kind = "bootstrap",
            step = "block_bootstrap", boot_B = boot_B, B_ok = bb$B_ok, re_used = bb$re_used, n = bb$n,
            n_units = bb$n_units, pd_hess = if (is.null(bb$pd_hess)) NA else bb$pd_hess,
            max_grad = if (is.null(bb$max_grad)) NA_real_ else bb$max_grad)
  }))
}

# ---- bootstrap sizes ----------------------------------------------------------------------------------------------

default_cores_f <- function() {
  e <- Sys.getenv("F_PRIMARY_CORES", unset = "")
  if (nzchar(e)) return(as.integer(e))
  max(1L, parallel::detectCores(logical = FALSE) - 1L)
}

timing_minutes <- function(name, path = file.path(F_OUT, "timing.csv")) {
  t <- data.table::fread(path)
  m <- t[t$fit == name, minutes][1]
  if (is.na(m)) stop("timing_minutes: no timing for ", name, " in ", path, call. = FALSE)
  m
}
# Model L: 200 refits unless projected over 12 h (then 100), from the primary Model L minutes (an upper bound: refits
# omit the state-month effect). Model T: 500 unless projected over 12 h (then 200), from the primary Model T minutes.
boot_B_l <- function(cores, minutes = timing_minutes("model_l_primary"))
  boot_plan(minutes, B_L, B_L_REDUCED, cores)
boot_B_t <- function(cores, minutes = timing_minutes("model_t_primary"))
  boot_plan(minutes, B_T, B_T_REDUCED, cores)

# ---- state-cluster bootstrap --------------------------------------------------------------------------------------

# One cluster resample: states drawn with replacement (as many draws as states), every row of a drawn state kept; unit_id,
# state_ym and state_unit relabelled "<label>_<k>", k = the draw index, so a state drawn twice has distinct units and
# distinct state-months. Seeded locally (the caller's RNG state is restored).
cluster_resample <- function(d, seed = NULL) {
  d <- data.table::as.data.table(d)
  states <- levels(droplevels(factor(d$state_unit)))
  idx <- split(seq_len(nrow(d)), factor(d$state_unit, levels = states))
  draws <- .with_seed(seed, sample.int(length(states), length(states), replace = TRUE))
  rows <- idx[draws]
  k <- rep(seq_along(draws), lengths(rows))
  out <- d[unlist(rows, use.names = FALSE)]
  relabel <- function(x) {
    lab <- paste0(as.character(x), "_", k)
    factor(lab, levels = unique(lab))
  }
  out[, `:=`(unit_id = relabel(unit_id), state_ym = relabel(state_ym), state_unit = relabel(state_unit))]
  for (nm in names(out)) if (is.factor(out[[nm]])) data.table::set(out, j = nm, value = droplevels(out[[nm]]))
  out[]
}

.fp_boot_one <- function(i, st) {
  di <- cluster_resample(st$d, seed = st$seed + i - 1L)
  r <- tryCatch({
    m <- .e_fit_fixed_re(st$spec, di, st$re, st$fitter)
    b <- glmmTMB::fixef(m)$cond[st$terms]
    if (anyNA(b)) stop("term(s) unidentified (NA): ", paste(st$terms[is.na(b)], collapse = ", "))
    unname(b)
  }, error = function(e) e)
  if (inherits(r, "error")) return(list(i = as.integer(i), beta = rep(NA_real_, length(st$terms)), error = conditionMessage(r)))
  list(i = as.integer(i), beta = r, error = NA_character_)
}
.fp_boot_task <- function(i) .fp_boot_one(i, get(".FP_BOOT_STATE", envir = globalenv()))

# PSOCK workers: Paper E's worker start-up (frozen .e_cluster) plus the Paper F functions; one OpenMP/TMB thread per fit.
.fp_cluster <- function(cores) {
  old_omp <- Sys.getenv("OMP_NUM_THREADS", unset = NA)
  Sys.setenv(OMP_NUM_THREADS = "1")
  on.exit(if (is.na(old_omp)) Sys.unsetenv("OMP_NUM_THREADS") else Sys.setenv(OMP_NUM_THREADS = old_omp))
  cl <- .e_cluster(as.integer(cores))
  parallel::clusterCall(cl, function(root) {
    for (f in c("common_f.R", "perinatal.R", "primary_f.R")) source(file.path(root, "F", "R", f), local = globalenv())
    options(glmmTMB.cores = 1L)
    invisible(TRUE)
  }, MODELS_ROOT)
  cl
}

# State-cluster bootstrap for Model L when the (1 | state_ym) effect does not converge. The model without it is fitted on
# the original rows (or `fit0`, an nbfit already fitted without it), which selects the unit random-effect structure; B
# resamples of states (resample i uses seed + i - 1) are refitted with that structure fixed (no per-resample fallback,
# Paper E F57). More than 10% failed refits stops with "cluster bootstrap: more than 10% of refits failed". Returns
# list(terms, est (the original fit's coefficients), B, B_ok, ok (per resample), betas (B x terms, NA for a failed
# refit), re_used, n, n_units, errors, error_counts, pd_hess, max_grad). `extra` adds fixed terms to the returned betas.
cluster_bootstrap_state <- function(spec, d, B, seed = SEED_F, cores = 1L, fit_fun = e_glmmTMB_fit,
                                    extra = character(), fit0 = NULL, progress = NULL, terms = NULL) {
  B <- as.integer(B); cores <- as.integer(cores); seed <- as.integer(seed)
  if (is.na(B) || B < 1L) stop("cluster_bootstrap_state: B must be a positive integer", call. = FALSE)
  vars <- unique(c(spec_vars(spec), "unit_id", "state_unit", "state_ym", "ym_f"))
  d0 <- droplevels(complete_rows(data.table::as.data.table(d), vars)$data[, vars, with = FALSE])
  fitter <- nb_fitter_with(character(), fit_fun)
  f0 <- if (is.null(fit0)) fit_nb(spec, d0, fitter = fitter) else fit0
  terms <- if (is.null(terms)) unique(c(L_TERMS_ALL, extra)) else unique(c(terms, extra))
  est <- glmmTMB::fixef(f0$model)$cond[terms]
  if (anyNA(est)) stop("cluster bootstrap: term(s) not estimated on the original rows: ",
                       paste(terms[is.na(est)], collapse = ", "), call. = FALSE)
  names(est) <- terms
  st <- list(spec = spec, d = d0, terms = terms, seed = seed, fitter = fitter, re = f0$re_used)
  cl <- NULL
  if (cores > 1L) {
    cl <- .fp_cluster(cores)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterCall(cl, function(s) { assign(".FP_BOOT_STATE", s, envir = globalenv()); NULL }, st)
  }
  chunk <- if (cores > 1L) 4L * cores else 5L
  res <- vector("list", B)
  for (s in seq(1L, B, by = chunk)) {
    idx <- s:min(B, s + chunk - 1L)
    res[idx] <- if (is.null(cl)) lapply(idx, .fp_boot_one, st = st) else parallel::clusterApplyLB(cl, idx, .fp_boot_task)
    if (is.function(progress)) progress(max(idx), B)
  }
  betas <- do.call(rbind, lapply(res, `[[`, "beta"))
  colnames(betas) <- terms
  errs <- vapply(res, `[[`, "", "error")
  ok <- is.na(errs) & apply(is.finite(betas), 1, all)
  emsg <- ifelse(is.na(errs), "non-finite coefficient", trimws(sub("[\r\n].*$", "", errs)))[!ok]
  error_counts <- if (any(!ok)) sort(table(emsg), decreasing = TRUE) else integer()
  error_counts <- stats::setNames(as.integer(error_counts), names(error_counts))
  if (B - sum(ok) > 0.1 * B)
    stop(errorCondition(sprintf("cluster bootstrap: more than 10%% of refits failed (most common error, %d of %d refits: %s)",
                                error_counts[[1]], B, names(error_counts)[1]),
                        class = "f_boot_too_many_failed", B_ok = as.integer(sum(ok)), B = B, error_counts = error_counts))
  m <- .fit_meta(f0, terms)
  list(terms = terms, est = est, B = B, B_ok = as.integer(sum(ok)), ok = ok, betas = betas, re_used = f0$re_used,
       n = m$n, n_units = m$n_units, errors = unique(errs[!is.na(errs)]), error_counts = error_counts,
       pd_hess = m$pd_hess, max_grad = m$max_grad, grad_par = m$grad_par, newton_se = m$newton_se)
}

# ---- Model L ------------------------------------------------------------------------------------------------------

# Model L for one outcome on its analysis rows `d` (outcome_rows()): l_spec through fit_nb with the (1 | state_ym) random
# effect; if no unit structure converges with it, the model without it, refitted inside the state-cluster bootstrap on
# the structure the original rows select (B from boot_plan(): 200, or 100 when projected over 12 h). Returns list(fit
# (the nbfit; for the bootstrap step the fit without state_ym), state_ym (TRUE if the random effect was used), rows,
# boot_B (NA without a bootstrap), B_ok, n, n_units, re_used, pd_hess, max_grad).
fit_model_l <- function(d, outcome, spec = l_spec(outcome), fit_fun = e_glmmTMB_fit, B = NULL, cores = 1L,
                        seed = SEED_F, boot_fun = cluster_bootstrap_state, progress = NULL, contrasts = L_CONTRASTS) {
  f <- tryCatch(fit_nb(spec, d, fitter = nb_fitter_with(L_RE, fit_fun)), error = function(e) e)
  if (inherits(f, "error")) {
    if (!startsWith(conditionMessage(f), "fit_nb: no structure converged")) stop(f)
    f0 <- fit_nb(spec, d, fitter = nb_fitter_with(character(), fit_fun))
    if (is.null(B)) B <- boot_B_l(cores)
    bb <- tryCatch(boot_fun(spec, d, B = B, seed = seed, cores = cores, fit_fun = fit_fun, fit0 = f0, progress = progress),
                   error = function(e) if (is_estimation_failure_f(e)) e else stop(e))
    if (inherits(bb, "error")) {          # keep the known structure, B, B_ok and n (the estimates are not estimable)
      m0 <- .fit_meta(f0, .contrast_terms(contrasts))
      rows <- .rows_na(outcome, "L", names(contrasts), "error", first_line(conditionMessage(bb)),
                       step = "cluster_bootstrap", boot_B = B, B_ok = if (is.null(bb$B_ok)) NA_integer_ else bb$B_ok)
      rows[, `:=`(n = m0$n, n_units = m0$n_units, re_used = m0$re_used)]
      return(list(fit = f0, state_ym = FALSE, rows = rows, boot_B = as.integer(B), B_ok = rows$B_ok[1], n = m0$n,
                  n_units = m0$n_units, re_used = m0$re_used, pd_hess = m0$pd_hess, max_grad = m0$max_grad,
                  error_counts = integer()))
    }
    return(list(fit = f0, state_ym = FALSE, rows = rows_from_bootstrap(bb, outcome, contrasts), boot_B = as.integer(B),
                B_ok = bb$B_ok, n = bb$n, n_units = bb$n_units, re_used = bb$re_used, pd_hess = bb$pd_hess,
                max_grad = bb$max_grad, error_counts = bb$error_counts))
  }
  m <- .fit_meta(f, .contrast_terms(contrasts))
  list(fit = f, state_ym = TRUE, rows = rows_from_fit_l(f, outcome, contrasts = contrasts), boot_B = NA_integer_, B_ok = NA_integer_,
       n = m$n, n_units = m$n_units, re_used = m$re_used, pd_hess = m$pd_hess, max_grad = m$max_grad,
       error_counts = integer())
}

# ---- Model T ------------------------------------------------------------------------------------------------------

# One Model T fit of `terms`: fit_time_chain over `chain`; if the chain is empty or exhausted (the error names
# block_bootstrap as the next step), block_boot over months. A genuine estimation failure gives kind "error" (first line);
# any other error is re-raised.
.t_part <- function(spec, d, terms, chain, fit_fun, boot_fun, B, block, seed, cores, progress) {
  booted <- FALSE
  tryCatch({
    if (length(chain)) {
      f <- tryCatch(fit_time_chain(spec, d, chain = chain, fit_fun = fit_fun), error = function(e) e)
      if (!inherits(f, "error")) return(list(kind = "wald", fit = f, step = f$time_re))
      if (!grepl("next step: block_bootstrap", conditionMessage(f), fixed = TRUE)) stop(f)
    }
    booted <- TRUE
    bb <- boot_fun(spec, d, terms, B = B, block = block, seed = seed, cores = cores, fit_fun = fit_fun,
                   progress = progress)
    list(kind = "boot", bb = bb, step = "block_bootstrap")
  }, error = function(e) {
    if (!is_estimation_failure_f(e)) stop(e)
    ni <- tryCatch(.n_info(spec, d), error = function(e2) list(n = NA_integer_, n_units = NA_integer_))
    list(kind = "error", error = first_line(conditionMessage(e)), B_ok = if (is.null(e$B_ok)) NA_integer_ else e$B_ok,
         step = if (booted) "block_bootstrap" else NA_character_, n = ni$n, n_units = ni$n_units)
  })
}

.t_rows_err <- function(part, outcome, model, terms, B) {
  r <- .rows_na(outcome, model, unname(T_TERM_NAMES[terms]), "error", part$error, step = part$step,
                boot_B = if (identical(part$step, "block_bootstrap")) B else NA_integer_, B_ok = part$B_ok)
  if (!is.null(part$n)) r[, `:=`(n = as.integer(part$n), n_units = as.integer(part$n_units))]
  r
}
# A term-extraction failure (a term not in the model: F56 estimation failure) makes the part not estimable.
.t_rows <- function(part, outcome, model, terms, B) {
  if (identical(part$kind, "error")) return(.t_rows_err(part, outcome, model, terms, B))
  tryCatch(
    if (part$kind == "wald") rows_t_wald(part$fit, outcome, model, terms) else rows_t_boot(part$bb, outcome, model, terms, B),
    error = function(e) {
      if (!is_estimation_failure_f(e)) stop(e)
      ni <- if (part$kind == "wald") list(n = part$fit$n, n_units = nlevels(part$fit$data$unit_id)) else
        list(n = part$bb$n, n_units = part$bb$n_units)
      .t_rows_err(list(error = first_line(conditionMessage(e)), step = part$step, B_ok = NA_integer_, n = ni$n,
                       n_units = ni$n_units), outcome, model, terms, B)
    })
}

# Model T for one outcome on its analysis rows `d`: the primary fit (en_gest, ln_gest) through the time chain, and the
# episode refit (en_ep1415, en_ep1819, en_other, ln_gest) on the same step (the chain from the primary step on; straight
# to the block bootstrap if the primary used it). Model T's bootstrap: B = 500, or 200 when projected over 12 h
# (boot_plan). Returns list(rows (model T and T_ep), time_re, ep_time_re, boot_B (NA without a bootstrap), B_ok, n,
# n_units, re_used, pd_hess, max_grad, error, ep_error).
fit_model_t <- function(d, outcome, chain = c("ar1", "iid"), fit_fun = e_glmmTMB_fit, boot_fun = block_bootstrap_irr,
                        B = NULL, cores = 1L, seed = SEED_F, block = 12L, progress = NULL) {
  terms <- c("en_gest", "ln_gest")
  if (is.null(B)) B <- boot_B_t(cores)
  p1 <- .t_part(t_spec_f(outcome), d, terms, chain, fit_fun, boot_fun, B, block, seed, cores, progress)
  used_boot <- identical(p1$kind, "boot") || identical(p1$step, "block_bootstrap")
  rows1 <- .t_rows(p1, outcome, "T", terms, B)
  ep_terms <- EP_EXPOSURE_F
  if (identical(p1$kind, "error")) {
    p2 <- list(kind = "error", error = paste("primary Model T not estimable:", p1$error), B_ok = NA_integer_,
               step = NA_character_)
  } else {
    ep_chain <- if (identical(p1$kind, "boot")) character() else chain[match(p1$step, chain):length(chain)]
    p2 <- .t_part(t_spec_f(outcome, exposure = ep_terms), d, ep_terms, ep_chain, fit_fun, boot_fun, B, block, seed,
                  cores, progress)
  }
  rows2 <- .t_rows(p2, outcome, "T_ep", ep_terms, B)
  r1 <- rows1[1]
  list(rows = rbind(rows1, rows2), time_re = p1$step,
       ep_time_re = p2$step, boot_B = if (used_boot) as.integer(B) else NA_integer_,
       B_ok = if (identical(p1$kind, "boot")) p1$bb$B_ok else if (used_boot) p1$B_ok else NA_integer_, n = r1$n, n_units = r1$n_units, re_used = r1$re_used,
       pd_hess = r1$pd_hess, max_grad = r1$max_grad, error = r1$error,
       ep_error = if (identical(p2$kind, "error")) p2$error else NA_character_)
}

# ---- the six tests, Holm family and verdicts from a primary table ---------------------------------------------------

# The six tests (TESTS) with their estimate, p, matching lead (Model L) or episode RRs (Model T) from `tab`, the Holm
# adjusted p and the verdict. A row that is not estimable has NA estimate and p, so p_holm NA and "not consistent with".
build_tests <- function(tab) {
  tab <- data.table::as.data.table(tab)
  pick <- function(o, m, tm) {
    r <- tab[outcome == o & model == m & term == tm]
    if (nrow(r) != 1L) stop(sprintf("build_tests: %d rows for %s %s %s", nrow(r), o, m, tm), call. = FALSE)
    r
  }
  est_ok <- function(r) identical(r$status, "ok") && !is.na(r$rr)
  rows <- data.table::rbindlist(lapply(seq_len(nrow(TESTS)), function(i) {
    tr <- TESTS[i]
    r <- pick(tr$outcome, tr$model, if (tr$model == "L") tr$summary else "en")
    ok <- est_ok(r)
    ep <- if (tr$model == "T") list(a = pick(tr$outcome, "T_ep", "ep1415"), b = pick(tr$outcome, "T_ep", "ep1819"))
    data.table::data.table(
      test_id = tr$test_id, hypothesis = toupper(substr(tr$test_id, 1, 3)), outcome = tr$outcome, model = tr$model,
      summary = tr$summary, direction = "gt", rr = if (ok) r$rr else NA_real_, lo = if (ok) r$lo else NA_real_,
      hi = if (ok) r$hi else NA_real_, p = if (ok) r$p else NA_real_, est = if (ok) log(r$rr) else NA_real_,
      lead_rr = if (ok && tr$model == "L") r$lead_rr else NA_real_,
      lead_lo = if (ok && tr$model == "L") r$lead_lo else NA_real_,
      lead_hi = if (ok && tr$model == "L") r$lead_hi else NA_real_,
      ep1415 = if (!is.null(ep) && est_ok(ep$a)) ep$a$rr else NA_real_,
      ep1819 = if (!is.null(ep) && est_ok(ep$b)) ep$b$rr else NA_real_,
      p_kind = r$p_kind, B_ok = r$B_ok, error = if (ok) NA_character_ else r$error)
  }))
  rows <- holm_family_f(rows)
  rows[, verdict := verdict_test(rows)]
  rows[]
}

# ---- dropped outcomes ---------------------------------------------------------------------------------------------

dropped_outcomes_f <- function(path = GATE_SUMMARY_F) {
  g <- data.table::fread(path, colClasses = list(character = "dropped"))
  if (!all(OUTS %in% g[scope == "primary"]$variable))
    stop("dropped_outcomes_f: ", path, " lacks an outcome", call. = FALSE)
  g[scope == "primary" & variable %in% OUTS & tolower(dropped) == "true"]$variable
}

# Rows of an outcome dropped by the Task 4 masking rule: not estimable in every key.
dropped_rows <- function(outcome) {
  rbind(.rows_na(outcome, "L", names(L_CONTRASTS), "dropped", DROPPED_REASON),
        .rows_na(outcome, "T", unname(T_TERM_NAMES[c("en_gest", "ln_gest")]), "dropped", DROPPED_REASON),
        .rows_na(outcome, "T_ep", unname(T_TERM_NAMES[EP_EXPOSURE_F]), "dropped", DROPPED_REASON))
}

# ---- run_primary ---------------------------------------------------------------------------------------------------

.git_default <- function(args) suppressWarnings(system2("git", c("-C", shQuote(REPO_ROOT), args), stdout = TRUE, stderr = TRUE))

# Spec 5.6 order: the contract and the power output (power.csv; the R6 stop plan is a committed result) must be committed
# and unmodified before any primary fit.
assert_power_committed <- function(git_fun = .git_default, files = c(CONTRACT_REL, POWER_CSV_REL)) {
  for (f in files) {
    ls <- git_fun(c("ls-files", "--error-unmatch", f))
    if (!length(ls) || !is.null(attr(ls, "status")) || length(git_fun(c("status", "--porcelain", "--", f))))
      stop("run_primary: ", f, " must be committed and unmodified before the primary fits (spec 5.6 order)", call. = FALSE)
  }
  invisible(TRUE)
}

.cache_get <- function(path, resume) if (resume && file.exists(path)) readRDS(path) else NULL

# All primary fits. Each fit (Model L and Model T, per outcome) is cached in `cache` as a light record (rows and
# metadata; no model object) as soon as it is done, so an interrupted run loses at most one fit. Returns list(entries,
# table, tests, overall, settings).
run_primary <- function(cores = default_cores_f(), git_fun = .git_default, cache = F_CACHE, resume = TRUE,
                        out_csv = file.path(F_OUT, "primary_estimates.csv"),
                        verdicts_csv = file.path(F_OUT, "verdicts.csv"), log_file = "02_primary.log") {
  assert_power_committed(git_fun)
  lg <- function(...) flog(..., file = log_file)
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(out_csv), recursive = TRUE, showWarnings = FALSE)
  dropped <- dropped_outcomes_f()
  settings <- list(cores = cores, seed = SEED_F, B_l_plan = boot_B_l(cores), B_t_plan = boot_B_t(cores))
  lg("primary: cores ", cores, "; planned B: Model L ", settings$B_l_plan, ", Model T ", settings$B_t_plan,
     "; dropped outcomes: ", if (length(dropped)) paste(dropped, collapse = ", ") else "none")
  d_all <- read_perinatal_model("primary")
  tabs <- list()
  runtime <- c()
  prog <- function(label) {
    last <- 0L
    function(k, n) {
      if (k %/% 10L > last %/% 10L || k == n) { lg(label, ": bootstrap ", k, " of ", n, " refits"); last <<- k }
      invisible(NULL)
    }
  }
  for (o in OUTS) {
    if (o %in% dropped) { tabs[[o]] <- dropped_rows(o); next }
    d <- outcome_rows(d_all, o)
    lg(o, ": ", nrow(d), " analysis rows")
    fl <- file.path(cache, sprintf("l_%s.rds", o))
    rl <- .cache_get(fl, resume)
    if (is.null(rl)) {
      t0 <- proc.time()[["elapsed"]]
      lg(o, ": Model L start")
      rl <- catch_failure_f(fit_model_l(d, o, cores = cores, progress = prog(paste(o, "Model L"))),
                            function(e) list(rows = .rows_na(o, "L", names(L_CONTRASTS), "error", first_line(conditionMessage(e)))))
      rl$fit <- NULL
      rl$minutes <- (proc.time()[["elapsed"]] - t0) / 60
      saveRDS(rl, fl)
      lg(o, ": Model L done in ", sprintf("%.1f", rl$minutes), " min; state_ym ", rl$state_ym, ", re ", rl$re_used)
    } else lg(o, ": Model L from cache")
    ft <- file.path(cache, sprintf("t_%s.rds", o))
    rt <- .cache_get(ft, resume)
    if (is.null(rt)) {
      t0 <- proc.time()[["elapsed"]]
      lg(o, ": Model T start")
      rt <- fit_model_t(d, o, cores = cores, progress = prog(paste(o, "Model T")))
      rt$minutes <- (proc.time()[["elapsed"]] - t0) / 60
      saveRDS(rt, ft)
      lg(o, ": Model T done in ", sprintf("%.1f", rt$minutes), " min; time_re ", rt$time_re, ", episode ", rt$ep_time_re)
    } else lg(o, ": Model T from cache")
    runtime[[paste0(o, "_L")]] <- rl$minutes
    runtime[[paste0(o, "_T")]] <- rt$minutes
    tabs[[o]] <- .upgrade_rows(rbind(rl$rows, rt$rows, fill = TRUE))
  }
  tab <- data.table::rbindlist(tabs, fill = TRUE)
  tests <- build_tests(tab)
  v <- stats::setNames(tests$verdict, tests$test_id)
  overall <- list(h10 = overall_verdict_f(v, "H10"), h11 = overall_verdict_f(v, "H11"))
  data.table::fwrite(tab, out_csv)
  ver <- data.table::copy(tests)
  ver[, `:=`(est = NULL, direction = NULL)]
  ver[, verdict_text := NA_character_]
  ov <- data.table::rbindlist(lapply(c("h10", "h11"), function(h)
    data.table::data.table(test_id = h, hypothesis = toupper(h), verdict = overall[[h]]$verdict,
                           verdict_text = overall[[h]]$text)), fill = TRUE)
  data.table::fwrite(rbind(ver, ov, fill = TRUE), verdicts_csv)
  settings$runtime_min <- runtime
  saveRDS(list(table = tab, tests = tests, overall = overall, settings = settings), file.path(cache, "primary.rds"))
  lg("primary: wrote ", out_csv, " and ", verdicts_csv)
  list(entries = primary_entries(tab, tests, overall), table = tab, tests = tests, overall = overall,
       settings = settings)
}

# Evaluate expr; an estimation failure is passed to on_failure(condition), any other error is re-raised (F56).
catch_failure_f <- function(expr, on_failure) tryCatch(expr, error = function(e) if (is_estimation_failure_f(e)) on_failure(e) else stop(e))

# ---- contract keys (sections 5 to 7) ------------------------------------------------------------------------------

TIME_RE_DISPLAY_F <- c(ar1 = "AR(1) year-month random effect", iid = "independent year-month random effect")
.s6 <- function(x) if (is.null(x) || is.na(x)) "NA" else format(signif(x, 6), scientific = FALSE, trim = TRUE)

# The 72 keys of contract sections 5 (Model L), 6 (Model T) and 7 (verdicts) from the primary table, the six tests and the
# overall verdicts.
primary_entries <- function(tab, tests, overall, script = PRIMARY_SCRIPT_F) {
  tab <- data.table::as.data.table(tab)
  E <- list()
  put <- function(k, value, display, description) E[[k]] <<- res_entry(value, display, script, description)
  row <- function(o, m, tm) {
    r <- tab[outcome == o & model == m & term == tm]
    if (nrow(r) != 1L) stop(sprintf("primary_entries: %d rows for %s %s %s", nrow(r), o, m, tm), call. = FALSE)
    r
  }
  ok <- function(r) identical(r$status, "ok") && !is.na(r$rr)
  reason <- function(r) if (!is.na(r$error)) r$error else "estimate missing"
  ne <- function(k, r, what) put(k, NA, not_estimable(reason(r)), sprintf("%s: %s", what, not_estimable(reason(r))))
  step_text <- function(r) {
    if (r$model == "L") {
      if (identical(r$step, "state_ym")) "state error: (1 | state_ym) random effect"
      else sprintf("state error: state-cluster bootstrap (B = %s, B_ok = %s)", r$boot_B, r$B_ok)
    } else if (identical(r$step, "block_bootstrap")) {
      sprintf("time effect: moving-block bootstrap over months (block 12, B = %s, B_ok = %s)", r$boot_B, r$B_ok)
    } else sprintf("time effect: %s", c(ar1 = "ar1(ym_f + 0 | national)", iid = "(1 | ym_f)")[[r$step]])
  }
  # which = "lead": the negative-control lead's own log-scale estimate, SE, RR, CI and p
  est_text <- function(r, which = c("main", "lead")) {
    which <- match.arg(which)
    f <- function(x) r[[if (which == "main") x else paste0("lead_", x)]]
    boot <- identical(r$p_kind, "bootstrap")
    sprintf("%s; %s; %s unit-months, %s link units; unit random effect %s; log-scale coefficient %s, SE %s%s; RR %s (%s %s to %s); p %s (%s); seed SEED_F = %d",
            if (r$model == "L") "Model L (l_spec: heat and SPI strata, leads, ym_f, offset, (1 + t_c | unit_id); NB2 glmmTMB)" else
              "Model T (t_spec_f: en_gest, ln_gest, moy, t_c, programme indicators, offset, (1 + t_c | unit_id) + time random effect; NB2 glmmTMB)",
            step_text(r), fmt_int(r$n), r$n_units, r$re_used, .s6(f("est")), .s6(f("se")), if (boot) " (bootstrap SD)" else "",
            .s6(f("rr")), if (boot) sprintf("percentile 95%% CI over %d successful resamples", r$B_ok) else "Wald 95% CI",
            .s6(f("lo")), .s6(f("hi")), .s6(f("p")),
            if (boot) "two-sided Wald p from the bootstrap SE, no floor" else "two-sided Wald", SEED_F)
  }
  rr_key <- function(k, r, what, which = c("main", "lead")) {
    which <- match.arg(which)
    rr <- if (which == "main") r$rr else r$lead_rr
    lo <- if (which == "main") r$lo else r$lead_lo
    hi <- if (which == "main") r$hi else r$lead_hi
    if (!ok(r) || is.na(rr)) return(ne(k, r, what))
    put(k, rr, fmt_rr_ci(rr, lo, hi), sprintf("%s. %s", what, est_text(r, which)))
  }
  p_key <- function(k, r, what) {
    if (!ok(r)) return(ne(k, r, what))
    put(k, r$p, fmt_p(r$p), sprintf("%s. %s", what, est_text(r)))
  }
  for (o in OUTS) {
    ## section 5: Model L
    for (s in c("heat_t3", "heat_gest", "dry_gest")) {
      r <- row(o, "L", s)
      what <- sprintf("Model L RR of %s (%s), %s", s, c(heat_t3 = "per +1 deg C sustained over the third trimester",
                      heat_gest = "per +1 deg C sustained over gestation", dry_gest = "per SPI -1 sustained over gestation")[[s]], o)
      rr_key(sprintf("F.l.%s.%s.rr", o, s), r, what)
      p_key(sprintf("F.l.%s.%s.p", o, s), r, sprintf("Two-sided p of %s, Model L, %s (unadjusted)", s, o))
      rr_key(sprintf("F.l.%s.%s.lead_rr", o, s), r, sprintf("Negative-control lead of %s (%s), Model L, %s", s,
             if (s == "dry_gest") "spi3_dry_lead3 per SPI -1" else "tmax_lead12 per +1 deg C", o), "lead")
    }
    for (g in c("heat", "dry")) for (k in 1:3)
      rr_key(sprintf("F.l.%s.%s.tri%d", o, g, k), row(o, "L", sprintf("%s_tri%d", g, k)),
             sprintf("Model L RR of the trimester %d stratum, %s, %s", k, g, o))
    r <- row(o, "L", "heat_t3")
    if (!is.na(r$step) && !is.na(r$n)) {
      put(sprintf("F.l.%s.state_ym", o), r$step,
          if (identical(r$step, "state_ym")) "state-month random effect" else
            sprintf("state-cluster bootstrap (B = %s)", fmt_int(r$boot_B)),
          sprintf("Structure used for the state error in Model L, %s: %s", o, r$step))
      if (identical(r$step, "state_ym"))
        put(sprintf("F.l.%s.boot_B", o), NA, "not applicable (state-month random effect converged)",
            sprintf("No state-cluster bootstrap was needed for Model L, %s", o))
      else put(sprintf("F.l.%s.boot_B", o), r$boot_B, fmt_int(r$boot_B),
               sprintf("State-cluster bootstrap resamples requested for Model L, %s; %s successful (B_ok)", o, r$B_ok))
      put(sprintf("F.l.%s.n", o), r$n, fmt_int(r$n), sprintf("Unit-months in the primary Model L fit, %s", o))
      put(sprintf("F.l.%s.n_units", o), r$n_units, fmt_int(r$n_units), sprintf("Link units in the primary Model L fit, %s", o))
    } else for (k in c("state_ym", "boot_B", "n", "n_units")) ne(sprintf("F.l.%s.%s", o, k), r, sprintf("Model L %s, %s", k, o))
    ## section 6: Model T
    en <- row(o, "T", "en"); ln <- row(o, "T", "ln")
    e1 <- row(o, "T_ep", "ep1415"); e2 <- row(o, "T_ep", "ep1819")
    rr_key(sprintf("F.t.%s.en.rr", o), en, sprintf("Model T RR per +1 deg C of the gestation-mean El Nino term en_gest, %s", o))
    p_key(sprintf("F.t.%s.en.p", o), en, sprintf("Two-sided p of en_gest, Model T, %s (unadjusted)", o))
    rr_key(sprintf("F.t.%s.en.ep1415", o), e1,
           sprintf("Episode model RR per +1 deg C, en_ep1415 (birth months October 2014 to February 2017), %s; time random effect step %s", o, e1$step))
    rr_key(sprintf("F.t.%s.en.ep1819", o), e2,
           sprintf("Episode model RR per +1 deg C, en_ep1819 (birth months September 2018 to February 2020), %s; time random effect step %s", o, e2$step))
    rr_key(sprintf("F.t.%s.ln.rr", o), ln,
           sprintf("Model T RR per 1 deg C cooler La Nina term, exp(-beta_ln) with the bounds swapped, %s; the term is weakly identified", o))
    if (!is.na(en$step) && !is.na(en$n)) {
      put(sprintf("F.t.%s.time_re", o), en$step,
          if (identical(en$step, "block_bootstrap")) sprintf("moving-block bootstrap over months (block 12, B = %s)", fmt_int(en$boot_B))
          else TIME_RE_DISPLAY_F[[en$step]],
          sprintf("Time random-effect step used by Model T, %s; episode step %s", o, e1$step))
      if (identical(en$step, "block_bootstrap"))
        put(sprintf("F.t.%s.boot_B", o), en$boot_B, fmt_int(en$boot_B),
            sprintf("Block-bootstrap resamples requested for Model T, %s; %s successful (B_ok)", o, en$B_ok))
      else put(sprintf("F.t.%s.boot_B", o), NA, "not applicable (no bootstrap step)", sprintf("No block bootstrap for Model T, %s", o))
      put(sprintf("F.t.%s.n", o), en$n, fmt_int(en$n), sprintf("Unit-months in the primary Model T fit, %s", o))
      put(sprintf("F.t.%s.n_units", o), en$n_units, fmt_int(en$n_units), sprintf("Link units in the primary Model T fit, %s", o))
    } else for (k in c("time_re", "boot_B", "n", "n_units")) ne(sprintf("F.t.%s.%s", o, k), en, sprintf("Model T %s, %s", k, o))
  }
  ## section 7: verdicts
  for (i in seq_len(nrow(tests))) {
    t <- tests[i]
    put(sprintf("F.%s.verdict", t$test_id), t$verdict, t$verdict,
        sprintf("%s verdict: RR %s, Holm p %s, lead CI %s to %s, episode RRs %s and %s", toupper(t$test_id), .s6(t$rr), .s6(t$p_holm),
                .s6(t$lead_lo), .s6(t$lead_hi), .s6(t$ep1415), .s6(t$ep1819)))
    if (is.na(t$p_holm)) put(sprintf("F.%s.p_holm", t$test_id), NA, not_estimable(if (is.na(t$error)) "left the Holm family" else t$error),
                             sprintf("%s left the Holm family (not estimable)", toupper(t$test_id)))
    else put(sprintf("F.%s.p_holm", t$test_id), t$p_holm, fmt_p(t$p_holm),
             sprintf("Holm-adjusted p of %s over the %d performed tests; p entered %s", toupper(t$test_id), sum(!is.na(tests$p)), .s6(t$p)))
  }
  for (h in c("h10", "h11")) {
    put(sprintf("F.%s.verdict", h), overall[[h]]$verdict, overall[[h]]$verdict,
        sprintf("Overall %s verdict: consistent with if at least one of its tests is", toupper(h)))
    put(sprintf("F.%s.verdict_text", h), overall[[h]]$text, overall[[h]]$text,
        sprintf("Overall %s verdict naming the consistent tests", toupper(h)))
  }
  E
}
