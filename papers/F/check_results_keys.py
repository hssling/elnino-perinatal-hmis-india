"""Check papers/F/results.json against the contract papers/F/results_keys.md and the manuscript files.

    python papers/F/check_results_keys.py                  # exit 1 on any failure below
    python papers/F/check_results_keys.py --build          # also fill and trace the manuscript files with
                                                           # tools.build_manuscript.build(names=F_NAMES)
    --results PATH                                         # another results file (default papers/F/results.json)

Contract keys are the backticked `F.*` names in the first cell of the table rows that start with "| `F.", with
shell-style brace expansion only (`{a,b}`; consecutive groups expand as a product; no nesting). Adapted from
papers/E/check_results_keys.py (prefix F; no pending mode: Paper F's run_all.R never writes pending keys).
Fails (exit 1) when:
- the results.json key set differs from the contract;
- a placeholder {{F.*}} in a manuscript file (F_NAMES: manuscript, supplement, title page, cover letter) is not in
  the contract;
- a display is empty;
- the contract's declared total "(N keys)" or a section's "(N keys)" differs from the keys it lists;
- a key naming FY2020-21 is not one of the sensitivity estimates F.sens.<O>.fy2021.{heat,dry,en} (R2: no key carries a
  FY2020-21 descriptive value).
Manuscript files that do not exist yet are reported as missing, not failed (the manuscript is written in Task 14);
contract keys not used by the manuscript files are reported, not failed.
"""
import itertools
import json
import re
import sys
from pathlib import Path

PAPER = Path(__file__).resolve().parent
REPO = PAPER.parents[1]
# The manuscript files are named explicitly, the supplement included, so that its keys are filled and traced.
F_NAMES = ("manuscript", "supplement", "title_page", "cover_letter")
SECTION_RE = re.compile(r"^## (\d+)\. .*\((\d[\d,]*) keys?\)\s*$")
FY2021_KEY_RE = re.compile(r"fy2021|2020_21", re.IGNORECASE)
FY2021_ALLOWED_RE = re.compile(r"^F\.sens\.(sb|lbw)\.fy2021\.(heat|dry|en)$")


def expand(key: str) -> list[str]:
    parts = re.split(r"(\{[^{}]*\})", key)
    opts = [p[1:-1].split(",") if p.startswith("{") else [p] for p in parts]
    return ["".join(c) for c in itertools.product(*opts)]


def _row_keys(lines) -> list[str]:
    keys = []
    for line in lines:
        if not line.startswith("| `F."):
            continue
        cell = line.split("|")[1]
        for k in re.findall(r"`(F\.[^`]+)`", cell):
            keys += [x for x in expand(k) if x not in keys]
    return keys


def contract_keys(md: str) -> set[str]:
    return set(_row_keys(md.splitlines()))


def declared_total(md: str) -> int:
    intro = next(ln for ln in md.splitlines() if ln.startswith("This contract lists"))
    return int(re.search(r"\((\d[\d,]*) keys\)", intro).group(1).replace(",", ""))


def section_counts(md: str) -> list[tuple[str, int, int]]:
    """(section number, declared, found) for every numbered section with a "(N keys)" heading."""
    lines = md.splitlines()
    out = []
    for i, line in enumerate(lines):
        m = SECTION_RE.match(line)
        if not m:
            continue
        j = next((k for k in range(i + 1, len(lines)) if lines[k].startswith("## ")), len(lines))
        out.append((m.group(1), int(m.group(2).replace(",", "")), len(_row_keys(lines[i + 1:j]))))
    return out


def placeholders(paper: Path, names=F_NAMES) -> tuple[set[str], list[str]]:
    """(placeholders used by the manuscript files that exist, names of the files that do not exist)."""
    used, missing = set(), []
    for n in names:
        f = paper / f"{n}.md"
        if f.exists():
            used |= set(re.findall(r"\{\{(F\.[A-Za-z0-9_.]+)\}\}", f.read_text(encoding="utf-8")))
        else:
            missing.append(f"{n}.md")
    return used, missing


def fy2021_violations(res: dict) -> list[str]:
    """Keys naming FY2020-21 that are not one of the sensitivity estimates F.sens.<O>.fy2021.{heat,dry,en} (R2)."""
    bad = []
    for k, v in res.items():
        if FY2021_KEY_RE.search(k) and not FY2021_ALLOWED_RE.match(k):
            bad.append(k)
    return sorted(bad)


def main(argv=None, paper: Path = PAPER) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    build = "--build" in argv
    results_path = Path(argv[argv.index("--results") + 1]) if "--results" in argv else paper / "results.json"
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    md = (paper / "results_keys.md").read_text(encoding="utf-8")
    contract = contract_keys(md)
    declared = declared_total(md)
    res = json.loads(results_path.read_text(encoding="utf-8"))
    used, missing_files = placeholders(paper)
    errors = []
    if len(contract) != declared:
        errors.append(f"contract lists {len(contract)} keys but declares {declared}")
    secs = section_counts(md)
    for sec, dec, found in secs:
        if dec != found:
            errors.append(f"section {sec} declares {dec} keys but lists {found}")
    if sum(f for _, _, f in secs) != len(contract):
        errors.append(f"sections list {sum(f for _, _, f in secs)} keys, the contract {len(contract)}")
    if set(res) - contract:
        errors.append(f"results.json keys not in contract: {sorted(set(res) - contract)}")
    if contract - set(res):
        errors.append(f"contract keys missing from results.json: {sorted(contract - set(res))}")
    if used - contract:
        errors.append(f"manuscript placeholders not in contract: {sorted(used - contract)}")
    for k, v in sorted(res.items()):
        if not isinstance(v.get("display"), str) or not v["display"].strip():
            errors.append(f"{k}: empty display")
    if fy2021_violations(res):
        errors.append(f"keys with a FY2020-21 descriptive value (R2): {fy2021_violations(res)}")
    print(f"contract {len(contract)} keys (declared {declared}; {len(secs)} sections); results.json {len(res)}; "
          f"manuscript files {', '.join(F_NAMES)} use {len(used)} ({len(contract - used)} contract keys not used yet)")
    print(f"checked {results_path.name}")
    if missing_files:
        print(f"manuscript files missing (written in Task 14): {', '.join(missing_files)}")
    for e in errors:
        print("FAIL:", e)
    if errors:
        return 1
    print(f"OK: {results_path.name} matches the contract key set exactly")
    if build:
        if str(REPO) not in sys.path:
            sys.path.insert(0, str(REPO))
        from tools import build_manuscript as bm
        for p in bm.build(paper, results_path=results_path, names=F_NAMES):
            print("wrote", p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
