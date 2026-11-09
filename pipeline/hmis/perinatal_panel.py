"""Paper F link-unit-month perinatal panel, gates and halt rules (Task 4; spec 3.3-3.5, rulings R1, R4).

Districts of Task 2's parts are aggregated to the Task 3 link units (`hmis_link_units.csv`) per FY. Paper E's gates are
called, not edited (`gates.gate_plausibility`, `gate_partial_component`, `gate_district_sum`, `gate_national`); the
new rules are the completeness filter, the rate gates, the F-specific component and FY-total gates and the halt rules.

Completeness (spec 3.5). `comp` = valid member districts / member districts listed in the state-FY. Primary values need
comp == 1 (COMP_MIN_F); the sensitivities use comp >= 0.5 scaled by 1/comp (`<v>_scaled`). Controller ruling on
pre-listed ghosts: a district is a *ghost* for an FY when it is listed in that FY's state file, every PANEL_VARS cell is
nofile in all of the FY's months, and its first valid month anywhere in FY2012-13..2020-21 falls in a later FY (the 22
Telangana districts of October 2016 are listed in the FY2015-16 file but their births are reported under the parents).
A ghost is not a member of its link unit for that FY, in the numerator or the denominator. Every other nofile district
still counts, so comp < 1 and the primary value is NaN. `find_ghosts` lists them; the build writes the names to
`data/derived/hmis/perinatal_ghost_members.csv`.

Gate scopes. Link-unit level: count plausibility (F41/F42, same-calendar-month within-era median >= 20), the F37
partial-component rule (lb, home, inst), the E1 component sums (lb_m + lb_f = lb_c, home = home_c, within +-1) and the
rate gates. State level (a failure masks the indicator-month in EVERY link unit of the state unit): district sum vs the
state row (comp == 1 at state level, ghosts excluded) and the 12-months-vs-FY-total check. National: sum of the state
rows vs the folder-1 total (a failure masks the indicator-month in every link unit). Failing cells are masked by
default; a reviewed `keep` row of `pipeline/reference/hmis_perinatal_reviewed.csv` overrides; a plausibility low is kept
by default (`keep_low:plausibility`) and masked only in `<v>_masklow`. Cells with 0.5 <= comp < 1 are gated on the
scaled value (value_sum / comp) by the same count-plausibility and rate rules, and a failure masks their `v_raw`,
`v_scaled`, `v_masklow` and `v_allcomp`; cells with comp < 0.5 stay ungated in `v_raw` and `v_allcomp`. A cell
counts as masked (masked share, excluded units) only where it had a value before masking. A FY2020-21 district that
is unmatched (or review-excluded) sets every link unit of its state unit to NaN for FY2020-21, flag `fy2021_unmatched`. Missing is never zero: masked, flagged and
incomplete cells are NaN.

Panel columns: link_id, state_unit, fy, year, month, ym, era; per PANEL_VARS variable v: `v` (primary: comp == 1 and
not gate-masked), `v_raw` (valid-member sum after the gates, before the completeness filter), `v_scaled`, `v_masklow`,
`v_allcomp` (primary where no valid member lacks a component), `comp_v`, `flag_v`; then tb = lb + sb with tb_scaled,
tb_masklow, tb_allcomp (NaN when a part is NaN); status_date_min / status_date_max. FY2020-21 rows of the link units
touched by a split district are NaN with flag `fy2021_split` (R1). The panel is git-ignored; the tracked outputs hold
counts and shares only. FY2020-21 appears only in git-ignored files and in tracked rows labelled `fy2020_21`.
"""
from pathlib import Path

import numpy as np
import pandas as pd

from pipeline.hmis import exposure
from pipeline.hmis import gates as hg
from pipeline.hmis import panel as hpanel
from pipeline.hmis import perinatal_parts as pp
from pipeline.hmis import perinatal_units as pu
from pipeline.hmis.difference import FY_MONTHS
from pipeline.hmis.gates import FAIL_COLUMNS, FY2021, PRIMARY_FYS, REVIEWED_COLUMNS
from pipeline.hmis.parse import era_for_fy
from pipeline.hmis.perinatal_crosswalk import PANEL_VARS
from pipeline.outcomes.gates import agree
from pipeline.paths import DERIVED

HMIS_DIR = hpanel.HMIS_DIR
PANEL_PATH = HMIS_DIR / "perinatal_unit_month.csv.gz"
SUMMARY_PATH = HMIS_DIR / "perinatal_gate_summary.csv"
BREAK_PATH = HMIS_DIR / "perinatal_break_ratio_2017.csv"
D24_PATH = HMIS_DIR / "perinatal_d24_state_fy.csv"
GHOST_PATH = HMIS_DIR / "perinatal_ghost_members.csv"
REVIEWED_PATH_F = hg.REF / "hmis_perinatal_reviewed.csv"
VALIDATION_REPORT = hpanel.VALIDATION_REPORT
REPORT_HEADING = "## Paper F HMIS gates"

COMP_MIN_F = 1.0
COMP_SENS = 0.5
MAX_MASKED = 0.20
RATE_SB_MAX = 100
RATE_MIN_DENOM = 50
LBW_BAND = 0.20
WT_LB_MAX = 1.10
TOL_COMPONENT = 1.0
TOL_FY_TOTAL = 0.01
OUTCOMES = ("sb", "lbw")                                # primary outcomes (drop and halt rules)
USABLE_VARS = ("lb", "sb", "wt", "lbw")                 # an FY is unusable when none of these has a final value
PARTIAL_VARS = ("lb", "home", "inst")                   # additive sums (F37)
COMPONENT_VARS = ("lb_m", "lb_f", "lb_c", "home_c")     # aggregated for the E1 component gate only
ALL_FYS = PRIMARY_FYS + (FY2021,)
WINDOW = (exposure.PRIMARY_START, exposure.PRIMARY_END)

CHECKS_F = ("district_sum", "plausibility", "national_total", "partial_component", "fy_total", "component_sum",
            "rate_order", "rate_sbr", "rate_lbw_band")
RULES_F = {
    "district_sum": "default mask (spec 3.5): the state row vs the sum of all valid districts (every listed district "
                    "valid, ghosts excluded) differs by > 2% (both >= 100) or > 5; every link unit of the state",
    "fy_total": "default mask (spec 3.5): the 12 months differ from the FY Total column by > 1% for an item of the "
                "indicator; every link unit of the state, all months of the FY",
    "national_total": "default mask (spec 3.5, ruling F39): sum of the 34 state rows vs the folder-1 All India value net "
                      "of M/O rows differs by > 1%; the indicator-month is masked in every link unit",
    "partial_component": hg.RULES["partial_component"].replace("(penta3, mcv1 exempt)", "(lb, home, inst)"),
    "component_sum": "default mask (spec 3.5, E1): lb_m + lb_f differs from the printed lb_c, or home from home_c, by > 1",
    "rate_order": "default mask (spec 3.5): sb > lb, lbw > wt or wt > 1.10 x lb in the link-unit-month; the affected "
                  "outcome is masked",
    "rate_sbr": "default mask (spec 3.5): stillbirth rate above 100 per 1,000 total births with tb >= 50; sb masked",
    "rate_lbw_band": "default mask (spec 3.5): LBW share outside the link unit's same-calendar-month within-era median "
                     "+- 0.20 with wt >= 50; lbw masked",
}


class PerinatalHalt(RuntimeError):
    """A primary outcome (sb, lbw) is dropped, or an FY of FY2012-13..2019-20 is wholly unusable (spec 3.5)."""


# ---- ghosts and aggregation ---------------------------------------------------------------------------------------
def find_ghosts(dm: pd.DataFrame) -> pd.DataFrame:
    """[state_unit, fy, district_raw]: listed in the FY, every PANEL_VARS cell nofile in all 12 months (a partial-year district is never a
    ghost), first valid FY later (see the
    module docstring). `dm` needs state_unit, fy, district_raw, indicator, nofile, valid."""
    p = dm[dm.indicator.isin(PANEL_VARS)]
    g = p.groupby(["state_unit", "fy", "district_raw"])
    cell = g["nofile"].all() & (g["month"].nunique() == 12)          # all 12 months present and nofile
    first = p[p.valid.astype(bool)].groupby(["state_unit", "district_raw"])["fy"].min()
    rows = [(s, fy, d) for (s, fy, d), allnf in cell.items()
            if allnf and (s, d) in first.index and first[(s, d)] > fy]
    return pd.DataFrame(rows, columns=["state_unit", "fy", "district_raw"]).sort_values(
        ["state_unit", "fy", "district_raw"], ignore_index=True)


def membership(units: pd.DataFrame) -> pd.DataFrame:
    """[state_unit, fy, district_raw, link_id] of the mapped HMIS district-FYs; one link unit per district-FY."""
    h = units[(units.kind == "hmis") & units.link_id.notna() & (units.link_id.astype(str) != "")]
    h = h.drop_duplicates(["state_unit", "fy", "district_raw", "link_id"])[["state_unit", "fy", "district_raw",
                                                                            "link_id"]]
    if h.duplicated(["state_unit", "fy", "district_raw"]).any():
        raise ValueError("a district-FY maps to more than one link unit")
    return h.reset_index(drop=True)


def aggregate_link_units(dm: pd.DataFrame, units: pd.DataFrame, ghosts: pd.DataFrame | None = None) -> pd.DataFrame:
    """Long frame, one row per link unit x FY x month x indicator: link_id, state_unit, fy, month, indicator,
    value_full (the sum of the valid members, only when comp == 1), value_sum (the sum of the valid members),
    comp (valid members / members listed in the FY, ghosts excluded), n_members, n_valid, n_partial and n_incomp
    (valid members with a partial / incomplete component set), status_date_min and status_date_max (valid members)."""
    ghosts = find_ghosts(dm) if ghosts is None else ghosts
    d = dm.merge(membership(units), on=["state_unit", "fy", "district_raw"], how="inner")
    if len(ghosts):
        d = d.merge(ghosts.assign(_ghost=True), on=["state_unit", "fy", "district_raw"], how="left")
        d = d[d["_ghost"].isna()].drop(columns="_ghost")
    ok = d.valid.astype(bool)
    d = d.assign(_v=d.value.where(ok), _ok=ok,
                 _partial=ok & d.get("partial_component", False).astype(bool),
                 _incomp=ok & (d.get("n_present", 1) < d.get("n_components", 1)),
                 _date=pd.to_datetime(d.get("status_date"), errors="coerce").where(ok))
    keys = ["link_id", "state_unit", "fy", "month", "indicator"]
    g = d.groupby(keys, sort=True)
    out = pd.DataFrame({"value_sum": g["_v"].sum(min_count=1), "n_members": g.size(), "n_valid": g["_ok"].sum(),
                        "n_partial": g["_partial"].sum(), "n_incomp": g["_incomp"].sum(),
                        "status_date_min": g["_date"].min(), "status_date_max": g["_date"].max()}).reset_index()
    out["comp"] = out.n_valid / out.n_members
    out["value_full"] = out.value_sum.where(out.comp >= COMP_MIN_F - 1e-12)
    for c in ("status_date_min", "status_date_max"):
        out[c] = out[c].dt.strftime("%Y-%m-%d")
    out["month"] = out.month.astype(int)
    for c in ("n_valid", "n_partial", "n_incomp"):
        out[c] = out[c].astype(int)
    return out[["link_id", "state_unit", "fy", "month", "indicator", "value_full", "value_sum", "comp", "n_members",
                "n_valid", "n_partial", "n_incomp", "status_date_min", "status_date_max"]]


def state_level_frames(dm: pd.DataFrame, ghosts: pd.DataFrame, st: pd.DataFrame) -> dict:
    """The state-level inputs of the district-sum and national gates, for the PANEL_VARS indicators: `values` (the
    official state aggregate pooled to the 34 units, unit_id = state unit), `dsum` and `comp` (valid districts / districts
    listed in the state-FY, ghosts excluded)."""
    d = dm[dm.indicator.isin(PANEL_VARS)]
    if len(ghosts):
        d = d.merge(ghosts.assign(_ghost=True), on=["state_unit", "fy", "district_raw"], how="left")
        d = d[d["_ghost"].isna()]
    d = d.assign(_ok=d.valid.astype(bool), _v=lambda x: x.value.where(x.valid.astype(bool)))
    g = d.groupby(["state_unit", "indicator", "fy", "month"])
    agg = pd.DataFrame({"dsum": g["_v"].sum(min_count=1), "n": g.size(), "n_valid": g["_ok"].sum()}).reset_index()
    agg["comp"] = agg.n_valid / agg.n
    agg["month"] = agg.month.astype(int)
    agg = agg.rename(columns={"state_unit": "unit_id"})
    vals = hpanel.state_series(st[st.indicator.isin(PANEL_VARS)])[hg.LONG_KEYS + ["value"]]
    return {"values": vals, "dsum": agg[hg.LONG_KEYS + ["dsum"]], "comp": agg[hg.LONG_KEYS + ["comp"]]}


# ---- count gates --------------------------------------------------------------------------------------------------
def _cat(parts) -> pd.DataFrame:
    parts = [p for p in parts if len(p)]
    if not parts:
        return pd.DataFrame(columns=FAIL_COLUMNS)
    return pd.concat(parts, ignore_index=True)[FAIL_COLUMNS]


def gate_fy_total(check: pd.DataFrame, xw: pd.DataFrame) -> pd.DataFrame:
    """The 12-months-vs-FY-total check of Task 2 (`month_total_check`): a failing district or state item masks the
    indicator that reads the item, in the state unit, for every month of the FY."""
    bad = check[~check["pass"].astype(bool)]
    code = {}
    for r in xw.itertuples():
        for c in str(r.item_codes).split("|"):
            code[(r.era, c)] = r.indicator
    rows = []
    for r in bad.itertuples():
        ind = code.get((era_for_fy(r.fy), str(r.item_code)))
        if ind in PANEL_VARS:
            rows.append((hpanel.resolve_hmis_state(r.state_raw), ind, r.fy, r.rel_diff))
    if not rows:
        return pd.DataFrame(columns=FAIL_COLUMNS)
    t = pd.DataFrame(rows, columns=["unit_id", "indicator", "fy", "rel"]).groupby(
        ["unit_id", "indicator", "fy"]).agg(n=("rel", "size"), worst=("rel", lambda s: s.abs().max())).reset_index()
    t = t.merge(pd.DataFrame({"month": list(range(1, 13))}), how="cross")
    ev = [f"{n} failing item total(s) in the state-FY, largest relative difference {w:.4f} (> {TOL_FY_TOTAL:g})"
          for n, w in zip(t.n, t.worst)]
    return hg._fail(t, "fy_total", ev, rule=RULES_F["fy_total"])


def _component_fails(long: pd.DataFrame) -> pd.DataFrame:
    sub = long[long.indicator.isin(("lb", "lb_m", "lb_f", "lb_c", "home", "home_c"))]
    if sub.empty:
        return pd.DataFrame(columns=FAIL_COLUMNS)
    w = sub.set_index(["link_id", "fy", "month", "indicator"]).value_full.unstack("indicator")
    for c in ("lb", "lb_m", "lb_f", "lb_c", "home", "home_c"):
        if c not in w:
            w[c] = np.nan
    w = w.reset_index()
    e1 = w.fy.map(lambda fy: era_for_fy(fy) == "E1")
    lb_diff = (w.lb_m + w.lb_f - w.lb_c).abs()
    home_diff = (w.home - w.home_c).abs()
    parts = []
    for diff, inds, label in ((lb_diff, ("lb", "lb_m", "lb_f"), "lb_m + lb_f vs lb_c"),
                              (home_diff, ("home",), "home vs home_c")):
        bad = w[e1 & (diff > TOL_COMPONENT + 1e-9)]
        for ind in inds:
            b = bad.assign(indicator=ind).rename(columns={"link_id": "unit_id"})
            ev = [f"{label}: difference {x:.0f} (> {TOL_COMPONENT:g})" for x in diff[bad.index]]
            parts.append(hg._fail(b, "component_sum", ev, rule=RULES_F["component_sum"]))
    return _cat(parts)


def _incomplete_plausibility(long: pd.DataFrame, raw: pd.DataFrame) -> pd.DataFrame:
    """Plausibility of the cells with 0.5 <= comp < 1, on the scaled value (value_sum / comp), against the same-calendar-
    month within-era median of the complete cells and these scaled cells. Only failures of the incomplete cells are
    returned; the raw partial sum is never compared with a full-unit median (the 0.33x rule would fire spuriously)."""
    inc = long[long.indicator.isin(PANEL_VARS) & long.value_full.isna() & long.value_sum.notna()
               & (long.comp >= COMP_SENS - 1e-12) & (long.comp < COMP_MIN_F - 1e-12)]
    if inc.empty:
        return pd.DataFrame(columns=FAIL_COLUMNS)
    sc = inc.assign(value=inc.value_sum / inc.comp).rename(columns={"link_id": "unit_id"})[
        ["unit_id", "fy", "month", "indicator", "value"]]
    f = hg.gate_plausibility(pd.concat([raw, sc], ignore_index=True))[0]
    k = set(zip(sc.unit_id, sc.indicator, sc.fy, sc.month))
    keep = [(u, i, fy, int(m)) in k for u, i, fy, m in zip(f.unit_id, f.indicator, f.fy, f.month)]
    f = f[keep].reset_index(drop=True)
    return f.assign(evidence=[e + "; scaled value of an incomplete cell (comp >= 0.5)" for e in f.evidence])


def count_gates(long: pd.DataFrame, state: dict | None = None, national: pd.DataFrame | None = None,
                fy_total: pd.DataFrame | None = None) -> pd.DataFrame:
    """Failing cells (FAIL_COLUMNS) of the count gates on the long frame. Link-unit failures carry unit_id = link_id;
    state-level failures (district sum, FY total) unit_id = the state unit; a national failure unit_id "ALL"."""
    v = long[long.indicator.isin(PANEL_VARS) & long.value_full.notna()]
    raw = v.rename(columns={"link_id": "unit_id", "value_full": "value"})[["unit_id", "fy", "month", "indicator",
                                                                          "value"]]
    parts = [hg.gate_plausibility(raw)[0]]
    parts.append(_incomplete_plausibility(long, raw))
    p = v[v.indicator.isin(PARTIAL_VARS)]
    pc = p.rename(columns={"link_id": "unit_id", "value_full": "value"}).assign(
        partial_component=(p.n_partial > 0) if "n_partial" in p else False)
    pf = hg.gate_partial_component(pc[["unit_id", "fy", "month", "indicator", "value", "partial_component"]])[0]
    if len(pf):
        pf = pf.assign(rule=RULES_F["partial_component"])
    parts.append(pf)
    parts.append(_component_fails(long))
    if state is not None:
        ds = hg.gate_district_sum(state["values"], state["dsum"], state["comp"])[0]
        if len(ds):
            ds = ds.assign(rule=RULES_F["district_sum"])
        parts.append(ds)
        if national is not None and len(national):
            nat = national[national.indicator.isin(PANEL_VARS)][["fy", "month", "indicator", "national"]]
            gn = hg.gate_national(state["values"], nat)[0]
            if len(gn):
                gn = gn.assign(rule=RULES_F["national_total"])
            parts.append(gn)
    if fy_total is not None:
        parts.append(fy_total)
    out = _cat(parts)
    return out.sort_values(["check", "indicator", "unit_id", "fy", "month"], kind="stable", ignore_index=True)


# ---- rate gates ----------------------------------------------------------------------------------------------------
def rate_gates(wide: pd.DataFrame) -> pd.DataFrame:
    """The rate rules on the primary values and, when the scaled columns and comp columns are present, on the scaled
    values of the incomplete cells (0.5 <= comp < 1; primary where present, else scaled). Failures of the second pass
    are kept only for cells where a tested variable is incomplete and that the first pass did not already flag."""
    first = _rate_core(wide)
    need = [f"{v}_scaled" for v in ("lb", "sb", "wt", "lbw")] + [f"comp_{v}" for v in ("lb", "sb", "wt", "lbw")]
    if not all(c in wide for c in need):
        return first
    x = wide[["link_id", "fy", "month"]].copy()
    for v in ("lb", "sb", "wt", "lbw"):
        x[v] = wide[v].fillna(wide[f"{v}_scaled"])
    allf = _rate_core(x)
    incomplete = set()
    for r in wide.itertuples():
        if any((getattr(r, f"comp_{v}") < COMP_MIN_F - 1e-12) for v in ("lb", "sb", "wt", "lbw")):
            incomplete.add((r.link_id, r.fy, int(r.month)))
    have = set(zip(first.unit_id, first.indicator, first.fy, first.month.astype(int), first.check))
    extra = allf[[(u, fy, int(m)) in incomplete and (u, i, fy, int(m), c) not in have
                  for u, i, fy, m, c in zip(allf.unit_id, allf.indicator, allf.fy, allf.month, allf.check)]]
    return _cat([first, extra]).sort_values(["check", "indicator", "unit_id", "fy", "month"], kind="stable",
                                            ignore_index=True)


def _rate_core(wide: pd.DataFrame) -> pd.DataFrame:
    """Spec 3.5 rate rules on the link-unit-month (primary values lb, sb, wt, lbw; NaN = nothing to test):
    sb > lb -> sb; lbw > wt -> lbw; wt > 1.10 x lb -> lbw and wt; stillbirth rate > 100 per 1,000 with tb >= 50 -> sb;
    LBW share outside the unit's same-calendar-month within-era median +- 0.20 with wt >= 50 -> lbw. A cell already
    failing an order rule is not tested again by the rate and band rules."""
    w = wide[["link_id", "fy", "month", "lb", "sb", "wt", "lbw"]].reset_index(drop=True)
    sb_gt_lb = (w.sb > w.lb).fillna(False)
    lbw_gt_wt = (w.lbw > w.wt).fillna(False)
    wt_gt_lb = (w.wt > WT_LB_MAX * w.lb).fillna(False)
    tb = w.lb + w.sb
    sbr = 1000.0 * w.sb / tb.where(tb > 0)
    sbr_bad = ((tb >= RATE_MIN_DENOM) & (sbr > RATE_SB_MAX)).fillna(False) & ~sb_gt_lb
    share = w.lbw / w.wt.where(w.wt > 0)
    era = w.fy.map(hg.reference_era)
    ref = w.assign(_share=share, _era=era)
    ref = ref[ref.fy.isin(PRIMARY_FYS) & ref._share.notna()]
    med = ref.groupby(["link_id", "month", "_era"])["_share"].median().rename("_med").reset_index()
    m = w.assign(_era=era).merge(med, on=["link_id", "month", "_era"], how="left")
    band_bad = ((m.wt >= RATE_MIN_DENOM) & ((share - m._med).abs() > LBW_BAND + 1e-12)).fillna(False) \
        & ~lbw_gt_wt & ~wt_gt_lb

    def mk(mask, ind, check, ev):
        d = w[mask.values].assign(indicator=ind, unit_id=w.link_id[mask.values])
        return hg._fail(d, check, [ev(r) for r in d.itertuples()], rule=RULES_F[check]) if len(d) \
            else pd.DataFrame(columns=FAIL_COLUMNS)

    f = lambda x: "NA" if pd.isna(x) else f"{x:.0f}"      # noqa: E731
    parts = [
        mk(sb_gt_lb, "sb", "rate_order", lambda r: f"sb={f(r.sb)} > lb={f(r.lb)}"),
        mk(lbw_gt_wt, "lbw", "rate_order", lambda r: f"lbw={f(r.lbw)} > wt={f(r.wt)}"),
        mk(wt_gt_lb, "lbw", "rate_order", lambda r: f"wt={f(r.wt)} > {WT_LB_MAX} x lb={f(r.lb)}"),
        mk(wt_gt_lb, "wt", "rate_order", lambda r: f"wt={f(r.wt)} > {WT_LB_MAX} x lb={f(r.lb)}"),
        mk(sbr_bad, "sb", "rate_sbr", lambda r: f"sb={f(r.sb)} lb={f(r.lb)} rate above {RATE_SB_MAX} per 1000"),
        mk(band_bad, "lbw", "rate_lbw_band", lambda r: f"lbw={f(r.lbw)} wt={f(r.wt)}: share outside median +- "
                                                       f"{LBW_BAND:g}")]
    return _cat(parts).sort_values(["check", "indicator", "unit_id", "fy", "month"], kind="stable", ignore_index=True)


# ---- dispositions --------------------------------------------------------------------------------------------------
def value_columns(wide: pd.DataFrame, var: str) -> list[str]:
    return [c for c in (var, f"{var}_raw", f"{var}_scaled", f"{var}_masklow", f"{var}_allcomp") if c in wide]


def _merge_hit(p: pd.DataFrame, keys: pd.DataFrame, on: list[str], by: str) -> np.ndarray:
    k = keys[["unit_id", "fy", "month"]].drop_duplicates().rename(columns={"unit_id": by}).assign(_h=True)
    return p[on].merge(k, on=on, how="left")["_h"].notna().values


def apply_dispositions_f(wide, failures, reviewed):
    """Mask every failing cell (all value columns of the indicator) unless an author row of `reviewed` (rule starting
    "reviewed", same indicator, unit_id, fy, month, check) says keep; a default `keep` (plausibility low) is only
    flagged. Returns (wide, log as REVIEWED_COLUMNS). Tokens: the check name (masked), "keep:<check>" (author keep),
    hg.LOW_TOKEN (default keep). unit_id is a link_id, a state unit (masks every link unit of it) or "ALL"."""
    p = wide.reset_index(drop=True).copy()
    if failures is None or failures.empty:
        return p, pd.DataFrame(columns=REVIEWED_COLUMNS)
    for v in set(failures.indicator):
        if f"flag_{v}" not in p:
            p[f"flag_{v}"] = ""
        p[f"flag_{v}"] = p[f"flag_{v}"].fillna("").astype(str)
    rev = hg.manual_rows(reviewed) if len(reviewed) else hg.empty_reviewed()
    rk = {(x.indicator, x.unit_id, x.fy, int(x.month), x.check): x for x in rev.itertuples()}
    log = []
    for f in failures.itertuples():
        x = rk.get((f.indicator, f.unit_id, f.fy, int(f.month), f.check))
        if x is not None:
            log.append((f.indicator, f.unit_id, f.fy, int(f.month), f.check, x.disposition, x.rule, x.reason,
                        x.evidence))
        else:
            disp = f.default if f.default in hg.DISPOSITIONS else "mask"
            log.append((f.indicator, f.unit_id, f.fy, int(f.month), f.check, disp, f.rule,
                        hg.DEFAULT_REASON if disp == "mask" else hg.DEFAULT_KEEP_REASON, f.evidence))
    log = pd.DataFrame(log, columns=REVIEWED_COLUMNS)
    tok = [c if d == "mask" else (hg.LOW_TOKEN if r.startswith("default_keep_low") else f"keep:{c}")
           for c, d, r in zip(log.check, log.disposition, log.rule)]
    has_state = "state_unit" in p
    for (ind, token, disp), sub in log.assign(_tok=tok).groupby(["indicator", "_tok", "disposition"], sort=False):
        hit = np.zeros(len(p), bool)
        link_ids = set(p.link_id)
        links = sub[sub.unit_id.isin(link_ids)]
        alls = sub[sub.unit_id == "ALL"]
        states = sub[~sub.unit_id.isin(link_ids) & (sub.unit_id != "ALL")]
        if len(links):
            hit |= _merge_hit(p, links, ["link_id", "fy", "month"], "link_id")
        if len(states) and has_state:
            hit |= _merge_hit(p, states, ["state_unit", "fy", "month"], "state_unit")
        if len(alls):
            k = alls[["fy", "month"]].drop_duplicates().assign(_h=True)
            hit |= p[["fy", "month"]].merge(k, on=["fy", "month"], how="left")["_h"].notna().values
        present = p[value_columns(p, ind)].notna().any(axis=1).values       # a cell without a value is not "masked"
        hit &= present
        if disp == "mask":
            for c in value_columns(p, ind):
                p.loc[hit, c] = np.nan
        elif token == hg.LOW_TOKEN and f"{ind}_masklow" in p:
            p.loc[hit, f"{ind}_masklow"] = np.nan                    # the masklow sensitivity masks default-kept lows
        p[f"flag_{ind}"] = hg._add_flag(p[f"flag_{ind}"], hit, token)
    return p, log


# ---- the wide frame ------------------------------------------------------------------------------------------------
def link_frame(units: pd.DataFrame, fys=ALL_FYS) -> pd.DataFrame:
    """Every link unit x every month of `fys`: link_id, state_unit, fy, year, month, ym, era."""
    g = units[units.kind == "gadm"].drop_duplicates("link_id")[["link_id", "state_unit"]].sort_values("link_id")
    rows = []
    for fy in fys:
        y0 = int(fy[:4])
        for m in FY_MONTHS:
            y = y0 if m >= 4 else y0 + 1
            rows.append((fy, y, m, exposure.ym_of(y, m), era_for_fy(fy)))
    t = pd.DataFrame(rows, columns=["fy", "year", "month", "ym", "era"])
    out = g.merge(t, how="cross")
    return out.sort_values(["link_id", "ym"], ignore_index=True)[["link_id", "state_unit", "fy", "year", "month", "ym",
                                                                   "era"]]


def panel_columns_f() -> list[str]:
    cols = ["link_id", "state_unit", "fy", "year", "month", "ym", "era"]
    for v in PANEL_VARS:
        cols += [v, f"{v}_raw", f"{v}_scaled", f"{v}_masklow", f"{v}_allcomp", f"comp_{v}", f"flag_{v}"]
    cols += ["tb", "tb_scaled", "tb_masklow", "tb_allcomp", "status_date_min", "status_date_max"]
    return cols


def base_wide(long: pd.DataFrame, frame: pd.DataFrame) -> pd.DataFrame:
    """The frame with, per PANEL_VARS variable, the pre-gate columns (v = value_full, v_raw = valid-member sum,
    v_scaled = sum / comp where comp >= 0.5, v_masklow = v, v_allcomp, comp_v, flag_v) and the status dates."""
    w = frame.copy()
    keys = ["link_id", "fy", "month"]
    idx = pd.MultiIndex.from_frame(w[keys])
    for v in PANEL_VARS:
        g = long[long.indicator == v].set_index(keys).reindex(idx)
        incomp = g["n_incomp"] if "n_incomp" in g else pd.Series(0, index=g.index)
        w[v] = g.value_full.values
        w[f"{v}_raw"] = g.value_sum.values
        w[f"{v}_scaled"] = (g.value_sum / g.comp.where(g.comp > 0)).where(g.comp >= COMP_SENS - 1e-12).values
        w[f"{v}_masklow"] = g.value_full.values
        w[f"{v}_allcomp"] = g.value_full.where(incomp.fillna(1) == 0).values
        w[f"comp_{v}"] = g.comp.values
        part = (g.value_sum.notna() & (g.comp < COMP_MIN_F - 1e-12)).values
        w[f"flag_{v}"] = np.where(part, "comp_lt_1", "")
    if "status_date_min" in long:
        t = long.assign(_a=pd.to_datetime(long.status_date_min), _b=pd.to_datetime(long.status_date_max))
        d = t.groupby(keys).agg(status_date_min=("_a", "min"), status_date_max=("_b", "max")).reset_index()
        for c in ("status_date_min", "status_date_max"):
            d[c] = d[c].dt.strftime("%Y-%m-%d")
        w = w.merge(d, on=keys, how="left")
    else:
        w["status_date_min"] = w["status_date_max"] = np.nan
    return w


def apply_fy2021_split(w: pd.DataFrame, missing: set) -> pd.DataFrame:
    """FY2020-21 months of the link units touched by a split district: every value and comp NaN, flag fy2021_split (R1)."""
    return _nan_fy2021(w, ((w.fy == FY2021) & w.link_id.isin(missing)).values, "fy2021_split")


def apply_fy2021_unmatched(w: pd.DataFrame, states: set) -> pd.DataFrame:
    """FY2020-21 months of every link unit of a state unit holding an unmatched (or review-excluded) district: that
    district cannot be placed in one unit, so no unit of the state is complete; values NaN, flag fy2021_unmatched."""
    return _nan_fy2021(w, ((w.fy == FY2021) & w.state_unit.isin(states)).values, "fy2021_unmatched")


def _nan_fy2021(w: pd.DataFrame, sel, token: str) -> pd.DataFrame:
    out = w.copy()
    for v in PANEL_VARS:
        for c in value_columns(out, v) + [f"comp_{v}"]:
            if c in out:
                out.loc[sel, c] = np.nan
        out[f"flag_{v}"] = hg._add_flag(out[f"flag_{v}"].fillna("").astype(str), sel, token)
    return out


def add_total_births(w: pd.DataFrame) -> pd.DataFrame:
    """tb = lb + sb and its scaled / masklow / allcomp versions: NaN when either part is NaN."""
    out = w.copy()
    for suffix in ("", "_scaled", "_masklow", "_allcomp"):
        out[f"tb{suffix}"] = out[f"lb{suffix}"] + out[f"sb{suffix}"]
    return out


def fy2021_unmatched_states(units: pd.DataFrame) -> set:
    """State units with a FY2020-21 district whose status is `unmatched` (no parent region, or a review exclude)."""
    m = units[(units.kind == "hmis") & (units.fy == FY2021)][["state_unit", "fy", "district_raw", "region_id"]]
    mapped = pu.map_fy2021(m, units)
    return set(mapped[mapped.status == "unmatched"].state_unit)


def fy2021_missing_units(units: pd.DataFrame) -> set:
    """Link units touched by a FY2020-21 district that spans several units (Task 3's map_fy2021 applied to the matches
    held in hmis_link_units.csv)."""
    m = units[(units.kind == "hmis") & (units.fy == FY2021)][["state_unit", "fy", "district_raw", "region_id"]]
    return pu.fy2021_missing_units(pu.map_fy2021(m, units))


# ---- masked shares, drop and halt rules ----------------------------------------------------------------------------
def _is_masked(flags: pd.Series) -> pd.Series:
    return flags.fillna("").astype(str).map(lambda f: any(t in CHECKS_F for t in f.split(";") if t)).astype(bool)


def _window(panel: pd.DataFrame, yms) -> pd.DataFrame:
    return panel[(panel.ym >= yms[0]) & (panel.ym <= yms[1])]


def masked_share_f(panel: pd.DataFrame, var: str, yms=WINDOW) -> float:
    """Gate-masked link-unit-months / link-unit-months with a reported value (masked included), months in `yms`
    (inclusive ym range; default April 2012 to February 2020)."""
    p = _window(panel, yms)
    m = _is_masked(p[f"flag_{var}"])
    rep = p[f"{var}_raw"].notna() | m
    return float(m.sum()) / float(rep.sum()) if rep.sum() else float("nan")


def dropped_outcomes(panel: pd.DataFrame, yms=WINDOW) -> list[str]:
    return [v for v in OUTCOMES if masked_share_f(panel, v, yms) > MAX_MASKED]


def excluded_units(panel: pd.DataFrame, var: str, yms=WINDOW) -> list[str]:
    """Link units with more than 20% of their reported-or-masked months in the window masked for `var`."""
    p = _window(panel, yms)
    m = _is_masked(p[f"flag_{var}"])
    rep = (p[f"{var}_raw"].notna() | m)
    g = pd.DataFrame({"link_id": p.link_id, "m": m, "rep": rep}).groupby("link_id").sum()
    share = g.m / g.rep.where(g.rep > 0)
    return sorted(share[share > MAX_MASKED].index)


def unusable_fys(panel: pd.DataFrame, fys) -> list[str]:
    present = [fy for fy in fys if (panel.fy == fy).any()]
    return [fy for fy in present if panel.loc[panel.fy == fy, list(USABLE_VARS)].isna().all().all()]


def check_halt_f(panel: pd.DataFrame) -> dict:
    """Raise PerinatalHalt when sb or lbw is dropped or any FY of FY2012-13..2019-20 is unusable (no link unit has a
    final value for lb, sb, wt or lbw). An unusable FY2020-21 is reported, never raised (R1)."""
    dropped, bad = dropped_outcomes(panel), unusable_fys(panel, PRIMARY_FYS)
    msgs = []
    if dropped:
        msgs.append(f"primary outcome(s) dropped (> {MAX_MASKED:.0%} of link-unit-months gate-masked): "
                    f"{', '.join(dropped)}")
    if bad:
        msgs.append(f"{len(bad)} fiscal year(s) of FY2012-13..2019-20 unusable: {', '.join(bad)}")
    if msgs:
        raise PerinatalHalt("; ".join(msgs))
    if (panel.fy == FY2021).any():
        fy21 = "not estimable (FY2020-21 unusable)" if unusable_fys(panel, (FY2021,)) else "estimable"
    else:
        fy21 = "absent"
    return {"dropped": dropped, "unusable_primary": bad, "fy2021": fy21}


# ---- 2017 break ratios and the d24 table -------------------------------------------------------------------------
def break_ratio_2017_f(long: pd.DataFrame) -> pd.DataFrame:
    """National March 2017 (FY2016-17) to April 2017 (FY2017-18) sums over the link units with a complete value in both
    months, for each PANEL_VARS count and for the rates sbr (per 1,000 total births), lbw_share and wt_cov. A rate
    ratio off 1 by more than 15% is flagged (spec 3.3); counts are never flagged."""
    v = long[long.value_full.notna()]
    mar = v[(v.fy == "2016-17") & (v.month == 3)].pivot(index="link_id", columns="indicator", values="value_full")
    apr = v[(v.fy == "2017-18") & (v.month == 4)].pivot(index="link_id", columns="indicator", values="value_full")
    for t in (mar, apr):
        for c in PANEL_VARS:
            if c not in t:
                t[c] = np.nan
    rows = []

    def pair(cols):
        ids = mar[list(cols)].dropna().index.intersection(apr[list(cols)].dropna().index)
        return mar.loc[ids], apr.loc[ids], len(ids)

    for ind in PANEL_VARS:
        a, b, n = pair([ind])
        m, p = (a[ind].sum(), b[ind].sum()) if n else (np.nan, np.nan)
        rows.append((ind, m, p, p / m if n and m else np.nan, False, n))
    rates = {"sbr": (("sb", "lb"), lambda t: 1000.0 * t.sb.sum() / (t.sb.sum() + t.lb.sum())),
             "lbw_share": (("lbw", "wt"), lambda t: t.lbw.sum() / t.wt.sum()),
             "wt_cov": (("wt", "lb"), lambda t: t.wt.sum() / t.lb.sum())}
    for name, (cols, fn) in rates.items():
        a, b, n = pair(cols)
        m, p = (fn(a), fn(b)) if n else (np.nan, np.nan)
        ratio = p / m if n and m else np.nan
        rows.append((name, m, p, ratio, bool(pd.notna(ratio) and abs(ratio - 1) > 0.15), n))
    return pd.DataFrame(rows, columns=["indicator", "mar2017", "apr2017", "ratio", "gt15pct_rate", "n_units"])


def d24_state_fy(state_rows: pd.DataFrame, national: pd.DataFrame) -> pd.DataFrame:
    """Deaths within 24 h by state unit x FY (FY2012-13..2019-20 only; R4, R1), plus state_unit "TOTAL" from the national
    table. A blank E1 cell is NaN and its month is not counted (never 0). `lb` is summed over the months in which d24
    is reported, so d24_per_1000 is like for like; n_months_reported counts those months."""
    s = state_rows[state_rows.fy.isin(PRIMARY_FYS) & state_rows.indicator.isin(["d24", "lb"])]
    ser = hpanel.state_series(s).pivot(index=["unit_id", "fy", "month"], columns="indicator",
                                       values="value").reset_index()
    nat = national[national.fy.isin(PRIMARY_FYS) & national.indicator.isin(["d24", "lb"])]
    tot = nat.pivot(index=["fy", "month"], columns="indicator", values="national").reset_index().assign(
        unit_id="TOTAL")

    def agg(t):
        t = t.assign(lb_m=t.lb.where(t.d24.notna()))
        g = t.groupby(["unit_id", "fy"])
        o = pd.DataFrame({"lb": g.lb_m.sum(min_count=1), "d24": g.d24.sum(min_count=1),
                          "n_months_reported": g.d24.count()}).reset_index()
        o["d24_per_1000"] = 1000.0 * o.d24 / o.lb.where(o.lb > 0)
        return o

    out = pd.concat([agg(ser), agg(tot)], ignore_index=True).rename(columns={"unit_id": "state_unit"})
    out["_t"] = (out.state_unit == "TOTAL").astype(int)
    out = out.sort_values(["fy", "_t", "state_unit"]).drop(columns="_t").reset_index(drop=True)
    return out[["state_unit", "fy", "lb", "d24", "d24_per_1000", "n_months_reported"]]


# ---- summary, report -------------------------------------------------------------------------------------------------
SUMMARY_COLUMNS = (["variable", "scope", "unit_months", "reported"] + [f"masked_{c}" for c in CHECKS_F]
                   + ["kept_low", "masked", "masked_share", "masked_share_window", "comp_lt_1", "entering_models",
                      "dropped", "excluded_units", "fy2021_split", "note"])


def _has(flags: pd.Series, pred) -> pd.Series:
    return flags.fillna("").astype(str).map(lambda f: pred([t for t in f.split(";") if t]))


def gate_summary_f(panel: pd.DataFrame, dropped: list[str]) -> pd.DataFrame:
    """One row per PANEL_VARS variable x scope (primary = FY2012-13..2019-20, fy2020_21), counts and shares only.
    `masked_share_window` is the 20%-rule share (April 2012 to February 2020)."""
    rows = []
    for scope, fys in (("primary", PRIMARY_FYS), ("fy2020_21", (FY2021,))):
        p = panel[panel.fy.isin(fys)]
        if p.empty:
            continue
        for v in PANEL_VARS:
            fl = p[f"flag_{v}"]
            m = _is_masked(fl)
            rep = p[f"{v}_raw"].notna() | m
            row = {"variable": v, "scope": scope, "unit_months": int(p[f"comp_{v}"].notna().sum()),
                   "reported": int(rep.sum())}
            for c in CHECKS_F:
                row[f"masked_{c}"] = int(_has(fl, lambda t, c=c: c in t).sum())
            row.update({
                "kept_low": int(_has(fl, lambda t: hg.LOW_TOKEN in t).sum()),
                "masked": int(m.sum()), "masked_share": float(m.sum()) / rep.sum() if rep.sum() else np.nan,
                "masked_share_window": masked_share_f(panel[panel.fy.isin(fys)], v) if scope == "primary" else np.nan,
                "comp_lt_1": int((rep & ~m & (p[f"comp_{v}"] < COMP_MIN_F - 1e-12)).sum()),
                "entering_models": int(p[v].notna().sum()),
                "dropped": bool(scope == "primary" and v in dropped),
                "excluded_units": len(excluded_units(panel[panel.fy.isin(fys)], v)) if scope == "primary" else np.nan,
                "fy2021_split": int(_has(fl, lambda t: "fy2021_split" in t).sum()) if scope == "fy2020_21" else 0,
                "note": "" if scope == "primary" else "COVID-period sensitivity (R1); outside the drop and halt rules"})
            rows.append(row)
    return pd.DataFrame(rows, columns=SUMMARY_COLUMNS)


def write_report_section(path: Path, section: str, heading: str = REPORT_HEADING) -> None:
    """Replace (or append) the `heading` section of the validation report."""
    path = Path(path)
    text = path.read_text(encoding="utf-8") if path.exists() else "# Validation report\n"
    lines = text.splitlines()
    if heading in lines:
        a = lines.index(heading)
        b = next((k for k in range(a + 1, len(lines)) if lines[k].startswith("## ")), len(lines))
        lines = lines[:a] + lines[b:]
    while lines and not lines[-1].strip():
        lines.pop()
    path.write_text("\n".join(lines) + "\n\n" + section, encoding="utf-8")


def _fmt(x, nd=0) -> str:
    return "" if pd.isna(x) else (f"{x:,.{nd}f}" if nd else f"{x:,.0f}")


def report_section_f(res: dict) -> str:
    s = res["summary"]
    pr = s[s.scope == "primary"]
    checks = res["failures"].groupby("check").size().to_dict() if len(res["failures"]) else {}
    lines = [REPORT_HEADING, "",
             "Generated by `python -I pipeline/hmis/run_f.py panel` (pipeline/hmis/perinatal_panel.py). Districts of the "
             "perinatal parts are aggregated to the Task 3 link units; a link-unit-month is primary only when every "
             "member district is valid (comp == 1). Pre-listed ghost districts (listed, nofile all year, first valid in "
             "a later FY) are not members for that FY. Failing cells are masked by default (author rows of "
             "pipeline/reference/hmis_perinatal_reviewed.csv override); plausibility lows are kept and masked only in "
             "`<v>_masklow`. Counts and shares only; the panel is git-ignored."
             + (f" **HALT: {res['halt']}.**" if res["halt"] else ""), "",
             f"- Link units: {res['n_units']}; link-unit-months built: {res['n_rows']} (108 months each, "
             f"April 2012 to March 2021 incl. the FY2020-21 sensitivity).",
             f"- Ghost members excluded from completeness (`perinatal_ghost_members.csv`): {res['n_ghosts']} "
             f"district-FYs.",
             "- Failing cells by check (before dispositions): "
             + ("; ".join(f"{k} {v}" for k, v in sorted(checks.items())) or "none") + ".",
             f"- Dropped outcomes (> {MAX_MASKED:.0%} gate-masked over April 2012 to February 2020): "
             f"{', '.join(res['dropped']) or 'none'}.",
             f"- FY2020-21 sensitivity: {res['halt_info']['fy2021']}; link units with FY2020-21 months set to missing "
             f"(a district spanning several units): {len(res['fy2021_missing'])}; state units set to missing for "
             f"FY2020-21 (an unmatched district): {len(res['fy2021_unmatched'])}.",
             "- Gating of incomplete cells: 0.5 <= comp < 1 is gated on the scaled value; comp < 0.5 stays ungated in "
             "`v_raw` and `v_allcomp` (the primary `v` needs comp == 1).", "",
             "### Primary scope FY2012-13..2019-20 (perinatal_gate_summary.csv)", "",
             "| variable | reported | masked | masked share (window) | lows kept | comp < 1 | entering models | "
             "excluded units |", "|---|---|---|---|---|---|---|---|"]
    lines += [f"| {r.variable} | {r.reported} | {r.masked} | {r.masked_share_window:.4f} | {r.kept_low} | {r.comp_lt_1} | "
              f"{r.entering_models} | {int(r.excluded_units)} |" for r in pr.itertuples()]
    sd = res["status_dates"]
    lines += ["", "Status dates (\"Status As On\"), primary window: " + (f"{sd[0]} to {sd[1]}" if sd else "none") + ".",
              "", "### National March 2017 to April 2017 ratio (descriptive; spec 3.3; rates flagged above 15%)", "",
              "| indicator | March 2017 | April 2017 | ratio | rate > 15% | units |", "|---|---|---|---|---|---|"]
    lines += [f"| {r.indicator} | {_fmt(r.mar2017, 3 if r.mar2017 < 10 else 0)} | "
              f"{_fmt(r.apr2017, 3 if r.apr2017 < 10 else 0)} | {'' if pd.isna(r.ratio) else f'{r.ratio:.3f}'} | "
              f"{r.gt15pct_rate} | {r.n_units} |" for r in res["breaks"].itertuples()]
    return "\n".join(lines) + "\n"


# ---- assembly and files --------------------------------------------------------------------------------------------
def read_reviewed_f(path=REVIEWED_PATH_F) -> pd.DataFrame:
    """The Paper F dispositions file (header hg.REVIEWED_COLUMNS; unit_id holds the link_id). An absent file reads as
    empty. Validated: indicator in PANEL_VARS, check in CHECKS_F, disposition mask/keep, an author row."""
    path = Path(path)
    if not path.exists():
        return hg.empty_reviewed()
    raw = pd.read_csv(path, dtype=str, keep_default_na=False)
    if list(raw.columns) != REVIEWED_COLUMNS:
        raise ValueError(f"{path.name}: columns {list(raw.columns)} != {REVIEWED_COLUMNS}")
    for i, x in raw.iterrows():
        where = f"{path.name} row {i + 2}"
        if x.indicator not in PANEL_VARS or x.check not in CHECKS_F or x.disposition not in hg.DISPOSITIONS:
            raise ValueError(f"{where}: indicator {x.indicator!r}, check {x.check!r} or disposition "
                             f"{x.disposition!r} not valid")
        if not (x.rule.startswith("reviewed") and x.reason and x.evidence and x.unit_id and x.fy and x.month.isdigit()):
            raise ValueError(f"{where}: an author row needs rule 'reviewed: ...', reason, evidence, unit_id, fy, month")
    return raw


def assemble_f(dm, st, national, units, check, xw, reviewed=None, fys=ALL_FYS) -> dict:
    """The panel and its gates from the parts (no files written). `dm` needs state_unit."""
    reviewed = reviewed if reviewed is not None else hg.empty_reviewed()
    ghosts = find_ghosts(dm)
    long = aggregate_link_units(dm, units, ghosts)
    state = state_level_frames(dm, ghosts, st)
    failures = count_gates(long, state, national, gate_fy_total(check, xw))
    frame = link_frame(units, fys)
    wide = base_wide(long, frame)
    wide, log1 = apply_dispositions_f(wide, failures, reviewed)
    rf = rate_gates(wide)
    wide, log2 = apply_dispositions_f(wide, rf, reviewed)
    missing = fy2021_missing_units(units)
    wide = apply_fy2021_split(wide, missing)
    unmatched = fy2021_unmatched_states(units)
    wide = apply_fy2021_unmatched(wide, unmatched)
    wide = add_total_births(wide)[panel_columns_f()]
    allfail = pd.concat([failures, rf], ignore_index=True)
    log = pd.concat([x for x in (log1, log2) if len(x)], ignore_index=True) if len(log1) or len(log2) \
        else pd.DataFrame(columns=REVIEWED_COLUMNS)
    dropped = dropped_outcomes(wide)
    try:
        halt, halt_info = None, check_halt_f(wide)
    except PerinatalHalt as e:
        halt, halt_info = str(e), {"dropped": dropped, "unusable_primary": unusable_fys(wide, PRIMARY_FYS),
                                   "fy2021": "n/a (halt)"}
    pw = wide[(wide.ym >= WINDOW[0]) & (wide.ym <= WINDOW[1])]
    dates = pd.to_datetime(pw.status_date_min).min(), pd.to_datetime(pw.status_date_max).max()
    sd = (dates[0].strftime("%Y-%m-%d"), dates[1].strftime("%Y-%m-%d")) if pd.notna(dates[0]) else None
    return {"panel": wide, "long": long, "failures": allfail, "log": log, "ghosts": ghosts, "dropped": dropped,
            "halt": halt, "halt_info": halt_info, "fy2021_missing": missing, "fy2021_unmatched": unmatched,
            "breaks": break_ratio_2017_f(long),
            "summary": gate_summary_f(wide, dropped), "status_dates": sd, "n_units": int(wide.link_id.nunique()),
            "n_rows": len(wide), "n_ghosts": len(ghosts)}


def _read_parts(parts: Path):
    parts = Path(parts)
    dm = pd.read_csv(parts / "district_month.csv.gz", dtype={"fy": str, "state_raw": str, "district_raw": str},
                     usecols=["fy", "month", "state_raw", "district_raw", "indicator", "value", "n_components",
                              "n_present", "partial_component", "nofile", "valid", "status_date"])
    for c in ("partial_component", "nofile", "valid"):
        dm[c] = dm[c].astype(str).str.lower().eq("true")
    lab = {s: hpanel.resolve_hmis_state(s) for s in dm.state_raw.unique()}
    dm["state_unit"] = dm.state_raw.map(lab)
    st = pd.read_csv(parts / "state_month.csv.gz", dtype={"fy": str, "state_raw": str})
    st["partial_component"] = st.partial_component.astype(str).str.lower().eq("true")
    nat = pd.read_csv(parts / "national_month.csv.gz", dtype={"fy": str})
    chk = pd.read_csv(parts / "month_total_check.csv.gz", dtype={"fy": str, "state_raw": str, "item_code": str},
                      usecols=["state_raw", "fy", "item_code", "rel_diff", "pass", "is_state_aggregate"])
    chk["pass"] = chk["pass"].astype(str).str.lower().eq("true")
    return dm, st, nat, chk


def _round(p: pd.DataFrame) -> pd.DataFrame:
    p = p.copy()
    for v in PANEL_VARS:
        p[f"comp_{v}"] = p[f"comp_{v}"].round(6)
    for c in [c for c in p if c.endswith("_scaled")]:
        p[c] = p[c].round(2)
    return p


def build_perinatal_panel(out=PANEL_PATH, parts=pp.PARTS_F, units_path=pu.LINK_UNITS_PATH, summary_out=SUMMARY_PATH,
                          break_out=BREAK_PATH, d24_out=D24_PATH, ghost_out=GHOST_PATH, report_path=VALIDATION_REPORT,
                          reviewed_path=REVIEWED_PATH_F) -> dict:
    """Build and write the panel and its tracked summaries. On a halt (spec 3.5) only the gate summary, break ratios and
    the validation-report section (with the HALT line) are written; the panel, ghost list, d24 table and reviewed file
    are left as they were. Returns assemble_f's dict (with `halt`); the caller raises PerinatalHalt."""
    free = pp._free(Path(out).parent)
    if free < 2 * 1024 ** 3:
        raise RuntimeError("less than 2 GB free on the data drive; stopped")
    from pipeline.hmis import perinatal_crosswalk as pc
    dm, st, nat, chk = _read_parts(parts)
    units = pd.read_csv(units_path, dtype=str)
    xw = pc.load_perinatal_crosswalk()
    reviewed = read_reviewed_f(reviewed_path)
    res = assemble_f(dm, st, nat, units, chk, xw, reviewed)
    for path, df in ((summary_out, res["summary"]), (break_out, res["breaks"])):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(path, index=False, float_format="%.6g")
    write_report_section(report_path, report_section_f(res))
    if res["halt"]:
        return res
    res["d24"] = d24_state_fy(st, nat)
    res["d24"].to_csv(d24_out, index=False, float_format="%.6g")
    link = membership(units)
    gh = res["ghosts"].merge(link, on=["state_unit", "fy", "district_raw"], how="left")
    gh[["link_id", "state_unit", "fy", "district_raw"]].to_csv(ghost_out, index=False)
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    _round(res["panel"]).to_csv(out, index=False)
    if not Path(reviewed_path).exists() or len(reviewed) == 0:
        pd.DataFrame(columns=REVIEWED_COLUMNS).to_csv(reviewed_path, index=False)   # author rows only; defaults not tracked
    return res
