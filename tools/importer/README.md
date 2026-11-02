# Program importer

Turns the coach's workbooks in `Resources/Source/` into the JSON the app bundles.
The workbooks are never modified.

```bash
python3 tools/importer/import_programs.py           # regenerate Resources/Generated/*
python3 -m unittest discover -s tools/importer      # parser + whole-file tests
```

Needs Python 3.10+ and `openpyxl`. It reads cached cell values, so if a workbook is
edited, open and save it in Excel/Numbers first so formulas are recalculated.

## Outputs (`Resources/Generated/`)

| File | Contents |
|---|---|
| `programs.json` | Program → Week → Workout → ExerciseSlot, plus source SHA-256s |
| `exercise_library.json` | 181 movements: pattern, equipment, muscles, cues, every spelling used, ranked substitutes |
| `equipment.json` | Equipment vocabulary and the five equipment profiles |
| `checkin_defaults.json` | Check-in structure and defaults (no sample-client values) |
| `IMPORT_REPORT.md` | Everything to confirm, every repaired cell, warnings, session-length estimates |

Output is deterministic: unchanged sources give byte-identical files.

## ExerciseSlot fields

- `exercise`, `exerciseKey` (lower-case, used to match the library), `label` (cell text as written)
- `sets` `{count, perSide}`. `"2each"` means 2 sets per side.
- `reps`: always has `raw` and `perSide`, plus `kind`:
  `fixed` · `range` · `perSet` (`11,9,7`) · `plus` (`10+`) · `amrap` · `duration` · `distance` ·
  `segments` (drop sets `10/15`, 21s `7/7/7`) · `restPause` (`8-10(+4+4)`) · `unknown` (never guessed).
  `repairedFrom` marks a rep range Excel had turned into a date.
- `effort` `{type: rpe|rir, min, max}`, `pct1RM` `{min, max, lift}` (12-week only), `warmupSets` (12-week only)
- `rest` `{minSec, maxSec}`. Inside a superset, earlier members rest 0 and the last carries the round's rest (`inferred` explains any move).
- `superset` `{group, label, order, size}`, `modifier` (18-week column E text), `lastSetPlus`
- `isMainLift` + `mainLiftBasis` (how it was decided), `source` `{sheet, row}`

## Per-file rules

See `Resources/Source/SOURCE_NOTES.md`. In short:
- **Upper/Lower:** sessions are every 7 rows, named by position from week 1 (sheet names are inconsistent).
- **Body Part Split:** sessions keyed by position; the second "Legs & Abs" is labelled "(second)".
- **12-week:** different columns (B session, D warm-ups, H %1RM, L notes). Columns G and K are ignored
  (G was pre-calculated from someone else's 1RMs). Week 9's missing header is inferred.
- **18-week:** RIR; column E is a superset label or a modifier; RIR above 4 is flagged as probable RPE.
- **Beginner:** main lifts are rows whose Notes start with `Main lift.`; phases come from the week number.

## Source files in this folder

| File | What it holds |
|---|---|
| `import_programs.py` | Reads the workbooks, applies decisions, writes the outputs and the report |
| `parsing.py` | Cell parsers (reps, sets, rest, RPE/RIR, %1RM, superset labels) |
| `coach_decisions.json` | Every call made on ambiguous source data, with the reason. Edit and re-run to change one |
| `library_catalogue.py` | The exercise catalogue, one line per movement, including aliases for every workbook spelling |
| `exercise_seed.json` | The 28 exercises from the brief (cues, swaps, rep defaults); these override the catalogue text |
| `equipment.py` | Equipment vocabulary and profiles (full gym, basic gym, hotel gym, home dumbbells, travel) |
| `substitution.py` | Swap ranking (import time) and the runtime `choose` / `options` / `adapt` rules the app ports |
| `versions.py` | Standard / low-energy / express / minimum versions and the 60-minute trim |

## Adapting a session (rules the app follows)

1. **Equipment.** The user picks where they are training (a profile, adjustable item by item), or marks one
   exercise as "busy". `choose()` keeps the exercise if it fits; otherwise it takes an alternative the program
   names itself (e.g. "Front squat [or box squat]"), then the coach's curated swaps in order, then the closest
   movement by pattern, muscles and difficulty. Beginner programs never get a swap above difficulty 2.
   Every exercise's list is guaranteed to contain an option for every profile, so no slot is left empty.
2. **Prescription.** `adapt()` drops %1RM when the stand-in is a different lift, switches to per-side reps for
   single-side stand-ins, raises the rep target for bodyweight stand-ins, and never carries a weight across
   exercises (each exercise has its own history; the first time is by feel at the slot's RPE/RIR).
3. **Time and energy.** `version()` builds a low-energy, express or minimum copy of the session;
   `trim_options()` offers to pair accessories or drop them from the end when a session is over 60 minutes.
   The user sees the result before applying it. The program file never changes.
