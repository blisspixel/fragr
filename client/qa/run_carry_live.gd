extends SceneTree

## Manual integration check against a server-generated M01 AwaitingMission fixture.
## Set FRAGR_RUN_DIR to the fixture directory and, for rendered stills, set
## FRAGR_LOCAL_QA_DIR to an absolute output directory before launching Godot.
var failures: int = 0
var settings_path: String
var captures: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://run-carry-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	captures = OS.get_environment("FRAGR_LOCAL_QA_DIR")
	call_deferred("_run")

func _finalize() -> void:
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("run_carry_live: " + message)

func _until(condition: Callable, description: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 20000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	_expect(passed, description)
	if not passed:
		quit(1)
	return passed

func _menu() -> bool:
	return current_scene != null and current_scene.has_method("_start_campaign_resume")

func _playing() -> bool:
	return current_scene != null and current_scene.has_method("change_role") \
		and current_scene.current_map_id == 1002 and not current_scene.latest_snapshot.is_empty() \
		and current_scene.mission_hud.state.get("phase") == "in_progress"

func _local_pawn() -> Dictionary:
	for player: Dictionary in current_scene.latest_snapshot.get("players", []):
		if player.get("id") == current_scene.net_client.player_id:
			return player
	return {}

func _capture(filename: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_expect(DirAccess.make_dir_recursive_absolute(captures) == OK, "capture directory created")
	_expect(root.get_texture().get_image().save_png(captures.path_join(filename + ".png")) == OK, "capture saved")

func _run() -> void:
	var run_dir: String = OS.get_environment("FRAGR_RUN_DIR")
	_expect(run_dir.is_absolute_path() and FileAccess.file_exists(run_dir.path_join("run.json")), "isolated fixture path is present")
	if failures > 0:
		quit(1)
		return
	var prefs: FragrSettings = FragrSettings.new(settings_path)
	prefs.set_value("video", "display_mode", 0)
	prefs.set_value("profile", "body", PlayerBody.HUMAN)
	_expect(prefs.save_to_disk() == OK, "isolated preferences saved")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 960)
	_expect(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "boot menu loads")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return LocalMatch.for_tree(self).run_preview.get("status") == "awaiting_mission", "M01 departure previews as M02"):
		return
	var owned: LocalMatch = LocalMatch.for_tree(self)
	var preview: Dictionary = owned.run_preview
	_expect(preview.get("mission") == MissionState.M02_ID and preview.get("difficulty") == "severe" \
		and preview.get("continues") == 2 and preview.get("body") == PlayerBody.SYNTHETIC,
		"M02 preview preserves mission, difficulty, shared continues and saved body")
	await process_frame
	_expect(current_scene._root.get_node_or_null("PersonsUnknownSaved") != null, "Single Player offers durable M02")
	await _capture("01-single-player-m02")
	current_scene._start_campaign_resume()
	if not await _until(_playing, "Continue Run enters authoritative M02"):
		return
	if not await _until(func() -> bool: return not current_scene.net_client.equipment.is_empty(),
		"M02 join receives its first private loadout"):
		return
	var state: Dictionary = current_scene.mission_hud.state
	var run: Dictionary = state.get("run", {})
	var run_id: String = str(run.get("id", ""))
	_expect(owned.mission == MissionState.M02_ID and owned.has_durable_run(), "owned child is durable M02")
	_expect(state.get("attempt") == 1 and run.get("continues") == 2 and run.get("level_start_continues") == 2 \
		and state.get("rules", {}).get("difficulty") == "severe" and not run_id.is_empty(),
		"M02 entry resets level attempt and retains severe shared allowance")
	_expect(current_scene.net_client.accepted_body == PlayerBody.SYNTHETIC and _local_pawn().get("body") == PlayerBody.SYNTHETIC,
		"saved synthetic body overrides current human preference: welcome=%s snapshot=%s" % [current_scene.net_client.accepted_body, _local_pawn().get("body")])
	_expect(current_scene.net_client.equipment.get("selected") == "tack" \
		and current_scene.net_client.equipment.get("weapons") == ["fists", "tack"],
		"first private M02 loadout carries exact M01 weapon ownership and Tack selection")
	_expect(_local_pawn().get("hp") == 61 and _local_pawn().get("armor") == 7,
		"M01 health and armour carry into M02: hp=%s armor=%s" % [_local_pawn().get("hp"), _local_pawn().get("armor")])
	_expect(EquipmentState.ammo(current_scene.net_client.equipment, "bullets") == 29,
		"M01 ammunition carries into M02")
	_expect(current_scene.net_client.equipment.get("personal_claims") == [] and EquipmentState.ammo(current_scene.net_client.equipment, "shells") == 0 \
		and EquipmentState.ammo(current_scene.net_client.equipment, "cells") == 0,
		"first private M02 loadout clears M01 claims and preserves empty ammo pools: %s" % current_scene.net_client.equipment)
	_expect(current_scene.mission_hud._run_badge.visible and current_scene.mission_hud._run_badge.text.contains("2"),
		"M02 HUD shows the carried allowance")
	await _capture("02-m02-entry")
	current_scene.pause_menu.leave_requested.emit()
	if not await _until(func() -> bool: return _menu() and owned.state == LocalMatch.State.IDLE, "exit stops owned M02 child"):
		return
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "ready", "saved M02 previews after child restart"):
		return
	preview = owned.run_preview
	_expect(preview.get("mission") == MissionState.M02_ID and preview.get("attempt") == 1 \
		and preview.get("continues") == 2 and preview.get("body") == PlayerBody.SYNTHETIC,
		"M02 save round-trips mission, level attempt, shared continues and body")
	await _capture("03-m02-resume")
	current_scene._start_campaign_resume()
	if not await _until(_playing, "M02 resume starts a second local child"):
		return
	if not await _until(func() -> bool: return not current_scene.net_client.equipment.is_empty(),
		"M02 resume receives its first private saved loadout"):
		return
	state = current_scene.mission_hud.state
	_expect(state.get("run", {}).get("id") == run_id and state.get("attempt") == 1,
		"M02 resume preserves run identity and level attempt")
	_expect(current_scene.net_client.accepted_body == PlayerBody.SYNTHETIC \
		and current_scene.net_client.equipment.get("selected") == "tack" \
		and current_scene.net_client.equipment.get("weapons") == ["fists", "tack"] \
		and EquipmentState.ammo(current_scene.net_client.equipment, "bullets") == 29 \
		and EquipmentState.ammo(current_scene.net_client.equipment, "shells") == 0 \
		and EquipmentState.ammo(current_scene.net_client.equipment, "cells") == 0 \
		and current_scene.net_client.equipment.get("personal_claims") == [],
		"M02 resume restores exact saved body and first private loadout: welcome=%s loadout=%s" % [current_scene.net_client.accepted_body, current_scene.net_client.equipment])
	current_scene.pause_menu.leave_requested.emit()
	if not await _until(func() -> bool: return _menu() and owned.state == LocalMatch.State.IDLE, "second M02 child stops"):
		return
	# The next mission has no bundled child yet. Preview its read-only layout
	# with a marked synthetic state, without claiming a server departure.
	owned.run_preview = {"status": "awaiting_mission", "mission": LocalMatch.NEXT_MISSION,
		"difficulty": "severe", "continues": 2, "body": PlayerBody.SYNTHETIC}
	current_scene._show("single")
	_expect(current_scene._root.get_node_or_null("PersonsUnknownSaved") == null,
		"pending Scheduled Service has no launch action")
	await _capture("04-m03-pending-layout-mock")
	await create_timer(0.5).timeout
	if failures == 0:
		print("run_carry_live: PASS M01 departure preview, durable M02 launch, body/loadout carry, M02 restart")
	quit(0 if failures == 0 else 1)
