"""Paper F HMIS pipeline CLI (Task 1: perinatal crosswalk sample parse).

    python -I pipeline/hmis/run_f.py parse-sample   # one member per sampled FY + every crosswalk verified_in_file:
                                                    # parse, apply the perinatal crosswalk, print COUNTS only
                                                    # (unit-months found and non-missing per variable); exit 1 when a
                                                    # variable wanted in an era (ERAS_BY_VAR) is not found
    python -I pipeline/hmis/run_f.py parts          # Task 2: every FY member by member -> data/derived/hmis/_parts_f/
                                                    # and the counts-only perinatal_flag_report.csv
    python -I pipeline/hmis/run_f.py national       # Task 2: folder-1 All India month files, net of M/O rows (F39)
    python -I pipeline/hmis/run_f.py units          # Task 3: HMIS districts -> GADM link units, R3 manual-review guard
                                                    # (exit 1: unresolved names listed; exit 2: a halt)
    python -I pipeline/hmis/run_f.py panel          # Task 4: link-unit-month panel, gates, halt rules, d24 table
                                                    # (exit 2: PerinatalHalt; the panel is then not written)
    python -I pipeline/hmis/run_f.py release-panel  # Task 5: tracked small-number release panel (R7), FY2012-13 to
                                                    # 2019-20, suppression applied; exit 1 on any suppression finding
    python -I pipeline/hmis/run_f.py climate        # Task 6: link-unit-month climate, tracked climate_link_unit_month.csv.gz
    python -I pipeline/hmis/run_f.py model-table    # Task 6: gestational exposures + model table (git-ignored
                                                    # perinatal_model.csv.gz); prints NaN shares and descriptive SDs only
    python -I pipeline/hmis/run_f.py sources        # Task 12: papers/F/sources.md (pipeline/hmis/perinatal_sources.py)

Raw downloads are untrusted data: members are read in place with parse.iter_members (never extracted) and parsed as
data only. Paper E's modules are called unchanged.
"""
import argparse
import re
import sys
from pathlib import Path

import pandas as pd

if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pipeline import manifest as mf  # noqa: E402
from pipeline.hmis import crosswalk as hx  # noqa: E402
from pipeline.hmis import fetch as hf  # noqa: E402
from pipeline.hmis import parse as hp  # noqa: E402
from pipeline.hmis import perinatal_crosswalk as pc  # noqa: E402
from pipeline.hmis import perinatal_climate as pcl  # noqa: E402
from pipeline.hmis import perinatal_model_table as pmt  # noqa: E402
from pipeline.hmis import perinatal_panel as ppanel  # noqa: E402
from pipeline.hmis import perinatal_parts as pp  # noqa: E402
from pipeline.hmis import perinatal_release as prel  # noqa: E402
from pipeline.hmis import perinatal_sources as psrc  # noqa: E402
from pipeline.hmis import perinatal_units as pu  # noqa: E402
from pipeline.paths import ROOT  # noqa: E402

SAMPLE_MEMBER = "A & N Islands.xls"            # smallest state workbook with districts, every FY
SAMPLE_FY2021 = "Andaman_Nicobar_Islands__A-Andaman_Nicobar_Islands_Apr.xlsx"
SAMPLE_FYS = ("2012-13", "2014-15", "2017-18", "2019-20")


def _fy_short(text: str) -> str | None:
    m = re.search(r"(20\d\d)-(20\d\d)", text)
    return f"{m.group(1)}-{m.group(2)[2:]}" if m else None


def sample_targets(xw, root: Path | None = None) -> list[tuple[str, Path, str | None]]:
    """(fy, file, zip member or None): the A & N Islands workbook of each sampled folder-3 FY, one FY2020-21
    folder-2 month file, and every crosswalk verified_in_file."""
    root = Path(root or hf.HMIS_ROOT)
    f3 = root / "hmis_c2_3_states_months"
    out = []
    for fy in SAMPLE_FYS:
        y = int(fy[:4])
        out.append((fy, f3 / f"{y}-{y + 1}.zip", f"{y}-{y + 1}/{SAMPLE_MEMBER}"))
    out.append(("2020-21", root / "hmis_c2_2_states_districts_fy2021" / SAMPLE_FY2021, None))
    for era, v in sorted(set(zip(xw.era, xw.verified_in_file))):
        path, _, member = v.partition("::")
        out.append(("2020-21" if era == "E3" else _fy_short(path), ROOT / path, member or None))
    seen, uniq = set(), []
    for t in out:
        key = (t[0], str(t[1]), t[2])
        if key not in seen:
            seen.add(key)
            uniq.append(t)
    return uniq


def parse_sample(xw_path: Path = pc.PERINATAL_XW_PATH, root: Path | None = None) -> dict:
    """Parse the sample targets and apply the perinatal crosswalk. Prints COUNTS only, never values."""
    xw = pc.load_perinatal_crosswalk(xw_path)
    problems = hx.verify_crosswalk(xw, mf.read())
    results, missing, absent_files = [], [], []
    for fy, path, member in sample_targets(xw, root):
        source = mf._key(path) + (f"::{member}" if member else "")
        if not path.exists():
            results.append({"fy": fy, "source": source, "status": "absent"})
            absent_files.append(source)
            print(f"{fy}  {source}: absent")
            continue
        if member:
            found = list(hp.iter_members(path, only={member}))
            if len(found) != 1:
                absent_files.append(source)
                print(f"{fy}  {source}: member {member!r} not found in {path.name} ({len(found)} matches)")
                continue
            (_, data), = found
        else:
            data = path.read_bytes()
        long = hp.parse_member(source, data, fy)
        era = hp.era_for_fy(fy)
        out = hx.apply_crosswalk(long, xw)
        wanted = [v for v, eras in pc.ERAS_BY_VAR.items() if era in eras]
        per = {v: (int((out.indicator == v).sum()), int(out[out.indicator == v].value.notna().sum()))
               for v in wanted}
        absent = [v for v in wanted if per[v][0] == 0]
        extra = sorted(set(out.indicator) - set(wanted))
        missing += [(fy, source, v) for v in absent]
        results.append({"fy": fy, "source": source, "era": era, "per": per})
        print(f"{fy} {era}  {source}: {len(long)} rows; unit-months found/non-missing: "
              + " ".join(f"{v}={n}/{k}" for v, (n, k) in per.items())
              + f"; not found: {absent or 'none'}; unexpected: {extra or 'none'}", flush=True)
    print(f"crosswalk verified_in_file problems: {problems or 'none'}; "
          f"wanted variables not found: {missing or 'none'}; {len(absent_files)} files absent")
    return {"files": results, "problems": problems, "missing": missing, "absent": absent_files}


def parts_step() -> int:
    res = pp.perinatal_parts()
    rep = res["report"]
    print(f"member errors: {res['errors']}; excluded members: {len(res['excluded'])}")
    print(rep.pivot(index="indicator", columns="fy", values="share_flagged").round(3).to_string())
    return 1 if res["errors"] else 0


def national_step() -> int:
    nat = pp.perinatal_national()
    state = pd.read_csv(pp.PARTS_F / "state_month.csv.gz") if (pp.PARTS_F / "state_month.csv.gz").exists() else None
    print(f"national: {nat.national.notna().sum()} of {len(nat)} indicator-months available")
    if state is not None:
        print(pp.national_check(nat, state).round(3).to_string())
    return 0


def panel_step() -> int:
    res = ppanel.build_perinatal_panel()
    s = res["summary"]
    print(s[s.scope == "primary"][["variable", "reported", "masked", "masked_share_window", "comp_lt_1",
                                   "entering_models", "excluded_units"]].round(4).to_string(index=False))
    print(f"dropped: {res['dropped'] or 'none'}; ghosts: {res['n_ghosts']}; FY2020-21: {res['halt_info']['fy2021']}")
    if res["halt"]:
        print(f"HALT: {res['halt']}")
        return 2
    return 0


def climate_step() -> int:
    out = pcl.build()
    c = pd.read_csv(out)
    print(f"{out}: {len(c)} rows, {c.link_id.nunique()} link units, ym {c.ym.min()}..{c.ym.max()}, "
          f"{out.stat().st_size / 1e6:.2f} MB")
    print(c[["rain_mm", "tmax_mean", "heatwave_days", "spi3", "spi3_dry", "tmax_anom"]].isna().mean().round(4).to_string())
    return 0


def model_table_step() -> int:
    out = pmt.build_perinatal_model()
    m = pd.read_csv(out, dtype={"fy": str})
    p = m[m.in_primary == 1]
    print(f"{out}: {len(m)} rows ({m.link_id.nunique()} link units x {m.ym.nunique()} months), "
          f"{len(p)} in the primary window")
    for rep in pmt.describe(m):
        print(rep.round(4).to_string())
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("step", choices=["parse-sample", "parts", "national", "units", "panel", "release-panel", "climate",
                                     "model-table", "sources"])
    step = ap.parse_args(argv).step
    if step == "sources":
        return psrc.sources_step()
    if step == "climate":
        return climate_step()
    if step == "model-table":
        return model_table_step()
    if step == "release-panel":
        return prel.release_step()
    if step == "units":
        return pu.units_step()
    if step == "panel":
        return panel_step()
    if step in ("parts", "national"):
        try:
            return parts_step() if step == "parts" else national_step()
        except pp.MissingSourcesError as e:
            print(f"FAILED: {e}", file=sys.stderr)
            return 1
    res = parse_sample()
    if res["absent"]:
        print(f"FAILED: {len(res['absent'])} files absent: nothing was verified for them", file=sys.stderr)
    return 1 if res["missing"] or res["problems"] or res["absent"] else 0


if __name__ == "__main__":
    sys.exit(main())
