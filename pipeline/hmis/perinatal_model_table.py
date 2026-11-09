"""Paper F model table (Task 6; spec 3.4, 3.6, 4, 5.1, rulings R1, R5).

One row per link unit x birth month, April 2012 to March 2021 (108 months; `in_primary` marks April 2012 to February 2020,
95 months). Columns, in order:
- the panel (perinatal_panel.panel_columns_f());
- in_primary, moy, t_months (0 at April 2012), t_c = (t_months - 47) / 12, era_e2 (ym >= April 2017), state_ym
  (`state_unit:ym`);
- the programme and period indicators hmis_format2017, demonet, pmsma, laqshya, covid_mar2020, covid_fy2021 (from
  model_table.programme_indicators over pipeline/reference/hmis_programme_events.csv) and covid_lockdown (April to June
  2020; plan decision: not in Paper E's events file, so computed here);
- offsets log_tb, log_wt, log_lb, log_lb_f (log of the primary value; a zero or missing count is NaN, never -inf) and
  log_days (log of the days in the month);
- inst_share = inst / (inst + home) and wt_cov = wt / lb (NaN where the denominator is 0 or missing);
- unit descriptors: small_unit (LD, AN, DNH_DD, CH, PY, or median primary-window tb < 100), single_district (exactly one
  GADM district and one HMIS district in every primary FY), inst090_all_fy (inst_share >= 0.90 in every primary FY, from
  FY sums of inst and home over the months where both are reported);
- excluded_<v> (Task 4 unit exclusions, perinatal_panel.excluded_units; excluded_tb is the union of lb and sb) and
  small_denom_<out> (denominator < 20: sb on tb, lbw on wt, preterm on lb);
- the gestational exposures (perinatal_exposure.gestation_terms).

The table holds the panel's outcomes and the exposures side by side; nothing here relates one to the other.
Git-ignored (holds FY2020-21 values).
"""
from pathlib import Path

import numpy as np
import pandas as pd

from pipeline.hmis import exposure
from pipeline.hmis import perinatal_climate as pcl
from pipeline.hmis import perinatal_exposure as pex
from pipeline.hmis import perinatal_panel as pf
from pipeline.hmis import perinatal_units as pu
from pipeline.hmis.model_table import (EVENTS_PATH, ENSO_PATH, programme_indicators, read_events)
from pipeline.hmis.perinatal_crosswalk import PANEL_VARS
from pipeline.hmis.perinatal_panel import excluded_units
from pipeline.paths import DERIVED

HMIS_DIR = DERIVED / "hmis"
MODEL_PATH = HMIS_DIR / "perinatal_model.csv.gz"
T_CENTRE = 47
SMALL_UTS = ("LD", "AN", "DNH_DD", "CH", "PY")
SMALL_TB_MEDIAN = 100
SMALL_DENOM = 20
INST_MIN = 0.90
PROGRAMME_COLUMNS = ("hmis_format2017", "demonet", "pmsma", "laqshya", "covid_mar2020", "covid_fy2021")
LOCKDOWN = (exposure.ym_of(2020, 4), exposure.ym_of(2020, 6))
EXCLUDE_VARS = tuple(PANEL_VARS)
SMALL_DENOM_OF = {"sb": "tb", "lbw": "wt", "preterm": "lb"}


def _log_pos(x: pd.Series) -> pd.Series:
    return np.log(x.where(x > 0))


def unit_descriptors(panel: pd.DataFrame, units: pd.DataFrame) -> pd.DataFrame:
    """link_id, small_unit, single_district, inst090_all_fy."""
    prim = panel[panel.ym.between(exposure.PRIMARY_START, exposure.PRIMARY_END)]
    link = panel.drop_duplicates("link_id")[["link_id", "state_unit"]].set_index("link_id")
    med = prim.groupby("link_id").tb.median()                      # NaN ignored; all-NaN -> NaN
    link["small_unit"] = (link.state_unit.isin(SMALL_UTS) | (med.reindex(link.index) < SMALL_TB_MEDIAN)).astype(int)

    n_gadm = units[units.kind == "gadm"].groupby("link_id").region_id.nunique()
    h = units[(units.kind == "hmis") & units.link_id.notna() & (units.link_id.astype(str) != "")
              & units.fy.isin(pf.PRIMARY_FYS)]
    n_h = h.groupby(["link_id", "fy"]).district_raw.nunique().unstack("fy").reindex(columns=list(pf.PRIMARY_FYS))
    one = n_h.eq(1).all(axis=1)
    link["single_district"] = (n_gadm.reindex(link.index).eq(1) & one.reindex(link.index).fillna(False)).astype(int)

    both = prim[prim.inst.notna() & prim.home.notna() & prim.fy.isin(pf.PRIMARY_FYS)]
    s = both.groupby(["link_id", "fy"])[["inst", "home"]].sum()
    s["share"] = s.inst / (s.inst + s.home).where((s.inst + s.home) > 0)
    sh = s.share.unstack("fy").reindex(index=link.index, columns=list(pf.PRIMARY_FYS))
    link["inst090_all_fy"] = (sh >= INST_MIN).all(axis=1).astype(int)
    return link.drop(columns="state_unit").reset_index()


def assemble_model(panel: pd.DataFrame, clim: pd.DataFrame, enso: pd.DataFrame, units: pd.DataFrame,
                   events: pd.DataFrame) -> pd.DataFrame:
    cols = pf.panel_columns_f()
    if list(panel.columns) != cols:
        raise ValueError("panel columns differ from perinatal_panel.panel_columns_f()")
    if panel.duplicated(["link_id", "ym"]).any():
        raise ValueError("duplicate link-unit-months in the panel")
    m = panel[panel.ym.between(exposure.PRIMARY_START, exposure.FY2021_END)].copy()
    m = m.sort_values(["link_id", "ym"], ignore_index=True)
    yms = np.arange(exposure.PRIMARY_START, exposure.FY2021_END + 1)

    m["in_primary"] = m.ym.between(exposure.PRIMARY_START, exposure.PRIMARY_END).astype(int)
    m["moy"] = m.month.astype(int)
    m["t_months"] = m.ym - exposure.PRIMARY_START
    m["t_c"] = (m.t_months - T_CENTRE) / 12
    m["era_e2"] = (m.ym >= exposure.ym_of(2017, 4)).astype(int)
    m["state_ym"] = m.state_unit.astype(str) + ":" + m.ym.astype(str)

    prog = programme_indicators(yms, events)[["ym", *PROGRAMME_COLUMNS]]
    prog["covid_lockdown"] = prog.ym.between(*LOCKDOWN).astype(int)
    m = m.merge(prog, on="ym", how="left", validate="many_to_one")

    for v in ("tb", "wt", "lb", "lb_f"):
        m[f"log_{v}"] = _log_pos(m[v])
    m["log_days"] = np.log(pd.PeriodIndex.from_fields(year=m.year, month=m.month, freq="M").days_in_month)
    m["inst_share"] = m.inst / (m.inst + m.home).where((m.inst + m.home) > 0)
    m["wt_cov"] = m.wt / m.lb.where(m.lb > 0)

    m = m.merge(unit_descriptors(panel, units), on="link_id", how="left", validate="many_to_one")
    ex = {v: set(excluded_units(panel, v)) for v in EXCLUDE_VARS}
    ex["tb"] = ex["lb"] | ex["sb"]
    for v, s in ex.items():
        m[f"excluded_{v}"] = m.link_id.isin(s).astype(int)
    for out, den in SMALL_DENOM_OF.items():
        m[f"small_denom_{out}"] = (m[den] < SMALL_DENOM).astype(int)       # NaN < 20 is False: the outcome is NaN too

    g = pex.gestation_terms(clim, enso, yms)
    m = m.merge(g, on=["link_id", "ym"], how="left", validate="one_to_one")
    return m


OUTCOME_COLUMNS = ("lb", "sb", "tb", "wt", "lbw", "home", "inst", "preterm")


def exposure_columns(m: pd.DataFrame) -> list[str]:
    """The gestational terms: every column from tmax_t3 on (the merge is last)."""
    return list(m.columns[m.columns.get_loc("tmax_t3"):])


def describe(m: pd.DataFrame) -> list[pd.DataFrame]:
    """Descriptive tables over the primary window: [NaN share of each outcome and exposure; SD of each exposure across
    link-unit-months and within year-month (SD of the deviation from the month's mean over link units)]. No outcome
    is related to any exposure."""
    p = m[m.in_primary == 1]
    exp = exposure_columns(m)
    cols = [c for c in OUTCOME_COLUMNS if c in p] + exp
    nan = pd.DataFrame({"n": len(p), "nan": p[cols].isna().sum(), "nan_share": p[cols].isna().mean()})
    sd = pd.DataFrame({"sd_overall": p[exp].std(),
                       "sd_within_ym": (p[exp] - p.groupby("ym")[exp].transform("mean")).std()})
    return [nan, sd]


def build_perinatal_model(out=MODEL_PATH, panel_path=pf.PANEL_PATH,
                          climate_path=pcl.OUT_PATH, enso_path=ENSO_PATH,
                          units_path=pu.LINK_UNITS_PATH, events_path=EVENTS_PATH) -> Path:
    panel = pd.read_csv(panel_path, dtype={"fy": str})
    clim = pd.read_csv(climate_path)
    units = pd.read_csv(units_path, dtype=str, keep_default_na=False)
    m = assemble_model(panel, clim, pd.read_csv(enso_path), units, read_events(events_path))
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    m.to_csv(out, index=False)
    return out
