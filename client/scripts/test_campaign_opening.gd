extends SceneTree

var failures: int = 0
var completions: int = 0
var settings_path: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://opening-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	call_deferred("_run")

func _finalize() -> void:
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_campaign_opening: " + message)

func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func _run() -> void:
	var navigation: Dictionary[Key, String] = {KEY_LEFT: "ui_left", KEY_UP: "ui_up", KEY_RIGHT: "ui_right", KEY_DOWN: "ui_down"}
	for code: Key in navigation:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = code
		_expect(key.is_action(navigation[code]), "controller additions preserve arrow bindings: " + navigation[code])
	root.size = Vector2i(1280, 960)
	var opening: CampaignOpening = CampaignOpening.new()
	opening.completed.connect(func() -> void: completions += 1)
	root.add_child(opening)
	await process_frame
	await process_frame
	_expect(opening.page == 0 and opening._back.disabled, "first page has no previous beat")
	_expect(opening._body.text.contains("Latch") and not opening._body.text.contains("STORY_"), "keyed script is loaded")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "story releases pointer")
	await _key(KEY_ENTER, true)
	await _key(KEY_ENTER, false)
	_expect(opening.page == 1 and completions == 0, "real Enter event advances without completing")
	opening._back.grab_focus()
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	Input.parse_input_event(pad)
	await process_frame
	pad = pad.duplicate()
	pad.pressed = false
	Input.parse_input_event(pad)
	await process_frame
	_expect(opening.page == 0, "controller activates the previous-page button: page=%d, accepted=%s, focus=%s" % [opening.page, pad.is_action("ui_accept"), root.gui_get_focus_owner()])
	var expanded: Translation = Translation.new()
	expanded.locale = "de"
	expanded.add_message("STORY_M01_HOME_BODY", "Überarbeitung. Freiheit für alle. ".repeat(300))
	TranslationServer.add_translation(expanded)
	TranslationServer.set_locale("de")
	await process_frame
	await process_frame
	_expect(opening._body.text.begins_with("Überarbeitung"), "existing page refreshes when locale changes")
	_expect(opening._body.size.y > opening._scroll.size.y, "long text remains scrollable instead of truncated")
	_expect(opening._next.get_global_rect().end.y <= root.get_visible_rect().size.y, "expanded text keeps controls on screen")
	await _key(KEY_PAGEDOWN, true)
	await _key(KEY_PAGEDOWN, false)
	_expect(opening._scroll.scroll_vertical > 0 and opening._scroll_hint.visible, "keyboard can reach expanded text")
	pad = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_LEFT_SHOULDER
	pad.pressed = true
	Input.parse_input_event(pad)
	await process_frame
	pad = pad.duplicate()
	pad.pressed = false
	Input.parse_input_event(pad)
	await process_frame
	_expect(opening._scroll.scroll_vertical == 0, "controller can scroll expanded text back")
	TranslationServer.set_locale("en")
	TranslationServer.remove_translation(expanded)
	await process_frame
	while opening.page < CampaignOpening.BEATS.size() - 1:
		opening.advance()
	_expect(completions == 0 and opening._next.text == tr("STORY_FINISH"), "reaching the last page does not auto-finish")
	opening.advance()
	opening.finish()
	_expect(completions == 1, "completion emits once without requiring narration")
	opening.free()

	var menu: Control = load("res://scripts/boot_menu.gd").new()
	root.add_child(menu)
	await process_frame
	menu._show("single")
	await process_frame
	menu._replay_opening()
	await process_frame
	_expect(is_instance_valid(menu._opening), "menu reuses the opening presenter")
	_expect(menu._local_match.state == LocalMatch.State.IDLE and not has_meta("fragr_boot"), "replay launches no game session")
	await _key(KEY_ESCAPE, true)
	await _key(KEY_ESCAPE, false)
	_expect(not is_instance_valid(menu._opening) and menu._page == "single", "Escape closes replay without dismissing its underlying menu")
	_expect(menu._local_match.state == LocalMatch.State.IDLE and not has_meta("fragr_boot"), "closing replay mutates no game session")
	menu.free()
	await process_frame
	await process_frame
	if failures == 0:
		print("test_campaign_opening: PASS paging, input, localization, completion and offline replay")
	quit(0 if failures == 0 else 1)
