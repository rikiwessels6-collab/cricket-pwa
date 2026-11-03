#!/usr/bin/env python3
"""Steady Strength program importer.

Reads the untouched source workbooks in Resources/Source/ and writes:

  Resources/Generated/programs.json          every program, week, workout and exercise slot
  Resources/Generated/exercise_library.json  seed library + every exercise name found
  Resources/Generated/checkin_defaults.json  structure/defaults from the check-in workbook
  Resources/Generated/IMPORT_REPORT.md       everything ambiguous, for a human to confirm

Usage:  python3 tools/importer/import_programs.py [--root PATH]

The output is deterministic, so re-running on unchanged sources produces
identical files (safe to commit and diff).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

import sys

import openpyxl

sys.path.insert(0, str(Path(__file__).resolve().parent))  # works under python -I too
import equipment as equip  # noqa: E402
import library_catalogue  # noqa: E402
import steady_programs  # noqa: E402
import substitution  # noqa: E402
import versions  # noqa: E402
from parsing import (  # noqa: E402
    exercise_key,
    one_rm_lift,
    parse_effort,
    parse_pct_1rm,
    parse_reps,
    parse_rest,
    parse_sets,
    raw_text,
    split_exercise_label,
)

HERE = Path(__file__).resolve().parent
SCHEMA_VERSION = 1

FILES = {
    "full_body": "RWFitness_Full_Body_8_Week_Program_3days_COMPLETED.xlsx",
    "upper_lower": "RwFitness_Upper_Lower_8_Week_Program_4days.xlsx",
    "body_part": "RWfitness_Body_Part_Split_8_Week_Program_5days.xlsx",
    "twelve": "Copy_of_Riki_of_RWFitness_12_Weeks.xlsx",
    "eighteen": "Intermediate_18_weeks.xlsx",
    "checkin": "Copy_of_New_Done_For_You_Client_Check-In_System_MASTER_COPY.xlsx",
    "beginner": "Beginner_12_Week_Strength_Program.xlsx",
    "guide": "Steady_Strength_Program_Guide.pdf",
}

WORK_SEC, WARMUP_MIN, COOLDOWN_MIN = versions.WORK_SEC, versions.WARMUP_MIN, versions.COOLDOWN_MIN


class Issues:
    """Collects everything a human should look at, grouped by severity.

    confirm  - the importer made a call you need to approve
    decision - a call made in coach_decisions.json
    warning  - data looks wrong or incomplete in the source
    info     - noteworthy but handled
    """

    def __init__(self):
        self.items: list[dict] = []

    def add(self, severity, code, program, where, message):
        self.items.append(
            {"severity": severity, "code": code, "program": program, "where": where, "message": message}
        )

    def of(self, severity):
        return [i for i in self.items if i["severity"] == severity]


def rows(ws):
    """Yield (excel_row_number, tuple_of_values) for non-empty rows."""
    for idx, values in enumerate(ws.iter_rows(values_only=True), start=1):
        if any(v not in (None, "") for v in values):
            yield idx, values


def col(values, letter):
    i = ord(letter) - ord("A")
    return values[i] if i < len(values) else None


def text(values, letter):
    return raw_text(col(values, letter))


def new_slot(sheet, row, label, sets, reps, effort, rest, notes):
    parts = split_exercise_label(label)
    slot = {
        "exercise": parts["name"],
        "exerciseKey": exercise_key(parts["name"]),
        "label": parts["label"],
        "sets": sets,
        "reps": reps,
        "effort": effort,
        "rest": rest,
        "notes": notes or None,
        "source": {"sheet": sheet, "row": row},
    }
    if "supersetGroup" in parts:
        slot["superset"] = {"group": parts["supersetGroup"], "order": parts["supersetOrder"]}
    if "alternatives" in parts:
        slot["alternatives"] = parts["alternatives"]
    return slot


# ======================================================================
# Standard RW layout: B week | C workout | D exercise | E sets | F reps |
# G load | H RPE | I rest | J notes   (Full Body, Upper/Lower, Body Part, Beginner)
# ======================================================================


def read_standard(ws, effort_kind="rpe"):
    weeks = []
    week = workout = None
    for r, v in rows(ws):
        b, c, d = text(v, "B"), text(v, "C"), text(v, "D")
        if b.lower().startswith("week") and d == "Exercise":
            week = {"number": int(re.search(r"\d+", b).group()), "label": b, "workouts": []}
            weeks.append(week)
            workout = None
            continue
        if week is None or not d or d == "Exercise":
            continue
        if c:
            workout = {"rawName": c, "slots": []}
            week["workouts"].append(workout)
        if workout is None:
            raise ValueError(f"{ws.title} row {r}: exercise before any workout name")
        workout["slots"].append(
            new_slot(
                ws.title, r, d,
                parse_sets(col(v, "E")),
                parse_reps(col(v, "F")),
                parse_effort(col(v, "H"), effort_kind),
                parse_rest(col(v, "I")),
                text(v, "J"),
            )
        )
    return weeks


def normalise_superset_rest(members, program, where, issues):
    """One rest per superset round, taken after the last exercise.

    The 18-week sheet sometimes writes the pair's rest on the first exercise
    and leaves the last one blank. Earlier members get 0 s (go straight to the
    partner); the last member carries the round's rest.
    """
    given = [m["rest"] for m in members if m["rest"] and m["rest"].get("maxSec")]
    last = members[-1]
    if not (last["rest"] and last["rest"].get("maxSec")) and given:
        last["rest"] = {**given[-1], "inferred": "moved from an earlier exercise in the superset"}
        issues.add("info", "superset-rest", program, where,
                   f"Rest '{given[-1]['raw']}' written on an earlier exercise; applied after the last one ({last['exercise']})")
    for m in members[:-1]:
        if m["rest"] is None or m["rest"].get("maxSec"):
            m["rest"] = {"raw": raw_text((m["rest"] or {}).get("raw")), "minSec": 0, "maxSec": 0,
                         "inferred": "go straight to the next exercise in the superset"}


def unit_of(ws):
    for _, v in rows(ws):
        for cell in v[:6]:
            if raw_text(cell).lower() in ("kg", "lbs"):
                return raw_text(cell).lower()
    return None


def finish_workouts(weeks):
    """Number workouts by position and slots by order."""
    for w in weeks:
        for i, wo in enumerate(w["workouts"], start=1):
            wo["position"] = i
            wo.setdefault("name", wo["rawName"])
            for j, s in enumerate(wo["slots"], start=1):
                s["order"] = j


def mark_main_by_rest(weeks, program, issues):
    """RW files without an explicit marker: a lift is 'main' if it rests 3+ min."""
    for w in weeks:
        for wo in w["workouts"]:
            for s in wo["slots"]:
                rest = s.get("rest") or {}
                s["isMainLift"] = bool(rest.get("maxSec") and rest["maxSec"] >= 180)
                s["mainLiftBasis"] = "rest>=3min (heuristic)"
    issues.add("confirm", "main-lift-heuristic", program, "all weeks",
               "No main-lift marker in this file. Lifts resting 3+ minutes are treated as main lifts "
               "(they get warm-up ramp sets and larger load jumps).")


# ---------------------------------------------------------------- Full Body


def import_full_body(src, issues):
    pid = "rw-full-body-3day-8wk"
    wb = openpyxl.load_workbook(src, data_only=True, read_only=True)
    ws = wb.worksheets[0]
    weeks = read_standard(ws)
    finish_workouts(weeks)
    program_notes = []
    for w in weeks:
        w["isDeload"] = w["number"] in (4, 8)
        for wo in w["workouts"]:
            for s in wo["slots"]:
                if s["notes"] and w["number"] == 1 and wo["position"] == 1 and s["order"] == 1:
                    program_notes.append(s["notes"])
    # Verify the structure described in SOURCE_NOTES.
    for w in weeks:
        for wo in w["workouts"]:
            first = wo["slots"][0]
            for s in wo["slots"]:
                n = s["sets"]["count"]
                if w["isDeload"]:
                    ok = n == 2 and (s["effort"] or {}).get("max") == 6
                elif w["number"] in (3, 7) and s is first:
                    ok = n == 4
                else:
                    ok = n == 3
                if not ok:
                    issues.add("warning", "structure", pid, f"week {w['number']} {wo['rawName']} row {s['source']['row']}",
                               f"{s['exercise']}: {n} sets, RPE {(s['effort'] or {}).get('raw')} does not match the block pattern")
    issues.add("info", "provenance", pid, "file",
               "Marked in SOURCE_NOTES as completed by Claude from an empty template; review the exercise choices as the coach.")
    return {
        "id": pid, "name": "Full Body 3-Day (8 weeks)", "author": "RW Fitness",
        "intensityType": "rpe", "unit": unit_of(ws), "weeks": weeks,
        "status": "complete", "programNotes": program_notes,
        "source": {"file": FILES["full_body"], "sheet": ws.title},
    }


# ---------------------------------------------------------------- Upper/Lower


def import_upper_lower(src, issues):
    pid = "rw-upper-lower-4day-8wk"
    wb = openpyxl.load_workbook(src, data_only=True, read_only=True)
    ws = wb.worksheets[0]
    raw_weeks = read_standard(ws)
    # Do not trust session names: every 7 exercise rows is one session.
    weeks = []
    for w in raw_weeks:
        slots, names = [], []
        for wo in w["workouts"]:
            for k, s in enumerate(wo["slots"]):
                slots.append(s)
                names.append(wo["rawName"] if k == 0 else None)
        if len(slots) % 7:
            issues.add("warning", "structure", pid, f"week {w['number']}", f"{len(slots)} exercise rows is not a multiple of 7")
        chunks = [slots[i:i + 7] for i in range(0, len(slots), 7)]
        workouts = []
        for i, chunk in enumerate(chunks):
            raw = names[i * 7] or ""
            workouts.append({"rawName": raw, "slots": chunk})
        weeks.append({"number": w["number"], "label": w["label"], "workouts": workouts, "isDeload": False})
    canonical = [wo["rawName"] for wo in weeks[0]["workouts"]]
    for w in weeks:
        for i, wo in enumerate(w["workouts"]):
            wo["name"] = canonical[i] if i < len(canonical) else f"Session {i + 1}"
            if re.sub(r"\s+", "", wo["rawName"]).lower() != re.sub(r"\s+", "", wo["name"]).lower():
                issues.add("confirm", "session-name", pid, f"week {w['number']} session {i + 1}",
                           f"Sheet says '{wo['rawName'] or '(no name: second session in a 14-row block)'}'; "
                           f"imported by position as '{wo['name']}'")
            elif wo["rawName"] != wo["name"]:
                issues.add("info", "session-name", pid, f"week {w['number']} session {i + 1}",
                           f"'{wo['rawName']}' normalised to '{wo['name']}'")
    # Weeks 6-8 should repeat week 5's prescription.
    def sig(week):
        return [[(s["exerciseKey"], s["sets"]["raw"], s["reps"]["raw"], (s["effort"] or {}).get("raw"), (s["rest"] or {}).get("raw"))
                 for s in wo["slots"]] for wo in week["workouts"]]
    w5 = next(w for w in weeks if w["number"] == 5)
    for n in (6, 7, 8):
        wk = next(w for w in weeks if w["number"] == n)
        if sig(wk) == sig(w5):
            issues.add("info", "repeat-check", pid, f"week {n}", "Identical to week 5 (as expected)")
        else:
            diffs = [(i, a, b) for i, (x, y) in enumerate(zip(sig(wk), sig(w5))) for a, b in zip(x, y) if a != b]
            issues.add("warning", "repeat-check", pid, f"week {n}",
                       f"Differs from week 5 in {len(diffs)} slot(s), e.g. {diffs[:2]}")
    finish_workouts(weeks)
    return {
        "id": pid, "name": "Upper/Lower 4-Day (8 weeks)", "author": "RW Fitness",
        "intensityType": "rpe", "unit": unit_of(ws), "weeks": weeks, "status": "complete",
        "source": {"file": FILES["upper_lower"], "sheet": ws.title},
    }


# ---------------------------------------------------------------- Body Part


def import_body_part(src, issues):
    pid = "rw-body-part-split-5day-8wk"
    wb = openpyxl.load_workbook(src, data_only=True, read_only=True)
    ws = wb.worksheets[0]
    weeks = read_standard(ws)
    for w in weeks:
        w["isDeload"] = False
        counts = Counter(wo["rawName"] for wo in w["workouts"])
        for wo in w["workouts"]:
            wo["name"] = wo["rawName"]
        seen = Counter()
        for wo in w["workouts"]:
            if counts[wo["rawName"]] > 1:
                seen[wo["rawName"]] += 1
                wo["name"] = f"{wo['rawName']} ({'second' if seen[wo['rawName']] == 2 else seen[wo['rawName']]})" \
                    if seen[wo["rawName"]] > 1 else wo["rawName"]
        if len(w["workouts"]) != 5:
            issues.add("warning", "structure", pid, f"week {w['number']}", f"{len(w['workouts'])} sessions, expected 5")
    issues.add("info", "session-name", pid, "all weeks",
               "Two sessions are both called 'Legs & Abs'; the second is shown as 'Legs & Abs (second)' and sessions are keyed by position.")
    finish_workouts(weeks)
    return {
        "id": pid, "name": "Body Part Split 5-Day (8 weeks)", "author": "RW Fitness",
        "intensityType": "rpe", "unit": unit_of(ws), "weeks": weeks, "status": "complete",
        "source": {"file": FILES["body_part"], "sheet": ws.title},
    }


# ---------------------------------------------------------------- 12-week
# B session | C exercise | D warm-up sets | E sets | F reps | G load (ignored:
# pre-computed from someone else's 1RMs) | H %1RM | I RPE | J rest | K W/S load
# (ignored: junk) | L notes


def import_twelve(src, issues, date_repairs):
    pid = "rw-12-week"
    wb = openpyxl.load_workbook(src, data_only=True, read_only=True)
    ws = wb["12 Week Program"]
    weeks, week, workout, banner = [], None, None, None
    for r, v in rows(ws):
        b, c = text(v, "B"), text(v, "C")
        if c == "Exercise" or text(v, "D") == "Warm-up Sets":
            number = len(weeks) + 1
            label = b or f"Week {number}"
            if b:
                m = re.search(r"\d+", b)
                if m and int(m.group()) != number:
                    issues.add("warning", "structure", pid, f"row {r}", f"Header '{b}' but this is week {number} in sequence")
            else:
                issues.add("confirm", "missing-week-header", pid, f"row {r}",
                           f"Header row has no week label; treated as Week {number} (follows week {number - 1}).")
            week = {"number": number, "label": label, "workouts": [], "isDeload": "deload" in b.lower()}
            if banner:
                week["banner"] = banner
                issues.add("confirm", "deload-week", pid, f"row {banner['row']}",
                           f"Banner '{banner['text'][:60]}...' sits directly above '{label}'. "
                           f"Imported week {number} as the semi-deload (the header itself says so).")
                banner = None
            weeks.append(week)
            workout = None
            continue
        if b and not c:
            banner = {"row": r, "text": b}
            continue
        if week is None or not c:
            continue
        if b:
            workout = {"rawName": b, "name": b.rstrip(":").strip().title().replace("(Pump Day)", "(Pump Day)"), "slots": []}
            week["workouts"].append(workout)
        reps = parse_reps(col(v, "F"))
        if "repairedFrom" in reps:
            date_repairs.append({"program": pid, "row": r, "exercise": c, "repair": reps["repairedFrom"]})
        slot = new_slot(ws.title, r, c, parse_sets(col(v, "E")), reps,
                        parse_effort(col(v, "I"), "rpe"), parse_rest(col(v, "J")), text(v, "L"))
        wu = col(v, "D")
        slot["warmupSets"] = int(wu) if isinstance(wu, (int, float)) else None
        pct = parse_pct_1rm(col(v, "H"))
        if pct:
            lift = one_rm_lift(slot["exercise"])
            pct["lift"] = lift
            if lift is None:
                issues.add("warning", "pct-no-lift", pid, f"row {r}", f"{c}: %1RM given but no 1RM lift matches")
        slot["pct1RM"] = pct
        slot["isMainLift"] = bool(pct) or (slot["warmupSets"] or 0) >= 3
        slot["mainLiftBasis"] = "has %1RM or 3+ warm-up sets"
        workout["slots"].append(slot)
    finish_workouts(weeks)
    per_week = Counter(len(w["workouts"]) for w in weeks)
    issues.add("confirm", "days-per-week", pid, "all weeks",
               "Odd weeks have 5 full-body sessions; even weeks have 6 Legs/Push/Pull sessions "
               f"(counts: {dict(per_week)}). The brief says 4-5 days. The app will run them as a rotation, "
               "so 6 sessions simply take longer than a calendar week.")
    variations = sorted({(s["exercise"], s["pct1RM"]["lift"]) for w in weeks for wo in w["workouts"]
                         for s in wo["slots"] if s.get("pct1RM") and s["pct1RM"].get("lift")})
    direct = {"back squat": "squat", "barbell bench press": "bench", "deadlift": "deadlift", "barbell overhead press": "ohp"}
    for name, lift in variations:
        if direct.get(name.lower()) != lift:
            issues.add("confirm", "pct-variation", pid, name,
                       f"'{name}' loads are calculated from your {lift.upper()} 1RM")
    issues.add("info", "ignored-columns", pid, "columns G, K",
               "Load (G) holds values pre-calculated from the sample 1RMs (120/90/135/45) and W/S Load (K) holds junk; "
               "both ignored. Loads are computed from each user's own 1RMs and the %1RM column.")
    return {
        "id": pid, "name": "RW 12-Week Program", "author": "RW Fitness",
        "intensityType": "rpe", "usesPercent1RM": True, "requires1RM": list(("squat", "bench", "deadlift", "ohp")),
        "warmupMethod": {"kind": "pyramid", "appliesTo": "main lifts",
                         "steps": [{"load": "bar", "reps": 15}, {"pct": 0.40, "reps": 5},
                                   {"pct": 0.60, "reps": 3}, {"pctMin": 0.70, "pctMax": 0.75, "reps": 2}],
                         "pctOf": "working weight"},
        "unit": unit_of(ws), "weeks": weeks, "status": "complete",
        "source": {"file": FILES["twelve"], "sheet": ws.title},
    }


# ---------------------------------------------------------------- 18-week
# B week | C workout | D exercise | E superset / modifier | F sets | G reps |
# H weight (empty input) | I RIR | J rest | K notes


def import_eighteen(src, issues):
    pid = "rw-intermediate-18wk"
    wb = openpyxl.load_workbook(src, data_only=True, read_only=True)
    weeks = []
    for ws in wb.worksheets:
        week = workout = None
        for r, v in rows(ws):
            b, c, d, e = text(v, "B"), text(v, "C"), text(v, "D"), text(v, "E")
            if b.lower().startswith("week") and d == "Exercise":
                week = {"number": int(re.search(r"\d+", b).group()), "label": b, "workouts": [], "isDeload": False}
                weeks.append(week)
                continue
            if week is None or not d:
                continue
            if c:
                name = re.sub(r"\s*&\s*", " & ", c).strip()
                if name != c:
                    issues.add("info", "session-name", pid, f"{ws.title} row {r}", f"'{c}' normalised to '{name}'")
                workout = {"rawName": c, "name": name.title(), "slots": []}
                week["workouts"].append(workout)
            slot = new_slot(ws.title, r, d, parse_sets(col(v, "F")), parse_reps(col(v, "G")),
                            parse_effort(col(v, "I"), "rir"), parse_rest(col(v, "J")), text(v, "K"))
            m = re.fullmatch(r"SUPERSET\s*(\d+)", e.upper())
            if m:
                slot["superset"] = {"group": f"S{m.group(1)}"}
            elif re.fullmatch(r"(\d+)\+ FOR LAST SET", e.upper()):
                slot["lastSetPlus"] = True
                slot["modifier"] = e
            elif e:
                slot["modifier"] = e
            workout["slots"].append(slot)
    weeks.sort(key=lambda w: w["number"])
    finish_workouts(weeks)
    return {
        "id": pid, "name": "Intermediate 18 Weeks", "author": "RW Fitness",
        "intensityType": "rir", "unit": "kg", "weeks": weeks, "status": "complete",
        "source": {"file": FILES["eighteen"], "sheet": "Weeks 1 - 9 + Weeks 10 -18"},
    }


# ---------------------------------------------------------------- Beginner

BEGINNER_OPTIONS = {
    "Option A": ("a", 2, "Busy weeks"),
    "Option B": ("b", 3, "Recommended start"),
    "Option C": ("c", 4, "After about 8 weeks of Option B"),
    "Option D": ("d", 5, "Only after a full 12 weeks of Option B or C"),
}


def beginner_phase(week):
    if week <= 4:
        return "Learn"
    if week <= 7:
        return "Build"
    if week in (8, 12):
        return "Easy week"
    return "Strengthen"


def import_beginner(src, issues):
    wb = openpyxl.load_workbook(src, data_only=True, read_only=True)
    readme = [raw_text(v[0]) for _, v in rows(wb["Read Me"])]
    programs, cues = [], {}
    for sheet, (suffix, days, when) in BEGINNER_OPTIONS.items():
        pid = f"beginner-12wk-option-{suffix}"
        ws = wb[sheet]
        weeks = read_standard(ws)
        finish_workouts(weeks)
        for w in weeks:
            w["phase"] = beginner_phase(w["number"])
            w["isDeload"] = w["phase"] == "Easy week"
            for wo in w["workouts"]:
                for s in wo["slots"]:
                    notes = s["notes"] or ""
                    s["isMainLift"] = notes.startswith("Main lift.")
                    s["mainLiftBasis"] = "'Main lift.' in Notes"
                    cue = notes.removeprefix("Main lift.").strip()
                    if w["number"] == 1 and cue:
                        cues.setdefault(s["exerciseKey"], cue)
                    n, eff = s["sets"]["count"], s["effort"] or {}
                    reps = s["reps"]
                    # Validate the phase rules from the brief.
                    problems = []
                    if w["phase"] == "Learn" and n != 2:
                        problems.append("Learn weeks should be 2 sets")
                    if w["phase"] == "Build" and n != (3 if s["isMainLift"] else 2):
                        problems.append("Build weeks: main lifts 3 sets, others 2")
                    if w["phase"] == "Easy week" and (n != 2 or eff.get("max") != 6):
                        problems.append("Easy weeks should be 2 sets at RPE 6")
                    if w["phase"] == "Strengthen" and s["isMainLift"] and (n != 3 or (reps.get("kind") == "range" and (reps["min"], reps["max"]) != (8, 10))):
                        problems.append("Strengthen weeks: main lifts 3 sets of 8-10")
                    for p in problems:
                        issues.add("warning", "phase-rule", pid, f"week {w['number']} {wo['name']} row {s['source']['row']}",
                                   f"{s['exercise']}: {n} x {reps['raw']} RPE {eff.get('raw')}; {p}")
        if len({len(w['workouts']) for w in weeks}) != 1 or len(weeks[0]["workouts"]) != days:
            issues.add("warning", "structure", pid, sheet, "Unexpected number of sessions per week")
        programs.append({
            "id": pid, "name": f"Beginner 12-Week Strength, {sheet} ({days} days)", "author": "RW Fitness",
            "intensityType": "rpe", "unit": unit_of(ws), "weeks": weeks, "status": "complete",
            "family": "beginner-12wk", "optionDaysPerWeek": days, "whenToUse": when, "maxSwapDifficulty": 2,
            "progression": "double progression; starting weights by feel (about RPE 6 for 12 clean reps)",
            "sessionMinutesEstimate": {"weeks1to4": [44, 49], "fromWeek5": [49, 60]},
            "readMe": readme,
            "source": {"file": FILES["beginner"], "sheet": sheet},
        })
    return programs, cues


# ======================================================================
# Validation shared by every program
# ======================================================================


def validate_common(program, issues):
    pid = program["id"]
    for w in program["weeks"]:
        for wo in w["workouts"]:
            for s in wo["slots"]:
                where = f"week {w['number']} {wo['name']} row {s['source']['row']}"
                if s["sets"]["count"] is None:
                    issues.add("warning", "sets-unparsed", pid, where, f"{s['exercise']}: sets '{s['sets']['raw']}'")
                if s["reps"]["kind"] == "unknown":
                    issues.add("warning", "reps-unparsed", pid, where, f"{s['exercise']}: reps '{s['reps']['raw']}'")
                if s["rest"] is None:
                    issues.add("warning", "rest-missing", pid, where, f"{s['exercise']}: no rest given")
                elif s["rest"]["minSec"] is None:
                    single = s["sets"]["count"] == 1
                    issues.add("info" if single else "warning", "rest-unparsed", pid, where,
                               f"{s['exercise']}: rest '{s['rest']['raw']}'" + (" (only 1 set, so no rest needed)" if single else ""))
                if s["effort"] is None and program["intensityType"] in ("rpe", "rir"):
                    issues.add("info", "effort-missing", pid, where, f"{s['exercise']}: no {program['intensityType'].upper()} given")
                elif s["effort"] and s["effort"]["min"] is None:
                    issues.add("warning", "effort-unparsed", pid, where, f"{s['exercise']}: '{s['effort']['raw']}'")
                p = s.get("pct1RM")
                if p and (p["min"] is None or not 0.4 <= p["min"] <= p["max"] <= 1.0):
                    issues.add("warning", "pct-range", pid, where, f"{s['exercise']}: %1RM '{p['raw']}'")


def process_supersets(program, issues):
    """Group superset members by adjacency, not label alone.

    A session can reuse a label for two separate pairs (12-week Legs #1 has
    A1/A2 twice), so a group is a run of adjacent rows with the same label,
    restarting whenever the 12-week order number goes back to 1. Each group
    gets a unique id within its workout.
    """
    pid = program["id"]
    for w in program["weeks"]:
        for wo in w["workouts"]:
            runs, prev = [], None
            for s in wo["slots"]:
                ss = s.get("superset")
                if not ss:
                    prev = None
                    continue
                label = ss["group"]
                restart = ss.get("order") == 1 and prev is not None and prev[0] == label
                if prev is None or prev[0] != label or restart:
                    runs.append((label, []))
                runs[-1][1].append(s)
                prev = (label, s)
            used = Counter()
            for label, members in runs:
                used[label] += 1
                gid = label if used[label] == 1 else f"{label}#{used[label]}"
                where = f"week {w['number']} {wo['name']} {gid}"
                if used[label] > 1:
                    issues.add("info", "superset-label-reused", pid, where,
                               f"Label '{label}' used for a second, separate superset in this session")
                for k, m in enumerate(members, start=1):
                    m["superset"] = {"group": gid, "label": label, "order": k, "size": len(members)}
                if len(members) < 2:
                    issues.add("warning", "superset-size", pid, f"{where} row {members[0]['source']['row']}",
                               f"Superset '{members[0]['label']}' has no partner; run as a normal exercise")
                    del members[0]["superset"]
                    continue
                normalise_superset_rest(members, pid, where, issues)
                counts = {m["sets"]["count"] for m in members}
                if len(counts) > 1:
                    issues.add("info", "superset-sets", pid, where,
                               f"Superset members have different set counts {sorted(c for c in counts if c)}; "
                               "extra sets are done on their own after the paired rounds")


estimate_minutes = versions.estimate_minutes


# ======================================================================
# Exercise library
# ======================================================================

def build_catalogue(seed, beginner_cues, issues):
    """Catalogue entries + seed fields + ranked substitutes, and a name index."""
    entries = library_catalogue.parse()
    seed_by_key = {exercise_key(e["name"]): e for e in seed}
    index, problems = {}, []
    for e in entries:
        for k in [exercise_key(e["name"])] + [exercise_key(a) for a in e["aliases"]]:
            if k in index and index[k] != e["id"]:
                problems.append(f"'{k}' maps to both {index[k]} and {e['id']}")
            index[k] = e["id"]
        for m in e["primaryMuscles"] + e["secondaryMuscles"]:
            if m not in library_catalogue.MUSCLES:
                problems.append(f"{e['id']}: unknown muscle '{m}'")
        if e["pattern"] not in library_catalogue.PATTERNS:
            problems.append(f"{e['id']}: unknown pattern '{e['pattern']}'")
        for item in e["equipment"]:
            for opt in item.split("/"):
                if opt not in equip.EQUIPMENT:
                    problems.append(f"{e['id']}: unknown equipment '{opt}'")
        s = seed_by_key.get(exercise_key(e["name"]))
        if s:
            e.update({"cues": s["cues"], "cueSource": "brief", "swapText": s["swap"],
                      "repsWeeks1to8": s["repsWeeks1to8"], "repsWeeks9to12": s["repsWeeks9to12"],
                      "defaultRest": s["rest"], "seed": True})
        else:
            e.update({"cueSource": "drafted - coach to review", "seed": False})
        e["videoSources"] = []
        e["demoSearchQuery"] = f"{e['name'].lower()} Jeff Nippard technique"
        # Stretch-focused tip for isolation work, after Jeff Nippard's public teaching on lengthened partials.
        if e["tier"] == "accessory" and e["loadable"] and not e["timed"] and not e["pattern"].startswith("core") \
                and e["pattern"] not in ("carry", "plyometric", "calf"):
            e["advancedTip"] = ("Optional on the last set: once you can't do another full rep, add a few partial reps "
                                "in the stretched half of the movement.")
    if problems:
        raise ValueError("catalogue problems:\n  " + "\n  ".join(problems))
    missing_seed = set(seed_by_key) - {exercise_key(e["name"]) for e in entries}
    if missing_seed:
        raise ValueError(f"seed exercises missing from catalogue: {sorted(missing_seed)}")
    for e in entries:
        e["substitutes"] = substitution.rank_substitutes(e, entries)
        if not e["substitutes"]:
            issues.add("warning", "no-substitutes", "exercise-library", e["name"], "No stand-in exercises found")
    for k, cue in beginner_cues.items():
        sid = index.get(k)
        s = seed_by_key.get(k)
        if s and s["cues"].rstrip(".") != cue.rstrip("."):
            issues.add("info", "cue-differs", "exercise-library", s["name"],
                       f"Workbook cue '{cue}' differs from the brief's cue; the brief's cue is kept")
        elif sid and not s:
            pass
    return entries, index


def resolve_exercises(programs, index, by_id, issues):
    """Point every slot at a catalogue entry; fail loudly on any unknown name."""
    unknown, merges = [], defaultdict(set)
    for p in programs:
        for w in p["weeks"]:
            for wo in w["workouts"]:
                for s in wo["slots"]:
                    eid = index.get(s["exerciseKey"])
                    if eid is None:
                        unknown.append((p["id"], s["exercise"]))
                        continue
                    s["exerciseId"] = eid
                    merges[eid].add(s["exercise"].lower())
                    alts = [index.get(exercise_key(a)) for a in s.get("alternatives", [])]
                    if any(a is None for a in alts):
                        issues.add("warning", "alt-unknown", p["id"], f"row {s['source']['row']}",
                                   f"Alternative {s['alternatives']} not in the library")
                    s["alternativeIds"] = [a for a in alts if a]
    if unknown:
        raise ValueError(f"exercise names not in the catalogue: {sorted(set(unknown))[:20]}")
    used = defaultdict(set)
    for p in programs:
        for w in p["weeks"]:
            for wo in w["workouts"]:
                for s in wo["slots"]:
                    used[s["exerciseId"]].add(p["id"])
    for eid, progs in used.items():
        by_id[eid]["usedIn"] = sorted(progs)
    for e in by_id.values():
        e.setdefault("usedIn", [])
    return {by_id[k]["name"]: sorted(v) for k, v in merges.items() if len(v) > 1}


def slot_where(w, wo, s):
    return f"week {w['number']} {wo['name']} row {s['source']['row']}"


def apply_decisions(programs, decisions, issues):
    """Apply coach_decisions.json. Every change is recorded on the slot and in the report."""
    P = {p["id"]: p for p in programs}

    def slots(pid):
        for w in P[pid]["weeks"]:
            for wo in w["workouts"]:
                for s in wo["slots"]:
                    yield w, wo, s

    d = decisions["rirAboveIsRpe"]
    for w, wo, s in slots(d["program"]):
        e = s.get("effort")
        if e and e["type"] == "rir" and e["max"] is not None and e["max"] > d["threshold"]:
            s["effort"] = {"type": "rir", "raw": e["raw"], "min": 10 - e["max"], "max": 10 - e["min"],
                           "correctedFrom": f"RIR column said {e['raw']}; read as RPE {e['raw']}"}
            issues.add("decision", "rir-from-rpe", d["program"], slot_where(w, wo, s),
                       f"{s['exercise']}: RIR {e['raw']} read as RPE {e['raw']} = RIR {10 - e['max']}")
    for f in decisions["fillSets"]:
        for w, wo, s in slots(f["program"]):
            if s["source"] == {"sheet": f["sheet"], "row": f["row"]} and s["sets"]["count"] is None:
                s["sets"] = {"raw": "", "count": f["sets"], "perSide": False, "filled": f["why"]}
                issues.add("decision", "fill-sets", f["program"], slot_where(w, wo, s), f"{s['exercise']}: {f['sets']} sets ({f['why']})")
    for pair in decisions["pairAsSuperset"]:
        members = [s for _, _, s in slots(pair["program"]) if s["source"]["row"] in pair["rows"]]
        if len(members) != len(pair["rows"]):
            raise ValueError(f"pairAsSuperset rows not found: {pair}")
        for k, s in enumerate(sorted(members, key=lambda s: s["source"]["row"]), start=1):
            s["superset"] = {"group": pair["group"], "order": k}
        issues.add("decision", "pair-superset", pair["program"], f"rows {pair['rows']}",
                   " + ".join(m["exercise"] for m in members) + f" as superset {pair['group']}")


def fill_missing_rest(programs, issues):
    """Missing rest: same exercise, same session position, nearest week; else 2 min."""
    for p in programs:
        for w in p["weeks"]:
            for wo in w["workouts"]:
                for s in wo["slots"]:
                    if s["rest"] is not None:
                        continue
                    best = None
                    for w2 in p["weeks"]:
                        if w2 is w or len(w2["workouts"]) < wo["position"]:
                            continue
                        for s2 in w2["workouts"][wo["position"] - 1]["slots"]:
                            if s2["exerciseKey"] == s["exerciseKey"] and s2["rest"] and s2["rest"].get("maxSec"):
                                dist = abs(w2["number"] - w["number"])
                                if best is None or dist < best[0]:
                                    best = (dist, s2["rest"], w2["number"])
                    if best:
                        s["rest"] = {**best[1], "filled": f"copied from week {best[2]}"}
                    else:
                        s["rest"] = {"raw": "2min", "minSec": 120, "maxSec": 120, "filled": "default 2 min"}
                    issues.add("decision", "fill-rest", p["id"], slot_where(w, wo, s),
                               f"{s['exercise']}: rest {s['rest']['raw']} ({s['rest']['filled']})")


def apply_main_lift_rule(programs, decisions, by_id, issues):
    rule_for = set(decisions["mainLiftRule"]["appliesTo"])
    for p in programs:
        if p["id"] not in rule_for:
            continue
        for w in p["weeks"]:
            for wo in w["workouts"]:
                for s in wo["slots"]:
                    rest = (s["rest"] or {}).get("maxSec") or 0
                    tier = by_id[s["exerciseId"]]["tier"]
                    if p.get("family") == "steady-strength":
                        # Rest here is derived from the guide's rule, so it can't signal the role.
                        s["isMainLift"] = tier == "main"
                        s["mainLiftBasis"] = "library main lift"
                    else:
                        s["isMainLift"] = (tier == "main" and rest >= 120) or rest >= 180
                        s["mainLiftBasis"] = "library main lift with 2+ min rest, or 3+ min rest"


def program_equipment(p, by_id):
    """Equipment the program needs as written, and how it copes with each profile."""
    needed = set()
    slots = [s for w in p["weeks"] for wo in w["workouts"] for s in wo["slots"]]
    for s in slots:
        for item in by_id[s["exerciseId"]]["equipment"]:
            needed.add(item)
    coverage = {}
    for prof in equip.PROFILES:
        as_written = swapped = none = 0
        gaps = Counter()
        for s in slots:
            choice, _ = substitution.choose(s["exerciseId"], by_id, prof["equipment"],
                                            max_difficulty=p.get("maxSwapDifficulty", 3),
                                            slot_alternatives=s.get("alternativeIds", []))
            if choice == s["exerciseId"]:
                as_written += 1
            elif choice:
                swapped += 1
            else:
                none += 1
                gaps[by_id[s["exerciseId"]]["name"]] += 1
        coverage[prof["id"]] = {"asWritten": as_written, "swapped": swapped, "unavailable": none,
                                "total": len(slots), "gaps": dict(gaps.most_common())}
    return sorted(needed), coverage


# ======================================================================
# Check-in workbook
# ======================================================================


def sheet_cells(ws):
    cells = {}
    for r, v in rows(ws):
        for i, val in enumerate(v):
            if val not in (None, ""):
                cells[f"{chr(ord('A') + i) if i < 26 else 'A' + chr(ord('A') + i - 26)}{r}"] = val
    return cells


def macro_timing(cal_targets, carb_w, fat_w, meals):
    """Reproduce the workbook's meal split.

    Pre/post-workout meals share `carb_w` of carbs and `fat_w` of fat equally;
    the remaining meals split the rest equally. Protein and fibre are split
    evenly across all meals. Calories = 4P + 4C + 9F.
    """
    p, c, f, fib = cal_targets["protein"], cal_targets["carbs"], cal_targets["fat"], cal_targets["fibre"]
    peri = [m for m in meals if m in ("Pre-Training", "Post-Training")]
    other = [m for m in meals if m not in peri]
    out = []
    for m in meals:
        if peri:
            mc = c * carb_w / len(peri) if m in peri else c * (1 - carb_w) / len(other)
            mf = f * fat_w / len(peri) if m in peri else f * (1 - fat_w) / len(other)
        else:
            mc, mf = c / len(meals), f / len(meals)
        mp = p / len(meals)
        out.append({"meal": m, "protein": mp, "carbs": mc, "fat": mf, "fibre": fib / len(meals),
                    "kcal": 4 * mp + 4 * mc + 9 * mf})
    return out


def import_checkin(src, issues):
    wb = openpyxl.load_workbook(src, data_only=True, read_only=True)
    cfg = sheet_cells(wb["Configuration Sheet"])
    mt = sheet_cells(wb["Macro Timing"])
    amc = sheet_cells(wb["Approximate Maintenance Calorie"])

    presets = []
    for r in range(16, 23):
        name = amc.get(f"W{r}")
        if name:
            presets.append({"name": str(name).title(), "protein": amc[f"X{r}"], "carbs": amc[f"Y{r}"], "fat": amc[f"Z{r}"]})

    def meal_block(first_row, count):
        return [str(mt[f"D{r}"]).strip() for r in range(first_row, first_row + count)]

    templates = {
        "morning": meal_block(20, 6), "afternoon": meal_block(32, 6),
        "evening": meal_block(44, 6), "restDay": meal_block(57, 5),
    }
    # Check our formula reproduces the workbook's cached numbers.
    targets = {"protein": mt["H12"], "carbs": mt["I12"], "fat": mt["J12"], "fibre": mt["L12"]}
    active = templates["morning"][: int(mt["I18"])]
    ours = macro_timing(targets, mt["L6"], mt["L7"], active)
    sheet = [{"kcal": mt[f"F{r}"], "carbs": mt[f"I{r}"], "fat": mt[f"J{r}"]} for r in range(20, 20 + len(active))]
    reproduced = all(abs(a["kcal"] - b["kcal"]) < 0.01 and abs(a["carbs"] - b["carbs"]) < 0.01 and abs(a["fat"] - b["fat"]) < 0.01
                     for a, b in zip(ours, sheet))
    issues.add("info" if reproduced else "warning", "macro-timing", "checkin", "Macro Timing",
               "Meal split formula reproduces the workbook's numbers exactly" if reproduced
               else "Meal split formula does NOT reproduce the workbook; check before relying on it")
    fibre_per_1000 = round(mt["L12"] / mt["F12"] * 1000, 2)

    sites = [str(cfg[c]) for c in ("N20", "O20", "P20", "N21", "O21", "P21", "N22", "O22")]
    issues.add("info", "measurements", "checkin", "Configuration Sheet",
               f"The '9 sites' are 8 measured sites plus a TOTAL: {', '.join(sites)}")
    issues.add("info", "training-time", "checkin", "Macro Timing",
               "The workbook has three training-time templates (morning, afternoon, evening), one more than the brief's morning/afternoon")
    issues.add("info", "self-grade", "checkin", "Weekly Reports",
               "Weekly report includes a 'Grade yourself' (A-F) field that the brief doesn't mention; included as optional")
    issues.add("info", "protein-by-percent", "checkin", "Approximate Maintenance Calorie",
               "The sheet sets protein as a % of calories: the sample HIGH PROTEIN preset gives 274 g/day at 83 kg (3.3 g/kg). "
               "The app sets protein in g/kg first, as the brief says, so presets only shape carbs and fat.")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "source": FILES["checkin"],
        "checkInDay": str(cfg.get("I14", "Tuesday")).title(),
        "sleepGoalHours": cfg["E5"],
        "dailyStepsGoal": int(cfg["G9"]),
        "customMetricOptions": [str(cfg[f"C{r}"]) for r in range(6, 11)],
        "customMetricsDefault": [str(cfg["G5"]), str(cfg["I5"]), str(cfg["I9"])],
        "customMetricScale": [1, 10],
        "separateRestDayTargets": not bool(cfg.get("N16")),
        "measurementSites": sites,
        "measurementTotal": True,
        "photoAngles": ["front", "side", "rear"],
        "placeholderSets": ["Female silhouette", "Male silhouette", "Blank"],
        "placeholderSetDefault": "Female silhouette",
        "mealFrequency": {"trainingDay": int(mt["F6"]), "restDay": int(mt["F7"])},
        "periWorkout": {"carbShare": mt["L6"], "fatShare": mt["L7"]},
        "mealTemplates": templates,
        "fibrePer1000kcal": fibre_per_1000,
        "dietaryPresets": presets,
        "activityFactors": {"sedentary": 1.2, "light": 1.375, "moderate": 1.55, "veryActive": 1.725},
        "activityFactorFromWorkbook": {"moderate": amc["Z12"]},
        "maintenanceAdvice": "Establish maintenance for at least two weeks before starting a deficit or surplus.",
        "weeklyQuestions": ["Top two goals", "Supplements, travel and holiday dates, other notes", "Grade yourself (A-F, optional)"],
        "placeholdersIgnored": "Sample client values (age 37, 179 cm, 83 kg, 2125 kcal, 125 g macros) are not used as defaults.",
    }


# ======================================================================
# Report
# ======================================================================


def write_report(path, programs, issues, date_repairs, library, merges, durations, hashes, decisions):
    by_id = {e["id"]: e for e in library}
    L = []
    add = L.append
    add("# Import report\n")
    add("Generated by `tools/importer/import_programs.py`. Source workbooks are read, never modified. "
        "Coach decisions come from `tools/importer/coach_decisions.json`.\n")
    add("## Source files\n")
    add("| File | SHA-256 (first 16) |\n|---|---|")
    for f, h in hashes.items():
        add(f"| {f} | `{h[:16]}` |")

    add("\n## Programs\n")
    add("| Program | Weeks | Sessions/week | Slots | Main-lift slots | Easy/deload weeks | Session length |\n|---|---|---|---|---|---|---|")
    for p in programs:
        per = sorted({len(w["workouts"]) for w in p["weeks"]})
        slots = [s for w in p["weeks"] for wo in w["workouts"] for s in wo["slots"]]
        dl = [str(w["number"]) for w in p["weeks"] if w.get("isDeload")]
        d = durations[p["id"]]
        add(f"| {p['name']} | {len(p['weeks'])} | {'/'.join(map(str, per))} | {len(slots)} | "
            f"{sum(1 for s in slots if s.get('isMainLift'))} | {', '.join(dl) or 'none'} | {min(d)}-{max(d)} min |")

    add("\n## Works with your equipment?\n")
    add("For each equipment profile: how many exercise slots run as written, how many get an automatic swap, "
        "and how many have no stand-in (the app offers to skip those). Swaps never change the program file.\n")
    names = [pr["name"] for pr in equip.PROFILES]
    add("| Program | " + " | ".join(names) + " |\n|---|" + "---|" * len(names))
    for p in programs:
        cells = []
        for pr in equip.PROFILES:
            c = p["equipmentCoverage"][pr["id"]]
            cells.append(f"{c['asWritten']} / {c['swapped']} / **{c['unavailable']}**" if c["unavailable"] else f"{c['asWritten']} / {c['swapped']} / 0")
        add(f"| {p['name']} | " + " | ".join(cells) + " |")
    add("\nCells are *as written / swapped / no option*.\n")
    gaps = defaultdict(set)
    for p in programs:
        for pr in equip.PROFILES:
            for g in p["equipmentCoverage"][pr["id"]]["gaps"]:
                gaps[pr["name"]].add(g)
    if gaps:
        add("Exercises with no stand-in, by profile:\n")
        for prof, g in gaps.items():
            add(f"- **{prof}:** {', '.join(sorted(g))}")

    add("\n### Example swaps for the main lifts\n")
    add("| Main lift | " + " | ".join(names[1:]) + " |\n|---|" + "---|" * (len(names) - 1))
    mains = sorted({s["exerciseId"] for p in programs for w in p["weeks"] for wo in w["workouts"] for s in wo["slots"]
                    if by_id[s["exerciseId"]]["tier"] == "main"}, key=lambda i: by_id[i]["name"])
    for eid in mains:
        row = []
        for pr in equip.PROFILES[1:]:
            c, why = substitution.choose(eid, by_id, pr["equipment"])  # adult/advanced cap
            row.append("as written" if c == eid else by_id[c]["name"] if c else "—")
        add(f"| {by_id[eid]['name']} | " + " | ".join(row) + " |")

    dec = issues.of("decision")
    add(f"\n## Decisions applied ({len(dec)})\n")
    grouped = defaultdict(list)
    for i in dec:
        grouped[(i["program"], i["code"])].append(i)
    for (prog, code), items in grouped.items():
        add(f"### {prog}: {code} ({len(items)})\n")
        for i in items[:20]:
            add(f"- **{i['where']}**: {i['message']}")
        if len(items) > 20:
            add(f"- ... and {len(items) - 20} more")
        add("")
    add("### How ambiguous exercise names were read\n")
    for k, v in decisions["ambiguousNames"].items():
        if not k.startswith("_"):
            add(f"- `{k}` → {v}")

    add(f"\n## Exercise library\n")
    n_names = sum(len(v) for v in merges.values()) + sum(1 for e in library if e["usedIn"]) - len(merges)
    drafted = [e for e in library if not e["seed"]]
    add(f"- {len(library)} movements: {sum(1 for e in library if e['seed'])} from the brief's seed list, "
        f"{len(drafted)} added (cues drafted for you to review as the coach).")
    add(f"- {sum(1 for e in library if e['usedIn'])} are used by the programs; the rest exist as stand-ins "
        "(bodyweight, band, dumbbell and machine versions).")
    add(f"- Different spellings merged into one movement ({len(merges)}), so history carries across programs:\n")
    for name, spellings in sorted(merges.items()):
        add(f"  - **{name}**: {', '.join(spellings)}")

    add(f"\n## Date-corrupted rep ranges repaired ({len(date_repairs)})\n")
    summary = Counter(re.search(r"-> reps '([^']+)'", d["repair"]).group(1) for d in date_repairs)
    add("| Excel date | Repaired to | Cells |\n|---|---|---|")
    for rng, n in sorted(summary.items(), key=lambda x: [int(t) for t in x[0].split('-')]):
        m, d = rng.split("-")
        add(f"| 2021-{int(m):02d}-{int(d):02d} | `{rng}` | {n} |")
    odd = [d for d in date_repairs if "UNEXPECTED" in d["repair"]]
    add(f"\nUnexpected dates: **{len(odd)}**. Every repaired cell is listed at the end.\n")

    for sev, title in (("confirm", "Still needs your confirmation"), ("warning", "Warnings")):
        items = issues.of(sev)
        add(f"## {title} ({len(items)})\n")
        for i in items:
            add(f"- {i['program']} / {i['where']}: {i['message']}")
        if not items:
            add("None.")
        add("")

    add("## Session versions (average minutes)\n")
    add("Every session can be run in a shorter version on busy or low-energy days, and sessions over 60 min get a trim offer "
        "(pair accessories into supersets, or drop accessories from the end). Figures include warm-up and cool-down.\n")
    add("| Program | Standard | Trimmed to fit 60 | Low-energy | Express | Minimum |\n|---|---|---|---|---|---|")
    for p in programs:
        ramp = 3 if p.get("family") == "beginner-12wk" else 0
        acc = defaultdict(list)
        for w in p["weeks"]:
            for wo in w["workouts"]:
                for kind in ("standard", "low_energy", "express", "minimum"):
                    acc[kind].append(estimate_minutes(versions.version(wo, kind, by_id), ramp))
                opts = versions.trim_options(wo, by_id, extra_warmup_min=ramp)
                acc["trim"].append(min([o["minutes"] for o in opts] or [estimate_minutes(wo, ramp)]))
        avg = {k: round(sum(v) / len(v)) for k, v in acc.items()}
        add(f"| {p['name']} | {avg['standard']} | {avg['trim']} | {avg['low_energy']} | {avg['express']} | {avg['minimum']} |")
    add("")
    add("## Estimated session length\n")
    add(f"Formula: sets × ({WORK_SEC} s work + average rest) + ramp-up sets + {WARMUP_MIN} min warm-up + {COOLDOWN_MIN} min cool-down.\n")
    add("| Program | Shortest | Longest | Sessions over 60 min |\n|---|---|---|---|")
    for pid, vals in durations.items():
        add(f"| {pid} | {min(vals)} min | {max(vals)} min | {sum(1 for v in vals if v > 60)} of {len(vals)} |")

    infos = issues.of("info")
    add(f"\n## Handled automatically ({len(infos)})\n")
    for i in infos:
        add(f"- {i['program']} / {i['where']}: {i['message']}")

    add("\n## Appendix: every repaired cell\n")
    add("| Program | Row | Exercise | Repair |\n|---|---|---|---|")
    for d in date_repairs:
        add(f"| {d['program']} | {d['row']} | {d['exercise']} | {d['repair']} |")
    path.write_text("\n".join(L) + "\n")


# ======================================================================


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(HERE.parent.parent))
    args = ap.parse_args()
    root = Path(args.root)
    src_dir, out_dir = root / "Resources" / "Source", root / "Resources" / "Generated"
    out_dir.mkdir(parents=True, exist_ok=True)

    hashes = {f: hashlib.sha256((src_dir / f).read_bytes()).hexdigest() for f in FILES.values()}
    decisions = json.loads((HERE / "coach_decisions.json").read_text())
    issues, date_repairs = Issues(), []

    programs = [
        import_full_body(src_dir / FILES["full_body"], issues),
        import_upper_lower(src_dir / FILES["upper_lower"], issues),
        import_body_part(src_dir / FILES["body_part"], issues),
        import_twelve(src_dir / FILES["twelve"], issues, date_repairs),
        import_eighteen(src_dir / FILES["eighteen"], issues),
    ]
    beginner, cues = import_beginner(src_dir / FILES["beginner"], issues)
    programs += beginner
    # Questions the importer raised are answered in coach_decisions.json.
    for i in issues.items:
        if i["severity"] == "confirm":
            i["severity"] = "decision"

    apply_decisions(programs, decisions, issues)
    for p in programs:
        process_supersets(p, issues)
    fill_missing_rest(programs, issues)

    seed = json.loads((HERE / "exercise_seed.json").read_text())
    library, index = build_catalogue(seed, cues, issues)
    by_id = {e["id"]: e for e in library}
    programs += steady_programs.build(index, by_id)
    merges = resolve_exercises(programs, index, by_id, issues)
    apply_main_lift_rule(programs, decisions, by_id, issues)
    for p in programs:
        validate_common(p, issues)
        p["equipmentNeeded"], p["equipmentCoverage"] = program_equipment(p, by_id)

    durations = {}
    for p in programs:
        ramp = 3 if p.get("family") == "beginner-12wk" else 0
        vals = []
        for w in p["weeks"]:
            for wo in w["workouts"]:
                wo["estimatedMinutes"] = estimate_minutes(wo, ramp)
                vals.append(wo["estimatedMinutes"])
        durations[p["id"]] = vals

    checkin = import_checkin(src_dir / FILES["checkin"], issues)

    def dump(name, obj):
        (out_dir / name).write_text(json.dumps(obj, indent=1, ensure_ascii=False, sort_keys=False) + "\n")

    dump("programs.json", {"schemaVersion": SCHEMA_VERSION,
                           "sources": [{"file": f, "sha256": h} for f, h in hashes.items()],
                           "programs": programs})
    dump("exercise_library.json", {"schemaVersion": SCHEMA_VERSION, "patterns": library_catalogue.PATTERNS,
                                   "muscles": library_catalogue.MUSCLES, "exercises": library})
    dump("equipment.json", {"schemaVersion": SCHEMA_VERSION, "equipment": equip.EQUIPMENT,
                            "alwaysAvailable": sorted(equip.ALWAYS_AVAILABLE), "profiles": equip.PROFILES})
    dump("checkin_defaults.json", checkin)
    write_report(out_dir / "IMPORT_REPORT.md", programs, issues, date_repairs, library, merges, durations, hashes, decisions)

    print(f"programs: {len(programs)}  slots: {sum(len(wo['slots']) for p in programs for w in p['weeks'] for wo in w['workouts'])}")
    print(f"library: {len(library)} movements  merged spellings: {len(merges)}")
    print(" ".join(f"{s}: {len(issues.of(s))}" for s in ("decision", "confirm", "warning", "info")))
    for p in programs:
        print(f"  {p['id']:32s}", "  ".join(f"{k}:{v['unavailable']}" for k, v in p["equipmentCoverage"].items()))


if __name__ == "__main__":
    main()
