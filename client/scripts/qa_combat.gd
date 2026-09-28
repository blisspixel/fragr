class_name QaCombat
extends RefCounted

## Rendered tour driver only. Sends ordinary human input through GameManager;
## health, ammunition, movement, hits and encounter state remain server-owned.
const CAMERA = preload("res://scripts/spectator_cam.gd")

var samples: Array[Dictionary] = []
var defeated: Dictionary[String, bool] = {}
var phases: Dictionary[String, bool] = {}
var phases_by_kind: Dictionary[String, bool] = {}
var shots: int = 0
var enemy_shots: int = 0
var companion_shots: Array[Dictionary] = []
var participant_died: bool = false
var _last_tick: int = -1
var _kind: String = ""
var _player_id: String = ""
var _initial_dead: Dictionary[String, bool] = {}
var _network: Node
var _recording: bool = false
var _evade_left: bool = true
var _evade_started: int = -1
var _participant_seen: bool = false
var confirmed_deaths: Dictionary[String, int] = {}
var first_crawler_leap_started: bool = false
var first_crawler_leap_finished: bool = false
var first_crawler_leap_start_hp: int = -1
var first_crawler_leap_low_hp: int = -1
var first_crawler_encounter_start_hp: int = -1
var first_crawler_encounter_low_hp: int = -1
var first_crawler_encounter_finished: bool = false
var _previous_participant_hp: int = -1
var _first_crawler_last_phase: String = ""
var first_crawler_trace: Array[Dictionary] = []

func finish() -> void:
	if is_instance_valid(_network) and _network.snapshot_received.is_connected(_observe):
		_network.snapshot_received.disconnect(_observe)
	_network = null
	_recording = false

func begin(manager: Node) -> void:
	var network: Node = manager.get("net_client")
	var player_id: String = str(network.get("player_id"))
	if network == _network and player_id == _player_id:
		return
	finish()
	_network = network
	_player_id = player_id
	_last_tick = -1
	participant_died = false
	_participant_seen = false
	confirmed_deaths.clear()
	companion_shots.clear()
	first_crawler_leap_started = false
	first_crawler_leap_finished = false
	first_crawler_leap_start_hp = -1
	first_crawler_leap_low_hp = -1
	first_crawler_encounter_start_hp = -1
	first_crawler_encounter_low_hp = -1
	first_crawler_encounter_finished = false
	_previous_participant_hp = -1
	_first_crawler_last_phase = ""
	first_crawler_trace.clear()
	_network.snapshot_received.connect(_observe)

func confirmed(required: Array) -> Dictionary[String, int]:
	var result: Dictionary[String, int] = {}
	for name: String in required:
		if confirmed_deaths.has(name):
			result[name] = confirmed_deaths[name]
	return result

static func valid_waypoints(value: Variant) -> bool:
	if not value is Array or value.size() > 32:
		return false
	for point: Variant in value:
		if not point is Array or point.size() != 3:
			return false
		for coordinate: Variant in point:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
				return false
	return true

## Server-tick cadence for a bounded tour probe. The player keeps ordinary
## movement, aim, health, ammunition and weapon cooldowns.
static func valid_fire_cadence(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3:
		return false
	for key: String in ["period_ticks", "fire_ticks", "duration_ticks"]:
		if not value.has(key) or not (value[key] is int or value[key] is float):
			return false
		var number: float = float(value[key])
		if not is_finite(number) or number < 0.0 or number > 400.0 or number != floorf(number):
			return false
	var period: int = value["period_ticks"]
	var fire: int = value["fire_ticks"]
	var duration: int = value["duration_ticks"]
	return period >= 4 and period <= 80 and fire >= 1 and fire < period and \
		duration >= 20 and duration <= 400

static func cadence_allows_fire(cadence: Dictionary, elapsed_ticks: int) -> bool:
	if elapsed_ticks >= int(cadence["duration_ticks"]):
		return true
	return elapsed_ticks % int(cadence["period_ticks"]) < int(cadence["fire_ticks"])

static func actor_by_id(snapshot: Dictionary, id: String) -> Dictionary:
	for actor: Dictionary in snapshot.get("players", []):
		if str(actor["id"]) == id:
			return actor
	return {}

static func exposed_point(actor: Dictionary, eye: Vector3, solids: Array) -> Vector3:
	# Aim at a visible part of the real body. A low counter can hide the centre
	# while leaving the upper body exposed to an ordinary player shot.
	var height: float = AimAssist.CRAWLER_HEIGHT if actor.get("campaign", {}).get("kind") == "crawler" else MoveStep.BODY_HEIGHT
	for fraction: float in [0.5, 0.85, 0.2]:
		var point: Vector3 = Vector3(actor.x, float(actor.y) - CAMERA.FP_SERVER_REFERENCE_Y + height * fraction, actor.z)
		var clear: bool = true
		for solid: Dictionary in solids:
			var lower: Vector3 = Vector3(solid.min_x, solid.get("bottom", 0.0), solid.min_z)
			var upper: Vector3 = Vector3(solid.max_x, solid.top, solid.max_z)
			if AABB(lower, upper - lower).intersects_segment(eye, point) != null:
				clear = false
				break
		if clear:
			return point
	return Vector3.INF

static func visible_target(snapshot: Dictionary, player_id: String, solids: Array, committed_only: bool = false, max_distance: float = INF, allowed_names: Array = []) -> Dictionary:
	var me: Dictionary = actor_by_id(snapshot, player_id)
	if me.is_empty() or int(me["hp"]) <= 0:
		return {}
	var eye: Vector3 = Vector3(me.x, float(me.y) + CAMERA.FP_EYE_HEIGHT, me.z)
	var nearest: Dictionary = {}
	var distance: float = max_distance * max_distance
	for actor: Dictionary in snapshot.get("players", []):
		# The campaign has both Union hostiles and a free companion.
		if not ActorState.is_union(actor) or int(actor["hp"]) <= 0:
			continue
		if not allowed_names.is_empty() and actor.get("name", "") not in allowed_names:
			continue
		if committed_only and str(actor["campaign"]["phase"]) not in ["windup", "leaping", "firing"]:
			continue
		var point: Vector3 = exposed_point(actor, eye, solids)
		if not point.is_finite() or eye.distance_squared_to(point) >= distance:
			continue
		nearest = actor
		distance = eye.distance_squared_to(point)
	return nearest

func _observe(snapshot: Dictionary) -> void:
	var tick: int = int(snapshot["tick"])
	if tick <= _last_tick:
		return
	_last_tick = tick
	var participant: Dictionary = actor_by_id(snapshot, _player_id)
	if not participant.is_empty():
		_participant_seen = true
		participant_died = participant_died or int(participant["hp"]) <= 0
	elif _participant_seen:
		# The server omits participants while they are awaiting respawn.
		participant_died = true
	_track_first_crawler_leap(snapshot, participant)
	for actor: Dictionary in snapshot.get("players", []):
		if not ActorState.is_union(actor):
			continue
		if int(actor["hp"]) <= 0 and actor.has("name") and not confirmed_deaths.has(str(actor["name"])):
			confirmed_deaths[str(actor["name"])] = tick
		if not _recording:
			continue
		var campaign: Dictionary = actor["campaign"]
		if _kind == "union" or campaign["kind"] == _kind:
			phases[str(campaign["phase"])] = true
			phases_by_kind[str(campaign["kind"]) + "_" + str(campaign["phase"])] = true
			if int(actor["hp"]) <= 0 and not _initial_dead.has(str(actor["id"])):
				defeated[str(actor["id"])] = true
	if not _recording:
		return
	for shot: Dictionary in snapshot.get("shot_results", []):
		if str(shot["shooter_id"]) == _player_id:
			shots += 1
		else:
			var shooter: Dictionary = actor_by_id(snapshot, str(shot["shooter_id"]))
			if not shooter.is_empty() and ActorState.is_companion(shooter):
				var trace: Dictionary = shot.get("trace", {}) if shot.get("trace") is Dictionary else {}
				companion_shots.append({"tick": tick, "shooter_id": str(shot["shooter_id"]),
					"weapon": str(trace.get("weapon", "")), "target_id": str(shot.get("target_id", "")),
					"target": str(shot.get("target", "")), "hit": shot.get("hit") == true,
					"damage": int(shot.get("damage", 0)), "killed": shot.get("killed") == true})
			elif not shooter.is_empty() and ActorState.is_union(shooter) \
				and (_kind == "union" or shooter["campaign"]["kind"] == _kind):
				enemy_shots += 1

func _track_first_crawler_leap(snapshot: Dictionary, participant: Dictionary) -> void:
	if participant.is_empty():
		return
	var hp: int = int(participant["hp"])
	var phase: String = ""
	var crawler_found: bool = false
	var crawler_dead: bool = false
	var crawler_body: Dictionary = {}
	for actor: Dictionary in snapshot.get("players", []):
		if actor.get("name", "") == "stair_crawler_first":
			crawler_found = true
			crawler_dead = int(actor["hp"]) <= 0
			crawler_body = actor
			phase = str(actor.get("campaign", {}).get("phase", ""))
			break
	if crawler_found and (phase != _first_crawler_last_phase or (_previous_participant_hp >= 0 and hp < _previous_participant_hp)):
		var entry: Dictionary = {
			"tick": int(snapshot["tick"]),
			"phase": phase,
			"hp": hp,
			"player_feet": [float(participant["x"]), float(participant["y"]) - CAMERA.FP_SERVER_REFERENCE_Y, float(participant["z"])],
			"crawler_feet": [float(crawler_body["x"]), float(crawler_body["y"]) - CAMERA.FP_SERVER_REFERENCE_Y, float(crawler_body["z"])],
		}
		first_crawler_trace.append(entry)
		if is_instance_valid(_network):
			print("qa_combat: first Crawler trace ", JSON.stringify(entry))
		_first_crawler_last_phase = phase
	if crawler_found and phase not in ["idle", "dead"] and not first_crawler_encounter_finished:
		if first_crawler_encounter_start_hp < 0:
			# Start with the authored activation, not earlier guard-room damage.
			first_crawler_encounter_start_hp = hp
			first_crawler_encounter_low_hp = first_crawler_encounter_start_hp
		first_crawler_encounter_low_hp = mini(first_crawler_encounter_low_hp, hp)
	elif crawler_found and first_crawler_encounter_start_hp >= 0 and not first_crawler_encounter_finished:
		first_crawler_encounter_low_hp = mini(first_crawler_encounter_low_hp, hp)
	first_crawler_encounter_finished = first_crawler_encounter_finished or \
		(crawler_found and crawler_dead and first_crawler_encounter_start_hp >= 0)
	if not first_crawler_leap_finished:
		if phase == "leaping":
			if not first_crawler_leap_started:
				first_crawler_leap_started = true
				first_crawler_leap_start_hp = _previous_participant_hp if _previous_participant_hp >= 0 else hp
				first_crawler_leap_low_hp = first_crawler_leap_start_hp
			first_crawler_leap_low_hp = mini(first_crawler_leap_low_hp, hp)
		elif first_crawler_leap_started:
			# Include the first post-leap snapshot: landing contact is server-owned.
			first_crawler_leap_low_hp = mini(first_crawler_leap_low_hp, hp)
			first_crawler_leap_finished = true
	_previous_participant_hp = hp

func first_crawler_leap_no_contact_proven() -> bool:
	return first_crawler_leap_finished and first_crawler_leap_start_hp >= 0 and \
		first_crawler_leap_low_hp == first_crawler_leap_start_hp

func first_crawler_encounter_no_damage_proven() -> bool:
	return first_crawler_encounter_finished and first_crawler_leap_no_contact_proven() and \
		first_crawler_encounter_start_hp >= 0 and \
		first_crawler_encounter_low_hp == first_crawler_encounter_start_hp

func engage(manager: Node, me: Dictionary, target: Dictionary, solids: Array, anchor: Vector2, evade: bool, allow_fire: bool) -> void:
	var camera: Node3D = manager.get_node("SpectatorCamera")
	var network: Node = manager.get("net_client")
	var snapshot: Dictionary = manager.get("latest_snapshot")
	var eye: Vector3 = Vector3(me.x, float(me.y) + CAMERA.FP_EYE_HEIGHT, me.z)
	var aim: Vector3 = exposed_point(target, eye, solids) - eye
	camera.set("fp_yaw", atan2(aim.z, aim.x))
	camera.set("fp_pitch", atan2(aim.y, Vector2(aim.x, aim.z).length()))
	var tell: Dictionary = visible_target(snapshot, _player_id, solids, true) if evade else {}
	if not tell.is_empty():
		var started: int = int(tell["campaign"]["phase_started"])
		if started != _evade_started:
			_evade_started = started
			var offset: Vector2 = Vector2(me.x, me.z) - anchor
			var direction: Vector2 = MoveStep.wish_dir({"left": _evade_left, "right": not _evade_left}, atan2(aim.z, aim.x))
			# Pick a side once per tell, heading back towards the entry
			# position instead of circling through adjacent rooms. Reversing
			# mid-tell would carry a long tell's locked aim back onto the
			# body. Collision and the input speed remain unmodified.
			if offset.length_squared() > 1.0 and offset.dot(direction) > 0.0:
				_evade_left = not _evade_left
		Input.action_press("move_left" if _evade_left else "move_right")
	var loadout: Dictionary = network.get("equipment")
	if not loadout.is_empty() and EquipmentState.shots(loadout, loadout["selected"]) != 0 and allow_fire:
		Input.action_press("fire")

func travel(manager: Node, anchor: Vector2) -> bool:
	release_inputs()
	var snapshot: Dictionary = manager.get("latest_snapshot")
	var me: Dictionary = actor_by_id(snapshot, _player_id)
	var solids: Array = manager.get("current_map_info")["solids"]
	# Continue towards the room instead of spending a walking deadline sniping
	# guards beyond ordinary enemy attack range. Named combat stages still
	# require every authored guard, including those encountered later.
	var target: Dictionary = visible_target(snapshot, _player_id, solids, false, 24.0)
	if target.is_empty() or participant_died:
		return false
	engage(manager, me, target, solids, anchor, true, true)
	return true

static func release_inputs() -> void:
	for action: String in ["fire", "move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(action)

static func route_buttons(course: Vector2, yaw: float) -> Dictionary[String, bool]:
	var direction: Vector2 = course.normalized()
	var forward: float = direction.dot(Vector2(cos(yaw), sin(yaw)))
	var right: float = direction.dot(Vector2(-sin(yaw), cos(yaw)))
	return {
		"move_forward": forward > 0.2,
		"move_back": forward < -0.2,
		"move_right": right > 0.2,
		"move_left": right < -0.2,
	}

static func follow_route(me: Dictionary, camera: Node3D, route: Array, index: int,
		look_at: Vector3 = Vector3.INF) -> int:
	if index >= route.size():
		return index
	var point: Array = route[index]
	var delta: Vector3 = Vector3(float(point[0]) - float(me.x),
		float(point[1]) - (float(me.y) - CAMERA.FP_SERVER_REFERENCE_Y),
		float(point[2]) - float(me.z))
	var yaw: float = atan2(delta.z, delta.x)
	var pitch: float = 0.0
	if look_at.is_finite():
		var toward: Vector2 = Vector2(look_at.x - float(me.x), look_at.z - float(me.z))
		if toward.length_squared() > 0.04:
			yaw = atan2(toward.y, toward.x)
			pitch = atan2(look_at.y - (float(me.y) + CAMERA.FP_EYE_HEIGHT), toward.length())
	camera.set("fp_yaw", yaw)
	camera.set("fp_pitch", pitch)
	if Vector2(delta.x, delta.z).length() < 0.5 and absf(delta.y) < 0.2:
		return index + 1
	var buttons: Dictionary[String, bool] = route_buttons(Vector2(delta.x, delta.z), yaw)
	for action: String in buttons:
		if buttons[action]:
			Input.action_press(action)
	return index

func run(tree: SceneTree, manager: Node, spec: Dictionary, output: String) -> Dictionary:
	begin(manager)
	var fire_cadence: Dictionary = {}
	if spec.has("fire_cadence"):
		if not valid_fire_cadence(spec["fire_cadence"]):
			push_error("qa_combat: invalid bounded fire cadence")
			return {"passed": false}
		fire_cadence = spec["fire_cadence"]
	if spec.has("require_companion_damage") and not spec["require_companion_damage"] is bool:
		push_error("qa_combat: companion damage requirement must be a boolean")
		return {"passed": false}
	_kind = str(spec.get("kind", ""))
	var expected: int = int(spec.get("defeat", 0))
	if not valid_waypoints(spec.get("search_route", [])):
		push_error("qa_combat: invalid search route")
		return {"passed": false}
	if not valid_waypoints(spec.get("approach_route", [])):
		push_error("qa_combat: invalid approach route")
		return {"passed": false}
	var required: Array = spec.get("required", [])
	if spec.get("target_required_only", false) and required.is_empty():
		push_error("qa_combat: target_required_only needs named required enemies")
		return {"passed": false}
	var target_names: Array = required if spec.get("target_required_only", false) else []
	if spec.get("require_companion_damage", false) and required.is_empty():
		push_error("qa_combat: companion damage proof requires named targets")
		return {"passed": false}
	var required_phases_value: Variant = spec.get("required_phases", [])
	if not required_phases_value is Array or required_phases_value.size() > ActorState.PHASES.size():
		push_error("qa_combat: invalid required phases")
		return {"passed": false}
	var required_phases: Array = required_phases_value
	var phase_kind: String = str(spec.get("phase_kind", _kind))
	var observe_phase: String = str(spec.get("observe_phase", ""))
	if not observe_phase.is_empty() and observe_phase not in ActorState.PHASES:
		push_error("qa_combat: invalid observed phase")
		return {"passed": false}
	if not required_phases.is_empty() and phase_kind not in ActorState.KINDS:
		push_error("qa_combat: required phases need a specific enemy kind")
		return {"passed": false}
	for phase: Variant in required_phases:
		if not phase is String or phase not in ActorState.PHASES:
			push_error("qa_combat: invalid required phase")
			return {"passed": false}
	if not required.is_empty():
		var unique: Dictionary[String, bool] = {}
		for value: Variant in required:
			if not value is String or value.is_empty() or unique.has(value):
				push_error("qa_combat: required guards must have unique nonempty names")
				return {"passed": false}
			unique[value] = true
		expected = required.size()
	if (_kind not in ActorState.KINDS and _kind != "union") or expected < 1 or expected > 64:
		push_error("qa_combat: invalid encounter expectation")
		return {"passed": false}
	samples.clear()
	defeated.clear()
	phases.clear()
	phases_by_kind.clear()
	_initial_dead.clear()
	shots = 0
	enemy_shots = 0
	_recording = true
	var camera: Node3D = manager.get_node("SpectatorCamera")
	var info: Dictionary = manager.get("current_map_info")
	var solids: Array = info["solids"]
	var frames: Array[Image] = []
	var companion_fire_file: String = ""
	var captured: Dictionary[String, bool] = {}
	var captured_ticks: Dictionary[String, int] = {}
	var deadline: int = Time.get_ticks_msec() + 25000
	var next_frame: int = 0
	var finish_at: int = -1
	var last_target_id: String = ""
	var alive: bool = true
	var starting_actor: Dictionary = actor_by_id(manager.get("latest_snapshot"), _player_id)
	var start_tick: int = int(manager.get("latest_snapshot").get("tick", 0))
	var companion_shots_before: int = companion_shots.size()
	var participant_hp_start: int = int(starting_actor.get("hp", 0))
	var participant_armor_start: int = int(starting_actor.get("armor", 0))
	var anchor: Vector2 = Vector2(starting_actor.get("x", 0.0), starting_actor.get("z", 0.0))
	_evade_left = true
	_evade_started = -1
	var search_route: Array = spec.get("search_route", [])
	var search_index: int = 0
	var approach_route: Array = spec.get("approach_route", [])
	var approach_index: int = 0
	# A corpse from the preceding room cannot satisfy this encounter's claim.
	for actor: Dictionary in manager.get("latest_snapshot").get("players", []):
		if ActorState.is_union(actor) and int(actor["hp"]) <= 0:
			_initial_dead[str(actor["id"])] = true
	while Time.get_ticks_msec() < deadline and alive and not participant_died:
		var snapshot: Dictionary = manager.get("latest_snapshot")
		_observe(snapshot)
		var complete: bool = confirmed(required).size() == expected if not required.is_empty() else defeated.size() >= expected
		if complete:
			if finish_at < 0:
				finish_at = Time.get_ticks_msec() + 800
			elif Time.get_ticks_msec() >= finish_at:
				break
		var me: Dictionary = actor_by_id(snapshot, _player_id)
		alive = not me.is_empty() and int(me["hp"]) > 0
		var target: Dictionary = visible_target(snapshot, _player_id, solids, false, INF, target_names)
		if not target.is_empty():
			last_target_id = str(target["id"])
		release_inputs()
		if alive and not complete and approach_index < approach_route.size():
			var committed: Dictionary = visible_target(snapshot, _player_id, solids, true)
			if not committed.is_empty():
				engage(manager, me, committed, solids, anchor, true, false)
			else:
				var previous_index: int = approach_index
				var focus: Vector3 = Vector3.INF
				for actor: Dictionary in snapshot.get("players", []):
					if actor.get("name", "") == "stair_crawler_first" and \
						actor.get("campaign", {}).get("phase", "") == "windup":
						focus = Vector3(float(actor.x), float(actor.y) - CAMERA.FP_SERVER_REFERENCE_Y + AimAssist.CRAWLER_HEIGHT * 0.5, float(actor.z))
						break
				approach_index = follow_route(me, camera, approach_route, approach_index, focus)
				if approach_index != previous_index:
					anchor = Vector2(me.x, me.z)
		elif not target.is_empty() and alive and not complete:
			var may_fire: bool = (not spec.get("observe_first_shot", false) or enemy_shots > 0) and \
				(observe_phase.is_empty() or phases.has(observe_phase))
			if not fire_cadence.is_empty():
				may_fire = may_fire and cadence_allows_fire(fire_cadence, maxi(0, int(snapshot["tick"]) - start_tick))
			engage(manager, me, target, solids, anchor, spec.get("evade_tells", false), may_fire)
		elif target.is_empty() and alive and not complete and search_index < search_route.size():
			var previous_index: int = search_index
			search_index = follow_route(me, camera, search_route, search_index)
			if search_index != previous_index:
				anchor = Vector2(me.x, me.z)
		var handled_phase: String = ""
		var handled_actor: Dictionary = actor_by_id(snapshot, last_target_id)
		if not handled_actor.is_empty():
			handled_phase = str(handled_actor["campaign"]["kind"]) + "_" + str(handled_actor["campaign"]["phase"])
		await tree.process_frame
		var rendered: Dictionary = actor_by_id(manager.get("latest_snapshot"), last_target_id)
		var capture_key: String = ""
		if not rendered.is_empty():
			capture_key = str(rendered["campaign"]["kind"]) + "_" + str(rendered["campaign"]["phase"])
		# Single-shot firing can last only one server tick. Capture a new phase
		# immediately as well as sampling the ongoing motion at a steady cadence.
		var new_companion_hit: bool = false
		if companion_fire_file.is_empty():
			for companion_shot: Dictionary in companion_shots.slice(companion_shots_before):
				if int(companion_shot["damage"]) > 0:
					new_companion_hit = true
					break
		if new_companion_hit or (frames.size() < 128 and (Time.get_ticks_msec() >= next_frame or \
			(not capture_key.is_empty() and not captured.has(capture_key)))):
			next_frame = Time.get_ticks_msec() + 150
			await RenderingServer.frame_post_draw
			var frame: Image = tree.root.get_texture().get_image()
			if new_companion_hit:
				var support_file: String = output + "_companion_fire.png"
				if frame.save_png(support_file) == OK:
					companion_fire_file = support_file
				else:
					push_error("qa_combat: failed to save companion fire frame")
			# Label the rendered state, not the observation from before the await.
			snapshot = manager.get("latest_snapshot")
			target = actor_by_id(snapshot, last_target_id)
			me = actor_by_id(snapshot, _player_id)
			if not target.is_empty():
				var identity: Dictionary = target["campaign"]
				var key: String = str(identity["kind"]) + "_" + str(identity["phase"])
				# A phase can change while this frame is drawing. Name only a
				# frame whose phase the controller already handled before drawing.
				if key == handled_phase and phase_ready_for_capture(identity, int(snapshot["tick"])) and not captured.has(key):
					captured[key] = true
					captured_ticks[key] = int(snapshot["tick"])
					if frame.save_png(output + "_" + key + ".png") != OK:
						push_error("qa_combat: failed to save phase capture")
			frame.resize(320, 180, Image.INTERPOLATE_BILINEAR)
			frame.convert(Image.FORMAT_RGB8)
			frames.append(frame)
			var sample: Dictionary = {"ms": Time.get_ticks_msec(), "tick": snapshot["tick"], "target": target.duplicate(true), "hp": me.get("hp", 0)}
			var pawn: Node = manager.get("players").get(last_target_id)
			if is_instance_valid(pawn):
				var body: Sprite3D = pawn.get_node("Body")
				sample["body_frame"] = body.frame
				sample["body_scale"] = body.scale.x
			samples.append(sample)
	release_inputs()
	_recording = false
	var saved: bool = false
	if not frames.is_empty():
		var sheet: Image = Image.create(1280, 180 * ceili(float(frames.size()) / 4.0), false, Image.FORMAT_RGB8)
		sheet.fill(Color("17191b"))
		for index: int in range(frames.size()):
			sheet.blit_rect(frames[index], Rect2i(0, 0, 320, 180), Vector2i((index % 4) * 320, (index / 4) * 180))
		saved = sheet.save_png(output + "_combat.png") == OK
	var confirmed_names: Dictionary[String, int] = confirmed(required)
	var completed: bool = confirmed_names.size() == expected if not required.is_empty() else defeated.size() == expected and shots > 0
	var phases_proven: bool = required_phases_proven(phases_by_kind, captured, phase_kind, required_phases)
	var no_damage_proven: bool = not bool(spec.get("expect_first_crawler_no_damage", false)) or \
		first_crawler_encounter_no_damage_proven()
	var approach_complete: bool = approach_index == approach_route.size()
	var stage_companion_shots: Array[Dictionary] = companion_shots.slice(companion_shots_before)
	var companion_damage: bool = false
	for shot: Dictionary in stage_companion_shots:
		if int(shot["damage"]) > 0 and str(shot["target"]) in required:
			companion_damage = true
	var participant_end: Dictionary = actor_by_id(manager.get("latest_snapshot"), _player_id)
	var passed: bool = alive and not participant_died and completed and saved and \
		phases_proven and no_damage_proven and approach_complete and \
		(not spec.get("require_companion_damage", false) or companion_damage)
	if spec.get("require_companion_damage", false):
		print("qa_combat: companion support ", JSON.stringify({"shots": stage_companion_shots,
			"participant_hp_start": participant_hp_start, "participant_armor_start": participant_armor_start,
			"participant_hp_end": int(participant_end.get("hp", 0)),
			"participant_armor_end": int(participant_end.get("armor", 0)), "passed": companion_damage}))
	if not passed:
		push_error("qa_combat: %s defeated %d, required %s confirmed %s, shots %d, alive %s, saved %s, approach %s, encounter HP %d to %d, no damage %s" % [
			_kind, defeated.size(), required, confirmed_names.keys(), shots, alive, saved,
			approach_complete, first_crawler_encounter_start_hp,
			first_crawler_encounter_low_hp, no_damage_proven,
		])
	return {
		"passed": passed,
		"kind": _kind,
		"defeated": defeated.size(),
		"required": required,
		"confirmed": confirmed_names,
		"shots": shots,
		"enemy_shots": enemy_shots,
		"companion_shots": stage_companion_shots,
		"companion_damage": companion_damage,
		"companion_fire_file": companion_fire_file,
		"participant_hp_start": participant_hp_start,
		"participant_armor_start": participant_armor_start,
		"participant_hp_end": int(participant_end.get("hp", 0)),
		"participant_armor_end": int(participant_end.get("armor", 0)),
		"observed_phases": phases.keys(),
		"observed_kind_phases": phases_by_kind.keys(),
		"captured_phases": captured.keys(),
		"captured_phase_ticks": captured_ticks,
		"approach_complete": approach_complete,
		"first_crawler_leap_started": first_crawler_leap_started,
		"first_crawler_leap_finished": first_crawler_leap_finished,
		"first_crawler_leap_start_hp": first_crawler_leap_start_hp,
		"first_crawler_leap_low_hp": first_crawler_leap_low_hp,
		"first_crawler_encounter_start_hp": first_crawler_encounter_start_hp,
		"first_crawler_encounter_low_hp": first_crawler_encounter_low_hp,
		"first_crawler_no_damage_proven": first_crawler_encounter_no_damage_proven(),
		"first_crawler_trace": first_crawler_trace.duplicate(true),
		"samples": samples.duplicate(true),
	}

static func required_phases_proven(observed: Dictionary, captured: Dictionary,
		kind: String, required: Array) -> bool:
	for phase: String in required:
		var key: String = kind + "_" + phase
		if not observed.has(key) or not captured.has(key):
			return false
	return true

static func phase_ready_for_capture(identity: Dictionary, tick: int) -> bool:
	# The first network frame can precede a readable pose and camera turn.
	# Five of twelve windup ticks still leave a visible reaction window.
	if identity.get("kind", "") == "crawler" and identity.get("phase", "") == "windup":
		return tick - int(identity.get("phase_started", tick)) >= 5
	return true
