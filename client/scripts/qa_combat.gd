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

static func actor_by_id(snapshot: Dictionary, id: String) -> Dictionary:
	for actor: Dictionary in snapshot.get("players", []):
		if str(actor["id"]) == id:
			return actor
	return {}

static func visible_target(snapshot: Dictionary, player_id: String, solids: Array) -> Dictionary:
	var me: Dictionary = actor_by_id(snapshot, player_id)
	if me.is_empty() or int(me["hp"]) <= 0:
		return {}
	var eye: Vector3 = Vector3(me.x, float(me.y) + CAMERA.FP_EYE_HEIGHT, me.z)
	var nearest: Dictionary = {}
	var distance: float = INF
	for actor: Dictionary in snapshot.get("players", []):
		if ActorState.is_participant(actor) or int(actor["hp"]) <= 0:
			continue
		var centre: Vector3 = Vector3(actor.x, float(actor.y) - CAMERA.FP_SERVER_REFERENCE_Y + MoveStep.BODY_HEIGHT * 0.5, actor.z)
		if eye.distance_squared_to(centre) >= distance:
			continue
		var clear: bool = true
		for solid: Dictionary in solids:
			var lower: Vector3 = Vector3(solid.min_x, solid.get("bottom", 0.0), solid.min_z)
			var upper: Vector3 = Vector3(solid.max_x, solid.top, solid.max_z)
			if AABB(lower, upper - lower).intersects_segment(eye, centre) != null:
				clear = false
				break
		if clear:
			nearest = actor
			distance = eye.distance_squared_to(centre)
	return nearest

func _observe(snapshot: Dictionary) -> void:
	var tick: int = int(snapshot["tick"])
	if tick <= _last_tick:
		return
	_last_tick = tick
	for actor: Dictionary in snapshot.get("players", []):
		if str(actor["id"]) == _player_id and int(actor["hp"]) <= 0:
			participant_died = true
		if ActorState.is_participant(actor):
			continue
		var campaign: Dictionary = actor["campaign"]
		if campaign["kind"] == _kind:
			phases[str(campaign["phase"])] = true
			if int(actor["hp"]) <= 0:
				defeated[str(actor["id"])] = true
	for shot: Dictionary in snapshot.get("shot_results", []):
		if str(shot["shooter_id"]) == _player_id:
			shots += 1
		else:
			var shooter: Dictionary = actor_by_id(snapshot, str(shot["shooter_id"]))
			if not ActorState.is_participant(shooter) and shooter["campaign"]["kind"] == _kind:
				enemy_shots += 1

func run(tree: SceneTree, manager: Node, spec: Dictionary, output: String) -> Dictionary:
	_kind = str(spec.get("kind", ""))
	var expected: int = int(spec.get("defeat", 0))
	if _kind not in ["clerk", "sweeper"] or expected < 1 or expected > 64:
		push_error("qa_combat: invalid encounter expectation")
		return {"passed": false}
	var network: Node = manager.get("net_client")
	_player_id = str(network.get("player_id"))
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
	network.snapshot_received.connect(_observe)
	while Time.get_ticks_msec() < deadline and alive and not participant_died:
		var snapshot: Dictionary = manager.get("latest_snapshot")
		_observe(snapshot)
		if defeated.size() >= expected:
			if finish_at < 0:
				finish_at = Time.get_ticks_msec() + 800
			elif Time.get_ticks_msec() >= finish_at:
				break
		var me: Dictionary = actor_by_id(snapshot, _player_id)
		alive = not me.is_empty() and int(me["hp"]) > 0
		var target: Dictionary = visible_target(snapshot, _player_id, solids)
		if not target.is_empty():
			last_target_id = str(target["id"])
		Input.action_release("fire")
		if not target.is_empty() and alive:
			var eye: Vector3 = Vector3(me.x, float(me.y) + CAMERA.FP_EYE_HEIGHT, me.z)
			var aim: Vector3 = Vector3(target.x, float(target.y) - CAMERA.FP_SERVER_REFERENCE_Y + MoveStep.BODY_HEIGHT * 0.5, target.z) - eye
			camera.set("fp_yaw", atan2(aim.z, aim.x))
			camera.set("fp_pitch", atan2(aim.y, Vector2(aim.x, aim.z).length()))
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
				elif not spec.get("observe_first_shot", false) or enemy_shots > 0:
					Input.action_press("fire")
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
	Input.action_release("fire")
	network.snapshot_received.disconnect(_observe)
	var saved: bool = false
	if not frames.is_empty():
		var sheet: Image = Image.create(1280, 180 * ceili(float(frames.size()) / 4.0), false, Image.FORMAT_RGB8)
		sheet.fill(Color("17191b"))
		for index: int in range(frames.size()):
			sheet.blit_rect(frames[index], Rect2i(0, 0, 320, 180), Vector2i((index % 4) * 320, (index / 4) * 180))
		saved = sheet.save_png(output + "_combat.png") == OK
	var passed: bool = alive and not participant_died and defeated.size() == expected and shots > 0 and saved
	if not passed:
		push_error("qa_combat: %s defeated %d/%d, shots %d, alive %s, saved %s" % [_kind, defeated.size(), expected, shots, alive, saved])
	return {"passed": passed, "kind": _kind, "defeated": defeated.size(), "shots": shots, "enemy_shots": enemy_shots, "observed_phases": phases.keys(), "captured_phases": captured.keys(), "samples": samples}
