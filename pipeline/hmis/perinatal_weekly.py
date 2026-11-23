"""Paper F: weekly gestational exposures (papers/F/analysis_plan_weekly.md, section 2).

Daily link-unit series, 1981-2020:
- Tmax: IMD 1 deg daily grids (data/raw/imd/tmax_<year>.grd) -> districts with the t100 cell weights
  (grid_weights.Aggregator, nearest-cell fallback as in Phase 1, pipeline/build_climate.build_temperature);
- rain: IMD 0.25 deg daily grids (data/raw/imd/rain_<year>.grd) with the Phase 1 masks: the zero-filled cell-years
  (ruling R19, build_climate.zero_annual_mask: a cell whose annual total is exactly 0 mm is NaN for that year) before
  the district aggregation (r025 weights), then the reviewed district masks (climate_annual.qc_mask_for_level
  ("district"); a mask covers the months climate_annual.QC_MONTHS of its variable) on every day of a masked
  district-month;
- districts -> link units: area-weighted mean over the member GADM districts with a non-NaN value, weights (district
  areas, perinatal_climate.district_areas) renormalised over those members; no non-NaN member -> NaN, never 0
  (perinatal_climate.pool_to_link_units at daily level).

Exposures (per link unit):
- heat: tmax_anom = Tmax minus the unit's 1981-2010 day-of-year mean, 31-day centred window
  (climate_daily.tmax_climatology), averaged within each week (7-day mean ending on the week's last day);
- rainfall deficit: SPI-28 = the 28-day rainfall total ending on each day through a gamma distribution with a mass at
  zero, fitted per unit and calendar week of the year (week_of_year) on 1981-2010 (the climate_annual.spi rule: at
  least 10 non-zero base totals, H(0) = q/2); deficit = min(SPI-28, 0) at the end of each gestational week;
- gestational alignment (term birth at 40 weeks): for births in month m, the exposure in week w (1-40) is the
  equal-weight mean over the days d of month m of the weekly value of days d - 280 + 7(w - 1) .. d - 280 + 7w - 1;
  the 39-week alignment (sensitivity 4) uses 273 days and weeks 1-39;
- negative controls (after birth): heat_nc8 = mean tmax_anom over days d + 1 .. d + 56; dry_nc8 = min(SPI-28, 0) on
  day d + 56 (the end of the 8th week after birth; its 28-day window lies wholly after birth); each averaged over the
  days of the birth month;
- ENSO: en = max(ONI, 0) and ln = min(ONI, 0) of the season ending in each calendar month (exposure.enso_exposures),
  given to every day of that month and averaged over the 280 days d - 280 .. d - 1 (the 40 gestational weeks) and over
  the days of the birth month.
Every mean is strict: any NaN input day makes the value NaN (never 0).

Outputs (birth months April 2012 to February 2020 only; no FY2020-21 row is written; no outcome is read):
- data/derived/hmis/perinatal_weekly_exposure.csv.gz: link_id, ym, year, month, heat_w01..heat_w40,
  dry_w01..dry_w40, heat_nc8, dry_nc8, heat39_w01..heat39_w39, dry39_w01..dry39_w39;
- data/derived/hmis/perinatal_weekly_oni.csv.gz: ym, year, month, en_gest_w, ln_gest_w.
The daily link-unit series are cached in data/derived/hmis/_parts_f/weekly_daily.npz (git-ignored).
"""
import os
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import sparse, stats

from pipeline import climate_annual as ca
from pipeline import climate_daily as cd
from pipeline import imd_grid
from pipeline.hmis import exposure
from pipeline.hmis import perinatal_climate as pcl
from pipeline.paths import DERIVED, RAW

HMIS_DIR = DERIVED / "hmis"
OUT_EXPOSURE = HMIS_DIR / "perinatal_weekly_exposure.csv.gz"
OUT_ONI = HMIS_DIR / "perinatal_weekly_oni.csv.gz"
DAILY_CACHE = HMIS_DIR / "_parts_f" / "weekly_daily.npz"
IMD_DIR = RAW / "imd"
ENSO_PATH = DERIVED / "enso_monthly.csv"

FIRST_YEAR, LAST_YEAR = 1981, 2020
BASE = ca.BASE                                  # (1981, 2010)
DAY0 = date(FIRST_YEAR, 1, 1)
GEST_DAYS, N_WEEKS = 280, 40
GEST_DAYS_39, N_WEEKS_39 = 273, 39
NC_DAYS = 56                                    # 8 weeks after birth
SPI_DAYS = 28
CLIM_WINDOW = 31
FLOAT_FORMAT = "%.5g"


# ------------------------------------------------------------------ calendar helpers

def day_number(y: int, m: int, d: int, day0: date = DAY0) -> int:
    return date(y, m, d).toordinal() - day0.toordinal()


def day_dates(n_days: int, day0: date = DAY0) -> pd.DatetimeIndex:
    return pd.date_range(pd.Timestamp(day0), periods=n_days, freq="D")


def week_of_year(dates: pd.DatetimeIndex) -> np.ndarray:
    """Calendar week of the year, 0..51: days 1-7 are week 0, ..., days 358-366 week 51 (the last week takes the
    year's one or two extra days)."""
    return np.minimum((np.asarray(dates.dayofyear) - 1) // 7, 51)


def birth_days(year: int, month: int, day0: date = DAY0) -> np.ndarray:
    """Day numbers of every day of a birth month."""
    first = day_number(year, month, 1, day0)
    n = pd.Period(year=year, month=month, freq="M").days_in_month
    return first + np.arange(n)


def primary_months() -> list[tuple[int, int, int]]:
    """(ym, year, month) of the primary window, April 2012 to February 2020."""
    return [(ym, ym // 12, ym % 12 + 1) for ym in range(exposure.PRIMARY_START, exposure.PRIMARY_END + 1)]


# ------------------------------------------------------------------ strict rolling windows (axis 0 = days)

def rolling_sum_strict(x: np.ndarray, n: int) -> np.ndarray:
    """Sum of x[t - n + 1 .. t] along axis 0; NaN if any value in the window is NaN or the window starts before 0."""
    x = np.asarray(x, dtype=float)
    bad = np.isnan(x)
    z = np.where(bad, 0.0, x)
    cs = np.concatenate([np.zeros((1,) + x.shape[1:]), np.cumsum(z, axis=0)])
    cb = np.concatenate([np.zeros((1,) + x.shape[1:]), np.cumsum(bad, axis=0)])
    out = np.full(x.shape, np.nan)
    if x.shape[0] >= n:
        s = cs[n:] - cs[:-n]
        nb = cb[n:] - cb[:-n]
        out[n - 1:] = np.where(nb > 0, np.nan, s)
    return out


def rolling_mean_strict(x: np.ndarray, n: int) -> np.ndarray:
    return rolling_sum_strict(x, n) / n


def _take(series: np.ndarray, idx: np.ndarray) -> np.ndarray:
    """series[idx] along axis 0 with NaN for indices outside 0..T-1. idx may have any shape; result idx.shape + L."""
    T = series.shape[0]
    ok = (idx >= 0) & (idx < T)
    out = np.full(idx.shape + series.shape[1:], np.nan)
    out[ok] = series[idx[ok]]
    return out


def _strict_mean(a: np.ndarray, axis: int) -> np.ndarray:
    """Mean along axis; NaN if any element is NaN (never 0, never a partial mean)."""
    return np.mean(a, axis=axis)                 # np.mean propagates NaN


# ------------------------------------------------------------------ gestational alignment

def gestational_weeks(week_end_value: np.ndarray, days: np.ndarray, n_weeks: int = N_WEEKS,
                      gest_days: int = GEST_DAYS) -> np.ndarray:
    """(n_weeks, L): for week w = 1..n_weeks, the equal-weight mean over the birth days d in `days` of
    week_end_value[d - gest_days + 7w - 1] (the value attached to the last day of the week's window
    d - gest_days + 7(w - 1) .. d - gest_days + 7w - 1). Strict: any NaN -> NaN."""
    w = np.arange(1, n_weeks + 1)
    idx = np.asarray(days)[:, None] - gest_days + 7 * w[None, :] - 1          # (n_days, n_weeks)
    vals = _take(week_end_value, idx)                                         # (n_days, n_weeks, L)
    return _strict_mean(vals, axis=0)


def after_birth(value: np.ndarray, days: np.ndarray, offset: int = NC_DAYS) -> np.ndarray:
    """(L,): mean over the birth days d of value[d + offset]. Strict."""
    return _strict_mean(_take(value, np.asarray(days) + offset), axis=0)


def heat_week_values(anom: np.ndarray) -> np.ndarray:
    """Weekly heat attached to a week's last day: the mean anomaly over that day and the 6 days before."""
    return rolling_mean_strict(anom, 7)


def heat_nc_values(anom: np.ndarray, n_days: int = NC_DAYS) -> np.ndarray:
    """At day t: mean anomaly over t - n_days + 1 .. t; read at d + n_days it is the mean over d + 1 .. d + n_days."""
    return rolling_mean_strict(anom, n_days)


def deficit(spi_values: np.ndarray) -> np.ndarray:
    """min(SPI, 0); NaN stays NaN."""
    return np.minimum(spi_values, 0)            # np.minimum propagates NaN


# ------------------------------------------------------------------ SPI-28

def _spi_block(acc: np.ndarray, ref: np.ndarray) -> np.ndarray:
    """SPI of the accumulations `acc` (1-D) given the base-period accumulations `ref` (climate_annual.spi rule)."""
    ref = ref[np.isfinite(ref)]
    out = np.full(acc.shape, np.nan)
    nonzero = ref[ref > 0]
    if len(nonzero) < 10 or np.std(nonzero) == 0:
        return out
    q = float((ref == 0).mean())
    try:
        a, _, b = stats.gamma.fit(nonzero, floc=0)
    except Exception:                           # degenerate sample -> SPI undefined
        return out
    ok = np.isfinite(acc)
    x = acc[ok]
    h = q + (1 - q) * stats.gamma.cdf(np.clip(x, 0, None), a, loc=0, scale=b)
    h = np.where(x == 0, q / 2 if q > 0 else 1e-6, h)
    out[ok] = stats.norm.ppf(np.clip(h, 1e-6, 1 - 1e-6))
    return out


def spi_daily(rain: np.ndarray, dates: pd.DatetimeIndex, scale: int = SPI_DAYS, base=BASE) -> np.ndarray:
    """(T, L) SPI-<scale> per day: the <scale>-day total ending on each day (strict), standardised per column and
    calendar week of the year (week_of_year) against the base-period totals of that week."""
    acc = rolling_sum_strict(rain, scale)
    woy = week_of_year(dates)
    years = np.asarray(dates.year)
    in_base = (years >= base[0]) & (years <= base[1])
    out = np.full(acc.shape, np.nan)
    for k in range(52):
        sel = woy == k
        ref_sel = sel & in_base
        for j in range(acc.shape[1]):
            out[sel, j] = _spi_block(acc[sel, j], acc[ref_sel, j])
    return out


# ------------------------------------------------------------------ Tmax anomaly

def tmax_anomaly(tmax: np.ndarray, dates: pd.DatetimeIndex, base=BASE, window: int = CLIM_WINDOW) -> np.ndarray:
    """Tmax minus the column's base-period day-of-year mean (31-day centred window, climate_daily.tmax_climatology)."""
    years = np.asarray(dates.year)
    by_year = {int(y): tmax[years == y] for y in range(base[0], base[1] + 1) if (years == y).any()}
    clim = cd.tmax_climatology(by_year, window=window)                      # (366, L)
    out = np.full(tmax.shape, np.nan)
    for y in np.unique(years):
        sel = years == y
        out[sel] = tmax[sel] - clim[cd.doy366_index(int(y))]
    return out


# ------------------------------------------------------------------ grids -> districts -> link units

def district_qc_days(qc_mask: pd.DataFrame, region_ids, year: int) -> np.ndarray:
    """(n_days(year), n_regions) True on the days of a masked district-month (climate_annual.QC_MONTHS)."""
    pos = {r: k for k, r in enumerate(region_ids)}
    months = cd.month_index(year) + 1
    out = np.zeros((len(months), len(region_ids)), dtype=bool)
    q = qc_mask[qc_mask.year.astype(int) == year]
    for r in q.itertuples():
        if r.region_id not in pos:
            continue
        out[np.isin(months, ca.QC_MONTHS[r.variable]), pos[r.region_id]] = True
    return out


def link_pool_matrix(region_ids, link_of: dict, areas: dict):
    """(link_ids, sparse (L x D) matrix of district areas) for pool_daily."""
    link_ids = sorted({link_of[r] for r in region_ids if r in link_of})
    lpos = {l: k for k, l in enumerate(link_ids)}
    rows, cols, vals = [], [], []
    for j, r in enumerate(region_ids):
        if r not in link_of:
            continue
        if r not in areas:
            raise KeyError(f"no area for district {r}")
        rows.append(lpos[link_of[r]]); cols.append(j); vals.append(float(areas[r]))
    M = sparse.csr_matrix((vals, (rows, cols)), shape=(len(link_ids), len(region_ids)))
    return link_ids, M


def pool_daily(dist: np.ndarray, M) -> np.ndarray:
    """(T, L): area-weighted mean of the (T, D) district values over the members with a non-NaN value, weights
    renormalised over them; a day with no non-NaN member is NaN (never 0)."""
    ok = ~np.isnan(dist)
    num = (M @ np.where(ok, dist, 0.0).T).T
    den = (M @ ok.T.astype(float)).T
    with np.errstate(invalid="ignore", divide="ignore"):
        return np.where(den > 0, num / den, np.nan)


def _aggregator(gridname: str, grid, parts_dir: Path):
    from pipeline import boundaries
    from pipeline.grid_weights import Aggregator
    regions = boundaries.load("district")
    w = pd.read_csv(Path(parts_dir) / f"weights_{gridname}_district.csv")
    return Aggregator(grid, regions, weights=w)


def daily_link_series(years=range(FIRST_YEAR, LAST_YEAR + 1), raw_dir=IMD_DIR, derived=DERIVED, units=None,
                      log=print) -> dict:
    """{'link_ids', 'dates', 'tmax', 'rain'}: daily link-unit Tmax and rain (T x L, float32)."""
    from pipeline.hmis import perinatal_units as pu
    derived = Path(derived)
    if units is None:
        units = pd.read_csv(pu.LINK_UNITS_PATH, dtype=str, keep_default_na=False)
    link_of = pcl.gadm_members(units)
    areas = pcl.district_areas(derived)
    parts = derived / "_parts"
    agg_t = _aggregator("t100", imd_grid.TEMP, parts)
    agg_r = _aggregator("r025", imd_grid.RAIN, parts)
    if agg_t.region_ids != agg_r.region_ids:
        raise ValueError("t100 and r025 aggregators list different districts")
    region_ids = agg_r.region_ids
    missing = set(link_of) - set(region_ids)
    if missing:
        raise ValueError(f"link-unit districts with no grid weights: {sorted(missing)[:5]}")
    link_ids, M = link_pool_matrix(region_ids, link_of, areas)
    qc = ca.qc_mask_for_level("district")
    tmax_parts, rain_parts = [], []
    for y in years:
        tg = imd_grid.read("tmax", Path(raw_dir) / f"tmax_{y}.grd", y)
        td = agg_t.apply(tg)
        rp = Path(raw_dir) / f"rain_{y}.grd"
        rg = imd_grid.read("rain", rp, y)
        zero = _zero_annual_mask(rg)
        rg[:, zero] = np.nan
        rd = agg_r.apply(rg)
        rd[district_qc_days(qc, region_ids, y)] = np.nan
        tmax_parts.append(pool_daily(td, M).astype(np.float32))
        rain_parts.append(pool_daily(rd, M).astype(np.float32))
        log(f"  {y}: tmax and rain pooled ({int(zero.sum())} zero-filled rain cells masked)")
    dates = day_dates(sum(len(p) for p in tmax_parts), date(min(years), 1, 1))
    return {"link_ids": np.array(link_ids), "dates": dates, "tmax": np.concatenate(tmax_parts),
            "rain": np.concatenate(rain_parts)}


def _zero_annual_mask(daily: np.ndarray) -> np.ndarray:
    from pipeline.build_climate import zero_annual_mask           # the Phase 1 rule (R19), reused unchanged
    return zero_annual_mask(daily)


def save_daily(s: dict, path: Path = DAILY_CACHE) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.stem + ".tmp.npz")
    np.savez_compressed(tmp, link_ids=s["link_ids"], first_day=str(s["dates"][0].date()), tmax=s["tmax"],
                        rain=s["rain"])
    os.replace(tmp, path)
    return path


def load_daily(path: Path = DAILY_CACHE) -> dict:
    with np.load(path, allow_pickle=False) as z:
        tmax, rain = z["tmax"], z["rain"]
        return {"link_ids": z["link_ids"], "dates": day_dates(len(tmax), date.fromisoformat(str(z["first_day"]))),
                "tmax": tmax, "rain": rain}


# ------------------------------------------------------------------ exposures per birth month

def week_cols(prefix: str, n: int) -> list[str]:
    return [f"{prefix}_w{w:02d}" for w in range(1, n + 1)]


EXPOSURE_COLUMNS = (["link_id", "ym", "year", "month"] + week_cols("heat", N_WEEKS) + week_cols("dry", N_WEEKS)
                    + ["heat_nc8", "dry_nc8"] + week_cols("heat39", N_WEEKS_39) + week_cols("dry39", N_WEEKS_39))
ONI_COLUMNS = ["ym", "year", "month", "en_gest_w", "ln_gest_w"]


def exposure_table(link_ids, dates: pd.DatetimeIndex, anom: np.ndarray, dry: np.ndarray,
                   months=None) -> pd.DataFrame:
    """One row per link unit x birth month (EXPOSURE_COLUMNS). `anom` and `dry` are (T, L) daily series on `dates`."""
    months = primary_months() if months is None else months
    day0 = dates[0].date()
    hw = heat_week_values(anom)
    hnc = heat_nc_values(anom)
    parts = []
    for ym, y, m in months:
        days = birth_days(y, m, day0)
        block = np.column_stack([
            gestational_weeks(hw, days).T, gestational_weeks(dry, days).T,
            after_birth(hnc, days)[:, None], after_birth(dry, days)[:, None],
            gestational_weeks(hw, days, N_WEEKS_39, GEST_DAYS_39).T,
            gestational_weeks(dry, days, N_WEEKS_39, GEST_DAYS_39).T])
        df = pd.DataFrame(block, columns=EXPOSURE_COLUMNS[4:])
        df.insert(0, "month", m); df.insert(0, "year", y); df.insert(0, "ym", ym)
        df.insert(0, "link_id", np.asarray(link_ids))
        parts.append(df)
    out = pd.concat(parts, ignore_index=True)
    return out.sort_values(["link_id", "ym"], ignore_index=True)[EXPOSURE_COLUMNS]


def oni_daily(enso: pd.DataFrame, dates: pd.DatetimeIndex) -> tuple[np.ndarray, np.ndarray]:
    """Daily en = max(ONI, 0) and ln = min(ONI, 0): every day takes the ONI of the season ending in its month."""
    ym = np.asarray(dates.year) * 12 + np.asarray(dates.month) - 1
    u = np.unique(ym)
    e = exposure.enso_exposures(enso, u).set_index("ym")
    return e.en_t.reindex(ym).to_numpy(dtype=float), e.ln_t.reindex(ym).to_numpy(dtype=float)


def oni_table(enso: pd.DataFrame, dates: pd.DatetimeIndex, months=None) -> pd.DataFrame:
    months = primary_months() if months is None else months
    en, ln = oni_daily(enso, dates)
    en_g = rolling_mean_strict(en[:, None], GEST_DAYS)            # at t: mean over t - 279 .. t
    ln_g = rolling_mean_strict(ln[:, None], GEST_DAYS)
    day0 = dates[0].date()
    rows = []
    for ym, y, m in months:
        days = birth_days(y, m, day0)
        rows.append((ym, y, m, float(after_birth(en_g, days, -1)[0]), float(after_birth(ln_g, days, -1)[0])))
    return pd.DataFrame(rows, columns=ONI_COLUMNS)


def _write_gz(df: pd.DataFrame, path: Path) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    df.to_csv(tmp, index=False, float_format=FLOAT_FORMAT, compression={"method": "gzip", "mtime": 0})
    os.replace(tmp, path)
    return path


def check_no_fy2021(df: pd.DataFrame) -> None:
    if (df.ym > exposure.PRIMARY_END).any() or (df.ym < exposure.PRIMARY_START).any():
        raise ValueError("weekly exposures: a birth month outside April 2012 to February 2020")


def build(out_exposure: Path = OUT_EXPOSURE, out_oni: Path = OUT_ONI, cache: Path = DAILY_CACHE,
          raw_dir=IMD_DIR, derived=DERIVED, enso_path=ENSO_PATH, rebuild_daily: bool = False, log=print) -> dict:
    """Build the daily link-unit series (or read the cache), the SPI-28 and anomaly series, and write the two
    exposure files. Returns the paths and a few counts."""
    import time
    t0 = time.time()
    if Path(cache).exists() and not rebuild_daily:
        s = load_daily(cache)
        log(f"daily series from {cache}")
    else:
        for y in range(FIRST_YEAR, LAST_YEAR + 1):
            for var in ("tmax", "rain"):
                p = Path(raw_dir) / f"{var}_{y}.grd"
                if not p.exists() or p.stat().st_size != imd_grid.expected_bytes(var, y):
                    raise FileNotFoundError(f"{p} missing or incomplete")
        s = daily_link_series(raw_dir=raw_dir, derived=derived, log=log)
        save_daily(s, cache)
        log(f"daily series built and cached ({time.time() - t0:.0f} s)")
    dates = s["dates"]
    tmax = s["tmax"].astype(float)
    rain = s["rain"].astype(float)
    anom = tmax_anomaly(tmax, dates)
    log(f"tmax anomaly done ({time.time() - t0:.0f} s)")
    spi = spi_daily(rain, dates)
    log(f"SPI-28 done ({time.time() - t0:.0f} s)")
    dry = deficit(spi)
    ex = exposure_table(s["link_ids"], dates, anom, dry)
    check_no_fy2021(ex)
    oni = oni_table(pd.read_csv(enso_path), dates)
    check_no_fy2021(oni)
    _write_gz(ex, out_exposure)
    _write_gz(oni, out_oni)
    log(f"wrote {out_exposure} ({len(ex)} rows) and {out_oni} ({len(oni)} rows) in {time.time() - t0:.0f} s")
    return {"exposure": Path(out_exposure), "oni": Path(out_oni), "n_rows": len(ex),
            "nan_share": ex.iloc[:, 4:].isna().mean().to_dict(), "seconds": time.time() - t0}


if __name__ == "__main__":
    r = build()
    print(r["exposure"], r["oni"], r["n_rows"])
