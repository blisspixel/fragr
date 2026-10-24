extends SceneTree

## The radio's two faces: the brief now-playing toast in the HUD and the
## Music / Radio area of the match menu. Both read the radio's own state, so
## no label claims a song after playback stops. With FRAGR_RADIO_CAPTURE set
## and a window, the toast, the match menu and the Controls page are saved as
## PNGs for inspection (run with --audio-driver Dummy).

const RadioScript := preload("res://scripts/radio.gd")

var _failures: int = 0
var _settings_path: String = ""
var hud: CanvasLayer

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_settings_path = "user://radio-controls-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", _settings_path)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_radio_controls: " + message)

func _run() -> void:
	# A stopped decoder is released only after a mixer turn. The radio this
	# harness frees must retire before quit, as it does in the game.
	var retirement: ClientRetirement = ClientRetirement.for_tree(self)
	root.size = Vector2i(1280, 720)
	if _capturing():
		var background: ColorRect = ColorRect.new()
		background.color = MenuTheme.SURFACE.darkened(0.3)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(background)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	hud = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	await process_frame
	hud.set_process(false)
	await _test_toast()
	hud.queue_free()
	await process_frame
	await _test_pause_menu()
	await _test_controls_page()
	InputDevice.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings_path))
	_check(await retirement.drain(), "every radio decoder retires before the harness exits")
	if _failures == 0:
		print("test_radio_controls: PASS now-playing toast lifetime and states, match menu music controls, controls page radio rows")
	quit(0 if _failures == 0 else 1)

func _capturing() -> bool:
	return not OS.get_environment("FRAGR_RADIO_CAPTURE").is_empty() and DisplayServer.get_name() != "headless"

func _capture(name: String) -> void:
	if not _capturing():
		return
	for i: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var directory: String = OS.get_environment("FRAGR_RADIO_CAPTURE")
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "capture directory")
	_check(root.get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, "save capture " + name)

func _stations(station_count: int = 3) -> Array:
	var list: Array = []
	var entries: Dictionary = {}
	for index: int in range(station_count):
		var id: String = "s%d" % index
		list.append({"id": id, "name": "Station %d" % index, "badge": "S%d" % index, "dj": "DJ %d" % index if index == 0 else ""})
		if index < station_count - 1:
			entries["radio/%s/01" % id] = {"file": "radio/lockin/01-push.mp3", "title": "Song on %d" % index}
	return RadioScript.build_stations(list, entries)

func _test_toast() -> void:
	_check(not hud.radio_toast_visible(), "no toast before the radio speaks")
	InputDevice.force(InputDevice.Kind.KEYBOARD)
	var long_title: String = "Overnight Extended Remix For The Five Levels Of The Larak Lot Parking Structure"
	hud.show_now_playing({"state": "playing", "station": "Larak Lot Rock", "badge": "LR", "title": long_title})
	await process_frame
	_check(hud.radio_toast_visible() and hud.radio_card.modulate.a == 1.0, "a station change shows the toast at full strength")
	_check(hud.radio_card_name.text == "LARAK LOT ROCK" and hud.radio_card_title.text == long_title, "the toast names the station and the song")
	_check(hud.radio_card.rotation == 0.0, "the toast is level")
	_check(hud.radio_card_title.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS and hud.radio_card_title.max_lines_visible == 1, "a long title trims to one line")
	# Background flavour: no station badge, no controls line, a small corner card.
	_check(_card_texts() == ["LARAK LOT ROCK", long_title], "the toast carries only the station and the song: " + str(_card_texts()))
	_check(hud.find_child("RadioLabel", true, false) == null, "no radio controls line in combat")
	var view: Rect2 = root.get_visible_rect()
	var card: Rect2 = hud.radio_card.get_global_rect()
	_check(view.encloses(card), "the toast stays on screen")
	_check(card.size.x <= view.size.x * 0.36 and card.size.y <= view.size.y * 0.11, "the toast stays small: %s in %s" % [str(card.size), str(view.size)])
	_check(card.position.x >= view.size.x * 0.5 and card.end.y >= view.size.y * 0.5, "the toast sits in the lower right corner")
	for line: Label in [hud.radio_card_name, hud.radio_card_title]:
		_check(card.encloses(line.get_global_rect()), "each toast line fits inside the card")
	await _capture("radio-toast-keyboard")
	hud.tick_radio_toast(_hold() - 0.1)
	_check(hud.radio_toast_visible() and is_equal_approx(hud.radio_card.modulate.a, 1.0), "the toast holds before fading")
	hud.tick_radio_toast(0.4)
	_check(hud.radio_card.modulate.a < 1.0 and hud.radio_card.modulate.a > 0.0, "then fades")
	hud.show_now_playing({"state": "playing", "station": "Signal Bleed", "badge": "SB", "title": "Tempo Locked"})
	_check(hud.radio_card.modulate.a == 1.0 and hud.radio_toast_age == 0.0, "a new change restarts the toast")
	hud.tick_radio_toast(_hold() + _fade() + 0.01)
	_check(not hud.radio_toast_visible(), "the toast leaves after hold and fade")
	hud.tick_radio_toast(1.0)
	_check(not hud.radio_toast_visible(), "and stays gone")
	var states: Dictionary = {
		"off": ["RADIO OFF", "SIGNAL BLEED"],
		"off_air": ["SIGNAL BLEED", "Off the air. No tracks yet."],
		"unavailable": ["SIGNAL BLEED", "Track unavailable. Skip or change station."],
		"held": ["SIGNAL BLEED", "Tempo Locked (paused for the scene)"],
	}
	for state: String in states:
		hud.show_now_playing({"state": state, "station": "Signal Bleed", "badge": "SB", "title": "Tempo Locked" if state == "held" else ""})
		_check(hud.radio_card_name.text == states[state][0] and hud.radio_card_title.text == states[state][1],
			"%s reads %s, got %s / %s" % [state, str(states[state]), hud.radio_card_name.text, hud.radio_card_title.text])
	var off_line: Dictionary = hud.radio_toast_lines({"state": "off", "station": "X", "title": "Stale"})
	_check(not str(off_line["detail"]).contains("Stale"), "an off radio never names a stale song")
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "shapes")
	hud.show_now_playing({"state": "playing", "station": "Dead Air", "badge": "DA", "title": "3 AM"})
	await process_frame
	_check(_card_texts() == ["DEAD AIR", "3 AM"], "a pad gets the same small card: " + str(_card_texts()))
	# A short station and song get a short card, still holding its text.
	var short_card: Rect2 = hud.radio_card.get_global_rect()
	_check(short_card.size.x < card.size.x and short_card.size.x <= 300.0, "a short song gets a narrower card: %s" % str(short_card.size))
	_check(is_equal_approx(short_card.end.x, card.end.x), "the narrow card keeps the same right edge")
	for line: Label in [hud.radio_card_name, hud.radio_card_title]:
		var font: Font = line.get_theme_font("font")
		var needed: float = font.get_string_size(line.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, line.get_theme_font_size("font_size")).x
		_check(line.size.x >= needed, "the narrow card does not trim %s (%d of %d px)" % [line.text, int(line.size.x), int(needed)])
	await _capture("radio-toast-pad")
	InputDevice.force(InputDevice.Kind.KEYBOARD)

## Every visible text in the toast, in reading order.
func _card_texts() -> Array[String]:
	var texts: Array[String] = []
	for node: Node in hud.radio_card.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.is_visible_in_tree() and not label.text.is_empty():
			texts.append(label.text)
	return texts

func _hold() -> float:
	return float(hud.RADIO_TOAST_HOLD)

func _fade() -> float:
	return float(hud.RADIO_TOAST_FADE)

func _test_pause_menu() -> void:
	var prefs: FragrSettings = FragrSettings.new(_settings_path)
	prefs.reset_all()
	var menu: PauseMenu = PauseMenu.new()
	menu.preferences = prefs
	root.add_child(menu)
	await process_frame
	menu.refresh_music()
	_check(menu._music_station.text == tr("RADIO_STATE_NONE"), "no radio says so")
	for button: Button in menu._music_buttons.values():
		_check(button.disabled, "every radio button is disabled without a radio: " + button.name)
	var radio: Node = RadioScript.new()
	# Every station change replaces the decoder; each old one retires too.
	# Connected before add_child, because _ready already starts a real track.
	var retirement: ClientRetirement = ClientRetirement.for_tree(self)
	radio.track_started.connect(func(_station: String, _title: String) -> void: retirement.track_audio(radio))
	root.add_child(radio)
	await process_frame
	radio.stations = _stations()
	radio.station_index = 0
	radio.enabled = true
	radio.play_random()
	menu.bind_radio(radio)
	InputDevice.force(InputDevice.Kind.KEYBOARD)
	menu.open()
	await process_frame
	_check(menu._music_station.text.begins_with("STATION 0  1/3") and menu._music_station.text.contains("DJ 0"), "the match menu names the station, dial position and DJ: " + menu._music_station.text)
	_check(menu._music_title.text == tr("MENU_RADIO_NOW_PLAYING").format({"title": "Song on 0"}), "and the song: " + menu._music_title.text)
	var next: Button = menu._music_buttons["radio_next_station"]
	_check(next.text.contains("[C]") and (menu._music_buttons["radio_prev_station"] as Button).text.contains("[X]"), "buttons show the bound keys: " + next.text)
	await _capture("radio-match-menu-keyboard")
	next.pressed.emit()
	_check(radio.station_index == 1 and menu._music_station.text.begins_with("STATION 1"), "the button turns the same dial as the key")
	next.pressed.emit()
	_check(menu._music_title.text == tr("RADIO_STATE_OFF_AIR") and (menu._music_buttons["radio_next_track"] as Button).disabled, "an empty station disables skip")
	next.pressed.emit()
	_check(menu._music_station.text.begins_with(tr("RADIO_STATE_OFF")) and (menu._music_buttons["radio_toggle"] as Button).text.begins_with(tr("MENU_RADIO_ON")), "RADIO OFF offers to switch on")
	_check(radio.now_playing()["title"] == "" and not radio.player.playing, "no stale playing label after the radio stops")
	(menu._music_buttons["radio_toggle"] as Button).pressed.emit()
	_check(radio.enabled and radio.station_index == 2 and menu._music_title.text == tr("RADIO_STATE_OFF_AIR"), "power on returns to the last station")
	(menu._music_buttons["radio_prev_station"] as Button).pressed.emit()
	_check(radio.station_index == 1 and menu._music_title.text.contains("Song on 1"), "previous station from the menu")
	# A shortcut pressed while the menu is open updates the menu too.
	radio.next_track()
	_check(menu._music_title.text.contains("Song on"), "a shortcut refreshes the open menu")
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "letters")
	menu._process(0.0)
	_check((menu._music_buttons["radio_next_track"] as Button).text.contains("HOLD D-RIGHT"), "on a pad, skip reads as the D-pad hold: " + (menu._music_buttons["radio_next_track"] as Button).text)
	_check((menu._music_buttons["radio_toggle"] as Button).text.contains("HOLD D-LEFT"), "and power as the other hold")
	for i: int in range(2):
		await process_frame
	var frame: Rect2 = menu._panel.get_global_rect()
	for button: Button in menu._music_buttons.values():
		_check(frame.encloses(button.get_global_rect()), "the menu panel holds the radio button " + button.name)
	_check(root.get_visible_rect().encloses(frame), "the match menu stays on screen with the music area")
	var announcer_label: Label = menu.find_child("AnnouncerVolumeLabel", true, false) as Label
	_check(announcer_label != null and announcer_label.text == tr("MENU_ANNOUNCER_VOLUME") and frame.encloses(announcer_label.get_global_rect()), "the announcer slider is named in the match menu")
	await _capture("radio-match-menu-pad")
	# The D-pad moves the menu focus; it must not also turn the dial behind it.
	var before_index: int = radio.station_index
	var before_enabled: bool = radio.enabled
	for direction: JoyButton in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_LEFT]:
		for pressed: bool in [true, false]:
			var pad: InputEventJoypadButton = InputEventJoypadButton.new()
			pad.button_index = direction
			pad.pressed = pressed
			Input.parse_input_event(pad)
			await process_frame
	await process_frame
	_check(radio.station_index == before_index and radio.enabled == before_enabled, "D-pad in the open match menu leaves the station alone (%d to %d)" % [before_index, radio.station_index])
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await process_frame
	_check(radio.station_index == before_index, "a station key does not act behind the open match menu either")
	menu._music_volume.value = 0.0
	_check(menu._music_volume_note.visible, "volume zero says the radio is still playing")
	_check(is_equal_approx(float(prefs.get_value("audio", "music")), 0.7), "volume is a draft until the menu closes")
	menu.close()
	_check(is_equal_approx(float(prefs.get_value("audio", "music")), 0.0), "closing the menu saves the music volume")
	var shortcut: InputEventKey = InputEventKey.new()
	shortcut.physical_keycode = KEY_C
	shortcut.pressed = true
	var closed_index: int = radio.station_index
	_check(not radio.shortcuts_blocked and radio.handle_input(shortcut) and radio.station_index != closed_index, "with the menu closed the station key turns the dial again")
	radio.prev_station()
	var saved: FragrSettings = FragrSettings.new(_settings_path)
	saved.load_from_disk()
	_check(is_equal_approx(float(saved.get_value("audio", "music")), 0.0), "the volume reached the settings file")
	menu.open()
	await process_frame
	_check(is_equal_approx(menu._music_volume.value, 0.0) and menu._music_title.text.contains("Song on"), "reopening shows the live state")
	# A pad nudges the slider without a drag end; the Audio page must not lose
	# its own later choice to that pending value when the menu closes.
	menu._music_volume.value = 0.3
	menu.show_settings()
	_check(is_equal_approx(float(prefs.get_value("audio", "music")), 0.3), "opening Settings saves the pending slider value first")
	var audio_page: FragrSettings = prefs.draft()
	audio_page.set_value("audio", "music", 0.5)
	_check(prefs.commit(audio_page) == OK, "the Audio page saves")
	menu._hide_settings()
	_check(is_equal_approx(menu._music_volume.value, 0.5), "back in the menu, the slider shows the Audio page's value")
	menu.close()
	_check(is_equal_approx(float(prefs.get_value("audio", "music")), 0.5), "closing the menu keeps the Audio page's value")
	root.remove_child(radio)
	radio.free()
	menu.refresh_music()
	menu.bind_radio(null)
	_check(menu._music_station.text == tr("RADIO_STATE_NONE"), "leaving the scene drops the radio")
	menu.queue_free()
	FragrSettings.new(_settings_path + ".defaults").apply_audio()
	await process_frame

func _test_controls_page() -> void:
	var prefs: FragrSettings = FragrSettings.new(_settings_path)
	prefs.reset_all()
	var panel: SettingsPanel = SettingsPanel.new()
	panel.preferences = prefs
	panel.custom_minimum_size = Vector2(1200, 680)
	panel.position = Vector2(40, 20)
	panel.size = Vector2(1200, 680)
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "shapes")
	root.add_child(panel)
	await process_frame
	await process_frame
	var skip: Button = panel.find_child("bind_radio_next_track_2", true, false) as Button
	var prev: Button = panel.find_child("bind_radio_prev_station_2", true, false) as Button
	_check(prev != null and prev.text == "D-LEFT", "the controls page shows D-pad left for the previous station")
	_check(skip != null and skip.text == "HOLD D-RIGHT", "an empty skip pad slot shows its hold gesture: " + (skip.text if skip != null else "missing"))
	_check(panel.find_child("RadioHoldNote", true, false) is Label, "the page explains the radio holds")
	var reload: Button = panel.find_child("bind_reload_2", true, false) as Button
	_check(reload != null and reload.text == "SQUARE", "PlayStation names on the controls page: " + (reload.text if reload != null else "missing"))
	var scroll: ScrollContainer = panel.get("_scroll")
	var note: Control = panel.find_child("RadioHoldNote", true, false) as Control
	if scroll != null and note != null:
		scroll.ensure_control_visible(note)
	await _capture("controls-page-radio-playstation")
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "letters")
	panel._process(0.0)
	_check(reload.text == "X", "Xbox names on the same page")
	await _capture("controls-page-radio-xbox")
	panel.show_page("AUDIO")
	_check(panel.find_child("announcer", true, false) is OptionButton, "the Audio page offers the announcer next to the radio volume")
	await _capture("settings-audio")
	panel.queue_free()
	await process_frame
