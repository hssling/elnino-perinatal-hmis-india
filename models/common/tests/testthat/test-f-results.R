# Paper F Task 12: results assembly, run_all, reading rules and the conclusion sentence (models/F/R/results_f.R,
# models/F/04_results.R, models/F/run_all.R). Contract papers/F/results_keys.md (297 keys; controller rulings I1/I2:
# national keys from the official All_India series, rr_ci to 3 decimals, power keys at the R6 stop). No test fits a
# model or reads an HMIS outcome: every input is synthetic and written to a temporary directory.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  for (f in c("common_f.R", "perinatal.R", "power_f.R", "verdicts_f.R", "primary_f.R", "secondary_f.R", "results_f.R"))
    source(file.path(root, "F", "R", f), local = globalenv())
  source(file.path(root, "D", "R", "contract.R"), local = globalenv())
})

YES <- "consistent with"
NO <- "not consistent with"
WANT <- contract_keys(F_CONTRACT, prefix = "F")
DASH <- "–"

.fake <- function(k, value = 1, display = "1.000") res_entry(value, display, "test", paste("fake", k))

# Entries for every key a step owns; verdict keys take the fixed vocabulary.
fake_step_entries <- function(step, h = c(h10a = NO, h10b = NO, h10c = NO, h11a = NO, h11b = NO, h11c = NO)) {
  keys <- WANT[f_key_step(WANT) == step]
  E <- stats::setNames(lapply(keys, .fake), keys)
  if (step == "primary") {
    for (t in names(h)) E[[sprintf("F.%s.verdict", t)]] <- res_entry(h[[t]], h[[t]], "test", "fake")
    for (hh in c("h10", "h11")) {
      v <- overall_verdict_f(h, toupper(hh))
      E[[sprintf("F.%s.verdict", hh)]] <- res_entry(v$verdict, v$verdict, "test", "fake")
      E[[sprintf("F.%s.verdict_text", hh)]] <- res_entry(v$text, v$text, "test", "fake")
    }
  }
  E
}

fake_steps <- function(...) {
  nm <- c("power", "primary", "secondary", "reading")
  stats::setNames(lapply(nm, function(n) list(name = n, status = "cached", entries = fake_step_entries(n, ...))), nm)
}

# ---- display --------------------------------------------------------------------------------------------------------

test_that("rr_ci is shown to 3 decimals (contract amendment 2026-11-09) and Paper E's formatter is untouched", {
  expect_identical(fmt_rr_ci(1.0113829261509, 1.00396528350385, 1.01885537290657), paste0("1.011 (95% CI 1.004", DASH, "1.019)"))
  expect_identical(fmt_ci(1.0113829261509, 1.00396528350385, 1.01885537290657, 2), paste0("1.01 (95% CI 1.00", DASH, "1.02)"))
  expect_identical(RR_DIGITS_F, 3L)
  # the producers use the wrapper
  ent <- .entry_from_row(data.table::data.table(model = "L", term = "heat_t3", rr = 1.0113829, lo = 1.003965, hi = 1.018855, p = 0.01,
    est = 0.011, se = 0.004, p_kind = "wald", step = "state_ym", boot_B = NA_integer_, B_ok = NA_integer_, re_used = "us", n = 10L,
    n_units = 3L, status = "ok", error = NA_character_), "x")
  expect_identical(ent$display, paste0("1.011 (95% CI 1.004", DASH, "1.019)"))
})

test_that("power step codes map to the contract's displays", {
  expect_identical(power_step_display("200"), "200")
  expect_identical(power_step_display("100"), "100")
  expect_identical(power_step_display("100_reduced_grid"), "100 with reduced grid")
  expect_identical(power_step_display("stop"), "stop")
  expect_error(power_step_display("50"), "unknown power step")
})

# ---- the contract ---------------------------------------------------------------------------------------------------

test_that("the contract declares 297 keys and its sections add up", {
  cnt <- assert_contract_counts_f(F_CONTRACT)
  expect_identical(attr(cnt, "declared_total"), 297L)
  expect_identical(sum(cnt$found), 297L)
  expect_identical(length(WANT), 297L)
  expect_identical(nrow(cnt), 12L)
  # every key has exactly one owner
  expect_identical(sort(unique(f_key_step(WANT))), c("conclusion", "panel", "power", "primary", "reading", "secondary"))
  expect_identical(sum(f_key_step(WANT) == "panel"), 82L)
  expect_identical(sum(f_key_step(WANT) == "power"), 20L)
  expect_identical(sum(f_key_step(WANT) == "primary"), 72L)
  expect_identical(sum(f_key_step(WANT) == "secondary"), 118L)
  expect_identical(sum(f_key_step(WANT) == "reading"), 4L)
  expect_error(f_key_step("F.nosuch.key"), "no owner")
})

test_that("results key set equals the contract", {
  e <- assemble_f_results(fake_steps(), panel = fake_step_entries("panel"), contract = F_CONTRACT)
  expect_setequal(names(e), WANT)
  expect_identical(length(e), 297L)
  expect_identical(names(e), WANT[order(WANT, method = "radix")])
  expect_true(startsWith(e[["F.abstract.conclusion_sentence"]]$display, "In this link-unit-month analysis"))
  # a missing key and an extra key both stop the run
  s <- fake_steps(); s$secondary$entries[["F.sens.sb.fy2021.heat"]] <- NULL
  expect_error(assemble_f_results(s, panel = fake_step_entries("panel"), contract = F_CONTRACT), "key set differs.*F.sens.sb.fy2021.heat")
  s <- fake_steps(); s$secondary$entries[["F.sens.sb.nosuch.heat"]] <- .fake("x")
  expect_error(assemble_f_results(s, panel = fake_step_entries("panel"), contract = F_CONTRACT), "key set differs.*Extra: F.sens.sb.nosuch.heat")
  # a key produced by two steps stops
  s <- fake_steps(); s$reading$entries[["F.l.sb.heat_t3.rr"]] <- .fake("x")
  expect_error(assemble_f_results(s, panel = fake_step_entries("panel"), contract = F_CONTRACT), "duplicate key")
})

test_that("keyset complete when an outcome is dropped", {
  DROP <- "not estimable (dropped: more than 20% of link-unit-months masked)"
  tab <- data.table::rbindlist(list(
    .rows_na("sb", "L", names(L_CONTRASTS), "ok", NA_character_)[, `:=`(rr = 1.02, lo = 1.0, hi = 1.04, p = 0.03, est = log(1.02), se = 0.01,
      lead_rr = 1, lead_lo = 0.97, lead_hi = 1.03, p_kind = "wald", step = "state_ym", re_used = "us", n = 100L, n_units = 10L)],
    .rows_na("sb", "T", c("en", "ln"), "ok", NA_character_)[, `:=`(rr = 1.03, lo = 1.01, hi = 1.05, p = 0.002, est = 0.03, se = 0.01, p_kind = "wald",
      step = "ar1", re_used = "us", n = 90L, n_units = 9L)],
    .rows_na("sb", "T_ep", c("ep1415", "ep1819", "en_other", "ln"), "ok", NA_character_)[, `:=`(rr = 1.03, lo = 1.01, hi = 1.05, p = 0.002,
      est = 0.03, se = 0.01, p_kind = "wald", step = "ar1", re_used = "us", n = 90L, n_units = 9L)],
    dropped_rows("lbw")), fill = TRUE)
  tests <- build_tests(tab)
  v <- stats::setNames(tests$verdict, tests$test_id)
  prim <- primary_entries(tab, tests, list(h10 = overall_verdict_f(v, "H10"), h11 = overall_verdict_f(v, "H11")))
  lbw_keys <- grep("^F\\.(l|t)\\.lbw\\.", names(prim), value = TRUE)
  expect_gt(length(lbw_keys), 10L)
  # every Model L / Model T lbw key reads "not estimable (dropped: ...)" with a null value
  for (k in lbw_keys) { expect_identical(prim[[k]]$display, DROP, info = k); expect_true(is.na(prim[[k]]$value), info = k) }
  s <- fake_steps()
  s$primary$entries <- prim
  # the secondary producer's own entries for a dropped lbw (every lbw sensitivity row an error row carrying the dropped reason)
  mk_ok <- function(o, arm, terms, id) data.table::rbindlist(lapply(terms, function(tm) .tag_rows(.mk_row(o, arm, tm,
    list(est = log(1.02), se = 0.01, rr = 1.02, lo = 1.0, hi = 1.04, p = 0.05), p_kind = "wald", step = if (arm == "T") "ar1" else "state_ym", re_used = "us",
    n = 100L, n_units = 10L), case = id, arm = arm, note = "x")))
  fk <- function(label, model, terms, case) mk_ok(label, model, terms, case)
  sens <- data.table::rbindlist(lapply(OUTS, function(o) data.table::rbindlist(lapply(SENS_IDS_F, function(id) {
    mk <- function(arm) {
      terms <- SENS_TERMS_F[[arm]]; reason <- sens_na_reason(id, arm)
      if (o == "lbw") .sens_na_rows(o, id, arm, terms, DROPPED_REASON, "error")
      else if (!is.null(reason)) .sens_na_rows(o, id, arm, terms, reason) else mk_ok(o, arm, terms, id)
    }
    data.table::rbindlist(list(mk("L"), mk("T")), use.names = TRUE, fill = TRUE)
  }), use.names = TRUE, fill = TRUE)), use.names = TRUE, fill = TRUE)
  sel <- data.table::rbindlist(lapply(SEL_DENOMS, function(den) rbind(fk(den, "L", SENS_TERMS_F$L, "selection"), fk(den, "T", "en", "selection"))))
  sec <- rbind(fk("preterm", "L", SENS_TERMS_F$L, "preterm"), fk("lb_m", "L", SENS_TERMS_F$L, "sexratio"))
  s$secondary$entries <- secondary_entries(sel, sec, sens)
  lbw_sens <- grep("^F[.]sens[.]lbw[.]", names(s$secondary$entries), value = TRUE)
  expect_identical(length(lbw_sens), 51L)
  for (k in lbw_sens) expect_identical(s$secondary$entries[[k]]$display, DROP, info = k)
  e <- assemble_f_results(s, panel = fake_step_entries("panel"), contract = F_CONTRACT, dropped = "lbw")
  expect_setequal(names(e), WANT)
  expect_identical(e[["F.l.lbw.heat_t3.rr"]]$display, DROP)
  expect_identical(e[["F.h11.verdict"]]$display, NO)
  # a dropped outcome that still carries an estimate in a model key stops the run
  s2 <- s; s2$secondary$entries[["F.sens.lbw.betabin.heat"]] <- .fake("x", 1.1, "1.100")
  expect_error(assemble_f_results(s2, panel = fake_step_entries("panel"), contract = F_CONTRACT, dropped = "lbw"),
               "dropped outcome lbw has a value in F.sens.lbw.betabin.heat")
  # the reading rules of a dropped outcome read "not applicable" (no heat test is consistent)
  tst <- data.table::copy(tests)
  rd <- reading_rules_f(list(table = tab, tests = tst), selection = data.table::data.table(), sens = data.table::data.table())
  expect_identical(rd[["F.read.lbw.selection"]]$display, "not applicable (heat test not consistent with)")
  expect_identical(rd[["F.read.lbw.national"]]$display, "not applicable (El Niño test not consistent with)")
})

# ---- national keys (ruling I1: the primary window only, from the official All_India series) -------------------------

write_fake_national <- function(path) {
  mk <- function(fy, month, ...) {
    v <- list(...)
    data.table::rbindlist(lapply(names(v), function(i) data.table::data.table(fy = fy, month = month, indicator = i,
      all_india = v[[i]], mo_value = NA_real_, national = v[[i]])))
  }
  rows <- list()
  inds <- c("lb", "sb", "wt", "lbw", "home", "inst", "d24")
  for (fy in c("2012-13", "2013-14", "2014-15", "2015-16", "2016-17", "2017-18", "2018-19", "2019-20", "2020-21"))
    for (m in c(4:12, 1:3)) {
      big <- (fy == "2019-20" && m == 3) || fy == "2020-21"          # March 2020 and FY2020-21: junk, must not enter
      rows[[length(rows) + 1L]] <- mk(fy, m, lb = if (big) 1e6 else 1000, sb = if (big) 5e5 else 10, wt = if (big) 1e6 else 900,
        lbw = if (big) 5e5 else 90, home = if (big) 1e6 else 100, inst = if (big) 1e6 else 800,
        d24 = if (fy %in% c("2017-18", "2018-19", "2019-20", "2020-21") && !(fy == "2019-20" && m == 3)) 2 else NA_real_)
    }
  nat <- data.table::rbindlist(rows)
  nat[fy == "2019-20" & month == 5 & indicator == "inst", national := NA_real_]      # one month without inst
  data.table::fwrite(nat, path)
  invisible(nat)
}

write_fake_break <- function(path)
  data.table::fwrite(data.table::data.table(indicator = c("sbr", "lbw_share", "wt_cov"), mar2017 = c(13, 0.114, 0.946),
    apr2017 = c(13.06, 0.1157, 0.952), ratio = c(1.00494, 1.01441, 1.00611), gt15pct_rate = FALSE, n_units = c(655L, 655L, 656L)), path)

test_that("national keys use the primary window only", {
  dir <- withr::local_tempdir()
  write_fake_national(file.path(dir, "national_month.csv"))
  write_fake_break(file.path(dir, "break.csv"))
  E <- national_keys_f(file.path(dir, "national_month.csv"), file.path(dir, "break.csv"), script = "t")
  expect_setequal(names(E), grep("^F\\.(national|d24\\.national|break2017)\\.", WANT, value = TRUE))
  # fy1920: April 2019 to February 2020 (11 months); March 2020 and FY2020-21 never enter
  expect_equal(E[["F.national.sbr.fy1920"]]$value, 10 / 1010 * 1000)
  expect_identical(E[["F.national.sbr.fy1920"]]$display, "9.9")
  expect_match(E[["F.national.sbr.fy1920"]]$description, "April 2019 to February 2020", fixed = TRUE)
  expect_match(E[["F.national.sbr.fy1920"]]$description, "11 of 11", fixed = TRUE)
  expect_match(E[["F.national.sbr.fy1920"]]$description, "FY2020-21 was analysed as a sensitivity analysis", fixed = TRUE)
  expect_equal(E[["F.national.lbw_share.fy1920"]]$value, 0.1)
  expect_identical(E[["F.national.lbw_share.fy1920"]]$display, "10.0%")
  expect_identical(E[["F.national.wt_cov.fy1920"]]$display, "90%")
  expect_identical(E[["F.national.tb_per_delivery.fy1920"]]$display, "1.12")
  # the ratio of sums runs over the months in which every count is present: May 2019 has no inst
  expect_equal(E[["F.national.inst_share.fy1920"]]$value, 800 / 900)
  expect_match(E[["F.national.inst_share.fy1920"]]$description, "10 of 11", fixed = TRUE)
  # d24: months with a reported d24 only, per 1,000 live births of the same months
  expect_equal(E[["F.d24.national.fy1920"]]$value, 2 / 1000 * 1000)
  expect_identical(E[["F.d24.national.fy1920"]]$display, "2.00")
  expect_identical(E[["F.d24.national.fy1213"]]$display, "not available (no national month with a reported d24)")
  expect_true(is.na(E[["F.d24.national.fy1213"]]$value))
  # break ratios
  expect_identical(E[["F.break2017.sbr.ratio"]]$display, "1.005")
  expect_identical(E[["F.break2017.wt_cov.ratio"]]$display, "1.006")
  # no key carries a FY2020-21 value
  expect_false(any(grepl("2020-21 (rate|count)|fy2021", names(E))))
})

test_that("national keys stop on a missing indicator and read a blank M/O as already netted", {
  dir <- withr::local_tempdir()
  write_fake_national(file.path(dir, "national_month.csv"))
  write_fake_break(file.path(dir, "break.csv"))
  nat <- data.table::fread(file.path(dir, "national_month.csv"))
  data.table::fwrite(nat[indicator != "wt"], file.path(dir, "n2.csv"))
  expect_error(national_keys_f(file.path(dir, "n2.csv"), file.path(dir, "break.csv"), script = "t"), "no national rows for indicator.*wt")
})

# ---- panel keys -----------------------------------------------------------------------------------------------------

write_fake_panel_inputs <- function(dir) {
  yms <- (2012L * 12L + 3L):(2021L * 12L + 2L)                          # April 2012 .. March 2021
  d <- data.table::CJ(link_id = c("L1", "L2", "L3", "L4"), ym = yms)
  d[, state_unit := ifelse(link_id %in% c("L1", "L2"), "S1", "S2")]
  d[, in_primary := as.integer(ym <= 2020L * 12L + 1L)]
  set.seed(4)
  d[, `:=`(sb = rpois(.N, 20), lbw = rpois(.N, 50), excluded_sb = 0L, excluded_lbw = as.integer(link_id == "L4"),
           small_denom_sb = 0L, small_denom_lbw = 0L, single_district = as.integer(link_id != "L2"))]
  d[ym %in% yms[1:3] & link_id == "L1", sb := NA_integer_]
  d[, `:=`(status_date_min = "2015-09-19", status_date_max = "2020-11-06")]
  d[link_id == "L2", status_date_min := "2016-01-02"]
  d[, `:=`(tmax_t3 = rnorm(.N), tmax_t2 = rnorm(.N), tmax_t1 = rnorm(.N), spi3_dry_l0 = -abs(rnorm(.N)), spi3_dry_l3 = -abs(rnorm(.N)),
           spi3_dry_l6 = -abs(rnorm(.N)))]
  d[, `:=`(en_gest = pmax(sin(ym / 7), 0), ln_gest = pmin(sin(ym / 7), 0))]
  d[ym %in% yms[1:2], `:=`(tmax_t1 = NA_real_, en_gest = NA_real_)]
  data.table::fwrite(d, file.path(dir, "model.csv"))
  data.table::fwrite(data.table::data.table(variable = c("sb", "lbw"), scope = "primary", masked_share_window = c(0.0041, 0.0248),
                                            excluded_units = c(0L, 1L), dropped = c(FALSE, FALSE)), file.path(dir, "gate.csv"))
  data.table::fwrite(data.table::data.table(kind = c("gadm", "gadm", "gadm", "gadm", "gadm", "hmis"),
    state_unit = c("S1", "S1", "S2", "S2", "S2", "S1"), fy = NA_character_, district_raw = NA_character_,
    region_id = c("r1", "r2", "r3", "r4", "r5", "r1"), link_id = c("L1", "L2", "L3", "L4", "L4", NA), match_type = NA_character_,
    source = NA_character_), file.path(dir, "links.csv"))
  writeLines(c("# report", "", "- FY2012-13..2019-20 state x normalised-name combinations: manual/carve_out/unmatched 5 of 90 = 0.0556 (limit 0.10); fuzzy matches do not count."),
             file.path(dir, "units.md"))
  data.table::fwrite(data.table::data.table(state_unit = "S1", district_raw = c("a", "b", "c"),
    fys = c("2012-13|2013-14|2019-20", "2020-21", "2012-13|2020-21")), file.path(dir, "fuzzy.csv"))
  invisible(d)
}

test_that("panel keys: counts, shares, dates and exposure SDs from the primary window", {
  dir <- withr::local_tempdir()
  write_fake_panel_inputs(dir)
  p <- function(f) file.path(dir, f)
  write_fake_national(p("national_month.csv")); write_fake_break(p("break.csv"))
  E <- panel_keys_f(model_csv = p("model.csv"), gate_csv = p("gate.csv"), link_csv = p("links.csv"), units_report = p("units.md"),
                    fuzzy_csv = p("fuzzy.csv"), national_csv = p("national_month.csv"), break_csv = p("break.csv"), min_link_units = 3L,
                    script = "t")
  expect_setequal(names(E), WANT[f_key_step(WANT) == "panel"])
  expect_identical(E[["F.panel.n_link_units"]]$display, "4")
  expect_identical(E[["F.panel.n_months"]]$display, "95")
  expect_identical(E[["F.panel.n_unit_months"]]$display, "380")                    # 4 units x 95 primary months
  expect_identical(E[["F.panel.n_states"]]$display, "2")
  # sb: three NA months of L1 leave the model; lbw: L4 is excluded (all its 95 rows)
  expect_identical(E[["F.panel.sb.n_valid"]]$display, "377")
  expect_identical(E[["F.panel.lbw.n_valid"]]$display, "285")
  expect_identical(E[["F.panel.lbw.n_units_excluded"]]$display, "1")
  expect_identical(E[["F.panel.sb.share_masked"]]$display, "0.41%")
  expect_identical(E[["F.units.n_link"]]$display, "4")
  expect_identical(E[["F.units.n_gadm"]]$display, "5")
  expect_identical(E[["F.units.n_single"]]$display, "3")
  expect_identical(E[["F.units.n_fuzzy"]]$display, "2")                              # rows whose fys include a primary FY
  expect_identical(E[["F.units.n_manual"]]$display, "5")
  expect_identical(E[["F.units.n_hmis_names"]]$display, "90")
  expect_identical(E[["F.units.manual_share"]]$display, "5.6%")
  expect_identical(E[["F.status_date.min"]]$display, "19 September 2015")
  expect_identical(E[["F.status_date.max"]]$display, "6 November 2020")
  # exposure: tmax_t3 SD over all primary unit-months; tmax_gest NaN when a stratum is NaN (the two first months)
  d <- data.table::fread(p("model.csv"))[in_primary == 1L]
  expect_equal(E[["F.exposure.tmax_t3.sd"]]$value, stats::sd(d$tmax_t3))
  g <- rowMeans(d[, .(tmax_t3, tmax_t2, tmax_t1)])
  expect_equal(E[["F.exposure.tmax_gest.sd"]]$value, stats::sd(g, na.rm = TRUE))
  expect_equal(E[["F.exposure.tmax_t3.sd_within"]]$value, stats::sd(d$tmax_t3 - stats::ave(d$tmax_t3, d$ym)))
  expect_identical(E[["F.exposure.en_gest.sd_within"]]$value, 0)
  expect_identical(E[["F.exposure.en_gest.sd_within"]]$display, "0.000")
  expect_identical(E[["F.exposure.n_months"]]$display, "93")                          # two months without en_gest
  expect_equal(E[["F.exposure.n_en_months"]]$value, length(unique(d[en_gest > 0]$ym)))
  # the R3 guard and the link-unit floor stop the build
  expect_error(panel_keys_f(model_csv = p("model.csv"), gate_csv = p("gate.csv"), link_csv = p("links.csv"), units_report = p("units.md"),
                            fuzzy_csv = p("fuzzy.csv"), national_csv = p("national_month.csv"), break_csv = p("break.csv"),
                            min_link_units = 600L, script = "t"), "fewer than 600 link units")
})

# ---- power and timing keys ------------------------------------------------------------------------------------------

STOP_DISPLAY <- "not estimated (power simulation stopped: projected run over 24 hours after both R6 reductions)"

write_fake_power <- function(dir, step = "stop") {
  ids <- TESTS$test_id
  if (step == "stop") {
    tab <- data.table::rbindlist(lapply(ids, function(i) data.table::data.table(test_id = i, rr = c(1.03, 1.05, 1.1), n_ok = NA_integer_,
      power = NA_real_, mean_rr = NA_real_, n_sim = 100L, step = "stop", projected_h = 44.1547619047619, cores = 7L)))
  } else {
    tab <- data.table::rbindlist(lapply(ids, function(i) {
      g <- if (TESTS[test_id == i]$model == "L") c(1.01, 1.02, 1.03, 1.05) else c(1.02, 1.05, 1.1, 1.2)
      data.table::data.table(test_id = i, rr = g, n_ok = 198L, power = c(0.1, 0.5, 0.85, 0.95), mean_rr = g, n_sim = 200L,
                             step = "200", projected_h = 20.5, cores = 7L)
    }))
  }
  data.table::fwrite(tab, file.path(dir, "power.csv"))
  data.table::fwrite(data.table::data.table(fit = c("model_l_primary", "model_t_primary", "sim_l", "sim_t"),
    outcome = "sb", minutes = c(17.3666666666667, 5.96, 12.75, 5.40833333333333), re_used = "us", time_re = NA_character_,
    state_ym = c(TRUE, FALSE, FALSE, FALSE), converged = TRUE, n_rows = 1L, n_units = 1L), file.path(dir, "timing.csv"))
}

test_that("power keys at the R6 stop display the contract's stop text", {
  dir <- withr::local_tempdir()
  write_fake_power(dir, "stop")
  E <- power_keys_f(file.path(dir, "power.csv"), file.path(dir, "timing.csv"), script = "t")
  expect_setequal(names(E), WANT[f_key_step(WANT) == "power"])
  for (t in TESTS$test_id) for (w in c("mde", "power_at_grid_max")) {
    k <- sprintf("F.power.%s.%s", t, w)
    expect_identical(E[[k]]$display, STOP_DISPLAY, info = k)
    expect_true(is.na(E[[k]]$value), info = k)
  }
  expect_identical(E[["F.power.step"]]$display, "stop")
  expect_identical(E[["F.power.n_sim"]]$display, "100")
  expect_identical(E[["F.power.grid"]]$display, "1.03, 1.05, 1.10 (every test)")
  expect_identical(E[["F.power.hours"]]$display, "44.2")
  expect_equal(E[["F.power.hours"]]$value, 44.1547619047619)
  expect_match(E[["F.power.hours"]]$description, "7 workers", fixed = TRUE)
  expect_identical(E[["F.timing.l_primary.minutes"]]$display, "17.4")
  expect_identical(E[["F.timing.t_primary.minutes"]]$display, "6.0")
  expect_identical(E[["F.timing.l_sim.minutes"]]$display, "12.8")
  expect_identical(E[["F.timing.t_sim.minutes"]]$display, "5.4")
})

test_that("power keys of a completed run give the MDE and the power at the largest RR", {
  dir <- withr::local_tempdir()
  write_fake_power(dir, "200")
  E <- power_keys_f(file.path(dir, "power.csv"), file.path(dir, "timing.csv"), script = "t")
  expect_identical(E[["F.power.step"]]$display, "200")
  expect_identical(E[["F.power.grid"]]$display, "Model L 1.01, 1.02, 1.03, 1.05; Model T 1.02, 1.05, 1.10, 1.20")
  expect_identical(E[["F.power.h10a.mde"]]$display, "1.03 (optimistic: simulated on a simplified model)")
  expect_identical(E[["F.power.h10c.mde"]]$display, "1.10 (optimistic: simulated on a simplified model)")
  expect_identical(E[["F.power.h10a.power_at_grid_max"]]$display, "95%")
  expect_match(E[["F.power.h10a.power_at_grid_max"]]$description, "n_ok = 198", fixed = TRUE)
})

# ---- reading rules --------------------------------------------------------------------------------------------------

rd_tab <- function(heat_rr = 1.02, heat_lo = 1.004, dry_lo = 0.99, o = "sb", hs = "heat_t3") {
  rows <- list()
  for (oo in OUTS) {
    for (s in c("heat_t3", "heat_gest", "dry_gest")) {
      lo <- if (oo == o && s == hs) heat_lo else if (s == "dry_gest" && oo == o) dry_lo else 0.99
      rows[[length(rows) + 1L]] <- .mk_row(oo, "L", s, list(est = log(1.02), se = 0.01, rr = if (oo == o && s == hs) heat_rr else 1.01, lo = lo,
        hi = 1.05, p = 0.01), list(rr = 1, lo = 0.97, hi = 1.03, p = 0.9), p_kind = "wald", step = "state_ym", re_used = "us",
        n = 10L, n_units = 2L)
    }
  }
  data.table::rbindlist(rows)
}
rd_tests <- function(h) data.table::data.table(test_id = names(h), verdict = unname(h))
rd_sel <- function(wt_hi = 0.99, inst_hi = 1.02, den_terms = c("heat_t3", "heat_gest"), bad = NULL) {
  r <- data.table::rbindlist(lapply(c("wt", "inst_share"), function(den) data.table::rbindlist(lapply(den_terms, function(s) {
    hi <- if (den == "wt") wt_hi else inst_hi
    .mk_row(den, "L", s, list(est = log(hi), se = 0.005, rr = hi * 0.99, lo = hi * 0.97, hi = hi, p = 0.04), p_kind = "wald",
            step = "state_ym", re_used = "us", n = 10L, n_units = 2L)
  }))))
  if (!is.null(bad)) r[outcome == bad[[1]] & term == bad[[2]], `:=`(status = "error", error = "no unit random-effect structure converged",
                                                                      rr = NA_real_, lo = NA_real_, hi = NA_real_)]
  r
}
rd_sens <- function(adj = 1.005, o = "sb", term = "heat_t3", status = "ok") {
  r <- .mk_row(o, "L", term, list(est = log(adj), se = 0.005, rr = adj, lo = adj * 0.99, hi = adj * 1.01, p = 0.4), p_kind = "wald",
               step = "state_ym", re_used = "us", n = 10L, n_units = 2L, status = status, error = if (status == "ok") NA_character_ else "x failed")
  r[, `:=`(case = "inst_adj", arm = "L")]
  if (status != "ok") r[, `:=`(rr = NA_real_, lo = NA_real_, hi = NA_real_)]
  r
}
HV <- function(...) { h <- c(h10a = NO, h10b = NO, h10c = NO, h11a = NO, h11b = NO, h11c = NO); a <- list(...); h[names(a)] <- unlist(a); h }

test_that("selection reading rule (spec 5.5; contract Reading rules)", {
  rd <- function(tests, tab = rd_tab(), sel = rd_sel(), sens = rd_sens()) reading_rules_f(list(table = tab, tests = rd_tests(tests)), sel, sens)
  # heat test not consistent: not applicable (also when the negative control failed)
  expect_identical(rd(HV())[["F.read.sb.selection"]]$display, "not applicable (heat test not consistent with)")
  expect_identical(rd(HV(h10a = "not consistent with (negative control failed)"))[["F.read.sb.selection"]]$display,
                   "not applicable (heat test not consistent with)")
  # consistent, audit CI wholly below 1 (wt hi 0.99) and ln(adj)/ln(primary) = ln 1.005 / ln 1.02 = 0.25 < 0.5: may explain
  expect_identical(rd(HV(h10a = YES))[["F.read.sb.selection"]]$display, "selection may explain part of the association")
  # adjusted estimate stays (1.019 / 1.02): not indicated
  expect_identical(rd(HV(h10a = YES), sens = rd_sens(1.019))[["F.read.sb.selection"]]$display, "selection not indicated")
  # no audit CI wholly below 1: not indicated
  expect_identical(rd(HV(h10a = YES), sel = rd_sel(wt_hi = 1.02, inst_hi = 1.02))[["F.read.sb.selection"]]$display, "selection not indicated")
  # inst_share alone below 1 is enough
  expect_identical(rd(HV(h10a = YES), sel = rd_sel(wt_hi = 1.02, inst_hi = 0.98))[["F.read.sb.selection"]]$display,
                   "selection may explain part of the association")
  # a sign change satisfies the ratio rule
  expect_identical(rd(HV(h10a = YES), sens = rd_sens(0.99))[["F.read.sb.selection"]]$display, "selection may explain part of the association")
  # lbw uses heat_gest and the lbw rows of inst_adj
  tab <- rd_tab(o = "lbw", hs = "heat_gest")
  r <- reading_rules_f(list(table = tab, tests = rd_tests(HV(h11a = YES))), rd_sel(), rd_sens(1.004, "lbw", "heat_gest"))
  expect_identical(r[["F.read.lbw.selection"]]$display, "selection may explain part of the association")
  expect_identical(r[["F.read.sb.selection"]]$display, "not applicable (heat test not consistent with)")
  # not estimable inputs: the first failing input is named, in the fixed order (wt, inst_share, inst_adj, primary)
  bad <- rd(HV(h10a = YES), sel = rd_sel(bad = c("wt", "heat_t3")))[["F.read.sb.selection"]]
  expect_identical(bad$display, "not estimable (F.sel.wt.heat_t3.rr: no unit random-effect structure converged)")
  expect_true(is.na(bad$value))
  bad <- rd(HV(h10a = YES), sens = rd_sens(status = "error"))[["F.read.sb.selection"]]
  expect_identical(bad$display, "not estimable (F.sens.sb.inst_adj.heat: x failed)")
})

test_that("national-events reading rule (spec 5.5; contract Reading rules)", {
  rd <- function(tests, tab = rd_tab()) reading_rules_f(list(table = tab, tests = rd_tests(tests)), rd_sel(), rd_sens())
  expect_identical(rd(HV())[["F.read.sb.national"]]$display, "not applicable (El Niño test not consistent with)")
  # en consistent, neither local CI wholly above 1 (heat lo 0.99, dry lo 0.99): coincident national events
  null_tab <- rd_tab(heat_lo = 0.99, dry_lo = 0.99)
  expect_identical(rd(HV(h10c = YES), null_tab)[["F.read.sb.national"]]$display, "total may reflect coincident national events")
  # the heat summary above 1 (lo 1.004): local associations also present
  expect_identical(rd(HV(h10c = YES))[["F.read.sb.national"]]$display, "local-climate associations also present")
  # dry_gest above 1 alone: also present
  expect_identical(rd(HV(h10c = YES), rd_tab(heat_lo = 0.99, dry_lo = 1.002))[["F.read.sb.national"]]$display, "local-climate associations also present")
  # lbw uses heat_gest and the h11c test
  r <- reading_rules_f(list(table = rd_tab(heat_lo = 0.99, dry_lo = 0.99, o = "lbw", hs = "heat_gest"), tests = rd_tests(HV(h11c = YES))),
                       rd_sel(), rd_sens())
  expect_identical(r[["F.read.lbw.national"]]$display, "total may reflect coincident national events")
  # a not-estimable input of a consistent en test
  tab <- rd_tab(); tab[outcome == "sb" & term == "dry_gest", `:=`(status = "error", error = "term(s) not estimated", rr = NA_real_, lo = NA_real_, hi = NA_real_)]
  bad <- rd(HV(h10c = YES), tab)[["F.read.sb.national"]]
  expect_identical(bad$display, "not estimable (F.l.sb.dry_gest.rr: term(s) not estimated)")
  expect_true(is.na(bad$value))
  expect_identical(names(reading_rules_f(list(table = rd_tab(), tests = rd_tests(HV())), rd_sel(), rd_sens())),
                   sort(WANT[f_key_step(WANT) == "reading"], method = "radix"))
})

# ---- the conclusion sentence ----------------------------------------------------------------------------------------

test_that("the conclusion sentence follows the contract template and never uses causal wording", {
  prim <- function(h) fake_step_entries("primary", h)
  s <- conclusion_sentence_f(prim(HV(h10a = YES, h10c = YES, h11b = YES)))
  expect_identical(s, paste0("In this link-unit-month analysis of routine HMIS data from India, April 2012 to February 2020, the results were ",
    "consistent with higher stillbirth rates after third-trimester heat, full-gestation rainfall deficit or an El Niño gestation ",
    "(third-trimester heat and an El Niño gestation); and consistent with a higher low birth weight share among weighed newborns after ",
    "full-gestation heat, rainfall deficit or an El Niño gestation (full-gestation rainfall deficit)."))
  s0 <- conclusion_sentence_f(prim(HV()))
  expect_match(s0, "the results were not consistent with higher stillbirth rates after third-trimester heat, full-gestation rainfall deficit or an El Niño gestation; and not consistent with a higher low birth weight share", fixed = TRUE)
  expect_false(grepl("third-trimester heat and", s0, fixed = TRUE))
  expect_false(grepl(CONCLUSION_CAUSAL_F, s, ignore.case = TRUE, perl = TRUE))
  expect_false(grepl("Paper [A-F]\\b", s))
  # the fixed phrases are verbatim in the contract
  md <- paste(readLines(F_CONTRACT, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  for (ph in CONCLUSION_PHRASES_F) expect_true(grepl(trimws(ph), md, fixed = TRUE), info = ph)
  # stops: a missing key, a verdict outside the vocabulary, an overall verdict that disagrees with its tests
  E <- prim(HV()); E[["F.h10.verdict"]] <- NULL
  expect_error(conclusion_sentence_f(E), "missing key F.h10.verdict")
  E <- prim(HV()); E[["F.h10a.verdict"]] <- res_entry("not consistent with (negative control failed)", "maybe", "t", "d")
  expect_error(conclusion_sentence_f(E), "outside")
  E <- prim(HV()); E[["F.h11.verdict"]] <- res_entry(YES, YES, "t", "d")
  expect_error(conclusion_sentence_f(E), "disagrees")
  # a negative-control-failed test is a "not consistent with" in the sentence and the list
  E <- prim(HV(h10a = "not consistent with (negative control failed)"))
  expect_false(grepl("third-trimester heat and", conclusion_sentence_f(E), fixed = TRUE))
})

# ---- provenance and stability ----------------------------------------------------------------------------------------

test_that("the dirty flag is computed on tracked files only", {
  expect_true("--untracked-files=no" %in% f_status_args(c("models/F")))
  expect_identical(f_status_args("models/F")[1:2], c("status", "--porcelain"))
  expect_true(all(c("models/F", "pipeline/hmis", "papers/F/results_keys.md") %in% F_CODE_PATHS))
})

test_that("provenance records the code commit, the dirty flag, the seed and the input hashes", {
  dir <- withr::local_tempdir()
  f1 <- file.path(dir, "a.csv"); writeBin(charToRaw("x
1
"), f1)
  f2 <- file.path(dir, "b.csv"); writeBin(charToRaw("x\r\n1\r\n"), f2)           # CRLF checkout of the same committed file
  expect_identical(f_sha256_lf(f1), f_sha256_lf(f2))
  prov <- f_provenance(list(list(name = "power", status = "cached", script = "01_power.R", entries = list(), rds_sha256 = "abc",
                                 rds = "models/F/_cache/power.rds", outputs = data.table::data.table(path = "papers/F/output/power.csv", sha256_lf = "def"))),
                       n_keys = 297L, inputs = c(a = f1), git_fun = function(args) if (args[1] == "log") "9c71c36" else character())
  expect_identical(prov[item == "results_code_commit"]$value, "9c71c36")
  expect_identical(prov[item == "results_code_dirty"]$value, "FALSE")
  expect_identical(prov[item == "seed"]$value, as.character(SEED_F))
  expect_identical(prov[item == "n_keys"]$value, "297")
  expect_true(any(grepl("^input:", prov$item)) && any(grepl("^cache:power", prov$item)) && any(grepl("^output:", prov$item)))
  dirty <- f_provenance(list(), n_keys = 1L, inputs = character(), git_fun = function(args) if (args[1] == "log") "x" else " M models/F/R/common_f.R")
  expect_identical(dirty[item == "results_code_dirty"]$value, "TRUE")
})

test_that("--use-cache never fits: a missing cache stops with a clear error, and the script runner is never called", {
  calls <- character()
  real_runner <- f_run_script
  assign("f_run_script", function(script, args = character()) { calls <<- c(calls, script); invisible(0L) }, envir = globalenv())
  withr::defer(assign("f_run_script", real_runner, envir = globalenv()))
  defs <- f_step_defs(out_dir = file.path(withr::local_tempdir(), "out"), cache = file.path(withr::local_tempdir(), "nocache"))
  expect_error(resolve_f_step(defs$primary, mode = "use_cache"), "cache.*primary.rds.*missing.*never refits")
  expect_error(resolve_f_step(defs$secondary, mode = "use_cache"), "missing")
  expect_error(resolve_f_step(defs$power, mode = "use_cache"), "missing")
  expect_identical(calls, character())
  # a present cache with a missing output also stops without running anything
  d <- withr::local_tempdir(); dir.create(file.path(d, "c")); saveRDS(list(), file.path(d, "c", "primary.rds"))
  defs2 <- f_step_defs(out_dir = file.path(d, "out"), cache = file.path(d, "c"))
  expect_error(resolve_f_step(defs2$primary, mode = "use_cache"), "output.*missing")
  expect_identical(calls, character())
  # a cache that differs from the committed CSV stops ("different runs")
  dir.create(file.path(d, "out"))
  saveRDS(list(table = data.table::data.table(a = 1), tests = data.table::data.table(test_id = "h10a", verdict = "x")), file.path(d, "c", "primary.rds"))
  data.table::fwrite(data.table::data.table(a = 2), file.path(d, "out", "primary_estimates.csv"))
  data.table::fwrite(data.table::data.table(test_id = "h10a", verdict = "x"), file.path(d, "out", "verdicts.csv"))
  expect_error(resolve_f_step(defs2$primary, mode = "use_cache"), "different runs")
  expect_identical(calls, character())
  # default mode (not use_cache) does call the runner for an incomplete step; refit always does
  try(resolve_f_step(defs$primary, mode = "default"), silent = TRUE)
  expect_identical(calls, "02_primary.R")
  try(resolve_f_step(defs2$primary, mode = "refit"), silent = TRUE)
  expect_identical(calls, c("02_primary.R", "02_primary.R"))
  expect_error(f_results_settings(c("--use-cache", "--refit")), "exclude each other")
  expect_error(f_results_settings("--nonsense"), "unknown argument")
  expect_identical(f_results_settings("--use-cache")$mode, "use_cache")
  expect_identical(f_results_settings("--refit")$mode, "refit")
})
