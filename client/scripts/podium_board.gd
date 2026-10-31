class_name PodiumBoard
extends PanelContainer

## The podium between rounds when the server sends a story or a map vote:
## your nemesis and your book against the room this session, the personal
## bests this round set in your service record, the three-map vote counting
## down, and the ready-up. A spectator reads the room's loudest books and the
## vote. Every line sits level; nothing here rotates or tilts.

const TITLE_SIZE: int = 32
const BOT_TAG: String = " [BOT]"
const AGENT_TAG: String = " [AGENT]"
const MAX_ROOM_LINES: int = 2
const VOTE_KEYS: Array[String] = ["weapon_1", "weapon_2", "weapon_3"]
const NEMESIS_LINES: Array[String] = ["PODIUM_NEMESIS_A", "PODIUM_NEMESIS_B", "PODIUM_NEMESIS_C", "PODIUM_NEMESIS_D"]

var _label: RichTextLabel
var _shown: String = ""
var _revision: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_theme_stylebox_override("panel", MenuTheme.panel(MenuTheme.INK, MenuTheme.BONE))
	_label = RichTextLabel.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_label.add_theme_font_override("normal_font", MenuTheme.FONT)
	_label.add_theme_font_size_override("normal_font_size", MenuTheme.BODY)
	_label.add_theme_color_override("default_color", MenuTheme.BONE)
	_label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)


## Whether a podium block carries anything this board shows.
static func wants(podium: Variant) -> bool:
	if not podium is Dictionary:
		return false
	var data: Dictionary = podium
	return (data.get("story") is Array and not (data["story"] as Array).is_empty()) or data.get("vote") is Dictionary


## Show the lines, or hide when there are none. Re-renders only on change.
func present(lines: Array[Dictionary]) -> void:
	if _label == null:
		_ready()
	var key: String = JSON.stringify(lines)
	if lines.is_empty():
		visible = false
		_shown = ""
		return
	if key == _shown and _revision == InputDevice.revision and visible:
		_place()
		return
	_shown = key
	_revision = InputDevice.revision
	_label.clear()
	for index: int in lines.size():
		var line: Dictionary = lines[index]
		if index > 0:
			_label.newline()
		_label.push_font_size(int(line.get("size", MenuTheme.BODY)))
		_label.push_color(line.get("color", MenuTheme.BONE))
		InputGlyphs.append(_label, str(line.get("text", "")), 32)
		_label.pop()
		_label.pop()
	visible = true
	_place()


## Under the screen's centre, where the ready-up plate sits, as wide as the
## longest line and never wider than most of the screen.
func _place() -> void:
	var viewport_node: Viewport = get_viewport()
	if viewport_node == null:
		return
	var viewport: Vector2 = viewport_node.get_visible_rect().size
	if viewport.x < 1.0:
		return
	_label.custom_minimum_size = Vector2.ZERO
	var inner: float = minf(maxf(_label.get_content_width(), 420.0), viewport.x * 0.8)
	_label.custom_minimum_size = Vector2(inner, 0.0)
	reset_size()
	var plate: Vector2 = get_combined_minimum_size()
	size = plate
	position = Vector2(roundf((viewport.x - plate.x) * 0.5), roundf(viewport.y * 0.5 + 24.0))


static func tag(kind: Variant) -> String:
	if kind == "bot":
		return BOT_TAG
	if kind == "agent":
		return AGENT_TAG
	return ""


static func _count(value: Variant) -> int:
	return maxi(0, int(value)) if (value is int or value is float) and is_finite(float(value)) else 0


static func _line(text: String, color: Color = MenuTheme.BONE, size: int = MenuTheme.BODY) -> Dictionary:
	return {"text": text, "color": color, "size": size}


## A stable pick among the nemesis lines, so one podium does not flicker.
static func nemesis_key(name: String, lost: int) -> String:
	return NEMESIS_LINES[absi(hash(name.to_upper()) + lost) % NEMESIS_LINES.size()]


## Every line the board shows, top to bottom. `podium` is the snapshot's
## block, `my_id` empty for a spectator, `bests` from
## `PlayerRecords.arena_bests`, `extra` the Duel line's own words.
static func lines(podium: Dictionary, my_id: String, bests: Array[Dictionary], pad: bool, extra: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stories: Array[Dictionary] = []
	if podium.get("story") is Array:
		for entry: Variant in podium["story"]:
			if entry is Dictionary and entry.get("id") is String and entry.get("name") is String:
				stories.append(entry)
	var mine: Dictionary = {}
	for story: Dictionary in stories:
		if story["id"] == my_id and not my_id.is_empty():
			mine = story
	var duel: Variant = podium.get("duel")
	if duel is Array and (duel as Array).size() == 2 and duel[0] is Dictionary and duel[1] is Dictionary:
		out.append(_line(TranslationServer.translate("HUD_DUEL_SERIES").format({
			"a": str(duel[0].get("name", "?")).to_upper(), "a_wins": _count(duel[0].get("wins")),
			"b": str(duel[1].get("name", "?")).to_upper(), "b_wins": _count(duel[1].get("wins")),
		}), MenuTheme.BONE, TITLE_SIZE))
	# Your own book when you have met somebody; otherwise the room's.
	var own: Array[Dictionary] = _own_lines(mine) if not my_id.is_empty() else ([] as Array[Dictionary])
	out.append_array(own if not own.is_empty() else _room_lines(stories))
	var best_parts: Array[String] = []
	for best: Dictionary in bests:
		if best_parts.size() >= 2:
			break
		best_parts.append(TranslationServer.translate("PODIUM_BEST").format({
			"value": _count(best.get("value")), "stat": TranslationServer.translate("PODIUM_STAT_" + str(best.get("stat", "")).to_upper()),
			"was": _count(best.get("was")),
		}))
	if not best_parts.is_empty():
		out.append(_line(TranslationServer.translate("PODIUM_BEST_HEAD") + "  " + "   ".join(best_parts), MenuTheme.SUCCESS))
	var seated: bool = not my_id.is_empty() and _count(podium.get("voters")) > 0
	if podium.get("vote") is Dictionary:
		# A breath between the story and the choice.
		if not out.is_empty():
			out.append(_line("", MenuTheme.BONE, MenuTheme.BODY / 2))
		out.append_array(_vote_lines(podium["vote"], my_id if seated else "", pad))
	for line: String in extra:
		out.append(_line(line))
	if seated:
		var ready: Array = podium["again"] if podium.get("again") is Array else []
		var voters: int = _count(podium.get("voters"))
		if ready.has(my_id):
			var waiting: int = maxi(voters - ready.size(), 0)
			out.append(_line(TranslationServer.translate("HUD_AGAIN_READY").format({"waiting": waiting}) if waiting > 0 else TranslationServer.translate("HUD_AGAIN_GO")))
		else:
			out.append(_line(TranslationServer.translate("HUD_AGAIN_PROMPT").format({"ready": ready.size(), "voters": voters})))
	return out


## Your nemesis first, then up to two more rivals in plain words.
static func _own_lines(mine: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if mine.is_empty():
		return out
	var rivals: Array[Dictionary] = []
	if mine.get("rivals") is Array:
		for rival: Variant in mine["rivals"]:
			if rival is Dictionary and rival.get("name") is String:
				rivals.append(rival)
	var nemesis: String = str(mine["nemesis"]) if mine.get("nemesis") is String else ""
	var book: Array[String] = []
	for rival: Dictionary in rivals:
		var name: String = str(rival["name"]).to_upper()
		var won: int = _count(rival.get("won"))
		var lost: int = _count(rival.get("lost"))
		if not nemesis.is_empty() and str(rival["name"]) == nemesis:
			out.push_front(_line(TranslationServer.translate(nemesis_key(name, lost)).format({"name": name}), MenuTheme.MUTED))
			out.push_front(_line(TranslationServer.translate("PODIUM_NEMESIS").format({
				"name": name, "tag": tag(rival.get("kind")), "lost": lost, "won": won}), MenuTheme.EMBER, TITLE_SIZE))
			continue
		var key: String = "PODIUM_UP" if won > lost else "PODIUM_DOWN" if lost > won else "PODIUM_LEVEL"
		book.append(TranslationServer.translate(key).format({"name": name, "tag": tag(rival.get("kind")), "won": won, "lost": lost}))
		if book.size() >= 2:
			break
	if nemesis.is_empty() and not rivals.is_empty():
		out.push_front(_line(TranslationServer.translate("PODIUM_NO_NEMESIS"), MenuTheme.EMBER, TITLE_SIZE))
	if not book.is_empty():
		out.append(_line(TranslationServer.translate("PODIUM_BOOK") + "  " + "   ".join(book)))
	return out


## For a watcher: the room's most lopsided books, widest margin first.
static func _room_lines(stories: Array[Dictionary]) -> Array[Dictionary]:
	var books: Array[Dictionary] = []
	for story: Dictionary in stories:
		if not story.get("nemesis") is String or not story.get("rivals") is Array:
			continue
		for rival: Variant in story["rivals"]:
			if rival is Dictionary and rival.get("name") == story["nemesis"]:
				books.append({"a": str(rival["name"]).to_upper(), "a_tag": tag(rival.get("kind")),
					"b": str(story["name"]).to_upper(), "b_tag": tag(story.get("kind")),
					"won": _count(rival.get("lost")), "lost": _count(rival.get("won"))})
	books.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var margin_x: int = int(x["won"]) - int(x["lost"])
		var margin_y: int = int(y["won"]) - int(y["lost"])
		return margin_x > margin_y if margin_x != margin_y else str(x["b"]) < str(y["b"]))
	var out: Array[Dictionary] = []
	for book: Dictionary in books.slice(0, MAX_ROOM_LINES):
		out.append(_line(TranslationServer.translate("PODIUM_ROOM_OWNS").format(book), MenuTheme.EMBER, TITLE_SIZE if out.is_empty() else MenuTheme.BODY))
	return out


## The vote: a heading with its countdown, then one row per map. The
## leader is lit; your own ballot is marked.
static func _vote_lines(vote: Dictionary, my_id: String, pad: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not vote.get("options") is Array:
		return out
	var mine: int = my_ballot(vote, my_id)
	var leader: int = _count(vote.get("leader"))
	var seconds: int = ceili(_count(vote.get("closes_in")) / 20.0)
	var head: String = TranslationServer.translate("PODIUM_VOTE_HEAD").format({"seconds": seconds})
	if vote.get("bots_vote") == true:
		head += "  //  " + TranslationServer.translate("PODIUM_VOTE_BOTS")
	elif not my_id.is_empty():
		head += "  //  " + TranslationServer.translate("PODIUM_VOTE_PAD" if pad else "PODIUM_VOTE_KEYS")
	out.append(_line(head, MenuTheme.MUTED))
	var index: int = 0
	for option: Variant in vote["options"]:
		if not option is Dictionary or index >= VOTE_KEYS.size():
			continue
		var map_id: int = _count(option.get("map_id"))
		var votes: int = _count(option.get("votes"))
		var key: String = "{" + VOTE_KEYS[index] + "} " if not my_id.is_empty() and not pad else ""
		var row: String = key + str(option.get("map_name", "?")).to_upper() + "  " + TranslationServer.translate("PODIUM_VOTE_ONE" if votes == 1 else "PODIUM_VOTES").format({"votes": votes})
		if map_id == mine:
			row += "  " + TranslationServer.translate("PODIUM_YOUR_VOTE")
		out.append(_line(row, MenuTheme.EMBER if map_id == leader else MenuTheme.BONE))
		index += 1
	return out


## The map this fighter voted for, or 0.
static func my_ballot(vote: Dictionary, my_id: String) -> int:
	if my_id.is_empty() or not vote.get("ballots") is Array:
		return 0
	for ballot: Variant in vote["ballots"]:
		if ballot is Dictionary and ballot.get("id") == my_id:
			return _count(ballot.get("map_id"))
	return 0


## The map a vote key asks for: `slot` 0 to 2 picks an option, and -1 or +1
## steps from this fighter's ballot (or the leader) for a pad. 0 is no vote.
static func choice(vote: Variant, my_id: String, slot: int, step: int = 0) -> int:
	if not vote is Dictionary or not (vote as Dictionary).get("options") is Array:
		return 0
	var ids: Array[int] = []
	for option: Variant in vote["options"]:
		if option is Dictionary and _count(option.get("map_id")) > 0:
			ids.append(_count(option["map_id"]))
	if ids.is_empty():
		return 0
	if step == 0:
		return ids[slot] if slot >= 0 and slot < ids.size() else 0
	var current: int = my_ballot(vote, my_id)
	var at: int = ids.find(current)
	if at < 0:
		at = ids.find(_count(vote.get("leader")))
		if at < 0:
			at = 0
	return ids[posmod(at + step, ids.size())]
