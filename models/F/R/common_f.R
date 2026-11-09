# Paper F (El Nino, local heat and drought, and perinatal outcomes; HMIS link-unit-month panel): shared settings.
# Sourced from <repo>/models after common/R/load.R. models/common/R and Paper E's models/E/R are frozen and are
# sourced read-only: Paper F adds functions in models/F/R and calls the common and Paper E functions unchanged.

if (!exists("MODELS_ROOT")) source("common/R/load.R")
for (f in c("common_e.R", "monthly.R", "secondary.R", "verdicts.R", "power.R"))
  source(file.path(MODELS_ROOT, "E", "R", f), local = globalenv())

F_DIR <- file.path(MODELS_ROOT, "F")
F_CACHE <- file.path(F_DIR, "_cache")          # git-ignored
F_LOGS <- file.path(F_DIR, "logs")             # git-ignored
PAPER_F <- file.path(REPO_ROOT, "papers", "F")
F_OUT <- file.path(PAPER_F, "output")
SEED_F <- 20261026L                            # resample i of any bootstrap uses SEED_F + i - 1 (contract)

# rr_ci display (contract amendment 2026-11-09, after results): every RR and OR is shown to 3 decimals (display only;
# the common fmt_ci() and Paper E are untouched).
RR_DIGITS_F <- 3L
fmt_rr_ci <- function(est, lo, hi) fmt_ci(est, lo, hi, digits = RR_DIGITS_F)

OUTS <- c("sb", "lbw")                         # H10 stillbirth, H11 low birth weight
DENOM <- c(sb = "log_tb", lbw = "log_wt")      # offset: log total births, log weighed births

PERINATAL_MODEL_CSV <- file.path(REPO_ROOT, "data", "derived", "hmis", "perinatal_model.csv.gz")

# Timestamped message, echoed and appended to models/F/logs/<file> (an absolute `file` is used as given).
flog <- function(..., file = "f_run.log") {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), paste0(...))
  message(msg)
  path <- if (grepl("^([A-Za-z]:)?[/\\\\]", file)) file else file.path(F_LOGS, file)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  cat(msg, "\n", file = path, append = TRUE, sep = "")
  invisible(msg)
}

# The perinatal model table (pipeline/hmis/perinatal_model_table.py). window "primary": the 95 months April 2012 to
# February 2020 (in_primary == 1); "fy2021": every row, April 2012 to March 2021 (the FY2020-21 sensitivity). Missing
# values stay NA. Factors: unit_id (= link_id); state_unit; moy (levels 1..12); ym_f (levels = every ym of the window
# in time order); national (one level, the grouping of the AR(1) time effect); state_ym (the state-month random
# effect of Model L); unit_era (unit_id x era_e2, levels "<unit>:<0|1>"; used only by the era_int sensitivity).
read_perinatal_model <- function(window = c("primary", "fy2021"), path = PERINATAL_MODEL_CSV) {
  window <- match.arg(window)
  # fread reads .gz only with R.utils (not in the renv lock): decompress through a gzfile connection instead
  d <- if (grepl("[.]gz$", path)) {
    con <- gzfile(path)
    lines <- tryCatch(readLines(con, warn = FALSE), finally = close(con))
    data.table::fread(text = lines, na.strings = c("", "NA", "NaN"))
  } else {
    data.table::fread(path, na.strings = c("", "NA", "NaN"))
  }
  if (window == "primary") d <- d[in_primary == 1L]
  if (!nrow(d)) stop("read_perinatal_model: no rows in window ", window, " of ", path, call. = FALSE)
  d[, unit_id := factor(link_id)]
  d[, state_unit := factor(state_unit)]
  d[, state_ym := factor(state_ym)]
  d[, moy := factor(moy, levels = 1:12)]
  d[, ym_f := factor(ym, levels = sort(unique(ym)))]
  d[, national := factor(rep("IN", .N))]
  d[, unit_era := interaction(unit_id, era_e2, sep = ":", drop = TRUE, lex.order = TRUE)]
  data.table::setorder(d, unit_id, ym)
  d[]
}

# Rows of the analysis of `out`: the rows with excluded_<out> == 1 (gate exclusions) and small_denom_<out> == 1
# (denominator too small) are removed. NA in either flag does not remove a row (the gates write 0/1).
outcome_rows <- function(d, out) {
  ex <- paste0("excluded_", out)
  sm <- paste0("small_denom_", out)
  absent <- setdiff(c(ex, sm), names(d))
  if (length(absent)) stop("outcome_rows: missing column(s): ", paste(absent, collapse = ", "), call. = FALSE)
  d[!(d[[ex]] %in% 1L) & !(d[[sm]] %in% 1L)]
}
