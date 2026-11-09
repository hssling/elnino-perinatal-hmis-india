# Paper F Task 10: primary Model L and Model T, episode fits, bootstrap fallbacks, the six-test Holm family and the
# verdicts (contract papers/F/results_keys.md sections 5-7). Run from <repo>/models, detached (it takes hours):
#   Rscript F/02_primary.R
# Refuses to start unless the contract and papers/F/output/power.csv (the R6 stop plan) are committed and unmodified.
# Each fit is checkpointed to models/F/_cache/{l,t}_<outcome>.rds, so a restart resumes after the last finished fit.
# Writes papers/F/output/primary_estimates.csv and verdicts.csv, and models/F/_cache/primary.rds.
source("common/R/load.R")
source("F/R/common_f.R")
source("F/R/perinatal.R")
source("F/R/power_f.R")
source("F/R/verdicts_f.R")
source("F/R/primary_f.R")
res <- run_primary()
print(res$tests[, .(test_id, outcome, model, summary, rr, lo, hi, p, p_holm, lead_lo, lead_hi, ep1415, ep1819, verdict)])
print(res$overall)
