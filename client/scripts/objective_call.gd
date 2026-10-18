class_name ObjectiveCall
extends Control

const LIFETIME: float = 1.5
var notices := HudNoticeQueue.new(1, 16, LIFETIME)
var coverage_query: Callable
var _covered: bool = false
var _plate: PanelContainer
var _copy: Label
var _serial: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_theme_stylebox_override("panel", MenuTheme.panel(MenuTheme.INK, MenuTheme.BORDER))
	add_child(_plate)
	_plate.resized.connect(_place_plate)
	_copy = Label.new()
	_copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_copy.add_theme_font_override("font", MenuTheme.DISPLAY_FONT)
	_copy.add_theme_font_size_override("font_size", MenuTheme.DISPLAY_SMALL)
	_copy.add_theme_color_override("font_color", MenuTheme.BONE)
	_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plate.add_child(_copy)
	_plate.hide()

func push(text: String) -> bool:
	return false if text.strip_edges().is_empty() else notices.push({"text": text.left(512)})

func clear() -> void:
	notices.clear()
	_serial = -1
	if _plate != null:
		_plate.hide()

func set_region(rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	if _plate != null:
		_copy.custom_minimum_size.x = maxf(64.0, size.x - 36.0)
		_plate.size = Vector2(size.x, 0)
		_place_plate()

func _place_plate() -> void:
	if _plate != null:
		# Wrapped copy grows upward, keeping its measured bottom above aim.
		_plate.position = Vector2(0, size.y - _plate.size.y)

func occupied_region() -> Rect2:
	return _plate.get_global_rect() if _plate != null else get_global_rect()

func set_covered(value: bool) -> void:
	_covered = value
	visible = not covered()

func covered() -> bool:
	return _covered or (coverage_query.is_valid() and bool(coverage_query.call()))

func _process(delta: float) -> void:
	var hidden: bool = covered()
	visible = not hidden
	notices.advance(delta, hidden)
	if _plate == null:
		return
	_plate.visible = not notices.active.is_empty()
	if not notices.active.is_empty() and _serial != int(notices.active[0].serial):
		_serial = int(notices.active[0].serial)
		_copy.text = notices.active[0].payload.text
		_plate.size = Vector2(size.x, 0)
		_place_plate()
