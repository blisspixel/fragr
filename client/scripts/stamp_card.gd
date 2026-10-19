class_name StampCard
extends Control

## Signature moment: Stamped (round, match, and episode result cards).
## The result line lands as an ink stamp on the card:
## 2-frame settle from 106% to 100% at a 2-3 degree tilt, with worn-ink texture
## in the winning side's relation colour and a faint offset impression.
## No flash, no shake. Zero magenta.
## Honors Reduced motion (immediately at 100% scale).

const TILT_DEGREES: float = -2.5
const FRAME1_SCALE: float = 1.06

var stamp_color: Color = MenuTheme.EMBER
var target_label: Label = null
var is_animating: bool = false
var settle_frames: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Trigger the stamp arrival on a label or card.
func trigger_stamp(label: Label, p_color: Color, reduced_motion: bool = false) -> void:
	target_label = label
	stamp_color = p_color
	# Magenta is strictly forbidden in the UI palette.
	if stamp_color.r > 0.5 and stamp_color.b > 0.5 and stamp_color.g < 0.25:
		stamp_color = MenuTheme.DANGER

	if target_label != null:
		target_label.pivot_offset = target_label.size * 0.5
		target_label.rotation = deg_to_rad(TILT_DEGREES)
		if reduced_motion:
			target_label.scale = Vector2.ONE
			is_animating = false
			settle_frames = 0
		else:
			target_label.scale = Vector2(FRAME1_SCALE, FRAME1_SCALE)
			is_animating = true
			settle_frames = 1

	visible = true
	queue_redraw()

func _process(_delta: float) -> void:
	if not is_animating:
		return
	if settle_frames > 0:
		settle_frames -= 1
		if settle_frames == 0:
			is_animating = false
			if target_label != null:
				target_label.scale = Vector2.ONE
			queue_redraw()

func _draw() -> void:
	if target_label == null or not target_label.visible:
		return

	# Draw worn-ink stamp border around the card / label bounds
	var l_rect: Rect2 = Rect2(target_label.position, target_label.size)
	# Faint offset impression behind/offset by (2, 2)
	var shadow_rect: Rect2 = l_rect.grow(4.0)
	shadow_rect.position += Vector2(2, 2)
	var faint_ink: Color = MenuTheme.alpha(stamp_color, 0.22)
	_draw_worn_border(shadow_rect, faint_ink)

	# Main stamped border
	var main_rect: Rect2 = l_rect.grow(4.0)
	_draw_worn_border(main_rect, stamp_color)

func _draw_worn_border(rect: Rect2, col: Color) -> void:
	# Heavy 3px stamped border with broken/weathered ink notches
	var border_w: float = 3.0
	# Top line with 2 worn pixel gaps
	draw_line(Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x + rect.size.x * 0.35, rect.position.y), col, border_w)
	draw_line(Vector2(rect.position.x + rect.size.x * 0.40, rect.position.y), Vector2(rect.position.x + rect.size.x * 0.75, rect.position.y), col, border_w)
	draw_line(Vector2(rect.position.x + rect.size.x * 0.80, rect.position.y), Vector2(rect.position.x + rect.size.x, rect.position.y), col, border_w)

	# Bottom line with worn notches
	var by: float = rect.position.y + rect.size.y
	draw_line(Vector2(rect.position.x, by), Vector2(rect.position.x + rect.size.x * 0.45, by), col, border_w)
	draw_line(Vector2(rect.position.x + rect.size.x * 0.52, by), Vector2(rect.position.x + rect.size.x, by), col, border_w)

	# Left line
	draw_line(Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.position.y + rect.size.y * 0.6), col, border_w)
	draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.68), Vector2(rect.position.x, by), col, border_w)

	# Right line
	var rx: float = rect.position.x + rect.size.x
	draw_line(Vector2(rx, rect.position.y), Vector2(rx, rect.position.y + rect.size.y * 0.5), col, border_w)
	draw_line(Vector2(rx, rect.position.y + rect.size.y * 0.58), Vector2(rx, by), col, border_w)
