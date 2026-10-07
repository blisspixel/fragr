extends SceneTree

var failures: int = 0
var settings_path: String
var run_directory: String
const RUN_ID: String = "40000000-0000-4000-8000-000000000008"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://m08-local-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	run_directory = ProjectSettings.globalize_path("user://m08-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	call_deferred("_run")

func _finalize() -> void:
	Input.action_release("fire")
	Input.action_release("place_mine")
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if run_directory == ProjectSettings.globalize_path("user://m08-run-%d" % OS.get_process_id()):
		for filename: String in DirAccess.get_files_at(run_directory):
			DirAccess.remove_absolute(run_directory.path_join(filename))
		DirAccess.remove_absolute(run_directory)
	OS.unset_environment("FRAGR_RUN_DIR")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m08_local: " + message)

func _until(condition: Callable, description: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 25000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	_check(passed, description)
	if not passed:
		quit(1)
	return passed

func _arrived() -> bool:
	return current_scene != null and current_scene.has_method("change_role") and current_scene.current_map_id == 1008 \
		and is_instance_valid(current_scene.opening) and not current_scene.mission_hud.state.is_empty()

func _playing() -> bool:
	return current_scene != null and current_scene.has_method("change_role") \
		and current_scene.mission_hud.state.get("phase") == "in_progress" and not current_scene.controls_blocked()

func _gear() -> Dictionary:
	return current_scene.net_client.equipment if current_scene != null and current_scene.has_method("change_role") else {}

func _run() -> void:
	var preferences: FragrSettings = FragrSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	_check(preferences.save_to_disk() == OK, "isolated settings saved")
	_check(DirAccess.make_dir_recursive_absolute(run_directory) == OK, "isolated run prepared")
	var digest: PackedByteArray = FileAccess.get_sha256("res://../server/maps/m07_declared_goods.json").hex_decode()
	var hash: Array[int] = []
	for byte: int in digest:
		hash.append(byte)
	_check(hash.size() == 32, "historical exit binds actual M07 authored bytes")
	var fixture: Dictionary = {
		"version": 8, "id": RUN_ID, "starting_continues": 3, "remaining_continues": 1,
		"level_start_continues": 1, "body": "synthetic", "rules": {"difficulty": "standard", "revision": 3}, "content_sha256": hash,
		"m03_outcome": {"liberated_cars": ["roof_car"]},
		"m04_outcome": {"rescued_patients": ["edda_team_a"], "photos_completed": 2},
		"m05_outcome": {"released_workers": ["workshop_agent_b", "splice", "workshop_agent_a"], "evacuated_workers": ["splice"]},
		"m06_outcome": {"prisoner_route_marked": true},
		"step": {"kind": "awaiting_mission", "completed_mission": "declared_goods", "next_mission": "custodian_of_record",
			"exit": {"hp": 15, "armor": 0, "equipment": {"selected": "sniper", "weapons": ["fists", "flechette", "scatter", "sniper"],
				"ammo": [{"pool": "bullets", "rounds": 76}, {"pool": "shells", "rounds": 32}, {"pool": "cells", "rounds": 1}],
				"grenades": 1, "personal_claims": ["post_sniper"]}}}}
	var source: String = JSON.stringify(fixture) + "\n  \n"
	var expected: Variant = JSON.parse_string(source)
	_write_run(source)
	var owned: LocalMatch = LocalMatch.for_tree(self)
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "boot loads")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "awaiting_mission", "actual read-only preview accepts the M07 edge"):
		return
	_check(owned.run_preview["mission"] == MissionState.M08_ID and int(owned.run_preview["continues"]) == 1, "preview names M08 with retained allowance")
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == source, "preview preserves exact v8 source bytes")
	var resume: Button = current_scene._root.get_node_or_null("CustodianOfRecordSaved") as Button
	_check(resume != null and not resume.disabled, "M08 saved continuation offers a real launch")
	if resume == null:
		quit(1)
		return
	resume.pressed.emit()
	if not await _until(_arrived, "owned M08 child reaches its actual map and arrival"):
		return
	var game: Node = current_scene
	_check(owned.has_durable_run() and game.opening.scene["id"] == StoryScene.BEFORE_MISSION[MissionState.M08_ID], "M08 is a durable arrival, with its own story scene")
	Input.action_press("fire")
	game.opening._skip.pressed.emit()
	await create_timer(0.2).timeout
	_check(game.mission_hud.state["phase"] == "briefing", "held arrival fire cannot acknowledge or spend the last Cell")
	Input.action_release("fire")
	if not await _until(_playing, "released arrival acknowledges the actual M08 attempt"):
		return
	if not await _until(func() -> bool: return not _gear().is_empty(), "carried private loadout arrives"):
		return
	var gear: Dictionary = _gear()
	_check(gear["selected"] == "sniper" and EquipmentState.ammo(gear, "cells") == 1 and int(gear.get("proximity_mines", 0)) == 0, "Sniper and last Cell carry, historical mines become zero")
	_check(gear["personal_claims"].is_empty() and int(gear["grenades"]) == 1, "old claims clear while grenades remain independent")
	_check(game.mission_hud.state["run"]["id"] == RUN_ID and int(game.mission_hud.state["run"]["continues"]) == 1, "M08 never refills Episode II")
	_check(game.net_client.accepted_body == "synthetic", "saved body wins over the current profile")
	if not await _stop(owned):
		return
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(run_directory.path_join("run.json")))
	_check(saved is Dictionary and saved["version"] == 14 and saved["step"]["mission"] == MissionState.M08_ID, "child atomically writes current M08 entry")
	if not saved is Dictionary:
		quit(1)
		return
	var entry: Dictionary = saved["step"]["entry"]
	_check(int(entry["hp"]) == 15 and int(entry["armor"]) == 0 and int(entry["equipment"]["proximity_mines"]) == 0, "actual entry does not heal or invent mines")
	for outcome: String in ["m03_outcome", "m04_outcome", "m05_outcome", "m06_outcome"]:
		_check(expected is Dictionary and saved[outcome] == expected[outcome], "M08 retains " + outcome)
	var archives: Array[String] = []
	for filename: String in DirAccess.get_files_at(run_directory):
		if filename.begins_with("run.prior-"):
			archives.append(filename)
	_check(archives.size() == 1 and FileAccess.get_file_as_string(run_directory.path_join(archives[0])) == source, "single archive contains exact v8 bytes")
	# Reopen a valid M08 entry with a finite mine anchor. Stopping after placing
	# one must persist the mission entry, never the live mid-fight inventory.
	var saved_bytes: String = FileAccess.get_file_as_string(run_directory.path_join("run.json"))
	var count_pattern: RegEx = RegEx.new()
	_check(count_pattern.compile('"proximity_mines":\\s*0') == OK, "finite anchor pattern is valid")
	_check(count_pattern.search_all(saved_bytes).size() == 1, "one mine anchor is available")
	_write_run(count_pattern.sub(saved_bytes, '"proximity_mines":3'))
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "saved M08 entry boot loads")
	await process_frame
	await process_frame
	owned.run_preview.clear()
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "ready", "actual preview reopens M08 entry"):
		return
	resume = current_scene._root.get_node_or_null("CustodianOfRecordSaved") as Button
	_check(resume != null, "M08 entry still exposes Continue Run")
	if resume == null:
		quit(1)
		return
	resume.pressed.emit()
	if not await _until(_playing, "existing M08 entry resumes without replaying arrival"):
		return
	if not await _until(func() -> bool: return int(_gear().get("proximity_mines", -1)) == 3, "disk mine count reaches actual loadout"):
		return
	game = current_scene
	if not await _until(func() -> bool: return game._has_local_input_target() and game.place_armed, "actual resumed pawn input is armed before a fresh mine press"):
		return
	Input.action_press("place_mine")
	if not await _until(func() -> bool: return int(_gear().get("proximity_mines", -1)) == 2, "ordinary input consumes one actual finite mine"):
		return
	Input.action_release("place_mine")
	_check(int(_gear()["grenades"]) == 1, "mine placement preserves grenade count")
	if not await _stop(owned):
		return
	var reopened: Variant = JSON.parse_string(FileAccess.get_file_as_string(run_directory.path_join("run.json")))
	_check(reopened is Dictionary and int(reopened["step"]["entry"]["equipment"]["proximity_mines"]) == 3, "saved retry anchor retains entry mines rather than spent live count")
	if failures == 0:
		print("test_m08_local: PASS v8 exact archive, M07-M08 carry, owned child, finite mines and saved entry anchor")
	quit(0 if failures == 0 else 1)

func _write_run(bytes: String) -> void:
	var file: FileAccess = FileAccess.open(run_directory.path_join("run.json"), FileAccess.WRITE)
	_check(file != null, "isolated run is writable")
	if file != null:
		file.store_string(bytes)
		file.close()

func _stop(owned: LocalMatch) -> bool:
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "owned M08 child exits cleanly"):
		return false
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	return true
