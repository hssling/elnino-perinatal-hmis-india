"""Paper F GADM link units and the R3 manual-review guard (Task 3; spec 3.4, rulings R1, R3).

HMIS district names change across financial years as districts split. Each FY's HMIS district list is matched to GADM
districts inside the GADM states of its `state_unit`; the bipartite graph of HMIS district-FYs (FY2012-13..2019-20) and
GADM districts is closed into connected components, the stable "link units" of the panel. FY2020-21 names are mapped
on top of the primary units (sensitivity only, R1).

Match tiers, in order: review (hand-resolved, `hmis_district_review.csv`), exact, normalised, nfhs (Paper B's
district crosswalk, names only), fuzzy, unmatched. A fuzzy match is accepted only when the best within-state
difflib ratio is >= FUZZY_MIN and no other candidate is within FUZZY_MARGIN of it; every accepted fuzzy match goes to
`perinatal_fuzzy_matches.csv` (ratio and runner-up) for review. R3 counts only review-resolved names (`manual`,
`carve_out`) and `unmatched` ones: `manual_share` over distinct primary-FY state x normalised-name combinations.

The review file accepts `fy == "*"` for a name whose resolution is the same in every FY it appears.
Names only: no HMIS value is read or written here.
"""
import difflib
import re
from pathlib import Path

import numpy as np
import pandas as pd

from pipeline.hmis import run
from pipeline.outcomes import states
from pipeline.paths import DERIVED, ROOT

REF = ROOT / "pipeline" / "reference"
REVIEW_PATH = REF / "hmis_district_review.csv"
LINK_UNITS_PATH = REF / "hmis_link_units.csv"
NFHS_XW_PATH = REF / "nfhs_district_crosswalk.csv"
FUZZY_PATH = DERIVED / "hmis" / "perinatal_fuzzy_matches.csv"
REPORT_PATH = DERIVED / "hmis" / "perinatal_units_report.md"
DISTRICT_MONTH = DERIVED / "hmis" / "_parts_f" / "district_month.csv.gz"
CLIMATE_PATH = DERIVED / "climate_district_month.csv.gz"

PRIMARY_FYS = run.PRIMARY_FYS
FY2021 = run.FY2021
FUZZY_MIN = 0.75
FUZZY_MARGIN = 0.05
MAX_MANUAL_SHARE = 0.10
MIN_UNITS = 600
MANUAL_TYPES = ("manual", "carve_out", "unmatched")
REVIEW_COLUMNS = ["state_unit", "fy", "district_raw", "parent_region_ids", "source", "disposition", "note"]
MATCH_COLUMNS = ["state_unit", "fy", "district_raw", "region_id", "match_type", "source"]
UNIT_COLUMNS = ["kind", "state_unit", "fy", "district_raw", "region_id", "link_id"]
DISPOSITIONS = ("assign", "carve_out", "exclude")

# Spelling variants -> the GADM spelling, applied to the whole normalised name (HMIS and GADM sides alike).
SPELLING = {
    "gurgaon": "gurugram",
    "pakaur": "pakur",
}


class ManualReviewHalt(RuntimeError):
    """R3: more than 10% of FY2012-13..2019-20 name combinations needed manual resolution."""


class LinkUnitCountHalt(RuntimeError):
    """Spec 3.4: fewer than 600 link units; report to the author before modelling."""


def normalise_district(name: str) -> str:
    """Lower case, '&' -> 'and', punctuation and the words 'district'/'dist' removed, whitespace collapsed, then the
    SPELLING table (whole name)."""
    s = str(name).lower().replace("&", " and ")
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    s = " ".join(w for w in s.split() if w not in ("district", "dist"))
    return SPELLING.get(s, s)


def _ratio(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, a, b).ratio()


def fuzzy_pick(name: str, cands: dict):
    """(region_id | None, best_ratio, runner_up_region_id, runner_up_ratio) over `cands` ({region_id: normalised name}).
    region_id is None unless best >= FUZZY_MIN and no other candidate is within FUZZY_MARGIN of the best."""
    n = normalise_district(name)
    scored = sorted(((_ratio(n, c), rid) for rid, c in cands.items()), key=lambda t: (-t[0], t[1]))
    if not scored:
        return None, 0.0, None, 0.0
    best, rid = scored[0]
    runner, runner_id = scored[1] if len(scored) > 1 else (0.0, None)
    ok = best >= FUZZY_MIN and (best - runner) > FUZZY_MARGIN + 1e-9
    return (rid if ok else None), best, runner_id, runner


def _split(ids) -> list[str]:
    return [p.strip() for p in str(ids).split("|") if p.strip() and str(ids) != "nan"]


def _review_lookup(review: pd.DataFrame, gadm_ids: set) -> dict:
    """(state_unit, fy-or-'*', district_raw) -> (disposition, [region_id], source). Blank dispositions are ignored."""
    out = {}
    for r in review.fillna("").itertuples():
        if r.disposition == "":
            continue
        if r.disposition not in DISPOSITIONS:
            raise ValueError(f"review row {r.state_unit}/{r.fy}/{r.district_raw}: disposition {r.disposition!r}")
        parents = _split(r.parent_region_ids)
        unknown = [p for p in parents if p not in gadm_ids]
        if unknown:
            raise ValueError(f"review row {r.state_unit}/{r.fy}/{r.district_raw}: unknown region ids {unknown}")
        if r.disposition == "assign" and len(parents) != 1:
            raise ValueError(f"review row {r.state_unit}/{r.fy}/{r.district_raw}: assign needs exactly one parent")
        if r.disposition == "carve_out" and len(parents) < 2:
            raise ValueError(f"review row {r.state_unit}/{r.fy}/{r.district_raw}: carve_out needs two or more parents")
        out[(r.state_unit, r.fy or "*", r.district_raw)] = (r.disposition, parents, r.source)
    return out


def _nfhs_lookup(nfhs_xw: pd.DataFrame) -> dict:
    """normalised NFHS name -> {region_id}: a name that points to one region only is usable."""
    out = {}
    for r in nfhs_xw.dropna(subset=["region_id"]).itertuples():
        out.setdefault(normalise_district(r.nfhs_name), set()).add(r.region_id)
    return out


def match_districts(names, gadm, nfhs_xw, review) -> pd.DataFrame:
    """names: [state_unit, fy, district_raw]; gadm: [region_id, region_name, state_unit]. One row per name and parent
    region (a carve-out lists several); unmatched and excluded names have region_id None."""
    gadm = gadm.assign(_norm=gadm.region_name.map(normalise_district))
    ids = set(gadm.region_id)
    by_state = {u: g for u, g in gadm.groupby("state_unit")}
    nfhs = _nfhs_lookup(nfhs_xw)
    rev = _review_lookup(review, ids)
    cache, rows = {}, []
    for s, fy, d in names[["state_unit", "fy", "district_raw"]].drop_duplicates().itertuples(index=False):
        hit = rev.get((s, fy, d)) or rev.get((s, "*", d))
        if hit:
            disp, parents, src = hit
            if disp == "exclude":
                rows.append((s, fy, d, None, "unmatched", src))
            else:
                rows += [(s, fy, d, p, "manual" if disp == "assign" else "carve_out", src) for p in parents]
            continue
        if (s, d) not in cache:
            cache[(s, d)] = _auto_match(s, d, by_state.get(s), nfhs)
        rid, mt, src = cache[(s, d)]
        rows.append((s, fy, d, rid, mt, src))
    return pd.DataFrame(rows, columns=MATCH_COLUMNS)


def _auto_match(state_unit, name, g, nfhs):
    if g is None or g.empty:
        return None, "unmatched", ""
    raw = str(name).strip()
    hit = g[g.region_name == raw]
    if len(hit) == 1:
        return hit.region_id.iloc[0], "exact", ""
    n = normalise_district(name)
    hit = g[g._norm == n]
    if len(hit) == 1:
        return hit.region_id.iloc[0], "normalised", ""
    inside = set(g.region_id) & nfhs.get(n, set())
    if len(inside) == 1:
        return next(iter(inside)), "nfhs", "pipeline/reference/nfhs_district_crosswalk.csv"
    rid, *_ = fuzzy_pick(name, dict(zip(g.region_id, g._norm)))
    if rid is not None:
        return rid, "fuzzy", ""
    return None, "unmatched", ""


def fuzzy_table(matches: pd.DataFrame, gadm: pd.DataFrame) -> pd.DataFrame:
    """The R3 review table: one row per accepted fuzzy (state_unit, district_raw) with ratio and runner-up."""
    gadm = gadm.assign(_norm=gadm.region_name.map(normalise_district))
    name = dict(zip(gadm.region_id, gadm.region_name))
    rows = []
    f = matches[matches.match_type == "fuzzy"]
    for (s, d), grp in f.groupby(["state_unit", "district_raw"]):
        g = gadm[gadm.state_unit == s]
        rid, best, runner_id, runner = fuzzy_pick(d, dict(zip(g.region_id, g._norm)))
        rows.append(dict(state_unit=s, district_raw=d, fys="|".join(sorted(set(grp.fy))), region_id=grp.region_id.iloc[0],
                         gadm_name=name[grp.region_id.iloc[0]], ratio=round(best, 4), runner_up_region_id=runner_id,
                         runner_up_name=name.get(runner_id), runner_up_ratio=round(runner, 4)))
    return pd.DataFrame(rows, columns=["state_unit", "district_raw", "fys", "region_id", "gadm_name", "ratio",
                                       "runner_up_region_id", "runner_up_name", "runner_up_ratio"])


def _natkey(region_id: str) -> tuple:
    return tuple(int(x) for x in re.findall(r"\d+", str(region_id)))


def link_units(matches: pd.DataFrame) -> pd.DataFrame:
    """Connected components of the FY2012-13..2019-20 HMIS district-FY x GADM graph. `link_id` = "L" + the 1-based
    rank (3 digits) of the component's smallest region_id (numeric order), so ids do not depend on row order."""
    m = matches[matches.fy.isin(PRIMARY_FYS) & matches.region_id.notna() & (matches.match_type != "unmatched")]
    m = m.drop_duplicates(["state_unit", "fy", "district_raw", "region_id"])
    parent = {}

    def find(x):
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for r in m.itertuples():
        a, b = find(("h", r.state_unit, r.fy, r.district_raw)), find(("g", r.region_id))
        if a != b:
            parent[a] = b
    regions = sorted(set(m.region_id), key=_natkey)
    comp_min = {}
    for rid in regions:                                        # ascending: the first region seen is the smallest
        comp_min.setdefault(find(("g", rid)), rid)
    link = {c: f"L{i + 1:03d}" for i, c in enumerate(sorted(comp_min, key=lambda c: _natkey(comp_min[c])))}
    h = m.assign(kind="hmis", link_id=[link[find(("h", r.state_unit, r.fy, r.district_raw))] for r in m.itertuples()])
    first_state = m.drop_duplicates("region_id").set_index("region_id").state_unit
    g = pd.DataFrame({"kind": "gadm", "state_unit": [first_state[r] for r in regions], "fy": "", "district_raw": "",
                      "region_id": regions, "link_id": [link[find(("g", r))] for r in regions]})
    out = pd.concat([h[UNIT_COLUMNS], g], ignore_index=True)
    return out.sort_values(["kind", "link_id", "state_unit", "fy", "district_raw", "region_id"],
                           ignore_index=True)[UNIT_COLUMNS]


def _combos(matches, fys) -> pd.DataFrame:
    m = matches[matches.fy.isin(fys)]
    c = m.assign(_n=m.district_raw.map(normalise_district),
                 _manual=m.match_type.isin(MANUAL_TYPES)).groupby(["state_unit", "_n"])._manual.any()
    return c


def manual_share(matches, fys=PRIMARY_FYS) -> dict:
    """Distinct `fys` state x normalised-name combinations that are manual, carve_out or unmatched (any FY), over all
    such combinations. Fuzzy matches do not count (R3)."""
    c = _combos(matches, fys)
    n_manual, n_total = int(c.sum()), int(len(c))
    return {"n_manual": n_manual, "n_total": n_total, "share": n_manual / n_total if n_total else 0.0}


def check_manual_guard(matches, max_share=MAX_MANUAL_SHARE) -> dict:
    """Raise ManualReviewHalt above `max_share` on the primary FYs; the FY2020-21 manual load is reported, never raised
    (R3)."""
    p = manual_share(matches)
    if p["share"] > max_share:
        raise ManualReviewHalt(f"R3: {p['n_manual']} of {p['n_total']} primary-FY name combinations need manual "
                               f"resolution ({p['share']:.3f} > {max_share:.2f})")
    q = manual_share(matches, (FY2021,))
    return {**p, "n_manual_fy2021": q["n_manual"], "n_total_fy2021": q["n_total"], "share_fy2021": q["share"]}


def check_unit_count(units, min_units=MIN_UNITS) -> int:
    n = int(units.link_id.nunique())
    if n < min_units:
        raise LinkUnitCountHalt(f"{n} link units < {min_units}: report to the author before modelling (spec 3.4)")
    return n


def map_fy2021(matches_fy2021, units) -> pd.DataFrame:
    """FY2020-21 districts onto the primary link units. `mapped`: every parent region sits in one unit;
    `split_across_units`: the parents span several units, or some parent is outside every unit; `unmatched`: no
    parent. One row per district and touched unit."""
    link = dict(zip(units[units.kind == "gadm"].region_id, units[units.kind == "gadm"].link_id))
    m = matches_fy2021[matches_fy2021.fy == FY2021] if "fy" in matches_fy2021 else matches_fy2021
    rows = []
    for (s, d), g in m.groupby(["state_unit", "district_raw"], sort=True):
        regions = [r for r in g.region_id if pd.notna(r)]
        links = sorted({link[r] for r in regions if r in link})
        outside = any(r not in link for r in regions)
        if not links:
            rows.append((s, d, None, "unmatched"))
        elif len(links) == 1 and not outside:
            rows.append((s, d, links[0], "mapped"))
        else:
            rows += [(s, d, lk, "split_across_units") for lk in links]
    return pd.DataFrame(rows, columns=["state_unit", "district_raw", "link_id", "status"])


def fy2021_missing_units(mapped) -> set:
    """Every link unit touched by a split_across_units district (spec 3.4: FY2020-21 months missing, R1)."""
    return set(mapped[mapped.status == "split_across_units"].link_id.dropna())


# ---- data loading and the `units` step ----------------------------------------------------------------------------

def load_gadm(path=CLIMATE_PATH) -> pd.DataFrame:
    """[region_id, region_name, state_unit]: names only, no geometry or climate values."""
    g = pd.read_csv(path, usecols=["region_id", "region_name", "state_id"]).drop_duplicates()
    frame = states.frame()
    unit = {gid: r.unit_id for r in frame.itertuples() for gid in r.gid1_members}
    g["state_unit"] = g.state_id.map(unit)
    if g.state_unit.isna().any():
        raise ValueError(f"GADM states not in state_frame: {sorted(g[g.state_unit.isna()].state_id.unique())}")
    return g[["region_id", "region_name", "state_unit"]].reset_index(drop=True)


def load_names(path=DISTRICT_MONTH) -> pd.DataFrame:
    """Distinct [state_unit, fy, district_raw, state_raw] of the Task 2 district-month parts (chunked read)."""
    from pipeline.hmis import panel
    seen = []
    for chunk in pd.read_csv(path, usecols=["state_raw", "fy", "district_raw"], chunksize=2_000_000, dtype=str):
        seen.append(chunk.drop_duplicates())
    d = pd.concat(seen).drop_duplicates().reset_index(drop=True)
    d["state_unit"] = d.state_raw.map(panel.resolve_hmis_state)
    return d[["state_unit", "fy", "district_raw", "state_raw"]]


def load_review(path=REVIEW_PATH) -> pd.DataFrame:
    if not path.exists():
        return pd.DataFrame(columns=REVIEW_COLUMNS)
    return pd.read_csv(path, dtype=str).fillna("")[REVIEW_COLUMNS]


class UnresolvedNames(RuntimeError):
    """FY2012-13..2019-20 names with no match: the review rows were written (disposition blank) and the step stops."""


def _write_pending(unresolved: pd.DataFrame, review: pd.DataFrame, path=REVIEW_PATH) -> int:
    new = unresolved[["state_unit", "fy", "district_raw"]].drop_duplicates().assign(
        parent_region_ids="", source="", disposition="", note="")[REVIEW_COLUMNS]
    key = set(zip(review.state_unit, review.fy, review.district_raw))
    new = new[[k not in key for k in zip(new.state_unit, new.fy, new.district_raw)]]
    pd.concat([review, new], ignore_index=True).to_csv(path, index=False)
    return len(new)


def per_fy_rates(matches: pd.DataFrame) -> pd.DataFrame:
    """Share of distinct HMIS district names per FY by match_type (a carve-out counts once)."""
    d = matches.drop_duplicates(["state_unit", "fy", "district_raw"])
    t = d.groupby(["fy", "match_type"]).size().unstack(fill_value=0)
    t["n_names"] = t.sum(axis=1)
    for c in [c for c in t.columns if c != "n_names"]:
        t[c + "_share"] = (t[c] / t.n_names).round(4)
    return t


def build_units(names, gadm, nfhs_xw, review, review_path=REVIEW_PATH, max_share=MAX_MANUAL_SHARE) -> dict:
    """Match, then (1) stop with the unresolved primary-FY names, (2) apply the R3 guard, (3) build the units and
    the FY2020-21 mapping. Raises UnresolvedNames, ManualReviewHalt or LinkUnitCountHalt before returning."""
    matches = match_districts(names, gadm, nfhs_xw, review)
    un = matches[matches.fy.isin(PRIMARY_FYS) & (matches.match_type == "unmatched")]
    if len(un):
        n_new = _write_pending(matches[matches.match_type == "unmatched"], review, review_path)
        raise UnresolvedNames(f"{len(un[['state_unit', 'district_raw']].drop_duplicates())} primary-FY names unresolved "
                              f"({n_new} review rows written with blank disposition): "
                              + "; ".join(sorted(set(un.state_unit + ":" + un.district_raw))))
    guard = check_manual_guard(matches, max_share)
    units = link_units(matches)
    n_units = check_unit_count(units)
    mapped = map_fy2021(matches, units)
    return {"matches": matches, "guard": guard, "units": units, "n_units": n_units, "fy2021": mapped,
            "fy2021_missing": fy2021_missing_units(mapped), "fuzzy": fuzzy_table(matches, gadm)}


def link_units_table(matches, units, mapped) -> pd.DataFrame:
    """The tracked reference file: kind, state_unit, fy, district_raw, region_id, link_id, match_type, source. FY2020-21
    rows carry link_id only when mapped (split and unmatched districts stay blank; see map_fy2021)."""
    prim = units[units.kind == "hmis"].merge(matches.drop_duplicates(["state_unit", "fy", "district_raw", "region_id"]),
                                             on=["state_unit", "fy", "district_raw", "region_id"], how="left")
    f21 = matches[matches.fy == FY2021].copy()
    ok = mapped[mapped.status == "mapped"].set_index(["state_unit", "district_raw"]).link_id
    f21["link_id"] = [ok.get((s, d), "") for s, d in zip(f21.state_unit, f21.district_raw)]
    f21["kind"] = "hmis"
    g = units[units.kind == "gadm"].assign(match_type="", source="")
    cols = UNIT_COLUMNS + ["match_type", "source"]
    out = pd.concat([prim[cols], f21[cols], g[cols]], ignore_index=True)
    return out.fillna("").sort_values(["kind", "link_id", "state_unit", "fy", "district_raw", "region_id"],
                                      ignore_index=True)


def write_report(res: dict, gadm: pd.DataFrame, review: pd.DataFrame, path=REPORT_PATH) -> str:
    m, g, units = res["matches"], res["guard"], res["units"]
    rates = per_fy_rates(m)
    cov = set(m[m.fy.isin(PRIMARY_FYS)].region_id.dropna())
    unseen = gadm[~gadm.region_id.isin(cov)]
    st = res["fy2021"].drop_duplicates(["state_unit", "district_raw"]).status.value_counts().to_dict()
    sizes = units[units.kind == "gadm"].groupby("link_id").size()
    nrev = review.disposition.value_counts().to_dict()
    lines = ["# Paper F perinatal HMIS: GADM link units (names only)", "",
             f"Match rule: review, exact, normalised, nfhs, fuzzy (best ratio >= {FUZZY_MIN} and no other candidate within "
             f"{FUZZY_MARGIN}), unmatched; all inside the GADM states of the HMIS state unit.", "",
             "## Match rates per FY (distinct district names)", "", rates.to_markdown(), "",
             "## R3 manual-review guard", "",
             f"- FY2012-13..2019-20 state x normalised-name combinations: manual/carve_out/unmatched {g['n_manual']} of "
             f"{g['n_total']} = {g['share']:.4f} (limit {MAX_MANUAL_SHARE:.2f}); fuzzy matches do not count.",
             f"- FY2020-21 manual load (reported separately, never halts): {g['n_manual_fy2021']} of {g['n_total_fy2021']} "
             f"= {g['share_fy2021']:.4f}.",
             f"- Review rows with a disposition: {sum(v for k, v in nrev.items() if k)} "
             f"(assign {nrev.get('assign', 0)}, carve_out {nrev.get('carve_out', 0)}, exclude {nrev.get('exclude', 0)}).",
             f"- Accepted fuzzy matches (`perinatal_fuzzy_matches.csv`): {len(res['fuzzy'])}.", "",
             "## Link units", "",
             f"- Link units: {res['n_units']} (minimum {MIN_UNITS}); GADM districts in units: {int((units.kind == 'gadm').sum())} "
             f"of {len(gadm)}.",
             f"- Units with more than one GADM district: {int((sizes > 1).sum())}; largest unit: {int(sizes.max())} districts.",
             f"- GADM districts with no FY2012-13..2019-20 HMIS name: {len(unseen)}"
             + (" (" + "; ".join(unseen.state_unit + ":" + unseen.region_name) + ")" if len(unseen) else "") + ".", "",
             "## FY2020-21 mapping (sensitivity only, R1)", "",
             f"- District status counts: {st}; link units touched by a split district (months missing): "
             f"{len(res['fy2021_missing'])}.", ""]
    text = "\n".join(lines)
    Path(path).write_text(text, encoding="utf-8")
    return text


def units_step() -> int:
    gadm, names, nfhs = load_gadm(), load_names(), pd.read_csv(NFHS_XW_PATH)
    review = load_review()
    try:
        res = build_units(names, gadm, nfhs, review)
    except UnresolvedNames as e:
        print(f"STOPPED: {e}")
        return 1
    except (ManualReviewHalt, LinkUnitCountHalt) as e:
        print(f"HALT: {type(e).__name__}: {e}")
        return 2
    res["fuzzy"].to_csv(FUZZY_PATH, index=False)
    link_units_table(res["matches"], res["units"], res["fy2021"]).to_csv(LINK_UNITS_PATH, index=False)
    print(write_report(res, gadm, review))
    return 0
