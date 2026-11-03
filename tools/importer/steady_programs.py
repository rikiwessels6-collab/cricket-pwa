"""The five Steady Strength programs from the implementation guide.

Source: "Steady Strength - Complete Muscle-Building Program Library and App
Implementation Guide", v1.0, 3 November 2026 (Resources/Source/
Steady_Strength_Program_Guide.pdf). Sections 3 (templates), 4 (12-week
progression) and 5 (approved substitutions).

Per the guide's hand-off (section 10) the templates are base sessions and the
12 weeks are dynamic: every week repeats the same exercises, and the week's
phase changes the target effort (RIR) and which recovery options are offered.
Progression comes from actual performance, not from pre-written loads.

Reps are written in the importer's rep syntax ("8-10 each side", "30-45 sec").
"""
from __future__ import annotations

from parsing import exercise_key, parse_effort, parse_reps, parse_rest, parse_sets

GUIDE = "Steady_Strength_Program_Guide.pdf"

# (name in the guide, sets, reps)
PROGRAMS = [
    {
        "id": "ss-strength-foundations", "name": "Strength Foundations", "level": "beginner",
        "days": 3, "split": "Full body", "goals": ["strength", "muscle", "general health"],
        "description": "Three full-body sessions a week to learn the main lifts and build a base.",
        "workouts": [
            ("Full Body A", False, [("Goblet squat", 3, "8-12"), ("Dumbbell bench press", 3, "8-12"),
                                    ("Seated cable row", 3, "10-12"), ("Dumbbell Romanian deadlift", 2, "10-12"),
                                    ("Plank", 3, "30-45 sec")]),
            ("Full Body B", False, [("Leg press", 3, "10-12"), ("Lat pulldown", 3, "8-12"),
                                    ("Dumbbell shoulder press", 2, "8-12"), ("Glute bridge", 3, "10-15"),
                                    ("Dead bug", 2, "10 each side")]),
            ("Full Body C", False, [("Split squat", 3, "8-10 each side"), ("Incline dumbbell press", 3, "8-12"),
                                    ("Chest-supported row", 3, "8-12"), ("Leg curl", 2, "10-15"),
                                    ("Lateral raise", 2, "12-15")]),
        ],
    },
    {
        "id": "ss-build-and-grow", "name": "Build & Grow", "level": "beginner-intermediate",
        "days": 4, "split": "Upper/lower", "goals": ["muscle", "strength"],
        "description": "Four days, upper and lower, for steady muscle and strength gains.",
        "workouts": [
            ("Upper A", False, [("Bench press", 3, "6-10"), ("Chest-supported row", 3, "8-12"),
                                ("Incline dumbbell press", 3, "8-12"), ("Lat pulldown", 3, "10-12"),
                                ("Lateral raise", 3, "12-15"), ("Triceps pressdown", 2, "10-15")]),
            ("Lower A", False, [("Squat", 3, "6-10"), ("Romanian deadlift", 3, "8-10"), ("Leg press", 3, "10-12"),
                                ("Leg curl", 3, "10-15"), ("Calf raise", 3, "12-15")]),
            ("Upper B", False, [("Overhead press", 3, "6-10"), ("Assisted pull-up", 3, "8-12"),
                                ("Machine chest press", 3, "10-12"), ("Seated cable row", 3, "10-12"),
                                ("Biceps curl", 3, "10-15"), ("Rear-delt fly", 3, "12-15")]),
            ("Lower B", False, [("Hip thrust", 3, "8-12"), ("Hack squat", 3, "8-12"),
                                ("Bulgarian split squat", 2, "10 each side"), ("Seated leg curl", 3, "10-15"),
                                ("Calf raise", 3, "12-15")]),
        ],
    },
    {
        "id": "ss-lower-body-focus", "name": "Lower Emphasis", "master": "Lower Body Focus", "level": "intermediate",
        "days": 4, "split": "Lower-body emphasis", "goals": ["glutes", "legs", "muscle"],
        "description": "Four days with extra glute and leg work, plus two upper-body days.",
        "workouts": [
            ("Lower A - Glutes and Quads", False, [("Hip thrust", 4, "8-12"), ("Squat", 3, "8-10"),
                                                   ("Bulgarian split squat", 3, "10 each side"),
                                                   ("Leg extension", 2, "12-15"), ("Hip abduction", 2, "15-20")]),
            ("Upper A", False, [("Lat pulldown", 3, "8-12"), ("Incline dumbbell press", 3, "8-12"),
                                ("Cable row", 3, "10-12"), ("Shoulder press", 2, "10-12"), ("Lateral raise", 2, "12-15")]),
            ("Lower B - Glutes and Hamstrings", False, [("Romanian deadlift", 3, "8-10"), ("Leg press", 3, "10-12"),
                                                        ("Glute bridge", 3, "10-12"), ("Leg curl", 3, "10-15"),
                                                        ("Cable kickback", 2, "12-15")]),
            ("Upper B", False, [("Chest press", 3, "8-12"), ("Chest-supported row", 3, "8-12"),
                                ("Assisted pull-up", 2, "8-12"), ("Rear-delt fly", 2, "12-15"),
                                ("Biceps curl", 2, "10-15"), ("Triceps pressdown", 2, "10-15")]),
        ],
    },
    {
        "id": "ss-muscle-builder-pro", "name": "Muscle Builder", "master": "Muscle Builder Pro", "level": "intermediate-advanced",
        "days": 5, "split": "Push/pull/legs + upper/lower", "goals": ["muscle", "strength"],
        "description": "Five days: push, pull and legs, then upper and lower, for experienced lifters.",
        "workouts": [
            ("Push", False, [("Bench press", 3, "6-8"), ("Incline dumbbell press", 3, "8-12"), ("Shoulder press", 3, "8-10"),
                             ("Cable fly", 2, "12-15"), ("Lateral raise", 3, "12-20"), ("Triceps extension", 3, "10-15")]),
            ("Pull", False, [("Weighted or assisted pull-up", 3, "6-10"), ("Chest-supported row", 3, "8-12"),
                             ("Lat pulldown", 2, "10-12"), ("Reverse pec deck", 3, "12-15"),
                             ("Incline curl", 3, "10-12"), ("Hammer curl", 2, "12-15")]),
            ("Legs", False, [("Squat", 3, "6-10"), ("Romanian deadlift", 3, "8-10"), ("Leg press", 3, "10-12"),
                             ("Leg curl", 3, "10-15"), ("Calf raise", 3, "12-15")]),
            ("Upper", False, [("Incline machine press", 3, "8-12"), ("Seated cable row", 3, "8-12"),
                              ("Machine chest press", 2, "10-12"), ("One-arm lat pulldown", 2, "10-12"),
                              ("Lateral raise", 3, "12-20"), ("Cable curl", 2, "12-15")]),
            ("Lower", False, [("Hack squat", 3, "8-12"), ("Hip thrust", 3, "8-12"), ("Split squat", 2, "10 each side"),
                              ("Seated leg curl", 3, "10-15"), ("Leg extension", 2, "12-15"), ("Calf raise", 3, "12-15")]),
        ],
    },
    {
        "id": "ss-strong-for-life", "name": "Strong for Life", "level": "all levels",
        "days": 2, "split": "Full body", "goals": ["general health", "strength", "longevity"],
        "description": "Two full-body sessions a week, with an optional third, for lasting strength.",
        "workouts": [
            ("Full Body A", False, [("Goblet squat", 3, "8-12"), ("Machine chest press", 3, "8-12"),
                                    ("Seated row", 3, "10-12"), ("Dumbbell Romanian deadlift", 2, "10-12"),
                                    ("Farmer carry", 3, "30 sec")]),
            ("Full Body B", False, [("Leg press", 3, "10-12"), ("Lat pulldown", 3, "8-12"), ("Hip thrust", 3, "10-12"),
                                    ("Dumbbell shoulder press", 2, "8-12"), ("Pallof press", 2, "12 each side")]),
            ("Full Body C", True, [("Step-up", 2, "10 each side"), ("Incline push-up", 3, "8-12"),
                                   ("Cable row", 3, "10-12"), ("Leg curl", 2, "12-15"), ("Calf raise", 2, "12-15")]),
        ],
    },
]

# Guide name -> catalogue id, where the name isn't already a catalogue alias.
NAME_TO_ID = {
    "squat": "back_squat", "bench press": "bench_press", "overhead press": "ohp",
    "shoulder press": "seated_db_shoulder_press", "dumbbell shoulder press": "seated_db_shoulder_press",
    "glute bridge": "db_glute_bridge", "leg curl": "seated_leg_curl", "calf raise": "standing_calf_raise",
    "biceps curl": "db_curl", "incline curl": "incline_db_curl", "rear-delt fly": "reverse_pec_deck",
    "cable row": "seated_cable_row", "seated row": "seated_cable_row", "chest press": "machine_chest_press",
    "incline machine press": "machine_incline_press", "one-arm lat pulldown": "single_arm_pulldown",
    "triceps extension": "overhead_cable_triceps", "hip abduction": "hip_abduction_machine",
    "weighted or assisted pull-up": "assisted_pull_up", "farmer carry": "farmers_carry", "cable kickback": "cable_glute_kickback",
    "incline push-up": "incline_push_up", "split squat": "split_squat",
}
# A slot may name its own fallback (the guide's "weighted or assisted pull-up").
SLOT_ALTERNATIVES = {"weighted or assisted pull-up": ["pull_up"]}

# Audit section 6: names the master leaves ambiguous get a default pick that the coach must confirm.
AMBIGUOUS_NAMES = {"squat", "calf raise", "leg curl", "chest press", "shoulder press", "lateral raise", "cable row",
                   "seated row", "biceps curl", "triceps extension", "weighted or assisted pull-up"}
# Audit: calf raise is standing in lower sessions A and seated in B.
SLOT_OVERRIDES = {
    ("ss-build-and-grow", "Lower B", "calf raise"): "seated_calf_raise",
    ("ss-muscle-builder-pro", "Lower", "calf raise"): "seated_calf_raise",
}

# Section 4: the 12-week progression, as dynamic week modifiers.
PHASES = [
    (range(1, 2), "Baseline and build", "3",
     "Establish technique and baseline loads, about 3 reps in reserve."),
    (range(2, 4), "Baseline and build", "1-2",
     "Add reps or load while working towards about 1-2 reps in reserve."),
    (range(4, 5), "Optional lower-fatigue week", "2-3",
     "If fatigue or performance warrants it, use the Low-energy version (fewer sets, no failure). Otherwise train as normal."),
    (range(5, 8), "Progressive growth", "1-2",
     "Keep double-progressing. Add 1-2 sets a week to a priority muscle only if performance and recovery support it."),
    (range(8, 9), "Recovery review", "2-3",
     "Check soreness, sleep, joint comfort and consistency. Use the Low-energy version if you need it."),
    (range(9, 12), "Performance block", "1-2",
     "Continue gradual overload. Advanced lifters may take safe isolation sets to 0-1 reps in reserve; it is optional."),
    (range(12, 13), "Reassessment", "2",
     "Repeat your usual working sets at a submaximal effort, review your goals and choose the next block. No 1RM test."),
]
LOW_FATIGUE_WEEKS = {4, 8}


def phase_for(week):
    for weeks, name, rir, note in PHASES:
        if week in weeks:
            return name, rir, note
    raise ValueError(week)


def rest_for(tier, pattern):
    """Guide rule: 2-3 min for demanding multi-joint lifts, 60-120 s for isolation work."""
    if tier in ("main", "compound") and not pattern.startswith("core") and pattern != "carry":
        return "2-3min"
    return "1-2min"


def build(index, by_id):
    """Expand the five templates into 12-week programs in the importer's JSON shape."""
    programs = []
    for spec in PROGRAMS:
        weeks = []
        for w in range(1, 13):
            phase, rir, note = phase_for(w)
            workouts = []
            for pos, (name, optional, rows) in enumerate(spec["workouts"], start=1):
                slots = []
                for order, (ex_name, sets, reps) in enumerate(rows, start=1):
                    key = exercise_key(ex_name)
                    eid = SLOT_OVERRIDES.get((spec["id"], name, key)) or NAME_TO_ID.get(key) or index.get(key)
                    if eid is None or eid not in by_id:
                        raise ValueError(f"{spec['id']}: '{ex_name}' is not in the exercise catalogue")
                    ex = by_id[eid]
                    rest = rest_for(ex["tier"], ex["pattern"])
                    slots.append({
                        "exercise": ex["name"], "exerciseKey": exercise_key(ex["name"]), "label": ex_name,
                        "sets": parse_sets(sets), "reps": parse_reps(reps),
                        "effort": parse_effort(rir, "rir"), "rest": parse_rest(rest),
                        "notes": note if (order == 1 and pos == 1) else None,
                        "source": {"sheet": GUIDE, "row": order},
                        "exerciseId": eid, "alternativeIds": SLOT_ALTERNATIVES.get(key, []),
                        "order": order,
                        **({"needsCoachConfirmation": True} if key in AMBIGUOUS_NAMES else {}),
                    })
                workouts.append({"rawName": name, "name": name, "position": pos, "optional": optional, "slots": slots})
            weeks.append({"number": w, "label": f"Week {w}", "phase": phase, "isDeload": False,
                          "lowFatigueOptional": w in LOW_FATIGUE_WEEKS, "phaseNote": note, "workouts": workouts})
        programs.append({
            "id": spec["id"], "name": spec["name"], "masterName": spec["master"] if "master" in spec else spec["name"],
            "author": "Steady Strength", "family": "steady-strength",
            "intensityType": "rir", "unit": "kg", "weeks": weeks, "status": "complete",
            "experienceLevel": spec["level"], "defaultDaysPerWeek": spec["days"], "split": spec["split"],
            "goalTags": spec["goals"], "description": spec["description"], "durationWeeks": 12,
            "maxSwapDifficulty": 2 if spec["level"].startswith("beginner") else 3,
            "progression": "double progression: reach the top of the rep range on every set at the target RIR, "
                           "then add the smallest practical load",
            "source": {"file": GUIDE, "sheet": "section 3"},
        })
    return programs
