"""Paper F small-number release panel (Task 5, R7). Synthetic frames only."""
import numpy as np
import pandas as pd
import pytest

from pipeline.hmis import perinatal_release as pr

YM_2018 = 2018 * 12 + 5          # June 2018
YM_2015 = 2015 * 12 + 5


def _frame(cells, ym=YM_2018, state="S1", var="sb", **extra):
    """cells: {link_id: value} for one state-month and one variable; the other suppress vars get 50."""
    rows = []
    for link, v in cells.items():
        r = dict(link_id=link, state_unit=state, fy="2018-19", year=ym // 12, month=ym % 12 + 1, ym=ym,
                 lb=500.0, lb_m=260.0, lb_f=240.0, sb=50.0, wt=450.0, lbw=60.0, inst=400.0, home=20.0,
                 preterm=50.0, comp_sb=1.0, comp_lbw=1.0, flag_sb=np.nan, flag_lbw=np.nan)
        r[var] = v
        r.update(extra)
        rows.append(r)
    return pd.DataFrame(rows)


def _shown(out, var="sb"):
    return dict(zip(out.link_id, out[var].astype(object)))


def test_one_to_four_suppressed_and_zero_shown():
    out = pr.suppress_small_cells(_frame({"L1": 1, "L2": 4, "L3": 0, "L4": 5, "L5": 40, "L6": 30}))
    s = _shown(out)
    assert s["L1"] == "<5" and s["L2"] == "<5"
    assert s["L3"] == 0 and s["L4"] == 5 and s["L5"] == 40 and s["L6"] == 30


def test_preterm_suppressed_and_blank_before_2017_stays_blank():
    a = _frame({"L1": 2, "L2": 30, "L3": 40}, var="preterm", ym=YM_2018)
    b = _frame({"L1": np.nan, "L2": np.nan, "L3": np.nan}, var="preterm", ym=YM_2015)
    out = pr.suppress_small_cells(pd.concat([a, b], ignore_index=True))
    p18 = out[out.ym == YM_2018].set_index("link_id").preterm
    p15 = out[out.ym == YM_2015].preterm
    assert p18["L1"] == "<5"
    assert p18["L2"] == "<5"          # complement: the smallest non-zero cell
    assert p15.isna().all()           # blank is neither "<5" nor 0


def test_single_suppressed_cell_gets_a_complement():
    s = _shown(pr.suppress_small_cells(_frame({"L1": 3, "L2": 7, "L3": 12})))
    assert s["L1"] == "<5" and s["L2"] == "<5" and s["L3"] == 12


def test_complement_tie_breaks_on_link_id():
    s = _shown(pr.suppress_small_cells(_frame({"L001": 3, "L010": 7, "L002": 7})))
    assert s["L002"] == "<5" and s["L010"] == 7 and s["L001"] == "<5"


def test_complement_falls_back_to_zero_cell():
    s = _shown(pr.suppress_small_cells(_frame({"L001": 3, "L009": 0, "L003": 0})))
    assert s["L001"] == "<5" and s["L003"] == "<5" and s["L009"] == 0


def test_complement_ignores_blank_cells():
    s = _shown(pr.suppress_small_cells(_frame({"L1": 3, "L2": np.nan, "L3": 9})))
    assert s["L1"] == "<5" and s["L3"] == "<5" and np.isnan(s["L2"])


def test_single_unit_state_month_is_exempt_and_listed():
    df = pd.concat([_frame({"L1": 3}, state="SOLO"), _frame({"L2": 3, "L3": 8, "L4": 20}, state="S2")],
                   ignore_index=True)
    out, exempt = pr.release_panel(df)
    assert len(exempt) == 1
    e = exempt.iloc[0]
    assert (e.state_unit, e.ym, e.variable) == ("SOLO", YM_2018, "sb")
    assert _shown(out)["L1"] == "<5"
    assert pr.suppression_findings(out) == []


def test_single_unit_state_with_one_blank_neighbour_is_exempt():
    out, exempt = pr.release_panel(_frame({"L1": 2, "L2": np.nan}))
    assert len(exempt) == 1 and exempt.iloc[0].link_id == "L1"


def test_rounds_repeat_until_no_single_suppressed_cell():
    a = _frame({"L1": 3, "L2": 8, "L3": 9}, var="sb")
    a["lbw"] = [2, 6, 30]
    b = _frame({"L1": 20, "L2": 1, "L3": 0}, var="sb", ym=YM_2018 + 1)
    out = pr.suppress_small_cells(pd.concat([a, b], ignore_index=True))
    for v in pr.SUPPRESS_VARS:
        n = (out[v] == "<5").groupby([out.state_unit, out.ym]).sum()
        assert not (n == 1).any(), v
    assert pr.suppression_findings(out) == []


def test_rates_blank_for_suppressed_and_small_denominator():
    df = _frame({"L1": 3, "L2": 8, "L3": 40, "L4": 25})
    df["lb"] = [500.0, 500.0, 500.0, 10.0]
    df.loc[df.link_id == "L3", "wt"] = 15.0          # small LBW denominator
    df["lbw"] = [2, 30, 30, 60]
    out = pr.suppress_small_cells(df).set_index("link_id")
    assert out.loc[["L1", "L2"], "sbr"].isna().all()                 # suppressed (L2 by complement)
    assert out.loc["L3", "sbr"] == pytest.approx(40 / 540 * 1000, abs=1e-3)
    assert out.loc["L4", "sbr"] == pytest.approx(25 / 35 * 1000, abs=1e-3)
    assert pd.isna(out.loc["L3", "lbw_share"])                      # wt < 20
    assert out.loc["L4", "lbw_share"] == pytest.approx(60 / 450, abs=1e-4)
    tiny = _frame({"L1": 10, "L2": 50})
    tiny["lb"] = [3.0, 300.0]
    o2 = pr.suppress_small_cells(tiny).set_index("link_id")
    assert pd.isna(o2.loc["L1", "sbr"])                              # 13 < MIN_RATE_DENOM


def test_no_tb_or_d24_column_and_no_fy2021_rows():
    keep = _frame({"L1": 20, "L2": 30})
    late = _frame({"L1": 20, "L2": 30}, ym=2020 * 12 + 3)          # April 2020
    late["fy"] = "2020-21"
    fy21 = _frame({"L1": 20, "L2": 30}, ym=2020 * 12 + 4)
    fy21["fy"] = "2020-21"
    keep["tb"] = 99.0
    keep["d24"] = 1.0
    out, _ = pr.release_panel(pd.concat([keep, late, fy21], ignore_index=True))
    assert list(out.columns) == pr.RELEASE_COLUMNS
    assert "tb" not in out.columns and "d24" not in out.columns
    assert (out.fy != "2020-21").all() and (out.ym < 2020 * 12 + 3).all()


def test_suppress_is_idempotent():
    df = pd.concat([_frame({"L1": 3, "L2": 7, "L3": 12}), _frame({"L1": 0, "L2": 2, "L3": 0}, ym=YM_2018 + 1),
                    _frame({"L1": 1}, state="SOLO")], ignore_index=True)
    once = pr.suppress_small_cells(df)
    twice = pr.suppress_small_cells(once)
    pd.testing.assert_frame_equal(once.reset_index(drop=True), twice.reset_index(drop=True))


def test_findings_empty_on_suppressed_output_and_catch_each_breach():
    df = _frame({"L1": 3, "L2": 7, "L3": 12, "L4": 40})
    ok, _ = pr.release_panel(df)
    assert pr.suppression_findings(ok) == []

    def breach(edits):
        bad = ok.copy()
        for c in bad.columns:
            if c in pr.SUPPRESS_VARS:
                bad[c] = bad[c].astype(object)
        for (link, col), val in edits.items():
            bad.loc[bad.link_id == link, col] = val
        return pr.suppression_findings(bad)

    assert any("1-4" in f for f in breach({("L1", "sb"): 3}))
    assert any("one suppressed" in f for f in breach({("L2", "sb"): 7}))
    assert any("rate" in f for f in breach({("L1", "sbr"): 5.0}))
    assert any("rate" in f for f in breach({("L4", "wt"): 10.0, ("L4", "lbw_share"): 0.5}))
    for col in ("tb", "d24"):
        bad = ok.copy()
        bad[col] = 1.0
        assert any(col in f for f in pr.suppression_findings(bad))
    assert any("2020-21" in f for f in breach({("L4", "fy"): "2020-21"}))
    assert any("April 2020" in f for f in breach({("L4", "ym"): 2020 * 12 + 3}))


def test_findings_work_on_csv_roundtrip(tmp_path):
    df = pd.concat([_frame({"L1": 3, "L2": 7, "L3": 12}), _frame({"L1": np.nan, "L2": 0, "L3": 9}, ym=YM_2018 + 1)],
                   ignore_index=True)
    out, _ = pr.release_panel(df)
    p = tmp_path / "r.csv.gz"
    pr.write_release(out, p)
    back = pd.read_csv(p)
    assert pr.suppression_findings(back) == []
    assert (back["sb"] == "<5").sum() == 2
    assert not back["sb"].astype(str).str.contains(r"\.0$").any()   # counts written as integers
