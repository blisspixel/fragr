class_name CampaignResults
extends CanvasLayer

signal completed
var result: Dictionary
var armed: bool = false
var finished: bool = false
var _continue: Button

func _init(value: Dictionary = {}) -> void:
	result = value.duplicate(true)

func _ready() -> void:
	layer = 110
	MouseCapture.release()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.025, 0.03, 0.025, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.theme = MenuTheme.build()
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.panel(Color("181c18"), MenuTheme.BONE))
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	var inset: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(inset)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	inset.add_child(column)
	column.add_child(_label(tr("RESULT_COMPLETE"), 32))
	column.add_child(_label(str(result["map_name"]), 22))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 16)
	column.add_child(grid)
	grid.add_child(_label("", 20))
	grid.add_child(_label(tr("RESULT_ATTEMPT").format({"number": result["attempt_number"]}), 20))
	grid.add_child(_label(tr("RESULT_ALL_ATTEMPTS"), 20))
	for field: String in ["kills", "secrets", "deaths"]:
		grid.add_child(_label(tr("RESULT_" + field.to_upper()), 22))
		for scope: String in ["attempt", "total"]:
			grid.add_child(_label(str(result[scope][field]), 28))
	column.add_child(_label(tr("RESULT_TIME") + ": " + CampaignResult.elapsed_text(result), 24))
	_continue = Button.new()
	_continue.text = tr("RESULT_CONTINUE")
	_continue.disabled = true
	_continue.pressed.connect(finish)
	column.add_child(_continue)

func _label(text: String, size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label

func _process(_delta: float) -> void:
	if not armed and CampaignResult.controls_released():
		armed = true
		_continue.disabled = false
		_continue.grab_focus()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if armed and not event.is_echo():
			finish()

func finish() -> void:
	if not armed or finished:
		return
	finished = true
	completed.emit()
