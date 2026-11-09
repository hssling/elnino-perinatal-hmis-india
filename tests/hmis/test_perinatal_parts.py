"""Paper F perinatal district-month parts (Task 2). Synthetic fixtures only; every file goes to tmp_path."""
import importlib.util
import math
import zipfile
from pathlib import Path

import pandas as pd
import pytest

from pipeline.hmis import fetch as hf
from pipeline.hmis import flags as hfl
from pipeline.hmis import perinatal_crosswalk as pc
from pipeline.hmis import perinatal_parts as pp
from pipeline.hmis import run
from tests.hmis.test_panel import across_states_html

FIX = Path(__file__).resolve().parent / "fixtures"
E1 = FIX / "f_e1_teststate_1213.xls.html"
E2 = FIX / "f_e2_teststate_1819.xls.html"


def _mk():
    spec = importlib.util.spec_from_file_location("hmis_make_fixtures_f", FIX / "make_fixtures_f.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="module")
def xw():
    return pc.load_perinatal_crosswalk()


def _root(tmp_path, with_zero=False):
    """Folder-3 zips for FY2012-13 (E1) and FY2018-19 (E2); `with_zero` makes a 4.1.3 (stillbirth) zero in July
    for District A of the E2 member, whose other months are >= 100 (so the district median is >= 20)."""
    mk = _mk()
    root = tmp_path / "hmis"
    z3 = root / run.FOLDER3
    z3.mkdir(parents=True)
    e2 = E2.read_bytes()
    if with_zero:
        mk.mk.SPECIAL[("f_e2z", "District A", "4.1.3", 7)] = "0"
        e2 = mk.mk.sas_html("f_e2z", "District", "Test State", "2018-2019", "06 Nov 2020, 2:00 PM",
                            ["District A", "District B"], mk.E2_ITEMS, splits=True)
    allindia = lambda fy4, items, splits, fx: mk.mk.sas_html(fx, "State", "All India", fy4, "19SEP2015",
                                                           ["Test State", "M/O Defence"], items, splits=splits)
    with zipfile.ZipFile(z3 / "2012-2013.zip", "w") as z:
        z.writestr("2012-2013/Test State.xls", E1.read_bytes())
        z.writestr("2012-2013/All_India.xls", allindia("2012-2013", mk.E1_ITEMS, False, "f_e1ai"))
        z.writestr("2012-2013/M O Defence.xls", b"<html><h1>Data ItemWise Report for - M/O Defence</h1></html>")
    with zipfile.ZipFile(z3 / "2018-2019.zip", "w") as z:
        z.writestr("2018-2019/Test State.xls", e2)
    return root


@pytest.fixture(scope="module")
def run_e1_e2(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("parts")
    root = _root(tmp)
    out = tmp / "_parts_f"
    res = pp.perinatal_parts(out_dir=out, root=root, fys=["2012-13", "2018-19"], report_path=tmp / "rep.csv")
    return res, out, tmp


def test_parts_use_the_perinatal_crosswalk(run_e1_e2):
    res, out, _ = run_e1_e2
    dm = res["tables"]["district_month"]
    for fy, era in (("2012-13", "E1"), ("2018-19", "E2")):
        got = set(dm[dm.fy == fy].indicator)
        assert got == {v for v, eras in pc.ERAS_BY_VAR.items() if era in eras}
        assert set(pc.PANEL_VARS + pc.STATE_ONLY_VARS) - got == ({"preterm"} if era == "E1" else set())
    assert {"lb_c", "home_c"} <= set(dm[dm.fy == "2012-13"].indicator)         # E1 check items stay in the parts
    assert not set(dm.indicator) & {"anc_reg", "opd"}                           # nothing of Paper E's
    for k in run.TABLES:
        assert (out / f"{k}.csv.gz").exists()
    # the 4.1.2/4.1.3 trap: E1 still births come from 4.1.2, E2 from 4.1.3 (formula: 100*(item+1) + 10*unit + month)
    sb1 = dm[(dm.fy == "2012-13") & (dm.indicator == "sb") & (dm.district_raw == "District B") & (dm.month == 5)]
    sb2 = dm[(dm.fy == "2018-19") & (dm.indicator == "sb") & (dm.district_raw == "District B") & (dm.month == 5)]
    assert sb1.value.iloc[0] == 100 * (8 + 1) + 10 + 5 and sb2.value.iloc[0] == 100 * (6 + 1) + 10 + 5


def test_flags_applied_and_flagged_cells_nan(tmp_path):
    root = _root(tmp_path, with_zero=True)
    res = pp.perinatal_parts(out_dir=tmp_path / "p", root=root, fys=["2018-19"], report_path=tmp_path / "r.csv")
    dm = res["tables"]["district_month"]
    sel = dm[(dm.indicator == "sb") & (dm.district_raw == "District A") & (dm.month == 7)].iloc[0]
    assert sel.value_raw == 0 and bool(sel.nonreport) and math.isnan(sel.value)
    other = dm[(dm.indicator == "sb") & (dm.district_raw == "District A") & (dm.month == 8)].iloc[0]
    assert not other.nonreport and other.value == other.value_raw > 0
    assert list(dm.columns) == hfl.DM_COLUMNS


def test_missing_cells_are_nan_not_zero(run_e1_e2):
    dm = run_e1_e2[0]["tables"]["district_month"]
    d = dm[(dm.fy == "2012-13") & (dm.district_raw == "District B")]
    d24 = d[(d.indicator == "d24") & (d.month == 4)].iloc[0]                    # blank cell
    assert math.isnan(d24.value_raw) and math.isnan(d24.value)
    lb6 = d[(d.indicator == "lb") & (d.month == 6)].iloc[0]                      # both components "NA"
    assert math.isnan(lb6.value)
    lb5 = d[(d.indicator == "lb") & (d.month == 5)].iloc[0]                      # female "NA", male present
    assert lb5.n_present == 1 and lb5.n_components == 2


def test_mo_members_excluded(run_e1_e2):
    mem = run_e1_e2[0]["tables"]["members"].set_index("member")
    assert mem.loc["2012-2013/M O Defence.xls", "status"] == "excluded"
    assert mem.loc["2012-2013/All_India.xls", "excluded_units"] == 1             # the M/O Defence state row
    assert run_e1_e2[0]["errors"] == 0 and run_e1_e2[0]["excluded"] == ["2012-2013/M O Defence.xls"]
    st = run_e1_e2[0]["tables"]["state_month"]
    assert set(st.state_raw) == {"Test State"}


def test_flag_report_counts_only(run_e1_e2):
    res, _, tmp = run_e1_e2
    rep = res["report"]
    assert list(rep.columns) == hfl.REPORT_COLUMNS and "district_raw" not in rep.columns
    assert set(rep.indicator) == set(pc.PANEL_VARS + pc.STATE_ONLY_VARS) and set(rep.fy) == {"2012-13", "2018-19"}
    assert len(rep) == 2 * len(pp.REPORT_VARS)
    text = (tmp / "rep.csv").read_text(encoding="utf-8")
    assert "District" not in text and "Test State" not in text
    pre = rep[(rep.indicator == "preterm") & (rep.fy == "2012-13")].iloc[0]
    assert pre.n_district_months == 0 and "not collected" in pre.notes


def test_stops_below_2gb(tmp_path, monkeypatch):
    root = _root(tmp_path)
    monkeypatch.setattr(hf, "free_bytes", lambda p: 1024 ** 3)
    out = tmp_path / "_parts_f"
    with pytest.raises(RuntimeError, match="2 GB"):
        pp.perinatal_parts(out_dir=out, root=root, fys=["2012-13"], report_path=tmp_path / "r.csv")
    assert not out.exists() and not (tmp_path / "r.csv").exists()


def test_national_is_net_of_mo_rows(tmp_path, xw):
    mk = _mk()
    root = _root(tmp_path)
    f1 = root / run.FOLDER1
    f1.mkdir()
    items = [(c, t, "TOTAL") for c, t, _ in mk.E1_ITEMS]
    with zipfile.ZipFile(f1 / "2012-2013.zip", "w") as z:
        z.writestr("2012-2013/A.MonthWise/A - April.xls",
                   across_states_html(fy4="2012-2013", items=items))
    out = tmp_path / "n" / "national_month.csv.gz"
    nat = pp.perinatal_national(out=out, root=root, fys=["2012-13"])
    assert out.exists() and list(nat.columns) == pp.NATIONAL_COLUMNS
    assert set(nat.indicator) == {v for v, e in pc.ERAS_BY_VAR.items() if "E1" in e}
    apr = nat[(nat.month == 4) & (nat.indicator == "sb")].iloc[0]
    assert apr.mo_value > 0 and apr.national == pytest.approx(apr.all_india - apr.mo_value)
    assert math.isnan(nat[(nat.month == 5) & (nat.indicator == "sb")].iloc[0].national)   # no month file: NaN


def test_national_f39_blank_mo_counts_as_zero(xw):
    """F39: M/O columns present and M/O value absent -> national == all_india; a present M/O value is subtracted."""
    import numpy as np
    mk = _mk()
    items = [(c, t, "TOTAL") for c, t, _ in mk.E1_ITEMS]
    data = across_states_html(fy4="2012-2013", items=items)
    empty_mo = pd.DataFrame(columns=["fy", "month", "indicator", "mo_value"])
    nat = pp._national_fy("2012-13", {4: "2012-2013/A.MonthWise/A - April.xls"}, lambda n: data, xw, empty_mo)
    apr = nat[nat.month == 4]
    assert apr.all_india.notna().all() and apr.mo_value.isna().all()
    assert np.allclose(apr.national, apr.all_india)
    mo = pd.DataFrame({"fy": "2012-13", "month": 4, "indicator": ["sb"], "mo_value": [7.0]})
    sb = pp._national_fy("2012-13", {4: "x/A - April.xls"}, lambda n: data, xw, mo).query("month == 4 and indicator == 'sb'")
    assert sb.national.iloc[0] == sb.all_india.iloc[0] - 7.0


def test_missing_primary_fy_source_raises_and_writes_nothing(tmp_path):
    root = _root(tmp_path)                                    # has FY2012-13 and FY2018-19 only
    out, rep = tmp_path / "_parts_f", tmp_path / "perinatal_flag_report.csv"
    rep.write_text("sentinel\n", encoding="utf-8")
    with pytest.raises(pp.MissingSourcesError, match="2013-14.*2019-20|2013-14"):
        pp.perinatal_parts(out_dir=out, root=root, fys=["2012-13", "2013-14", "2019-20"], report_path=rep)
    assert not out.exists() and rep.read_text(encoding="utf-8") == "sentinel\n"
    with pytest.raises(pp.MissingSourcesError, match="2012-13"):
        pp.perinatal_national(out=tmp_path / "n.csv.gz", root=root, fys=["2012-13"])    # folder 1 absent
    assert not (tmp_path / "n.csv.gz").exists()


def test_cli_exits_nonzero_on_missing_sources(monkeypatch, capsys):
    from pipeline.hmis import run_f

    def boom(*a, **k):
        raise pp.MissingSourcesError("missing primary-FY sources, nothing written: 2013-14")
    monkeypatch.setattr(pp, "perinatal_parts", boom)
    monkeypatch.setattr(pp, "perinatal_national", boom)
    assert run_f.main(["parts"]) == 1 and run_f.main(["national"]) == 1
    assert "2013-14" in capsys.readouterr().err
