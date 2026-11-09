"""Paper F model table (Task 6). A synthetic two-link panel exercises the assembly; the real programme events file
drives the indicator test. No outcome is related to any exposure."""
import numpy as np
import pandas as pd
import pytest

from pipeline.hmis import perinatal_model_table as pm
from pipeline.hmis import perinatal_panel as pf
from pipeline.hmis.exposure import PRIMARY_END, PRIMARY_START, ym_of
from pipeline.hmis.model_table import programme_indicators, read_events
from pipeline.paths import DERIVED

from .test_perinatal_exposure import _clim, _enso


def _units():
    rows = []
    for link, state, dists in (("L001", "AB", ["a"]), ("L002", "AB", ["b", "c"]), ("L003", "LD", ["d"])):
        rows.append(dict(kind="gadm", state_unit=state, fy="", district_raw="", region_id="R_" + link, link_id=link))
        if link == "L002":
            rows.append(dict(kind="gadm", state_unit=state, fy="", district_raw="", region_id="R2_" + link,
                             link_id=link))
        for fy in pf.PRIMARY_FYS:
            for d in dists:
                rows.append(dict(kind="hmis", state_unit=state, fy=fy, district_raw=d, region_id="R_" + link,
                                 link_id=link))
    return pd.DataFrame(rows)


def _panel(units):
    p = pf.link_frame(units)
    for c in pf.panel_columns_f():
        if c not in p.columns:
            p[c] = np.nan
    p["tb"] = np.where(p.link_id == "L001", 400.0, 60.0)
    for v in ("lb", "sb", "wt", "lbw", "home", "inst", "lb_f"):
        p[v] = 50.0
    p.loc[p.link_id == "L001", ["inst", "home"]] = [95.0, 5.0]
    p.loc[(p.link_id == "L002") & (p.ym == ym_of(2015, 1)), "lb"] = 0.0
    p["flag_sb"] = ""
    p["flag_lbw"] = ""
    return p[pf.panel_columns_f()]


@pytest.fixture(scope="module")
def model():
    units = _units()
    return pm.assemble_model(_panel(units), _clim(("L001", "L002", "L003"), first=(2011, 1), last=(2021, 9)),
                             _enso(), units, read_events())


def test_model_table_shape(model):
    n_link = 3
    assert len(model) == n_link * 108
    assert model.ym.min() == PRIMARY_START and model.ym.max() == ym_of(2021, 3)
    assert int(model.in_primary.sum()) == n_link * 95
    assert model[model.in_primary == 1].ym.max() == PRIMARY_END
    assert not model.duplicated(["link_id", "ym"]).any()


def test_time_terms_and_keys(model):
    assert (model.t_months == model.ym - PRIMARY_START).all()
    assert np.allclose(model.t_c, (model.t_months - 47) / 12)
    assert (model.moy == model.month).all()
    assert (model.era_e2 == (model.ym >= ym_of(2017, 4)).astype(int)).all()
    assert (model.state_ym == model.state_unit + ":" + model.ym.astype(str)).all()
    assert np.allclose(model.log_days, np.log(pd.PeriodIndex.from_fields(year=model.year, month=model.month,
                                                                         freq="M").days_in_month))


def test_offsets_and_shares(model):
    a = model[model.link_id == "L001"].iloc[0]
    assert a.log_tb == pytest.approx(np.log(400)) and a.log_wt == pytest.approx(np.log(50))
    assert a.log_lb_f == pytest.approx(np.log(50))
    assert a.inst_share == pytest.approx(0.95) and a.wt_cov == pytest.approx(1.0)
    zero = model[(model.link_id == "L002") & (model.ym == ym_of(2015, 1))].iloc[0]
    assert np.isnan(zero.log_lb) and np.isnan(zero.wt_cov)                       # log(0) and x/0 are NaN, never -inf
    assert not np.isinf(model.select_dtypes("number")).any().any()


def test_unit_descriptors(model):
    d = model.groupby("link_id").first()
    assert d.small_unit.to_dict() == {"L001": 0, "L002": 1, "L003": 1}           # median tb 60 < 100; LD is a small UT
    assert d.single_district.to_dict() == {"L001": 1, "L002": 0, "L003": 1}     # L002 has two GADM districts
    assert d.inst090_all_fy.to_dict() == {"L001": 1, "L002": 0, "L003": 0}
    assert (model.small_denom_sb == (model.tb < 20)).all() and not model.small_denom_sb.any()


def test_small_denominator_flag():
    units = _units()
    p = _panel(units)
    p.loc[(p.link_id == "L001") & (p.ym == ym_of(2014, 5)), ["tb", "wt", "lb"]] = [19, 19, 19]
    p.loc[(p.link_id == "L001") & (p.ym == ym_of(2014, 6)), ["tb", "wt", "lb"]] = [20, 20, 20]
    m = pm.assemble_model(p, _clim(("L001", "L002", "L003"), last=(2021, 9)), _enso(), units, read_events())
    r = m[m.link_id == "L001"].set_index("ym")
    assert r.loc[ym_of(2014, 5), ["small_denom_sb", "small_denom_lbw"]].tolist() == [1, 1]
    assert r.loc[ym_of(2014, 6), ["small_denom_sb", "small_denom_lbw"]].tolist() == [0, 0]


def test_programme_and_covid_indicators_exact_months(model):
    one = model[model.link_id == "L001"].set_index("ym")
    on = lambda c: sorted(one.index[one[c] == 1])
    assert on("covid_mar2020") == [ym_of(2020, 3)]
    assert on("covid_lockdown") == [ym_of(2020, 4), ym_of(2020, 5), ym_of(2020, 6)]
    assert on("covid_fy2021") == list(range(ym_of(2020, 4), ym_of(2021, 3) + 1))
    assert on("demonet") == [ym_of(2016, 11), ym_of(2016, 12), ym_of(2017, 1)]
    assert on("hmis_format2017")[0] == ym_of(2017, 4) and on("hmis_format2017")[-1] == ym_of(2021, 3)
    assert on("pmsma")[0] == ym_of(2016, 6) and on("laqshya")[0] == ym_of(2017, 12)
    ev = programme_indicators(one.index, read_events()).set_index("ym")
    assert (ev.covid_mar2020 == one.covid_mar2020).all()


def test_exposure_columns_present_and_nan_discipline(model):
    for c in ("tmax_t3", "hw_t1", "spi3_dry_l6", "tmax_lead12", "spi3_dry_lead3", "en_gest", "ln_gest",
              "en_ep1415", "en_ep1819", "en_other", "tmax_l8"):
        assert c in model.columns
    first = model[(model.link_id == "L001") & (model.ym == PRIMARY_START)].iloc[0]
    assert first.tmax_t1 == first.tmax_t1                                        # April 2012 gestation is covered


def test_exclusions_follow_task4(monkeypatch):
    units = _units()
    p = _panel(units)
    m = pm.assemble_model(p, _clim(("L001", "L002", "L003"), last=(2021, 9)), _enso(), units, read_events())
    assert int(m.excluded_sb.sum()) == 0
    monkeypatch.setattr(pm, "excluded_units", lambda panel, var: ["L003"] if var == "sb" else [])
    m = pm.assemble_model(p, _clim(("L001", "L002", "L003"), last=(2021, 9)), _enso(), units, read_events())
    assert set(m.link_id[m.excluded_sb == 1]) == {"L003"} and int(m.excluded_lbw.sum()) == 0


@pytest.mark.skipif(not (pf.PANEL_PATH.exists() and (DERIVED / "hmis" / "climate_link_unit_month.csv.gz").exists()),
                    reason="local panel or climate file not present")
def test_real_model_table_in_primary_count(tmp_path):
    out = pm.build_perinatal_model(tmp_path / "m.csv.gz")
    m = pd.read_csv(out, usecols=["link_id", "ym", "in_primary"])
    n = m.link_id.nunique()
    assert len(m) == n * 108 and int(m.in_primary.sum()) == n * 95
