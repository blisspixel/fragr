extends SceneTree

var failures: int = 0
var settings_path: String
var owned: LocalMatch

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://late-local-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	node_added.connect(func(node: Node) -> void:
		if node.has_signal("server_error"):
			node.server_error.connect(func(message: String) -> void: print("late wire refusal: ", message)))
	_run.call_deferred()

func _finalize() -> void:
	MouseCapture.release()
	if is_instance_valid(owned):
		owned.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_late_campaign_local: " + message)

func _until(condition: Callable, message: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 25000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	if not passed:
		print("late lifecycle: scene=", current_scene.name if current_scene != null else "none", " selected=", owned.mission, " state=", owned.state, " error=", owned.error_key)
	if not passed and current_scene != null and current_scene.has_method("change_role"):
		print("late entry diagnostics: map=", current_scene.current_map_id, " geometry=", current_scene.net_client.mission_geometry.get("id"), " mission=", current_scene.net_client.mission, " opening=", is_instance_valid(current_scene.opening), " local=", owned.state, " error=", owned.error_key)
	_check(passed, message)
	return passed

func _run() -> void:
	var preferences := FragrSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	_check(preferences.save_to_disk() == OK, "isolated settings")
	owned = LocalMatch.for_tree(self)
	for mission: String in [MissionState.M15_ID, MissionState.M16_ID, MissionState.M17_ID, MissionState.M18_ID]:
		_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "actual boot scene")
		await process_frame
		await process_frame
		current_scene._start_development(mission)
		if not await _until(func() -> bool: return current_scene != null and current_scene.has_method("change_role") and current_scene.net_client.mission_geometry.get("id") == mission and is_instance_valid(current_scene.opening), mission + " owned entry and reader page"):
			quit(1)
			return
		var game: Node = current_scene
		_check(game._mission_map() and game.controls_blocked(), "accepted mission waits for readiness")
		_check(game.net_client.mission.get("state", {}).get("phase") == "briefing", "server remains in briefing")
		game.opening._skip.pressed.emit()
		if not await _until(func() -> bool: return current_scene != null and current_scene.has_method("change_role") and current_scene.net_client.mission.get("state", {}).get("phase") == "in_progress" and not current_scene.controls_blocked(), mission + " reader dismissal reaches live play"):
			quit(1)
			return
		var initial: int = int(game.latest_snapshot.get("tick", 0))
		await _until(func() -> bool: return current_scene != null and current_scene.has_method("change_role") and int(current_scene.latest_snapshot.get("tick", 0)) >= initial + 5, "successive snapshots remain accepted")
		_check(not owned.has_durable_run(), "practice cannot replace the saved run")
		game.pause_menu.leave_requested.emit()
		await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE and current_scene != null and current_scene.has_method("_start_development"), "exit returns to menu and stops the owned child")
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	if failures == 0:
		print("test_late_campaign_local: PASS")
	quit(0 if failures == 0 else 1)
