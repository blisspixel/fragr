extends "res://scripts/qa_tour.gd"

## Exercise the saved death choice and spent allowance through real child restarts.
var _run_directory: String = ""

func _expect_saved(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error("test_saved_run_restart: " + message)

func _until_saved(condition: Callable, message: String, timeout_ms: int = 35000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	var passed: bool = condition.call()
	_expect_saved(passed, message)
	return passed

func _state() -> Dictionary:
	var manager: Node = _game_manager()
	return {} if manager == null else manager.net_client.mission.get("state", {})

func _run() -> void:
	_run_directory = ProjectSettings.globalize_path("res://../.agents/saved-run-restart-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", _run_directory)
	var settings_path: String = "user://test-saved-run-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	set_meta("fragr_records_path", ProjectSettings.globalize_path("res://../.agents/saved-run-records-%d" % OS.get_process_id()))
	var preferences: FragrSettings = FragrSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	_expect_saved(preferences.save_to_disk() == OK, "isolated preferences saved")
	change_scene_to_file("res://scenes/boot_menu.tscn")
	await process_frame
	await process_frame
	current_scene._start_campaign("severe")
	if not await _until_saved(func() -> bool: return _game_manager() != null and is_instance_valid(_game_manager().opening), "new run shows its opening"):
		quit(1)
		return
	_game_manager().opening.finish()
	if not await _until_saved(func() -> bool: return _state().get("phase") == "find_transfer" and not _game_manager().controls_blocked(), "opening hands off to combat"):
		quit(1)
		return
	var run_id: String = str(_state()["run"]["id"])
	await _walk_to(Vector3(0, 0, -26))
	await _walk_to(Vector3(0, 0, -21))
	if not await _until_saved(func() -> bool: return _state().get("run", {}).get("status") == "continue", "first death offers a continue"):
		quit(1)
		return
	if not await _restart_saved(run_id, "continue", 1, 3, true):
		quit(1)
		return
	QaCombat.release_inputs()
	if not await _until_saved(func() -> bool: return _game_manager()._continue_armed and _game_manager().net_client.record.get("status") == "continue", "resumed continue is armed with its matching record"):
		quit(1)
		return
	var press: InputEventKey = InputEventKey.new()
	press.keycode = KEY_ENTER
	press.physical_keycode = KEY_ENTER
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	press = press.duplicate()
	press.pressed = false
	Input.parse_input_event(press)
	if not await _until_saved(func() -> bool: return _state().get("run", {}).get("status") == "playing" and int(_state().get("attempt", 0)) == 2 and int(_state()["run"]["continues"]) == 2, "continue spends once after restart"):
		quit(1)
		return
	if not await _restart_saved(run_id, "playing", 2, 2, false):
		quit(1)
		return
	QaCombat.release_inputs()
	_track_scene_audio()
	_game_manager()._on_leave_requested()
	await _until_saved(func() -> bool: return current_scene != null and current_scene.has_method("_start_campaign_resume") and LocalMatch.for_tree(self).state == LocalMatch.State.IDLE, "final child stops")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	OS.unset_environment("FRAGR_RUN_DIR")
	await _retire_scene()
	if not _failed:
		print("test_saved_run_restart: PASS pending death and spent continue survive process restarts")
	quit(1 if _failed else 0)

func _restart_saved(run_id: String, status: String, attempt: int, continues: int, pending: bool) -> bool:
	_track_scene_audio()
	_game_manager()._on_leave_requested()
	if not await _until_saved(func() -> bool: return current_scene != null and current_scene.has_method("_start_campaign_resume") and LocalMatch.for_tree(self).state == LocalMatch.State.IDLE, "owned child stops before restart"):
		return false
	current_scene._show("single")
	if not await _until_saved(func() -> bool: return LocalMatch.for_tree(self).run_preview.get("status") == "ready", "menu previews saved run"):
		return false
	var preview: Dictionary = LocalMatch.for_tree(self).run_preview
	_expect_saved(int(preview["attempt"]) == attempt and int(preview["continues"]) == continues and preview["pending_continue"] == pending, "preview preserves exact death choice and allowance")
	current_scene._start_campaign_resume()
	if not await _until_saved(func() -> bool: return _game_manager() != null and not _state().is_empty() and _state().get("run", {}).get("status") == status, "saved state returns on the wire"):
		return false
	_expect_saved(str(_state()["run"]["id"]) == run_id and int(_state()["run"]["continues"]) == continues and int(_state()["attempt"]) == attempt, "authoritative run identity and allowance survive restart")
	_expect_saved(not is_instance_valid(_game_manager().opening), "restart skips the opening replay")
	if status == "playing":
		return await _until_saved(func() -> bool: return _state().get("phase") == "find_transfer" and not _game_manager().controls_blocked(), "resumed entry becomes ready")
	return true
