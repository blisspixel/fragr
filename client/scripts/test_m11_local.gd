extends SceneTree

const RUN_ID: String = "40000000-0000-4000-8000-000000000011"
var failures: int = 0
var run_directory: String = ""
var settings_path: String = ""

## Representative historical bytes isolate M11 entry. This is not M10 play evidence.
static func completed_ship() -> Dictionary:
	var hash: Array[int] = []
	for byte: int in FileAccess.get_sha256("res://../server/maps/m10_common_carrier.json").hex_decode():
		hash.append(byte)
	return {"version": 13, "id": RUN_ID, "starting_continues": 3, "remaining_continues": 1, "level_start_continues": 3,
		"body": "synthetic", "rules": {"difficulty": "standard", "revision": 3}, "content_sha256": hash,
		"m03_outcome": {"liberated_cars": ["roof_car"]}, "m04_outcome": {"rescued_patients": ["edda_team_a"], "photos_completed": 2},
		"m05_outcome": {"released_workers": ["splice", "workshop_agent_a", "workshop_agent_b"], "evacuated_workers": ["splice"]},
		"m06_outcome": {"prisoner_route_marked": true},
		"m08_outcome": {"kind": "recorded", "custody_released": true, "recovered_mind_secured": true, "captives_evacuated": true},
		"m09_outcome": {"kind": "recorded", "released_crew": ["tern", "berth_crew_a", "berth_crew_b", "edda", "splice"], "aboard_at_departure": ["tern", "berth_crew_a", "berth_crew_b"]},
		"m10_transit": {"kind": "recorded", "arrived_crew": ["tern", "berth_crew_a", "berth_crew_b", "edda", "splice"]},
		"step": {"kind": "awaiting_mission", "completed_mission": "common_carrier", "next_mission": "right_of_search",
			"exit": {"hp": 43, "armor": 22, "equipment": {"selected": "flechette", "weapons": ["fists", "flechette", "scatter", "sniper"],
				"ammo": [{"pool": "bullets", "rounds": 100}, {"pool": "shells", "rounds": 32}, {"pool": "cells", "rounds": 8}],
				"grenades": 2, "proximity_mines": 3, "personal_claims": ["m10_actual_find"]}}}}

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://m11-local-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	set_meta("fragr_records_path", "user://m11-records-%d" % OS.get_process_id())
	run_directory = ProjectSettings.globalize_path("user://m11-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	_run.call_deferred()

func _finalize() -> void:
	QaCombat.release_inputs()
	for action: String in ["fire", "place_remote_mine", "trigger_remote_mines"]:
		Input.action_release(action)
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if run_directory == ProjectSettings.globalize_path("user://m11-run-%d" % OS.get_process_id()):
		for filename: String in DirAccess.get_files_at(run_directory):
			DirAccess.remove_absolute(run_directory.path_join(filename))
		DirAccess.remove_absolute(run_directory)
	OS.unset_environment("FRAGR_RUN_DIR")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m11_local: " + message)

func _until(condition: Callable, message: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 25000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		if current_scene != null and current_scene.has_method("change_role") and current_scene.net_client != null and not current_scene.net_client.has_meta("m11_observer"):
			current_scene.net_client.set_meta("m11_observer", true)
			current_scene.net_client.server_error.connect(func(text: String) -> void: print("test_m11_local: boundary refusal: ", text))
		await process_frame
	var passed: bool = condition.call()
	_check(passed, message)
	if not passed:
		print("test_m11_local: preview ", LocalMatch.for_tree(self).run_preview, " state ", LocalMatch.for_tree(self).state)
		if current_scene != null and current_scene.has_method("change_role"):
			print("test_m11_local: observed ", current_scene.current_map_id, " ", current_scene.net_client.mission)
		LocalMatch.for_tree(self).stop()
		quit(1)
	return passed

func _playing() -> bool:
	return current_scene != null and current_scene.has_method("change_role") and current_scene.mission_hud.state.get("phase") == "in_progress" and not current_scene.controls_blocked()

func _gear() -> Dictionary:
	return current_scene.net_client.equipment if current_scene != null and current_scene.has_method("change_role") else {}

func _walk(game: Node, route: Array) -> bool:
	var next: int = 0
	var deadline: int = Time.get_ticks_msec() + 18000
	while next < route.size() and Time.get_ticks_msec() < deadline:
		var me: Dictionary = QaCombat.actor_by_id(game.latest_snapshot, str(game.net_client.player_id))
		QaCombat.release_inputs()
		if not me.is_empty():
			next = QaCombat.follow_route(me, game.get_node("SpectatorCamera"), route, next)
		await create_timer(0.05).timeout
	QaCombat.release_inputs()
	if next < route.size():
		print("test_m11_local: route stopped at ", QaCombat.actor_by_id(game.latest_snapshot, str(game.net_client.player_id)), " target ", route[next])
	_check(next == route.size(), "ordinary movement reaches armory")
	return next == route.size()

func _run() -> void:
	var preferences: FragrSettings = FragrSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	_check(preferences.save_to_disk() == OK, "isolated settings")
	_check(DirAccess.make_dir_recursive_absolute(run_directory) == OK, "isolated run directory")
	var fixture: Dictionary = completed_ship()
	var source: String = JSON.stringify(fixture) + "\n  \n"
	var file: FileAccess = FileAccess.open(run_directory.path_join("run.json"), FileAccess.WRITE)
	_check(file != null, "historical fixture writable")
	if file == null:
		quit(1)
		return
	file.store_string(source)
	file.close()
	var owned: LocalMatch = LocalMatch.for_tree(self)
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "real boot menu")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "awaiting_mission", "actual preview reads M10 completion"):
		return
	_check(owned.run_preview.get("mission") == MissionState.M11_ID, "preview names M11")
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == source, "preview preserves exact historical bytes")
	var resume: Button = current_scene._root.get_node_or_null("RightOfSearchSaved") as Button
	_check(resume != null and not resume.disabled, "real saved tender button")
	if resume == null:
		quit(1)
		return
	resume.pressed.emit()
	if not await _until(func() -> bool: return current_scene != null and current_scene.has_method("change_role") and current_scene.current_map_id == 1011 and is_instance_valid(current_scene.opening), "actual owned child reaches tender arrival"):
		return
	var game: Node = current_scene
	Input.action_press("fire")
	game.opening._skip.pressed.emit()
	await create_timer(0.2).timeout
	_check(game.mission_hud.state.get("phase") == "briefing", "held story dismissal cannot fire or ready")
	Input.action_release("fire")
	if not await _until(_playing, "release uses canonical readiness") or not await _until(func() -> bool: return not _gear().is_empty(), "actual entry equipment"):
		return
	_check(_gear()["selected"] == "flechette" and EquipmentState.ammo(_gear(), "bullets") == 100 and _gear()["grenades"] == 2 and _gear()["proximity_mines"] == 3 and _gear().get("remote_mines", 0) == 0, "finite historical carry upgrades with zero invented remote charges")
	_check(_gear()["personal_claims"].is_empty() and game.net_client.accepted_body == "synthetic", "old claims clear and actual saved body remains")
	_check(game.mission_hud.state["run"]["continues"] == 1, "M11 has no Episode III refill")
	_check(game.m11_tender._people.size() == 3, "actual map presents three anonymous transfer people")
	_check(game.arena_cover.get_node("Backdrop").get_child_count() == 0 and not game.arena_cover.get_node("MapFloor").visible, "sealed tender uses its actual interior")
	if not await _walk(game, [[-16.0, 0.3, -26.5], [-9.0, 0.3, -26.5], [-4.0, 0.3, -26.5], [-4.0, 0.3, -25.0]]):
		owned.stop()
		quit(1)
		return
	if not await _until(func() -> bool: return _gear().get("remote_mines") == 4 and game.remote_place_armed, "real armory supplies four charges"):
		return
	Input.action_press("place_remote_mine")
	if not await _until(func() -> bool: return _gear().get("remote_mines") == 3, "ordinary V input spends exactly one charge"):
		return
	Input.action_release("place_remote_mine")
	if not await _until(func() -> bool: return game.latest_snapshot.get("remote_mines", []).any(func(m: Dictionary) -> bool: return m["phase"] == "armed"), "server arms actual charge after finite delay"):
		return
	Input.action_press("trigger_remote_mines")
	if not await _until(func() -> bool: return game.latest_snapshot.get("remote_mines", []).is_empty(), "ordinary H trigger resolves and retires actual device"):
		return
	Input.action_release("trigger_remote_mines")
	_check(_gear().get("remote_mines", 0) == 3 and _gear()["grenades"] == 2 and _gear()["proximity_mines"] == 3, "independent finite counts remain exact")
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "owned child exits"):
		return
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(run_directory.path_join("run.json")))
	_check(saved["version"] == 14 and saved["step"]["mission"] == MissionState.M11_ID and saved["remaining_continues"] == 1, "actual locked writer stores M11 entry without refill")
	_check(saved["step"]["entry"]["equipment"].get("remote_mines", 0) == 0 and saved["step"]["entry"]["hp"] == 43, "durable entry retains original finite counts")
	var archives: Array[String] = []
	for filename: String in DirAccess.get_files_at(run_directory):
		if filename.begins_with("run.prior-"):
			archives.append(filename)
	_check(archives.size() == 1 and FileAccess.get_file_as_string(run_directory.path_join(archives[0])) == source, "v13 archive retains exact original bytes")
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "reopen boot")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "ready" and owned.run_preview.get("mission") == MissionState.M11_ID, "preview recognizes current entry"):
		return
	resume = current_scene._root.get_node_or_null("RightOfSearchSaved") as Button
	if resume == null:
		_check(false, "saved entry has real resume button")
		quit(1)
		return
	resume.pressed.emit()
	if not await _until(func() -> bool: return current_scene != null and current_scene.has_method("change_role") and current_scene.mission_hud.state.get("run", {}).get("status") == "continue" and current_scene._continue_armed, "resolved self blast persists actual pending continue"):
		return
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = false
	Input.parse_input_event(event)
	if not await _until(_playing, "ordinary continue restores actual M11 play") or not await _until(func() -> bool: return not _gear().is_empty(), "retry inventory arrives"):
		return
	game = current_scene
	_check(game._opening_finished and not is_instance_valid(game.opening), "saved entry does not repeat arrival")
	_check(_gear().get("remote_mines", 0) == 0 and _gear()["grenades"] == 2 and game.mission_hud.state["run"]["continues"] == 0 and game.mission_hud.state["attempt"] == 2, "continue spends one allowance and restores actual finite entry")
	_check(game.latest_snapshot.get("remote_mines", []).is_empty(), "no live device survives process restart")
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "reopened owned child exits"):
		return
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	if failures == 0:
		print("test_m11_local: PASS")
	quit(0 if failures == 0 else 1)
