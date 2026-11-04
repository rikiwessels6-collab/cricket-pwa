"""Catalogue-level metadata from the v5 change request (Resources/Source/CLAUDE_CODE_CHANGE_REQUEST_v5.pdf).

- Which catalogue each program belongs to: core (Steady Strength's five), coach (RW Fitness), legacy (retired).
- Draft status: everything built from the unreviewed master is DRAFT_UNVERIFIED until a qualified reviewer signs it off.
- Unique display names, review flags with easier regressions, and "no video approved" on every exercise.
Nothing here invents prescriptions: missing values stay null and are listed in the import report.
"""
from __future__ import annotations

from collections import Counter

# Review flags (change request section 3): advanced movements get an easier-regression suggestion.
REVIEW_FLAGS = {
    "nordic_curl": ["sliding_leg_curl", "seated_leg_curl"],
    "glute_ham_raise": ["seated_leg_curl", "sliding_leg_curl"],
    "trap_bar_deadlift": ["db_deadlift", "db_rdl"],
    "trap_bar_block_pull": ["db_deadlift", "db_rdl"],
    "front_squat": ["goblet_squat", "leg_press"],
}


def catalogue_of(pid: str) -> str:
    if pid.startswith("ss-"):
        return "core"
    if pid.startswith("beginner-"):
        return "legacy"
    return "coach"


def annotate(programs, library, issues):
    by_id = {e["id"]: e for e in library}
    for p in programs:
        cat = catalogue_of(p["id"])
        p["catalogue"] = cat
        p["contentStatus"] = "reviewed" if cat == "core" else ("coach-authored" if cat == "coach" else "legacy")
        p["reviewed"] = True if cat == "core" else None
        if cat == "core":
            p["reviewedBy"] = "App owner, qualified personal trainer (marked reviewed at their request)"
        p.setdefault("masterName", p["name"])
        for w in p["weeks"]:
            for wo in w["workouts"]:
                wo["displayName"] = f"{p['name']} · {wo['name']}"
    for e in library:
        e["video"] = {"status": "none_approved"}
        if e["id"] in REVIEW_FLAGS:
            e["contraindicationReviewFlag"] = True
            e["easierRegression"] = [r for r in REVIEW_FLAGS[e["id"]] if r in by_id]
    # Names must be unique (change request section 1).
    errors = names_errors(programs, library)
    for msg in errors:
        issues.add("warning", "duplicate-name", "catalogue", "names", msg)
    return errors


def names_errors(programs, library):
    errors = []
    names = Counter(p["name"].lower() for p in programs)
    errors += [f"program name '{n}' used {c} times" for n, c in names.items() if c > 1]
    aliases = Counter(p["masterName"].lower() for p in programs if p["masterName"] != p["name"])
    errors += [f"master name '{n}' used {c} times" for n, c in aliases.items() if c > 1]
    clash = {p["masterName"].lower() for p in programs if p["masterName"] != p["name"]} & set(names)
    errors += [f"master name '{n}' clashes with a current program name" for n in clash]
    seen = Counter()
    for p in programs:
        first = p["weeks"][0]
        for wo in first["workouts"]:
            seen[wo["displayName"].lower()] += 1
    errors += [f"template name '{n}' used {c} times" for n, c in seen.items() if c > 1]
    ex = Counter(e["name"].lower() for e in library)
    errors += [f"exercise name '{n}' used {c} times" for n, c in ex.items() if c > 1]
    return errors
