extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_frontend: " + message)

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
	var bob: CheckButton = column.get_node("WeaponBob")
	bob.button_pressed = false
	menu._save_profile()
	await process_frame
	var saved: FragrSettings = FragrSettings.new(test_path)
	saved.load_from_disk()
	_check(saved.player_name() == "Patch 67", "profile save must persist the chosen callsign")
	_check(saved.reticle_colour() == Color("8ee9df"), "profile selection must persist the chosen reticle")
	_check(not bool(saved.get_value("gameplay", "head_bob")), "profile bob switch must persist")
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
		menu._unhandled_input(cancel)
		await process_frame
		_check(menu._page == "main", "keyboard and controller cancel return to the main menu")
		await menu._show("profile")
		_check(column.get_node("Callsign").text == "Patch 67", "back must discard unsaved callsign")
		_check(column.get_node("ReticleColour").selected == 2, "back must discard unsaved colour")
	for page in ["single", "multi", "settings", "main"]:
		await menu._show(page)
		_check(column.get_child_count() > 0, "page should expose controls: " + page)
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
