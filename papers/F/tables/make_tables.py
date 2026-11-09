"""Paper F tables 1 and 2 as Markdown (Table 3, the primary estimates and verdicts, is written in the manuscript from keys).

    python -I papers/F/tables/make_tables.py                    (from <repo>; needs papers/F/results.json)

Outputs (out_dir, default papers/F/tables/):
  table1_crosswalk.md   the item crosswalk and definitions: variable, role, HMIS item numbers per format era
                        (pipeline/reference/hmis_perinatal_crosswalk.csv; FY2012-13 to 2016-17 and FY2017-18 onward),
                        definition, and the national April/March 2017 ratios (F.break2017.*, display verbatim).
  table2_panel.md       the panel by financial year, FY2012-13 to FY2019-20 (FY2019-20 = April 2019 to February 2020):
                        panel totals (F.panel.*, F.units.* displays verbatim), national months used and the national
                        rates (F.national.<FY>.*, displays verbatim). Every number traces to a contract key; per-FY
                        counts, which no key holds, are not shown. No stillbirth, LBW or birth count by month or state.
  data/table2.csv       the FY rows as numbers, from the F.national.* keys only.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import pandas as pd

TABLES = Path(__file__).resolve().parent
PAPER = TABLES.parent
ROOT = TABLES.parents[2]
RESULTS = PAPER / "results.json"
CROSSWALK = ROOT / "pipeline" / "reference" / "hmis_perinatal_crosswalk.csv"
FYS = ["2012-13", "2013-14", "2014-15", "2015-16", "2016-17", "2017-18", "2018-19", "2019-20"]
NOTE = "FY2020-21 was analysed as a sensitivity analysis"
RATES = ["sbr", "lbw_share", "wt_cov", "inst_share", "tb_per_delivery"]

LABEL = {"lb": "Live births", "lb_m": "Male live births", "lb_f": "Female live births",
         "lb_c": "Live births, printed total (check)", "sb": "Stillbirths", "wt": "Newborns weighed at birth",
         "lbw": "Newborns weighing less than 2.5 kg", "home": "Home deliveries",
         "home_c": "Home deliveries, printed total (check)",
         "inst": "Institutional deliveries", "preterm": "Preterm newborns (< 37 weeks)",
         "d24": "Infant deaths within 24 hours"}
ROLE = {"lb": "Denominator of total births", "lb_m": "Component of live births", "lb_f": "Component of live births",
        "lb_c": "Completeness check only", "sb": "Outcome H10; numerator of the stillbirth rate",
        "wt": "Denominator of the LBW share; weighing coverage", "lbw": "Outcome H11; numerator of the LBW share",
        "home": "Institutional share", "home_c": "Completeness check only", "inst": "Institutional share",
        "preterm": "Secondary outcome, no verdict (FY2017-18 onward)",
        "d24": "State and national description only (not modelled)"}
ORDER = list(LABEL)


def load_results(path: Path = RESULTS) -> dict:
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"{path} not found: run models/F/run_all.R first")
    return json.loads(path.read_text(encoding="utf-8"))


def disp(res: dict, key: str) -> str:
    if key not in res:
        raise KeyError(f"results.json has no key {key}")
    return str(res[key]["display"])


def items_text(codes: str) -> str:
    return " + ".join(str(codes).split("|"))


def fy_key(fy: str) -> str:
    return "fy" + fy[2:4] + fy[5:7]


def _clean(t: str) -> str:
    return str(t).replace("|", "/").replace("\n", " ")


def table1(res: dict, crosswalk: Path = CROSSWALK) -> str:
    cw = pd.read_csv(crosswalk, dtype=str)
    cw = cw[cw["era"].isin(["E1", "E2", "E3"])]
    lines = ["# Table 1. Item crosswalk and definitions", "",
             "| Variable | Role | HMIS items, FY2012-13 to 2016-17 | HMIS items, FY2017-18 onward | Definition |",
             "|---|---|---|---|---|"]
    for ind in ORDER:
        g = cw[cw["indicator"] == ind].set_index("era")
        if "E3" in g.index and "E2" in g.index and g.loc["E3", "item_codes"] != g.loc["E2", "item_codes"]:
            raise ValueError(f"{ind}: items differ between the FY2017-18 format and the later format")
        e1 = items_text(g.loc["E1", "item_codes"]) if "E1" in g.index else "not collected"
        e2 = items_text(g.loc["E2", "item_codes"]) if "E2" in g.index else "not collected"
        notes = [g.loc[e, "definition_note"] for e in ("E1", "E2") if e in g.index]
        notes = [n for n in notes if not str(n).startswith("As E")]
        defn = " ".join(dict.fromkeys(_clean(n) for n in notes))
        lines.append(f"| {LABEL[ind]} | {ROLE[ind]} | {e1} | {e2} | {defn} |")
    lines += ["",
              "Items are the HMIS data-item numbers of the monthly state reports; \"+\" means the items are added. "
              "Each item is matched by its text in every financial year, so that item 4.1.2 (stillbirths before "
              "April 2017, preterm newborns from April 2017) is never read as the other. Deaths within 24 hours are "
              "reported by state only and are not modelled.", "",
              "National ratio of the April 2017 rate to the March 2017 rate (descriptive; no ratio is beyond 15%): "
              f"stillbirth rate {disp(res, 'F.break2017.sbr.ratio')}, low birth weight share "
              f"{disp(res, 'F.break2017.lbw_share.ratio')}, weighing coverage {disp(res, 'F.break2017.wt_cov.ratio')}. "
              "The 2017 format change enters Model T as a step; Model L has year-month fixed effects.", "",
              f"{NOTE} and contributes no descriptive value here.", ""]
    return "\n".join(lines)


def national_months(res: dict, fy: str) -> tuple[int, str, str]:
    """(months used, 'first to last' span, months without or '') read from the key description."""
    d = res[f"F.national.sbr.{fy_key(fy)}"]["description"]
    m = re.search(r"(\d+) of (\d+) national months \(([^)]*)\)(?:; months without: ([^;]*?);)?", d)
    if not m:
        raise ValueError(f"cannot read the national months of {fy} from its key description")
    return int(m.group(1)), m.group(3), m.group(4) or ""


def table2_data(res: dict) -> pd.DataFrame:
    """One row per FY: national months used and the national rates, all from F.national.* keys."""
    rows = []
    for fy in FYS:
        r = {"fy": fy, "n_national_months": national_months(res, fy)[0]}
        for k in RATES:
            r[k] = float(res[f"F.national.{k}.{fy_key(fy)}"]["value"])
        rows.append(r)
    return pd.DataFrame(rows)


def table2(res: dict, d: pd.DataFrame) -> str:
    lines = ["# Table 2. Panel by financial year, FY2012-13 to FY2019-20", "",
             f"Link units: {disp(res, 'F.units.n_link')} (HMIS district names, FY2012-13 to 2019-20: "
             f"{disp(res, 'F.units.n_hmis_names')}). State units: {disp(res, 'F.panel.n_states')}. Link-unit-months in the "
             f"primary window: {disp(res, 'F.panel.n_unit_months')} ({disp(res, 'F.panel.n_months')} months, April 2012 to "
             f"February 2020). Link-unit-months entering the models: {disp(res, 'F.panel.sb.n_valid')} for stillbirths and "
             f"{disp(res, 'F.panel.lbw.n_valid')} for low birth weight; masked share of reported values "
             f"{disp(res, 'F.panel.sb.share_masked')} and {disp(res, 'F.panel.lbw.share_masked')}; link units excluded "
             f"{disp(res, 'F.panel.sb.n_units_excluded')} and {disp(res, 'F.panel.lbw.n_units_excluded')}. "
             f"HMIS status dates (all values provisional): {disp(res, 'F.status_date.min')} to "
             f"{disp(res, 'F.status_date.max')}.", "",
             "| Financial year | National months used (stillbirth rate)<sup>a</sup> | Stillbirths per 1,000 total births | "
             "LBW share of newborns weighed | Weighing coverage | Institutional share | Total births per delivery |",
             "|---|---|---|---|---|---|---|"]
    for r in d.itertuples():
        k = fy_key(r.fy)
        mark = "<sup>b</sup>" if r.fy == "2019-20" else ""
        lines.append(f"| FY{r.fy}{mark} | {r.n_national_months} | "
                     + " | ".join(disp(res, f"F.national.{x}.{k}") for x in RATES) + " |")
    n17, span17, lost17 = national_months(res, "2017-18")
    n19, span19, _ = national_months(res, "2019-20")
    lines += ["",
              "<sup>a</sup> National rates are ratios of sums over the national months in which every count of the rate is "
              "present, from the official All_India series net of the M/O rows. "
              f"FY2017-18 national data cover {n17} months ({span17}); no national count for {lost17}.  ",
              f"<sup>b</sup> FY2019-20 covers {span19} ({n19} months); March 2020 is outside the primary window. "
              f"{NOTE} and contributes no descriptive value here.", ""]
    return "\n".join(lines)


def main(out_dir: Path = TABLES, results: Path = RESULTS) -> list[Path]:
    res = load_results(results)
    out_dir = Path(out_dir)
    (out_dir / "data").mkdir(parents=True, exist_ok=True)
    d = table2_data(res)
    paths = [out_dir / "data" / "table2.csv", out_dir / "table1_crosswalk.md", out_dir / "table2_panel.md"]
    d.to_csv(paths[0], index=False, lineterminator="\n", float_format="%.15g")
    paths[1].write_text(table1(res), encoding="utf-8", newline="\n")
    paths[2].write_text(table2(res, d), encoding="utf-8", newline="\n")
    for p in paths:
        print("wrote", p)
    return paths


if __name__ == "__main__":
    main()
