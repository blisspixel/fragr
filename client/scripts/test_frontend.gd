extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_frontend: " + message)

func _menu_text(column: VBoxContainer) -> String:
	var lines: Array[String] = []
	for node: Node in column.find_children("*", "Label", true, false):
		lines.append((node as Label).text)
	return "\n".join(lines)

func _run() -> void:
	var test_path: String = "user://test-profile-%d.cfg" % OS.get_process_id()
	var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
	menu.set("_settings", FragrSettings.new(test_path))
	root.add_child(menu)
	await process_frame
	await menu._show("profile")
	var column: VBoxContainer = menu.get("_root")
	var callsign: LineEdit = column.get_node("Callsign")
	callsign.text = "Patch 67"
	var colour: OptionButton = column.get_node("ReticleColour")
	colour.select(2)
	colour.item_selected.emit(2)
	var body: OptionButton = column.find_child("Body", true, false)
	var preview: TextureRect = column.find_child("BodyPreview", true, false)
	_check(body != null and preview != null and preview.texture != null, "profile shows a body choice with its preview")
	var human_preview: Texture2D = preview.texture if preview != null else null
	body.select(1)
	body.item_selected.emit(1)
	_check(preview.texture != human_preview and (preview.texture as AtlasTexture).atlas.resource_path == PlayerBody.strip_path("synthetic"),
		"choosing a body previews that body")
	var bob: CheckButton = column.get_node("WeaponBob")
	bob.button_pressed = false
	menu._save_profile()
	await process_frame
	var saved: FragrSettings = FragrSettings.new(test_path)
	saved.load_from_disk()
	_check(saved.player_name() == "Patch 67", "profile save must persist the chosen callsign")
	_check(saved.reticle_colour() == Color("8ee9df"), "profile selection must persist the chosen reticle")
	_check(not bool(saved.get_value("gameplay", "head_bob")), "profile bob switch must persist")
	_check(saved.player_body() == "synthetic", "profile save must persist the chosen body")
	var escape: InputEventKey = InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	var pad_cancel: InputEventJoypadButton = InputEventJoypadButton.new()
	pad_cancel.button_index = JOY_BUTTON_B
	pad_cancel.pressed = true
	for cancel: InputEvent in [escape, pad_cancel]:
		await menu._show("profile")
		column.get_node("Callsign").text = "Discard this"
		column.get_node("ReticleColour").item_selected.emit(0)
		(column.find_child("Body", true, false) as OptionButton).item_selected.emit(0)
		menu._unhandled_input(cancel)
		await process_frame
		_check(menu._page == "main", "keyboard and controller cancel return to the main menu")
		await menu._show("profile")
		_check(column.get_node("Callsign").text == "Patch 67", "back must discard unsaved callsign")
		_check(column.get_node("ReticleColour").selected == 2, "back must discard unsaved colour")
		_check((column.find_child("Body", true, false) as OptionButton).selected == 1, "back must discard an unsaved body")
	for page in ["single", "practice", "multi", "settings", "main"]:
		await menu._show(page)
		_check(column.get_child_count() > 0, "page should expose controls: " + page)
	var owned: LocalMatch = menu.get("_local_match")
	owned._preview_active = false
	owned.run_preview = {"status": "awaiting_mission", "mission": MissionState.M02_ID, "difficulty": "severe", "continues": 2.0, "body": null}
	menu._show("single")
	_check(column.get_node_or_null("PersonsUnknownSaved") != null, "M01 completion offers the saved M02 continuation")
	_check(_menu_text(column).contains("Body for this run: EMBODIED AGENT"), "legacy unknown body shows the explicit current selection")
	_check(_menu_text(column).contains("2 continues left") and not _menu_text(column).contains("2.0 continues"), "saved M02 destination shows a whole-number allowance")
	var choose_body: Button = column.get_node("ChooseRunBody")
	choose_body.pressed.emit()
	await process_frame
	_check(menu._page == "profile", "unbound run opens the body selector")
	menu._unhandled_input(escape)
	await process_frame
	_check(menu._page == "single", "cancel from run body choice returns to Single Player")
	choose_body = column.get_node("ChooseRunBody")
	choose_body.pressed.emit()
	await process_frame
	menu._save_profile()
	await process_frame
	_check(menu._page == "single", "saving run body choice returns to Single Player")
	owned.run_preview = {"status": "ready", "mission": MissionState.M02_ID, "difficulty": "severe", "attempt": 1.0, "continues": 2.0, "pending_continue": false, "body": PlayerBody.HUMAN}
	menu._show("single")
	_check(column.get_node_or_null("PersonsUnknownSaved") != null and _menu_text(column).contains("Run body: HUMAN"), "a bound run body wins over the current profile")
	_check(_menu_text(column).contains("attempt 1") and _menu_text(column).contains("2 continues left") and not _menu_text(column).contains(".0"), "ready run shows whole-number attempt and allowance")
	owned.run_preview = {"status": "awaiting_mission", "mission": MissionState.M03_ID, "difficulty": "severe", "continues": 2.0, "body": PlayerBody.HUMAN}
	menu._show("single")
	_check(column.get_node_or_null("ScheduledServiceSaved") != null and _menu_text(column).contains("SCHEDULED SERVICE"), "M02 completion offers the saved M03 continuation")
	owned.run_preview["mission"] = MissionState.M04_ID
	menu._show("single")
	_check(column.get_node_or_null("NoticeToVacateSaved") != null and _menu_text(column).contains("NOTICE TO VACATE"), "M03 completion offers saved M04 carry through the same menu")
	_check(menu._arrival_for_preview(owned.run_preview), "pending M03 to M04 entry requests its arrival scene")
	var existing_entry: Dictionary = owned.run_preview.duplicate(true)
	existing_entry["status"] = "ready"
	_check(not menu._arrival_for_preview(existing_entry), "restart of an existing M04 entry never requests the arrival again")
	_check(menu._arrival_for_preview({"status": "awaiting_mission", "mission": MissionState.M03_ID}) \
		and not menu._arrival_for_preview({"status": "ready", "mission": MissionState.M03_ID}) \
		and not menu._arrival_for_preview({"status": "awaiting_mission", "mission": LocalMatch.NEXT_MISSION}),
		"same arrival selection covers M02 to M03 without replaying existing or unavailable missions")
	_check(_menu_text(column).contains("2 continues left") and _menu_text(column).contains("Run body: HUMAN"), "M04 carry displays retained allowance and saved body")
	owned.run_preview["mission"] = MissionState.M06_ID
	owned.run_preview["continues"] = 0
	menu._show("single")
	_check(column.get_node_or_null("PortOfEntrySaved") != null and _menu_text(column).contains("PORT OF ENTRY"), "completed M05 offers the real lunar continuation with spent old allowance")
	_check(menu._arrival_for_preview(owned.run_preview) and not menu._arrival_for_preview({"status": "ready", "mission": MissionState.M06_ID}), "new lunar transition plays arrival while an existing lunar entry does not")
	owned.run_preview["continues"] = 2
	owned.run_preview["mission"] = MissionState.M07_ID
	menu._show("single")
	_check(column.get_node_or_null("DeclaredGoodsSaved") != null and _menu_text(column).contains("DECLARED GOODS"), "completed M06 offers the real town continuation with retained allowance")
	_check(menu._arrival_for_preview(owned.run_preview) and not menu._arrival_for_preview({"status": "ready", "mission": MissionState.M07_ID}), "new town transition plays arrival while an existing town entry does not")
	owned.run_preview["mission"] = MissionState.M08_ID
	menu._show("single")
	_check(column.get_node_or_null("CustodianOfRecordSaved") != null and _menu_text(column).contains("CUSTODIAN OF RECORD"), "completed M07 offers the actual archive continuation")
	_check(menu._arrival_for_preview(owned.run_preview) and not menu._arrival_for_preview({"status": "ready", "mission": MissionState.M08_ID}), "new archive transition plays arrival while its existing entry does not")
	owned.run_preview["mission"] = MissionState.M09_ID
	menu._show("single")
	_check(column.get_node_or_null("PassengerManifestSaved") != null and _menu_text(column).contains("PASSENGER MANIFEST"), "completed M08 offers the actual launch berth continuation")
	_check(menu._arrival_for_preview(owned.run_preview) and not menu._arrival_for_preview({"status": "ready", "mission": MissionState.M09_ID}), "new berth transition plays arrival while its existing entry does not")
	owned.run_preview["mission"] = MissionState.M10_ID
	menu._show("single")
	_check(column.get_node_or_null("CommonCarrierSaved") != null and _menu_text(column).contains("COMMON CARRIER"), "completed M09 offers the actual ship continuation")
	_check(menu._arrival_for_preview(owned.run_preview) and not menu._arrival_for_preview({"status": "ready", "mission": MissionState.M10_ID}), "new ship transition plays arrival while its existing entry does not")
	owned.run_preview["mission"] = LocalMatch.NEXT_MISSION
	menu._show("single")
	_check(column.get_node_or_null("PassengerManifestSaved") == null and column.get_node_or_null("CommonCarrierSaved") == null and _menu_text(column).contains("Right of Search is not playable yet"), "pending M11 has no mission launch button")
	menu._onward_pending = true
	var saved_preview: Dictionary = owned.run_preview.duplicate(true)
	owned.run_preview = {"status": "loading"}
	menu._try_onward()
	_check(menu._onward_pending and not menu._launch_pending, "an onward request waits for the saved run preview")
	owned.run_preview = saved_preview
	owned.state = LocalMatch.State.STOPPING
	menu._try_onward()
	_check(menu._onward_pending and not menu._launch_pending, "an onward request waits for the finished child to stop")
	owned.state = LocalMatch.State.IDLE
	menu._try_onward()
	_check(not menu._onward_pending and not menu._launch_pending and menu._page == "single",
		"an unbuilt next mission settles the onward request on Single Player without launching")
	_check(_menu_text(column).contains("NEXT: RIGHT OF SEARCH") and _menu_text(column).contains("2 continues left") \
		and _menu_text(column).contains("Run body: HUMAN"), "pending M11 previews mission, shared continues and saved body")
	owned.run_preview["body"] = null
	menu._show("single")
	_check(_menu_text(column).contains("Run body is not bound yet") and column.get_node_or_null("ChooseRunBody") == null,
		"pending M11 leaves an unbound body visible without an unavailable selector")
	menu._show("practice")
	var development: OptionButton = column.get_node("DevelopmentMission") as OptionButton
	_check(development.item_count == 9 and development.get_item_text(4).contains("PORT OF ENTRY")
		and development.get_item_text(5).contains("DECLARED GOODS") and development.get_item_text(6).contains("CUSTODIAN OF RECORD")
		and development.get_item_text(7).contains("PASSENGER MANIFEST") and development.get_item_text(8) == tr("M10_PROTOTYPE_TITLE"), "compact practice selector retains old indices and includes the ship prototype")
	_check(column.get_node_or_null("DevelopmentMission") != null and _menu_text(column).contains("NO SAVE OVERWRITE"), "M03 development entry states save isolation")
	_check(column.get_node_or_null("LaunchDevelopmentMission") != null, "M04 has a separate labeled development entry")
	await menu._show("multi")
	menu._apply_status({"schema_version": 2, "kind": "arena", "map": "Arena Duel", "fighters": 4, "connections": 2})
	_check(menu._match_line.text == "Arena Duel. Arena. 4 fighters. 2 connections.", "a live arena enables the match line")
	_check(not menu._watch_button.disabled and not menu._join_button.disabled, "watch and join stay in the app after a match line")
	menu._apply_status({"schema_version": 2, "kind": "campaign", "map": "Recall Notice: intake prototype", "fighters": 1, "connections": 1})
	_check(menu._match_line.text.begins_with("Recall Notice: intake prototype. Mission."), "a mission host is named as a mission")
	var with_ops: Dictionary = {"schema_version": 2, "kind": "arena", "map": "Tripoint Works", "fighters": 8, "connections": 6, "health": {"status": "degraded", "reasons": ["outbound_drops"]}, "ops": {"version": 1, "tick": {"window": {"p99_ms": 1.5}}}}
	menu._apply_status(with_ops)
	_check(menu._match_line.text == "Tripoint Works. Arena. 8 fighters. 6 connections.", "additive health and ops fields keep the schema 2 match line")
	_check(not menu._join_button.disabled, "operator fields do not close watch or join")
	menu._apply_status({"schema_version": 1, "map": "Arena Duel", "fighters": 1, "connections": 1})
	_check(menu._watch_button.disabled and menu._join_button.disabled, "schema 1 does not open watch or join")
	menu._apply_status(null)
	_check(menu._match_line.text == "This host did not answer.", "a missing host stays on the menu")
	await menu._show("main")
	menu.queue_free()
	await process_frame
	var pause_menu: PauseMenu = PauseMenu.new()
	root.add_child(pause_menu)
	pause_menu.open()
	await process_frame
	_check(pause_menu.is_open() and not paused, "match menu must keep server snapshots flowing")
	_check(pause_menu._note.text == tr("MENU_LIVE_MATCH"), "arena menu does not say leaving abandons a campaign run")
	pause_menu.close()
	pause_menu.local_campaign = true
	pause_menu.open()
	await process_frame
	_check(pause_menu.is_open() and pause_menu._note.text == tr("MENU_EXIT_SAVES_RUN"), "local campaign menu says exit preserves the run")
	_check(pause_menu._leave_button.text == tr("RUN_EXIT_MENU"), "local campaign action is exit to menu")
	_check(not pause_menu._note.text.contains("Prototype"), "campaign leave note is not a prototype disclaimer")
	pause_menu.close()
	_check(not pause_menu.is_open() and not paused, "closing the menu returns to the live match")
	pause_menu.queue_free()
	await process_frame
	# Exercise the real HUD independently of a network connection.
	var match_scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = match_scene.get_node("HUD")
	match_scene.remove_child(hud)
	match_scene.free()
	root.add_child(hud)
	hud.set_mode("SPECTATING")
	hud.set_fp_juice(true)
	hud.set_fp_weapon("Rail")
	hud.set_vitals(42, 17)
	_check(hud.get_node("Vitals").visible, "spectator eyes show the watched fighter's vitals")
	_check(hud.get_node("Vitals/HealthValue").text == "42", "spectator health is the observed value")
	_check(hud.get_node("Vitals/ArmorValue").text == "17", "spectator armour is the observed value")
	hud.set_fp_juice(false)
	_check(not hud.get_node("Vitals").visible and not hud.get_node("FpWeapon").visible, "chase view clears first-person presentation")
	hud.queue_free()
	await process_frame
	DirAccess.remove_absolute(test_path)
	if _failures == 0:
		print("test_frontend: PASS profile save/cancel, menu pages, live match overlay")
	quit(0 if _failures == 0 else 1)
