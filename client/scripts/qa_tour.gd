extends SceneTree

# Visual QA tour. Walks every player-facing state named in qa/tour.json, saves
# one still per state, and writes a manifest beside them with the numbers a
# critic would otherwise have to eyeball.
#
# Run under a real framebuffer (Windows directly, Linux under Xvfb with
# opengl3). Bare --headless has no framebuffer and every still comes back
# empty. See tools/qa_tour.sh.
#
# The one number worth explaining is hud_coverage: the share of the screen the
# HUD paints over. The tour captures each frame twice, once with the HUD and
# once with it hidden, and counts the pixels that differ. It turns "the HUD is
# taking over" from an argument into a measurement, and a state that creeps
# upward shows up without anyone having to remember what it used to look like.

const MANIFEST_PATH: String = "res://qa/tour.json"
const CameraScript = preload("res://scripts/spectator_cam.gd")
const THUMB_WIDTH: int = 320
const CONTACT_COLUMNS: int = 4
const STRIP_TILE_WIDTH: int = 320
const DIFF_EPSILON: float = 0.02

var _out_dir: String = ""
var _results: Array = []
var _clock_ms: int = 0
var _joined: bool = false
var _strip_for_state: String = ""
var _probe_frames: int = 0
var _strip_times_ms: Array[int] = []
var _failed: bool = false
var _movement_samples: Array[Dictionary] = []
## Frames between the trigger and the first strip frame. The shot is resolved by
## the server, so the flash arrives a round trip later, not on the next frame.
const STRIP_LEAD_FRAMES: int = 2

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("_run")

func _finalize() -> void:
	MouseCapture.release()

func _process(_delta: float) -> bool:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		MouseCapture.release()
		push_error("qa_tour: automation attempted to capture the desktop pointer")
		_failed = true
	return false

func _run() -> void:
	_out_dir = OS.get_environment("FRAGR_QA_DIR")
	if _out_dir.is_empty():
		_out_dir = ProjectSettings.globalize_path("res://../.agents/qa/latest")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# Captures must not depend on or modify the player's saved preferences.
	var settings_path: String = _out_dir.path_join("settings.cfg")
	set_meta("fragr_settings_path", settings_path)
	var capture_settings: FragrSettings = FragrSettings.new(settings_path)
	capture_settings.set_value("video", "display_mode", 0)
	if capture_settings.save_to_disk() != OK:
		push_error("qa_tour: could not create isolated capture settings")
		quit(1)
		return

	var tour: Dictionary = _load_manifest()
	if tour.is_empty():
		quit(1)
		return
	# A custom SceneTree can inherit the project's fullscreen mode even when
	# the launcher requests a resolution. Set the actual window explicitly.
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(int(tour["width"]), int(tour["height"]))
	await process_frame

	var states: Array = tour.get("states", [])
	if states.is_empty():
		push_error("qa_tour: manifest lists no states")
		quit(1)
		return

	var current_scene: String = ""
	_clock_ms = Time.get_ticks_msec()
	for entry in states:
		var state: Dictionary = entry
		var state_name: String = state.get("name", "")
		if state_name.is_empty():
			push_error("qa_tour: a state has no name")
			quit(1)
			return

		var scene: String = state.get("scene", "")
		if not scene.is_empty() and scene != current_scene:
			change_scene_to_file(scene)
			current_scene = scene
			# Let the scene build and the shaders warm. Judging a game by its
			# first frame is how a still ends up full of pink placeholders.
			await create_timer(1.5).timeout
			_clock_ms = Time.get_ticks_msec()

		var due_ms: int = int(float(state.get("at_seconds", 0.0)) * 1000.0)
		var wait_s: float = float(due_ms - (Time.get_ticks_msec() - _clock_ms)) / 1000.0
		if wait_s > 0.0:
			await create_timer(wait_s).timeout

		var menu_page: String = state.get("menu_page", "")
		if not menu_page.is_empty():
			get_root().get_node("BootMenu").call("_show", menu_page)
			await process_frame
		if state.has("join"):
			await _change_role(state["join"] == "human")
		if state.has("weapon"):
			await _select_weapon(str(state["weapon"]))
		if state.has("aim_pitch"):
			await _set_aim_pitch(float(state["aim_pitch"]))
		_movement_samples.clear()
		if state.get("jump_probe", false):
			await _jump_probe()
		for point: Array in state.get("walk_to", []):
			await _walk_to(Vector3(float(point[0]), float(point[1]), float(point[2])))
		if state.has("look_at"):
			var target: Array = state["look_at"]
			var camera: Node3D = _spectator_camera()
			var direction: Vector3 = Vector3(float(target[0]), float(target[1]), float(target[2])) - camera.global_position
			camera.set("fp_yaw", atan2(direction.z, direction.x))
			await _set_aim_pitch(atan2(direction.y, Vector2(direction.x, direction.z).length()))
		if state.get("empty_magazine", false):
			await _empty_magazine()
		if state.get("overlay", "") == "match_menu":
			_game_manager().get_node("PauseMenu").call("open")
		if state.get("overlay", "") == "match_settings":
			var match_menu: PauseMenu = _game_manager().get_node("PauseMenu")
			match_menu.open()
			match_menu.show_settings()
		if state.has("settings_tab"):
			var settings_root: Node = get_root().get_node("BootMenu").get("_root")
			(settings_root.get_node("SettingsPanel") as SettingsPanel).show_page(str(state["settings_tab"]))
		_pose_camera(state.get("camera", "none"))
		await create_timer(0.75).timeout
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw

		# An effect that lasts sixty milliseconds is never in a still taken at a
		# fixed second. A state can instead pull the trigger and keep a strip of
		# consecutive frames, which is the only way the muzzle flash, the tracer
		# and the impact can be judged at all.
		var strip_frames: int = int(state.get("strip_frames", 0))
		if strip_frames > 0:
			var strip_name: String = "%02d_%s_strip.png" % [_results.size() + 1, state_name]
			await _capture_strip(state, strip_frames, strip_name)
			_strip_for_state = strip_name
		else:
			_strip_for_state = ""
			_probe_frames = 0
			_strip_times_ms.clear()
		if state.has("expect_equipment"):
			_check_equipment(state["expect_equipment"])

		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw

		var measured: Dictionary = await _measure()
		var shot: Image = measured.get("shot")
		if shot == null:
			push_error("qa_tour: no frame for state " + state_name)
			quit(1)
			return

		var file_name: String = "%02d_%s.png" % [_results.size() + 1, state_name]
		if _looks_blank(shot) or measured.get("world_blank", false):
			push_error("qa_tour: blank capture for " + state_name)
			_failed = true
		if shot.get_width() != int(tour["width"]) or shot.get_height() != int(tour["height"]):
			push_error("qa_tour: unexpected capture size for " + state_name)
			_failed = true
		var observed: Dictionary = _observed_state()
		if state.has("expect_yaw"):
			var expected_yaw: float = float(state["expect_yaw"])
			if observed.get("server_yaw") == null or absf(angle_difference(float(observed["camera_yaw"]), expected_yaw)) > 0.001 or absf(angle_difference(float(observed["server_yaw"]), expected_yaw)) > 0.001:
				push_error("qa_tour: captured facing disagrees with the authored spawn for " + state_name)
				_failed = true
		if current_scene == "res://scenes/main.tscn" and (observed.get("fighters", 0) == 0 or observed.get("map_id", 0) == 0):
			push_error("qa_tour: no live match for " + state_name)
			_failed = true
		if state.has("aim_pitch"):
			var expected_pitch: float = float(state["aim_pitch"])
			if absf(float(observed.get("camera_pitch", 99.0)) - expected_pitch) > 0.001 or absf(_local_server_pitch(_game_manager()) - expected_pitch) > 0.001:
				push_error("qa_tour: captured aim disagrees with the server for " + state_name)
				_failed = true
		var path: String = _out_dir.path_join(file_name)
		var err: Error = shot.save_png(path)
		if err != OK:
			push_error("qa_tour: could not write %s (%s)" % [path, str(err)])
			quit(1)
			return

		# The same frame with the HUD hidden, so art and chrome can be judged
		# apart from each other instead of arguing over one picture.
		var world_name: String = ""
		var world: Image = measured.get("world_image")
		if world != null:
			world_name = "%02d_%s_world.png" % [_results.size() + 1, state_name]
			world.save_png(_out_dir.path_join(world_name))

		_results.append({
			"state": state_name,
			"observed": observed,
			"file": file_name,
			"world_file": world_name,
			"strip_file": _strip_for_state,
			"probe_visible_frames": _probe_frames,
			"strip_sample_ms": _strip_times_ms.duplicate(),
			"movement_samples": _movement_samples.duplicate(true),
			"width": shot.get_width(),
			"height": shot.get_height(),
			"hud_coverage": snappedf(measured.get("hud_coverage", 0.0), 0.0001),
			"frame_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
			"blank": _looks_blank(shot),
			# The world behind the HUD. A tour run against a server that never
			# started photographs an empty grey room, and the HUD panel alone
			# is enough texture to make the whole frame look non-blank.
			"world_blank": measured.get("world_blank", false),
			"note": state.get("note", ""),
		})
		print("qa_tour: %s -> %s hud %.1f%% world_blank=%s" % [
			state_name, file_name, measured.get("hud_coverage", 0.0) * 100.0,
			str(measured.get("world_blank", false)),
		])
		if state.get("overlay", "") in ["match_menu", "match_settings"]:
			_game_manager().get_node("PauseMenu").call("close")

	_write_manifest(tour)
	_write_contact_sheet()
	print("qa_tour: ", _results.size(), " states under ", _out_dir)
	# Retire the live world while the rendering server can still drain resource
	# frees. Quitting on the capture frame can strand Compatibility sky textures.
	if self.current_scene != null:
		self.current_scene.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	quit(1 if _failed else 0)

func _load_manifest() -> Dictionary:
	var path: String = OS.get_environment("FRAGR_QA_MANIFEST")
	if path.is_empty():
		path = MANIFEST_PATH
	if not FileAccess.file_exists(path):
		push_error("qa_tour: no manifest at " + path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("qa_tour: manifest is not an object")
		return {}
	return parsed

func _grab() -> Image:
	return get_root().get_viewport().get_texture().get_image()

## Hide the HUD for one frame and compare. Gives two numbers at once: the share
## of the screen the HUD paints over, measured rather than argued about, and
## whether there is a game behind it at all.
func _measure() -> Dictionary:
	var out: Dictionary = {"hud_coverage": 0.0, "world_blank": false}
	# Freeze first. Without this the two frames are a fight two frames apart,
	# and every bot that moved between them counts as HUD.
	paused = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var with_hud: Image = _grab()
	out["shot"] = with_hud
	var hud: Node = _find_hud()
	if hud == null or with_hud == null:
		paused = false
		out["world_blank"] = with_hud != null and _looks_blank(with_hud)
		return out
	hud.set("visible", false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var bare: Image = _grab()
	hud.set("visible", true)
	await RenderingServer.frame_post_draw
	paused = false
	out["world_image"] = bare
	if bare == null or bare.get_size() != with_hud.get_size():
		return out
	out["world_blank"] = _looks_blank(bare)
	var differing: int = 0
	var total: int = 0
	# Every fourth pixel on each axis: a sixteenth of the work, for a number
	# that does not move in the second decimal place.
	for y in range(0, bare.get_height(), 4):
		for x in range(0, bare.get_width(), 4):
			total += 1
			var a: Color = bare.get_pixel(x, y)
			var b: Color = with_hud.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > DIFF_EPSILON:
				differing += 1
	if total > 0:
		out["hud_coverage"] = float(differing) / float(total)
	return out

## Capture consecutive frames or timed samples through an effect's full lifetime.
func _capture_strip(state: Dictionary, frames: int, file_name: String) -> void:
	var trigger: String = state.get("trigger", "")
	var interval: float = float(state.get("strip_interval_seconds", 0.0))
	var walk_action: String = str(state.get("walk_action", "move_forward"))
	var walk_start: Vector3 = Vector3.ZERO
	if trigger == "walk":
		walk_start = _local_feet()
		Input.action_press(walk_action)
	# A named node to watch while the strip runs. An effect that lasts a frame
	# or two is easy to miss by eye and easy to believe is absent, so the tour
	# counts the frames it was actually up instead of leaving it to the eye.
	var probe_name: String = state.get("probe", "")
	var probe: Node = get_root().find_child(probe_name, true, false) if probe_name != "" else null
	_probe_frames = 0
	_strip_times_ms.clear()
	if probe_name != "" and probe == null:
		push_error("qa_tour: no node named " + probe_name + " to watch")
		_failed = true
	if trigger == "fire":
		Input.action_press("fire")
		# Start at an acknowledged visible flash, not a guessed round trip.
		if probe != null:
			var deadline: int = Time.get_ticks_msec() + 2500
			while not _probe_active(probe, state) and Time.get_ticks_msec() < deadline:
				await RenderingServer.frame_post_draw
		if state.get("single_shot", false):
			Input.action_release("fire")
	elif trigger == "reload":
		var press: InputEventAction = InputEventAction.new()
		press.action = &"reload"
		press.pressed = true
		Input.parse_input_event(press)
		var release: InputEventAction = InputEventAction.new()
		release.action = &"reload"
		Input.parse_input_event(release)
		var deadline: int = Time.get_ticks_msec() + 2000
		while _equipment().get("reload") == null and Time.get_ticks_msec() < deadline:
			await process_frame
		if _equipment().get("reload") == null:
			push_error("qa_tour: no authoritative reload after input")
			_failed = true
	for _i in range(STRIP_LEAD_FRAMES):
		await RenderingServer.frame_post_draw
	var shots: Array[Image] = []
	var start_ms: int = Time.get_ticks_msec()
	for i in range(frames):
		if i > 0 and interval > 0.0:
			await create_timer(interval).timeout
		await RenderingServer.frame_post_draw
		_strip_times_ms.append(Time.get_ticks_msec() - start_ms)
		if trigger == "walk":
			_record_movement()
		if probe != null and _probe_active(probe, state):
			_probe_frames += 1
		var img: Image = _grab()
		if img != null:
			img.convert(Image.FORMAT_RGBA8)
			if i == 0 and img.save_png(_out_dir.path_join(file_name.trim_suffix("_strip.png") + "_shot.png")) != OK:
				push_error("qa_tour: could not save full-size acknowledged shot")
				_failed = true
			if state.get("bottom_crop", false):
				img = img.get_region(Rect2i((img.get_width() - 384) / 2, img.get_height() - 256, 384, 256))
			shots.append(img)
	if trigger == "walk":
		Input.action_release(walk_action)
		if _local_feet().distance_to(walk_start) < 0.8:
			push_error("qa_tour: weapon walk strip did not move through the server")
			_failed = true
	if trigger == "fire":
		Input.action_release("fire")
	if probe_name != "" and _probe_frames == 0:
		push_error("qa_tour: shot produced no visible " + probe_name)
		_failed = true
	if state.get("expect_expiry", false) and probe != null and _probe_active(probe, state):
		push_error("qa_tour: effect remained active at the end of its lifetime strip")
		_failed = true
	if shots.is_empty():
		return
	var tile_width: int = STRIP_TILE_WIDTH
	var tile_height: int = int(round(
		float(tile_width) * float(shots[0].get_height()) / float(shots[0].get_width())
	))
	var sheet: Image = Image.create(
		tile_width * shots.size(), tile_height, false, Image.FORMAT_RGBA8
	)
	sheet.fill(Color(0.06, 0.06, 0.07, 1.0))
	for i in range(shots.size()):
		var tile: Image = shots[i]
		tile.resize(tile_width, tile_height, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(i * tile_width, 0))
	var err: Error = sheet.save_png(_out_dir.path_join(file_name))
	if err != OK:
		push_error("qa_tour: strip failed (%s)" % str(err))
		return
	if probe_name != "":
		print("qa_tour: %s -> %s (%d frames, %s up for %d)" % [
			state.get("name", ""), file_name, shots.size(), probe_name, _probe_frames,
		])
	else:
		print("qa_tour: %s -> %s (%d frames)" % [state.get("name", ""), file_name, shots.size()])

func _probe_active(probe: Node, state: Dictionary) -> bool:
	if probe is MeleeView:
		return probe.visible and probe.remaining > 0.0
	if probe is EquipmentHud:
		return probe.visible and probe.state.get("reload") != null and EquipmentState.reload_progress(probe.state, probe.tick) < 1.0
	if probe is ShotEffects:
		var network: Node = _game_manager().get("net_client")
		return probe.has_shot_from(str(network.get("player_id")), str(state.get("impact_kind", "")))
	return bool(probe.get("visible"))

func _find_hud() -> Node:
	return get_root().find_child("HUD", true, false)

## Join the match as a person rather than watching it. Without this the
## first-person states are photographs of the spectator camera, which is the
## one view a player never sees.
func _change_role(play: bool) -> void:
	var gm: Node = _game_manager()
	if gm == null:
		push_error("qa_tour: no GameManager for role transition")
		_failed = true
		return
	if bool(gm.get("is_human_player")) != play:
		await gm.change_role(play)
		await create_timer(4.5).timeout
	var net: Node = gm.get_node("NetClient")
	if net.get("connection_state") != WebSocketPeer.STATE_OPEN or (play and net.get("player_id") == null):
		push_error("qa_tour: role transition did not connect")
		_failed = true
	_joined = play

func _select_weapon(weapon: String) -> void:
	var gm: Node = _game_manager()
	gm.set("pending_weapon_swap", weapon.to_lower())
	var deadline: int = Time.get_ticks_msec() + 3000
	while str(gm.call("_local_weapon_name")) != weapon and Time.get_ticks_msec() < deadline:
		await process_frame
	if str(gm.call("_local_weapon_name")) != weapon:
		push_error("qa_tour: server did not equip " + weapon)
		_failed = true

func _observed_state() -> Dictionary:
	var gm: Node = _game_manager()
	if gm == null:
		return {"menu": true}
	var snapshot: Dictionary = gm.get("latest_snapshot")
	var cam: Node = _spectator_camera()
	var server_pitch: float = _local_server_pitch(gm)
	var server_yaw: float = _local_server_yaw(gm)
	var camera_forward: Vector3 = -cam.get("transform").basis.z
	return {
		"map_id": snapshot.get("map_id", 0),
		"round_state": snapshot.get("round_state", "unknown"),
		"fighters": (snapshot.get("players", []) as Array).size(),
		"human": gm.get("is_human_player"),
		"local_weapon": gm.call("_local_weapon_name"),
		"equipment": _equipment(),
		"eye_view": cam.get("fp_mode") or cam.call("is_observing_first_person"),
		"following": gm.call("_followed_player_id"),
		"camera_pitch": float(cam.get("rotation").x),
		"camera_yaw": atan2(camera_forward.z, camera_forward.x),
		"server_yaw": server_yaw if absf(server_yaw) <= TAU else null,
		"server_pitch": server_pitch if absf(server_pitch) <= ServerYaw.PITCH_LIMIT else null,
	}

func _equipment() -> Dictionary:
	return _game_manager().get("net_client").get("equipment")

func _empty_magazine() -> void:
	var state: Dictionary = _equipment()
	if state.is_empty() or state["selected"] == "fists":
		push_error("qa_tour: cannot drain a missing gun")
		_failed = true
		return
	Input.action_press("fire")
	var deadline: int = Time.get_ticks_msec() + 15000
	while EquipmentState.magazine(_equipment(), state["selected"]) > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	# Keep the trigger down long enough to observe the dry edge as well.
	await create_timer(0.5).timeout
	Input.action_release("fire")
	if EquipmentState.magazine(_equipment(), state["selected"]) != 0 or int(_equipment()["dry_fire_count"]) <= int(state["dry_fire_count"]):
		push_error("qa_tour: magazine did not empty and produce dry feedback")
		_failed = true

func _check_equipment(expected: Dictionary) -> void:
	var state: Dictionary = _equipment()
	if state.is_empty():
		push_error("qa_tour: missing equipment")
		_failed = true
		return
	for key: String in expected:
		var actual: Variant = state.get(key)
		if key == "magazine":
			actual = EquipmentState.magazine(state, state["selected"])
		elif key == "reserve":
			actual = EquipmentState.reserve(state, state["selected"])
		if actual != expected[key]:
			push_error("qa_tour: expected %s %s, observed %s" % [key, expected[key], actual])
			_failed = true

func _local_server_yaw(gm: Node) -> float:
	var snapshot: Dictionary = gm.get("latest_snapshot")
	var network: Node = gm.get("net_client")
	for player: Dictionary in snapshot.get("players", []):
		if str(player.get("id", "")) == str(network.get("player_id")):
			return float(player.get("yaw", 99.0))
	return 99.0

func _local_server_pitch(gm: Node) -> float:
	var snapshot: Dictionary = gm.get("latest_snapshot")
	var network: Node = gm.get("net_client")
	for player in snapshot.get("players", []):
		if str(player.get("id", "")) == str(network.get("player_id")):
			return float(player.get("pitch", 99.0))
	return 99.0

func _local_feet() -> Vector3:
	var gm: Node = _game_manager()
	var snapshot: Dictionary = gm.get("latest_snapshot")
	var network: Node = gm.get("net_client")
	for player: Dictionary in snapshot.get("players", []):
		if str(player.get("id", "")) == str(network.get("player_id")):
			return Vector3(float(player.x), float(player.y) - CameraScript.FP_SERVER_REFERENCE_Y, float(player.z))
	push_error("qa_tour: movement probe has no live human")
	_failed = true
	return Vector3(INF, INF, INF)

func _record_movement() -> void:
	var feet: Vector3 = _local_feet()
	var camera: Node3D = _spectator_camera()
	var hud: Node = _find_hud()
	var weapon: TextureRect = hud.get_node("FpWeapon")
	_movement_samples.append({"ms": Time.get_ticks_msec(), "x": feet.x,
		"y": feet.y, "z": feet.z, "camera_y": camera.global_position.y,
		"weapon_y": weapon.position.y, "weapon_bottom": weapon.position.y + weapon.size.y,
		"bob_weight": float(hud.get("fp_bob_weight"))})

func _jump_probe() -> void:
	var start: Vector3 = _local_feet()
	if not start.is_finite():
		return
	# Both events happen before a render frame, then travel through normal input,
	# networking, the authoritative tick, pawn interpolation, and the eye camera.
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_SPACE
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	var peak: float = start.y
	var camera_start: float = (_spectator_camera() as Node3D).global_position.y
	var camera_peak: float = camera_start
	for sample in range(24):
		await create_timer(0.05).timeout
		_record_movement()
		peak = maxf(peak, _local_feet().y)
		camera_peak = maxf(camera_peak, (_spectator_camera() as Node3D).global_position.y)
		if sample == 6:
			await RenderingServer.frame_post_draw
			if _grab().save_png(_out_dir.path_join("jump_peak.png")) != OK:
				_failed = true
	if peak - start.y < 0.8 or absf(_local_feet().y - start.y) > 0.03 or camera_peak - camera_start < 0.5:
		push_error("qa_tour: short jump did not rise, move the eye camera, and land")
		_failed = true
	print("qa_tour: jump peak %.3f m, eye rise %.3f m" % [peak - start.y, camera_peak - camera_start])

func _walk_to(goal: Vector3) -> void:
	var deadline: int = Time.get_ticks_msec() + 15000
	var camera: Node = _spectator_camera()
	Input.action_release("jump")
	Input.action_press("move_forward")
	var arrived: bool = false
	while Time.get_ticks_msec() < deadline:
		var feet: Vector3 = _local_feet()
		if not feet.is_finite():
			break
		if Vector2(feet.x - goal.x, feet.z - goal.z).length() < 0.3 and absf(feet.y - goal.y) < 0.03:
			arrived = true
			break
		camera.set("fp_yaw", atan2(goal.z - feet.z, goal.x - feet.x))
		camera.set("fp_pitch", 0.0)
		_record_movement()
		await create_timer(0.05).timeout
	Input.action_release("move_forward")
	await create_timer(0.15).timeout
	if not arrived:
		push_error("qa_tour: ordinary walk failed to reach %s, stopped at %s" % [goal, _local_feet()])
		_failed = true

func _set_aim_pitch(pitch: float) -> void:
	var gm: Node = _game_manager()
	var cam: Node = _spectator_camera()
	if gm == null or cam == null or not bool(gm.get("is_human_player")):
		push_error("qa_tour: pitch capture requires a joined human")
		_failed = true
		return
	cam.set("fp_pitch", pitch)
	var deadline: int = Time.get_ticks_msec() + 3000
	while absf(_local_server_pitch(gm) - pitch) > 0.001 and Time.get_ticks_msec() < deadline:
		await process_frame
	if absf(_local_server_pitch(gm) - pitch) > 0.001:
		push_error("qa_tour: pitch did not reach the authoritative snapshot")
		_failed = true

func _pose_camera(mode: String) -> void:
	if mode == "none":
		return
	var cam: Node = _spectator_camera()
	if cam == null:
		return
	cam.set("frag_follow_timer", 0.0)
	match mode:
		"overview":
			cam.set("spectator_first_person", false)
			if cam is Node3D:
				var n3: Node3D = cam
				n3.global_position = Vector3(0, 22, 28)
				n3.look_at(Vector3.ZERO, Vector3.UP)
			if "follow_mode" in cam:
				cam.set("follow_mode", false)
			if "fp_mode" in cam:
				cam.set("fp_mode", false)
		"follow":
			cam.set("spectator_first_person", false)
			if "follow_mode" in cam:
				cam.set("follow_mode", true)
			if "fp_mode" in cam:
				cam.set("fp_mode", false)
		"first_person":
			if not _joined:
				cam.set("follow_mode", true)
				cam.set("spectator_first_person", true)
		_:
			push_warning("qa_tour: unknown camera mode " + mode)

func _spectator_camera() -> Node:
	var gm: Node = _game_manager()
	return gm.get_node_or_null("SpectatorCamera") if gm != null else null

func _game_manager() -> Node:
	for child in get_root().get_children():
		if child.name == "GameManager":
			return child
	return null

## A still that is one flat colour is a failed capture, not a clean frame.
func _looks_blank(img: Image) -> bool:
	if img.get_width() < 2 or img.get_height() < 2:
		return true
	var first: Color = img.get_pixel(0, 0)
	for y in range(0, img.get_height(), 16):
		for x in range(0, img.get_width(), 16):
			var c: Color = img.get_pixel(x, y)
			if absf(c.r - first.r) + absf(c.g - first.g) + absf(c.b - first.b) > DIFF_EPSILON:
				return false
	return true

func _write_manifest(tour: Dictionary) -> void:
	var out: Dictionary = {
		"captured_utc": Time.get_datetime_string_from_system(true),
		"godot": Engine.get_version_info().get("string", ""),
		"width": tour.get("width", 0),
		"height": tour.get("height", 0),
		"states": _results,
	}
	var path: String = _out_dir.path_join("manifest.json")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("qa_tour: could not write " + path)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()

## One sheet, every state, in tour order, so a pass over the whole game is one
## look rather than a folder opened a file at a time.
func _write_contact_sheet() -> void:
	if _results.is_empty():
		return
	var thumbs: Array[Image] = []
	for row in _results:
		var img: Image = Image.load_from_file(_out_dir.path_join(row["file"]))
		if img == null:
			continue
		var height: int = int(round(float(THUMB_WIDTH) * float(img.get_height()) / float(img.get_width())))
		img.resize(THUMB_WIDTH, height, Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGBA8)
		thumbs.append(img)
	if thumbs.is_empty():
		return
	var thumb_height: int = thumbs[0].get_height()
	var columns: int = mini(CONTACT_COLUMNS, thumbs.size())
	var rows: int = int(ceil(float(thumbs.size()) / float(columns)))
	var sheet: Image = Image.create(columns * THUMB_WIDTH, rows * thumb_height, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.06, 0.06, 0.07, 1.0))
	for i in range(thumbs.size()):
		var col: int = i % columns
		var row_index: int = i / columns
		sheet.blit_rect(
			thumbs[i],
			Rect2i(Vector2i.ZERO, thumbs[i].get_size()),
			Vector2i(col * THUMB_WIDTH, row_index * thumb_height)
		)
	var err: Error = sheet.save_png(_out_dir.path_join("contact.png"))
	if err != OK:
		push_error("qa_tour: contact sheet failed (%s)" % str(err))
