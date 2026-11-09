"""Paper F gestational exposure terms (Task 6). Synthetic climate and ENSO frames, except the episode-window test, which
reads data/derived/enso_monthly.csv. No outcome is read."""
import numpy as np
import pandas as pd
import pytest

from pipeline.hmis import perinatal_exposure as pe
from pipeline.hmis.exposure import PRIMARY_END, PRIMARY_START, ym_of
from pipeline.paths import DERIVED

ENSO_PATH = DERIVED / "enso_monthly.csv"


def _enso(first=(2011, 1), last=(2021, 12), seed=3):
    """oni_anom row for centre month c; enso_exposures reads the season ending in t from row t - 1."""
    rng = np.random.default_rng(seed)
    rows = []
    for t in range(ym_of(*first), ym_of(*last) + 1):
        rows.append(dict(year=t // 12, month=t % 12 + 1, oni_anom=round(float(rng.normal(0, 1)), 2),
                         roni=round(float(rng.normal(0, 1)), 2), nino34_anom=float(rng.normal(0, 1)),
                         dmi=float(rng.normal(0, .3))))
    return pd.DataFrame(rows)


def _clim(links=("L1", "L2"), first=(2011, 1), last=(2020, 12), seed=5):
    rng = np.random.default_rng(seed)
    rows = [dict(link_id=l, ym=t, tmax_anom=float(rng.normal(0, 1)), heatwave_days=float(rng.integers(0, 4)),
                 spi3_dry=float(-abs(rng.normal(0, 1)))) for l in links
            for t in range(ym_of(*first), ym_of(*last) + 1)]
    return pd.DataFrame(rows)


YMS = list(range(PRIMARY_START, ym_of(2021, 3) + 1))


@pytest.mark.skipif(not ENSO_PATH.exists(), reason="enso_monthly.csv not present")
def test_episode_windows_from_oni():
    w = pe.episode_windows(pd.read_csv(ENSO_PATH))
    assert w == pe.EPISODES_F
    assert pe.EPISODES_F == {"ep1415": (ym_of(2014, 10), ym_of(2017, 2)), "ep1819": (ym_of(2018, 9), ym_of(2020, 2))}
    # the last El Nino months (ONI of the season ending in the month >= 0.5) are June 2016 and April 2020
    from pipeline.hmis.exposure import enso_exposures
    e = enso_exposures(pd.read_csv(ENSO_PATH), range(ym_of(2014, 10), ym_of(2020, 8) + 1)).set_index("ym").oni
    last1 = e.loc[ym_of(2014, 10):ym_of(2016, 12) + 6].pipe(lambda s: s.index[s >= .5].max())
    last2 = e.loc[ym_of(2018, 9):ym_of(2020, 2) + 6].pipe(lambda s: s.index[s >= .5].max())
    assert (last1, last2) == (ym_of(2016, 6), ym_of(2020, 4))
    assert last1 + 8 == pe.EPISODES_F["ep1415"][1] and last2 + 8 > PRIMARY_END     # ep1819 cut at the cap


def test_episode_windows_extend_cap_and_no_el_nino():
    enso = _enso()
    enso["oni_anom"] = 0.0
    enso.loc[(enso.year == 2013) & enso.month.between(3, 5), "oni_anom"] = 1.0          # seasons ending Apr-Jun 2013
    w = pe.episode_windows(enso, spans={"x": (ym_of(2013, 1), ym_of(2013, 3))}, extend=8, tail=6, cap=ym_of(2014, 1))
    assert w == {"x": (ym_of(2013, 1), ym_of(2014, 1))}                                 # Jun 2013 + 8 = Feb 2014 -> cap
    w = pe.episode_windows(enso, spans={"x": (ym_of(2013, 1), ym_of(2013, 3))}, extend=2, tail=6, cap=ym_of(2020, 2))
    assert w == {"x": (ym_of(2013, 1), ym_of(2013, 8))}
    with pytest.raises(ValueError):
        pe.episode_windows(enso, spans={"y": (ym_of(2016, 1), ym_of(2016, 3))})


def test_episode_terms_partition_en_gest():
    enso, clim = _enso(), _clim()
    enso.loc[:, "oni_anom"] = enso.oni_anom.abs() + 0.1                                 # keep en_t positive everywhere
    t = pe.gestation_terms(clim, enso, YMS)
    s = t.en_ep1415 + t.en_ep1819 + t.en_other
    ok = t.en_gest.notna()
    assert ok.any() and np.allclose(s[ok], t.en_gest[ok])
    a, b = pe.EPISODES_F["ep1415"]
    inside = t.ym.between(a, b)
    assert (t.loc[inside & ok, "en_ep1415"] == t.loc[inside & ok, "en_gest"]).all()
    assert (t.loc[inside & ok, ["en_ep1819", "en_other"]] == 0).all().all()
    late = t.ym >= ym_of(2020, 3)                                                        # March 2020 onward
    assert (t.loc[late, "en_other"] == t.loc[late, "en_gest"]).all()
    assert (t.loc[late, ["en_ep1415", "en_ep1819"]] == 0).all().all()
    assert t.loc[late, "en_gest"].gt(0).all()


def test_trimester_strata_are_lag_means():
    clim, enso = _clim(), _enso()
    t = pe.gestation_terms(clim, enso, YMS)
    c = clim.set_index(["link_id", "ym"])
    m = ym_of(2015, 7)
    row = t[(t.link_id == "L2") & (t.ym == m)].iloc[0]
    v = lambda k, col: c.loc[("L2", m - k), col]
    assert row.tmax_t3 == pytest.approx(np.mean([v(k, "tmax_anom") for k in (0, 1, 2)]))
    assert row.tmax_t2 == pytest.approx(np.mean([v(k, "tmax_anom") for k in (3, 4, 5)]))
    assert row.tmax_t1 == pytest.approx(np.mean([v(k, "tmax_anom") for k in (6, 7, 8)]))
    assert row.hw_t3 == pytest.approx(np.mean([v(k, "heatwave_days") for k in (0, 1, 2)]))
    assert row.hw_t1 == pytest.approx(np.mean([v(k, "heatwave_days") for k in (6, 7, 8)]))
    for k in range(9):
        assert row[f"tmax_l{k}"] == pytest.approx(v(k, "tmax_anom"))
    assert (row.spi3_dry_l0, row.spi3_dry_l3, row.spi3_dry_l6) == (v(0, "spi3_dry"), v(3, "spi3_dry"), v(6, "spi3_dry"))
    assert row.tmax_lead12 == pytest.approx(np.mean([c.loc[("L2", m + 1), "tmax_anom"], c.loc[("L2", m + 2), "tmax_anom"]]))
    assert row.spi3_dry_lead3 == c.loc[("L2", m + 3), "spi3_dry"]
    e = enso.set_index(enso.year * 12 + enso.month - 1).oni_anom                         # season ending in t = row t - 1
    en = [max(e.loc[m - k - 1], 0) for k in range(9)]
    ln = [min(e.loc[m - k - 1], 0) for k in range(9)]
    assert row.en_gest == pytest.approx(np.mean(en)) and row.ln_gest == pytest.approx(np.mean(ln))


def test_lags_and_leads_merge_on_ym_at_window_edges():
    clim, enso = _clim(last=(2020, 5)), _enso()
    t = pe.gestation_terms(clim, enso, range(PRIMARY_START, PRIMARY_END + 1))
    c = clim.set_index(["link_id", "ym"])
    first = t[(t.link_id == "L1") & (t.ym == PRIMARY_START)].iloc[0]
    assert first.tmax_l8 == c.loc[("L1", ym_of(2011, 8)), "tmax_anom"]                   # April 2012 uses August 2011
    assert first.tmax_t1 == pytest.approx(np.mean([c.loc[("L1", ym_of(2011, mm)), "tmax_anom"] for mm in (8, 9, 10)]))
    last = t[(t.link_id == "L1") & (t.ym == PRIMARY_END)].iloc[0]
    assert last.spi3_dry_lead3 == c.loc[("L1", ym_of(2020, 5)), "spi3_dry"]              # Feb 2020 lead +3 = May 2020
    # a missing month leaves the lag NaN, never the previous row
    gap = clim[~((clim.link_id == "L1") & (clim.ym == ym_of(2012, 6)))]
    tg = pe.gestation_terms(gap, enso, range(PRIMARY_START, PRIMARY_END + 1))
    r = tg[(tg.link_id == "L1") & (tg.ym == ym_of(2012, 8))].iloc[0]                     # lag 2 of Aug 2012 is June 2012
    assert np.isnan(r.tmax_l2) and np.isnan(r.tmax_t3) and np.isnan(r.hw_t3)
    assert not np.isnan(r.tmax_l1) and not np.isnan(r.tmax_t2)
    r2 = tg[(tg.link_id == "L2") & (tg.ym == ym_of(2012, 8))].iloc[0]
    assert not np.isnan(r2.tmax_t3)                                                      # other link units are untouched
    # leads beyond the climate table are NaN
    beyond = pe.gestation_terms(clim, enso, [ym_of(2020, 3)]).iloc[0]
    assert np.isnan(beyond.spi3_dry_lead3) and not np.isnan(beyond.tmax_lead12)
    # a missing ENSO month leaves the gestation mean NaN
    enso_gap = enso[~((enso.year == 2013) & (enso.month == 5))]
    tgap = pe.gestation_terms(clim, enso_gap, [ym_of(2013, 8), ym_of(2014, 8)])
    assert tgap.set_index("ym").en_gest.loc[ym_of(2013, 8)].isna().all()
    assert tgap.set_index("ym").en_gest.loc[ym_of(2014, 8)].notna().all()


def test_gestation_term_columns():
    t = pe.gestation_terms(_clim(), _enso(), YMS)
    want = (["link_id", "ym", "tmax_t3", "tmax_t2", "tmax_t1", "hw_t3", "hw_t2", "hw_t1"]
            + [f"tmax_l{k}" for k in range(9)] + ["spi3_dry_l0", "spi3_dry_l3", "spi3_dry_l6", "tmax_lead12",
               "spi3_dry_lead3", "en_gest", "ln_gest", "en_roni_gest", "ln_roni_gest", "en_ep1415", "en_ep1819",
               "en_other"])
    assert list(t.columns) == want
    assert len(t) == 2 * len(YMS)
