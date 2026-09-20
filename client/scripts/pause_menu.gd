extends CanvasLayer
class_name PauseMenu

## Escape opens the match menu. The server has no pause command yet, including
## solo sessions. Keep snapshots flowing and neutralize input in game_manager.

signal resume_requested
signal leave_requested

var _open: bool = false
var _panel: Panel = null
var _column: VBoxContainer = null
var _note: Label = null
var preferences: FragrSettings
var _settings_panel: SettingsPanel
var _settings_frame: PanelContainer
var _centre: CenterContainer

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

func _build() -> void:
	var veil: ColorRect = ColorRect.new()
	veil.color = Color(0.02, 0.02, 0.03, 0.75)
	veil.anchor_right = 1.0
	veil.anchor_bottom = 1.0
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)

	var centre: CenterContainer = CenterContainer.new()
	centre.theme = MenuTheme.build()
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
	title.add_theme_font_size_override("font_size", 40)
	_column.add_child(title)

	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 14)
	_note.add_theme_color_override("font_color", Color(0.82, 0.55, 0.28))
	_column.add_child(_note)

	_add_button("Resume", func() -> void: close())
	_add_button("Settings", show_settings)
	_add_button("Leave match", func() -> void:
		close()
		leave_requested.emit()
	)
	_add_button("Quit to desktop", func() -> void: get_tree().quit())

	var hint: Label = Label.new()
	hint.text = "Escape resumes. Tilde opens the console."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6))
	_column.add_child(hint)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 16.0)
	_column.add_child(spacer)

func _add_button(text: String, handler: Callable) -> void:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 42.0)
	b.pressed.connect(handler)
	_column.add_child(b)

func is_open() -> bool:
	return _open

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_note.text = "LIVE MATCH. FIND COVER FIRST."
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
	_hide_settings()
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
	_panel.visible = false
	_settings_panel = SettingsPanel.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.custom_minimum_size.x = 780
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
	if _open:
		for child: Node in _column.get_children():
			if child is Button:
				(child as Button).grab_focus()
				break
