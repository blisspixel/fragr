extends SceneTree

## Actual development and saved transition, owned children and arrival barriers.
var failures: int = 0
var settings_path: String
var run_directory: String
const PRIOR_BYTES: String = "prior personal run bytes retained by development launch\n"
const RUN_ID: String = "40000000-0000-4000-8000-000000000007"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://m07-local-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	run_directory = ProjectSettings.globalize_path("user://m07-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	call_deferred("_run")

func _finalize() -> void:
	Input.action_release("fire")
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	# Only this process's isolated directory and flat files are disposable.
	var expected: String = ProjectSettings.globalize_path("user://m07-run-%d" % OS.get_process_id())
	if run_directory == expected:
		for filename: String in DirAccess.get_files_at(run_directory):
			DirAccess.remove_absolute(run_directory.path_join(filename))
		DirAccess.remove_absolute(run_directory)
	OS.unset_environment("FRAGR_RUN_DIR")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m07_local: " + message)

func _until(condition: Callable, description: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 25000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	_check(passed, description)
	if not passed:
		print("test_m07_local: child ", LocalMatch.for_tree(self).state, " error ", LocalMatch.for_tree(self).error_key)
		quit(1)
	return passed

func _arrived() -> bool:
	return current_scene != null and current_scene.has_method("change_role") and current_scene.current_map_id == 1007 \
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
	(current_scene._root.get_node("DevelopmentMission") as OptionButton).select(5)
	var entry: Button = current_scene._root.get_node_or_null("LaunchDevelopmentMission") as Button
	_check(entry != null and not entry.disabled, "labeled M07 development entry is selectable")
	if entry == null:
		quit(1)
		return
	entry.pressed.emit()
	if not await _until(_arrived, "owned development child reaches the M07 reader-paced arrival"):
		return
	var owned: LocalMatch = LocalMatch.for_tree(self)
	var game: Node = current_scene
	_check(owned.mission == MissionState.M07_ID and not owned.has_durable_run(), "actual M07 child uses development mode")
	_check(game.opening.scene["id"] == StoryScene.BEFORE_MISSION[MissionState.M07_ID] and game.controls_blocked(), "M07 uses its own story scene and shared input barrier")
	_check(game.mission_hud.state["phase"] == "briefing" and not game.mission_hud.state["party"][0]["ready"], "server remains in briefing while the player reads")
	# Dismissing while fire is held must not acknowledge or shoot into the level.
	Input.action_press("fire")
	game.opening._skip.pressed.emit()
	await create_timer(0.2).timeout
	_check(game.mission_hud.state["phase"] == "briefing" and game.controls_blocked(), "arrival dismissal waits for held gameplay input to release")
	Input.action_release("fire")
	if not await _until(_playing, "release acknowledges M07 through the shared readiness wire"):
		return
	var state: Dictionary = game.mission_hud.state
	_check(not state.has("run") and state["m07"]["completed"].is_empty() and state["m07"]["current"]["id"] == "ring_cleared", "development M07 starts at the curfew patrol without a durable run")
	_check(state["m07"]["current"]["action"]["kind"] == "arrival" and game.pending_interact == false, "authoritative first goal is Arrival and arrival input leaves no use press")
	var town: M07Town = game.m07_town
	_check(town._root != null and town.lamps.size() == 7 and town.lamps_lit_count == 0 and town.figure != null,
		"the real town presents seven dark curfew lamps and the window figure")
	_check(town._root.find_child("DepotRadialTower", true, false) != null and town.chime_count >= 1, "the depot tower stands and the curfew chime has rung")
	_check(game.current_map_info["map_name"] == "Declared Goods", "the bundled town map is loaded")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and game.mouse_capture.desired_mode() == Input.MOUSE_MODE_VISIBLE,
		"automated local launch never captures the desktop")
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == PRIOR_BYTES,
		"actual development child preserves existing personal run bytes")
	var pause: PauseMenu = game.get_node("PauseMenu")
	pause.open()
	_check(pause._note.text == tr("MENU_EXIT_DEVELOPMENT"), "development menu never promises a save")
	pause.close()
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "owned M07 child stops cleanly"):
		return
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == PRIOR_BYTES, "stopping development preserves the same save bytes")
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	await process_frame
	if not await _saved_transition(owned):
		return
	if failures == 0:
		print("test_m07_local: PASS development isolation, town presentation and v7 saved M06-M07 carry without refill, v9 archive and owned cleanup")
	quit(0 if failures == 0 else 1)

func _saved_transition(owned: LocalMatch) -> bool:
	var hash: String = FileAccess.get_sha256(ProjectSettings.globalize_path("res://../server/maps/m06_port_of_entry.json"))
	var digest: Array[int] = []
	for index: int in range(0, hash.length(), 2):
		digest.append(hash.substr(index, 2).hex_to_int())
	_check(digest.size() == 32, "version 7 fixture binds actual current M06 content")
	var fixture: Dictionary = {
		"version": 7, "id": RUN_ID, "starting_continues": 3, "remaining_continues": 1,
		"level_start_continues": 3, "body": "human", "rules": {"difficulty": "severe", "revision": 3},
		"content_sha256": digest, "m03_outcome": {"liberated_cars": ["platform_car", "roof_car"]},
		"m04_outcome": {"rescued_patients": ["edda_team_a"], "photos_completed": 2},
		"m05_outcome": {"released_workers": ["workshop_agent_b", "splice", "workshop_agent_a"], "evacuated_workers": ["workshop_agent_a", "splice"]},
		"m06_outcome": {"prisoner_route_marked": true},
		"step": {"kind": "awaiting_mission", "completed_mission": "port_of_entry", "next_mission": "declared_goods",
			"exit": {"hp": 54, "armor": 12, "equipment": {"selected": "rail", "weapons": ["fists", "flechette", "scatter", "rail"],
				"ammo": [{"pool": "bullets", "rounds": 41}, {"pool": "shells", "rounds": 6}, {"pool": "cells", "rounds": 9}],
				"grenades": 1, "personal_claims": ["customs_cells"]}}}}
	var legacy_bytes: String = JSON.stringify(fixture) + "\n"
	var legacy: FileAccess = FileAccess.open(run_directory.path_join("run.json"), FileAccess.WRITE)
	_check(legacy != null, "isolated compatible version 7 transition is writable")
	if legacy == null:
		quit(1)
		return false
	legacy.store_string(legacy_bytes)
	legacy.close()
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "saved transition boot menu loads")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "awaiting_mission", "real preview accepts the pending M06-M07 save"):
		return false
	var preview: Dictionary = owned.run_preview
	_check(preview["mission"] == MissionState.M07_ID and preview["body"] == "human" and int(preview["continues"]) == 1,
		"preview retains destination, body and the episode's remaining continues")
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == legacy_bytes, "read-only menu preview preserves exact version 7 bytes")
	var resume: Button = current_scene._root.get_node_or_null("DeclaredGoodsSaved") as Button
	_check(resume != null and not resume.disabled, "saved M07 transition offers its actual resume button")
	if resume == null:
		quit(1)
		return false
	resume.pressed.emit()
	if not await _until(_arrived, "pending saved transition plays the M07 arrival before readiness"):
		return false
	var game: Node = current_scene
	_check(owned.has_durable_run() and game.opening.scene["id"] == StoryScene.BEFORE_MISSION[MissionState.M07_ID],
		"pending resume retains durable mode and reader scene")
	Input.action_press("fire")
	game.opening._skip.pressed.emit()
	await create_timer(0.2).timeout
	_check(game.mission_hud.state["phase"] == "briefing" and game.controls_blocked(), "saved arrival dismissal consumes held fire")
	Input.action_release("fire")
	if not await _until(_playing, "saved arrival release acknowledges the current attempt once"):
		return false
	if not await _until(func() -> bool: return not game.net_client.equipment.is_empty() and not _local_player(game).is_empty(), "carried private gear and authoritative body reach the client"):
		return false
	var state: Dictionary = game.mission_hud.state
	var player: Dictionary = _local_player(game)
	var equipment: Dictionary = game.net_client.equipment
	_check(state["run"]["id"] == RUN_ID and int(state["run"]["continues"]) == 1 \
		and int(state["run"]["level_start_continues"]) == 1 and int(state["attempt"]) == 1,
		"M07 keeps the episode's continues with no refill: " + JSON.stringify(state["run"]))
	_check(state["m07"]["carried_prisoner_route_marked"] == true, "the M06 route outcome reaches the town wire")
	_check(state["m07"]["carried_recall_cars"] == ["platform_car", "roof_car"] and state["m07"]["carried_patients"] == ["edda_team_a"]
		and state["m07"]["carried_released_workers"] == fixture["m05_outcome"]["released_workers"], "earlier outcomes ride along unchanged")
	_check(int(player["hp"]) == 54 and int(player["armor"]) == 12 and game.net_client.accepted_body == "human", "actual HP, armor and body carry exactly")
	_check(equipment["selected"] == "rail" and equipment["weapons"] == ["fists", "flechette", "scatter", "rail"] and int(equipment["grenades"]) == 1,
		"actual carried guns, selection and grenades are exact")
	_check(EquipmentState.ammo(equipment, "bullets") == 41 and EquipmentState.ammo(equipment, "shells") == 6 and EquipmentState.ammo(equipment, "cells") == 9,
		"held arrival fire never consumes carried ammunition: " + JSON.stringify(equipment))
	_check(equipment["personal_claims"].is_empty(), "old port claims retire on entry")
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "durable owned M07 child stops cleanly before inspecting disk"):
		return false
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(run_directory.path_join("run.json")))
	_check(saved is Dictionary and saved["version"] == 12 and saved["id"] == RUN_ID, "actual child atomically persists the current run")
	if saved is Dictionary:
		_check(saved["step"]["kind"] == "mission_entry" and saved["step"]["mission"] == MissionState.M07_ID \
			and saved["m06_outcome"] == fixture["m06_outcome"] and saved["m05_outcome"] == fixture["m05_outcome"] \
			and int(saved["remaining_continues"]) == 1 and int(saved["level_start_continues"]) == 1,
			"current entry retains every outcome and the unrefilled baseline: " + JSON.stringify(saved))
	var archives: Array[String] = []
	for filename: String in DirAccess.get_files_at(run_directory):
		if filename.begins_with("run.prior-") and filename.ends_with(".json"):
			archives.append(filename)
	_check(archives.size() == 1, "the upgrade creates exactly one prior archive")
	if archives.size() == 1:
		_check(FileAccess.get_file_as_string(run_directory.path_join(archives[0])) == legacy_bytes, "archive preserves the exact version 7 bytes")
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	return true

func _local_player(game: Node) -> Dictionary:
	for player: Dictionary in game.latest_snapshot.get("players", []):
		if player.get("id") == game.net_client.player_id:
			return player
	return {}
