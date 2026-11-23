"""Descriptive and derived quantities for the weekly analysis (no model is fitted).

Reproduces the analysed sample of models/F/R/weekly_f.R (w_prepare: outcome present, total births >= 20, every weekly
exposure and both negative controls present; no gate exclusions in this panel) and checks its size against
F.w.flow.n_analysed. Computes: births, stillbirths and the stillbirth rate; the rate by thirds of the gestation-mean
heat anomaly; the distribution of the gestation-mean exposures (overall SD and SD within year-month); cumulative risk
ratios and E-values per within-year-month SD (from the primary model's log-RR and SE in w_cumulative.csv); missingness
split into missing values and ineligibility; the AIC difference of the season-specific model.
Writes models/F/output/w_descriptives.csv and appends the keys F.w.desc.* to papers/F/results.json (text append; every
existing byte kept; re-running replaces only the appended block). Run after models/F/05_weekly.R --step=results:
    python -I models/F/06_weekly_descriptives.py
"""
import csv
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "papers/F/results.json"
OUTD = ROOT / "models/F/output"
MINUS = "−"
SCRIPT = "models/F/06_weekly_descriptives.py"


def f1(x):
    return f"{x:.1f}".replace("-", MINUS)


def f2(x):
    return f"{x:.2f}".replace("-", MINUS)


def evalue(rr):
    rr = 1 / rr if rr < 1 else rr
    return rr + math.sqrt(rr * (rr - 1))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    res = json.loads(RES.read_text(encoding="utf-8"))
    m = pd.read_csv(ROOT / "data/derived/hmis/perinatal_model.csv.gz",
                    usecols=["link_id", "ym", "year", "month", "sb", "tb", "in_primary", "inst"])
    m = m[m.in_primary == 1]
    ex = pd.read_csv(ROOT / "data/derived/hmis/perinatal_weekly_exposure.csv.gz")
    hc = [f"heat_w{w:02d}" for w in range(1, 41)]
    dc = [f"dry_w{w:02d}" for w in range(1, 41)]
    ex = ex[["link_id", "ym"] + hc + dc + ["heat_nc8", "dry_nc8"]]
    d = m.merge(ex, on=["link_id", "ym"], how="left")
    n_panel = len(d)
    ok_out = d.sb.notna() & d.tb.notna() & (d.tb > 0)
    ok_den = ok_out & (d.tb >= 20)
    ok_exp = d[hc + dc + ["heat_nc8", "dry_nc8"]].notna().all(axis=1)
    inc = ok_den & ok_exp
    n_inc = int(inc.sum())
    want = int(res["F.w.flow.n_analysed"]["value"])
    if n_inc != want:
        sys.exit(f"analysed sample {n_inc} != F.w.flow.n_analysed {want}; definitions differ")
    a = d[inc].copy()
    a["heat_g"] = a[hc].mean(axis=1)
    a["dry_g"] = a[dc].mean(axis=1)
    births, sbs = float(a.tb.sum()), float(a.sb.sum())
    rate = 1000 * sbs / births
    a["tert"] = pd.qcut(a.heat_g, 3, labels=["low", "mid", "high"])
    tr = a.groupby("tert", observed=True).agg(sb=("sb", "sum"), tb=("tb", "sum"), lo=("heat_g", "min"),
                                              hi=("heat_g", "max"))
    tr["rate"] = 1000 * tr.sb / tr.tb
    sd_within = lambda s: float((s - s.groupby(a.ym).transform("mean")).std())  # noqa: E731
    stats = {"heat_mean": a.heat_g.mean(), "heat_sd": a.heat_g.std(), "heat_sd_within": sd_within(a.heat_g),
             "dry_mean": a.dry_g.mean(), "dry_sd": a.dry_g.std(), "dry_sd_within": sd_within(a.dry_g)}
    cum = {(r["exposure"], r["block"]): r for r in csv.DictReader(open(OUTD / "w_cumulative.csv", encoding="utf-8"))
           if r["model"] == "pooled"}
    persd = {}
    for e, sdk, sign in (("heat", "heat_sd_within", 1), ("dry", "dry_sd_within", 1)):
        for b in ("t3", "gest"):
            r = cum[(e, b)]
            est, se = float(r["est"]), float(r["se"])
            sd = stats[sdk]
            # cumulative log-RR per unit sustained over the block; per SD of the gestation-mean exposure
            # (deficit orientation as in the primary keys: RR per one unit more deficit = rr column)
            rr_unit, lo_unit, hi_unit = float(r["rr"]), float(r["lo"]), float(r["hi"])
            lrr, llo, lhi = (math.log(rr_unit) * sd, math.log(lo_unit) * sd, math.log(hi_unit) * sd)
            persd[(e, b)] = (math.exp(lrr), math.exp(llo), math.exp(lhi))
    flow = {k[len("F.w.flow."):]: int(v["value"]) for k, v in res.items() if k.startswith("F.w.flow.")}
    miss_n = flow["excl_outcome"] + flow["excl_exposure"]
    inel_n = flow["excl_denom"]
    aic_diff = float(res["F.w.aic.pooled"]["value"]) - float(res["F.w.aic.season"]["value"])

    keys = {}

    def put(k, v, disp, desc):
        keys["F.w.desc." + k] = {"value": v, "display": disp, "script": SCRIPT, "description": desc}

    put("births", births, f"{births:,.0f}", "Total births (live births plus stillbirths) in the analysed unit-months")
    put("stillbirths", sbs, f"{sbs:,.0f}", "Stillbirths in the analysed unit-months")
    put("rate", rate, f1(rate), "Stillbirths per 1,000 total births, analysed unit-months")
    for t, lab in (("low", "lowest"), ("mid", "middle"), ("high", "highest")):
        r = tr.loc[t]
        put(f"rate_{t}", float(r.rate), f1(float(r.rate)),
            f"Stillbirths per 1,000 total births in unit-months in the {lab} third of the gestation-mean heat anomaly "
            f"({r.lo:.2f} to {r.hi:.2f} °C)")
        put(f"tert_{t}_range", [float(r.lo), float(r.hi)], f"{f2(r.lo)} to {f2(r.hi)} °C",
            f"Range of the gestation-mean heat anomaly in the {lab} third")
    put("heat_mean_sd", [stats["heat_mean"], stats["heat_sd"]], f"{f2(stats['heat_mean'])} °C ({f2(stats['heat_sd'])})",
        "Mean (SD) of the gestation-mean maximum-temperature anomaly, analysed unit-months")
    put("heat_sd_within", stats["heat_sd_within"], f"{f2(stats['heat_sd_within'])} °C",
        "SD of the gestation-mean heat anomaly within year-month (the variation the model uses)")
    put("dry_mean_sd", [stats["dry_mean"], stats["dry_sd"]], f"{f2(stats['dry_mean'])} ({f2(stats['dry_sd'])})",
        "Mean (SD) of the gestation-mean SPI-28 deficit (min(SPI-28, 0)), analysed unit-months")
    put("dry_sd_within", stats["dry_sd_within"], f2(stats["dry_sd_within"]),
        "SD of the gestation-mean SPI-28 deficit within year-month")
    for (e, b), (rr, lo, hi) in persd.items():
        put(f"persd.{e}.{b}", [rr, lo, hi], f"{f2(rr)} (95% CI {f2(lo)}, {f2(hi)})",
            f"Cumulative RR per within-year-month SD of the gestation-mean {e} exposure sustained over block {b}")
    for b in ("t3", "gest"):
        rr, lo, hi = persd[("heat", b)]
        put(f"persd.evalue.heat.{b}", [evalue(rr), evalue(lo) if lo > 1 else 1.0],
            f"{f2(evalue(rr))} ({f2(evalue(lo) if lo > 1 else 1.0)})",
            f"E-value (and for the CI limit nearer 1) for the per-SD heat RR, block {b}")
    put("missing_n", miss_n, f"{miss_n:,}", "Unit-months with a missing stillbirth, total-birth or exposure value")
    put("missing_share", miss_n / n_panel, f"{100 * miss_n / n_panel:.1f}%", "Share of the panel with a missing value")
    put("inelig_n", inel_n, f"{inel_n:,}", "Unit-months with fewer than 20 total births (ineligible)")
    put("inelig_share", inel_n / n_panel, f"{100 * inel_n / n_panel:.1f}%", "Share of the panel ineligible (fewer than 20 births)")
    wm = {r["variable"]: r for r in csv.DictReader(open(OUTD / "w_missing.csv", encoding="utf-8"))}
    for v, lab in (("inst_share", "institutional share of deliveries"), ("lb", "live births")):
        sh = float(wm[v]["share"])
        put(f"missing_{v}", sh, f"{100 * sh:.1f}%", f"Share of the panel with {lab} missing (inclusion-weight model only)")
    sel = {r["group"]: r for r in csv.DictReader(open(OUTD / "w_selection.csv", encoding="utf-8"))}
    for g in ("included", "excluded"):
        v = float(sel[g]["lb_median"])
        put(f"lb_median_{g[:4]}", v, f"{v:,.0f}", f"Median live births per unit-month, {g} unit-months")
    put("aic_diff", aic_diff, f"{aic_diff:,.1f}", "AIC of the pooled minus the season-specific model")
    put("n_units_analysed", flow["n_units_analysed"], f"{flow['n_units_analysed']:,}", "Units with an analysed unit-month")

    with open(OUTD / "w_descriptives.csv", "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["key", "display", "value"])
        for k, v in keys.items():
            w.writerow([k, v["display"], json.dumps(v["value"])])

    text = RES.read_text(encoding="utf-8")
    if any(k in json.loads(text) for k in keys):
        cut = text.index('  "F.w.desc.')
        text = text[:cut].rstrip().rstrip(",") + "\n}\n"
    body = text.rstrip()[:-1].rstrip()
    blocks = [json.dumps({k: v}, indent=2, ensure_ascii=False)[2:-2] for k, v in keys.items()]
    out = body + ",\n" + ",\n".join(blocks) + "\n}\n"
    json.loads(out)
    RES.write_text(out, encoding="utf-8", newline="\n")
    for k, v in keys.items():
        print(k, "=", v["display"])


if __name__ == "__main__":
    main()
