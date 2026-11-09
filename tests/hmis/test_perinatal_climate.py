"""Paper F link-unit climate (Task 6). Synthetic district-month tables; the real-file test reads local derived data when
it exists. No outcome is read."""
import numpy as np
import pandas as pd
import pytest

from pipeline.hmis import perinatal_climate as pc

YEARS = range(1981, 2016)


def _month(regions, seed=1):
    """regions: {region_id: rain_scale}; district-month rows 1981-2015."""
    rng = np.random.default_rng(seed)
    rows = []
    for rid, scale in regions.items():
        for y in YEARS:
            for m in range(1, 13):
                rows.append(dict(region_id=rid, year=y, month=m, rain_mm=float(rng.gamma(2.0, scale)),
                                 tmax_mean=30 + 4 * np.sin(m / 12 * 2 * np.pi) + rng.normal(0, 1) + 0.02 * (y - 1981),
                                 heatwave_days=float(rng.integers(0, 3))))
    return pd.DataFrame(rows)


AREAS = {"d1": 1.0, "d2": 3.0, "d3": 2.0}
LINK_OF = {"d1": "L1", "d2": "L1", "d3": "L2"}


def test_link_climate_renormalises_over_nonnan_members():
    m = _month({"d1": 50, "d2": 60, "d3": 40})
    hit = (m.region_id == "d2") & (m.year == 2000) & (m.month == 5)
    m.loc[hit, ["tmax_mean", "rain_mm"]] = np.nan
    out = pc.from_district_month(m, AREAS, LINK_OF).set_index(["link_id", "year", "month"])
    a = m[(m.region_id == "d1") & (m.year == 2000) & (m.month == 5)].iloc[0]
    assert out.loc[("L1", 2000, 5), "tmax_mean"] == pytest.approx(a.tmax_mean)      # d2 drops out, d1 alone
    assert out.loc[("L1", 2000, 5), "rain_mm"] == pytest.approx(a.rain_mm)
    b = m[(m.region_id == "d1") & (m.year == 2001) & (m.month == 5)].iloc[0]
    c = m[(m.region_id == "d2") & (m.year == 2001) & (m.month == 5)].iloc[0]
    assert out.loc[("L1", 2001, 5), "tmax_mean"] == pytest.approx((1 * b.tmax_mean + 3 * c.tmax_mean) / 4)
    # no non-NaN member -> NaN, never 0
    m2 = m.copy()
    m2.loc[(m2.year == 2003) & (m2.month == 7) & m2.region_id.isin(["d1", "d2"]), "rain_mm"] = np.nan
    o2 = pc.from_district_month(m2, AREAS, LINK_OF).set_index(["link_id", "year", "month"])
    assert np.isnan(o2.loc[("L1", 2003, 7), "rain_mm"])


def test_an_rain_terms_nan_heat_present():
    m = _month({"d1": 50, "d2": 60, "d3": 40})
    m.loc[m.region_id == "d3", "rain_mm"] = np.nan                  # as the QC mask leaves A&N
    out = pc.from_district_month(m, AREAS, LINK_OF)
    an = out[out.link_id == "L2"]
    assert an.rain_mm.isna().all() and an.spi3.isna().all() and an.spi3_dry.isna().all()
    assert an.tmax_mean.notna().all() and an.tmax_anom.notna().all() and an.heatwave_days.notna().all()
    assert out[out.link_id == "L1"].spi3.notna().sum() > 400


def test_tmax_anom_against_1981_2010_calendar_month_mean():
    m = _month({"d1": 50, "d2": 60, "d3": 40})
    out = pc.from_district_month(m, AREAS, LINK_OF)
    g = out[out.link_id == "L2"]
    base = g[g.year.between(1981, 2010)]
    normal = base.groupby("month").tmax_mean.mean()
    assert np.allclose(g.tmax_anom, g.tmax_mean - g.month.map(normal))
    assert np.allclose(base.groupby("month").tmax_anom.mean(), 0, atol=1e-9)    # anomalies centre on the base
    assert g[g.year > 2010].tmax_anom.mean() > 0.2                               # the post-base warming trend stays


def test_spi3_dry_is_min_with_zero_and_ym():
    m = _month({"d1": 50, "d2": 60, "d3": 40})
    out = pc.from_district_month(m, AREAS, LINK_OF)
    assert (out.spi3_dry.dropna() <= 0).all()
    assert np.allclose(out.spi3_dry.dropna(), np.minimum(out.spi3.dropna(), 0))
    assert (out.ym == 12 * out.year + out.month - 1).all()
    assert list(out.columns) == pc.COLUMNS


def test_district_areas_sums_per_region(tmp_path):
    (tmp_path / "_parts").mkdir()
    pd.DataFrame(dict(region_id=["a", "a", "b"], ilat=[1, 1, 2], ilon=[1, 2, 3], area_km2=[1.5, 2.5, 4.0],
                      weight=[.4, .6, 1])).to_csv(tmp_path / "_parts" / "weights_r025_district.csv", index=False)
    assert pc.district_areas(tmp_path) == {"a": 4.0, "b": 4.0}


def test_gadm_members_rejects_a_district_in_two_units():
    u = pd.DataFrame(dict(kind=["gadm", "gadm", "hmis"], region_id=["a", "a", "a"], link_id=["L1", "L2", "L1"]))
    with pytest.raises(ValueError):
        pc.gadm_members(u)
