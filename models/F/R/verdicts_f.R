# Paper F Task 10: the six-test Holm family and the verdict rules (contract papers/F/results_keys.md: "One Holm family of
# six tests", "Per test, consistent with if and only if", "Negative-control wording"). Pure functions, no model fits.
# Sourced after common_f.R and perinatal.R (TESTS) and Paper E's verdicts.R (VERDICT_YES / VERDICT_NO, holm_family,
# overall_verdict, join_labels), which are called unchanged.

VERDICT_NC_FAILED <- "not consistent with (negative control failed)"

# Labels of the tests in the overall verdict sentence (contract "Verdict-sentence templates").
F_TEST_LABELS <- c(h10a = "third-trimester heat", h10b = "full-gestation rainfall deficit",
                   h10c = "an El Niño gestation", h11a = "full-gestation heat",
                   h11b = "full-gestation rainfall deficit", h11c = "an El Niño gestation")

# Condition (i): the estimate is in the hypothesised direction (RR > 1) and the Holm-adjusted p is below 0.05.
# NA (a not-estimable test) is FALSE.
.cond_i <- function(rr, p_holm) (rr > 1) %in% TRUE & (p_holm < 0.05) %in% TRUE

# Local tests (a, b). Condition (ii): the lead's 95% CI does not lie wholly above 1 (a lead "signal" in the same
# direction). The negative-control wording is written only when (i) held and (ii) failed; if (i) failed the verdict is
# plain "not consistent with" whatever the lead. Vectorised.
verdict_local <- function(rr, p_holm, lead_lo, lead_hi) {
  i <- .cond_i(rr, p_holm)
  signal <- (lead_lo > 1) %in% TRUE
  ifelse(!i, VERDICT_NO, ifelse(signal, VERDICT_NC_FAILED, VERDICT_YES))
}

# El Nino tests (c): (i) and both episode RRs above 1 (point estimates). An episode model that is not estimable gives
# NA episode RRs, so (iii) fails and the test is "not consistent with". Vectorised.
verdict_enso <- function(rr, p_holm, ep1415, ep1819)
  ifelse(.cond_i(rr, p_holm) & (ep1415 > 1) %in% TRUE & (ep1819 > 1) %in% TRUE, VERDICT_YES, VERDICT_NO)

# One verdict per row of `tests` (columns test_id, model "L" | "T", rr, p_holm, lead_lo, lead_hi, ep1415, ep1819).
verdict_test <- function(tests) {
  t <- data.table::as.data.table(tests)
  out <- rep(VERDICT_NO, nrow(t))
  l <- t$model == "L"
  if (any(l)) out[l] <- verdict_local(t$rr[l], t$p_holm[l], t$lead_lo[l], t$lead_hi[l])
  if (any(!l)) out[!l] <- verdict_enso(t$rr[!l], t$p_holm[!l], t$ep1415[!l], t$ep1819[!l])
  out
}

# The one Holm family: stats::p.adjust(method = "holm") over the non-NA p of the six tests (Paper E holm_family);
# a not-estimable test (p NA) has p_holm NA and leaves the family. Exactly the six tests are required.
holm_family_f <- function(tests) {
  t <- data.table::as.data.table(tests)
  if (nrow(t) != nrow(TESTS) || !setequal(t$test_id, TESTS$test_id))
    stop("holm_family_f: the family is the six tests ", paste(TESTS$test_id, collapse = ", "), call. = FALSE)
  holm_family(t)
}

# Overall verdict of one hypothesis ("H10" or "H11") from the per-test verdicts `v` (named by test id): consistent with
# if at least one test is; text is the contract's template. "not consistent with (negative control failed)" is a
# "not consistent with" here.
overall_verdict_f <- function(v, hypothesis) {
  if (is.null(names(v))) stop("overall_verdict_f: v must be named by test id", call. = FALSE)
  pre <- tolower(hypothesis)
  v <- v[startsWith(names(v), pre)]
  v <- stats::setNames(ifelse(v == VERDICT_YES, VERDICT_YES, VERDICT_NO), names(v))
  overall_verdict(v, labels = F_TEST_LABELS[startsWith(names(F_TEST_LABELS), pre)], hypothesis = hypothesis)
}
overall_f <- function(v, hypothesis) overall_verdict_f(v, hypothesis)
