# Paper F Task 7: Model L / Model T helpers (models/F/R/common_f.R, models/F/R/perinatal.R).
# models/common/R and models/E/R are frozen; the F helpers call them unchanged.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  for (f in c("common_f.R", "perinatal.R")) source(file.path(root, "F", "R", f), local = globalenv())
})

test_that("l_spec builds the Model L formula", {
  f <- deparse1(spec_formula(l_spec("sb")))
  expect_match(f, "sb ~ tmax_t3 + tmax_t2 + tmax_t1 + spi3_dry_l0 + spi3_dry_l3 + spi3_dry_l6 + tmax_lead12 + spi3_dry_lead3 + ym_f + offset(log_tb) + (1 + t_c | unit_id)", fixed = TRUE)
  s <- l_spec("lbw", extra = "covid_fy2021")
  expect_identical(s$offset, "log_wt")
  expect_identical(s$trend_df, 0L)
  expect_identical(s$slopes, "t_c")
  expect_identical(s$re, "us")
  expect_identical(tail(s$fixed, 1), "covid_fy2021")
  expect_identical(L_RE, "(1 | state_ym)")
  expect_identical(l_spec("sb", heat = "tmax_t3")$fixed[1], "tmax_t3")
})

test_that("t_spec_f uses the gestation means and the outcome's denominator", {
  f <- deparse1(spec_formula(t_spec_f("lbw")))
  expect_match(f, "lbw ~ en_gest + ln_gest + moy + t_c + hmis_format2017 + demonet + offset(log_wt)", fixed = TRUE)
  f2 <- deparse1(spec_formula(t_spec_f("sb", exposure = c("en_roni_gest", "ln_roni_gest"), extra = "pmsma")))
  expect_match(f2, "sb ~ en_roni_gest + ln_roni_gest + moy + t_c + hmis_format2017 + demonet + pmsma + offset(log_tb)",
               fixed = TRUE)
})

test_that("constants and the test table are as the contract lists them", {
  expect_identical(SEED_F, 20261026L)
  expect_identical(OUTS, c("sb", "lbw"))
  expect_identical(DENOM, c(sb = "log_tb", lbw = "log_wt"))
  expect_identical(TESTS$test_id, c("h10a", "h10b", "h10c", "h11a", "h11b", "h11c"))
  expect_identical(TESTS$summary, c("heat_t3", "dry_gest", "en", "heat_gest", "dry_gest", "en"))
  expect_identical(SUMMARIES$dry_gest$sign, -1)
  expect_identical(SUMMARIES$heat_gest$terms, L_HEAT)
})

# summary_rr_from / lead_rr_from are the arithmetic of summary_rr / lead_rr on a coefficient vector and its vcov.

test_that("deficit summaries are per SPI -1", {
  nm <- c(L_HEAT, L_DRY, L_LEADS)
  est <- stats::setNames(rep(0, length(nm)), nm)
  V <- diag(1e-4, length(nm)); dimnames(V) <- list(nm, nm)
  e1 <- est; e1[L_DRY] <- -0.01
  r <- summary_rr_from(e1, V, SUMMARIES$dry_gest)
  expect_equal(r$rr, exp(0.03))
  expect_true(r$lo < r$rr && r$rr < r$hi)
  e2 <- est; e2[L_HEAT] <- 0.01; e2["tmax_lead12"] <- 0.07
  expect_equal(summary_rr_from(e2, V, SUMMARIES$heat_gest)$rr, exp(0.03))
  expect_equal(lead_rr_from(e2, V, SUMMARIES$heat_gest)$rr, exp(0.07))
  e3 <- est; e3["spi3_dry_lead3"] <- -0.2
  expect_equal(lead_rr_from(e3, V, SUMMARIES$dry_gest)$rr, exp(0.2))
  expect_identical(names(r), c("rr", "lo", "hi", "p"))
})

test_that("summary_rr sums the strata with the joint vcov", {
  nm <- c(L_HEAT, L_DRY, L_LEADS)
  est <- stats::setNames(seq(0.01, by = 0.005, length.out = length(nm)), nm)
  set.seed(3)
  A <- matrix(stats::rnorm(length(nm)^2), length(nm)); V <- crossprod(A) * 1e-4
  dimnames(V) <- list(nm, nm)
  r <- summary_rr_from(est, V, SUMMARIES$heat_gest)
  lc <- lin_comb(est, V, L_HEAT)
  expect_equal(r$rr, exp(lc$est))
  expect_equal(r$lo, exp(lc$est - stats::qnorm(0.975) * lc$se), tolerance = 1e-5)
  expect_equal(r$hi, exp(lc$est + stats::qnorm(0.975) * lc$se), tolerance = 1e-5)
  expect_equal(r$p, lc$p)
  expect_false(isTRUE(all.equal(lc$se, sqrt(sum(diag(V)[L_HEAT])))))
  # a single-term summary (heat_t3) is that term alone
  r3 <- summary_rr_from(est, V, SUMMARIES$heat_t3)
  expect_equal(r3$rr, exp(est[["tmax_t3"]]))
})

test_that("simulation specs have unit intercepts only", {
  s <- sim_spec_l("sb")
  expect_identical(s$re, "int"); expect_identical(s$slopes, character())
  f <- deparse1(spec_formula(s))
  expect_false(grepl("state_ym", f, fixed = TRUE)); expect_false(grepl("t_c |", f, fixed = TRUE))
  expect_match(f, "(1 | unit_id)", fixed = TRUE)
  st <- sim_spec_t("lbw")
  expect_identical(st$re, "int"); expect_identical(st$slopes, character())
  expect_identical(st$offset, "log_wt")
  expect_match(deparse1(spec_formula(st)),
               "lbw ~ en_gest + ln_gest + moy + t_c + hmis_format2017 + demonet + offset(log_wt) + (1 | unit_id)",
               fixed = TRUE)
})

test_that("timing_data permutes exposures within unit and keeps outcomes", {
  d <- sim_link_panel(n_units = 8, n_months = 36, seed = 5)
  d0 <- data.table::copy(d)
  cols <- c(L_HEAT, "en_gest", "ln_gest")
  p <- timing_data(d, cols, seed = 11L)
  expect_identical(p$sb, d$sb); expect_identical(p$log_tb, d$log_tb); expect_identical(p$unit_id, d$unit_id)
  for (cl in cols) {
    expect_false(identical(p[[cl]], d[[cl]]), info = cl)
    for (u in levels(d$unit_id)) {
      i <- d$unit_id == u
      expect_identical(sort(p[[cl]][i]), sort(d[[cl]][i]))
    }
  }
  expect_identical(timing_data(d, cols, seed = 11L)$tmax_t3, p$tmax_t3)
  expect_false(identical(timing_data(d, cols, seed = 12L)$tmax_t3, p$tmax_t3))
  expect_identical(d, d0)                                   # the input is not modified
})

test_that("Model T simulation spec recovers a known en_gest effect", {
  skip_on_cran()
  d <- sim_link_panel(n_units = 40, n_months = 95, beta = 0.10, theta = 40, seed = 2)
  f <- fit_time_chain(sim_spec_t("lbw"), d, chain = "iid")
  expect_identical(f$re_used, "int")
  b <- glmmTMB::fixef(f$model)$cond[["en_gest"]]
  expect_lt(abs(b - 0.10), 0.03)
})

test_that("Model L simulation spec recovers the sustained heat effect", {
  skip_on_cran()
  d <- sim_link_panel(n_units = 40, n_months = 95, beta = 0.05, theta = 40, seed = 4)
  f <- fit_nb(sim_spec_l("sb"), d, fitter = e_glmmTMB_fit)
  expect_identical(f$re_used, "int")
  r <- summary_rr(f, SUMMARIES$heat_gest)
  expect_lt(abs(log(r$rr) - 0.05), 0.04)
  expect_lt(r$lo, r$rr); expect_gt(r$hi, r$rr)
})

test_that("00_timing.R reads no coefficient", {
  src <- readLines(file.path(F_DIR, "00_timing.R"))
  expect_false(any(grepl("term_row|summary_rr|fixef|coef\\(|summary\\(|confint|vcov", src)))
})

test_that("read_perinatal_model builds the factors and outcome_rows drops gated rows", {
  tf <- tempfile(fileext = ".csv.gz")
  d <- data.table::data.table(link_id = rep(c("A", "B"), each = 4), state_unit = rep(c("X", "Y"), each = 4),
                              ym = rep(24144:24147, 2), era_e2 = rep(c(0L, 0L, 1L, 1L), 2),
                              in_primary = rep(c(1L, 1L, 1L, 0L), 2), moy = rep(c(4L, 5L, 6L, 7L), 2),
                              state_ym = paste(rep(c("X", "Y"), each = 4), rep(24144:24147, 2), sep = ":"),
                              excluded_sb = c(0L, 1L, 0L, 0L, 0L, 0L, 0L, 0L),
                              small_denom_sb = c(0L, 0L, 1L, 0L, 0L, 0L, 0L, 0L),
                              sb = c(1, 2, 3, 4, 5, 6, 7, 8))
  data.table::fwrite(d, tf)
  p <- read_perinatal_model("primary", path = tf)
  expect_identical(nrow(p), 6L)
  expect_identical(levels(p$unit_id), c("A", "B"))
  expect_identical(levels(p$moy), as.character(1:12))
  expect_identical(levels(p$national), "IN")
  expect_identical(nlevels(p$ym_f), 3L)
  expect_true(all(c("state_ym", "unit_era") %in% names(p)))
  expect_identical(levels(p$unit_era), c("A:0", "A:1", "B:0", "B:1"))
  o <- outcome_rows(p, "sb")
  expect_identical(o$sb, c(1L, 5L, 6L, 7L))
  expect_identical(nrow(read_perinatal_model("fy2021", path = tf)), 8L)
})
