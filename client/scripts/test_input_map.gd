extends SceneTree

## Default input map regression: one coherent layout for keyboard and mouse,
## Xbox and PlayStation pads (the same SDL button indices), no input shared by
## two actions in one context, every action bound where intended, family
## names for prompts, and custom bindings from an older layout refused, not migrated.

var _failures: int = 0
var _path: String = ""

## The shipped gamepad layout. Changing a default means changing this table on
## purpose, together with docs/PLAYING.md.
const PAD_LAYOUT: Dictionary = {
	"jump": "pad:b0",                  # A / Cross
	"duck": "pad:b1",                  # B / Circle, held
	"reload": "pad:b2",                # X / Square
	"interact": "pad:b3",              # Y / Triangle
	"scoreboard": "pad:b4",            # View / Create, held
	"pause": "pad:b6",                 # Menu / Options
	"place_remote_mine": "pad:b7",     # left stick click
	"trigger_remote_mines": "pad:b8",  # right stick click
	"weapon_prev": "pad:b9",           # LB / L1
	"weapon_next": "pad:b10",          # RB / R1
	"throw_grenade": "pad:b11",        # D-pad up
	"place_mine": "pad:b12",           # D-pad down
	"radio_prev_station": "pad:b13",   # D-pad left, hold for power
	"radio_next_station": "pad:b14",   # D-pad right, hold to skip
	"scope": "pad:a4+",                # LT / L2
	"fire": "pad:a5+",                 # RT / R2
	"join_as_human": "pad:b0",         # watching
	"cycle_cam": "pad:b2",             # watching
	"toggle_follow": "pad:b3",         # watching
}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_input_map: " + message)

func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event

func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func _run() -> void:
	_path = "user://input-map-%d.cfg" % OS.get_process_id()
	var prefs: FragrSettings = FragrSettings.new(_path)
	prefs.reset_all()
	prefs.apply_controls()
	_test_defaults(prefs)
	_test_menu_context()
	_test_family_names()
	_test_prompt_templates()
	_test_old_custom_files()
	InputDevice.reset()
	FragrSettings.new(_path + ".unused").apply_controls()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	if _failures == 0:
		print("test_input_map: PASS defaults are conflict free per context, bound on keyboard and pad where intended, and named per pad family")
	quit(0 if _failures == 0 else 1)

func _test_defaults(prefs: FragrSettings) -> void:
	var conflicts: Array[Dictionary] = InputBindings.conflicts(prefs)
	_check(conflicts.is_empty(), "default layout has no conflicts within a context: " + str(conflicts))
	for action: String in InputBindings.ACTIONS:
		var slots: Array[String] = InputBindings.default_slots(action)
		_check(not slots[0].is_empty(), "every action has a keyboard or mouse default: " + action)
		var wants_pad: bool = action not in InputBindings.NO_PAD_DEFAULT
		_check(slots[InputBindings.PAD_SLOT].is_empty() != wants_pad, "pad default present exactly where intended: %s has %s" % [action, slots[InputBindings.PAD_SLOT]])
		if PAD_LAYOUT.has(action):
			_check(slots[InputBindings.PAD_SLOT] == PAD_LAYOUT[action], "%s pad default is %s, got %s" % [action, PAD_LAYOUT[action], slots[InputBindings.PAD_SLOT]])
		else:
			_check(not wants_pad, "pad layout table covers " + action)
	for action: String in InputBindings.NO_PAD_DEFAULT:
		_check(action in InputBindings.ACTIONS, "no-pad list names a real action: " + action)
	# The Guide or Xbox button belongs to the console and the platform overlay.
	for action: String in InputBindings.ACTIONS:
		_check(not InputMap.action_has_event(action, _pad(JOY_BUTTON_GUIDE)), "nothing uses the system Guide button: " + action)
	# Radio on the D-pad arms that nothing else in play or watching uses.
	for action: String in InputBindings.ACTIONS:
		if action.begins_with("radio_"):
			continue
		_check(not InputMap.action_has_event(action, _pad(JOY_BUTTON_DPAD_LEFT)) and not InputMap.action_has_event(action, _pad(JOY_BUTTON_DPAD_RIGHT)),
			"D-pad left and right belong to the radio only: " + action)
	_check(_key(KEY_X).is_action_pressed("radio_prev_station") and _key(KEY_C).is_action_pressed("radio_next_station"), "X and C sit side by side as previous and next station")
	_check(_key(KEY_N).is_action_pressed("radio_next_track") and _key(KEY_M).is_action_pressed("radio_toggle"), "N skips and M is power")
	_check(InputBindings.context("radio_prev_station") == "everywhere", "previous station works while playing and watching")
	var trigger: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 0.3
	_check(trigger.is_action_pressed("scope"), "a light left trigger pull scopes")

func _test_menu_context() -> void:
	# Menus confirm with the south face button and go back with the east one,
	# on Xbox and on PlayStation alike; Enter, Space and Escape on keys.
	_check(_pad(JOY_BUTTON_A).is_action_pressed("ui_accept") and _pad(JOY_BUTTON_B).is_action_pressed("ui_cancel"), "A or Cross confirms, B or Circle backs out")
	_check(_key(KEY_ESCAPE).is_action_pressed("ui_cancel"), "Escape backs out")
	var enter: InputEventKey = InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	_check(enter.is_action_pressed("ui_accept"), "Enter confirms")
	for pair: Array in [[JOY_BUTTON_DPAD_UP, "ui_up"], [JOY_BUTTON_DPAD_DOWN, "ui_down"], [JOY_BUTTON_DPAD_LEFT, "ui_left"], [JOY_BUTTON_DPAD_RIGHT, "ui_right"]]:
		_check(_pad(pair[0] as JoyButton).is_action_pressed(str(pair[1])), "the D-pad navigates menus: " + str(pair[1]))
	_check(_pad(JOY_BUTTON_START).is_action_pressed("pause"), "Menu or Options opens the match menu")

func _test_family_names() -> void:
	var expected: Dictionary = {
		"reload": ["X", "SQUARE", "WEST"],
		"duck": ["B", "CIRCLE", "EAST"],
		"interact": ["Y", "TRIANGLE", "NORTH"],
		"jump": ["A", "CROSS", "SOUTH"],
		"scope": ["LT", "L2", "LT"],
		"fire": ["RT", "R2", "RT"],
		"weapon_next": ["RB", "R1", "RB"],
		"pause": ["MENU", "OPTIONS", "START"],
		"scoreboard": ["VIEW", "CREATE", "SELECT"],
		"trigger_remote_mines": ["RS", "R3", "RS"],
		"radio_prev_station": ["D-LEFT", "D-LEFT", "D-LEFT"],
		"radio_next_station": ["D-RIGHT", "D-RIGHT", "D-RIGHT"],
	}
	var layouts: Array[String] = ["letters", "shapes", "generic"]
	for action: String in expected:
		for index: int in range(layouts.size()):
			InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", layouts[index])
			var name: String = InputGlyphs.action_name(action)
			_check(name == expected[action][index], "%s on %s reads %s, got %s" % [action, layouts[index], expected[action][index], name])
	_check(InputDevice.layout_for("Xbox Wireless Controller", {}) == "letters" and InputDevice.layout_for("DualSense Wireless Controller", {}) == "shapes",
		"Xbox and PlayStation pads are told apart by name")
	_check(InputDevice.layout_for("", {"vendor_id": 0x054C}) == "shapes" and InputDevice.layout_for("", {"vendor_id": 0x045E}) == "letters",
		"and by vendor")
	InputDevice.force(InputDevice.Kind.KEYBOARD)
	_check(InputGlyphs.action_name("radio_prev_station") == "X" and InputGlyphs.action_name("radio_next_station") == "C", "keyboard prompts name the radio keys")

func _test_prompt_templates() -> void:
	for kind: InputDevice.Kind in [InputDevice.Kind.KEYBOARD, InputDevice.Kind.GAMEPAD]:
		InputDevice.force(kind, "", "letters")
		for key: String in ["HUD_CONTROLS_PLAY", "HUD_CONTROLS_WATCH", "LOADING_CONTROLS_KEYS", "LOADING_CONTROLS_PAD", "MENU_PAUSE_HINT"]:
			var template: String = TranslationServer.translate(key)
			_check(template != key, "prompt is keyed: " + key)
			var plain: String = InputGlyphs.plain(template)
			_check(not plain.contains("{") and not plain.contains("?"), "%s resolves every control on %s: %s" % [key, str(kind), plain])
	InputDevice.reset()

## One current controls layout: custom bindings saved against another layout
## are refused whole, never migrated, and the rest of the file still loads.
func _test_old_custom_files() -> void:
	var older: ConfigFile = ConfigFile.new()
	older.set_value("meta", "controls_layout", FragrSettings.CONTROLS_LAYOUT - 1)
	older.set_value("bindings", "interact", "key:70|key:4194309|pad:b2")
	older.set_value("audio", "music", 0.25)
	_check(older.save(_path) == OK, "older layout fixture saves")
	var loaded: FragrSettings = FragrSettings.new(_path)
	loaded.load_from_disk()
	_check(loaded.controls_refused, "custom bindings from an older layout are refused")
	_check(InputBindings.slots_for(loaded, "interact") == InputBindings.default_slots("interact") and InputBindings.slots_for(loaded, "reload")[2] == "pad:b2", "the current layout is in force instead")
	_check(InputBindings.conflicts(loaded).is_empty(), "the refused file leaves no conflict")
	_check(is_equal_approx(float(loaded.get_value("audio", "music")), 0.25), "other settings in the file still load")
	var unstamped: ConfigFile = ConfigFile.new()
	unstamped.set_value("bindings", "speak", "key:84||pad:b1")
	_check(unstamped.save(_path) == OK, "unstamped fixture saves")
	loaded.load_from_disk()
	_check(loaded.controls_refused and InputBindings.slots_for(loaded, "speak") == InputBindings.default_slots("speak"), "a file without a layout stamp is refused too")
	# Saving stamps the current layout, so the player's next rebind sticks.
	var current: FragrSettings = FragrSettings.new(_path)
	current.reset_all()
	var moved: Array[String] = InputBindings.assign(current, "speak", InputBindings.PAD_SLOT, "pad:b1")
	_check(moved == (["duck"] as Array[String]), "B leaves crouch for the custom speak: " + str(moved))
	_check(loaded.commit(current) == OK and not loaded.controls_refused, "a save clears the notice")
	var again: FragrSettings = FragrSettings.new(_path)
	again.load_from_disk()
	_check(not again.controls_refused and InputBindings.slots_for(again, "speak")[2] == "pad:b1", "current-layout customs load as saved")
	_check(InputBindings.conflicts(again).is_empty(), "the saved custom layout stays conflict free: " + str(InputBindings.conflicts(again)))
	var defaults: FragrSettings = FragrSettings.new(_path)
	defaults.reset_all()
	_check(defaults.save_to_disk() == OK, "defaults save")
	defaults.load_from_disk()
	_check(not defaults.controls_refused, "a file with no custom bindings is never refused")
