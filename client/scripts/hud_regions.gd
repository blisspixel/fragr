class_name HudRegions
extends RefCounted

## One geometry owner for match facts, context and notices. All coordinates
## are logical canvas units, before the project's viewport stretch.
var hud: CanvasLayer
var context: VBoxContainer
var hints: Label
var conquest: ConquestHud
var vehicle: VehicleHud
var _layout_key: Array = []

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
	var key: Array = [view, origin, hud.sabotage(), hud.campaign_context, hud_scale, hud.mode_chip_label.text,
		hud.mode_chip_label.get_minimum_size(), context.get_combined_minimum_size(), hints.text,
		hud.weapon_label.text, hud.weapon_label.visible, hud.map_chip_label.text, hud.map_chip_label.visible,
		hud.radio_label, hud.radio_card, conquest, vehicle_rect, hud.frag_feed.reserved_height]
	if key == _layout_key:
		return
	_layout_key = key
	var panel: Control = hud.get_node("Panel")
	panel.position = Vector2(20, origin)
	panel.size = Vector2(minf(view.x * 0.45, 460.0 * hud_scale), 120.0 * hud_scale)
	var width: float = minf(720.0, maxf(320.0, view.x - 1200.0))
	var top: float = origin + (60.0 if hud.sabotage() else 0.0)
	hud.mode_chip_label.position = Vector2((view.x - width) * 0.5, top)
	hud.mode_chip_label.size = Vector2(width, 0)
	hud.mode_chip_label.size.y = hud.mode_chip_label.get_minimum_size().y
	if hud.sabotage_hud != null:
		hud.sabotage_hud.set_header_origin(origin)
	if conquest != null:
		conquest.set_header_rect(Rect2((view.x - width) * 0.5, top + hud.mode_chip_label.size.y + 8, width, 280))
	context.size = Vector2(minf(view.x * 0.45, 480.0 * hud_scale), 0)
	context.size.y = context.get_combined_minimum_size().y
	context.position = Vector2(24, view.y - (164.0 * hud_scale) - context.size.y)
	var frag_top: float = origin + 4.0
	var feed_w: float = minf(view.x * 0.48, 560.0 * hud_scale)
	hud.frag_feed.set_region(Rect2(view.x - feed_w - 16.0, frag_top, feed_w, hud.frag_feed.reserved_height))
	hud.objective_call.set_region(Rect2((view.x - width) * 0.5, view.y * 0.5 - (120.0 * hud_scale), width, 96.0 * hud_scale))
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
