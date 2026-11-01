extends SceneTree
## The live 20 Hz movement goldens, written by server/src/movement.rs, replayed
## through the client's real prediction loop at 30, 60, 144 and 240 frames a
## second (#525). A human holds each golden input for the tick it lands in;
## Actions go out once a frame (at most every 8.3 ms, as GameManager sends);
## a model server on a fixed 50 ms grid steps the GDScript mirror with the
## newest Action it holds and its press latches, and Acks every tick.
##
## Asserted at every frame rate and both latencies: the server body equals
## the Rust golden state at every recorded step, the client's own speculative
## step for that tick equals it too, and no Ack ever corrects the prediction.
## The server's half is server/src/tests/frame_rate.rs.

const LIVE_GOLDEN_PATH := "res://golden/live_move_vectors.json"
const RATES: Array[int] = [30, 60, 144, 240]
## One way, microseconds: LAN and a 60 ms round trip.
const LATENCIES: Array[int] = [500, 30000]
const TOLERANCE := 1e-4
const FIELDS: Array[String] = ["x", "z", "y", "vx", "vz", "vy"]
## Cases a held-key client cannot reproduce: blasts come from the server,
## and a body already moving at the start has no rest to settle the clock.
const SKIPPED: Array[String] = ["blast_momentum"]

var _failures: Array[String] = []
var _replays: int = 0
var _states: int = 0


func _initialize() -> void:
	set_meta("fragr_automated", true)
	var file: FileAccess = FileAccess.open(LIVE_GOLDEN_PATH, FileAccess.READ)
	if file == null:
		_fail("cannot open " + LIVE_GOLDEN_PATH)
	else:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not parsed is Dictionary or not (parsed as Dictionary).get("cases") is Array:
			_fail("live golden is not an object with cases")
		else:
			var golden: Dictionary = parsed
			_check(absf(float(golden.get("dt", 0.0)) - MoveStep.DT_LIVE) < 1e-7, "live golden is the 20 Hz step")
			var replayed: Array[String] = []
			for entry: Variant in golden["cases"]:
				if not entry is Dictionary:
					_fail("a golden case is not an object")
					continue
				var case: Dictionary = entry
				if not _replayable(case):
					continue
				replayed.append(str(case["name"]))
				for latency: int in LATENCIES:
					for fps: int in RATES:
						_replay(case, fps, latency)
			for needed: String in ["start_and_stop", "counter_strafe", "jump_arc", "air_steer", "ground_dodge", "stair_climb_and_deck", "strafe_jump_air_cap"]:
				_check(replayed.has(needed), "replays %s" % needed)
	if _failures.is_empty():
		print("test_frame_rate_golden: PASS (%d replays, %d golden states at 30, 60, 144 and 240 fps)" % [_replays, _states])
		quit(0)
	else:
		for failure: String in _failures.slice(0, 20):
			printerr("test_frame_rate_golden: FAIL " + failure)
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _replayable(case: Dictionary) -> bool:
	if SKIPPED.has(str(case.get("name", ""))) or not (case.get("blasts", []) as Array).is_empty():
		return false
	var start: Dictionary = case["start"]
	if absf(float(start["vx"])) + absf(float(start["vz"])) + absf(float(start["vy"])) > 0.0:
		return false
	for input: Variant in case["inputs"]:
		if absf(float((input as Dictionary).get("speed_scale", 1.0)) - 1.0) > 1e-6:
			return false
	return true


func _input_at(inputs: Array, index: int) -> Dictionary:
	if index < 0 or index >= inputs.size():
		var rest: Dictionary = MoveStep.make_input(false, false, false, false, float((inputs[0] as Dictionary)["yaw"]))
		return rest
	var golden: Dictionary = inputs[index]
	return {"forward": bool(golden.get("forward", false)), "back": bool(golden.get("back", false)),
		"left": bool(golden.get("left", false)), "right": bool(golden.get("right", false)),
		"jump": bool(golden.get("jump", false)), "dodge": bool(golden.get("dodge", false)),
		"yaw": float(golden["yaw"]), "speed_scale": 1.0}


func _ack(seq: int, at_tick: int, body: Dictionary, speed: float) -> Dictionary:
	return {"type": "ack", "seq": seq, "tick": at_tick, "x": float(body["x"]), "z": float(body["z"]),
		"yaw": float(body["yaw"]),
		"movement": {"version": 2, "epoch": 1, "applied": true, "y": float(body["y"]) + LocalPrediction.FLOOR_OFFSET,
			"vx": float(body["vx"]), "vy": float(body["vy"]), "vz": float(body["vz"]),
			"effective_speed": speed, "jump_input": false, "dodge_cooldown": 0}}


func _replay(case: Dictionary, fps: int, latency: int) -> void:
	_replays += 1
	var name: String = "%s at %d fps, %d us" % [str(case["name"]), fps, latency]
	var arena: Dictionary = {"half": float(case["arena"]["half"]), "solids": (case["arena"]["solids"] as Array).duplicate(true)}
	var predictor: LocalPrediction = LocalPrediction.new()
	predictor.configure_map({"map_id": 1, "geometry_version": 2, "half_extent": arena["half"], "solids": arena["solids"]})
	var speed: float = float(case.get("speed", MoveStep.TOP_SPEED))
	var inputs: Array = case["inputs"]
	var expected: Array = case["expected"]
	var stride: int = int(case.get("stride", 1))
	var body: Dictionary = (case["start"] as Dictionary).duplicate()
	var frame_usec: int = roundi(1000000.0 / float(fps))
	# The server's grid and where the golden steps begin on it, after three
	# seconds of rest for the client's tick clock to settle.
	var grid: int = 1001234
	var first_tick: int = 100
	var golden_from: int = first_tick + 60
	var server_tick: int = first_tick
	var sent: Array[Array] = []
	var acks: Array[Array] = [[grid + latency, _ack(0, server_tick, body, speed)]]
	var used: Dictionary = _input_at(inputs, -1)
	var used_seq: int = 0
	var latch_jump: bool = false
	var latch_dodge: bool = false
	var seq: int = 0
	var last_send: int = -100000
	var now: int = grid
	var frame: int = 0
	var end_tick: int = golden_from + inputs.size() + 2
	var predicted: Dictionary = {}
	var checked: int = 0
	while server_tick < end_tick:
		frame += 1
		now += frame_usec + ((frame * 7919) % 5 - 2) * 200
		while grid + 50000 <= now:
			grid += 50000
			server_tick += 1
			for entry: Array in sent:
				if int(entry[0]) <= grid and int(entry[1]) > used_seq:
					used_seq = int(entry[1])
					used = entry[2]
					latch_jump = latch_jump or bool(used["jump"])
					latch_dodge = latch_dodge or bool(used["dodge"])
			var step_input: Dictionary = used.duplicate()
			step_input["jump"] = bool(used["jump"]) or latch_jump
			step_input["dodge"] = latch_dodge
			latch_jump = false
			latch_dodge = false
			body = MoveStep.fighter_step(body, step_input, speed, MoveStep.DT_LIVE, arena)
			var index: int = server_tick - golden_from
			if index >= 0 and index < inputs.size() and (index + 1) % stride == 0:
				var want: Dictionary = expected[(index + 1) / stride - 1]
				for field: String in FIELDS:
					if absf(float(body[field]) - float(want[field])) > TOLERANCE:
						_fail("%s: server step %d %s %f, golden %f" % [name, index + 1, field, float(body[field]), float(want[field])])
						return
				checked += 1
				predicted[server_tick] = want
			acks.append([grid + latency, _ack(used_seq, server_tick, body, speed)])
		while not acks.is_empty() and int(acks[0][0]) <= now:
			var ack: Dictionary = acks.pop_front()[1]
			var at_tick: int = int(ack["tick"])
			if predicted.has(at_tick):
				var mine: Dictionary = {}
				for step: Dictionary in predictor.steps:
					if int(step["tick"]) == at_tick:
						mine = step["state_after"]
				if mine.is_empty():
					_fail("%s: no speculative step for tick %d" % [name, at_tick])
					return
				var want: Dictionary = predicted[at_tick]
				for field: String in FIELDS:
					if absf(float(mine[field]) - float(want[field])) > TOLERANCE:
						_fail("%s: predicted tick %d %s %f, golden %f" % [name, at_tick, field, float(mine[field]), float(want[field])])
						return
				_states += 1
			predictor.accept_ack(ack, now)
			predictor.presented_position(now)
		# The key held now is the golden input of the tick this Action lands in.
		var lands: int = first_tick + ceili(float(now + latency - 1001234) / 50000.0)
		var held: Dictionary = _input_at(inputs, lands - golden_from)
		if now - last_send >= 8333 and not predictor.baseline.is_empty():
			seq += 1
			last_send = now
			sent.append([now + latency, seq, held])
			var action: Dictionary = held.duplicate()
			action["seq"] = seq
			predictor.record_action(action, now, true)
		predictor.advance(now)
		predictor.decay_visual(float(frame_usec) / 1000000.0)
		predictor.presented_position(now)
	_check(predictor.active(), "%s: prediction stayed active (%s)" % [name, predictor.last_fallback_reason])
	_check(predictor.correction_max <= TOLERANCE, "%s: an Ack corrected the prediction by %f m at tick %d" % [name, predictor.correction_max, predictor.correction_max_tick])
	_check(checked == expected.size(), "%s: checked %d of %d golden states" % [name, checked, expected.size()])
