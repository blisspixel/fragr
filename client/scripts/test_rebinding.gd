extends SceneTree

## Rebinding: tokens, strict parsing, conflict detection and resolution,
## persistence through settings.gd, the InputMap actually changing, reset,
## the Controls page capture flow, and every label keyed in client/i18n.

var _failures: int = 0
var _path: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_rebinding: " + message)

func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event

func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event

func _run() -> void:
	_path = "user://rebinding-%d.cfg" % OS.get_process_id()
	_test_tokens()
	_test_assign_and_conflicts()
	_test_persistence_and_input_map()
	await _test_panel()
	_test_labels_keyed()
	FragrSettings.new(_path + ".unused").apply_controls()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	if _failures == 0:
		print("test_rebinding: PASS tokens, conflicts, persistence, InputMap, panel capture, keyed labels")
	quit(0 if _failures == 0 else 1)

func _test_tokens() -> void:
	for token: String in ["key:70", "key:4194326@r", "mouse:1", "mouse:5", "pad:b0", "pad:b10", "pad:a5+", "pad:a4+"]:
		var event: InputEvent = InputBindings.event_from_token(token)
		_check(event != null and InputBindings.token_from_event(event) == token, "token round trips: " + token)
	for bad: String in ["key:", "key:-4", "key:07", "key:12@x", "mouse:0", "mouse:99", "pad:b-1", "pad:b99", "pad:a0+", "pad:a5*", "joy:1", "key:70 "]:
		_check(InputBindings.event_from_token(bad) == null, "malformed token rejected: " + bad)
	_check(InputBindings.parse("key:70|key:4194309|pad:b1") == (["key:70", "key:4194309", "pad:b1"] as Array[String]), "a full override parses")
	_check(InputBindings.parse("key:70||") == (["key:70", "", ""] as Array[String]), "empty slots are allowed")
	_check(InputBindings.parse("pad:b1|key:70|").is_empty(), "a pad token in a keyboard slot is rejected")
	_check(InputBindings.parse("key:70|key:71|key:72").is_empty(), "a key in the pad slot is rejected")
	_check(InputBindings.parse("key:70|key:71").is_empty(), "exactly three slots")
	_check(InputBindings.parse(42).is_empty(), "non-strings are not overrides")
	_check(InputBindings.default_slots("interact") == (["key:70", "key:4194309", "pad:b1"] as Array[String]), "defaults come from project settings: " + str(InputBindings.default_slots("interact")))
	_check(InputBindings.default_slots("fire") == (["key:4194326", "mouse:1", "pad:a5+"] as Array[String]), "fire defaults to Ctrl, left mouse and the right trigger")
	_check("reload" not in InputBindings.ACTIONS, "reload is not offered for rebinding")

func _test_assign_and_conflicts() -> void:
	var prefs: FragrSettings = FragrSettings.new(_path)
	_check(InputBindings.conflicts(prefs).is_empty(), "defaults have no conflicts")
	# F uses while playing and changes fighter while watching: no conflict.
	_check("key:70" in InputBindings.slots_for(prefs, "cycle_cam") and "key:70" in InputBindings.slots_for(prefs, "interact"), "F is shared across contexts by design")
	# Binding G to fire leaves every other action alone.
	var displaced: Array[String] = InputBindings.assign(prefs, "fire", 0, "key:71")
	_check(displaced.is_empty() and InputBindings.slots_for(prefs, "fire")[0] == "key:71", "a free key binds without displacing anything")
	# Binding F to jump moves it off use, but not off the spectator camera.
	displaced = InputBindings.assign(prefs, "jump", 0, "key:70")
	_check(displaced == (["interact"] as Array[String]), "F moves from use to jump: " + str(displaced))
	_check("key:70" not in InputBindings.slots_for(prefs, "interact"), "use lost F")
	_check("key:70" in InputBindings.slots_for(prefs, "cycle_cam"), "the watching context keeps F")
	# Radio works everywhere, so it conflicts with both contexts.
	displaced = InputBindings.assign(prefs, "radio_toggle", 0, "key:74")
	_check(displaced == (["join_as_human"] as Array[String]), "an everywhere action takes a key from a watching action: " + str(displaced))
	# The same key in both keyboard slots of one action collapses to one.
	InputBindings.assign(prefs, "turn_left", 1, "key:4194319")
	var turn: Array[String] = InputBindings.slots_for(prefs, "turn_left")
	_check(turn[1] == "key:4194319" and turn[0] == "", "one key never fills both slots: " + str(turn))
	# Slot kinds are enforced.
	_check(InputBindings.assign(prefs, "fire", 2, "key:72").is_empty() and InputBindings.slots_for(prefs, "fire")[2] == "pad:a5+", "a key cannot enter the pad slot")
	_check(InputBindings.assign(prefs, "nonsense", 0, "key:72").is_empty(), "unknown actions are refused")
	# A hand-edited file can still hold a conflict; it is reported.
	prefs.set_value("bindings", "speak", "key:4194326||pad:b3")
	prefs.set_value("bindings", "fire", "key:4194326|mouse:1|pad:a5+")
	var found: Array[Dictionary] = InputBindings.conflicts(prefs)
	_check(found.size() == 1 and found[0]["token"] == "key:4194326", "a hand-made conflict is detected: " + str(found))
	prefs.set_value("bindings", "speak", "garbage|x|y")
	_check(prefs.get_value("bindings", "speak") == "", "invalid stored bindings fall back to defaults")
	# Unchanged bindings are not written out.
	InputBindings.store(prefs, "pause", InputBindings.default_slots("pause"))
	_check(prefs.get_value("bindings", "pause") == "", "defaults are stored as empty")

func _test_persistence_and_input_map() -> void:
	var prefs: FragrSettings = FragrSettings.new(_path)
	InputBindings.assign(prefs, "fire", 0, "key:71")
	InputBindings.assign(prefs, "interact", 2, "pad:b2")
	_check(prefs.save_to_disk() == OK, "bindings save")
	var loaded: FragrSettings = FragrSettings.new(_path)
	loaded.load_from_disk()
	_check(InputBindings.slots_for(loaded, "fire")[0] == "key:71", "fire binding survives a fresh store")
	_check(InputBindings.slots_for(loaded, "interact")[2] == "pad:b2", "pad binding survives a fresh store")
	loaded.apply()
	_check(_key(KEY_G).is_action_pressed("fire"), "the InputMap fires on G after apply")
	_check(not _key(KEY_CTRL).is_action_pressed("fire"), "Ctrl no longer fires")
	_check(_pad(JOY_BUTTON_X).is_action_pressed("interact") and not _pad(JOY_BUTTON_B).is_action_pressed("interact"), "the gamepad use button moved")
	_check(is_equal_approx(InputMap.action_get_deadzone("fire"), 0.2), "project deadzones survive a rebuild")
	InputBindings.reset(loaded)
	loaded.apply()
	_check(_key(KEY_CTRL).is_action_pressed("fire") and not _key(KEY_G).is_action_pressed("fire"), "reset restores the defaults")

func _test_panel() -> void:
	var prefs: FragrSettings = FragrSettings.new(_path)
	prefs.load_from_disk()
	var panel: SettingsPanel = SettingsPanel.new()
	panel.preferences = prefs
	root.add_child(panel)
	await process_frame
	_check(panel.current_page() == "CONTROLS", "settings open on Controls")
	for action: String in InputBindings.ACTIONS:
		for slot: int in range(InputBindings.SLOTS):
			_check(panel.find_child("bind_%s_%d" % [action, slot], true, false) is Button, "every action has slot %d: %s" % [slot, action])
	var use_key: Button = panel.find_child("bind_interact_0", true, false)
	_check(use_key.text == "F", "slot shows the bound key, got " + use_key.text)
	use_key.grab_focus()
	_check(root.gui_get_focus_owner() == use_key, "binding slots take keyboard focus")
	panel.begin_capture("interact", 0)
	await process_frame
	_check(panel.accept_capture_event(_key(KEY_H)), "a key fills the slot")
	_check(not panel.capturing() and InputBindings.slots_for(panel._draft, "interact")[0] == "key:72", "use is on H in the draft")
	_check(InputBindings.slots_for(prefs, "interact")[0] == "key:70", "the draft does not touch saved preferences before Save")
	panel.begin_capture("interact", 2)
	await process_frame
	panel.accept_capture_event(_key(KEY_J))
	_check(panel.capturing(), "the pad slot ignores keys and keeps waiting")
	panel.accept_capture_event(_pad(JOY_BUTTON_Y))
	_check(InputBindings.slots_for(panel._draft, "interact")[2] == "pad:b3", "a pad button fills the pad slot")
	_check(InputBindings.slots_for(panel._draft, "speak")[2] == "", "and leaves the taunt it came from")
	panel.begin_capture("fire", 1)
	await process_frame
	panel.accept_capture_event(_key(KEY_ESCAPE))
	_check(not panel.capturing() and InputBindings.slots_for(panel._draft, "fire")[1] == "mouse:1", "Escape cancels without changing the slot")
	panel.begin_capture("fire", 1)
	await process_frame
	panel.accept_capture_event(_key(KEY_BACKSPACE))
	_check(InputBindings.slots_for(panel._draft, "fire")[1] == "", "Backspace clears the slot")
	panel.begin_capture("jump", 0)
	await process_frame
	panel.accept_capture_event(_key(KEY_H))
	var note: Label = panel.get("_note")
	_check(note.text == tr("BIND_MOVED").format({"input": "H", "from": tr("ACTION_INTERACT"), "to": tr("ACTION_JUMP")}), "the page says where a key moved from: " + note.text)
	panel.save()
	var loaded: FragrSettings = FragrSettings.new(_path)
	loaded.load_from_disk()
	_check(InputBindings.slots_for(loaded, "jump")[0] == "key:72" and InputBindings.slots_for(loaded, "interact")[2] == "pad:b3", "Save persists the Controls page")
	panel.free()
	panel = SettingsPanel.new()
	panel.preferences = loaded
	root.add_child(panel)
	await process_frame
	panel.reset_bindings()
	panel.save()
	loaded.load_from_disk()
	_check(InputBindings.slots_for(loaded, "jump") == InputBindings.default_slots("jump"), "reset to defaults persists")
	panel.free()

func _test_labels_keyed() -> void:
	for action: String in InputBindings.ACTIONS:
		var key: String = "ACTION_" + action.to_upper()
		_check(tr(key) != key, "action label is keyed in client/i18n: " + key)
	for key: String in ["SETTINGS_TAB_CONTROLS", "SETTINGS_TAB_LOOK", "BIND_HEADER_KEY", "BIND_HEADER_ALT", "BIND_HEADER_PAD", "BIND_NOTE", "BIND_MOVED", "BIND_CONFLICT", "BIND_RESET", "BIND_WAITING", "LOOK_AIM_ASSIST", "LOOK_STICK_DEADZONE", "LOOK_NOTE"]:
		_check(tr(key) != key, "settings label is keyed: " + key)
