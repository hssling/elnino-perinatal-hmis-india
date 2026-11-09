# Paper F Task 9: power simulation on the simplified model (R6). Run from <repo>/models:   Rscript F/01_power.R
# Refuses to start unless the contract papers/F/results_keys.md is committed (clean in git) and timing.csv exists.
# Plans the run with power_plan() from timing.csv. If the plan is "stop" (projected over 24 h after both R6
# reductions), NOTHING is simulated or fitted: the script writes the plan rows, saves the plan and exits. Otherwise it
# runs the six tests on the plan's grid. It never fits a model with a tested exposure to the real outcome.
source("common/R/load.R")
source("F/R/common_f.R")
source("F/R/perinatal.R")
source("F/R/power_f.R")

log_file <- "power.log"
CONTRACT <- "papers/F/results_keys.md"
TIMING_CSV <- file.path(F_OUT, "timing.csv")
POWER_CSV <- file.path(F_OUT, "power.csv")
POWER_RDS <- file.path(F_CACHE, "power.rds")

git <- function(...) suppressWarnings(system2("git", c("-C", shQuote(REPO_ROOT), ...), stdout = TRUE, stderr = TRUE))
tracked <- length(git("ls-files", "--error-unmatch", CONTRACT)) > 0L && is.null(attr(git("ls-files", "--error-unmatch", CONTRACT), "status"))
dirty <- length(git("status", "--porcelain", "--", CONTRACT)) > 0L
if (!tracked || dirty) stop("01_power.R: ", CONTRACT, " must be committed and unmodified before the power run (R6)", call. = FALSE)
if (!file.exists(TIMING_CSV)) stop("01_power.R: ", TIMING_CSV, " is missing (run 00_timing.R first)", call. = FALSE)

cores <- as.integer(Sys.getenv("F_POWER_CORES", unset = max(1L, parallel::detectCores(logical = FALSE) - 1L)))
timing <- data.table::fread(TIMING_CSV)
plan <- power_plan(timing, n_tests = nrow(TESTS), cores = cores)
dir.create(F_CACHE, recursive = TRUE, showWarnings = FALSE)
dir.create(F_OUT, recursive = TRUE, showWarnings = FALSE)
flog("power: plan step ", plan$step, ", n_sim ", plan$n_sim, ", projected ", sprintf("%.1f", plan$projected_h),
     " h on ", cores, " workers", file = log_file)

grid_of <- function(model) plan$grid[[model]]

if (plan$step == "stop") {
  rows <- data.table::rbindlist(lapply(seq_len(nrow(TESTS)), function(i) {
    data.table::data.table(test_id = TESTS$test_id[i], rr = grid_of(TESTS$model[i]), n_ok = NA_integer_,
                           power = NA_real_, mean_rr = NA_real_, n_sim = plan$n_sim, step = "stop",
                           projected_h = plan$projected_h, cores = cores)
  }))
  data.table::fwrite(rows, POWER_CSV)
  saveRDS(list(plan = plan, cores = cores, timing = timing, mde = NULL), POWER_RDS)
  msg <- sprintf(paste0("STOP: projected %.1f h (%d simulations, grid %s, %d workers) exceeds 24 h after both R6 reductions. ",
                        "Nothing was simulated. Report to the author before any run (R6)."),
                 plan$projected_h, plan$n_sim, paste(GRID_REDUCED, collapse = ", "), cores)
  flog(msg, file = log_file)
  cat(msg, "\n")
  quit(save = "no", status = 0L)
}

# Run: one data set per outcome (gate and small-denominator rows removed), six tests, power.csv written after each.
dat <- lapply(stats::setNames(OUTS, OUTS), function(o) outcome_rows(read_perinatal_model("primary"), o))
res <- list()
t0 <- proc.time()[["elapsed"]]
for (i in seq_len(nrow(TESTS))) {
  tr <- TESTS[i]
  flog("power: ", tr$test_id, " (", tr$model, " ", tr$summary, ") start", file = log_file)
  tab <- simulate_power_f(dat[[tr$outcome]], tr$test_id, grid_of(tr$model), n_sim = plan$n_sim, cores = cores)
  tab[, `:=`(n_sim = plan$n_sim, step = plan$step, projected_h = plan$projected_h, cores = cores)]
  res[[tr$test_id]] <- tab
  data.table::fwrite(data.table::rbindlist(res), POWER_CSV)
  flog("power: ", tr$test_id, " done; MDE ", mde_f(tab)$display, file = log_file)
}
actual_h <- (proc.time()[["elapsed"]] - t0) / 3600
mdes <- lapply(res, mde_f)
saveRDS(list(plan = plan, cores = cores, timing = timing, power = data.table::rbindlist(res), mde = mdes,
             actual_h = actual_h), POWER_RDS)
flog("power: finished in ", sprintf("%.1f", actual_h), " h (projected ", sprintf("%.1f", plan$projected_h), " h)",
     file = log_file)
