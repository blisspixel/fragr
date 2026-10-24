class_name LocalPrediction
extends RefCounted
## Local human presentation only. One speculative move per server tick, even
## though Actions are sampled more often. The server and its snapshots own truth.
##
## The drawn body is the predicted tick states interpolated on a tick clock
## phase-locked to the server's input cutoff. Each Ack names the newest Action
## its tick used, so the send times of that Action and the next one bracket
## the moment, in this client's clock, after which a sent input lands in the
## following tick. Step n is drawn, and its input sampled, between two such
## cutoffs: an input then lands in the tick the client predicted for it, at any
## latency. Until both bounds are known the earliest Ack arrival stands in.
## The eye is drawn half a tick behind that input clock (PRESENT_LAG_USEC), so
## a key released in the first half of a tick changes a step not yet drawn and
## one released later can no longer carry the eye past where the body stops.
## Anything that changes the drawn pose without time passing, an Ack correction
## or a revised input inside the open tick, becomes an offset that decays over
## about 60 ms, and never pulls the eye back against the way it is moving. A
## release that leaves the eye ahead of the slowing body glides instead: the
## offset shrinks with the distance the body has left to its predicted rest,
## so the eye decelerates into the stop and arrives there with the body.

const TICK_USEC: int = 50000
const MAX_STEPS: int = 3
const MAX_SAMPLES: int = 64
const MAX_SEQUENCE: int = MovementAck.MAX_SEQUENCE
const FLOOR_OFFSET: float = 1.5
## A correction larger than this is a teleport, drawn at once.
const SNAP_DISTANCE: float = 1.0
## Per second. 35 leaves a tenth of an offset after 66 ms.
const OFFSET_DECAY: float = 35.0
const CLOCK_WINDOW: int = 40
## An offset this small left over at rest settles at this speed, metres per
## second, instead of the correction rate: a stop never visibly springs back.
const SETTLE_REACH: float = 0.12
const SETTLE_SPEED: float = 0.5
## While the body moves, the schedule follows its estimate by at most this
## much per Ack, so a new estimate stretches a tick by 2 percent instead of
## moving the eye. A body at rest takes the estimate at once.
const CLOCK_SLEW_USEC: int = 1000
## How far the drawn body runs behind the input clock. A release from full run
## in the last half of a tick predicts a stop 0.168 m past that tick's start,
## and a half-tick lag draws at most 0.15 m of it, so the eye never overshoots
## the stop and has nothing to settle back. A press waits for it only when it
## lands in the first half of a tick: 6 ms on average, 25 ms at most.
const PRESENT_LAG_USEC: int = TICK_USEC / 2
## Ticks a released body is followed to find its rest. Friction stops a full
## run in three; one still moving after this is airborne or pushed, not
## stopping, and takes the ordinary decay.
const REST_SEARCH_TICKS: int = 6
const MAX_CORRECTION_SAMPLES: int = 4096

var arena: Dictionary = {}
var _tram_geometry: Dictionary = {}
var _foundry_geometry: Dictionary = {}
var _foundry_moving: bool = false
var _walker_geometry: Dictionary = {}
var _walker_moving: bool = false
var _walker_tick: int = -1
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
var pending_dodge_latch: bool = false
var epoch: int = 0
var tick: int = -1
var last_speed: float = 0.0
## The newest Ack's model: the arena fighter (version 2) or the immediate step
## a campaign mission keeps (version 1). Each step records the one it ran.
var fighter_model: bool = true
var ack_seq: int = 0
var first_recorded_seq: int = -1
var next_step_usec: int = 0
var visual_offset: Vector3 = Vector3.ZERO
## Arrival time minus tick times tick length, newest last. The minimum is the
## schedule base: tick n's step opens at base + (n - 1) * TICK_USEC.
var _clock_samples: Array[int] = []
var _clock_base: int = 0
## Send-time bounds on the server's input cutoff, each minus tick * TICK_USEC:
## an applied Action was sent before it, the next Action after it.
var _cutoff_after: Array[int] = []
var _cutoff_before: Array[int] = []
## The base the step schedule actually uses, slewed toward clock_base().
var _schedule_base: int = 0
var _schedule_ready: bool = false
## The body before the newest acknowledged tick, so the lagged eye can still
## draw that tick after its step has left the speculative list.
var _acked_from: Dictionary = {}
## A stop glide: the offset at its start, the undisturbed body then, and where
## the body is predicted to come to rest. Empty `_glide_rest` means none.
var _glide_offset: Vector3 = Vector3.ZERO
var _glide_from: Vector3 = Vector3.ZERO
var _glide_rest: Vector3 = Vector3.ZERO
var _gliding: bool = false
## The previous frame's drawn and undisturbed positions, for the guard that
## keeps a decaying offset from pulling the eye backwards.
var _last_drawn: Vector3 = Vector3.ZERO
var _last_raw: Vector3 = Vector3.ZERO
var _has_last_drawn: bool = false
var _last_drawn_usec: int = 0
var _last_offset: Vector3 = Vector3.ZERO
var correction_count: int = 0
var correction_max: float = 0.0
var correction_max_tick: int = -1
var correction_max_usec: int = -1
var correction_max_server_position: Vector3 = Vector3.ZERO
var correction_samples: Array[float] = []
## Drawn-eye jumps an Ack would have caused, now absorbed by the offset.
var presented_corrections: Array[float] = []
var fallback_count: int = 0
var fallback_reasons: Dictionary = {}
var last_fallback_reason: String = ""
var fallback_reason: String = "no_ack"


func configure_map(info: Dictionary) -> void:
	reset("map", true)
	arena.clear()
	_archive_neutrals = M08NeutralBodies.layout(info) if info.get("m08") is Dictionary and M08MissionState.map_error(info).is_empty() else {}
	_moon_residents = MoonResidentBodies.read(info)
	if info.get("m11") is Dictionary and M11MissionState.map_error(info).is_empty():
		for index: int in range(info["m11"]["transfer_people"].size()):
			_moon_residents.append({"key": "m11/transfer/%d" % index, "feet": GrenadeFacts.vector(info["m11"]["transfer_people"][index])})
	if info.get("m12") is Dictionary and M12MissionState.map_error(info).is_empty():
		for group: String in ["shelter_people", "workers"]:
			for index: int in range(info["m12"][group].size()):
				_moon_residents.append({"key":"m12/%s/%d" % [group,index],"feet":GrenadeFacts.vector(info["m12"][group][index])})
	_tram_geometry = MissionState.geometry_for(info) if info.get("m05") is Dictionary else {}
	_foundry_geometry = MissionState.geometry_for(info) if info.get("m13") is Dictionary else {}
	_foundry_moving = false
	_walker_geometry = info.duplicate(true) if info.get("walker") is Dictionary and WalkerFacts.map_error(info).is_empty() else {}
	_walker_moving = not _walker_geometry.is_empty()
	_walker_tick = -1
	if not _foundry_geometry.is_empty():
		_moon_residents.append({"key":"m13/overseer","feet":GrenadeFacts.vector(info["m13"]["overseer"])})
	_tram_samples.clear()
	if MapGeometry.validation_error(info) == "":
		arena = {"half": float(info["half_extent"]), "solids": info["solids"].duplicate(true), "water_regions": info.get("water_regions", []).duplicate(true)}
		# A worn pack climbs only to the map's authored ceiling.
		arena["jet_ceiling"] = float(info["m19"]["jetpack_ceiling"]) if info.get("m19") is Dictionary and M19MissionState.map_error(info).is_empty() else JetMovement.DEFAULT_CEILING


func reset(reason: String, clear_measurements: bool = false) -> void:
	var was_active: bool = active()
	baseline.clear()
	state.clear()
	steps.clear()
	samples.clear()
	held.clear()
	if reason in ["map", "role", "disconnect", "connected", "connection_lost"]:
		_contacts_required = false
		_clock_samples.clear()
		_cutoff_after.clear()
		_cutoff_before.clear()
		_schedule_ready = false
	_contact_waiting = _contacts_required
	_contact_samples.clear()
	_contact_player_id = ""
	contact_error = ""
	pending_jump_latch = false
	pending_dodge_latch = false
	epoch = 0
	tick = -1
	ack_seq = 0
	first_recorded_seq = -1
	last_speed = 0.0
	next_step_usec = 0
	visual_offset = Vector3.ZERO
	_has_last_drawn = false
	_acked_from = {}
	_gliding = false
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
	presented_corrections.clear()
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
	var body: Dictionary = {
		"x": float(ack["x"]), "z": float(ack["z"]),
		"y": float(movement["y"]) - FLOOR_OFFSET,
		"vx": float(movement["vx"]), "vy": float(movement["vy"]),
		"vz": float(movement["vz"]), "yaw": float(ack["yaw"]),
		"dodge_cooldown": int(movement.get("dodge_cooldown", 0)),
	}
	# A worn pack replays from the acknowledged fuel after that same step.
	if movement.has("jet_fuel"):
		body["fuel"] = int(movement["jet_fuel"])
	return body


static func world_position(pose: Dictionary) -> Vector3:
	return Vector3(float(pose["x"]), float(pose["y"]) + FLOOR_OFFSET, float(pose["z"]))


func accept_ack(ack: Dictionary, now_usec: int) -> void:
	if _walker_moving:
		reset("walker_motion")
		return
	if _foundry_moving:
		reset("foundry_lift")
		return
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
	var was_drawing: bool = active() and not state.is_empty()
	if was_drawing and _gliding:
		_glide_to(_presented_raw(now_usec))
	var before: Vector3 = _presented_raw(now_usec) + visual_offset if was_drawing else world_position(new_body)
	if not discontinuity and incoming_tick - tick > MAX_STEPS + 1:
		reset("ack_gap")
		return
	_clock_sample(now_usec, incoming_tick)
	if not discontinuity:
		_cutoff_sample(int(ack["seq"]), incoming_tick, now_usec)
	var target: int = clock_base()
	if not _schedule_ready or absi(target - _schedule_base) > TICK_USEC * 2 or _still(new_body):
		_schedule_base = target
		_schedule_ready = true
	else:
		_schedule_base += clampi(target - _schedule_base, -CLOCK_SLEW_USEC, CLOCK_SLEW_USEC)
	if discontinuity:
		if tick >= 0:
			_contact_samples.clear()
		steps.clear()
		samples.clear()
		first_recorded_seq = -1
		held.clear()
		pending_jump_latch = false
		pending_dodge_latch = false
		visual_offset = Vector3.ZERO
		_has_last_drawn = false
		_acked_from = {}
		_gliding = false
	else:
		# The lagged eye may still be drawing this tick: keep where it began,
		# the previous authoritative body when the ticks are consecutive.
		var acked_from: Dictionary = baseline if tick == incoming_tick - 1 else {}
		for index: int in range(steps.size()):
			if int(steps[index]["tick"]) == incoming_tick:
				if acked_from.is_empty():
					acked_from = baseline if index == 0 else steps[index - 1]["state_after"]
				break
		# A teleport is drawn at once, never glided from where it began.
		var far: bool = acked_from.is_empty() or world_position(acked_from).distance_to(world_position(new_body)) > SNAP_DISTANCE
		_acked_from = {} if far else acked_from.duplicate()
		while not steps.is_empty() and int(steps[0]["tick"]) <= incoming_tick:
			steps.pop_front()
		while not samples.is_empty() and not newer_sequence(int(samples[0]["seq"]), int(ack["seq"])):
			samples.pop_front()
		pending_jump_latch = _latched_after_steps("jump")
		pending_dodge_latch = _latched_after_steps("dodge")
	epoch = incoming_epoch
	tick = incoming_tick
	ack_seq = int(ack["seq"])
	baseline = new_body
	# The ack has no stance. Seed it from the step this tick already predicted,
	# then replay. An old server and a fresh baseline stay standing.
	if matched_state.is_empty():
		new_body["ducking"] = false
	else:
		new_body["ducking"] = bool(matched_state.get("ducking", false))
	state = new_body.duplicate()
	fallback_reason = ""
	if _contacts_required:
		_contact_waiting = _contact_sample(tick + 1, now_usec).is_empty()
		if _contact_waiting:
			fallback_reason = "contact_stale"
	var speed: float = float(movement["effective_speed"])
	last_speed = speed
	fighter_model = int(movement["version"]) == MovementAck.FIGHTER
	var replay_tick: int = tick
	for step: Dictionary in steps:
		if int(step["tick"]) != replay_tick + 1:
			steps.clear()
			break
		step["speed"] = speed
		state = _step(state, step)
		step["state_after"] = state.duplicate()
		replay_tick += 1
	next_step_usec = _start_usec(tick + steps.size() + 1)
	if not discontinuity and was_drawing:
		var correction: Vector3 = before - _presented_raw(now_usec)
		presented_corrections.append((correction - visual_offset).length())
		if presented_corrections.size() > MAX_CORRECTION_SAMPLES:
			presented_corrections.pop_front()
		visual_offset = correction if correction.length() <= SNAP_DISTANCE else Vector3.ZERO
		_begin_glide(now_usec, _gliding)
		_rebase_guard(now_usec)
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


## Whether a pressed edge of `key` among unacknowledged samples is not yet
## carried by any remaining speculative step.
func _latched_after_steps(key: String) -> bool:
	for sample: Dictionary in samples:
		if not bool(sample.get(key, false)):
			continue
		var consumed: bool = false
		for step: Dictionary in steps:
			if bool(step["input"].get(key, false)) and not newer_sequence(int(sample["seq"]), int(step["input"]["seq"])):
				consumed = true
				break
		if not consumed:
			return true
	return false


func _clock_sample(now_usec: int, at_tick: int) -> void:
	var sample: int = now_usec - at_tick * TICK_USEC
	# Jitter is what the earliest-arrival filter smooths. An Ack two ticks
	# later than the schedule is a changed path or a long stall: start the
	# schedule again from it rather than predict three ticks ahead for the
	# next two seconds.
	if not _clock_samples.is_empty() and sample - _clock_base > TICK_USEC * 2:
		_clock_samples.clear()
	_clock_samples.append(sample)
	while _clock_samples.size() > CLOCK_WINDOW:
		_clock_samples.pop_front()
	_clock_base = _clock_samples.min()


## Whether the drawn body is the same at every moment of the schedule: no
## step moves it and the new Ack leaves it where it was. Moving the step
## schedule then moves nothing on screen, so it can jump to its estimate.
func _still(new_body: Dictionary) -> bool:
	if baseline.is_empty():
		return true
	var at: Vector3 = world_position(baseline)
	if world_position(new_body).distance_to(at) > 0.0001:
		return false
	if not _acked_from.is_empty() and world_position(_acked_from).distance_to(at) > 0.0001:
		return false
	for step: Dictionary in steps:
		if world_position(step["state_after"]).distance_to(at) > 0.0001:
			return false
	return true


## Bound the cutoff for `at_tick` from the send times of the Action it used
## and the first newer one, which it did not use. The Ack's own arrival is an
## upper bound too: nothing sent after it can have reached that tick. On a
## LAN the next Action is rarely sent before the Ack arrives, and the arrival
## bound is then the tight one.
func _cutoff_sample(seq: int, at_tick: int, now_usec: int) -> void:
	var after: int = 0
	var before: int = now_usec - at_tick * TICK_USEC
	var has_after: bool = false
	for sample: Dictionary in samples:
		if not sample.has("usec"):
			continue
		if int(sample["seq"]) == seq:
			after = int(sample["usec"]) - at_tick * TICK_USEC
			has_after = true
		elif newer_sequence(int(sample["seq"]), seq):
			before = mini(before, int(sample["usec"]) - at_tick * TICK_USEC)
			break
	# A bound that contradicts the window means the path changed: start over.
	if has_after and not _cutoff_before.is_empty() and after > _cutoff_before.min():
		_cutoff_after.clear()
		_cutoff_before.clear()
	if not _cutoff_after.is_empty() and before < _cutoff_after.max():
		_cutoff_after.clear()
		_cutoff_before.clear()
	if has_after:
		_cutoff_after.append(after)
	_cutoff_before.append(before)
	while _cutoff_after.size() > CLOCK_WINDOW:
		_cutoff_after.pop_front()
	while _cutoff_before.size() > CLOCK_WINDOW:
		_cutoff_before.pop_front()


## The schedule base: the bracketed input cutoff when known, otherwise the
## earliest Ack arrival.
func clock_base() -> int:
	if not _cutoff_after.is_empty() and not _cutoff_before.is_empty():
		return (_cutoff_after.max() + _cutoff_before.min()) / 2
	return _clock_base


## When tick `at_tick`'s step opens on the phase-locked prediction clock.
func _start_usec(at_tick: int) -> int:
	return _schedule_base + (at_tick - 1) * TICK_USEC


func record_action(action: Dictionary, now_usec: int, sent: bool) -> void:
	if not active() or not sent:
		return
	if not action.has("yaw"):
		reset("no_yaw")
		return
	var sample: Dictionary = _sample_action(action)
	sample["usec"] = now_usec
	if first_recorded_seq < 0:
		first_recorded_seq = int(sample["seq"])
	samples.append(sample)
	held = sample.duplicate()
	if bool(sample["jump"]):
		pending_jump_latch = true
	if bool(sample.get("dodge", false)):
		pending_dodge_latch = true
	if samples.size() > MAX_SAMPLES:
		reset("sample_overflow")
		return
	if not steps.is_empty() and now_usec < next_step_usec:
		# Several sampled Actions can belong to the same speculative server tick.
		# Replace its continuous controls without adding another 50 ms step.
		var drawn: Vector3 = _presented_raw(now_usec)
		# The offset a glide would draw now, not the one the last frame drew:
		# a revision measured against a stale offset would restart the glide
		# from the wrong place and push the eye past the rest.
		if _gliding:
			_glide_to(drawn)
		var latest_step: Dictionary = steps.back()
		var revised: Dictionary = sample.duplicate()
		revised["jump"] = _unconsumed_before_latest_step("jump")
		revised["dodge"] = _unconsumed_before_latest_step("dodge")
		pending_jump_latch = false
		pending_dodge_latch = false
		latest_step["input"] = revised
		state = baseline.duplicate()
		for step: Dictionary in steps:
			state = _step(state, step)
			step["state_after"] = state.duplicate()
		var moved: Vector3 = drawn - _presented_raw(now_usec)
		visual_offset = visual_offset + moved if (visual_offset + moved).length() <= SNAP_DISTANCE else Vector3.ZERO
		_begin_glide(now_usec, not _moving(revised))
		_rebase_guard(now_usec)
	advance(now_usec)

## Vehicle replay retains its additional held descend bit through this seam;
## history, sequence ordering and reconciliation remain shared.
func _sample_action(action: Dictionary) -> Dictionary:
	return {"seq": int(action["seq"]), "forward": bool(action["forward"]),
		"back": bool(action["back"]), "left": bool(action["left"]),
		"right": bool(action["right"]), "jump": bool(action["jump"]),
		"dodge": bool(action.get("dodge", false)),
		"duck": bool(action.get("duck", false)), "yaw": float(action["yaw"])}


func _unconsumed_before_latest_step(key: String) -> bool:
	# A true sample already covered by an earlier speculative tick cannot make
	# a later tick jump (or dodge) after a neutral release. A tap within this
	# tick still survives that release, matching the server's latch.
	for sample: Dictionary in samples:
		if not bool(sample.get(key, false)):
			continue
		var consumed: bool = false
		for index: int in range(steps.size() - 1):
			var earlier: Dictionary = steps[index]
			if bool(earlier["input"].get(key, false)) and not newer_sequence(int(sample["seq"]), int(earlier["input"]["seq"])):
				consumed = true
				break
		if not consumed:
			return true
	return false


func advance(now_usec: int) -> void:
	if not active() or held.is_empty():
		return
	next_step_usec = _start_usec(tick + steps.size() + 1)
	if now_usec - next_step_usec > TICK_USEC * MAX_STEPS:
		reset("ack_timeout")
		return
	while now_usec >= next_step_usec and steps.size() < MAX_STEPS:
		var input: Dictionary = held.duplicate()
		input["jump"] = bool(held["jump"]) or pending_jump_latch
		input["dodge"] = pending_dodge_latch
		pending_jump_latch = false
		pending_dodge_latch = false
		var step: Dictionary = {"tick": tick + steps.size() + 1, "input": input, "speed": last_speed, "usec": next_step_usec, "fighter": fighter_model}
		if _contacts_required and _contact_sample(int(step["tick"]), now_usec).is_empty():
			reset("contact_stale")
			return
		step["blockers"] = _contact_blockers(int(step["tick"]), now_usec)
		step["vehicle_hulls"] = _contact_sample(int(step["tick"]), now_usec).get("vehicle_hulls", []).duplicate(true)
		step["body_key"] = _contact_player_id
		state = _step(state, step)
		step["state_after"] = state.duplicate()
		steps.append(step)
		next_step_usec = _start_usec(tick + steps.size() + 1)
	if steps.size() >= MAX_STEPS and now_usec > next_step_usec:
		reset("ack_lag")


func _step(pose: Dictionary, step: Dictionary, dt: float = -1.0) -> Dictionary:
	var world: Dictionary = arena
	if not step.get("vehicle_hulls", []).is_empty():
		world = arena.duplicate(true)
		world["solids"].append_array(step["vehicle_hulls"])
	# A short slice is the render pose only. A full tick still carries the tram.
	if dt > 0.0 and dt < MoveStep.DT_LIVE:
		return _contact_step(pose, step, world, dt)
	if _tram_geometry.is_empty() or _tram_samples.is_empty():
		return _contact_step(pose, step, world)
	var before: Array = _tram_feet(int(step["tick"]) - 1)
	var after: Array = _tram_feet(int(step["tick"]))
	var old_solid: Dictionary = M05Tram.solid_at(_tram_geometry, before)
	world = world.duplicate(true)
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
	_contact_samples.append({"tick": incoming, "usec": now_usec, "bodies": parsed["bodies"].duplicate(true), "vehicle_hulls": VehicleState.hulls(snapshot)})
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
	var input: Dictionary = step.get("input", {})
	var short: bool = bool(input.get("duck", false)) or bool(pose.get("ducking", false))
	var height: float = MoveStep.DUCK_HEIGHT if short else MoveStep.BODY_HEIGHT
	var mover: Dictionary = {"key": step.get("body_key", ""), "from": pose, "proposed": carried, "height": height, "radius": MoveStep.RADIUS, "jump": false}
	for body: Dictionary in _near_contacts(pose, reach, step.get("blockers", [])):
		if ActorContact.sweep_time(mover, body) >= 0.0:
			return false
	return true


static func _contact_step(pose: Dictionary, step: Dictionary, world: Dictionary, dt: float = -1.0) -> Dictionary:
	var live_dt: float = MoveStep.DT_LIVE if dt <= 0.0 else dt
	var want: bool = bool(step["input"].get("duck", false))
	var was: bool = bool(pose.get("ducking", false))
	var feet_y: float = float(pose.get("y", 0.0))
	var fits: bool = not MoveStep.arena_blocked_body_at(world, float(pose["x"]), float(pose["z"]), feet_y, feet_y, MoveStep.BODY_HEIGHT)
	var ducking: bool = want or (was and not fits)
	var speed: float = float(step["speed"])
	var height: float = MoveStep.BODY_HEIGHT
	if ducking:
		speed *= MoveStep.DUCK_SPEED_SCALE
		height = MoveStep.DUCK_HEIGHT
	# The server's dodge cooldown counts down every tick, and a dodge that
	# happens starts it again. The Ack carries the count after its tick.
	var input: Dictionary = step["input"]
	var fighter: bool = bool(step.get("fighter", true))
	var cooldown: int = maxi(int(pose.get("dodge_cooldown", 0)) - 1, 0)
	if bool(input.get("dodge", false)):
		input = input.duplicate()
		input["dodge"] = fighter and cooldown == 0
		if bool(input["dodge"]) and WaterMovement.dodge_applies(pose, input, world):
			cooldown = MoveStep.DODGE_COOLDOWN_TICKS
	var proposed: Dictionary
	if pose.has("fuel"):
		proposed = JetMovement.live_step(pose, input, speed, live_dt, world, height, int(pose["fuel"]),
			float(world.get("jet_ceiling", JetMovement.DEFAULT_CEILING)), dt <= 0.0)
	else:
		proposed = WaterMovement.step(pose, input, speed, live_dt, world, height, fighter)
	proposed["ducking"] = ducking
	proposed["dodge_cooldown"] = cooldown
	var reach: float = Vector2(float(proposed["x"]) - float(pose["x"]), float(proposed["z"]) - float(pose["z"])).length()
	var bodies: Array[Dictionary] = _near_contacts(pose, reach, step.get("blockers", []))
	if bodies.is_empty():
		return proposed
	var from: Dictionary = pose.duplicate()
	from["yaw"] = proposed["yaw"]
	bodies.append({"key": step["body_key"], "from": from, "proposed": proposed, "height": height, "radius": MoveStep.RADIUS, "jump": bool(step["input"]["jump"])})
	var accepted: Dictionary = ActorContact.resolve(bodies, live_dt, WaterMovement.supported_arena(world)).back()
	accepted["ducking"] = ducking
	accepted["dodge_cooldown"] = cooldown
	for key: String in ["fuel", "thrusting"]:
		if proposed.has(key):
			accepted[key] = proposed[key]
	if accepted["x"] != proposed["x"] or accepted["z"] != proposed["z"]:
		accepted["vx"] = (float(accepted["x"]) - float(pose["x"])) / live_dt
		accepted["vz"] = (float(accepted["z"]) - float(pose["z"])) / live_dt
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
	if _gliding:
		return
	visual_offset *= exp(-OFFSET_DECAY * maxf(delta, 0.0))
	if visual_offset.length() < 0.0005:
		visual_offset = Vector3.ZERO


static func _moving(input: Dictionary) -> bool:
	return bool(input.get("forward", false)) or bool(input.get("back", false)) \
		or bool(input.get("left", false)) or bool(input.get("right", false))


## Start (or restart from a new body) a stop glide when the keys are released
## and the eye is drawn ahead of where the body will come to rest along its
## way. Anything else leaves the ordinary decay in charge.
func _begin_glide(now_usec: int, released: bool) -> void:
	_gliding = false
	if not released or held.is_empty() or visual_offset.length() < 0.0005 or visual_offset.length() > SETTLE_REACH * 2.0:
		return
	var from: Vector3 = _presented_raw(now_usec)
	var rest: Variant = _rest_position()
	if rest == null:
		return
	var way: Vector3 = (rest as Vector3) - from
	# Only an eye ahead of the body along its way to rest, and short of that
	# rest, glides. One behind or beside it is an ordinary correction, and one
	# already past the rest stands still until the body stops (the guard) and
	# only then settles back.
	var ahead: float = visual_offset.dot(way) / way.length_squared()
	if way.length() < 0.001 or ahead <= 0.0 or ahead >= 1.0:
		return
	_glide_offset = visual_offset
	_glide_from = from
	_glide_rest = rest
	_gliding = true


## While gliding, the offset is the share of the way to rest the body at
## `raw` has still to go; the glide ends when the body gets there.
func _glide_to(raw: Vector3) -> void:
	var way: Vector3 = _glide_rest - _glide_from
	var left: float = clampf((_glide_rest - raw).dot(way) / way.length_squared(), 0.0, 1.0)
	visual_offset = _glide_offset * left
	if left <= 0.0:
		_gliding = false


## Where the newest predicted body comes to rest with no keys held, or null
## when it is still moving after REST_SEARCH_TICKS (airborne or thrown).
func _rest_position() -> Variant:
	var pose: Dictionary = state
	# An Ack can leave no speculative step until the next one opens; the held
	# input stands in for it.
	var template: Dictionary = steps.back() if not steps.is_empty() else {"tick": tick,
		"input": held, "speed": last_speed, "fighter": fighter_model, "blockers": [],
		"vehicle_hulls": [], "body_key": _contact_player_id}
	var neutral: Dictionary = template["input"].duplicate()
	for key: String in ["forward", "back", "left", "right", "jump", "dodge"]:
		neutral[key] = false
	for index: int in range(REST_SEARCH_TICKS):
		var ahead: Dictionary = template.duplicate()
		ahead["input"] = neutral
		ahead["tick"] = int(template["tick"]) + index + 1
		var next: Dictionary = _step(pose, ahead)
		var still: bool = world_position(next).distance_to(world_position(pose)) < 0.0001
		pose = next
		if still:
			return world_position(pose)
	return null


## No clock returns the committed tick pose. A clock draws the predicted tick
## states interpolated on the prediction clock, plus the decaying offset.
func presented_position(now_usec: int = -1) -> Vector3:
	if now_usec < 0 or not active() or held.is_empty() or state.is_empty():
		var committed: Vector3 = world_position(state) if not state.is_empty() else Vector3.ZERO
		return committed + visual_offset
	var raw: Vector3 = _presented_raw(now_usec)
	if _gliding:
		_glide_to(raw)
	elif _has_last_drawn:
		var moved: Vector3 = raw - _last_raw
		# A second draw at the same moment (an Ack and the frame after it) has
		# not moved the body; its velocity still says which way is forward.
		var along: Vector3 = moved.normalized() if moved.length() > 0.000001 else _drawn_heading(now_usec)
		if along != Vector3.ZERO:
			# The undisturbed body is moving one way; the eye may stand still
			# while an offset ahead of the truth runs out, never step back.
			var back: float = (raw + visual_offset - _last_drawn).dot(along)
			if back < 0.0:
				visual_offset -= along * back
		elif now_usec > _last_drawn_usec and _last_offset.length() < SETTLE_REACH:
			# At rest, the last few centimetres a body was drawn ahead of its
			# stop settle back slowly rather than at the correction rate. Only
			# the offset's own decay is slowed; a move of the body itself is not.
			var limit: float = SETTLE_SPEED * float(now_usec - _last_drawn_usec) / 1000000.0
			var change: Vector3 = visual_offset - _last_offset
			if change.length() > limit:
				visual_offset = _last_offset + change.normalized() * limit
	var drawn: Vector3 = raw + visual_offset
	_last_drawn = drawn
	_last_raw = raw
	_last_offset = visual_offset
	_last_drawn_usec = now_usec
	_has_last_drawn = true
	return drawn


## The horizontal direction the drawn body is moving at `now_usec`, or zero
## at rest.
func _drawn_heading(now_usec: int) -> Vector3:
	var pose: Dictionary = presented_pose(now_usec)
	var velocity: Vector3 = Vector3(float(pose.get("vx", 0.0)), 0.0, float(pose.get("vz", 0.0)))
	return velocity.normalized() if velocity.length() > 0.01 else Vector3.ZERO


## The stance of the step open on the input clock, without the position lag:
## a crouch drops the eye the frame its tick opens. Missing stance on an old
## step stays standing.
func presented_ducking(now_usec: int = -1) -> bool:
	if now_usec >= 0 and active() and not held.is_empty() and not state.is_empty():
		return bool(presented_pose(now_usec + PRESENT_LAG_USEC).get("ducking", false))
	return bool(state.get("ducking", false))


## A correction moves the undisturbed body without time passing; it is not
## motion the guard should follow.
func _rebase_guard(now_usec: int) -> void:
	if _has_last_drawn:
		_last_raw = _presented_raw(now_usec)
		_last_offset = visual_offset


func _presented_raw(now_usec: int) -> Vector3:
	return world_position(presented_pose(now_usec))


## The predicted body at `now_usec`, drawn PRESENT_LAG_USEC behind the input
## clock: the newest step that has opened by then, between the state it starts
## from and the state it ends at. Before the first speculative step it is the
## acknowledged tick, from the body before it to the authoritative one.
func presented_pose(now_usec: int) -> Dictionary:
	if state.is_empty():
		return {}
	if baseline.is_empty():
		return state
	var at: int = now_usec - PRESENT_LAG_USEC
	var index: int = steps.size() - 1
	while index >= 0 and at < _start_usec(int(steps[index]["tick"])):
		index -= 1
	var from: Dictionary
	var to: Dictionary
	var opened: int
	if index >= 0:
		from = baseline if index == 0 else steps[index - 1]["state_after"]
		to = steps[index]["state_after"]
		opened = _start_usec(int(steps[index]["tick"]))
	elif _acked_from.is_empty():
		return baseline
	else:
		from = _acked_from
		to = baseline
		opened = _start_usec(tick)
	var t: float = clampf(float(at - opened) / float(TICK_USEC), 0.0, 1.0)
	var pose: Dictionary = to.duplicate()
	for key: String in ["x", "y", "z"]:
		pose[key] = lerpf(float(from[key]), float(to[key]), t)
	pose["yaw"] = lerp_angle(float(from["yaw"]), float(to["yaw"]), t)
	return pose


func presented_correction_percentile(percentile: float) -> float:
	if presented_corrections.is_empty():
		return 0.0
	var ordered: Array[float] = presented_corrections.duplicate()
	ordered.sort()
	var index: int = mini(int(ceilf(clampf(percentile, 0.0, 1.0) * ordered.size())) - 1, ordered.size() - 1)
	return ordered[maxi(index, 0)]


func correction_percentile(percentile: float) -> float:
	if correction_samples.is_empty():
		return 0.0
	var ordered: Array[float] = correction_samples.duplicate()
	ordered.sort()
	var index: int = mini(int(ceilf(clampf(percentile, 0.0, 1.0) * ordered.size())) - 1, ordered.size() - 1)
	return ordered[maxi(index, 0)]

func apply_m13(value: Dictionary) -> void:
	if _foundry_geometry.is_empty():
		return
	if value.get("id") != MissionState.M13_ID or not value.get("m13") is Dictionary:
		_foundry_moving = false
		reset("foundry_handoff")
		return
	var p: Dictionary = value["m13"]
	if not M13MissionState.validation_error({"tick":p.get("lift",{}).get("tick"),"state":value},_foundry_geometry).is_empty():
		return
	arena["solids"][int(_foundry_geometry["m13"]["deck"])] = M13MissionState.deck_at(_foundry_geometry,float(p["lift"]["top"]))
	_foundry_moving = p["lift"]["phase"] not in ["parked", "arrived"]
	if _foundry_moving:
		reset("foundry_lift")

func apply_walker(snapshot: Dictionary) -> void:
	if _walker_geometry.is_empty() or not WalkerFacts.validation_error(snapshot,_walker_geometry).is_empty() \
		or int(snapshot["tick"]) <= _walker_tick:
		return
	_walker_tick = int(snapshot["tick"])
	var value: Dictionary = snapshot["walker"]
	for index: Variant in _walker_geometry["walker"]["solids"]:
		arena["solids"][int(index)] = WalkerFacts.translated_solid(_walker_geometry,int(index),value["feet"])
	_walker_moving = value["phase"] == "relocating"
	if _walker_moving:
		reset("walker_motion")
