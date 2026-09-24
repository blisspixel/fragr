extends SceneTree

## Prompts follow the last device used: keyboard keys, or gamepad glyphs in a
## letter, shape or positional layout picked from the pad's reported name.

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_input_glyphs: " + message)

func _run() -> void:
	FragrSettings.new("user://glyphs-unused.cfg").apply_controls()
	InputDevice.reset()
	_test_layout_detection()
	_test_device_switching()
	_test_prompts()
	_test_glyph_images()
	await _test_mission_prompt()
	InputDevice.reset()
	if _failures == 0:
		print("test_input_glyphs: PASS layout detection, device switching, prompts, pixel glyphs")
	quit(0 if _failures == 0 else 1)

func _test_layout_detection() -> void:
	_check(InputDevice.layout_for("Xbox Series Controller") == "letters", "Xbox names use letters")
	_check(InputDevice.layout_for("XInput Gamepad (GLFW)") == "letters", "XInput uses letters")
	_check(InputDevice.layout_for("PS5 Controller") == "shapes", "PS5 uses shapes")
	_check(InputDevice.layout_for("DualSense Wireless Controller") == "shapes", "DualSense uses shapes")
	_check(InputDevice.layout_for("Wireless Controller") == "shapes", "the DualShock 4 Windows name uses shapes")
	_check(InputDevice.layout_for("Nintendo Switch Pro Controller") == "generic", "Nintendo pads use positional glyphs, since A and B are swapped")
	_check(InputDevice.layout_for("8BitDo Something") == "generic", "unknown pads fall back to positional glyphs")
	_check(InputDevice.layout_for("", {"vendor_id": 0x054C}) == "shapes", "Sony's vendor id uses shapes")
	_check(InputDevice.layout_for("", {"xinput_index": 0}) == "letters", "an XInput slot uses letters")

func _test_device_switching() -> void:
	InputDevice.reset()
	var revision: int = InputDevice.revision
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	_check(InputDevice.note(pad) and InputDevice.is_gamepad() and InputDevice.revision > revision, "a pad button switches prompts to the gamepad")
	_check(not InputDevice.note(pad), "the same device again is not a change")
	var release: InputEventJoypadButton = pad.duplicate()
	release.pressed = false
	InputDevice.force(InputDevice.Kind.KEYBOARD)
	_check(not InputDevice.note(release), "a release never switches devices")
	var drift: InputEventJoypadMotion = InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.2
	_check(not InputDevice.note(drift) and not InputDevice.is_gamepad(), "stick drift does not steal the prompts")
	drift.axis_value = 0.8
	_check(InputDevice.note(drift) and InputDevice.is_gamepad(), "a deliberate stick push does")
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	_check(InputDevice.note(key) and InputDevice.kind == InputDevice.Kind.KEYBOARD, "a key switches back to keyboard prompts")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_check(InputDevice.note(click) and InputDevice.kind == InputDevice.Kind.MOUSE and not InputDevice.is_gamepad(), "the mouse shares keyboard prompts")

func _test_prompts() -> void:
	var use: String = tr("MISSION_USE_RECORD")
	InputDevice.force(InputDevice.Kind.KEYBOARD)
	_check(InputGlyphs.plain(use) == "F: READ TRANSFER RECORD", "keyboard use prompt: " + InputGlyphs.plain(use))
	_check(InputGlyphs.plain("{accept}") == "ENTER" and InputGlyphs.plain("{pause}") == "ESC", "keyboard accept and pause")
	InputDevice.force(InputDevice.Kind.MOUSE)
	_check(InputGlyphs.plain("{fire}") == "LMB", "the mouse fires with its button")
	InputDevice.force(InputDevice.Kind.KEYBOARD)
	_check(InputGlyphs.plain("{fire}") == "CTRL", "the keyboard fires with Ctrl")
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "letters")
	_check(InputGlyphs.plain(use) == "B: READ TRANSFER RECORD", "letter pad use prompt: " + InputGlyphs.plain(use))
	_check(InputGlyphs.plain("{accept} {fire} {pause} {weapon}") == "A RT MENU RB", "letter pad names: " + InputGlyphs.plain("{accept} {fire} {pause} {weapon}"))
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "shapes")
	_check(InputGlyphs.plain(use) == "CIRCLE: READ TRANSFER RECORD", "shape pad use prompt")
	_check(InputGlyphs.plain("{accept} {fire}") == "CROSS R2", "shape pad names")
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "generic")
	_check(InputGlyphs.plain(use) == "EAST: READ TRANSFER RECORD", "positional pad use prompt")
	_check(InputGlyphs.plain("{weapon_1}") == "1", "a key-only action still shows its key on a pad")
	_check(InputGlyphs.plain("{unknown} {}") == "{unknown} {}", "unknown names stay literal")
	# A rebound key shows up in the prompt.
	var prefs: FragrSettings = FragrSettings.new("user://glyphs-unused.cfg")
	InputBindings.assign(prefs, "interact", 0, "key:71")
	prefs.apply_controls()
	InputDevice.force(InputDevice.Kind.KEYBOARD)
	_check(InputGlyphs.plain("{use}") == "G", "prompts follow rebinding")
	FragrSettings.new("user://glyphs-unused.cfg").apply_controls()

func _test_glyph_images() -> void:
	var seen: Dictionary = {}
	for layout: String in ["letters", "shapes", "generic"]:
		for token: String in ["pad:b0", "pad:b1", "pad:b2", "pad:b3", "pad:b9", "pad:b10", "pad:a4+", "pad:a5+", "pad:b4", "pad:b6", "pad:b7", "pad:b8", "pad:b11", "pad:b12", "pad:b13", "pad:b14"]:
			var image: Image = InputGlyphs.glyph_image(token, layout)
			_check(image.get_size() == Vector2i(16, 16), "glyphs are 16 pixel sprites")
			var used: int = 0
			for y: int in range(16):
				for x: int in range(16):
					if image.get_pixel(x, y).a > 0.0:
						used += 1
			_check(used > 40, "glyph %s %s is drawn" % [token, layout])
			seen[layout + token] = image.get_data()
	for button: String in ["pad:b0", "pad:b1", "pad:b2", "pad:b3"]:
		_check(seen["letters" + button] != seen["shapes" + button] and seen["shapes" + button] != seen["generic" + button], "face glyph %s differs by layout" % button)
	_check(seen["generic" + "pad:b0"] != seen["generic" + "pad:b3"], "positional glyphs mark different buttons")
	_check(InputGlyphs.glyph("pad:b0", "letters") == InputGlyphs.glyph("pad:b0", "letters"), "glyph textures are cached")

func _test_mission_prompt() -> void:
	var hud: MissionHud = MissionHud.new()
	root.add_child(hud)
	await process_frame
	var state: Dictionary = {"id": MissionState.ID, "phase": "find_transfer", "attempt": 1, "rules": {"difficulty": "standard"}, "party": [], "prompts": [{"player_id": "me", "kind": "transfer_record"}]}
	InputDevice.force(InputDevice.Kind.KEYBOARD)
	hud.apply(state, "me")
	_check(hud.prompt_text == "F: READ TRANSFER RECORD" and hud._prompt.visible, "keyboard use prompt in the HUD")
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "letters")
	hud._process(0.0)
	_check(hud.prompt_text == "B: READ TRANSFER RECORD", "the HUD prompt follows a device switch without a new mission state")
	_check(hud._prompt.get_parsed_text().contains("READ TRANSFER RECORD"), "the glyph prompt still carries its words")
	hud.free()
