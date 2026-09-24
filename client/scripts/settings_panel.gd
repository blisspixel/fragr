extends VBoxContainer
class_name SettingsPanel

## One draft editor for boot and match menus. Saving is the only apply path.
## Every page is reachable by keyboard and gamepad: arrows or the d-pad move
## focus, Enter or A chooses, and the shoulder buttons change tabs.
signal closed

## Page ids in tab order. The Controls page rebinds every action; the Look
## page holds sensitivity, stick shape and aim assist.
const PAGES: Array[String] = ["CONTROLS", "LOOK", "DISPLAY", "GRAPHICS", "AUDIO"]
const SLOT_HEADERS: Array[String] = ["BIND_HEADER_KEY", "BIND_HEADER_ALT", "BIND_HEADER_PAD"]

var preferences: FragrSettings
var _draft: FragrSettings
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _note: Label
var _tabs: HBoxContainer
var _page: String = "CONTROLS"
## Binding capture: the action and slot waiting for input, or "" when idle.
var _capture_action: String = ""
var _capture_slot: int = -1
var _capture_frame: int = -1
var _device_revision: int = -1

func _ready() -> void:
	assert(preferences != null)
	_draft = preferences.draft()
	theme = MenuTheme.build()
	add_theme_constant_override("separation", 10)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	add_child(_tabs)
	for page: String in PAGES:
		var button: Button = Button.new()
		button.name = "Tab" + page
		button.text = tr("SETTINGS_TAB_" + page)
		button.set_meta("page", page)
		button.add_theme_font_size_override("font_size", 16)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(show_page.bind(page))
		_tabs.add_child(button)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size.y = 380
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	_scroll.add_child(_rows)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 14)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.y = 40
	add_child(_note)
	var actions: HBoxContainer = HBoxContainer.new()
	add_child(actions)
	for action: String in ["SAVE", "CANCEL"]:
		var button: Button = Button.new()
		button.name = action.capitalize()
		button.text = tr("SETTINGS_" + action)
		button.custom_minimum_size.y = 46
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(save if action == "SAVE" else cancel)
		actions.add_child(button)
	show_page("CONTROLS")

func show_page(page: String) -> void:
	_page = page
	_cancel_capture()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for tab: Button in _tabs.get_children():
		var current: bool = str(tab.get_meta("page")) == page
		tab.modulate = MenuTheme.EMBER if current else Color.WHITE
		if current:
			tab.grab_focus()
	_scroll.scroll_vertical = 0
	match page:
		"CONTROLS":
			_bindings_page()
		"LOOK":
			_slider(tr("LOOK_MOUSE_SENSITIVITY"), "controls", "mouse_sensitivity", 0.1, 10.0, 0.05)
			_toggle(tr("LOOK_INVERT"), "controls", "invert_y")
			_slider(tr("LOOK_TURN_SPEED"), "controls", "turn_speed", 0.5, 6.0, 0.1, "degrees")
			_toggle(tr("LOOK_AUTO_CENTRE"), "controls", "auto_centre")
			_slider(tr("LOOK_STICK_YAW"), "controls", "stick_yaw_speed", 60.0, 720.0, 10.0)
			_slider(tr("LOOK_STICK_PITCH"), "controls", "stick_pitch_speed", 40.0, 480.0, 10.0)
			_slider(tr("LOOK_STICK_DEADZONE"), "controls", "stick_deadzone", 0.02, 0.4, 0.01)
			_slider(tr("LOOK_STICK_CURVE"), "controls", "stick_curve", 1.0, 3.0, 0.1)
			_toggle(tr("LOOK_STICK_ACCEL"), "controls", "stick_accel")
			_option(tr("LOOK_AIM_ASSIST"), "controls", "aim_assist", [tr("LOOK_ASSIST_OFF"), tr("LOOK_ASSIST_LIGHT"), tr("LOOK_ASSIST_STANDARD")], [0, 1, 2])
			_toggle(tr("LOOK_WEAPON_BOB"), "gameplay", "head_bob")
			_update_look_note()
		"DISPLAY":
			var window_mode: OptionButton = _option("WINDOW", "video", "display_mode", ["WINDOWED", "FULLSCREEN"], [0, 2])
			window_mode.item_selected.connect(func(_index: int) -> void: show_page.call_deferred("DISPLAY"))
			_resolution()
			_slider("VERTICAL FOV", "video", "vertical_fov", 60.0, 110.0, 1.0)
			_frame_cap()
			_toggle("VERTICAL SYNC", "video", "vsync")
			_update_display_note()
		"GRAPHICS":
			_option("QUALITY", "video", "quality", ["PERFORMANCE", "BALANCED", "HIGH"], [0, 1, 2])
			_option("UPSCALING", "video", "upscaling", ["STANDARD", "FSR 1", "FSR 2"], [0, 1, 2])
			var renderer: String = RenderingServer.get_current_rendering_method()
			if not RenderQuality.supports_fsr(renderer):
				var upscaling: OptionButton = _rows.find_child("upscaling", true, false) as OptionButton
				upscaling.disabled = true
				_note.text = "Standard scaling active. FSR needs the Forward+ renderer.\nSaved FSR choices are kept. High adds supported contact shading."
			else:
				_note.text = "High: smoother edges and contact shading. Pixel textures stay sharp.\nFSR reconstructs lower resolutions. FSR 2 may soften moving sprites."
		"AUDIO":
			_slider("MASTER", "audio", "master", 0.0, 1.0, 0.05)
			_slider("RADIO", "audio", "music", 0.0, 1.0, 0.05)
			_slider("EFFECTS", "audio", "effects", 0.0, 1.0, 0.05)
			_note.text = "C: next station. N: next track. M: radio on/off.\nChanges apply when saved. Zero volume mutes the bus."

func focus_first() -> void:
	(_tabs.get_child(0) as Button).grab_focus()

func current_page() -> String:
	return _page

## Shoulder buttons change tabs, so a gamepad never has to walk focus up to
## the tab row. Ignored while a binding is being captured.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not _capture_action.is_empty():
		return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var button: int = (event as InputEventJoypadButton).button_index
		if button in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
			var step: int = 1 if button == JOY_BUTTON_RIGHT_SHOULDER else -1
			show_page(PAGES[wrapi(PAGES.find(_page) + step, 0, PAGES.size())])
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	# Pad glyph names follow the layout of the pad in use.
	if _page == "CONTROLS" and _capture_action.is_empty() and _device_revision != InputDevice.revision:
		_device_revision = InputDevice.revision
		_refresh_binding_labels()

## --- Controls page: rebinding -----------------------------------------------

func _bindings_page() -> void:
	var header: HBoxContainer = _binding_row(tr("BIND_HEADER_ACTION"))
	for key: String in SLOT_HEADERS:
		var label: Label = Label.new()
		label.text = tr(key)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", MenuTheme.EMBER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(label)
	for action: String in InputBindings.ACTIONS:
		var row: HBoxContainer = _binding_row(tr("ACTION_" + action.to_upper()))
		row.name = "Row_" + action
		for slot: int in range(InputBindings.SLOTS):
			var button: Button = Button.new()
			button.name = "bind_%s_%d" % [action, slot]
			button.custom_minimum_size = Vector2(0, 34)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", 14)
			button.clip_text = true
			button.pressed.connect(begin_capture.bind(action, slot))
			row.add_child(button)
	var reset: Button = Button.new()
	reset.name = "reset_bindings"
	reset.text = tr("BIND_RESET")
	reset.custom_minimum_size.y = 40
	reset.add_theme_font_size_override("font_size", 16)
	reset.pressed.connect(reset_bindings)
	_rows.add_child(reset)
	_device_revision = InputDevice.revision
	_refresh_binding_labels()
	_note.text = tr("BIND_NOTE")
	_show_conflicts()

func _binding_row(title: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label: Label = Label.new()
	label.text = title
	label.custom_minimum_size.x = 250
	label.add_theme_font_size_override("font_size", 14)
	label.clip_text = true
	row.add_child(label)
	_rows.add_child(row)
	return row

func _refresh_binding_labels() -> void:
	var clashing: Dictionary = {}
	for conflict: Dictionary in InputBindings.conflicts(_draft):
		for action: Variant in conflict["actions"]:
			clashing[str(action) + "#" + str(conflict["token"])] = true
	for action: String in InputBindings.ACTIONS:
		var slots: Array[String] = InputBindings.slots_for(_draft, action)
		for slot: int in range(InputBindings.SLOTS):
			var button: Button = _rows.find_child("bind_%s_%d" % [action, slot], true, false) as Button
			if button == null:
				continue
			button.text = InputGlyphs.token_name(slots[slot], InputDevice.pad_layout)
			button.modulate = Color("ff8a6a") if clashing.has(action + "#" + slots[slot]) else Color.WHITE

func _show_conflicts() -> void:
	var found: Array[Dictionary] = InputBindings.conflicts(_draft)
	if found.is_empty():
		return
	var first: Dictionary = found[0]
	_note.text = tr("BIND_CONFLICT").format({
		"input": InputGlyphs.token_name(str(first["token"]), InputDevice.pad_layout),
		"first": tr("ACTION_" + str(first["actions"][0]).to_upper()),
		"second": tr("ACTION_" + str(first["actions"][1]).to_upper()),
	})

## Wait for the next key, mouse button, pad button or trigger for a slot.
func begin_capture(action: String, slot: int) -> void:
	_capture_action = action
	_capture_slot = slot
	_capture_frame = Engine.get_process_frames()
	var button: Button = _rows.find_child("bind_%s_%d" % [action, slot], true, false) as Button
	if button != null:
		button.text = tr("BIND_WAITING")
	_note.text = tr("BIND_WAITING_NOTE").format({"slot": tr(SLOT_HEADERS[slot]), "action": tr("ACTION_" + action.to_upper())})

func capturing() -> bool:
	return not _capture_action.is_empty()

func _cancel_capture() -> void:
	_capture_action = ""
	_capture_slot = -1

## Capture runs ahead of every other handler so Escape, B and Start can be
## bound or cancel without also closing the menu underneath.
func _input(event: InputEvent) -> void:
	if _capture_action.is_empty() or not is_visible_in_tree():
		return
	if accept_capture_event(event):
		get_viewport().set_input_as_handled()

## Feed one event to an active capture. Returns true when it was consumed.
func accept_capture_event(event: InputEvent) -> bool:
	if _capture_action.is_empty():
		return false
	if event is InputEventMouseMotion:
		return false
	# The press that opened the capture must not also fill it.
	if Engine.get_process_frames() == _capture_frame:
		return true
	var pad_slot: bool = _capture_slot == InputBindings.PAD_SLOT
	if event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return true
		if key.physical_keycode == KEY_ESCAPE:
			_finish_capture("", false)
			return true
		if key.physical_keycode == KEY_BACKSPACE:
			_finish_capture("", true)
			return true
		if pad_slot:
			_note.text = tr("BIND_WRONG_SLOT_PAD")
			return true
		_finish_capture(InputBindings.token_from_event(key), true)
		return true
	if event is InputEventMouseButton:
		if not (event as InputEventMouseButton).pressed:
			return true
		if pad_slot:
			_note.text = tr("BIND_WRONG_SLOT_PAD")
			return true
		_finish_capture(InputBindings.token_from_event(event), true)
		return true
	if event is InputEventJoypadButton:
		if not (event as InputEventJoypadButton).pressed:
			return true
		if not pad_slot:
			_note.text = tr("BIND_WRONG_SLOT_KEY")
			return true
		_finish_capture(InputBindings.token_from_event(event), true)
		return true
	if event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		if not pad_slot or int(motion.axis) not in InputBindings.PAD_AXES or absf(motion.axis_value) < 0.6:
			return true
		_finish_capture(InputBindings.token_from_event(motion), true)
		return true
	return false

func _finish_capture(token: String, store: bool) -> void:
	var action: String = _capture_action
	var slot: int = _capture_slot
	_cancel_capture()
	if store:
		var displaced: Array[String] = InputBindings.assign(_draft, action, slot, token)
		var name: String = InputGlyphs.token_name(token, InputDevice.pad_layout)
		if not displaced.is_empty():
			_note.text = tr("BIND_MOVED").format({"input": name, "from": tr("ACTION_" + displaced[0].to_upper()), "to": tr("ACTION_" + action.to_upper())})
		else:
			_note.text = tr("BIND_SET").format({"action": tr("ACTION_" + action.to_upper()), "input": name})
	else:
		_note.text = tr("BIND_NOTE")
	_refresh_binding_labels()
	var button: Button = _rows.find_child("bind_%s_%d" % [action, slot], true, false) as Button
	if button != null:
		button.grab_focus.call_deferred()

func reset_bindings() -> void:
	InputBindings.reset(_draft)
	_refresh_binding_labels()
	_note.text = tr("BIND_RESET_DONE")

## --- Shared rows --------------------------------------------------------------

func _row(title: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 14)
	var label: Label = Label.new()
	label.text = title
	label.custom_minimum_size.x = 300
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)
	_rows.add_child(row)
	return row

func _slider(title: String, section: String, key: String, low: float, high: float, step: float, unit: String = "") -> void:
	var row: HBoxContainer = _row(title)
	var control: HSlider = HSlider.new()
	control.name = key
	control.min_value = low
	control.max_value = maxf(high, float(_draft.get_value(section, key)))
	control.step = step
	control.value = float(_draft.get_value(section, key))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.custom_minimum_size.y = 24
	row.add_child(control)
	var readout: Label = Label.new()
	readout.custom_minimum_size.x = 85
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_font_size_override("font_size", 18)
	row.add_child(readout)
	var update: Callable = func(value: float) -> void:
		readout.text = _format_value(value, section, step, unit)
		_draft.set_value(section, key, value)
		if _page == "LOOK":
			_update_look_note()
	control.value_changed.connect(update)
	# Displaying a value must not quantize a hand-edited preference on Cancel/Save.
	readout.text = _format_value(float(_draft.get_value(section, key)), section, step, unit)

static func _format_value(value: float, section: String, step: float, unit: String = "") -> String:
	if section == "audio":
		return "%.0f%%" % (value * 100.0)
	if unit == "degrees":
		return "%.0f" % rad_to_deg(value)
	return "%.2f" % value if step < 1.0 else "%.0f" % value

func _toggle(title: String, section: String, key: String) -> void:
	var row: HBoxContainer = _row(title)
	var control: Button = Button.new()
	control.name = key
	control.toggle_mode = true
	control.button_pressed = bool(_draft.get_value(section, key))
	control.text = tr("LOOK_ON") if control.button_pressed else tr("LOOK_OFF")
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.toggled.connect(func(on: bool) -> void:
		control.text = tr("LOOK_ON") if on else tr("LOOK_OFF")
		_draft.set_value(section, key, on)
	)
	row.add_child(control)

func _option(title: String, section: String, key: String, labels: Array[String], values: Array[int]) -> OptionButton:
	var row: HBoxContainer = _row(title)
	var control: OptionButton = OptionButton.new()
	control.name = key
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label: String in labels:
		control.add_item(label)
	control.select(maxi(0, values.find(int(_draft.get_value(section, key)))))
	control.item_selected.connect(func(index: int) -> void: _draft.set_value(section, key, values[index]))
	row.add_child(control)
	return control

func _update_look_note() -> void:
	var cm: float = LookInput.cm_per_360(float(_draft.get_value("controls", "mouse_sensitivity")), 800.0)
	_note.text = tr("LOOK_NOTE").format({"cm": "%.1f" % cm})

func _resolution() -> void:
	var fullscreen: bool = int(_draft.get_value("video", "display_mode")) == 2
	var aspect: Vector2i = Vector2i(16, 9)
	if fullscreen and DisplayServer.get_name() != "headless":
		aspect = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var labels: Array[String] = []
	for height: int in RenderQuality.RESOLUTION_HEIGHTS:
		if height == 0:
			labels.append("NATIVE" if fullscreen else "AUTOMATIC")
		else:
			labels.append("%d x %d" % [roundi(float(height) * aspect.x / maxi(1, aspect.y)), height])
	var control: OptionButton = _option("RESOLUTION", "video", "resolution_height", labels, RenderQuality.RESOLUTION_HEIGHTS)
	control.item_selected.connect(func(_index: int) -> void: _update_display_note())

func _update_display_note() -> void:
	var height: int = int(_draft.get_value("video", "resolution_height"))
	var fullscreen: bool = int(_draft.get_value("video", "display_mode")) == 2
	var output: Vector2i = Vector2i(1920, 1080)
	if DisplayServer.get_name() != "headless":
		var screen: int = DisplayServer.window_get_current_screen()
		output = DisplayServer.screen_get_size(screen) if fullscreen else DisplayServer.screen_get_usable_rect(screen).size
	var world: Vector2i = RenderQuality.render_size(height, output) if fullscreen else RenderQuality.window_size(height, output)
	if not fullscreen and height == 0 and DisplayServer.get_name() != "headless" and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		world = DisplayServer.window_get_size()
	if fullscreen:
		_note.text = "Fullscreen uses desktop output. Menus stay sharp.\nEffective world: %d x %d. Resolution preserves screen shape." % [world.x, world.y]
	else:
		_note.text = "Window: %d x %d, bounded to your display.\nAutomatic preserves manual resizing. VSync depends on your driver." % [world.x, world.y]

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
	_cancel_capture()
	var result: Error = preferences.commit(_draft)
	if result != OK:
		_note.text = "SAVE FAILED (%d). Check disk space and write access." % result
		return
	closed.emit()

func cancel() -> void:
	_cancel_capture()
	closed.emit()
