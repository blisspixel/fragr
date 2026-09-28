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
var _companion_strip_samples: Array[Dictionary] = []
var _companion_route_samples: Array[Dictionary] = []
var _companion_route_images: Array[Image] = []
var _companion_route_capture: bool = false
var _companion_route_last_ms: int = 0
var _companion_route_file: String = ""
var _failed: bool = false
var _movement_samples: Array[Dictionary] = []
var _walk_results: Array[Dictionary] = []
var _combat_probe: QaCombat = QaCombat.new()
var _combat_travel: bool = false
var _retiring_audio: Array[WeakRef] = []
var _capture_size: Vector2i = Vector2i.ZERO
## The fighter a "body" camera holds on, and the side it had to be on.
var _body_pawn: Node3D = null
var _body_kind: String = ""
var _body_team: String = ""
## Frames between the trigger and the first strip frame. The shot is resolved by
## the server, so the flash arrives a round trip later, not on the next frame.
const STRIP_LEAD_FRAMES: int = 2

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("_run")

func _finalize() -> void:
	_combat_probe.finish()
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
	set_meta("fragr_records_path", _out_dir.path_join("service-record"))
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
	_combat_travel = tour.get("combat_travel", false)
	# A custom SceneTree can inherit the project's fullscreen mode even when
	# the launcher requests a resolution. Set the actual window explicitly.
	root.mode = Window.MODE_WINDOWED
	_capture_size = Vector2i(int(tour["width"]), int(tour["height"]))
	root.size = _capture_size
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
		_companion_route_capture = state.get("capture_companion_route", false)
		_companion_route_samples.clear()
		_companion_route_images.clear()
		_companion_route_last_ms = 0
		_companion_route_file = ""

		var scene: String = state.get("scene", "")
		if not scene.is_empty() and scene != current_scene:
			_track_scene_audio()
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

		_release_body_camera()
		var menu_page: String = state.get("menu_page", "")
		if not menu_page.is_empty():
			get_root().get_node("BootMenu").call("_show", menu_page)
			await process_frame
			if menu_page == "single":
				var preview_deadline: int = Time.get_ticks_msec() + 10000
				var preview: Dictionary = LocalMatch.for_tree(self).run_preview
				while str(preview.get("status", "loading")) == "loading" and Time.get_ticks_msec() < preview_deadline:
					await create_timer(0.05).timeout
					preview = LocalMatch.for_tree(self).run_preview
				if str(preview.get("status", "")) != "missing":
					push_error("qa_tour: isolated Single Player preview did not reach missing-run state")
					_failed = true
			if menu_page == "records":
				var panel: RecordsPanel = get_root().get_node("BootMenu").get("_root").get_node("ServiceRecord")
				panel._select_kind(str(state.get("record_kind", "mission")))
				if state.get("expect_records", false) and panel.records.entries.is_empty():
					push_error("qa_tour: service record has no actual match observation")
					_failed = true
		if state.has("profile_body"):
			# The next join asks for this body through the saved profile.
			var preferences: FragrSettings = FragrSettings.for_tree(self)
			preferences.load_from_disk()
			preferences.set_value("profile", "body", str(state["profile_body"]))
			preferences.save_to_disk()
			if _game_manager() != null:
				_game_manager().settings.set_value("profile", "body", str(state["profile_body"]))
		if state.has("join"):
			await _change_role(state["join"] == "human")
			if _joined:
				_combat_probe.begin(_game_manager())
		if state.has("record_status"):
			var deadline: int = Time.get_ticks_msec() + 200000
			while _game_manager().net_client.record.get("status") != state["record_status"] and Time.get_ticks_msec() < deadline:
				await create_timer(0.05).timeout
			if _game_manager().net_client.record.get("status") != state["record_status"]:
				push_error("qa_tour: participant never reached requested record status")
				_failed = true
		if state.has("weapon"):
			await _select_weapon(str(state["weapon"]))
		if state.has("aim_pitch"):
			await _set_aim_pitch(float(state["aim_pitch"]))
		_movement_samples.clear()
		_walk_results.clear()
		if state.get("jump_probe", false):
			await _jump_probe()
		# A detached observation state must hand the eye back before ordinary
		# walking resumes, or the next live route would send no human input.
		if state.get("camera", "") == "first_person" and _joined and not bool(_spectator_camera().get("fp_mode")):
			_pose_camera("first_person", state)
		for point: Array in state.get("walk_to", []):
			await _walk_to(Vector3(float(point[0]), float(point[1]), float(point[2])),
				state.get("route_look_back", false))
			if _failed:
				await _retire_scene()
				quit(1)
				return
		if state.has("expect_companion_displacement"):
			await _expect_companion_displacement(float(state["expect_companion_displacement"]), state_name)
		if state.get("expect_crawler_scrabble", false):
			var manager: Node = _game_manager()
			var caption: Node = manager.hud.get("crawler_caption") if manager != null else null
			var caption_label: Label = caption.get("caption_label") as Label if is_instance_valid(caption) else null
			var required_cues: int = int(state.get("expect_crawler_cues", 1))
			if manager == null or int(manager.get("crawler_scrabble_count")) != required_cues or \
				not is_instance_valid(caption_label) or \
				caption_label.text != tr("CAPTION_CRAWLER_SCRABBLE"):
				push_error("qa_tour: Crawler scrabble cue and live caption were not observed")
				_failed = true
			if manager != null and state.has("expect_crawler_source"):
				var source: Array = state["expect_crawler_source"]
				var expected_source: Vector3 = Vector3(float(source[0]), float(source[1]), float(source[2]))
				if (manager.get("crawler_last_position") as Vector3).distance_to(expected_source) > 0.2:
					push_error("qa_tour: Crawler scrabble came from the wrong landing")
					_failed = true
		var combat: Dictionary = {}
		if state.has("combat"):
			if state.get("camera", "") == "first_person":
				_pose_camera("first_person", state)
			combat = await _combat_probe.run(self, _game_manager(), state["combat"], _out_dir.path_join(state_name))
			if not combat.get("passed", false):
				_failed = true
		if state.has("look_at"):
			var target: Array = state["look_at"]
			var camera: Node3D = _spectator_camera()
			var direction: Vector3 = Vector3(float(target[0]), float(target[1]), float(target[2])) - camera.global_position
			camera.set("fp_yaw", atan2(direction.z, direction.x))
			await _set_aim_pitch(atan2(direction.y, Vector2(direction.x, direction.z).length()))
		if state.get("empty_ammo", false):
			await _empty_ammo()
		if state.has("interact"):
			await _use_mission_control(str(state["interact"]))
		if state.has("expect_m02_ward_stage"):
			await _expect_m02_ward_stage(str(state["expect_m02_ward_stage"]), state_name)
		if state.has("expect_m02_side_stage"):
			await _expect_m02_side_stage(str(state["expect_m02_side_stage"]), state_name)
		if state.has("expect_m02_evacuation_phase"):
			await _expect_m02_evacuation_phase(str(state["expect_m02_evacuation_phase"]), state_name)
		if state.has("expect_m02_gate_mask"):
			await _expect_m02_gate_mask(int(state["expect_m02_gate_mask"]), state_name)
		if state.has("expect_companion_phase"):
			await _expect_companion_phase(str(state["expect_companion_phase"]), state_name)
		if state.has("await_run_status"):
			var run_deadline: int = Time.get_ticks_msec() + 120000
			while _run_status() != str(state["await_run_status"]) and Time.get_ticks_msec() < run_deadline:
				await create_timer(0.1).timeout
			if _run_status() != str(state["await_run_status"]):
				push_error("qa_tour: %s never reached run status %s" % [state_name, state["await_run_status"]])
				_failed = true
		if state.has("input_device"):
			await _use_input_device(str(state["input_device"]), str(state.get("pad_layout", "")))
		if state.get("expect_prompt", false):
			var prompt_deadline: int = Time.get_ticks_msec() + 3000
			while _game_manager().mission_hud.prompt_text.is_empty() and Time.get_ticks_msec() < prompt_deadline:
				await create_timer(0.05).timeout
			if _game_manager().mission_hud.prompt_text.is_empty():
				push_error("qa_tour: %s expected a live use prompt" % state_name)
				_failed = true
		if state.get("overlay", "") == "match_menu":
			_game_manager().get_node("PauseMenu").call("open")
		if state.get("overlay", "") == "match_settings":
			var match_menu: PauseMenu = _game_manager().get_node("PauseMenu")
			match_menu.open()
			match_menu.show_settings()
		if state.has("settings_tab"):
			var settings_root: Node = get_root().get_node("BootMenu").get("_root")
			(settings_root.get_node("SettingsPanel") as SettingsPanel).show_page(str(state["settings_tab"]))
		if state.has("graphics"):
			_apply_graphics_capture(state["graphics"])
		var frame_timing: Dictionary = {}
		if state.has("frame_sample"):
			_pose_camera(state.get("camera", "none"), state)
			frame_timing = await _sample_frames(int(state["frame_sample"]))
		# Readability evidence: the _world still of this state then has neither HUD
		# nor world sign copy, so only lamps, pictograms and geometry explain it.
		var hidden_copy: Array[Node3D] = []
		if state.get("hide_world_text", false):
			for label: Node in get_root().find_children("*", "Label3D", true, false):
				if label is WorldSign and (label as Node3D).visible:
					(label as Node3D).visible = false
					hidden_copy.append(label as Node3D)
		if state.get("camera", "") == "body":
			await _find_body(str(state.get("body", "")), str(state.get("body_team", "")))
		_pose_camera(state.get("camera", "none"), state)
		# A detached live-combat view needs only a few settled frames. Holding
		# the human still for the menu-still delay would change the fight.
		await create_timer(0.2 if state.has("expect_active_enemies") else 0.75).timeout
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var active_enemy_phases: Dictionary[String, String] = {}
		if state.has("expect_active_enemies"):
			var expected_active: Variant = state["expect_active_enemies"]
			if not expected_active is Array or expected_active.is_empty():
				push_error("qa_tour: active enemies require a nonempty name list")
				_failed = true
			else:
				active_enemy_phases = active_named_enemies(_game_manager().get("latest_snapshot"), expected_active)
				if active_enemy_phases.size() != expected_active.size():
					push_error("qa_tour: named pack enemies were not all active in the spectator frame")
					_failed = true
		if state.has("expect_enemy_phases"):
			var expected_phases: Variant = state["expect_enemy_phases"]
			if not expected_phases is Dictionary or expected_phases.is_empty():
				push_error("qa_tour: enemy phases require a nonempty name-to-phase map")
				_failed = true
			else:
				var actual_phases: Dictionary[String, String] = active_named_enemies(
					_game_manager().get("latest_snapshot"), expected_phases.keys())
				for enemy_name: String in expected_phases:
					if actual_phases.get(enemy_name, "") != str(expected_phases[enemy_name]):
						push_error("qa_tour: %s has phase %s, expected %s in %s" % [
							enemy_name, actual_phases.get(enemy_name, "missing"), expected_phases[enemy_name], state_name])
						_failed = true

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
			_companion_strip_samples.clear()
		if state.has("expect_equipment"):
			_check_equipment(state["expect_equipment"])
		# A live bot can kill the idle tour pawn during the framing delay. Wait
		# for its next authoritative spawn and resend the authored aim before
		# sampling the frame, including after a first-person camera handoff.
		if state.has("weapon"):
			await _select_weapon(str(state["weapon"]))
		if state.has("aim_pitch"):
			await _set_aim_pitch(float(state["aim_pitch"]))

		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw

		var measured: Dictionary = await _measure()
		var shot: Image = measured.get("shot")
		if shot == null:
			push_error("qa_tour: no frame for state " + state_name)
			quit(1)
			return

		var file_name: String = "%02d_%s.png" % [_results.size() + 1, state_name]
		if _companion_route_capture:
			await _record_companion_route(true)
			_companion_route_file = _save_companion_route_strip(state_name)
			_companion_route_capture = false
		if _looks_blank(shot) or measured.get("world_blank", false):
			push_error("qa_tour: blank capture for " + state_name)
			_failed = true
		if shot.get_width() != int(tour["width"]) or shot.get_height() != int(tour["height"]):
			push_error("qa_tour: unexpected capture size for " + state_name)
			_failed = true
		var observed: Dictionary = _observed_state().duplicate(true)
		if state.has("expect_active_enemies"):
			observed["active_enemy_phases"] = active_enemy_phases
		if _joined and _game_manager() != null:
			observed["accepted_body"] = _game_manager().net_client.accepted_body
		if is_instance_valid(_body_pawn):
			observed["body"] = _body_pawn.get("body_kind")
			observed["body_team"] = _body_pawn.get("team")
			observed["body_name"] = _body_pawn.get("player_name")
		observed["render_scale"] = root.scaling_3d_scale
		observed["upscaling"] = root.scaling_3d_mode
		observed["msaa"] = root.msaa_3d
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
			var camera_pitch: float = float(observed.get("camera_pitch", 99.0))
			var server_pitch: float = _local_server_pitch(_game_manager())
			if absf(camera_pitch - expected_pitch) > 0.001 or absf(server_pitch - expected_pitch) > 0.001:
				push_error("qa_tour: captured aim disagrees with the server for %s (expected %.3f, camera %.3f, server %.3f)" % [state_name, expected_pitch, camera_pitch, server_pitch])
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
			"companion_strip_samples": _companion_strip_samples.duplicate(true),
			"companion": _companion_observation(),
			"companion_route_samples": _companion_route_samples.duplicate(true),
			"companion_route_strip": _companion_route_file,
			"movement_samples": _movement_samples.duplicate(true),
			"walks": _walk_results.duplicate(true),
			"combat": combat,
			"width": shot.get_width(),
			"height": shot.get_height(),
			"hud_coverage": snappedf(measured.get("hud_coverage", 0.0), 0.0001),
			"frame_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
			"frame_timing": frame_timing,
			"blank": _looks_blank(shot),
			# The world behind the HUD. A tour run against a server that never
			# started photographs an empty grey room, and the HUD panel alone
			# is enough texture to make the whole frame look non-blank.
			"world_blank": measured.get("world_blank", false),
			"note": state.get("note", ""),
			"input": {"kind": ["keyboard", "mouse", "gamepad"][InputDevice.kind], "look": InputDevice.look_source, "pad_layout": InputDevice.pad_layout, "prompt": _game_manager().mission_hud.prompt_text if _game_manager() != null and _game_manager().get("mission_hud") != null else "", "recovery": _game_manager().mission_hud.recovery_text if _game_manager() != null and _game_manager().get("mission_hud") != null and _game_manager().mission_hud._recovery.visible else ""},
		})
		print("qa_tour: %s -> %s hud %.1f%% world_blank=%s" % [
			state_name, file_name, measured.get("hud_coverage", 0.0) * 100.0,
			str(measured.get("world_blank", false)),
		])
		for label: Node3D in hidden_copy:
			if is_instance_valid(label):
				label.visible = true
		if state.get("overlay", "") in ["match_menu", "match_settings"]:
			_game_manager().get_node("PauseMenu").call("close")
		if _failed and _combat_travel:
			break

	_write_manifest(tour)
	_write_contact_sheet()
	print("qa_tour: ", _results.size(), " states under ", _out_dir)
	await _retire_scene()
	quit(1 if _failed else 0)

func _retire_scene() -> void:
	# Retire the live world while the rendering server can still drain resource
	# frees. Quitting on the capture frame can leave textures pending retirement.
	if self.current_scene != null:
		_track_scene_audio()
		self.current_scene.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	else:
		await process_frame
	# Audio retirement runs on mixer time, not rendering or process frames.
	# Observe release instead of guessing how many frames make shutdown safe.
	var deadline: int = Time.get_ticks_msec() + 2000
	while not _retiring_audio.is_empty() and Time.get_ticks_msec() < deadline:
		for index: int in range(_retiring_audio.size() - 1, -1, -1):
			if _retiring_audio[index].get_ref() == null:
				_retiring_audio.remove_at(index)
		if not _retiring_audio.is_empty():
			await create_timer(0.01).timeout
	if not _retiring_audio.is_empty():
		push_error("qa_tour: %d audio playbacks remain after scene retirement" % _retiring_audio.size())
		_failed = true

func _track_scene_audio() -> void:
	if self.current_scene == null:
		return
	for node: Node in self.current_scene.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			if node.has_stream_playback():
				_retiring_audio.append(weakref(node.get_stream_playback()))

static func valid_walks(states: Variant) -> bool:
	if not states is Array or states.is_empty():
		return false
	for state: Variant in states:
		if not state is Dictionary or not QaCombat.valid_waypoints(state.get("walk_to", [])):
			return false
		if state.get("camera", "") == "overview" and state.has("camera_position") and \
			not QaCombat.valid_waypoints([state.get("camera_position"), state.get("camera_look_at")]):
			return false
	return true

static func active_named_enemies(snapshot: Dictionary, names: Array) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for actor: Dictionary in snapshot.get("players", []):
		if actor.get("name", "") in names and int(actor.get("hp", 0)) > 0 and \
			ActorState.is_union(actor):
			found[str(actor["name"])] = str(actor["campaign"]["phase"])
	return found

func _apply_graphics_capture(options: Variant) -> void:
	var manager: Node = _game_manager()
	if manager == null or not options is Dictionary:
		push_error("qa_tour: graphics capture needs a live match and an options object")
		_failed = true
		return
	var preferences: FragrSettings = manager.get("settings")
	var draft: FragrSettings = preferences.draft()
	for key: Variant in options:
		if key == "dither":
			if not options[key] is bool:
				push_error("qa_tour: dither capture option must be a boolean")
				_failed = true
				return
			draft.set_value("video", key, options[key])
			continue
		if key not in ["quality", "upscaling", "resolution_height", "pixel_scale"] or not (options[key] is int or options[key] is float) or not is_finite(float(options[key])) or float(options[key]) != floorf(float(options[key])):
			push_error("qa_tour: invalid graphics capture option")
			_failed = true
			return
		draft.set_value("video", key, int(options[key]))
		if draft.get_value("video", key) != int(options[key]):
			push_error("qa_tour: unsupported graphics capture value")
			_failed = true
			return
	for key: String in options:
		preferences.set_value("video", key, draft.get_value("video", key))
	# Keep the capture window fixed while exercising the production world-buffer
	# and quality path. Display-mode transitions have their own real-window check.
	manager.call("_apply_render_preferences")

## Frame pacing for a held view: wall time between drawn frames plus the
## renderer's own CPU and GPU measurements for the root viewport. The capture
## settings leave VSync off and the frame cap unlimited, so the wall time is
## the cost of the frame rather than the display's refresh interval.
func _sample_frames(count: int) -> Dictionary:
	if count < 10 or count > 2000:
		push_error("qa_tour: frame_sample needs 10 to 2000 frames")
		_failed = true
		return {}
	# The desktop can resize a large capture window between states. Timing is
	# only comparable at the manifest's size, so restore it before sampling.
	if root.size != _capture_size:
		print("qa_tour: restoring capture window from ", root.size)
		root.mode = Window.MODE_WINDOWED
		root.size = _capture_size
		for _settle: int in range(10):
			await RenderingServer.frame_post_draw
	var viewport: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	for _warm: int in range(30):
		await RenderingServer.frame_post_draw
	var deltas: Array[float] = []
	var gpu: float = 0.0
	var cpu: float = 0.0
	var last: int = Time.get_ticks_usec()
	for _i: int in range(count):
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		deltas.append(float(now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
	RenderingServer.viewport_set_measure_render_time(viewport, false)
	var total: float = 0.0
	for value: float in deltas:
		total += value
	var sorted: Array[float] = deltas.duplicate()
	sorted.sort()
	var result: Dictionary = {
		"frames": count,
		"mean_ms": snappedf(total / count, 0.01),
		"p95_ms": snappedf(sorted[mini(count - 1, int(count * 0.95))], 0.01),
		"gpu_ms": snappedf(gpu / count, 0.01),
		"render_cpu_ms": snappedf(cpu / count, 0.01),
		"viewport": [root.size.x, root.size.y],
		"render_scale": root.scaling_3d_scale,
		"scaling_mode": root.scaling_3d_mode,
	}
	print("qa_tour: frame timing ", JSON.stringify(result))
	return result

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
	if not valid_walks(parsed.get("states")):
		push_error("qa_tour: states require finite lists of XYZ walking waypoints")
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
	_companion_strip_samples.clear()
	var interval: float = float(state.get("strip_interval_seconds", 0.0))
	var walk_action: String = str(state.get("walk_action", "move_forward"))
	var walk_start: Vector3 = Vector3.ZERO
	var walk_inputs: Array[Dictionary] = []
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
	for _i in range(STRIP_LEAD_FRAMES):
		await RenderingServer.frame_post_draw
	var shots: Array[Image] = []
	var start_ms: int = Time.get_ticks_msec()
	for i in range(frames):
		if i > 0 and interval > 0.0:
			await create_timer(interval).timeout
		await RenderingServer.frame_post_draw
		_strip_times_ms.append(Time.get_ticks_msec() - start_ms)
		if state.get("expect_companion_transition", false):
			_companion_strip_samples.append(_companion_observation())
		if trigger == "walk":
			_record_movement()
			var manager: Node = _game_manager()
			walk_inputs.append({"pressed": Input.is_action_pressed(walk_action), "blocked": manager.controls_blocked(), "action": manager.action_state.duplicate(true), "ack": manager.last_ack.duplicate(true)})
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
			push_error("qa_tour: weapon walk strip did not move through the server: " + JSON.stringify(walk_inputs))
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
	if state.get("expect_companion_transition", false):
		var saw_releasing: bool = false
		var saw_following: bool = false
		var release_tick: int = -1
		var following_tick: int = -1
		var transition_index: int = -1
		for sample_index: int in range(_companion_strip_samples.size()):
			var observation: Dictionary = _companion_strip_samples[sample_index]
			var phase: String = str(observation.get("phase", ""))
			var moving: bool = phase in ["following", "firing"]
			if observation.is_empty() or observation.get("pawn_visible") != moving \
				or observation.get("ward_visible") == moving or observation.get("followable") == true:
				push_error("qa_tour: companion strip handoff disagreed with the server: " + JSON.stringify(observation))
				_failed = true
			if phase == "releasing":
				if saw_following:
					push_error("qa_tour: companion returned to releasing after following")
					_failed = true
				saw_releasing = true
				release_tick = int(observation.get("phase_started", -1))
			elif phase in ["following", "firing"]:
				saw_following = true
				if following_tick < 0:
					following_tick = int(observation.get("phase_started", -1))
					transition_index = sample_index
		if not saw_releasing or not saw_following:
			push_error("qa_tour: companion strip missed the authoritative release-to-follow transition")
			_failed = true
		elif following_tick - release_tick != 240:
			push_error("qa_tour: companion release phase lasted %d ticks instead of 240" % (following_tick - release_tick))
			_failed = true
		if transition_index > 0 and transition_index < shots.size():
			var handoff_base: String = _out_dir.path_join(file_name.trim_suffix("_strip.png"))
			if shots[transition_index - 1].save_png(handoff_base + "_before.png") != OK \
				or shots[transition_index].save_png(handoff_base + "_after.png") != OK:
				push_error("qa_tour: could not save consecutive full-size companion handoff frames")
				_failed = true
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
	if probe is TextureRect and probe.name == "FpWeapon":
		# The held Shiv is always drawn; only its thrust is the effect.
		var hud: Node = _find_hud()
		if str(hud.get("current_fp_weapon")) == "Shiv":
			return probe.visible and float(hud.get("fp_stab_timer")) > 0.0
	if probe is MeleeView:
		return probe.visible and probe.remaining > 0.0
	if probe is EquipmentHud:
		return probe.visible and probe.dry_seconds > 0.0
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
	if play:
		if is_instance_valid(gm.opening):
			gm.opening.finish()
			print("qa_tour: skipped campaign opening through the presenter")
		var deadline: int = Time.get_ticks_msec() + 5000
		while gm._mission_controls_blocked() and Time.get_ticks_msec() < deadline:
			await process_frame
		if gm._mission_controls_blocked():
			push_error("qa_tour: server did not admit the ready participant")
			_failed = true
	_joined = play

func _select_weapon(weapon: String) -> void:
	var gm: Node = _game_manager()
	var deadline: int = Time.get_ticks_msec() + 6000
	while str(gm.call("_local_weapon_name")) != weapon and Time.get_ticks_msec() < deadline:
		# A swap issued during the respawn gap is cleared by the manager.
		# Reissue only after an authoritative pawn exists in the snapshot.
		if _local_server_pitch(gm) != 99.0:
			gm.set("pending_weapon_swap", weapon.to_lower())
		await create_timer(0.1).timeout
	if str(gm.call("_local_weapon_name")) != weapon:
		push_error("qa_tour: server did not equip " + weapon)
		_failed = true

func _observed_state() -> Dictionary:
	var gm: Node = _game_manager()
	if gm == null:
		var menu: Node = get_root().get_node_or_null("BootMenu")
		if menu != null and menu.get("_page") == "records":
			var panel: RecordsPanel = menu.get("_root").get_node("ServiceRecord")
			return {"menu": true, "record_kind": panel.get("_kind"), "records": panel.records.entries}
		return {"menu": true}
	var snapshot: Dictionary = gm.get("latest_snapshot")
	var cam: Node = _spectator_camera()
	var server_pitch: float = _local_server_pitch(gm)
	var server_yaw: float = _local_server_yaw(gm)
	var camera_forward: Vector3 = -cam.get("transform").basis.z
	var evacuation: Dictionary = gm.get("net_client").get("mission").get("state", {}).get("m02", {}).get("evacuation", {})
	var ward: M02Ward = gm.get("m02_ward") as M02Ward
	var captive_views: Array[Array] = []
	if ward != null:
		for captive: Node3D in ward._side_captives:
			captive_views.append([captive.position.x, captive.position.y, captive.position.z])
	return {
		"m02_evacuation": evacuation,
		"m02_captive_views": captive_views,
		"participant_record": gm.get("net_client").get("record"),
		"mission_rules": gm.get("net_client").get("mission").get("state", {}).get("rules", {}),
		"mission_run": gm.get("net_client").get("mission").get("state", {}).get("run", {}),
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

## Hold the trigger until the held gun's ammunition count is spent. There is
## no magazine: the whole count empties through authoritative shots.
func _empty_ammo() -> void:
	var state: Dictionary = _equipment()
	if state.is_empty() or state["selected"] == "fists":
		push_error("qa_tour: cannot drain a missing gun")
		_failed = true
		return
	Input.action_press("fire")
	var deadline: int = Time.get_ticks_msec() + 30000
	while EquipmentState.shots(_equipment(), state["selected"]) > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	# Keep the trigger down long enough to observe the dry edge as well.
	await create_timer(0.5).timeout
	Input.action_release("fire")
	if EquipmentState.shots(_equipment(), state["selected"]) != 0 or int(_equipment()["dry_fire_count"]) <= int(state["dry_fire_count"]):
		push_error("qa_tour: ammunition did not empty and produce dry feedback")
		_failed = true

func _check_equipment(expected: Dictionary) -> void:
	var state: Dictionary = _equipment()
	if state.is_empty():
		push_error("qa_tour: missing equipment")
		_failed = true
		return
	for key: String in expected:
		var actual: Variant = state.get(key)
		if key == "ammo":
			actual = EquipmentState.shots(state, state["selected"])
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

func _run_status() -> String:
	var manager: Node = _game_manager()
	if manager == null:
		return ""
	var run: Variant = (manager.get("mission_hud") as MissionHud).state.get("run")
	return str((run as Dictionary).get("status", "")) if run is Dictionary else ""

## Switch prompts through the real input path: a key the game does not bind,
## or a pull of the unbound left trigger. No pad is attached during a tour, so
## the driver reports no name and the layout is positional unless the state
## names one; a named layout is recorded in the manifest as forced.
func _use_input_device(kind: String, layout: String) -> void:
	if kind == "keyboard":
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = KEY_F12
		key.pressed = true
		Input.parse_input_event(key)
		var up: InputEventKey = key.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
	else:
		var pull: InputEventJoypadMotion = InputEventJoypadMotion.new()
		pull.axis = JOY_AXIS_TRIGGER_LEFT
		pull.axis_value = 0.8
		Input.parse_input_event(pull)
		var rest: InputEventJoypadMotion = pull.duplicate()
		rest.axis_value = 0.0
		Input.parse_input_event(rest)
	await process_frame
	await process_frame
	if kind != "keyboard" and layout in ["letters", "shapes", "generic"] and InputDevice.is_gamepad():
		InputDevice.force(InputDevice.Kind.GAMEPAD, InputDevice.look_source, layout)
	await process_frame

func _use_mission_control(expected_phase: String) -> void:
	var network: Node = _game_manager().get("net_client")
	var deadline: int = Time.get_ticks_msec() + 2000
	var available: bool = false
	while Time.get_ticks_msec() < deadline:
		var mission: Dictionary = network.get("mission")
		var prompts: Array = mission.get("state", {}).get("prompts", [])
		for prompt: Dictionary in prompts:
			available = available or str(prompt["player_id"]) == str(network.get("player_id"))
		if available:
			break
		await create_timer(0.05).timeout
	if not available:
		print("qa_tour: no use prompt before pressing at ", _local_feet())
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_F
	press.pressed = true
	Input.parse_input_event(press)
	# Released in the same frame on purpose: a sub-frame tap must still arrive once.
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	deadline = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		var mission: Dictionary = network.get("mission")
		var mission_state: Dictionary = mission.get("state", {})
		# M02 stays in_progress; its expectation names the completed objective.
		var progress: Variant = mission_state.get("m02")
		if mission_state.get("phase") == expected_phase \
			or (progress is Dictionary and expected_phase in progress.get("completed", [])):
			print("qa_tour: mission reached ", expected_phase)
			return
		await create_timer(0.05).timeout
	push_error("qa_tour: physical use did not reach %s from %s, prompts %s" % [expected_phase, _local_feet(),
		network.get("mission").get("state", {}).get("prompts", [])])
	_failed = true

func _expect_m02_ward_stage(stage: String, state_name: String) -> void:
	var manager: Node = _game_manager()
	var ward: M02Ward = manager.get("m02_ward") as M02Ward if manager != null else null
	var deadline: int = Time.get_ticks_msec() + 8000
	while ward != null and Time.get_ticks_msec() < deadline:
		var progress: Dictionary = manager.net_client.mission.get("state", {}).get("m02", {})
		var secured: bool = progress.get("ward_secured") == true
		var released: bool = "companion_released" in progress.get("completed", [])
		var passed: bool = false
		match stage:
			"secured":
				passed = secured and not released and not (ward._machine_lamp.material_override as StandardMaterial3D).emission_enabled
			"restrained":
				passed = secured and not released and ward._second_left.position.x > -0.5
			"released":
				passed = secured and released and ward._release_elapsed >= 0.0 and ward._second_left.position.x > -0.5
			"second_open":
				passed = secured and released and ward._release_elapsed >= M02Ward.SECOND_OPEN_END \
					and ward._second_left.position.x < -0.9 and ward._caption_key == "M02_LATCH_SPEECH"
			"low_water":
				passed = secured and released and ward._release_elapsed >= M02Ward.LIST_REVEAL \
					and ward._transfer_list.visible and (ward._transfer_list.get_node("Copy") as WorldSign).text.contains("LOW WATER")
		if passed:
			print("qa_tour: %s reached M02 ward stage %s" % [state_name, stage])
			return
		await create_timer(0.05).timeout
	push_error("qa_tour: %s never reached M02 ward stage %s" % [state_name, stage])
	_failed = true

func _expect_m02_side_stage(stage: String, state_name: String) -> void:
	var manager: Node = _game_manager()
	var ward: M02Ward = manager.get("m02_ward") as M02Ward if manager != null else null
	var deadline: int = Time.get_ticks_msec() + 8000
	while ward != null and Time.get_ticks_msec() < deadline:
		if ward._side_captives.size() != 2 or ward._side_left_bars.size() != 2:
			await create_timer(0.05).timeout
			continue
		var progress: Dictionary = manager.net_client.mission.get("state", {}).get("m02", {})
		var secured: bool = progress.get("side_ward_secured") == true
		var held: bool = ward._side_captives.size() == 2 and ward._side_left_bars.size() == 2 \
			and ward._side_captives[0].position == M02Ward.SIDE_CAPTIVE_FEET[0] \
			and ward._side_left_bars[0].position.x > -0.5
		var evacuation: Dictionary = progress.get("evacuation", {})
		var free: bool = ward._side_release_elapsed >= M02Ward.SIDE_RELEASE_SECONDS \
			and evacuation.get("phase") != "held" and ward._side_left_bars[0].position.x < -0.9
		if (stage == "held" and not secured and held) or (stage == "released" and secured and free):
			print("qa_tour: %s reached M02 side ward stage %s" % [state_name, stage])
			return
		await create_timer(0.05).timeout
	push_error("qa_tour: %s never reached M02 side ward stage %s" % [state_name, stage])
	_failed = true

func _expect_m02_evacuation_phase(phase: String, state_name: String) -> void:
	var manager: Node = _game_manager()
	var ward: M02Ward = manager.get("m02_ward") as M02Ward if manager != null else null
	var deadline: int = Time.get_ticks_msec() + 45000
	while ward != null and Time.get_ticks_msec() < deadline:
		var evacuation: Dictionary = manager.net_client.mission.get("state", {}).get("m02", {}).get("evacuation", {})
		if evacuation.get("phase") == phase and ward._side_captives.size() == 2:
			var feet: Array = evacuation.get("captives", [])
			var presented: bool = feet.size() == 2
			for index: int in range(mini(feet.size(), ward._side_captives.size())):
				var target: Vector3 = Vector3(float(feet[index][0]), float(feet[index][1]), float(feet[index][2]))
				presented = presented and ward._side_captives[index].position.distance_to(target) < 0.4
				if phase == "moving":
					presented = presented and target.distance_to(M02Ward.SIDE_CAPTIVE_FEET[index]) > 2.0
				elif phase == "waiting":
					var wait_feet: Vector3 = Vector3(-5.2 if index == 0 else -3.5, 0.0, 11.0)
					presented = presented and target.distance_to(wait_feet) < 0.25
			if presented and evacuation.get("evacuated") == (phase == "evacuated"):
				print("qa_tour: %s observed two server captives at M02 evacuation phase %s" % [state_name, phase])
				return
		await create_timer(0.05).timeout
	push_error("qa_tour: %s never presented two server captives at M02 evacuation phase %s" % [state_name, phase])
	_failed = true

func _expect_m02_gate_mask(expected: int, state_name: String) -> void:
	var manager: Node = _game_manager()
	var deadline: int = Time.get_ticks_msec() + 8000
	while manager != null and Time.get_ticks_msec() < deadline:
		var progress: Dictionary = manager.net_client.mission.get("state", {}).get("m02", {})
		if progress.get("gate_mask") == expected:
			print("qa_tour: %s reached M02 gate mask %d" % [state_name, expected])
			return
		await create_timer(0.05).timeout
	push_error("qa_tour: %s never reached M02 gate mask %d" % [state_name, expected])
	_failed = true

## Read the authoritative pawn and both render nodes on the same frame.
## The nameplate or callsign alone cannot prove which Latch is visible.
func _companion_observation() -> Dictionary:
	var manager: Node = _game_manager()
	if manager == null:
		return {}
	var snapshot: Dictionary = manager.get("latest_snapshot")
	for actor: Dictionary in snapshot.get("players", []):
		if not ActorState.is_companion(actor):
			continue
		var pawn: Node3D = manager.players.get(actor["id"])
		var ward: M02Ward = manager.get("m02_ward") as M02Ward
		var targets: Array = manager.camera.get("available_targets") if manager.camera != null else []
		return {"tick": int(snapshot.get("tick", -1)), "phase": str(actor["campaign"]["phase"]),
			"phase_started": int(actor["campaign"]["phase_started"]),
			"position": [float(actor["x"]), float(actor["y"]), float(actor["z"])],
			"pawn_visible": is_instance_valid(pawn) and pawn.visible,
			"ward_visible": ward != null and is_instance_valid(ward._latch) and ward._latch.visible,
			"followable": pawn in targets}
	return {}

func _expect_companion_phase(phase: String, state_name: String) -> void:
	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var observed: Dictionary = _companion_observation()
		if observed.get("phase") == phase:
			print("qa_tour: %s reached companion phase %s at tick %d" % [state_name, phase, observed["tick"]])
			return
		await create_timer(0.05).timeout
	push_error("qa_tour: %s never reached companion phase %s" % [state_name, phase])
	_failed = true

func _expect_companion_displacement(metres: float, state_name: String) -> void:
	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var observed: Dictionary = _companion_observation()
		if not observed.is_empty():
			var point: Array = observed["position"]
			var distance: float = Vector2(float(point[0]) - M02Ward.SECOND_FEET.x,
				float(point[2]) - M02Ward.SECOND_FEET.z).length()
			if distance >= metres and observed["phase"] in ["following", "firing"]:
				await _record_companion_route(true)
				print("qa_tour: %s companion moved %.2f m from the second bay at tick %d" % [state_name, distance, observed["tick"]])
				return
		await _record_companion_route()
		await create_timer(0.05).timeout
	push_error("qa_tour: %s companion did not move %.1f m from the second bay" % [state_name, metres])
	_failed = true

func _record_companion_route(force: bool = false) -> void:
	if not _companion_route_capture or _companion_route_images.size() >= 24:
		return
	var now: int = Time.get_ticks_msec()
	if not force and now - _companion_route_last_ms < 500:
		return
	await RenderingServer.frame_post_draw
	_companion_route_last_ms = Time.get_ticks_msec()
	_companion_route_samples.append(_companion_observation())
	var frame: Image = _grab()
	if frame != null:
		frame.convert(Image.FORMAT_RGBA8)
		_companion_route_images.append(frame)

func _save_companion_route_strip(state_name: String) -> String:
	if _companion_route_images.size() < 2:
		push_error("qa_tour: %s had fewer than two companion route frames" % state_name)
		_failed = true
		return ""
	var first: Dictionary = _companion_route_samples.front()
	var last: Dictionary = _companion_route_samples.back()
	if first.is_empty() or last.is_empty():
		push_error("qa_tour: %s lost the companion during route capture" % state_name)
		_failed = true
		return ""
	var start: Array = first["position"]
	var finish: Array = last["position"]
	var visual_displacement: float = Vector2(float(finish[0]) - float(start[0]),
		float(finish[2]) - float(start[2])).length()
	if visual_displacement < 4.0:
		push_error("qa_tour: %s route frames moved the server companion only %.2f m" % [state_name, visual_displacement])
		_failed = true
	for observation: Dictionary in _companion_route_samples:
		var moving: bool = str(observation.get("phase", "")) in ["following", "firing"]
		if observation.get("pawn_visible") != moving or observation.get("ward_visible") == moving \
			or observation.get("followable") == true:
			push_error("qa_tour: %s route frame showed the wrong Latch figure: %s" % [state_name, JSON.stringify(observation)])
			_failed = true
	var tile_width: int = STRIP_TILE_WIDTH
	var tile_height: int = int(round(float(tile_width) * float(_companion_route_images[0].get_height()) \
		/ float(_companion_route_images[0].get_width())))
	var sheet: Image = Image.create(tile_width * _companion_route_images.size(), tile_height,
		false, Image.FORMAT_RGBA8)
	for i: int in range(_companion_route_images.size()):
		var tile: Image = _companion_route_images[i]
		if i == 0 or i == _companion_route_images.size() - 1:
			var full_name: String = "%s_companion_route_%02d.png" % [state_name, i]
			if tile.save_png(_out_dir.path_join(full_name)) != OK:
				_failed = true
		tile.resize(tile_width, tile_height, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(i * tile_width, 0))
	var file_name: String = "%s_companion_route_strip.png" % state_name
	if sheet.save_png(_out_dir.path_join(file_name)) != OK:
		push_error("qa_tour: could not save companion route strip")
		_failed = true
	return file_name

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

func _walk_to(goal: Vector3, look_back: bool = false) -> void:
	# Keep the original movement bound. Opt-in combat uses a separate bounded
	# allowance, because the controller intentionally stops walking to fight.
	var walking_ms: int = 0
	var fighting_ms: int = 0
	var camera: Node = _spectator_camera()
	Input.action_release("jump")
	var movement_action: StringName = &"move_back" if look_back else &"move_forward"
	Input.action_press(movement_action)
	var arrived: bool = false
	var anchor: Vector2 = Vector2(_local_feet().x, _local_feet().z)
	while walking_ms < 15000 and fighting_ms < 25000:
		var step_started: int = Time.get_ticks_msec()
		await _record_companion_route()
		var feet: Vector3 = _local_feet()
		if not feet.is_finite() or (_combat_travel and _combat_probe.participant_died):
			break
		if Vector2(feet.x - goal.x, feet.z - goal.z).length() < 0.3 and absf(feet.y - goal.y) < 0.03:
			arrived = true
			break
		if _combat_travel and _combat_probe.travel(_game_manager(), anchor):
			_record_movement()
			await create_timer(0.05).timeout
			fighting_ms += Time.get_ticks_msec() - step_started
			continue
		anchor = Vector2(feet.x, feet.z)
		Input.action_press(movement_action)
		camera.set("fp_yaw", atan2(goal.z - feet.z, goal.x - feet.x) + (PI if look_back else 0.0))
		camera.set("fp_pitch", 0.0)
		_record_movement()
		await create_timer(0.05).timeout
		walking_ms += Time.get_ticks_msec() - step_started
	QaCombat.release_inputs()
	_walk_results.append({"goal": [goal.x, goal.y, goal.z], "arrived": arrived, "walking_ms": walking_ms, "fighting_ms": fighting_ms})
	await create_timer(0.15).timeout
	if not arrived:
		push_error("qa_tour: ordinary walk failed to reach %s, stopped at %s (walking %d ms, fighting %d ms)" % [goal, _local_feet(), walking_ms, fighting_ms])
		_failed = true

func _set_aim_pitch(pitch: float) -> void:
	var gm: Node = _game_manager()
	var cam: Node = _spectator_camera()
	if gm == null or cam == null or not bool(gm.get("is_human_player")):
		push_error("qa_tour: pitch capture requires a joined human")
		_failed = true
		return
	cam.set("fp_pitch", pitch)
	var deadline: int = Time.get_ticks_msec() + 5000
	while absf(_local_server_pitch(gm) - pitch) > 0.001 and Time.get_ticks_msec() < deadline:
		await process_frame
	if absf(_local_server_pitch(gm) - pitch) > 0.001:
		push_error("qa_tour: pitch did not reach the authoritative snapshot")
		_failed = true

func _pose_camera(mode: String, state: Dictionary = {}) -> void:
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
				var position: Vector3 = Vector3(0, 22, 28)
				var look: Vector3 = Vector3.ZERO
				if state.has("camera_position"):
					var p: Array = state["camera_position"]
					var l: Array = state["camera_look_at"]
					position = Vector3(float(p[0]), float(p[1]), float(p[2]))
					look = Vector3(float(l[0]), float(l[1]), float(l[2]))
				n3.global_position = position
				n3.look_at(look, Vector3.UP)
			if "follow_mode" in cam:
				cam.set("follow_mode", false)
			if "fp_mode" in cam:
				cam.set("fp_mode", false)
			if state.has("camera_position"):
				cam.set("tip_locked_transform", cam.global_transform)
				cam.set("tip_has_locked_transform", true)
				cam.set("tip_pose_lock", true)
		"follow":
			cam.set("spectator_first_person", false)
			if "follow_mode" in cam:
				cam.set("follow_mode", true)
			if "fp_mode" in cam:
				cam.set("fp_mode", false)
		"first_person":
			if _joined:
				release_camera_pose_lock(cam)
				var manager: Node = _game_manager()
				var pawn_id: String = str(manager.net_client.player_id)
				var pawn: Variant = manager.players.get(pawn_id)
				if pawn is Node3D and is_instance_valid(pawn):
					cam.call("set_fp_mode", true, pawn)
			else:
				cam.set("follow_mode", true)
				cam.set("spectator_first_person", true)
		"body":
			# A close, eye-level still of one fighter's accepted body. The
			# camera leaves follow mode and is held on the pawn every frame.
			cam.set("spectator_first_person", false)
			cam.set("follow_mode", false)
			if is_instance_valid(_body_pawn) and not process_frame.is_connected(_hold_body_camera):
				process_frame.connect(_hold_body_camera)
				_hold_body_camera()
		_:
			push_warning("qa_tour: unknown camera mode " + mode)

## Wait for a live fighter wearing `kind`, on `team` when one is named.
func _find_body(kind: String, team: String) -> void:
	_body_kind = kind
	_body_team = team
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		_body_pawn = _live_body()
		if _body_pawn != null:
			return
		await create_timer(0.1).timeout
	push_error("qa_tour: no live fighter wears body %s %s" % [kind, team])
	_failed = true

func _live_body() -> Node3D:
	var gm: Node = _game_manager()
	if gm == null:
		return null
	for pawn: Variant in (gm.get("players") as Dictionary).values():
		if is_instance_valid(pawn) and pawn.get("body_kind") == _body_kind and int(pawn.get("hp")) > 0 			and (_body_team.is_empty() or pawn.get("team") == _body_team) and not bool(pawn.get("is_local_fp")):
			return pawn
	return null

## Three metres from the fighter toward the arena centre, at chest height,
## so the nearest wall is behind the subject rather than in front of it.
func _hold_body_camera() -> void:
	var cam: Node = _spectator_camera()
	if not is_instance_valid(_body_pawn) or int(_body_pawn.get("hp")) <= 0:
		# The subject died before the shutter: hold on another who matches.
		_body_pawn = _live_body()
	if _body_pawn == null or not cam is Node3D:
		return
	var feet: Vector3 = _body_pawn.global_position - Vector3(0, CameraScript.FP_SERVER_REFERENCE_Y, 0)
	var toward: Vector3 = Vector3(-feet.x, 0, -feet.z)
	toward = toward.normalized() if toward.length() > 0.5 else Vector3.BACK
	var camera: Node3D = cam
	camera.global_position = feet + toward * 3.0 + Vector3(0, 1.3, 0)
	camera.look_at(feet + Vector3(0, 0.95, 0), Vector3.UP)
	# The pose lock keeps a frag cut or follow step from moving the camera.
	cam.set("tip_locked_transform", camera.global_transform)
	cam.set("tip_has_locked_transform", true)
	cam.set("tip_pose_lock", true)

func _release_body_camera() -> void:
	if process_frame.is_connected(_hold_body_camera):
		process_frame.disconnect(_hold_body_camera)
	var cam: Node = _spectator_camera()
	if cam != null:
		release_camera_pose_lock(cam)
	_body_pawn = null

static func release_camera_pose_lock(cam: Node) -> void:
	cam.set("tip_pose_lock", false)
	cam.set("tip_has_locked_transform", false)

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
		"renderer": RenderingServer.get_current_rendering_method(),
		"device": RenderingServer.get_video_adapter_name(),
		"width": tour.get("width", 0),
		"height": tour.get("height", 0),
		"companion_shots": _combat_probe.companion_shots.duplicate(true),
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
