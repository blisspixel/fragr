extends SceneTree

## Actual development and saved transition, owned children and arrival barriers.
var failures: int = 0
var settings_path: String
var run_directory: String
const PRIOR_BYTES: String = "prior personal run bytes retained by development launch\n"
const RUN_ID: String = "40000000-0000-4000-8000-000000000004"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://m06-local-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	run_directory = ProjectSettings.globalize_path("user://m06-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	call_deferred("_run")

func _finalize() -> void:
	Input.action_release("fire")
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	# Only this process's isolated directory and flat files are disposable.
	var expected: String = ProjectSettings.globalize_path("user://m06-run-%d" % OS.get_process_id())
	if run_directory == expected:
		for filename: String in DirAccess.get_files_at(run_directory):
			DirAccess.remove_absolute(run_directory.path_join(filename))
		DirAccess.remove_absolute(run_directory)
	OS.unset_environment("FRAGR_RUN_DIR")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m06_local: " + message)

func _until(condition: Callable, description: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 25000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	_check(passed, description)
	if not passed:
		print("test_m06_local: child ", LocalMatch.for_tree(self).state, " error ", LocalMatch.for_tree(self).error_key)
		quit(1)
	return passed

func _arrived() -> bool:
	return current_scene != null and current_scene.has_method("change_role") and current_scene.current_map_id == 1006 \
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
	(current_scene._root.get_node("DevelopmentMission") as OptionButton).select(4)
	var entry: Button = current_scene._root.get_node_or_null("LaunchDevelopmentMission") as Button
	_check(entry != null and not entry.disabled, "labeled M06 development entry is selectable")
	if entry == null:
		quit(1)
		return
	entry.pressed.emit()
	if not await _until(_arrived, "owned development child reaches the M06 reader-paced arrival"):
		return
	var owned: LocalMatch = LocalMatch.for_tree(self)
	var game: Node = current_scene
	_check(owned.mission == MissionState.M06_ID and not owned.has_durable_run(), "actual M06 child uses development mode")
	_check(game.opening.scene["id"] == StoryScene.BEFORE_MISSION[MissionState.M06_ID] and game.controls_blocked(), "M06 uses its own story scene and shared input barrier")
	_check(game.mission_hud.state["phase"] == "briefing" and not game.mission_hud.state["party"][0]["ready"], "server remains in briefing while the player reads")
	# Dismissing while fire is held must not acknowledge or shoot into the level.
	Input.action_press("fire")
	game.opening._skip.pressed.emit()
	await create_timer(0.2).timeout
	_check(game.mission_hud.state["phase"] == "briefing" and game.controls_blocked(), "arrival dismissal waits for held gameplay input to release")
	Input.action_release("fire")
	if not await _until(_playing, "release acknowledges M06 through the shared readiness wire"):
		return
	var state: Dictionary = game.mission_hud.state
	_check(not state.has("run") and state["m06"]["completed"].is_empty() and not state["m06"]["prisoner_route_marked"], "development M06 starts with freight clearance without a durable run")
	_check(state["m06"]["current"]["action"]["kind"] == "arrival" and game.pending_interact == false, "authoritative first goal is Arrival and arrival input leaves no use press")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and game.mouse_capture.desired_mode() == Input.MOUSE_MODE_VISIBLE,
		"automated local launch never captures the desktop")
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == PRIOR_BYTES,
		"actual development child preserves existing personal run bytes")
	var pause: PauseMenu = game.get_node("PauseMenu")
	pause.open()
	_check(pause._note.text == tr("MENU_EXIT_DEVELOPMENT"), "development menu never promises a save")
	pause.close()
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "owned M06 child stops cleanly"):
		return
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == PRIOR_BYTES, "stopping development preserves the same save bytes")
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	await process_frame
	if not await _saved_transition(owned):
		return
	if failures == 0:
		print("test_m06_local: PASS development isolation and v6 saved M05-M06 carry, arrival/readiness release, v8 promotion/refill and owned cleanup")
	quit(0 if failures == 0 else 1)

func _saved_transition(owned: LocalMatch) -> bool:
	var hash: String = FileAccess.get_sha256(ProjectSettings.globalize_path("res://../server/maps/m05_no_forwarding_address.json"))
	var digest: Array[int] = []
	for index: int in range(0, hash.length(), 2):
		digest.append(hash.substr(index, 2).hex_to_int())
	_check(digest.size() == 32, "legacy fixture binds actual current M05 content")
	var fixture: Dictionary = {
		"version": 6, "id": RUN_ID, "starting_continues": 3, "remaining_continues": 0,
		"level_start_continues": 2, "body": "synthetic", "rules": {"difficulty": "severe", "revision": 3},
		"content_sha256": digest, "m03_outcome": {"liberated_cars": ["platform_car", "roof_car"]},
		"m04_outcome": {"rescued_patients": ["edda_team_a"], "photos_completed": 2},
		"m05_outcome": {"released_workers": ["workshop_agent_b", "splice", "workshop_agent_a"], "evacuated_workers": ["workshop_agent_a", "splice"]},
		"step": {"kind": "awaiting_mission", "completed_mission": "no_forwarding_address", "next_mission": "port_of_entry",
			"exit": {"hp": 61, "armor": 7, "equipment": {"selected": "flechette", "weapons": ["fists", "flechette", "scatter"],
				"ammo": [{"pool": "bullets", "rounds": 29}, {"pool": "shells", "rounds": 8}, {"pool": "cells", "rounds": 0}],
				"grenades": 2, "personal_claims": ["roof_rifle"]}}}}
	var legacy_bytes: String = JSON.stringify(fixture) + "\n"
	var legacy: FileAccess = FileAccess.open(run_directory.path_join("run.json"), FileAccess.WRITE)
	_check(legacy != null, "isolated compatible v6 transition is writable")
	if legacy == null:
		quit(1)
		return false
	legacy.store_string(legacy_bytes)
	legacy.close()
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "saved transition boot menu loads")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "awaiting_mission", "real preview accepts historical pending M05-M06 save"):
		return false
	var preview: Dictionary = owned.run_preview
	_check(preview["mission"] == MissionState.M06_ID and preview["body"] == "synthetic" and int(preview["continues"]) == 0,
		"preview retains destination, body and spent continue allowance")
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == legacy_bytes, "read-only menu preview preserves exact legacy bytes")
	var resume: Button = current_scene._root.get_node_or_null("PortOfEntrySaved") as Button
	_check(resume != null and not resume.disabled, "saved M06 transition offers its actual resume button")
	if resume == null:
		quit(1)
		return false
	resume.pressed.emit()
	if not await _until(_arrived, "pending saved transition plays M06 arrival before readiness"):
		return false
	var game: Node = current_scene
	_check(owned.has_durable_run() and game.opening.scene["id"] == StoryScene.BEFORE_MISSION[MissionState.M06_ID],
		"pending resume retains durable mode and reader scene")
	_check(game.mission_hud.state["phase"] == "briefing" and not game.mission_hud.state["party"][0]["ready"],
		"saved transition does not silently acknowledge the arrival")
	Input.action_press("fire")
	game.opening._skip.pressed.emit()
	await create_timer(0.2).timeout
	_check(game.mission_hud.state["phase"] == "briefing" and game.controls_blocked(), "saved arrival dismissal also consumes held fire")
	Input.action_release("fire")
	if not await _until(_playing, "saved arrival release acknowledges current attempt once"):
		return false
	if not await _until(func() -> bool: return not game.net_client.equipment.is_empty() and not _local_player(game).is_empty(), "carried private gear and authoritative body reach the client"):
		return false
	var state: Dictionary = game.mission_hud.state
	var player: Dictionary = _local_player(game)
	var equipment: Dictionary = game.net_client.equipment
	_check(state["rules"]["difficulty"] == "severe" and int(state["rules"]["revision"]) == MissionState.RULES_REVISION,
		"historical rules upgrade explicitly to current wire: " + str(state["rules"]))
	_check(state["run"]["id"] == RUN_ID and int(state["run"]["continues"]) == 3 \
		and int(state["run"]["level_start_continues"]) == 3 and int(state["attempt"]) == 1,
		"destination preserves run identity and grants the new episode allowance exactly once")
	_check(state["m06"]["carried_recall_cars"] == ["platform_car", "roof_car"], "actual M03 optional choices reach M06 wire")
	_check(state["m06"]["carried_patients"] == ["edda_team_a"] and int(state["m06"]["carried_photos"]) == 2, "actual M04 patient and photo outcomes reach M06 unchanged")
	_check(state["m06"]["carried_released_workers"] == fixture["m05_outcome"]["released_workers"]
		and state["m06"]["carried_evacuated_workers"] == fixture["m05_outcome"]["evacuated_workers"], "actual M05 freed and aboard subsets preserve historical ordering")
	_check(int(equipment["grenades"]) == 2, "v6 carries its exact counted grenade stock")
	_check(int(player["hp"]) == 61 and int(player["armor"]) == 7 and game.net_client.accepted_body == "synthetic", "actual HP, armor and body carry exactly")
	_check(equipment["selected"] == "flechette" and equipment["weapons"] == ["fists", "flechette", "scatter"], "actual carried gun ownership and selection are exact")
	_check(EquipmentState.ammo(equipment, "bullets") == 29 and EquipmentState.ammo(equipment, "shells") == 8 and EquipmentState.ammo(equipment, "cells") == 0,
		"held arrival fire never consumes carried ammunition: " + JSON.stringify(equipment))
	_check(equipment["personal_claims"].is_empty() and not game.pending_interact, "old map claims retire while arrival leaves no interaction: " + JSON.stringify(equipment))
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "durable owned M06 child stops cleanly before inspecting disk"):
		return false
	var saved_bytes: String = FileAccess.get_file_as_string(run_directory.path_join("run.json"))
	var saved: Variant = JSON.parse_string(saved_bytes)
	_check(saved is Dictionary and saved["version"] == 12 and saved["id"] == RUN_ID and saved["rules"]["revision"] == MissionState.RULES_REVISION,
		"actual child atomically persists upgraded v8 identity and current rules")
	if saved is Dictionary:
		_check(saved["step"]["kind"] == "mission_entry" and saved["step"]["mission"] == MissionState.M06_ID \
			and saved["m03_outcome"]["liberated_cars"] == fixture["m03_outcome"]["liberated_cars"] \
			and saved["m04_outcome"]["rescued_patients"] == fixture["m04_outcome"]["rescued_patients"] \
			and int(saved["m04_outcome"]["photos_completed"]) == 2 and saved["m05_outcome"] == fixture["m05_outcome"]
			and int(saved["remaining_continues"]) == 3 and int(saved["level_start_continues"]) == 3, "v8 entry retains authored outcomes and new episode baseline: " + JSON.stringify(saved))
	var archives: Array[String] = []
	for filename: String in DirAccess.get_files_at(run_directory):
		if filename.begins_with("run.prior-") and filename.ends_with(".json"):
			archives.append(filename)
	_check(archives.size() == 1, "legacy transition creates exactly one prior archive")
	if archives.size() == 1:
		_check(FileAccess.get_file_as_string(run_directory.path_join(archives[0])) == legacy_bytes, "archive preserves exact original v6 source bytes")
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	if saved is Dictionary:
		if not await _reopen_spent_entry(owned, saved, saved_bytes, archives):
			return false
	return true

func _reopen_spent_entry(owned: LocalMatch, saved: Dictionary, original: String, archives: Array[String]) -> bool:
	# A legitimate already-spent entry must remain spent when resumed.
	# Preserve the writer's integer tokens. Godot's JSON parser reads them as
	# floats, and reserializing that dictionary would create invalid v8 bytes.
	var field: String = '"remaining_continues":3'
	_check(original.count(field) == 1, "actual writer has one exact episode allowance field")
	if original.count(field) != 1:
		quit(1)
		return false
	var bytes: String = original.replace(field, '"remaining_continues":2')
	var file: FileAccess = FileAccess.open(run_directory.path_join("run.json"), FileAccess.WRITE)
	_check(file != null, "isolated already-spent v8 entry is writable")
	if file == null:
		return false
	file.store_string(bytes)
	file.close()
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "already-spent entry returns to boot")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "ready", "spent M06 entry preview remains ready"):
		return false
	_check(int(owned.run_preview["continues"]) == 2 and int(owned.run_preview["attempt"]) == 2, "preview never refills an existing lunar entry")
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == bytes, "spent-entry preview preserves exact bytes")
	(current_scene._root.get_node("PortOfEntrySaved") as Button).pressed.emit()
	if not await _until(_playing, "real existing M06 entry resumes without replaying arrival"):
		return false
	var game: Node = current_scene
	_check(not is_instance_valid(game.opening) and int(game.mission_hud.state["run"]["continues"]) == 2
		and int(game.mission_hud.state["attempt"]) == 2, "resume leaves spent allowance and arrival barrier unchanged")
	if not await _until(func() -> bool: return not game.net_client.equipment.is_empty(), "spent entry receives exact private equipment"):
		return false
	_check(int(game.net_client.equipment["grenades"]) == 2, "resume does not refill counted equipment")
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "spent entry owned child stops cleanly"):
		return false
	var after: Variant = JSON.parse_string(FileAccess.get_file_as_string(run_directory.path_join("run.json")))
	_check(after is Dictionary and int(after["remaining_continues"]) == 2 and after["m05_outcome"] == saved["m05_outcome"], "second process never refills or rewrites passenger outcomes")
	var after_archives: Array[String] = []
	for filename: String in DirAccess.get_files_at(run_directory):
		if filename.begins_with("run.prior-") and filename.ends_with(".json"):
			after_archives.append(filename)
	_check(after_archives == archives, "reopening current v8 entry creates no second migration archive")
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	return true

func _local_player(game: Node) -> Dictionary:
	for player: Dictionary in game.latest_snapshot.get("players", []):
		if player.get("id") == game.net_client.player_id:
			return player
	return {}
