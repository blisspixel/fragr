class_name LocalPrediction
extends RefCounted
## Local human presentation only. One speculative move per server tick, even
## though Actions are sampled more often. The server and its snapshots own truth.

const TICK_USEC: int = 50000
const MAX_STEPS: int = 3
const MAX_SAMPLES: int = 64
const MAX_SEQUENCE: int = MovementAck.MAX_SEQUENCE
const FLOOR_OFFSET: float = 1.5
const SNAP_DISTANCE: float = 1.0
const OFFSET_LIMIT: float = 0.25
const MAX_CORRECTION_SAMPLES: int = 4096

var arena: Dictionary = {}
var _tram_geometry: Dictionary = {}
var _archive_neutrals: Dictionary = {}
var _moon_residents: Array[Dictionary] = []
var _tram_samples: Array[Dictionary] = []
var _tram_attempt: int = -1
var _contact_samples: Array[Dictionary] = []
var _contact_player_id: String = ""
var _contacts_required: bool = false
var _contact_waiting: bool = false
var contact_error: String = ""
var baseline: Dictionary = {}
var state: Dictionary = {}
var steps: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var held: Dictionary = {}
var pending_jump_latch: bool = false
var epoch: int = 0
var tick: int = -1
var last_speed: float = 0.0
var ack_seq: int = 0
var first_recorded_seq: int = -1
var next_step_usec: int = 0
var visual_offset: Vector3 = Vector3.ZERO
var correction_count: int = 0
var correction_max: float = 0.0
var correction_max_tick: int = -1
var correction_max_usec: int = -1
var correction_max_server_position: Vector3 = Vector3.ZERO
var correction_samples: Array[float] = []
var fallback_count: int = 0
var fallback_reasons: Dictionary = {}
var last_fallback_reason: String = ""
var fallback_reason: String = "no_ack"


func configure_map(info: Dictionary) -> void:
	reset("map", true)
	arena.clear()
	_archive_neutrals = M08NeutralBodies.layout(info) if info.get("m08") is Dictionary and M08MissionState.map_error(info).is_empty() else {}
	_moon_residents = MoonResidentBodies.read(info)
	_tram_geometry = MissionState.geometry_for(info) if info.get("m05") is Dictionary else {}
	_tram_samples.clear()
	if MapGeometry.validation_error(info) == "":
		arena = {"half": float(info["half_extent"]), "solids": info["solids"].duplicate(true)}


func reset(reason: String, clear_measurements: bool = false) -> void:
	var was_active: bool = active()
	baseline.clear()
	state.clear()
	steps.clear()
	samples.clear()
	held.clear()
	if reason in ["map", "role", "disconnect", "connected", "connection_lost"]:
		_contacts_required = false
	_contact_waiting = _contacts_required
	_contact_samples.clear()
	_contact_player_id = ""
	contact_error = ""
	pending_jump_latch = false
	epoch = 0
	tick = -1
	ack_seq = 0
	first_recorded_seq = -1
	last_speed = 0.0
	next_step_usec = 0
	visual_offset = Vector3.ZERO
	if clear_measurements:
		clear_measurements()
	elif was_active:
		fallback_count += 1
		fallback_reasons[reason] = int(fallback_reasons.get(reason, 0)) + 1
		last_fallback_reason = reason
	fallback_reason = reason


## Start an opt-in measurement window without changing replay state.
func clear_measurements() -> void:
	correction_count = 0
	correction_max = 0.0
	correction_max_tick = -1
	correction_max_usec = -1
	correction_max_server_position = Vector3.ZERO
	correction_samples.clear()
	fallback_count = 0
	fallback_reasons.clear()
	last_fallback_reason = ""


func active() -> bool:
	return not baseline.is_empty() and not arena.is_empty() and fallback_reason == "" and not _contact_waiting


static func newer_sequence(seq: int, before: int) -> bool:
	var distance: int = (seq - before) & MAX_SEQUENCE
	return distance > 0 and distance < 2147483648


static func _body(ack: Dictionary) -> Dictionary:
	var movement: Dictionary = ack["movement"]
	return {
		"x": float(ack["x"]), "z": float(ack["z"]),
		"y": float(movement["y"]) - FLOOR_OFFSET,
		"vx": float(movement["vx"]), "vy": float(movement["vy"]),
		"vz": float(movement["vz"]), "yaw": float(ack["yaw"]),
	}


static func world_position(pose: Dictionary) -> Vector3:
	return Vector3(float(pose["x"]), float(pose["y"]) + FLOOR_OFFSET, float(pose["z"]))


func accept_ack(ack: Dictionary, now_usec: int) -> void:
	if not MovementAck.has_replay_body(ack):
		reset("unsupported_ack")
		return
	var movement: Dictionary = ack["movement"]
	if not bool(movement["applied"]):
		reset("inactive")
		return
	if arena.is_empty():
		reset("no_map")
		return
	var incoming_epoch: int = int(movement["epoch"])
	var incoming_tick: int = int(ack["tick"])
	var new_body: Dictionary = _body(ack)
	var discontinuity: bool = epoch != incoming_epoch or tick < 0 or incoming_tick <= tick
	var matched_state: Dictionary = {}
	if not discontinuity:
		for step: Dictionary in steps:
			if int(step["tick"]) == incoming_tick:
				matched_state = step["state_after"]
				break
	if not discontinuity and newer_sequence(int(ack["seq"]), ack_seq):
		var known: bool = false
		for sample: Dictionary in samples:
			if int(sample["seq"]) == int(ack["seq"]):
				known = true
				break
		# A delayed Ack can select an Action sent before this predictor began
		# recording samples. Accept that authoritative body as a new baseline;
		# a later unknown Action is still a broken replay history.
		if not known and first_recorded_seq >= 0 and \
				not newer_sequence(first_recorded_seq, int(ack["seq"])):
			reset("unknown_seq")
			return
	var before: Vector3 = world_position(state) + visual_offset if active() else world_position(new_body)
	if not discontinuity and incoming_tick - tick > MAX_STEPS + 1:
		reset("ack_gap")
		return
	if discontinuity:
		if tick >= 0:
			_contact_samples.clear()
		steps.clear()
		samples.clear()
		first_recorded_seq = -1
		held.clear()
		pending_jump_latch = false
		visual_offset = Vector3.ZERO
	else:
		while not steps.is_empty() and int(steps[0]["tick"]) <= incoming_tick:
			steps.pop_front()
		while not samples.is_empty() and not newer_sequence(int(samples[0]["seq"]), int(ack["seq"])):
			samples.pop_front()
		pending_jump_latch = false
		for sample: Dictionary in samples:
			if not bool(sample["jump"]):
				continue
			var consumed: bool = false
			for step: Dictionary in steps:
				if bool(step["input"]["jump"]) and not newer_sequence(int(sample["seq"]), int(step["input"]["seq"])):
					consumed = true
					break
			if not consumed:
				pending_jump_latch = true
	epoch = incoming_epoch
	tick = incoming_tick
	ack_seq = int(ack["seq"])
	baseline = new_body
	state = new_body.duplicate()
	fallback_reason = ""
	if _contacts_required:
		_contact_waiting = _contact_sample(tick + 1, now_usec).is_empty()
		if _contact_waiting:
			fallback_reason = "contact_stale"
	var speed: float = float(movement["effective_speed"])
	last_speed = speed
	var replay_tick: int = tick
	for step: Dictionary in steps:
		if int(step["tick"]) != replay_tick + 1:
			steps.clear()
			break
		step["speed"] = speed
		state = _step(state, step)
		step["state_after"] = state.duplicate()
		replay_tick += 1
	if steps.is_empty():
		next_step_usec = now_usec
	else:
		next_step_usec = max(now_usec, int(steps.back()["usec"]) + TICK_USEC)
	var correction: Vector3 = before - world_position(state)
	var distance: float = correction.length()
	if not discontinuity and not matched_state.is_empty():
		var same_tick_error: float = world_position(matched_state).distance_to(world_position(new_body))
		correction_count += 1
		if same_tick_error > correction_max:
			correction_max = same_tick_error
			correction_max_tick = incoming_tick
			correction_max_usec = now_usec
			correction_max_server_position = world_position(new_body)
		correction_samples.append(same_tick_error)
		if correction_samples.size() > MAX_CORRECTION_SAMPLES:
			correction_samples.pop_front()
		visual_offset = correction if distance <= SNAP_DISTANCE else Vector3.ZERO
		if visual_offset.length() > OFFSET_LIMIT:
			visual_offset = visual_offset.normalized() * OFFSET_LIMIT


func record_action(action: Dictionary, now_usec: int, sent: bool) -> void:
	if not active() or not sent:
		return
	if not action.has("yaw"):
		reset("no_yaw")
		return
	var sample: Dictionary = {
		"seq": int(action["seq"]), "forward": bool(action["forward"]),
		"back": bool(action["back"]), "left": bool(action["left"]),
		"right": bool(action["right"]), "jump": bool(action["jump"]),
		"yaw": float(action["yaw"]),
	}
	if first_recorded_seq < 0:
		first_recorded_seq = int(sample["seq"])
	samples.append(sample)
	held = sample.duplicate()
	if bool(sample["jump"]):
		pending_jump_latch = true
	if samples.size() > MAX_SAMPLES:
		reset("sample_overflow")
		return
	if not steps.is_empty() and now_usec < next_step_usec:
		# Several sampled Actions can belong to the same speculative server tick.
		# Replace its continuous controls without adding another 50 ms step.
		var latest_step: Dictionary = steps.back()
		var revised: Dictionary = sample.duplicate()
		revised["jump"] = _jump_unconsumed_before_latest_step()
		pending_jump_latch = false
		latest_step["input"] = revised
		state = baseline.duplicate()
		for step: Dictionary in steps:
			state = _step(state, step)
			step["state_after"] = state.duplicate()
	advance(now_usec)


func _jump_unconsumed_before_latest_step() -> bool:
	# A true sample already covered by an earlier speculative tick cannot make
	# a later tick jump after a neutral release. A tap within this tick still
	# survives that release, matching the server's jump latch.
	for sample: Dictionary in samples:
		if not bool(sample["jump"]):
			continue
		var consumed: bool = false
		for index: int in range(steps.size() - 1):
			var earlier: Dictionary = steps[index]
			if bool(earlier["input"]["jump"]) and not newer_sequence(int(sample["seq"]), int(earlier["input"]["seq"])):
				consumed = true
				break
		if not consumed:
			return true
	return false


func advance(now_usec: int) -> void:
	if not active() or held.is_empty():
		return
	if now_usec - next_step_usec > TICK_USEC * MAX_STEPS:
		reset("ack_timeout")
		return
	while now_usec >= next_step_usec and steps.size() < MAX_STEPS:
		var input: Dictionary = held.duplicate()
		input["jump"] = bool(held["jump"]) or pending_jump_latch
		pending_jump_latch = false
		var step: Dictionary = {"tick": tick + steps.size() + 1, "input": input, "speed": last_speed, "usec": next_step_usec}
		if _contacts_required and _contact_sample(int(step["tick"]), now_usec).is_empty():
			reset("contact_stale")
			return
		step["blockers"] = _contact_blockers(int(step["tick"]), now_usec)
		step["body_key"] = _contact_player_id
		state = _step(state, step)
		step["state_after"] = state.duplicate()
		steps.append(step)
		next_step_usec += TICK_USEC
	if steps.size() >= MAX_STEPS and now_usec > next_step_usec:
		reset("ack_lag")


func _step(pose: Dictionary, step: Dictionary) -> Dictionary:
	if _tram_geometry.is_empty() or _tram_samples.is_empty():
		return _contact_step(pose, step, arena)
	var before: Array = _tram_feet(int(step["tick"]) - 1)
	var after: Array = _tram_feet(int(step["tick"]))
	var old_solid: Dictionary = M05Tram.solid_at(_tram_geometry, before)
	var world: Dictionary = arena.duplicate(true)
	var index: int = int(_tram_geometry["m05"]["tram"]["solid"])
	world["solids"][index] = M05Tram.solid_at(_tram_geometry, after)
	var carried_pose: Dictionary = pose
	if M05Tram.supported(pose, old_solid, bool(step["input"]["jump"])):
		var other: Dictionary = world.duplicate(true)
		other["solids"].remove_at(index)
		var carried: Dictionary = M05Tram.carried(pose, float(after[2]) - float(before[2]), other)
		if not carried.is_empty():
			if _carry_contacts_clear(pose, carried, step):
				carried_pose = carried
			else:
				world["solids"][index] = old_solid
	return _contact_step(carried_pose, step, world)


## Static recent server bodies are presentation obstacles, never outcomes.
## Keep each step's sample immutable so later snapshots cannot alter its replay.
func accept_snapshot(snapshot: Dictionary, player_id: String, mission: Dictionary, now_usec: int) -> void:
	_contacts_required = true
	if player_id.is_empty():
		reset("contact_identity")
		return
	if _contact_player_id != player_id:
		if not _contact_player_id.is_empty():
			reset("contact_identity")
		else:
			_contact_samples.clear()
	_contact_player_id = player_id
	var parsed: Dictionary = ActorContact.read_snapshot(snapshot, mission, _archive_neutrals, _moon_residents)
	contact_error = str(parsed["error"])
	if not contact_error.is_empty():
		var problem: String = contact_error
		reset("contact_invalid")
		contact_error = problem
		return
	var incoming: int = int(snapshot["tick"])
	if not _contact_samples.is_empty():
		if incoming < int(_contact_samples.back()["tick"]):
			return
		if incoming == int(_contact_samples.back()["tick"]):
			_contact_samples.pop_back()
	_contact_samples.append({"tick": incoming, "usec": now_usec, "bodies": parsed["bodies"].duplicate(true)})
	while _contact_samples.size() > MAX_STEPS + 1:
		_contact_samples.pop_front()
	_contact_waiting = tick >= 0 and _contact_sample(tick + 1, now_usec).is_empty()
	if _contact_waiting and not baseline.is_empty():
		fallback_reason = "contact_stale"
	if not _contact_waiting and fallback_reason == "contact_stale" and not baseline.is_empty():
		fallback_reason = ""


func _contact_sample(at_tick: int, now_usec: int) -> Dictionary:
	for index: int in range(_contact_samples.size() - 1, -1, -1):
		var sample: Dictionary = _contact_samples[index]
		var age: int = at_tick - int(sample["tick"])
		if age < 0:
			continue
		if age > MAX_STEPS or now_usec - int(sample["usec"]) > TICK_USEC * (MAX_STEPS + 1):
			return {}
		return sample
	return {}


func _contact_blockers(at_tick: int, now_usec: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var sample: Dictionary = _contact_sample(at_tick, now_usec)
	if not sample.is_empty():
		for body: Dictionary in sample["bodies"]:
			if str(body["key"]) != _contact_player_id:
				result.append(body.duplicate(true))
	return result


static func _near_contacts(pose: Dictionary, reach: float, blockers: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for body: Dictionary in blockers:
		var distance: float = Vector2(float(body["from"]["x"]) - float(pose["x"]), float(body["from"]["z"]) - float(pose["z"])).length()
		if distance <= reach + MoveStep.RADIUS + float(body["radius"]) + ActorContact.EPSILON:
			result.append(body)
	return result


static func _carry_contacts_clear(pose: Dictionary, carried: Dictionary, step: Dictionary) -> bool:
	var reach: float = Vector2(float(carried["x"]) - float(pose["x"]), float(carried["z"]) - float(pose["z"])).length()
	var mover: Dictionary = {"key": step.get("body_key", ""), "from": pose, "proposed": carried, "height": MoveStep.BODY_HEIGHT, "radius": MoveStep.RADIUS, "jump": false}
	for body: Dictionary in _near_contacts(pose, reach, step.get("blockers", [])):
		if ActorContact.sweep_time(mover, body) >= 0.0:
			return false
	return true


static func _contact_step(pose: Dictionary, step: Dictionary, world: Dictionary) -> Dictionary:
	var proposed: Dictionary = MoveStep.live_step(pose, step["input"], float(step["speed"]), MoveStep.DT_LIVE, world)
	var reach: float = float(step["speed"]) * MoveStep.DT_LIVE
	var bodies: Array[Dictionary] = _near_contacts(pose, reach, step.get("blockers", []))
	if bodies.is_empty():
		return proposed
	var from: Dictionary = pose.duplicate()
	from["yaw"] = proposed["yaw"]
	bodies.append({"key": step["body_key"], "from": from, "proposed": proposed, "height": MoveStep.BODY_HEIGHT, "radius": MoveStep.RADIUS, "jump": bool(step["input"]["jump"])})
	var accepted: Dictionary = ActorContact.resolve(bodies, MoveStep.DT_LIVE, world).back()
	if accepted["x"] != proposed["x"] or accepted["z"] != proposed["z"]:
		accepted["vx"] = (float(accepted["x"]) - float(pose["x"])) / MoveStep.DT_LIVE
		accepted["vz"] = (float(accepted["z"]) - float(pose["z"])) / MoveStep.DT_LIVE
	return accepted

func apply_m05(value: Dictionary) -> void:
	if _tram_geometry.is_empty():
		return
	if value.get("id") != MissionState.M05_ID:
		_tram_samples.clear()
		reset("tram_handoff")
		return
	if int(value["attempt"]) != _tram_attempt:
		_tram_samples.clear()
		_tram_attempt = int(value["attempt"])
	var sample: Dictionary = value["m05"]["tram"].duplicate(true)
	if not _tram_samples.is_empty() and int(sample["tick"]) < int(_tram_samples.back()["tick"]):
		_tram_samples.clear()
	if not _tram_samples.is_empty() and sample == _tram_samples.back():
		return
	_tram_samples.append(sample)
	while _tram_samples.size() > MAX_SAMPLES:
		_tram_samples.pop_front()
	arena["solids"][int(_tram_geometry["m05"]["tram"]["solid"])] = M05Tram.solid_at(_tram_geometry, sample["feet"])

func _tram_feet(at_tick: int) -> Array:
	var chosen: Dictionary = _tram_samples[0]
	for sample: Dictionary in _tram_samples:
		if int(sample["tick"]) > at_tick:
			break
		chosen = sample
	var feet: Array = chosen["feet"].duplicate()
	# Prediction has the same three-tick ceiling as walking. A refusal or block
	# replaces this sample with server facts; no mission progress is predicted.
	if chosen["phase"] == "moving":
		var bound: Dictionary = _tram_geometry["m05"]["tram"]
		var advance_ticks: int = clampi(at_tick - int(chosen["tick"]), 0, MAX_STEPS)
		feet[2] = move_toward(float(feet[2]), float(bound["end"][2]), float(bound["speed"]) * MoveStep.DT_LIVE * advance_ticks)
	return feet


func decay_visual(delta: float) -> void:
	visual_offset *= exp(-12.0 * maxf(delta, 0.0))
	if visual_offset.length() < 0.001:
		visual_offset = Vector3.ZERO


func presented_position() -> Vector3:
	return world_position(state) + visual_offset


func correction_percentile(percentile: float) -> float:
	if correction_samples.is_empty():
		return 0.0
	var ordered: Array[float] = correction_samples.duplicate()
	ordered.sort()
	var index: int = mini(int(ceilf(clampf(percentile, 0.0, 1.0) * ordered.size())) - 1, ordered.size() - 1)
	return ordered[maxi(index, 0)]
