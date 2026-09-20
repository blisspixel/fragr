class_name QaCombat
extends RefCounted

## Rendered tour driver only. Sends ordinary human input through GameManager;
## health, ammunition, movement, hits and encounter state remain server-owned.
const CAMERA = preload("res://scripts/spectator_cam.gd")

var samples: Array[Dictionary] = []
var defeated: Dictionary[String, bool] = {}
var phases: Dictionary[String, bool] = {}
var shots: int = 0
var enemy_shots: int = 0
var participant_died: bool = false
var _last_tick: int = -1
var _kind: String = ""
var _player_id: String = ""
var _initial_dead: Dictionary[String, bool] = {}
var _network: Node
var _recording: bool = false
var _evade_left: bool = true
var _participant_seen: bool = false
var confirmed_deaths: Dictionary[String, int] = {}

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

static func actor_by_id(snapshot: Dictionary, id: String) -> Dictionary:
	for actor: Dictionary in snapshot.get("players", []):
		if str(actor["id"]) == id:
			return actor
	return {}

static func exposed_point(actor: Dictionary, eye: Vector3, solids: Array) -> Vector3:
	# Aim at a visible part of the real body. A low counter can hide the centre
	# while leaving the upper body exposed to an ordinary player shot.
	for fraction: float in [0.5, 0.85, 0.2]:
		var point: Vector3 = Vector3(actor.x, float(actor.y) - CAMERA.FP_SERVER_REFERENCE_Y + MoveStep.BODY_HEIGHT * fraction, actor.z)
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

static func visible_target(snapshot: Dictionary, player_id: String, solids: Array, committed_only: bool = false, max_distance: float = INF) -> Dictionary:
	var me: Dictionary = actor_by_id(snapshot, player_id)
	if me.is_empty() or int(me["hp"]) <= 0:
		return {}
	var eye: Vector3 = Vector3(me.x, float(me.y) + CAMERA.FP_EYE_HEIGHT, me.z)
	var nearest: Dictionary = {}
	var distance: float = max_distance * max_distance
	for actor: Dictionary in snapshot.get("players", []):
		if ActorState.is_participant(actor) or int(actor["hp"]) <= 0:
			continue
		if committed_only and str(actor["campaign"]["phase"]) not in ["windup", "firing"]:
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
	for actor: Dictionary in snapshot.get("players", []):
		if ActorState.is_participant(actor):
			continue
		if int(actor["hp"]) <= 0 and actor.has("name") and not confirmed_deaths.has(str(actor["name"])):
			confirmed_deaths[str(actor["name"])] = tick
		if not _recording:
			continue
		var campaign: Dictionary = actor["campaign"]
		if _kind == "union" or campaign["kind"] == _kind:
			phases[str(campaign["phase"])] = true
			if int(actor["hp"]) <= 0 and not _initial_dead.has(str(actor["id"])):
				defeated[str(actor["id"])] = true
	if not _recording:
		return
	for shot: Dictionary in snapshot.get("shot_results", []):
		if str(shot["shooter_id"]) == _player_id:
			shots += 1
		else:
			var shooter: Dictionary = actor_by_id(snapshot, str(shot["shooter_id"]))
			if not shooter.is_empty() and not ActorState.is_participant(shooter) and (_kind == "union" or shooter["campaign"]["kind"] == _kind):
				enemy_shots += 1

func engage(manager: Node, me: Dictionary, target: Dictionary, solids: Array, anchor: Vector2, evade: bool, allow_fire: bool) -> void:
	var camera: Node3D = manager.get_node("SpectatorCamera")
	var network: Node = manager.get("net_client")
	var snapshot: Dictionary = manager.get("latest_snapshot")
	var eye: Vector3 = Vector3(me.x, float(me.y) + CAMERA.FP_EYE_HEIGHT, me.z)
	var aim: Vector3 = exposed_point(target, eye, solids) - eye
	camera.set("fp_yaw", atan2(aim.z, aim.x))
	camera.set("fp_pitch", atan2(aim.y, Vector2(aim.x, aim.z).length()))
	if evade and not visible_target(snapshot, _player_id, solids, true).is_empty():
		var offset: Vector2 = Vector2(me.x, me.z) - anchor
		var direction: Vector2 = MoveStep.wish_dir({"left": _evade_left, "right": not _evade_left}, atan2(aim.z, aim.x))
		# Alternate near the entry position instead of circling through
		# adjacent rooms. Collision and the input speed remain unmodified.
		if offset.length_squared() > 4.0 and offset.dot(direction) > 0.0:
			_evade_left = not _evade_left
		Input.action_press("move_left" if _evade_left else "move_right")
	var loadout: Dictionary = network.get("equipment")
	if not loadout.is_empty() and loadout.get("reload") == null:
		if EquipmentState.magazine(loadout, loadout["selected"]) == 0:
			var reload: InputEventAction = InputEventAction.new()
			reload.action = &"reload"
			reload.pressed = true
			Input.parse_input_event(reload)
			reload = reload.duplicate()
			reload.pressed = false
			Input.parse_input_event(reload)
		elif allow_fire:
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
	for action: String in ["fire", "move_forward", "move_left", "move_right"]:
		Input.action_release(action)

func run(tree: SceneTree, manager: Node, spec: Dictionary, output: String) -> Dictionary:
	begin(manager)
	_kind = str(spec.get("kind", ""))
	var expected: int = int(spec.get("defeat", 0))
	if not valid_waypoints(spec.get("search_route", [])):
		push_error("qa_combat: invalid search route")
		return {"passed": false}
	var required: Array = spec.get("required", [])
	if not required.is_empty():
		var unique: Dictionary[String, bool] = {}
		for value: Variant in required:
			if not value is String or value.is_empty() or unique.has(value):
				push_error("qa_combat: required guards must have unique nonempty names")
				return {"passed": false}
			unique[value] = true
		expected = required.size()
	if _kind not in ["clerk", "sweeper", "union"] or expected < 1 or expected > 64:
		push_error("qa_combat: invalid encounter expectation")
		return {"passed": false}
	samples.clear()
	defeated.clear()
	phases.clear()
	_initial_dead.clear()
	shots = 0
	enemy_shots = 0
	_recording = true
	var camera: Node3D = manager.get_node("SpectatorCamera")
	var info: Dictionary = manager.get("current_map_info")
	var solids: Array = info["solids"]
	var frames: Array[Image] = []
	var captured: Dictionary[String, bool] = {}
	var deadline: int = Time.get_ticks_msec() + 25000
	var next_frame: int = 0
	var finish_at: int = -1
	var last_target_id: String = ""
	var alive: bool = true
	var starting_actor: Dictionary = actor_by_id(manager.get("latest_snapshot"), _player_id)
	var anchor: Vector2 = Vector2(starting_actor.get("x", 0.0), starting_actor.get("z", 0.0))
	_evade_left = true
	var search_route: Array = spec.get("search_route", [])
	var search_index: int = 0
	# A corpse from the preceding room cannot satisfy this encounter's claim.
	for actor: Dictionary in manager.get("latest_snapshot").get("players", []):
		if not ActorState.is_participant(actor) and int(actor["hp"]) <= 0:
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
		var target: Dictionary = visible_target(snapshot, _player_id, solids)
		if not target.is_empty():
			last_target_id = str(target["id"])
		release_inputs()
		if not target.is_empty() and alive and not complete:
			engage(manager, me, target, solids, anchor, spec.get("evade_tells", false), not spec.get("observe_first_shot", false) or enemy_shots > 0)
		elif target.is_empty() and alive and not complete and search_index < search_route.size():
			var point: Array = search_route[search_index]
			var delta: Vector3 = Vector3(float(point[0]) - float(me.x), float(point[1]) - (float(me.y) - CAMERA.FP_SERVER_REFERENCE_Y), float(point[2]) - float(me.z))
			if Vector2(delta.x, delta.z).length() < 0.5 and absf(delta.y) < 0.2:
				search_index += 1
				anchor = Vector2(me.x, me.z)
			else:
				camera.set("fp_yaw", atan2(delta.z, delta.x))
				camera.set("fp_pitch", 0.0)
				Input.action_press("move_forward")
		await tree.process_frame
		var rendered: Dictionary = actor_by_id(manager.get("latest_snapshot"), last_target_id)
		var capture_key: String = ""
		if not rendered.is_empty():
			capture_key = str(rendered["campaign"]["kind"]) + "_" + str(rendered["campaign"]["phase"])
		# Single-shot firing can last only one server tick. Capture a new phase
		# immediately as well as sampling the ongoing motion at a steady cadence.
		if frames.size() < 128 and (Time.get_ticks_msec() >= next_frame or (not capture_key.is_empty() and not captured.has(capture_key))):
			next_frame = Time.get_ticks_msec() + 150
			await RenderingServer.frame_post_draw
			var frame: Image = tree.root.get_texture().get_image()
			# Label the rendered state, not the observation from before the await.
			snapshot = manager.get("latest_snapshot")
			target = actor_by_id(snapshot, last_target_id)
			me = actor_by_id(snapshot, _player_id)
			if not target.is_empty():
				var identity: Dictionary = target["campaign"]
				var key: String = str(identity["kind"]) + "_" + str(identity["phase"])
				if not captured.has(key):
					captured[key] = true
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
	var passed: bool = alive and not participant_died and completed and saved
	if not passed:
		push_error("qa_combat: %s defeated %d, required %s confirmed %s, shots %d, alive %s, saved %s" % [_kind, defeated.size(), required, confirmed_names.keys(), shots, alive, saved])
	return {"passed": passed, "kind": _kind, "defeated": defeated.size(), "required": required, "confirmed": confirmed_names, "shots": shots, "enemy_shots": enemy_shots, "observed_phases": phases.keys(), "captured_phases": captured.keys(), "samples": samples}
