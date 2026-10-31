class_name ClutchCard
extends Control
## The clutch (#510): one fighter left on a side of two or more, against two
## or more. The server names that fighter in `sabotage.clutch`; this card
## stamps it once, upright, for a few seconds: the fighter's own line, their
## side's, or the other side's. No rotation, no shake, nothing over the aim
## point. The Host's voiced `last_standing` call is separate and rare.

const StampCardScript = preload("res://scripts/stamp_card.gd")

## Fraction of the view height where the card's top sits: under the
## Sabotage header, above the aim point.
const TOP_FRACTION: float = 0.17
const HOLD_SECONDS: float = 3.0
## Narrow enough to stay between the booth panel and the event lane at 720p.
const WIDTH: float = 480.0

var reduced_motion: bool = false
var _title: Label
var _odds: Label
var _rows: VBoxContainer
var _plate: PanelContainer
var _stamp: StampCard
var _remaining: float = 0.0


func _ready() -> void:
	name = "ClutchCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A dark plate, as the death card has, so the lines read over any wall.
	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_theme_stylebox_override("panel", MenuTheme.panel(MenuTheme.alpha(MenuTheme.INK, 0.86), MenuTheme.BORDER))
	add_child(_plate)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_plate.add_child(_rows)
	_title = _line(MenuTheme.BODY)
	_title.name = "Title"
	# A long callsign wraps inside the plate, never into the event lane.
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(_title)
	_odds = _line(MenuTheme.LARGE)
	_odds.name = "Odds"
	_rows.add_child(_odds)
	_stamp = StampCardScript.new()
	_stamp.name = "ClutchStamp"
	add_child(_stamp)
	_plate.resized.connect(_place)
	resized.connect(_place)
	visible = false
	set_process(false)


func _line(size: int) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MenuTheme.pixel_text(label, size, MenuTheme.BONE, 4)
	return label


## Two lines, the moment and the odds, stamped in `ink`. Fewer clears it.
func present(lines: PackedStringArray, ink: Color) -> void:
	if lines.size() < 2:
		clear()
		return
	_title.text = lines[0]
	_odds.text = lines[1]
	_title.rotation = 0.0
	_odds.rotation = 0.0
	_odds.add_theme_color_override("font_color", MenuTheme.readable_text(ink))
	visible = true
	_remaining = HOLD_SECONDS
	set_process(true)
	_place()
	# The odds are the moment: the ink lands around them.
	_stamp.trigger_stamp(_odds, ink, reduced_motion)


func clear() -> void:
	visible = false
	_remaining = 0.0
	set_process(false)
	if _stamp != null:
		_stamp.retire()
	if _title != null:
		_title.text = ""
		_odds.text = ""


func title() -> String:
	return _title.text if _title != null and visible else ""


func odds() -> String:
	return _odds.text if _odds != null and visible else ""


func stamped() -> bool:
	return _stamp != null and _stamp.active()


func card_rect() -> Rect2:
	return _plate.get_global_rect() if _plate != null else Rect2()


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		clear()


func _place() -> void:
	if _plate == null:
		return
	var view: Vector2 = size
	var width: float = minf(WIDTH, maxf(view.x - 32.0, 0.0))
	var text_width: float = maxf(64.0, width - 32.0)
	_title.custom_minimum_size.x = text_width
	_odds.custom_minimum_size.x = text_width
	_plate.size = Vector2(width, _plate.get_combined_minimum_size().y)
	_plate.position = Vector2(roundf((view.x - width) * 0.5), roundf(view.y * TOP_FRACTION))
