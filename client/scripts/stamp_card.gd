class_name StampCard
extends Control

## Signature moment: Stamped (round, match, and episode result cards).
## A worn-ink border lands around the card's drawn text in the winning side's
## relation colour, with a faint offset impression behind it. No flash, no
## shake. Zero magenta.
##
## Nothing about a card is rotated: not the copy, not the backing, not the ink
## (#437, "no tilted text, anywhere"). The winner, score, reason and next line
## keep one level baseline at 100 percent; the settle (106% to 100% over one
## frame) scales the decorative ink only. Reduced motion lands the ink at rest
## immediately.
##
## The stamp follows its card. When the target label hides, leaves the tree or
## is replaced by another card, the ink retires and redraws empty, so a border
## never outlives the card it marked.

const FRAME1_SCALE: float = 1.06
## Space between the drawn text and the border.
const PADDING: float = 10.0

var stamp_color: Color = MenuTheme.EMBER
var target_label: Label = null
var is_animating: bool = false
var settle_frames: int = 0
## Decorative ink scale about the text center; the label itself stays at 1.
var ink_scale: float = 1.0
## The target's drawn text bounds in this node's coordinates.
var text_frame: Rect2 = Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if target_label == null:
		visible = false
		set_process(false)

## Trigger the stamp arrival on a result card label.
func trigger_stamp(label: Label, p_color: Color, reduced_motion: bool = false) -> void:
	retire()
	if label == null:
		return
	target_label = label
	stamp_color = p_color
	# Magenta is strictly forbidden in the UI palette.
	if stamp_color.r > 0.5 and stamp_color.b > 0.5 and stamp_color.g < 0.25:
		stamp_color = MenuTheme.DANGER
	# Essential copy stays upright on its own baseline, whatever came before.
	label.rotation = 0.0
	label.scale = Vector2.ONE
	ink_scale = 1.0 if reduced_motion else FRAME1_SCALE
	is_animating = not reduced_motion
	settle_frames = 0 if reduced_motion else 1
	visible = true
	set_process(true)
	_refresh_frame()
	queue_redraw()

## Remove the ink and forget the card. Safe to call at any time.
func retire() -> void:
	target_label = null
	is_animating = false
	settle_frames = 0
	ink_scale = 1.0
	text_frame = Rect2()
	visible = false
	set_process(false)
	queue_redraw()

func active() -> bool:
	return target_label != null

func _process(_delta: float) -> void:
	if not is_instance_valid(target_label) or not target_label.is_visible_in_tree():
		retire()
		return
	if is_animating:
		settle_frames -= 1
		if settle_frames <= 0:
			is_animating = false
			ink_scale = 1.0
			queue_redraw()
	_refresh_frame()

## Text can reflow after the trigger (card fitting, HUD scale): follow it.
func _refresh_frame() -> void:
	if target_label == null:
		return
	var bounds: Rect2 = HudRegions.text_bounds(target_label)
	var local: Rect2 = get_global_transform().affine_inverse() * bounds
	if local != text_frame:
		text_frame = local
		queue_redraw()

## The main border: the text bounds plus padding, scaled about their center
## while the ink settles.
func ink_rect() -> Rect2:
	if not text_frame.has_area():
		return Rect2()
	var rect: Rect2 = text_frame.grow(PADDING)
	var size_scaled: Vector2 = rect.size * ink_scale
	return Rect2(rect.get_center() - size_scaled * 0.5, size_scaled)

func _draw() -> void:
	if target_label == null:
		return
	var main_rect: Rect2 = ink_rect()
	if not main_rect.has_area():
		return
	# Faint impression, offset by (2, 2) and level like everything else.
	_draw_worn_border(Rect2(main_rect.position + Vector2(2, 2), main_rect.size), MenuTheme.alpha(stamp_color, 0.22))
	# Main stamped border.
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
