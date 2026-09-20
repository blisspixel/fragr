class_name CampaignOpening
extends CanvasLayer

## Reader-paced story presentation. Completion is a request, never mission authority.
signal completed

const BEATS: Array[String] = ["HOME", "CHOICE", "ADDRESS", "RECALL", "PURSUIT"]
var page: int = 0
var finished: bool = false
var _title: Label
var _body: Label
var _page_number: Label
var _mission_title: Label
var _back: Button
var _next: Button
var _skip: Button
var _scroll: ScrollContainer
var _scroll_hint: Label

func _ready() -> void:
	layer = 110
	MouseCapture.release()
	var backdrop: MenuBackdrop = MenuBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var frame: MarginContainer = MarginContainer.new()
	frame.theme = MenuTheme.build()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		frame.add_theme_constant_override("margin_" + side, 100)
	for side: String in ["top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, 64)
	add_child(frame)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(1180, 760)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", MenuTheme.panel(Color("171d1a"), Color("8c714e")))
	frame.add_child(panel)
	var inset: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 30)
	panel.add_child(inset)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	inset.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	column.add_child(heading)
	_mission_title = _label(22)
	_mission_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mission_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(_mission_title)
	_page_number = _label(22)
	heading.add_child(_page_number)
	_title = _label(52)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_color_override("font_color", MenuTheme.EMBER)
	column.add_child(_title)
	var rule: ColorRect = ColorRect.new()
	rule.color = Color("875739")
	rule.custom_minimum_size.y = 4
	column.add_child(rule)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	column.add_child(_scroll)
	_body = _label(32)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("line_spacing", 10)
	_scroll.add_child(_body)
	_scroll_hint = _label(16)
	column.add_child(_scroll_hint)
	_body.resized.connect(_update_scroll_hint)
	_scroll.resized.connect(_update_scroll_hint)
	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 18)
	column.add_child(controls)
	_back = _button(controls, previous)
	_skip = _button(controls, finish)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	_next = _button(controls, advance)
	_refresh()
	_next.grab_focus.call_deferred()

func _label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(parent: Control, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(180, 62)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()

func _refresh() -> void:
	if _title == null:
		return
	_mission_title.text = tr("MISSION_M01_TITLE")
	_title.text = tr("STORY_M01_" + BEATS[page] + "_TITLE")
	_body.text = tr("STORY_M01_" + BEATS[page] + "_BODY")
	_page_number.text = tr("STORY_PAGE").format({"current": page + 1, "total": BEATS.size()})
	_back.text = tr("STORY_BACK")
	_back.disabled = page == 0
	_next.text = tr("STORY_FINISH" if page == BEATS.size() - 1 else "STORY_NEXT")
	_skip.text = tr("STORY_SKIP")
	_scroll_hint.text = tr("STORY_SCROLL_HINT")
	_scroll.scroll_vertical = 0
	_update_scroll_hint()

func _update_scroll_hint() -> void:
	_scroll_hint.visible = _body.size.y > _scroll.size.y

func previous() -> void:
	if finished or page == 0:
		return
	page -= 1
	_refresh()
	if page == 0:
		_next.grab_focus()

func advance() -> void:
	if finished:
		return
	if page == BEATS.size() - 1:
		finish()
	else:
		page += 1
		_refresh()

func finish() -> void:
	if finished:
		return
	finished = true
	completed.emit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		finish()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed():
		var down: bool = event.is_action("ui_page_down") or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_RIGHT_SHOULDER)
		var up: bool = event.is_action("ui_page_up") or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_LEFT_SHOULDER)
		if down or up:
			_scroll.scroll_vertical += int(_scroll.size.y * 0.8) * (1 if down else -1)
	# Menu/console shortcuts beneath the story must not react to its input.
	get_viewport().set_input_as_handled()
