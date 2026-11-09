# Paper F Task 12: results assembly (contract papers/F/results_keys.md, 297 keys; controller rulings I1 and I2 of
# 2026-11-08, the rr_ci display amendment of 2026-11-09 and the R6 stop of 2026-11-08). Used by models/F/04_results.R and
# models/F/run_all.R; the pure functions are driven by test-f-results.R with synthetic inputs. Sourced after
# common/R/load.R and the Paper F helpers. No model is fitted here, ever: a missing cache is an error.
# Non-ASCII characters are written as escapes, never as literals.
#
# Steps and the keys they own (f_key_step(); every contract key has exactly one owner):
#   panel      panel_keys_f() here: F.panel, F.units, F.status_date, F.national, F.d24, F.break2017, F.exposure (82)
#   power      00_timing.R / 01_power.R -> timing.csv, power.csv; power_keys_f() here: F.timing, F.power (20)
#   primary    02_primary.R -> primary_estimates.csv, verdicts.csv, cache primary.rds; primary_entries(): F.l, F.t,
#              F.h10*, F.h11* (72)
#   secondary  03_secondary.R -> selection.csv, secondary.csv, sensitivity.csv, trimester.csv; secondary_entries():
#              F.sel, F.pre, F.nc, F.sens (118), rebuilt from the committed CSVs; the cached entries
#              (secondary_entries.rds, refreshed by 03_secondary.R assemble) must agree in value, description and display
#   reading    reading_rules_f() here from the primary table, the selection audit and the sensitivity table: F.read (4)
#   conclusion conclusion_sentence_f() here: F.abstract.conclusion_sentence (1)
#
# Step resolution (resolve_f_step()):
#   use_cache  never fits: a step whose cache (models/F/_cache) and outputs exist is read from them after checking that
#              the cache agrees with the committed CSVs; a missing cache or output is an error.
#   default    as use_cache, except that a step with a missing cache or output is run (Rscript F/<script>).
#   refit      every step is rerun (Rscript F/<script>); for a future full rerun only.
# Hand-offs: papers/F/results.json (Paper 0 schema; keys in C-locale order) and papers/F/output/provenance.csv (item,
# value, note): results_code_commit (last commit touching the code paths), results_code_dirty (uncommitted changes to
# TRACKED files of those paths: untracked files never count, so the cached rerun is stable), seed, n_keys, input,
# step, cache and output hashes. No time stamps, so two runs from one repository state give identical bytes.

if (!exists("MODELS_ROOT")) source("common/R/load.R")
if (!exists("F_DIR")) source(file.path(MODELS_ROOT, "F", "R", "common_f.R"))
for (.f in c("perinatal.R", "power_f.R", "verdicts_f.R", "primary_f.R", "secondary_f.R")) {
  .probe <- c(perinatal.R = "TESTS", power_f.R = "power_plan", verdicts_f.R = "verdict_test", primary_f.R = "primary_entries",
              secondary_f.R = "secondary_entries")[[.f]]
  if (!exists(.probe)) source(file.path(MODELS_ROOT, "F", "R", .f))
}
if (!exists("contract_keys")) source(file.path(MODELS_ROOT, "D", "R", "contract.R"))      # read-only

RES_SCRIPT_F <- "models/F/04_results.R"
TIMING_SCRIPT_F <- "models/F/00_timing.R"
POWER_SCRIPT_F <- "models/F/01_power.R"
F_CONTRACT <- file.path(PAPER_F, "results_keys.md")
HMIS_DERIVED <- file.path(REPO_ROOT, "data", "derived", "hmis")
LINK_UNITS_CSV <- file.path(REPO_ROOT, "pipeline", "reference", "hmis_link_units.csv")
UNITS_REPORT_MD <- file.path(HMIS_DERIVED, "perinatal_units_report.md")
FUZZY_CSV <- file.path(HMIS_DERIVED, "perinatal_fuzzy_matches.csv")
NATIONAL_MONTH_CSV <- file.path(HMIS_DERIVED, "_parts_f", "national_month.csv.gz")
BREAK_RATIO_CSV <- file.path(HMIS_DERIVED, "perinatal_break_ratio_2017.csv")
F_CODE_PATHS <- c("models/F", "models/common/R", "models/E/R", "pipeline/hmis", "papers/F/results_keys.md")
F_PROV_INPUTS <- c("data/derived/hmis/perinatal_unit_month.csv.gz", "data/derived/hmis/perinatal_model.csv.gz",
                   "data/derived/hmis/perinatal_release_panel.csv.gz", "data/derived/hmis/_parts_f/national_month.csv.gz",
                   "pipeline/reference/hmis_link_units.csv", "pipeline/reference/hmis_perinatal_crosswalk.csv",
                   "data/derived/hmis/perinatal_gate_summary.csv", "data/derived/hmis/perinatal_break_ratio_2017.csv",
                   "data/derived/hmis/perinatal_fuzzy_matches.csv", "data/derived/hmis/perinatal_units_report.md")
PRIMARY_FYS_F <- c("2012-13", "2013-14", "2014-15", "2015-16", "2016-17", "2017-18", "2018-19", "2019-20")
FY21_NOTE <- "FY2020-21 was analysed as a sensitivity analysis only and contributes no descriptive value here"
CONCLUSION_CAUSAL_F <- "\\b(cause[sd]?|causing|effect of|impacts?|led to|reduces?|reduced|kills?)\\b"
# The fixed phrases of the contract's section 12 template (test-f-results.R checks each is verbatim in the contract).
CONCLUSION_PHRASES_F <- c(
  lead = "In this link-unit-month analysis of routine HMIS data from India, April 2012 to February 2020, the results were ",
  h10 = " higher stillbirth rates after third-trimester heat, full-gestation rainfall deficit or an El Ni\u00f1o gestation",
  h11 = " a higher low birth weight share among weighed newborns after full-gestation heat, rainfall deficit or an El Ni\u00f1o gestation")
POWER_STEP_DISPLAY <- c("200" = "200", "100" = "100", "100_reduced_grid" = "100 with reduced grid", "stop" = "stop")
NOT_APPLICABLE_SELECTION <- "not applicable (heat test not consistent with)"
NOT_APPLICABLE_NATIONAL <- "not applicable (El Ni\u00f1o test not consistent with)"

.res_f <- function(value, display, description, script = RES_SCRIPT_F)
  res_entry(value, enc2utf8(display), script, enc2utf8(description))

# The display of a power step code (power.csv writes "100_reduced_grid").
power_step_display <- function(step) {
  if (length(step) != 1L || !step %in% names(POWER_STEP_DISPLAY)) stop("power_step_display: unknown power step ", step, call. = FALSE)
  unname(POWER_STEP_DISPLAY[[step]])
}

# ------------------------------------------------------------------ contract: owners and declared counts

F_KEY_OWNERS <- list(
  panel = function(k) grepl("^F\\.(panel|units|status_date|national|d24|break2017|exposure)\\.", k),
  power = function(k) grepl("^F\\.(timing|power)\\.", k),
  primary = function(k) grepl("^F\\.(l|t)\\.", k) | grepl("^F\\.h1[01][a-c]?\\.", k),
  secondary = function(k) grepl("^F\\.(sel|pre|nc|sens)\\.", k),
  reading = function(k) grepl("^F\\.read\\.", k),
  conclusion = function(k) k == "F.abstract.conclusion_sentence")

f_key_step <- function(keys) {
  m <- do.call(cbind, lapply(F_KEY_OWNERS, function(f) f(keys)))
  n <- rowSums(m)
  if (any(n != 1L)) stop("f_key_step: key(s) with no owner or several owners: ", paste(head(keys[n != 1L], 10), collapse = ", "),
                         call. = FALSE)
  names(F_KEY_OWNERS)[max.col(m, ties.method = "first")]
}

# Declared "(N keys)" per numbered section against the keys its table rows list; attr declared_total = the intro's total.
contract_section_counts_f <- function(path = F_CONTRACT) {
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  head_re <- "^## ([0-9]+)\\. .*\\(([0-9,]+) keys?\\)\\s*$"
  h <- grep(head_re, lines)
  nxt <- grep("^## ", lines)
  rows <- lapply(seq_along(h), function(j) {
    stop_at <- min(c(nxt[nxt > h[j]] - 1L, length(lines)))
    seg <- lines[(h[j] + 1L):stop_at]
    r <- grep("^\\|\\s*`F\\.", seg, value = TRUE)
    first <- vapply(strsplit(r, "|", fixed = TRUE), function(x) x[2], character(1))
    toks <- gsub("`", "", unlist(regmatches(first, gregexpr("`F\\.[^`]+`", first))))
    keys <- unique(unlist(lapply(toks, expand_keys)))
    data.table::data.table(section = sub(head_re, "\\1", lines[h[j]]), declared = as.integer(gsub(",", "", sub(head_re, "\\2", lines[h[j]]))),
                           found = length(keys), keys = list(keys))
  })
  out <- data.table::rbindlist(rows)
  intro <- grep("^This contract lists", lines, value = TRUE)[1]
  tot <- regmatches(intro, regexpr("\\(([0-9,]+) keys\\)", intro))
  attr(out, "declared_total") <- if (length(tot)) as.integer(gsub("[^0-9]", "", tot)) else NA_integer_
  out
}

assert_contract_counts_f <- function(path = F_CONTRACT) {
  cnt <- contract_section_counts_f(path)
  bad <- cnt[declared != found]
  if (nrow(bad)) stop(paste(sprintf("contract: section %s declares %d keys but lists %d", bad$section, bad$declared, bad$found),
                            collapse = "; "), call. = FALSE)
  all_keys <- unlist(cnt$keys)
  if (anyDuplicated(all_keys)) stop("contract: key(s) listed in two sections: ", paste(unique(all_keys[duplicated(all_keys)]), collapse = ", "),
                                    call. = FALSE)
  want <- contract_keys(path, prefix = "F")
  tot <- attr(cnt, "declared_total")
  if (!identical(tot, length(want)) || sum(cnt$found) != length(want))
    stop(sprintf("contract: declares %s keys, the sections list %d and the parser finds %d", tot, sum(cnt$found), length(want)), call. = FALSE)
  invisible(cnt)
}

# ------------------------------------------------------------------ helpers

f_git <- function(args) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(REPO_ROOT), args), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) stop("git ", paste(args, collapse = " "), " failed: ", paste(out, collapse = "; "), call. = FALSE)
  out
}

# git status arguments of the dirty flag: tracked files only (an untracked file never makes the tree dirty).
f_status_args <- function(paths) c("status", "--porcelain", "--untracked-files=no", "--", paths)

# sha256 of a file: text files after CRLF -> LF (git's autocrlf checkout of a committed LF file), gz files as they are.
f_sha256_lf <- function(path) {
  b <- readBin(path, "raw", file.size(path))
  if (!grepl("[.]gz$", path) && length(b) > 1L) {
    cr <- which(b == as.raw(13L))
    cr <- cr[cr < length(b) & b[cr + 1L] == as.raw(10L)]
    if (length(cr)) b <- b[-cr]
  }
  cli::hash_raw_sha256(b)
}

f_table_sha <- function(x) {
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f))
  data.table::fwrite(x, f, eol = "\n")
  f_sha256_lf(f)
}

f_rel <- function(path) {
  p <- normalizePath(path, winslash = "/", mustWork = FALSE)
  root <- paste0(normalizePath(REPO_ROOT, winslash = "/"), "/")
  ifelse(startsWith(p, root), substring(p, nchar(root) + 1L), p)
}

# "committed, clean", "uncommitted changes", "untracked" (also git-ignored) or "outside the repository".
f_git_state <- function(path, git_fun = f_git) {
  rel <- f_rel(path)
  if (grepl("^([A-Za-z]:)?/", rel)) return("outside the repository")
  if (!length(git_fun(c("ls-files", "--", rel)))) return("untracked")
  if (length(git_fun(c("status", "--porcelain", "--untracked-files=no", "--", rel)))) return("uncommitted changes")
  "committed, clean"
}

date_display_f <- function(x) {
  d <- as.Date(as.character(x))
  if (anyNA(d)) stop("date_display_f: not a date: ", paste(x[is.na(d)], collapse = ", "), call. = FALSE)
  paste(as.integer(format(d, "%d")), month.name[as.integer(format(d, "%m"))], format(d, "%Y"))
}

# "2019-20", 3 -> "March 2020".
.fy_month_label <- function(fy, month) paste(month.name[month], as.integer(substr(fy, 1, 4)) + as.integer(month < 4L))

# Selected columns of a (possibly gzipped) csv; fread reads .gz only with R.utils (not in the renv lock).
.read_cols <- function(path, cols = NULL) {
  cc <- list(character = intersect(c("status_date_min", "status_date_max", "fy", "dropped"), if (is.null(cols)) character() else cols))
  if (grepl("[.]gz$", path)) {
    con <- gzfile(path)
    lines <- tryCatch(readLines(con, warn = FALSE), finally = close(con))
    data.table::fread(text = lines, select = cols, na.strings = c("", "NA", "NaN"), colClasses = if (length(cc$character)) cc)
  } else data.table::fread(path, select = cols, na.strings = c("", "NA", "NaN"), colClasses = if (length(cc$character)) cc)
}

.sd_n <- function(x) { x <- x[!is.na(x)]; if (length(x) > 1L) stats::sd(x) else NA_real_ }
.sd_within <- function(x, g) {
  ok <- !is.na(x)
  r <- x[ok] - stats::ave(x[ok], g[ok])
  s <- if (length(r) > 1L) stats::sd(r) else NA_real_
  if (!is.na(s) && abs(s) < 1e-10) 0 else s                    # national ENSO terms: exactly 0 up to rounding
}

# ------------------------------------------------------------------ sections 1 and 3: panel, units, exposure

exposure_keys_f <- function(p, script = RES_SCRIPT_F, src = "the primary window") {
  E <- list()
  put <- function(k, value, display, description) E[[k]] <<- .res_f(value, display, description, script)
  tg <- rowMeans(cbind(p$tmax_t3, p$tmax_t2, p$tmax_t1))
  sg <- rowMeans(cbind(p$spi3_dry_l0, p$spi3_dry_l3, p$spi3_dry_l6))
  terms <- list(tmax_t3 = p$tmax_t3, tmax_gest = tg, spi3_dry_gest = sg, en_gest = p$en_gest, ln_gest = p$ln_gest)
  what <- c(tmax_t3 = "third-trimester mean Tmax anomaly (deg C)", tmax_gest = "mean of tmax_t3, tmax_t2, tmax_t1 (deg C; NaN if any stratum is NaN)",
            spi3_dry_gest = "mean of spi3_dry_l0, spi3_dry_l3, spi3_dry_l6 (SPI; NaN if any stratum is NaN)",
            en_gest = "gestation-mean max(ONI, 0) (deg C)", ln_gest = "gestation-mean min(ONI, 0) (deg C)")
  for (t in names(terms)) {
    x <- terms[[t]]
    s <- .sd_n(x); w <- .sd_within(x, p$ym)
    put(sprintf("F.exposure.%s.sd", t), s, fmt_num(s, 3),
        sprintf("SD (n - 1) of %s, %s, across the %d link-unit-months of %s with the term non-missing; full value %s",
                t, what[[t]], sum(!is.na(x)), src, format(signif(s, 10))))
    put(sprintf("F.exposure.%s.sd_within", t), w, fmt_num(w, 3),
        sprintf("SD of %s after removing its year-month mean (within-month, across link units; 0 for the national ENSO terms), %d link-unit-months; full value %s",
                t, sum(!is.na(x)), format(signif(w, 10))))
  }
  m <- unique(p[!is.na(en_gest), .(ym, en_gest)])
  nm <- data.table::uniqueN(m$ym); ne <- data.table::uniqueN(m[en_gest > 0]$ym)
  put("F.exposure.n_months", nm, fmt_int(nm), sprintf("Primary birth months with a gestation-mean ONI term (en_gest non-missing), %s", src))
  put("F.exposure.n_en_months", ne, fmt_int(ne), sprintf("Primary birth months with en_gest > 0, %s", src))
  E
}

# The 82 keys of sections 1 to 3 (F.panel, F.units, F.status_date, F.national, F.d24, F.break2017, F.exposure).
panel_keys_f <- function(model_csv = PERINATAL_MODEL_CSV, gate_csv = GATE_SUMMARY_F, link_csv = LINK_UNITS_CSV,
                         units_report = UNITS_REPORT_MD, fuzzy_csv = FUZZY_CSV, national_csv = NATIONAL_MONTH_CSV,
                         break_csv = BREAK_RATIO_CSV, min_link_units = 600L, script = RES_SCRIPT_F) {
  E <- list()
  put <- function(k, value, display, description) E[[k]] <<- .res_f(value, display, description, script)
  cols <- c("link_id", "state_unit", "ym", "in_primary", "status_date_min", "status_date_max", "single_district", "sb", "lbw",
            paste0(c("excluded_", "small_denom_"), rep(OUTS, each = 2)), "tmax_t3", "tmax_t2", "tmax_t1", "spi3_dry_l0", "spi3_dry_l3",
            "spi3_dry_l6", "en_gest", "ln_gest")
  d <- .read_cols(model_csv, cols)
  p <- d[in_primary == 1L]
  if (!nrow(p)) stop("panel_keys_f: no primary-window rows in ", model_csv, call. = FALSE)
  src <- sprintf("%s (in_primary == 1; April 2012 to February 2020)", f_rel(model_csv))
  note <- paste0(". ", FY21_NOTE)
  nl <- data.table::uniqueN(p$link_id); nmo <- data.table::uniqueN(p$ym); nst <- data.table::uniqueN(p$state_unit)
  put("F.panel.n_link_units", nl, fmt_int(nl), sprintf("Distinct link_id in %s%s", src, note))
  put("F.panel.n_unit_months", nrow(p), fmt_int(nrow(p)), sprintf("Link-unit-months (rows, whatever the outcome values) in %s%s", src, note))
  put("F.panel.n_months", nmo, fmt_int(nmo), sprintf("Distinct birth months (ym) in %s%s", src, note))
  put("F.panel.n_states", nst, fmt_int(nst), sprintf("State units with at least one link unit in %s%s", src, note))
  g <- data.table::fread(gate_csv, colClasses = list(character = "dropped"))[scope == "primary"]
  for (o in OUTS) {
    x <- outcome_rows(p, o)
    nv <- sum(!is.na(x[[o]]))
    put(sprintf("F.panel.%s.n_valid", o), nv, fmt_int(nv),
        sprintf("Primary-window unit-months entering the %s model (outcome_rows() on the 95-month model table: non-missing %s, excluded_%s == 0, small_denom_%s == 0); %s%s",
                o, o, o, o, src, note))
    r <- g[variable == o]
    if (nrow(r) != 1L) stop(sprintf("panel_keys_f: %s has %d primary rows for %s", f_rel(gate_csv), nrow(r), o), call. = FALSE)
    ex <- as.integer(r$excluded_units)
    put(sprintf("F.panel.%s.n_units_excluded", o), ex, fmt_int(ex),
        sprintf("Link units excluded from the %s primary model (more than 20%% of months gate-masked); %s, scope primary%s", o, f_rel(gate_csv), note))
    put(sprintf("F.panel.%s.share_masked", o), r$masked_share_window, fmt_pct(r$masked_share_window, 2),
        sprintf("Gate-masked share of the %s unit-months that had a value, over the 95 primary months (masked_share_window %s); %s, scope primary%s",
                o, format(signif(r$masked_share_window, 6)), f_rel(gate_csv), note))
  }
  lk <- data.table::fread(link_csv)
  n_link <- data.table::uniqueN(lk[!is.na(link_id) & nzchar(link_id)]$link_id)
  n_gadm <- data.table::uniqueN(lk[kind == "gadm"]$region_id)
  if (n_link < min_link_units) stop(sprintf("panel_keys_f: fewer than %d link units (%d)", min_link_units, n_link), call. = FALSE)
  rep <- paste(readLines(units_report, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  m <- regmatches(rep, regexec("manual/carve_out/unmatched ([0-9]+) of ([0-9]+) = ([0-9.]+)", rep))[[1]]
  if (length(m) != 4L) stop("panel_keys_f: the R3 line (manual/carve_out/unmatched N of M = share) is not in ", f_rel(units_report), call. = FALSE)
  n_manual <- as.integer(m[2]); n_names <- as.integer(m[3]); share <- n_manual / n_names
  if (share > 0.10) stop(sprintf("panel_keys_f: R3 manual-review share %.4f exceeds 0.10", share), call. = FALSE)
  fz <- data.table::fread(fuzzy_csv)
  n_fuzzy <- sum(vapply(strsplit(fz$fys, "|", fixed = TRUE), function(x) any(x %in% PRIMARY_FYS_F), NA))
  n_single <- data.table::uniqueN(p[single_district == 1L]$link_id)
  put("F.units.n_link", n_link, fmt_int(n_link), sprintf("Link units: distinct link_id of %s (minimum %d); spec 3.4%s", f_rel(link_csv), min_link_units, note))
  put("F.units.n_single", n_single, fmt_int(n_single),
      sprintf("Link units with exactly one GADM district and one HMIS district in every primary FY (single_district == 1 in %s)%s", src, note))
  put("F.units.n_hmis_names", n_names, fmt_int(n_names),
      sprintf("Distinct FY2012-13 to 2019-20 state x normalised HMIS names (R3 line of %s)%s", f_rel(units_report), note))
  put("F.units.n_gadm", n_gadm, fmt_int(n_gadm), sprintf("GADM 4.1 districts in link units (distinct region_id of kind gadm in %s)%s", f_rel(link_csv), note))
  put("F.units.n_fuzzy", n_fuzzy, fmt_int(n_fuzzy),
      sprintf("Accepted fuzzy matches (rows of %s whose fys include a FY2012-13 to 2019-20 year)%s", f_rel(fuzzy_csv), note))
  put("F.units.n_manual", n_manual, fmt_int(n_manual),
      sprintf("Hand-assigned names (manual, carve_out, unmatched) counted by the R3 guard (%s)%s", f_rel(units_report), note))
  put("F.units.manual_share", share, fmt_pct(share, 1),
      sprintf("R3 guard share n_manual / n_hmis_names = %d / %d = %s (limit 0.10)%s", n_manual, n_names, format(signif(share, 6)), note))
  dmin <- min(as.Date(as.character(p$status_date_min)), na.rm = TRUE)
  dmax <- max(as.Date(as.character(p$status_date_max)), na.rm = TRUE)
  put("F.status_date.min", as.character(dmin), date_display_f(dmin),
      sprintf("Earliest status_date_min over %s (HMIS values are provisional as of their status date)", src))
  put("F.status_date.max", as.character(dmax), date_display_f(dmax), sprintf("Latest status_date_max over %s", src))
  E <- c(E, exposure_keys_f(p, script, src), national_keys_f(national_csv, break_csv, script))
  E[order(names(E), method = "radix")]
}

# ------------------------------------------------------------------ section 2: national descriptives (ruling I1)

fy_key <- function(fy) paste0("fy", substr(fy, 3, 4), substr(fy, 6, 7))

NATIONAL_RATES <- list(
  sbr = list(cols = c("sb", "lb"), num = function(w) w$sb, den = function(w) w$lb + w$sb, scale = 1000,
             fmt = function(x) fmt_num(x, 1), what = "Stillbirths per 1,000 total births (sb / (lb + sb) x 1,000)"),
  lbw_share = list(cols = c("lbw", "wt"), num = function(w) w$lbw, den = function(w) w$wt, scale = 1,
                   fmt = function(x) fmt_pct(x, 1), what = "LBW share of newborns weighed (lbw / wt)"),
  wt_cov = list(cols = c("wt", "lb"), num = function(w) w$wt, den = function(w) w$lb, scale = 1,
                fmt = function(x) fmt_pct(x, 0), what = "Weighing coverage, newborns weighed per live birth (wt / lb)"),
  inst_share = list(cols = c("inst", "home"), num = function(w) w$inst, den = function(w) w$inst + w$home, scale = 1,
                    fmt = function(x) fmt_pct(x, 0), what = "Institutional share of deliveries (inst / (inst + home))"),
  tb_per_delivery = list(cols = c("lb", "sb", "inst", "home"), num = function(w) w$lb + w$sb, den = function(w) w$inst + w$home, scale = 1,
                         fmt = function(x) fmt_num(x, 2), what = "Total births per delivery ((lb + sb) / (inst + home))"))
NATIONAL_D24 <- list(cols = c("d24", "lb"), num = function(w) w$d24, den = function(w) w$lb, scale = 1000,
                     fmt = function(x) fmt_num(x, 2),
                     what = "Deaths within 24 h per 1,000 live births (sum of d24 over sum of lb of the months with a reported d24; descriptive only, R4)")

# The 51 keys of section 2 from the national month table (the official All_India series net of the M/O rows, Paper E F39:
# a blank M/O cell counts as zero in that series; ruling I1) and the 2017 break ratios. Each FY rate is a ratio of sums
# over the FY's months in which every count of the rate is non-missing; April 2012 to February 2020 only.
national_keys_f <- function(national_csv = NATIONAL_MONTH_CSV, break_csv = BREAK_RATIO_CSV, script = RES_SCRIPT_F) {
  E <- list()
  put <- function(k, value, display, description) E[[k]] <<- .res_f(value, display, description, script)
  nat <- .read_cols(national_csv, c("fy", "month", "indicator", "national"))
  nat <- nat[fy %in% PRIMARY_FYS_F & !(fy == "2019-20" & month == 3L)]            # primary window: ends February 2020
  need <- c("lb", "sb", "wt", "lbw", "home", "inst", "d24")
  for (i in need) if (!any(nat$indicator == i)) stop("national_keys_f: no national rows for indicator ", i, " in ", f_rel(national_csv), call. = FALSE)
  w <- data.table::dcast(nat[indicator %in% need], fy + month ~ indicator, value.var = "national")
  src <- sprintf("%s (official All_India series net of the M/O rows; blank M/O = 0, Paper E F39)", f_rel(national_csv))
  one <- function(yr, def, key, kind) {
    x <- w[w$fy == yr]
    ok <- stats::complete.cases(x[, def$cols, with = FALSE])
    xo <- x[ok]
    if (!nrow(xo)) {
      txt <- if (kind == "d24") "not available (no national month with a reported d24)" else "not available (no national month with every count present)"
      return(put(key, NA, txt, sprintf("%s, national, FY%s: %s; %s. %s", def$what, yr, txt, src, FY21_NOTE)))
    }
    val <- sum(def$num(xo)) / sum(def$den(xo)) * def$scale
    xo <- xo[order(match(month, c(4:12, 1:3)))]
    lost <- x[!ok][order(match(month, c(4:12, 1:3)))]
    put(key, val, def$fmt(val),
        sprintf("%s, national, FY%s, ratio of sums over the months with %s: %d of %d national months (%s to %s)%s; full value %s; %s. %s",
                def$what, yr, if (kind == "d24") "a reported d24" else "every count present", nrow(xo), nrow(x),
                .fy_month_label(yr, xo$month[1]), .fy_month_label(yr, xo$month[nrow(xo)]),
                if (nrow(lost)) paste0("; months without: ", paste(.fy_month_label(yr, lost$month), collapse = ", ")) else "",
                format(signif(val, 8)), src, FY21_NOTE))
  }
  for (fy in PRIMARY_FYS_F) {
    for (r in names(NATIONAL_RATES)) one(fy, NATIONAL_RATES[[r]], sprintf("F.national.%s.%s", r, fy_key(fy)), "rate")
    one(fy, NATIONAL_D24, sprintf("F.d24.national.%s", fy_key(fy)), "d24")
  }
  br <- data.table::fread(break_csv)
  for (r in c("sbr", "lbw_share", "wt_cov")) {
    x <- br[indicator == r]
    if (nrow(x) != 1L) stop(sprintf("national_keys_f: %s has %d rows for %s", f_rel(break_csv), nrow(x), r), call. = FALSE)
    put(sprintf("F.break2017.%s.ratio", r), x$ratio, fmt_num(x$ratio, 3),
        sprintf("National April 2017 / March 2017 ratio of %s over the %d link units with a complete value for both months (descriptive; %s); full value %s; ends before FY2020-21, which was analysed as a sensitivity analysis only",
                r, x$n_units, f_rel(break_csv), format(signif(x$ratio, 6))))
  }
  E
}

# ------------------------------------------------------------------ sections 4 and 9: timing and power keys

TIMING_FITS <- c(l_primary = "model_l_primary", t_primary = "model_t_primary", l_sim = "sim_l", t_sim = "sim_t")

# The 20 keys: F.timing.*.minutes (timing.csv) and the power keys (power.csv; at step "stop" nothing was simulated and
# every MDE and power key reads the contract's stop text).
power_keys_f <- function(power_csv = file.path(F_OUT, "power.csv"), timing_csv = file.path(F_OUT, "timing.csv"), script = NULL) {
  E <- list()
  put <- function(k, value, display, description, scr) E[[k]] <<- .res_f(value, display, description, if (is.null(script)) scr else script)
  tm <- data.table::fread(timing_csv)
  for (k in names(TIMING_FITS)) {
    r <- tm[fit == TIMING_FITS[[k]]]
    if (nrow(r) != 1L) stop(sprintf("power_keys_f: %s has %d rows for fit %s", f_rel(timing_csv), nrow(r), TIMING_FITS[[k]]), call. = FALSE)
    put(sprintf("F.timing.%s.minutes", k), r$minutes, fmt_num(r$minutes, 1),
        sprintf("Wall time of one %s fit (outcome %s, exposures permuted within link unit; %s rows, %s link units; unit random effect %s; converged %s); full value %s minutes (%s)",
                gsub("_", " ", k), r$outcome, fmt_int(r$n_rows), r$n_units, r$re_used, r$converged, format(signif(r$minutes, 8)), f_rel(timing_csv)),
        TIMING_SCRIPT_F)
  }
  pw <- data.table::fread(power_csv, colClasses = list(character = "step"))
  one <- function(col) { v <- unique(pw[[col]]); if (length(v) != 1L) stop("power_keys_f: ", f_rel(power_csv), " has several values of ", col, call. = FALSE); v }
  step <- one("step"); n_sim <- one("n_sim"); hours <- one("projected_h"); cores <- one("cores")
  gl <- sort(unique(pw[test_id %in% TESTS[model == "L"]$test_id]$rr)); gt <- sort(unique(pw[test_id %in% TESTS[model == "T"]$test_id]$rr))
  g2 <- function(x) paste(sprintf("%.2f", x), collapse = ", ")
  grid <- if (isTRUE(all.equal(gl, GRID_REDUCED)) && isTRUE(all.equal(gt, GRID_REDUCED))) "1.03, 1.05, 1.10 (every test)" else
    sprintf("Model L %s; Model T %s", g2(gl), g2(gt))
  sd <- power_step_display(step)
  stopped <- identical(step, "stop")
  src <- sprintf("%s; R6 plan (spec 5.6)%s", f_rel(power_csv),
                 if (stopped) "; the plan was STOPPED (projected over 24 h after both reductions, user decision 2026-11-08): no simulation was run" else "")
  put("F.power.n_sim", n_sim, fmt_int(n_sim), sprintf("Simulations per test x grid point in the plan used (%s)", src), POWER_SCRIPT_F)
  put("F.power.grid", grid, grid, sprintf("RR grid of the plan used (%s)", src), POWER_SCRIPT_F)
  put("F.power.hours", hours, fmt_num(hours, 1),
      sprintf("Projected hours of the plan used: sum over the six tests of simulations x grid points x minutes of one simulation fit / 60 / %d workers (the workers used); step %s; full value %s (%s)",
              cores, step, format(signif(hours, 8)), src), POWER_SCRIPT_F)
  put("F.power.step", sd, sd, sprintf("Step of the R6 order reached (power.csv code %s) (%s)", step, src), POWER_SCRIPT_F)
  for (t in TESTS$test_id) {
    if (stopped) {
      put(sprintf("F.power.%s.mde", t), NA, STOP_TEXT, sprintf("MDE of %s: %s. %s", toupper(t), STOP_TEXT, src), POWER_SCRIPT_F)
      put(sprintf("F.power.%s.power_at_grid_max", t), NA, STOP_TEXT, sprintf("Power of %s at the largest RR of the grid: %s. %s", toupper(t), STOP_TEXT, src), POWER_SCRIPT_F)
      next
    }
    tb <- pw[test_id == t]
    m <- mde_f(tb)
    put(sprintf("F.power.%s.mde", t), m$value, m$display,
        sprintf("Minimum detectable RR of %s: the RR closest to 1 in the grid used with power >= 0.80 (two-sided p < 0.05 and RR > 1), per test at alpha 0.05, not Holm-adjusted; grid %s (%s)",
                toupper(t), paste(sprintf("%.2f", sort(tb$rr)), collapse = ", "), src), POWER_SCRIPT_F)
    top <- tb[which.max(rr)]
    put(sprintf("F.power.%s.power_at_grid_max", t), top$power, fmt_pct(top$power, 0),
        sprintf("Simulated power of %s at RR %.2f (the largest of the grid): rejections / successful refits; n_ok = %d of %d simulations; full value %s (%s)",
                toupper(t), top$rr, top$n_ok, top$n_sim, format(signif(top$power, 6)), src), POWER_SCRIPT_F)
  }
  E[order(names(E), method = "radix")]
}

# ------------------------------------------------------------------ section 8: reading rules (spec 5.5; contract)

.pick_f <- function(tab, ...) {
  tab <- data.table::as.data.table(tab)
  f <- list(...)
  if (!nrow(tab) || !all(names(f) %in% names(tab))) return(tab[0])
  tab[Reduce(`&`, lapply(names(f), function(k) tab[[k]] == f[[k]]))]
}
.row_ok_f <- function(r) nrow(r) == 1L && identical(r$status, "ok") && !is.na(r$rr) && !is.na(r$lo) && !is.na(r$hi)
.row_why_f <- function(r) {
  if (nrow(r) != 1L) return("row missing")
  if (!is.na(r$error)) return(first_line(r$error))
  if (!identical(r$status, "ok")) return(as.character(r$status))
  "estimate missing"
}
.verdict_of <- function(tests, id) {
  v <- data.table::as.data.table(tests)[test_id == id]$verdict
  if (length(v) != 1L) stop("reading_rules_f: no verdict for test ", id, call. = FALSE)
  v
}

# F.read.<O>.selection and F.read.<O>.national from the primary table and tests (primary = list(table, tests)), the
# selection-audit table and the sensitivity table (rows as written to selection.csv and sensitivity.csv).
reading_rules_f <- function(primary, selection, sens, script = RES_SCRIPT_F) {
  tab <- data.table::as.data.table(primary$table)
  E <- list()
  put <- function(k, value, display, description) E[[k]] <<- .res_f(value, display, description, script)
  hs_of <- c(sb = "heat_t3", lbw = "heat_gest"); heat_test <- c(sb = "h10a", lbw = "h11a"); en_test <- c(sb = "h10c", lbw = "h11c")
  first_bad <- function(inputs) {
    for (i in inputs) if (!.row_ok_f(i$row)) return(sprintf("not estimable (%s: %s)", i$key, .row_why_f(i$row)))
    NULL
  }
  for (o in OUTS) {
    hs <- hs_of[[o]]
    ## selection: the outcome's heat test is consistent with, an audit CI wholly below 1, and the adjusted estimate more than halfway to 1
    k <- sprintf("F.read.%s.selection", o)
    v <- .verdict_of(primary$tests, heat_test[[o]])
    if (!identical(v, VERDICT_YES)) {
      put(k, NOT_APPLICABLE_SELECTION, NOT_APPLICABLE_SELECTION, sprintf("Selection reading rule, %s: the heat test (%s, %s) reads '%s'", o, toupper(heat_test[[o]]), hs, v))
    } else {
      wt <- .pick_f(selection, outcome = "wt", model = "L", term = hs); is <- .pick_f(selection, outcome = "inst_share", model = "L", term = hs)
      adj <- .pick_f(sens, case = "inst_adj", outcome = o, arm = "L", term = hs); prm <- .pick_f(tab, outcome = o, model = "L", term = hs)
      inputs <- list(list(key = sprintf("F.sel.wt.%s.rr", hs), row = wt), list(key = sprintf("F.sel.inst_share.%s.rr", hs), row = is),
                     list(key = sprintf("F.sens.%s.inst_adj.heat", o), row = adj), list(key = sprintf("F.l.%s.%s.rr", o, hs), row = prm))
      bad <- first_bad(inputs)
      if (!is.null(bad)) {
        put(k, NA, bad, sprintf("Selection reading rule, %s: %s; the Discussion takes the cautious branch (selection may explain part of the association)", o, bad))
      } else {
        below <- (wt$hi < 1) || (is$hi < 1)
        ratio <- log(adj$rr) / log(prm$rr)
        half <- ratio < 0.5
        txt <- if (below && half) "selection may explain part of the association" else "selection not indicated"
        put(k, txt, txt, sprintf("Selection reading rule, %s (primary heat summary %s, test %s consistent with): audit CI upper bounds wt %s, inst_share %s (wholly below 1: %s); RR_adj (inst_adj) %s, RR_primary %s, ln(RR_adj) / ln(RR_primary) = %s (< 0.5: %s)",
                                 o, hs, toupper(heat_test[[o]]), .s6(wt$hi), .s6(is$hi), below, .s6(adj$rr), .s6(prm$rr), .s6(ratio), half))
      }
    }
    ## national events: the outcome's El Nino test is consistent with and neither primary heat nor dry_gest has a CI wholly above 1
    k <- sprintf("F.read.%s.national", o)
    v <- .verdict_of(primary$tests, en_test[[o]])
    if (!identical(v, VERDICT_YES)) {
      put(k, NOT_APPLICABLE_NATIONAL, NOT_APPLICABLE_NATIONAL, sprintf("National-events reading rule, %s: the El Ni\u00f1o test (%s) reads '%s'", o, toupper(en_test[[o]]), v))
    } else {
      ht <- .pick_f(tab, outcome = o, model = "L", term = hs); dr <- .pick_f(tab, outcome = o, model = "L", term = "dry_gest")
      bad <- first_bad(list(list(key = sprintf("F.l.%s.%s.rr", o, hs), row = ht), list(key = sprintf("F.l.%s.dry_gest.rr", o), row = dr)))
      if (!is.null(bad)) {
        put(k, NA, bad, sprintf("National-events reading rule, %s: %s; the Discussion takes the cautious branch (total may reflect coincident national events)", o, bad))
      } else {
        null <- !(ht$lo > 1) && !(dr$lo > 1)
        txt <- if (null) "total may reflect coincident national events" else "local-climate associations also present"
        put(k, txt, txt, sprintf("National-events reading rule, %s (El Ni\u00f1o test %s consistent with): lower CI bounds of %s %s and of dry_gest %s; local associations null or opposite: %s",
                                 o, toupper(en_test[[o]]), hs, .s6(ht$lo), .s6(dr$lo), null))
      }
    }
  }
  E[order(names(E), method = "radix")]
}
reading_rules <- reading_rules_f

# ------------------------------------------------------------------ section 12: the conclusion sentence

conclusion_sentence_f <- function(E) {
  need <- function(k, allow_nc = FALSE) {
    e <- E[[k]]
    if (is.null(e)) stop("conclusion sentence: missing key ", k, call. = FALSE)
    v <- e$display
    if (!v %in% c(VERDICT_YES, VERDICT_NO, if (allow_nc) VERDICT_NC_FAILED))
      stop(sprintf("conclusion sentence: %s is outside 'consistent with' / 'not consistent with': %s", k, v), call. = FALSE)
    v
  }
  part <- function(h, phrase) {
    ids <- TESTS$test_id[startsWith(TESTS$test_id, h)]
    v <- stats::setNames(vapply(ids, function(i) need(sprintf("F.%s.verdict", i), allow_nc = TRUE), ""), ids)
    ov <- overall_verdict_f(v, toupper(h))
    top <- need(sprintf("F.%s.verdict", h))
    if (!identical(top, ov$verdict))
      stop(sprintf("conclusion sentence: F.%s.verdict (%s) disagrees with the per-test verdicts (%s)", h, top, ov$verdict), call. = FALSE)
    txt <- E[[sprintf("F.%s.verdict_text", h)]]
    if (is.null(txt) || !identical(txt$display, ov$text))
      stop(sprintf("conclusion sentence: F.%s.verdict_text disagrees with the per-test verdicts", h), call. = FALSE)
    yes <- names(v)[v == VERDICT_YES]
    paste0(top, phrase, if (length(yes) && identical(top, VERDICT_YES)) paste0(" (", join_labels(unname(F_TEST_LABELS[yes])), ")") else "")
  }
  s <- enc2utf8(paste0(CONCLUSION_PHRASES_F[["lead"]], part("h10", CONCLUSION_PHRASES_F[["h10"]]), "; and ",
                       part("h11", CONCLUSION_PHRASES_F[["h11"]]), "."))
  if (grepl(CONCLUSION_CAUSAL_F, s, ignore.case = TRUE, perl = TRUE)) stop("conclusion sentence: causal wording: ", s, call. = FALSE)
  if (grepl("Paper [A-F]\\b", s)) stop("conclusion sentence: paper label: ", s, call. = FALSE)
  s
}

conclusion_entry_f <- function(E) {
  s <- conclusion_sentence_f(E)
  list(F.abstract.conclusion_sentence = .res_f(s, s,
    "Code-built from the contract section 12 template: H10 from F.h10.verdict and F.h10a to F.h10c verdicts, H11 from F.h11.verdict and F.h11a to F.h11c verdicts ({LIST} as section 7); no causal wording, no paper label"))
}

# ------------------------------------------------------------------ assembly

# A dropped outcome carries no estimate: a model key of it with a numeric value stops the run.
check_dropped_f <- function(E, dropped) {
  for (o in dropped) {
    ks <- grep(sprintf("^F\\.(l|t|sel|sens|pre|nc)\\.%s\\.", o), names(E), value = TRUE)
    for (k in ks) {
      v <- E[[k]]$value
      if (is.numeric(v) && length(v) == 1L && !is.na(v))
        stop(sprintf("04_results: dropped outcome %s has a value in %s (%s)", o, k, E[[k]]$display), call. = FALSE)
    }
  }
  invisible(dropped)
}

# steps: named list of resolved steps (name, entries, ...). Returns every entry after the key-set check, sorted C-locale.
assemble_f_results <- function(steps, panel, contract = F_CONTRACT, dropped = character()) {
  assert_contract_counts_f(contract)
  want <- contract_keys(contract, prefix = "F")
  f_key_step(want)                                                       # every key has an owner
  entries <- panel
  for (s in steps) {
    dup <- intersect(names(entries), names(s$entries))
    if (length(dup)) stop("04_results: duplicate key(s) from step ", s$name, ": ", paste(head(dup, 10), collapse = ", "), call. = FALSE)
    entries <- c(entries, s$entries)
  }
  entries <- c(entries, conclusion_entry_f(entries))
  missing <- setdiff(want, names(entries)); extra <- setdiff(names(entries), want)
  if (length(missing) || length(extra))
    stop("04_results: key set differs from the contract. Missing: ", paste(head(missing, 40), collapse = ", "),
         ". Extra: ", paste(head(extra, 40), collapse = ", "), call. = FALSE)
  check_dropped_f(entries, dropped)
  entries[order(names(entries), method = "radix")]
}

# provenance.csv (item, value, note).
f_provenance <- function(steps, n_keys, inputs = file.path(REPO_ROOT, F_PROV_INPUTS), git_fun = f_git) {
  code_commit <- git_fun(c("log", "-1", "--format=%h", "--", F_CODE_PATHS))[1]
  code_dirty <- length(git_fun(f_status_args(F_CODE_PATHS))) > 0L
  rows <- list(data.table::data.table(
    item = c("results_code_commit", "results_code_dirty", "seed", "n_keys"),
    value = c(code_commit, as.character(code_dirty), as.character(SEED_F), as.character(n_keys)),
    note = c(paste("last commit touching", paste(F_CODE_PATHS, collapse = ", ")),
             "TRUE if TRACKED files of those paths had uncommitted changes when results.json was assembled (untracked files never count)",
             "SEED_F (models/F/R/common_f.R)", "keys in results.json (= contract)")))
  if (length(inputs))
    rows[[2]] <- data.table::data.table(item = paste0("input:", vapply(inputs, f_rel, "")), value = vapply(inputs, f_sha256_lf, ""),
                                        note = paste("sha256 (CRLF -> LF for text; gz as is);", vapply(inputs, f_git_state, "", git_fun = git_fun)))
  for (s in steps) {
    rows[[length(rows) + 1L]] <- data.table::data.table(item = paste0("step:", s$name), value = s$status,
      note = sprintf("models/F/%s; %d keys", s$script, length(s$entries)))
    if (!is.null(s$rds_sha256) && !is.na(s$rds_sha256))
      rows[[length(rows) + 1L]] <- data.table::data.table(item = paste0("cache:", s$name), value = s$rds_sha256,
                                                          note = paste("sha256 of", s$rds, "(git-ignored)"))
    if (!is.null(s$outputs) && nrow(s$outputs))
      rows[[length(rows) + 1L]] <- s$outputs[, .(item = paste0("output:", path), value = sha256_lf,
        note = paste("sha256 (CRLF -> LF); consistent with the cache;", vapply(file.path(REPO_ROOT, path), f_git_state, "", git_fun = git_fun)))]
  }
  data.table::rbindlist(rows)
}

f_results_settings <- function(args = commandArgs(trailingOnly = TRUE), default_mode = "default") {
  known <- c("--use-cache", "--refit")
  bad <- args[!args %in% known & !grepl("^--out-dir=", args)]
  if (length(bad)) stop("04_results: unknown argument(s): ", paste(bad, collapse = " "), call. = FALSE)
  if (all(known %in% args)) stop("04_results: --use-cache and --refit exclude each other", call. = FALSE)
  mode <- if ("--refit" %in% args) "refit" else if ("--use-cache" %in% args) "use_cache" else default_mode
  od <- sub("^--out-dir=", "", grep("^--out-dir=", args, value = TRUE))
  list(mode = mode, out_dir = if (length(od)) od[length(od)] else NULL)
}

f_output_paths <- function(out_dir = NULL) {
  if (!is.null(out_dir)) return(list(json = file.path(out_dir, "results.json"), prov = file.path(out_dir, "provenance.csv")))
  list(json = file.path(PAPER_F, "results.json"), prov = file.path(F_OUT, "provenance.csv"))
}

# Assemble, check and write results.json and provenance.csv. Returns the entries and the provenance table invisibly.
write_f_results <- function(steps, panel = panel_keys_f(), out_json = file.path(PAPER_F, "results.json"),
                            out_prov = file.path(F_OUT, "provenance.csv"), contract = F_CONTRACT,
                            dropped = dropped_outcomes_f(), inputs = file.path(REPO_ROOT, F_PROV_INPUTS)) {
  entries <- assemble_f_results(steps, panel = panel, contract = contract, dropped = dropped)
  write_results(entries, out_json)
  prov <- f_provenance(steps, length(entries), inputs = inputs)
  dir.create(dirname(out_prov), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(prov, out_prov, eol = "\n")
  invisible(list(entries = entries, provenance = prov))
}

# ------------------------------------------------------------------ steps: definitions, resolution

.rd_csv <- function(path) data.table::fread(path, na.strings = c("", "NA"), colClasses = list(character = c("grad_par", "note", "error")))

f_step_defs <- function(out_dir = F_OUT, cache = F_CACHE) {
  o <- function(...) file.path(out_dir, c(...))
  list(
    power = list(name = "power", script = "01_power.R", rds = file.path(cache, "power.rds"), outputs = o("timing.csv", "power.csv"),
      check = function(obj, def) {
        pw <- data.table::fread(file.path(out_dir, "power.csv"), colClasses = list(character = "step"))
        if (!identical(obj$plan$step, unique(pw$step)) || !isTRUE(all.equal(obj$plan$projected_h, unique(pw$projected_h))))
          stop("run_all: the power cache (models/F/_cache/power.rds) and papers/F/output/power.csv are from different runs", call. = FALSE)
      },
      entries = function(obj, def) power_keys_f(file.path(out_dir, "power.csv"), file.path(out_dir, "timing.csv")),
      data = function(obj, entries, def) NULL),
    primary = list(name = "primary", script = "02_primary.R", rds = file.path(cache, "primary.rds"),
      outputs = o("primary_estimates.csv", "verdicts.csv"),
      check = function(obj, def) {
        if (!identical(f_table_sha(obj$table), f_sha256_lf(file.path(out_dir, "primary_estimates.csv"))))
          stop("run_all: the primary cache (models/F/_cache/primary.rds) differs from papers/F/output/primary_estimates.csv (different runs)", call. = FALSE)
        v <- data.table::fread(file.path(out_dir, "verdicts.csv"))
        if (!identical(as.character(v[match(obj$tests$test_id, test_id)]$verdict), as.character(obj$tests$verdict)))
          stop("run_all: the cached verdicts differ from papers/F/output/verdicts.csv (different runs)", call. = FALSE)
      },
      entries = function(obj, def) primary_entries(obj$table, obj$tests, obj$overall),
      data = function(obj, entries, def) list(table = obj$table, tests = obj$tests)),
    secondary = list(name = "secondary", script = "03_secondary.R", rds = file.path(cache, "secondary_entries.rds"),
      outputs = o("selection.csv", "secondary.csv", "sensitivity.csv", "trimester.csv"),
      # the entries are rebuilt from the committed CSVs (the display follows the current formatter); the cached entries must
      # agree with them in value and description
      load = function() list(selection = .rd_csv(file.path(out_dir, "selection.csv")), secondary = .rd_csv(file.path(out_dir, "secondary.csv")),
                             sensitivity = .rd_csv(file.path(out_dir, "sensitivity.csv"))),
      check = function(obj, def) {
        t <- def$load(); e <- secondary_entries(t$selection, t$secondary, t$sensitivity)
        same <- setequal(names(e), names(obj)) && all(vapply(names(e), function(k)
          identical(e[[k]]$value, obj[[k]]$value) && identical(e[[k]]$description, obj[[k]]$description) &&
            identical(e[[k]]$display, obj[[k]]$display), NA))
        if (!same) stop("run_all: the secondary cache (models/F/_cache/secondary_entries.rds) differs from the committed selection, secondary and sensitivity CSVs in value, description or display (different runs or an older formatter; rerun Rscript F/03_secondary.R assemble, which fits nothing)", call. = FALSE)
      },
      entries = function(obj, def) { t <- def$load(); secondary_entries(t$selection, t$secondary, t$sensitivity) },
      data = function(obj, entries, def) def$load()))
}

# Run a producer script from <repo>/models (only in default and refit modes; never in use_cache).
f_run_script <- function(script, args = character()) {
  rs <- file.path(R.home("bin"), "Rscript")
  flog("run_all: running Rscript F/", script, " ", paste(args, collapse = " "), file = "results.log")
  st <- system2(rs, c(file.path("F", script), args))
  if (!identical(st, 0L)) stop("run_all: Rscript F/", script, " failed (exit ", st, ")", call. = FALSE)
}

resolve_f_step <- function(def, mode = c("use_cache", "default", "refit")) {
  mode <- match.arg(mode)
  incomplete <- !file.exists(def$rds) || any(!file.exists(def$outputs))
  if (mode == "refit" || (mode == "default" && incomplete)) f_run_script(def$script)
  if (!file.exists(def$rds))
    stop(sprintf("run_all: step %s: cache %s is missing; --use-cache never refits (run Rscript F/%s, or use --refit)", def$name, f_rel(def$rds), def$script), call. = FALSE)
  if (any(!file.exists(def$outputs)))
    stop(sprintf("run_all: step %s: output(s) missing: %s", def$name, paste(f_rel(def$outputs[!file.exists(def$outputs)]), collapse = ", ")), call. = FALSE)
  obj <- readRDS(def$rds)
  def$check(obj, def)
  entries <- def$entries(obj, def)
  list(name = def$name, status = "cached", script = def$script, entries = entries, rds = f_rel(def$rds), rds_sha256 = f_sha256_lf(def$rds),
       outputs = data.table::data.table(path = f_rel(def$outputs), sha256_lf = vapply(def$outputs, f_sha256_lf, "")),
       data = def$data(obj, entries, def))
}
