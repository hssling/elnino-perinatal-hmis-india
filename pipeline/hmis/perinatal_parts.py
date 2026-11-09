"""Paper F district-month parts for the perinatal items (Task 2; spec 3.1, 3.5).

Paper E's run functions take the crosswalk as an argument and nothing in `flags_fy_zip` / `flags_fy2021` hard-wires
Paper E's indicators, so they are called unchanged with the perinatal crosswalk (parse -> apply_crosswalk ->
flags.flag_all happen inside them). Two Paper E helpers do hard-wire its indicators and are composed here instead:
`flags.flag_report` (loops `INDICATORS`) and `run.national_fy` (loops `INDICATORS`).

Outputs (`data/derived/hmis/_parts_f/`, git-ignored): district_month, state_month, completeness, vintage,
month_total_check, members (`run.TABLES`) and national_month. `lb_c` and `home_c` (E1 printed totals) stay in the
parts for the E1 component gate. `data/derived/hmis/perinatal_flag_report.csv` (tracked) holds counts and shares only;
FY2020-21 rows stay in it and are stripped by the Task 15 exporter.

Missing is never zero: blank, NA and "-" cells and every flagged district-month are NaN. National totals follow
Paper E's F39 rule: the folder-1 All India month file net of the M/O Defence and M/O Railways rows (summed from the
folder-3 All_India.xls; FY2020-21 from the national file's own M/O columns).
"""
import time
from pathlib import Path

import numpy as np
import pandas as pd

from pipeline import manifest as mf
from pipeline.hmis import difference as hd
from pipeline.hmis import fetch as hf
from pipeline.hmis import flags as hfl
from pipeline.hmis import parse as hp
from pipeline.hmis import perinatal_crosswalk as pc
from pipeline.hmis import run
from pipeline.paths import DERIVED

PARTS_F = DERIVED / "hmis" / "_parts_f"
FLAG_REPORT_F = DERIVED / "hmis" / "perinatal_flag_report.csv"
REPORT_VARS = pc.PANEL_VARS + pc.STATE_ONLY_VARS
NATIONAL_COLUMNS = ["fy", "month", "indicator", "all_india", "mo_value", "national"]
_CONCORDANCE = "upload-status concordance not run (login-only reports); nonreport is inferred (spec 3.6)"


def _era_vars(xw, fy) -> list[str]:
    return list(xw[xw.era == hp.era_for_fy(fy)].indicator)


class MissingSourcesError(RuntimeError):
    """A primary-FY source (zip) is absent: the step stops before writing anything."""


def _require_sources(root: Path, fys, folders) -> None:
    """Raise, naming the FYs, when a source zip of a primary FY (FY2012-13..2019-20) is absent. Checked before any
    parsing or writing, so a partial table can never replace the tracked report. FY2020-21 may be absent."""
    missing = []
    for fy in fys:
        if fy == run.FY2021:
            continue
        y = int(fy[:4])
        for folder in folders:
            z = root / folder / f"{y}-{y + 1}.zip"
            if not z.exists():
                missing.append(f"{fy} ({mf._key(z)})")
    if missing:
        raise MissingSourcesError("missing primary-FY sources, nothing written: " + "; ".join(missing))


def _free(out_dir: Path) -> int:
    return hf.free_bytes(out_dir if out_dir.exists() else out_dir.parent)


def perinatal_flag_report(dm, state, check, xw, vint=None, notes=None) -> pd.DataFrame:
    """flags.REPORT_COLUMNS, one row per REPORT_VARS variable x FY. Counts and shares only: no district names.
    A variable the FY's era does not collect has n_district_months 0 and a note."""
    notes = notes or {}
    if vint is None:
        vint = pd.DataFrame(columns=["state_raw", "fy", "vintage_mixed"])
    rows = []
    for fy in sorted(set(notes) | set(dm.fy) | set(state.fy)):
        era = hp.era_for_fy(fy)
        mixed = set(vint[(vint.fy == fy) & vint.vintage_mixed.astype(bool)].state_raw)
        for ind in REPORT_VARS:
            d, s = dm[(dm.fy == fy) & (dm.indicator == ind)], state[(state.fy == fy) & (state.indicator == ind)]
            xrow = xw[(xw.era == era) & (xw.indicator == ind)]
            codes = "|".join(xrow.item_codes).split("|")
            c = check[(check.fy == fy) & check.item_code.isin(codes)]
            n, reported, s_ok = len(d), d.value_raw.notna(), s.value.notna()
            note = notes.get(fy, "")
            if xrow.empty:
                note = "; ".join(x for x in (f"{ind} not collected in {era}", note) if x)
            rows.append({
                "indicator": ind, "fy": fy, "n_district_months": n,
                "negative": int(d.negative.sum()), "nonreport": int(d.nonreport.sum()),
                "catchup": int(d.catchup.sum()), "vintage_mixed": int(d.state_raw.isin(mixed).sum()),
                "nofile": int(d.nofile.sum()), "share_flagged": hfl._share(d[hfl.FLAGS].any(axis=1).sum(), n),
                "vintage_mixed_state_fys": len(mixed), "month_total_checked": len(c),
                "month_total_fail": int((~c["pass"].astype(bool)).sum()), "state_months": int(s_ok.sum()),
                "partial_component": hfl._share((s.partial_component.astype(bool) & s_ok).sum(), s_ok.sum()),
                "state_all_components_share": hfl._share(((s.n_present == s.n_components) & s_ok).sum(),
                                                         s_ok.sum()),
                "district_all_components_share": hfl._share(
                    ((d.n_present == d.n_components) & reported).sum(), reported.sum()),
                "notes": note})
    return pd.DataFrame(rows, columns=hfl.REPORT_COLUMNS)


def perinatal_parts(out_dir: Path = PARTS_F, root: Path | None = None, fys=None, xw_path: Path = pc.PERINATAL_XW_PATH,
                    report_path: Path = FLAG_REPORT_F) -> dict:
    """Every FY (default FY2012-13..2019-20 plus FY2020-21 when its folder exists), member by member, with the
    perinatal crosswalk. Stops, writing nothing, when D: has less than 2 GB free."""
    root = Path(root or hf.HMIS_ROOT)
    xw = pc.load_perinatal_crosswalk(xw_path)
    fys = list(fys) if fys else list(run.PRIMARY_FYS) + [run.FY2021]
    out_dir = Path(out_dir)
    _require_sources(root, fys, [run.FOLDER3])
    results = []
    for fy in fys:
        if _free(out_dir) < run.MIN_FREE_BYTES:
            raise RuntimeError("less than 2 GB free on the data drive; stopped")
        t0 = time.time()
        if fy == run.FY2021:
            d2, d1 = root / run.FOLDER2_FY2021, root / run.FOLDER1_FY2021
            if not d2.exists():
                print(f"{fy}: {mf._key(d2)} absent; skipped")
                continue
            res = run.flags_fy2021(d2, d1, xw)
        else:
            y = int(fy[:4])
            z = root / run.FOLDER3 / f"{y}-{y + 1}.zip"
            if not z.exists():
                print(f"{fy}: {mf._key(z)} absent; skipped")
                continue
            res = run.flags_fy_zip(z, fy, xw)
        results.append(res)
        print(f"{fy}: done in {time.time() - t0:.0f} s", flush=True)
    if _free(out_dir) < run.MIN_FREE_BYTES:
        raise RuntimeError("less than 2 GB free on the data drive; stopped")
    out_dir.mkdir(parents=True, exist_ok=True)
    tables = {}
    for k in run.TABLES:
        cols = list(results[0][k].columns) if results else []
        tables[k] = run._concat([r[k] for r in results], cols)
        tables[k].to_csv(out_dir / f"{k}.csv.gz", index=False)
    notes = {fy: run._notes(fy, tables["members"], _CONCORDANCE) for fy in sorted(set(tables["members"].fy))}
    rep = perinatal_flag_report(tables["district_month"], tables["state_month"], tables["month_total_check"], xw,
                                tables["vintage"], notes)
    report_path = Path(report_path)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    rep.to_csv(report_path, index=False, float_format="%.6f")
    mem = tables["members"]
    return {"report": rep, "tables": tables, "errors": int((mem.status == "error").sum()),
            "excluded": mem[mem.status == "excluded"].member.tolist()}


def _national_fy(fy, files, read, xw, mo_xls) -> pd.DataFrame:
    """run.national_fy for the perinatal variables of the FY's era (that function loops Paper E's INDICATORS)."""
    inds = _era_vars(xw, fy)
    rows = []
    for m in hd.FY_MONTHS:
        base = {"fy": fy, "month": m, "all_india": np.nan, "mo_in_national": False, "mo_value": np.nan}
        name = files.get(m)
        if name is None:
            rows += [dict(base, indicator=i) for i in inds]
            continue
        try:
            long = hp.parse_national(name, read(name), fy)
            ai, has_mo, mo_own = run._national_from_long(long, xw)
        except run.PARSE_ERRORS:
            rows += [dict(base, indicator=i) for i in inds]
            continue
        mo = mo_xls if mo_xls is not None else mo_own
        mo_v = {r.indicator: r.mo_value for r in mo[mo.month == m].itertuples()} if len(mo) else {}
        av = {r.indicator: r.value for r in ai.itertuples()}
        for i in inds:
            rows.append(dict(base, indicator=i, all_india=av.get(i, np.nan), mo_in_national=has_mo,
                             mo_value=mo_v.get(i, np.nan)))
    out = pd.DataFrame(rows)
    # Paper E ruling F39 (run.py): national = all_india - mo_value when the file has M/O columns, and a blank M/O value
    # counts as 0 (a zero report, not a hidden value). The real data back it: state-sum vs national differs by 0.000.
    sub = out.mo_value.fillna(0.0).where(out.mo_in_national, 0.0)
    out["national"] = out.all_india - sub
    return out[NATIONAL_COLUMNS]


def perinatal_national(out: Path = PARTS_F / "national_month.csv.gz", root: Path | None = None, fys=None,
                       xw_path: Path = pc.PERINATAL_XW_PATH) -> pd.DataFrame:
    """The folder-1 All India month files (A.MonthWise; FY2020-21: hmis_c2_1_all_india_fy2021) through
    parse_national and apply_crosswalk, net of the M/O rows (Paper E F39). A month whose file is absent or cannot be
    parsed has all_india and national NaN."""
    root = Path(root or hf.HMIS_ROOT)
    xw = pc.load_perinatal_crosswalk(xw_path)
    fys = list(fys) if fys else list(run.PRIMARY_FYS) + [run.FY2021]
    _require_sources(root, fys, [run.FOLDER1, run.FOLDER3])
    frames = []
    for fy in fys:
        t0 = time.time()
        if fy == run.FY2021:
            d1 = root / run.FOLDER1_FY2021
            files = {hp.month_from_name(f.name): f.name for f in sorted(d1.glob("*.xlsx"))} if d1.exists() else {}
            frames.append(_national_fy(fy, files, lambda n, d1=d1: (d1 / n).read_bytes(), xw, None))
        else:
            y = int(fy[:4])
            z1, z3 = root / run.FOLDER1 / f"{y}-{y + 1}.zip", root / run.FOLDER3 / f"{y}-{y + 1}.zip"
            files = run._national_month_files(z1) if z1.exists() else {}
            mo = run._mo_all_india_xls(z3, fy, xw)

            def read(n, z1=z1):
                (_, data), = hp.iter_members(z1, only={n})
                return data
            frames.append(_national_fy(fy, files, read, xw, mo))
        print(f"  national {fy}: {frames[-1].national.notna().sum()} of {len(frames[-1])} indicator-months, "
              f"{time.time() - t0:.0f} s", flush=True)
    res = pd.concat(frames, ignore_index=True)[NATIONAL_COLUMNS]
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    res.to_csv(out, index=False)
    return res


def national_check(national: pd.DataFrame, state: pd.DataFrame) -> pd.DataFrame:
    """Per FY x indicator: months with a national total and with both, and the median relative difference of the
    state sum from the national total. Printed only; the state sum leaves out flagged months, so a gap is expected."""
    s = state.groupby(["fy", "month", "indicator"])["value"].sum(min_count=1).rename("state_sum").reset_index()
    m = national.merge(s, on=["fy", "month", "indicator"], how="left")
    m["rel"] = (m.state_sum - m.national) / m.national.where(m.national > 0)
    g = m.groupby(["fy", "indicator"])
    return pd.DataFrame({"n_national": g.national.count(), "n_both": g.rel.count(),
                         "median_rel_diff": g.rel.median()}).reset_index()
