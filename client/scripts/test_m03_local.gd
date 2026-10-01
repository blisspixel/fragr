extends SceneTree

## Actual development menu, owned child, reader-paced arrival and save isolation.
var failures: int = 0
var settings_path: String
var run_directory: String
const PRIOR_BYTES: String = "prior personal run bytes retained by development launch\n"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://m03-local-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	run_directory = ProjectSettings.globalize_path("user://m03-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	call_deferred("_run")

func _finalize() -> void:
	Input.action_release("fire")
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	DirAccess.remove_absolute(run_directory.path_join("run.json"))
	DirAccess.remove_absolute(run_directory)
	OS.unset_environment("FRAGR_RUN_DIR")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m03_local: " + message)

func _until(condition: Callable, description: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 25000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	_check(passed, description)
	if not passed:
		print("test_m03_local: child ", LocalMatch.for_tree(self).state, " error ", LocalMatch.for_tree(self).error_key)
		quit(1)
	return passed

func _arrived() -> bool:
	return current_scene != null and current_scene.has_method("change_role") and current_scene.current_map_id == 1003 \
		and is_instance_valid(current_scene.opening) and not current_scene.mission_hud.state.is_empty()

func _playing() -> bool:
	return current_scene != null and current_scene.has_method("change_role") \
		and current_scene.mission_hud.state.get("phase") == "in_progress" and not current_scene.controls_blocked()

func _run() -> void:
	var preferences: FragrSettings = FragrSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	_check(preferences.save_to_disk() == OK, "isolated settings saved")
	_check(DirAccess.make_dir_recursive_absolute(run_directory) == OK, "isolated run directory prepared")
	var prior: FileAccess = FileAccess.open(run_directory.path_join("run.json"), FileAccess.WRITE)
	_check(prior != null, "prior personal save fixture created")
	if prior == null:
		quit(1)
		return
	prior.store_string(PRIOR_BYTES)
	prior.close()
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "boot menu loads")
	await process_frame
	await process_frame
	current_scene._show("practice")
	await process_frame
	(current_scene._root.get_node("DevelopmentMission") as OptionButton).select(1)
	var entry: Button = current_scene._root.get_node_or_null("LaunchDevelopmentMission") as Button
	_check(entry != null and not entry.disabled, "labeled M03 development entry is selectable")
	if entry == null:
		quit(1)
		return
	entry.pressed.emit()
	if not await _until(_arrived, "owned development child reaches the M03 reader-paced arrival"):
		return
	var owned: LocalMatch = LocalMatch.for_tree(self)
	var game: Node = current_scene
	_check(owned.mission == MissionState.M03_ID and not owned.has_durable_run(), "actual M03 child uses development mode")
	_check(game.opening.scene["id"] == StoryScene.BEFORE_MISSION[MissionState.M03_ID] and game.controls_blocked(), "M03 uses its own story scene and shared input barrier")
	_check(game.mission_hud.state["phase"] == "briefing" and not game.mission_hud.state["party"][0]["ready"], "server remains in briefing while the player reads")
	# Dismissing while fire is held must not acknowledge or shoot into the level.
	Input.action_press("fire")
	game.opening._skip.pressed.emit()
	await create_timer(0.2).timeout
	_check(game.mission_hud.state["phase"] == "briefing" and game.controls_blocked(), "arrival dismissal waits for held gameplay input to release")
	Input.action_release("fire")
	if not await _until(_playing, "release acknowledges M03 through the shared readiness wire"):
		return
	var state: Dictionary = game.mission_hud.state
	_check(not state.has("run") and state["m03"]["mast_hp"] == 40 and not state["m03"]["mast_secured"], "development M03 starts intact without a durable run")
	_check(state["m03"]["current"]["action"]["kind"] == "shoot" and game.pending_interact == false, "authoritative mast goal is Shoot and arrival input leaves no use press")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and game.mouse_capture.desired_mode() == Input.MOUSE_MODE_VISIBLE,
		"automated local launch never captures the desktop")
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == PRIOR_BYTES,
		"actual development child preserves existing personal run bytes")
	var pause: PauseMenu = game.get_node("PauseMenu")
	pause.open()
	_check(pause._note.text == tr("MENU_EXIT_DEVELOPMENT"), "development menu never promises a save")
	pause.close()
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "owned M03 child stops cleanly"):
		return
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == PRIOR_BYTES, "stopping development preserves the same save bytes")
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	await process_frame
	if failures == 0:
		print("test_m03_local: PASS prototype menu, owned child, arrival/readiness release, save isolation and cleanup")
	quit(0 if failures == 0 else 1)
