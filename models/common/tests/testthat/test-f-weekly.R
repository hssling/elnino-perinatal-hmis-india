# Paper F: weekly distributed-lag functions (models/F/R/weekly_f.R). Synthetic data only: no HMIS outcome
# and no real exposure is read.

local({
  root <- if (exists("MODELS_ROOT")) MODELS_ROOT else normalizePath(file.path(getwd(), "..", "..", ".."), winslash = "/")
  for (f in c("common_f.R", "weekly_f.R")) source(file.path(root, "F", "R", f), local = globalenv())
})

sim_weekly <- function(df = 4L, n_units = 60L, n_months = 60L, seed = 11L) {
  set.seed(seed)
  d <- data.table::CJ(unit = seq_len(n_units), t = seq_len(n_months))
  n <- nrow(d)
  basis <- w_basis(W_NW, df)
  g_heat <- c(0.004, -0.002, 0.008, 0.012)[seq_len(df)]
  g_dry <- c(-0.006, 0.002, -0.004, 0.001)[seq_len(df)]
  Xh <- matrix(stats::rnorm(n * W_NW), n, W_NW)
  Xd <- matrix(pmin(stats::rnorm(n * W_NW), 0), n, W_NW)
  colnames(Xh) <- w_week_cols("heat"); colnames(Xd) <- w_week_cols("dry")
  a <- stats::rnorm(n_units, 0, 0.3)
  d[, log_tb := log(5000)]
  eta <- -4 + a[d$unit] + d$log_tb + as.numeric(Xh %*% (basis %*% g_heat)) + as.numeric(Xd %*% (basis %*% g_dry))
  d[, sb := stats::rpois(n, exp(eta))]
  d <- cbind(d, Xh, Xd)
  d[, unit_id := factor(unit)]
  list(d = d, basis = basis, beta_heat = as.numeric(basis %*% g_heat), beta_dry = as.numeric(basis %*% g_dry))
}

test_that("the hand-built cross-basis recovers a known lag curve from simulated Poisson data", {
  s <- sim_weekly()
  d <- w_add_cb(s$d, "heat", s$basis, "heat")
  d <- w_add_cb(d, "dry", s$basis, "dry")
  expect_equal(as.numeric(d$heat_cb2), as.numeric(as.matrix(s$d[, w_week_cols("heat"), with = FALSE]) %*% s$basis[, 2]))
  fit <- w_fit(d, w_rhs(4L, nc = FALSE), fe = "unit_id", id = "sim")
  cv <- w_curves(fit, 4L)
  h <- cv[exposure == "heat"]; dr <- cv[exposure == "dry"]
  expect_equal(nrow(h), 40L)
  expect_lt(max(abs(h$est - s$beta_heat)), 0.004)
  expect_lt(max(abs(dr$est - (-s$beta_dry))), 0.006)          # deficit curve is per one SPI unit more deficit
  expect_gte(mean(h$lo <= exp(s$beta_heat) & h$hi >= exp(s$beta_heat)), 0.8)
  # cumulative third-trimester sum against the truth
  cum <- w_cums(fit, 4L)
  expect_equal(cum[exposure == "heat" & block == "t3"]$est, sum(s$beta_heat[28:40]), tolerance = 0.02, scale = 1)
  expect_identical(cum$block, rep(names(W_BLOCKS), 2))
})

test_that("the lag basis is a natural cubic spline with intercept over weeks 1-40", {
  for (k in W_DFS) {
    b <- w_basis(W_NW, k)
    expect_identical(dim(b), c(40L, k))
    expect_lt(max(abs(qr.resid(qr(b), rep(1, 40)))), 1e-8)      # intercept included: constants are in the span
  }
  expect_identical(dim(w_basis(W_NW39, 4L)), c(39L, 4L))
  expect_identical(W_BLOCKS39$t3, 28:39)
})

test_that("RERI arithmetic", {
  expect_equal(reri_arith(1.5, 1.2, 1.1), 1.5 - 1.2 - 1.1 + 1)
  b <- w_basis(W_NW, 3L)
  a <- colSums(b[28:40, ])
  g0 <- c(0.01, 0.02, -0.01); g1 <- c(0.005, 0, 0.01)
  cf <- c(stats::setNames(g0, w_cb_names("heat", 3L)), stats::setNames(g1, paste0(w_cb_names("heat", 3L), "_sm")), summer = 0.05)
  r <- reri_from(cf, b)
  expect_equal(r[["rr10"]], exp(sum(a * g0)))
  expect_equal(r[["rr01"]], exp(0.05))
  expect_equal(r[["rr11"]], exp(0.05 + sum(a * (g0 + g1))))
  expect_equal(r[["reri"]], r[["rr11"]] - r[["rr10"]] - r[["rr01"]] + 1)
  # no interaction on the multiplicative scale -> RERI = (RR10 - 1)(RR01 - 1)
  cf0 <- cf; cf0[paste0(w_cb_names("heat", 3L), "_sm")] <- 0
  r0 <- reri_from(cf0, b)
  expect_equal(r0[["reri"]], (r0[["rr10"]] - 1) * (r0[["rr01"]] - 1))
  expect_true(all(is.na(reri_from(cf[-1], b))))
})

test_that("E-value formula (VanderWeele and Ding)", {
  expect_equal(evalue_rr(1.5), 1.5 + sqrt(1.5 * 0.5))
  expect_equal(evalue_rr(0.8), 1.25 + sqrt(1.25 * 0.25))
  expect_equal(evalue_rr(1), 1)
  expect_equal(evalue_ci(1.5, 1.2, 1.9), 1.2 + sqrt(1.2 * 0.2))
  expect_equal(evalue_ci(0.8, 0.7, 0.9), evalue_rr(0.9))
  expect_equal(evalue_ci(1.1, 0.95, 1.3), 1)
  expect_equal(evalue_ci(0.9, 0.8, 1.02), 1)
})

test_that("cumulative-sum standard errors equal the SE of the summed week coefficients", {
  set.seed(3)
  for (k in c(3L, 5L)) {
    b <- w_basis(W_NW, k)
    A <- matrix(stats::rnorm(k * k), k); V <- crossprod(A) / 100
    g <- stats::rnorm(k, 0, 0.01)
    Vb <- b %*% V %*% t(b)
    for (wk in W_BLOCKS) {
      cs <- w_cum_from(g, V, b, wk)
      expect_equal(cs$se, sqrt(sum(Vb[wk, wk])))
      expect_equal(cs$est, sum((b %*% g)[wk]))
      cd <- w_cum_from(g, V, b, wk, sign = -1)
      expect_equal(cd$est, -cs$est); expect_equal(cd$se, cs$se)
      expect_equal(c(cd$lo, cd$hi), exp(-cs$est + c(-1, 1) * stats::qnorm(0.975) * cs$se))
    }
    cv <- w_curve_from(g, V, b)
    expect_equal(cv$se, unname(sqrt(diag(Vb))))
  }
})

test_that("journal display, season coding, weights and bootstrap draws", {
  expect_identical(fmt_w_ci(1.0412, 1.0123, 1.0678), "1.04 (95% CI 1.01, 1.07)")
  expect_identical(fmt_w_ci(-0.012, -0.05, 0.031), "−0.01 (95% CI −0.05, 0.03)")
  expect_identical(fmt_w_pct(0.0321), "3.2%")
  expect_identical(as.character(season_of(c(12, 1, 2, 3, 5, 6, 9, 10, 11))),
                   c("winter", "winter", "winter", "summer", "summer", "monsoon", "monsoon", "postmonsoon", "postmonsoon"))
  sw <- stabilised_weights(c(TRUE, TRUE, FALSE, TRUE), c(0.5, 0.75, 0.2, 1))
  expect_equal(sw, c(1.5, 1, NA, 0.75))
  d1 <- w_boot_draws(10L, 5L, 1L); d2 <- w_boot_draws(10L, 5L, 1L)
  expect_identical(d1, d2); expect_identical(dim(d1), c(5L, 10L))
  expect_true(all(d1 >= 1L & d1 <= 10L))
})
