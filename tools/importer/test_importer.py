"""Run: python3 -m unittest discover -s tools/importer"""
import datetime as dt
import json
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from parsing import (exercise_key, one_rm_lift, parse_effort, parse_pct_1rm, parse_reps,  # noqa: E402
                     parse_rest, parse_sets, split_exercise_label)
from import_programs import macro_timing  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
GEN = ROOT / "Resources" / "Generated"


class RepParsing(unittest.TestCase):
    def test_date_corruption_is_repaired_and_flagged(self):
        for d, lo, hi in [((2021, 4, 6), 4, 6), ((2021, 12, 15), 12, 15), ((2021, 8, 10), 8, 10),
                          ((2021, 10, 12), 10, 12), ((2021, 6, 8), 6, 8)]:
            r = parse_reps(dt.datetime(*d))
            self.assertEqual((r["kind"], r["min"], r["max"]), ("range", lo, hi))
            self.assertIn("repairedFrom", r)
            self.assertNotIn("UNEXPECTED", r["repairedFrom"])

    def test_unexpected_dates_are_marked(self):
        self.assertIn("UNEXPECTED", parse_reps(dt.datetime(2022, 12, 15))["repairedFrom"])
        self.assertIn("UNEXPECTED", parse_reps(dt.datetime(2021, 6, 4))["repairedFrom"])

    def test_scheme_kinds(self):
        cases = {
            9: ("fixed", {"reps": 9}), 6.0: ("fixed", {"reps": 6}), "10": ("fixed", {"reps": 10}),
            "10-12": ("range", {"min": 10, "max": 12}),
            "11,9,7,5": ("perSet", {"reps": [11, 9, 7, 5]}),
            "10+": ("plus", {"reps": 10}),
            '"AMRAP"': ("amrap", {}), "FAILURE": ("amrap", {}),
            "10/15": ("segments", {"reps": [10, 15]}), "7/7/7": ("segments", {"reps": [7, 7, 7]}),
            "8-10(+4+4)": ("restPause", {"min": 8, "max": 10, "extras": [4, 4]}),
            "10(+3+3+3)": ("restPause", {"min": 10, "max": 10, "extras": [3, 3, 3]}),
            "20sec": ("duration", {"minSec": 20, "maxSec": 20}), "20-40 sec": ("duration", {"minSec": 20, "maxSec": 40}),
            "45 s": ("duration", {"minSec": 45, "maxSec": 45}), "20s": ("duration", {"minSec": 20, "maxSec": 20}),
            "30 m": ("distance", {"minM": 30, "maxM": 30}), "30-40 m": ("distance", {"minM": 30, "maxM": 40}),
        }
        for raw, (kind, fields) in cases.items():
            r = parse_reps(raw)
            self.assertEqual(r["kind"], kind, raw)
            for k, v in fields.items():
                self.assertEqual(r[k], v, raw)

    def test_each_side(self):
        for raw in ("8 each side", "10-12each", "8each"):
            self.assertTrue(parse_reps(raw)["perSide"], raw)
        self.assertEqual(parse_reps("8-10 each side")["max"], 10)
        self.assertFalse(parse_reps("10-12")["perSide"])

    def test_unknown_is_never_guessed(self):
        self.assertEqual(parse_reps("lots")["kind"], "unknown")
        self.assertEqual(parse_reps("12-8")["kind"], "unknown")


class OtherCells(unittest.TestCase):
    def test_sets(self):
        self.assertEqual(parse_sets(3.0)["count"], 3)
        self.assertEqual(parse_sets("2each"), {"raw": "2each", "count": 2, "perSide": True})
        self.assertIsNone(parse_sets(None)["count"])

    def test_rest(self):
        self.assertEqual(parse_rest("3min")["minSec"], 180)
        self.assertEqual((parse_rest("3-4 min")["minSec"], parse_rest("3-4 min")["maxSec"]), (180, 240))
        self.assertEqual(parse_rest("60sec")["maxSec"], 60)
        self.assertEqual(parse_rest("3MIN")["maxSec"], 180)
        self.assertEqual(parse_rest("0 min")["maxSec"], 0)
        self.assertIsNone(parse_rest(None))
        self.assertIsNone(parse_rest("N/A")["minSec"])

    def test_effort(self):
        self.assertEqual(parse_effort("6-7", "rpe")["max"], 7)
        self.assertEqual(parse_effort("1", "rir")["min"], 1)
        self.assertIsNone(parse_effort("N/A", "rir"))

    def test_pct(self):
        self.assertEqual(parse_pct_1rm("82.5-87.5% ")["min"], 0.825)
        self.assertEqual(parse_pct_1rm(0.8)["max"], 0.8)
        self.assertIsNone(parse_pct_1rm("N/A"))

    def test_labels(self):
        p = split_exercise_label("A1: Hammer curl")
        self.assertEqual((p["name"], p["supersetGroup"], p["supersetOrder"]), ("Hammer curl", "A", 1))
        p = split_exercise_label("Front squat [or box squat]")
        self.assertEqual((p["name"], p["alternatives"]), ("Front squat", ["box squat"]))
        self.assertEqual(exercise_key("  Goblet   SQUAT "), "goblet squat")

    def test_one_rm_mapping(self):
        self.assertEqual(one_rm_lift("Pin squat"), "squat")
        self.assertEqual(one_rm_lift('6" Block pull (Deadlift)'), "deadlift")
        self.assertEqual(one_rm_lift("Barbell overhead press"), "ohp")
        self.assertEqual(one_rm_lift("Pause barbell bench press"), "bench")
        self.assertIsNone(one_rm_lift("Hack squat machine row".replace("squat", "")))


class MacroTiming(unittest.TestCase):
    def test_reproduces_workbook(self):
        meals = ["Pre-Training", "Post-Training", "Breakfast", "Lunch", "Dinner"]
        out = macro_timing({"protein": 125, "carbs": 125, "fat": 125, "fibre": 29.75}, 0.65, 0.15, meals)
        self.assertAlmostEqual(out[0]["kcal"], 346.875)
        self.assertAlmostEqual(out[0]["carbs"], 40.625)
        self.assertAlmostEqual(out[2]["fat"], 35.4166667, places=5)
        self.assertAlmostEqual(sum(m["kcal"] for m in out), 2125)

    def test_rest_day_splits_evenly(self):
        out = macro_timing({"protein": 125, "carbs": 125, "fat": 125, "fibre": 29.75}, 0.65, 0.15,
                           ["Breakfast", "Lunch", "Dinner"])
        self.assertAlmostEqual(out[0]["kcal"], 708.3333333, places=5)


class GeneratedOutput(unittest.TestCase):
    """Whole-file checks against the real workbooks (regenerates first)."""

    @classmethod
    def setUpClass(cls):
        subprocess.run([sys.executable, str(Path(__file__).with_name("import_programs.py")), "--root", str(ROOT)],
                       check=True, capture_output=True)
        cls.programs = {p["id"]: p for p in json.loads((GEN / "programs.json").read_text())["programs"]}

    def slots(self, pid):
        return [s for w in self.programs[pid]["weeks"] for wo in w["workouts"] for s in wo["slots"]]

    def test_shapes(self):
        expect = {"rw-full-body-3day-8wk": (8, {3}), "rw-upper-lower-4day-8wk": (8, {4}),
                  "rw-body-part-split-5day-8wk": (8, {5}), "rw-12-week": (12, {5, 6}),
                  "rw-intermediate-18wk": (18, {5}), "beginner-12wk-option-a": (12, {2}),
                  "beginner-12wk-option-b": (12, {3}), "beginner-12wk-option-c": (12, {4}),
                  "beginner-12wk-option-d": (12, {5})}
        for pid, (weeks, per) in expect.items():
            p = self.programs[pid]
            self.assertEqual(len(p["weeks"]), weeks, pid)
            self.assertEqual([w["number"] for w in p["weeks"]], list(range(1, weeks + 1)), pid)
            self.assertEqual({len(w["workouts"]) for w in p["weeks"]}, per, pid)

    def test_no_date_values_survive(self):
        for pid in self.programs:
            for s in self.slots(pid):
                self.assertNotRegex(s["reps"]["raw"], r"^\d{4}-\d{2}-\d{2}$", (pid, s["source"]))

    def test_twelve_week_repairs(self):
        repaired = [s for s in self.slots("rw-12-week") if "repairedFrom" in s["reps"]]
        self.assertEqual(len(repaired), 141)
        self.assertEqual({s["reps"]["raw"] for s in repaired}, {"4-6", "6-8", "8-10", "10-12", "12-15"})

    def test_sample_1rms_never_used(self):
        text = (GEN / "programs.json").read_text()
        for sample_load in ('"100-105"', '"72.5-77.5"', '"107.5"'):
            self.assertNotIn(sample_load, text)

    def test_twelve_week_week9_and_deload(self):
        weeks = self.programs["rw-12-week"]["weeks"]
        self.assertTrue(weeks[7]["isDeload"])
        self.assertEqual(weeks[8]["workouts"][0]["name"], "Full Body 1")

    def test_upper_lower_positional_names(self):
        for w in self.programs["rw-upper-lower-4day-8wk"]["weeks"]:
            self.assertEqual([wo["name"] for wo in w["workouts"]],
                             ["Lower Body #1", "Upper Body #1", "Lower Body #2", "Upper Body #2"])
            self.assertTrue(all(len(wo["slots"]) == 7 for wo in w["workouts"]))

    def test_supersets_rest_after_last_member(self):
        for pid in ("rw-12-week", "rw-intermediate-18wk"):
            for w in self.programs[pid]["weeks"]:
                for wo in w["workouts"]:
                    groups = {}
                    for s in wo["slots"]:
                        if "superset" in s:
                            groups.setdefault(s["superset"]["group"], []).append(s)
                    for members in groups.values():
                        for m in members[:-1]:
                            self.assertEqual(m["rest"]["maxSec"], 0, (pid, m["source"]))

    def test_beginner_main_lifts_and_option_b(self):
        b = self.programs["beginner-12wk-option-b"]
        self.assertEqual([wo["name"] for wo in b["weeks"][0]["workouts"]], ["Full Body A", "Full Body B", "Full Body C"])
        first = b["weeks"][0]["workouts"][0]["slots"][0]
        self.assertEqual((first["exercise"], first["isMainLift"]), ("GOBLET SQUAT", True))
        self.assertEqual(b["weeks"][7]["phase"], "Easy week")

    def test_beginner_exercises_all_in_seed_library(self):
        lib = json.loads((GEN / "exercise_library.json").read_text())["exercises"]
        seed = {e["id"] for e in lib if e["seed"]}
        for pid in ("beginner-12wk-option-a", "beginner-12wk-option-b", "beginner-12wk-option-c", "beginner-12wk-option-d"):
            missing = {s["exerciseId"] for s in self.slots(pid)} - seed
            self.assertEqual(missing, set(), pid)

    def test_no_video_urls_invented(self):
        lib = json.loads((GEN / "exercise_library.json").read_text())["exercises"]
        self.assertTrue(all(e["videoSources"] == [] for e in lib))

    def test_deterministic(self):
        before = (GEN / "programs.json").read_bytes()
        subprocess.run([sys.executable, str(Path(__file__).with_name("import_programs.py")), "--root", str(ROOT)],
                       check=True, capture_output=True)
        self.assertEqual(before, (GEN / "programs.json").read_bytes())


class LibraryAndSwaps(unittest.TestCase):
    """Exercise library, equipment adaptation and coach decisions."""

    @classmethod
    def setUpClass(cls):
        GeneratedOutput.setUpClass.__func__(cls)
        cls.lib = {e["id"]: e for e in json.loads((GEN / "exercise_library.json").read_text())["exercises"]}
        import equipment
        cls.profiles = {p["id"]: p["equipment"] for p in equipment.PROFILES}

    def all_slots(self):
        return [(p, s) for p in self.programs.values() for w in p["weeks"] for wo in w["workouts"] for s in wo["slots"]]

    def test_every_slot_resolves_to_library(self):
        for p, s in self.all_slots():
            self.assertIn(s["exerciseId"], self.lib, (p["id"], s["exercise"]))

    def test_every_slot_has_an_option_in_every_profile(self):
        import substitution
        for p, s in self.all_slots():
            for prof, kit in self.profiles.items():
                choice, why = substitution.choose(s["exerciseId"], self.lib, kit,
                                                  max_difficulty=p.get("maxSwapDifficulty", 3),
                                                  slot_alternatives=s.get("alternativeIds", []))
                self.assertIsNotNone(choice, (p["id"], s["exercise"], prof, why))

    def test_beginner_swaps_stay_beginner_friendly(self):
        import substitution
        for p, s in self.all_slots():
            if p.get("family") != "beginner-12wk":
                continue
            for kit in self.profiles.values():
                choice, _ = substitution.choose(s["exerciseId"], self.lib, kit, max_difficulty=2)
                if choice != s["exerciseId"]:
                    self.assertLessEqual(self.lib[choice]["difficulty"], 2)

    def test_curated_order_wins(self):
        import substitution
        self.assertEqual(substitution.choose("trap_bar_deadlift", self.lib, self.profiles["basic_gym"])[0], "deadlift")
        self.assertEqual(substitution.choose("back_squat", self.lib, self.profiles["hotel_gym"])[0], "goblet_squat")
        self.assertEqual(substitution.choose("bench_press", self.lib, self.profiles["travel"])[0], "push_up")
        self.assertEqual(substitution.choose("goblet_squat", self.lib, self.profiles["full_gym"])[0], "goblet_squat")

    def test_unavailable_exercise_can_be_excluded(self):
        import substitution
        choice, why = substitution.choose("leg_press", self.lib, self.profiles["full_gym"], exclude={"leg_press"})
        self.assertEqual((choice, why), ("goblet_squat", "coach swap"))

    def test_box_jumps_need_a_real_box(self):
        import substitution
        self.assertEqual(substitution.choose("box_jump", self.lib, self.profiles["travel"])[0], "squat_jump")

    def test_adapt_drops_percent_and_handles_sides_and_bodyweight(self):
        import substitution
        slot = {"pct1RM": {"min": 0.8, "max": 0.8, "lift": "squat"}, "effort": {"type": "rpe", "raw": "8"},
                "reps": {"kind": "fixed", "reps": 5, "raw": "5"}}
        a = substitution.adapt(slot, self.lib["back_squat"], self.lib["bulgarian_split_squat"])
        self.assertIsNone(a["pct1RM"])
        self.assertTrue(a["perSide"])
        a = substitution.adapt(slot, self.lib["back_squat"], self.lib["bodyweight_squat"])
        self.assertEqual((a["reps"]["min"], a["reps"]["max"]), (8, 15))
        a = substitution.adapt(slot, self.lib["back_squat"], self.lib["pin_squat"])
        self.assertNotIn("pct1RM", a)  # same 1RM lift: %1RM still valid

    def test_decisions_applied(self):
        s18 = [s for w in self.programs["rw-intermediate-18wk"]["weeks"] for wo in w["workouts"] for s in wo["slots"]]
        self.assertEqual(sum(1 for s in s18 if "correctedFrom" in (s["effort"] or {})), 15)
        self.assertTrue(all((s["effort"] or {}).get("max", 0) <= 4 for s in s18))
        self.assertTrue(all(s["sets"]["count"] for s in s18))
        self.assertTrue(all(s["rest"] is not None for s in s18))
        twelve = {s["source"]["row"]: s for w in self.programs["rw-12-week"]["weeks"] for wo in w["workouts"] for s in wo["slots"]}
        for calf, shrug in ((48, 49), (124, 125), (200, 201)):
            self.assertEqual(twelve[calf]["superset"]["group"], twelve[shrug]["superset"]["group"])
            self.assertEqual(twelve[calf]["rest"]["maxSec"], 0)
            self.assertGreater(twelve[shrug]["rest"]["maxSec"], 0)

    def test_main_lift_rule(self):
        fb = self.programs["rw-full-body-3day-8wk"]["weeks"][0]["workouts"][0]["slots"]
        self.assertTrue(fb[0]["isMainLift"])        # back squat, 3 min
        self.assertFalse(fb[-1]["isMainLift"])      # calf raise, 1 min

    def test_every_library_entry_is_complete(self):
        for e in self.lib.values():
            self.assertTrue(e["cues"] and e["primaryMuscles"] and e["pattern"], e["id"])
            self.assertEqual(e["videoSources"], [])


class SessionVersions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        LibraryAndSwaps.setUpClass.__func__(cls)
        import versions
        cls.v = versions
        cls.fb_a = cls.programs["beginner-12wk-option-b"]["weeks"][4]["workouts"][0]   # week 5, Full Body A
        cls.long = max((wo for w in cls.programs["rw-12-week"]["weeks"] for wo in w["workouts"]),
                       key=lambda wo: wo["estimatedMinutes"])

    def test_standard_is_unchanged(self):
        self.assertEqual(self.v.version(self.fb_a, "standard", self.lib)["slots"], self.fb_a["slots"])

    def test_low_energy_caps_sets_and_eases_effort(self):
        low = self.v.version(self.fb_a, "low_energy", self.lib)
        self.assertEqual(len(low["slots"]), len(self.fb_a["slots"]))
        self.assertTrue(all(s["sets"]["count"] <= 2 for s in low["slots"]))
        self.assertEqual(low["slots"][0]["effort"]["max"], self.fb_a["slots"][0]["effort"]["max"] - 1)

    def test_express_is_main_lifts_at_two_sets(self):
        ex = self.v.version(self.fb_a, "express", self.lib)
        self.assertTrue(ex["slots"] and all(s["isMainLift"] and s["sets"]["count"] <= 2 for s in ex["slots"]))
        self.assertLessEqual(self.v.estimate_minutes(ex, 3), 35)

    def test_minimum_is_two_mains_plus_core(self):
        m = self.v.version(self.fb_a, "minimum", self.lib)
        self.assertEqual(len(m["slots"]), 3)
        self.assertEqual(self.lib[m["slots"][-1]["exerciseId"]]["pattern"][:4], "core")
        self.assertLessEqual(self.v.estimate_minutes(m, 3), 25)

    def test_versions_never_modify_the_program(self):
        before = json.dumps(self.fb_a, sort_keys=True)
        for kind in ("low_energy", "express", "minimum"):
            self.v.version(self.fb_a, kind, self.lib)
        self.v.trim_options(self.long, self.lib)
        self.assertEqual(before, json.dumps(self.fb_a, sort_keys=True))

    def test_trim_offers_a_shorter_session(self):
        opts = self.v.trim_options(self.long, self.lib)
        self.assertTrue(opts)
        self.assertTrue(all(o["minutes"] < self.long["estimatedMinutes"] for o in opts))
        drop = next(o for o in opts if o["kind"] == "drop")
        self.assertTrue(all(s.get("isMainLift") or s in drop["workout"]["slots"] for s in drop["workout"]["slots"]))
        self.assertEqual(self.v.trim_options(self.fb_a, self.lib), [])  # already under 60


if __name__ == "__main__":
    unittest.main()
