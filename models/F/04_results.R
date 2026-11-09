# Paper F Task 12: results assembly (contract papers/F/results_keys.md, 297 keys). Resolves the producer steps 01-03 from
# their caches and committed outputs (resolve_f_step() in models/F/R/results_f.R), adds the section 1-3 panel keys
# (panel_keys_f(): national keys from the official All_India series, ruling I1), the reading rules and the section 12
# conclusion sentence, stops unless the key set equals the contract, and writes papers/F/results.json and
# papers/F/output/provenance.csv. NO MODEL IS EVER FITTED HERE: --use-cache stops on a missing cache.
#
# Run from <repo>/models, normally through F/run_all.R:
#   Rscript F/04_results.R --use-cache [--out-dir=DIR]
# --out-dir=DIR  write results.json and provenance.csv to DIR instead of papers/F and papers/F/output (determinism check)

if (!exists("MODELS_ROOT")) source("common/R/load.R")
if (!exists("F_DIR")) source(file.path(MODELS_ROOT, "F", "R", "common_f.R"))
source(file.path(MODELS_ROOT, "F", "R", "results_f.R"))

run_f_results <- function(mode = "use_cache", out_dir = NULL, defs = f_step_defs()) {
  t0 <- Sys.time()
  flog(sprintf("04_results: mode %s, out_dir %s", mode, if (is.null(out_dir)) "(repository)" else out_dir), file = "results.log")
  steps <- lapply(defs, resolve_f_step, mode = mode)
  for (s in steps) flog(sprintf("step %s: %s (%d keys from %s)", s$name, s$status, length(s$entries), s$rds), file = "results.log")
  reading <- list(name = "reading", status = "derived", script = "R/results_f.R",
                  entries = reading_rules_f(steps$primary$data, steps$secondary$data$selection, steps$secondary$data$sensitivity))
  paths <- f_output_paths(out_dir)
  r <- write_f_results(c(steps, list(reading = reading)), panel = panel_keys_f(), out_json = paths$json, out_prov = paths$prov,
                       dropped = dropped_outcomes_f())
  flog(sprintf("04_results: wrote %s (%d keys) and %s in %.1f s", paths$json, length(r$entries), paths$prov,
               as.numeric(difftime(Sys.time(), t0, units = "secs"))), file = "results.log")
  flog("conclusion: ", r$entries[["F.abstract.conclusion_sentence"]]$display, file = "results.log")
  invisible(c(r, list(steps = steps)))
}

results_main <- function(args = commandArgs(trailingOnly = TRUE), default_mode = "use_cache") {
  s <- f_results_settings(args, default_mode = default_mode)
  invisible(run_f_results(mode = s$mode, out_dir = s$out_dir))
}

if (sys.nframe() == 0L) invisible(results_main())
