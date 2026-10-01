class_name DepartureReview
extends CanvasLayer

signal confirmed
signal cancelled
var armed: bool = false
var _copy: RichTextLabel
var _state: Dictionary = {}
var _boarding: Dictionary = {}
var _revision: int = -1

func _ready() -> void:
	layer = 100
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.panel(Color("202820"), Color("9c8967")))
	center.add_child(panel)
	_copy = RichTextLabel.new()
	_copy.custom_minimum_size = Vector2(620, 0)
	_copy.fit_content = true
	_copy.scroll_active = false
	_copy.add_theme_font_override("normal_font", MenuTheme.FONT)
	_copy.add_theme_font_size_override("normal_font_size", 24)
	_copy.add_theme_color_override("default_color", MenuTheme.BONE)
	panel.add_child(_copy)
	_refresh()

func apply(value: Dictionary, boarding: Dictionary) -> void:
	_state = value.duplicate(true)
	_boarding = boarding.duplicate(true)
	_refresh()

func _refresh() -> void:
	if _copy == null or _state.is_empty():
		return
	var progress: Dictionary = _state["m05"]
	var lines: Array[String] = [tr("M05_DEPARTURE_REVIEW"), ""]
	for captive: Dictionary in progress["captives"]:
		var status: String = "M05_PASSENGER_HELD"
		if progress["group_released"]:
			status = "M05_PASSENGER_ABOARD" if M03MissionState._inside(captive["feet"], _boarding) else "M05_PASSENGER_RELEASED"
		lines.append(tr("M05_WORKER_" + str(captive["id"]).to_upper()) + ": " + tr(status))
	lines.append("")
	lines.append(tr("M05_DEPARTURE_OPTIONAL"))
	lines.append("")
	lines.append(tr("M05_DEPARTURE_CONFIRM"))
	InputGlyphs.render(_copy, "\n".join(lines), 44, true)

func _process(_delta: float) -> void:
	if not Input.is_action_pressed("interact") and not Input.is_action_pressed("ui_cancel"):
		armed = true
	if _revision != InputDevice.revision:
		_revision = InputDevice.revision
		_refresh()

func _input(event: InputEvent) -> void:
	if not armed or event.is_echo():
		return
	if event.is_action_pressed("ui_cancel"):
		armed = false
		cancelled.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		armed = false
		confirmed.emit()
		get_viewport().set_input_as_handled()
