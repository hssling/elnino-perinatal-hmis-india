# Paper F Task 7: timing fits for the power simulation (R6). Runs BEFORE the analysis contract is committed.
# The fits use exposures permuted within unit (timing_data), so they carry no exposure information, and the script
# keeps only wall time, convergence, the random-effect steps reached and the row and unit counts. It extracts no
# estimate of any kind from a fit, never prints a fit object and writes papers/F/output/timing.csv only.
#
# Run from <repo>/models (detached; it can take hours):   Rscript F/00_timing.R
source("common/R/load.R")
source("F/R/common_f.R")
source("F/R/perinatal.R")

OUT_CSV <- file.path(F_OUT, "timing.csv")
dir.create(F_OUT, recursive = TRUE, showWarnings = FALSE)
log_file <- "timing.log"
OUT <- "sb"

flog("timing: reading ", PERINATAL_MODEL_CSV, file = log_file)
d <- outcome_rows(read_perinatal_model("primary"), OUT)
d <- timing_data(d, c(L_HEAT, L_DRY, L_LEADS, "en_gest", "ln_gest"))
flog("timing: ", nrow(d), " rows, ", nlevels(droplevels(d$unit_id)), " units (outcome ", OUT, ", exposures permuted within unit)",
     file = log_file)

# One timed fit. `fit_fun()` returns an nbfit; only its bookkeeping fields are read.
run_fit <- function(name, state_ym, fit_fun) {
  flog("timing: start ", name, file = log_file)
  t0 <- proc.time()[["elapsed"]]
  f <- tryCatch(fit_fun(), error = function(e) e)
  minutes <- (proc.time()[["elapsed"]] - t0) / 60
  if (inherits(f, "error")) {
    flog("timing: ", name, " did not converge after ", sprintf("%.1f", minutes), " min: ", first_line(conditionMessage(f)),
         file = log_file)
    row <- data.table::data.table(fit = name, outcome = OUT, minutes = minutes, re_used = NA_character_,
                                  time_re = NA_character_, state_ym = state_ym, converged = FALSE,
                                  n_rows = NA_integer_, n_units = NA_integer_)
  } else {
    row <- data.table::data.table(fit = name, outcome = OUT, minutes = minutes, re_used = f$re_used,
                                  time_re = if (is.null(f$time_re)) NA_character_ else f$time_re,
                                  state_ym = state_ym, converged = TRUE, n_rows = as.integer(f$n),
                                  n_units = nlevels(droplevels(f$data$unit_id)))
    flog("timing: ", name, " converged in ", sprintf("%.1f", minutes), " min, re_used ", f$re_used,
         ", time_re ", row$time_re, file = log_file)
  }
  row
}

res <- list()
write_now <- function() data.table::fwrite(data.table::rbindlist(res), OUT_CSV)

res$model_l <- run_fit("model_l_primary", TRUE,
                       function() fit_nb(l_spec(OUT), d, fitter = nb_fitter_with(L_RE)))
write_now()
res$model_t <- run_fit("model_t_primary", FALSE,
                       function() fit_time_chain(t_spec_f(OUT), d, chain = c("ar1", "iid")))
write_now()
res$sim_l <- run_fit("sim_l", FALSE, function() fit_nb(sim_spec_l(OUT), d, fitter = nb_fitter_with(character())))
write_now()
res$sim_t <- run_fit("sim_t", FALSE, function() fit_time_chain(sim_spec_t(OUT), d, chain = "iid"))
write_now()
flog("timing: wrote ", OUT_CSV, file = log_file)
