extends SceneTree

## Owned diagnostic range only. Both participants use ordinary wire actions.
## No local HP, positions or resolved traces are changed for the capture.
const NET = preload("res://scripts/net_client.gd")
var _directory: String
var _shooter: Node
var _manager: Node
var _feedback: IncomingCombatFeedback
var _standalone: bool = false
var _pending: Dictionary = {}
var _report: Array[Dictionary] = []
var _last_tick: int = -1
var _seen_damage: int = 0
var _seen_near: int = 0
var _failed: bool = false
var _started: int = 0


func _initialize() -> void:
	set_meta("fragr_automated", true)
	_started = Time.get_ticks_msec()
	MouseCapture.release()
	call_deferred("_run")


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started > 30000:
		_require(false, "owned range exceeded 30 second bound")
		quit(1)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		MouseCapture.release()
		_require(false, "automation attempted desktop pointer capture")
		quit(1)
	return false


func _finalize() -> void:
	MouseCapture.release()
	if is_instance_valid(_shooter):
		_shooter.leave_match()


func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error("qa_incoming_combat_feedback: " + message)
		_failed = true
	return condition


func _until(condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	return _require(condition.call(), "authoritative range condition timed out")


func _run() -> void:
	_directory = OS.get_environment("FRAGR_QA_DIR")
	if not _require(not _directory.is_empty(), "FRAGR_QA_DIR must name owned diagnostics"):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	set_meta("fragr_settings_path", _directory.path_join("settings.cfg"))
	set_meta("fragr_records_path", _directory.path_join("records.json"))
	set_meta("fragr_boot", {"mode": "join", "host": OS.get_environment("FRAGR_SERVER")})
	var settings: FragrSettings = FragrSettings.new(_directory.path_join("settings.cfg"))
	settings.set_value("video", "display_mode", 0)
	settings.set_value("audio", "music", 0.0)
	settings.set_value("audio", "voice", 0.0)
	if not _require(settings.save_to_disk() == OK, "isolated settings save"):
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/main.tscn")
	if not await _until(func() -> bool: return current_scene != null):
		quit(1)
		return
	_manager = current_scene
	_shooter = NET.new()
	root.add_child(_shooter)
	_shooter.connect_to_server("human", "Range shooter")
	if not await _until(func() -> bool: return _manager.net_client.player_id != null \
			and _shooter.player_id != null and not _actor(str(_shooter.player_id)).is_empty()):
		quit(1)
		return
	for property: Dictionary in _manager.get_property_list():
		if property["name"] == "incoming_feedback":
			_feedback = _manager.get("incoming_feedback")
	if _feedback == null and OS.get_environment("FRAGR_DIRECTIONAL_STANDALONE") == "1":
		_standalone = true
		_feedback = IncomingCombatFeedback.new()
		_manager.add_child(_feedback)
		_feedback.setup(_manager.hud)
		_feedback.configure_map(_manager.current_map_info)
	if not _require(_feedback != null, "production manager hook absent (standalone needs explicit diagnostic opt-in)"):
		quit(1)
		return
	if not await _until(func() -> bool: return _manager.get_node_or_null("LoadingCard") == null \
			and bool(_manager.camera.fp_mode) and _manager.local_hp_seen > 0):
		quit(1)
		return
	_manager.net_client.snapshot_received.connect(_observe)
	var camera: Node = _manager.camera
	for bearing: String in ["front", "right", "back", "left"]:
		var me: Dictionary = _actor(str(_manager.net_client.player_id))
		var shooter: Dictionary = _actor(str(_shooter.player_id))
		var source_yaw: float = atan2(float(shooter.z) - float(me.z), float(shooter.x) - float(me.x))
		var desired: float = {"front": 0.0, "right": PI * 0.5, "back": PI, "left": -PI * 0.5}[bearing]
		camera.fp_yaw = source_yaw - desired
		camera.fp_pitch = 0.0
		await create_timer(0.15).timeout
		_feedback.indicator.reset()
		_pending.clear()
		var hp_before: int = int(me.hp)
		var origin: Vector3 = Vector3(shooter.x, float(shooter.y) - 1.5 + MoveStep.EYE_HEIGHT, shooter.z)
		var target: Vector3 = Vector3(me.x, float(me.y) - 0.6, me.z)
		await _fire(origin, target)
		if not await _until(func() -> bool: return not _pending.is_empty()):
			quit(1)
			return
		var sample: Dictionary = _pending.duplicate(true)
		var after_actor: Dictionary = _actor(str(_manager.net_client.player_id))
		var hp_after: int = int(after_actor.hp) if not after_actor.is_empty() else 0
		if not _require(sample["damage_delta"] == 1 and hp_after < hp_before \
				and sample["near_delta"] == 0, "real local hit must yield one bearing without pass-by duplication"):
			quit(1)
			return
		var measured: float = DamageBearing.angle(_feedback.indicator.directions.back(), get_root().get_camera_3d().global_basis)
		if not _require(absf(wrapf(measured - desired, -PI, PI)) < 0.04, "render bearing follows real incoming source"):
			quit(1)
			return
		sample.merge({"name": bearing, "hp_before": hp_before, "hp_after": hp_after,
			"bearing_radians": measured, "standalone_attachment": _standalone})
		await _capture(bearing)
		_report.append(sample)
		await create_timer(0.9).timeout
	var me: Dictionary = _actor(str(_manager.net_client.player_id))
	var shooter: Dictionary = _actor(str(_shooter.player_id))
	var origin: Vector3 = Vector3(shooter.x, float(shooter.y) - 1.5 + MoveStep.EYE_HEIGHT, shooter.z)
	var offset: Vector3 = Vector3(-float(shooter.z) + float(me.z), 0.0, float(shooter.x) - float(me.x)).normalized() * 1.3
	var target: Vector3 = Vector3(me.x, float(me.y) - 1.5 + MoveStep.EYE_HEIGHT, me.z) + offset
	_pending.clear()
	await _fire(origin, target)
	if not await _until(func() -> bool: return not _pending.is_empty()):
		quit(1)
		return
	if not _require(_pending["near_delta"] == 1 and _pending["damage_delta"] == 0 \
			and int(_actor(str(_manager.net_client.player_id)).hp) == int(me.hp), "real near miss starts spatial cue without damage"):
		quit(1)
		return
	var near_sample: Dictionary = _pending.duplicate(true)
	near_sample["name"] = "near-miss"
	near_sample["standalone_attachment"] = _standalone
	_report.append(near_sample)
	if _standalone:
		_feedback.reset()
	else:
		_manager.call("_reset_prediction_for_connection", "diagnostic")
	if not _require(_feedback.cue_count == 0 and _feedback.damage_count == 0 \
			and not _feedback.indicator.visible and _feedback.last_tick == -1, "connection ownership reset clears resolved presentation"):
		quit(1)
		return
	for voice: AudioStreamPlayer3D in _feedback.voices:
		if not _require(not voice.playing, "connection ownership reset stops spatial voices"):
			quit(1)
			return
	await create_timer(0.1).timeout
	await _capture("cleared")
	var file: FileAccess = FileAccess.open(_directory.path_join("manifest.json"), FileAccess.WRITE)
	if not _require(file != null, "manifest writable"):
		quit(1)
		return
	file.store_string(JSON.stringify({"schema": 1, "map_id": _manager.current_map_info.map_id,
		"evidence": "ordinary two-client authoritative range shots", "rendered": DisplayServer.get_name() != "headless",
		"samples": _report, "listening_acceptance": "open"}, "\t") + "\n")
	file.close()
	_shooter.leave_match()
	_shooter.queue_free()
	_manager.net_client.snapshot_received.disconnect(_observe)
	_manager.net_client.leave_match()
	_manager.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	else:
		await process_frame
	await create_timer(0.3).timeout
	if _require(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "automation never captures pointer"):
		print("qa_incoming_combat_feedback: PASS four actual damage bearings, actual near miss, ownership and clear")
	quit(1 if _failed else 0)


func _fire(origin: Vector3, target: Vector3) -> void:
	var aim: Vector2 = AimAssist.aim_at(origin, target)
	_shooter.send_action({"weapon_swap": "tack", "yaw": aim.x, "pitch": aim.y, "fire": false})
	await create_timer(0.3).timeout
	if not _require(str(_actor(str(_shooter.player_id)).get("weapon", "")).to_lower() == "tack", "shooter actually selected supplied Tack"):
		quit(1)
		return
	_shooter.send_action({"yaw": aim.x, "pitch": aim.y, "fire": true})
	await create_timer(0.055).timeout
	_shooter.send_action({"yaw": aim.x, "pitch": aim.y, "fire": false})


func _actor(id: String) -> Dictionary:
	return QaCombat.actor_by_id(_manager.latest_snapshot, id)


func _observe(snapshot: Dictionary) -> void:
	var tick: int = int(snapshot["tick"])
	if tick <= _last_tick:
		return
	_last_tick = tick
	var camera: Camera3D = root.get_camera_3d()
	if _standalone:
		_feedback.ingest(tick, snapshot.get("shot_results", []), str(_manager.net_client.player_id),
			camera.global_transform, bool(_manager.camera.fp_mode), _manager.local_hp_seen > 0)
	for shot: Dictionary in snapshot.get("shot_results", []):
		if shot.get("shooter_id") == _shooter.player_id:
			_pending = {"tick": tick, "shot": shot.duplicate(true),
				"damage_delta": _feedback.damage_count - _seen_damage,
				"near_delta": _feedback.cue_count - _seen_near,
				"cue_positions": []}
			for point: Vector3 in _feedback.last_cue_positions:
				_pending["cue_positions"].append([point.x, point.y, point.z])
	_seen_damage = _feedback.damage_count
	_seen_near = _feedback.cue_count


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_require(not image.is_empty() and image.save_png(_directory.path_join(name + ".png")) == OK, "capture " + name)
