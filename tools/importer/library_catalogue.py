"""The exercise catalogue: one entry per distinct movement.

Every exercise name used in any program must resolve to an entry here, either
by its own name or through `aliases` (spellings, typos and labels used in the
workbooks). Aliased names share one exercise history, so progress carries
across programs.

Line format (fields separated by "|"; no field may contain one):

  id | Name | pattern | tier | equipment | primary muscles | secondary muscles | flags | form cue | aliases

  tier       P = main lift, S = secondary compound, A = accessory
  equipment  items joined with "+", alternatives with "/", "-" for none
  flags      U unilateral · N no external load (bodyweight/band) · T timed hold
             d1/d2/d3 difficulty · 1rm:<lift> shares a 1RM for %-based loading
  aliases    lower-case names from the workbooks, separated by ";"

Muscles come from a fixed list (MUSCLES) so weekly volume can be totalled.
Cues are short, plain instructions; the seed entries keep the coach's wording.
"""

MUSCLES = ["chest", "upper_chest", "lats", "upper_back", "front_delts", "side_delts", "rear_delts", "traps",
           "biceps", "triceps", "forearms", "quads", "hamstrings", "glutes", "glute_med", "adductors",
           "calves", "abs", "obliques", "lower_back"]

PATTERNS = {
    "squat": "Squat (both legs, knee dominant)",
    "single_leg": "Single-leg / lunge",
    "hinge": "Hip hinge",
    "glute_bridge": "Hip thrust / bridge",
    "knee_flexion": "Leg curl (knee flexion)",
    "knee_extension": "Leg extension (knee extension)",
    "calf": "Calf raise",
    "hip_abduction": "Hip abduction",
    "horizontal_push": "Horizontal press",
    "incline_push": "Incline press",
    "vertical_push": "Overhead press",
    "dip": "Dip",
    "chest_fly": "Chest fly",
    "horizontal_pull": "Row",
    "vertical_pull": "Pulldown / pull-up",
    "straight_arm_pull": "Straight-arm pulldown / pullover",
    "elbow_flexion": "Biceps curl",
    "elbow_extension": "Triceps extension",
    "lateral_raise": "Lateral raise",
    "rear_delt": "Rear delt / face pull",
    "shrug": "Shrug",
    "scapular": "Shoulder blade control",
    "core_flexion": "Core: crunch / leg raise",
    "core_anti_extension": "Core: plank / dead bug",
    "core_anti_rotation": "Core: anti-rotation",
    "core_rotation": "Core: rotation",
    "carry": "Loaded carry / hold",
    "plyometric": "Jump / plyometric",
}

# Patterns that can stand in for each other when nothing in the same pattern
# fits the available equipment (score is lower than a same-pattern swap).
NEIGHBOUR_PATTERNS = {
    "squat": ["single_leg"], "single_leg": ["squat"],
    "hinge": ["glute_bridge"], "glute_bridge": ["hinge"],
    "horizontal_push": ["incline_push", "dip"], "incline_push": ["horizontal_push"],
    "dip": ["horizontal_push", "elbow_extension"], "vertical_push": ["incline_push"],
    "vertical_pull": ["straight_arm_pull", "horizontal_pull"], "straight_arm_pull": ["vertical_pull"],
    "horizontal_pull": ["vertical_pull"], "chest_fly": ["horizontal_push"],
    "knee_extension": ["squat"], "knee_flexion": ["hinge"],
    "rear_delt": ["scapular"], "scapular": ["rear_delt"], "shrug": ["carry"],
    "core_flexion": ["core_anti_extension"], "core_anti_extension": ["core_flexion", "core_anti_rotation"],
    "core_anti_rotation": ["core_anti_extension", "core_rotation"], "core_rotation": ["core_anti_rotation"],
    "carry": ["shrug", "core_anti_rotation"], "plyometric": ["squat"],
}

CATALOGUE = r"""
# ---------------------------------------------------------------- squat
back_squat | Back squat | squat | P | barbell+rack | quads,glutes | adductors,lower_back | d2 1rm:squat | Bar on upper back, brace, sit down between your hips, knees track over toes, drive up through mid-foot. | barbell back squat;barbell squat
box_squat | Box squat | squat | P | barbell+rack+box | glutes,quads | hamstrings,lower_back | d2 1rm:squat | Sit back to the box with control, pause without relaxing, drive up hard. | barbell box squat;barbell box back squat
pin_squat | Pin squat | squat | P | barbell+rack | quads,glutes | adductors | d3 1rm:squat | Lower onto pins set near parallel, dead stop, then drive up without bouncing. |
front_squat | Front squat | squat | P | barbell+rack | quads | glutes,abs | d3 | Bar on front of shoulders, elbows high, stay upright and sit straight down. | barbell front squat
goblet_squat | Goblet squat | squat | S | dumbbells/kettlebell | quads,glutes | abs | d1 | Dumbbell at chest, sit down between your hips, heels flat, chest tall. |
heel_elevated_squat | Heel-elevated squat | squat | S | dumbbells/kettlebell | quads | glutes | d1 | Heels on a plate or wedge, hold a dumbbell at your chest, knees travel forward, sit deep. | heel elevated squat
leg_press | Leg press | squat | P | leg_press | quads,glutes | adductors | d1 | Feet mid-platform, lower to about 90 degrees at the knee, do not lock out. |
single_leg_press | Single-leg leg press | single_leg | S | leg_press | quads,glutes | | U d1 | One foot centred on the platform, lower under control, keep hips down on the seat. | unilateral leg press
hack_squat | Hack squat | squat | P | hack_squat | quads | glutes | d1 | Back flat on the pad, feet shoulder width, lower deep and drive through the whole foot. |
sissy_squat | Sissy squat | knee_extension | A | - | quads | | N d2 | Hold a support, rise onto toes, lean back as knees travel forward, keep hips extended. |
bodyweight_squat | Bodyweight squat | squat | A | - | quads,glutes | | N d1 | Arms forward for balance, sit to a comfortable depth, stand tall. |
# ---------------------------------------------------------------- single leg
reverse_lunge | Reverse lunge | single_leg | P | - | quads,glutes | adductors | U d1 | Step back, front heel down. Hold a support in weeks 1-4. |
walking_lunge | Dumbbell walking lunge | single_leg | S | dumbbells | quads,glutes | adductors | U d2 | Long steps, back knee kisses the floor, push through the front heel. |
split_squat | Dumbbell split squat | single_leg | S | dumbbells | quads,glutes | | U d1 | Staggered stance, drop the back knee straight down, front heel stays planted. | db split squat;db split squats;db spilt squat;split leg squat
bulgarian_split_squat | Bulgarian split squat | single_leg | S | bench/box | quads,glutes | adductors | U d2 | Back foot on a bench, sink straight down, front knee tracks over toes. Start with the weaker leg. | rear leg elevated split squat;rear elevated split squat;rear elevated squat
step_up | Step-up | single_leg | S | box | quads,glutes | | U d1 | Whole foot on the box, drive through the heel, control the step down. | step ups;db step ups
lateral_step_up | Lateral step-up | single_leg | A | box | quads,glute_med | | U d1 | Stand side-on to the box, push up through the top leg, lower slowly. | lateral step up;lateral step ups
single_leg_squat | Single-leg squat to box | single_leg | S | - | quads,glutes | glute_med | U N d3 | Sit back to a box on one leg with control, stand without pushing off the other foot. | s leg squat;single leg squat
# ---------------------------------------------------------------- hinge
deadlift | Deadlift | hinge | P | barbell | glutes,hamstrings,lower_back | upper_back,forearms | d2 1rm:deadlift | Bar over mid-foot, brace, push the floor away, hips and shoulders rise together. |
reset_deadlift | Reset deadlift | hinge | P | barbell | glutes,hamstrings,lower_back | forearms | d2 1rm:deadlift | Stand fully and reset your setup between every rep; perfect position each pull. |
opposite_stance_deadlift | Opposite-stance deadlift | hinge | P | barbell | glutes,hamstrings,adductors | lower_back | d3 1rm:deadlift | Pull with the stance you don't normally use (sumo if you pull conventional). | opposite stance deadlift
block_pull | Block pull | hinge | P | barbell+plates | glutes,lower_back,upper_back | hamstrings,forearms | d2 1rm:deadlift | Bar raised on blocks to the height given, same setup as a deadlift, lock out hard. | 1" block pull;2" block pull;4" block pull (deadlift);6" block pull (deadlift)
rack_pull | Rack pull | hinge | P | barbell+rack | glutes,lower_back,upper_back | traps,forearms | d2 | Pins at knee height, brace, drive hips through to lock out. |
trap_bar_deadlift | Trap bar deadlift | hinge | P | trap_bar | quads,glutes,hamstrings | traps | d1 | Stand in the centre, handles by your sides, push the floor away. |
trap_bar_block_pull | Trap bar block pull | hinge | P | trap_bar+plates | glutes,quads | traps | d1 | Trap bar raised on blocks, push the floor away and stand tall. | block trap bar deadlift;trap bar block deadlift
barbell_rdl | Romanian deadlift | hinge | P | barbell | hamstrings,glutes | lower_back | d2 | Soft knees, push hips back, bar slides down your thighs, back flat, stop at a hamstring stretch. | romanian deadlift;barbell rdl;bb rdl
db_rdl | Dumbbell Romanian deadlift | hinge | P | dumbbells | hamstrings,glutes | lower_back | d1 | Soft knees, push hips back, dumbbells slide down thighs, back flat. | db rdl
db_deadlift | Dumbbell deadlift | hinge | S | dumbbells | glutes,hamstrings,quads | | d1 | Dumbbells by your sides, sit hips back, stand tall with a flat back. | db deadlift
single_leg_rdl | Single-leg Romanian deadlift | hinge | S | dumbbells/cable/kettlebell | hamstrings,glutes | glute_med | U d2 | Hinge on one leg, back leg stays in line with your body, hips square to the floor. | s leg cable rdl
cable_pull_through | Cable pull-through | hinge | A | cable | glutes,hamstrings | | d1 | Face away from the cable, hinge back, then squeeze glutes to stand tall. | cable pull through
kb_swing | Kettlebell swing | hinge | S | kettlebell/dumbbells | glutes,hamstrings | lower_back | d2 | Hike the bell back, snap hips forward, arms just guide the weight. |
good_morning_band | Banded good morning | hinge | A | bands | hamstrings,glutes | lower_back | N d1 | Band under feet and behind neck, push hips back with a flat back, squeeze glutes to stand. |
back_extension | Back extension | hinge | A | back_ext | glutes,hamstrings,lower_back | | d1 | Hinge from the hips, stop when body is in a straight line. | prisoner back extension;glute extension;glute extensions
glute_ham_raise | Glute-ham raise | knee_flexion | S | ghr | hamstrings | glutes,calves | d3 | Knees on the pad, body straight, lower under control and curl back up with the hamstrings. | glute-ham raise
nordic_curl | Nordic ham curl | knee_flexion | S | - | hamstrings | | N d3 | Ankles anchored, lower as slowly as you can with hips straight, push off the floor to return. | nordic ham curl
# ---------------------------------------------------------------- glute bridge
hip_thrust | Barbell hip thrust | glute_bridge | P | barbell+bench | glutes | hamstrings | d2 | Upper back on bench, ribs down, squeeze glutes at top, pause 1 second. | hip thrust
single_leg_hip_thrust | Single-leg hip thrust | glute_bridge | S | bench | glutes | hamstrings,glute_med | U d2 | Upper back on bench, one foot down, drive through the heel and squeeze at the top. | dumbbell single-leg hip thrust
machine_hip_thrust | Machine hip thrust | glute_bridge | S | glute_machine | glutes | hamstrings | d1 | Pad across the hips, upper back on the support, drive up and squeeze for one second. |
db_glute_bridge | Dumbbell glute bridge | glute_bridge | S | dumbbells | glutes | hamstrings | d1 | Lie on the floor, dumbbell on hips, drive through heels and squeeze at the top. |
band_glute_bridge | Banded glute bridge | glute_bridge | A | bands | glutes | glute_med | N d1 | Loop band above knees, push knees out, drive hips up and pause. |
# ---------------------------------------------------------------- knee flexion / extension
seated_leg_curl | Seated leg curl | knee_flexion | A | leg_curl | hamstrings | | d1 | Slow lower, 2 seconds. | leg curl;leg curl (choice)
lying_leg_curl | Lying leg curl | knee_flexion | A | leg_curl | hamstrings | calves | d1 | Hips pressed into the pad, curl heels to glutes, lower for 2 seconds. |
single_leg_curl | Single-leg leg curl | knee_flexion | A | leg_curl | hamstrings | | U d1 | One leg at a time, keep hips down, slow lower. | single-leg lying leg curl;unilateral leg curl (choice)
sliding_leg_curl | Sliding leg curl | knee_flexion | A | sliders | hamstrings | glutes | N d2 | Bridge up, slide heels away slowly, curl them back in without dropping hips. |
stability_ball_leg_curl | Stability-ball leg curl | knee_flexion | A | stability_ball | hamstrings | glutes | N d2 | Heels on the ball, bridge up, curl the ball in without letting the hips drop. |
band_leg_curl | Banded leg curl | knee_flexion | A | bands | hamstrings | | N d1 | Band anchored low, lie face down, curl heel to glute and lower slowly. |
leg_extension | Leg extension | knee_extension | A | leg_ext | quads | | d1 | Pause at the top. Use lighter weight if knees complain. | leg extensions;eccentric-accentuated leg extension
single_leg_extension | Single-leg leg extension | knee_extension | A | leg_ext | quads | | U d1 | One leg at a time, squeeze at the top, lower slowly. | single-leg leg extension
band_leg_extension | Banded leg extension | knee_extension | A | bands | quads | | N d1 | Band anchored behind, straighten the knee fully and squeeze the quad. |
# ---------------------------------------------------------------- calves / abduction
standing_calf_raise | Standing calf raise | calf | A | calf_machine/dumbbells | calves | | d1 | Full stretch at the bottom, pause at the top. | enhanced-eccentric calf raise
single_leg_calf_raise | Single-leg calf raise | calf | A | box | calves | | U N d1 | Ball of one foot on a step, full stretch, rise as high as you can, pause. | unilateral standing calf raise
seated_calf_raise | Seated calf raise | calf | A | seated_calf | calves | | d1 | Knees under the pad, full stretch, pause at the top. |
leg_press_calf_raise | Calf raise on the leg press | calf | A | leg_press | calves | | d1 | Balls of feet on the platform edge, knees soft, press through the big toe. |
cable_glute_kickback | Cable glute kickback | glute_bridge | A | cable | glutes | | U d1 | Ankle strap on, slight forward lean, kick back and squeeze the glute without arching your back. |
hip_abduction_machine | Machine hip abduction | hip_abduction | A | abductor | glute_med | glutes | d1 | Controlled, no bouncing. | machine seated hip abduction;hip abduction
cable_hip_abduction | Cable hip abduction | hip_abduction | A | cable | glute_med | | U d1 | Ankle strap on, stand tall, sweep the leg out without leaning. |
banded_lateral_walk | Banded lateral walk | hip_abduction | A | bands | glute_med | glutes | N d1 | Band above knees, half squat, step sideways keeping tension. |
side_lying_leg_raise | Side-lying leg raise | hip_abduction | A | - | glute_med | | U N d1 | Lie on your side, top leg straight and slightly back, lift slowly. |
# ---------------------------------------------------------------- horizontal push
bench_press | Barbell bench press | horizontal_push | P | barbell+bench+rack | chest,triceps | front_delts | d2 1rm:bench | Shoulder blades pinned, feet planted, lower to mid-chest, press up and slightly back. | bench press;barbell bench press (back off);barbell bench press (rpe 9.5 amrap)
pause_bench_press | Pause bench press | horizontal_push | P | barbell+bench+rack | chest,triceps | front_delts | d2 1rm:bench | Lower to the chest, hold a full one-second pause, press without bouncing. | pause barbell bench press
close_grip_bench | Close-grip bench press | horizontal_push | S | barbell+bench+rack | triceps,chest | front_delts | d2 1rm:bench | Hands just inside shoulder width, elbows tucked, touch lower chest. | close-grip bench press
larsen_press | Larsen press | horizontal_push | S | barbell+bench+rack | chest,triceps | front_delts | d3 1rm:bench | Legs straight out off the floor, no leg drive, stay tight on the bench. |
pin_press | Pin press | horizontal_push | S | barbell+bench+rack | chest,triceps | | d2 1rm:bench | Bar starts on pins just above the chest, press from a dead stop. |
floor_press | Floor press | horizontal_push | S | barbell+rack/dumbbells | triceps,chest | | d1 | Lie on the floor, lower until upper arms touch the floor, pause, press. |
db_floor_press | Dumbbell floor press | horizontal_push | S | dumbbells | chest,triceps | | d1 | Lie on the floor, elbows about 45 degrees, pause when arms touch, press. |
db_bench_press | Dumbbell bench press | horizontal_push | P | dumbbells+bench | chest,triceps | front_delts | d1 | Shoulder blades pinned back, forearms vertical, lower under control. | flat db press;db press
single_arm_chest_press | Single-arm chest press | horizontal_push | S | cable/dumbbells+bench | chest,triceps | obliques | U d2 | Press one side at a time, don't let the torso twist. | s arm chest press;single arm chest press
machine_chest_press | Machine chest press | horizontal_push | S | chest_press | chest,triceps | front_delts | d1 | Handles at mid-chest height, press without shrugging, slow return. | plate loaded press
push_up | Push-up | horizontal_push | S | - | chest,triceps | front_delts,abs | N d1 | Hands under shoulders, body in one line, chest to the floor. Elevate hands to make it easier. | press up
incline_push_up | Incline push-up | horizontal_push | A | bench/box | chest,triceps | front_delts | N d1 | Hands on a bench, body in one straight line, lower the chest to the edge. |
deficit_push_up | Deficit push-up | horizontal_push | S | - | chest,triceps | front_delts | N d2 | Hands on plates or books, lower the chest below hand height. | deficit push-up
decline_push_up | Decline push-up | incline_push | S | box/bench | upper_chest,triceps | front_delts | N d2 | Feet raised on a bench, body straight, lower the chest between your hands. | decline press up
band_push_up | Band-resisted push-up | horizontal_push | S | bands | chest,triceps | front_delts | N d2 | Band across your back held under each hand, full push-up against the band. | banded press up;banded push ups
close_grip_push_up | Close-grip push-up | dip | A | - | triceps,chest | | N d2 | Hands under the chest, elbows brush your ribs. | close grip press up;close grip press ups
# ---------------------------------------------------------------- incline / vertical push
incline_db_press | Incline dumbbell press | incline_push | P | dumbbells+adj_bench | upper_chest,triceps | front_delts | d1 | Bench at 30 degrees, press up and slightly in. | dumbbell incline press;db incline press;incline db press
pause_incline_db_press | Pause incline dumbbell press | incline_push | S | dumbbells+adj_bench | upper_chest,triceps | front_delts | d2 | 3-second pause at the bottom, sink the dumbbells as low as is comfortable. | pause db incline press
close_grip_incline_bench | Close-grip incline bench press | incline_push | S | barbell+adj_bench+rack | upper_chest,triceps | front_delts | d2 | Incline bench, hands shoulder width, elbows tucked. | close-grip incline barbell bench press
machine_incline_press | Incline machine press | incline_push | S | chest_press | upper_chest,triceps | front_delts | d1 | Seat so handles are at upper-chest height, press up and slightly in. | machine incline chest press
landmine_press | Landmine press | incline_push | S | landmine | upper_chest,front_delts | triceps | U d1 | Hold the bar end at the shoulder, press up and forward, ribs down. |
ohp | Barbell overhead press | vertical_push | P | barbell+rack | front_delts,triceps | side_delts,abs | d2 1rm:ohp | Squeeze glutes, ribs down, press the bar up past your face and finish over mid-foot. | overhead press;barbell overhead press;standing barbell shoulder press
seated_db_shoulder_press | Seated dumbbell shoulder press | vertical_push | P | dumbbells+adj_bench | front_delts,triceps | side_delts | d1 | Ribs down, press to just short of lockout. | dumbbell seated shoulder press;seated db press;seated db shoulder press;seated shoulder press;seated neutral grip db press
standing_db_press | Standing dumbbell shoulder press | vertical_push | S | dumbbells | front_delts,triceps | side_delts,abs | d2 | Staggered or square stance, ribs down, press without leaning back. | standing neutral db press;b stance db press
half_kneeling_db_press | Half-kneeling dumbbell press | vertical_push | S | dumbbells | front_delts,triceps | abs,obliques | U d2 | One knee down, squeeze that glute, press one dumbbell overhead without leaning. | half kneeling db press;s arm press
machine_shoulder_press | Machine shoulder press | vertical_push | P | shoulder_press_machine | front_delts,triceps | side_delts | d1 | Seat so handles start at shoulder height. |
pike_push_up | Pike push-up | vertical_push | S | - | front_delts,triceps | | N d2 | Hips high, head travels forward of the hands, press back up. |
band_overhead_press | Banded overhead press | vertical_push | A | bands | front_delts,triceps | | N d1 | Stand on the band, press overhead, ribs down. |
# ---------------------------------------------------------------- dips / fly
dip | Dip | dip | S | dip_bars | chest,triceps | front_delts | d2 | Lean slightly forward, lower until shoulders are just below elbows, press up. | dips
assisted_dip | Assisted dip | dip | S | assist_machine | chest,triceps | front_delts | d1 | Kneel on the pad, lower under control, press up without shrugging. |
bench_dip | Bench dip | dip | A | bench/box | triceps | front_delts | N d1 | Hands on a bench behind you, elbows point back, lower to 90 degrees. |
cable_fly | Cable fly | chest_fly | A | cable | chest | front_delts | d1 | Slight bend in the elbows, hug a big tree, squeeze the chest together. | cable flye;seated cable flye;seated cable flyes;standing cable flye;lean over cable flyes;multi-height cable crossover;pec flye
pec_deck | Pec deck | chest_fly | A | pec_deck | chest | | d1 | Handles at chest height, elbows soft, squeeze and control the return. |
db_fly | Dumbbell fly | chest_fly | A | dumbbells+bench/adj_bench | chest | front_delts | d1 | Slight elbow bend, open wide to a stretch, squeeze back over the chest. |
band_fly | Banded chest fly | chest_fly | A | bands | chest | | N d1 | Band anchored behind you, arms wide, hug forward and squeeze. |
# ---------------------------------------------------------------- horizontal pull
seated_cable_row | Seated cable row | horizontal_pull | P | cable | upper_back,lats | biceps,rear_delts | d1 | Squeeze shoulder blades together, do not rock. | cable seated row
chest_supported_row | Chest-supported row | horizontal_pull | P | dumbbells+adj_bench/row_machine | upper_back,lats | rear_delts,biceps | d1 | Chest on pad, pull elbows back, pause at the top. | chest supported row;chest supported db row;helms row
chest_supported_high_row | Chest-supported high-elbow row | horizontal_pull | S | dumbbells+adj_bench | upper_back,rear_delts | traps | d1 | Chest on the incline pad, pull with elbows flared wide, squeeze the upper back. | chest supported high elbow row
t_bar_row | Chest-supported T-bar row | horizontal_pull | P | t_bar | upper_back,lats | biceps,rear_delts | d1 | Chest on pad, pull the handles to your lower chest, pause. | chest-supported t-bar row
machine_row | Machine row | horizontal_pull | S | row_machine | upper_back,lats | biceps | d1 | Chest on pad, strict form, pull elbows back and pause. | machine "strict form" row
bent_over_row | Barbell bent-over row | horizontal_pull | P | barbell | upper_back,lats | lower_back,biceps | d2 | Hinge to about 45 degrees, back flat, pull the bar to your lower ribs. | barbell bent over row;bent over row
pendlay_row | Pendlay row | horizontal_pull | P | barbell | upper_back,lats | lower_back | d2 | Torso near parallel, row from a dead stop on the floor each rep. | pendlay row / bent over row
pin_row | Pin row | horizontal_pull | S | barbell+rack | upper_back,lats | | d2 | Bar on pins at shin height, row explosively from a dead stop. |
db_row | One-arm dumbbell row | horizontal_pull | S | dumbbells+bench | lats,upper_back | biceps | U d1 | Hand and knee on the bench, pull the dumbbell to your hip, don't twist. | dumbbell row;one-arm row;s arm row;single arm row;single arm rows;s arm db bench row
meadows_row | Meadows row | horizontal_pull | S | landmine | lats,upper_back | rear_delts | U d2 | Stand side-on to the bar end, brace on your knee, row to the hip. |
half_kneeling_cable_row | Half-kneeling single-arm cable row | horizontal_pull | S | cable | lats,upper_back | obliques | U d1 | Kneel tall, pull the handle to your ribs without rotating. | 1/2 kneeling row
inverted_row | Inverted row | horizontal_pull | S | rack/pullup_bar | upper_back,lats | biceps | N d2 | Body straight under a bar or table edge, pull chest to it. Bend knees to make it easier. |
band_row | Banded row | horizontal_pull | A | bands | upper_back,lats | biceps | N d1 | Band anchored at chest height, pull elbows back and squeeze. |
# ---------------------------------------------------------------- vertical pull
lat_pulldown | Lat pulldown | vertical_pull | P | lat_pulldown/cable | lats | biceps,upper_back | d1 | Pull elbows to ribs, chest up, no swinging. | lat pull down;pronated lat pull down;wide grip lat pull down;wide-grip lat pulldown;omni-grip lat pulldown
neutral_pulldown | Neutral-grip lat pulldown | vertical_pull | P | lat_pulldown/cable | lats | biceps | d1 | Palms facing, elbows down and in. | neutral-grip pulldown;neutral lat pull down;neutral lat pulldown;close grip lat pull down;close grip pull down
supinated_pulldown | Reverse-grip lat pulldown | vertical_pull | S | lat_pulldown/cable | lats,biceps | | d1 | Palms facing you, pull to upper chest, elbows drive down. | reverse grip lat pulldown;supinated lat pull down;supinated wide grip pull down;supinateed wide grip pull down
single_arm_pulldown | Single-arm pulldown | vertical_pull | S | cable | lats | | U d1 | Kneel or sit, pull the elbow down to your side, full stretch at the top. | single-arm pulldown;s arm half kneel cable pull down
pull_up | Pull-up | vertical_pull | P | pullup_bar | lats | biceps,upper_back | N d3 | Hands just wider than shoulders, pull your chest to the bar, lower all the way. Add weight when strong. | weighted pull-up;pull up;pull ups;wide grip pull up
neutral_pull_up | Neutral-grip pull-up | vertical_pull | P | pullup_bar | lats | biceps | N d3 | Palms facing, pull chest to the bar, control the descent. | weighted neutral-grip pull-up;close grip pull up
chin_up | Chin-up | vertical_pull | P | pullup_bar | lats,biceps | | N d3 | Palms facing you, pull chin over the bar, full hang at the bottom. |
eccentric_pull_up | Eccentric pull-up | vertical_pull | S | pullup_bar | lats | biceps | N d2 | Jump or step to the top, lower for 3-5 seconds. | eccentric-accentuated pull-up;weighted eccentric-overload pull-up
assisted_pull_up | Assisted pull-up | vertical_pull | S | assist_machine/pullup_bar+bands | lats | biceps | d1 | Machine or band assistance, full range, chest to the bar. |
band_pulldown | Banded pulldown | vertical_pull | A | bands | lats | | N d1 | Band anchored high, kneel, pull elbows down to your ribs. |
straight_arm_pulldown | Straight-arm pulldown | straight_arm_pull | A | cable | lats | | d1 | Arms nearly straight, hinge slightly, sweep the bar to your thighs. | straight arm pull down;constant-tension cable kneeling pullover
db_pullover | Dumbbell pullover | straight_arm_pull | A | dumbbells+bench | lats | chest | d1 | Across a bench, arms slightly bent, lower behind your head to a stretch. |
band_straight_arm_pulldown | Banded straight-arm pulldown | straight_arm_pull | A | bands | lats | | N d1 | Band anchored high, arms straight, sweep down to your thighs. |
# ---------------------------------------------------------------- arms
db_curl | Dumbbell biceps curl | elbow_flexion | A | dumbbells | biceps | forearms | d1 | No swinging, lower for 2 seconds. | dumbbell supinated curl
db_hammer_curl | Dumbbell hammer curl | elbow_flexion | A | dumbbells | biceps,forearms | | d1 | Palms facing in, elbows still. | hammer curl;standing hammer curl;hammer "cheat" curl
incline_db_curl | Incline dumbbell curl | elbow_flexion | A | dumbbells+adj_bench | biceps | | d1 | Lie back on an incline, elbows stay behind you, full stretch at the bottom. | incline bicep curl;incline dumbbell curl
spider_curl | Spider curl | elbow_flexion | A | dumbbells+adj_bench | biceps | | d1 | Chest down on an incline bench, arms hanging, curl without moving the elbows. |
concentration_curl | Concentration curl | elbow_flexion | A | dumbbells | biceps | | U d1 | Elbow braced on the inner thigh, curl and squeeze at the top. |
db_preacher_curl | Single-arm preacher curl | elbow_flexion | A | dumbbells+adj_bench | biceps | | U d1 | Arm over the back of an incline bench, full stretch, curl without lifting the elbow. | s arm bench preacher curl
zottman_curl | Inverse Zottman curl | elbow_flexion | A | dumbbells | biceps,forearms | | d1 | Curl up palms in (hammer), rotate palms up at the top, lower slowly. | inverse zottman curl
pinch_grip_curl | Pinch-grip curl | elbow_flexion | A | dumbbells | forearms,biceps | | d1 | Pinch the end of a dumbbell with an open hand and curl it up. | pinch grip curl
ez_bar_curl | EZ bar curl | elbow_flexion | A | ez_bar/barbell | biceps | forearms | d1 | Elbows by your sides, curl without swinging, lower slowly. | barbell or ez bar curl;ez bar supinated curl;eccentric-accentuated ez bar or barbell curl
reverse_curl | Reverse-grip EZ bar curl | elbow_flexion | A | ez_bar/barbell | forearms,biceps | | d1 | Palms down, elbows fixed, curl and lower slowly. | ez bar pronated curl
cable_curl | Cable curl | elbow_flexion | A | cable | biceps | | d1 | Elbows pinned, curl the bar to your shoulders, slow lower. | wide grip cable curl;seated double cable curl
single_arm_cable_curl | Single-arm cable curl | elbow_flexion | A | cable | biceps | | U d1 | One arm, elbow fixed, full stretch to full squeeze. | single-arm cable curl
bayesian_curl | Bayesian cable curl | elbow_flexion | A | cable | biceps | | U d1 | Face away from the low cable, arm behind you, curl forward from a full stretch. | bayesian curl
lying_cable_curl | Lying cable curl | elbow_flexion | A | cable | biceps | | d1 | Lie with feet towards the low pulley, elbows up, curl to your forehead. |
band_curl | Banded curl | elbow_flexion | A | bands | biceps | | N d1 | Stand on the band, elbows fixed, curl and lower slowly. |
triceps_pushdown | Triceps rope pushdown | elbow_extension | A | cable | triceps | | d1 | Elbows pinned to sides. | triceps pressdown;triceps pressdown 21s
single_arm_pushdown | Single-arm rope triceps extension | elbow_extension | A | cable | triceps | | U d1 | One hand on the rope, elbow pinned, extend fully and pause. | single-arm rope tricep extension;s arm tricep extension;s. arm tricep extension
overhead_cable_triceps | Overhead cable triceps extension | elbow_extension | A | cable | triceps | | d1 | Elbows close to head, full stretch. | overhead cable tricep extension;rope overhead triceps extension
single_arm_overhead_triceps | Single-arm overhead triceps extension | elbow_extension | A | cable/dumbbells/bands | triceps | | U d1 | Elbow points at the ceiling, lower behind the head, extend fully. | single-arm overhead triceps extension
cable_crossover_triceps | Cross-body cable triceps extension | elbow_extension | A | cable | triceps | | d1 | Cables crossed, pull out and down to full extension. | crossover tricep extension;crossover tricep extensions;crossover tricep extentsion
horizontal_cable_triceps | Horizontal cable triceps extension | elbow_extension | A | cable | triceps | | d1 | Face away from a chest-height cable, elbows forward, extend straight out. | horizontal tricep extension
cable_kickback | Cable triceps kickback | elbow_extension | A | cable | triceps | | U d1 | Lean slightly forward, lock your elbow by your side, extend back fully. | cable tricep kickback;constant-tension cable triceps kickback
db_kickback | Dumbbell triceps kickback | elbow_extension | A | dumbbells | triceps | | U d1 | Hinge forward, upper arm by your side, extend the dumbbell back. |
ez_skull_crusher | Skull crusher | elbow_extension | A | ez_bar/barbell+bench | triceps | | d2 | Lower the bar to just behind your forehead, elbows pointing up, extend. | skull crusher;barbell skull crusher;eccentric-accentuated barbell skull crusher
db_skull_crusher | Dumbbell skull crusher | elbow_extension | A | dumbbells+bench | triceps | | d1 | Palms facing, lower beside your head, extend without flaring. |
band_pushdown | Banded triceps pushdown | elbow_extension | A | bands | triceps | | N d1 | Band anchored high, elbows pinned, push down fully. |
# ---------------------------------------------------------------- shoulders
lateral_raise | Lateral raise | lateral_raise | A | dumbbells | side_delts | | d1 | Light weight, lead with the elbows. | dumbbell lateral raise;db lateral raise;standing lat raises;lateral raise (choice);dumbbell lateral raise 21s;db lateral raise swing
lateral_raise_hold | Lateral raise iso-hold | lateral_raise | A | dumbbells | side_delts | | T d1 | Raise to shoulder height and hold still for the time given. | dumbbell lateral raise iso-hold
cable_lateral_raise | Cable lateral raise | lateral_raise | A | cable | side_delts | | U d1 | Lean away from the cable, sweep out to shoulder height. | cable lateral raises;lying cable lat raises;lying cable lateral raises
machine_lateral_raise | Machine lateral raise | lateral_raise | A | shoulder_press_machine | side_delts | | d1 | Pads on the outside of the elbows, raise to shoulder height. |
band_lateral_raise | Banded lateral raise | lateral_raise | A | bands | side_delts | | N d1 | Stand on the band, lead with the elbows to shoulder height. |
face_pull | Face pull | rear_delt | A | cable | rear_delts,upper_back | traps | d1 | Pull to eye level, elbows high, squeeze rear shoulders. | seated face pull
reverse_pec_deck | Reverse pec deck | rear_delt | A | pec_deck | rear_delts | upper_back | d1 | Arms nearly straight, sweep back to a T, squeeze. | reverse pec deck (protracted scapulae);reverse pec deck (protraction/retraction rom);reverse pec deck (actively go through a protraction/retraction rom)
cable_reverse_fly | Cable reverse fly | rear_delt | A | cable | rear_delts | upper_back | d1 | Cables crossed, arms nearly straight, pull wide and back. | cable reverse flye
reverse_db_fly | Bent-over dumbbell reverse fly | rear_delt | A | dumbbells | rear_delts | upper_back | d1 | Hinge forward, slight elbow bend, raise wide and squeeze. | bent over reverse dumbbell flye
band_pull_apart | Band pull-apart | rear_delt | A | bands | rear_delts,upper_back | | N d1 | Arms straight at shoulder height, pull the band apart to your chest. | band pull-apart
prone_y_raise | Prone Y raise | scapular | A | adj_bench/bench | traps,rear_delts | | N d1 | Chest on an incline bench, thumbs up, raise arms in a Y. | prone trap raise;prone trap raise (y's)
wall_slide | Wall slide | scapular | A | - | traps,rear_delts | | N d1 | Back against a wall, slide forearms up keeping contact, then down. |
shrug | Dumbbell shrug | shrug | A | dumbbells/barbell/plates | traps | forearms | d1 | Shoulders straight up to your ears, pause, lower slowly. | plate shrug
incline_db_shrug | Incline dumbbell shrug | shrug | A | dumbbells+adj_bench | traps | | d1 | Chest on an incline bench, shrug up and back. | incline dumbbell shrug
band_shrug | Banded shrug | shrug | A | bands | traps | | N d1 | Stand on the band, shrug straight up, pause, lower slowly. |
cable_shrug_in | Cable shrug-in | shrug | A | cable | traps | | d1 | Cables crossed in front, shrug up and in towards the pulleys. | cable shrug-in (traps)
# ---------------------------------------------------------------- core
crunch | Crunch | core_flexion | A | - | abs | | N d1 | Lower back down, curl ribs towards hips, exhale at the top. |
bicycle_crunch | Bicycle crunch | core_flexion | A | - | abs,obliques | | N d1 | Slow and controlled, elbow towards the opposite knee, other leg straight. |
weighted_crunch | Weighted crunch | core_flexion | A | dumbbells/plates | abs | | d1 | Hold a plate or dumbbell on your chest and crunch hard. | weighted crunch;weighted crunches;weight crunches
cable_crunch | Cable crunch | core_flexion | A | cable | abs | | d1 | Kneel, rope by your head, curl your ribs to your hips; hips stay still. | cable crunch (abs)
hanging_leg_raise | Hanging leg raise | core_flexion | A | pullup_bar | abs | forearms | N d2 | Hang still, curl knees or straight legs up by tilting the pelvis. |
reverse_crunch | Reverse crunch | core_flexion | A | - | abs | | N d1 | On your back, curl hips off the floor towards your ribs, lower slowly. |
plank | Plank | core_anti_extension | A | - | abs | | N T d1 | Straight line from head to heels, breathe. |
long_lever_plank | Long-lever plank | core_anti_extension | A | - | abs | | N T d2 | Elbows further forward than your shoulders, squeeze glutes, ribs down. | long-lever plank (optional)
plank_saw | Plank saw | core_anti_extension | A | sliders | abs | | N d2 | Forearm plank, rock your body forward and back without sagging. | plank saws
l_sit | L-sit hold | core_flexion | A | pullup_bar/dip_bars | abs | | N T d3 | Hold your legs up in front, as for the top of a hanging leg raise. | l-sit hold
dead_bug | Dead bug | core_anti_extension | A | - | abs | | N d1 | Low back stays flat on the floor. |
bird_dog | Bird dog | core_anti_extension | A | - | abs,lower_back | | N d1 | On hands and knees, reach opposite arm and leg long, hips level. |
pallof_press | Pallof press | core_anti_rotation | A | cable/bands | obliques,abs | | U d1 | Resist the cable pulling you round. |
shoulder_taps | Shoulder taps | core_anti_rotation | A | - | abs,obliques | | N d1 | High plank, feet wide, tap opposite shoulder without rocking your hips. |
side_plank | Side plank | core_anti_rotation | A | - | obliques | glute_med | U N T d1 | Elbow under shoulder, hips high, straight line head to feet. | cable side plank
renegade_row | Renegade row | core_anti_rotation | S | dumbbells | upper_back,abs | obliques | U d2 | High plank on dumbbells, feet wide, row one side without twisting. |
cable_rotation | Kneeling cable rotation | core_rotation | A | cable/bands | obliques | abs | U d1 | Kneel side-on, rotate through your upper back, arms long. | kneeling rotation;kneeling push rotation;kneeling push rotations
rotation_pull_across | Rotational pull-across | core_rotation | A | cable/bands | obliques,lats | | U d1 | Cable high on one side, pull across and down to the opposite hip. | rotation pull across
# ---------------------------------------------------------------- carries / grip / jumps
farmers_carry | Farmer's carry | carry | A | dumbbells/kettlebell/trap_bar | forearms,traps | abs | d1 | Tall posture, heavy dumbbells, short steps. |
suitcase_carry | Suitcase carry | carry | A | dumbbells/kettlebell | obliques,forearms | | U d1 | One heavy weight, stand tall, don't lean. |
goblet_hold | Goblet hold | carry | A | dumbbells/kettlebell | abs,upper_back | | T d1 | Hold a dumbbell tight at your chest, stand tall and brace. |
grip_hold | Isometric grip hold | carry | A | barbell/dumbbells | forearms | traps | T d1 | Hold a heavy bar or dumbbells at your sides for time. | barbell or dumbbell isometric hold (grip work)
box_jump | Box jump | plyometric | A | plyo_box | quads,glutes | calves | N d2 | Swing arms, jump onto the box, land softly, step down. | box jumps
squat_jump | Squat jump | plyometric | A | - | quads,glutes | calves | N d2 | Quarter squat, jump straight up, land softly and reset. |
"""


def parse(text=CATALOGUE):
    entries = []
    for line in text.strip().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        f = [x.strip() for x in line.split("|")]
        if len(f) == 9:
            f.append("")
        assert len(f) == 10, f"bad catalogue line: {line[:60]}"
        eid, name, pattern, tier, equip, prim, sec, flags, cue, aliases = f
        flagset = flags.split()
        diff = next((int(x[1]) for x in flagset if x[0] == "d" and x[1:].isdigit()), 1)
        one_rm = next((x.split(":")[1] for x in flagset if x.startswith("1rm:")), None)
        entries.append({
            "id": eid, "name": name, "pattern": pattern, "tier": {"P": "main", "S": "compound", "A": "accessory"}[tier],
            "equipment": [] if equip == "-" else equip.split("+"),
            "primaryMuscles": [m for m in prim.split(",") if m],
            "secondaryMuscles": [m for m in sec.split(",") if m],
            "unilateral": "U" in flagset, "loadable": "N" not in flagset, "timed": "T" in flagset,
            "difficulty": diff, "oneRepMaxLift": one_rm, "cues": cue,
            "aliases": [a.strip() for a in aliases.split(";") if a.strip()],
        })
    return entries
