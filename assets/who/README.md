# WHO Child Growth Standards: LMS tables

These files hold the L (Box-Cox power), M (median) and S (coefficient of variation) parameters of the
**WHO Child Growth Standards** (WHO Multicentre Growth Reference Study Group, 2006) for children aged 0–5:

| File | Indicator | Indexed by |
| --- | --- | --- |
| `weianthro.txt` | Weight-for-age | sex, age in days (0–1856) |
| `lenanthro.txt` | Length/height-for-age (`loh` = L lying, H standing) | sex, age in days (0–1856) |
| `wflanthro.txt` | Weight-for-length (lying, under 2 years) | sex, length 45–110 cm in 0.1 cm steps |
| `wfhanthro.txt` | Weight-for-height (standing, 2 years and over) | sex, height 65–120 cm in 0.1 cm steps |

`sex`: 1 = male, 2 = female.

Source: the data files of WHO's official `anthro` package,
https://github.com/WorldHealthOrganization/anthro (`data-raw/growthstandards/`), which is licensed
**GPL-3.0**. The files are included unmodified and remain under that licence.

Reference: WHO Multicentre Growth Reference Study Group. *WHO Child Growth Standards:
Length/height-for-age, weight-for-age, weight-for-length, weight-for-height and body mass index-for-age:
Methods and development.* Geneva: World Health Organization, 2006.
