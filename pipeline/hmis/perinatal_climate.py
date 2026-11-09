"""Link-unit climate for Paper F (Task 6; spec 3.4 "Climate per link unit", 3.7).

Order of operations (climate_link_unit_month):
1. the reviewed QC masks at district level: climate_annual.apply_qc_to_month(<climate_district_month.csv.gz>, "district")
   (masked district-months get NaN rain; temperature is untouched). A&N rainfall is masked there (Phase 1 R19/R20), so
   its rain_mm and spi3 terms are NaN while tmax and heatwave terms are present;
2. pooling to link units: area-weighted mean over the member GADM districts with a non-NaN value, weights
   renormalised over those members (a link-unit-month with no non-NaN member stays NaN, never 0). The weight of a
   district is its area_km2 (sum of the r025 grid-overlap areas in _parts/weights_r025_district.csv);
3. SPI-3 per link unit with climate_annual.spi(series, 3) (base 1981-2010) on a contiguous monthly series
   (1981-2025), so a masked or absent month makes every 3-month window containing it NaN;
4. tmax_anom = tmax_mean minus the unit's 1981-2010 mean for that calendar month; spi3_dry = min(spi3, 0).

Climate only: no outcome column is read or written. Hand-off (build): data/derived/hmis/climate_link_unit_month.csv.gz
(tracked), January 1981 to December 2021.
"""
from pathlib import Path

import numpy as np
import pandas as pd

from pipeline import climate_annual as ca
from pipeline.paths import DERIVED

HMIS_DIR = DERIVED / "hmis"
OUT_PATH = HMIS_DIR / "climate_link_unit_month.csv.gz"
VALUE_COLUMNS = ["rain_mm", "tmax_mean", "heatwave_days"]
COLUMNS = ["link_id", "year", "month", "ym", "rain_mm", "tmax_mean", "heatwave_days", "spi3", "spi3_dry",
           "tmax_anom"]
FILE_LAST_YEAR = 2021


def district_areas(derived=DERIVED) -> dict:
    """Area (km2) per district region_id: the r025 grid-overlap areas summed per region."""
    w = pd.read_csv(Path(derived) / "_parts" / "weights_r025_district.csv")
    return w.groupby("region_id").area_km2.sum().to_dict()


def gadm_members(units: pd.DataFrame) -> dict:
    """region_id -> link_id from the `gadm` rows of hmis_link_units.csv."""
    g = units[units.kind == "gadm"]
    if g.region_id.duplicated().any():
        raise ValueError("a GADM district is in more than one link unit")
    return dict(zip(g.region_id, g.link_id))


def pool_to_link_units(month: pd.DataFrame, areas: dict, link_of: dict, columns=VALUE_COLUMNS) -> pd.DataFrame:
    """Area-weighted mean over the members with a non-NaN value, per link_id x year x month and column."""
    df = month[["region_id", "year", "month"] + list(columns)].copy()
    df["link_id"] = df.region_id.map(link_of)
    if df.link_id.isna().any():
        raise KeyError(f"districts not in a link unit: {sorted(df.region_id[df.link_id.isna()].unique())[:5]}")
    df["_w"] = df.region_id.map(areas)
    if df._w.isna().any():
        raise KeyError(f"no area for districts: {sorted(df.region_id[df._w.isna()].unique())[:5]}")
    keys = [df.link_id, df.year, df.month]
    out = None
    for c in columns:
        ok = df[c].notna()
        num = (df[c] * df._w).where(ok).groupby(keys).sum(min_count=1)
        den = df._w.where(ok).groupby(keys).sum(min_count=1)
        s = (num / den).rename(c)
        out = s.to_frame() if out is None else out.join(s)
    out.index.names = ["link_id", "year", "month"]
    return out.reset_index().sort_values(["link_id", "year", "month"], ignore_index=True)


def _spi3(g: pd.DataFrame) -> np.ndarray:
    idx = pd.PeriodIndex.from_fields(year=g.year, month=g.month, freq="M")
    full = pd.period_range(idx.min(), idx.max(), freq="M")          # contiguous: a missing row is a gap
    s = ca.spi(pd.Series(g.rain_mm.to_numpy(dtype=float), index=idx).reindex(full), 3, ca.BASE)
    return s.reindex(idx).to_numpy()


def from_district_month(month: pd.DataFrame, areas: dict, link_of: dict) -> pd.DataFrame:
    """Steps 2-4 on a QC-masked district-month table (region_id, year, month, rain_mm, tmax_mean, heatwave_days)."""
    u = pool_to_link_units(month, areas, link_of)
    u["year"], u["month"] = u.year.astype(int), u.month.astype(int)
    u["ym"] = 12 * u.year + u.month - 1
    u["spi3"] = np.nan
    for _, g in u.groupby("link_id", sort=False):
        u.loc[g.index, "spi3"] = _spi3(g)
    base = u[u.year.between(*ca.BASE)]
    normal = base.groupby(["link_id", "month"]).tmax_mean.mean().rename("_tmax_normal")
    u = u.merge(normal, left_on=["link_id", "month"], right_index=True, how="left")
    u["tmax_anom"] = u.tmax_mean - u._tmax_normal
    u["spi3_dry"] = np.minimum(u.spi3, 0)           # np.minimum propagates NaN
    return u[COLUMNS].reset_index(drop=True)


def climate_link_unit_month(units: pd.DataFrame, derived=DERIVED) -> pd.DataFrame:
    derived = Path(derived)
    month = pd.read_csv(derived / "climate_district_month.csv.gz")
    qc = ca.apply_qc_to_month(month, "district", derived=derived)
    link_of = gadm_members(units)
    missing = set(link_of) - set(qc.region_id)
    if missing:
        raise ValueError(f"link-unit districts with no climate rows: {sorted(missing)[:5]}")
    qc = qc[qc.region_id.isin(link_of)]
    return from_district_month(qc, district_areas(derived), link_of)


def build(out: Path = OUT_PATH, derived=DERIVED, units_path=None) -> Path:
    from pipeline.hmis import perinatal_units as pu
    units = pd.read_csv(units_path or pu.LINK_UNITS_PATH, dtype=str, keep_default_na=False)
    c = climate_link_unit_month(units, derived)
    c = c[c.year <= FILE_LAST_YEAR]
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    c.to_csv(out, index=False, float_format="%.5g")
    return out
