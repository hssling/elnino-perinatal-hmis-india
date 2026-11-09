"""Paper F GADM link units and the R3 manual-review guard (Task 3). Synthetic names only; no files are read."""
import pandas as pd
import pytest

from pipeline.hmis import perinatal_units as pu

REV_COLS = ["state_unit", "fy", "district_raw", "parent_region_ids", "source", "disposition", "note"]


def _gadm(rows):
    return pd.DataFrame(rows, columns=["region_id", "region_name", "state_unit"])


def _names(rows):
    return pd.DataFrame(rows, columns=["state_unit", "fy", "district_raw"])


def _review(rows=()):
    return pd.DataFrame(list(rows), columns=REV_COLS)


NFHS = pd.DataFrame(columns=["round", "nfhs_code", "nfhs_name", "state_code", "state_name", "region_id", "gadm_name",
                             "match_type", "boundary_flag", "note"])


def _m(rows):
    """matches frame from (state_unit, fy, district_raw, match_type) tuples."""
    return pd.DataFrame([dict(state_unit=s, fy=fy, district_raw=d, region_id="R" + d, match_type=t, source="")
                         for s, fy, d, t in rows])


def test_same_name_in_two_states_maps_within_state():
    gadm = _gadm([("IND.5.1_1", "Aurangabad", "BR"), ("IND.20.1_1", "Aurangabad", "MH")])
    names = _names([("BR", "2012-13", "Aurangabad"), ("MH", "2012-13", "Aurangabad")])
    m = pu.match_districts(names, gadm, NFHS, _review()).set_index("state_unit")
    assert m.loc["BR", "region_id"] == "IND.5.1_1" and m.loc["MH", "region_id"] == "IND.20.1_1"
    assert set(m.match_type) == {"exact"}


def test_normalise_district_variants():
    assert pu.normalise_district("Gurgaon District") == "gurugram"
    assert pu.normalise_district("Pakaur") == "pakur"
    assert pu.normalise_district("  Dist. Foo (Bar) ") == pu.normalise_district("foo bar")
    assert pu.normalise_district("East-Khasi  Hills") == "east khasi hills"


def test_fuzzy_needs_075_and_a_clear_winner(monkeypatch):
    cands = {"R1": "alpha", "R2": "beta"}

    def with_ratios(r1, r2):
        monkeypatch.setattr(pu, "_ratio", lambda a, b: {"alpha": r1, "beta": r2}[b])

    with_ratios(0.80, 0.77)                                   # runner-up within 0.05: unclear winner
    assert pu.fuzzy_pick("zzz", cands)[0] is None
    with_ratios(0.80, 0.70)
    assert pu.fuzzy_pick("zzz", cands) == ("R1", 0.80, "R2", 0.70)
    with_ratios(0.74, 0.30)                                   # below FUZZY_MIN
    assert pu.fuzzy_pick("zzz", cands)[0] is None
    assert pu.FUZZY_MIN == 0.75


def test_fuzzy_end_to_end_is_state_constrained():
    gadm = _gadm([("IND.1.1_1", "Gulbarga", "KA"), ("IND.2.1_1", "Kalaburagi", "MH")])
    names = _names([("KA", "2012-13", "Gulbarga Dist"), ("KA", "2012-13", "Gulbargaa")])
    m = pu.match_districts(names, gadm, NFHS, _review())
    assert dict(zip(m.district_raw, m.match_type)) == {"Gulbarga Dist": "normalised", "Gulbargaa": "fuzzy"}
    assert (m.region_id == "IND.1.1_1").all()                 # never the MH district


def test_components_close_over_every_fy():
    gadm = _gadm([("IND.1.1_1", "A", "TS"), ("IND.1.2_1", "B", "TS")])
    names = _names([("TS", "2012-13", "A"), ("TS", "2012-13", "B"), ("TS", "2015-16", "X"), ("TS", "2015-16", "Y"),
                    ("TS", "2017-18", "A"), ("TS", "2017-18", "B")])
    rev = _review([("TS", "2015-16", "X", "IND.1.1_1|IND.1.2_1", "gazette", "carve_out", ""),
                   ("TS", "2015-16", "Y", "IND.1.2_1", "gazette", "assign", "")])
    m = pu.match_districts(names, gadm, NFHS, rev)
    assert set(m[m.district_raw == "X"].match_type) == {"carve_out"} and len(m[m.district_raw == "X"]) == 2
    assert m[m.district_raw == "Y"].match_type.iloc[0] == "manual"
    u = pu.link_units(m)
    assert u.link_id.nunique() == 1
    assert set(u[u.kind == "gadm"].region_id) == {"IND.1.1_1", "IND.1.2_1"}
    assert set(u[u.kind == "hmis"].district_raw) == {"A", "B", "X", "Y"}


def test_unmatched_and_fy2021_names_do_not_build_units():
    gadm = _gadm([("IND.1.1_1", "A", "TS"), ("IND.1.2_1", "B", "TS")])
    names = _names([("TS", "2012-13", "A"), ("TS", "2012-13", "B"), ("TS", "2012-13", "Q")])
    m = pu.match_districts(names, gadm, NFHS, _review())
    assert m[m.district_raw == "Q"].match_type.iloc[0] == "unmatched"
    m2 = _m([("TS", "2012-13", "A", "exact"), ("TS", "2020-21", "B", "exact")])
    assert set(pu.link_units(m2).region_id) == {"RA"}


def test_link_ids_stable_across_reruns():
    gadm = _gadm([("IND.10.1_1", "A", "S1"), ("IND.2.1_1", "B", "S2"), ("IND.2.2_1", "C", "S2")])
    names = _names([("S1", "2012-13", "A"), ("S2", "2012-13", "B"), ("S2", "2012-13", "C")])
    m = pu.match_districts(names, gadm, NFHS, _review())
    a = pu.link_units(m)
    b = pu.link_units(m.sample(frac=1, random_state=3).reset_index(drop=True))

    def key(u):
        return u[u.kind == "gadm"].set_index("region_id").link_id.sort_index()

    assert key(a).equals(key(b))
    assert dict(key(a)) == {"IND.2.1_1": "L001", "IND.2.2_1": "L002", "IND.10.1_1": "L003"}   # numeric rank


def test_manual_guard_counts_primary_combinations_only():
    rows = [("S", "2012-13", f"n{i}", "manual" if i < 9 else "exact") for i in range(100)]
    rows += [("S", "2020-21", f"z{i}", "manual") for i in range(40)]
    g = pu.check_manual_guard(_m(rows))
    assert (g["n_manual"], g["n_total"]) == (9, 100) and g["share"] == pytest.approx(0.09)
    assert (g["n_manual_fy2021"], g["n_total_fy2021"]) == (40, 40)


def test_manual_share_counts_a_name_once_across_fys_and_spellings():
    rows = [("S", fy, "Foo District", "manual") for fy in pu.PRIMARY_FYS] + [("S", "2012-13", "bar", "exact")]
    s = pu.manual_share(_m(rows))
    assert (s["n_manual"], s["n_total"]) == (1, 2)


def test_fuzzy_matches_do_not_count():
    rows = ([("S", "2012-13", f"m{i}", "manual") for i in range(5)] + [("S", "2012-13", f"f{i}", "fuzzy") for i in range(20)]
            + [("S", "2012-13", f"e{i}", "exact") for i in range(75)])
    assert pu.manual_share(_m(rows))["share"] == pytest.approx(0.05)


def test_unmatched_and_carve_out_count_as_manual():
    rows = [("S", "2012-13", "a", "unmatched"), ("S", "2012-13", "b", "carve_out"), ("S", "2012-13", "c", "nfhs"),
            ("S", "2012-13", "d", "normalised")]
    assert pu.manual_share(_m(rows))["n_manual"] == 2


def test_guard_halts_above_10pct_not_at_10pct():
    def rows(k):
        return [("S", "2012-13", f"n{i}", "manual" if i < k else "exact") for i in range(100)]
    assert pu.check_manual_guard(_m(rows(10)))["share"] == pytest.approx(0.10)
    with pytest.raises(pu.ManualReviewHalt):
        pu.check_manual_guard(_m(rows(11)))


def _units_three(link_ids=("L001", "L002", "L003")):
    return pd.DataFrame([("gadm", "S", "", "", f"R{i + 1}", lid) for i, lid in enumerate(link_ids)],
                        columns=["kind", "state_unit", "fy", "district_raw", "region_id", "link_id"])


def _m21(rows):
    return pd.DataFrame([dict(state_unit="S", fy="2020-21", district_raw=d, region_id=r, match_type=t, source="")
                         for d, r, t in rows])


def test_fy2021_split_district_sets_every_touched_unit_missing():
    m = _m21([("One", "R3", "exact"), ("Split", "R1", "carve_out"), ("Split", "R2", "carve_out"),
              ("Gone", None, "unmatched")])
    mapped = pu.map_fy2021(m, _units_three())
    st = mapped.groupby("district_raw").status.agg(set)
    assert st["One"] == {"mapped"} and st["Split"] == {"split_across_units"} and st["Gone"] == {"unmatched"}
    assert pu.fy2021_missing_units(mapped) == {"L001", "L002"}


def test_fy2021_carve_out_inside_one_unit_is_mapped():
    mapped = pu.map_fy2021(_m21([("Split", "R1", "carve_out"), ("Split", "R2", "carve_out")]),
                           _units_three(("L001", "L001", "L003")))
    assert set(mapped.status) == {"mapped"} and set(mapped.link_id) == {"L001"}
    assert pu.fy2021_missing_units(mapped) == set()


def test_unit_count_below_600_halts():
    def units(n):
        return pd.DataFrame({"kind": "gadm", "link_id": [f"L{i:03d}" for i in range(n)], "region_id": range(n)})
    assert pu.check_unit_count(units(600)) == 600
    with pytest.raises(pu.LinkUnitCountHalt):
        pu.check_unit_count(units(599))
