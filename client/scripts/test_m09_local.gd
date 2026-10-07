extends SceneTree

const RUN_ID: String = "40000000-0000-4000-8000-000000000009"
var failures: int = 0
var run_directory: String = ""
var settings_path: String = ""

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://m09-local-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	run_directory = ProjectSettings.globalize_path("user://m09-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	_run.call_deferred()

func _finalize() -> void:
	Input.action_release("fire")
	Input.action_release("place_mine")
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if run_directory == ProjectSettings.globalize_path("user://m09-run-%d" % OS.get_process_id()):
		for filename: String in DirAccess.get_files_at(run_directory):
			DirAccess.remove_absolute(run_directory.path_join(filename))
		DirAccess.remove_absolute(run_directory)
	OS.unset_environment("FRAGR_RUN_DIR")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m09_local: " + message)

func _until(condition: Callable, message: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 25000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		if current_scene != null and current_scene.has_method("change_role") and current_scene.net_client != null \
			and not current_scene.net_client.has_meta("m09_failure_observer"):
			current_scene.net_client.set_meta("m09_failure_observer", true)
			current_scene.net_client.server_error.connect(func(text: String) -> void: print("test_m09_local: server boundary refusal: ", text))
		await process_frame
	var passed: bool = condition.call()
	_check(passed, message)
	if not passed:
		if current_scene != null and current_scene.has_method("change_role"):
			print("test_m09_local: observed map ", current_scene.current_map_id, " geometry ", current_scene.net_client.mission_geometry.get("id"), " mission ", current_scene.net_client.mission)
		quit(1)
	return passed

func _playing() -> bool:
	return current_scene != null and current_scene.has_method("change_role") \
		and current_scene.mission_hud.state.get("phase") == "in_progress" and not current_scene.controls_blocked()

func _gear() -> Dictionary:
	return current_scene.net_client.equipment if current_scene != null and current_scene.has_method("change_role") else {}

func _run() -> void:
	var preferences: FragrSettings = FragrSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	_check(preferences.save_to_disk() == OK, "isolated settings save")
	_check(DirAccess.make_dir_recursive_absolute(run_directory) == OK, "isolated run directory")
	var hash: Array[int] = []
	for byte: int in FileAccess.get_sha256("res://../server/maps/m08_custodian_of_record.json").hex_decode():
		hash.append(byte)
	_check(hash.size() == 32, "strict historical completion binds actual archive bytes")
	var fixture: Dictionary = {"version": 9, "id": RUN_ID, "starting_continues": 3, "remaining_continues": 1, "level_start_continues": 1,
		"body": "synthetic", "rules": {"difficulty": "standard", "revision": 3}, "content_sha256": hash,
		"m03_outcome": {"liberated_cars": ["roof_car"]}, "m04_outcome": {"rescued_patients": ["edda_team_a"], "photos_completed": 2},
		"m05_outcome": {"released_workers": ["splice", "workshop_agent_a", "workshop_agent_b"], "evacuated_workers": ["splice"]}, "m06_outcome": {"prisoner_route_marked": true},
		"step": {"kind": "awaiting_mission", "completed_mission": "custodian_of_record", "next_mission": "passenger_manifest",
			"exit": {"hp": 39, "armor": 17, "equipment": {"selected": "sniper", "weapons": ["fists", "flechette", "scatter", "sniper"],
				"ammo": [{"pool": "bullets", "rounds": 76}, {"pool": "shells", "rounds": 32}, {"pool": "cells", "rounds": 1}], "grenades": 2, "proximity_mines": 3, "personal_claims": ["cold_cabinet"]}}}}
	var source: String = JSON.stringify(fixture) + "\n  \n"
	var file: FileAccess = FileAccess.open(run_directory.path_join("run.json"), FileAccess.WRITE)
	_check(file != null, "isolated source is writable")
	if file == null:
		quit(1)
		return
	file.store_string(source)
	file.close()
	file = null
	var owned: LocalMatch = LocalMatch.for_tree(self)
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "boot scene loads")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "awaiting_mission", "actual preview reads M08 completion"):
		return
	_check(owned.run_preview.get("mission") == MissionState.M09_ID, "preview names supported M09")
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == source, "preview preserves exact v9 bytes")
	var resume: Button = current_scene._root.get_node_or_null("PassengerManifestSaved") as Button
	_check(resume != null and not resume.disabled, "real saved-run berth button")
	if resume == null:
		quit(1)
		return
	resume.pressed.emit()
	if not await _until(func() -> bool: return current_scene != null and current_scene.has_method("change_role") and current_scene.current_map_id == 1009 and is_instance_valid(current_scene.opening), "matching private child reaches actual berth arrival"):
		return
	var game: Node = current_scene
	Input.action_press("fire")
	game.opening._skip.pressed.emit()
	await create_timer(0.2).timeout
	_check(game.mission_hud.state.get("phase") == "briefing", "held dismissal fire cannot acknowledge or spend the last Cell")
	Input.action_release("fire")
	if not await _until(_playing, "released dismissal uses existing readiness boundary"):
		return
	if not await _until(func() -> bool: return not _gear().is_empty(), "actual carried loadout arrives"):
		return
	_check(_gear()["selected"] == "sniper" and EquipmentState.ammo(_gear(), "cells") == 1 and _gear()["grenades"] == 2 and _gear()["proximity_mines"] == 3, "finite counts and selected weapon carry without refill")
	_check(_gear()["personal_claims"].is_empty() and game.net_client.accepted_body == "synthetic", "old claims clear while saved body persists")
	_check(game.mission_hud.state["m09"]["carried_archive"] == {"kind": "historical_unrecorded"} and game.m09_berth._crew.size() == 5, "unknown archive choices and actual conditional cast remain honest")
	_check(game.mission_hud.state["run"]["continues"] == 1, "no Episode II refill")
	if not await _until(func() -> bool: return game._has_local_input_target() and game.place_armed, "actual pawn input is armed after the story release frame"):
		return
	Input.action_press("place_mine")
	if not await _until(func() -> bool: return _gear().get("proximity_mines") == 2, "ordinary input spends one actual mine"):
		return
	Input.action_release("place_mine")
	_check(_gear()["grenades"] == 2, "mine does not spend a grenade")
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "owned native child exits"):
		return
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(run_directory.path_join("run.json")))
	_check(saved is Dictionary and saved["version"] == 14 and saved["step"]["mission"] == MissionState.M09_ID, "locked writer stores current M09 entry")
	_check(saved is Dictionary and saved["step"]["entry"]["hp"] == 39 and saved["step"]["entry"]["armor"] == 17 and saved["step"]["entry"]["equipment"]["proximity_mines"] == 3, "retry anchor is exact entry, never spent live inventory")
	_check(saved is Dictionary and saved["m08_outcome"] == {"kind": "historical_unrecorded"}, "unknown history persists on disk")
	var archives: Array[String] = []
	for filename: String in DirAccess.get_files_at(run_directory):
		if filename.begins_with("run.prior-"):
			archives.append(filename)
	_check(archives.size() == 1 and FileAccess.get_file_as_string(run_directory.path_join(archives[0])) == source, "migration archive is exact historical source")
	# Reopen a strict v11 M09 entry through the actual saved-run process path.
	# Its absent crew outcome is an unfinished mission, never a guessed rescue.
	if not saved is Dictionary:
		quit(1)
		return
	# Preserve native integer literals: parsing and stringifying them here
	# would turn strict integer fields into floating-point JSON numbers.
	var native_source: String = FileAccess.get_file_as_string(run_directory.path_join("run.json"))
	_check(native_source.count('"version":14,') == 1, "native current version marker is unique")
	var retry_source: String = native_source.replace('"version":14,', '"version":11,') + "\n \n"
	file = FileAccess.open(run_directory.path_join("run.json"), FileAccess.WRITE)
	_check(file != null, "owned historical M09 retry fixture is writable after child exit")
	if file == null:
		quit(1)
		return
	file.store_string(retry_source)
	file.close()
	file = null
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "real retry boot scene")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "ready" and owned.run_preview.get("mission") == MissionState.M09_ID, "actual preview recognizes strict v11 M09 entry"):
		print("test_m09_local: retry preview ", owned.run_preview, " owned state ", owned.state)
		return
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == retry_source, "preview never rewrites v11 retry bytes")
	resume = current_scene._root.get_node_or_null("PassengerManifestSaved") as Button
	_check(resume != null and not resume.disabled, "real M09 retry button remains available")
	if resume == null:
		quit(1)
		return
	resume.pressed.emit()
	if not await _until(func() -> bool: return current_scene != null and current_scene.has_method("change_role") and current_scene.current_map_id == 1009, "fresh owned child reaches actual M09 retry"):
		return
	game = current_scene
	_check(game._opening_finished and not is_instance_valid(game.opening), "ordinary saved mission retry does not replay its arrival")
	if not await _until(_playing, "retry uses the existing server readiness boundary"):
		return
	if not await _until(func() -> bool: return not _gear().is_empty(), "retry loadout acknowledgement"):
		return
	_check(_gear()["proximity_mines"] == 3 and _gear()["grenades"] == 2 and EquipmentState.ammo(_gear(), "cells") == 1, "actual retry restores its anchor without ammo or explosive refill")
	_check(game.mission_hud.state["run"]["continues"] == 1 and game.net_client.accepted_body == "synthetic", "reopen preserves allowance and body")
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "reopened owned child exits cleanly"):
		return
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	var retry_saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(run_directory.path_join("run.json")))
	_check(retry_saved is Dictionary and retry_saved["version"] == 14 and not retry_saved.has("m09_outcome"), "native current unfinished retry never records departure crew")
	_check(retry_saved is Dictionary and retry_saved["step"]["entry"] == saved["step"]["entry"], "strict v11 real-process retry preserves every entry count")
	archives.clear()
	for filename: String in DirAccess.get_files_at(run_directory):
		if filename.begins_with("run.prior-"):
			archives.append(filename)
	var exact_retry_archive: bool = false
	for filename: String in archives:
		exact_retry_archive = exact_retry_archive or FileAccess.get_file_as_string(run_directory.path_join(filename)) == retry_source
	_check(archives.size() == 2 and exact_retry_archive, "actual process archives exact v11 bytes once")
	if failures == 0:
		print("test_m09_local: PASS")
	quit(0 if failures == 0 else 1)
