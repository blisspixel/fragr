extends SceneTree

# Passive rendered evidence for one real server participant. Connect before or
# during play, resolve a unique callsign once, then hold its server UUID.
const FRAME_COUNT: int = 8
const FRAME_INTERVAL_S: float = 0.5
const TARGET_WAIT_MS: int = 30000
const CAMERA_EPSILON: float = 0.025
const FACING_EPSILON: float = 0.02
const SERVER_REFERENCE_Y: float = 1.5

var _out_dir: String = ""
var _target_id: String = ""
var _target_name: String = ""
var _failed: bool = false

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("_run")

func _finalize() -> void:
	MouseCapture.release()

func _fail(message: String) -> void:
	push_error("qa_watch: " + message)
	_failed = true

func _run() -> void:
	_out_dir = OS.get_environment("FRAGR_WATCH_DIR")
	var brain_receipt: String = OS.get_environment("FRAGR_WATCH_VERIFY_BRAIN")
	if not brain_receipt.is_empty():
		_verify_receipt(brain_receipt)
		return
	_target_id = OS.get_environment("FRAGR_WATCH_ID").strip_edges()
	_target_name = OS.get_environment("FRAGR_WATCH_NAME").strip_edges()
	if _out_dir.is_empty() or (_target_id.is_empty() and _target_name.is_empty()):
		_fail("set FRAGR_WATCH_DIR and a target ID or callsign")
		quit(1)
		return
	_out_dir = ProjectSettings.globalize_path(_out_dir)
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("could not create output directory")
		quit(1)
		return
	set_meta("fragr_settings_path", _out_dir.path_join("settings.cfg"))
	set_meta("fragr_records_path", _out_dir.path_join("service-record"))
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var host: String = OS.get_environment("FRAGR_SERVER").strip_edges()
	if host.is_empty():
		host = "127.0.0.1:6767"
	set_meta("fragr_boot", {"mode": "spectate", "host": host})
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		_fail("could not load the match scene")
		quit(1)
		return
	var manager: Node = await _manager_ready()
	if manager == null:
		_fail("match did not connect or target never appeared")
		quit(1)
		return
	var camera: Node3D = manager.get_node("SpectatorCamera") as Node3D
	if camera == null:
		_fail("match has no spectator camera")
		quit(1)
		return
	camera.pin_player(_target_id)
	var frames: Array[Dictionary] = []
	var previous_tick: int = -1
	for index: int in range(FRAME_COUNT):
		await create_timer(FRAME_INTERVAL_S).timeout
		await RenderingServer.frame_post_draw
		var snapshot: Dictionary = manager.get("latest_snapshot")
		var pawns: Dictionary = manager.get("players")
		var pawn: Node3D = pawns.get(_target_id) as Node3D
		if pawn == null or not is_instance_valid(pawn):
			_fail("pinned participant disappeared at frame %d" % index)
			break
		if camera.get_followed_target() != pawn or not camera.is_observing_first_person():
			_fail("camera left the pinned first-person view")
			break
		var eye: Vector3 = pawn.global_position + Vector3(0.0, MoveStep.EYE_HEIGHT - SERVER_REFERENCE_Y, 0.0)
		if camera.global_position.distance_to(eye) > CAMERA_EPSILON:
			_fail("rendered eye differs from the authoritative pawn")
			break
		var yaw: float = float(pawn.get("target_yaw"))
		var pitch: float = float(pawn.get("target_pitch"))
		if (-camera.global_transform.basis.z).distance_to(ServerYaw.aim_direction(yaw, pitch)) > FACING_EPSILON:
			_fail("rendered facing differs from server aim")
			break
		var tick: int = int(snapshot.get("tick", -1))
		if tick <= previous_tick:
			_fail("authoritative tick did not advance")
			break
		previous_tick = tick
		var image: Image = root.get_viewport().get_texture().get_image()
		if image == null or image.get_width() < 640 or image.get_height() < 360 or _looks_blank(image):
			_fail("framebuffer was missing, blank or too small")
			break
		var filename: String = "eye_%02d.png" % index
		if image.save_png(_out_dir.path_join(filename)) != OK:
			_fail("could not save " + filename)
			break
		frames.append({
			"file": filename,
			"tick": tick,
			"player_id": _target_id,
			"eye": [camera.global_position.x, camera.global_position.y, camera.global_position.z],
			"yaw": yaw,
			"pitch": pitch,
		})
	var manifest: Dictionary = {
		"target_id": _target_id,
		"target_name": _target_name,
		"frames": frames,
		"passed": not _failed and frames.size() == FRAME_COUNT,
	}
	var report: FileAccess = FileAccess.open(_out_dir.path_join("manifest.json"), FileAccess.WRITE)
	if report == null:
		_fail("could not write manifest")
	else:
		report.store_string(JSON.stringify(manifest, "  "))
		report.flush()
		report.close()
	if not _failed and frames.size() == FRAME_COUNT:
		print("qa_watch: PASS %s %d frames" % [_target_id, frames.size()])
	quit(0 if not _failed and frames.size() == FRAME_COUNT else 1)

func _manager_ready() -> Node:
	var deadline: int = Time.get_ticks_msec() + TARGET_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		var manager: Node = root.get_node_or_null("GameManager")
		if manager != null:
			var snapshot: Dictionary = manager.get("latest_snapshot")
			if int(snapshot.get("tick", -1)) >= 0:
				var found: Array[String] = []
				for entry: Variant in snapshot.get("players", []):
					if entry is Dictionary:
						var player: Dictionary = entry
						if not _target_id.is_empty() and str(player.get("id", "")) == _target_id:
							found.append(_target_id)
						elif _target_id.is_empty() and str(player.get("name", "")) == _target_name:
							found.append(str(player.get("id", "")))
				if found.size() > 1:
					_fail("target callsign is ambiguous")
					return null
				if found.size() == 1 and not found[0].is_empty():
					_target_id = found[0]
					return manager
		await create_timer(0.05).timeout
	return null

func _looks_blank(image: Image) -> bool:
	var first: Color = image.get_pixel(0, 0)
	for row: int in range(1, 9):
		for column: int in range(1, 16):
			var pixel: Color = image.get_pixel(
				column * (image.get_width() - 1) / 16,
				row * (image.get_height() - 1) / 9
			)
			if absf(pixel.r - first.r) + absf(pixel.g - first.g) + absf(pixel.b - first.b) > 0.1:
				return false
	return true

func _verify_receipt(brain_path: String) -> void:
	var watch_path: String = _out_dir.path_join("manifest.json")
	var watch_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(watch_path))
	var brain_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(brain_path))
	if not watch_value is Dictionary or not brain_value is Dictionary:
		_fail("watch manifest or brain receipt is missing or invalid")
		quit(1)
		return
	var watch: Dictionary = watch_value
	var brain: Dictionary = brain_value
	var frames_value: Variant = watch.get("frames")
	if not frames_value is Array:
		_fail("watch manifest has no frame list")
		quit(1)
		return
	var frames: Array = frames_value
	var passed_value: Variant = watch.get("passed")
	var id_value: Variant = watch.get("target_id")
	var brain_id_value: Variant = brain.get("player_id")
	var provider_value: Variant = brain.get("provider")
	var spend_value: Variant = brain.get("run_usd")
	var actions_value: Variant = brain.get("actions_sent")
	if not passed_value is bool or not id_value is String \
		or not brain_id_value is String or not provider_value is String \
		or not (spend_value is float or spend_value is int) \
		or not (actions_value is float or actions_value is int):
		_fail("watch or brain receipt has wrong field types")
		quit(1)
		return
	var id: String = id_value
	if not passed_value or frames.size() != FRAME_COUNT \
		or id.is_empty() or id != brain_id_value \
		or provider_value != "local" \
		or is_nan(float(spend_value)) or is_inf(float(spend_value)) \
		or float(spend_value) != 0.0 \
		or float(actions_value) <= 0.0 or float(actions_value) != floorf(float(actions_value)):
		_fail("watch and free brain receipts do not describe one valid participant")
		quit(1)
		return
	var last_tick: int = -1
	for entry: Variant in frames:
		if not entry is Dictionary:
			_fail("malformed watch frame entry")
			break
		var frame: Dictionary = entry
		var tick_value: Variant = frame.get("tick")
		var file_value: Variant = frame.get("file")
		var frame_id_value: Variant = frame.get("player_id")
		if not (tick_value is float or tick_value is int) \
			or not file_value is String or not frame_id_value is String:
			_fail("watch frame has wrong field types")
			break
		var tick: int = int(tick_value)
		var file: String = file_value
		if float(tick_value) != float(tick) or frame_id_value != id or tick <= last_tick \
			or file.get_file() != file or not FileAccess.file_exists(_out_dir.path_join(file)):
			_fail("watch frames changed identity, stopped ticking, or lost an image")
			break
		last_tick = tick
	if not _failed:
		var verified: Dictionary = {
			"player_id": id,
			"frame_count": frames.size(),
			"first_tick": int(frames[0]["tick"]),
			"last_tick": last_tick,
			"brain_actions": int(brain["actions_sent"]),
			"brain_end_reason": str(brain.get("end_reason", "")),
			"run_usd": 0.0,
		}
		var output: FileAccess = FileAccess.open(_out_dir.path_join("verified.json"), FileAccess.WRITE)
		if output == null:
			_fail("could not write paired receipt")
		else:
			output.store_string(JSON.stringify(verified, "  "))
			output.flush()
			output.close()
	if not _failed:
		print("qa_watch: VERIFIED " + id)
	quit(1 if _failed else 0)
