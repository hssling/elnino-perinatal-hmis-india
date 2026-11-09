"""Paper F perinatal item crosswalk (Task 1): code AND text must match, the 4.1.2/4.1.3 double trap is stopped,
missing is never zero, and Paper E's crosswalk is untouched."""
import math
import subprocess
from pathlib import Path

import pandas as pd
import pytest

from pipeline import manifest as mf
from pipeline.hmis import crosswalk as cx
from pipeline.hmis import parse as hp
from pipeline.hmis import perinatal_crosswalk as pc
from tests.hmis.release_mode import RELEASE

REPO = Path(__file__).resolve().parents[2]
FIX = Path(__file__).resolve().parent / "fixtures"
E1 = FIX / "f_e1_teststate_1213.xls.html"
E2 = FIX / "f_e2_teststate_1819.xls.html"
E3 = FIX / "f_e3_teststate_2021_apr.xlsx"


def long_of(path, fy):
    return hp.parse_member(path.name.removesuffix(".html"), path.read_bytes(), fy)


def cell(path, unit, code, month, width):
    """The raw cell text of (unit, item code, calendar month) in a fixture's first (Total) split, read straight
    from the table so that the expectation does not depend on the parser."""
    rows = hp.read_table(path.name.removesuffix(".html"), path.read_bytes())
    col = 4 + width * hp.FY_MONTHS.index(month)
    hit = [r for r in rows if len(r) > col and r[0] == unit and r[1].strip("'") == code]
    assert len(hit) == 1, (unit, code)
    return hit[0][col]


def ind(out, indicator, unit, month):
    sel = out[(out.indicator == indicator) & (out.district_raw == unit) & (out.month == month)]
    assert len(sel) == 1
    return sel.iloc[0]


@pytest.fixture(scope="module")
def xw():
    return pc.load_perinatal_crosswalk()


def edited(xw, tmp_path, mutate):
    x = xw.copy()
    mutate(x)
    p = tmp_path / "xw.csv"
    x.to_csv(p, index=False)
    return p, x


def test_loader_requires_exactly_the_wanted_rows(xw, tmp_path):
    want = sorted((v, e) for v, eras in pc.ERAS_BY_VAR.items() for e in eras)
    assert sorted(zip(xw.indicator, xw.era)) == want
    assert list(xw.columns) == cx.XW_COLUMNS
    p, _ = edited(xw, tmp_path, lambda x: x.drop(x[(x.indicator == "sb") & (x.era == "E2")].index, inplace=True))
    with pytest.raises(cx.CrosswalkError, match=r"\('sb', 'E2'\)"):
        pc.load_perinatal_crosswalk(p)
    extra = xw[(xw.indicator == "preterm") & (xw.era == "E2")].assign(era="E1")
    p = tmp_path / "xw2.csv"
    pd.concat([xw, extra]).to_csv(p, index=False)
    with pytest.raises(cx.CrosswalkError, match=r"\('preterm', 'E1'\)"):
        pc.load_perinatal_crosswalk(p)
    assert set(pc.PANEL_VARS) | set(pc.STATE_ONLY_VARS) | {"lb_c", "home_c"} == set(pc.ERAS_BY_VAR)
    assert ("d24", "E3") not in set(zip(xw.indicator, xw.era))                      # R4: no E3 row


def test_loader_rejects_wrong_combine_and_bad_pattern(xw, tmp_path):
    p, _ = edited(xw, tmp_path, lambda x: x.__setitem__("combine", x["combine"].where(x.indicator != "lb", "single")))
    with pytest.raises(cx.CrosswalkError, match="lb"):
        pc.load_perinatal_crosswalk(p)
    p, _ = edited(xw, tmp_path, lambda x: x.__setitem__("text_pattern", x.text_pattern.where(x.indicator != "wt", "(")))
    with pytest.raises(cx.CrosswalkError, match="wt"):
        pc.load_perinatal_crosswalk(p)


def test_e1_still_birth_code_is_412_and_e2_is_413(xw):
    row = lambda v, e: xw[(xw.indicator == v) & (xw.era == e)].iloc[0]       # noqa: E731
    assert row("sb", "E1").item_codes == "4.1.2" and row("sb", "E2").item_codes == "4.1.3"
    assert row("sb", "E3").item_codes == "4.1.3"
    assert row("preterm", "E2").item_codes == "4.1.2" and row("preterm", "E3").item_codes == "4.1.2"
    o1 = cx.apply_crosswalk(long_of(E1, "2012-13"), xw)
    o2 = cx.apply_crosswalk(long_of(E2, "2018-19"), xw)
    for m in (4, 7, 12):
        for u in ("District A", "District B"):
            r1 = ind(o1, "sb", u, m)
            e1 = hp.to_number(cell(E1, u, "4.1.2", m, 1))
            assert (math.isnan(r1.value) and math.isnan(e1)) or r1.value == e1
            assert r1.value != hp.to_number(cell(E1, u, "4.1.3", m, 1))       # not the abortions row
            assert ind(o2, "sb", u, m).value == hp.to_number(cell(E2, u, "4.1.3", m, 5))
            assert ind(o2, "preterm", u, m).value == hp.to_number(cell(E2, u, "4.1.2", m, 5))
    assert set(o1.indicator) == {v for v, eras in pc.ERAS_BY_VAR.items() if "E1" in eras}
    assert set(o2.indicator) == {v for v, eras in pc.ERAS_BY_VAR.items() if "E2" in eras}


def test_e1_413_abortions_never_read_as_stillbirths(xw, tmp_path):
    _, x = edited(xw, tmp_path, lambda x: x.__setitem__(
        "item_codes", x.item_codes.where(~((x.indicator == "sb") & (x.era == "E1")), "4.1.3")))
    with pytest.raises(cx.CrosswalkError, match=r"4\.1\.3") as e:
        cx.apply_crosswalk(long_of(E1, "2012-13"), x)
    assert "Abortions" in str(e.value) and E1.name.removesuffix(".html") in str(e.value)


def test_e2_412_preterm_never_read_as_stillbirths(xw, tmp_path):
    _, x = edited(xw, tmp_path, lambda x: x.__setitem__(
        "item_codes", x.item_codes.where(~((x.indicator == "sb") & (x.era == "E2")), "4.1.2")))
    with pytest.raises(cx.CrosswalkError, match=r"4\.1\.2") as e:
        cx.apply_crosswalk(long_of(E2, "2018-19"), x)
    assert "Pre term" in str(e.value)


def test_e3_mapping_and_wording(xw):
    out = cx.apply_crosswalk(long_of(E3, "2020-21"), xw)
    assert set(out.indicator) == {v for v, eras in pc.ERAS_BY_VAR.items() if "E3" in eras}
    r = out[(out.indicator == "sb") & (out.district_raw == "District A")].iloc[0]
    rows = hp.read_table(E3.name, E3.read_bytes())
    raw = [x for x in rows if len(x) > 9 and x[1].strip("'") == "4.1.3"]
    assert len(raw) == 1 and r.value == hp.to_number(raw[0][9])             # group 1 (District A), Total split


def test_lb_is_sum_of_male_and_female_with_min_count(xw):
    long = long_of(E1, "2012-13")
    a = long.district_raw == "District A"
    long.loc[a & (long.item_code == "4.1.1.a") & (long.month == 4), "value"] = 10
    long.loc[a & (long.item_code == "4.1.1.b") & (long.month == 4), "value"] = float("nan")
    long.loc[a & long.item_code.isin(["4.1.1.a", "4.1.1.b"]) & (long.month == 5), "value"] = float("nan")
    out = cx.apply_crosswalk(long, xw)
    r = ind(out, "lb", "District A", 4)
    assert (r.value, r.n_components, r.n_present) == (10, 2, 1)
    r = ind(out, "lb", "District A", 5)
    assert math.isnan(r.value) and r.n_present == 0
    # the printed total is its own row, never mixed into the sum
    assert ind(out, "lb_c", "District A", 6).value == hp.to_number(cell(E1, "District A", "4.1.1.c", 6, 1))


def test_lb_fixture_cells_missing_are_nan(xw):
    out = cx.apply_crosswalk(long_of(E1, "2012-13"), xw)
    r = ind(out, "lb", "District B", 5)                          # fixture: female cell "NA" in May
    assert r.n_present == 1 and r.value == hp.to_number(cell(E1, "District B", "4.1.1.a", 5, 1))
    r = ind(out, "lb", "District B", 6)                          # both cells "NA" in June
    assert math.isnan(r.value) and r.n_present == 0


def test_sb_zero_is_real_zero(xw):
    out = cx.apply_crosswalk(long_of(E1, "2012-13"), xw)
    r = ind(out, "sb", "District A", 4)                          # fixture: "0"
    assert r.value == 0 and r.n_present == 1


def test_d24_e1_blank_is_nan_never_zero(xw):
    out = cx.apply_crosswalk(long_of(E1, "2012-13"), xw)
    r = ind(out, "d24", "District B", 4)                         # fixture: blank cell
    assert math.isnan(r.value) and r.n_present == 0
    assert not (out[out.indicator == "d24"].value == 0).any()
    o2 = cx.apply_crosswalk(long_of(E2, "2018-19"), xw)
    assert ind(o2, "d24", "District A", 4).value == hp.to_number(cell(E2, "District A", "16.1", 4, 5))


def test_d24_not_parsed_from_e3(xw):
    long = long_of(E3, "2020-21")
    assert (long.item_code == "16.1").any()                      # the item is in the file ...
    assert "d24" not in set(cx.apply_crosswalk(long, xw).indicator)   # ... but the crosswalk has no E3 row


def test_home_and_inst_components(xw):
    o1 = cx.apply_crosswalk(long_of(E1, "2012-13"), xw)
    r = ind(o1, "inst", "District A", 7)
    assert r.n_components == 2 and r.value == (hp.to_number(cell(E1, "District A", "2.2", 7, 1))
                                               + hp.to_number(cell(E1, "District A", "2.3", 7, 1)))
    r = ind(o1, "home", "District A", 7)
    assert r.n_components == 2 and r.value == (hp.to_number(cell(E1, "District A", "2.1.1.a", 7, 1))
                                               + hp.to_number(cell(E1, "District A", "2.1.1.b", 7, 1)))
    assert ind(o1, "home_c", "District A", 7).n_components == 1
    o2 = cx.apply_crosswalk(long_of(E2, "2018-19"), xw)
    assert ind(o2, "inst", "District A", 7).n_components == 1
    assert ind(o2, "inst", "District A", 7).value == hp.to_number(cell(E2, "District A", "2.2", 7, 5))


def test_paper_e_crosswalk_unchanged():
    assert len(cx.load_crosswalk()) == 21
    if RELEASE:
        pytest.skip("release mode: no version-control tags")
    tracked = subprocess.run(["git", "-C", str(REPO), "show", "paperE-submitted:pipeline/reference/"
                              "hmis_item_crosswalk.csv"], capture_output=True, check=True).stdout
    assert cx.XW_PATH.read_bytes() == tracked


def test_perinatal_rows_verified_in_manifest(xw):
    assert cx.verify_crosswalk(xw, mf.read()) == []
    assert all("::" in v or v.endswith(".xlsx") for v in xw.verified_in_file)


def test_parse_sample_absent_files_fail(tmp_path, monkeypatch, capsys):
    from pipeline.hmis import run_f
    monkeypatch.setattr(run_f.hf, "HMIS_ROOT", tmp_path / "nowhere")
    res = run_f.parse_sample()
    assert res["absent"] and any("nowhere" in a or "absent" in a or a for a in res["absent"])
    assert run_f.main(["parse-sample"]) == 1
    assert "files absent" in capsys.readouterr().out


def test_parse_sample_missing_member_names_zip_and_member(tmp_path, monkeypatch, capsys):
    from pipeline.hmis import run_f
    monkeypatch.setattr(run_f, "SAMPLE_MEMBER", "No Such State.xls")
    res = run_f.parse_sample()
    assert res["absent"]
    assert "No Such State.xls" in capsys.readouterr().out
