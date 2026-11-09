"""Paper F synthetic HMIS fixtures (perinatal items). Layout real, numbers invented (as Paper E's F1 fixtures).

    python -I tests/hmis/fixtures/make_fixtures_f.py

Reuses the writers of make_fixtures.py (SAS-HTML table, FY2020-21 month workbook) and its value formula
(SPLIT_BASE + 100*(item index + 1) + 10*unit index + calendar month). Unit names ("Test State", "District A",
"District B") and every number are invented; item codes and texts are the real ones read on 2026-11-08.

Special cells (all other cells follow the formula):
  f_e1  District B 4.1.1.b April..: May "NA" (female missing, male present); June 4.1.1.a and 4.1.1.b both "NA"
  f_e1  District A 4.1.2 April "0" (a real zero stillbirth count)
  f_e1  District B 17.1 April blank (deaths within 24 h: blank is missing, never zero)
"""
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("make_fixtures", HERE / "make_fixtures.py")
mk = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mk)

T = ["TOTAL"]
E1_ITEMS = [
    ("2.1.1.a", "Number of deliveries conducted at Home and attended by trained SBA(i.e. Doctor or Nurse or ANM)", T),
    ("2.1.1.b", "Number of deliveries conducted at Home and attended by non trained SBA (i.e. trained TBA or "
                "Relatives etc.)", T),
    ("2.1.1.c", "Total number of deliveries conducted at Home and attended by trained or non-trained SBA "
                "(i.e. sum of 2.1.1.a and 2.1.1.b)", T),
    ("2.2", "Deliveries conducted at Public Institutions (Including C-Sections)", T),
    ("2.3", "Deliveries conducted at Private Institutions (Including C-Sections)", T),
    ("4.1.1.a", "Number of male live births", T),
    ("4.1.1.b", "Number of female live births", T),
    ("4.1.1.c", "Total number of male and female live births (4.1.1.a and 4.1.1.b)", T),
    ("4.1.2", "Number of still births", T),
    ("4.1.3", "Number of Abortions (spontaneous or induced)", T),
    ("4.2.1", "Number of Newborns weighed at birth", T),
    ("4.2.2", "Number of Newborns having weight less than 2.5 kg", T),
    ("17.1", "Number of cases of Infant deaths within 24 hrs of birth", T),
]
E2_ITEMS = [
    ("2.1.1.a", "Number of Home Deliveries attended by Skill Birth Attendant(SBA) (Doctor/Nurse/ANM)", T),
    ("2.1.1.b", "Number of Home Deliveries attended by Non SBA (Trained Birth Attendant(TBA) /Relatives/etc.)", T),
    ("2.2", "Number of Institutional Deliveries conducted (Including C-Sections)", T),
    ("4.1.1.a", "Live Birth - Male", T),
    ("4.1.1.b", "Live Birth - Female", T),
    ("4.1.2", "Number of Pre term newborns ( < 37 weeks of pregnancy)", T),
    ("4.1.3", "Still Birth", T),
    ("4.2", "Abortion (spontaneous)", T),
    ("4.4.1", "Number of newborns weighed at birth", T),
    ("4.4.2", "Number of newborns having weight less than 2.5 kg", T),
    ("16.1", "Infant deaths within 24 hrs(1 to 23 Hrs) of birth", T),
]
E3_ITEMS = [(c, t.replace("Skill Birth Attendant(SBA) (Doctor/Nurse/ANM)", "Skill Birth Attendant(SBA) "
                                                                         "(Doctor/Nurse/ANM/ Midwife)")
             .replace("( < 37", "(< 37").replace("24 hrs(1 to 23 Hrs)", "24 hours (1 to 23 hours)"), ty)
            for c, t, ty in E2_ITEMS]

mk.SECTION.update({"4": "M4 [Child Health]", "17": "M17 [Mortality]"})
mk.SPECIAL.update({
    ("f_e1", "District B", "4.1.1.b", 5): "NA",
    ("f_e1", "District B", "4.1.1.a", 6): "NA",
    ("f_e1", "District B", "4.1.1.b", 6): "NA",
    ("f_e1", "District A", "4.1.2", 4): "0",
    ("f_e1", "District B", "17.1", 4): "",
})


def write_all(out_dir: Path = HERE) -> list[Path]:
    out_dir = Path(out_dir)
    made = []
    units = ["District A", "District B"]
    p = out_dir / "f_e1_teststate_1213.xls.html"
    p.write_bytes(mk.sas_html("f_e1", "District", "Test State", "2012-2013", "19SEP2015", units, E1_ITEMS,
                              splits=False))
    made.append(p)
    p = out_dir / "f_e2_teststate_1819.xls.html"
    p.write_bytes(mk.sas_html("f_e2", "District", "Test State", "2018-2019", "06 Nov 2020, 2:00 PM", units,
                              E2_ITEMS, splits=True))
    made.append(p)
    p = out_dir / "f_e3_teststate_2021_apr.xlsx"
    mk.e3_xlsx(p, "f_e3", "Data ItemWise Report for Test State", "Apr-2020", "01 Oct 2024,06:05:11",
               ["Test State"] + units, E3_ITEMS)
    made.append(p)
    return made


if __name__ == "__main__":
    for q in write_all(Path(sys.argv[1]) if len(sys.argv) > 1 else HERE):
        print(q)
