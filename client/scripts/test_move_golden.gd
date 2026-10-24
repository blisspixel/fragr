extends SceneTree
## Headless check that the GDScript fighter step matches the Rust step against
## both golden files: client/golden/live_move_vectors.json at the live 20 Hz
## step and client/golden/move_vectors.json at 60 Hz. Run with:
## godot --headless --path client --script res://scripts/test_move_golden.gd
##
## Tolerances: 1e-4 on every recorded state for the short cases, and 1e-2 at
## the checkpoints of strided cases such as the thousand-step wander, since the
## two languages do their arithmetic in different precisions.

const GOLDEN_PATH := "res://golden/move_vectors.json"
const LIVE_GOLDEN_PATH := "res://golden/live_move_vectors.json"
const GOLDEN_VERSION := 3
const STEP_TOLERANCE := 1e-4
const LONG_TOLERANCE := 1e-2
## Height and vertical speed are checked too, because the heightfield is the
## part of the model a mirror is most likely to get subtly wrong.
const FIELDS := ["x", "z", "y", "vx", "vz", "vy", "yaw"]
const CONSTANTS := {
	"radius": MoveStep.RADIUS, "top_speed": MoveStep.TOP_SPEED,
	"ground_accel": MoveStep.GROUND_ACCEL, "friction": MoveStep.FRICTION,
	"stop_speed": MoveStep.STOP_SPEED, "air_accel": MoveStep.AIR_ACCEL,
	"air_speed_cap": MoveStep.AIR_SPEED_CAP, "gravity": MoveStep.GRAVITY,
	"jump_speed": MoveStep.JUMP_SPEED, "dodge_speed": MoveStep.DODGE_SPEED,
	"dodge_up": MoveStep.DODGE_UP,
}

var failures: Array = []
var case_count: int = 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	var checked: int = 0
	checked += _run_file(GOLDEN_PATH, MoveStep.DT_60HZ, ["straight_run", "start_and_stop", "jump_arc", "stair_climb", "stair_descend", "deck_edge_fall", "stair_fractional_above", "stair_fractional_below", "ledge_escape_east", "ledge_escape_south", "ledge_escape_west", "ledge_escape_north", "balcony_underpass", "balcony_exit_east", "balcony_exit_south", "balcony_exit_west", "balcony_exit_north", "ceiling_head_strike", "ceiling_edge_contact", "ceiling_step_blocked", "ceiling_step_clear", "long_wander_1000"])
	checked += _run_file(LIVE_GOLDEN_PATH, MoveStep.DT_LIVE, ["start_and_stop", "counter_strafe", "diagonal_yaw", "wall_slide", "stair_climb_and_deck", "deck_edge_fall", "jump_arc", "air_steer", "strafe_jump_air_cap", "ground_dodge", "blast_momentum", "ceiling_head_strike", "compliance_half_speed", "crouch_speed"])
	_test_unit_behaviour()

	if failures.is_empty():
		print("test_move_golden: PASS (%d cases, %d states)" % [case_count, checked])
		quit(0)
	else:
		for failure: String in failures:
			printerr("test_move_golden: FAIL " + failure)
		quit(1)


func _run_file(path: String, dt: float, needed: Array) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_check(false, "cannot open " + path)
		return 0
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_check(false, "%s is not a JSON object" % path)
		return 0
	var golden: Dictionary = parsed
	_check(int(golden.get("version", 0)) == GOLDEN_VERSION, "%s version is %d" % [path, GOLDEN_VERSION])
	_check(absf(float(golden.get("dt", 0.0)) - dt) < 1e-7, "%s dt matches" % path)
	var constants: Variant = golden.get("constants")
	if not constants is Dictionary:
		_check(false, "%s records its constants" % path)
		return 0
	for key: String in CONSTANTS:
		_check(absf(float(constants.get(key, -1.0)) - float(CONSTANTS[key])) < 1e-6, "%s constant %s matches the mirror" % [path, key])
	var cases: Array = golden.get("cases", [])
	case_count += cases.size()
	var names: Array[String] = []
	for case: Dictionary in cases:
		names.append(str(case.get("name", "?")))
	for name: String in needed:
		_check(names.has(name), "%s covers %s" % [path, name])
	var checked: int = 0
	for case: Dictionary in cases:
		checked += _run_case(case, dt)
	return checked


func _run_case(case: Dictionary, dt: float) -> int:
	var name: String = str(case.get("name", "?"))
	var arena: Dictionary = case["arena"]
	var state: Dictionary = (case["start"] as Dictionary).duplicate()
	var inputs: Array = case["inputs"]
	var expected: Array = case["expected"]
	var stride: int = int(case.get("stride", 1))
	var speed: float = float(case.get("speed", 0.0))
	var tolerance: float = LONG_TOLERANCE if stride > 1 else STEP_TOLERANCE
	var checked: int = 0
	var next_expected: int = 0
	for i in range(inputs.size()):
		state = MoveStep.fighter_step(state, inputs[i], speed, dt, arena)
		if (i + 1) % stride == 0:
			if next_expected >= expected.size():
				_check(false, "%s: more checkpoints than expected states" % name)
				break
			var want: Dictionary = expected[next_expected]
			for field: String in FIELDS:
				var a: float = float(state[field])
				var b: float = float(want[field])
				if absf(a - b) > tolerance:
					_check(false, "%s step %d %s: got %.6f want %.6f" % [name, i + 1, field, a, b])
					break
			next_expected += 1
			checked += 1
	_check(next_expected == expected.size(), "%s: consumed every expected state" % name)
	return checked


func _test_unit_behaviour() -> void:
	_check(absf(MoveStep.normalize_yaw(-0.5) - (2.0 * PI - 0.5)) < 1e-6, "negative yaw wraps up")
	_check(MoveStep.normalize_yaw(2.0 * PI) < 1e-6, "full turn wraps to zero")
	_check(MoveStep.normalize_yaw(NAN) == 0.0, "nan yaw becomes zero")
	var none := MoveStep.make_input(false, false, false, false, 0.0)
	_check(MoveStep.wish_dir(none, 0.0) == Vector2.ZERO, "no keys, no wish")
	var diag := MoveStep.make_input(true, false, false, true, 0.0)
	_check(absf(MoveStep.wish_dir(diag, 0.0).length() - 1.0) < 1e-6, "diagonal wish is unit")
	var arena := {"half": 25.0, "solids": [MoveStep.solid_from_center(0.0, 0.0, 1.0, 1.0)]}
	_check(MoveStep.arena_blocked(arena, 1.4, 0.0), "radius inflates solids")
	_check(not MoveStep.arena_blocked(arena, 1.6, 0.0), "outside the inflated solid is free")
	var s := MoveStep.make_state(10.0, 0.0, 0.0)
	var go := MoveStep.make_input(true, false, false, false, 0.0)
	for i in range(3):
		s = MoveStep.fighter_step(s, go, MoveStep.TOP_SPEED, MoveStep.DT_LIVE, arena)
	_check(absf(float(s["vx"]) - MoveStep.TOP_SPEED) < 1e-4, "reaches top speed in three live ticks")
	var dodge := MoveStep.make_input(false, false, false, true, 0.0)
	dodge["dodge"] = true
	_check(MoveStep.dodge_applies(s, dodge, arena), "a standing fighter with a direction dodges")
	var thrown: Dictionary = MoveStep.fighter_step(s, dodge, MoveStep.TOP_SPEED, MoveStep.DT_LIVE, arena)
	_check(absf(float(thrown["vz"]) - MoveStep.DODGE_SPEED) < 1e-4 and float(thrown["vy"]) > 0.0, "the dodge throws sideways on a hop")
	_check(not MoveStep.dodge_applies(thrown, dodge, arena), "nobody dodges in the air")

	# A solid with no top on the wire is a wall, which is what keeps an older
	# server's map readable by a newer client.
	var legacy := {"min_x": -1.0, "max_x": 1.0, "min_z": -1.0, "max_z": 1.0}
	_check(MoveStep.solid_top(legacy) == MoveStep.WALL_TOP, "a solid with no top is a wall")

	# A step is walked onto; a wall is not.
	var stepped := {
		"half": 25.0,
		"solids": [
			MoveStep.solid_from_center(4.0, 0.0, 1.0, 4.0, 0.5),
			MoveStep.solid_from_center(10.0, 0.0, 1.0, 4.0, 2.2),
		],
	}
	var w := MoveStep.make_state(0.0, 0.0, 0.0)
	for i in range(45):
		w = MoveStep.fighter_step(w, go, MoveStep.TOP_SPEED, MoveStep.DT_60HZ, stepped)
	_check(absf(float(w["y"]) - 0.5) < 1e-5, "walked up onto the step, y=%.4f" % float(w["y"]))
	for i in range(120):
		w = MoveStep.fighter_step(w, go, MoveStep.TOP_SPEED, MoveStep.DT_60HZ, stepped)
	_check(float(w["x"]) < 9.0, "stopped by the wall it cannot climb, x=%.3f" % float(w["x"]))
