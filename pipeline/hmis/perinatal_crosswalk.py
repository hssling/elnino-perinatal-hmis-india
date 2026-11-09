"""Paper F perinatal item crosswalk (Task 1; spec §3.3).

`pipeline/reference/hmis_perinatal_crosswalk.csv` has the columns of Paper E's `hmis_item_crosswalk.csv`
(`crosswalk.XW_COLUMNS`) but is a separate file, because Paper E's loader requires exactly its 7 indicators x 3 eras
and its frozen pipeline rejects others. The rows are applied with `crosswalk.apply_crosswalk` unchanged: a code is
read only when its normalised text matches `text_pattern`, so the HMIS double trap stops the build instead of
swapping series silently:
  - E1 (FY2012-13..2016-17): 4.1.2 = "Number of still births", 4.1.3 = "Number of Abortions (spontaneous or induced)";
  - E2/E3 (FY2017-18..2020-21): 4.1.2 = "Number of Pre term newborns (< 37 weeks of pregnancy)", 4.1.3 = "Still Birth".
Read by code alone, E1 would give abortions and E2 preterm births.

Variables (ERAS_BY_VAR): lb (live births, 4.1.1.a + 4.1.1.b), lb_m / lb_f (its components), lb_c (printed E1 total
4.1.1.c, used only by the E1 component gate), sb (stillbirths), wt (newborns weighed), lbw (weight < 2.5 kg), home
(home deliveries, 2.1.1.a + 2.1.1.b), home_c (printed E1 total 2.1.1.c), inst (institutional deliveries), preterm
(E2/E3 only, secondary) and d24 (deaths within 24 h; E1/E2 only, descriptive at national and state level, R4).
"""
import re

import pandas as pd

from pipeline.hmis.crosswalk import REF, XW_COLUMNS, CrosswalkError

PERINATAL_XW_PATH = REF / "hmis_perinatal_crosswalk.csv"
E1_E3 = ("E1", "E2", "E3")
ERAS_BY_VAR = {"lb": E1_E3, "lb_m": E1_E3, "lb_f": E1_E3, "lb_c": ("E1",), "sb": E1_E3, "wt": E1_E3,
               "lbw": E1_E3, "home": E1_E3, "home_c": ("E1",), "inst": E1_E3, "preterm": ("E2", "E3"),
               "d24": ("E1", "E2")}
PANEL_VARS = ("lb", "lb_m", "lb_f", "sb", "wt", "lbw", "home", "inst", "preterm")    # link-unit level
STATE_ONLY_VARS = ("d24",)                                                           # R4: national and state only


def load_perinatal_crosswalk(path=PERINATAL_XW_PATH) -> pd.DataFrame:
    """The perinatal crosswalk, validated like crosswalk.load_crosswalk but against ERAS_BY_VAR: one row per wanted
    (variable, era), 'single' = one code, 'sum' = two or more, every pattern compiles."""
    # Mirrors crosswalk.load_crosswalk, which is frozen to Paper E's indicator set and so cannot validate these rows.
    xw = pd.read_csv(path, dtype=str, keep_default_na=False)
    if list(xw.columns) != XW_COLUMNS:
        raise CrosswalkError(f"{path}: columns {list(xw.columns)} != {XW_COLUMNS}")
    keys = list(zip(xw.indicator, xw.era))
    want = [(v, e) for v, eras in ERAS_BY_VAR.items() for e in eras]
    if sorted(keys) != sorted(want):
        raise CrosswalkError(f"{path}: need exactly one row per wanted variable x era; extra "
                             f"{sorted(set(keys) - set(want))}, missing {sorted(set(want) - set(keys))}, "
                             f"duplicated {sorted({k for k in keys if keys.count(k) > 1})}")
    for r in xw.itertuples():
        codes = [c for c in r.item_codes.split("|") if c]
        if r.combine not in ("single", "sum") or (r.combine == "single") != (len(codes) == 1) or not codes:
            raise CrosswalkError(f"{path}: {r.indicator} {r.era}: combine {r.combine!r} with codes {r.item_codes!r}")
        try:
            re.compile(r.text_pattern)
        except re.error as e:
            raise CrosswalkError(f"{path}: {r.indicator} {r.era}: bad text_pattern ({e})") from e
    return xw
