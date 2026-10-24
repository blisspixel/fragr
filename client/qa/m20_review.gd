extends SceneTree

## Local Exception review stills on any desktop: the live client renders into
## a fixed 1280x720 viewport, independent of how a compositor sizes the
## window. States follow the QA tour's manifest keys for overview poses and
## first-person looks. Development inspection only, never an acceptance.
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
		push_error("m20_review: FRAGR_QA_DIR and FRAGR_QA_MANIFEST are required")
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
		push_error("m20_review: manifest needs states")
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
	# Silence the radio once, then let its station card fade before any still.
	var first: Node = _manager()
	var radio: Node = first.get("radio") if first != null else null
	if radio != null and bool(radio.get("enabled")):
		radio.call("toggle")
		await create_timer(6.0).timeout
	var started: int = Time.get_ticks_msec()
	for entry: Variant in manifest["states"]:
		var state: Dictionary = entry
		var due: float = float(state.get("at_seconds", 0.0))
		var wait: float = due - float(Time.get_ticks_msec() - started) / 1000.0
		if wait > 0.0:
			await create_timer(wait).timeout
		var manager: Node = _manager()
		if manager == null:
			push_error("m20_review: no GameManager")
			quit(1)
			return
		if state.get("join") == "human" and not bool(manager.get("is_human_player")):
			await manager.change_role(true)
			var admitted: int = Time.get_ticks_msec() + 12000
			while bool(manager.call("_mission_controls_blocked")) and Time.get_ticks_msec() < admitted:
				if is_instance_valid(manager.opening):
					manager.opening.finish()
				await create_timer(0.1).timeout
			if bool(manager.call("_mission_controls_blocked")):
				var mission: Dictionary = manager.net_client.mission
				push_error("m20_review: still blocked: opening=%s release=%s interlude=%s phase=%s party=%s" % [
					is_instance_valid(manager.opening), manager.get("_opening_release"), is_instance_valid(manager.get("interlude")),
					mission.get("state", {}).get("phase"), mission.get("state", {}).get("party")])
		elif state.get("join") == "spectator" and bool(manager.get("is_human_player")):
			await manager.change_role(false)
			await create_timer(3.0).timeout
		if state.has("await"):
			if not await _await(str(state["await"]), float(state.get("await_seconds", 120.0))):
				push_error("m20_review: %s never happened for %s" % [state["await"], state["name"]])
			# A mission reset can rebuild the scene while we wait.
			manager = _manager()
			if manager == null:
				quit(1)
				return
		for point: Variant in state.get("walk_to", []):
			await _walk(manager, Vector3(float(point[0]), float(point[1]), float(point[2])))
		_pose(manager, state)
		var settle_until: int = Time.get_ticks_msec() + roundi(float(state.get("settle_seconds", 0.6)) * 1000.0)
		while Time.get_ticks_msec() < settle_until:
			await create_timer(0.25).timeout
			if state.get("watch", false):
				_report(manager)
		_pose(manager, state)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = _viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		var path: String = _out_dir.path_join("%s.png" % str(state["name"]))
		image.save_png(path)
		print("m20_review: saved ", path)
		_report(manager)
	quit(0)

## The facts behind a still: where the pawn stands and what the lenses do.
func _report(manager: Node) -> void:
	var pawn: Node3D = _pawn(manager)
	var snapshot: Dictionary = manager.get("latest_snapshot") if manager.get("latest_snapshot") is Dictionary else {}
	var lenses: Array[String] = []
	var others: Array[String] = []
	for actor: Variant in snapshot.get("players", []):
		if actor is Dictionary and not ActorState.is_hostile(actor):
			others.append("%s@(%.1f,%.1f,%.1f) hp %d" % [actor.get("name", "?"), float(actor["x"]), float(actor["y"]), float(actor["z"]), int(actor.get("hp", 0))])
		elif actor is Dictionary and int(actor.get("hp", 0)) > 0:
			others.append("%s@(%.0f,%.0f)" % [str(actor["campaign"].get("kind")), float(actor["x"]), float(actor["z"])])
		if actor is Dictionary and ActorState.is_hostile(actor) and actor["campaign"].get("kind") == "surveyor":
			lenses.append("%s@(%.1f,%.1f,%.1f) yaw %.2f" % [actor["campaign"].get("phase"), float(actor["x"]), float(actor["y"]), float(actor["z"]), float(actor.get("yaw", 0.0))])
	print("m20_review: pawn ", pawn.global_position if pawn != null else Vector3.INF, " lenses ", lenses,
		" marks ", snapshot.get("surveyor_marks", []).size(), " actors ", others, " fps ", Engine.get_frames_per_second())

## Wait for an accepted fact: a live Surveyor disc, or a named M20 field.
func _await(what: String, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var manager: Node = _manager()
		if is_instance_valid(manager) and not manager.is_queued_for_deletion() and _happened(manager, what):
			return true
		await create_timer(0.1).timeout
	return false

func _happened(manager: Node, what: String) -> bool:
	var snapshot: Dictionary = manager.get("latest_snapshot") if manager.get("latest_snapshot") is Dictionary else {}
	if what == "mark":
		return not snapshot.get("surveyor_marks", []).is_empty()
	if what == "strip":
		return not snapshot.get("paver_strips", []).is_empty()
	var mission: Dictionary = manager.net_client.mission
	var state: Dictionary = mission.get("state", {}) if mission.get("state") is Dictionary else {}
	if what.begins_with("phase:"):
		return state.get("phase") == what.trim_prefix("phase:")
	var facts: Variant = state.get("m20")
	if not facts is Dictionary:
		return false
	if what == "gate_open_true":
		return facts.get("gate_open") == true
	if what.begins_with("completed:"):
		return (facts.get("completed", []) as Array).size() >= int(what.trim_prefix("completed:"))
	if what.begins_with("seconds:"):
		var geometry: Dictionary = manager.get("m20_hold").get("geometry")
		var left: int = M20MissionState.seconds_left(geometry, facts, int(snapshot.get("tick", 0))) if not geometry.is_empty() else -1
		return left >= 0 and left <= int(what.trim_prefix("seconds:"))
	return facts.get(what) != null

func _mark_center(manager: Node) -> Vector3:
	var snapshot: Dictionary = manager.get("latest_snapshot") if manager.get("latest_snapshot") is Dictionary else {}
	var marks: Array = snapshot.get("surveyor_marks", [])
	if marks.is_empty():
		return Vector3.INF
	var c: Array = marks[0]["center"]
	return Vector3(float(c[0]), float(c[1]), float(c[2]))

func _strip_origin(manager: Node) -> Vector3:
	var snapshot: Dictionary = manager.get("latest_snapshot") if manager.get("latest_snapshot") is Dictionary else {}
	var strips: Array = snapshot.get("paver_strips", [])
	if strips.is_empty():
		return Vector3.INF
	var o: Array = strips[0]["origin"]
	return Vector3(float(o[0]), float(o[1]), float(o[2]))

func _pawn(manager: Node) -> Node3D:
	var pawn: Variant = manager.players.get(str(manager.net_client.player_id))
	return pawn as Node3D if pawn is Node3D and is_instance_valid(pawn) else null

## Ordinary held movement toward a point, steering the first-person yaw.
func _walk(manager: Node, goal: Vector3) -> void:
	var cam: Node = manager.get_node_or_null("SpectatorCamera")
	var deadline: int = Time.get_ticks_msec() + 20000
	# Input only flows from the pawn's own eye.
	_pose(manager, {"camera": "first_person"})
	await process_frame
	print("m20_review: walk target=", manager.call("_has_local_input_target"), " blocked=", manager.call("controls_blocked"),
		" mission_blocked=", manager.call("_mission_controls_blocked"))
	Input.action_press(&"move_forward")
	while Time.get_ticks_msec() < deadline:
		var pawn: Node3D = _pawn(manager)
		if pawn == null:
			break
		var feet: Vector3 = pawn.global_position
		if Vector2(feet.x - goal.x, feet.z - goal.z).length() < 0.5:
			break
		cam.set("fp_yaw", atan2(goal.z - feet.z, goal.x - feet.x))
		cam.set("fp_pitch", 0.0)
		await create_timer(0.05).timeout
	Input.action_release(&"move_forward")
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
		var base: Vector3 = Vector3.ZERO
		# A relative pose frames the joined pawn from outside its eye.
		if state.get("relative", false) and _pawn(manager) != null:
			base = _pawn(manager).global_position
		elif state.get("mark_relative", false) and _mark_center(manager).is_finite():
			base = _mark_center(manager)
		elif state.get("strip_relative", false) and _strip_origin(manager).is_finite():
			base = _strip_origin(manager)
		n3.global_position = base + Vector3(float(p[0]), float(p[1]), float(p[2]))
		n3.look_at(base + Vector3(float(l[0]), float(l[1]), float(l[2])), Vector3.UP)
		cam.set("tip_locked_transform", n3.global_transform)
		cam.set("tip_has_locked_transform", true)
		cam.set("tip_pose_lock", true)
	elif state.get("camera") == "first_person" and bool(manager.get("is_human_player")):
		cam.set("tip_pose_lock", false)
		cam.set("tip_has_locked_transform", false)
		var pawn: Variant = manager.players.get(str(manager.net_client.player_id))
		if pawn is Node3D and is_instance_valid(pawn):
			cam.call("set_fp_mode", true, pawn)
			if state.has("look_at") or state.has("look_at_relative"):
				var eye: Vector3 = (pawn as Node3D).global_position + Vector3.UP * 0.1
				var target: Array = state["look_at"] if state.has("look_at") else []
				if target.is_empty():
					var offset: Array = state["look_at_relative"]
					target = [eye.x + float(offset[0]), eye.y + float(offset[1]), eye.z + float(offset[2])]
				var direction: Vector3 = Vector3(float(target[0]), float(target[1]), float(target[2])) - eye
				cam.set("fp_yaw", atan2(direction.z, direction.x))
				cam.set("fp_pitch", atan2(direction.y, Vector2(direction.x, direction.z).length()))
	elif state.get("camera") == "follow":
		cam.set("tip_pose_lock", false)
		cam.set("follow_mode", true)
		cam.set("fp_mode", false)
