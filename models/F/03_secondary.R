# Paper F Task 11: selection audit, secondary models (preterm, sex-ratio negative control), trimester rows and the 17
# sensitivity analyses (contract papers/F/results_keys.md sections 8, 10 and 11; models/F/R/secondary_f.R).
# Run from <repo>/models. Real fits take about 44 min (Model L) and 20-45 min (Model T) each, 56 fits (60 if allcomp differs from the primary columns), so the
# run is parallel and detached (launch with PowerShell Start-Process, logs in models/F/logs/):
#   Rscript F/03_secondary.R worker      one worker process (use up to 5; glmmTMB cores 1, OMP_NUM_THREADS 1);
#                                        claims tasks through <task>.lock directories in models/F/_cache/sec/ and
#                                        checkpoints every fit to <task>.rds, so a rerun resumes
#   Rscript F/03_secondary.R assemble    after the workers: writes papers/F/output/{selection,secondary,sensitivity,
#                                        trimester}.csv and checks the contract keys
#   Rscript F/03_secondary.R unlock      clear the lock of every task without a result (only when no worker is alive)
#   Rscript F/03_secondary.R status      tasks done, running (locked), failed and still to do
#   Rscript F/03_secondary.R             serial: one worker, then assemble
# FY2020-21 (R2): the fy2021 rows carry model estimates only; their unit-month and link-unit counts are withheld.
source("common/R/load.R")
source("F/R/common_f.R")
source("F/R/perinatal.R")
source("F/R/power_f.R")
source("F/R/verdicts_f.R")
source("F/R/primary_f.R")
source("F/R/secondary_f.R")
source("D/R/contract.R")
options(glmmTMB.cores = 1L)
Sys.setenv(OMP_NUM_THREADS = "1")

mode <- { a <- commandArgs(trailingOnly = TRUE); if (length(a)) a[1] else "serial" }
cache <- SEC_CACHE
cores <- as.integer(Sys.getenv("F_SEC_CORES", unset = "1"))     # bootstrap-fallback cores of one worker
LOG <- "03_secondary.log"

load_tables <- function() list(d = read_perinatal_model("primary"), d21 = read_perinatal_model("fy2021"))

status_report <- function(tasks) {
  st <- vapply(tasks, function(t) {
    id <- sec_task_id(t)
    if (file.exists(file.path(cache, paste0(id, ".rds")))) "done"
    else if (file.exists(file.path(cache, paste0(id, ".err")))) "failed"
    else if (dir.exists(file.path(cache, paste0(id, ".lock")))) "running" else "todo"
  }, "")
  print(table(st))
  if (any(st %in% c("running", "failed"))) print(data.frame(task = vapply(tasks, sec_task_id, "")[st %in% c("running", "failed")], state = st[st %in% c("running", "failed")]))
  invisible(st)
}

public <- function(tab) {
  tab <- .redact_fy2021(tab)
  tab[, grad_par := as.character(grad_par)]
  tab[]
}

assemble <- function(tasks, d, d21) {
  a <- assemble_secondary(tasks, d, d21, cache = cache)
  dir.create(F_OUT, recursive = TRUE, showWarnings = FALSE)
  sel <- public(a$selection); sec <- public(a$secondary); sens <- public(a$sensitivity)
  prim <- data.table::fread(file.path(F_OUT, "primary_estimates.csv"))
  tri <- data.table::rbindlist(lapply(OUTS, function(o) {
    r <- trimester_rows(prim[outcome == o & model == "L"])
    r[, outcome := o]
    data.table::setcolorder(r, "outcome")
    r
  }))
  data.table::fwrite(sel, file.path(F_OUT, "selection.csv"))
  data.table::fwrite(sec, file.path(F_OUT, "secondary.csv"))
  data.table::fwrite(sens, file.path(F_OUT, "sensitivity.csv"))
  data.table::fwrite(tri, file.path(F_OUT, "trimester.csv"))
  # the entries from the written tables must equal those from the in-memory tables and equal the contract's keys
  rd <- function(f) data.table::fread(file.path(F_OUT, f), na.strings = c("", "NA"))
  ent <- secondary_entries(rd("selection.csv"), rd("secondary.csv"), rd("sensitivity.csv"))
  want <- grep("^F\\.(sel|pre|nc|sens)\\.", contract_keys(file.path(REPO_ROOT, CONTRACT_REL), prefix = "F"), value = TRUE)
  stopifnot(setequal(names(ent), want), length(ent) == length(want))
  dir.create(F_CACHE, recursive = TRUE, showWarnings = FALSE)
  saveRDS(ent, file.path(F_CACHE, "secondary_entries.rds"))
  flog("secondary: wrote selection.csv, secondary.csv, sensitivity.csv, trimester.csv and ", length(ent), " entries", file = LOG)
  invisible(list(tables = a, entries = ent))
}

if (!interactive()) {
  if (!file.exists(file.path(F_OUT, "primary_estimates.csv")))
    stop("03_secondary.R: papers/F/output/primary_estimates.csv is missing (run 02_primary.R first)", call. = FALSE)
  tb <- load_tables()
  tasks <- sec_tasks(tb$d, tb$d21)
  switch(mode,
    worker = { flog("worker ", Sys.getpid(), " start; ", length(tasks), " tasks", file = LOG)
               run_worker(tasks, tb$d, tb$d21, cache = cache, cores = cores, log_file = LOG) },
    assemble = assemble(tasks, tb$d, tb$d21),
    unlock = print(clear_stale_locks(tasks, cache)),
    status = status_report(tasks),
    serial = { run_worker(tasks, tb$d, tb$d21, cache = cache, cores = cores, log_file = LOG)
               assemble(tasks, tb$d, tb$d21) },
    stop("03_secondary.R: unknown mode ", mode, call. = FALSE))
}
