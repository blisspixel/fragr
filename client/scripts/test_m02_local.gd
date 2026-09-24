extends SceneTree

## The Single Player development entry launches the real M02 child, joins as a
## human, becomes ready without a story page and never writes a run file.
var failures: int = 0
var settings_path: String
var run_directory: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://m02-local-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	run_directory = ProjectSettings.globalize_path("user://m02-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	call_deferred("_run")

func _finalize() -> void:
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	OS.unset_environment("FRAGR_RUN_DIR")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m02_local: " + message)

func _until(condition: Callable, description: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 20000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	_expect(passed, description)
	if not passed:
		quit(1)
	return passed

func _playing() -> bool:
	return current_scene != null and current_scene.has_method("change_role") \
		and current_scene.current_map_id == 1002 and not current_scene.latest_snapshot.is_empty() \
		and current_scene.mission_hud.state.get("phase") == "in_progress"

func _run() -> void:
	var prefs: FragrSettings = FragrSettings.new(settings_path)
	prefs.set_value("video", "display_mode", 0)
	_expect(prefs.save_to_disk() == OK, "isolated preferences saved")
	_expect(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "boot menu loads")
	await process_frame
	await process_frame
	current_scene._show("single")
	await process_frame
	var entry: Button = current_scene._root.get_node_or_null("PersonsUnknownGraybox") as Button
	_expect(entry != null and not entry.disabled, "the development entry is selectable")
	if entry == null:
		quit(1)
		return
	entry.pressed.emit()
	if not await _until(_playing, "the development entry enters authoritative M02"):
		print("test_m02_local: scene ", current_scene, " ", LocalMatch.for_tree(self).state, " ", LocalMatch.for_tree(self).error_key)
		if current_scene != null and current_scene.has_method("change_role"):
			print("test_m02_local: map ", current_scene.current_map_id, " snapshot ", not current_scene.latest_snapshot.is_empty(), " state ", current_scene.mission_hud.state, " blocked ", current_scene.controls_blocked())
		return
	var owned: LocalMatch = LocalMatch.for_tree(self)
	_expect(owned.mission == MissionState.M02_ID and owned.state == LocalMatch.State.RUNNING, "the owned child is the M02 development child")
	_expect(not is_instance_valid(current_scene.opening), "the graybox has no story page yet")
	var state: Dictionary = current_scene.mission_hud.state
	_expect(not state.has("run") and state["m02"]["current"]["id"] == "companion_released", "M02 starts at the first objective without a run")
	_expect(not current_scene.controls_blocked(), "the ready participant can move")
	var hud: MissionHud = current_scene.mission_hud
	_expect(hud._card.visible and hud._copy.text == tr("M02_OBJECTIVE_COMPANION_RELEASED") and not hud._prompt.visible, "one objective line shows on entry")
	await process_frame
	await process_frame
	# The card wraps; every M02 objective line must fit it without a second row.
	hud._copy.text = "FIND THE WAY DOWN TO THE CORRECTION WARD NOW"
	await process_frame
	_expect(hud._copy.get_line_count() > 1, "the line measurement detects a wrapped card")
	for id: String in MissionHud.M02_KNOWN:
		hud._copy.text = tr(MissionHud.objective_key(id))
		await process_frame
		_expect(hud._copy.get_line_count() == 1, "objective copy fits one card line: " + id)
	for key: String in ["M02_WAITING", "M02_DEPARTED", "M02_OBJECTIVE_UNKNOWN"]:
		hud._copy.text = tr(key)
		await process_frame
		_expect(hud._copy.get_line_count() == 1, "status copy fits one card line: " + key)
	var pause: PauseMenu = current_scene.get_node("PauseMenu")
	pause.open()
	_expect(pause._note.text == tr("MENU_EXIT_DEVELOPMENT"), "the match menu does not promise a saved run")
	pause.close()
	_expect(not DirAccess.dir_exists_absolute(run_directory) or DirAccess.get_files_at(run_directory).is_empty(), "the development child writes no run file")
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "the child stops on request"):
		return
	# Retire the match scene so its audio and radio streams release before exit.
	current_scene.queue_free()
	await process_frame
	# Audio playbacks retire on the mixer thread after their players leave.
	await create_timer(0.5).timeout
	await process_frame
	if failures == 0:
		print("test_m02_local: PASS development entry, M02 child, ready without a story page, one HUD line, no run file")
	quit(0 if failures == 0 else 1)
