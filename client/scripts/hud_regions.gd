class_name HudRegions
extends RefCounted

## One geometry owner for match facts, context and notices. All coordinates
## are logical canvas units, before the project's viewport stretch.
##
## The top band has three columns: the corner facts on the left, the centered
## match facts, and the frag feed with notices on the right. The side columns
## shrink before the center falls under its floor, so no HUD scale or text size
## puts two columns over the same pixels. Text owned by other canvas layers on
## the same canvas (the frame counter) arrives through
## `hud.top_region_query` as reserved rectangles, and each column starts below
## any reservation that crosses its span. Nothing is shrunk to fit under them.

## Space between neighbouring columns.
const GAP: float = 16.0
## The narrowest centered column at 100 percent HUD scale, and the widest.
const CENTER_FLOOR: float = 320.0
const CENTER_CEILING: float = 720.0

var hud: CanvasLayer
var context: VBoxContainer
var hints: Label
var conquest: ConquestHud
var vehicle: VehicleHud
var _layout_key: Array = []
## Vertical shift currently applied to the round card, so placement can be
## recomputed without accumulating.
var card_shift: float = 0.0

func _init(owner: CanvasLayer) -> void:
	hud = owner
	context = VBoxContainer.new()
	context.name = "Context"
	context.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context.add_theme_constant_override("separation", 8)
	hud.add_child(context)
	hints = Label.new()
	hints.name = "ControlsHint"
	hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hints.add_theme_constant_override("outline_size", 4)
	hints.add_theme_color_override("font_outline_color", MenuTheme.INK)
	context.add_child(hints)
	hud.weapon_label.reparent(context)
	hud.map_chip_label.reparent(context)
	for diagnostic: Label in [hud.status_label, hud.tick_label, hud.player_count_label]:
		diagnostic.reparent(context)
	for label: Label in [hud.weapon_label, hud.map_chip_label]:
		label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.mode_chip_label.reparent(hud)
	hud.mode_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.mode_chip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.mode_label.max_lines_visible = 1
	hud.round_label.max_lines_visible = 1
	hud.mode_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hud.round_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hud.scoreboard.hide()

func layout() -> void:
	var view: Vector2 = hud.get_viewport().get_visible_rect().size
	# Cards take priority without discarding the accepted match facts below them.
	var covered: bool = hud.round_message.visible or hud.warmup_tv_active
	hud.mode_chip_label.visible = not covered and not hud.campaign_context and not hud.mode_chip_label.text.is_empty()
	if hud.sabotage_hud != null:
		hud.sabotage_hud.visible = not covered
	if conquest != null:
		conquest.set_covered(covered)
	var vehicle_rect: Rect2 = vehicle.occupied_region() if is_instance_valid(vehicle) else Rect2()
	var origin: float = 16.0
	for decoration: Control in [hud.chrome_strip, hud.on_air_badge, hud.contested_frequency_badge]:
		if decoration != null and decoration.visible:
			origin = maxf(origin, decoration.position.y + decoration.size.y + 16.0)
	hud.weapon_label.visible = not hud.weapon_label.text.is_empty() and hud.client_mode == "SPECTATING"
	hints.visible = not hints.text.is_empty()
	var hud_scale: float = hud.hud_style.scale if hud != null and "hud_style" in hud and hud.hud_style != null else 1.0
	var text_scale: float = float(hud.hud_style.body_font_size()) / float(MenuTheme.BODY) if hud != null and "hud_style" in hud and hud.hud_style != null else hud_scale
	var reserved: Array[Rect2] = reserved_regions()
	var key: Array = [view, origin, hud.sabotage(), hud.campaign_context, hud_scale, text_scale, hud.mode_chip_label.text,
		hud.mode_chip_label.get_minimum_size(), context.get_combined_minimum_size(), hints.text,
		hud.weapon_label.text, hud.weapon_label.visible, hud.map_chip_label.text, hud.map_chip_label.visible,
		hud.radio_label, hud.radio_card, conquest, vehicle_rect, hud.frag_feed.reserved_height, reserved,
		hud.round_message.visible, hud.round_message.text, hud.round_backdrop != null and hud.round_backdrop.visible]
	if key == _layout_key:
		return
	_layout_key = key
	var band: Dictionary = top_band(view.x, hud_scale, text_scale)
	var panel: Control = hud.get_node("Panel")
	var panel_w: float = band.left_width
	panel.position = Vector2(20, column_top(origin, 20.0, panel_w, reserved))
	panel.size = Vector2(panel_w, 120.0 * hud_scale)
	var width: float = band.center_width
	var center_x: float = (view.x - width) * 0.5
	var center_origin: float = column_top(origin, center_x, width, reserved)
	var top: float = center_origin + (60.0 if hud.sabotage() else 0.0)
	hud.mode_chip_label.position = Vector2(center_x, top)
	hud.mode_chip_label.size = Vector2(width, 0)
	hud.mode_chip_label.size.y = hud.mode_chip_label.get_minimum_size().y
	if hud.sabotage_hud != null:
		hud.sabotage_hud.set_header_origin(center_origin)
	if conquest != null:
		conquest.set_header_rect(Rect2(center_x, top + hud.mode_chip_label.size.y + 8, width, 280))
	context.size = Vector2(minf(view.x * 0.45, 480.0 * hud_scale), 0)
	context.size.y = context.get_combined_minimum_size().y
	context.position = Vector2(24, view.y - (164.0 * hud_scale) - context.size.y)
	var feed_w: float = band.right_width
	var frag_top: float = column_top(origin + 4.0, view.x - feed_w - 16.0, feed_w, reserved)
	hud.frag_feed.set_region(Rect2(view.x - feed_w - 16.0, frag_top, feed_w, hud.frag_feed.reserved_height))
	# The objective call sits mid-screen, outside the top band's columns.
	var call_w: float = minf(CENTER_CEILING, maxf(CENTER_FLOOR, view.x - 1200.0))
	hud.objective_call.set_region(Rect2((view.x - call_w) * 0.5, view.y * 0.5 - (120.0 * hud_scale), call_w, 96.0 * hud_scale))
	var radio_bottom: float = view.y - (248.0 * hud_scale)
	if vehicle_rect.has_area():
		radio_bottom = minf(radio_bottom, vehicle_rect.position.y - 16.0)
	if hud.radio_label != null:
		hud.radio_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		hud.radio_label.position = Vector2(view.x - minf(view.x - 16.0, 640.0 * hud_scale), radio_bottom - (100.0 * hud_scale))
		hud.radio_label.size = Vector2(minf(view.x - 32.0, 624.0 * hud_scale), 100.0 * hud_scale)
	if hud.radio_card != null:
		hud.radio_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		hud.radio_card.position = Vector2(view.x - minf(view.x - 16.0, 640.0 * hud_scale), radio_bottom - (276.0 * hud_scale))
		hud.radio_card.size = Vector2(minf(view.x - 32.0, 624.0 * hud_scale), 164.0 * hud_scale)
	if hud.campaign_context:
		hud.combat_feed.set_limit(3)
		hud.combat_feed.set_region(Rect2(24, context.position.y - (246.0 * hud_scale), minf(view.x * 0.45, 480.0 * hud_scale), 230.0 * hud_scale))
	else:
		var voice_top: float = frag_top + hud.frag_feed.reserved_height + 12.0
		var card_on_right: bool = hud.radio_card != null
		if card_on_right and radio_bottom - (292.0 * hud_scale) - voice_top < 132.0:
			hud.radio_card.position = Vector2(24, origin + 144.0)
			card_on_right = false
		var voice_bottom: float = radio_bottom - ((292.0 if card_on_right else 116.0 if hud.radio_label != null else 16.0) * hud_scale)
		var available: float = maxf(0.0, voice_bottom - voice_top)
		hud.combat_feed.set_limit(clampi(int((available + 4.0) / 66.0), 0, 3))
		hud.combat_feed.set_region(Rect2(view.x - feed_w - 16.0, voice_top, feed_w, available))
	place_card(view, reserved)

## Undo the current card shift on the label and its backing, visible or not,
## before the card owner writes fresh offsets; the next layout places it again.
func reset_card_shift() -> void:
	_shift_card(-card_shift)
	card_shift = 0.0
	_layout_key = []

func _shift_card(amount: float) -> void:
	for node: Control in [hud.round_message, hud.round_backdrop]:
		if node != null:
			node.offset_top += amount
			node.offset_bottom += amount

## Keep the shared round card inside the space its neighbours leave. Above it:
## the corner facts and any reserved top text (the frame counter)
## that cross its span. Below it: the bottom-left context when they share
## columns, otherwise the band reserved for vitals. A tall card (a long podium,
## wrapped names, large text) moves the least distance that fits; a backed card
## grows upward from its anchor and may move down. When it cannot fit above the
## context, the context yields while the card is up and returns with it, the
## priority centered match facts already give cards. Text is never shrunk.
func place_card(view: Vector2, reserved: Array[Rect2]) -> void:
	var message: Label = hud.round_message
	var backdrop: Control = hud.round_backdrop
	var backed: bool = backdrop != null and backdrop.visible
	_shift_card(-card_shift)
	card_shift = 0.0
	if not message.visible:
		context.visible = true
		return
	var top: float
	var bottom: float
	var left: float
	var right: float
	if backed:
		top = view.y * 0.5 + backdrop.offset_top
		bottom = view.y * 0.5 + backdrop.offset_bottom
		left = view.x * 0.5 + backdrop.offset_left
		right = view.x * 0.5 + backdrop.offset_right
	else:
		# The label grows both ways about its offset center to fit its text.
		var center: float = view.y * 0.5 + (message.offset_top + message.offset_bottom) * 0.5
		var height: float = maxf(message.offset_bottom - message.offset_top, message.get_minimum_size().y)
		top = center - height * 0.5
		bottom = center + height * 0.5
		left = view.x * 0.5 + message.offset_left
		right = view.x * 0.5 + message.offset_right
	var panel: Rect2 = Rect2(hud.get_node("Panel").position, hud.get_node("Panel").size)
	var ceiling: float = column_top(GAP, left, right - left, reserved)
	if panel.position.x < right and panel.end.x > left:
		ceiling = maxf(ceiling, panel.end.y + GAP * 0.5)
	var vitals_floor: float = context.position.y + context.size.y
	var shares_context: bool = context.position.x < right and context.position.x + context.size.x > left
	var floor_y: float = context.position.y - GAP if shares_context else vitals_floor
	var fits: bool = bottom - top <= floor_y - ceiling
	if not fits:
		floor_y = vitals_floor
	card_shift = fit_shift(top, bottom, ceiling, floor_y)
	if card_shift != 0.0:
		_shift_card(card_shift)
	context.visible = fits or not shares_context

## The least vertical move that puts [top, bottom] inside [low, high]. A span
## taller than the room keeps its top at `low`, so the first lines stay readable.
static func fit_shift(top: float, bottom: float, low: float, high: float) -> float:
	if bottom - top > high - low or top < low:
		return low - top
	if bottom > high:
		return high - bottom
	return 0.0

## Column widths for a canvas width, HUD scale and text scale (the body font
## size over the standard 24). The corner takes up to 460 and the feed up to
## 560 logical units per 100 percent HUD scale. The center's floor follows the
## text it holds, so large text keeps a few words per line instead of a tall
## column running toward the crosshair. When the sides would leave the center
## under that floor, both give up width and the center stays centered.
static func top_band(view_width: float, hud_scale: float, text_scale: float = -1.0) -> Dictionary:
	if text_scale <= 0.0:
		text_scale = hud_scale
	var floor_width: float = minf(CENTER_FLOOR * text_scale, view_width * 0.5)
	# Each side owns its edge margin (20 left, 16 right) and one gap.
	var side_cap: float = (view_width - floor_width) * 0.5 - GAP
	var left: float = minf(minf(view_width * 0.45, 460.0 * hud_scale), side_cap - 20.0)
	var right: float = minf(minf(view_width * 0.48, 560.0 * hud_scale), side_cap - 16.0)
	var side: float = maxf(20.0 + left, 16.0 + right) + GAP
	var ceiling: float = maxf(floor_width, minf(CENTER_CEILING, view_width - 1200.0))
	var center: float = clampf(view_width - 2.0 * side, floor_width, ceiling)
	return {"left_width": left, "center_width": center, "right_width": right}

## The first y at or below `top` that clears every reservation crossing the
## horizontal span from x to x + width.
static func column_top(top: float, x: float, width: float, reserved: Array[Rect2]) -> float:
	var result: float = top
	for rect: Rect2 in reserved:
		if rect.position.x < x + width and rect.end.x > x:
			result = maxf(result, rect.end.y + GAP * 0.5)
	return result

## Rectangles the match manager reserves in the top band, validated here
## because the query is an external callable: anything but finite Rect2 values
## with area is ignored rather than trusted.
func reserved_regions() -> Array[Rect2]:
	var regions: Array[Rect2] = []
	var query: Variant = hud.get("top_region_query")
	if not query is Callable or not (query as Callable).is_valid():
		return regions
	var answer: Variant = (query as Callable).call()
	if not answer is Array:
		return regions
	for value: Variant in answer:
		if value is Rect2 and (value as Rect2).has_area() and (value as Rect2).is_finite():
			regions.append(value)
	return regions

## Drawn text bounds in canvas coordinates: the widest line from the label's
## own font and size (capped by its width when it wraps), aligned as the label
## aligns it, through the label's full canvas transform. A rotated or scaled
## label is measured as drawn, not as its logical rectangle.
static func text_bounds(label: Label) -> Rect2:
	if label == null or not label.is_visible_in_tree() or label.text.strip_edges().is_empty():
		return Rect2()
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var width: float = 0.0
	for line: String in label.text.split("\n"):
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	width = minf(width, label.size.x)
	var lines: int = maxi(1, label.get_visible_line_count())
	var height: float = minf(label.size.y, float(lines) * font.get_height(font_size) + float(lines - 1) * label.get_theme_constant("line_spacing"))
	var x: float = 0.0
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x = (label.size.x - width) * 0.5
	elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = label.size.x - width
	var y: float = 0.0
	if label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		y = (label.size.y - height) * 0.5
	elif label.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		y = label.size.y - height
	var transform: Transform2D = label.get_global_transform()
	var box: Rect2 = Rect2(transform * Vector2(x, y), Vector2.ZERO)
	for corner: Vector2 in [Vector2(x + width, y), Vector2(x, y + height), Vector2(x + width, y + height)]:
		box = box.expand(transform * corner)
	return box
