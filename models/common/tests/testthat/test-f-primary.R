# Paper F Task 10: primary Model L / Model T, state-cluster bootstrap, Holm family and verdicts
# (models/F/R/primary_f.R, verdicts_f.R). models/common/R and models/E/R are frozen and called unchanged.
# Synthetic data and fake fitters only: no real exposure estimate is produced by these tests.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  for (f in c("common_f.R", "perinatal.R", "power_f.R", "primary_f.R", "verdicts_f.R"))
    source(file.path(root, "F", "R", f), local = globalenv())
})

# ---- verdicts ------------------------------------------------------------------------------------------------------

test_that("negative control failure overrides a significant test", {
  expect_identical(verdict_local(1.04, 0.01, 1.01, 1.08), "not consistent with (negative control failed)")
})

test_that("a lead CI below 1 does not fail the control", {
  expect_identical(verdict_local(1.04, 0.01, 0.90, 0.98), "consistent with")
  expect_identical(verdict_local(1.04, 0.01, 0.95, 1.05), "consistent with")        # a lead CI containing 1 passes
})

test_that("the negative-control wording needs condition (i) to have held", {
  # contract: (i) failed (p_holm 0.30), so the verdict is plain 'not consistent with' whatever the lead
  expect_identical(verdict_local(1.01, 0.30, 1.01, 1.08), "not consistent with")
  expect_identical(verdict_local(0.97, 0.01, 1.01, 1.08), "not consistent with")    # wrong direction
  expect_identical(verdict_local(1.04, NA_real_, 1.01, 1.08), "not consistent with")  # not estimable
  expect_identical(verdict_local(NA_real_, NA_real_, NA_real_, NA_real_), "not consistent with")
})

test_that("El Nino test needs both episode RRs above 1", {
  expect_identical(verdict_enso(1.05, 0.01, 1.10, 0.99), "not consistent with")
  expect_identical(verdict_enso(1.05, 0.01, 0.99, 1.10), "not consistent with")
  expect_identical(verdict_enso(1.05, 0.01, 1.10, 1.02), "consistent with")
  expect_identical(verdict_enso(1.05, 0.06, 1.10, 1.02), "not consistent with")     # Holm p not below 0.05
  expect_identical(verdict_enso(0.95, 0.01, 1.10, 1.02), "not consistent with")
  # an episode model that is not estimable fails condition (iii)
  expect_identical(verdict_enso(1.05, 0.01, NA_real_, NA_real_), "not consistent with")
})

test_that("holm family of six equals p.adjust and drops NA", {
  tests <- data.table::data.table(test_id = TESTS$test_id, hypothesis = toupper(substr(TESTS$test_id, 1, 3)),
                                  outcome = TESTS$outcome, est = log(c(1.04, 1.02, 1.1, 1.03, 1.01, 1.2)),
                                  p = c(0.001, 0.02, 0.03, 0.2, 0.04, 0.5), direction = "gt")
  h <- holm_family_f(tests)
  expect_equal(h$p_holm, stats::p.adjust(tests$p, "holm"))
  expect_equal(nrow(h), 6L)
  t2 <- data.table::copy(tests); t2[3, p := NA_real_]
  h2 <- holm_family_f(t2)
  expect_true(is.na(h2$p_holm[3]))
  expect_equal(h2$p_holm[-3], stats::p.adjust(t2$p[-3], "holm"))                    # five-test family
  expect_error(holm_family_f(tests[1:5]), "six tests")
})

test_that("not estimable counts as not consistent", {
  expect_identical(verdict_local(NA_real_, NA_real_, 0.9, 1.1), "not consistent with")
  v <- c(h10a = "consistent with", h10b = "not consistent with", h10c = "not consistent with")
  o <- overall_verdict_f(v, "H10")
  expect_identical(o$verdict, "consistent with")
  expect_identical(o$text, "consistent with H10 for third-trimester heat")
  v2 <- c(h10a = "not consistent with (negative control failed)", h10b = "not consistent with",
          h10c = "not consistent with")
  expect_identical(overall_verdict_f(v2, "H10")$text, "not consistent with H10")
  expect_identical(overall_verdict_f(v2, "H10")$verdict, "not consistent with")
  v3 <- c(h11a = "consistent with", h11b = "consistent with", h11c = "consistent with")
  expect_identical(overall_f(v3, "H11")$text,
                   "consistent with H11 for full-gestation heat, full-gestation rainfall deficit and an El Niño gestation")
  v4 <- c(h10a = "consistent with", h10b = "not consistent with", h10c = "consistent with")
  expect_identical(overall_f(v4, "H10")$text, "consistent with H10 for third-trimester heat and an El Niño gestation")
})

test_that("verdict_test dispatches by test and reads not-estimable rows as not consistent", {
  tt <- data.table::data.table(test_id = c("h10a", "h10c"), model = c("L", "T"), rr = c(1.04, 1.05),
                               p_holm = c(0.01, 0.01), lead_lo = c(1.01, NA), lead_hi = c(1.08, NA),
                               ep1415 = c(NA, 1.1), ep1819 = c(NA, 1.2))
  expect_identical(verdict_test(tt), c("not consistent with (negative control failed)", "consistent with"))
  tt[2, ep1819 := NA_real_]
  expect_identical(verdict_test(tt)[2], "not consistent with")
})

# ---- cluster bootstrap ---------------------------------------------------------------------------------------------

small_panel <- function(seed = 3, n_units = 12, n_states = 4, n_months = 24, beta = 0.05)
  sim_link_panel(n_units = n_units, n_states = n_states, n_months = n_months, beta = beta, seed = seed)

fake_tab <- function(drop_t = FALSE) {
  set.seed(1)
  rows <- list()
  for (o in OUTS) {
    for (k in names(L_CONTRASTS)) {
      s <- L_CONTRASTS[[k]]
      rr <- exp(rnorm(1, 0.02, 0.01))
      rows[[length(rows) + 1L]] <- .mk_row(o, "L", k, list(est = log(rr), se = 0.01, rr = rr, lo = rr * 0.98, hi = rr * 1.02, p = 0.03),
        if (!is.null(s$lead)) list(rr = 1.0, lo = 0.97, hi = 1.03, p = 0.9), p_kind = "wald", step = "state_ym", re_used = "us",
        n = 1000L, n_units = 50L, pd_hess = TRUE, max_grad = 1e-5)
    }
    for (m in c("T", "T_ep")) for (tm in if (m == "T") c("en", "ln") else c("ep1415", "ep1819", "en_other", "ln"))
      rows[[length(rows) + 1L]] <- .mk_row(o, m, tm, list(est = 0.03, se = 0.01, rr = 1.03, lo = 1.01, hi = 1.05, p = 0.002),
        p_kind = "wald", step = "ar1", re_used = "us", n = 900L, n_units = 40L)
  }
  data.table::rbindlist(rows)
}

test_that("cluster bootstrap relabels duplicated states", {
  d <- small_panel()
  rs <- cluster_resample(d, seed = 7L)
  # every original state contributes whole copies; a drawn-twice state gives distinct ids
  expect_true(all(c("unit_id", "state_ym", "state_unit") %in% names(rs)))
  expect_gt(nlevels(rs$state_unit), 0L)
  st_orig <- table(d$state_unit)[levels(d$state_unit)]
  rs_state <- sub("_[0-9]+$", "", as.character(rs$state_unit))
  draws <- tapply(rs$state_unit, rs_state, function(x) length(unique(x)))
  expect_equal(sum(draws), nlevels(d$state_unit))                           # as many draws as states
  # find a seed that draws some state twice and check distinct levels
  twice <- NULL
  for (s in 1:200) {
    r <- cluster_resample(d, seed = s)
    k <- table(sub("_[0-9]+$", "", unique(as.character(r$state_unit))))
    if (any(k >= 2L)) { twice <- r; break }
  }
  expect_false(is.null(twice))
  base <- sub("_[0-9]+$", "", as.character(twice$unit_id))
  dup_state <- names(which(table(sub("_[0-9]+$", "", unique(as.character(twice$state_unit)))) >= 2L))[1]
  ids <- unique(as.character(twice$unit_id)[sub("_[0-9]+$", "", as.character(twice$state_unit)) == dup_state])
  expect_gt(length(ids), 0L)
  expect_equal(length(ids), 2L * length(unique(d$unit_id[d$state_unit == dup_state])))
  sym <- unique(as.character(twice$state_ym)[sub("_[0-9]+$", "", as.character(twice$state_unit)) == dup_state])
  expect_equal(length(sym), 2L * length(unique(d$state_ym[d$state_unit == dup_state])))
  expect_true(all(grepl("_[0-9]+$", levels(twice$unit_id))))
  expect_true(all(grepl("_[0-9]+$", levels(twice$state_ym))))
  # deterministic in the seed
  expect_identical(cluster_resample(d, seed = 9L)$unit_id, cluster_resample(d, seed = 9L)$unit_id)
})

test_that("cluster bootstrap reports a Wald p from the bootstrap SE and percentile CIs", {
  skip_on_cran()
  d <- small_panel(seed = 11)
  spec <- l_spec("sb", slopes = character(), re = "int")
  bb <- cluster_bootstrap_state(spec, d, B = 6L, seed = 100L, cores = 1L)
  expect_equal(bb$B, 6L)
  expect_gte(bb$B_ok, 5L)
  expect_true(all(c("tmax_t3", "tmax_t2", "tmax_t1", "spi3_dry_l0", "tmax_lead12") %in% colnames(bb$betas)))
  rows <- rows_from_bootstrap(bb, "sb")
  r <- rows[term == "heat_t3"]
  b <- bb$betas[is.finite(bb$betas[, "tmax_t3"]), "tmax_t3"]
  z <- bb$est[["tmax_t3"]] / stats::sd(b)
  expect_equal(r$p, 2 * (1 - stats::pnorm(abs(z))))                          # Wald from the bootstrap SE: no floor
  expect_equal(r$rr, exp(bb$est[["tmax_t3"]]))
  expect_equal(c(r$lo, r$hi), exp(unname(stats::quantile(b, c(0.025, 0.975)))))
  dry <- rows[term == "dry_gest"]
  bd <- -rowSums(bb$betas[, L_DRY, drop = FALSE])
  bd <- bd[is.finite(bd)]
  expect_equal(dry$rr, exp(-sum(bb$est[L_DRY])))
  expect_equal(c(dry$lo, dry$hi), exp(unname(stats::quantile(bd, c(0.025, 0.975)))))
  expect_gt(dry$hi, dry$lo)
})

test_that("cluster bootstrap stops when more than 10% of refits fail", {
  d <- small_panel(seed = 5)
  calls <- 0L
  flaky <- function(formula, data, family = glmmTMB::nbinom2()) {
    calls <<- calls + 1L
    if (calls == 1L) return(e_glmmTMB_fit(formula, data, family))          # the original rows
    stop("synthetic refit failure")
  }
  spec <- l_spec("sb", slopes = character(), re = "int")
  expect_error(cluster_bootstrap_state(spec, d, B = 4L, seed = 1L, cores = 1L, fit_fun = flaky),
               "cluster bootstrap: more than 10% of refits failed")
})

test_that("model L falls back to the cluster bootstrap when state_ym fails", {
  skip_on_cran()
  d <- small_panel(seed = 21)
  fake <- function(formula, data, family = glmmTMB::nbinom2()) {            # the state-month effect never converges
    if (grepl("state_ym", deparse1(formula), fixed = TRUE)) stop("synthetic: state_ym fails")
    e_glmmTMB_fit(formula, data, family)
  }
  spec <- l_spec("sb", slopes = character(), re = "int")
  r <- fit_model_l(d, "sb", spec = spec, fit_fun = fake, B = 5L, cores = 1L)
  expect_false(r$state_ym)
  expect_equal(r$boot_B, 5L)
  expect_gte(r$B_ok, 4L)
  expect_true(all(c("heat_t3", "heat_gest", "dry_gest") %in% r$rows$term))
  expect_true(all(r$rows[term %in% c("heat_t3", "heat_gest", "dry_gest")]$p_kind == "bootstrap"))
  expect_equal(nrow(r$rows[grepl("^(heat|dry)_tri", term)]), 6L)             # trimester strata rows
  expect_false(any(is.na(r$rows[term == "heat_t3", .(rr, lo, hi, p, lead_rr, lead_lo, lead_hi)])))
})

test_that("model L keeps the state-month effect when it converges", {
  skip_on_cran()
  d <- small_panel(seed = 22, n_units = 12, n_states = 3)
  spec <- l_spec("sb", slopes = character(), re = "int")
  r <- fit_model_l(d, "sb", spec = spec, B = 5L, cores = 1L)
  expect_true(r$state_ym)
  expect_true(is.na(r$boot_B))
  expect_true(all(r$rows[term == "heat_t3"]$p_kind == "wald"))
  dd <- r$rows[term == "heat_t3"]
  expect_lt(dd$lo, dd$rr); expect_gt(dd$hi, dd$rr)
})

# ---- Model T -------------------------------------------------------------------------------------------------------

test_that("model T falls back to the block bootstrap with a Wald p from the bootstrap SE", {
  d <- small_panel(seed = 31)
  d[, `:=`(en_ep1415 = en_gest, en_ep1819 = 0, en_other = 0)]
  # a chain that never converges (the fitter fails on every time random effect) and a fake block bootstrap
  failing <- function(formula, data, family = glmmTMB::nbinom2()) stop("synthetic: no time effect")
  calls <- list()
  fake_boot <- function(spec, d, term, B, block, seed, cores, fit_fun, progress = NULL) {
    set.seed(1)
    betas <- matrix(rnorm(B * length(term), mean = rep(c(0.05, -0.02, 0.01, 0.03)[seq_along(term)], each = B), sd = 0.02),
                    nrow = B, dimnames = list(NULL, term))
    betas[3, 1] <- NA_real_                                                  # a failed refit is dropped
    calls[[length(calls) + 1L]] <<- list(term = term, B = B, block = block, seed = seed, betas = betas)
    list(term = term, est = stats::setNames(rep(0.05, length(term)), term), B = B, B_ok = B - 1L, re_used = "int",
         n = nrow(d), n_units = nlevels(d$unit_id), betas = betas, pd_hess = TRUE, max_grad = 1e-6)
  }
  r <- fit_model_t(d, "sb", fit_fun = failing, boot_fun = fake_boot, B = 20L, cores = 1L)
  expect_identical(r$time_re, "block_bootstrap")
  expect_identical(r$ep_time_re, "block_bootstrap")
  expect_equal(r$boot_B, 20L)
  expect_length(calls, 2L)
  expect_identical(calls[[1]]$term, c("en_gest", "ln_gest"))
  expect_identical(calls[[2]]$term, c("en_ep1415", "en_ep1819", "en_other", "ln_gest"))
  expect_identical(calls[[1]]$block, 12L)
  expect_identical(calls[[1]]$seed, SEED_F)
  bt <- calls[[1]]$betas
  ok <- stats::complete.cases(bt)
  en <- r$rows[model == "T" & term == "en"]
  expect_identical(en$p_kind, "bootstrap")
  expect_equal(en$p, 2 * stats::pnorm(-abs(0.05 / stats::sd(bt[ok, "en_gest"]))))
  q <- stats::quantile(bt[ok, "en_gest"], c(0.025, 0.975), names = FALSE)
  expect_equal(c(en$lo, en$hi), exp(q))
  expect_equal(en$rr, exp(0.05))
  ln <- r$rows[model == "T" & term == "ln"]
  ql <- stats::quantile(bt[ok, "ln_gest"], c(0.025, 0.975), names = FALSE)
  expect_equal(ln$lo, 1 / exp(ql[2])); expect_equal(ln$hi, 1 / exp(ql[1]))   # the bounds swap on the bootstrap path
  expect_equal(ln$rr, exp(-0.05))
})

test_that("a Model T term-extraction failure is not estimable, not a stop (M2)", {
  d <- small_panel(seed = 33, n_units = 14, n_months = 40)
  d[, `:=`(en_ep1415 = en_gest, en_ep1819 = 0, en_other = 0)]            # en_ep1819 and en_other are all zero: dropped
  r <- fit_model_t(d, "sb", chain = "iid", B = 5L, cores = 1L)
  expect_true(all(r$rows[model == "T"]$status == "ok"))
  ep <- r$rows[model == "T_ep"]
  expect_true(all(ep$status == "error"))
  expect_match(ep$error[1], "^term_row: term\\(s\\) not in model")
  expect_true(all(is.na(ep$rr)))
  expect_equal(ep$n[1], r$n)                                              # known counts are kept
})

test_that("a bootstrap failure keeps the known structure keys (M5)", {
  d <- small_panel(seed = 34)
  fake <- function(formula, data, family = glmmTMB::nbinom2()) {
    if (grepl("state_ym", deparse1(formula), fixed = TRUE)) stop("synthetic: state_ym fails")
    e_glmmTMB_fit(formula, data, family)
  }
  boom <- function(...) stop(errorCondition("cluster bootstrap: more than 10% of refits failed (x)", B_ok = 3L))
  spec <- l_spec("sb", slopes = character(), re = "int")
  r <- fit_model_l(d, "sb", spec = spec, fit_fun = fake, B = 7L, cores = 1L, boot_fun = boom)
  expect_false(r$state_ym)
  expect_equal(r$boot_B, 7L); expect_equal(r$B_ok, 3L)
  expect_true(all(r$rows$status == "error"))
  expect_identical(unique(r$rows$step), "cluster_bootstrap")
  expect_gt(r$rows$n[1], 0L)
  # Model T: the chain fails and the block bootstrap fails the 10% rule
  d2 <- small_panel(seed = 35)
  d2[, `:=`(en_ep1415 = en_gest, en_ep1819 = 0, en_other = 0)]
  failing <- function(formula, data, family = glmmTMB::nbinom2()) stop("synthetic")
  bad_boot <- function(...) stop(errorCondition("block bootstrap: more than 10% of refits failed (x)", B_ok = 5L))
  rt <- fit_model_t(d2, "sb", fit_fun = failing, boot_fun = bad_boot, B = 9L, cores = 1L)
  expect_identical(rt$time_re, "block_bootstrap")
  expect_equal(rt$boot_B, 9L); expect_equal(rt$B_ok, 5L)
  expect_true(all(rt$rows$status == "error"))
  expect_gt(rt$n, 0L)
  # the keys: structure, B and n stay known; estimates read not estimable
  tab <- fake_tab()
  tab <- tab[!(outcome == "sb" & model %in% c("L", "T", "T_ep"))]
  tab <- rbind(tab, r$rows, rt$rows, fill = TRUE)
  tests <- build_tests(tab)
  v <- stats::setNames(tests$verdict, tests$test_id)
  ent <- primary_entries(tab, tests, list(h10 = overall_verdict_f(v, "H10"), h11 = overall_verdict_f(v, "H11")))
  expect_identical(ent[["F.l.sb.state_ym"]]$display, "state-cluster bootstrap (B = 7)")
  expect_identical(ent[["F.l.sb.boot_B"]]$display, "7")
  expect_identical(ent[["F.t.sb.time_re"]]$display, "moving-block bootstrap over months (block 12, B = 9)")
  expect_match(ent[["F.l.sb.heat_t3.rr"]]$display, "^not estimable")
  expect_false(is.na(ent[["F.l.sb.n"]]$value))
  expect_false(is.na(ent[["F.t.sb.n"]]$value))
})

test_that("model T runs the chain and the episode refit on the same step", {
  skip_on_cran()
  d <- small_panel(seed = 32, n_units = 14, n_months = 40)
  ym0 <- min(d$ym)
  d[, `:=`(en_ep1415 = en_gest * (ym < ym0 + 14L), en_ep1819 = en_gest * (ym >= ym0 + 14L & ym < ym0 + 28L), en_other = 0)]
  d[, en_other := en_gest - en_ep1415 - en_ep1819]
  r <- fit_model_t(d, "lbw", chain = "iid", B = 5L, cores = 1L)
  expect_identical(r$time_re, "iid")
  expect_identical(r$ep_time_re, "iid")
  expect_true(all(c("en", "ln", "ep1415", "ep1819", "en_other") %in% r$rows$term))
  ln <- r$rows[model == "T" & term == "ln"]
  expect_lt(ln$lo, ln$rr); expect_gt(ln$hi, ln$lo)
  expect_true(all(is.finite(unlist(r$rows[term %in% c("en", "ep1415", "ep1819"), .(rr, lo, hi, p)]))))
  expect_gt(r$n, 0L); expect_gt(r$n_units, 0L)
})

# ---- run_primary guard ---------------------------------------------------------------------------------------------

test_that("run_primary refuses without committed power output", {
  untracked <- function(...) structure(character(), status = 1L)
  clean_tracked <- function(args) {
    if (args[1] == "ls-files") return("papers/F/output/power.csv")
    character()
  }
  expect_error(assert_power_committed(git_fun = untracked), "committed")
  dirty <- function(args) if (args[1] == "ls-files") "papers/F/output/power.csv" else " M papers/F/output/power.csv"
  expect_error(assert_power_committed(git_fun = dirty), "unmodified")
  expect_silent(assert_power_committed(git_fun = clean_tracked))
  expect_error(run_primary(git_fun = untracked), "committed")
})

test_that("dropped outcomes read not estimable in every row", {
  r <- dropped_rows("sb")
  expect_true(all(r$error == "dropped: more than 20% of link-unit-months masked"))
  expect_identical(not_estimable(r$error[1]), "not estimable (dropped: more than 20% of link-unit-months masked)")
  expect_true(all(r$status == "dropped"))
  expect_true(all(is.na(r$rr)))
})

test_that("estimation failures are only the genuine ones", {
  expect_true(is_estimation_failure_f("fit_nb: no structure converged for sb (tried us, diag, int)"))
  expect_true(is_estimation_failure_f("cluster bootstrap: more than 10% of refits failed (x)"))
  expect_true(is_estimation_failure_f("term_row: term(s) not in model: tmax_t3"))
  expect_false(is_estimation_failure_f("complete_rows: missing column(s): tmax_t3"))
})

# ---- contract keys -------------------------------------------------------------------------------------------------

test_that("primary_entries covers exactly the contract keys of sections 5 to 7", {
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  if (!exists("contract_keys")) source(file.path(root, "D", "R", "contract.R"))
  keys <- contract_keys(file.path(root, "..", "papers", "F", "results_keys.md"), prefix = "F")
  mine <- keys[grepl("^F[.](l|t|h1[01][abc]?)[.]", keys)]
  expect_length(mine, 72L)
  tab <- fake_tab()
  tests <- build_tests(tab)
  v <- stats::setNames(tests$verdict, tests$test_id)
  ent <- primary_entries(tab, tests, list(h10 = overall_verdict_f(v, "H10"), h11 = overall_verdict_f(v, "H11")))
  expect_setequal(names(ent), mine)
  expect_true(all(vapply(ent, function(e) is.character(e$display) && nzchar(e$display), NA)))
  expect_identical(ent[["F.l.sb.state_ym"]]$display, "state-month random effect")
  expect_identical(ent[["F.l.sb.boot_B"]]$display, "not applicable (state-month random effect converged)")
  expect_identical(ent[["F.t.lbw.time_re"]]$display, "AR(1) year-month random effect")
})

test_that("build_tests: lead and episode columns, Holm family and not-estimable tests", {
  tab <- fake_tab()
  tab[outcome == "sb" & model == "L" & term == "heat_t3", `:=`(lead_lo = 1.01, lead_hi = 1.08, p = 1e-6)]
  tab[outcome == "lbw" & model == "T_ep" & term == "ep1819", rr := 0.99]
  tt <- build_tests(tab)
  expect_equal(tt$p_holm, stats::p.adjust(tt$p, "holm"))
  expect_identical(tt[test_id == "h10a"]$verdict, "not consistent with (negative control failed)")
  expect_identical(tt[test_id == "h11c"]$verdict, "not consistent with")
  expect_identical(tt[test_id == "h10c"]$verdict, "consistent with")
  # a not-estimable Model T leaves the family and counts as not consistent
  tab[outcome == "sb" & model == "T" & term == "en", `:=`(rr = NA_real_, p = NA_real_, status = "error", error = "fit_nb: no structure converged for sb")]
  tt <- build_tests(tab)
  expect_true(is.na(tt[test_id == "h10c"]$p_holm))
  expect_identical(tt[test_id == "h10c"]$verdict, "not consistent with")
  expect_equal(tt[!is.na(p)]$p_holm, stats::p.adjust(tt[!is.na(p)]$p, "holm"))
})

test_that("lead descriptions carry the lead's own numbers and every rr/p description names the step (I1)", {
  tab <- fake_tab()
  tab[outcome == "sb" & model == "L" & term %in% c("heat_t3", "heat_gest", "dry_gest"),
      `:=`(lead_est = 0.00226, lead_se = 0.0031, lead_rr = 1.00226, lead_lo = 0.99625, lead_hi = 1.00831, lead_p = 0.466)]
  tests <- build_tests(tab)
  v <- stats::setNames(tests$verdict, tests$test_id)
  ent <- primary_entries(tab, tests, list(h10 = overall_verdict_f(v, "H10"), h11 = overall_verdict_f(v, "H11")))
  d <- ent[["F.l.sb.heat_t3.lead_rr"]]$description
  expect_match(d, "log-scale coefficient 0.00226, SE 0.0031", fixed = TRUE)
  expect_match(d, "RR 1.00226 (Wald 95% CI 0.99625 to 1.00831); p 0.466", fixed = TRUE)
  expect_false(grepl("p 0.03", d, fixed = TRUE))                         # not the summary's p
  m <- ent[["F.l.sb.heat_t3.rr"]]$description
  expect_match(m, "(1 | state_ym) random effect", fixed = TRUE)
  expect_match(ent[["F.l.sb.heat_t3.p"]]$description, "(1 | state_ym) random effect", fixed = TRUE)
  expect_match(ent[["F.t.sb.en.rr"]]$description, "ar1(ym_f + 0 | national)", fixed = TRUE)
  expect_match(ent[["F.t.lbw.en.p"]]$description, "ar1(ym_f + 0 | national)", fixed = TRUE)
})

test_that("primary_entries covers bootstrap steps and a dropped outcome (M4)", {
  tab <- fake_tab()
  tab <- tab[outcome != "lbw"]
  tab <- rbind(tab, dropped_rows("lbw"), fill = TRUE)
  tab[outcome == "sb" & model == "L", `:=`(step = "cluster_bootstrap", boot_B = 200L, B_ok = 190L, p_kind = "bootstrap")]
  tab[outcome == "sb" & model %in% c("T", "T_ep"), `:=`(step = "block_bootstrap", boot_B = 500L, B_ok = 480L, p_kind = "bootstrap")]
  tests <- build_tests(tab)
  v <- stats::setNames(tests$verdict, tests$test_id)
  ent <- primary_entries(tab, tests, list(h10 = overall_verdict_f(v, "H10"), h11 = overall_verdict_f(v, "H11")))
  expect_identical(ent[["F.l.sb.state_ym"]]$display, "state-cluster bootstrap (B = 200)")
  expect_identical(ent[["F.l.sb.boot_B"]]$display, "200")
  expect_identical(ent[["F.t.sb.time_re"]]$display, "moving-block bootstrap over months (block 12, B = 500)")
  expect_match(ent[["F.l.sb.heat_t3.rr"]]$description, "state-cluster bootstrap (B = 200, B_ok = 190)", fixed = TRUE)
  expect_match(ent[["F.l.sb.heat_t3.rr"]]$description, "two-sided Wald p from the bootstrap SE, no floor", fixed = TRUE)
  expect_identical(ent[["F.h11a.p_holm"]]$display, "not estimable (dropped: more than 20% of link-unit-months masked)")
  expect_identical(ent[["F.h11a.verdict"]]$display, "not consistent with")
  expect_identical(ent[["F.l.lbw.state_ym"]]$display, "not estimable (dropped: more than 20% of link-unit-months masked)")
  expect_identical(ent[["F.h11.verdict"]]$display, "not consistent with")
  expect_true(is.na(tests[test_id == "h11a"]$p_holm))
})

test_that("fit diagnostics are stored per fit (M1)", {
  skip_on_cran()
  d <- small_panel(seed = 41)
  spec <- l_spec("sb", slopes = character(), re = "int")
  r <- fit_model_l(d, "sb", spec = spec, B = 4L, cores = 1L)
  hr <- r$rows[term == "heat_t3"]
  expect_true(hr$pd_hess)
  expect_false(is.na(hr$grad_par))
  expect_true(is.finite(hr$newton_se))
  expect_true(is.finite(hr$max_grad))
})
