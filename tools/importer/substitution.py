"""Exercise substitution: the reference implementation the Swift app ports.

Two parts:

1. `rank_substitutes(entry, catalogue)` runs at import time. For every exercise
   it produces a ranked list of stand-ins (coach-curated first, then by movement
   pattern, muscles, unilateral match and difficulty). The list is stored in the
   library, so the coach can read and override it.

2. `choose(...)` and `adapt(...)` run on the phone. Given the equipment the user
   has today, pick the best available stand-in and adjust the prescription so
   it still makes sense (no %1RM on a different lift, per-side reps for
   single-side swaps, rep targets for bodyweight moves).

The original program is never edited: a swap is a per-session (or "always at
this gym") choice stored with the user's data.
"""
from __future__ import annotations

from equipment import PROFILES, missing, satisfied
from library_catalogue import NEIGHBOUR_PATTERNS

# Coach-curated swaps come first, in this order. The 28 seed exercises use the
# swaps from the brief; main lifts get the obvious equipment fallbacks.
CURATED = {
    "goblet_squat": ["leg_press", "bodyweight_squat"],
    "db_rdl": ["back_extension", "cable_pull_through"],
    "hip_thrust": ["db_glute_bridge"],
    "leg_press": ["goblet_squat", "hack_squat"],
    "reverse_lunge": ["split_squat", "step_up"],
    "db_bench_press": ["machine_chest_press", "push_up"],
    "incline_db_press": ["machine_incline_press"],
    "seated_db_shoulder_press": ["machine_shoulder_press"],
    "machine_shoulder_press": ["seated_db_shoulder_press"],
    "lat_pulldown": ["assisted_pull_up"],
    "neutral_pulldown": ["lat_pulldown"],
    "seated_cable_row": ["machine_row", "db_row"],
    "chest_supported_row": ["seated_cable_row", "db_row"],
    "seated_leg_curl": ["lying_leg_curl", "sliding_leg_curl"],
    "leg_extension": ["leg_press"],
    "standing_calf_raise": ["seated_calf_raise", "leg_press_calf_raise"],
    "hip_abduction_machine": ["banded_lateral_walk", "cable_hip_abduction"],
    "back_extension": ["db_rdl"],
    "lateral_raise": ["cable_lateral_raise", "machine_lateral_raise"],
    "triceps_pushdown": ["overhead_cable_triceps"],
    "overhead_cable_triceps": ["triceps_pushdown"],
    "face_pull": ["band_pull_apart", "reverse_pec_deck"],
    "db_curl": ["cable_curl", "ez_bar_curl"],
    "db_hammer_curl": ["cable_curl"],
    "dead_bug": ["bird_dog"],
    "plank": ["dead_bug"],
    "pallof_press": ["side_plank"],
    "farmers_carry": ["suitcase_carry"],
    # main-lift fallbacks
    "back_squat": ["hack_squat", "leg_press", "goblet_squat", "bulgarian_split_squat"],
    "front_squat": ["goblet_squat", "hack_squat", "back_squat"],
    "box_squat": ["back_squat", "goblet_squat", "leg_press"],
    "pin_squat": ["back_squat", "box_squat", "goblet_squat"],
    "bench_press": ["db_bench_press", "machine_chest_press", "floor_press", "push_up"],
    "pause_bench_press": ["bench_press", "db_bench_press", "machine_chest_press"],
    "deadlift": ["trap_bar_deadlift", "barbell_rdl", "db_deadlift", "db_rdl"],
    "barbell_rdl": ["db_rdl", "single_leg_rdl", "back_extension"],
    "ohp": ["seated_db_shoulder_press", "machine_shoulder_press", "landmine_press", "pike_push_up"],
    "pull_up": ["assisted_pull_up", "lat_pulldown", "band_pulldown"],
    "chin_up": ["assisted_pull_up", "supinated_pulldown", "band_pulldown"],
    "bent_over_row": ["chest_supported_row", "t_bar_row", "db_row"],
    "t_bar_row": ["chest_supported_row", "seated_cable_row", "db_row"],
    "dip": ["assisted_dip", "close_grip_push_up", "bench_dip"],
    "assisted_dip": ["dip", "close_grip_push_up", "bench_dip"],
    "hack_squat": ["leg_press", "back_squat", "goblet_squat"],
    "trap_bar_deadlift": ["deadlift", "db_deadlift"],
    "nordic_curl": ["glute_ham_raise", "sliding_leg_curl", "seated_leg_curl"],
    "glute_ham_raise": ["nordic_curl", "seated_leg_curl", "sliding_leg_curl"],
}

TOP_N = 12


def _jaccard(a, b):
    a, b = set(a), set(b)
    return len(a & b) / len(a | b) if a | b else 0.0


def score(src, cand, curated_rank=None):
    """Higher is a closer stand-in. 0 means not a sensible swap."""
    if cand["id"] == src["id"]:
        return 0
    if cand["pattern"] == src["pattern"]:
        s = 50
    elif cand["pattern"] in NEIGHBOUR_PATTERNS.get(src["pattern"], []):
        s = 20
    else:
        return 0
    s += 20 * _jaccard(src["primaryMuscles"], cand["primaryMuscles"])
    s += 5 * _jaccard(src["secondaryMuscles"], cand["secondaryMuscles"])
    s += 6 if cand["unilateral"] == src["unilateral"] else 0
    s += 4 if cand["tier"] == src["tier"] else 0
    s += 3 if cand["loadable"] == src["loadable"] else 0
    s -= 4 * abs(cand["difficulty"] - src["difficulty"])
    if curated_rank is not None:
        s += 40 - 4 * curated_rank
    return round(s, 1)


def rank_substitutes(src, catalogue):
    curated = CURATED.get(src["id"], [])
    ranked = []
    for cand in catalogue:
        rank = curated.index(cand["id"]) if cand["id"] in curated else None
        sc = score(src, cand, rank)
        if sc > 0:
            ranked.append({"id": cand["id"], "score": sc, "curated": rank is not None,
                           "samePattern": cand["pattern"] == src["pattern"]})
    # Curated swaps first in the coach's order, then everything else by score.
    ranked.sort(key=lambda r: (not r["curated"], curated.index(r["id"]) if r["curated"] else 0, -r["score"], r["id"]))
    top = ranked[:TOP_N]
    # Guarantee every equipment profile has an option in the list, including
    # one at beginner difficulty (2 or less), whenever any candidate exists.
    by_id = {c["id"]: c for c in catalogue}
    for prof in PROFILES:
        for cap in (3, 2):
            fits = lambda r: satisfied(by_id[r["id"]]["equipment"], prof["equipment"]) and by_id[r["id"]]["difficulty"] <= cap
            if not any(fits(r) for r in top):
                extra = next((r for r in ranked if fits(r)), None)
                if extra:
                    top.append({**extra, "fallbackFor": prof["id"]})
    return top


# ---------------------------------------------------------------- runtime


def choose(exercise_id, by_id, available, max_difficulty=3, exclude=(), slot_alternatives=()):
    """Best exercise for this slot with today's equipment.

    Returns (exercise_id, reason). The prescribed exercise wins if it fits;
    then any alternative the program itself names; then the ranked list.
    Returns (None, reason) if nothing fits, so the app can offer to skip.
    """
    src = by_id[exercise_id]
    if exercise_id not in exclude and satisfied(src["equipment"], available):
        return exercise_id, "as written"
    for alt in slot_alternatives:
        if alt in by_id and alt not in exclude and satisfied(by_id[alt]["equipment"], available):
            return alt, "alternative named in the program"
    for sub in src["substitutes"]:
        cand = by_id[sub["id"]]
        if sub["id"] in exclude or cand["difficulty"] > max_difficulty:
            continue
        if satisfied(cand["equipment"], available):
            return sub["id"], ("coach swap" if sub["curated"] else "same movement" if sub["samePattern"] else "closest movement")
    return None, f"needs {', '.join(missing(src['equipment'], available))}; no stand-in with this equipment"


def options(exercise_id, by_id, available, limit=5):
    """Every stand-in that works with today's equipment, for the swap sheet."""
    src = by_id[exercise_id]
    return [s["id"] for s in src["substitutes"] if satisfied(by_id[s["id"]]["equipment"], available)][:limit]


def adapt(slot, original, sub):
    """Adjust a slot's prescription for a substituted exercise.

    Returns a dict of changes plus human-readable notes. Loads never carry over
    between different exercises: each exercise has its own history, and the
    first session on a new one is picked by feel at the slot's target effort.
    """
    if sub["id"] == original["id"]:
        return {"notes": []}
    out = {"notes": []}
    pct = slot.get("pct1RM")
    if pct and sub.get("oneRepMaxLift") != original.get("oneRepMaxLift"):
        out["pct1RM"] = None
        eff = slot.get("effort") or {}
        target = f"RPE {eff.get('raw')}" if eff.get("type") == "rpe" else f"{eff.get('raw')} reps in reserve" if eff else "RPE 7-8"
        out["notes"].append(f"%1RM doesn't apply to {sub['name']}; choose a weight for {target}.")
    if sub["unilateral"] and not original["unilateral"]:
        out["perSide"] = True
        out["notes"].append("Do the prescribed reps on each side.")
    elif original["unilateral"] and not sub["unilateral"]:
        out["perSide"] = False
    reps = slot.get("reps") or {}
    if not sub["loadable"] and original["loadable"] and reps.get("kind") in ("fixed", "range"):
        hi = reps.get("max", reps.get("reps"))
        lo = reps.get("min", reps.get("reps"))
        if hi is not None and hi < 12:
            out["reps"] = {"kind": "range", "min": max(lo, 8), "max": max(hi + 6, 15), "raw": f"{max(lo, 8)}-{max(hi + 6, 15)}"}
            out["notes"].append("Bodyweight version: higher reps; slow the lowering to 3 seconds if it gets easy.")
    if sub["timed"] and not original["timed"]:
        out["notes"].append("Hold for time instead of reps.")
    if not out["notes"]:
        out["notes"].append(f"Start {sub['name']} at a weight that matches the target effort; it has its own history.")
    return out
