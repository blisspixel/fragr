extends CanvasLayer
class_name PauseMenu

## Escape opens the match menu. The server has no pause command yet, including
## solo sessions. Keep snapshots flowing and neutralize input in game_manager.

signal resume_requested
signal leave_requested
signal stop_server_requested

var _open: bool = false
var _panel: Panel = null
var _column: VBoxContainer = null
var _note: Label = null
var _leave_button: Button = null
## True only for the owned local campaign. Arena and joined servers keep the live-match note.
var local_campaign: bool = false
## A development mission keeps no run, so leaving never promises a save.
var development_mission: bool = false
var hosting_server: bool = false
var preferences: FragrSettings
var _settings_panel: SettingsPanel
var _settings_frame: PanelContainer
var _centre: CenterContainer
var _hint: Label
## The match radio, when there is one. Buttons call the same methods as the
## shortcuts, and every label reads `radio.now_playing()`.
var radio: Node = null
var _music_box: VBoxContainer
var _music_station: Label
var _music_title: Label
var _music_buttons: Dictionary = {}
var _music_volume: HSlider
var _music_volume_note: Label
## Settings > Audio > Announcer, here too so the Host can be quieted mid-match.
var _announcer_mode: OptionButton
var _announcer_volume: HSlider
## Menu audio changes are heard at once and written on drag end or close.
## Only the keys this menu owns are copied, so the Audio page keeps the rest.
const MENU_AUDIO_KEYS: Array[String] = ["music", "announcer", "announcer_volume"]
var _audio_draft: FragrSettings = null
var _music_revision: int = -1

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	MenuFocus.attach(self)
	_build()
	visible = false

func _build() -> void:
	var veil: ColorRect = ColorRect.new()
	veil.color = MenuTheme.alpha(MenuTheme.INK, 0.75)
	veil.anchor_right = 1.0
	veil.anchor_bottom = 1.0
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	var centre: CenterContainer = CenterContainer.new()
	centre.theme = MenuTheme.build(MenuTheme.Context.GAMEPLAY)
	centre.anchor_right = 1.0
	centre.anchor_bottom = 1.0
	_centre = centre
	add_child(centre)

	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", MenuTheme.panel())
	_panel.custom_minimum_size = Vector2(700.0, 430.0)
	centre.add_child(_panel)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 10)
	_column.anchor_right = 1.0
	_column.offset_left = 24.0
	_column.offset_top = 24.0
	_column.offset_right = -24.0
	_panel.add_child(_column)

	var title: Label = Label.new()
	title.text = "MATCH MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", MenuTheme.BODY)
	_column.add_child(title)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(640.0, 0.0)
	_note.add_theme_font_size_override("font_size", MenuTheme.BODY)
	_note.add_theme_color_override("font_color", MenuTheme.EMBER)
	_column.add_child(_note)

	_add_button("Resume", func() -> void: close())
	_add_button("Settings", show_settings)
	_leave_button = _add_button("Leave match", func() -> void:
		close()
		leave_requested.emit()
	)
	if hosting_server:
		_add_button(tr("HOST_STOP"), func() -> void:
			close()
			stop_server_requested.emit())
	_add_button("Quit to desktop", func() -> void: ClientRetirement.for_tree(get_tree()).request_quit())
	_build_music()

	var hint: Label = Label.new()
	_hint = hint
	hint.text = InputGlyphs.plain(tr("MENU_PAUSE_HINT"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", MenuTheme.BODY)
	hint.add_theme_color_override("font_color", MenuTheme.BONE)
	_column.add_child(hint)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 16.0)
	_column.add_child(spacer)

func _add_button(text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 42.0)
	b.pressed.connect(handler)
	_column.add_child(b)
	return b

## The panel is not a container, so grow it to the column it holds.
func _fit_panel() -> void:
	var content: Vector2 = _column.get_combined_minimum_size()
	_panel.custom_minimum_size = Vector2(maxf(700.0, content.x + 48.0), maxf(430.0, content.y + 48.0))

## --- Music / Radio ------------------------------------------------------------

func _build_music() -> void:
	_music_box = VBoxContainer.new()
	_music_box.name = "Music"
	_music_box.add_theme_constant_override("separation", 6)
	_column.add_child(_music_box)
	var header: Label = Label.new()
	header.text = tr("MENU_MUSIC_HEADER")
	header.add_theme_font_size_override("font_size", MenuTheme.BODY)
	header.add_theme_color_override("font_color", MenuTheme.EMBER)
	_music_box.add_child(header)
	_music_station = _music_line("Station")
	_music_title = _music_line("Title")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	_music_box.add_child(grid)
	for entry: Array in [["Prev", "radio_prev_station"], ["Next", "radio_next_station"], ["Skip", "radio_next_track"], ["Power", "radio_toggle"]]:
		var button: Button = Button.new()
		button.name = "Radio" + str(entry[0])
		button.custom_minimum_size = Vector2(316.0, 42.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_music_button.bind(str(entry[1])))
		grid.add_child(button)
		_music_buttons[str(entry[1])] = button
	var volume_row: HBoxContainer = HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	_music_box.add_child(volume_row)
	var volume_label: Label = Label.new()
	volume_label.text = tr("MENU_MUSIC_VOLUME")
	volume_label.add_theme_font_size_override("font_size", MenuTheme.BODY)
	volume_row.add_child(volume_label)
	_music_volume = HSlider.new()
	_music_volume.name = "MusicVolume"
	_music_volume.min_value = 0.0
	_music_volume.max_value = 1.0
	_music_volume.step = 0.05
	_music_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_music_volume.value_changed.connect(_on_music_volume)
	_music_volume.drag_ended.connect(func(_changed: bool) -> void: commit_audio())
	volume_row.add_child(_music_volume)
	_music_volume_note = _music_line("VolumeNote")
	_music_volume_note.add_theme_color_override("font_color", MenuTheme.MUTED)
	_build_announcer()

## One row: who speaks (On, Big moments only, Off) and how loud.
func _build_announcer() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Announcer"
	row.add_theme_constant_override("separation", 12)
	_column.add_child(row)
	var label: Label = Label.new()
	label.text = tr("SETTINGS_ANNOUNCER")
	label.add_theme_font_size_override("font_size", MenuTheme.BODY)
	row.add_child(label)
	_announcer_mode = OptionButton.new()
	_announcer_mode.name = "AnnouncerMode"
	_announcer_mode.custom_minimum_size = Vector2(260.0, 42.0)
	for text: String in FragrSettings.announcer_labels():
		_announcer_mode.add_item(text)
	_announcer_mode.item_selected.connect(func(index: int) -> void:
		_set_menu_audio("announcer", FragrSettings.ANNOUNCER_MODES[index])
		commit_audio())
	row.add_child(_announcer_mode)
	# Name the slider: without it the row reads as a second music control.
	var volume_label: Label = Label.new()
	volume_label.name = "AnnouncerVolumeLabel"
	volume_label.text = tr("MENU_ANNOUNCER_VOLUME")
	volume_label.add_theme_font_size_override("font_size", MenuTheme.BODY)
	row.add_child(volume_label)
	_announcer_volume = HSlider.new()
	_announcer_volume.name = "AnnouncerVolume"
	_announcer_volume.min_value = 0.0
	_announcer_volume.max_value = 1.0
	_announcer_volume.step = 0.05
	_announcer_volume.custom_minimum_size.x = 180.0
	_announcer_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_announcer_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_announcer_volume.value_changed.connect(func(value: float) -> void: _set_menu_audio("announcer_volume", value))
	_announcer_volume.drag_ended.connect(func(_changed: bool) -> void: commit_audio())
	row.add_child(_announcer_volume)

func _music_line(node_name: String) -> Label:
	var line: Label = Label.new()
	line.name = node_name
	# Full text wraps here; the HUD toast only trims it.
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(640.0, 0.0)
	line.add_theme_font_size_override("font_size", MenuTheme.BODY)
	_music_box.add_child(line)
	return line

## Attach the match radio. Safe before or after the menu enters the tree.
func bind_radio(node: Node) -> void:
	if radio != null and radio.has_signal("now_playing_changed") and radio.is_connected("now_playing_changed", _on_now_playing):
		radio.disconnect("now_playing_changed", _on_now_playing)
	_block_radio_shortcuts(false)
	radio = node
	if radio != null and radio.has_signal("now_playing_changed"):
		radio.connect("now_playing_changed", _on_now_playing)
	_block_radio_shortcuts(_open)
	refresh_music()

## While the menu is open its buttons own the radio; the station shortcuts
## (D-pad arms included) would otherwise act behind the focused button.
func _block_radio_shortcuts(on: bool) -> void:
	if is_instance_valid(radio) and "shortcuts_blocked" in radio:
		radio.set("shortcuts_blocked", on)

func _exit_tree() -> void:
	_block_radio_shortcuts(false)

func _on_now_playing(_info: Dictionary) -> void:
	if _open:
		refresh_music()

func _on_music_button(action: String) -> void:
	if radio == null:
		return
	match action:
		"radio_prev_station": radio.call("prev_station")
		"radio_next_station": radio.call("next_station")
		"radio_next_track": radio.call("next_track")
		"radio_toggle": radio.call("toggle")
	refresh_music()

## What a shortcut is on the device in use. On a gamepad without its own skip
## or power button, those are holds on the D-pad station arms.
static func radio_shortcut(action: String) -> String:
	if InputDevice.is_gamepad() and InputBindings.live_token(action, true).is_empty():
		var arm: String = str({"radio_next_track": "radio_next_station", "radio_toggle": "radio_prev_station"}.get(action, ""))
		if not arm.is_empty() and not InputBindings.live_token(arm, true).is_empty():
			return TranslationServer.translate("MENU_RADIO_HOLD").format({"input": InputGlyphs.action_name(arm)})
	return InputGlyphs.action_name(action)

func music_state() -> String:
	if radio == null or not radio.has_method("now_playing"):
		return "none"
	return str((radio.call("now_playing") as Dictionary).get("state", "none"))

## Rebuild every music label from the radio's own state.
func refresh_music() -> void:
	if _music_box == null:
		return
	_music_revision = InputDevice.revision
	var info: Dictionary = radio.call("now_playing") if radio != null and radio.has_method("now_playing") else {"state": "none"}
	var state: String = str(info.get("state", "none"))
	var station: String = str(info.get("station", "")).to_upper()
	if state == "none":
		_music_station.text = tr("RADIO_STATE_NONE")
	elif state == "off":
		_music_station.text = tr("RADIO_STATE_OFF") + "  //  " + station
	else:
		var dj: String = str(info.get("dj", ""))
		_music_station.text = "%s  %d/%d%s" % [station, int(info.get("index", 0)) + 1, int(info.get("count", 0)), ("  //  " + dj.to_upper()) if not dj.is_empty() else ""]
	_music_title.text = _state_line(info)
	_music_title.add_theme_color_override("font_color", MenuTheme.BONE if state == "playing" else MenuTheme.MUTED)
	var labels: Dictionary = {
		"radio_prev_station": tr("MENU_RADIO_PREV"),
		"radio_next_station": tr("MENU_RADIO_NEXT"),
		"radio_next_track": tr("MENU_RADIO_SKIP"),
		"radio_toggle": tr("MENU_RADIO_ON") if state == "off" else tr("MENU_RADIO_OFF"),
	}
	for action: String in _music_buttons:
		var button: Button = _music_buttons[action]
		button.text = "%s  [%s]" % [labels[action], radio_shortcut(action)]
		button.disabled = state == "none" or (action == "radio_next_track" and state in ["off", "off_air"])
	var volume: float = float(_menu_audio("music", 1.0))
	_music_volume.set_value_no_signal(volume)
	_music_volume.editable = preferences != null
	_update_volume_note(volume)
	_announcer_mode.select(maxi(0, FragrSettings.ANNOUNCER_MODES.find(int(_menu_audio("announcer", FragrSettings.ANNOUNCER_ON)))))
	_announcer_mode.disabled = preferences == null
	_announcer_volume.set_value_no_signal(float(_menu_audio("announcer_volume", 1.0)))
	_announcer_volume.editable = preferences != null
	_fit_panel()

func _state_line(info: Dictionary) -> String:
	var title: String = str(info.get("title", ""))
	match str(info.get("state", "")):
		"playing":
			return tr("MENU_RADIO_NOW_PLAYING").format({"title": title}) + (("  " + tr("MENU_RADIO_DUCKED")) if bool(info.get("ducked", false)) else "")
		"held":
			return tr("RADIO_STATE_HELD").format({"title": title})
		"off":
			return tr("MENU_RADIO_OFF_NOTE")
		"off_air":
			return tr("RADIO_STATE_OFF_AIR")
		"unavailable":
			return tr("RADIO_STATE_UNAVAILABLE")
		"idle":
			return tr("RADIO_STATE_IDLE")
	return ""

## Volume zero is not stopped playback, so say which one it is.
func _update_volume_note(volume: float) -> void:
	_music_volume_note.text = tr("MENU_MUSIC_VOLUME_ZERO") if volume <= 0.0 and music_state() == "playing" else ""
	_music_volume_note.visible = not _music_volume_note.text.is_empty()

func _on_music_volume(value: float) -> void:
	_set_menu_audio("music", value)
	_update_volume_note(value)

func _menu_audio(key: String, fallback: Variant) -> Variant:
	if _audio_draft != null:
		return _audio_draft.get_value("audio", key)
	if preferences != null:
		return preferences.get_value("audio", key)
	return fallback

func _set_menu_audio(key: String, value: Variant) -> void:
	if preferences == null:
		return
	if _audio_draft == null:
		_audio_draft = preferences.draft()
	_audio_draft.set_value("audio", key, value)
	# Heard at once; written when the drag ends or the menu closes.
	_audio_draft.apply_audio()

func commit_audio() -> void:
	if _audio_draft == null or preferences == null:
		return
	var draft: FragrSettings = _audio_draft
	_audio_draft = null
	var candidate: FragrSettings = preferences.draft()
	for key: String in MENU_AUDIO_KEYS:
		candidate.set_value("audio", key, draft.get_value("audio", key))
	if preferences.commit(candidate) != OK:
		push_warning("pause_menu: audio settings could not be saved")
		preferences.apply_audio()

func _process(_delta: float) -> void:
	if _open and _music_revision != InputDevice.revision:
		refresh_music()

func is_open() -> bool:
	return _open

## The owned Single Player process, or an explicit test flag. A joined server
## and an arena match leave local_match empty.
func _local_campaign_run() -> bool:
	if local_campaign:
		return true
	var node: Node = get_parent()
	while node != null:
		if node.get("local_match") != null:
			return true
		node = node.get_parent()
	return false

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _open and _note != null:
		_refresh_note()

func _refresh_note() -> void:
	if development_mission:
		_note.text = tr("MENU_EXIT_DEVELOPMENT")
	else:
		_note.text = tr("MENU_EXIT_SAVES_RUN" if _local_campaign_run() else "MENU_LIVE_MATCH")
	_leave_button.text = tr("RUN_EXIT_MENU") if _local_campaign_run() else "Leave match"
	_hint.text = InputGlyphs.plain(tr("MENU_PAUSE_HINT"))

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_block_radio_shortcuts(true)
	_refresh_note()
	refresh_music()
	_fit_panel()
	MouseCapture.release()
	await get_tree().process_frame
	for child in _column.get_children():
		if child is Button:
			(child as Button).grab_focus()
			break

func close() -> void:
	if not _open:
		return
	_open = false
	_block_radio_shortcuts(false)
	_hide_settings()
	commit_audio()
	visible = false
	resume_requested.emit()

func toggle() -> void:
	if is_instance_valid(_settings_panel):
		_hide_settings()
	elif _open:
		close()
	else:
		open()

func show_settings() -> void:
	if preferences == null or is_instance_valid(_settings_panel):
		return
	# Save a pending menu slider change first, so the Audio page starts from
	# it and closing the menu later cannot write it over the page's choice.
	commit_audio()
	_panel.visible = false
	_settings_panel = SettingsPanel.new()
	_settings_panel.theme_context = MenuTheme.Context.GAMEPLAY
	_settings_panel.name = "SettingsPanel"
	_settings_panel.custom_minimum_size.x = 1200
	_settings_panel.preferences = preferences
	_settings_panel.closed.connect(_hide_settings)
	_settings_frame = PanelContainer.new()
	var frame: StyleBoxFlat = MenuTheme.panel()
	frame.content_margin_top = 24
	frame.content_margin_bottom = 24
	frame.content_margin_left = 24
	frame.content_margin_right = 24
	_settings_frame.add_theme_stylebox_override("panel", frame)
	_settings_frame.add_child(_settings_panel)
	_centre.add_child(_settings_frame)
	_settings_panel.focus_first()

func _hide_settings() -> void:
	if is_instance_valid(_settings_panel):
		_centre.remove_child(_settings_frame)
		_settings_frame.queue_free()
		_settings_panel = null
		_settings_frame = null
	_panel.visible = true
	# The Audio page may have changed the music volume.
	refresh_music()
	if _open:
		for child: Node in _column.get_children():
			if child is Button:
				(child as Button).grab_focus()
				break
