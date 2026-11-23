# Paper F: weekly distributed-lag analysis (analysis plan papers/F/analysis_plan_weekly.md;
# analysis_plan.md, sections 3-7; contract papers/F/results_keys.md section 15; functions models/F/R/weekly_f.R).
# Run from <repo>/models:
#   Rscript F/05_weekly.R --step=fits [--refit]        AIC choice of df, pooled, season, RERI point, sensitivity, IPW and
#                                                      ENSO fits; each fit cached as models/F/_cache/w_fit_<id>.rds, the
#                                                      prepared tables as w_fits.rds
#   Rscript F/05_weekly.R --step=boot [--workers=N]     the 500-resample link-unit cluster bootstrap of the RERI model
#                                                      (seed 20261123) -> models/F/_cache/w_boot.rds
#   Rscript F/05_weekly.R --step=results                tables models/F/output/w_*.csv, the F.w.* entries
#                                                      (models/F/_cache/w_entries.rds) appended to papers/F/results.json
#                                                      (every existing key byte-identical)
# Inputs: data/derived/hmis/perinatal_model.csv.gz (primary window only), perinatal_weekly_exposure.csv.gz and
# perinatal_weekly_oni.csv.gz (pipeline/hmis/perinatal_weekly.py). No p-value, test or verdict is computed. FY2020-21 is
# never read into a model (read_perinatal_model("primary")).

source("common/R/load.R")
source("F/R/common_f.R")
source("F/R/weekly_f.R")

w_args <- function(a = commandArgs(trailingOnly = TRUE)) {
  step <- sub("^--step=", "", grep("^--step=", a, value = TRUE))
  wk <- sub("^--workers=", "", grep("^--workers=", a, value = TRUE))
  list(step = if (length(step)) step else "all", refit = "--refit" %in% a,
       workers = if (length(wk)) as.integer(wk) else max(1L, min(8L, parallel::detectCores() - 2L)))
}

w_load <- function() {
  d <- read_perinatal_model("primary")
  w_prepare(d, read_weekly_exposure(), read_weekly_oni())
}

w_cached <- function(id, fun, refit = FALSE) {
  path <- file.path(W_CACHE, paste0("w_fit_", id, ".rds"))
  if (file.exists(path) && !refit) return(readRDS(path))
  f <- fun()
  dir.create(W_CACHE, recursive = TRUE, showWarnings = FALSE)
  saveRDS(f, path)
  flog(sprintf("fit %s: n = %d, %d units, AIC %.2f, %.1f s", id, f$nobs, f$n_units, f$aic, f$seconds), file = W_LOG)
  f
}

step_fits <- function(refit = FALSE) {
  t0 <- Sys.time()
  m <- w_load()
  miss <- w_missing(m)
  cc <- miss[variable == "cc_loss_panel"]$share
  flog(sprintf("fits: %d unit-months, %d eligible, %d included; complete-case loss %.4f of the panel, %.4f of eligible rows",
               nrow(m), sum(m$eligible), sum(m$included), cc, miss[variable == "cc_loss_eligible"]$share), file = W_LOG)
  if (cc >= W_MI_THRESHOLD)
    stop("05_weekly: complete-case loss >= 5% of the panel: the plan requires multiple imputation (50 imputations)", call. = FALSE)
  # AIC choice of the spline df (the same for heat and deficit), pooled primary model on the same rows
  fits <- list()
  for (k in W_DFS) {
    rows <- w_analysis(m, k)
    fits[[paste0("df", k)]] <- w_cached(paste0("pooled_df", k), function()
      w_fit(rows, w_rhs(k), extra_vcov = list(cluster2 = ~unit_id + ym_f), id = paste0("pooled_df", k)), refit)
  }
  aic <- data.table::data.table(df = W_DFS, aic = vapply(fits, `[[`, 0, "aic"), nobs = vapply(fits, `[[`, 0, "nobs"))
  if (data.table::uniqueN(aic$nobs) != 1L) stop("05_weekly: the df candidates were fitted on different rows", call. = FALSE)
  df <- aic$df[which.min(aic$aic)]
  flog("AIC choice: df = ", df, " (", paste(sprintf("%d: %.2f", aic$df, aic$aic), collapse = "; "), ")", file = W_LOG)
  rows <- w_analysis(m, df)
  season <- w_cached(paste0("season_df", df), function()
    w_fit(w_season_data(rows, df), w_season_rhs(df), id = "season"), refit)
  reri <- w_cached(paste0("reri_df", df), function()
    w_fit(w_reri_data(rows, df), w_reri_rhs(df), fe = W_FE_RERI, id = "reri"), refit)
  sens <- list()
  sens$negbin <- w_cached(paste0("sens_negbin_df", df), function() w_fit(rows, w_rhs(df), family = "negbin", id = "negbin"), refit)
  sens$trend <- w_cached(paste0("sens_trend_df", df), function() w_fit(rows, w_rhs(df), fe = W_FE_TREND, id = "trend"), refit)
  sens$inst090 <- w_cached(paste0("sens_inst090_df", df), function() w_fit(rows[inst090_all_fy == 1L], w_rhs(df), id = "inst090"), refit)
  rows39 <- w_analysis(m, df, align39 = TRUE)
  sens$align39 <- w_cached(paste0("sens_align39_df", df), function() w_fit(rows39, w_rhs(df), id = "align39"), refit)
  ipw <- w_ipw(m)
  m[, sw := ipw$sw]
  rows_w <- data.table::copy(rows)
  rows_w[m[included == TRUE], sw := i.sw, on = c("link_id", "ym")]
  if (anyNA(rows_w$sw)) stop("05_weekly: missing IPW weight on an analysed row", call. = FALSE)
  sens$ipw <- w_cached(paste0("sens_ipw_df", df), function() w_fit(rows_w, w_rhs(df), weights = ~sw, id = "ipw"), refit)
  enso_rows <- m[eligible & !is.na(en_gest_w) & !is.na(ln_gest_w)]
  enso <- w_cached("enso", function() w_fit(enso_rows, c("en_gest_w", "ln_gest_w", "t_c"), fe = "unit_id + state_unit^moy",
                                            cluster = ~ym_f, id = "enso"), refit)
  primary <- fits[[paste0("df", df)]]
  sel <- w_selection_table(m)
  out <- list(df = df, aic = aic, aic_season = data.table::data.table(model = c("pooled", "season"),
                                                                       aic = c(primary$aic, season$aic), nobs = c(primary$nobs, season$nobs)),
              fit_ids = c(names(fits), "season", "reri", names(sens), "enso"),
              flow = w_flow(m, fit = primary), missing = miss, selection = sel,
              ipw = list(model = ipw$model, sw = summary(ipw$sw[m$included]), sw_min = min(ipw$sw[m$included]),
                         sw_max = max(ipw$sw[m$included]), sw_mean = mean(ipw$sw[m$included])),
              enso_n = enso$nobs, enso_n_units = enso$n_units,
              n_episodes_note = "two El Nino episodes (2014-16 and 2018-19) fall in the birth-month window",
              seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  saveRDS(out, file.path(W_CACHE, "w_fits.rds"))
  flog(sprintf("fits step done in %.1f min", out$seconds / 60), file = W_LOG)
  invisible(out)
}

step_boot <- function(workers) {
  info <- readRDS(file.path(W_CACHE, "w_fits.rds"))
  m <- w_load()
  rows <- w_analysis(m, info$df)
  rr <- w_reri_data(rows, info$df)
  b <- w_bootstrap(rr, info$df, workers = workers)
  saveRDS(b, file.path(W_CACHE, "w_boot.rds"))
  invisible(b)
}

if (sys.nframe() == 0L) {
  a <- w_args()
  if (a$step %in% c("fits", "all")) step_fits(a$refit)
  if (a$step %in% c("boot", "all")) step_boot(a$workers)
  if (a$step %in% c("results", "all")) w_results()
}
