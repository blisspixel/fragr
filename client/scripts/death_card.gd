class_name DeathCard
extends Control
## The joined player's death indication (#441): who or what, the camera's
## actual perspective, and the server's respawn countdown. One plate below
## the aim point, where the hidden crosshair was, never over the result card.

## Fraction of the view height from the top where the plate's top sits.
const TOP_FRACTION: float = 0.56
## Wide enough for "FRAGGED BY" and a 16-character callsign on one line at
## the large pixel size; wrapping is the fallback for longer names.
const PLATE_WIDTH: float = 960.0

var _plate: PanelContainer
var _headline: Label
var _detail: Label
var _timing: Label


func _ready() -> void:
	name = "DeathCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_theme_stylebox_override("panel", MenuTheme.panel(MenuTheme.alpha(MenuTheme.INK, 0.86), MenuTheme.BORDER))
	add_child(_plate)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_plate.add_child(rows)
	_headline = _line(MenuTheme.LARGE, MenuTheme.DANGER)
	_headline.name = "Headline"
	rows.add_child(_headline)
	_detail = _line(MenuTheme.BODY, MenuTheme.BONE)
	_detail.name = "Detail"
	rows.add_child(_detail)
	_timing = _line(MenuTheme.BODY, MenuTheme.EMBER)
	_timing.name = "Timing"
	rows.add_child(_timing)
	_plate.resized.connect(_place)
	resized.connect(_place)
	visible = false


## Every line is the HUD's pixel type; the headline is the large size.
func _line(size: int, colour: Color) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MenuTheme.pixel_text(label, size, colour, 4)
	return label


## Show cause, view and timing; anything shorter hides the card.
func present(lines: PackedStringArray) -> void:
	if lines.size() < 3:
		clear()
		return
	_headline.text = lines[0]
	_detail.text = lines[1]
	_timing.text = lines[2]
	visible = true
	_place()


func clear() -> void:
	visible = false
	if _headline != null:
		_headline.text = ""
		_detail.text = ""
		_timing.text = ""


func headline() -> String:
	return _headline.text if _headline != null else ""


func detail() -> String:
	return _detail.text if _detail != null else ""


func timing() -> String:
	return _timing.text if _timing != null else ""


func plate_rect() -> Rect2:
	return _plate.get_global_rect() if _plate != null else Rect2()


func _place() -> void:
	if _plate == null:
		return
	var view: Vector2 = size
	var width: float = minf(PLATE_WIDTH, maxf(view.x - 32.0, 0.0))
	# Wrapped labels measure their height from a known width, not from zero.
	var text_width: float = maxf(64.0, width - 32.0)
	_headline.custom_minimum_size.x = text_width
	_detail.custom_minimum_size.x = text_width
	_timing.custom_minimum_size.x = text_width
	_plate.size = Vector2(width, _plate.get_combined_minimum_size().y)
	_plate.position = Vector2(roundf((view.x - _plate.size.x) * 0.5), roundf(view.y * TOP_FRACTION))
