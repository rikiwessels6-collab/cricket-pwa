"""Equipment vocabulary and the equipment profiles the app offers.

Requirements in the catalogue are a list of items that must ALL be present;
an item written "a/b" is satisfied by either. Bodyweight, floor space, a mat
and a towel are assumed to be available everywhere.
"""

EQUIPMENT = {
    # free weights
    "barbell": "Barbell and plates",
    "rack": "Squat rack or power rack (with safety pins)",
    "ez_bar": "EZ curl bar",
    "trap_bar": "Trap (hex) bar",
    "landmine": "Landmine attachment (or barbell wedged in a corner)",
    "plates": "Weight plates",
    "dumbbells": "Dumbbells",
    "kettlebell": "Kettlebell",
    # benches and boxes
    "bench": "Flat bench",
    "adj_bench": "Adjustable (incline) bench",
    "box": "Step or sturdy bench to step onto",
    "plyo_box": "Plyo box rated for jumping",
    # stations
    "cable": "Cable station (adjustable pulley)",
    "lat_pulldown": "Lat pulldown station",
    "pullup_bar": "Pull-up bar",
    "dip_bars": "Dip bars (or parallel bars)",
    "assist_machine": "Assisted pull-up / dip machine",
    "t_bar": "T-bar row (or landmine with handle)",
    # machines
    "leg_press": "Leg press",
    "hack_squat": "Hack squat machine",
    "leg_curl": "Leg curl machine (seated or lying)",
    "leg_ext": "Leg extension machine",
    "abductor": "Hip abduction machine",
    "calf_machine": "Standing calf raise machine (or a step plus dumbbells)",
    "seated_calf": "Seated calf raise machine",
    "chest_press": "Chest press machine (flat or incline)",
    "shoulder_press_machine": "Shoulder press machine",
    "row_machine": "Seated row machine (plate or pin loaded)",
    "pec_deck": "Pec deck / rear delt fly machine",
    "back_ext": "45-degree back extension bench",
    "ghr": "Glute-ham raise bench",
    # small kit
    "bands": "Resistance bands (loop and long bands)",
    "sliders": "Sliders (or a towel on a smooth floor)",
}

ALWAYS_AVAILABLE = {"bodyweight", "mat", "towel"}

_GYM = set(EQUIPMENT) - {"sliders"}

PROFILES = [
    {
        "id": "full_gym", "name": "Full gym",
        "description": "A commercial gym with free weights, cables and machines.",
        "equipment": sorted(_GYM | {"sliders"}),
    },
    {
        "id": "basic_gym", "name": "Basic gym",
        "description": "Racks, barbells, dumbbells, benches and a cable stack, but few machines.",
        "equipment": sorted({"barbell", "rack", "ez_bar", "plates", "dumbbells", "kettlebell", "bench", "adj_bench",
                             "box", "plyo_box", "cable", "lat_pulldown", "pullup_bar", "dip_bars", "bands", "landmine"}),
    },
    {
        "id": "hotel_gym", "name": "Hotel gym",
        "description": "Dumbbells, an adjustable bench and usually one cable machine.",
        "equipment": sorted({"dumbbells", "adj_bench", "bench", "cable", "bands", "box"}),
    },
    {
        "id": "home_dumbbells", "name": "Home: dumbbells and bench",
        "description": "Adjustable dumbbells, an incline bench, bands and a doorway pull-up bar.",
        "equipment": sorted({"dumbbells", "adj_bench", "bench", "bands", "pullup_bar", "box", "sliders"}),
    },
    {
        "id": "travel", "name": "Travel: bodyweight and bands",
        "description": "A set of resistance bands and whatever furniture the room has.",
        "equipment": sorted({"bands", "sliders", "box"}),
    },
]


def satisfied(requirements, available):
    """True if every requirement is met by `available` (plus the always-available items)."""
    have = set(available) | ALWAYS_AVAILABLE
    return all(any(opt in have for opt in item.split("/")) for item in requirements)


def missing(requirements, available):
    have = set(available) | ALWAYS_AVAILABLE
    return [item for item in requirements if not any(opt in have for opt in item.split("/"))]
