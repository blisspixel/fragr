extends SceneTree

class BoardInputManager extends "res://scripts/game_manager.gd":
	func _ready() -> void:
		pass
	func controls_blocked() -> bool:
		return false

## Headless gate for the rule set as the client shows it: validation of
## `map_info.rules`, the mode chip, the team scoreboard, team-coloured
## fighters and every keyed Host reaction.
## Run: godot --path client --headless --script res://scripts/test_match_rules.gd

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_match_rules: " + message)


func _run() -> void:
	set_meta("fragr_settings_path", "user://test-match-rules-%d.cfg" % OS.get_process_id())
	_check_parse()
	_check_labels()
	_check_reactions()
	await _check_hud()
	await _check_board_input_route()
	await _check_pawn()
	if _failures == 0:
		print("test_match_rules: PASS")
	quit(0 if _failures == 0 else 1)


func _check_parse() -> void:
	var tdm: Dictionary = MatchRules.parse({"mode": "tdm", "name": "Team Deathmatch: Rail Only, Two Lives", "mutators": ["rail-only", "two-lives", "rail-only", "low-gravity"], "friendly_fire": true, "lives": 2.0})
	_check(tdm.get("mode") == "tdm", "tdm parses")
	_check(tdm.get("mutators") == ["rail-only", "two-lives"], "mutators dedupe and drop unknown ids: " + str(tdm.get("mutators")))
	_check(tdm.get("friendly_fire") == true and tdm.get("lives") == 2, "friendly fire and lives parse")
	_check(MatchRules.teams(tdm), "tdm has sides")
	var ctf: Dictionary = MatchRules.parse({"mode": "ctf", "name": "Capture the Flag"})
	_check(MatchRules.teams(ctf), "ctf has sides")
	var ffa: Dictionary = MatchRules.parse({"mode": "ffa", "name": "Free-for-all"})
	_check(ffa.get("mutators") == [] and ffa.get("lives") == 0 and not MatchRules.teams(ffa), "plain ffa parses with defaults")
	for bad: Variant in [null, "tdm", {}, {"mode": "unknown"}, {"mode": 1}, {"mode": "ffa", "mutators": "rail-only"},
			{"mode": "ffa", "friendly_fire": "yes"}, {"mode": "ffa", "lives": 0}, {"mode": "ffa", "lives": 1.5},
			{"mode": "ffa", "lives": 99}, {"mode": "ffa", "lives": "2"}, {"mode": "ffa", "start_kit": "tack"},
			{"mode": "ffa", "start_kit": ["tack", "tack"]}, {"mode": "ffa", "start_kit": ["pistol"]}, {"mode": "ffa", "start_kit": [3]}]:
		_check(MatchRules.parse(bad).is_empty(), "malformed rules are refused: " + str(bad))
	# The start kit: what a fresh life holds, and so what a death costs.
	var scrap: Dictionary = MatchRules.parse({"mode": "ffa", "name": "Free-for-all", "start_kit": ["fists", "tack"]})
	_check(scrap.get("start_kit") == ["fists", "tack"], "the free-for-all kit parses: " + str(scrap.get("start_kit")))
	_check(MatchRules.lost_at_death(scrap, ["fists", "tack", "rail", "flechette"]) == ["flechette", "rail"], "found guns are lost, in wire order")
	_check(MatchRules.lost_at_death(scrap, ["fists", "tack"]) == [], "the kit itself is never lost")
	_check(MatchRules.lost_at_death({}, ["rail"]) == [], "a campaign map names no loss")
	var arsenal: Dictionary = MatchRules.parse({"mode": "ffa", "mutators": ["full-arsenal"], "start_kit": ["flechette", "scatter", "rail"]})
	_check(arsenal.get("mutators") == ["full-arsenal"], "full arsenal is a known mutator")
	_check(MatchRules.lost_at_death(arsenal, ["flechette", "scatter", "rail"]) == [], "an arsenal life loses nothing")
	_check(MatchRules.chip_text(arsenal) == "FREE FOR ALL // FULL ARSENAL", "full arsenal chip: " + MatchRules.chip_text(arsenal))
	_check(MatchRules.weapon_list(["flechette", "rail"]) == "RIFLE + RAILGUN", "player names, not wire ids: " + MatchRules.weapon_list(["flechette", "rail"]))


func _check_labels() -> void:
	var tdm: Dictionary = MatchRules.parse({"mode": "tdm", "mutators": ["rail-only", "two-lives"], "friendly_fire": true, "lives": 2})
	_check(MatchRules.chip_text(tdm) == "TEAM DEATHMATCH // RAIL ONLY + TWO LIVES + FRIENDLY FIRE", "tdm chip: " + MatchRules.chip_text(tdm))
	_check(MatchRules.chip_text(MatchRules.parse({"mode": "ffa"})) == "FREE FOR ALL", "ffa chip")
	var duel: Dictionary = MatchRules.parse({"mode": "duel", "name": "Duel", "start_kit": ["fists", "tack"]})
	_check(MatchRules.chip_text(duel) == "DUEL" and not MatchRules.teams(duel), "a duel is a sideless mode with its own chip")
	_check(MatchRules.chip_text(MatchRules.parse({"mode": "ctf"})) == "CAPTURE THE FLAG", "ctf chip")
	_check(MatchRules.chip_text({}) == "", "no rules, no chip")
	for mutator: String in MatchRules.MUTATORS:
		var chip: String = MatchRules.chip_text(MatchRules.parse({"mode": "ffa", "mutators": [mutator]}))
		_check(not chip.contains("MUTATOR_"), "every mutator has a label: " + chip)
	_check(MatchRules.team_score_line({"union": 3.0, "coalition": 5}) == "UNION 3 : 5 FREE COALITION", "side score line")
	for bad: Variant in [null, {}, {"union": -1, "coalition": 0}, {"union": 1.5, "coalition": 0}, {"union": "3", "coalition": 1}]:
		_check(MatchRules.team_score_line(bad) == "", "bad side scores show nothing: " + str(bad))
	_check(MatchRules.team_short("union") == "UNION" and MatchRules.team_short("coalition") == "FREE", "side chips")
	_check(MatchRules.team_relation("coalition", "coalition") == "mate" and MatchRules.team_relation("union", "coalition") == "foe", "the same side is yours")
	_check(MatchRules.team_relation("", "union") == "" and MatchRules.team_relation("union", "") == "", "a missing side is not a team mark")
	_check(MatchRules.relation_mark("mate") == "OURS" and MatchRules.relation_mark("foe") == "THEIRS" and MatchRules.relation_mark("") == "", "marks name your side and the other")
	_check(MatchRules.team_name("coalition") == "The Free Coalition", "side name")
	_check(MatchRules.valid_team("union") == "union" and MatchRules.valid_team("office") == "" and MatchRules.valid_team(3) == "", "only two sides")
	_check(MatchRules.team_label_color("union") == MatchRules.UNION_LABEL and MatchRules.team_label_color("coalition") == MatchRules.COALITION_LABEL, "side colours")
	_check(MatchRules.team_label_color("union", true) == MatchRules.UNION_LABEL and MatchRules.team_label_color("coalition", true) == Color("e8e2d6"), "high contrast side colours")
	_check(MatchRules.team_shape_mark("union") == "■" and MatchRules.team_shape_mark("coalition") == "□" and MatchRules.team_shape_mark("") == "", "shape marks for sides")
	var free_pole: Color = MatchRules.team_body_color("coalition")
	_check(not FactionPalette.is_off_white(free_pole) and free_pole.get_luminance() < 0.6 and free_pole.r > free_pole.b,
		"the free flag pole is worn leather, never bone: " + free_pole.to_html(false))
	_check(FactionPalette.free_accent_allowed(MatchRules.COALITION_LABEL), "the free cloth is a non-reserved warm accent")


func _check_reactions() -> void:
	for kind: String in MatchRules.REACTIONS:
		for variant: int in range(MatchRules.REACTION_VARIANTS):
			var line: String = MatchRules.reaction_line({"kind": kind, "variant": variant, "player": "Dead Air Dan", "other": "Nightfall", "team": "union"})
			_check(line.begins_with("HOST: "), "every reaction is keyed: %s %d -> %s" % [kind, variant, line])
			_check(not line.contains("{"), "every placeholder fills: " + line)
			_check(not line.contains(char(0x2014)) and not line.contains(char(0x2013)), "no long dashes: " + line)
	var first: String = MatchRules.reaction_line({"kind": "first_blood", "variant": 0.0, "player": "Dead Air Dan"})
	_check(first == "HOST: FIRST BLOOD. DEAD AIR DAN. SOMEBODY HAD TO.", "first blood line: " + first)
	var comeback: String = MatchRules.reaction_line({"kind": "comeback", "variant": 0, "team": "coalition"})
	_check(comeback == "HOST: THE FREE COALITION CLAWS IT BACK. LEVEL GAME.", "comeback names the side: " + comeback)
	for variant: int in range(MatchRules.REACTION_VARIANTS):
		var special: String = MatchRules.reaction_line({"kind": "larak_lot_special", "variant": variant, "player": "Nightfall"})
		_check(special.contains("THE LARAK LOT SPECIAL"), "the frag spike keeps the league's own name: " + special)
	for bad: Dictionary in [{}, {"kind": "ace"}, {"kind": "first_blood", "variant": 3}, {"kind": "first_blood", "variant": -1}, {"kind": 4}]:
		_check(MatchRules.reaction_line(bad) == "", "unknown reactions stay silent: " + str(bad))
	# A side call keys its own words, so no line names an empty fighter.
	for kind: String in MatchRules.SIDE_REACTIONS:
		for variant: int in range(MatchRules.REACTION_VARIANTS):
			var side: String = MatchRules.reaction_line({"kind": kind, "variant": variant, "team": "union"})
			_check(side.contains("UNION") and not side.contains("  ") and not side.contains(" ."), "side call names the side: " + side)
	var point: String = MatchRules.reaction_line({"kind": "match_point", "variant": 0, "team": "coalition"})
	_check(point == "HOST: MATCH POINT! THE FREE COALITION!", "side match point: " + point)
	var triple: String = MatchRules.reaction_line({"kind": "triple_frag", "variant": 0, "player": "Nightfall", "big": true})
	_check(triple == "HOST: TRIPLE FRAG! NIGHTFALL!", "triple frag caption keeps the name: " + triple)
	_check(MatchRules.reaction_big({"big": true}) and not MatchRules.reaction_big({"big": 1}) and not MatchRules.reaction_big({}), "only a true flag is a big moment")
	# Canon: the Host never sells the station inside a match call.
	for kind: String in MatchRules.REACTIONS:
		for variant: int in range(MatchRules.REACTION_VARIANTS):
			var line: String = MatchRules.reaction_line({"kind": kind, "variant": variant, "player": "A", "other": "B", "team": "union"}).to_upper()
			_check(not line.contains("FREQUENCY") and not line.contains("TUNES IN"), "no station puns: " + line)


func _check_hud() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	await process_frame
	hud.set_process(false)
	var chip: Label = hud.get("mode_chip_label")
	_check(chip != null and not chip.visible, "no chip before rules")
	hud.set_round_info("Active", 0, 0)
	var round_line: Label = hud.get("round_label")
	_check(chip.get_parent() == hud and round_line.get_parent() != hud and round_line.max_lines_visible == 1, "center facts are separate from the short corner state")
	hud.call("set_match_rules", MatchRules.parse({"mode": "tdm", "mutators": ["rail-only"]}))
	hud.call("set_team_scores", {"union": 3, "coalition": 5})
	hud.call("sync_scores_from_players", [
		{"name": "Dead Air Dan", "score": 2, "team": "union"},
		{"name": "Nightfall", "score": 4, "team": "coalition", "behavior": "Defensive"},
		{"name": "Static Kid", "score": 1, "team": "coalition"},
	])
	_check(chip.visible and chip.text == "UNION 3 : 5 FREE COALITION\nRAIL ONLY" and hud.mode_label.text == "TEAM DEATHMATCH", "center carries side score and modifiers; corner names the mode: " + chip.text)
	var board: String = hud.get("scoreboard").text
	var lines: PackedStringArray = board.strip_edges().split("\n")
	_check(lines.size() == 4, "side score plus three rows: " + board)
	_check(lines[0] == "UNION 3 : 5 FREE COALITION", "side score leads the scoreboard: " + lines[0])
	_check(lines[1] == "1.*[FREE] Nightfall [DEF]: 4", "leader row carries the side chip: " + lines[1])
	_check(lines[2] == "2. [UNION] Dead Air Dan: 2", "second row: " + lines[2])
	hud.call("set_match_rules", MatchRules.parse({"mode": "ctf", "mutators": []}))
	hud.call("set_league_identity", "Scrap League", "Arena Duel")
	var league_line: String = hud.get("mode_label").text
	_check(league_line == "CAPTURE THE FLAG", "ctf names its actual mode without the older arena playlist: " + league_line)
	var flags: Array = [
		{"team": "union", "status": "carried", "carrier": "a1"},
		{"team": "coalition", "status": "dropped", "return_ticks": 39, "position": [10.0, 0.0, -10.0]},
	]
	hud.call("set_ctf_state", flags, {"union": 1.0, "coalition": 2.0}, 3.0,
		[{"id": "a1", "name": "Dead Air Dan", "x": 0.0, "y": 0.0, "z": 0.0}], "a1")
	_check(chip.text.contains("CAPTURES U 1 : 2 FREE / 3 TO WIN"), "ctf score and win target: " + chip.text)
	_check(chip.text.contains("UNION FLAG CARRIED BY Dead Air Dan\nFREE FLAG DOWN 2S, 14M NE"), "carrier and dropped bearing: " + chip.text)
	_check(hud.get("scoreboard").text.begins_with("FRAGS (CAPTURES WIN)"), "fighter frag rows are secondary to captures")
	await process_frame
	var ctf_chip_bounds: Rect2 = chip.get_global_rect()
	var ctf_panel_bounds: Rect2 = Rect2(510, 16, 900, 344)
	_check(ctf_panel_bounds.encloses(ctf_chip_bounds), "ctf status fits inside its centered region")
	var home_flags: Array = [
		{"team": "union", "status": "carried", "carrier": "a1", "stand": [-70.0, 0.0, 0.0], "position": [0.0, 0.0, 0.0]},
		{"team": "coalition", "status": "home", "stand": [70.0, 0.0, 0.0], "position": [70.0, 0.0, 0.0]},
	]
	hud.call("set_ctf_state", home_flags, {"union": 1.0, "coalition": 2.0}, 3.0, [
		{"id": "a1", "name": "Dead Air Dan", "team": "coalition", "x": 0.0, "y": 0.0, "z": 0.0},
		{"id": "b2", "name": "Nightfall", "team": "union", "x": 0.0, "y": 0.0, "z": -14.0},
	], "a1")
	_check(chip.text.contains("UNION FLAG CARRIED BY Dead Air Dan\nFREE FLAG HOME 70M E"), "carrier return bearing: " + chip.text)
	hud.call("set_ctf_state", home_flags, {"union": 1.0, "coalition": 2.0}, 3.0, [
		{"id": "a1", "name": "Dead Air Dan", "team": "coalition", "x": 0.0, "y": 0.0, "z": 0.0},
		{"id": "b2", "name": "Nightfall", "team": "union", "x": 0.0, "y": 0.0, "z": -14.0},
	], "b2")
	_check(chip.text.contains("UNION FLAG CARRIED BY Dead Air Dan, 14M S\nFREE FLAG HOME"), "chase bearing: " + chip.text)
	await process_frame
	var compass_bounds: Rect2 = chip.get_global_rect()
	_check(ctf_panel_bounds.encloses(compass_bounds), "a compass line still fits the centered region")
	hud.call("set_fp_juice", true)
	hud.call("set_fp_carried_flag", "union")
	var pennant: Control = hud.get_node("FpPennant")
	_check(pennant.visible, "first person shows the carried flag beside the weapon")
	var pennant_words: Label = pennant.get_node("Words")
	_check(pennant_words.text == "UNION FLAG", "pennant uses the stand words: " + pennant_words.text)
	_check((pennant.get_node("Cloth") as ColorRect).color == MatchRules.UNION_LABEL, "union pennant uses the union cloth")
	_check((pennant.get_node("Pole") as ColorRect).color == MatchRules.UNION_BODY, "union pennant uses the union pole")
	_check(pennant.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the pennant does not take the pointer")
	var view_size: Vector2 = hud.get_viewport().get_visible_rect().size
	var pennant_rect: Rect2 = pennant.get_global_rect()
	_check(pennant_rect.end.x < view_size.x * 0.5, "pennant stays left of the crosshair: " + str(pennant_rect))
	_check(not pennant_rect.has_point(view_size * 0.5), "pennant does not cover the crosshair")
	hud.call("set_fp_carried_flag", "coalition")
	_check(pennant.visible and pennant_words.text == "FREE FLAG", "coalition pennant uses the free words: " + pennant_words.text)
	_check((pennant.get_node("Cloth") as ColorRect).color == MatchRules.COALITION_LABEL, "coalition pennant uses the free cloth")
	var free_staff: Color = (pennant.get_node("Pole") as ColorRect).color
	_check(free_staff == MatchRules.COALITION_BODY and not FactionPalette.is_off_white(free_staff),
		"coalition pennant staff is leather, not bone: " + free_staff.to_html(false))
	hud.call("set_fp_carried_flag", "office")
	_check(not pennant.visible, "an unknown side does not invent a pennant")
	hud.call("set_fp_carried_flag", "union")
	hud.call("set_fp_juice", false)
	_check(not pennant.visible, "leaving first person hides the pennant")
	hud.call("set_fp_juice", true)
	_check(pennant.visible and pennant_words.text == "UNION FLAG", "returning to first person keeps the carried flag")
	hud.call("set_fp_juice", false)
	hud.call("set_fp_carried_flag", "")
	hud.call("show_round_end", "Dead Air Dan", "Capture limit reached", 8, "", [], "coalition", {"union": 1.0, "coalition": 3.0})
	var round_banner: Label = hud.get("round_message")
	_check(round_banner.text.begins_with("FREE TAKES THE ROUND\nCAPTURES: UNION 1 : 3 FREE"), "ctf winner follows captures instead of mvp frags: " + round_banner.text)
	var result_card: Panel = hud.get_node("RoundBackdrop")
	_check(result_card.visible, "a capture result sits on a card")
	var result_style: StyleBoxFlat = result_card.get_theme_stylebox("panel") as StyleBoxFlat
	_check(result_style != null and is_equal_approx(result_style.bg_color.a, 1.0), "the result card hides the flag behind the words")
	await process_frame
	_check(result_card.get_global_rect().encloses(round_banner.get_global_rect()), "the result words stay on the card")
	hud.call("show_round_end", "Dead Air Dan", "Clock expired", 8, "", [], null, {"union": 1.0, "coalition": 1.0})
	_check(round_banner.text.begins_with("ROUND DRAW: FLAGS DEADLOCKED\nCAPTURES: UNION 1 : 1 FREE"), "equal captures announce a draw: " + round_banner.text)
	hud.call("set_own_lives", 2)
	_check(not chip.text.contains("LIVES"), "no lives line without limited lives")
	hud.call("set_match_rules", MatchRules.parse({"mode": "tdm", "mutators": ["rail-only", "two-lives"], "lives": 2}))
	hud.call("set_own_lives", 2)
	await process_frame
	var chip_bounds: Rect2 = chip.get_global_rect()
	var panel_bounds: Rect2 = Rect2(510, 16, 900, 344)
	_check(chip.text.contains("RAIL ONLY") and chip.text.contains("TWO LIVES") and chip.text.contains("LIVES 2"), "combined rules and lives stay in the chip")
	_check(panel_bounds.encloses(chip_bounds), "combined rule chip fits inside the centered region")
	hud.call("set_match_rules", MatchRules.parse({"mode": "ffa", "mutators": ["two-lives"], "lives": 2}))
	hud.call("set_own_lives", 1)
	_check(chip.text == "TWO LIVES\nLIVES 1" and hud.mode_label.text == "FREE FOR ALL", "lives line under two lives: " + chip.text)
	hud.call("set_own_lives", 0)
	_check(chip.text.ends_with("OUT OF LIVES. WATCHING UNTIL THE ROUND ENDS."), "an eliminated player is told why: " + chip.text)
	hud.call("sync_scores_from_players", [{"name": "Dead Air Dan", "score": 2}])
	_check(not hud.get("scoreboard").text.contains("[UNION]"), "free-for-all rows carry no side")
	hud.call("sync_scores_from_players", [
		{"name": "Dead Air Dan", "score": 4},
		{"name": "Nightfall", "score": 3},
		{"name": "Static Kid", "score": 2},
		{"name": "Aunt Linda", "score": 1},
		{"name": "Meat Proxy", "score": 5, "deaths": 1, "attacks": 3, "connects": 2, "heads": 1, "damage": 40, "ping": 23},
		{"name": "Probe", "score": 0, "ping": 1000},
	])
	hud.call("set_board_name", "Meat Proxy")
	var leaders: String = str(hud.call("leaderboard_text"))
	_check(leaders.begins_with("LEADERS\n"), "tab board names itself: " + leaders)
	_check(leaders.contains("#  CALLSIGN  FRAGS  DEATHS  PING"), "tab board names its columns: " + leaders)
	_check(leaders.contains("1. Meat Proxy  5  1  23  YOU"), "local fighter carries rank, frags, deaths and ping: " + leaders)
	_check(leaders.contains("6. Probe  0  0  --"), "an impossible ping reads as no reading, never a number: " + leaders)
	_check(leaders.contains("2. Dead Air Dan  4  0  --"), "a fighter with no reading shows a dash: " + leaders)
	hud.call("set_board_name", "")
	var spectator: String = str(hud.call("leaderboard_text"))
	_check(spectator.contains("1. Meat Proxy  5  1  23") and not spectator.contains("YOU"), "a spectator still gets the columns: " + spectator)
	hud.call("set_board_name", "Meat Proxy")
	var corner: String = str(hud.get("scoreboard").text)
	_check(not corner.contains("Probe"), "the corner stays the top four: " + corner)
	_check(corner.contains("Meat Proxy: 5") and not corner.contains("HIT%"), "the corner stays on frags: " + corner)
	hud.call("set_leaderboard_open", true)
	await process_frame
	var leaders_panel: Control = hud.get_node("Leaderboard")
	_check(leaders_panel.visible and leaders_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "tab opens a board that ignores the pointer")
	var view: Rect2 = hud.get_viewport().get_visible_rect()
	_check(view.encloses(leaders_panel.get_global_rect()), "the board stays on screen: " + str(leaders_panel.get_global_rect()) + " in " + str(view))
	var leader_rows: VBoxContainer = hud.get("_leaderboard_rows")
	_check(leaders_panel.get_global_rect().encloses(leader_rows.get_global_rect()), "ordinary standings text fits its backing")
	await _check_large_board(hud)
	hud.call("set_leaderboard_open", false)
	_check(not leaders_panel.visible, "releasing tab hides the board")
	hud.call("show_host_reaction", {"kind": "golden_rail", "variant": 2, "player": "Aunt Linda"})
	hud.call("set_match_rules", {})
	_check(not chip.visible, "a campaign map clears the chip")
	hud.call("set_followed_weapon", "Rail", "Nightfall", "", "coalition")
	var follow: Label = hud.get("weapon_label")
	_check(follow.text.begins_with("[FREE] FOLLOWING: Nightfall"), "spectators see the followed side: " + follow.text)
	hud.queue_free()
	await process_frame


func _check_large_board(hud: CanvasLayer) -> void:
	var roster: Array = []
	for i: int in range(64):
		roster.append({"name": "測試界abcdefghijklmnopqr%02d" % i, "score": 64 - i,
			"team": "union", "deaths": 999, "attacks": 999999, "connects": 999999,
			"heads": 999999, "damage": 999999})
	hud.call("sync_scores_from_players", roster)
	hud.call("set_leaderboard_open", true)
	for frame: int in range(3):
		await process_frame
	var panel: Control = hud.get_node("Leaderboard")
	var scroll: ScrollContainer = hud.get("_leaderboard_scroll")
	var rows: VBoxContainer = hud.get("_leaderboard_rows")
	var hint: Label = hud.get("_leaderboard_hint")
	_check(panel.get_global_rect().encloses(scroll.get_global_rect()), "large roster has a bounded scrolling viewport")
	_check(panel.get_global_rect().encloses(hint.get_global_rect()), "scroll instructions stay inside the panel")
	_check(rows.get_global_rect().end.x <= scroll.get_global_rect().end.x, "long Unicode names and counts wrap within the board width")
	var final_row: Control = rows.get_child(64)
	var final_label: Label = final_row.get_node("Content/Text")
	_check(final_label.text.contains("測試界abcdefghijklmnopqr63") and str(final_row.get_meta("text")).contains("64. [UNION] 測試界abcdefghijklmnopqr63  1  999  --"), "large roster retains the final fighter and full counts: " + str(final_row.get_meta("text")))
	_check((final_row.get_node("Content/Rank") as Label).text == "64" and (final_row.get_node("Content/Deaths") as Label).text == "999", "rank and deaths sit in their own columns")
	var heading: Control = rows.get_child(0).get_node("Columns") if rows.get_child(0).has_node("Columns") else rows.get_child(0).find_child("Columns", true, false)
	var frags_head: Label = heading.get_node("Frags")
	var frags_cell: Label = final_row.get_node("Content/Frags")
	_check(absf(frags_head.get_global_rect().end.x - frags_cell.get_global_rect().end.x) <= 1.0, "numbers line up under their heading: " + str([frags_head.get_global_rect(), frags_cell.get_global_rect()]))
	var next: InputEventAction = InputEventAction.new()
	next.action = "weapon_next"
	next.pressed = true
	_check(not hud.call("handle_leaderboard_input", next), "weapon input is not consumed without the held scoreboard action")
	Input.action_press("scoreboard")
	_check(hud.call("handle_leaderboard_input", next) and scroll.scroll_vertical > 0, "held board consumes the existing next binding and scrolls")
	var offset: int = scroll.scroll_vertical
	hud.call("set_leaderboard_open", true)
	_check(scroll.scroll_vertical == offset, "snapshot refresh does not reset browsing")
	for page: int in range(64):
		hud.call("handle_leaderboard_input", next)
	await process_frame
	_check(rows.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1.0, "the last fighter is reachable without clipping its final line")
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	offset = scroll.scroll_vertical
	_check(hud.call("handle_leaderboard_input", wheel) and scroll.scroll_vertical < offset, "wheel up scrolls upward instead of selecting equipment")
	Input.action_release("scoreboard")
	hud.call("set_leaderboard_open", false)
	hud.call("set_leaderboard_open", true)
	_check(scroll.scroll_vertical == 0, "a newly held board starts at the leaders")


func _check_board_input_route() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.set_script(BoardInputManager)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	await process_frame
	game.is_human_player = true
	game.net_client.equipment = {"selected": "tack", "weapons": ["fists", "tack"]}
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_BRACKETRIGHT
	key.pressed = true
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	var pad: InputEventJoypadButton = InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_SHOULDER
	pad.pressed = true
	Input.action_press("scoreboard")
	for event: InputEvent in [key, wheel, pad]:
		game._input(event)
		_check(game.pending_weapon_swap == null and game.pending_seat.is_empty(), "held board browsing cannot select equipment or a seat: " + event.as_text())
	Input.action_release("scoreboard")
	game._input(key)
	_check(game.pending_weapon_swap == "fists", "releasing the board restores ordinary weapon selection")
	game.pending_weapon_swap = null
	game.net_client.player_id = "self"
	game.latest_snapshot = {"vehicles": [{"kind": "jeep", "driver": "self", "gunner": null}]}
	Input.action_press("scoreboard")
	game._input(pad)
	_check(game.pending_seat.is_empty(), "a seated driver's held-board input does not switch seats")
	Input.action_release("scoreboard")
	game._input(pad)
	_check(game.pending_seat == "gunner", "releasing the board restores the driver's seat switch")
	game.queue_free()
	await process_frame


func _check_pawn() -> void:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(pawn)
	await process_frame
	pawn.call("set_player_data", "a1", "Dead Air Dan")
	var own: Color = pawn.get("player_color")
	var state: Dictionary = {"id": "a1", "name": "Dead Air Dan", "x": 0.0, "y": 1.5, "z": 0.0, "yaw": 0.0, "hp": 100, "armor": 0, "score": 1, "weapon": "Rail", "team": "union"}
	pawn.call("update_state", state, 1)
	_check(pawn.get("team") == "union", "pawn reads its side")
	_check(pawn.get("player_color") == MatchRules.UNION_LABEL, "Union fighters wear Union red")
	var label: Label3D = pawn.get_node("Label3D")
	_check(label.text.begins_with("[UNION] Dead Air Dan"), "nameplate leads with the side: " + label.text)
	var body: Sprite3D = pawn.get_node("Body")
	_check(body.modulate.get_luminance() < 0.8, "Union body reads dark: " + str(body.modulate))
	state["team"] = "coalition"
	pawn.call("update_state", state, 2)
	_check(pawn.get("player_color") == MatchRules.COALITION_LABEL, "a moved fighter changes colour")
	_check(body.modulate == Color.WHITE, "a legacy coalition fighter keeps its own art, never washed to bone: " + str(body.modulate))
	pawn.set_team_relation("mate")
	_check(label.text == "OURS" and label.modulate == MatchRules.COALITION_LABEL, "a teammate is marked OURS in its side colour: " + label.text)
	_check(body.modulate == Color.WHITE, "a teammate is not tinted: " + str(body.modulate))
	pawn.set_team_relation("foe")
	_check(label.text == "THEIRS" and label.modulate == MatchRules.COALITION_LABEL and body.modulate == Color.WHITE,
		"a free foe is never tinted or plated Union red: " + str(body.modulate))
	pawn.set_team_relation("")
	_check(label.text.begins_with("[FREE]"), "clearing the mark restores the side chip: " + label.text)
	state.erase("team")
	state["golden"] = true
	pawn.call("update_state", state, 3)
	_check(pawn.get("player_color") == own, "a sideless fighter keeps its own colour")
	_check(label.modulate == MatchRules.GOLD, "the golden holder's plate glows gold")
	_check(body.modulate.r > body.modulate.b, "the golden holder's body glows warm")
	pawn.queue_free()
	await process_frame
