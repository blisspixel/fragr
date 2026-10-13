extends SceneTree

var failures: int = 0
var settings_path: String
var owned: LocalMatch

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://m13-local-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	_run.call_deferred()

func _finalize() -> void:
	MouseCapture.release()
	if is_instance_valid(owned):
		owned.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m13_local: " + message)

func _until(condition: Callable, message: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 25000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	_check(passed, message)
	return passed

func _run() -> void:
	var preferences := FragrSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	_check(preferences.save_to_disk() == OK, "isolated settings")
	owned = LocalMatch.for_tree(self)
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "actual boot scene")
	await process_frame
	await process_frame
	current_scene._start_development(MissionState.M13_ID)
	if not await _until(func() -> bool: return current_scene != null and current_scene.has_method("change_role") and current_scene.current_map_id == 1013 and is_instance_valid(current_scene.opening), "owned M13 practice child crosses real human admission and plays arrival"):
		owned.stop()
		quit(1)
		return
	var game: Node = current_scene
	_check(game.net_client.mission.get("state", {}).get("phase") == "briefing", "accepted wire briefing waits for the actual arrival dismissal")
	game.opening._skip.pressed.emit()
	if not await _until(func() -> bool: return game.net_client.mission.get("state", {}).get("phase") == "in_progress" and not game.controls_blocked(), "arrival dismissal crosses canonical readiness"):
		owned.stop()
		quit(1)
		return
	_check(game.net_client.mission_geometry["id"] == MissionState.M13_ID and game.m13_foundry._people.size() == 3, "accepted foundry geometry presents three actual workers")
	_check(game.net_client.mission["state"]["m13"]["lift"]["phase"] == "parked" and not game.net_client.mission["state"]["m13"]["challenges"].has("workers"), "practice entry retains parked lift and unreleased worker facts")
	var start_tick: int = int(game.net_client.mission["tick"])
	if await _until(func() -> bool: return int(game.net_client.mission.get("tick",0)) >= start_tick + 5, "successive real mission frames remain accepted"):
		_check(game.net_client.mission["state"]["m13"]["lift"]["tick"] == game.net_client.mission["tick"], "live lift facts bind the exact accepted message tick")
	owned.stop()
	await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "owned native child exits")
	current_scene.queue_free()
	await process_frame
	# Let stopped mixer playbacks retire before the headless process exits,
	# matching the other actual local-campaign launch harnesses.
	await create_timer(0.5).timeout
	if failures == 0:
		print("test_m13_local: PASS")
	quit(0 if failures == 0 else 1)
