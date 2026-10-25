extends SceneTree

## Still Here review stills on any desktop: the live client renders into a
## fixed 1280x720 viewport, joins as the human, walks the refuge with ordinary
## held movement, uses Latch's ledger and the quay bench through the real
## interact action, and saves a still for each manifest state. States may
## wait for an epilogue fact ("later", "phase:departed"), walk to points,
## look at a point in first person or pose an overview camera. Development
## inspection only, never an acceptance.
const SIZE: Vector2i = Vector2i(1280, 720)
var _viewport: SubViewport
var _out_dir: String = ""

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _manager() -> Node:
	return _viewport.get_node_or_null("GameManager") if _viewport != null else null

func _run() -> void:
	_out_dir = OS.get_environment("FRAGR_QA_DIR")
	var manifest_path: String = OS.get_environment("FRAGR_QA_MANIFEST")
	if _out_dir.is_empty() or manifest_path.is_empty():
		push_error("still_here_review: FRAGR_QA_DIR and FRAGR_QA_MANIFEST are required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	set_meta("fragr_records_path", _out_dir.path_join("service-record"))
	var settings_path: String = _out_dir.path_join("settings.cfg")
	set_meta("fragr_settings_path", settings_path)
	var settings: FragrSettings = FragrSettings.new(settings_path)
	settings.set_value("video", "display_mode", 0)
	settings.set_value("video", "quality", int(OS.get_environment("FRAGR_QA_QUALITY")) if not OS.get_environment("FRAGR_QA_QUALITY").is_empty() else 2)
	settings.save_to_disk()
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary or not manifest.get("states") is Array:
		push_error("still_here_review: manifest needs states")
		quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.audio_listener_enable_3d = false
	root.add_child(_viewport)
	var scene: PackedScene = load("res://scenes/main.tscn")
	_viewport.add_child(scene.instantiate())
	await create_timer(2.5).timeout
	for entry: Variant in manifest["states"]:
		var state: Dictionary = entry
		var manager: Node = _manager()
		if manager == null:
			push_error("still_here_review: no GameManager")
			quit(1)
			return
		if state.get("join") == "human" and not bool(manager.get("is_human_player")):
			await manager.change_role(true)
			# The arrival page opens first; a state may photograph it before
			# the next one dismisses it.
			var paged: int = Time.get_ticks_msec() + 8000
			while not is_instance_valid(manager.get("opening")) and Time.get_ticks_msec() < paged:
				await create_timer(0.1).timeout
		if state.get("dismiss") == "opening" and is_instance_valid(manager.get("opening")):
			manager.opening.finish()
		if state.get("dismiss") == "page" and is_instance_valid(manager.get("still_here_page")):
			manager.still_here_page.finish()
		if state.has("dismiss"):
			var admitted: int = Time.get_ticks_msec() + 12000
			while bool(manager.call("_mission_controls_blocked")) and Time.get_ticks_msec() < admitted:
				await create_timer(0.1).timeout
		if state.has("await"):
			if not await _await(str(state["await"]), float(state.get("await_seconds", 30.0))):
				push_error("still_here_review: %s never happened for %s" % [state["await"], state["name"]])
			manager = _manager()
		for point: Variant in state.get("walk_to", []):
			await _walk(manager, Vector3(float(point[0]), float(point[1]), float(point[2])))
		_pose(manager, state)
		if state.has("interact"):
			await _interact(manager, state["interact"])
		var settle_until: int = Time.get_ticks_msec() + roundi(float(state.get("settle_seconds", 0.8)) * 1000.0)
		while Time.get_ticks_msec() < settle_until:
			await create_timer(0.1).timeout
			if not state.has("interact") and state.get("camera") != "hold":
				_pose(manager, state)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = _viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		var path: String = _out_dir.path_join("%s.png" % str(state["name"]))
		image.save_png(path)
		print("still_here_review: saved ", path, " ", _report(manager))
	# Retire the client before quitting and give the mixer time to drop the
	# radio's stopped stream; an immediate quit leaks the playing stream.
	for child: Node in _viewport.get_children():
		child.queue_free()
	await create_timer(0.5).timeout
	quit(0)

func _report(manager: Node) -> String:
	var pawn: Node3D = _pawn(manager)
	var mission: Dictionary = manager.net_client.mission
	var state: Dictionary = mission.get("state", {}) if mission.get("state") is Dictionary else {}
	var facts: Variant = state.get("epilogue")
	return "pawn %s phase %s completed %s later %s fps %d" % [pawn.global_position if pawn != null else Vector3.INF, state.get("phase"),
		facts.get("completed") if facts is Dictionary else "-", facts.get("later") if facts is Dictionary else "-", Engine.get_frames_per_second()]

func _await(what: String, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var manager: Node = _manager()
		if is_instance_valid(manager) and _happened(manager, what):
			return true
		await create_timer(0.1).timeout
	return false

func _happened(manager: Node, what: String) -> bool:
	var mission: Dictionary = manager.net_client.mission
	var state: Dictionary = mission.get("state", {}) if mission.get("state") is Dictionary else {}
	if what.begins_with("phase:"):
		return state.get("phase") == what.trim_prefix("phase:")
	if what == "page":
		return is_instance_valid(manager.get("still_here_page"))
	if what == "fragment":
		var refuge: Variant = manager.get("still_here")
		return refuge != null and bool(refuge.get("fragment"))
	var facts: Variant = state.get("epilogue")
	if not facts is Dictionary:
		return false
	if what == "turning":
		return facts.get("turning_at") != null
	if what == "later":
		return facts.get("later") == true and not is_instance_valid(manager.get("still_here_turn"))
	if what.begins_with("completed:"):
		return (facts.get("completed", []) as Array).size() >= int(what.trim_prefix("completed:"))
	return facts.get(what) != null

func _pawn(manager: Node) -> Node3D:
	var pawn: Variant = manager.players.get(str(manager.net_client.player_id))
	return pawn as Node3D if pawn is Node3D and is_instance_valid(pawn) else null

## Ordinary held movement toward a point, steering the first-person yaw.
func _walk(manager: Node, goal: Vector3) -> void:
	var cam: Node = manager.get_node_or_null("SpectatorCamera")
	var deadline: int = Time.get_ticks_msec() + 20000
	_pose(manager, {"camera": "first_person"})
	await process_frame
	Input.action_press(&"move_forward")
	while Time.get_ticks_msec() < deadline:
		var pawn: Node3D = _pawn(manager)
		if pawn == null:
			break
		var feet: Vector3 = pawn.global_position
		if Vector2(feet.x - goal.x, feet.z - goal.z).length() < 0.35:
			break
		cam.set("fp_yaw", atan2(goal.z - feet.z, goal.x - feet.x))
		cam.set("fp_pitch", 0.0)
		await create_timer(0.03).timeout
	Input.action_release(&"move_forward")
	await create_timer(0.3).timeout

## Look at a world point in first person and press Use once.
func _interact(manager: Node, target: Variant) -> void:
	_pose(manager, {"camera": "first_person", "look_at": target})
	await create_timer(0.4).timeout
	_pose(manager, {"camera": "first_person", "look_at": target})
	# The review viewport receives no input events; this is the press the
	# game manager would take from one.
	manager.set("pending_interact", true)
	manager.set("interact_held", true)
	await create_timer(0.15).timeout
	manager.set("interact_held", false)
	await create_timer(0.2).timeout

func _pose(manager: Node, state: Dictionary) -> void:
	var cam: Node = manager.get_node_or_null("SpectatorCamera")
	if cam == null:
		return
	if state.get("camera") == "overview" and cam is Node3D:
		cam.set("spectator_first_person", false)
		cam.set("follow_mode", false)
		cam.set("fp_mode", false)
		var p: Array = state["camera_position"]
		var l: Array = state["camera_look_at"]
		var n3: Node3D = cam
		n3.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		n3.look_at(Vector3(float(l[0]), float(l[1]), float(l[2])), Vector3.UP)
		cam.set("tip_locked_transform", n3.global_transform)
		cam.set("tip_has_locked_transform", true)
		cam.set("tip_pose_lock", true)
	elif state.get("camera") == "first_person" and bool(manager.get("is_human_player")):
		cam.set("tip_pose_lock", false)
		cam.set("tip_has_locked_transform", false)
		var pawn: Node3D = _pawn(manager)
		if pawn != null:
			cam.call("set_fp_mode", true, pawn)
			if state.has("look_at"):
				var eye: Vector3 = pawn.global_position + Vector3.UP * 0.1
				var target: Array = state["look_at"]
				var direction: Vector3 = Vector3(float(target[0]), float(target[1]), float(target[2])) - eye
				cam.set("fp_yaw", atan2(direction.z, direction.x))
				cam.set("fp_pitch", atan2(direction.y, Vector2(direction.x, direction.z).length()))
