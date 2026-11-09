# Paper F: results.json in one command, from <repo>/models (cached-step pattern of models/E/run_all.R):
#   Rscript F/run_all.R --use-cache      # NEVER fits: reuse every finished step (its cache must agree with the committed
#                                        # outputs); a missing cache or output is an error; then assemble results.json
#   Rscript F/run_all.R                  # as --use-cache, except that a step with a missing cache or output is run
#                                        # (Rscript F/<script>)
#   Rscript F/run_all.R --refit          # rerun every producer step (real fits take 10 min to 4 h each), then assemble;
#                                        # for a future full rerun only
#   --out-dir=DIR                        # write results.json and provenance.csv to DIR (determinism check)
# Steps (cache models/F/_cache, git-ignored):
#   01 power plan (R6; stopped at 24 h)        -> papers/F/output/timing.csv, power.csv     -> F.timing.*, F.power.* (20)
#   02 Models L and T, verdicts (primary.rds)  -> primary_estimates.csv, verdicts.csv       -> F.l/t/h10/h11 (72)
#   03 secondary analyses (sec/*.rds)          -> selection, secondary, sensitivity, trimester .csv -> F.sel/pre/nc/sens (118)
#   04 results assembly (this task)            -> panel keys (82), reading rules (4), conclusion sentence (1),
#                                                 papers/F/results.json (297 = papers/F/results_keys.md) and
#                                                 papers/F/output/provenance.csv
# Seed: SEED_F (models/F/R/common_f.R).

source("common/R/load.R")
source("F/R/common_f.R")
source("F/04_results.R")

invisible(results_main(commandArgs(trailingOnly = TRUE), default_mode = "default"))
