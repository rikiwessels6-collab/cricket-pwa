"""Session versions and the 60-minute trim: the reference rules the app ports.

Every program session can be run as:

  standard     the session as written
  low_energy   every exercise, at most 2 working sets, one RPE easier (or one
               more rep in reserve), same weights as last time
  express      main lifts only, at most 2 working sets, 5 min warm-up and
               3 min cool-down (about 30 min)
  minimum      the first two main lifts at 2 sets plus one core exercise,
               3 min warm-up, 2 min cool-down (about 20 min) - something is
               always better than skipping

and a session longer than the limit (60 min) gets a trim offer, shown before
it's applied:

  pair         accessories next to each other become supersets (one rest per pair)
  drop         drop accessories from the end until it fits

None of these change the program; they produce a copy of the session for today.
"""
from __future__ import annotations

import copy

WORK_SEC = 45
WARMUP_MIN = 7
COOLDOWN_MIN = 5
LIMIT_MIN = 60
# Warm-up / cool-down minutes per version (shorter versions get a shorter guided routine).
ROUTINE_MIN = {"standard": (WARMUP_MIN, COOLDOWN_MIN), "low_energy": (WARMUP_MIN, COOLDOWN_MIN),
               "express": (5, 3), "minimum": (3, 2)}
CORE_PATTERNS = {"core_flexion", "core_anti_extension", "core_anti_rotation", "core_rotation"}


def estimate_minutes(workout, extra_warmup_min=0):
    """sets x (work + average rest) + ramp-up sets + warm-up + cool-down."""
    warm, cool = workout.get("warmupMin", WARMUP_MIN), workout.get("cooldownMin", COOLDOWN_MIN)
    sec = (warm + cool + extra_warmup_min) * 60
    for s in workout["slots"]:
        sets = s["sets"]["count"] or 0
        if s["sets"].get("perSide"):
            sets *= 2
        work = WORK_SEC
        if s["reps"]["kind"] == "duration":
            work = s["reps"]["maxSec"]
        if s["reps"].get("perSide"):
            work *= 2
        rest = s["rest"] or {}
        rest_sec = ((rest.get("minSec") or 0) + (rest.get("maxSec") or 0)) / 2
        sec += sets * (work + rest_sec)
        sec += (s.get("warmupSets") or 0) * 90
    return round(sec / 60)


def _cap_sets(slot, n):
    if (slot["sets"]["count"] or 0) > n:
        slot["sets"] = {**slot["sets"], "count": n, "cappedFrom": slot["sets"]["count"]}


def _easier(slot):
    e = slot.get("effort")
    if not e or e.get("min") is None:
        return
    if e["type"] == "rpe":
        slot["effort"] = {**e, "min": max(5, e["min"] - 1), "max": max(5, e["max"] - 1), "easierBy": 1}
    else:
        slot["effort"] = {**e, "min": e["min"] + 1, "max": e["max"] + 1, "easierBy": 1}


def _strip_superset_if_alone(slots):
    groups = {}
    for s in slots:
        if "superset" in s:
            groups.setdefault(s["superset"]["group"], []).append(s)
    for members in groups.values():
        if len(members) == 1:
            members[0].pop("superset")
            members[0]["rest"] = {"raw": "2min", "minSec": 90, "maxSec": 120, "note": "partner removed"}


def version(workout, kind, library):
    """Return a copy of `workout` for the chosen version."""
    w = copy.deepcopy(workout)
    w["version"] = kind
    w["warmupMin"], w["cooldownMin"] = ROUTINE_MIN[kind]
    if kind == "standard":
        return w
    if kind == "low_energy":
        for s in w["slots"]:
            _cap_sets(s, 2)
            _easier(s)
            s["loadRule"] = "same as last time"
        return w
    mains = [s for s in w["slots"] if s.get("isMainLift")]
    if not mains:  # sessions with no main lift: use the first two compound movements
        mains = [s for s in w["slots"] if library[s["exerciseId"]]["tier"] != "accessory"][:2] or w["slots"][:2]
    if kind == "express":
        keep = mains
    elif kind == "minimum":
        core = next((s for s in w["slots"] if library[s["exerciseId"]]["pattern"] in CORE_PATTERNS), None)
        keep = mains[:2] + ([core] if core else [])
        if not core:
            w["addCore"] = "dead_bug"
    else:
        raise ValueError(kind)
    w["slots"] = [copy.deepcopy(s) for s in w["slots"] if any(s is k for k in keep)]
    for s in w["slots"]:
        _cap_sets(s, 2)
    _strip_superset_if_alone(w["slots"])
    if w.get("addCore"):
        w["slots"].append({"exerciseId": "dead_bug", "exercise": "Dead bug", "sets": {"count": 2},
                           "reps": {"kind": "fixed", "reps": 8, "perSide": True, "raw": "8 each side"},
                           "rest": {"minSec": 45, "maxSec": 45, "raw": "45sec"}, "effort": None, "added": True})
    return w


def trim_options(workout, library, limit=LIMIT_MIN, extra_warmup_min=0):
    """Ways to bring a long session under `limit` minutes. Empty if it already fits."""
    before = estimate_minutes(workout, extra_warmup_min)
    if before <= limit:
        return []
    out = []

    # 1. Pair neighbouring accessories into supersets.
    paired = copy.deepcopy(workout)
    free = [s for s in paired["slots"] if "superset" not in s and not s.get("isMainLift")
            and library[s["exerciseId"]]["tier"] == "accessory"]
    pairs, i = 0, 0
    while i + 1 < len(free):
        a, b = free[i], free[i + 1]
        if paired["slots"].index(b) == paired["slots"].index(a) + 1:
            gid = f"T{pairs + 1}"
            a["superset"] = {"group": gid, "order": 1, "added": True}
            b["superset"] = {"group": gid, "order": 2, "added": True}
            a["rest"] = {"raw": "0", "minSec": 0, "maxSec": 0}
            pairs += 1
            i += 2
        else:
            i += 1
    if pairs:
        out.append({"kind": "pair", "minutes": estimate_minutes(paired, extra_warmup_min), "pairs": pairs, "workout": paired})

    # 2. Drop accessories from the end until it fits.
    dropped = copy.deepcopy(workout)
    removed = []
    while estimate_minutes(dropped, extra_warmup_min) > limit:
        idx = next((j for j in range(len(dropped["slots"]) - 1, -1, -1)
                    if not dropped["slots"][j].get("isMainLift")), None)
        if idx is None:
            break
        removed.append(dropped["slots"].pop(idx)["exercise"])
    _strip_superset_if_alone(dropped["slots"])
    if removed:
        out.append({"kind": "drop", "minutes": estimate_minutes(dropped, extra_warmup_min), "removed": removed, "workout": dropped})
    return out
