class_name SpeakerCaption
extends CanvasLayer

## One spoken line in play: sentence case with its speaker label, low on the
## screen above the HUD strip, never a combat notice banner. Lines queue and
## each holds for a reading time. Presentation only; a server fact decides
## when a line is said.
const LINE_SECONDS: float = 3.6
signal line_said(text: String)

var label: Label
var _queue: Array[String] = []
var _left: float = 0.0

func _ready() -> void:
	layer = 4
	label = Label.new()
	label.name = "SpeakerLine"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 160.0
	label.offset_right = -160.0
	label.offset_top = -252.0
	label.offset_bottom = -188.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", MenuTheme.BODY)
	label.add_theme_color_override("font_color", MenuTheme.BONE)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 5)
	label.visible = false
	add_child(label)

## Queue already translated lines.
func say(lines: Array[String]) -> void:
	_queue.append_array(lines)
	for line: String in lines:
		line_said.emit(line)
	if label != null and not label.visible:
		_left = 0.0
		advance(0.0)

func clear() -> void:
	_queue.clear()
	_left = 0.0
	if label != null:
		label.visible = false

func showing() -> String:
	return label.text if label != null and label.visible else ""

func advance(delta: float) -> void:
	if label == null:
		return
	_left -= maxf(delta, 0.0)
	if _left > 0.0:
		return
	if _queue.is_empty():
		label.visible = false
		return
	label.text = _queue.pop_front()
	label.visible = true
	_left = LINE_SECONDS

func _process(delta: float) -> void:
	if is_finite(delta):
		advance(delta)
