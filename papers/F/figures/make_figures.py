"""Paper F figures: Figure_1-4 as RGB TIF (LZW, no alpha, one layer, 600 dpi) plus PNG review copies.

    python -I papers/F/figures/make_figures.py                    (from <repo>)
    python -I papers/F/figures/make_figures.py --figures 1 3 --dpi 600

prepare step: each figure's data CSV is written to papers/F/figures/data/figure_<n>.csv from its inputs, and the
figure is drawn from that CSV only. Figure data hold rates, risk ratios and completeness; never stillbirth, LBW or
total-birth counts (spec 6, R2, R7). Everything ends at February 2020: no FY2020-21 value is read or written.
  1  national monthly stillbirth rate (per 1,000 total births) and LBW share (of newborns weighed), April 2012 to
     February 2020: the national month table data/derived/hmis/_parts_f/national_month.csv.gz (the official All_India
     series net of the M/O rows, blank M/O = 0; Paper E F39), the same source as the F.national.* keys. A month with a
     missing count has a missing rate (a gap), never zero. Columns: fy, ym, year, month, oni, en_month (ONI >= 0.5),
     sbr, lbw_share, and the financial-year ratio-of-sums rates sbr_fy, lbw_share_fy (months with every count present;
     they equal the F.national.sbr.<FY> and F.national.lbw_share.<FY> values, checked here to 1e-9).
  2  per-trimester RR curves (heat per +1 C, rainfall deficit per SPI -1) for both outcomes with the negative-control
     leads: papers/F/output/trimester.csv and the lead columns of primary_estimates.csv, checked against
     F.l.<O>.{heat,dry}.tri* and F.l.<O>.<S>.lead_rr. Columns: kind (trimester / lead), outcome, exposure, stratum,
     rr, lo, hi, key, display.
  3  forest plot of the six tests (verdicts.csv; keys F.l.<O>.<S>.rr, F.t.<O>.en.rr) with the selection-audit
     estimates of the same exposure summary beside them (selection.csv; keys F.sel.<D>.<S>.rr). Columns: test_id,
     hypothesis, outcome, summary, row_type (test / audit), denominator, measure (RR / OR for inst_share), key,
     display, rr, lo, hi.
  4  completeness heatmap, link unit x month, April 2012 to February 2020 (supplement): the git-ignored panel
     perinatal_unit_month.csv.gz, lowest of comp_sb and comp_lbw (blank when either is blank). Wide table: link_id,
     state_unit, then one column per month m<year>_<mm>.

Design: black-and-white readable. Series are told apart by marker shape, fill and line style, never by colour.
"""
from __future__ import annotations

import io
import json
import re
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
from matplotlib.colors import ListedColormap  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import Patch  # noqa: E402

FIG = Path(__file__).resolve().parent
PAPER = FIG.parent
ROOT = FIG.parents[2]
sys.path.insert(0, str(ROOT))
from pipeline.hmis import exposure  # noqa: E402

DATA = FIG / "data"
RESULTS = PAPER / "results.json"
OUTPUT = PAPER / "output"
HMIS = ROOT / "data" / "derived" / "hmis"
NATIONAL_CSV = HMIS / "_parts_f" / "national_month.csv.gz"
PANEL_CSV = HMIS / "perinatal_unit_month.csv.gz"
LINK_UNITS = ROOT / "pipeline" / "reference" / "hmis_link_units.csv"
ENSO_CSV = ROOT / "data" / "derived" / "enso_monthly.csv"

MM = 1 / 25.4
WIDTH_MM = {"single": 84, "double": 174}
plt.rcParams.update({
    "font.family": "sans-serif", "font.sans-serif": ["Arial", "Helvetica", "DejaVu Sans"],
    "font.size": 8, "axes.titlesize": 8, "axes.labelsize": 7.5, "xtick.labelsize": 7, "ytick.labelsize": 7,
    "legend.fontsize": 7, "legend.title_fontsize": 7, "axes.linewidth": 0.6, "xtick.major.width": 0.6,
    "ytick.major.width": 0.6, "xtick.minor.width": 0.5, "ytick.minor.width": 0.5, "lines.linewidth": 0.8,
    "axes.spines.top": False, "axes.spines.right": False, "savefig.facecolor": "white", "axes.unicode_minus": True,
    "patch.linewidth": 0.5,
})
INK = "#000000"
DARK = "#404040"
MID = "#808080"
TEXT_GREY = "#595959"
SHADE = "#DCDCDC"
MINUS = "\u2212"
EN_DASH = "\u2013"
NINO = "El Ni\u00f1o"
# Numbers that may appear in figure text outside Figure 3's key displays: design labels and scales, never estimates.
DESIGN_NUMBERS = {"0", "1", "+1", "\u22121", "1,000", "100", "0.5", "0.75", "0.90", "2012", "2013", "2014", "2015",
                  "2016", "2017", "2018", "2019", "2020", "95"}

FIRST_YM = exposure.PRIMARY_START          # April 2012
LAST_YM = exposure.PRIMARY_END             # February 2020
N_MONTHS = LAST_YM - FIRST_YM + 1
APR2017 = exposure.ym_of(2017, 4)
FYS = ["2012-13", "2013-14", "2014-15", "2015-16", "2016-17", "2017-18", "2018-19", "2019-20"]


def fy_key(fy: str) -> str:
    return "fy" + fy[2:4] + fy[5:7]


def ym_of_fy_month(fy: str, month: int) -> int:
    return exposure.ym_of(int(fy[:4]) + (0 if month >= 4 else 1), month)


# ----------------------------------------------------------------------------- keys
def load_results(path: Path = RESULTS) -> dict:
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"{path} not found: run models/F/run_all.R first")
    return json.loads(path.read_text(encoding="utf-8"))


def kv(res: dict, key: str) -> dict:
    if key not in res:
        raise KeyError(f"results.json has no key {key}")
    return {"key": key, "value": res[key]["value"], "display": res[key]["display"]}


def key_value(res: dict, key: str, want: float, tol: float = 1e-9) -> dict:
    """The key, which must hold a number equal to `want` (the CSV value) to `tol`; a mismatch is an error."""
    k = kv(res, key)
    if k["value"] is None or abs(float(k["value"]) - float(want)) > tol:
        raise ValueError(f"{key}: the output CSV gives {want}, the key {k['value']}")
    return k


def en_months(first: int = FIRST_YM, last: int = LAST_YM) -> pd.DataFrame:
    enso = pd.read_csv(ENSO_CSV)
    return exposure.enso_exposures(enso, range(first, last + 1))[["ym", "oni"]]


# ----------------------------------------------------------------------------- data CSVs
def national_month_table(national_csv: Path = NATIONAL_CSV) -> pd.DataFrame:
    """One row per primary month (95), indicators as columns (the `national` series), in time order."""
    n = pd.read_csv(national_csv, usecols=["fy", "month", "indicator", "national"])
    n = n[n["fy"].isin(FYS) & ~((n["fy"] == "2019-20") & (n["month"] == 3))]      # March 2020 is outside the window
    w = n.pivot(index=["fy", "month"], columns="indicator", values="national").reset_index()
    w["ym"] = [ym_of_fy_month(f, m) for f, m in zip(w["fy"], w["month"])]
    w = w.sort_values("ym").reset_index(drop=True)
    if len(w) != N_MONTHS or w["ym"].iloc[0] != FIRST_YM or w["ym"].iloc[-1] != LAST_YM:
        raise ValueError(f"national month table: expected {N_MONTHS} months April 2012 to February 2020, got {len(w)}")
    return w


def data_fig1(res: dict, output_dir: Path = OUTPUT, national_csv: Path = NATIONAL_CSV) -> pd.DataFrame:
    w = national_month_table(national_csv)
    d = pd.DataFrame({"fy": w["fy"], "ym": w["ym"], "year": w["ym"] // 12, "month": w["ym"] % 12 + 1})
    e = en_months().set_index("ym")["oni"]
    d["oni"] = d["ym"].map(e)
    d["en_month"] = d["oni"] >= 0.5
    d["sbr"] = w["sb"] / (w["lb"] + w["sb"]) * 1000
    d["lbw_share"] = w["lbw"] / w["wt"]
    d["sbr_fy"] = np.nan
    d["lbw_share_fy"] = np.nan
    for fy in FYS:
        sel = w["fy"] == fy
        ok = sel & w[["sb", "lb"]].notna().all(axis=1)
        d.loc[sel, "sbr_fy"] = w.loc[ok, "sb"].sum() / (w.loc[ok, "lb"] + w.loc[ok, "sb"]).sum() * 1000
        ok = sel & w[["lbw", "wt"]].notna().all(axis=1)
        d.loc[sel, "lbw_share_fy"] = w.loc[ok, "lbw"].sum() / w.loc[ok, "wt"].sum()
        key_value(res, f"F.national.sbr.{fy_key(fy)}", d.loc[sel, "sbr_fy"].iloc[0])
        key_value(res, f"F.national.lbw_share.{fy_key(fy)}", d.loc[sel, "lbw_share_fy"].iloc[0])
    return d


EXPOSURE_LABEL = {"heat": "heat", "dry": "rainfall deficit"}
OUTCOME_LABEL = {"sb": "Stillbirth rate", "lbw": "Low birth weight share"}
LEAD_SUMMARY = {"heat": "heat_t3", "dry": "dry_gest"}


def data_fig2(res: dict, output_dir: Path = OUTPUT, **_) -> pd.DataFrame:
    out = Path(output_dir)
    tri = pd.read_csv(out / "trimester.csv")
    pe = pd.read_csv(out / "primary_estimates.csv")
    rows = []
    for o in ("sb", "lbw"):
        for x in ("heat", "dry"):
            for s in ("tri1", "tri2", "tri3"):
                r = tri[(tri["outcome"] == o) & (tri["exposure"] == x) & (tri["stratum"] == s)]
                if len(r) != 1:
                    raise ValueError(f"trimester.csv: {o} {x} {s} has {len(r)} rows")
                r = r.iloc[0]
                k = key_value(res, f"F.l.{o}.{x}.{s}", r["rr"])
                rows.append({"kind": "trimester", "outcome": o, "exposure": x, "stratum": s, "rr": r["rr"],
                             "lo": r["lo"], "hi": r["hi"], "key": k["key"], "display": k["display"]})
            summ = LEAD_SUMMARY[x]
            e = pe[(pe["outcome"] == o) & (pe["model"] == "L") & (pe["term"] == summ)]
            if len(e) != 1 or e["status"].iloc[0] != "ok":
                raise ValueError(f"primary_estimates.csv: no single ok row for {o} L {summ}")
            e = e.iloc[0]
            k = key_value(res, f"F.l.{o}.{summ}.lead_rr", e["lead_rr"])
            rows.append({"kind": "lead", "outcome": o, "exposure": x, "stratum": "lead", "rr": e["lead_rr"],
                         "lo": e["lead_lo"], "hi": e["lead_hi"], "key": k["key"], "display": k["display"]})
    return pd.DataFrame(rows)


TESTS = [("h10a", "H10", "sb", "heat_t3"), ("h10b", "H10", "sb", "dry_gest"), ("h10c", "H10", "sb", "en"),
         ("h11a", "H11", "lbw", "heat_gest"), ("h11b", "H11", "lbw", "dry_gest"), ("h11c", "H11", "lbw", "en")]
DENOMS = ["tb", "wt", "inst_share"]


def data_fig3(res: dict, output_dir: Path = OUTPUT, **_) -> pd.DataFrame:
    out = Path(output_dir)
    vd = pd.read_csv(out / "verdicts.csv").set_index("test_id")
    sel = pd.read_csv(out / "selection.csv")
    rows = []
    for tid, hyp, o, s in TESTS:
        v = vd.loc[tid]
        if v["outcome"] != o or v["summary"] != s:
            raise ValueError(f"verdicts.csv: {tid} is {v['outcome']} {v['summary']}, expected {o} {s}")
        key = f"F.t.{o}.en.rr" if s == "en" else f"F.l.{o}.{s}.rr"
        k = key_value(res, key, v["rr"])
        rows.append({"test_id": tid, "hypothesis": hyp, "outcome": o, "summary": s, "row_type": "test",
                     "denominator": "", "measure": "RR", "key": k["key"], "display": k["display"],
                     "rr": v["rr"], "lo": v["lo"], "hi": v["hi"]})
        for dn in DENOMS:
            r = sel[(sel["outcome"] == dn) & (sel["term"] == s)]
            if len(r) != 1 or r["status"].iloc[0] != "ok":
                raise ValueError(f"selection.csv: no single ok row for {dn} {s}")
            r = r.iloc[0]
            k = key_value(res, f"F.sel.{dn}.{s}.rr", r["rr"])
            rows.append({"test_id": tid, "hypothesis": hyp, "outcome": o, "summary": s, "row_type": "audit",
                         "denominator": dn, "measure": "OR" if dn == "inst_share" else "RR", "key": k["key"],
                         "display": k["display"], "rr": r["rr"], "lo": r["lo"], "hi": r["hi"]})
    return pd.DataFrame(rows)


def month_col(ym: int) -> str:
    return f"m{ym // 12}_{ym % 12 + 1:02d}"


def band(x: pd.Series) -> pd.Series:
    return pd.Series(np.select([x >= 0.90, x >= 0.75], ["ge090", "075_090"], "lt075"), index=x.index).where(x.notna())


def data_fig4(res: dict | None = None, output_dir: Path = OUTPUT, panel_csv: Path = PANEL_CSV,
              link_units: Path = LINK_UNITS, **_) -> pd.DataFrame:
    p = pd.read_csv(panel_csv, usecols=["link_id", "state_unit", "ym", "comp_sb", "comp_lbw"])
    p = p[(p["ym"] >= FIRST_YM) & (p["ym"] <= LAST_YM)].copy()               # primary window: no FY2020-21 row
    lu = set(pd.read_csv(link_units)["link_id"].dropna())
    if set(p["link_id"]) != lu:
        raise ValueError("panel link units differ from hmis_link_units.csv")
    if len(p) != len(lu) * N_MONTHS:
        raise ValueError(f"panel: expected {len(lu) * N_MONTHS} link-unit-months in the primary window, got {len(p)}")
    if res is not None and len(p) != int(kv(res, "F.panel.n_unit_months")["value"]):
        raise ValueError("panel unit-months differ from F.panel.n_unit_months")
    p["comp_min"] = p[["comp_sb", "comp_lbw"]].min(axis=1, skipna=False).round(4)
    p["col"] = p["ym"].map(month_col)
    wide = p.pivot(index="link_id", columns="col", values="comp_min")
    wide = wide[[month_col(y) for y in range(FIRST_YM, LAST_YM + 1)]]
    st = p.drop_duplicates("link_id").set_index("link_id")["state_unit"]
    wide.insert(0, "state_unit", st.reindex(wide.index))
    wide = wide.reset_index().sort_values(["state_unit", "link_id"], kind="stable").reset_index(drop=True)
    return wide


# ----------------------------------------------------------------------------- drawing helpers
def panel_label(ax, text: str) -> None:
    ax.set_title(text, loc="left", fontweight="bold", fontsize=8)


def _runs(mask) -> list[tuple[int, int]]:
    out, start = [], None
    vals = list(mask) + [False]
    for i, v in enumerate(vals):
        if v and start is None:
            start = i
        if not v and start is not None:
            out.append((start, i - 1))
            start = None
    return out


def _year_ticks(ax, ym: pd.Series) -> None:
    ym = pd.Series(list(ym))
    idx = [i for i, v in enumerate(ym) if v % 12 == 0]          # January
    ax.set_xticks(idx)
    ax.set_xticklabels([str(int(ym.iloc[i]) // 12) for i in idx])
    ax.set_xticks([i for i, v in enumerate(ym) if v % 12 == 3], minor=True)   # April (FY start)
    ax.set_xlim(-0.5, len(ym) - 0.5)


# ----------------------------------------------------------------------------- Figure 1
def figure1(csv: Path, width_mm: dict) -> plt.Figure:
    d = pd.read_csv(csv)
    fig, axs = plt.subplots(2, 1, sharex=True, layout="constrained", figsize=(width_mm["double"] * MM, 105 * MM))
    x = np.arange(len(d))
    i17 = int(np.flatnonzero(d["ym"] == APR2017)[0])
    panels = (("sbr", "(a) Stillbirths per 1,000 total births", "Per 1,000 total births", 1.0),
              ("lbw_share", "(b) Low birth weight share of newborns weighed", "Per cent of newborns weighed", 100.0))
    for ax, (col, title, ylabel, scale) in zip(axs, panels):
        for a, b in _runs(d["en_month"].astype(bool)):
            ax.axvspan(a - 0.5, b + 0.5, facecolor=SHADE, edgecolor="none", lw=0, zorder=0, gid="en_shade")
        ax.axvline(i17 - 0.5, color=INK, ls=(0, (1, 1.5)), lw=0.8, zorder=1)
        y = d[col].to_numpy() * scale
        ax.plot(x, y, color=INK, lw=0.9, zorder=3)                       # a missing month leaves a gap
        for fy, g in d.groupby("fy"):
            ax.hlines(g[f"{col}_fy"].iloc[0] * scale, g.index.min() - 0.5, g.index.max() + 0.5, color=MID, lw=1.2,
                      ls=(0, (4, 2)), zorder=2, gid="fy_mean")
        lo, hi = np.nanmin(y), np.nanmax(y)
        ax.set_ylim(lo - 0.08 * (hi - lo), hi + 0.08 * (hi - lo))
        ax.yaxis.set_major_locator(matplotlib.ticker.MaxNLocator(5))
        ax.set_ylabel(ylabel)
        panel_label(ax, title)
    _year_ticks(axs[-1], d["ym"])
    axs[-1].set_xlabel("Birth month, calendar year (minor ticks: April, the start of each financial year)")
    handles = [Patch(facecolor=SHADE, edgecolor="none", label=f"{NINO} month (ONI \u2265 0.5)"),
               Line2D([], [], color=INK, ls=(0, (1, 1.5)), lw=0.8, label="HMIS format change, April 2017"),
               Line2D([], [], color=INK, lw=0.9, label="Monthly national value"),
               Line2D([], [], color=MID, ls=(0, (4, 2)), lw=1.2, label="Financial-year ratio of sums")]
    fig.legend(handles=handles, loc="outside upper center", ncol=2, frameon=False)
    return fig


# ----------------------------------------------------------------------------- Figure 2
F2_COLS = (("heat", f"heat, RR per +1 \u00b0C"),
           ("dry", f"rainfall deficit, RR per SPI {MINUS}1"))
F2_X = {"tri1": 0, "tri2": 1, "tri3": 2, "lead": 3.4}
F2_TICKS = ["First\ntrimester", "Second\ntrimester", "Third\ntrimester", "Negative\ncontrol (lead)"]


def figure2(csv: Path, width_mm: dict) -> plt.Figure:
    d = pd.read_csv(csv)
    fig, axs = plt.subplots(2, 2, sharex=True, layout="constrained", figsize=(width_mm["double"] * MM, 115 * MM))
    lo, hi = float(d["lo"].min()), float(d["hi"].max())
    pad = 0.06 * (hi - lo)
    letters = iter("abcd")
    for i, o in enumerate(("sb", "lbw")):
        for j, (x, what) in enumerate(F2_COLS):
            ax = axs[i, j]
            g = d[(d["outcome"] == o) & (d["exposure"] == x)]
            ax.axhline(1, color=MID, lw=0.6, zorder=0)
            t = g[g["kind"] == "trimester"].sort_values("stratum")
            xs = [F2_X[s] for s in t["stratum"]]
            ax.plot(xs, t["rr"], color=INK, lw=0.9, zorder=2)
            ax.vlines(xs, t["lo"], t["hi"], color=INK, lw=0.8, zorder=2)
            ax.plot(xs, t["rr"], ls="none", marker="o", mfc=INK, mec=INK, ms=4, zorder=3)
            ld = g[g["kind"] == "lead"].iloc[0]
            ax.vlines([F2_X["lead"]], [ld["lo"]], [ld["hi"]], color=INK, lw=0.8, zorder=2)
            ax.plot([F2_X["lead"]], [ld["rr"]], ls="none", marker="s", mfc="white", mec=INK, ms=4, mew=0.8, zorder=3)
            ax.set_ylim(lo - pad, hi + pad)
            ax.set_ylabel("RR")
            ax.set_xticks(list(F2_X.values()))
            ax.set_xticklabels(F2_TICKS)
            ax.set_xlim(-0.5, 3.9)
            panel_label(ax, f"({next(letters)}) {OUTCOME_LABEL[o]}:\n{what}")
    handles = [Line2D([], [], color=INK, lw=0.9, marker="o", mfc=INK, ms=4, label="Trimester stratum, 95% CI"),
               Line2D([], [], ls="none", marker="s", mfc="white", mec=INK, ms=4, mew=0.8,
                      label="Negative-control lead, 95% CI"),
               Line2D([], [], color=MID, lw=0.6, label="RR = 1")]
    fig.legend(handles=handles, loc="outside upper center", ncol=3, frameon=False)
    return fig


# ----------------------------------------------------------------------------- Figure 3
TEST_LABEL = {"h10a": "H10a stillbirth, third-trimester heat", "h10b": "H10b stillbirth, rainfall deficit",
              "h10c": f"H10c stillbirth, {NINO} gestation", "h11a": "H11a low birth weight, full-gestation heat",
              "h11b": "H11b low birth weight, rainfall deficit", "h11c": f"H11c low birth weight, {NINO} gestation"}
DENOM_LABEL = {"tb": "audit: total births (RR)", "wt": "audit: newborns weighed (RR)",
               "inst_share": "audit: institutional share (OR)"}
AUDIT_STYLE = {"tb": "s", "wt": "D", "inst_share": "^"}


def figure3(csv: Path, width_mm: dict) -> plt.Figure:
    d = pd.read_csv(csv, dtype={"denominator": str}, keep_default_na=False, na_values=[""])
    d["denominator"] = d["denominator"].fillna("")
    fig, (ax, tx) = plt.subplots(1, 2, sharey=True, layout="constrained", figsize=(width_mm["double"] * MM, 150 * MM),
                                 gridspec_kw={"width_ratios": [3.0, 1.35]})
    ys, y, labels, ticks = [], 0.0, [], []
    for tid, g in d.groupby("test_id", sort=False):
        for r in g.itertuples():
            ys.append(y)
            ticks.append(y)
            labels.append(TEST_LABEL[tid] if r.row_type == "test" else "    " + DENOM_LABEL[r.denominator])
            y -= 1.0
        y -= 0.6
    d["y"] = ys
    ax.axvline(1, color=MID, lw=0.6, zorder=0)
    for r in d.itertuples():
        ax.plot([r.lo, r.hi], [r.y, r.y], color=INK, lw=0.8, solid_capstyle="butt", zorder=2)
        if r.row_type == "test":
            ax.plot([r.rr], [r.y], ls="none", marker="o", mfc=INK, mec=INK, ms=4.2, zorder=3)
        else:
            ax.plot([r.rr], [r.y], ls="none", marker=AUDIT_STYLE[r.denominator], mfc="white", mec=INK, ms=3.6,
                    mew=0.8, zorder=3)
        tx.text(0.0, r.y, r.display, ha="left", va="center", fontsize=7, fontweight="bold" if r.row_type == "test"
                else "normal")
    lo, hi = float(d["lo"].min()), float(d["hi"].max())
    span = max(1 - lo, hi - 1)
    ax.set_xlim(1 - 1.1 * span, 1 + 1.1 * span)
    ax.xaxis.set_major_locator(matplotlib.ticker.MaxNLocator(6))
    ax.xaxis.set_major_formatter(matplotlib.ticker.FormatStrFormatter("%.2f"))
    ax.set_xlabel("RR or OR")
    ax.set_yticks(ticks)
    ax.set_yticklabels(labels)
    ax.tick_params(axis="y", length=0)
    ax.set_ylim(min(ys) - 0.8, 0.8)
    tx.axis("off")
    tx.set_xlim(0, 1)
    tx.set_title("RR or OR (95% CI)", loc="left", fontsize=7)
    handles = [Line2D([], [], ls="none", marker="o", mfc=INK, mec=INK, ms=4.2, label="Primary test (RR)"),
               Line2D([], [], ls="none", marker="s", mfc="white", mec=INK, ms=3.6, mew=0.8, label="Audit, total births"),
               Line2D([], [], ls="none", marker="D", mfc="white", mec=INK, ms=3.6, mew=0.8,
                      label="Audit, newborns weighed"),
               Line2D([], [], ls="none", marker="^", mfc="white", mec=INK, ms=3.6, mew=0.8,
                      label="Audit, institutional share (OR)")]
    fig.legend(handles=handles, loc="outside upper center", ncol=4, frameon=False)
    return fig


# ----------------------------------------------------------------------------- Figure 4
BAND_CODES = {"ge090": 0, "075_090": 1, "lt075": 2}
BAND_GREYS = ["#F2F2F2", "#8C8C8C", "#1A1A1A"]
BAND_LABELS = ["\u2265 0.90", "0.75 to < 0.90", "< 0.75"]


def figure4(csv: Path, width_mm: dict) -> plt.Figure:
    d = pd.read_csv(csv)
    month_cols = [c for c in d.columns if re.fullmatch(r"m\d{4}_\d{2}", c)]
    yms = [12 * int(c[1:5]) + int(c[6:8]) - 1 for c in month_cols]
    vals = d[month_cols].to_numpy(dtype=float)
    code = np.where(np.isnan(vals), np.nan, np.where(vals >= 0.90, 0, np.where(vals >= 0.75, 1, 2)))
    fig, ax = plt.subplots(layout="constrained", figsize=(width_mm["double"] * MM, 170 * MM))
    cmap = ListedColormap(BAND_GREYS)
    cmap.set_bad("white")
    ax.imshow(np.ma.masked_invalid(code), cmap=cmap, vmin=-0.5, vmax=2.5, aspect="auto", interpolation="nearest")
    states = list(dict.fromkeys(d["state_unit"]))
    first = {s: int(np.flatnonzero(d["state_unit"] == s)[0]) for s in states}
    last = {s: int(np.flatnonzero(d["state_unit"] == s)[-1]) for s in states}
    big = [s for s in states if last[s] - first[s] + 1 >= 12]      # smaller state units are unlabelled (no room)
    ax.set_yticks([(first[s] + last[s]) / 2 for s in big])
    ax.set_yticklabels(big)
    ax.tick_params(axis="y", length=2)
    for s in states[:-1]:
        if last[s] - first[s] + 1 >= 12:                           # separators only where a unit has room
            ax.axhline(last[s] + 0.5, color=MID, lw=0.5)
    _year_ticks(ax, pd.Series(yms))
    ax.axvline(yms.index(APR2017) - 0.5, color=INK, ls=(0, (1, 1.5)), lw=0.8)
    for sp in ("top", "right"):
        ax.spines[sp].set_visible(True)
    ax.set_xlabel("Birth month, calendar year (minor ticks: April)")
    ax.set_ylabel("Link unit, grouped by state unit")
    bands = [Patch(facecolor=g, edgecolor=INK, lw=0.5, label=lab) for g, lab in zip(BAND_GREYS, BAND_LABELS)]
    handles = bands + [Line2D([], [], color=INK, ls=(0, (1, 1.5)), lw=0.8, label="HMIS format change, April 2017")]
    if np.isnan(vals).any():
        handles.append(Patch(facecolor="white", edgecolor=INK, lw=0.5, label="Blank"))
    fig.legend(handles=handles, loc="outside upper center", ncol=5, frameon=False,
               title="Lowest completeness of the stillbirth and LBW items (valid / member HMIS districts)")
    return fig


# ----------------------------------------------------------------------------- registry, save and main
FIGURES = {
    "1": {"build": figure1, "data": data_fig1, "results": True},
    "2": {"build": figure2, "data": data_fig2, "results": True},
    "3": {"build": figure3, "data": data_fig3, "results": True},
    "4": {"build": figure4, "data": data_fig4, "results": True},
}


def save(fig, out_dir: Path, name: str, dpi: int) -> list[Path]:
    """Figure_<name>.tif (RGB, LZW, `dpi`, no alpha, one layer) and Figure_<name>.png (half-resolution review copy)."""
    from PIL import Image
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=dpi, facecolor="white")
    plt.close(fig)
    buf.seek(0)
    with Image.open(buf) as im:
        rgb = im.convert("RGB")
    tif, png = out_dir / f"Figure_{name}.tif", out_dir / f"Figure_{name}.png"
    rgb.save(tif, format="TIFF", compression="tiff_lzw", dpi=(dpi, dpi))
    w, h = rgb.size
    rgb.resize((max(1, w // 2), max(1, h // 2)), Image.LANCZOS).save(png, format="PNG", dpi=(dpi // 2, dpi // 2))
    print(f"Figure_{name}: {w}x{h} px at {dpi} dpi ({w / dpi * 25.4:.0f} x {h / dpi * 25.4:.0f} mm)")
    return [tif, png]


def main(out_dir: Path = FIG, data_dir: Path = DATA, dpi: int = 600, figures: list[str] | None = None,
         results: Path = RESULTS, output_dir: Path = OUTPUT, width_mm: dict | None = None) -> dict:
    width_mm = dict(width_mm or WIDTH_MM)
    res = load_results(results)
    out: dict = {}
    for n in figures or list(FIGURES):
        d = FIGURES[n]["data"](res, output_dir=Path(output_dir))
        csv = Path(data_dir) / f"figure_{n}.csv"
        csv.parent.mkdir(parents=True, exist_ok=True)
        d.to_csv(csv, index=False, lineterminator="\n", float_format="%.15g")
        out[n] = save(FIGURES[n]["build"](csv, width_mm), Path(out_dir), n, dpi)
    return out


def cli(argv: list[str] | None = None) -> dict:
    import argparse
    ap = argparse.ArgumentParser(description="Draw Paper F Figures 1-4.")
    ap.add_argument("--out-dir", type=Path, default=FIG)
    ap.add_argument("--data-dir", type=Path, default=DATA)
    ap.add_argument("--dpi", type=int, default=600)
    ap.add_argument("--figures", nargs="*", choices=list(FIGURES), default=None)
    a = ap.parse_args(argv)
    return main(out_dir=a.out_dir, data_dir=a.data_dir, dpi=a.dpi, figures=a.figures)


if __name__ == "__main__":
    cli()
