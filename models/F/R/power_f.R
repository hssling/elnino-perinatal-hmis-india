# Paper F Task 9: power simulation on the simplified model (R6; contract "Power design (R6)" and section 9). Sourced
# after common_f.R and perinatal.R. models/common/R and Paper E's models/E/R are frozen and called unchanged.
#
# Design: per test, fit the simplified model (sim_spec_l / sim_spec_t: link-unit intercepts only, no (1 | state_ym))
# WITHOUT the tested exposure terms, once, on the data given. Per simulation: redraw the year-month effects (Model T),
# set mu = exp(eta + b) * rr^x, draw y ~ NB2(mu, theta), refit the simplified model WITH the tested terms and count a
# rejection at two-sided p < 0.05 with RR > 1. A model containing a tested exposure is never fitted to the real
# outcome: the refits see simulated counts only (the null fit omits the tested terms).
# Seeds: simulation i (any rr) draws with set.seed(seed + i - 1), so the grid points share their random numbers.

GRID <- list(L = c(1.01, 1.02, 1.03, 1.05), T = c(1.02, 1.05, 1.10, 1.20))
GRID_REDUCED <- c(1.03, 1.05, 1.10)
MDE_LABEL <- "(optimistic: simulated on a simplified model)"
STOP_TEXT <- "not estimated (power simulation stopped: projected run over 24 hours after both R6 reductions)"

# The summaries tested by the simulation: the Model L summaries of perinatal.R and the El Nino coefficient of Model T.
SIM_SUMMARY <- c(SUMMARIES, list(en = list(terms = "en_gest", sign = 1)))

# Plan (R6 order): 200 simulations on the full grid; if projected over `budget_h`, 100 simulations; if still over, the
# grid GRID_REDUCED for every test; if still over, step "stop" (the script runs nothing; n_sim, grid and projected_h
# are then those of the fully reduced plan). Hours = sum over the six tests of n_sim * grid points * minutes of one
# simulation fit of the test's model (timing$fit "sim_l" or "sim_t") / 60 / cores. The six tests are never reduced.
power_plan <- function(timing, n_tests = 6L, cores, budget_h = 24) {
  if (!identical(as.integer(n_tests), nrow(TESTS)))
    stop("power_plan: the plan always covers the six tests (n_tests = ", nrow(TESTS), "), not ", n_tests, call. = FALSE)
  timing <- data.table::as.data.table(timing)
  mins <- c(L = timing[fit == "sim_l", minutes][1], T = timing[fit == "sim_t", minutes][1])
  if (anyNA(mins)) stop("power_plan: timing needs the fits sim_l and sim_t (minutes)", call. = FALSE)
  nL <- sum(TESTS$model == "L")
  nT <- sum(TESTS$model == "T")
  hours <- function(n_sim, grid)
    n_sim * (nL * length(grid$L) * mins[["L"]] + nT * length(grid$T) * mins[["T"]]) / 60 / cores
  red <- list(L = GRID_REDUCED, T = GRID_REDUCED)
  steps <- list(list("200", 200L, GRID), list("100", 100L, GRID), list("100_reduced_grid", 100L, red))
  for (s in steps) {
    h <- hours(s[[2]], s[[3]])
    if (h <= budget_h)
      return(list(n_sim = s[[2]], grid = s[[3]], projected_h = unname(h), step = s[[1]], n_tests = nrow(TESTS),
                  cores = as.integer(cores)))
  }
  list(n_sim = 100L, grid = red, projected_h = unname(hours(100L, red)), step = "stop", n_tests = nrow(TESTS),
       cores = as.integer(cores))
}

# Bootstrap size (Task 10): B unless the projection B * minutes_per_refit / 60 / cores exceeds budget_h, then B_reduced.
boot_plan <- function(minutes_per_refit, B, B_reduced, cores, budget_h = 12) {
  if (B * minutes_per_refit / 60 / cores > budget_h) as.integer(B_reduced) else as.integer(B)
}

# The covariate x of a test summary such that the injected RR is rr per unit of x.
sim_exposure <- function(d, summary) {
  switch(summary,
    heat_t3 = d$tmax_t3,
    heat_gest = rowMeans(as.matrix(d[, L_HEAT, with = FALSE])),
    dry_gest = -rowMeans(as.matrix(d[, L_DRY, with = FALSE])),
    en = d$en_gest,
    stop("sim_exposure: unknown summary ", summary, call. = FALSE))
}

# The terms the null fit leaves out: the three strata of the tested exposure (Model L; the heat tests drop the heat
# strata, the deficit test the SPI terms) or en_gest (Model T).
sim_drop_terms <- function(model, summary) {
  if (model == "T") return("en_gest")
  if (summary == "dry_gest") L_DRY else L_HEAT
}

.test_row <- function(test) {
  if (is.character(test)) {
    r <- TESTS[test_id == test]
    if (nrow(r) != 1L) stop("unknown test_id: ", test, call. = FALSE)
    return(as.list(r))
  }
  as.list(test)
}

# Null state of a test: the simplified model without the tested terms, fitted once. Rows are those complete for the
# model WITH the tested terms, so the null fit and the refits use the same rows. eta = linear predictor (offset, fixed
# effects, unit intercepts) without the Model T iid year-month effect; sd_ym (Model T only) and theta are fitted values.
sim_null_state <- function(d, test) {
  tr <- .test_row(test)
  alt <- if (tr$model == "L") sim_spec_l(tr$outcome) else sim_spec_t(tr$outcome)
  drop <- sim_drop_terms(tr$model, tr$summary)
  null <- alt
  null$fixed <- setdiff(alt$fixed, drop)
  if (length(null$fixed) != length(alt$fixed) - length(drop))
    stop("sim_null_state: tested terms not in the spec", call. = FALSE)
  d0 <- droplevels(complete_rows(d, unique(c(spec_vars(alt), "ym_f")))$data)
  f0 <- if (tr$model == "L") fit_nb(null, d0, fitter = nb_fitter_with(character())) else
    fit_time_chain(null, d0, chain = "iid")
  if (nrow(f0$data) != nrow(d0)) stop("sim_null_state: the null fit dropped rows", call. = FALSE)
  m <- f0$model
  eta <- unname(stats::predict(m, type = "link"))
  sd_ym <- NULL
  if (tr$model == "T") {
    b_ym <- glmmTMB::ranef(m)$cond$ym_f
    eta <- eta - unname(b_ym[as.character(f0$data$ym_f), "(Intercept)"])
    sd_ym <- unname(attr(glmmTMB::VarCorr(m)$cond$ym_f, "stddev")[[1]])
  }
  list(test_id = tr$test_id, outcome = tr$outcome, model = tr$model, summary = tr$summary, null_spec = null,
       alt_spec = alt, data = f0$data, eta = eta, ym_f = f0$data$ym_f, x = sim_exposure(f0$data, tr$summary),
       sd_ym = sd_ym, theta = unname(stats::sigma(m)))
}

# Simulated counts of simulation i at `rr` (seed + i - 1): mu = exp(eta + b) * rr^x, y ~ NB2(mu, theta); b = the
# redrawn year-month effects N(0, sd_ym^2) for Model T and 0 for Model L.
power_draw_f <- function(st, rr, i, seed) {
  set.seed(seed + i - 1L)
  b <- if (!is.null(st$sd_ym)) stats::rnorm(nlevels(st$ym_f), 0, st$sd_ym)[as.integer(st$ym_f)] else 0
  mu <- exp(st$eta + b) * rr^st$x
  stats::rnbinom(length(mu), size = st$theta, mu = mu)
}

# One refit on a simulated outcome: the summary's RR and two-sided p (or the error).
power_refit_f <- function(task, st) {
  t0 <- Sys.time()
  dd <- data.table::copy(st$data)
  data.table::set(dd, j = st$outcome, value = power_draw_f(st, task$rr, task$sim, st$seed))
  r <- tryCatch({
    f <- if (st$model == "L") fit_nb(st$alt_spec, dd, fitter = nb_fitter_with(character())) else
      fit_time_chain(st$alt_spec, dd, chain = "iid")
    summary_rr(f, SIM_SUMMARY[[st$summary]])
  }, error = function(e) e)
  ok <- !inherits(r, "error")
  data.table::data.table(rr = task$rr, sim = task$sim, ok = ok, est = if (ok) r$rr else NA_real_,
                         p = if (ok) r$p else NA_real_, error = if (ok) NA_character_ else conditionMessage(r),
                         secs = as.numeric(difftime(Sys.time(), t0, units = "secs")))
}

.f_power_task <- function(task) power_refit_f(task, get(".F_POWER_STATE", envir = globalenv()))

# PSOCK workers: Paper E's worker start-up (frozen .e_cluster) plus the Paper F functions.
.f_cluster <- function(cores) {
  cl <- .e_cluster(as.integer(cores))
  parallel::clusterCall(cl, function(root) {
    for (f in c("common_f.R", "perinatal.R", "power_f.R")) source(file.path(root, "F", "R", f), local = globalenv())
    invisible(TRUE)
  }, MODELS_ROOT)
  cl
}

# Power per rr: data.table(test_id, rr, n_ok, power, mean_rr). power = rejections / successful refits; a rejection is
# p < 0.05 with RR > 1; mean_rr = exp(mean log RR over successful refits). Attribute "sims": one row per simulation.
simulate_power_f <- function(d, test_id, rrs, n_sim = 200L, seed = SEED_F, cores = 1L, progress = NULL) {
  n_sim <- as.integer(n_sim)
  # one OpenMP/TMB thread per fit (workers do the same in .e_worker_init), restored on exit
  old_opt <- options(glmmTMB.cores = 1L)
  old_omp <- Sys.getenv("OMP_NUM_THREADS", unset = NA)
  Sys.setenv(OMP_NUM_THREADS = "1")
  on.exit({
    options(old_opt)
    if (is.na(old_omp)) Sys.unsetenv("OMP_NUM_THREADS") else Sys.setenv(OMP_NUM_THREADS = old_omp)
  }, add = TRUE)
  st <- sim_null_state(d, test_id)
  st$seed <- as.integer(seed)
  tasks <- lapply(seq_len(n_sim * length(rrs)), function(k)
    list(rr = rrs[(k - 1L) %/% n_sim + 1L], sim = (k - 1L) %% n_sim + 1L))
  ship <- st[c("outcome", "model", "summary", "alt_spec", "data", "eta", "ym_f", "x", "sd_ym", "theta", "seed")]
  chunk <- max(1L, 4L * as.integer(cores))
  out <- vector("list", length(tasks))
  cl <- NULL
  if (cores > 1L) {
    cl <- .f_cluster(cores)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterCall(cl, function(s) { assign(".F_POWER_STATE", s, envir = globalenv()); NULL }, ship)
  }
  for (s in seq(1L, length(tasks), by = chunk)) {
    idx <- s:min(length(tasks), s + chunk - 1L)
    out[idx] <- if (is.null(cl)) lapply(tasks[idx], power_refit_f, st = ship) else
      parallel::clusterApplyLB(cl, tasks[idx], .f_power_task)
    if (is.function(progress)) progress(max(idx), length(tasks))
  }
  sims <- data.table::rbindlist(out)
  sims[, reject := ok & !is.na(p) & p < 0.05 & est > 1]
  tab <- sims[, .(n_ok = as.integer(sum(ok)), power = if (any(ok)) sum(reject) / sum(ok) else NA_real_,
                  mean_rr = if (any(ok)) exp(mean(log(est[ok]))) else NA_real_), by = rr]
  tab <- data.table::data.table(test_id = st$test_id, tab)
  data.table::setattr(tab, "sims", sims)
  tab[]
}

# The MDE rule on a power table (rr, power) with the contract's wording: Paper E's mde(tbl, "increase") with "IRR"
# shown as "RR" and the label of the simplification appended.
mde_f <- function(tbl) {
  m <- mde(data.table::data.table(irr = tbl$rr, power = tbl$power), "increase")
  list(value = m$value, display = paste(gsub("IRR", "RR", m$display, fixed = TRUE), MDE_LABEL))
}
