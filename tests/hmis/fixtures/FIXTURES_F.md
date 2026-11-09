# Paper F perinatal fixtures (Task 1)

**All fixtures are SYNTHETIC (as Paper E's F1 ruling).** Each copies the *layout* of a real cached portal file:
title lines, header rows, row and column spans, item codes and item texts of the perinatal rows. The unit names
("Test State", "District A", "District B") and every number are invented; nothing was cut from a downloaded file and
no real value appears. They are written by `make_fixtures_f.py` (`python -I tests/hmis/fixtures/make_fixtures_f.py`),
which reuses the writers and value formula of Paper E's `make_fixtures.py`; its docstring lists the special cells.
The SAS-HTML fixtures are stored as `*.xls.html` (as Paper E's: the controlled-data guard treats `.xls` as unscanned
binary); tests pass a member name ending in `.xls` to `parse_member`/`read_table`.

The item codes and texts below were read in place with `python -I` on 2026-11-08 from the `A & N Islands.xls` member
of FY2012-13, 2014-15, 2017-18 and 2019-20 and from the FY2020-21 A and N Islands April workbook (header rows and the
item rows of sections 2, 4, 16 and 17 only). The SHA-256 is the MANIFEST row of the real file whose layout the
fixture mirrors (the zip, for members).

| Fixture | Layout mirrored (repo path :: member) | MANIFEST SHA-256 | Rows kept |
|---|---|---|---|
| `f_e1_teststate_1213.xls.html` | `data/raw/hmis/hmis_c2_3_states_months/2012-2013.zip` :: `2012-2013/A & N Islands.xls` | `88575e9bbbc2af6a8a6845f0ee8879ce3ab712848100e3e22db0107269c38ba3` | E1 SAS HTML (1 column per month + Total, "District" label row), 2 districts x 13 items: 2.1.1.a/b/c, 2.2, 2.3, 4.1.1.a/b/c, 4.1.2 "Number of still births", 4.1.3 "Number of Abortions (spontaneous or induced)", 4.2.1, 4.2.2, 17.1 "Number of cases of Infant deaths within 24 hrs of birth". Special cells: District B 4.1.1.b May "NA"; District B 4.1.1.a and 4.1.1.b June "NA"; District A 4.1.2 April "0"; District B 17.1 April blank |
| `f_e2_teststate_1819.xls.html` | `data/raw/hmis/hmis_c2_3_states_months/2018-2019.zip` :: `2018-2019/A & N Islands.xls` | `5fc13094bbe8fcec29e18ec1294d70fbc0bed8801dc6cad63a0c7eace99ce8f3` | E2 SAS HTML (5 splits per month, Total kept; same layout as FY2017-18 and FY2019-20), 2 districts x 11 items: 2.1.1.a/b, 2.2, 4.1.1.a "Live Birth - Male", 4.1.1.b "Live Birth - Female", 4.1.2 "Number of Pre term newborns ( < 37 weeks of pregnancy)", 4.1.3 "Still Birth", 4.2 "Abortion (spontaneous)", 4.4.1, 4.4.2, 16.1 "Infant deaths within 24 hrs(1 to 23 Hrs) of birth" |
| `f_e3_teststate_2021_apr.xlsx` | `data/raw/hmis/hmis_c2_2_states_districts_fy2021/Andaman_Nicobar_Islands__A-Andaman_Nicobar_Islands_Apr.xlsx` | `a87fbf8beb5b73f59d33d1783255c7c04ddedccdd1e53c8be68fa6a4d9844cf4` (also in `data/MANIFEST.csv`) | FY2020-21 month workbook, groups "Test State" (state aggregate), "District A", "District B" x 5 splits; the 11 E2 items with FY2020-21 wording: 16.1 reads "within 24 hours (1 to 23 hours)", 4.1.2 "(< 37 weeks", 2.1.1.a "(Doctor/Nurse/ANM/ Midwife)"; codes written `'4.1.3` |

## Codes and texts confirmed per era (real files, 2026-11-08)

| Variable | FY2012-13 and 2014-15 (E1) | FY2017-18 and 2019-20 (E2) | FY2020-21 (E3) |
|---|---|---|---|
| lb | 4.1.1.a "Number of male live births" + 4.1.1.b "Number of female live births" (4.1.1.c "Total number of male and female live births (4.1.1.a and 4.1.1.b)") | 4.1.1.a "Live Birth - Male" + 4.1.1.b "Live Birth - Female" (no 4.1.1.c) | as E2 |
| sb | **4.1.2** "Number of still births" (4.1.3 is "Number of Abortions (spontaneous or induced)") | **4.1.3** "Still Birth" (4.1.2 is "Number of Pre term newborns ( < 37 weeks of pregnancy)") | as E2 (4.1.2 "(< 37 weeks of pregnancy)") |
| wt, lbw | 4.2.1, 4.2.2 | 4.4.1, 4.4.2 | as E2 |
| home | 2.1.1.a, 2.1.1.b (+ 2.1.1.c total) | 2.1.1.a, 2.1.1.b | as E2 |
| inst | 2.2 "Deliveries conducted at Public Institutions (Including C-Sections)" + 2.3 "... Private Institutions ..." | 2.2 "Number of Institutional Deliveries conducted (Including C-Sections)" | as E2 |
| preterm | not collected | 4.1.2 | 4.1.2 |
| d24 | 17.1 "Number of cases of Infant deaths within 24 hrs of birth" | 16.1 "Infant deaths within 24 hrs(1 to 23 Hrs) of birth" | 16.1 "... within 24 hours (1 to 23 hours) ..." (no crosswalk row, R4) |

The E2 text of 4.1.2 differs in spacing between `( < 37` (FY2017-18 to 2019-20) and `(< 37` (FY2020-21); the
crosswalk pattern allows both.
