class_name SpectatorPanel
extends Control

## The booth panel a watcher sees down the left of the screen: the power
## pads and when they return, who wears the Custody Plate, and who is on a
## run. The clocks come from the server's booth facts (`spectator_facts`),
## which no fighter receives, and count down here between messages. Every
## word is Silkscreen in capitals on a dark backing, on a level baseline.
## Presentation only.

## Facts older than this are a booth that stopped talking: a joined fighter,
## a campaign map or a dropped connection. The panel hides.
const STALE_MS: int = 2500
const TICKS_PER_SECOND: float = 20.0
const ROW_HEIGHT: float = 40.0
const ICON_SIZE: Vector2 = Vector2(64, 24)
const VALUE_WIDTH: float = 132.0
## A clock this close to zero is a fight about to start over the pad.
const SOON_SECONDS: float = 5.0
## Runs shorter than this stay off the panel; the feed already shows a double.
const MIN_RUN: int = 3
const MAX_RUNS: int = 2
## Pads worth a row, in the order a caster reads them. The Plate leads.
const POWER_ORDER: Array[String] = ["Rail", "Rocket", "Sniper", "Arc", "Scatter", "Repeater", "Article Blade"]
const NAMES: Dictionary = {
	"Rail": "BOOTH_PAD_RAIL", "Rocket": "BOOTH_PAD_ROCKET", "Sniper": "BOOTH_PAD_SNIPER",
	"Arc": "BOOTH_PAD_ARC", "Scatter": "BOOTH_PAD_SCATTER", "Repeater": "BOOTH_PAD_REPEATER",
	"Article Blade": "BOOTH_PAD_ARTICLE_BLADE", "armor": "BOOTH_PAD_ARMOR", "plate": "BOOTH_PAD_PLATE",
}

## True while this client watches rather than fights.
var watching: bool = false
var _covered: bool = false
var _facts: Dictionary = {}
var _facts_ms: int = -STALE_MS
var _pickups: Array = []
var _names: Dictionary = {}
var _list: VBoxContainer
var _shown: Array = []
var _region: Rect2 = Rect2()
## A clock reading for the harnesses: milliseconds since the facts arrived.
var clock_override_ms: int = -1
## The clocks change once a second; the rows are read ten times a second.
const REFRESH_SECONDS: float = 0.1
var _refresh_in: float = 0.0

func _ready() -> void:
	name = "SpectatorPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)

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

func set_region(rect: Rect2) -> void:
	_region = rect

func set_covered(value: bool) -> void:
	if value != _covered:
		_refresh_in = 0.0
	_covered = value

func _elapsed_ms() -> int:
	return clock_override_ms if clock_override_ms >= 0 else Time.get_ticks_msec() - _facts_ms

## Seconds left on a clock the facts gave in ticks, counted down since.
func seconds_left(back_in_ticks: int) -> float:
	return maxf(0.0, float(back_in_ticks) / TICKS_PER_SECOND - float(_elapsed_ms()) / 1000.0)

static func clock_text(seconds: float) -> String:
	var whole: int = ceili(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]

## The rows to show, as plain data: `{key, icon, label, value, tone}` where
## tone is `up`, `wait`, `soon`, `held` or `run`. Empty while the booth is
## quiet or stale.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _facts.is_empty() or _elapsed_ms() > STALE_MS:
		return out
	var clocks: Dictionary = {}
	for pad: Dictionary in _facts.get("pads", []):
		clocks[pad["id"]] = int(pad["back_in"])
	var plate: Dictionary = _facts.get("plate", {})
	if not plate.is_empty():
		var row: Dictionary = {"key": "plate", "icon": WeaponArt.SUPPLY.get("plate"), "label": tr(NAMES["plate"])}
		if not str(plate.get("holder", "")).is_empty():
			# Worn: the wearer's callsign and what the Plate has left on them.
			row["label"] = str(_names.get(plate["holder"], "?")).to_upper()
			row["value"] = str(plate.get("armor", 0))
			row["tone"] = "held"
		elif bool(plate.get("up")):
			row["value"] = tr("BOOTH_UP")
			row["tone"] = "up"
		else:
			var left: float = seconds_left(int(plate.get("back_in", 0)))
			row["value"] = clock_text(left)
			row["tone"] = "soon" if left <= SOON_SECONDS else "wait"
		out.append(row)
	for key: String in POWER_ORDER + ["armor"]:
		var row: Dictionary = _pad_row(key, clocks)
		if not row.is_empty():
			out.append(row)
	# Runs: a small heading, then each callsign and its frags without dying.
	# The tier word names the longest one; the Host already calls the rest.
	var step: int = maxi(1, int(_facts.get("spree_step", 5)))
	var runs: Array[Dictionary] = []
	var chains: Array = _facts.get("chains", [])
	var chain_id: String = str(chains[0]["id"]) if not chains.is_empty() else ""
	var chain_word: String = tr("BOOTH_CHAIN_" + str(clampi(int(chains[0]["frags"]), 2, 5))) if not chains.is_empty() else ""
	for spree: Dictionary in _facts.get("sprees", []):
		if int(spree["frags"]) >= MIN_RUN and runs.size() < MAX_RUNS:
			var row: Dictionary = {"key": "run:" + str(spree["id"]), "icon": null, "label": str(_names.get(spree["id"], "?")).to_upper(),
				"value": str(int(spree["frags"])), "tone": "run"}
			# A run with an open chain says both on one row.
			if str(spree["id"]) == chain_id:
				row["value"] = chain_word + " " + row["value"]
				chain_id = ""
			runs.append(row)
	var chain_row: Dictionary = {}
	if not chain_id.is_empty():
		chain_row = {"key": "chain:" + chain_id, "icon": null, "label": str(_names.get(chain_id, "?")).to_upper(),
			"value": chain_word, "tone": "soon"}
	if not runs.is_empty() or not chain_row.is_empty():
		var top: int = int(_facts["sprees"][0]["frags"]) if not (_facts.get("sprees", []) as Array).is_empty() else 0
		out.append({"key": "heading", "icon": null, "label": run_heading(top, step), "value": "", "tone": "heading"})
		out.append_array(runs)
		if not chain_row.is_empty():
			out.append(chain_row)
	return out

## One row per kind of power pad: up when any copy is, else the soonest.
func _pad_row(key: String, clocks: Dictionary) -> Dictionary:
	var any: bool = false
	var up: bool = false
	var soonest: int = -1
	for pad: Variant in _pickups:
		if not pad is Dictionary:
			continue
		var kind: String = str(pad.get("kind", "weapon"))
		var matches: bool = (key == "armor" and kind == "armor") or (kind == "weapon" and str(pad.get("weapon", "")) == key)
		if not matches:
			continue
		any = true
		if pad.get("available") == true:
			up = true
		elif clocks.has(pad.get("id")):
			var ticks: int = int(clocks[pad["id"]])
			soonest = ticks if soonest < 0 else mini(soonest, ticks)
	if not any:
		return {}
	var icon: Texture2D = WeaponArt.SUPPLY.get("armor") if key == "armor" else WeaponArt.PROFILE.get(key)
	var row: Dictionary = {"key": key, "icon": icon, "label": tr(str(NAMES.get(key, key)))}
	if up:
		row["value"] = tr("BOOTH_UP")
		row["tone"] = "up"
	elif soonest >= 0:
		var left: float = seconds_left(soonest)
		row["value"] = clock_text(left)
		row["tone"] = "soon" if left <= SOON_SECONDS else "wait"
	else:
		row["value"] = "--"
		row["tone"] = "wait"
	return row

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

func _process(delta: float) -> void:
	_refresh_in -= delta
	if _refresh_in > 0.0:
		return
	_refresh_in = REFRESH_SECONDS
	var shown: Array[Dictionary] = []
	if watching:
		shown = rows()
	visible = not _covered and not shown.is_empty() and _region.has_area()
	if not visible:
		return
	var key: Array = []
	for row: Dictionary in shown:
		key.append([row["key"], row["label"], row["value"], row["tone"]])
	if key != _shown:
		_shown = key
		_rebuild(shown)
	position = _region.position
	size = Vector2(_region.size.x, 0)
	_list.position = Vector2.ZERO
	_list.size = Vector2(_region.size.x, 0)

func _rebuild(shown: Array[Dictionary]) -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var room: int = maxi(1, int(_region.size.y / (ROW_HEIGHT + 4.0)))
	for index: int in range(mini(shown.size(), room)):
		_list.add_child(_row(shown[index]))

func _row(row: Dictionary) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.name = "Row"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_meta("row", row.duplicate())
	plate.add_theme_stylebox_override("panel", MenuTheme.backing())
	if row["tone"] == "heading":
		var heading := Label.new()
		heading.name = "Label"
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		MenuTheme.pixel_text(heading, MenuTheme.BODY, MenuTheme.MUTED, 0)
		heading.text = str(row["label"])
		plate.add_child(heading)
		return plate
	plate.custom_minimum_size.y = ROW_HEIGHT
	var content := HBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	plate.add_child(content)
	if row.get("icon") is Texture2D:
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = ICON_SIZE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.texture = row["icon"]
		content.add_child(icon)
	else:
		# A callsign row has no icon: the name takes the room, indented a
		# little under the heading.
		var indent := Control.new()
		indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		indent.custom_minimum_size = Vector2(8, 0)
		content.add_child(indent)
	var label := Label.new()
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.pixel_text(label, MenuTheme.BODY, MenuTheme.BONE, 0)
	# A callsign too long for its room is shortened the killfeed's way
	# ("S. SIGHTING"), never cut mid-letter.
	var has_icon: bool = row.get("icon") is Texture2D
	var value_w: float = maxf(VALUE_WIDTH if has_icon else 0.0,
		MenuTheme.FONT.get_string_size(str(row["value"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, MenuTheme.BODY).x)
	var room: float = _region.size.x - 20.0 - (ICON_SIZE.x if has_icon else 8.0) - 20.0 - value_w
	label.text = FragFeed.abbreviate(str(row["label"]), MenuTheme.FONT, MenuTheme.BODY, maxf(24.0, room))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(label)
	var value := Label.new()
	value.name = "Value"
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.pixel_text(value, MenuTheme.BODY, tone_colour(str(row["tone"])), 0)
	value.text = str(row["value"])
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.custom_minimum_size.x = VALUE_WIDTH if row.get("icon") is Texture2D else 0.0
	content.add_child(value)
	return plate
