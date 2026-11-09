"""Paper F small-number release panel (Task 5, R7; spec section 8).

One suppression rule, applied when the tracked release panel is written and again by the exporter (idempotent), and
checked by `suppression_findings`:
  - `sb`, `lbw`, `preterm` values 1-4 become "<5"; zeros stay 0; blank (NaN) stays blank, never "<5" and never 0.
  - Complementary suppression: a state-month (state_unit x ym) with exactly one suppressed cell of a variable gets the
    smallest non-zero unsuppressed cell of that variable (ties by link_id); if none is non-zero, the smallest zero cell
    (by link_id), shown "<5" (a true statement). Rounds repeat until no state-month has exactly one suppressed cell,
    except a state-month with a single link unit with a value, which cannot be complemented: it is exempt and listed.
  - sbr (per 1,000 total births, total = lb + sb) and lbw_share (lbw / wt) are blank for every suppressed cell and for
    denominators < MIN_RATE_DENOM.
  - No `tb` (tb - lb would give sb back), no `d24` (R4), no FY2020-21 row (R2).
"""
import gzip
import shutil
from pathlib import Path

import numpy as np
import pandas as pd

from pipeline.paths import DERIVED

SUPPRESS_VARS = ("sb", "lbw", "preterm")
SUPPRESSED = "<5"
MIN_RATE_DENOM = 20
RELEASE_COLUMNS = ["link_id", "state_unit", "fy", "year", "month", "ym", "lb", "lb_m", "lb_f", "sb", "wt", "lbw",
                   "inst", "home", "preterm", "comp_sb", "comp_lbw", "sbr", "lbw_share", "flag_sb", "flag_lbw"]
RELEASE_PATH = DERIVED / "hmis" / "perinatal_release_panel.csv.gz"
YM_APRIL_2020 = 2020 * 12 + 3          # ym = year * 12 + month - 1
FY_PRIVATE = "2020-21"
_COUNT_COLS = ["year", "month", "ym", "lb", "lb_m", "lb_f", "wt", "inst", "home"]


def _split(col: pd.Series) -> tuple[pd.Series, pd.Series]:
    """(numeric value, suppressed mask). "<5" is suppressed and has no numeric value; 1-4 are suppressed."""
    shown = col.astype(object).eq(SUPPRESSED)
    val = pd.to_numeric(col.where(~shown), errors="coerce")
    return val, shown | ((val >= 1) & (val < 5))


def _complement(link: np.ndarray, val: np.ndarray, sup: np.ndarray, groups: list) -> tuple[int, int, list]:
    """Mutates `sup`. Returns (n complement cells, n of them zero cells, row indices of exempt lone cells)."""
    n_comp = n_zero = 0
    exempt: set = set()
    while True:
        changed = False
        for idx in groups:
            if sup[idx].sum() != 1:
                continue
            lone = int(idx[sup[idx]][0])
            cand = idx[~sup[idx] & ~np.isnan(val[idx])]
            if len(cand) == 0:
                exempt.add(lone)
                continue
            nz = cand[val[cand] > 0]
            pool = nz if len(nz) else cand
            pick = min(pool, key=lambda i: (val[i], link[i]))
            sup[pick] = True
            n_comp += 1
            n_zero += int(val[pick] == 0)
            changed = True
        if not changed:
            return n_comp, n_zero, sorted(exempt)


def suppress_with_report(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """(suppressed frame, exempt single-unit state-months, per-variable counts). Rates are recomputed from the counts."""
    out = df.reset_index(drop=True).copy()
    link = out.link_id.astype(str).to_numpy()
    groups = [np.asarray(ix) for ix in out.groupby(["state_unit", "ym"], sort=False).indices.values()]
    exempt_rows, stats, sup_by = [], [], {}
    for v in SUPPRESS_VARS:
        val, sup0 = _split(out[v])
        val_a, sup = val.to_numpy(float), sup0.to_numpy(bool).copy()
        n_prim = int(sup.sum())
        n_comp, n_zero, ex = _complement(link, val_a, sup, groups)
        for i in ex:
            exempt_rows.append(dict(state_unit=out.state_unit[i], ym=int(out.ym[i]), variable=v, link_id=link[i]))
        shown = pd.Series(val_a, index=out.index, dtype=object)
        shown[sup] = SUPPRESSED
        out[v] = shown
        sup_by[v] = (pd.Series(val_a, index=out.index), pd.Series(sup, index=out.index))
        stats.append(dict(variable=v, suppressed_primary=n_prim, suppressed_complement=n_comp,
                          complement_zero_cells=n_zero, exempt_state_months=len(ex)))
    sb, sb_sup = sup_by["sb"]
    lbw, lbw_sup = sup_by["lbw"]
    lb = pd.to_numeric(out["lb"], errors="coerce") if "lb" in out else pd.Series(np.nan, index=out.index)
    wt = pd.to_numeric(out["wt"], errors="coerce") if "wt" in out else pd.Series(np.nan, index=out.index)
    tot = lb + sb
    out["sbr"] = (sb / tot * 1000).where(~sb_sup & (tot >= MIN_RATE_DENOM)).round(3)
    out["lbw_share"] = (lbw / wt).where(~lbw_sup & (wt >= MIN_RATE_DENOM)).round(4)
    exempt = pd.DataFrame(exempt_rows, columns=["state_unit", "ym", "variable", "link_id"])
    return out, exempt, pd.DataFrame(stats)


def suppress_small_cells(df: pd.DataFrame) -> pd.DataFrame:
    return suppress_with_report(df)[0]


def prepare_release(panel: pd.DataFrame) -> pd.DataFrame:
    """FY2012-13 to 2019-20 (April 2012 to March 2020) rows, release columns only (no tb, no d24), sorted."""
    p = panel[(panel.fy != FY_PRIVATE) & (panel.ym < YM_APRIL_2020)]
    cols = [c for c in RELEASE_COLUMNS if c not in ("sbr", "lbw_share")]
    return p[cols].sort_values(["link_id", "ym"]).reset_index(drop=True)


def release_panel(panel: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    out, exempt, _ = suppress_with_report(prepare_release(panel))
    return out[RELEASE_COLUMNS], exempt


def suppression_findings(df: pd.DataFrame) -> list[str]:
    f: list[str] = []
    for c in ("tb", "d24"):
        if c in df.columns:
            f.append(f"column {c} is present")
    if "fy" in df and (df.fy.astype(str) == FY_PRIVATE).any():
        f.append(f"{int((df.fy.astype(str) == FY_PRIVATE).sum())} rows with fy 2020-21")
    ym = pd.to_numeric(df["ym"], errors="coerce")
    if (ym >= YM_APRIL_2020).any():
        f.append(f"{int((ym >= YM_APRIL_2020).sum())} rows with ym from April 2020")
    keys = [df.state_unit.astype(str), ym]
    split = {}
    for v in SUPPRESS_VARS:
        if v not in df:
            continue
        shown = df[v].astype(object).eq(SUPPRESSED)
        val = pd.to_numeric(df[v].where(~shown), errors="coerce")
        split[v] = (val, shown)
        n = int(((val >= 1) & (val < 5)).sum())
        if n:
            f.append(f"{n} released 1-4 values in {v}")
        has = (shown | val.notna()).groupby(keys).sum()
        sup = shown.groupby(keys).sum()
        bad = int(((sup == 1) & (has >= 2)).sum())
        if bad:
            f.append(f"{bad} state-months with exactly one suppressed cell in {v}")
    for rate, num, den_cols in (("sbr", "sb", ("lb", "sb")), ("lbw_share", "lbw", ("wt",))):
        if rate not in df or num not in split:
            continue
        shown_rate = pd.to_numeric(df[rate], errors="coerce").notna()
        den = sum(split[num][0] if c == num else pd.to_numeric(df[c], errors="coerce") for c in den_cols)
        breach = shown_rate & (split[num][1] | ~(den >= MIN_RATE_DENOM))
        if breach.any():
            f.append(f"{int(breach.sum())} rates shown for a suppressed cell or denominator < {MIN_RATE_DENOM} ({rate})")
    return f


def to_csv_frame(df: pd.DataFrame) -> pd.DataFrame:
    """Counts as integers ("<5" kept, blank stays blank) so the written file has no 12.0 values."""
    out = df.copy()
    for c in SUPPRESS_VARS:
        out[c] = out[c].map(lambda x: x if x == SUPPRESSED else (np.nan if pd.isna(x) else str(int(x)))).astype(object)
    for c in [c for c in _COUNT_COLS if c in out]:
        out[c] = pd.to_numeric(out[c], errors="coerce").round().astype("Int64")
    return out


def write_release(df: pd.DataFrame, path: Path = RELEASE_PATH) -> None:
    """Deterministic gzip (mtime 0)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    text = to_csv_frame(df).to_csv(index=False)
    with open(path, "wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as gz:
        gz.write(text.encode("utf-8"))


def release_step(panel_path: Path | None = None, out: Path = RELEASE_PATH) -> int:
    from pipeline.hmis import perinatal_panel as ppanel
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(out.parent).free < 2 * 1024 ** 3:
        raise RuntimeError("less than 2 GB free on the data drive; stopped")
    panel = pd.read_csv(panel_path or ppanel.PANEL_PATH)
    rel, exempt, stats = suppress_with_report(prepare_release(panel))
    write_release(rel[RELEASE_COLUMNS], out)
    findings = suppression_findings(pd.read_csv(out))
    print(f"release panel: {len(rel)} rows, {rel.link_id.nunique()} link units, {out.stat().st_size} bytes")
    print(stats.to_string(index=False))
    print(f"exempt single-unit state-months: {len(exempt)}")
    if len(exempt) < 30:
        print(exempt.to_string(index=False))
    print(f"suppression_findings on the written file: {findings or 'none'}")
    return 1 if findings else 0
