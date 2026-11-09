# Paper F (Task 7): simulated link-unit-month panel with known truth, laid out like
# data/derived/hmis/perinatal_model.csv.gz (primary window April 2012 onward). It carries every column the Paper F
# specs (Model L, Model T, the simulation specs) and the common spec_vars()/complete_rows() use. Counts are NB2 with
# unit random intercepts and slopes and a log-denominator offset. Log IRR `beta`: per +1 deg C sustained over the three
# trimesters for sb (each tmax_t* carries beta/3) and per +1 deg C of en_gest for lbw. Both outcomes are drawn;
# sb uses log_tb and lbw uses log_wt.
sim_link_panel <- function(n_units = 40, n_states = 5, n_months = 95, beta = 0, theta = 30, seed = 1) {
  set.seed(seed)
  ym <- 2012L * 12L + 3L + seq_len(n_months) - 1L                   # ym = year * 12 + month - 1; April 2012 first
  year <- ym %/% 12L
  month <- ym %% 12L + 1L
  oni <- rep_len(c(-0.4, -0.2, 0.1, 0.5, 1.0, 1.6, 2.2, 1.2, 0.3, -0.3, -0.7, -0.5, 0, 0.4, 0.9, 0.6), n_months)
  m <- data.table::data.table(ym = ym, year = year, moy = month, t_c = ((seq_len(n_months) - 1L) - 47) / 12,
                              hmis_format2017 = as.integer(ym >= 2017L * 12L + 3L),
                              demonet = as.integer(ym >= 2016L * 12L + 10L & ym <= 2017L * 12L),
                              en_gest = pmax(oni, 0), ln_gest = pmin(oni, 0),
                              season = 0.08 * sin(2 * pi * month / 12),
                              b_ym = stats::rnorm(n_months, 0, 0.03))
  u <- data.table::data.table(unit_id = sprintf("L%03d", seq_len(n_units)),
                              state_unit = sprintf("S%02d", rep_len(seq_len(n_states), n_units)),
                              a = stats::rnorm(n_units, 0, 0.3), b = stats::rnorm(n_units, 0.02, 0.02),
                              tb = round(stats::runif(n_units, 2e3, 2e4)),
                              tbase = stats::rnorm(n_units, 30, 1))
  d <- data.table::CJ(unit_id = u$unit_id, ym = ym)
  d <- u[d, on = "unit_id"][m, on = "ym"]
  d[, tmax_base := tbase + 4 * sin(2 * pi * (moy - 4) / 12)]
  d[, `:=`(tmax_t3 = tmax_base + stats::rnorm(.N, 0, 0.8), tmax_t2 = tmax_base + stats::rnorm(.N, 0, 0.8),
           tmax_t1 = tmax_base + stats::rnorm(.N, 0, 0.8),
           spi3_dry_l0 = pmax(0, -stats::rnorm(.N)), spi3_dry_l3 = pmax(0, -stats::rnorm(.N)),
           spi3_dry_l6 = pmax(0, -stats::rnorm(.N)),
           tmax_lead12 = 30 + stats::rnorm(.N, 0, 1), spi3_dry_lead3 = pmax(0, -stats::rnorm(.N)))]
  d[, mu_sb := exp(-6.2 + a + b * t_c + season + 0.05 * hmis_format2017 - 0.04 * demonet + b_ym +
                     (beta / 3) * (tmax_t1 + tmax_t2 + tmax_t3 - 3 * tmax_base) + log(tb))]
  d[, mu_lbw := exp(-2.4 + a + b * t_c + season + 0.05 * hmis_format2017 - 0.04 * demonet + b_ym +
                      beta * en_gest + log(tb * 0.85))]
  d[, `:=`(sb = stats::rnbinom(.N, size = theta, mu = mu_sb), lbw = stats::rnbinom(.N, size = theta, mu = mu_lbw))]
  d[, `:=`(log_tb = log(tb), log_wt = log(tb * 0.85))]
  d[, state_ym := paste(state_unit, ym, sep = ":")]
  d[, `:=`(unit_id = factor(unit_id), state_unit = factor(state_unit), ym_f = factor(ym, levels = sort(unique(ym))),
           state_ym = factor(state_ym), national = factor("IN"), moy = factor(moy, levels = 1:12))]
  data.table::setorder(d, unit_id, ym)
  d[, c("unit_id", "state_unit", "year", "ym", "ym_f", "state_ym", "national", "moy", "t_c", "hmis_format2017",
        "demonet", "tmax_t3", "tmax_t2", "tmax_t1", "spi3_dry_l0", "spi3_dry_l3", "spi3_dry_l6", "tmax_lead12",
        "spi3_dry_lead3", "en_gest", "ln_gest", "log_tb", "log_wt", "sb", "lbw"), with = FALSE]
}
