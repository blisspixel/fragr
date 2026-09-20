extends VBoxContainer
class_name SettingsPanel

## One draft editor for boot and match menus. Saving is the only apply path.
signal closed

var preferences: FragrSettings
var _draft: FragrSettings
var _rows: VBoxContainer
var _note: Label
var _tabs: HBoxContainer
var _page: String = "CONTROLS"

func _ready() -> void:
	assert(preferences != null)
	_draft = preferences.draft()
	theme = MenuTheme.build()
	add_theme_constant_override("separation", 10)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	add_child(_tabs)
	for page: String in ["CONTROLS", "DISPLAY", "AUDIO"]:
		var button: Button = Button.new()
		button.text = page
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(show_page.bind(page))
		_tabs.add_child(button)
	_rows = VBoxContainer.new()
	_rows.custom_minimum_size.y = 245
	_rows.add_theme_constant_override("separation", 10)
	add_child(_rows)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 14)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.y = 40
	add_child(_note)
	var actions: HBoxContainer = HBoxContainer.new()
	add_child(actions)
	for action: String in ["SAVE", "CANCEL"]:
		var button: Button = Button.new()
		button.text = action
		button.custom_minimum_size.y = 46
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(save if action == "SAVE" else cancel)
		actions.add_child(button)
	show_page("CONTROLS")

func show_page(page: String) -> void:
	_page = page
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for tab: Button in _tabs.get_children():
		tab.modulate = MenuTheme.EMBER if tab.text == page else Color.WHITE
		if tab.text == page:
			tab.grab_focus()
	match page:
		"CONTROLS":
			_slider("MOUSE SENSITIVITY", "controls", "mouse_sensitivity", 0.1, 10.0, 0.05)
			_slider("TURN SPEED", "controls", "turn_speed", 0.5, 6.0, 0.1)
			_toggle("INVERT LOOK", "controls", "invert_y")
			_toggle("WEAPON BOB", "gameplay", "head_bob")
			_note.text = "Mouse: 0.022 degrees per count at 1.0.\nTurn speed controls keyboard and stick look."
		"DISPLAY":
			_option("WINDOW", "video", "display_mode", ["WINDOWED", "FULLSCREEN"], [0, 2])
			_slider("VERTICAL FOV", "video", "vertical_fov", 60.0, 110.0, 1.0)
			_frame_cap()
			_toggle("VERTICAL SYNC", "video", "vsync")
			_note.text = "Frame cap 0 is unlimited. VSync depends on your display driver.\nWider screens preserve vertical FOV."
		"AUDIO":
			_slider("MASTER", "audio", "master", 0.0, 1.0, 0.05)
			_slider("RADIO", "audio", "music", 0.0, 1.0, 0.05)
			_slider("EFFECTS", "audio", "effects", 0.0, 1.0, 0.05)
			_note.text = "C: next station. N: next track. M: radio on/off.\nChanges apply when saved. Zero volume mutes the bus."

func focus_first() -> void:
	(_tabs.get_child(0) as Button).grab_focus()

func _row(title: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = 48
	row.add_theme_constant_override("separation", 14)
	var label: Label = Label.new()
	label.text = title
	label.custom_minimum_size.x = 300
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	_rows.add_child(row)
	return row

func _slider(title: String, section: String, key: String, low: float, high: float, step: float) -> void:
	var row: HBoxContainer = _row(title)
	var control: HSlider = HSlider.new()
	control.name = key
	control.min_value = low
	control.max_value = maxf(high, float(_draft.get_value(section, key)))
	control.step = step
	control.value = float(_draft.get_value(section, key))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	var readout: Label = Label.new()
	readout.custom_minimum_size.x = 85
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_font_size_override("font_size", 20)
	row.add_child(readout)
	var update: Callable = func(value: float) -> void:
		readout.text = _format_value(value, section, step)
		_draft.set_value(section, key, value)
	control.value_changed.connect(update)
	# Displaying a value must not quantize a hand-edited preference on Cancel/Save.
	readout.text = _format_value(float(_draft.get_value(section, key)), section, step)

static func _format_value(value: float, section: String, step: float) -> String:
	if section == "audio":
		return "%.0f%%" % (value * 100.0)
	return "%.2f" % value if step < 1.0 else "%.0f" % value

func _toggle(title: String, section: String, key: String) -> void:
	var row: HBoxContainer = _row(title)
	var control: Button = Button.new()
	control.name = key
	control.toggle_mode = true
	control.button_pressed = bool(_draft.get_value(section, key))
	control.text = "ON" if control.button_pressed else "OFF"
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.toggled.connect(func(on: bool) -> void:
		control.text = "ON" if on else "OFF"
		_draft.set_value(section, key, on)
	)
	row.add_child(control)

func _option(title: String, section: String, key: String, labels: Array[String], values: Array[int]) -> void:
	var row: HBoxContainer = _row(title)
	var control: OptionButton = OptionButton.new()
	control.name = key
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label: String in labels:
		control.add_item(label)
	control.select(maxi(0, values.find(int(_draft.get_value(section, key)))))
	control.item_selected.connect(func(index: int) -> void: _draft.set_value(section, key, values[index]))
	row.add_child(control)

func _frame_cap() -> void:
	var caps: Array[int] = [0, 30, 60, 90, 120, 144, 165, 240, 360]
	var current: int = int(_draft.get_value("video", "fps_cap"))
	if current not in caps:
		caps.append(current)
		caps.sort()
	var labels: Array[String] = []
	for cap: int in caps:
		labels.append("UNLIMITED" if cap == 0 else "%d FPS" % cap)
	_option("FRAME CAP", "video", "fps_cap", labels, caps)

func save() -> void:
	var result: Error = preferences.commit(_draft)
	if result != OK:
		_note.text = "SAVE FAILED (%d). Check disk space and write access." % result
		return
	closed.emit()

func cancel() -> void:
	closed.emit()
