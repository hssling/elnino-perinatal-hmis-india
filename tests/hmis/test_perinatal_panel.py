"""Paper F link-unit-month panel, gates and halt rules (Task 4). Synthetic frames only, except `test_panel_shape`, which
reads the git-ignored panel when it exists."""
import numpy as np
import pandas as pd
import pytest

from pipeline.hmis import exposure
from pipeline.hmis import perinatal_panel as pf
from pipeline.hmis.gates import FAIL_COLUMNS, REVIEWED_COLUMNS

FY1, FY2 = "2012-13", "2013-14"


def _units(members, fys=(FY1,), state="S1"):
    """members: {link_id: [district, ...]} -> hmis_link_units-style frame (hmis rows per FY, gadm rows)."""
    rows = []
    for link, dists in members.items():
        rows.append(dict(kind="gadm", state_unit=state, fy="", district_raw="", region_id="R_" + link, link_id=link))
        for fy in fys:
            for d in dists:
                rows.append(dict(kind="hmis", state_unit=state, fy=fy, district_raw=d, region_id="R_" + link,
                                 link_id=link))
    return pd.DataFrame(rows)


def _dm(cells, state="S1"):
    """cells: (fy, month, district, indicator, value) with value None = nofile."""
    rows = []
    for fy, m, d, ind, v in cells:
        ok = v is not None
        rows.append(dict(fy=fy, month=m, state_unit=state, district_raw=d, indicator=ind,
                         value=float(v) if ok else np.nan, valid=ok, nofile=not ok, partial_component=False,
                         n_components=1, n_present=1 if ok else 0, status_date="2020-01-01"))
    return pd.DataFrame(rows)


def _long(rows):
    """rows: (link_id, fy, month, indicator, value_full) -> aggregate_link_units-style long frame."""
    return pd.DataFrame([dict(link_id=l, state_unit="S1", fy=fy, month=m, indicator=i, value_full=v, value_sum=v,
                              comp=1.0, n_members=1, n_valid=1, n_partial=0, n_incomp=0)
                         for l, fy, m, i, v in rows])


def test_incomplete_link_unit_month_is_nan_not_partial_sum():
    units = _units({"L001": ["A", "B", "C"]})
    dm = _dm([(FY1, 4, "A", "sb", 10), (FY1, 4, "B", "sb", 20), (FY1, 4, "C", "sb", None)])
    long = pf.aggregate_link_units(dm, units)
    r = long.iloc[0]
    assert (r.n_members, r.n_valid) == (3, 2) and r.comp == pytest.approx(2 / 3)
    assert np.isnan(r.value_full) and r.value_sum == 30
    w = pf.base_wide(long, pf.link_frame(units, (FY1,))).query("month == 4").iloc[0]
    assert np.isnan(w.sb)                                    # primary: NaN, not the partial sum 30
    assert w.sb_raw == 30 and w.sb_scaled == pytest.approx(45.0)     # comp 2/3 >= 0.5: scaled by 1/comp
    assert w.comp_sb == pytest.approx(2 / 3)


def _two_fy_cells(ind="sb"):
    """A, B report both FYs. G (ghost) is nofile all of FY1 and reports from FY2. C (control) reports in FY1 and is
    nofile all of FY2."""
    cells = []
    for m in range(1, 13):
        cells += [(FY1, m, "A", ind, 10), (FY1, m, "B", ind, 20), (FY1, m, "G", ind, None),
                  (FY1, m, "C", ind, 5),
                  (FY2, m, "A", ind, 10), (FY2, m, "B", ind, 20), (FY2, m, "G", ind, 7), (FY2, m, "C", ind, None)]
    return cells


def test_prelisted_ghost_district_not_counted_in_comp():
    units = _units({"L001": ["A", "B", "G"], "L002": ["A2", "B2", "C"]}, fys=(FY1, FY2))
    cells = [c for c in _two_fy_cells() if c[2] != "C"]
    dm = _dm(cells)
    ghosts = pf.find_ghosts(dm)
    assert [(g.fy, g.district_raw) for g in ghosts.itertuples()] == [(FY1, "G")]
    long = pf.aggregate_link_units(dm, units).set_index(["link_id", "fy", "month", "indicator"])
    r1 = long.loc[("L001", FY1, 4, "sb")]
    assert r1.n_members == 2 and r1.comp == 1.0 and r1.value_full == 30        # ghost out of numerator and denominator
    r2 = long.loc[("L001", FY2, 4, "sb")]
    assert r2.n_members == 3 and r2.comp == 1.0 and r2.value_full == 37        # reports from FY2: a real member
    # control: nofile all year but reported in an earlier FY -> still a member, comp < 1, primary NaN
    units = _units({"L003": ["A", "B", "C"]}, fys=(FY1, FY2))
    dm = _dm([c for c in _two_fy_cells() if c[2] != "G"])
    assert pf.find_ghosts(dm).empty
    c = pf.aggregate_link_units(dm, units).set_index(["link_id", "fy", "month", "indicator"]).loc[("L003", FY2, 4, "sb")]
    assert c.n_members == 3 and c.comp == pytest.approx(2 / 3) and np.isnan(c.value_full) and c.value_sum == 30


def test_ghost_needs_a_later_first_valid_month():
    """Listed, nofile all year, but never valid anywhere: not a ghost (it counts, so comp < 1)."""
    cells = [(FY1, m, d, "sb", v) for m in range(1, 13) for d, v in (("A", 10), ("N", None))]
    assert pf.find_ghosts(_dm(cells)).empty


def test_rate_gates_mask_the_affected_outcome():
    w = pd.DataFrame([dict(link_id="L1", fy=FY1, month=4, lb=50.0, sb=60.0, wt=40.0, lbw=10.0)])
    f = pf.rate_gates(w)
    assert list(f.columns) == FAIL_COLUMNS
    assert list(zip(f.indicator, f.check)) == [("sb", "rate_order")]
    out, log = pf.apply_dispositions_f(w.assign(flag_sb="", flag_lbw=""), f, pd.DataFrame(columns=REVIEWED_COLUMNS))
    assert np.isnan(out.sb.iloc[0]) and out.lbw.iloc[0] == 10                   # lbw untouched
    assert len(log) == 1 and log.disposition.iloc[0] == "mask"


def test_lbw_above_wt_and_wt_above_lb_are_masked():
    w = pd.DataFrame([dict(link_id="L1", fy=FY1, month=4, lb=100.0, sb=1.0, wt=90.0, lbw=95.0),
                      dict(link_id="L2", fy=FY1, month=4, lb=100.0, sb=1.0, wt=111.0, lbw=10.0),
                      dict(link_id="L3", fy=FY1, month=4, lb=100.0, sb=1.0, wt=110.0, lbw=10.0)])
    f = pf.rate_gates(w)
    got = sorted(zip(f.unit_id, f.indicator))
    assert got == [("L1", "lbw"), ("L2", "lbw"), ("L2", "wt")]                  # wt = 1.10 x lb is allowed


def test_sbr_over_100_needs_tb_50():
    w = pd.DataFrame([dict(link_id="L1", fy=FY1, month=4, lb=43.0, sb=6.0, wt=40.0, lbw=4.0),     # tb 49, 122 per 1000
                      dict(link_id="L2", fy=FY1, month=4, lb=44.0, sb=6.0, wt=40.0, lbw=4.0),     # tb 50, 120 per 1000
                      dict(link_id="L3", fy=FY1, month=4, lb=450.0, sb=50.0, wt=400.0, lbw=40.0)])  # tb 500, exactly 100
    f = pf.rate_gates(w)
    assert list(zip(f.unit_id, f.indicator, f.check)) == [("L2", "sb", "rate_sbr")]


def _band_frame(test_value_wt_lbw):
    rows = []
    for k, fy in enumerate(("2012-13", "2013-14", "2014-15", "2015-16", "2016-17")):
        wt, lbw = (100, 15) if k < 4 else test_value_wt_lbw
        rows.append(dict(link_id="L1", fy=fy, month=4, lb=200.0, sb=1.0, wt=float(wt), lbw=float(lbw)))
    return pd.DataFrame(rows)


def test_lbw_band_is_absolute_020():
    # median share 0.15 (four of five months)
    assert list(pf.rate_gates(_band_frame((100, 36))).indicator) == ["lbw"]     # 0.36 > 0.15 + 0.20
    assert pf.rate_gates(_band_frame((100, 34))).empty                           # 0.34 inside the band
    assert pf.rate_gates(_band_frame((40, 15 + 0.4 * 40 / 1))).empty             # wt < 50: exempt (share 0.5)
    low = pf.rate_gates(_band_frame((100, 0)))                                    # 0 < 0.15 - 0.20 is not below -0.05
    assert low.empty


def test_count_plausibility_uses_within_era_median():
    rows = [("L1", fy, 4, "sb", 1000.0) for fy in ("2012-13", "2013-14", "2014-15", "2015-16", "2016-17")]
    rows += [("L1", fy, 4, "sb", 100.0) for fy in ("2017-18", "2018-19", "2019-20")]
    rows += [("L1", "2020-21", 4, "sb", 400.0)]                                  # 4x the E2 median, below the E1 median
    f = pf.count_gates(_long(rows))
    assert [(r.fy, r.check, r.default) for r in f.itertuples()] == [("2020-21", "plausibility", "mask")]


def test_tb_nan_when_either_part_nan():
    w = pd.DataFrame([dict(link_id="L1", state_unit="S1", fy=FY1, month=m, ym=m, era="E1", lb=lb, sb=sb,
                           lb_scaled=lb, sb_scaled=sb, lb_masklow=lb, sb_masklow=sb, lb_allcomp=lb, sb_allcomp=sb)
                      for m, lb, sb in ((4, 100.0, 5.0), (5, 100.0, np.nan), (6, np.nan, 5.0))])
    out = pf.add_total_births(w)
    assert out.tb.iloc[0] == 105 and out.tb_scaled.iloc[0] == 105
    assert out.tb.iloc[1:].isna().all() and out.tb_scaled.iloc[1:].isna().all()
    assert out.tb_masklow.iloc[1:].isna().all() and out.tb_allcomp.iloc[1:].isna().all()


def _fail(unit, ind, fy, month, check, default="mask"):
    return pd.DataFrame([dict(indicator=ind, unit_id=unit, fy=fy, month=month, check=check, rule="default_keep_low: x" if default == "keep" else "rule: x",
                              evidence="e", default=default)])[FAIL_COLUMNS]


def _wide(**vals):
    d = dict(link_id="L1", state_unit="S1", fy=FY1, month=4)
    d.update(vals)
    return pd.DataFrame([d])


def test_reviewed_keep_overrides_default_mask():
    w = _wide(sb=40.0, sb_raw=40.0, sb_scaled=40.0, sb_masklow=40.0, sb_allcomp=40.0, flag_sb="")
    f = _fail("L1", "sb", FY1, 4, "plausibility")
    none = pd.DataFrame(columns=REVIEWED_COLUMNS)
    masked, log = pf.apply_dispositions_f(w, f, none)
    assert masked.sb.isna().all() and masked.sb_scaled.isna().all() and masked.flag_sb.iloc[0] == "plausibility"
    assert log.disposition.iloc[0] == "mask"
    rev = pd.DataFrame([dict(indicator="sb", unit_id="L1", fy=FY1, month="4", check="plausibility",
                             disposition="keep", rule="reviewed: checked against the state file", reason="genuine",
                             evidence="e")])[REVIEWED_COLUMNS]
    kept, log = pf.apply_dispositions_f(w, f, rev)
    assert kept.sb.iloc[0] == 40 and kept.flag_sb.iloc[0] == "keep:plausibility"
    assert log.disposition.iloc[0] == "keep"


def test_default_keep_low_is_flagged_and_masked_only_in_masklow():
    w = _wide(sb=3.0, sb_raw=3.0, sb_scaled=3.0, sb_masklow=3.0, sb_allcomp=3.0, flag_sb="")
    out, _ = pf.apply_dispositions_f(w, _fail("L1", "sb", FY1, 4, "plausibility", "keep"),
                                     pd.DataFrame(columns=REVIEWED_COLUMNS))
    assert out.sb.iloc[0] == 3 and np.isnan(out.sb_masklow.iloc[0]) and "keep_low" in out.flag_sb.iloc[0]


def test_state_and_national_failures_mask_every_link_unit_they_cover():
    w = pd.concat([_wide(sb=1.0, sb_raw=1.0, flag_sb=""), _wide(sb=2.0, sb_raw=2.0, flag_sb="").assign(link_id="L2"),
                   _wide(sb=3.0, sb_raw=3.0, flag_sb="").assign(link_id="L3", state_unit="S2")], ignore_index=True)
    none = pd.DataFrame(columns=REVIEWED_COLUMNS)
    out, _ = pf.apply_dispositions_f(w, _fail("S1", "sb", FY1, 4, "district_sum"), none)
    assert out.sb.isna().tolist() == [True, True, False]
    out, _ = pf.apply_dispositions_f(w, _fail("ALL", "sb", FY1, 4, "national_total"), none)
    assert out.sb.isna().all()


def _panel(rows):
    """rows: (link_id, fy, ym, var, raw, masked) -> a minimal panel with sb/lbw/lb/wt columns."""
    recs = {}
    for l, fy, ym, var, raw, masked in rows:
        r = recs.setdefault((l, fy, ym), dict(link_id=l, fy=fy, ym=ym))
        r[f"{var}_raw"] = raw
        r[f"flag_{var}"] = "plausibility" if masked else ""
        r[var] = np.nan if (masked or pd.isna(raw)) else raw
    p = pd.DataFrame(list(recs.values()))
    for v in ("sb", "lbw", "lb", "wt"):
        for c, fill in ((v, np.nan), (f"{v}_raw", np.nan), (f"flag_{v}", "")):
            if c not in p:
                p[c] = fill
    return p


def _fy_rows(var, fy, start_ym, n_masked, n=10, link="L1"):
    return [(link, fy, start_ym + k, var, 5.0, k < n_masked) for k in range(n)]


def test_twenty_pct_rule_uses_april_2012_to_february_2020():
    mar2020 = exposure.ym_of(2020, 3)
    in_window = [("L1", "2019-20", exposure.ym_of(2019, 4) + k, "sb", 5.0, False) for k in range(10)]
    out_window = [("L1", "2019-20", mar2020, "sb", 5.0, True)] * 1
    p = _panel(in_window + out_window)
    assert pf.masked_share_f(p, "sb") == 0.0                                      # the March 2020 mask is outside
    assert pf.masked_share_f(p, "sb", (exposure.PRIMARY_START, mar2020)) == pytest.approx(1 / 11)
    assert pf.excluded_units(p, "sb") == []
    p2 = _panel([("L1", "2019-20", exposure.ym_of(2019, 4) + k, "sb", 5.0, k < 3) for k in range(10)]
                + [("L2", "2019-20", exposure.ym_of(2019, 4) + k, "sb", 5.0, k < 2) for k in range(10)])
    assert pf.excluded_units(p2, "sb") == ["L1"]                                  # 30% > 20%, 20% is not above it


def _full_panel(sb_masked=0, fys=pf.PRIMARY_FYS, with_fy2021=True):
    rows = []
    for k, fy in enumerate(list(fys) + (["2020-21"] if with_fy2021 else [])):
        y0 = int(fy[:4])
        for var in ("sb", "lbw", "lb", "wt"):
            rows += [("L1", fy, exposure.ym_of(y0, 4) + j, var, 5.0, var == "sb" and j < sb_masked) for j in range(10)]
    return _panel(rows)


def test_halt_when_sb_dropped_or_primary_fy_unusable():
    assert pf.check_halt_f(_full_panel())["dropped"] == []
    # sb masked in 3 of 10 months of every FY -> 30% > 20% -> dropped -> halt
    p = _full_panel(sb_masked=3)
    assert pf.dropped_outcomes(p) == ["sb"]
    with pytest.raises(pf.PerinatalHalt, match="sb"):
        pf.check_halt_f(p)
    # one primary FY with no usable value at all
    p = _full_panel()
    sel = p.fy == "2015-16"
    p.loc[sel, ["sb", "lbw", "lb", "wt"]] = np.nan
    with pytest.raises(pf.PerinatalHalt, match="2015-16"):
        pf.check_halt_f(p)


def test_unusable_fy2021_does_not_halt():
    p = _full_panel()
    p.loc[p.fy == "2020-21", ["sb", "lbw", "lb", "wt"]] = np.nan
    out = pf.check_halt_f(p)
    assert out["fy2021"] == "not estimable (FY2020-21 unusable)" and out["dropped"] == []


def test_split_fy2021_units_are_nan():
    cols = {}
    for v in pf.PANEL_VARS:
        cols.update({v: 5.0, f"{v}_raw": 5.0, f"{v}_scaled": 5.0, f"{v}_masklow": 5.0, f"{v}_allcomp": 5.0,
                     f"comp_{v}": 1.0, f"flag_{v}": ""})
    w = pd.DataFrame([dict(link_id=l, fy=fy, **cols) for l in ("L1", "L2") for fy in (FY1, "2020-21")])
    out = pf.apply_fy2021_split(w, {"L2"})
    sel = (out.link_id == "L2") & (out.fy == "2020-21")
    assert out.loc[sel, "sb"].isna().all() and out.loc[sel, "sb_scaled"].isna().all()
    assert (out.loc[sel, "flag_sb"] == "fy2021_split").all()
    assert out.loc[~sel, "sb"].eq(5.0).all() and (out.loc[~sel, "flag_sb"] == "").all()


def _state_rows(rows):
    return pd.DataFrame([dict(fy=fy, month=m, state_raw=s, indicator=i, value=v, n_components=1, n_present=1,
                              partial_component=False, status_date="2020-01-01", source_file="x")
                         for fy, m, s, i, v in rows])


def test_d24_state_fy_has_no_fy2021_rows_and_blank_is_not_zero():
    rows = []
    for m in range(1, 13):
        rep = 4 <= m <= 9
        rows += [("2019-20", m, "Bihar", "d24", 2.0 if rep else np.nan), ("2019-20", m, "Bihar", "lb", 100.0),
                 ("2019-20", m, "Assam", "d24", np.nan), ("2019-20", m, "Assam", "lb", 50.0),
                 ("2020-21", m, "Bihar", "d24", 9.0), ("2020-21", m, "Bihar", "lb", 100.0)]
    nat = pd.DataFrame([dict(fy="2019-20", month=m, indicator=i, all_india=v, mo_value=np.nan, national=v)
                        for m in range(1, 13) for i, v in (("d24", 3.0 if m <= 6 else np.nan), ("lb", 1000.0))]
                       + [dict(fy="2020-21", month=4, indicator="d24", all_india=1.0, mo_value=np.nan, national=1.0)])
    out = pf.d24_state_fy(_state_rows(rows), nat)
    assert list(out.columns) == ["state_unit", "fy", "lb", "d24", "d24_per_1000", "n_months_reported"]
    assert set(out.fy) == {"2019-20"}                                             # R4 / R1: no FY2020-21 row
    bi = out[out.state_unit == "BR"].iloc[0]
    assert (bi.d24, bi.n_months_reported, bi.lb) == (12.0, 6, 600.0) and bi.d24_per_1000 == pytest.approx(20.0)
    asm = out[out.state_unit == "AS"].iloc[0]
    assert np.isnan(asm.d24) and asm.n_months_reported == 0 and np.isnan(asm.d24_per_1000)   # blank is not 0
    tot = out[out.state_unit == "TOTAL"].iloc[0]
    assert (tot.d24, tot.n_months_reported, tot.lb) == (18.0, 6, 6000.0)


def test_break_ratio_flags_rates_above_15pct():
    rows = []
    for l in ("L1", "L2"):
        for fy, m, f in (("2016-17", 3, 1.0), ("2017-18", 4, 1.0)):
            for ind, v in (("lb", 1000.0 * f), ("sb", 20.0 * f if fy == "2016-17" else 40.0), ("wt", 900.0), ("lbw", 90.0)):
                rows.append((l, fy, m, ind, v))
    out = pf.break_ratio_2017_f(_long(rows)).set_index("indicator")
    assert list(pf.break_ratio_2017_f(_long(rows)).columns) == ["indicator", "mar2017", "apr2017", "ratio",
                                                                  "gt15pct_rate", "n_units"]
    assert out.loc["lb", "ratio"] == 1.0 and out.loc["sb", "ratio"] == 2.0 and out.loc["lb", "n_units"] == 2
    assert out.loc["sbr", "ratio"] > 1.15 and bool(out.loc["sbr", "gt15pct_rate"])
    assert not bool(out.loc["lbw_share", "gt15pct_rate"]) and out.loc["wt_cov", "ratio"] == 1.0


def test_fy_total_failure_masks_the_state_fy_indicator():
    chk = pd.DataFrame([dict(state_raw="Bihar", district_raw="X", fy="2013-14", item_code="4.1.2", rel_diff=0.2,
                             **{"pass": False}, is_state_aggregate=False),
                        dict(state_raw="Bihar", district_raw="Y", fy="2013-14", item_code="4.1.2", rel_diff=0.0,
                             **{"pass": True}, is_state_aggregate=False)])
    xw = pd.DataFrame([dict(indicator="sb", era="E1", item_codes="4.1.2"), dict(indicator="sb", era="E2", item_codes="4.1.3")])
    f = pf.gate_fy_total(chk, xw)
    assert set(f.check) == {"fy_total"} and set(f.indicator) == {"sb"} and set(f.unit_id) == {"BR"}
    assert sorted(f.month) == list(range(1, 13))


def test_component_sum_gate_e1_only():
    rows = []
    for fy, ok in (("2013-14", True), ("2014-15", False), ("2018-19", False)):
        rows += [("L1", fy, 4, "lb_m", 60.0), ("L1", fy, 4, "lb_f", 40.0), ("L1", fy, 4, "lb_c", 100.0 if ok else 103.0),
                 ("L1", fy, 4, "lb", 100.0)]
    f = pf.count_gates(_long(rows))
    comp = f[f.check == "component_sum"]
    assert sorted(set(comp.fy)) == ["2014-15"]                                    # E2 has no printed total
    assert set(comp.indicator) == {"lb", "lb_m", "lb_f"}


def test_panel_shape():
    import os
    path = pf.PANEL_PATH
    if not os.path.exists(path):
        pytest.skip("git-ignored panel not built")
    p = pd.read_csv(path, dtype={"fy": str}, usecols=["link_id", "fy", "ym", "era", "sb", "flag_sb"])
    assert not p.duplicated(["link_id", "ym"]).any()
    assert (p.groupby("link_id").size() == 108).all()
    assert p.link_id.nunique() >= 600
    assert p.ym.min() == exposure.ym_of(2012, 4) and p.ym.max() == exposure.ym_of(2021, 3)


# ---- fix round 1 ------------------------------------------------------------------------------------------------
def test_fy2021_unmatched_district_makes_its_state_nan():
    rows = [dict(kind="gadm", state_unit="S1", fy="", district_raw="", region_id="R1", link_id="L1"),
            dict(kind="gadm", state_unit="S2", fy="", district_raw="", region_id="R2", link_id="L2"),
            dict(kind="hmis", state_unit="S1", fy="2020-21", district_raw="A", region_id="R1", link_id="L1"),
            dict(kind="hmis", state_unit="S1", fy="2020-21", district_raw="U", region_id=None, link_id=""),
            dict(kind="hmis", state_unit="S2", fy="2020-21", district_raw="B", region_id="R2", link_id="L2")]
    units = pd.DataFrame(rows)
    assert pf.fy2021_unmatched_states(units) == {"S1"}
    cols = {}
    for v in pf.PANEL_VARS:
        cols.update({v: 5.0, f"{v}_raw": 5.0, f"{v}_scaled": 5.0, f"{v}_masklow": 5.0, f"{v}_allcomp": 5.0,
                     f"comp_{v}": 1.0, f"flag_{v}": ""})
    w = pd.DataFrame([dict(link_id=l, state_unit=s, fy=fy, **cols)
                      for l, s in (("L1", "S1"), ("L2", "S2")) for fy in (FY1, "2020-21")])
    out = pf.apply_fy2021_unmatched(w, {"S1"})
    sel = (out.link_id == "L1") & (out.fy == "2020-21")
    assert out.loc[sel, "sb"].isna().all() and (out.loc[sel, "flag_sb"] == "fy2021_unmatched").all()
    assert out.loc[~sel, "sb"].eq(5.0).all() and (out.loc[~sel, "flag_sb"] == "").all()      # S2 and FY1 untouched


def test_incomplete_cells_are_gated_on_the_scaled_value():
    rows = [("L1", fy, 4, "sb", 100.0) for fy in ("2012-13", "2013-14", "2014-15", "2015-16")]
    long = _long(rows)

    def inc(fy, vs, comp):
        return dict(link_id="L1", state_unit="S1", fy=fy, month=4, indicator="sb", value_full=np.nan, value_sum=vs,
                    comp=comp, n_members=3, n_valid=2, n_partial=0, n_incomp=0)
    long = pd.concat([long, pd.DataFrame([inc("2016-17", 220.0, 2 / 3)]),                 # scaled 330 > 3 x 100
                      pd.DataFrame([inc("2017-18", 30.0, 0.5)]),                          # raw 30 < 33, scaled 60: fine
                      pd.DataFrame([inc("2018-19", 3000.0, 1 / 3)])], ignore_index=True)  # comp < 0.5: ungated
    f = pf.count_gates(long)
    assert [(r.fy, r.check, r.default) for r in f.itertuples()] == [("2016-17", "plausibility", "mask")]


def test_incomplete_cells_are_rate_gated_on_scaled_values():
    base = dict(link_id="L1", state_unit="S1", fy=FY1, month=4, lb=np.nan, sb=np.nan, wt=np.nan, lbw=np.nan,
                comp_lb=1.0, comp_sb=1.0, comp_wt=1.0, comp_lbw=1.0)
    w = pd.DataFrame([dict(base, lb_scaled=50.0, sb_scaled=60.0, wt_scaled=40.0, lbw_scaled=10.0, comp_sb=2 / 3)])
    f = pf.rate_gates(w)
    assert list(zip(f.indicator, f.check)) == [("sb", "rate_order")]


def test_state_failure_flags_only_cells_that_had_a_value():
    w = pd.DataFrame([dict(link_id="L1", state_unit="S1", fy=FY1, month=4, ym=exposure.ym_of(2015, 4), sb=5.0,
                           sb_raw=5.0, flag_sb=""),
                      dict(link_id="L2", state_unit="S1", fy=FY1, month=4, ym=exposure.ym_of(2015, 4), sb=np.nan,
                           sb_raw=np.nan, flag_sb=""),
                      dict(link_id="L3", state_unit="S2", fy=FY1, month=4, ym=exposure.ym_of(2015, 4), sb=5.0,
                           sb_raw=5.0, flag_sb="")])
    out, _ = pf.apply_dispositions_f(w, _fail("S1", "sb", FY1, 4, "district_sum"),
                                     pd.DataFrame(columns=REVIEWED_COLUMNS))
    assert out.flag_sb.tolist() == ["district_sum", "", ""]
    assert pf.masked_share_f(out, "sb") == pytest.approx(0.5)      # L1 masked, L3 reported; L2 never had a value
    assert pf.excluded_units(out, "sb") == ["L1"]                  # not L2: no value, nothing masked


def test_partial_year_district_is_not_a_ghost():
    cells = [(FY1, m, d, "sb", v) for m in range(1, 13) for d, v in (("A", 10),)]
    cells += [(FY1, m, "P", "sb", None) for m in range(1, 7)]                   # only 6 months present
    cells += [(FY2, m, "P", "sb", 3) for m in range(1, 13)]
    assert pf.find_ghosts(_dm(cells)).empty


def test_disposition_none_failures_is_a_noop():
    w = _wide(sb=1.0, flag_sb="")
    out, log = pf.apply_dispositions_f(w, None, pd.DataFrame(columns=REVIEWED_COLUMNS))
    assert out.sb.iloc[0] == 1 and log.empty
