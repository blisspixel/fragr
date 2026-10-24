class_name FragFeed
extends Control

signal geometry_changed
const LIMIT: int = 5
const LIFETIME: float = 4.5
const PENDING_LIMIT: int = 64
const ROW_HEIGHT: float = 40.0
const GAP: float = 4.0
const WEAPONS: Dictionary = {
	"tack": "Tack", "flechette": "Flechette", "scatter": "Scatter", "rail": "Rail",
	"sniper": "Sniper", "shiv": "Shiv", "arc": "Arc", "article_blade": "Article Blade",
}
var notices := HudNoticeQueue.new(LIMIT, PENDING_LIMIT, LIFETIME)
var coverage_query: Callable
var _covered: bool = false
var _rows: Dictionary = {}
var reserved_height: float = 216.0
## Body size from the HUD style; names and rows follow the HUD scale.
var text_size: int = MenuTheme.BODY
## Room on each side of the weapon glyph, so it reads as the verb between two
## names instead of touching either.
const GLYPH_GAP: int = 8

func occupied_region() -> Rect2:
	return Rect2(global_position, Vector2(size.x, reserved_height))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

static func _name(value: Variant) -> String:
	if not value is String:
		return "?"
	return value.replace("\n", " ").replace("\r", " ").replace("\t", " ").left(64)

func push(data: Dictionary, killer_id: String = "", victim_id: String = "", local_id: String = "", viewer_team: String = "") -> bool:
	var killer_team: String = MatchRules.valid_team(data.get("killer_team"))
	var victim_team: String = MatchRules.valid_team(data.get("victim_team"))
	var weapon: Variant = data.get("weapon")
	return notices.push({
		"killer": _name(data.get("killer")), "victim": _name(data.get("victim")),
		"killer_id": killer_id, "victim_id": victim_id,
		"killer_team": killer_team, "victim_team": victim_team,
		"killer_relation": HudRelation.token(killer_team, viewer_team),
		"victim_relation": HudRelation.token(victim_team, viewer_team),
		"weapon": weapon if weapon is String and weapon.length() <= 64 else "",
		"own": not local_id.is_empty() and local_id in [killer_id, victim_id],
	})

func clear() -> void:
	notices.clear()
	_sync_rows()

func set_text_size(value: int) -> void:
	if value == text_size:
		return
	text_size = value
	for row: PanelContainer in _rows.values():
		for label: Label in [row.get_node("Content/Killer"), row.get_node("Content/Victim")]:
			label.add_theme_font_size_override("font_size", text_size)
	_layout_rows()

## A callsign that does not fit its share of the row is shortened on purpose,
## not cut mid-letter: every word but the last becomes its initial
## ("DEAD AIR DAN" -> "D.A. DAN", "COMPLIANCE-DRONE" -> "C-DRONE"). Only a
## name still too wide after that is trimmed, with a closing period.
static func abbreviate(name: String, font: Font, size: int, width: float) -> String:
	var shown: String = name.to_upper()
	if font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return name
	var words: PackedStringArray = shown.split(" ", false)
	var last: String = words[words.size() - 1] if not words.is_empty() else shown
	var initials: String = ""
	for index: int in range(words.size() - 1):
		initials += words[index].left(1) + "."
	var parts: PackedStringArray = last.split("-", false)
	if parts.size() > 1:
		var tail: String = parts[parts.size() - 1]
		var heads: String = ""
		for index: int in range(parts.size() - 1):
			heads += parts[index].left(1) + "-"
		last = heads + tail
	var short: String = (initials + " " + last) if not initials.is_empty() else last
	while short.length() > 2 and font.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		short = short.left(short.length() - 2) + "."
	return short

func set_region(rect: Rect2) -> void:
	if position == rect.position and size == rect.size:
		return
	position = rect.position
	size = rect.size
	_layout_rows()

func set_covered(value: bool) -> void:
	_covered = value
	visible = not covered()

func covered() -> bool:
	return _covered or (coverage_query.is_valid() and bool(coverage_query.call()))

func _process(delta: float) -> void:
	var hidden: bool = covered()
	visible = not hidden
	notices.advance(delta, hidden)
	_sync_rows()

func _sync_rows() -> void:
	var retained: Dictionary = {}
	for entry: Dictionary in notices.active:
		var serial: int = entry.serial
		retained[serial] = true
		if not _rows.has(serial):
			var row: PanelContainer = _row(entry.payload)
			_rows[serial] = row
			add_child(row)
	for serial: Variant in _rows.keys():
		if not retained.has(serial):
			var row: PanelContainer = _rows[serial]
			_rows.erase(serial)
			remove_child(row)
			row.queue_free()
	_layout_rows()

static func _label(text: String, own: bool, font_size: int = MenuTheme.BODY) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.tooltip_text = text
	label.set_meta("full_name", text)
	MenuTheme.pixel_text(label, font_size, MenuTheme.INK if own else MenuTheme.BONE, 0)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label

func _row(payload: Dictionary) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("facts", payload.duplicate(true))
	var style := StyleBoxFlat.new()
	style.bg_color = MenuTheme.BONE if payload.own else MenuTheme.INK
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var content := HBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	content.add_child(HudRelation.mark(payload.killer_team, payload.killer_relation, payload.own))
	var killer: Label = _label(payload.killer, payload.own, text_size)
	killer.name = "Killer"
	content.add_child(killer)
	var wire: String = payload.weapon
	var art: String = str(WEAPONS.get(wire, ""))
	if WeaponArt.PROFILE.has(art):
		var glyph := TextureRect.new()
		glyph.name = "Weapon"
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.texture = WeaponArt.PROFILE[art]
		glyph.tooltip_text = wire
		# The glyph's own box carries the gap on both sides of the art.
		glyph.custom_minimum_size = Vector2(88 + 2 * GLYPH_GAP, 32)
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		content.add_child(glyph)
	else:
		var fallback: Label = _label(wire if not wire.is_empty() else ">", payload.own, text_size)
		fallback.name = "Weapon"
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.custom_minimum_size.x = minf(210.0, MenuTheme.FONT.get_string_size(fallback.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x) + 2 * GLYPH_GAP
		content.add_child(fallback)
	content.add_child(HudRelation.mark(payload.victim_team, payload.victim_relation, payload.own))
	var victim: Label = _label(payload.victim, payload.own, text_size)
	victim.name = "Victim"
	content.add_child(victim)
	return panel

func _layout_rows() -> void:
	var top: float = 0.0
	for entry: Dictionary in notices.active:
		if not _rows.has(entry.serial):
			continue
		var panel: PanelContainer = _rows[entry.serial]
		var content: HBoxContainer = panel.get_node("Content")
		var killer: Label = content.get_node("Killer")
		var victim: Label = content.get_node("Victim")
		var weapon: Control = content.get_node("Weapon")
		# Row margins, two relation marks and four gaps around them.
		var chrome: float = 16.0 + 12.0 + 4.0 * float(content.get_theme_constant("separation"))
		var budget: float = maxf(48.0, size.x - chrome - weapon.get_combined_minimum_size().x)
		var font: Font = killer.get_theme_font("font")
		var font_size: int = killer.get_theme_font_size("font_size")
		var killer_name: String = str(killer.get_meta("full_name", killer.text))
		var victim_name: String = str(victim.get_meta("full_name", victim.text))
		var first: float = font.get_string_size(killer_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var second: float = font.get_string_size(victim_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var killer_room: float = floorf(minf(first, maxf(budget * 0.5, budget - second)))
		var victim_room: float = floorf(minf(second, maxf(budget * 0.5, budget - first)))
		killer.text = abbreviate(killer_name, font, font_size, killer_room)
		victim.text = abbreviate(victim_name, font, font_size, victim_room)
		killer.custom_minimum_size.x = ceilf(font.get_string_size(killer.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		victim.custom_minimum_size.x = ceilf(font.get_string_size(victim.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		var height: float = maxf(ROW_HEIGHT, panel.get_combined_minimum_size().y)
		panel.position = Vector2(0, top)
		panel.size = Vector2(size.x, height)
		top += height + GAP
	var measured: float = maxf(216.0, top - GAP)
	if measured != reserved_height:
		reserved_height = measured
		geometry_changed.emit()
