class_name SpectatorPanel
extends Control

## The booth strip a watcher sees under the scoreline: one tile per kind of
## pad worth timing, each a pickup icon inside a countdown ring with its clock
## under it, then one line for who wears the Custody Plate and who is on a
## run. The clocks come from the server's booth facts (`spectator_facts`),
## which no fighter receives, and count down here between messages.
##
## Power items (the Plate and the heavy guns) always show; ordinary guns,
## armour and health join only in their last seconds, or all of them while
## the watcher holds the scoreboard (`expanded`). Every word is Silkscreen in
## capitals on a level baseline. Presentation only.

## Facts older than this are a booth that stopped talking: a joined fighter,
## a campaign map or a dropped connection. The strip hides.
const STALE_MS: int = 2500
const TICKS_PER_SECOND: float = 20.0
## A clock this close to zero is a fight about to start over the pad, and
## the window in which an ordinary pad earns a tile.
const SOON_SECONDS: float = 5.0
## Runs shorter than this stay off the strip; the feed already shows a double.
const MIN_RUN: int = 3
const MAX_RUNS: int = 2
## The tile at full size: the ring's diameter and the column it sits in.
const RING: float = 60.0
const TILE_W: float = 84.0
const TILE_GAP: int = 6
const PAD_X: float = 12.0
const PAD_Y: float = 8.0
## Power items in the order a caster reads them. The Plate leads.
const POWER_ORDER: Array[String] = ["Rail", "Rocket", "Sniper", "Arc", "Article Blade"]
## Ordinary pads, shown only near their return or on the expanded strip.
const ORDINARY_ORDER: Array[String] = ["Scatter", "Repeater", "Flechette", "Tack", "armor", "health"]
const NAMES: Dictionary = {
	"Rail": "BOOTH_PAD_RAIL", "Rocket": "BOOTH_PAD_ROCKET", "Sniper": "BOOTH_PAD_SNIPER",
	"Arc": "BOOTH_PAD_ARC", "Scatter": "BOOTH_PAD_SCATTER", "Repeater": "BOOTH_PAD_REPEATER",
	"Flechette": "BOOTH_PAD_FLECHETTE", "Tack": "BOOTH_PAD_TACK",
	"Article Blade": "BOOTH_PAD_ARTICLE_BLADE", "armor": "BOOTH_PAD_ARMOR", "health": "BOOTH_PAD_HEALTH",
	"plate": "BOOTH_PAD_PLATE",
}

## True while this client watches rather than fights.
var watching: bool = false
## True while the watcher holds the scoreboard: every pad gets a tile.
var expanded: bool = false
var _covered: bool = false
var _facts: Dictionary = {}
var _facts_ms: int = -STALE_MS
var _pickups: Array = []
var _names: Dictionary = {}
var _backing: Panel
var _tiles: HBoxContainer
var _heading: Label
var _notes: Label
var _shown: Array = []
var _region: Rect2 = Rect2()
## A clock reading for the harnesses: milliseconds since the facts arrived.
var clock_override_ms: int = -1
## The rings move every frame a clock runs; the tiles rebuild only when the
## set of tiles or their words change.
const REFRESH_SECONDS: float = 0.05
var _refresh_in: float = 0.0

## One countdown ring: a dark disc, the pickup icon, a track and the arc of
## the clock still to run. Drawn level, never rotated.
class PadRing extends Control:
	var icon: Texture2D = null
	## Share of the clock still to run, 0 when up.
	var left: float = 0.0
	var tone: String = "wait"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		var centre: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.5 - 3.0
		draw_circle(centre, radius + 2.0, MenuTheme.alpha(MenuTheme.INK, 0.85), true, -1.0, false)
		var colour: Color = SpectatorPanel.tone_colour(tone)
		draw_arc(centre, radius, 0.0, TAU, 48, MenuTheme.EDGE, 4.0, false)
		var sweep: float = TAU if tone in ["up", "held"] else clampf(left, 0.0, 1.0) * TAU
		if sweep > 0.0:
			draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + sweep, maxi(4, int(48.0 * sweep / TAU)), colour, 4.0, false)
		if icon != null:
			var room: float = radius * 2.0 - 4.0
			var art: Vector2 = icon.get_size()
			var fit: float = minf(room / maxf(1.0, art.x), room / maxf(1.0, art.y))
			# Whole pixels when the art fits at least once over: no smeared texels.
			if fit >= 1.0:
				fit = floorf(fit)
			var drawn: Vector2 = (art * fit).floor()
			var shade: Color = MenuTheme.UNTINTED if tone in ["up", "held"] else Color(0.8, 0.8, 0.8, 1.0)
			draw_texture_rect(icon, Rect2((centre - drawn * 0.5).round(), drawn), false, shade)

func _ready() -> void:
	name = "SpectatorPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_backing = Panel.new()
	_backing.name = "Backing"
	_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backing.add_theme_stylebox_override("panel", MenuTheme.backing())
	add_child(_backing)
	_heading = Label.new()
	_heading.name = "Heading"
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.pixel_text(_heading, MenuTheme.BODY, MenuTheme.MUTED, 0)
	_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_heading)
	_tiles = HBoxContainer.new()
	_tiles.name = "Rows"
	_tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tiles.add_theme_constant_override("separation", TILE_GAP)
	add_child(_tiles)
	_notes = Label.new()
	_notes.name = "Notes"
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notes.clip_text = true
	_notes.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	MenuTheme.pixel_text(_notes, MenuTheme.BODY, MenuTheme.BONE, 0)
	add_child(_notes)

## The booth's latest facts, as `SpectatorFacts.parse` typed them.
func observe_facts(facts: Dictionary) -> void:
	if facts.is_empty():
		return
	if not _facts.is_empty() and int(facts.get("tick", 0)) < int(_facts.get("tick", 0)):
		return
	_facts = facts
	_facts_ms = Time.get_ticks_msec()

## The shared world: every pad's availability and every fighter's callsign.
func observe_snapshot(snapshot: Dictionary) -> void:
	var pickups: Variant = snapshot.get("pickups", [])
	_pickups = pickups if pickups is Array else []
	_names.clear()
	var players: Variant = snapshot.get("players", [])
	if players is Array:
		for player: Variant in players:
			if player is Dictionary and player.get("id") is String:
				_names[player["id"]] = FragFeed._name(player.get("name"))

## Forget the booth: a new map, a join, or the end of the session.
func clear() -> void:
	_facts = {}
	_facts_ms = -STALE_MS
	_pickups = []
	_names.clear()

## The room the strip may use: centred in it, as tall as it needs from its top.
func set_region(rect: Rect2) -> void:
	_region = rect

func set_covered(value: bool) -> void:
	if value != _covered:
		_refresh_in = 0.0
	_covered = value

func set_expanded(value: bool) -> void:
	if value != expanded:
		_refresh_in = 0.0
	expanded = value

func _elapsed_ms() -> int:
	return clock_override_ms if clock_override_ms >= 0 else Time.get_ticks_msec() - _facts_ms

## Seconds left on a clock the facts gave in ticks, counted down since.
func seconds_left(back_in_ticks: int) -> float:
	return maxf(0.0, float(back_in_ticks) / TICKS_PER_SECOND - float(_elapsed_ms()) / 1000.0)

static func clock_text(seconds: float) -> String:
	var whole: int = ceili(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]

func _live() -> bool:
	return not _facts.is_empty() and _elapsed_ms() <= STALE_MS

## The tiles to show, as plain data: `{key, icon, label, value, tone, left,
## power}`. `tone` is `up`, `wait`, `soon` or `held`; `left` is the share of
## the clock still to run. Power items always; an ordinary pad only in its
## last `SOON_SECONDS` or while expanded. Empty while the booth is quiet or
## stale.
func tiles(all: bool = expanded) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _live():
		return out
	var clocks: Dictionary = {}
	for pad: Dictionary in _facts.get("pads", []):
		clocks[pad["id"]] = pad
	var plate: Dictionary = _facts.get("plate", {})
	if not plate.is_empty():
		var tile: Dictionary = {"key": "plate", "icon": WeaponArt.SUPPLY.get("plate"), "label": tr(NAMES["plate"]), "power": true, "left": 0.0}
		if not str(plate.get("holder", "")).is_empty():
			# Worn: what the Plate has left on its wearer; the name is a note.
			tile["value"] = str(plate.get("armor", 0))
			tile["tone"] = "held"
		elif bool(plate.get("up")):
			tile["value"] = tr("BOOTH_UP")
			tile["tone"] = "up"
		else:
			var left: float = seconds_left(int(plate.get("back_in", 0)))
			tile["value"] = clock_text(left)
			tile["tone"] = "soon" if left <= SOON_SECONDS else "wait"
			var whole: float = float(plate.get("clock", -1)) / TICKS_PER_SECOND
			tile["left"] = left / whole if whole > 0.0 else 1.0
		out.append(tile)
	for key: String in POWER_ORDER:
		var tile: Dictionary = _pad_tile(key, clocks)
		if not tile.is_empty():
			tile["power"] = true
			out.append(tile)
	for key: String in ORDINARY_ORDER:
		var tile: Dictionary = _pad_tile(key, clocks)
		if tile.is_empty():
			continue
		tile["power"] = false
		if all or tile["tone"] == "soon":
			out.append(tile)
	return out

## One tile per kind of pad: up when any copy is, else the soonest copy.
func _pad_tile(key: String, clocks: Dictionary) -> Dictionary:
	var any: bool = false
	var up: bool = false
	var soonest: Dictionary = {}
	for pad: Variant in _pickups:
		if not pad is Dictionary or pad.get("dropped") == true:
			continue
		var kind: String = str(pad.get("kind", "weapon"))
		var matches: bool = kind == key if key in ["armor", "health"] else (kind == "weapon" and str(pad.get("weapon", "")) == key)
		if not matches:
			continue
		any = true
		if pad.get("available") == true:
			up = true
		elif clocks.has(pad.get("id")):
			var clock: Dictionary = clocks[pad["id"]]
			if soonest.is_empty() or int(clock["back_in"]) < int(soonest["back_in"]):
				soonest = clock
	if not any:
		return {}
	# Guns wear their bone kill-feed silhouette, which reads on the dark disc.
	var icon: Texture2D = WeaponArt.SUPPLY.get(key) if key in ["armor", "health"] else WeaponArt.kill_icon(key)
	var tile: Dictionary = {"key": key, "icon": icon, "label": tr(str(NAMES.get(key, key))), "left": 0.0}
	if up:
		tile["value"] = tr("BOOTH_UP")
		tile["tone"] = "up"
	elif not soonest.is_empty():
		var left: float = seconds_left(int(soonest["back_in"]))
		tile["value"] = clock_text(left)
		tile["tone"] = "soon" if left <= SOON_SECONDS else "wait"
		var whole: float = float(soonest.get("clock", 0)) / TICKS_PER_SECOND
		tile["left"] = left / whole if whole > 0.0 else 1.0
	else:
		tile["value"] = "--"
		tile["tone"] = "wait"
	return tile

## The line under the tiles: who wears the Plate, then the longest runs and
## any open chain, each `{text, tone}`. Empty while nothing is worth a word.
func notes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _live():
		return out
	var plate: Dictionary = _facts.get("plate", {})
	if not plate.is_empty() and not str(plate.get("holder", "")).is_empty():
		out.append({"text": tr("BOOTH_PLATE_WORN").format({"name": str(_names.get(plate["holder"], "?")).to_upper()}), "tone": "held"})
	var step: int = maxi(1, int(_facts.get("spree_step", 5)))
	var chains: Array = _facts.get("chains", [])
	var chain_id: String = str(chains[0]["id"]) if not chains.is_empty() else ""
	var chain_word: String = tr("BOOTH_CHAIN_" + str(clampi(int(chains[0]["frags"]), 2, 5))) if not chains.is_empty() else ""
	var runs: Array[String] = []
	var top: int = 0
	for spree: Dictionary in _facts.get("sprees", []):
		if int(spree["frags"]) >= MIN_RUN and runs.size() < MAX_RUNS:
			top = maxi(top, int(spree["frags"]))
			var words: String = str(_names.get(spree["id"], "?")).to_upper() + " " + str(int(spree["frags"]))
			# A run with an open chain says both at once.
			if str(spree["id"]) == chain_id:
				words += " " + chain_word
				chain_id = ""
			runs.append(words)
	if not runs.is_empty():
		out.append({"text": run_heading(top, step) + ": " + "  ".join(runs), "tone": "run"})
	if not chain_id.is_empty():
		out.append({"text": str(_names.get(chain_id, "?")).to_upper() + " " + chain_word, "tone": "soon"})
	return out

## The runs heading in the Host's own tiers for the longest run: a step in
## this mode is a Rampage, two a Riot, three Untouchable; below a step it is
## a plain run.
static func run_heading(frags: int, step: int) -> String:
	var tier: int = frags / maxi(1, step)
	var key: String = "BOOTH_RUNS"
	if tier >= 3:
		key = "BOOTH_UNTOUCHABLE"
	elif tier == 2:
		key = "BOOTH_RIOT"
	elif tier == 1:
		key = "BOOTH_RAMPAGE"
	return TranslationServer.translate(key)

static func tone_colour(tone: String) -> Color:
	match tone:
		"up":
			return MenuTheme.BONE
		"soon", "run":
			return MenuTheme.EMBER
		"held":
			return MatchRules.GOLD
	return MenuTheme.MUTED

## The tile column for `count` tiles in `width`: full size when they fit,
## narrower (never under the clock's own width) when they do not.
static func tile_width(count: int, width: float, heading: float) -> float:
	if count <= 0:
		return TILE_W
	var room: float = width - 2.0 * PAD_X - heading - float(TILE_GAP * count)
	return clampf(floorf(room / float(count)), 48.0, TILE_W)

func _process(delta: float) -> void:
	_refresh_in -= delta
	if _refresh_in > 0.0:
		return
	_refresh_in = REFRESH_SECONDS
	var shown: Array[Dictionary] = []
	var lines: Array[Dictionary] = []
	if watching:
		shown = tiles()
		lines = notes()
	visible = not _covered and not (shown.is_empty() and lines.is_empty()) and _region.has_area()
	if not visible:
		return
	var key: Array = [expanded, TranslationServer.get_locale(), _region.size.x]
	for tile: Dictionary in shown:
		key.append([tile["key"], tile["value"], tile["tone"]])
	for line: Dictionary in lines:
		key.append([line["text"], line["tone"]])
	if key != _shown:
		_shown = key
		_rebuild(shown, lines)
	# The rings sweep between rebuilds.
	for index: int in range(mini(shown.size(), _tiles.get_child_count())):
		var ring: PadRing = _tiles.get_child(index).get_node("Ring") as PadRing
		if ring != null and not is_equal_approx(ring.left, float(shown[index]["left"])):
			ring.left = float(shown[index]["left"])
			ring.queue_redraw()

func _rebuild(shown: Array[Dictionary], lines: Array[Dictionary]) -> void:
	for child: Node in _tiles.get_children():
		_tiles.remove_child(child)
		child.queue_free()
	_heading.text = tr("BOOTH_HEADING_ALL") if expanded else tr("BOOTH_HEADING")
	var heading_w: float = MenuTheme.FONT.get_string_size(_heading.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, MenuTheme.BODY).x + 14.0 \
		if not shown.is_empty() else 0.0
	_heading.visible = not shown.is_empty()
	var tile_w: float = tile_width(shown.size(), _region.size.x, heading_w)
	var ring: float = minf(RING, tile_w - 8.0)
	var caption: int = MenuTheme.BODY if tile_w >= 68.0 else MenuTheme.PIXEL_SIZES[0]
	for tile: Dictionary in shown:
		_tiles.add_child(_tile(tile, tile_w, ring, caption))
	var tiles_w: float = 0.0 if shown.is_empty() else shown.size() * tile_w + (shown.size() - 1) * TILE_GAP
	var tiles_h: float = 0.0 if shown.is_empty() else ring + 4.0 + MenuTheme.FONT.get_height(caption)
	var note_parts: PackedStringArray = []
	for line: Dictionary in lines:
		note_parts.append(str(line["text"]))
	_notes.text = "   ".join(note_parts)
	_notes.visible = not note_parts.is_empty()
	# The first note's tone colours the line: the Plate's gold leads.
	_notes.add_theme_color_override("font_color", tone_colour(str(lines[0]["tone"])) if not lines.is_empty() else MenuTheme.BONE)
	# Measured as drawn (capitals, outline); clipped only past the column.
	_notes.clip_text = false
	var note_w: float = ceilf(_notes.get_minimum_size().x) if _notes.visible else 0.0
	_notes.clip_text = note_w > _region.size.x - 2.0 * PAD_X
	var note_h: float = MenuTheme.FONT.get_height(MenuTheme.BODY) if _notes.visible else 0.0
	var inner_w: float = minf(_region.size.x - 2.0 * PAD_X, maxf(heading_w + tiles_w, note_w))
	var width: float = inner_w + 2.0 * PAD_X
	var height: float = PAD_Y * 2.0 + tiles_h + (6.0 if tiles_h > 0.0 and note_h > 0.0 else 0.0) + note_h
	position = Vector2(roundf(_region.position.x + (_region.size.x - width) * 0.5), roundf(_region.position.y))
	size = Vector2(width, height)
	_backing.position = Vector2.ZERO
	_backing.size = size
	var row_x: float = roundf((width - heading_w - tiles_w) * 0.5)
	_heading.position = Vector2(row_x, PAD_Y)
	_heading.size = Vector2(heading_w, ring)
	_tiles.position = Vector2(row_x + heading_w, PAD_Y)
	_tiles.size = Vector2(tiles_w, tiles_h)
	_notes.position = Vector2(PAD_X, PAD_Y + tiles_h + (6.0 if tiles_h > 0.0 else 0.0))
	_notes.size = Vector2(inner_w, note_h)

func _tile(tile: Dictionary, width: float, ring_size: float, caption: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Tile"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", 4)
	box.set_meta("tile", tile.duplicate())
	# The pad's name for a screen reader and the harnesses; the icon says it.
	box.tooltip_text = str(tile["label"])
	var ring := PadRing.new()
	ring.name = "Ring"
	ring.custom_minimum_size = Vector2(ring_size, ring_size)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.icon = tile.get("icon") as Texture2D
	ring.left = float(tile["left"])
	ring.tone = str(tile["tone"])
	box.add_child(ring)
	var value := Label.new()
	value.name = "Value"
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.pixel_text(value, caption, tone_colour(str(tile["tone"])), 3)
	value.text = str(tile["value"])
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value)
	return box
