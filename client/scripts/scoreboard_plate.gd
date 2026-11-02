class_name ScoreboardPlate
extends Panel

## The board held on Tab (pad: View). Free-for-all ranks every fighter on
## frags. A team mode splits the sides into two blocks, the viewer's own side
## first (the Union first for a watcher), each under a header bar in its
## faction's look with the side's total and round wins, Counter-Strike's
## board in localexception's colours. Objective modes add their own columns: Sabotage
## plants and defuses, flag captures and returns, Conquest captures. The
## round's best fighter carries an MVP mark, and the viewer's head-to-head
## book this session marks a nemesis and the fighters they lead or trail.
## Facts come from the snapshot and the podium story through the HUD.
## Presentation only; every word sits level.

const WIDTH_CAP: float = 1040.0
## Objective columns need more room for the callsign beside them.
const WIDTH_CAP_OBJECTIVE: float = 1200.0
const RANK_W: float = 56.0
const FRAGS_W: float = 112.0
const DEATHS_W: float = 120.0
const PING_W: float = 88.0
const OBJECTIVE_W: float = 140.0
const ROW_GAP: int = 4
const HEADER_SIZE: int = 32
## A ping reading the server has not taken yet (a rule bot, a fighter whose
## connection has not answered) reads as a dash, never as a number.
const NO_PING: String = "--"
## Objective columns per mode, in reading order: `{key, heading}`. `key` is
## the standings row field the server's `objective` tally fills.
const OBJECTIVE_COLUMNS: Dictionary = {
	"sabotage": [{"key": "plants", "heading": "HUD_BOARD_PLANTS"}, {"key": "defuses", "heading": "HUD_BOARD_DEFUSES"}],
	"ctf": [{"key": "captures", "heading": "HUD_BOARD_CAPTURES"}, {"key": "returns", "heading": "HUD_BOARD_RETURNS"}],
	"conquest": [{"key": "captures", "heading": "HUD_BOARD_CAPTURES"}],
}

var scroll: ScrollContainer
var rows: VBoxContainer
var hint: RichTextLabel
var _key: Array = []
var _hint_key: Array = []

func _init() -> void:
	name = "Leaderboard"
	visible = false
	# Held on purpose, so it draws over every prompt and card under it.
	z_index = 2
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", MenuTheme.panel())
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", ROW_GAP)
	scroll.add_child(rows)
	hint = RichTextLabel.new()
	hint.name = "ScrollHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.fit_content = true
	hint.scroll_active = false
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hint.add_theme_font_override("normal_font", MenuTheme.FONT)
	hint.add_theme_font_size_override("normal_font_size", MenuTheme.BODY)
	hint.add_theme_color_override("default_color", MenuTheme.MUTED)
	add_child(hint)

## The ping cell for a standings row.
static func ping_text(row: Dictionary) -> String:
	var ping: int = int(row.get("ping", -1))
	return str(ping) if ping >= 0 else NO_PING

## The objective columns for a mode, possibly none.
static func objective_columns(mode: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for column: Variant in OBJECTIVE_COLUMNS.get(mode, []):
		out.append(column)
	return out

## The rows split for the board: one `{side, rows}` group per side in a team
## mode, the viewer's side first (the Union first for a watcher), then any
## fighter without a side; one group with side "" otherwise. Rows keep the
## standings order (frags first) inside each group.
static func groups(standings: Array, teams: bool, viewer_team: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not teams:
		out.append({"side": "", "rows": standings.duplicate()})
		return out
	var order: Array[String] = ["union", "coalition"]
	if viewer_team == "coalition":
		order = ["coalition", "union"]
	var sideless: Array = []
	for side: String in order:
		out.append({"side": side, "rows": []})
	for row: Variant in standings:
		var team: String = MatchRules.valid_team((row as Dictionary).get("team"))
		if team.is_empty():
			sideless.append(row)
		else:
			out[order.find(team)]["rows"].append(row)
	if not sideless.is_empty():
		out.append({"side": "", "rows": sideless})
	return out

## The round's best fighter, as the server named it once the round ended.
## A live round has none: the leader's ember rank already says who leads.
static func mvp_name(_standings: Array, ended_mvp: String) -> String:
	return ended_mvp

## The viewer's head-to-head book from the podium story, keyed by the
## callsign in capitals: `{won, lost, nemesis}`. Empty for a watcher or
## before the viewer has met anybody this session.
static func rivals_from_story(story: Variant, my_id: String) -> Dictionary:
	var out: Dictionary = {}
	if my_id.is_empty() or not story is Array:
		return out
	for entry: Variant in story:
		if not entry is Dictionary or entry.get("id") != my_id:
			continue
		var nemesis: String = str(entry["nemesis"]).to_upper() if entry.get("nemesis") is String else ""
		if not entry.get("rivals") is Array:
			continue
		for rival: Variant in entry["rivals"]:
			if not rival is Dictionary or not rival.get("name") is String:
				continue
			var name: String = str(rival["name"]).to_upper()
			out[name] = {"won": PodiumBoard._count(rival.get("won")), "lost": PodiumBoard._count(rival.get("lost")),
				"nemesis": name == nemesis}
		# The story lists only the three rivals met most; a nemesis met less
		# often is still marked, with the count from its own entry when that
		# names the viewer, and without one otherwise.
		if not nemesis.is_empty() and not out.has(nemesis):
			out[nemesis] = _nemesis_from_their_side(story, nemesis, str(entry.get("name", "")).to_upper())
	return out

static func _nemesis_from_their_side(story: Array, nemesis: String, me: String) -> Dictionary:
	for entry: Variant in story:
		if not entry is Dictionary or str(entry.get("name", "")).to_upper() != nemesis or not entry.get("rivals") is Array:
			continue
		for rival: Variant in entry["rivals"]:
			if rival is Dictionary and str(rival.get("name", "")).to_upper() == me:
				return {"won": PodiumBoard._count(rival.get("lost")), "lost": PodiumBoard._count(rival.get("won")), "nemesis": true}
	return {"won": -1, "lost": -1, "nemesis": true}

## The marks after a callsign: `{text, colour}` for the MVP and the viewer's
## book against this fighter. Never on the viewer's own row's book.
static func marks(row: Dictionary, mvp: String, rivals: Dictionary, own: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var name: String = str(row.get("name", ""))
	if not mvp.is_empty() and name == mvp:
		out.append({"text": tr_text("HUD_BOARD_MVP"), "colour": MatchRules.GOLD, "key": "mvp"})
	var book: Variant = rivals.get(name.to_upper()) if not own else null
	if book is Dictionary:
		var won: int = int(book["won"])
		var lost: int = int(book["lost"])
		var key: String = ("HUD_BOARD_NEMESIS" if won >= 0 else "HUD_BOARD_NEMESIS_PLAIN") if bool(book["nemesis"]) else ("HUD_BOARD_UP" if won > lost else ("HUD_BOARD_DOWN" if lost > won else "HUD_BOARD_LEVEL"))
		var colour: Color = MenuTheme.EMBER if bool(book["nemesis"]) else (MenuTheme.SUCCESS if won > lost else MenuTheme.MUTED)
		out.append({"text": tr_text(key).format({"won": won, "lost": lost}), "colour": colour,
			"key": "nemesis" if bool(book["nemesis"]) else ("up" if won > lost else ("down" if lost > won else "level"))})
	return out

## One row as text, for the accessible reading and the harnesses: rank, side,
## callsign and chip, then frags, deaths and ping, the mode's objective
## counts, any marks, and YOU on the viewer's.
static func row_text(row: Dictionary, index: int, own: bool, context: Dictionary = {}) -> String:
	var side: String = MatchRules.team_short(MatchRules.valid_team(row.get("team")))
	var tag: String = "[" + side + "] " if not side.is_empty() else ""
	var text: String = str(index + 1) + ". " + tag + str(row.get("name", "?")) + str(row.get("chip", ""))
	text += "  " + str(int(row.get("kills", 0))) + "  " + str(int(row.get("deaths", 0))) + "  " + ping_text(row)
	for column: Dictionary in objective_columns(str(context.get("mode", ""))):
		text += "  " + tr_text(str(column["heading"])) + " " + str(int(row.get(column["key"], 0)))
	for mark: Dictionary in marks(row, str(context.get("mvp", "")), context.get("rivals", {}), own):
		text += "  " + str(mark["text"])
	return text + ("  YOU" if own else "")

## A side's header as text: name, total and its unit, and round wins.
static func side_text(side: String, facts: Dictionary) -> String:
	var text: String = MatchRules.team_name(side).to_upper()
	if facts.has("total"):
		text += "  " + str(int(facts["total"])) + " " + tr_text(str(facts.get("unit", "HUD_BOARD_UNIT_FRAGS")))
	if int(facts.get("rounds", 0)) > 0 or facts.get("unit") == "HUD_BOARD_UNIT_ROUNDS":
		if facts.get("unit") != "HUD_BOARD_UNIT_ROUNDS":
			text += "  " + tr_text("HUD_BOARD_ROUNDS").format({"rounds": int(facts.get("rounds", 0))})
	return text

## The whole board as text, title and columns first. `context` is the HUD's
## `{line, mode, teams, viewer_team, sides, mvp, rivals}`.
static func board_text(standings: Array, board_line: String, own: Callable, context: Dictionary = {}) -> String:
	var body: String = tr_text("HUD_LEADERS") + "\n"
	var teams: bool = bool(context.get("teams", false))
	if not board_line.is_empty() and not teams:
		body += board_line + "\n"
	body += columns_text(str(context.get("mode", ""))) + "\n"
	var mvp: String = mvp_name(standings, str(context.get("mvp", "")))
	var row_context: Dictionary = context.duplicate()
	row_context["mvp"] = mvp
	for group: Dictionary in groups(standings, teams, str(context.get("own_team", ""))):
		if not str(group["side"]).is_empty():
			body += side_text(group["side"], (context.get("sides", {}) as Dictionary).get(group["side"], {})) + "\n"
		var group_rows: Array = group["rows"]
		for index: int in range(group_rows.size()):
			body += row_text(group_rows[index], index, bool(own.call(group_rows[index])), row_context) + "\n"
	if standings.is_empty():
		body += tr_text("HUD_BOARD_EMPTY")
	return body.strip_edges()

static func columns_text(mode: String = "") -> String:
	var parts: PackedStringArray = [tr_text("HUD_BOARD_RANK"), tr_text("HUD_BOARD_CALLSIGN"),
		tr_text("HUD_BOARD_FRAGS"), tr_text("HUD_BOARD_DEATHS"), tr_text("HUD_BOARD_PING")]
	for column: Dictionary in objective_columns(mode):
		parts.append(tr_text(str(column["heading"])))
	return "  ".join(parts)

static func tr_text(key: String) -> String:
	return TranslationServer.translate(key)

## Rebuild the rows when the standings, the viewer, the context or the locale
## changed. Returns true when it rebuilt them.
func refresh(standings: Array[Dictionary], revision: int, own: Callable, context: Dictionary, owner_key: Array) -> bool:
	var key: Array = [revision, context, TranslationServer.get_locale()] + owner_key
	if key == _key:
		return false
	_key = key
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var mode: String = str(context.get("mode", ""))
	var teams: bool = bool(context.get("teams", false))
	var viewer_team: String = str(context.get("viewer_team", ""))
	var own_team: String = str(context.get("own_team", ""))
	var row_context: Dictionary = context.duplicate()
	row_context["mvp"] = mvp_name(standings, str(context.get("mvp", "")))
	rows.add_child(_heading(str(context.get("line", "")) if not teams else "", mode))
	for group: Dictionary in groups(standings, teams, own_team):
		var side: String = group["side"]
		if teams and not side.is_empty():
			rows.add_child(_side_bar(side, (context.get("sides", {}) as Dictionary).get(side, {}), side == own_team))
		var group_rows: Array = group["rows"]
		for index: int in range(group_rows.size()):
			var row: Dictionary = group_rows[index]
			rows.add_child(_row(row, index, bool(own.call(row)), viewer_team, row_context))
	return true

func _heading(board_line: String, mode: String) -> VBoxContainer:
	var heading := VBoxContainer.new()
	heading.name = "Heading"
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.name = "Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.pixel_text(title, MenuTheme.PIXEL_SIZES[2], MenuTheme.BONE, 0)
	title.text = tr_text("HUD_LEADERS")
	heading.add_child(title)
	if not board_line.is_empty():
		var line := Label.new()
		line.name = "BoardLine"
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		MenuTheme.pixel_text(line, MenuTheme.BODY, MenuTheme.EMBER, 0)
		line.text = board_line
		heading.add_child(line)
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override("separation", 8)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	margin.add_child(columns)
	var objective: PackedStringArray = []
	for column: Dictionary in objective_columns(mode):
		objective.append(tr_text(str(column["heading"])))
	_cells(columns, tr_text("HUD_BOARD_RANK"), tr_text("HUD_BOARD_CALLSIGN"), [] as Array[Dictionary], objective,
		tr_text("HUD_BOARD_FRAGS"), tr_text("HUD_BOARD_DEATHS"), tr_text("HUD_BOARD_PING"), MenuTheme.MUTED, null)
	heading.add_child(margin)
	return heading

## A side's header bar: Union black with its red edge, the free coalition
## in its own colour; the side's name, round wins and total on one level line.
func _side_bar(side: String, facts: Dictionary, ours: bool) -> PanelContainer:
	var bar := PanelContainer.new()
	bar.name = "Side_" + side
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_meta("side", side)
	bar.set_meta("text", side_text(side, facts))
	var colour: Color = MatchRules.team_label_color(side)
	var style := StyleBoxFlat.new()
	style.bg_color = MatchRules.UNION_PLATE_DARK.darkened(0.55) if side == "union" else MenuTheme.INK
	style.border_color = colour
	style.border_width_left = 8
	style.border_width_bottom = 2
	style.content_margin_left = 14
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.anti_aliasing = false
	bar.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.name = "Content"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 14)
	bar.add_child(line)
	var name_label: Label = _cell("Side", MatchRules.team_name(side), 0.0, colour, HORIZONTAL_ALIGNMENT_LEFT, HEADER_SIZE)
	line.add_child(name_label)
	if ours:
		line.add_child(_cell("Ours", MatchRules.relation_mark("mate"), 0.0, MenuTheme.MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(spacer)
	var unit: String = str(facts.get("unit", "HUD_BOARD_UNIT_FRAGS"))
	if unit != "HUD_BOARD_UNIT_ROUNDS" and int(facts.get("rounds", 0)) > 0:
		line.add_child(_cell("Rounds", tr_text("HUD_BOARD_ROUNDS").format({"rounds": int(facts["rounds"])}), 0.0, MenuTheme.BONE, HORIZONTAL_ALIGNMENT_RIGHT))
	if facts.has("total"):
		line.add_child(_cell("Unit", tr_text(unit), 0.0, MenuTheme.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
		line.add_child(_cell("Total", str(int(facts["total"])), 0.0, MenuTheme.BONE, HORIZONTAL_ALIGNMENT_RIGHT, HEADER_SIZE))
	return bar

func _row(row: Dictionary, index: int, own: bool, viewer_team: String, context: Dictionary) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_meta("facts", row.duplicate(true))
	var team: String = MatchRules.valid_team(row.get("team"))
	var style := StyleBoxFlat.new()
	style.bg_color = MenuTheme.BONE if own else (MenuTheme.INK if index % 2 == 0 else MenuTheme.INSET)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.anti_aliasing = false
	plate.add_theme_stylebox_override("panel", style)
	var content := HBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	plate.add_child(content)
	var relation: String = HudRelation.token(team, viewer_team)
	plate.set_meta("relation", relation)
	var colour: Color = MenuTheme.INK if own else MenuTheme.BONE
	var name_text: String = str(row.get("name", "?")) + str(row.get("chip", "")) + ("  YOU" if own else "")
	var row_marks: Array[Dictionary] = marks(row, str(context.get("mvp", "")), context.get("rivals", {}), own)
	plate.set_meta("marks", row_marks.map(func(mark: Dictionary) -> String: return str(mark["key"])))
	var objective: PackedStringArray = []
	for column: Dictionary in objective_columns(str(context.get("mode", ""))):
		objective.append(str(int(row.get(column["key"], 0))))
	_cells(content, str(index + 1), name_text, row_marks, objective, str(int(row.get("kills", 0))), str(int(row.get("deaths", 0))),
		ping_text(row), colour, HudRelation.mark(team, relation, own))
	# The group's leader has the one ember rank on the board.
	if index == 0 and int(row.get("kills", 0)) > 0 and not own:
		(content.get_node("Rank") as Label).add_theme_color_override("font_color", MenuTheme.EMBER)
	plate.set_meta("text", row_text(row, index, own, context))
	return plate

## The cells in order, numbers right aligned in fixed columns so every row's
## numbers line up under the heading.
func _cells(into: HBoxContainer, rank: String, callsign: String, row_marks: Array[Dictionary], objective: PackedStringArray,
		frags: String, deaths: String, ping: String, colour: Color, mark: Control) -> void:
	var rank_label: Label = _cell("Rank", rank, RANK_W, colour, HORIZONTAL_ALIGNMENT_LEFT)
	into.add_child(rank_label)
	if mark != null:
		into.add_child(mark)
	else:
		var spacer := Control.new()
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.custom_minimum_size = Vector2(6, 0)
		into.add_child(spacer)
	var callsign_label: Label = _cell("Text", callsign, 0.0, colour, HORIZONTAL_ALIGNMENT_LEFT)
	callsign_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	callsign_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	into.add_child(callsign_label)
	for index: int in range(row_marks.size()):
		var tag: Label = _cell("Mark%d" % index, str(row_marks[index]["text"]), 0.0, row_marks[index]["colour"], HORIZONTAL_ALIGNMENT_RIGHT)
		tag.add_theme_color_override("font_outline_color", MenuTheme.INK)
		tag.add_theme_constant_override("outline_size", 4)
		into.add_child(tag)
	for index: int in range(objective.size()):
		into.add_child(_cell("Objective%d" % index, objective[index], OBJECTIVE_W, colour, HORIZONTAL_ALIGNMENT_RIGHT))
	into.add_child(_cell("Frags", frags, FRAGS_W, colour, HORIZONTAL_ALIGNMENT_RIGHT))
	into.add_child(_cell("Deaths", deaths, DEATHS_W, colour, HORIZONTAL_ALIGNMENT_RIGHT))
	into.add_child(_cell("Ping", ping, PING_W, colour, HORIZONTAL_ALIGNMENT_RIGHT))

func _cell(cell_name: String, text: String, width: float, colour: Color, align: HorizontalAlignment, font_size: int = MenuTheme.BODY) -> Label:
	var label := Label.new()
	label.name = cell_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.pixel_text(label, font_size, colour, 0)
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if width > 0.0:
		label.custom_minimum_size.x = width
	return label

## The footer: the hold prompt with the active device's glyph, and, when the
## board scrolls, the page keys and the page it shows.
func set_hint(template: String) -> void:
	var key: Array = [template, InputDevice.revision, InputDevice.kind]
	if key == _hint_key:
		return
	_hint_key = key
	hint.clear()
	InputGlyphs.append(hint, template, 32)

## Rows a page moves: most of the visible board, in whole rows.
func page_step() -> int:
	var row_h: float = MenuTheme.FONT.get_height(MenuTheme.BODY) + 8.0 + ROW_GAP
	return maxi(1, int(scroll.size.y * 0.8 / row_h)) * int(row_h)

## Which page of how many the board shows, 1-based.
func page() -> Vector2i:
	var visible_h: float = maxf(1.0, scroll.size.y)
	var total: float = rows.get_combined_minimum_size().y
	var pages: int = maxi(1, ceili((total - 1.0) / visible_h))
	var at: int = clampi(ceili((float(scroll.scroll_vertical) + visible_h - 1.0) / visible_h), 1, pages)
	return Vector2i(at, pages)

## Centre the plate in the view, as tall as its rows up to the view's height,
## starting at `top` or lower (the booth strip sits above a watcher's board).
func place(view: Vector2, top: float = 16.0, objective: bool = false) -> void:
	var width: float = minf(WIDTH_CAP_OBJECTIVE if objective else WIDTH_CAP, maxf(160.0, view.x - 64.0))
	hint.size = Vector2(width - 28.0, 0)
	var hint_height: float = maxf(hint.get_content_height(), MenuTheme.FONT.get_height(MenuTheme.BODY))
	var bar_width: float = scroll.get_v_scroll_bar().get_combined_minimum_size().x
	rows.size.x = width - 28.0 - bar_width
	var floor_y: float = maxf(16.0, top)
	var height: float = clampf(rows.get_combined_minimum_size().y + hint_height + 40.0, 100.0, maxf(100.0, view.y - floor_y - 32.0))
	var origin: Vector2 = ((view - Vector2(width, height)) * 0.5).round()
	origin.x = clampf(origin.x, 16.0, maxf(16.0, view.x - width - 16.0))
	origin.y = clampf(origin.y, floor_y, maxf(floor_y, view.y - height - 16.0))
	position = origin
	size = Vector2(width, height)
	scroll.position = Vector2(14, 10)
	scroll.size = Vector2(width - 28.0, height - hint_height - 40.0)
	hint.position = Vector2(14, height - hint_height - 14.0)
