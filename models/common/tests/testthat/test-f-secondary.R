# Paper F Task 11: selection audit, secondary models, trimester rows and the 17 sensitivities
# (models/F/R/secondary_f.R). models/common/R and models/E/R are frozen and called unchanged.
# Synthetic data and fake fitters only: no real exposure estimate is produced by these tests.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  for (f in c("common_f.R", "perinatal.R", "power_f.R", "primary_f.R", "verdicts_f.R", "secondary_f.R"))
    source(file.path(root, "F", "R", f), local = globalenv())
  source(file.path(root, "D", "R", "contract.R"), local = globalenv())
  assign("CONTRACT_MD_T", file.path(dirname(root), "papers", "F", "results_keys.md"), envir = globalenv())
})

# A small table with every column the cases read (primary-window layout).
sens_panel <- function(seed = 5, n_units = 14, n_states = 3, n_months = 30) {
  d <- sim_link_panel(n_units = n_units, n_states = n_states, n_months = n_months, beta = 0.02, seed = seed)
  set.seed(seed)
  d[, `:=`(tb = round(exp(log_tb)), wt = round(exp(log_wt)))]
  d[, `:=`(lb = tb - sb, lb_m = round((tb - sb) / 2), lb_f = tb - sb - round((tb - sb) / 2))]
  d[, `:=`(log_lb = log(lb), log_lb_f = log(lb_f), log_days = log(30), preterm = rbinom(.N, lb, 0.08),
           inst = round(tb * 0.8), home = tb - round(tb * 0.8), inst_share = 0.8, wt_cov = 0.85)]
  for (v in c("sb", "lbw", "tb", "wt")) {
    d[, paste0(v, "_scaled") := get(v) + 0]
    d[, paste0(v, "_masklow") := get(v) + 0]
    d[, paste0(v, "_allcomp") := get(v) + 0]
  }
  d[, `:=`(excluded_sb = 0L, excluded_lbw = 0L, small_denom_sb = 0L, small_denom_lbw = 0L, excluded_preterm = 0L,
           small_denom_preterm = 0L, excluded_lb_m = 0L, excluded_lb_f = 0L, excluded_tb = 0L, excluded_wt = 0L,
           excluded_inst = 0L, excluded_home = 0L, in_primary = 1L)]
  u <- levels(d$unit_id)
  d[, `:=`(small_unit = as.integer(unit_id == u[1]), single_district = as.integer(unit_id %in% u[1:5]),
           inst090_all_fy = as.integer(unit_id %in% u[3:9]))]
  d[, `:=`(hw_t3 = rpois(.N, 1), hw_t2 = rpois(.N, 1), hw_t1 = rpois(.N, 1))]
  for (k in 0:8) d[, paste0("tmax_l", k) := tmax_t3 + rnorm(.N, 0, 0.3)]
  d[, `:=`(covid_mar2020 = 0L, covid_lockdown = 0L, covid_fy2021 = 0L, laqshya = as.integer(ym >= min(ym) + 20L),
           pmsma = as.integer(ym >= min(ym) + 10L), en_roni_gest = en_gest * 0.9, ln_roni_gest = ln_gest * 0.9,
           era_e2 = as.integer(ym >= min(ym) + 15L))]
  d[, unit_era := interaction(unit_id, era_e2, sep = ":", drop = TRUE, lex.order = TRUE)]
  d[]
}

# ---- the contract ------------------------------------------------------------------------------------------------------

test_that("sens ids match the contract", {
  keys <- contract_keys(CONTRACT_MD_T, prefix = "F")
  ids <- unique(sub("^F\\.sens\\.(sb|lbw)\\.([a-z0-9_]+)\\.(heat|dry|en)$", "\\2", grep("^F\\.sens\\.", keys, value = TRUE)))
  expect_setequal(SENS_IDS_F, ids)
  expect_identical(length(SENS_IDS_F), 17L)
  expect_identical(SENS_IDS_F[1], "fy2021")                               # the order of the contract table
  expect_identical(SENS_IDS_F, ids)
})

# fake rows: an ok row per arm and term, the not-applicable rows from the real rule
fake_rows <- function(label, model, terms, case, arm, status = "ok", error = NA_character_) {
  data.table::rbindlist(lapply(terms, function(tm) {
    r <- .mk_row(label, model, tm, list(est = log(1.02), se = 0.01, rr = 1.02, lo = 1.0, hi = 1.04, p = 0.05),
                 p_kind = "wald", step = if (model == "L") "state_ym" else "ar1", re_used = "us", n = 100L, n_units = 10L,
                 pd_hess = TRUE, max_grad = 1e-4, status = status, error = error)
    r[, `:=`(case = case, arm = arm, note = "x")]
    r
  }))
}

test_that("the entries equal the contract keys of sections 8 (selection), 10 and 11", {
  sel <- data.table::rbindlist(lapply(SEL_DENOMS, function(den) rbind(fake_rows(den, "L", SENS_TERMS_F$L, "selection", "L"),
                                                                       fake_rows(den, "T", "en", "selection", "T"))))
  sec <- rbind(fake_rows("preterm", "L", SENS_TERMS_F$L, "preterm", "L"), fake_rows("lb_m", "L", SENS_TERMS_F$L, "sexratio", "L"))
  sens <- data.table::rbindlist(lapply(OUTS, function(o) data.table::rbindlist(lapply(SENS_IDS_F, function(id) {
    mk <- function(arm) {
      reason <- sens_na_reason(id, arm)
      terms <- SENS_TERMS_F[[arm]]
      if (!is.null(reason)) .sens_na_rows(o, id, arm, terms, reason) else fake_rows(o, arm, terms, id, arm)
    }
    data.table::rbindlist(list(mk("L"), mk("T")), use.names = TRUE, fill = TRUE)
  }), use.names = TRUE, fill = TRUE)), use.names = TRUE, fill = TRUE)
  ent <- secondary_entries(sel, sec, sens)
  keys <- contract_keys(CONTRACT_MD_T, prefix = "F")
  want <- grep("^F\\.(sel|pre|nc|sens)\\.", keys, value = TRUE)
  expect_setequal(names(ent), want)
  expect_identical(length(ent), 118L)
  expect_identical(length(want), 12L + 3L + 1L + 102L)
  expect_true(all(vapply(ent, function(e) is.character(e$display) && nzchar(e$display), NA)))
  expect_identical(ent[["F.sel.tb.heat_t3.rr"]]$display, fmt_ci(1.02, 1.0, 1.04, 3))
  expect_match(ent[["F.sens.sb.betabin.heat"]]$description, "odds ratio")
  expect_match(ent[["F.sel.inst_share.en.rr"]]$description, "odds ratio")
  # the written entries pass write_results' schema check
  expect_silent(write_results(ent, tempfile(fileext = ".json")))
})

# ---- not applicable ------------------------------------------------------------------------------------------------

test_that("not applicable cases display the reason", {
  d <- sens_panel()
  s <- sens_case_f("state_moy", d, NULL, "sb")
  expect_null(s$t_spec)
  expect_identical(s$t_reason, "not applicable (Model L only)")
  expect_identical(s$l_extra, "state_unit:moy")
  expect_false(is.null(s$l_spec))
  e <- sens_case_f("era_int", d, NULL, "sb")
  expect_null(e$l_spec); expect_identical(e$l_reason, "not applicable (Model T only)")
  expect_identical(e$t_extra, "(1 | unit_era)")
  expect_true("hmis_format2017" %in% e$t_spec$fixed)                       # the step is kept (contract)
  expect_identical(sens_case_f("extra_prog", d, NULL, "lbw")$l_reason,
                   "not applicable (Model T only; year-month fixed effects absorb programme indicators)")
  expect_identical(sens_case_f("ns4", d, NULL, "sb")$t_reason, "not applicable (Model L heat lag basis)")
  expect_identical(sens_case_f("heatwave", d, NULL, "sb")$t_reason, "not applicable (Model L heat metric)")
  for (id in c("roni", "drop_ep1415", "drop_ep1819")) expect_identical(sens_case_f(id, d, NULL, "sb")$l_reason, "not applicable (Model T only)")
  # and the null spec of a fitted arm is NULL only for the n/a one
  expect_false(is.null(sens_case_f("fy2021", d, d, "sb")$l_spec))
  # the arm rows carry the display and no fit happens
  r <- sens_arm_rows("state_moy", "sb", "T", d, case = s, fit_arm_fun = function(...) stop("must not fit"))
  expect_identical(unique(r$status), "not_applicable")
  expect_identical(unique(r$error), "not applicable (Model L only)")
})

test_that("allcomp is not applicable when it equals the primary columns on every primary row", {
  d <- sens_panel()
  cs <- sens_case_f("allcomp", d, NULL, "sb")
  expect_identical(cs$l_reason, "not applicable (identical to the primary analysis: no crosswalk component missing)")
  expect_identical(cs$t_reason, cs$l_reason)
  expect_null(cs$l_spec); expect_null(cs$t_spec)
  # a differing value or a differing missing pattern makes it applicable
  d2 <- data.table::copy(d); d2[3, sb_allcomp := sb_allcomp + 1]
  expect_true(is.null(sens_case_f("allcomp", d2, NULL, "sb")$l_reason))
  d3 <- data.table::copy(d); d3[5, tb_allcomp := NA_real_]
  expect_false(allcomp_identical(d3, "sb"))
  d4 <- data.table::copy(d); d4[5, `:=`(sb = NA_real_, sb_allcomp = NA_real_)]
  expect_true(allcomp_identical(d4, "sb"))                                   # NA in both: the pattern is the same
  d5 <- data.table::copy(d); d5[5, sb := NA_real_]
  expect_false(allcomp_identical(d5, "sb"))
  ok <- sens_case_f("allcomp", d2, NULL, "sb")
  expect_identical(ok$l_spec$outcome, "sb_allcomp")
  expect_identical(ok$l_spec$offset, "log_tb_allcomp")
  expect_true(all(c("log_tb_allcomp") %in% names(ok$data)))
  # rows outside the primary window are ignored by the check
  d6 <- data.table::copy(d); d6[1, `:=`(in_primary = 0L, sb_allcomp = sb_allcomp + 5)]
  expect_true(allcomp_identical(d6, "sb"))
})

# ---- case definitions -----------------------------------------------------------------------------------------------

test_that("fy2021 adds the three COVID terms to Model T only", {
  d <- sens_panel()
  d21 <- data.table::copy(d); d21[, ym := ym + 80L]                            # some rows from March 2020 on (24242)
  expect_true(any(d21$ym >= 24242L))
  cs <- sens_case_f("fy2021", d, d21, "sb")
  expect_true(all(c("covid_mar2020", "covid_lockdown", "covid_fy2021") %in% cs$t_spec$fixed))
  expect_false(any(c("covid_mar2020", "covid_lockdown", "covid_fy2021") %in% cs$l_spec$fixed))
  expect_identical(cs$l_spec, l_spec("sb"))                                  # Model L unchanged in form
  expect_identical(cs$t_spec$fixed, t_spec_f("sb", extra = c("covid_mar2020", "covid_lockdown", "covid_fy2021"))$fixed)
  expect_identical(nrow(cs$data), nrow(outcome_rows(d21, "sb")))
  expect_true(is.na(cs$skip))
  # no row through March 2020 or later: FY2020-21 unusable, the whole case is not estimable
  d_late <- data.table::copy(d); d_late[, ym := ym - 100000L]                   # every row before March 2020 only
  late <- sens_case_f("fy2021", d, d_late, "sb")
  expect_match(late$skip, "^FY2020-21 ")                                       # the bare reason; the key wraps it once
  r <- sens_arm_rows("fy2021", "sb", "T", d, case = late, fit_arm_fun = function(...) stop("must not fit"))
  expect_identical(unique(r$status), "error")
  expect_match(unique(r$error), "^FY2020-21 ")
  expect_identical(.entry_from_row(r[1], "x")$display, "not estimable (FY2020-21 has no usable link-unit-months)")
  # and through secondary_entries: the displayed key value is wrapped exactly once
  sens <- data.table::rbindlist(lapply(OUTS, function(o) data.table::rbindlist(lapply(SENS_IDS_F, function(id) {
    mk <- function(arm) {
      reason <- sens_na_reason(id, arm); terms <- SENS_TERMS_F[[arm]]
      if (!is.null(reason)) .sens_na_rows(o, id, arm, terms, reason)
      else if (id == "fy2021") .sens_na_rows(o, id, arm, terms, late$skip, "error") else fake_rows(o, arm, terms, id, arm)
    }
    data.table::rbindlist(list(mk("L"), mk("T")), use.names = TRUE, fill = TRUE)
  }), use.names = TRUE, fill = TRUE)), use.names = TRUE, fill = TRUE)
  sel <- data.table::rbindlist(lapply(SEL_DENOMS, function(den) rbind(fake_rows(den, "L", SENS_TERMS_F$L, "selection", "L"), fake_rows(den, "T", "en", "selection", "T"))))
  sec <- rbind(fake_rows("preterm", "L", SENS_TERMS_F$L, "preterm", "L"), fake_rows("lb_m", "L", SENS_TERMS_F$L, "sexratio", "L"))
  ent <- secondary_entries(sel, sec, sens)
  expect_identical(ent[["F.sens.sb.fy2021.heat"]]$display, "not estimable (FY2020-21 has no usable link-unit-months)")
  expect_identical(ent[["F.sens.lbw.fy2021.en"]]$display, "not estimable (FY2020-21 has no usable link-unit-months)")
  expect_match(ent[["F.sens.sb.heatwave.heat"]]$description, "per \\+1 heatwave day")
  expect_false(grepl("deg C", ent[["F.sens.sb.heatwave.heat"]]$description, fixed = TRUE))
  expect_match(ent[["F.sens.lbw.heatwave.heat"]]$description, "per \\+1 heatwave day sustained over gestation")
})

test_that("heatwave never enters with tmax strata", {
  d <- sens_panel()
  cs <- sens_case_f("heatwave", d, NULL, "sb")
  fx <- cs$l_spec$fixed
  expect_true(all(c("hw_t3", "hw_t2", "hw_t1") %in% fx))
  expect_false(any(c("tmax_t3", "tmax_t2", "tmax_t1") %in% fx))
  expect_true(all(c("tmax_lead12", "spi3_dry_lead3", "ym_f") %in% fx))        # the leads and SPI terms stay
  expect_setequal(cs$l_contrasts$heat_gest$terms, c("hw_t3", "hw_t2", "hw_t1"))
  expect_identical(cs$l_contrasts$heat_t3$terms, "hw_t3")
})

test_that("ns4 uses the natural-spline cross-basis and sums lag coefficients over the lag windows", {
  d <- sens_panel()
  b <- dlm_basis(lags = 0:8, df = 4L)
  expect_identical(dim(b), c(9L, 4L))
  cb <- ns_cross_basis(d, "tmax", b)
  expect_equal(unname(as.matrix(cb[, paste0("tmax_cb", 1:4), with = FALSE])),
               unname(as.matrix(d[, paste0("tmax_l", 0:8), with = FALSE]) %*% b))
  expect_equal(nrow(cb), nrow(d)); expect_false("tmax_cb1" %in% names(d))
  expect_error(ns_cross_basis(d[, !"tmax_l8"], "tmax", b), "missing lag column")
  cs <- sens_case_f("ns4", d, NULL, "sb")
  expect_false(any(c("tmax_t3", "tmax_t2", "tmax_t1") %in% cs$l_spec$fixed))
  expect_true(all(paste0("tmax_cb", 1:4) %in% cs$l_spec$fixed))
  expect_true(all(paste0("tmax_cb", 1:4) %in% names(cs$data)))
  w3 <- cs$l_contrasts$heat_t3$weights; w9 <- cs$l_contrasts$heat_gest$weights
  expect_equal(unname(w3), unname(colSums(b[1:3, ])))
  expect_equal(unname(w9), unname(colSums(b)))
  # the Wald contrast: sum over lags of (basis %*% beta) with CI from basis %*% V %*% t(basis), summed
  beta <- c(0.01, -0.02, 0.015, 0.005); V <- diag(c(1, 2, 1.5, 0.8)) * 1e-4; V[1, 2] <- V[2, 1] <- 3e-5
  est <- stats::setNames(c(beta, rep(0, 8)), c(paste0("tmax_cb", 1:4), L_DRY, L_LEADS, "x", "y"))
  VV <- diag(1e-4, 12); dimnames(VV) <- list(names(est), names(est)); VV[1:4, 1:4] <- V
  r <- .wald_contrast(est, VV, cs$l_contrasts$heat_t3$terms, 1, cs$l_contrasts$heat_t3$weights)
  lags <- b[1:3, ] %*% beta
  se <- sqrt(sum((b[1:3, ] %*% V %*% t(b[1:3, ]))))
  expect_equal(r$est, sum(lags)); expect_equal(r$se, se); expect_equal(r$rr, exp(sum(lags)))
  expect_equal(r$lo, exp(sum(lags) - stats::qnorm(0.975) * se))
  # the dry summary is unchanged
  expect_identical(cs$l_contrasts$dry_gest, SUMMARIES$dry_gest)
})

test_that("row-filter cases select their rows", {
  d <- sens_panel()
  u <- levels(d$unit_id)
  expect_setequal(as.character(unique(sens_case_f("inst090", d, NULL, "sb")$data$unit_id)), u[3:9])
  expect_setequal(as.character(unique(sens_case_f("single", d, NULL, "sb")$data$unit_id)), u[1:5])
  expect_false(u[1] %in% as.character(sens_case_f("nosmall", d, NULL, "sb")$data$unit_id))
  ia <- sens_case_f("inst_adj", d, NULL, "lbw")
  expect_true(all(c("inst_share", "wt_cov") %in% ia$l_spec$fixed)); expect_true(all(c("inst_share", "wt_cov") %in% ia$t_spec$fixed))
  ib <- sens_case_f("inst_adj", d, NULL, "sb")
  expect_true("inst_share" %in% ib$l_spec$fixed); expect_false("wt_cov" %in% ib$t_spec$fixed)
  ep <- sens_case_f("drop_ep1415", d, NULL, "sb")
  expect_false(any(ep$data$ym >= EP_WINDOWS_F$ep1415[1] & ep$data$ym <= EP_WINDOWS_F$ep1415[2]))
  expect_identical(nrow(ep$data), sum(!(d$ym >= EP_WINDOWS_F$ep1415[1] & d$ym <= EP_WINDOWS_F$ep1415[2])))
  expect_identical(EP_WINDOWS_F$ep1415, c(24177L, 24205L)); expect_identical(EP_WINDOWS_F$ep1819, c(24224L, 24241L))
  expect_true(all(sens_case_f("drop_ep1819", d, NULL, "sb")$data$ym < 24224L | sens_case_f("drop_ep1819", d, NULL, "sb")$data$ym > 24241L))
  ro <- sens_case_f("roni", d, NULL, "sb")
  expect_true(all(c("en_roni_gest", "ln_roni_gest") %in% ro$t_spec$fixed)); expect_false("en_gest" %in% ro$t_spec$fixed)
  xp <- sens_case_f("extra_prog", d, NULL, "sb")
  expect_true(all(c("laqshya", "pmsma") %in% xp$t_spec$fixed))
  # an outcome/denominator swap: outcome, offset, rows with denominator >= 20 and no gate exclusion
  d2 <- data.table::copy(d); d2[1:3, tb_scaled := 5]; d2[4, sb_scaled := NA_real_]
  cp <- sens_case_f("comp050", d2, NULL, "sb")
  expect_identical(cp$l_spec$outcome, "sb_scaled"); expect_identical(cp$l_spec$offset, "log_tb_scaled")
  expect_identical(cp$t_spec$offset, "log_tb_scaled")
  expect_false(any(cp$data$tb_scaled < 20))
  expect_equal(cp$data$log_tb_scaled, log(cp$data$tb_scaled))
  ml <- sens_case_f("masklow", d2, NULL, "lbw")
  expect_identical(ml$l_spec$outcome, "lbw_masklow"); expect_identical(ml$l_spec$offset, "log_wt_masklow")
  # betabin: both arms, the denominator column of the outcome
  bb <- sens_case_f("betabin", d, NULL, "lbw")
  expect_identical(bb$fitter, "betabin"); expect_identical(bb$denom_col, "wt")
  expect_identical(sens_case_f("betabin", d, NULL, "sb")$denom_col, "tb")
  expect_error(sens_case_f("nope", d, NULL, "sb"), "unknown sensitivity")
})

# ---- beta-binomial fitter -------------------------------------------------------------------------------------------

test_that("betabin_fitter rewrites the response and drops the offset", {
  seen <- NULL
  fake <- function(formula, data, family) { seen <<- list(formula = formula, family = family); "fitted" }
  ff <- betabin_fitter("tb", extra = "x2", fit_fun = fake)
  out <- ff(y ~ a + b + offset(log_tb) + (1 + t_c | unit_id), data.frame())
  expect_identical(out, "fitted")
  txt <- deparse1(seen$formula)
  expect_match(txt, "^cbind\\(y, tb - y\\) ~ ")
  expect_false(grepl("offset", txt, fixed = TRUE))
  expect_match(txt, "a \\+ b \\+ \\(1 \\+ t_c \\| unit_id\\) \\+ x2$")
  expect_identical(seen$family$family, "betabinomial")
  # no extra: nothing is appended; the response of any name is rewritten
  ff2 <- betabin_fitter("deliveries", fit_fun = fake)
  ff2(inst ~ a + offset(log_days) + (1 | unit_id), data.frame(), family = glmmTMB::nbinom2())
  expect_match(deparse1(seen$formula), "^cbind\\(inst, deliveries - inst\\) ~ a \\+ \\(1 \\| unit_id\\)$")
  expect_identical(seen$family$family, "betabinomial")                         # the NB2 family is replaced
})

test_that("a beta-binomial arm fits a bounded outcome through the same machinery", {
  skip_on_cran()
  d <- sens_panel(seed = 7, n_units = 12, n_states = 3, n_months = 24)
  cs <- sens_case_f("betabin", d, NULL, "sb")
  spec <- cs$l_spec; spec$slopes <- character(); spec$re <- "int"
  r <- fit_arm("L", spec, cs$data, "sb", fitter = "betabin", denom_col = "tb", contrasts = L_SUMMARY_CONTRASTS, B = 3L)
  expect_true(all(r$rows[term %in% c("heat_t3", "heat_gest", "dry_gest")]$status == "ok"))
  expect_true(all(is.finite(r$rows[term == "heat_t3", .(rr, lo, hi, p)] |> unlist())))
  expect_gt(r$n, 0L)
})

# ---- carriers and the era / state-month extras -----------------------------------------------------------------------

test_that("extra terms and carrier columns reach every fit, including bootstrap refits", {
  d <- sens_panel(seed = 8, n_units = 10, n_states = 3, n_months = 24)
  seen <- character()
  spy <- function(formula, data, family = glmmTMB::nbinom2()) { seen <<- c(seen, deparse1(formula)); stop("synthetic: stop here") }
  era <- sens_case_f("era_int", d, NULL, "sb")
  af <- .arm_fitter(era$t_spec, era$t_extra, "nb", NA_character_)
  expect_true("unit_era" %in% af$spec$fixed)                                   # the carrier rides in the spec
  pf <- .preflight_arm("T", era$t_spec, d, era$t_extra, "nb", NA_character_)       # the final formula of the first fit
  txt <- deparse1(pf, width.cutoff = 500L)
  expect_match(txt, "\\(1 \\| unit_era\\)"); expect_false(grepl("+ unit_era +", txt, fixed = TRUE))
  expect_match(txt, "ar1\\(ym_f \\+ 0 \\| national\\)"); expect_match(txt, "offset\\(log_tb\\)")
  mo <- sens_case_f("state_moy", d, NULL, "sb")
  am <- .arm_fitter(mo$l_spec, mo$l_extra, "nb", NA_character_)
  expect_true(all(c("state_unit", "moy") %in% am$spec$fixed))
  # the extra term appears in the formula and the carriers are removed from it
  rec <- NULL
  af2 <- extra_fitter("(1 | unit_era)", function(formula, data, family) { rec <<- deparse1(formula); stop("x") }, "unit_era")
  try(af2(sb ~ en_gest + unit_era + offset(log_tb) + (1 | unit_id), d), silent = TRUE)
  expect_match(rec, "\\(1 \\| unit_era\\)$"); expect_false(grepl("\\+ unit_era \\+", rec))
})

# ---- selection, preterm, sex ratio -------------------------------------------------------------------------------------

test_that("preterm uses April 2017 to February 2020 only", {
  d <- sens_panel(n_months = 30)
  d[, ym := ym + 24207L - min(ym) - 10L]                                      # window starts ten months before April 2017
  pd <- preterm_data(d)
  expect_identical(PRETERM_WINDOW_F, c(24207L, 24241L))
  expect_gte(min(pd$ym), 24207L); expect_lte(max(pd$ym), 24241L)
  expect_true(any(d$ym < 24207L))
  expect_identical(nrow(pd), sum(d$ym >= 24207L & d$ym <= 24241L))
  d[1, excluded_preterm := 1L]; d[2, small_denom_preterm := 1L]
  expect_identical(nrow(preterm_data(d)), sum(d$ym >= 24207L & d$ym <= 24241L & d$excluded_preterm == 0L & d$small_denom_preterm == 0L))
  # the model: Model L, preterm, offset log_lb, on exactly those rows
  seen <- NULL
  fake <- function(arm, spec, data, label, ...) {
    seen <<- list(arm = arm, spec = spec, data = data, label = label)
    list(rows = fake_rows(label, "L", SENS_TERMS_F$L, "x", "L"), structure = "state_ym", boot_B = NA_integer_, B_ok = NA_integer_,
         n = 1L, n_units = 1L, re_used = "us")
  }
  r <- preterm_model(d, fit_arm_fun = fake)
  expect_identical(seen$arm, "L"); expect_identical(seen$spec$outcome, "preterm"); expect_identical(seen$spec$offset, "log_lb")
  expect_identical(nrow(seen$data), nrow(preterm_data(d)))
  expect_setequal(r$term, SENS_TERMS_F$L); expect_identical(unique(r$case), "preterm")
  expect_identical(seen$spec$fixed, l_spec("preterm", offset = "log_lb")$fixed)
})

test_that("the sex-ratio model is Model L for male live births with the female live births as offset", {
  d <- sens_panel()
  d[1, excluded_lb_m := 1L]; d[2, lb_f := 10]; d[3, lb_f := NA_real_]
  sd <- sexratio_data(d)
  expect_false(any(sd$lb_f < 20 | is.na(sd$lb_f))); expect_identical(nrow(sd), nrow(d[excluded_lb_m == 0L & excluded_lb_f == 0L & lb_f >= 20 & !is.na(lb_f)]))
  seen <- NULL
  fake <- function(arm, spec, data, label, ...) { seen <<- list(spec = spec, label = label)
    list(rows = fake_rows(label, "L", SENS_TERMS_F$L, "x", "L")) }
  sexratio_model(d, fit_arm_fun = fake)
  expect_identical(seen$spec$outcome, "lb_m"); expect_identical(seen$spec$offset, "log_lb_f")
})

test_that("the selection audit fits Model L and Model T for tb, wt and inst_share", {
  d <- sens_panel()
  d[1, excluded_tb := 1L]; d[2, `:=`(inst = 0, home = 0)]
  tbc <- selection_case(d, "tb")
  expect_identical(tbc$l_spec$outcome, "tb"); expect_identical(tbc$l_spec$offset, "log_days"); expect_identical(tbc$t_spec$offset, "log_days")
  expect_false(any(tbc$data$excluded_tb == 1L))
  expect_identical(nrow(tbc$data), sum(d$excluded_tb == 0L))
  expect_identical(tbc$fitter, "nb")
  ic <- selection_case(d, "inst_share")
  expect_identical(ic$fitter, "betabin"); expect_identical(ic$denom_col, "deliveries"); expect_identical(ic$l_spec$outcome, "inst")
  expect_false(any(ic$data$deliveries < 1))                                   # inst + home = 0 leaves the audit
  expect_equal(ic$data$deliveries, ic$data$inst + ic$data$home)                # cbind(inst, deliveries - inst) = cbind(inst, home)
  calls <- list()
  fake <- function(arm, spec, data, label, ...) {
    calls[[length(calls) + 1L]] <<- list(arm = arm, label = label, spec = spec, extra = list(...))
    list(rows = fake_rows(label, arm, SENS_TERMS_F[[arm]], "x", arm))
  }
  r <- selection_models(d, fit_arm_fun = fake)
  expect_length(calls, 6L)
  expect_setequal(unique(r$outcome), c("tb", "wt", "inst_share"))
  expect_setequal(r[outcome == "wt"]$term, c(SENS_TERMS_F$L, "en"))
  expect_identical(unique(r$case), "selection")
  expect_identical(calls[[5]]$extra$fitter, "betabin")
})

test_that("trimester rows give the six strata", {
  tab <- fake_rows("sb", "L", c("heat_t3", "heat_gest", "dry_gest", paste0("heat_tri", 1:3), paste0("dry_tri", 1:3)), "x", "L")
  tab[, rr := seq(1.01, by = 0.01, length.out = .N)]
  tr <- trimester_rows(tab)
  expect_identical(names(tr), c("exposure", "stratum", "rr", "lo", "hi"))
  expect_identical(tr$exposure, rep(c("heat", "dry"), each = 3)); expect_identical(tr$stratum, rep(paste0("tri", 1:3), 2))
  r1 <- tab[term == "dry_tri1"]
  expect_equal(tr[exposure == "dry" & stratum == "tri1"]$rr, r1$rr)
  expect_equal(as.data.frame(trimester_rows(list(rows = tab))), as.data.frame(tr))
  expect_error(trimester_rows(tab[term != "heat_tri2"]), "six heat and dry strata")
})

# ---- workers ------------------------------------------------------------------------------------------------------------

test_that("the task list covers every fitted arm and no not-applicable arm", {
  d <- sens_panel(); d[, ym := ym + 80L]; d2 <- data.table::copy(d)
  d2[, sb_allcomp := sb_allcomp + 1]; d2[, lbw_allcomp := lbw_allcomp + 1]
  tasks <- sec_tasks(d2, d2)
  ids <- vapply(tasks, sec_task_id, "")
  expect_identical(anyDuplicated(ids), 0L)
  # 2 outcomes x (12 L arms + 14 T arms) + 6 selection + 2 secondary
  expect_length(tasks, 2L * (12L + 14L) + 6L + 2L)
  expect_false("sens_state_moy_sb_T" %in% ids); expect_true("sens_state_moy_sb_L" %in% ids)
  expect_false("sens_era_int_lbw_L" %in% ids); expect_true("sens_era_int_lbw_T" %in% ids)
  expect_true(all(c("sel_inst_share_L", "sel_inst_share_T", "sec_preterm_L", "sec_sexratio_L") %in% ids))
  # identical allcomp drops its four arms
  tasks0 <- sec_tasks(d, d)
  expect_length(tasks0, length(tasks) - 4L)
  expect_false(any(grepl("allcomp", vapply(tasks0, sec_task_id, ""))))
  expect_identical(tasks[[1]]$name, "betabin")                                 # longest first
})

test_that("a worker claims each task once, caches the rows and records errors", {
  d <- sens_panel()
  cache <- file.path(tempdir(), "sec_test"); unlink(cache, recursive = TRUE)
  tasks <- list(list(kind = "sec", name = "preterm", outcome = "", arm = "L"), list(kind = "sec", name = "sexratio", outcome = "", arm = "L"))
  real_run_task <- run_task
  assign("run_task", function(t, ...) {
    if (t$name == "sexratio") stop("synthetic programming error")
    fake_rows("preterm", "L", SENS_TERMS_F$L, "preterm", "L")
  }, envir = globalenv())
  on.exit(assign("run_task", real_run_task, envir = globalenv()), add = TRUE)
  run_worker(tasks, d, d, cache = cache, log_file = file.path(tempdir(), "sec_test.log"))
  expect_true(file.exists(file.path(cache, "sec_preterm_L.rds")))
  expect_true(file.exists(file.path(cache, "sec_sexratio_L.err")))
  expect_true("minutes" %in% names(readRDS(file.path(cache, "sec_preterm_L.rds"))))
  # a rerun does nothing (the result and the error are both final)
  n_before <- length(list.files(cache))
  run_worker(tasks, d, d, cache = cache, log_file = file.path(tempdir(), "sec_test.log"))
  expect_identical(length(list.files(cache)), n_before)
  expect_error(assemble_secondary(tasks, d, d, cache = cache), "synthetic programming error")
  # a stale lock without a result is cleared
  dir.create(file.path(cache, "sec_sexratio_L.lock"), showWarnings = FALSE)
  unlink(file.path(cache, "sec_sexratio_L.err"))
  expect_identical(clear_stale_locks(tasks, cache), 1L)
  expect_false(dir.exists(file.path(cache, "sec_sexratio_L.lock")))
})

test_that("FY2020-21 row counts are withheld from the published tables", {
  tab <- data.table::rbindlist(list(fake_rows("sb", "L", "heat_t3", "fy2021", "L"), fake_rows("sb", "L", "heat_t3", "betabin", "L")))
  red <- .redact_fy2021(tab)
  expect_true(is.na(red[case == "fy2021"]$n)); expect_true(is.na(red[case == "fy2021"]$n_units))
  expect_equal(red[case == "betabin"]$n, 100L)
  ent <- .entry_from_row(red[case == "fy2021"], "x")
  expect_match(ent$description, "withheld")
  expect_false(grepl("100 unit-months", ent$description))
})

# ---- fitter errors stop the run (I2), offset check (M3), weighted bootstrap contrast (M7) -------------------------------

test_that("a bad carrier or extra term stops the run instead of reading as not estimable", {
  d <- sens_panel(seed = 9, n_units = 10, n_states = 3, n_months = 24)
  ts <- t_spec_f("sb")
  expect_error(fit_arm("T", ts, d, "sb", extra = "(1 | no_such_col)", B = 2L), "no_such_col")
  ls <- l_spec("sb")
  expect_error(fit_arm("L", ls, d, "sb", extra = "state_unit:no_such_col", B = 2L), "no_such_col")
  # a betabin case whose denominator column is absent also stops
  expect_error(fit_arm("T", ts, d[, !"tb"], "sb", fitter = "betabin", denom_col = "tb", B = 2L), "tb")
  # the good case passes the pre-flight and returns the rewritten formula
  bf <- .preflight_arm("T", ts, d, character(), "betabin", "tb")
  expect_match(deparse1(bf, width.cutoff = 500L), "^cbind\\(sb, tb - sb\\) ~ ")
  expect_false(grepl("offset(", deparse1(bf, width.cutoff = 500L), fixed = TRUE))
})

test_that("betabin_fitter stops if an offset term remains", {
  fake <- function(formula, data, family) "fitted"
  ff <- betabin_fitter("tb", fit_fun = fake)
  expect_error(ff(y ~ a + offset(log(x)) + (1 | unit_id), data.frame()), "offset not removed")
  expect_error(ff(y ~ offset(log_tb) + a, data.frame()), "offset not removed")
})

test_that("the weighted bootstrap contrast uses the lag weights", {
  set.seed(4)
  terms <- paste0("tmax_cb", 1:4)
  betas <- matrix(rnorm(40 * 4, c(0.01, -0.02, 0.015, 0.005), 0.01), ncol = 4, byrow = TRUE, dimnames = list(NULL, terms))
  est <- stats::setNames(c(0.01, -0.02, 0.015, 0.005), terms)
  ok <- rep(TRUE, 40); ok[7] <- FALSE
  w <- c(0.5, 1, -0.3, 2); names(w) <- terms
  r <- .boot_contrast(est, betas, ok, terms, 1, w)
  xb <- as.vector(betas[ok, ] %*% w)
  expect_equal(r$est, sum(w * est)); expect_equal(r$se, stats::sd(xb))
  expect_equal(c(r$lo, r$hi), exp(unname(stats::quantile(xb, c(0.025, 0.975)))))
  expect_equal(r$p, 2 * stats::pnorm(-abs(sum(w * est) / stats::sd(xb))))
  u <- .boot_contrast(est, betas, ok, terms, -1)
  expect_equal(u$est, -sum(est)); expect_equal(u$se, stats::sd(rowSums(betas[ok, ])))
})
