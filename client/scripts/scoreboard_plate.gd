class_name ScoreboardPlate
extends Panel

## The board held on Tab: every fighter ranked by frags, with deaths and the
## measured round trip. One metal plate with a bone title, a column heading
## and level rows that line their numbers up; the viewer's own row is bone.
## Facts come from the snapshot through the HUD's standings. Presentation only.

const WIDTH_CAP: float = 1040.0
const RANK_W: float = 72.0
const FRAGS_W: float = 128.0
const DEATHS_W: float = 136.0
const PING_W: float = 112.0
const ROW_GAP: int = 4
## A ping reading the server has not taken yet (a rule bot, a fighter whose
## connection has not answered) reads as a dash, never as a number.
const NO_PING: String = "--"

var scroll: ScrollContainer
var rows: VBoxContainer
var hint: Label
var _key: Array = []

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
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", ROW_GAP)
	scroll.add_child(rows)
	hint = Label.new()
	hint.name = "ScrollHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MenuTheme.pixel_text(hint, MenuTheme.PIXEL_SIZES[0], MenuTheme.MUTED, 0)
	add_child(hint)

## The ping cell for a standings row.
static func ping_text(row: Dictionary) -> String:
	var ping: int = int(row.get("ping", -1))
	return str(ping) if ping >= 0 else NO_PING

## One row as text, for the accessible reading and the harnesses: rank, side,
## callsign and chip, then frags, deaths and ping, and YOU on the viewer's.
static func row_text(row: Dictionary, index: int, own: bool) -> String:
	var side: String = MatchRules.team_short(MatchRules.valid_team(row.get("team")))
	var tag: String = "[" + side + "] " if not side.is_empty() else ""
	var text: String = str(index + 1) + ". " + tag + str(row.get("name", "?")) + str(row.get("chip", ""))
	text += "  " + str(int(row.get("kills", 0))) + "  " + str(int(row.get("deaths", 0))) + "  " + ping_text(row)
	return text + ("  YOU" if own else "")

## The whole board as text, title and columns first.
static func board_text(standings: Array, board_line: String, own: Callable) -> String:
	var body: String = tr_text("HUD_LEADERS") + "\n"
	if not board_line.is_empty():
		body += board_line + "\n"
	body += columns_text() + "\n"
	for index: int in range(standings.size()):
		body += row_text(standings[index], index, bool(own.call(standings[index]))) + "\n"
	if standings.is_empty():
		body += "(waiting for scrap)"
	return body.strip_edges()

static func columns_text() -> String:
	return "  ".join(PackedStringArray([tr_text("HUD_BOARD_RANK"), tr_text("HUD_BOARD_CALLSIGN"),
		tr_text("HUD_BOARD_FRAGS"), tr_text("HUD_BOARD_DEATHS"), tr_text("HUD_BOARD_PING")]))

static func tr_text(key: String) -> String:
	return TranslationServer.translate(key)

## Rebuild the rows when the standings, the viewer or the locale changed.
## Returns true when it rebuilt them.
func refresh(standings: Array[Dictionary], revision: int, board_line: String, own: Callable, viewer_team: String, owner_key: Array) -> bool:
	var key: Array = [revision, board_line, viewer_team, TranslationServer.get_locale()] + owner_key
	if key == _key:
		return false
	_key = key
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	rows.add_child(_heading(board_line))
	for index: int in range(standings.size()):
		var row: Dictionary = standings[index]
		rows.add_child(_row(row, index, bool(own.call(row)), viewer_team))
	return true

func _heading(board_line: String) -> VBoxContainer:
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
	_cells(columns, tr_text("HUD_BOARD_RANK"), tr_text("HUD_BOARD_CALLSIGN"), tr_text("HUD_BOARD_FRAGS"),
		tr_text("HUD_BOARD_DEATHS"), tr_text("HUD_BOARD_PING"), MenuTheme.MUTED, null)
	heading.add_child(margin)
	return heading

func _row(row: Dictionary, index: int, own: bool, viewer_team: String) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_meta("facts", row.duplicate(true))
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
	var team: String = MatchRules.valid_team(row.get("team"))
	var relation: String = HudRelation.token(team, viewer_team)
	plate.set_meta("relation", relation)
	var colour: Color = MenuTheme.INK if own else MenuTheme.BONE
	var name_text: String = str(row.get("name", "?")) + str(row.get("chip", "")) + ("  YOU" if own else "")
	_cells(content, str(index + 1), name_text, str(int(row.get("kills", 0))), str(int(row.get("deaths", 0))),
		ping_text(row), colour, HudRelation.mark(team, relation, own))
	# The leader's rank is the one ember mark on the board.
	if index == 0 and int(row.get("kills", 0)) > 0 and not own:
		(content.get_node("Rank") as Label).add_theme_color_override("font_color", MenuTheme.EMBER)
	plate.set_meta("text", row_text(row, index, own))
	return plate

## The five cells in order, numbers right aligned in fixed columns so every
## row's numbers line up under the heading.
func _cells(into: HBoxContainer, rank: String, callsign: String, frags: String, deaths: String, ping: String, colour: Color, mark: Control) -> void:
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
	into.add_child(_cell("Frags", frags, FRAGS_W, colour, HORIZONTAL_ALIGNMENT_RIGHT))
	into.add_child(_cell("Deaths", deaths, DEATHS_W, colour, HORIZONTAL_ALIGNMENT_RIGHT))
	into.add_child(_cell("Ping", ping, PING_W, colour, HORIZONTAL_ALIGNMENT_RIGHT))

func _cell(cell_name: String, text: String, width: float, colour: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.name = cell_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.pixel_text(label, MenuTheme.BODY, colour, 0)
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if width > 0.0:
		label.custom_minimum_size.x = width
	return label

## Centre the plate in the view, as tall as its rows up to the view's height.
func place(view: Vector2, hint_text: String) -> void:
	var width: float = minf(WIDTH_CAP, maxf(160.0, view.x - 64.0))
	hint.text = hint_text
	hint.size = Vector2(width - 28.0, 0)
	var hint_height: float = hint.get_minimum_size().y
	var bar_width: float = scroll.get_v_scroll_bar().get_combined_minimum_size().x
	rows.size.x = width - 28.0 - bar_width
	var height: float = clampf(rows.get_combined_minimum_size().y + hint_height + 40.0, 100.0, maxf(100.0, view.y - 64.0))
	var origin: Vector2 = ((view - Vector2(width, height)) * 0.5).round()
	origin.x = clampf(origin.x, 16.0, maxf(16.0, view.x - width - 16.0))
	origin.y = clampf(origin.y, 16.0, maxf(16.0, view.y - height - 16.0))
	position = origin
	size = Vector2(width, height)
	scroll.position = Vector2(14, 10)
	scroll.size = Vector2(width - 28.0, height - hint_height - 40.0)
	hint.position = Vector2(14, height - hint_height - 14.0)
