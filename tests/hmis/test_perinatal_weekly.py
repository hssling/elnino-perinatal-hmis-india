"""Paper F: weekly gestational exposures (pipeline/hmis/perinatal_weekly.py). Synthetic inputs only; no
outcome and no grid file is read."""
from datetime import date

import numpy as np
import pandas as pd
import pytest

from pipeline.hmis import perinatal_weekly as pw

DAY0 = date(2010, 1, 1)


def _linear(n_days=3000, n_units=2):
    """x[t, l] = t + 1000 l: a week mean ending on day e is e - 3 + 1000 l."""
    t = np.arange(n_days, dtype=float)
    return np.column_stack([t + 1000 * l for l in range(n_units)])


@pytest.mark.parametrize("year,month,n_days", [(2012, 1, 31), (2011, 2, 28)])
def test_gestational_alignment_week_means_31_and_28_day_months(year, month, n_days):
    x = _linear()
    days = pw.birth_days(year, month, DAY0)
    assert len(days) == n_days
    out = pw.gestational_weeks(pw.heat_week_values(x), days)                 # (40, 2)
    d_mean = days.mean()                                                      # first day + (n_days - 1) / 2
    for w in (1, 13, 28, 40):
        # week w covers d - 280 + 7(w - 1) .. d - 280 + 7w - 1; its mean is d - 280 + 7w - 4
        assert out[w - 1, 0] == pytest.approx(d_mean - 280 + 7 * w - 4)
        assert out[w - 1, 1] == pytest.approx(d_mean - 280 + 7 * w - 4 + 1000)
    # week 40 ends the day before birth; week 1 starts 280 days before birth
    first = days[0]
    assert out[39, 0] == pytest.approx(np.mean([np.mean(np.arange(d - 7, d)) for d in days]))
    assert out[0, 0] == pytest.approx(np.mean([np.mean(np.arange(d - 280, d - 273)) for d in days]))
    assert first - 280 >= 0


def test_gestational_alignment_39_weeks_and_point_values():
    x = _linear()
    days = pw.birth_days(2012, 3, DAY0)
    out39 = pw.gestational_weeks(pw.heat_week_values(x), days, n_weeks=39, gest_days=273)
    assert out39.shape == (39, 2)
    assert out39[38, 0] == pytest.approx(days.mean() - 4)                     # week 39 ends the day before birth
    assert out39[0, 0] == pytest.approx(days.mean() - 273 + 3)
    # a point series (the deficit is read on the last day of each week)
    pt = pw.gestational_weeks(x, days)
    assert pt[39, 0] == pytest.approx(days.mean() - 1)
    assert pt[0, 0] == pytest.approx(days.mean() - 280 + 6)


def test_spi28_truncation_and_fit():
    rng = np.random.default_rng(3)
    dates = pd.date_range("1981-01-01", "2012-12-31", freq="D")
    rain = rng.gamma(0.5, 8.0, size=(len(dates), 2))
    rain[rng.random(rain.shape) < 0.4] = 0.0
    spi = pw.spi_daily(rain, dates)
    assert np.isnan(spi[:27]).all()                                           # incomplete first windows
    base = (dates.year <= 2010) & np.isfinite(spi[:, 0])
    assert abs(np.nanmean(spi[base, 0])) < 0.1 and 0.85 < np.nanstd(spi[base, 0]) < 1.15
    d = pw.deficit(spi)
    assert np.nanmax(d) == 0.0
    pos = spi > 0
    assert (d[pos] == 0).all()
    neg = spi < 0
    assert np.array_equal(d[neg], spi[neg])
    assert np.isnan(pw.deficit(np.array([np.nan, -1.2, 0.7])))[0]
    assert pw.deficit(np.array([np.nan, -1.2, 0.7]))[1:].tolist() == [-1.2, 0.0]
    # a 28-day total of exactly 0 takes H(0) = q / 2 -> a negative SPI (dry), never "normal"
    rain2 = rain.copy()
    rain2[-40:, 0] = 0.0
    assert pw.spi_daily(rain2, dates)[-1, 0] < -1


def test_spi_week_of_year_has_52_weeks():
    w = pw.week_of_year(pd.date_range("2012-01-01", "2012-12-31", freq="D"))
    assert w.min() == 0 and w.max() == 51 and (w == 51).sum() == 9               # leap year: days 358-366
    w = pw.week_of_year(pd.date_range("2013-01-01", "2013-12-31", freq="D"))
    assert (w == 51).sum() == 8


def test_negative_control_windows_lie_after_birth():
    x = _linear()
    days = pw.birth_days(2012, 2, DAY0)                                        # 29 days (leap year)
    assert len(days) == 29
    heat = pw.after_birth(pw.heat_nc_values(x), days)
    # mean over d + 1 .. d + 56 is d + 28.5
    assert heat[0] == pytest.approx(days.mean() + 28.5)
    dry_point = pw.after_birth(x, days)                                        # value read on day d + 56
    assert dry_point[0] == pytest.approx(days.mean() + 56)
    # a NaN on or before the first birth day does not touch the controls; a NaN after birth does
    y = x.copy()
    y[days[0] - 30: days[0] + 1, 0] = np.nan
    assert np.isfinite(pw.after_birth(pw.heat_nc_values(y), days)[0])
    y = x.copy()
    y[days[-1] + 56, 0] = np.nan
    assert np.isnan(pw.after_birth(pw.heat_nc_values(y), days)[0])
    assert np.isnan(pw.after_birth(y, days)[0])
    assert np.isfinite(pw.after_birth(y, days)[1])


def test_nan_propagates_never_zero():
    x = _linear()
    days = pw.birth_days(2012, 1, DAY0)
    y = x.copy()
    hole = days[10] - 280 + 7 * 5 - 1 - 2                                      # inside week 5 of one birth day
    y[hole, 0] = np.nan
    out = pw.gestational_weeks(pw.heat_week_values(y), days)
    assert np.isnan(out[4, 0])                                                 # strict: NaN, not a partial mean
    assert np.isfinite(out[4, 1])                                              # other unit untouched
    assert np.isfinite(out[20, 0])
    assert not (out[np.isnan(out) == False] == 0).any()
    # rolling sums: a NaN day blanks every window containing it, and nothing becomes 0
    r = np.ones((40, 1)); r[10] = np.nan
    s = pw.rolling_sum_strict(r, 28)
    assert np.isnan(s[:38]).all() and s[38, 0] == 28 and s[39, 0] == 28
    # out-of-range days are NaN
    early = pw.gestational_weeks(pw.heat_week_values(x), np.array([100]))
    assert np.isnan(early[0]).all()
    # district -> link pooling: renormalised over non-NaN members; no member -> NaN
    ids, M = pw.link_pool_matrix(["a", "b", "c"], {"a": "L1", "b": "L1", "c": "L2"}, {"a": 1.0, "b": 3.0, "c": 2.0})
    dist = np.array([[1.0, 2.0, np.nan], [np.nan, 2.0, 5.0], [1.0, 5.0, 3.0]])
    p = pw.pool_daily(dist, M)
    assert ids == ["L1", "L2"]
    assert p[0, 0] == pytest.approx(1.75) and np.isnan(p[0, 1])
    assert p[1, 0] == pytest.approx(2.0) and p[1, 1] == pytest.approx(5.0)
    assert p[2, 0] == pytest.approx(4.0)


def test_district_qc_days_cover_masked_months():
    q = pd.DataFrame({"region_id": ["d1", "d2"], "year": [2012, 2012], "variable": ["rain_jjas_mm", "rain_annual_mm"]})
    m = pw.district_qc_days(q, ["d1", "d2", "d3"], 2012)
    assert m.shape == (366, 3)
    assert m[:, 0].sum() == 30 + 31 + 31 + 30 and m[:, 1].all() and not m[:, 2].any()
    assert not pw.district_qc_days(q, ["d1", "d2"], 2013).any()


def test_tmax_anomaly_against_base_day_of_year_mean():
    dates = pd.date_range("1981-01-01", "2012-12-31", freq="D")
    doy = np.asarray(dates.dayofyear)
    tmax = (30 + 5 * np.sin(2 * np.pi * doy / 366))[:, None] + np.zeros((1, 2))
    tmax[dates.year == 2012, 1] += 2.0
    a = pw.tmax_anomaly(tmax, dates)
    assert np.nanmax(np.abs(a[dates.year <= 2010])) < 0.15                     # smoothing error only
    assert np.nanmean(a[dates.year == 2012, 1]) == pytest.approx(2.0, abs=0.05)


def test_oni_gestation_average_and_primary_window_only():
    dates = pd.date_range("2010-01-01", "2020-12-31", freq="D")
    rows = []
    for y in range(2009, 2021):
        for m in range(1, 13):
            rows.append(dict(year=y, month=m, oni_anom=1.0 if (y, m) >= (2011, 1) else -1.0, roni=0.0,
                             nino34_anom=0.0, dmi=0.0))
    enso = pd.DataFrame(rows)
    t = pw.oni_table(enso, dates)
    assert t.ym.min() == 2012 * 12 + 3 and t.ym.max() == 2020 * 12 + 1 and len(t) == 95
    assert (t.en_gest_w == 1.0).all() and (t.ln_gest_w == 0.0).all()
    pw.check_no_fy2021(t)
    with pytest.raises(ValueError):
        pw.check_no_fy2021(pd.DataFrame({"ym": [2020 * 12 + 2]}))


def test_exposure_table_columns():
    dates = pd.date_range("2011-01-01", "2020-06-30", freq="D")
    x = np.zeros((len(dates), 2))
    ex = pw.exposure_table(["L1", "L2"], dates, x + 1.0, x - 0.5, months=[(2012 * 12 + 3, 2012, 4)])
    assert list(ex.columns) == pw.EXPOSURE_COLUMNS
    assert len(ex) == 2 and (ex.heat_w01 == 1.0).all() and (ex.dry_w40 == -0.5).all()
    assert (ex.heat39_w39 == 1.0).all() and (ex.dry_nc8 == -0.5).all()
