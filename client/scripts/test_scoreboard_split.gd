extends SceneTree
## The hold-Tab board: free-for-all ranks everybody; a team mode splits the
## sides into their own blocks with side totals and round wins, the viewer's
## side first; objective modes carry their own columns from the server's
## credits; the MVP and the viewer's head-to-head book mark rows; the footer
## names the hold key on the active device; everything sits level and fits.

const ME: String = "00000000-0000-0000-0000-000000000001"
const MATE: String = "00000000-0000-0000-0000-000000000002"
const FOE_A: String = "00000000-0000-0000-0000-000000000003"
const FOE_B: String = "00000000-0000-0000-0000-000000000004"
const FOE_C: String = "00000000-0000-0000-0000-000000000005"

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_scoreboard_split: " + message)

func _roster() -> Array:
	return [
		{"id": ME, "name": "Nightfall", "team": "coalition", "score": 5, "deaths": 2, "objective": {"plants": 2, "captures": 1}},
		{"id": MATE, "name": "Aunt Linda", "team": "coalition", "score": 1, "deaths": 4},
		{"id": FOE_A, "name": "Meat Proxy", "team": "union", "score": 7, "deaths": 1, "objective": {"defuses": 1, "returns": 3}},
		{"id": FOE_B, "name": "Static Kid", "team": "union", "score": 3, "deaths": 3},
		{"id": FOE_C, "name": "Probe", "team": "union", "score": 0, "deaths": 5, "objective": {"plants": "two", "defuses": -1}},
	]

func _story() -> Dictionary:
	return {"story": [{"id": ME, "name": "Nightfall", "kind": "human", "nemesis": "Meat Proxy", "rivals": [
		{"name": "Meat Proxy", "kind": "bot", "won": 1, "lost": 5},
		{"name": "Static Kid", "kind": "bot", "won": 4, "lost": 1},
		{"name": "Probe", "kind": "agent", "won": 2, "lost": 2}]},
		{"id": FOE_A, "name": "Meat Proxy", "kind": "bot", "rivals": [{"name": "Nightfall", "kind": "human", "won": 5, "lost": 1}]}]}

func _run() -> void:
	_check_static_rules()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = game.get_node("HUD")
	game.remove_child(hud)
	hud.owner = null
	game.free()
	root.add_child(hud)
	hud.set_process(false)
	await process_frame
	await _check_ffa(hud)
	await _check_team_board(hud)
	await _check_objective_columns(hud)
	await _check_hint(hud)
	InputDevice.reset()
	Input.action_release("scoreboard")
	hud.queue_free()
	for frame: int in range(3):
		await process_frame
	if _failures == 0:
		print("test_scoreboard_split: PASS grouping, side bars, objective columns, MVP and rival marks, glyph prompt, level text")
		quit(0)
	else:
		quit(1)

func _check_static_rules() -> void:
	var rows: Array = [
		{"name": "A", "team": "union", "kills": 3}, {"name": "B", "team": "coalition", "kills": 2},
		{"name": "C", "team": "", "kills": 1}, {"name": "D", "team": "union", "kills": 0}]
	var ffa: Array[Dictionary] = ScoreboardPlate.groups(rows, false, "")
	_check(ffa.size() == 1 and ffa[0].side == "" and ffa[0].rows.size() == 4, "free-for-all is one block of everybody")
	var watcher: Array[Dictionary] = ScoreboardPlate.groups(rows, true, "")
	_check(watcher.map(func(group: Dictionary) -> String: return group.side) == ["union", "coalition", ""], "a watcher reads the Union first, then the free side, then anyone without a side")
	_check(watcher[0].rows.map(func(row: Dictionary) -> String: return row.name) == ["A", "D"], "a side keeps the standings order")
	var free: Array[Dictionary] = ScoreboardPlate.groups(rows.slice(0, 2), true, "coalition")
	_check(free.size() == 2 and free[0].side == "coalition", "a free fighter reads their own side first, and an empty sideless block is dropped")
	var empty: Array[Dictionary] = ScoreboardPlate.groups([], true, "union")
	_check(empty.size() == 2 and empty[0].rows.is_empty(), "both side blocks stand before anybody joins")
	_check(ScoreboardPlate.objective_columns("ffa").is_empty() and ScoreboardPlate.objective_columns("tdm").is_empty(), "arena modes carry no objective columns")
	_check(ScoreboardPlate.objective_columns("sabotage").map(func(column: Dictionary) -> String: return column.key) == ["plants", "defuses"], "Sabotage counts plants and defuses")
	_check(ScoreboardPlate.objective_columns("ctf").map(func(column: Dictionary) -> String: return column.key) == ["captures", "returns"], "capture the flag counts captures and returns")
	_check(ScoreboardPlate.objective_columns("conquest").map(func(column: Dictionary) -> String: return column.key) == ["captures"], "Conquest counts captures")
	var book: Dictionary = ScoreboardPlate.rivals_from_story(_story().story, ME)
	_check(book.size() == 3 and book["MEAT PROXY"].nemesis and book["MEAT PROXY"].lost == 5, "the viewer's book comes from their own story entry")
	_check(ScoreboardPlate.rivals_from_story(_story().story, "").is_empty(), "a watcher has no book")
	_check(ScoreboardPlate.rivals_from_story([{"id": ME, "name": "x", "rivals": "lots"}], ME).is_empty(), "a malformed story is ignored")
	var keys: Callable = func(row: Dictionary, own: bool) -> Array:
		return ScoreboardPlate.marks(row, "", book, own).map(func(mark: Dictionary) -> String: return mark.key)
	_check(keys.call({"name": "Meat Proxy"}, false) == ["nemesis"], "the nemesis is marked")
	_check(keys.call({"name": "Static Kid"}, false) == ["up"] and keys.call({"name": "Probe"}, false) == ["level"], "fighters led or level are marked")
	_check(keys.call({"name": "Static Kid"}, true).is_empty(), "the viewer's own row carries no book")
	_check(keys.call({"name": "Nobody"}, false).is_empty(), "a stranger is unmarked")
	_check(ScoreboardPlate.marks({"name": "Meat Proxy"}, "Meat Proxy", {}, false)[0].key == "mvp", "the server's MVP is marked")
	_check(ScoreboardPlate.mvp_name(rows, "") == "", "a live round names no MVP")

func _board(hud: CanvasLayer) -> Array[Node]:
	return (hud.get("_leaderboard_rows") as VBoxContainer).get_children()

func _open(hud: CanvasLayer) -> void:
	hud.set_leaderboard_open(true)
	for frame: int in range(3):
		await process_frame

func _check_ffa(hud: CanvasLayer) -> void:
	hud.set_match_rules(MatchRules.parse({"mode": "ffa"}))
	hud.set_round_info("Active", 120, 20)
	var roster: Array = _roster()
	for row: Dictionary in roster:
		row.erase("team")
	hud.sync_scores_from_players(roster)
	hud.set_viewer_context(ME, "")
	await _open(hud)
	var rows: Array[Node] = _board(hud)
	_check(rows.size() == 6 and not rows.any(func(row: Node) -> bool: return row.has_meta("side")), "free-for-all has no side bars")
	var text: String = hud.leaderboard_text()
	_check(text.contains("1. Meat Proxy  7  1  --") and text.contains("2. Nightfall  5  2  --  YOU"), "free-for-all ranks everybody on frags: " + text)
	_check(not text.contains("PLANTS") and not text.contains("CAPS"), "free-for-all shows no objective columns")
	hud.set_leaderboard_open(false)

func _check_team_board(hud: CanvasLayer) -> void:
	hud.set_match_rules(MatchRules.parse({"mode": "tdm"}))
	hud.set_round_info("Active", 120, 20)
	hud.sync_scores_from_players(_roster())
	hud.set_viewer_context(ME, "coalition")
	hud.set_team_scores({"union": 10, "coalition": 6})
	hud.note_round_winner("union")
	hud.note_round_winner("coalition")
	hud.note_round_winner("coalition")
	hud.note_round_winner("nobody")
	hud.observe_board_story(_story(), ME)
	await _open(hud)
	var rows: Array[Node] = _board(hud)
	_check(rows[1].get_meta("side", "") == "coalition" and rows[4].get_meta("side", "") == "union", "the viewer's side block leads, then the other side")
	_check(str(rows[1].get_meta("text")) == "THE FREE COALITION  6 FRAGS  ROUNDS 2" and str(rows[4].get_meta("text")) == "THE UNION  10 FRAGS  ROUNDS 1",
		"side bars carry totals and round wins: " + str([rows[1].get_meta("text"), rows[4].get_meta("text")]))
	_check((rows[1].get_node("Content/Side") as Label).get_theme_color("font_color") == MatchRules.team_label_color("coalition")
		and (rows[4].get_node("Content/Side") as Label).get_theme_color("font_color") == MatchRules.UNION_LABEL, "each side bar wears its faction colour")
	var union_style: StyleBoxFlat = (rows[4] as PanelContainer).get_theme_stylebox("panel")
	_check(union_style.border_color == MatchRules.UNION_LABEL and union_style.bg_color.r > union_style.bg_color.b, "the Union bar is black with its red edge")
	_check(rows[1].has_node("Content/Ours") and not rows[4].has_node("Content/Ours"), "the viewer's side is named as theirs")
	_check(str(rows[2].get_meta("text")).begins_with("1. [FREE] Nightfall") and str(rows[3].get_meta("text")).begins_with("2. [FREE] Aunt Linda"), "ranks count within a side")
	_check(str(rows[5].get_meta("text")).begins_with("1. [UNION] Meat Proxy") and rows.size() == 8, "the other side ranks from one: " + str(rows.size()))
	_check(rows[5].get_meta("marks") == ["nemesis"] and rows[6].get_meta("marks") == ["up"] and rows[7].get_meta("marks") == ["level"], "nemesis and head-to-head marks from the session book")
	_check(rows[2].get_meta("marks") == [] and rows[3].get_meta("marks") == [], "own side rows the viewer never met are unmarked")
	var nemesis: Label = rows[5].get_node("Content/Mark0")
	_check(nemesis.text == "NEMESIS 1-5" and nemesis.get_theme_color("font_color") == MenuTheme.EMBER, "the nemesis mark reads the book: " + nemesis.text)
	# The round ends: the server's MVP is marked, and a new round clears it.
	hud.show_round_end("Meat Proxy", "Frag limit reached", 7)
	hud.sync_scores_from_players(_roster())
	await _open(hud)
	rows = _board(hud)
	_check(rows[5].get_meta("marks") == ["mvp", "nemesis"], "the round's MVP is marked once it ended: " + str(rows[5].get_meta("marks")))
	hud.set_round_info("Active", 120, 20)
	await _open(hud)
	_check(_board(hud)[5].get_meta("marks") == ["nemesis"], "a live round carries no MVP")
	# A watcher following a free fighter still reads the Union first, owns no
	# side and has no book.
	hud.set_viewer_context("", "coalition")
	hud.observe_board_story(_story(), "")
	await _open(hud)
	rows = _board(hud)
	_check(rows[1].get_meta("side", "") == "union" and rows.all(func(row: Node) -> bool: return not row.has_meta("marks") or row.get_meta("marks") == []), "a watcher sees both sides in full, Union first, unmarked")
	_check(rows.size() == 8, "every fighter on both sides is listed for a watcher")
	_check(not rows[1].has_node("Content/Ours") and not rows[4].has_node("Content/Ours"), "a watcher owns neither side")
	_check_level(hud)
	hud.set_leaderboard_open(false)

func _check_objective_columns(hud: CanvasLayer) -> void:
	for mode: String in ["sabotage", "ctf", "conquest"]:
		hud.set_match_rules(MatchRules.parse({"mode": mode}))
		hud.set_round_info("Active", 120, 20)
		hud.sync_scores_from_players(_roster())
		hud.set_viewer_context(ME, "coalition")
		await _open(hud)
		var rows: Array[Node] = _board(hud)
		var heading: Node = rows[0].find_child("Columns", true, false)
		var mine: Node = rows[2]
		var heads: Array = ScoreboardPlate.objective_columns(mode).map(func(column: Dictionary) -> String: return tr(column.heading))
		for index: int in range(heads.size()):
			_check((heading.get_node("Objective%d" % index) as Label).text == heads[index], mode + " heading column " + str(index))
			var head: Label = heading.get_node("Objective%d" % index)
			var cell: Label = mine.get_node("Content/Objective%d" % index)
			_check(absf(head.get_global_rect().end.x - cell.get_global_rect().end.x) <= 1.0, mode + " objective counts line up under their heading")
		var expected: Dictionary = {"sabotage": ["2", "0"], "ctf": ["1", "0"], "conquest": ["1"]}
		for index: int in range(expected[mode].size()):
			_check((mine.get_node("Content/Objective%d" % index) as Label).text == expected[mode][index], mode + " carries the server's credits: " + str(index))
		var probe: Node = rows[rows.size() - 1]
		_check((probe.get_node("Content/Objective0") as Label).text == "0", mode + " malformed credits read as zero")
		var meat: Node = rows[5]
		if mode == "ctf":
			_check((meat.get_node("Content/Objective1") as Label).text == "3", "flag returns are counted")
		if mode == "sabotage":
			_check((meat.get_node("Content/Objective1") as Label).text == "1", "defuses are counted")
		var view: Rect2 = hud.get_viewport().get_visible_rect()
		var panel: Control = hud.get_node("Leaderboard")
		_check(view.encloses(panel.get_global_rect()), mode + " board stays on screen")
		for row: Node in rows:
			var text: Label = row.get_node_or_null("Content/Text")
			if text != null:
				_check(text.get_line_count() == 1, mode + " callsigns stay on one line beside the objective columns: " + text.text)
	hud.sabotage_score = {}
	hud.set_match_rules(MatchRules.parse({"mode": "sabotage"}))
	hud.set_viewer_context(ME, "coalition")
	hud.set_sabotage_state({"score": {"union": 2, "coalition": 3}}, "coalition", 0, false, false)
	await _open(hud)
	_check(str(_board(hud)[1].get_meta("text")) == "THE FREE COALITION  3 ROUNDS WON", "Sabotage sides count rounds won: " + str(_board(hud)[1].get_meta("text")))
	hud.set_leaderboard_open(false)

func _check_hint(hud: CanvasLayer) -> void:
	hud.set_match_rules(MatchRules.parse({"mode": "tdm"}))
	InputDevice.force(InputDevice.Kind.KEYBOARD)
	await _open(hud)
	var hint: RichTextLabel = hud.get("_leaderboard_hint")
	var keyboard: String = hint.get_parsed_text()
	_check(keyboard.contains("HOLD") and keyboard.contains(InputGlyphs.action_name("scoreboard")), "the keyboard prompt names the hold key: " + keyboard)
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "letters")
	await _open(hud)
	var pad: String = hint.get_parsed_text()
	_check(pad != keyboard and not pad.contains(InputGlyphs.key_name(InputBindings.live_token("scoreboard", false))), "the pad prompt draws the pad glyph instead of the key: " + pad)
	# A long roster pages on the existing weapon cycle and says which page.
	var roster: Array = []
	for index: int in range(80):
		roster.append({"id": "00000000-0000-0000-0000-0000000002%02d" % index, "name": "Fighter %02d" % index, "team": ["union", "coalition"][index % 2], "score": 90 - index})
	hud.sync_scores_from_players(roster)
	Input.action_press("scoreboard")
	await _open(hud)
	_check(hint.get_parsed_text().contains("PAGE 1/"), "a long board says which page it shows: " + hint.get_parsed_text())
	var next: InputEventAction = InputEventAction.new()
	next.action = "weapon_next"
	next.pressed = true
	var scroll: ScrollContainer = hud.get("_leaderboard_scroll")
	_check(hud.handle_leaderboard_input(next) and scroll.scroll_vertical > 0, "a bumper or key turns a page")
	await process_frame
	_check(hint.get_parsed_text().contains("PAGE 2/"), "the footer follows the page: " + hint.get_parsed_text())
	Input.action_release("scoreboard")
	hud.set_leaderboard_open(false)

func _check_level(hud: CanvasLayer) -> void:
	var panel: Control = hud.get_node("Leaderboard")
	for label: Node in panel.find_children("*", "Label", true, false):
		_check(is_zero_approx((label as Label).rotation) and (label as Label).get_theme_font("font") == MenuTheme.FONT, "every board word is level Silkscreen")
	var node: Node = panel
	while node != null:
		if node is Control:
			_check(is_zero_approx((node as Control).rotation), "nothing above the board rotates it")
		node = node.get_parent()
