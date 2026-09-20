extends "res://scripts/qa_tour.gd"

## Real local M01 deaths and retries through normal movement and input.
var _captures: String = ""

func _expect(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error("test_campaign_recovery: " + message)

func _until(condition: Callable, message: String, timeout_ms: int = 35000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	var passed: bool = condition.call()
	_expect(passed, message)
	return passed

func _state() -> Dictionary:
	var manager: Node = _game_manager()
	return {} if manager == null else manager.net_client.mission.get("state", {})

func _capture(name: String) -> void:
	if _captures.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png(_captures.path_join(name + ".png")) == OK, "capture " + name)

func _run() -> void:
	_captures = OS.get_environment("FRAGR_RECOVERY_CAPTURE_DIR")
	if not _captures.is_empty():
		DirAccess.make_dir_recursive_absolute(_captures)
	var settings_path: String = "user://test-campaign-recovery-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	var preferences: FragrSettings = FragrSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	_expect(preferences.save_to_disk() == OK, "isolated preferences saved")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/boot_menu.tscn")
	await process_frame
	await process_frame
	current_scene._start_campaign("severe")
	if await _until(func() -> bool: return _game_manager() != null and is_instance_valid(_game_manager().opening), "owned mission reaches introduction"):
		_game_manager().opening.finish()
		if await _until(func() -> bool: return _state().get("phase") == "find_transfer" and not _game_manager().controls_blocked(), "reader enters live run"):
			await _exercise_run()
	QaCombat.release_inputs()
	var owner: LocalMatch = LocalMatch.for_tree(self)
	owner.stop()
	await _until(func() -> bool: return owner.state == LocalMatch.State.IDLE, "owned child shuts down")
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if not _failed:
		print("test_campaign_recovery: PASS real M01 death, three input-driven retries, entry restore and exhaustion")
	quit(1 if _failed else 0)

func _exercise_run() -> void:
	var run_id: String = _state()["run"]["id"]
	var entry: Vector3 = _local_feet()
	var entry_yaw: float = _game_manager().camera.consume_yaw()
	for spent: int in range(4):
		_expect(_state()["run"]["id"] == run_id and int(_state()["run"]["continues"]) == 3 - spent, "same run retains spent allowance")
		await _walk_to(Vector3(0, 0, -26))
		await _walk_to(Vector3(0, 0, -21))
		if _failed:
			return
		if not await _until(func() -> bool: return _state().get("run", {}).get("status") in ["continue", "failed"], "Clerk defeats the exposed player"):
			return
		_expect(_game_manager().controls_blocked(), "death blocks gameplay")
		await _capture("death-%d" % spent)
		if spent == 3:
			_expect(_state()["run"]["status"] == "failed", "fourth death ends the run")
			_expect(not _game_manager().net_client.send_mission_continue(), "exhaustion offers no retry")
			return
		# A retry must not keep a player's last look direction at the new spawn.
		_game_manager().camera.fp_yaw = entry_yaw + 1.0
		_game_manager().camera.fp_pitch = 0.4
		await process_frame
		var press: InputEventKey = InputEventKey.new()
		press.keycode = KEY_ENTER
		press.physical_keycode = KEY_ENTER
		press.pressed = true
		Input.parse_input_event(press)
		await process_frame
		press = press.duplicate()
		press.pressed = false
		Input.parse_input_event(press)
		if not await _until(func() -> bool: return int(_state().get("attempt", 0)) == spent + 2 and _state()["run"]["status"] == "playing" and not _game_manager().controls_blocked(), "continue starts next attempt"):
			return
		await create_timer(0.25).timeout
		_expect(_local_feet().distance_to(entry) < 0.1, "retry restores actual entry position")
		_expect(_equipment().get("selected") == "fists", "M01 entry equipment is restored")
		_expect(absf(angle_difference(entry_yaw, _game_manager().camera.consume_yaw())) < 0.01 and absf(_game_manager().camera.consume_pitch()) < 0.01, "retry restores entry facing: entry=%f actual=%f pitch=%f" % [entry_yaw, _game_manager().camera.consume_yaw(), _game_manager().camera.consume_pitch()])
		_expect(not is_instance_valid(_game_manager().opening), "retry does not replay introduction")
		await _capture("retry-%d" % spent)
