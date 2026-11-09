"""Gestational exposure terms for Paper F (Task 6; spec 4, 5.2, rulings R1, R5).

Births reported in month m were exposed over months m-8..m; lag k is month m-k, lead +j is month m+j. Every lag and
lead is built by model_table.lag_merge (a merge on ym - k, negative k for leads), never shift(): a month absent from
the climate or ENSO table leaves the term NaN, and a term with any missing month is NaN.

Terms (gestation_terms): trimester stratum means over lags 0-2 (t3), 3-5 (t2), 6-8 (t1) of tmax_anom (tmax_t*) and
heatwave_days (hw_t*); the single lags tmax_l0..tmax_l8 (spline sensitivity); spi3_dry at lags 0, 3, 6; the negative
controls tmax_lead12 (mean of leads +1, +2) and spi3_dry_lead3; the gestation means en_gest, ln_gest (of en_t, ln_t)
and en_roni_gest, ln_roni_gest (RONI); and the episode partition en_ep1415 + en_ep1819 + en_other == en_gest over the
birth-month windows EPISODES_F.

EPISODES_F is spec 5.2 (R5): Paper E's calendar windows extended to 8 months past the episode's last El Nino month
(ONI >= 0.5, season ending in the month), cut at PRIMARY_END (R1). episode_windows() derives them from ONI.
"""
import numpy as np
import pandas as pd

from pipeline.hmis import exposure
from pipeline.hmis.exposure import PRIMARY_END, ym_of
from pipeline.hmis.model_table import lag_merge

EPISODES_F = {"ep1415": (ym_of(2014, 10), ym_of(2017, 2)), "ep1819": (ym_of(2018, 9), ym_of(2020, 2))}
EL_NINO_ONI = 0.5
LAGS = tuple(range(0, 9))
TRIMESTERS = {"t3": (0, 1, 2), "t2": (3, 4, 5), "t1": (6, 7, 8)}


def episode_windows(enso: pd.DataFrame, spans=exposure.EPISODES, extend: int = 8, tail: int = 6,
                    cap: int = PRIMARY_END) -> dict:
    """For each Paper E window (start, end): the El Nino months are those with ONI >= 0.5 (season ending in the month)
    from start to end + `tail`; the new end is min(last such month + extend, cap); the start is unchanged."""
    lo = min(s for s, _ in spans.values())
    hi = max(e for _, e in spans.values()) + tail
    oni = exposure.enso_exposures(enso, range(lo, hi + 1)).set_index("ym").oni
    out = {}
    for name, (start, end) in spans.items():
        w = oni.loc[start:end + tail]
        en = w.index[(w >= EL_NINO_ONI).to_numpy()]
        if len(en) == 0:
            raise ValueError(f"no El Nino month (ONI >= {EL_NINO_ONI}) in {name}")
        out[name] = (int(start), int(min(en.max() + extend, cap)))
    return out


def _stratum_mean(df: pd.DataFrame, col: str, ks) -> np.ndarray:
    win = np.column_stack([df[f"{col}_l{k}"].to_numpy(dtype=float) for k in ks])
    return win.mean(axis=1)           # NaN when any member is NaN


def _lagged(df: pd.DataFrame, cols, keys, ks) -> pd.DataFrame:
    for k in ks:
        df = lag_merge(df, cols, keys, k)
    return df


def _enso_terms(enso: pd.DataFrame, yms: np.ndarray, windows: dict) -> pd.DataFrame:
    t = np.arange(yms.min() - max(LAGS), yms.max() + 1)
    e = exposure.enso_exposures(enso, t)[["ym", "en_t", "ln_t", "en_roni", "ln_roni"]]
    e = _lagged(e, ["en_t", "ln_t", "en_roni", "ln_roni"], [], LAGS)
    out = pd.DataFrame({"ym": e.ym})
    for src, dst in (("en_t", "en_gest"), ("ln_t", "ln_gest"), ("en_roni", "en_roni_gest"),
                     ("ln_roni", "ln_roni_gest")):
        out[dst] = _stratum_mean(e, src, LAGS)
    inside = np.zeros(len(out), dtype=bool)
    for name, (a, b) in windows.items():
        w = out.ym.between(a, b).to_numpy()
        out[f"en_{name}"] = out.en_gest * w
        inside |= w
    out["en_other"] = out.en_gest * ~inside
    return out[out.ym.isin(yms)]


def gestation_terms(clim: pd.DataFrame, enso: pd.DataFrame, yms, windows: dict | None = None) -> pd.DataFrame:
    """One row per link_id x ym in `yms` (link units taken from `clim`). `clim` needs link_id, ym, tmax_anom,
    heatwave_days, spi3_dry (any months; a missing one leaves its terms NaN). `enso` is enso_monthly.csv."""
    windows = EPISODES_F if windows is None else windows
    yms = np.asarray(sorted(set(int(y) for y in yms)), dtype=int)
    c = clim[["link_id", "ym", "tmax_anom", "heatwave_days", "spi3_dry"]].copy()
    c = _lagged(c, ["tmax_anom", "heatwave_days"], ["link_id"], LAGS)
    c = _lagged(c, ["spi3_dry"], ["link_id"], (0, 3, 6))
    c = _lagged(c, ["tmax_anom"], ["link_id"], (-1, -2))
    c = _lagged(c, ["spi3_dry"], ["link_id"], (-3,))
    grid = pd.DataFrame([(l, t) for l in sorted(c.link_id.unique()) for t in yms], columns=["link_id", "ym"])
    c = grid.merge(c, on=["link_id", "ym"], how="left", validate="one_to_one")     # a ym absent from clim: all NaN
    out = c[["link_id", "ym"]].copy()
    for tag, ks in TRIMESTERS.items():
        out[f"tmax_{tag}"] = _stratum_mean(c, "tmax_anom", ks)
    for tag, ks in TRIMESTERS.items():
        out[f"hw_{tag}"] = _stratum_mean(c, "heatwave_days", ks)
    for k in LAGS:
        out[f"tmax_l{k}"] = c[f"tmax_anom_l{k}"].to_numpy()
    for k in (0, 3, 6):
        out[f"spi3_dry_l{k}"] = c[f"spi3_dry_l{k}"].to_numpy()
    out["tmax_lead12"] = _stratum_mean(c, "tmax_anom", (-1, -2))
    out["spi3_dry_lead3"] = c["spi3_dry_l-3"].to_numpy()
    e = _enso_terms(enso, yms, windows)
    return out.merge(e, on="ym", how="left", validate="many_to_one").reset_index(drop=True)
