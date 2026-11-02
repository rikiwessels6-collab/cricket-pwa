"""Cell-level parsers shared by every program importer.

Each parser takes the raw cell value (as openpyxl returns it from the cached
values) and returns a structured dict that always keeps the original text in
`raw`. Parsers never guess silently: anything they cannot read comes back with
kind "unknown" so the validator can flag it.
"""
from __future__ import annotations

import datetime as _dt
import re

# Excel turned rep ranges such as "4-6" into dates in the 12-week file.
# Only year-2021 dates were produced that way, so anything else is suspicious.
CORRUPTION_YEAR = 2021


def raw_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    if isinstance(value, (_dt.datetime, _dt.date)):
        return value.isoformat()[:10]
    return str(value).strip()


def num(s: str) -> float | int:
    f = float(s)
    return int(f) if f.is_integer() else f


# ---------------------------------------------------------------- reps


def repair_date_reps(value):
    """Return ("m-d", note) if `value` is a date Excel made from a rep range."""
    if isinstance(value, (_dt.datetime, _dt.date)):
        text = f"{value.month}-{value.day}"
        note = f"date {value.isoformat()[:10]} -> reps '{text}'"
        if value.year != CORRUPTION_YEAR or value.month >= value.day:
            note += " (UNEXPECTED: not a 2021 low-high range, check by hand)"
        return text, note
    return None, None


_RANGE = r"(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)"


def parse_reps(value) -> dict:
    """Parse the Reps / Duration column into a structured scheme.

    Kinds: fixed, range, perSet, amrap, plus, duration, distance,
    segments (drop sets, 21s, "5/10"), restPause, unknown.
    Every result has `raw` and `perSide` (for "each" / "each side").
    """
    repaired, note = repair_date_reps(value)
    text = repaired if repaired is not None else raw_text(value)
    out: dict = {"raw": raw_text(value)}
    if note:
        out["repairedFrom"] = note
        out["raw"] = text
    t = text.strip().strip('"').strip()
    low = t.lower()

    per_side = bool(re.search(r"each(\s*side)?$", low))
    if per_side:
        low = re.sub(r"\s*each(\s*side)?$", "", low).strip()
    out["perSide"] = per_side

    if low in ("amrap", "failure"):
        return {**out, "kind": "amrap"}

    # Durations: "20sec", "20-40 sec", "30-45 sec", "20s", "45 s"
    m = re.fullmatch(rf"(?:{_RANGE}|(\d+))\s*(sec|s)", low)
    if m:
        lo, hi = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(3))
        return {**out, "kind": "duration", "minSec": num(lo), "maxSec": num(hi)}

    # Distances: "30 m", "30-40 m"
    m = re.fullmatch(rf"(?:{_RANGE}|(\d+))\s*m", low)
    if m:
        lo, hi = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(3))
        return {**out, "kind": "distance", "minM": num(lo), "maxM": num(hi)}

    # Rest-pause / myo-reps: "8-10(+4+4)", "10(+3+3+3)"
    m = re.fullmatch(rf"(?:{_RANGE}|(\d+))\s*\(((?:\+\d+)+)\)", low)
    if m:
        lo, hi = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(3))
        extras = [int(x) for x in re.findall(r"\d+", m.group(4))]
        return {**out, "kind": "restPause", "min": num(lo), "max": num(hi), "extras": extras}

    # Descending per-set list: "11,9,7" / "11,9,7,5"
    if re.fullmatch(r"\d+(\s*,\s*\d+)+", low):
        return {**out, "kind": "perSet", "reps": [int(x) for x in low.split(",")]}

    # Segments within one set: drop sets "10/15", "12/20", 21s "7/7/7", "5/10"
    if re.fullmatch(r"\d+(\s*/\s*\d+)+", low):
        return {**out, "kind": "segments", "reps": [int(x) for x in low.split("/")]}

    # AMRAP-style plus: "10+"
    m = re.fullmatch(r"(\d+)\s*\+", low)
    if m:
        return {**out, "kind": "plus", "reps": int(m.group(1))}

    m = re.fullmatch(_RANGE, low)
    if m:
        lo, hi = num(m.group(1)), num(m.group(2))
        if lo > hi:
            return {**out, "kind": "unknown", "why": "range low > high"}
        return {**out, "kind": "range", "min": lo, "max": hi}

    m = re.fullmatch(r"\d+(?:\.0)?", low)
    if m:
        return {**out, "kind": "fixed", "reps": int(float(low))}

    return {**out, "kind": "unknown"}


# ---------------------------------------------------------------- sets


def parse_sets(value) -> dict:
    """Working sets: 3, 3.0, "2each" (2 sets per side)."""
    t = raw_text(value).lower()
    m = re.fullmatch(r"(\d+)\s*(each)?", t)
    if not m:
        return {"raw": raw_text(value), "count": None}
    return {"raw": raw_text(value), "count": int(m.group(1)), "perSide": bool(m.group(2))}


# ---------------------------------------------------------------- rest


def parse_rest(value) -> dict | None:
    """'3min', '3-4 min', '1-2min', '0min', '60sec', '45sec' -> seconds."""
    t = raw_text(value).lower().replace(" ", "")
    if not t:
        return None
    m = re.fullmatch(rf"(?:{_RANGE}|(\d+(?:\.\d+)?))(min|sec|s)", t)
    if not m:
        return {"raw": raw_text(value), "minSec": None, "maxSec": None}
    lo, hi = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(3))
    mult = 60 if m.group(4) == "min" else 1
    return {"raw": raw_text(value), "minSec": int(float(lo) * mult), "maxSec": int(float(hi) * mult)}


# ---------------------------------------------------------------- intensity


def parse_effort(value, kind: str) -> dict | None:
    """RPE or RIR: 7, '7', '6-7', 'N/A'."""
    t = raw_text(value)
    if not t or t.upper() == "N/A":
        return None
    m = re.fullmatch(rf"{_RANGE}|(\d+(?:\.\d+)?)", t)
    if not m:
        return {"type": kind, "raw": t, "min": None, "max": None}
    lo, hi = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(3))
    return {"type": kind, "raw": t, "min": num(lo), "max": num(hi)}


def parse_pct_1rm(value) -> dict | None:
    """'82.5-87.5% ', '72.5%', 0.8, 'N/A' -> fractions."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return {"raw": raw_text(value), "min": round(float(value), 4), "max": round(float(value), 4)}
    t = str(value).strip()
    if not t or t.upper() == "N/A":
        return None
    m = re.fullmatch(rf"(?:{_RANGE}|(\d+(?:\.\d+)?))\s*%", t)
    if not m:
        return {"raw": t, "min": None, "max": None}
    lo, hi = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(3))
    return {"raw": t, "min": round(float(lo) / 100, 4), "max": round(float(hi) / 100, 4)}


# ---------------------------------------------------------------- names

_SUPERSET_PREFIX = re.compile(r"^([A-Z])(\d)\s*:\s*(.+)$")
_ALT = re.compile(r"\s*\[or ([^\]]+)\]\s*")


def split_exercise_label(label: str) -> dict:
    """'A1: Hammer curl' -> group A, order 1. 'Front squat [or box squat]' -> alternatives."""
    out: dict = {"label": label.strip()}
    name = label.strip()
    m = _SUPERSET_PREFIX.match(name)
    if m:
        out["supersetGroup"], out["supersetOrder"] = m.group(1), int(m.group(2))
        name = m.group(3).strip()
    alts = _ALT.findall(name)
    if alts:
        out["alternatives"] = [a.strip() for a in alts]
        name = _ALT.sub(" ", name).strip()
    out["name"] = name
    return out


def exercise_key(name: str) -> str:
    """Case- and whitespace-insensitive key used to match library entries."""
    return re.sub(r"\s+", " ", name.strip().lower())


# Lift that a %1RM prescription is calculated from. Variations use the parent
# lift's 1RM; every non-identity mapping is listed in the report for review.
ONE_RM_LIFTS = ("squat", "bench", "deadlift", "ohp")


def one_rm_lift(name: str) -> str | None:
    n = name.lower()
    if "overhead press" in n or n == "ohp":
        return "ohp"
    if "bench" in n:
        return "bench"
    if "deadlift" in n or "block pull" in n:
        return "deadlift"
    if "squat" in n:
        return "squat"
    return None
