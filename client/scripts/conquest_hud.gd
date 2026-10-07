class_name ConquestHud
extends Control

const FONT: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")
var state: Dictionary = {}
var _tickets: Label
var _hint: Label
var _sites: Array[Label] = []
var _bars: Array[ColorRect] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tickets = _label(24)
	_hint = _label(14)
	_hint.text = tr("CONQUEST_HOLD_MAJORITY")
	_hint.modulate = Color("c3c0a7")
	for index: int in range(5):
		_sites.append(_label(18))
		var bar: ColorRect = ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		_bars.append(bar)
	resized.connect(_layout)
	apply({})

func _label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func apply(snapshot: Dictionary) -> void:
	var raw: Variant = snapshot.get("conquest")
	state = raw.duplicate(true) if raw is Dictionary and ConquestState.validation_error(snapshot).is_empty() else {}
	visible = not state.is_empty()
	if not visible or _tickets == null:
		return
	_tickets.text = tr("CONQUEST_TICKETS").format({"union": int(state.tickets.union), "coalition": int(state.tickets.coalition)})
	for index: int in range(5):
		var point: Dictionary = state.points[index]
		_sites[index].text = ConquestState.label(str(point.id)) + "\n" + ConquestState.status(point)
		_sites[index].modulate = Color("fff1c4") if point.contested else ConquestState.color(point)
		_bars[index].color = MatchRules.team_label_color(str(point.capturing)) if point.capturing != null else ConquestState.color(point)
	_layout()

func _layout() -> void:
	if _tickets == null or state.is_empty():
		return
	var width: float = minf(900.0, size.x - 24.0)
	var left: float = (size.x - width) * 0.5
	_tickets.position = Vector2(left, 52)
	_tickets.size = Vector2(width, 32)
	_hint.position = Vector2(left, 148)
	_hint.size = Vector2(width, 22)
	for index: int in range(5):
		var cell: float = width / 5.0
		_sites[index].position = Vector2(left + cell * float(index), 87)
		_sites[index].size = Vector2(cell, 50)
		_bars[index].position = Vector2(left + cell * float(index) + 5, 139)
		_bars[index].size = Vector2((cell - 10) * float(state.points[index].progress) / float(state.capture_ticks), 3)
