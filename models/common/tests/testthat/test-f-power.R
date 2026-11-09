# Paper F Task 9: power simulation on the simplified model (R6) (models/F/R/power_f.R).
# models/common/R and models/E/R are frozen; the F helpers call them unchanged. Synthetic data only.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  for (f in c("common_f.R", "perinatal.R", "power_f.R")) source(file.path(root, "F", "R", f), local = globalenv())
})

# timing table in which every fit takes `m` minutes: the 200-simulation, 4-point plan is 80 * m / cores hours
tim <- function(m) data.table::data.table(fit = c("sim_l", "sim_t"), minutes = m)

test_that("power_plan follows the R6 order and never drops tests", {
  p <- power_plan(tim(20 / 80), cores = 1L)                       # 20 h
  expect_identical(p$step, "200"); expect_equal(p$n_sim, 200L); expect_equal(p$projected_h, 20)
  expect_equal(p$grid, GRID)
  p <- power_plan(tim(30 / 80), cores = 1L)                       # 30 h -> 100 simulations: 15 h
  expect_identical(p$step, "100"); expect_equal(p$n_sim, 100L); expect_equal(p$projected_h, 15)
  expect_equal(p$grid, GRID)
  p <- power_plan(tim(60 / 80), cores = 1L)                       # 60 h -> 30 h at 100 -> reduced grid: 22.5 h
  expect_identical(p$step, "100_reduced_grid"); expect_equal(p$n_sim, 100L); expect_equal(p$projected_h, 22.5)
  expect_equal(p$grid, list(L = GRID_REDUCED, T = GRID_REDUCED))
  p <- power_plan(tim(130 / 80), cores = 1L)                      # 130 h -> 48.75 h after both reductions
  expect_identical(p$step, "stop"); expect_equal(p$n_sim, 100L); expect_equal(p$projected_h, 48.75)
  expect_equal(p$grid, list(L = GRID_REDUCED, T = GRID_REDUCED))  # the fully reduced plan that was projected
  expect_equal(p$n_tests, 6L)
  expect_error(power_plan(tim(1), n_tests = 5L, cores = 1L), "six tests")
  # workers divide the hours; Model L tests use sim_l and Model T tests sim_t (4 L tests and 2 T tests)
  tt <- data.table::data.table(fit = c("sim_l", "sim_t"), minutes = c(12.75, 5.41))
  expect_equal(power_plan(tt, cores = 7L)$projected_h, 100 * 3 * (4 * 12.75 + 2 * 5.41) / 60 / 7)
  expect_equal(power_plan(tt, cores = 70L)$projected_h, 200 * 4 * (4 * 12.75 + 2 * 5.41) / 60 / 70)
  expect_error(power_plan(data.table::data.table(fit = "sim_l", minutes = 1), cores = 1L), "sim_t")
  expect_identical(GRID$L, c(1.01, 1.02, 1.03, 1.05)); expect_identical(GRID$T, c(1.02, 1.05, 1.10, 1.20))
  expect_identical(GRID_REDUCED, c(1.03, 1.05, 1.10))
})

test_that("the actual timings give the stop plan and the cores rule", {
  skip_if_not(file.exists(file.path(F_OUT, "timing.csv")))
  tt <- data.table::fread(file.path(F_OUT, "timing.csv"))
  p <- power_plan(tt, cores = 7L)
  expect_identical(p$step, "stop"); expect_gt(p$projected_h, 24)
  expect_equal(p$projected_h, 100 * 3 * (4 * 12.75 + 2 * tt[fit == "sim_t", minutes]) / 60 / 7)
})

test_that("boot_plan falls back only above 12 h", {
  expect_identical(boot_plan(11.9 * 60 / 500, B = 500L, B_reduced = 200L, cores = 1L), 500L)
  expect_identical(boot_plan(12.1 * 60 / 500, B = 500L, B_reduced = 200L, cores = 1L), 200L)
  expect_identical(boot_plan(12 * 60 / 500, B = 500L, B_reduced = 200L, cores = 1L), 500L)
  expect_identical(boot_plan(12.1 * 60 / 200, B = 200L, B_reduced = 100L, cores = 1L), 100L)
  expect_identical(boot_plan(10, B = 500L, B_reduced = 200L, cores = 7L), 500L)    # 11.9 h
  expect_identical(boot_plan(10, B = 500L, B_reduced = 200L, cores = 6L), 200L)    # 13.9 h
})

test_that("null state drops only the tested terms", {
  d <- sim_link_panel(n_units = 12, n_states = 3, n_months = 40, beta = 0, seed = 3)
  st <- sim_null_state(d, "h10a")
  expect_false(any(L_HEAT %in% st$null_spec$fixed))
  expect_true(all(c(L_DRY, L_LEADS, "ym_f") %in% st$null_spec$fixed))
  expect_identical(st$alt_spec$fixed, sim_spec_l("sb")$fixed)
  expect_equal(st$x, st$data$tmax_t3)
  st2 <- sim_null_state(d, "h10b")
  expect_false(any(L_DRY %in% st2$null_spec$fixed)); expect_true(all(L_HEAT %in% st2$null_spec$fixed))
  expect_identical(st2$null_spec$re, "int"); expect_length(st2$null_spec$slopes, 0L)
  expect_length(st$eta, nrow(st$data)); expect_true(all(is.finite(st$eta))); expect_gt(st$theta, 0)
  expect_null(st$sd_ym)
  stT <- sim_null_state(d, "h11c")
  expect_false("en_gest" %in% stT$null_spec$fixed); expect_true("ln_gest" %in% stT$null_spec$fixed)
  expect_gt(stT$sd_ym, 0)
  expect_equal(stT$x, stT$data$en_gest)
})

# a state without a fit: only the draw is exercised
mk_state <- function(summary, model = "L") {
  n <- 400
  d <- data.table::data.table(tmax_t3 = rep(c(30, 31), n / 2), tmax_t2 = 30, tmax_t1 = 29,
                              spi3_dry_l0 = rep(c(0, -1), n / 2), spi3_dry_l3 = rep(c(0, -2), n / 2),
                              spi3_dry_l6 = rep(c(0, -3), n / 2), en_gest = rep(c(0, 2), n / 2))
  st <- list(summary = summary, model = model, eta = rep(log(5000), n), ym_f = factor(rep(1:40, 10)),
             sd_ym = if (model == "T") 0 else NULL, theta = 1e6, data = d)
  st$x <- sim_exposure(d, summary)
  st
}

test_that("deficit injection is per SPI -1", {
  st <- mk_state("dry_gest")
  expect_equal(st$x, rep(c(0, 2), 200))                       # minus the mean of the three SPI terms
  y <- power_draw_f(st, 1.10, 1L, 7L)
  dry <- st$data$spi3_dry_l0 < 0
  expect_equal(mean(y[dry]) / mean(y[!dry]), 1.10^2, tolerance = 0.01)
  expect_equal(mean(y[!dry]), 5000, tolerance = 0.02)
  # heat_gest: mean of the three strata; heat_t3: tmax_t3; en: en_gest
  expect_equal(sim_exposure(st$data, "heat_gest"), (st$data$tmax_t3 + 30 + 29) / 3)
  expect_equal(sim_exposure(st$data, "heat_t3"), st$data$tmax_t3)
  expect_equal(sim_exposure(st$data, "en"), st$data$en_gest)
  expect_error(sim_exposure(st$data, "zzz"))
  # one draw per simulation index, shared across rr (common random numbers), different across i
  a <- power_draw_f(st, 1.05, 3L, 7L)
  expect_identical(a, power_draw_f(st, 1.05, 3L, 7L))
  expect_false(identical(a, power_draw_f(st, 1.05, 4L, 7L)))
})

test_that("Model T redraws the year-month effects from N(0, sd^2)", {
  st <- mk_state("en", "T"); st$sd_ym <- 0.5
  b <- power_draw_f(st, 1, 1L, 1L)
  expect_gt(stats::sd(tapply(log(b), st$ym_f, mean)), 0.3)
  expect_lt(max(tapply(log(b), st$ym_f, stats::sd)), 0.05)
})

test_that("mde_f labels RR and the simplification", {
  lab <- " (optimistic: simulated on a simplified model)"
  r <- mde_f(data.table::data.table(rr = c(1.03, 1.05, 1.10), power = c(.2, .5, .7)))
  expect_identical(r$display, paste0("not reached at RR 1.10", lab)); expect_true(is.na(r$value))
  r <- mde_f(data.table::data.table(rr = c(1.01, 1.02, 1.03, 1.05), power = c(.1, .3, .5, .6)))
  expect_identical(r$display, paste0("not reached at RR 1.05", lab))
  r <- mde_f(data.table::data.table(rr = c(1.02, 1.05, 1.10, 1.20), power = c(.1, .85, .95, 1)))
  expect_identical(r$display, paste0("1.05", lab)); expect_equal(r$value, 1.05)
})

test_that("simulate_power_f detects a large effect and holds size", {
  skip_if_slow_disabled()
  d <- sim_link_panel(n_units = 20, n_states = 4, n_months = 30, beta = 0, theta = 30, seed = 11)
  d[, c("tmax_t3", "tmax_t2", "tmax_t1") := lapply(.SD, function(v) v - 30), .SDcols = c("tmax_t3", "tmax_t2", "tmax_t1")]   # centred: rr^x stays near 1
  r <- simulate_power_f(d, "h10a", rrs = c(1, 1.30), n_sim = 20L, seed = 5L, cores = 1L)
  expect_identical(names(r), c("test_id", "rr", "n_ok", "power", "mean_rr"))
  big <- r[rr == 1.30]; null <- r[rr == 1]
  expect_gte(big$n_ok, 15L); expect_gte(null$n_ok, 15L)
  expect_gte(big$power, 0.8)
  expect_lte(null$power, 0.2)
})
