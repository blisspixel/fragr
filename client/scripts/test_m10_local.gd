extends SceneTree

const RUN_ID: String = "40000000-0000-4000-8000-000000000010"
var failures: int = 0
var run_directory: String = ""
var settings_path: String = ""

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://m10-local-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	run_directory = ProjectSettings.globalize_path("user://m10-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	_run.call_deferred()

func _finalize() -> void:
	Input.action_release("fire")
	Input.action_release("place_mine")
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if run_directory == ProjectSettings.globalize_path("user://m10-run-%d" % OS.get_process_id()):
		for filename: String in DirAccess.get_files_at(run_directory):
			DirAccess.remove_absolute(run_directory.path_join(filename))
		DirAccess.remove_absolute(run_directory)
	OS.unset_environment("FRAGR_RUN_DIR")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m10_local: " + message)

func _until(condition: Callable, message: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 25000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		if current_scene != null and current_scene.has_method("change_role") and current_scene.net_client != null \
			and not current_scene.net_client.has_meta("m10_failure_observer"):
			current_scene.net_client.set_meta("m10_failure_observer", true)
			current_scene.net_client.server_error.connect(func(text: String) -> void: print("test_m10_local: server boundary refusal: ", text))
		await process_frame
	var passed: bool = condition.call()
	_check(passed, message)
	if not passed:
		if current_scene != null and current_scene.has_method("change_role"):
			print("test_m10_local: observed map ", current_scene.current_map_id, " geometry ", current_scene.net_client.mission_geometry.get("id"), " mission ", current_scene.net_client.mission)
		quit(1)
	return passed

func _playing() -> bool:
	return current_scene != null and current_scene.has_method("change_role") \
		and current_scene.mission_hud.state.get("phase") == "in_progress" and not current_scene.controls_blocked()

func _gear() -> Dictionary:
	return current_scene.net_client.equipment if current_scene != null and current_scene.has_method("change_role") else {}

func _ship_presentation(game: Node) -> void:
	var cover: ArenaCover = game.arena_cover
	var info: Dictionary = game.current_map_info
	_check(cover != null and cover._solid_views.size() == info["solids"].size(), "actual accepted ship solids have matching presentation")
	var bench_host: Dictionary = ShipFurnishings.matched_host(info)
	_check(not bench_host.is_empty(), "accepted server map has the measured physical bench host")
	var bench: Node3D = cover.get_node_or_null("RepairWorkbench") as Node3D
	_check(bench != null and ShipFurnishings.source_error(bench).is_empty(), "actual accepted map presents the packaged measured workbench")
	if bench != null and not bench_host.is_empty():
		_check(bench.position.distance_to(bench_host["origin"]) < 0.0001 and absf(bench.rotation.y - PI) < 0.0001, "source working face and feet register to the accepted host")
		for child: Node in bench.find_children("*", "MeshInstance3D", true, false):
			_check((child as MeshInstance3D).layers == 2, "workbench belongs to world lighting layer")
		for index: int in range(info["solids"].size()):
			_check(cover._solid_views[index].visible == not (index in bench_host["indices"]), "only measured proxy pieces are replaced by actual source art")
		var changed: Dictionary = info.duplicate(true)
		changed["solids"][bench_host["indices"][1]]["max_x"] += 0.02
		_check(ShipFurnishings.matched_host(changed).is_empty(), "changed physical cabinet cannot silently keep the old source fit")
		changed = info.duplicate(true)
		changed["solids"].append(changed["solids"][bench_host["indices"][1]].duplicate(true))
		changed["presentation"]["solids"].append("lift_panel")
		_check(ShipFurnishings.matched_host(changed).is_empty(), "ambiguous duplicated host refuses source selection")
		var replacement: ArenaCover = ArenaCover.new()
		root.add_child(replacement)
		replacement.apply_map_info(info)
		var old_source: WeakRef = weakref(replacement.get_node("RepairWorkbench"))
		replacement.apply_map_info(changed)
		_check(replacement.get_node_or_null("RepairWorkbench") == null, "a map rebuild with unmatched host retains physical fallback")
		for view: MeshInstance3D in replacement._solid_views:
			_check(view.visible, "fallback does not hide unmatched collision pieces")
		await process_frame
		_check(old_source.get_ref() == null, "map rebuild retires the old source and its resources")
		replacement.free()
	_check(not (cover.get_node("MapFloor") as Node3D).visible, "sealed ship does not draw an outside arena floor")
	for index: int in range(4):
		_check(not (cover.get_node("MapBoundary%d" % index) as Node3D).visible, "outside arena boundary cannot hide the pressure window")
	_check(cover.get_node("Backdrop").get_child_count() == 0, "actual ship has no borrowed industrial skyline")
	var pane: bool = false
	for index: int in range(info["presentation"]["solids"].size()):
		var surface: String = info["presentation"]["solids"][index]
		var material: Material = cover._solid_views[index].material_override
		if surface == "inspection_glass":
			pane = material is StandardMaterial3D and (material as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		elif surface == "service_steel":
			_check(material is ShaderMaterial and (material as ShaderMaterial).get_shader_parameter("trim_glow") == 0.0 \
				and (material as ShaderMaterial).get_shader_parameter("tile_enabled") == true, "actual accepted ship selects quiet reviewed working steel")
	_check(pane, "actual sealed command pane uses registered transparent glass")
	var signs: Array[String] = []
	var lamps: int = 0
	for detail: Dictionary in info["presentation"]["decorations"]:
		if detail["kind"] == "strip_light":
			lamps += 1
		elif str(detail["kind"]).begins_with("m10_"):
			signs.append(detail["kind"])
			_check(ArenaDecoration.SIGN_KEYS.has(detail["kind"]) and tr(ArenaDecoration.SIGN_KEYS[detail["kind"]]) != ArenaDecoration.SIGN_KEYS[detail["kind"]], "actual ship sign has its own localized purpose")
	_check(lamps == 8 and signs == ["m10_cargo_deck", "m10_passenger_deck", "m10_command_deck", "m10_ship_confirmation"], "actual accepted map retains bounded lights and four owning ship panels")

func _run() -> void:
	var preferences: FragrSettings = FragrSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	_check(preferences.save_to_disk() == OK, "isolated settings save")
	_check(DirAccess.make_dir_recursive_absolute(run_directory) == OK, "isolated run directory")
	var hash: Array[int] = []
	for byte: int in FileAccess.get_sha256("res://../server/maps/m09_passenger_manifest.json").hex_decode():
		hash.append(byte)
	_check(hash.size() == 32, "strict historical completion binds actual berth bytes")
	var fixture: Dictionary = {"version": 12, "id": RUN_ID, "starting_continues": 3, "remaining_continues": 1, "level_start_continues": 1,
		"body": "synthetic", "rules": {"difficulty": "standard", "revision": 3}, "content_sha256": hash,
		"m03_outcome": {"liberated_cars": ["roof_car"]}, "m04_outcome": {"rescued_patients": ["edda_team_a"], "photos_completed": 2},
		"m05_outcome": {"released_workers": ["splice", "workshop_agent_a", "workshop_agent_b"], "evacuated_workers": ["splice"]}, "m06_outcome": {"prisoner_route_marked": true},
		"m08_outcome": {"kind": "recorded", "custody_released": true, "recovered_mind_secured": true, "captives_evacuated": true},
		"m09_outcome": {"kind": "recorded", "released_crew": ["tern", "berth_crew_a", "berth_crew_b", "edda", "splice"], "aboard_at_departure": []},
		"step": {"kind": "awaiting_mission", "completed_mission": "passenger_manifest", "next_mission": "common_carrier",
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
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "awaiting_mission", "actual preview reads M09 completion"):
		return
	_check(owned.run_preview.get("mission") == MissionState.M10_ID, "preview names supported M10")
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == source, "preview preserves exact v12 bytes")
	var resume: Button = current_scene._root.get_node_or_null("CommonCarrierSaved") as Button
	_check(resume != null and not resume.disabled, "real saved-run ship button")
	if resume == null:
		quit(1)
		return
	resume.pressed.emit()
	if not await _until(func() -> bool: return current_scene != null and current_scene.has_method("change_role") and current_scene.current_map_id == 1010 and is_instance_valid(current_scene.opening), "matching private child reaches actual ship arrival"):
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
	_check(game.mission_hud.state["m10"]["carried_archive"] == fixture["m08_outcome"] and game.m10_ship._figures.size() == 5 and game.mission_hud.state["m10"]["transit"]["arrived_crew"] == fixture["m09_outcome"]["released_crew"], "actual archive facts and only released crew arrive aboard the ship")
	_check(game.mission_hud.state["run"]["continues"] == 3, "exactly one Episode III refill")
	await _ship_presentation(game)
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
	_check(saved is Dictionary and saved["version"] == 14 and saved["step"]["mission"] == MissionState.M10_ID, "locked writer stores current M10 entry")
	_check(saved is Dictionary and saved["step"]["entry"]["hp"] == 39 and saved["step"]["entry"]["armor"] == 17 and saved["step"]["entry"]["equipment"]["proximity_mines"] == 3, "retry anchor is exact entry, never spent live inventory")
	_check(saved is Dictionary and saved["m08_outcome"] == fixture["m08_outcome"] and saved["m09_outcome"] == fixture["m09_outcome"] and saved["m10_transit"]["arrived_crew"] == fixture["m09_outcome"]["released_crew"], "original zero-aboard receipt remains separate from real transit arrivals")
	var archives: Array[String] = []
	for filename: String in DirAccess.get_files_at(run_directory):
		if filename.begins_with("run.prior-"):
			archives.append(filename)
	_check(archives.size() == 1 and FileAccess.get_file_as_string(run_directory.path_join(archives[0])) == source, "migration archive is exact historical source")
	# Reopen the actual current native M10 entry. Arrival facts and the berth
	# subset stay exact, without a second transition or an episode refill.
	var native_source: String = FileAccess.get_file_as_string(run_directory.path_join("run.json"))
	_check(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "actual M10 retry boot scene")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "ready" and owned.run_preview.get("mission") == MissionState.M10_ID, "preview recognizes real M10 entry"):
		return
	_check(FileAccess.get_file_as_string(run_directory.path_join("run.json")) == native_source, "preview never mutates committed transit")
	resume = current_scene._root.get_node_or_null("CommonCarrierSaved") as Button
	_check(resume != null and not resume.disabled, "saved ship button uses existing launch door")
	if resume == null:
		quit(1)
		return
	resume.pressed.emit()
	if not await _until(func() -> bool: return current_scene != null and current_scene.has_method("change_role") and current_scene.current_map_id == 1010, "new owned child reaches real ship retry"):
		return
	game = current_scene
	_check(game._opening_finished and not is_instance_valid(game.opening), "ordinary saved mission retry does not replay arrival")
	if not await _until(_playing, "retry acknowledges through canonical readiness"):
		return
	if not await _until(func() -> bool: return not _gear().is_empty(), "retry loadout arrives"):
		return
	_check(_gear()["proximity_mines"] == 3 and _gear()["grenades"] == 2 and EquipmentState.ammo(_gear(), "cells") == 1, "retry restores actual finite entry, not spent live inventory")
	_check(game.mission_hud.state["run"]["continues"] == 3 and game.net_client.accepted_body == "synthetic", "reopen does not refill or alter identity")
	_check(game.mission_hud.state["m10"]["transit"]["arrived_crew"] == fixture["m09_outcome"]["released_crew"], "reopen never duplicates transit")
	await _ship_presentation(game)
	# Real ordinary movement crosses the forward activation boundary. This
	# death/continue fixture does not fire, clear guards or claim fight success.
	if not await _until(func() -> bool: return game._has_local_input_target() and not game.controls_blocked(), "retry input is live before entering danger"):
		return
	var route: Array = [[0.0, 4.8, -9.0]]
	var next: int = 0
	var deadline: int = Time.get_ticks_msec() + 20000
	while game.mission_hud.state.get("run", {}).get("status") == "playing" and Time.get_ticks_msec() < deadline:
		var me: Dictionary = QaCombat.actor_by_id(game.latest_snapshot, str(game.net_client.player_id))
		QaCombat.release_inputs()
		if not me.is_empty() and next < route.size():
			next = QaCombat.follow_route(me, game.get_node("SpectatorCamera"), route, next)
		await create_timer(0.05).timeout
	QaCombat.release_inputs()
	_check(next == route.size(), "ordinary forward-gallery arrival is reached")
	if not await _until(func() -> bool: return game.mission_hud.state.get("run", {}).get("status") == "continue" and game._continue_armed, "actual enemy damage kills the finite carried player and arms continue"):
		return
	var old_tick: int = int(game.latest_snapshot.get("tick", -1))
	var event: InputEventAction = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = false
	Input.parse_input_event(event)
	if not await _until(func() -> bool: return _playing() and int(game.mission_hud.state.get("attempt", 0)) == 2, "ordinary continue restores a real M10 attempt"):
		return
	if not await _until(func() -> bool: return _gear().get("proximity_mines") == 3, "actual continue acknowledges finite entry"):
		return
	_check(game.mission_hud.state["run"]["continues"] == 2 and game.local_hp_seen == 39, "death spends one continue and restores actual carried health")
	_check(game.mission_hud.state["m10"]["transit"]["arrived_crew"] == fixture["m09_outcome"]["released_crew"] and int(game.latest_snapshot["tick"]) > old_tick, "continue keeps real transit and monotonic ticks")
	owned.stop()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "reopened owned child exits cleanly"):
		return
	current_scene.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	var retry_saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(run_directory.path_join("run.json")))
	_check(retry_saved is Dictionary and retry_saved["version"] == 14 and retry_saved["m09_outcome"] == fixture["m09_outcome"] and retry_saved["m10_transit"]["arrived_crew"] == fixture["m09_outcome"]["released_crew"], "unfinished ship retry preserves actual earlier crew history")
	_check(retry_saved is Dictionary and retry_saved["step"]["entry"] == saved["step"]["entry"], "real-process retry preserves every entry count")
	archives.clear()
	for filename: String in DirAccess.get_files_at(run_directory):
		if filename.begins_with("run.prior-"):
			archives.append(filename)
	_check(archives.size() == 1 and FileAccess.get_file_as_string(run_directory.path_join(archives[0])) == source, "reopen does not duplicate the exact v12 archive")
	if failures == 0:
		print("test_m10_local: PASS")
	quit(0 if failures == 0 else 1)
