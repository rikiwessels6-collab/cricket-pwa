# Source files: notes for the importer

Put these seven .xlsx files in `Resources/Source/`. Never edit them; parse them into bundled JSON. All except the Beginner program are my RW Fitness files, copied byte for byte from my originals. The Full Body file is the completed version (the original was an empty template).

| File | What it is |
| --- | --- |
| RWFitness_Full_Body_8_Week_Program_3days_COMPLETED.xlsx | 8 weeks, 3 full body sessions a week, 7 exercises each. Completed by Claude. |
| RwFitness_Upper_Lower_8_Week_Program_4days.xlsx | 8 weeks, 4 sessions a week. |
| RWfitness_Body_Part_Split_8_Week_Program_5days.xlsx | 8 weeks, 5 sessions a week. |
| Copy_of_Riki_of_RWFitness_12_Weeks.xlsx | 12 weeks, alternating full body and legs/push/pull weeks, with %1RM. |
| Intermediate_18_weeks.xlsx | 18 weeks over two sheets, RIR based, with supersets. |
| Copy_of_New_Done_For_You_Client_Check-In_System_MASTER_COPY.xlsx | Check-in system: configuration defaults, macro timing, measurements, photo timeline. |
| Beginner_12_Week_Strength_Program.xlsx | 12 weeks, options A to D, for new lifters. |

## Layout shared by the program files
Week header row: column B `Week N`, then C Workout, D Exercise, E Working Sets, F Reps / Duration, G Load (kg), H RPE (or RIR in the 18-week file), I Rest, J Notes. The workout name sits in column C on the first exercise row of each session only, so carry it down until the next name. Unit cell is D5/D7 (`kg`). Header G is a formula, so read the file with cached values (these files have been recalculated) or treat the header by position.

## Quirks, file by file

**Full Body COMPLETED (new).** Two 4-week blocks. Weeks 1-4 use one set of exercises, weeks 5-8 use variations. Within a block: week 1 and 2 are 3 sets, week 3 gives the first lift of each session a 4th set (RPE up to 8-9), and weeks 4 and 8 are easy weeks (2 sets, RPE 6, same weights as the week before). The Load column is blank on purpose. Rep fields are text. Sessions run about 60-70 minutes including warm-up and cool-down, so show the app's trim offer.

**Upper/Lower.** Weeks 1-4 repeat the same prescription (progress by load only). Weeks 5-8 are a second block. Weeks 6 and 7 label the sessions `Full Body #1`, `Full Body #2` and `Full Body #3` twice (14 rows, which is two sessions); they are the same four sessions as week 5. Week 8 uses `Full Body #1`, `Full Body #2`, `Lower Body #2`, `Upper Body #2`. Week 3 writes `UpperBody #1` with no space. Do not trust session names: treat each block of 7 exercise rows after a name in column C as one session, four sessions a week, and flag the inconsistency for me.

**Body Part Split.** Weeks 1-8, five sessions a week: Chest & Triceps, Legs & Abs, Back & Biceps, Legs & Abs (second), Shoulders & Arms. Two sessions share the name `Legs & Abs`, so key sessions by position, not name.

**12-week.** 1RM inputs are in E13:H13 (Squat 120, Bench 90, Deadlift 135, OHP 45) and belong to someone else, so never use them as defaults. Excel turned many rep ranges into dates (for example 2021-04-06 is `4-6`, 2021-12-15 is `12-15`, 2021-08-10 is `8-10`, 2021-10-12 is `10-12`, 2021-06-08 is `6-8`); convert month-day back to `m-d` and list every conversion for me to confirm. Column K (`W/S Load`) contains junk such as 743 and dates; ignore it. Week 9 has no header: the legs/push/pull block under `Week 8 - semi deload` (header row 274) is followed by a `FULL BODY 1:` block at row 318, which is week 9. Weeks alternate: odd weeks full body, even weeks legs/push/pull. A banner at row 273 (`SEMI-DELOAD WEEK...`) sits between week 7 and week 8, so which week is the semi-deload is ambiguous; flag it for me. `A1:`/`A2:`/`B1:`/`B2:` prefixes mean superset or circuit pairs. Warm-up sets apply to primary lifts only (pyramid: bar x 15, ~40%, ~60%, 70-75%).

**18-week.** Two sheets: `Weeks 1 - 9` and `Weeks 10 -18`. Uses RIR (column I) and a `Weight` column (H). Column E holds `SUPERSET 1/2/3` labels and sometimes `10+ FOR LAST SET`. Reps can be text like `11,9,7` or `11,9,7,5`. Session names vary slightly (`LEGS &ABS`); the five sessions each week are PUSH, PULL, LEGS & ABS, UPPER, LOWER. Exercise counts vary week to week (week 12 LOWER has 4).

**Check-in workbook.** Use it for structure and defaults only: check-in day (Tuesday in the sample), sleep goal 8 h, steps goal 10,500, three custom 1-10 metrics, nine body measurement sites, front/side/rear photos, macro timing (peri-workout carb weight 0.65, fat weight 0.15), dietary presets and activity factors. The sample client values (age 37, 179 cm, 83 kg, 2125 kcal, 125 g each macro) are placeholders, not defaults. `Form Submissions` shows `#REF!` and the measurement delta cells show `#N/A`; these are template formulas with no data, so ignore them.

**Beginner program.** One sheet per option (`Option A` to `Option D`) plus `Read Me`. Clean data. Load column is blank on purpose.

Run validation on every file anyway and show me anything ambiguous before relying on it.
