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
const CAPTURE_SIZE_SETTLE_DRAWS: int = 32
const CAPTURE_SIZE_SETTLE_MSEC: int = 2000
const DIFF_EPSILON: float = 0.02
const RADIO_COMPARE_TRACK: String = "radio/lockin/01-push"

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
var _m05_ride_report: Dictionary = {}
var _grenade_strip_report: Dictionary = {}
var _fire_strip_report: Array[Dictionary] = []
var _grenade_strip_network: Node
var _grenade_strip_owner: String = ""
var _grenade_strip_follow: bool = false
var _grenade_strip_tick: int = -1
var _grenade_strip_existing: Dictionary = {}
var _grenade_strip_launches: Dictionary = {}
var _grenade_strip_explosions: Dictionary = {}
var _grenade_strip_samples: Array[Dictionary] = []
var _combat_probe: QaCombat = QaCombat.new()
var _combat_travel: bool = false
var _combat_travel_targets: Array[String] = []
var _radio_compare_on: bool = false
var _radio_comparison: Dictionary = {}
var _retiring_audio: Array[WeakRef] = []
var _audio_recorder: AudioEffectRecord = null
var _audio_master: int = -1
var _audio_effects_before: int = 0
var _audio_started_ms: int = 0
var _audio_start_state: String = ""
const MAX_LIVE_AUDIO_MS: int = 90000
var _capture_size: Vector2i = Vector2i.ZERO
var _capture_last_drawn: int = -1
var _capture_undrawn_seconds: float = 0.0
var _capture_forced_draws: int = 0
## The fighter a "body" camera holds on, and the side it had to be on.
var _body_pawn: Node3D = null
var _body_kind: String = ""
var _body_team: String = ""
var _body_frame_clear: bool = false
## Frames between the trigger and the first strip frame. The shot is resolved by
## the server, so the flash arrives a round trip later, not on the next frame.
const STRIP_LEAD_FRAMES: int = 2

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("_run")

func _finalize() -> void:
	_discard_audio()
	_combat_probe.finish()
	MouseCapture.release()

func _process(delta: float) -> bool:
	if _audio_recorder != null and Time.get_ticks_msec() - _audio_started_ms > MAX_LIVE_AUDIO_MS:
		push_error("qa_tour: live audio capture exceeded 90 seconds")
		_discard_audio()
		_failed = true
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		MouseCapture.release()
		push_error("qa_tour: automation attempted to capture the desktop pointer")
		_failed = true
	# A minimized capture can stop drawing while its owned match keeps running.
	# Reuse the non-presenting draw used by retirement and local capture tools.
	# This keeps timed strips and paused HUD measurements live, never measures FPS.
	var drawn: int = Engine.get_frames_drawn()
	_capture_undrawn_seconds = _capture_undrawn_seconds + delta if drawn == _capture_last_drawn else 0.0
	_capture_last_drawn = drawn
	if _capture_undrawn_seconds >= 0.25 and DisplayServer.get_name() != "headless" \
			and not DisplayServer.window_can_draw(root.get_window_id()):
		_capture_forced_draws += 1
		RenderingServer.force_draw(false)
		_capture_undrawn_seconds = 0.0
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
	var radio_compare_value: String = OS.get_environment("FRAGR_QA_RADIO_COMPARE")
	if not valid_radio_comparison(radio_compare_value, states):
		push_error("qa_tour: FRAGR_QA_RADIO_COMPARE must be on and the route must request radio_off")
		quit(1)
		return
	_radio_compare_on = radio_compare_value == "on"

	var current_scene: String = ""
	var audio_levels: Dictionary = {}
	_clock_ms = Time.get_ticks_msec()
	for entry in states:
		var state: Dictionary = entry
		_combat_travel = combat_travel_enabled(tour, state)
		_combat_travel_targets.assign(state.get("combat_travel_targets", []))
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
			var match_manager: Node = _game_manager()
			if match_manager != null:
				match_manager.net_client.server_error.connect(_record_network_error)
			_clock_ms = Time.get_ticks_msec()

		var due_ms: int = int(float(state.get("at_seconds", 0.0)) * 1000.0)
		var wait_s: float = float(due_ms - (Time.get_ticks_msec() - _clock_ms)) / 1000.0
		if wait_s > 0.0:
			await create_timer(wait_s).timeout
		if state.has("await_ctf"):
			if not await _await_ctf(state["await_ctf"], float(state.get("await_timeout_seconds", 120.0))):
				await _retire_scene()
				quit(1)
				return
		if state.has("await_sabotage"):
			if not await _await_sabotage(state["await_sabotage"], float(state.get("await_timeout_seconds", 120.0))):
				await _retire_scene()
				quit(1)
				return

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
		if state.has("await_alive") and _joined:
			# A Sabotage joiner after muster sits the round out; wait for the
			# next one to put the fighter on the floor.
			var alive_deadline: int = Time.get_ticks_msec() + roundi(float(state["await_alive"]) * 1000.0)
			while not _local_human_alive(_game_manager()) and Time.get_ticks_msec() < alive_deadline:
				await create_timer(0.1).timeout
			if not _local_human_alive(_game_manager()):
				push_error("qa_tour: %s never had a live joined fighter" % state_name)
				_failed = true
		if state.get("radio_off", false):
			var radio: Node = _game_manager().get("radio") if _game_manager() != null else null
			if radio == null:
				push_error("qa_tour: radio was unavailable for isolated audio capture")
				_failed = true
			elif _radio_compare_on:
				_radio_comparison = fixed_radio_track(radio, RADIO_COMPARE_TRACK)
				if _radio_comparison.is_empty():
					push_error("qa_tour: fixed radio comparison track did not start")
					_failed = true
				else:
					print("qa_tour: radio comparison ", JSON.stringify(_radio_comparison))
			elif bool(radio.get("enabled")):
				radio.call("toggle")
		if state.has("record_status"):
			var deadline: int = Time.get_ticks_msec() + 200000
			while _game_manager().net_client.record.get("status") != state["record_status"] and Time.get_ticks_msec() < deadline:
				await create_timer(0.05).timeout
			if _game_manager().net_client.record.get("status") != state["record_status"]:
				push_error("qa_tour: participant never reached requested record status")
				_failed = true
		if _joined and (state.has("weapon") or state.has("aim_pitch")):
			await _wait_live_joined_fighter(state_name)
		if state.has("weapon"):
			await _select_weapon(str(state["weapon"]))
		if state.has("aim_pitch"):
			await _set_aim_pitch(float(state["aim_pitch"]))
		if state.get("record_audio_start", false) and not _begin_audio(state_name):
			_failed = true
			await _retire_scene()
			quit(1)
			return
		_movement_samples.clear()
		_walk_results.clear()
		var ack_report: Dictionary = {}
		var moving_combat: Dictionary = {}
		var ack_deadline_usec: int = 0
		if state.has("moving_combat_seconds"):
			moving_combat = await _moving_combat_probe(float(state["moving_combat_seconds"]))
			ack_report = moving_combat.get("ack_probe", {})
			if not moving_combat.get("passed", false):
				_failed = true
		elif state.has("ack_probe_seconds"):
			if not _joined or _game_manager() == null or not _game_manager().begin_ack_probe():
				push_error("qa_tour: Ack probe requires a connected human fighter")
				quit(1)
				return
			ack_deadline_usec = Time.get_ticks_usec() + int(float(state["ack_probe_seconds"]) * 1000000.0)
		if state.get("jump_probe", false):
			await _jump_probe()
		# A detached observation state must hand the eye back before ordinary
		# walking resumes, or the next live route would send no human input.
		if state.get("camera", "") == "first_person" and _joined and not bool(_spectator_camera().get("fp_mode")):
			_pose_camera("first_person", state)
		var stop_round_state: String = str(state.get("stop_on_round_state", ""))
		for point: Array in state.get("walk_to", []):
			await _walk_to(Vector3(float(point[0]), float(point[1]), float(point[2])),
				state.get("route_look_back", false), stop_round_state)
			if _failed:
				await _retire_scene()
				quit(1)
				return
			if not _walk_results.is_empty() and bool(_walk_results.back().get("stopped_for_round", false)):
				break
		# `walk_into` is one route, or a route per Sabotage side keyed by
		# uniform, since a joiner lands on whichever side needs a fighter.
		var into: Variant = state.get("walk_into", [])
		if into is Dictionary:
			var manager: Node = _game_manager()
			into = (into as Dictionary).get(str(manager.get("_sabotage_team")) if manager != null else "", [])
		var fell: bool = false
		for point: Variant in (into as Array if into is Array else []):
			var at: Array = point if point is Array else []
			if at.size() < 3:
				continue
			if await _walk_into(Vector3(float(at[0]), float(at[1]), float(at[2]))):
				fell = true
				break
		if not fell and state.has("walk_into_wait_seconds"):
			var wait_until: int = Time.get_ticks_msec() + roundi(float(state["walk_into_wait_seconds"]) * 1000.0)
			while bool(_observed_state().get("self_alive", false)) and Time.get_ticks_msec() < wait_until:
				await create_timer(0.1).timeout
		if state.has("expect_companion_displacement"):
			await _expect_companion_displacement(float(state["expect_companion_displacement"]), state_name)
		if state.get("m05_board_tram", false):
			await _board_m05_tram()
		if state.has("m05_ride_seconds"):
			await _ride_m05_tram(float(state["m05_ride_seconds"]), float(state.get("expect_m05_ride_metres", 0.8)))
		if state.get("expect_crawler_scrabble", false):
			var manager: Node = _game_manager()
			var caption: Node = manager.hud.get("crawler_caption") if manager != null else null
			var caption_label: Label = caption.get("caption_label") as Label if is_instance_valid(caption) else null
			var required_cues: int = int(state.get("expect_crawler_cues", 1))
			var actual_cues: int = int(manager.get("crawler_scrabble_count")) if manager != null else 0
			var caption_text: String = caption_label.text if is_instance_valid(caption_label) else ""
			if manager == null or actual_cues != required_cues or \
				caption_text != tr("CAPTION_CRAWLER_SCRABBLE"):
				push_error("qa_tour: expected %d Crawler cues and live caption; observed %d and %s" % [
					required_cues, actual_cues, caption_text])
				_failed = true
			if manager != null and state.has("expect_crawler_source"):
				var source: Array = state["expect_crawler_source"]
				var expected_source: Vector3 = Vector3(float(source[0]), float(source[1]), float(source[2]))
				if (manager.get("crawler_last_position") as Vector3).distance_to(expected_source) > 0.2:
					push_error("qa_tour: Crawler scrabble came from the wrong landing")
					_failed = true
		if ack_deadline_usec > 0:
			while Time.get_ticks_usec() < ack_deadline_usec:
				await create_timer(0.1).timeout
			ack_report = _game_manager().end_ack_probe()
			if not valid_ack_capture(ack_report, float(state["ack_probe_seconds"])):
				push_error("qa_tour: Ack probe lacked a stable live human sample: " + JSON.stringify(ack_report))
				_failed = true
		var combat: Dictionary = {}
		if state.has("combat"):
			if state.get("camera", "") == "first_person":
				_pose_camera("first_person", state)
			combat = await _combat_probe.run(self, _game_manager(), state["combat"], _out_dir.path_join(state_name))
			if not combat.get("passed", false):
				_failed = true
				_write_manifest(tour)
				_write_contact_sheet()
				await _retire_scene()
				quit(1)
				return
		if state.has("look_at"):
			var target: Array = state["look_at"]
			var camera: Node3D = _spectator_camera()
			# Camera reconciliation can still trail the last combat sidestep.
			# Ordinary input must aim from the current authoritative eye.
			var origin: Vector3 = camera.global_position
			if _joined:
				var manager: Node = _game_manager()
				var me: Dictionary = QaCombat.actor_by_id(manager.latest_snapshot, str(manager.net_client.player_id))
				origin = _local_feet() + Vector3.UP * (MoveStep.DUCK_EYE_HEIGHT if me.get("ducking", false) else MoveStep.EYE_HEIGHT)
			var direction: Vector3 = Vector3(float(target[0]), float(target[1]), float(target[2])) - origin
			camera.set("fp_yaw", atan2(direction.z, direction.x))
			await _set_aim_pitch(atan2(direction.y, Vector2(direction.x, direction.z).length()))
		if state.get("empty_ammo", false):
			await _empty_ammo()
		if state.get("expect_prompt", false):
			var prompt_deadline: int = Time.get_ticks_msec() + 3000
			while _game_manager().mission_hud.prompt_text.is_empty() and Time.get_ticks_msec() < prompt_deadline:
				await create_timer(0.05).timeout
			if _game_manager().mission_hud.prompt_text.is_empty():
				push_error("qa_tour: %s expected a live use prompt" % state_name)
				_failed = true
		if state.has("interact"):
			await _use_mission_control(str(state["interact"]))
		if state.has("hold_use") and _game_manager() != null:
			# A Sabotage plant or defuse: Use stays held into the next states.
			_game_manager().set("interact_held", bool(state["hold_use"]))
		if state.get("m05_review_departure", false):
			await _set_m05_departure_review(true)
		if state.get("m05_cancel_review", false):
			await _set_m05_departure_review(false)
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
		if state.has("fixture_ctf_result"):
			# Layout fixture only. A scored match still needs separate live evidence.
			var fixture: Dictionary = state["fixture_ctf_result"]
			_find_hud().call("show_round_end", "", "Capture limit reached", 0, "", [],
				fixture.get("winning_team"), fixture.get("capture_scores"))
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
		# A held scope frames the still through the presentation-only overlay.
		var scoped_still: bool = state.get("scope", false) == true
		if scoped_still:
			Input.action_press("scope")
		_pose_camera(state.get("camera", "none"), state)
		# A detached live-combat view needs only a few settled frames. Holding
		# the human still for the menu-still delay would change the fight.
		await create_timer(float(state.get("settle_seconds",
			0.2 if state.has("expect_active_enemies") else 0.75))).timeout
		if state.has("expect_m02_machine_playing"):
			var ward: M02Ward = _game_manager().get("m02_ward") as M02Ward if _game_manager() != null else null
			var playing: bool = ward != null and is_instance_valid(ward._ward_machine_sound) and ward._ward_machine_sound.playing
			if playing != bool(state["expect_m02_machine_playing"]):
				push_error("qa_tour: %s ward machine playback did not match the live state" % state_name)
				_failed = true
		var audio_capture: Dictionary = {}
		if state.has("record_audio_seconds"):
			audio_capture = await _record_audio(float(state["record_audio_seconds"]), _results.size() + 1)
			if audio_capture.is_empty():
				_failed = true
			else:
				var comparison: String = str(state.get("expect_audio_louder_than", ""))
				if not comparison.is_empty():
					var reference_level: float = float(audio_levels.get(comparison, 0.0))
					var required_ratio: float = float(state.get("audio_level_ratio", 1.5))
					if reference_level <= 0.0 or float(audio_capture["rms"]) < reference_level * required_ratio:
						push_error("qa_tour: %s audio RMS %.6f was not %.2fx %s (%.6f)" % [state_name,
							float(audio_capture["rms"]), required_ratio, comparison, reference_level])
						_failed = true
				audio_levels[state_name] = audio_capture["rms"]
		if state.get("record_audio_stop", false):
			audio_capture = _finish_audio("%02d_live_audio.wav" % (_results.size() + 1), 0.25)
			if audio_capture.is_empty():
				_failed = true
			elif _radio_compare_on:
				if not radio_comparison_matches(_game_manager().get("radio"), _radio_comparison):
					push_error("qa_tour: radio comparison track stopped or changed during live capture")
					_failed = true
				else:
					audio_capture["radio"] = _radio_comparison.duplicate(true)
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
			_fire_strip_report.clear()
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
		if state.has("aim_pitch"):
			await _restore_static_aim_after_respawn(state)

		var measured: Dictionary = await _measure()
		if scoped_still:
			var scope_hud: Node = _find_hud()
			var scope_view: Variant = scope_hud.get("sniper_scope") if scope_hud != null else null
			if not scope_view is SniperScope or not (scope_view as SniperScope).scoped():
				push_error("qa_tour: %s expected the Sniper scope in the still" % state_name)
				_failed = true
			Input.action_release("scope")
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
		# The still is grabbed before the pixel compare. That compare resumes
		# the tree, and a capture result only lasts the round's end delay.
		var framed: Variant = measured.get("observed")
		if framed is Dictionary:
			for key: String in ["flags", "capture_scores", "round_state", "sabotage", "self_alive"]:
				if (framed as Dictionary).has(key):
					observed[key] = (framed as Dictionary)[key]
		if state.get("expect_crawler_scrabble", false) and _game_manager() != null:
			observed["crawler_cues"] = int(_game_manager().get("crawler_scrabble_count"))
			var last_crawler_source: Vector3 = _game_manager().get("crawler_last_position")
			if observed["crawler_cues"] > 0:
				observed["crawler_last_source"] = [last_crawler_source.x, last_crawler_source.y,
					last_crawler_source.z]
		if state.has("expect_active_enemies"):
			observed["active_enemy_phases"] = active_enemy_phases
		if state.has("await_ctf") and not _ctf_matches(state["await_ctf"], observed):
			push_error("qa_tour: %s lost the awaited live CTF state before capture" % state_name)
			_failed = true
		if state.has("expect_sabotage") and not _sabotage_matches(state["expect_sabotage"], observed):
			push_error("qa_tour: %s expected Sabotage %s, saw %s" % [state_name,
				str(state["expect_sabotage"]), str(observed.get("sabotage"))])
			_failed = true
		if state.has("expect_flag_statuses"):
			var actual_statuses: Array[String] = []
			var observed_flags: Variant = observed.get("flags")
			if observed_flags is Array:
				for flag: Variant in observed_flags:
					if flag is Dictionary:
						actual_statuses.append(str(flag.get("status", "")))
			if JSON.stringify(actual_statuses) != JSON.stringify(state["expect_flag_statuses"]):
				push_error("qa_tour: %s expected live flags %s, got %s" % [state_name,
					str(state["expect_flag_statuses"]), str(actual_statuses)])
				_failed = true
		if state.has("expect_carried_flag_team"):
			var carried_team: String = str(state["expect_carried_flag_team"])
			var local_id: Variant = _game_manager().net_client.player_id if _joined else null
			var self_carrying: bool = false
			var carried_flags: Variant = observed.get("flags")
			if local_id != null and carried_flags is Array:
				for flag: Variant in carried_flags:
					if flag is Dictionary and flag.get("team") == carried_team and flag.get("status") == "carried":
						self_carrying = str(flag.get("carrier", "")) == str(local_id)
			if not self_carrying:
				push_error("qa_tour: %s expected the joined fighter to carry the %s flag" % [state_name, carried_team])
				_failed = true
		if state.get("expect_return_bearing", false):
			var return_line: String = str(_game_manager().hud.get("flag_status_text"))
			var return_mark: RegEx = RegEx.new()
			return_mark.compile("HOME \\d+M (NE|NW|SE|SW|N|E|S|W)")
			if return_mark.search(return_line) == null:
				push_error("qa_tour: %s carrier has no way home in the corner: %s" % [state_name, return_line])
				_failed = true
		if state.has("expect_flag_return_ticks"):
			var timer_expectation: Dictionary = state["expect_flag_return_ticks"]
			var timer_found: bool = false
			var timer_flags: Variant = observed.get("flags")
			if timer_flags is Array:
				for flag: Variant in timer_flags:
					if flag is Dictionary and flag.get("team") == timer_expectation.get("team") and flag.get("status") == "dropped":
						var remaining: Variant = flag.get("return_ticks")
						if remaining is int or remaining is float:
							var ticks: int = int(remaining)
							timer_found = ticks >= int(timer_expectation.get("min", 1)) and ticks <= int(timer_expectation.get("max", 400))
			if not timer_found:
				push_error("qa_tour: %s has no live dropped-flag return timer in range" % state_name)
				_failed = true
		if state.has("expect_capture_scores") and observed.get("capture_scores") != state["expect_capture_scores"]:
			push_error("qa_tour: %s expected live capture scores %s, got %s" % [state_name,
				str(state["expect_capture_scores"]), str(observed.get("capture_scores"))])
			_failed = true
		if state.has("expect_round_state") and observed.get("round_state") != state["expect_round_state"]:
			push_error("qa_tour: %s expected live round state %s, got %s" % [state_name,
				str(state["expect_round_state"]), str(observed.get("round_state"))])
			_failed = true
		if _joined and _game_manager() != null:
			observed["accepted_body"] = _game_manager().net_client.accepted_body
			# A fallen Sabotage fighter has no body in the snapshot to measure.
			if _local_human_alive(_game_manager()):
				var feet: Vector3 = _local_feet()
				observed["local_feet"] = [feet.x, feet.y, feet.z]
		if is_instance_valid(_body_pawn):
			observed["body"] = _body_pawn.get("body_kind")
			observed["body_team"] = _body_pawn.get("team")
			observed["body_name"] = _body_pawn.get("player_name")
			observed["body_frame_clear"] = _body_frame_clear
		if state.get("camera", "") == "body" and (not is_instance_valid(_body_pawn) or not _body_frame_clear):
			push_error("qa_tour: no unobstructed named body in " + state_name)
			_failed = true
		observed["render_scale"] = root.scaling_3d_scale
		observed["upscaling"] = root.scaling_3d_mode
		observed["msaa"] = root.msaa_3d
		if state.has("expect_yaw"):
			var expected_yaw: float = float(state["expect_yaw"])
			if observed.get("server_yaw") == null or absf(angle_difference(float(observed["camera_yaw"]), expected_yaw)) > 0.001 or absf(angle_difference(float(observed["server_yaw"]), expected_yaw)) > 0.001:
				push_error("qa_tour: captured facing disagrees with the authored spawn for " + state_name)
				_failed = true
		if current_scene == "res://scenes/main.tscn" and (observed.get("map_id", 0) == 0 or (observed.get("fighters", 0) == 0 and not state.get("allow_empty_roster", false))):
			push_error("qa_tour: no live match for " + state_name)
			_failed = true
		if _joined and (state.has("weapon") or state.has("aim_pitch")):
			if not _local_human_alive(_game_manager()):
				push_error("qa_tour: no live joined fighter in " + state_name)
				_failed = true
			if state.has("weapon") and str(observed.get("local_weapon", "")) != str(state["weapon"]):
				push_error("qa_tour: captured weapon disagrees with the server for " + state_name)
				_failed = true
		if state.has("aim_pitch") or state.has("expect_pitch"):
			var expected_pitch: float = float(state["expect_pitch"] if state.has("expect_pitch") else state["aim_pitch"])
			var camera_pitch: float = float(observed.get("camera_pitch", 99.0))
			var server_pitch: float = _local_server_pitch(_game_manager())
			if absf(camera_pitch - expected_pitch) > 0.001 or absf(server_pitch - expected_pitch) > 0.001:
				push_error("qa_tour: captured pitch disagrees with the server for %s (expected %.3f, camera %.3f, server %.3f)" % [state_name, expected_pitch, camera_pitch, server_pitch])
				_failed = true
		var path: String = _out_dir.path_join(file_name)
		if state.has("expect_m05_review") and observed.get("m05_review") != state["expect_m05_review"]:
			push_error("qa_tour: physical M05 passenger review disagrees with " + state_name)
			_failed = true
		for key: String in ["completed", "prisoner_route_marked", "carried_recall_cars", "carried_patients", "carried_photos", "carried_released_workers", "carried_evacuated_workers"]:
			if state.has("expect_m06_" + key) and observed.get("m06", {}).get(key) != state["expect_m06_" + key]:
				push_error("qa_tour: M06 " + key + " disagrees with " + state_name)
				_failed = true
		for key: String in ["completed", "seal_open", "machine_fallen", "custody_released", "recovered_mind_secured", "transfer_evidence"]:
			if state.has("expect_m08_" + key) and observed.get("m08", {}).get(key) != state["expect_m08_" + key]:
				push_error("qa_tour: M08 " + key + " disagrees with " + state_name)
				_failed = true
		for key: String in ["completed", "crew_released", "hatch_open", "charge_falls"]:
			if state.has("expect_m09_" + key) and observed.get("m09", {}).get(key) != state["expect_m09_" + key]:
				push_error("qa_tour: M09 " + key + " disagrees with " + state_name)
				_failed = true
		if state.has("expect_m07_completed") and observed.get("m07", {}).get("completed") != state["expect_m07_completed"]:
			push_error("qa_tour: M07 completed disagrees with " + state_name)
			_failed = true
		if state.has("expect_m11_completed") and observed.get("m11", {}).get("completed") != state["expect_m11_completed"]:
			push_error("qa_tour: M11 completed disagrees with " + state_name)
			_failed = true
		for key: String in ["completed", "pump_health", "shelter_opened", "workers_released", "assessor_wreck_union_kills"]:
			if state.has("expect_m12_" + key):
				var facts: Dictionary = observed.get("m12", {})
				var actual: Variant = facts.get(key) if key == "completed" else facts.get("challenges", {}).get(key)
				if actual != state["expect_m12_" + key]:
					push_error("qa_tour: M12 " + key + " disagrees with " + state_name)
					_failed = true
		if state.has("expect_m12_aid_count") and observed.get("m12", {}).get("aid_vehicle_ids", []).size() != int(state["expect_m12_aid_count"]):
			push_error("qa_tour: M12 actual aid identity count disagrees with " + state_name)
			_failed = true
		if state.has("expect_m10_completed") and observed.get("m10", {}).get("completed") != state["expect_m10_completed"]:
			push_error("qa_tour: M10 completed disagrees with " + state_name)
			_failed = true
		if state.has("expect_m07_lamps_lit") and int(observed.get("m07_lamps_lit", -1)) != int(state["expect_m07_lamps_lit"]):
			push_error("qa_tour: M07 lamp line disagrees with " + state_name)
			_failed = true
		for key: String in ["completed", "group_released", "freight_open"]:
			if state.has("expect_m05_" + key) and observed.get("m05", {}).get(key) != state["expect_m05_" + key]:
				push_error("qa_tour: M05 " + key + " disagrees with " + state_name)
				_failed = true
		if state.has("expect_m05_tram_phase") and observed.get("m05", {}).get("tram", {}).get("phase") != state["expect_m05_tram_phase"]:
			push_error("qa_tour: M05 tram phase disagrees with " + state_name)
			_failed = true
		if state.has("expect_m05_workers_aboard") and int(observed.get("m05_workers_aboard", 0)) < int(state["expect_m05_workers_aboard"]):
			push_error("qa_tour: M05 passengers were not physically aboard in " + state_name)
			_failed = true
		if state.has("expect_notary_crashes") and int(observed.get("notary_crashes", 0)) < int(state["expect_notary_crashes"]):
			push_error("qa_tour: no observed Notary support contact for " + state_name)
			_failed = true
		if state.has("expect_m04_clinic_open") or state.has("expect_m04_patients_released") or state.has("expect_m04_completed"):
			var m04: Dictionary = observed.get("m04", {})
			if m04.is_empty() or (state.has("expect_m04_clinic_open") and m04.get("clinic_open") != state["expect_m04_clinic_open"]) \
				or (state.has("expect_m04_patients_released") and m04.get("patients_released") != state["expect_m04_patients_released"]) \
				or (state.has("expect_m04_completed") and m04.get("completed") != state["expect_m04_completed"]):
				push_error("qa_tour: M04 facts disagree with " + state_name)
				_failed = true
		if state.has("expect_m03_mast_disabled") or state.has("expect_m03_cars"):
			var m03: Dictionary = observed.get("m03", {})
			if m03.is_empty() or (state.has("expect_m03_mast_disabled") and \
				(m03.get("mast_hp") == 0) != bool(state["expect_m03_mast_disabled"])):
				push_error("qa_tour: M03 mast outcome disagrees with " + state_name)
				_failed = true
			if state.has("expect_m03_cars"):
				var actual: Array[String] = []
				for car: Dictionary in m03.get("cars", []):
					if car.get("released", false):
						actual.append(car["id"])
				if actual != state["expect_m03_cars"]:
					push_error("qa_tour: M03 car outcomes disagree with " + state_name)
					_failed = true
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
			"audio": audio_capture,
			"moving_combat": moving_combat,
			"ack_probe": ack_report,
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
	_disconnect_grenade_strip()
	if not _discard_audio():
		push_error("qa_tour: Master recording effect remained during scene retirement")
		_failed = true
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
			if audio_reference_retired(_retiring_audio[index]):
				_retiring_audio.remove_at(index)
		if not _retiring_audio.is_empty():
			await create_timer(0.01).timeout
	if not _retiring_audio.is_empty():
		push_error("qa_tour: %d audio playbacks remain after scene retirement" % _retiring_audio.size())
		_failed = true
	# Include earlier scene removals and skies transferred from a departing owner.
	if not await ClientRetirement.for_tree(self).drain():
		_failed = true

static func audio_reference_retired(reference: WeakRef) -> bool:
	# Keep the temporary strong reference out of the awaiting caller's frame.
	return reference.get_ref() == null

func _record_audio(seconds: float, state_index: int) -> Dictionary:
	if not _begin_audio("steady-state"):
		return {}
	await create_timer(seconds).timeout
	return _finish_audio("%02d_audio.wav" % state_index, seconds * 0.8)

func _begin_audio(state_name: String) -> bool:
	# Master receives Effects, Radio and Voice. The effect observes that bus
	# before its final fader, so its level is useful for relative QA only.
	if _audio_recorder != null:
		push_error("qa_tour: audio recording is already active")
		return false
	_audio_master = AudioServer.get_bus_index(&"Master")
	if _audio_master < 0:
		push_error("qa_tour: Master audio bus is missing")
		return false
	_audio_recorder = AudioEffectRecord.new()
	_audio_recorder.format = AudioStreamWAV.FORMAT_16_BITS
	_audio_effects_before = AudioServer.get_bus_effect_count(_audio_master)
	AudioServer.add_bus_effect(_audio_master, _audio_recorder)
	_audio_recorder.set_recording_active(true)
	_audio_started_ms = Time.get_ticks_msec()
	_audio_start_state = state_name
	return true

func _finish_audio(file_name: String, minimum_seconds: float) -> Dictionary:
	if _audio_recorder == null:
		push_error("qa_tour: audio recording was not active at stop")
		return {}
	# Obtain the buffer while active. Restarting or removing the effect clears
	# its capture, so copy it before stopping the mixer-side recording.
	var recording: AudioStreamWAV = _audio_recorder.get_recording()
	var start_state: String = _audio_start_state
	var elapsed_seconds: float = float(Time.get_ticks_msec() - _audio_started_ms) / 1000.0
	var removed: bool = _discard_audio()
	if not removed:
		push_error("qa_tour: Master recording effect remained on the bus")
		return {}
	if recording == null or recording.format != AudioStreamWAV.FORMAT_16_BITS:
		push_error("qa_tour: Master recording returned no 16-bit PCM")
		return {}
	var pcm: PackedByteArray = recording.data
	var channels: int = 2 if recording.stereo else 1
	var duration: float = float(pcm.size()) / float(recording.mix_rate * channels * 2)
	if pcm.size() < 2 or pcm.size() % 2 != 0 or duration < minimum_seconds:
		push_error("qa_tour: Master recording was empty or shorter than requested")
		return {}
	var sum_squares: float = 0.0
	var peak: float = 0.0
	for byte_index: int in range(0, pcm.size(), 2):
		var sample: int = int(pcm[byte_index]) | (int(pcm[byte_index + 1]) << 8)
		if sample >= 32768:
			sample -= 65536
		var level: float = absf(float(sample) / 32768.0)
		sum_squares += level * level
		peak = maxf(peak, level)
	var rms: float = sqrt(sum_squares / float(pcm.size() / 2))
	if rms <= 0.000001:
		push_error("qa_tour: Master recording is silent")
		return {}
	if recording.save_to_wav(_out_dir.path_join(file_name)) != OK:
		push_error("qa_tour: could not write " + file_name)
		return {}
	print("qa_tour: %s %.2f s RMS %.6f peak %.6f" % [file_name, duration, rms, peak])
	return {"file": file_name, "duration_seconds": duration, "elapsed_seconds": elapsed_seconds,
		"start_state": start_state, "rms": rms, "peak": peak,
		"sample_rate": recording.mix_rate, "channels": channels, "master_pre_fader": true}

func _discard_audio() -> bool:
	if _audio_recorder == null:
		return true
	_audio_recorder.set_recording_active(false)
	var removed: bool = false
	for effect_index: int in range(AudioServer.get_bus_effect_count(_audio_master) - 1, -1, -1):
		if AudioServer.get_bus_effect(_audio_master, effect_index) == _audio_recorder:
			AudioServer.remove_bus_effect(_audio_master, effect_index)
			removed = true
			break
	var count_restored: bool = AudioServer.get_bus_effect_count(_audio_master) == _audio_effects_before
	_audio_recorder = null
	_audio_master = -1
	_audio_started_ms = 0
	_audio_start_state = ""
	return removed and count_restored

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
	var live_audio_open: bool = false
	var scene_path: String = ""
	for state: Variant in states:
		if not state is Dictionary or not QaCombat.valid_waypoints(state.get("walk_to", [])) or not valid_m06_expectations(state) or not valid_m07_expectations(state) or not valid_m09_expectations(state) or not valid_m10_expectations(state) or not valid_m11_expectations(state) or not valid_m12_expectations(state):
			return false
		if state.has("combat_travel_targets"):
			var targets: Variant = state["combat_travel_targets"]
			if not targets is Array or targets.is_empty() or targets.size() > 32:
				return false
			var seen: Dictionary[String, bool] = {}
			for target: Variant in targets:
				if not target is String or target.is_empty() or target.length() > 64 or seen.has(target):
					return false
				seen[target] = true
		if state.has("scene") and not str(state["scene"]).is_empty():
			if live_audio_open and str(state["scene"]) != scene_path:
				return false
			scene_path = str(state["scene"])
		for key: String in ["record_audio_start", "record_audio_stop", "combat_travel", "grenade_follow"]:
			if state.has(key) and not state[key] is bool:
				return false
		if state.get("grenade_follow", false) and state.get("trigger") != "throw_grenade":
			return false
		var starts_audio: bool = state.get("record_audio_start", false)
		var stops_audio: bool = state.get("record_audio_stop", false)
		if starts_audio and live_audio_open or stops_audio and not (live_audio_open or starts_audio):
			return false
		if state.has("record_audio_seconds") and (starts_audio or stops_audio or live_audio_open):
			return false
		if starts_audio:
			live_audio_open = true
		if stops_audio:
			live_audio_open = false
		if state.get("camera", "") == "overview" and state.has("camera_position") and \
			not QaCombat.valid_waypoints([state.get("camera_position"), state.get("camera_look_at")]):
			return false
		if state.has("record_audio_seconds"):
			var seconds: Variant = state["record_audio_seconds"]
			if not (seconds is float or seconds is int) or not is_finite(float(seconds)) \
				or float(seconds) <= 0.0 or float(seconds) > 10.0:
				return false
		if state.has("expect_audio_louder_than"):
			var reference: Variant = state["expect_audio_louder_than"]
			var ratio: Variant = state.get("audio_level_ratio", 1.5)
			if not state.has("record_audio_seconds") or not reference is String or reference.is_empty() \
				or not (ratio is float or ratio is int) or not is_finite(float(ratio)) or float(ratio) < 1.0:
				return false
		if state.has("stop_on_round_state"):
			var stop_round: String = str(state["stop_on_round_state"])
			if stop_round != "Warmup" and stop_round != "Active" and stop_round != "Ended":
				return false
		if state.has("ack_probe_seconds"):
			var seconds: Variant = state["ack_probe_seconds"]
			if not (seconds is int or seconds is float) or not is_finite(float(seconds)) or \
				float(seconds) < 1.0 or float(seconds) > 120.0 or state.get("join") != "human":
				return false
		if state.has("moving_combat_seconds"):
			var combat_seconds: Variant = state["moving_combat_seconds"]
			if state.has("ack_probe_seconds") or not (combat_seconds is int or combat_seconds is float) or \
				not is_finite(float(combat_seconds)) or float(combat_seconds) < 5.0 or \
				float(combat_seconds) > 120.0 or state.get("join") != "human":
				return false
	return not live_audio_open

static func valid_m12_expectations(state: Dictionary) -> bool:
	if state.has("expect_m12_completed"):
		var completed: Variant = state["expect_m12_completed"]
		var order: Array[String] = M12MissionState.OBJECTIVES.duplicate()
		order.append(M12MissionState.DEPARTURE)
		if not completed is Array or completed.size() > order.size():
			return false
		for index: int in range(completed.size()):
			if completed[index] != order[index]:
				return false
	for key: String in ["shelter_opened", "workers_released"]:
		if state.has("expect_m12_" + key) and not state["expect_m12_" + key] is bool:
			return false
	if state.has("expect_m12_pump_health"):
		var pumps: Variant = state["expect_m12_pump_health"]
		if not pumps is Array or pumps.size() != 2:
			return false
		for hp: Variant in pumps:
			if not EquipmentState.integer(hp,100):
				return false
	if state.has("expect_m12_assessor_wreck_union_kills") and not EquipmentState.integer(state["expect_m12_assessor_wreck_union_kills"],3):
		return false
	return not state.has("expect_m12_aid_count") or (EquipmentState.integer(state["expect_m12_aid_count"],2) and int(state["expect_m12_aid_count"]) != 1)

static func valid_m11_expectations(state: Dictionary) -> bool:
	if not state.has("expect_m11_completed"):
		return true
	var completed: Variant = state["expect_m11_completed"]
	var order: Array[String] = M11MissionState.OBJECTIVES.duplicate()
	order.append(M11MissionState.DEPARTURE)
	if not completed is Array or completed.size() > order.size():
		return false
	for index: int in range(completed.size()):
		if completed[index] != order[index]:
			return false
	return true

static func valid_m10_expectations(state: Dictionary) -> bool:
	if not state.has("expect_m10_completed"):
		return true
	var completed: Variant = state["expect_m10_completed"]
	var order: Array[String] = M10MissionState.OBJECTIVES.duplicate()
	order.append(M10MissionState.DEPARTURE)
	if not completed is Array or completed.size() > order.size():
		return false
	for index: int in range(completed.size()):
		if completed[index] != order[index]:
			return false
	return true

static func valid_m09_expectations(state: Dictionary) -> bool:
	for flag: String in ["crew_released", "hatch_open"]:
		if state.has("expect_m09_" + flag) and not state["expect_m09_" + flag] is bool:
			return false
	if state.has("expect_m09_charge_falls") and not EquipmentState.integer(state["expect_m09_charge_falls"], 7):
		return false
	if state.has("expect_m09_completed"):
		var completed: Variant = state["expect_m09_completed"]
		var order: Array[String] = M09MissionState.OBJECTIVES.duplicate()
		order.append("party_departed")
		if not completed is Array or completed.size() > order.size():
			return false
		for index: int in range(completed.size()):
			if completed[index] != order[index]:
				return false
	return true

static func valid_m06_expectations(state: Dictionary) -> bool:
	for flag: String in ["seal_open", "machine_fallen", "custody_released", "recovered_mind_secured", "transfer_evidence"]:
		if state.has("expect_m08_" + flag) and not state["expect_m08_" + flag] is bool:
			return false
	if state.has("expect_m08_completed"):
		var done: Variant = state["expect_m08_completed"]
		var chain: Array[String] = M08MissionState.OBJECTIVES.duplicate()
		chain.append(M08MissionState.DEPARTURE)
		if not done is Array or done.size() > chain.size():
			return false
		for index: int in range(done.size()):
			if done[index] != chain[index]:
				return false
	if state.has("expect_m06_prisoner_route_marked") and not state["expect_m06_prisoner_route_marked"] is bool:
		return false
	if state.has("expect_m06_completed"):
		var completed: Variant = state["expect_m06_completed"]
		var order: Array[String] = M06MissionState.OBJECTIVES.duplicate()
		order.append(M06MissionState.DEPARTURE)
		if not completed is Array or completed.size() > order.size():
			return false
		for index: int in range(completed.size()):
			if completed[index] != order[index]:
				return false
	for key: String in ["carried_recall_cars", "carried_patients", "carried_released_workers", "carried_evacuated_workers"]:
		if state.has("expect_m06_" + key) and not M06MissionState._ids(state["expect_m06_" + key], 4):
			return false
	return not state.has("expect_m06_carried_photos") or EquipmentState.integer(state["expect_m06_carried_photos"], 1000000)

static func valid_m07_expectations(state: Dictionary) -> bool:
	if state.has("expect_m07_lamps_lit") and not EquipmentState.integer(state["expect_m07_lamps_lit"], 64):
		return false
	if not state.has("expect_m07_completed"):
		return true
	var completed: Variant = state["expect_m07_completed"]
	var order: Array[String] = M07MissionState.OBJECTIVES.duplicate()
	order.append(M07MissionState.DEPARTURE)
	if not completed is Array or completed.size() > order.size():
		return false
	for index: int in range(completed.size()):
		if completed[index] != order[index]:
			return false
	return true

static func valid_radio_comparison(value: String, states: Variant) -> bool:
	if value.is_empty():
		return true
	if value != "on" or not states is Array:
		return false
	for state: Variant in states:
		if state is Dictionary and state.get("radio_off") == true:
			return true
	return false

## Narrow the QA copy of the current catalog station to one committed track.
## Radio still owns loading, bus routing, volume and playback retirement.
static func fixed_radio_track(radio: Node, track_name: String) -> Dictionary:
	if radio == null or not radio.has_method("play_random"):
		return {}
	var stations: Array = radio.get("stations")
	if stations.is_empty() or not stations[0] is Dictionary or stations[0].get("id") != "lockin":
		return {}
	var station: Dictionary = stations[0].duplicate(true)
	for raw_track: Variant in station.get("tracks", []):
		if raw_track is Dictionary and raw_track.get("name") == track_name:
			station["tracks"] = [raw_track]
			stations[0] = station
			radio.set("stations", stations)
			radio.set("station_index", 0)
			if not bool(radio.get("enabled")):
				radio.call("toggle")
			else:
				radio.call("play_random")
			var player: AudioStreamPlayer = radio.get("player") as AudioStreamPlayer
			var path: String = str(raw_track.get("path", ""))
			if player == null or not player.playing or player.stream == null \
					or player.stream.resource_path != path or str(radio.get("current_title")) != str(raw_track.get("title", "")):
				return {}
			return {"station": str(station["id"]), "track": track_name,
				"title": str(raw_track["title"]), "path": path}
	return {}

static func radio_comparison_matches(radio: Node, expected: Dictionary) -> bool:
	if radio == null or expected.is_empty() or not bool(radio.get("enabled")):
		return false
	var player: AudioStreamPlayer = radio.get("player") as AudioStreamPlayer
	return player != null and player.playing and player.stream != null \
		and player.stream.resource_path == str(expected.get("path", "")) \
		and str(radio.get("current_title")) == str(expected.get("title", ""))

static func active_named_enemies(snapshot: Dictionary, names: Array) -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for actor: Dictionary in snapshot.get("players", []):
		if actor.get("name", "") in names and int(actor.get("hp", 0)) > 0 and \
			ActorState.is_union(actor):
			found[str(actor["name"])] = str(actor["campaign"]["phase"])
	return found

static func valid_ack_capture(report: Dictionary, seconds: float) -> bool:
	if report.get("interrupted", true) or int(report.get("failed_sends", -1)) != 0 or \
		int(report.get("invalid_acks", -1)) != 0 or int(report.get("invalid_snapshots", -1)) != 0 or \
		float(report.get("duration_seconds", 0.0)) < seconds - 0.05:
		return false
	for key: String in ["first_matched_ack_ms", "last_matched_ack_ms", "first_snapshot_ms", "last_snapshot_ms"]:
		if not report.get(key) is int:
			return false
	var window_ms: int = int(seconds * 1000.0)
	return int(report.get("sent", 0)) >= int(seconds * 30.0) and \
		int(report.get("matched_acks", 0)) >= int(seconds * 15.0) and \
		int(report.get("snapshots", 0)) >= int(seconds * 15.0) and \
		int(report["first_matched_ack_ms"]) <= 1000 and \
		int(report["first_snapshot_ms"]) <= 1000 and \
		int(report["last_matched_ack_ms"]) >= window_ms - 1000 and \
		int(report["last_snapshot_ms"]) >= window_ms - 1000 and \
		int(report.get("max_matched_ack_gap_ms", 100000)) <= 250 and \
		int(report.get("max_snapshot_gap_ms", 100000)) <= 250

static func valid_moving_combat_capture(report: Dictionary, seconds: float) -> bool:
	return str(report.get("interruption", "invalid")) == "" and \
		valid_ack_capture(report.get("ack_probe", {}), seconds) and \
		float(report.get("server_snapshot_distance_m", 0.0)) >= 5.0 and \
		int(report.get("server_shots", 0)) >= 2 and int(report.get("shots_while_moving", 0)) >= 1 and \
		int(report.get("snapshots_with_live_opponents", 0)) >= 10 and \
		int(report.get("snapshots_observed", 0)) >= int(seconds * 15.0) and \
		int(report.get("correction_m", {}).get("samples", 0)) >= int(seconds * 10.0) and \
		bool(report.get("prediction_active_at_end", false))

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
		if key not in ["quality", "upscaling", "resolution_height", "pixel_scale", "show_fps"] or not (options[key] is int or options[key] is float) or not is_finite(float(options[key])) or float(options[key]) != floorf(float(options[key])):
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
	var frame_counter: PerformanceOverlay = manager.get_node_or_null("PerformanceOverlay") as PerformanceOverlay
	if frame_counter != null:
		frame_counter.apply_preferences()

## Restore capture dimensions before an acknowledged shot or a frozen still.
## Window mode and focus belong to the desktop. A minimized window stays so.
func _ensure_capture_window_size(context: String) -> bool:
	# Canvas stretching can give Texture2D metadata a logical size. The raw
	# rendered image owns capture dimensions, as it does in the final PNG gate.
	var captured: Image = _grab()
	var image_size: Vector2i = captured.get_size() if captured != null else Vector2i.ZERO
	if root.size == _capture_size and image_size == _capture_size:
		return true
	var original_size: Vector2i = root.size
	var started: int = Time.get_ticks_msec()
	var draws: Array[int] = [0]
	var count_draw: Callable = func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	var last_checked_draw: int = 0
	var stable_draws: int = 0
	var process_frames: int = 0
	while Time.get_ticks_msec() - started < CAPTURE_SIZE_SETTLE_MSEC \
			and draws[0] < CAPTURE_SIZE_SETTLE_DRAWS:
		if root.size != _capture_size:
			stable_draws = 0
			root.size = _capture_size
		if draws[0] != last_checked_draw:
			last_checked_draw = draws[0]
			captured = _grab()
			image_size = captured.get_size() if captured != null else Vector2i.ZERO
			stable_draws = stable_draws + 1 if root.size == _capture_size and image_size == _capture_size else 0
			if stable_draws >= 2:
				RenderingServer.frame_post_draw.disconnect(count_draw)
				print("qa_tour: restored capture size for %s from %s after %d draws, %d process frames, %d ms (mode %d)" % [
					context, original_size, draws[0], process_frames, Time.get_ticks_msec() - started, root.mode])
				return true
		process_frames += 1
		await process_frame
	RenderingServer.frame_post_draw.disconnect(count_draw)
	push_error("qa_tour: capture size did not settle for %s within %d ms/%d draws: expected %s, window %s, raw image %s, mode %d (observed %d draws, %d process frames, %d ms)" % [
		context, CAPTURE_SIZE_SETTLE_MSEC, CAPTURE_SIZE_SETTLE_DRAWS, _capture_size, root.size,
		image_size, root.mode, draws[0], process_frames, Time.get_ticks_msec() - started])
	_failed = true
	return false

## Frame pacing for a held view: wall time between drawn frames plus the
## renderer's own CPU and GPU measurements for the root viewport. The capture
## settings leave VSync off and the frame cap unlimited, so the wall time is
## the cost of the frame rather than the display's refresh interval.
func _sample_frames(count: int) -> Dictionary:
	if count < 10 or count > 2000:
		push_error("qa_tour: frame_sample needs 10 to 2000 frames")
		_failed = true
		return {}
	if not await _ensure_capture_window_size("frame sample"):
		return {}
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
	if not valid_combat_travel(parsed):
		push_error("qa_tour: manifest combat_travel must be a boolean")
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
	if not await _ensure_capture_window_size("still"):
		return {}
	var out: Dictionary = {"hud_coverage": 0.0, "world_blank": false}
	# Freeze first. Without this the two frames are a fight two frames apart,
	# and every bot that moved between them counts as HUD.
	paused = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var with_hud: Image = _grab()
	out["shot"] = with_hud
	out["observed"] = _observed_state()
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
	if not await _ensure_capture_window_size("strip " + file_name):
		return
	var trigger: String = state.get("trigger", "")
	_grenade_strip_report = {}
	_fire_strip_report.clear()
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
		await _await_fire_strip(state, probe)
		if state.get("single_shot", false):
			Input.action_release("fire")
	if trigger == "place_mine":
		# The ordinary default key; the strip then records stick, arming and blink.
		var place: InputEventKey = InputEventKey.new()
		place.physical_keycode = KEY_B
		place.pressed = true
		Input.parse_input_event(place)
		var lift: InputEventKey = place.duplicate()
		lift.pressed = false
		Input.parse_input_event(lift)
	if trigger == "throw_grenade":
		_begin_grenade_strip(state.get("grenade_follow", false))
		var press: InputEventKey = InputEventKey.new()
		press.physical_keycode = KEY_G
		press.pressed = true
		Input.parse_input_event(press)
		var release: InputEventKey = press.duplicate()
		release.pressed = false
		Input.parse_input_event(release)
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
			if img.get_size() != _capture_size:
				push_error("qa_tour: capture size changed during strip %s frame %d: expected %s, got %s" % [
					file_name, i, _capture_size, img.get_size()])
				_failed = true
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
	if trigger == "throw_grenade":
		_finish_grenade_strip()
	if probe_name != "" and _probe_frames == 0:
		push_error("qa_tour: shot produced no visible " + probe_name + ": " + JSON.stringify(_fire_strip_report))
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
			var presenting: bool = phase in ["releasing", "following", "firing"]
			if observation.is_empty() or observation.get("pawn_visible") != presenting \
				or observation.get("ward_visible") == presenting or observation.get("followable") == true:
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

## Framing can outlive the selected pawn. Reestablish the actual live input
## premise at the trigger boundary, and permit one respawn if a bot kills it
## before a visible effect arrives. An alive pawn without an effect still fails.
func _await_fire_strip(state: Dictionary, probe: Node) -> void:
	var manager: Node = _game_manager()
	for attempt: int in range(2):
		Input.action_release("fire")
		if not await _wait_live_joined_fighter(str(state.get("name", "fire strip"))):
			return
		if state.has("weapon"):
			await _select_weapon(str(state["weapon"]))
		if state.has("aim_pitch"):
			await _set_aim_pitch(float(state["aim_pitch"]))
		var receipt: Dictionary = {"before": _fire_strip_status(), "respawn_retry": attempt}
		_fire_strip_report.append(receipt)
		var empty_loadout: Dictionary = _equipment().duplicate(true)
		if QaCombat.reload_needed(empty_loadout):
			# Fire strips use the same finite human magazines as ordinary play.
			# Request one normal reload and wait for the authoritative reply.
			receipt["reload_before"] = empty_loadout
			var reload_started: int = Time.get_ticks_msec()
			var press: InputEventAction = InputEventAction.new()
			press.action = "reload"
			press.pressed = true
			Input.parse_input_event(press)
			var release: InputEventAction = press.duplicate()
			release.pressed = false
			Input.parse_input_event(release)
			var reload_deadline: int = reload_started + 2500
			while EquipmentState.shots(_equipment(), str(empty_loadout["selected"])) == 0 and Time.get_ticks_msec() < reload_deadline:
				await process_frame
			receipt["reload_after"] = _equipment().duplicate(true)
			receipt["reload_elapsed_ms"] = Time.get_ticks_msec() - reload_started
			if EquipmentState.shots(_equipment(), str(empty_loadout["selected"])) <= 0:
				push_error("qa_tour: ordinary reload did not produce loaded rounds within 2500 ms")
				_failed = true
				return
		if not _local_human_alive(manager):
			receipt["interrupted_by_death"] = true
			continue
		Input.action_press("fire")
		# The named effect must really appear. The timeout and the strip's
		# visible-frame assertion are unchanged by respawn handling.
		var deadline: int = Time.get_ticks_msec() + 2500
		while probe != null and not _probe_active(probe, state) and Time.get_ticks_msec() < deadline:
			if not _local_human_alive(manager):
				break
			await RenderingServer.frame_post_draw
		receipt["after"] = _fire_strip_status()
		receipt["effect_seen"] = probe != null and _probe_active(probe, state)
		if probe == null or receipt["effect_seen"] or _local_human_alive(manager):
			return
		receipt["interrupted_by_death"] = true
		Input.action_release("fire")
	Input.action_release("fire")

func _fire_strip_status() -> Dictionary:
	var manager: Node = _game_manager()
	var equipment: Dictionary = _equipment()
	var weapon: String = str(manager.call("_local_weapon_name"))
	return {"tick": manager.latest_snapshot.get("tick", -1),
		"alive": _local_human_alive(manager), "weapon": weapon,
		"pitch": _local_server_pitch(manager), "loaded": EquipmentState.shots(equipment, weapon),
		"blocked": manager.controls_blocked(), "fire_sent": manager.action_state.get("fire", false)}

func _record_network_error(message: String) -> void:
	push_error("qa_tour: network refused live state: " + message)
	_failed = true

func _probe_active(probe: Node, state: Dictionary) -> bool:
	if probe is TextureRect and probe.name == "FpWeapon":
		# The held Shiv is always drawn; only its thrust is the effect.
		var hud: Node = _find_hud()
		if str(hud.get("current_fp_weapon")) == "Shiv":
			return probe.visible and float(hud.get("fp_stab_timer")) > 0.0
	if probe is TextureRect and probe.name == "FpMuzzle":
		# A gun with a drawn fire frame carries its own flash; the generic star
		# appears only for a gun without one.
		var hud_node: Node = _find_hud()
		var weapon_name: String = str(hud_node.get("current_fp_weapon"))
		var held: TextureRect = hud_node.get_node_or_null("FpWeapon")
		if WeaponArt.FIRE.has(weapon_name) and held != null:
			return held.visible and held.texture == WeaponArt.FIRE[weapon_name]
	if probe is MeleeView:
		return probe.visible and probe.remaining > 0.0
	if probe is EquipmentHud:
		return probe.visible and probe.dry_seconds > 0.0
	if probe is ShotEffects:
		var network: Node = _game_manager().get("net_client")
		for effect: ShotEffects.Effect in probe._effects:
			if effect.shooter == str(network.get("player_id")) \
				and (not state.has("weapon") or effect.weapon == str(state["weapon"]).to_lower()) \
				and (not state.has("impact_kind") or effect.kind == str(state["impact_kind"])):
				return true
		return false
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
	var report: Dictionary = {
		"fire_strip": _fire_strip_report.duplicate(true),
		"grenade_strip": _grenade_strip_report.duplicate(true),
		"m05_review": is_instance_valid(gm.get("departure_review")),
		"m05_ride": _m05_ride_report.duplicate(true),
		"m05": gm.get("net_client").get("mission").get("state", {}).get("m05", {}),
		"m06": gm.get("net_client").get("mission").get("state", {}).get("m06", {}),
		"m08": gm.get("net_client").get("mission").get("state", {}).get("m08", {}),
		"m09": gm.get("net_client").get("mission").get("state", {}).get("m09", {}),
		"m10": gm.get("net_client").get("mission").get("state", {}).get("m10", {}),
		"m11": gm.get("net_client").get("mission").get("state", {}).get("m11", {}),
		"m12": gm.get("net_client").get("mission").get("state", {}).get("m12", {}),
		"m07": gm.get("net_client").get("mission").get("state", {}).get("m07", {}),
		"m07_lamps_lit": gm.get("m07_town").lamps_lit_count if gm.get("m07_town") != null else -1,
		"m05_workers_aboard": MissionHud.workers_aboard(gm.get("net_client").get("mission").get("state", {}), gm.get("net_client").get("mission_geometry").get("m05", {}).get("boarding", {})),
		"m04": gm.get("net_client").get("mission").get("state", {}).get("m04", {}),
		"notary_crashes": gm.get("notary_audio").crash_count if gm.get("notary_audio") != null else 0,
		"m03": gm.get("net_client").get("mission").get("state", {}).get("m03", {}),
		"m02_evacuation": evacuation,
		"m02_captive_views": captive_views,
		"participant_record": gm.get("net_client").get("record"),
		"mission_rules": gm.get("net_client").get("mission").get("state", {}).get("rules", {}),
		"mission_run": gm.get("net_client").get("mission").get("state", {}).get("run", {}),
		"map_id": snapshot.get("map_id", 0),
		"flags": snapshot.get("flags"),
		"capture_scores": snapshot.get("capture_scores"),
		"sabotage": snapshot.get("sabotage"),
		"self_alive": _self_alive(gm, snapshot),
		"capture_limit": snapshot.get("capture_limit"),
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
		"jammer_launches": gm.jammer_audio.launch_count if is_instance_valid(gm.jammer_audio) else 0,
	}
	if bool(gm.get("is_human_player")):
		var predictor: LocalPrediction = gm.get("local_prediction")
		var pawn: Node = gm.get("players").get(gm.get("local_fp_pawn_id"))
		report["local_prediction"] = {
			"active": predictor.active(),
			"fallback": predictor.fallback_reason,
			"fallback_count": predictor.fallback_count,
			"fallback_reasons": predictor.fallback_reasons.duplicate(),
			"last_fallback": predictor.last_fallback_reason,
			"corrections": predictor.correction_count,
			"max_correction_m": snappedf(predictor.correction_max, 0.0001),
			"p50_correction_m": snappedf(predictor.correction_percentile(0.50), 0.0001),
			"p95_correction_m": snappedf(predictor.correction_percentile(0.95), 0.0001),
			"p99_correction_m": snappedf(predictor.correction_percentile(0.99), 0.0001),
			"pending_ticks": predictor.steps.size(),
			"camera_eye_gap_m": snappedf(cam.global_position.distance_to(
				pawn.global_position + Vector3(0.0, MoveStep.EYE_HEIGHT - LocalPrediction.FLOOR_OFFSET, 0.0)), 0.0001)
				if is_instance_valid(pawn) else null,
		}
	return report

func _equipment() -> Dictionary:
	return _game_manager().get("net_client").get("equipment")

## Hold the trigger until the shown count reaches zero. When the loadout has
## magazines, that count is the magazine. The reserve stays in the bag.
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
		if key == "pool_rounds":
			if not _pool_rounds_match(state, expected[key]):
				push_error("qa_tour: carried ammunition does not match %s; observed %s" % [expected[key], state.get("ammo", [])])
				_failed = true
			continue
		var actual: Variant = state.get(key)
		if key == "ammo":
			actual = EquipmentState.shots(state, state["selected"])
		if actual != expected[key]:
			push_error("qa_tour: expected %s %s, observed %s" % [key, expected[key], actual])
			_failed = true

static func _pool_rounds_match(state: Dictionary, expected: Variant) -> bool:
	# The carried pool includes loaded rounds; shots() reads the ready magazine.
	if not expected is Dictionary or expected.is_empty():
		return false
	for pool: Variant in expected:
		if not pool is String or not EquipmentState.CAPACITIES.has(pool) \
				or not EquipmentState.integer(expected[pool], EquipmentState.CAPACITIES[pool]):
			return false
		if EquipmentState.ammo(state, pool) != int(expected[pool]):
			return false
	return true

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

func _local_human_alive(gm: Node) -> bool:
	var network: Node = gm.get("net_client")
	for player: Dictionary in gm.get("latest_snapshot").get("players", []):
		if str(player.get("id", "")) == str(network.get("player_id")):
			return int(player.get("hp", 0)) > 0
	return false

func _wait_live_joined_fighter(state_name: String) -> bool:
	var gm: Node = _game_manager()
	if gm == null:
		push_error("qa_tour: missing match for " + state_name)
		_failed = true
		return false
	var deadline: int = Time.get_ticks_msec() + 10000
	while not _local_human_alive(gm) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _local_human_alive(gm):
		push_error("qa_tour: joined fighter did not respawn for " + state_name)
		_failed = true
		return false
	return true

func _restore_static_aim_after_respawn(state: Dictionary) -> void:
	var gm: Node = _game_manager()
	if gm == null or not _joined or _local_human_alive(gm):
		return
	if not await _wait_live_joined_fighter(str(state.get("name", "static aim"))):
		return
	if state.has("weapon"):
		await _select_weapon(str(state["weapon"]))
	await _set_aim_pitch(float(state["aim_pitch"]))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

func _snapshot_round_state() -> String:
	var gm: Node = _game_manager()
	if gm == null:
		return ""
	return str(gm.get("latest_snapshot").get("round_state", ""))

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

static func combat_travel_enabled(tour: Dictionary, state: Dictionary) -> bool:
	# A stage override is scoped to that stage. Targets are reset with it.
	var selected: Variant = state.get("combat_travel", tour.get("combat_travel", false))
	if selected is bool:
		return selected
	return false

static func valid_combat_travel(tour: Dictionary) -> bool:
	return not tour.has("combat_travel") or tour["combat_travel"] is bool

func _begin_grenade_strip(follow_projectile: bool = false) -> void:
	_disconnect_grenade_strip()
	_grenade_strip_existing.clear()
	_grenade_strip_launches.clear()
	_grenade_strip_explosions.clear()
	_grenade_strip_samples.clear()
	var manager: Node = _game_manager()
	_grenade_strip_network = manager.net_client
	_grenade_strip_owner = str(_grenade_strip_network.player_id)
	_grenade_strip_follow = follow_projectile
	_grenade_strip_tick = int(manager.latest_snapshot.get("tick", -1))
	for grenade: Dictionary in manager.latest_snapshot.get("grenades", []):
		if grenade["owner_id"] == _grenade_strip_owner:
			_grenade_strip_existing[int(grenade["id"])] = true
	_grenade_strip_report = {"stock_before": int(_equipment().get("grenades", 0)), "passed": false, "camera_follows_confirmed_projectile": follow_projectile}
	_grenade_strip_network.snapshot_received.connect(_collect_grenade_strip)

func _collect_grenade_strip(snapshot: Dictionary) -> void:
	if int(snapshot["tick"]) <= _grenade_strip_tick:
		return
	_grenade_strip_tick = int(snapshot["tick"])
	var live: Array[Dictionary] = []
	var resolved: Array[Dictionary] = []
	for grenade: Dictionary in snapshot.get("grenades", []):
		var serial: int = int(grenade["id"])
		if grenade["owner_id"] != _grenade_strip_owner or _grenade_strip_existing.has(serial):
			continue
		if not _grenade_strip_launches.has(serial) and _grenade_strip_launches.size() < 64:
			_grenade_strip_launches[serial] = grenade.duplicate(true)
		live.append(grenade.duplicate(true))
		if _grenade_strip_follow and _grenade_strip_launches.size() == 1 \
			and fresh_grenade_capture(_grenade_strip_owner, _grenade_strip_existing, _grenade_strip_launches, grenade):
			_follow_grenade_strip(GrenadeFacts.vector(grenade["position"]))
	for explosion: Dictionary in snapshot.get("explosions", []):
		var serial: int = int(explosion["id"])
		if explosion["owner_id"] != _grenade_strip_owner or _grenade_strip_existing.has(serial):
			continue
		if _grenade_strip_explosions.size() < 64:
			_grenade_strip_explosions[serial] = explosion.duplicate(true)
		resolved.append(explosion.duplicate(true))
		if _grenade_strip_follow and _grenade_strip_launches.size() == 1 \
			and fresh_grenade_capture(_grenade_strip_owner, _grenade_strip_existing, _grenade_strip_launches, explosion):
			_follow_grenade_strip(GrenadeFacts.vector(explosion["position"]))
	if _grenade_strip_samples.size() < 128 and (not live.is_empty() or not resolved.is_empty()):
		_grenade_strip_samples.append({"tick": snapshot["tick"], "grenades": live, "explosions": resolved})

func _disconnect_grenade_strip() -> void:
	if is_instance_valid(_grenade_strip_network) and _grenade_strip_network.snapshot_received.is_connected(_collect_grenade_strip):
		_grenade_strip_network.snapshot_received.disconnect(_collect_grenade_strip)
	_grenade_strip_network = null
	_grenade_strip_follow = false

static func fresh_grenade_capture(owner: String, excluded: Dictionary, launched: Dictionary, fact: Dictionary) -> bool:
	if not EquipmentState.integer(fact.get("id"), 4294967295) or int(fact["id"]) < 1:
		return false
	return fact.get("owner_id") == owner and not excluded.has(int(fact["id"])) \
		and launched.has(int(fact["id"])) and GrenadeFacts.point(fact.get("position"))

func _follow_grenade_strip(position: Vector3) -> void:
	var manager: Node = _game_manager()
	if manager == null or not _local_human_alive(manager) or str(manager.net_client.player_id) != _grenade_strip_owner:
		return
	var eye: Node3D = _spectator_camera()
	if eye == null or not eye.get("fp_mode"):
		return
	var direction: Vector3 = position - eye.global_position
	if not direction.is_finite() or direction.length() < 0.7:
		return
	eye.set("fp_yaw", atan2(direction.z, direction.x))
	eye.set("fp_pitch", clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT))

func _finish_grenade_strip() -> void:
	_disconnect_grenade_strip()
	_grenade_strip_report["stock_after"] = int(_equipment().get("grenades", 0))
	_grenade_strip_report["launches"] = _grenade_strip_launches.values().duplicate(true)
	_grenade_strip_report["explosions"] = _grenade_strip_explosions.values().duplicate(true)
	_grenade_strip_report["samples"] = _grenade_strip_samples.duplicate(true)
	var passed: bool = int(_grenade_strip_report["stock_before"]) > 0 \
		and int(_grenade_strip_report["stock_after"]) == int(_grenade_strip_report["stock_before"]) - 1 \
		and _grenade_strip_launches.size() == 1 and _grenade_strip_explosions.size() == 1
	if passed:
		passed = _grenade_strip_explosions.has(_grenade_strip_launches.keys()[0])
	_grenade_strip_report["passed"] = passed
	if not passed:
		push_error("qa_tour: grenade strip lacked one real stock decrement, launch and matching resolved explosion: " + JSON.stringify(_grenade_strip_report))
		_failed = true
	else:
		print("qa_tour: real grenade stock decrement, launch and matching explosion serial ", _grenade_strip_launches.keys()[0])

func _set_m05_departure_review(open_review: bool) -> void:
	var manager: Node = _game_manager()
	var before: Dictionary = manager.net_client.mission.get("state", {}).duplicate(true)
	if before.get("id") != MissionState.M05_ID or before.get("phase") != "in_progress" \
		or is_instance_valid(manager.get("departure_review")) == open_review:
		push_error("qa_tour: M05 review requires the matching live mission and modal state")
		_failed = true
		return
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_F if open_review else KEY_ESCAPE
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	await create_timer(0.2).timeout
	var after: Dictionary = manager.net_client.mission.get("state", {})
	if is_instance_valid(manager.get("departure_review")) != open_review \
		or manager.pending_interact or after.get("phase") != "in_progress" \
		or after.get("m05", {}).get("completed") != before.get("m05", {}).get("completed"):
		push_error("qa_tour: physical passenger review changed authoritative departure or failed its release barrier")
		_failed = true
		return
	print("qa_tour: physical passenger review ", "opened" if open_review else "cancelled", "; mission remains in_progress and no Use queued")

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
	await process_frame
	if is_instance_valid(_game_manager().get("departure_review")):
		# The first physical Use opens the passenger preview. A separate fresh
		# physical press confirms through the same Action channel.
		await create_timer(0.15).timeout
		Input.parse_input_event(press)
		Input.parse_input_event(release)
	deadline = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		var mission: Dictionary = network.get("mission")
		var mission_state: Dictionary = mission.get("state", {})
		# M02 stays in_progress; its expectation names the completed objective.
		var progress: Variant = mission_state.get("m02")
		if mission_state.get("phase") == expected_phase \
			or (mission_state.get("id") in [MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, MissionState.M08_ID, MissionState.M09_ID, MissionState.M10_ID, MissionState.M11_ID, MissionState.M12_ID] and expected_phase == "party_departed" and mission_state.get("phase") == "departed") \
			or (mission_state.get("id") == MissionState.M09_ID and expected_phase in mission_state.get("m09", {}).get("completed", [])) \
			or (mission_state.get("id") == MissionState.M11_ID and expected_phase in ["transfer_released", "records_read"] and mission_state.get("m11", {}).get("challenges", {}).get(expected_phase) == true) \
			or (mission_state.get("id") == MissionState.M12_ID and (expected_phase in mission_state.get("m12", {}).get("completed", []) or (expected_phase in ["shelter_opened", "workers_released"] and mission_state.get("m12", {}).get("challenges", {}).get(expected_phase) == true))) \
			or (mission_state.get("id") == MissionState.M04_ID and expected_phase == "clinic_shutter" and mission_state.get("m04", {}).get("clinic_open") == true) \
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

func _walk_to(goal: Vector3, look_back: bool = false, stop_round_state: String = "") -> void:
	# Keep the original movement bound. Opt-in combat uses a separate bounded
	# allowance, because the controller intentionally stops walking to fight.
	var walking_ms: int = 0
	var fighting_ms: int = 0
	var camera: Node = _spectator_camera()
	Input.action_release("jump")
	var movement_action: StringName = &"move_back" if look_back else &"move_forward"
	Input.action_press(movement_action)
	var arrived: bool = false
	var stopped_for_round: bool = false
	var anchor: Vector2 = Vector2(_local_feet().x, _local_feet().z)
	while walking_ms < 15000 and fighting_ms < 25000:
		var step_started: int = Time.get_ticks_msec()
		await _record_companion_route()
		if _combat_travel and _combat_probe.participant_died:
			break
		var feet: Vector3 = _local_feet()
		if not feet.is_finite():
			break
		# A capture freezes the pawn until the next round. A stand waypoint's
		# arrival disk sits inside the touch radius, so waiting for it
		# photographs the reset.
		if stop_round_state != "" and _snapshot_round_state() == stop_round_state:
			arrived = true
			stopped_for_round = true
			break
		if Vector2(feet.x - goal.x, feet.z - goal.z).length() < 0.3 and absf(feet.y - goal.y) < 0.03:
			arrived = true
			break
		if _combat_travel and _combat_probe.travel(_game_manager(), anchor, _combat_travel_targets):
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
	var walk_result: Dictionary = {"goal": [goal.x, goal.y, goal.z], "arrived": arrived, "walking_ms": walking_ms, "fighting_ms": fighting_ms}
	if stopped_for_round:
		walk_result["stopped_for_round"] = true
	_walk_results.append(walk_result)
	await create_timer(0.15).timeout
	if not arrived:
		var stopped: String = "participant died" if _combat_probe.participant_died else str(_local_feet())
		push_error("qa_tour: ordinary walk failed to reach %s, stopped at %s (walking %d ms, fighting %d ms)" % [goal, stopped, walking_ms, fighting_ms])
		_failed = true

## Walk an ordinary route into danger. Unlike `walk_to`, falling on the way is
## the expected end: returns true once the joined fighter is out of the round.
func _walk_into(goal: Vector3) -> bool:
	var camera: Node = _spectator_camera()
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000:
		# A fallen fighter leaves the snapshot, so check life before position.
		if not bool(_observed_state().get("self_alive", false)):
			QaCombat.release_inputs()
			return true
		var feet: Vector3 = _local_feet()
		if not feet.is_finite():
			QaCombat.release_inputs()
			return true
		if Vector2(feet.x - goal.x, feet.z - goal.z).length() < 0.5:
			break
		Input.action_press(&"move_forward")
		camera.set("fp_yaw", atan2(goal.z - feet.z, goal.x - feet.x))
		camera.set("fp_pitch", 0.0)
		await create_timer(0.05).timeout
	QaCombat.release_inputs()
	return false

## One uninterrupted diagnostic window. Every control goes through the same
## human Action path as ordinary play; snapshot shots and positions prove that
## the server resolved combat and movement during the measured interval.
func _moving_combat_probe(seconds: float) -> Dictionary:
	var gm: Node = _game_manager()
	if gm == null or not gm.begin_ack_probe():
		push_error("qa_tour: moving combat requires a connected human fighter")
		return {"passed": false}
	var network: Node = gm.get("net_client")
	var player_id: String = str(network.get("player_id"))
	var predictor: LocalPrediction = gm.get("local_prediction")
	predictor.clear_measurements()
	var started_usec: int = Time.get_ticks_usec()
	var deadline_usec: int = started_usec + int(seconds * 1000000.0)
	var previous_tick: int = -1
	var previous_position: Vector2 = Vector2.ZERO
	var distance_m: float = 0.0
	var shots: int = 0
	var moving_shots: int = 0
	var bot_shots: int = 0
	var bot_snapshots: int = 0
	var snapshots_observed: int = 0
	var interruption: String = ""
	while Time.get_ticks_usec() < deadline_usec:
		if network.get("connection_state") != WebSocketPeer.STATE_OPEN or not bool(gm.get("is_human_player")):
			interruption = "connection_or_role"
			break
		var snapshot: Dictionary = gm.get("latest_snapshot")
		var tick: int = int(snapshot.get("tick", -1))
		if tick > previous_tick:
			var me: Dictionary = QaCombat.actor_by_id(snapshot, player_id)
			if me.is_empty() or int(me.get("hp", 0)) <= 0:
				interruption = "death_or_respawn"
				break
			var position: Vector2 = Vector2(float(me["x"]), float(me["z"]))
			var moved: bool = false
			if previous_tick >= 0:
				var step_distance: float = position.distance_to(previous_position)
				distance_m += step_distance
				moved = step_distance > 0.01
			previous_position = position
			previous_tick = tick
			snapshots_observed += 1
			var target: Dictionary = {}
			var target_distance: float = INF
			for actor: Dictionary in snapshot.get("players", []):
				if str(actor.get("id", "")) == player_id or not ActorState.is_participant(actor) or int(actor.get("hp", 0)) <= 0:
					continue
				var gap: float = position.distance_squared_to(Vector2(float(actor["x"]), float(actor["z"])))
				if gap < target_distance:
					target = actor
					target_distance = gap
			if not target.is_empty():
				bot_snapshots += 1
				var camera: Node = _spectator_camera()
				camera.set("fp_yaw", atan2(float(target["z"]) - position.y, float(target["x"]) - position.x))
				camera.set("fp_pitch", 0.0)
			for shot: Dictionary in snapshot.get("shot_results", []):
				if str(shot.get("shooter_id", "")) == player_id:
					shots += 1
					if moved:
						moving_shots += 1
				else:
					bot_shots += 1
		Input.action_press("fire")
		Input.action_press("move_forward")
		if int((Time.get_ticks_usec() - started_usec) / 1000000) % 2 == 0:
			Input.action_press("move_left")
			Input.action_release("move_right")
		else:
			Input.action_release("move_left")
			Input.action_press("move_right")
		# Poll faster than the 20 Hz snapshot cadence so phase alignment does
		# not hide a valid server update from the observed-combat count.
		await create_timer(0.025).timeout
	QaCombat.release_inputs()
	var ack: Dictionary = gm.end_ack_probe()
	var correction_samples: Array[float] = predictor.correction_samples.duplicate()
	var corrections: Dictionary = _correction_distribution(correction_samples)
	var result: Dictionary = {
		"interruption": interruption,
		"duration_seconds": ack.get("duration_seconds", 0.0),
		"server_snapshot_distance_m": snappedf(distance_m, 0.001),
		"server_shots": shots, "shots_while_moving": moving_shots,
		"other_shots": bot_shots, "snapshots_with_live_opponents": bot_snapshots,
		"snapshots_observed": snapshots_observed,
		"correction_m": corrections, "prediction_fallbacks": predictor.fallback_reasons.duplicate(),
		"peak_correction": {"tick": predictor.correction_max_tick,
			"elapsed_ms": (predictor.correction_max_usec - started_usec) / 1000 if predictor.correction_max_usec >= started_usec else null,
			"server_position": [snappedf(predictor.correction_max_server_position.x, 0.001),
				snappedf(predictor.correction_max_server_position.y, 0.001),
				snappedf(predictor.correction_max_server_position.z, 0.001)]},
		"prediction_fallback_count": predictor.fallback_count,
		"prediction_active_at_end": predictor.active(),
		"ack_probe": ack,
	}
	var passed: bool = valid_moving_combat_capture(result, seconds)
	result["passed"] = passed
	if not passed:
		push_error("qa_tour: moving combat probe failed: " + JSON.stringify(result))
	return result

static func _correction_distribution(samples: Array[float]) -> Dictionary:
	if samples.is_empty():
		return {"samples": 0, "p50": null, "p95": null, "p99": null, "max": null}
	var ordered: Array[float] = samples.duplicate()
	ordered.sort()
	return {"samples": ordered.size(), "p50": snappedf(ordered[int(ceilf(ordered.size() * 0.50)) - 1], 0.0001),
		"p95": snappedf(ordered[int(ceilf(ordered.size() * 0.95)) - 1], 0.0001),
		"p99": snappedf(ordered[int(ceilf(ordered.size() * 0.99)) - 1], 0.0001),
		"max": snappedf(ordered.back(), 0.0001)}

func _set_aim_pitch(pitch: float) -> void:
	pitch = clampf(pitch, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT)
	var gm: Node = _game_manager()
	var cam: Node = _spectator_camera()
	if gm == null or cam == null or not bool(gm.get("is_human_player")):
		push_error("qa_tour: pitch capture requires a joined human")
		_failed = true
		return
	var deadline: int = Time.get_ticks_msec() + 5000
	# A live arcade opponent can kill this participant during the request.
	# Respawn restores facing, so keep sending the requested ordinary input
	# until a living snapshot and camera agree. Never accept a dead pose.
	while Time.get_ticks_msec() < deadline:
		if _self_alive(gm, gm.latest_snapshot):
			cam.set("fp_pitch", pitch)
			if absf(_local_server_pitch(gm) - pitch) <= 0.001:
				return
		await process_frame
	push_error("qa_tour: living pitch did not reach the authoritative snapshot (expected %.6f, server %.6f)" % [pitch, _local_server_pitch(gm)])
	_failed = true

func _ctf_matches(expected: Dictionary, observed: Dictionary) -> bool:
	if expected.has("status"):
		var flags: Variant = observed.get("flags")
		if not flags is Array:
			return false
		var found: bool = false
		for flag: Variant in flags:
			if flag is Dictionary:
				if flag.get("status") == expected["status"] and (not expected.has("team") or flag.get("team") == expected["team"]):
					found = true
		if not found:
			return false
	if expected.has("capture_at_least"):
		var scores: Variant = observed.get("capture_scores")
		if not scores is Dictionary or int(scores.get("union", 0)) + int(scores.get("coalition", 0)) < int(expected["capture_at_least"]):
			return false
	if expected.has("round_state") and observed.get("round_state") != expected["round_state"]:
		return false
	return true

## The joined fighter appears in the live snapshot.
func _self_alive(gm: Node, snapshot: Dictionary) -> bool:
	var net: Node = gm.get("net_client")
	if not bool(gm.get("is_human_player")) or net == null or net.get("player_id") == null:
		return false
	for player: Variant in snapshot.get("players", []):
		if player is Dictionary and str(player.get("id", "")) == str(net.get("player_id")):
			return true
	return false


## Live Sabotage facts a state waits for or expects: `phase`, `charge_status`,
## `progress_kind`, `progress_at_least` (0 to 1), `round_at_least`, `round_state`,
## `self_fallen` (a joined fighter out of an active round) and `winner_card`.
func _sabotage_matches(expected: Dictionary, observed: Dictionary) -> bool:
	var round: Variant = observed.get("sabotage")
	if not round is Dictionary:
		return false
	if expected.has("phase") and round.get("phase") != expected["phase"]:
		return false
	var charge: Dictionary = round.get("charge") if round.get("charge") is Dictionary else {}
	if expected.has("charge_status") and charge.get("status") != expected["charge_status"]:
		return false
	var progress: Dictionary = round.get("progress") if round.get("progress") is Dictionary else {}
	if expected.has("progress_kind") and progress.get("kind") != expected["progress_kind"]:
		return false
	if expected.has("progress_at_least") and SabotageState.progress_fraction(round) < float(expected["progress_at_least"]):
		return false
	if expected.has("round_at_least") and int(round.get("round", 0)) < int(expected["round_at_least"]):
		return false
	if expected.has("round_state") and observed.get("round_state") != expected["round_state"]:
		return false
	if expected.has("self_alive") and bool(expected["self_alive"]) != bool(observed.get("self_alive", false)):
		return false
	if expected.has("self_fallen") and bool(expected["self_fallen"]) != (observed.get("round_state") == "Active" and not bool(observed.get("self_alive", false))):
		return false
	if expected.has("hud_line_contains"):
		var manager: Node = _game_manager()
		var hud_node: Node = manager.get("hud") if manager != null else null
		var line: String = str(hud_node.get("sabotage_line")) if hud_node != null else ""
		if not line.contains(str(expected["hud_line_contains"])):
			return false
	return true


func _await_sabotage(expected: Dictionary, timeout_seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + roundi(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _sabotage_matches(expected, _observed_state()):
			return true
		await create_timer(0.05).timeout
	push_error("qa_tour: live Sabotage state never reached %s" % str(expected))
	_failed = true
	return false


func _await_ctf(expected: Dictionary, timeout_seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + roundi(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _ctf_matches(expected, _observed_state()):
			return true
		await create_timer(0.05).timeout
	push_error("qa_tour: live CTF state never reached %s" % str(expected))
	_failed = true
	return false

func _pose_camera(mode: String, state: Dictionary = {}) -> void:
	if mode == "none":
		return
	var cam: Node = _spectator_camera()
	if cam == null:
		return
	cam.set("frag_follow_timer", 0.0)
	match mode:
		"sabotage_site":
			var layout: Dictionary = _game_manager().get("sabotage_layout") if _game_manager() != null else {}
			var wanted_site: String = str(state.get("site", "a"))
			for site: Variant in layout.get("sites", []):
				if site is Dictionary and site.get("id") == wanted_site and cam is Node3D:
					var centre: Array = site["center"]
					var point: Vector3 = Vector3(float(centre[0]), float(centre[1]), float(centre[2]))
					cam.set("spectator_first_person", false)
					cam.set("follow_mode", false)
					cam.set("fp_mode", false)
					var offset: Array = state.get("camera_offset", [9.0, 4.0, 0.0])
					var camera: Node3D = cam
					camera.global_position = point + Vector3(float(offset[0]), float(offset[1]), float(offset[2]))
					camera.look_at(point + Vector3(0.0, 1.8, 0.0), Vector3.UP)
					cam.set("tip_locked_transform", cam.global_transform)
					cam.set("tip_has_locked_transform", true)
					cam.set("tip_pose_lock", true)
					return
			push_error("qa_tour: no Sabotage site %s to frame" % wanted_site)
			_failed = true
		"sabotage_charge":
			var round: Variant = _observed_state().get("sabotage")
			var charge: Variant = round.get("charge") if round is Dictionary else null
			if charge is Dictionary and cam is Node3D:
				var position: Array = charge["position"]
				var focus: Vector3 = Vector3(float(position[0]), float(position[1]) + 0.4, float(position[2]))
				var forward: Vector3 = Vector3(1.0, 0.0, 0.3).normalized()
				var manager: Node = _game_manager()
				if charge.get("status") == "carried" and manager != null:
					var pawn: Variant = manager.players.get(str(charge.get("carrier", "")))
					if pawn is Node3D and is_instance_valid(pawn):
						focus = (pawn as Node3D).global_position + Vector3(0.0, -0.3, 0.0)
						forward = (pawn as Node3D).global_transform.basis.x
				cam.set("spectator_first_person", false)
				cam.set("follow_mode", false)
				cam.set("fp_mode", false)
				var camera: Node3D = cam
				var back: float = float(state.get("camera_distance", 4.2))
				camera.global_position = focus + forward.normalized() * back + Vector3(0.0, float(state.get("camera_height", 1.6)), 0.0)
				camera.look_at(focus, Vector3.UP)
				cam.set("tip_locked_transform", cam.global_transform)
				cam.set("tip_has_locked_transform", true)
				cam.set("tip_pose_lock", true)
				return
			push_error("qa_tour: no live Sabotage charge to frame")
			_failed = true
		"sabotage_actor":
			var round: Variant = _observed_state().get("sabotage")
			var progress: Variant = round.get("progress") if round is Dictionary else null
			if progress is Dictionary and cam.has_method("pin_player"):
				release_camera_pose_lock(cam)
				cam.call("pin_player", str(progress.get("player_id", "")))
				return
			push_error("qa_tour: no Sabotage plant or defuse to follow")
			_failed = true
		"ctf_carried", "ctf_dropped":
			var wanted: String = "carried" if mode == "ctf_carried" else "dropped"
			var flags: Variant = _observed_state().get("flags")
			if flags is Array:
				for flag: Variant in flags:
					if flag is Dictionary and flag.get("status") == wanted:
						var position: Array = flag["position"]
						var point: Vector3 = Vector3(float(position[0]), float(position[1]), float(position[2]))
						cam.set("spectator_first_person", false)
						cam.set("follow_mode", false)
						cam.set("fp_mode", false)
						if cam is Node3D:
							var camera: Node3D = cam
							if mode == "ctf_carried":
								var focus: Vector3 = point + Vector3(0.0, 1.55, 0.0)
								var forward: Vector3 = Vector3(1.0, 0.0, 0.0)
								var manager: Node = _game_manager()
								if manager != null and flag.get("carrier") is String:
									var pawn: Variant = manager.players.get(str(flag["carrier"]))
									if pawn is Node3D and is_instance_valid(pawn):
										focus = (pawn as Node3D).global_position + Vector3(0.0, -0.15, 0.0)
										forward = (pawn as Node3D).global_transform.basis.x
								if forward.length_squared() > 0.01:
									forward = forward.normalized()
								camera.global_position = focus + forward * 4.6 + Vector3(0.0, 1.35, 0.0)
								camera.look_at(focus, Vector3.UP)
							else:
								camera.global_position = point + Vector3(9.0, 4.5, 11.0)
								camera.look_at(point + Vector3(0.0, 1.2, 0.0), Vector3.UP)
						return
			push_error("qa_tour: no live %s flag to frame" % wanted)
			_failed = true
		"union_flag", "coalition_flag":
			var team_name: String = "union" if mode == "union_flag" else "coalition"
			var side: float = -1.0 if team_name == "union" else 1.0
			var home_flags: Variant = _observed_state().get("flags")
			var framed: bool = false
			if home_flags is Array:
				for home_flag: Variant in home_flags:
					if home_flag is Dictionary and str(home_flag.get("team", "")) == team_name:
						var stand: Variant = home_flag.get("stand", home_flag.get("position"))
						if stand is Array and stand.size() == 3:
							cam.set("spectator_first_person", false)
							cam.set("follow_mode", false)
							cam.set("fp_mode", false)
							if cam is Node3D:
								var home: Vector3 = Vector3(float(stand[0]), float(stand[1]), float(stand[2]))
								# Seven metres toward center is the Sector 9 framing.
								# Arena Duel's perimeter wall sits at |x| = 56, so that
								# step from x = 63 lands inside the wall. Stay in the room.
								var inward: float = 3.0 if absf(home.x) < 65.0 else 7.0
								var n3: Node3D = cam
								n3.global_position = home + Vector3(-side * inward, 4.0, 11.0)
								n3.look_at(home + Vector3(0.0, 1.2, 0.0), Vector3.UP)
							framed = true
							break
			if not framed:
				push_error("qa_tour: no live %s flag stand to frame" % team_name)
				_failed = true
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

## Three metres from the fighter, preferring the arena centre and checking
## the full body against the same authoritative solids as the real camera.
static func body_camera_position(feet: Vector3, solids: Array) -> Vector3:
	var toward: Vector3 = Vector3(-feet.x, 0, -feet.z)
	toward = toward.normalized() if toward.length() > 0.5 else Vector3.BACK
	for index: int in range(16):
		var direction: Vector3 = toward.rotated(Vector3.UP, float(index) * TAU / 16.0)
		var side: Vector3 = Vector3(-direction.z, 0, direction.x) * 0.45
		var candidate: Vector3 = feet + direction * 3.0 + Vector3(0, 1.3, 0)
		var clear: bool = true
		for height: float in [0.12, 0.95, 1.85]:
			for offset: Vector3 in [Vector3.ZERO, side, -side]:
				if not AimAssist.line_of_sight(candidate, feet + Vector3(0, height, 0) + offset, solids):
					clear = false
		if clear:
			return candidate
	return Vector3.INF

## Holds the accepted body rather than leaving a still behind as it moves,
## so the nearest wall is behind the subject rather than in front of it.
func _hold_body_camera() -> void:
	var cam: Node = _spectator_camera()
	_body_frame_clear = false
	if not is_instance_valid(_body_pawn) or int(_body_pawn.get("hp")) <= 0:
		# The subject died before the shutter: hold on another who matches.
		_body_pawn = _live_body()
	if _body_pawn == null or not cam is Node3D:
		return
	var feet: Vector3 = _body_pawn.global_position - Vector3(0, CameraScript.FP_SERVER_REFERENCE_Y, 0)
	var position: Vector3 = body_camera_position(feet, cam.get("assist_solids"))
	if not position.is_finite():
		return
	var camera: Node3D = cam
	camera.global_position = position
	camera.look_at(feet + Vector3(0, 0.95, 0), Vector3.UP)
	_body_frame_clear = true
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
	_body_frame_clear = false

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
		"radio_comparison": _radio_comparison.duplicate(true) if _radio_compare_on else {},
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

func _m05_local_body() -> Dictionary:
	var manager: Node = _game_manager()
	var actor: Dictionary = {}
	for player: Dictionary in manager.latest_snapshot.get("players", []):
		if player["id"] == manager.net_client.player_id:
			actor = player
	if actor.is_empty() or int(actor["hp"]) <= 0:
		return {}
	var feet: Vector3 = _local_feet()
	return {"x": feet.x, "y": feet.y, "z": feet.z, "vy": float(manager.last_ack.get("movement", {}).get("vy", INF))}

func _board_m05_tram() -> void:
	var manager: Node = _game_manager()
	var geometry: Dictionary = manager.net_client.mission_geometry
	if geometry.get("id") != MissionState.M05_ID:
		push_error("qa_tour: tram boarding requires M05")
		_failed = true
		return
	var start: Vector3 = _local_feet()
	var bound: Dictionary = geometry["m05"]["tram"]
	var target: Vector3 = GrenadeFacts.vector(bound["start"]) + Vector3.UP * (MoveStep.solid_top(geometry["tram_solid"]) - float(bound["start"][1]))
	if Vector2(start.x - target.x, start.z - target.z).length() > 5.0 or absf(start.y - target.y) > 0.6:
		push_error("qa_tour: ordinary tram jump must start at its reachable dock")
		_failed = true
		return
	manager.camera.set("fp_yaw", atan2(target.z - start.z, target.x - start.x))
	Input.action_press("jump")
	Input.action_press("move_forward")
	var deadline: int = Time.get_ticks_msec() + 4000
	var jumped: bool = false
	var grounded: bool = false
	while Time.get_ticks_msec() < deadline:
		var body: Dictionary = _m05_local_body()
		if body.is_empty():
			break
		var feet: Vector3 = _local_feet()
		if feet.y > start.y + 0.1:
			jumped = true
			Input.action_release("jump")
		var tram: Dictionary = manager.net_client.mission["state"]["m05"]["tram"]
		var solid: Dictionary = M05Tram.solid_at(geometry, tram["feet"])
		if absf(feet.x - target.x) < 0.25:
			Input.action_release("move_forward")
		if jumped and M05Tram.supported(body, solid, false):
			grounded = true
			break
		await create_timer(0.02).timeout
	Input.action_release("jump")
	Input.action_release("move_forward")
	if not grounded:
		push_error("qa_tour: ordinary jump never landed on live tram: " + str(_local_feet()))
		_failed = true
	else:
		print("qa_tour: ordinary jump boarded live tram from ", start, " to ", _local_feet())

func _ride_m05_tram(seconds: float, required_metres: float) -> void:
	var manager: Node = _game_manager()
	var geometry: Dictionary = manager.net_client.mission_geometry
	if geometry.get("id") != MissionState.M05_ID or not is_finite(seconds) or seconds < 0.5 or seconds > 15.0 \
		or not is_finite(required_metres) or required_metres < 0.1 or required_metres > 20.0:
		push_error("qa_tour: invalid bounded tram ride request")
		_failed = true
		return
	var start: Vector3 = _local_feet()
	var first: Dictionary = manager.net_client.mission["state"]["m05"]["tram"].duplicate(true)
	var supported_samples: int = 0
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var body: Dictionary = _m05_local_body()
		var tram: Dictionary = manager.net_client.mission["state"]["m05"]["tram"]
		if body.is_empty() or not M05Tram.supported(body, M05Tram.solid_at(geometry, tram["feet"]), false):
			push_error("qa_tour: rider lost actual support during tram motion")
			_failed = true
			return
		supported_samples += 1
		await create_timer(0.05).timeout
	var last: Dictionary = manager.net_client.mission["state"]["m05"]["tram"]
	var delta: float = float(last["feet"][2]) - float(first["feet"][2])
	var player_delta: float = _local_feet().z - start.z
	_m05_ride_report = {"tram_metres": delta, "rider_metres": player_delta, "supported_samples": supported_samples, "start_tick": first["tick"], "end_tick": last["tick"]}
	if absf(delta) < required_metres or absf(delta - player_delta) > 0.12 or supported_samples < int(seconds * 10.0):
		push_error("qa_tour: actual tram/rider displacement disagreed: " + JSON.stringify(_m05_ride_report))
		_failed = true
	print("qa_tour: actual tram ride ", JSON.stringify(_m05_ride_report))
