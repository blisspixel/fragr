extends SceneTree

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
			{"mode": "ffa", "lives": 99}, {"mode": "ffa", "lives": "2"}]:
		_check(MatchRules.parse(bad).is_empty(), "malformed rules are refused: " + str(bad))


func _check_labels() -> void:
	var tdm: Dictionary = MatchRules.parse({"mode": "tdm", "mutators": ["rail-only", "two-lives"], "friendly_fire": true, "lives": 2})
	_check(MatchRules.chip_text(tdm) == "TEAM DEATHMATCH // RAIL ONLY + TWO LIVES + FRIENDLY FIRE", "tdm chip: " + MatchRules.chip_text(tdm))
	_check(MatchRules.chip_text(MatchRules.parse({"mode": "ffa"})) == "FREE FOR ALL", "ffa chip")
	_check(MatchRules.chip_text(MatchRules.parse({"mode": "ctf"})) == "CAPTURE THE FLAG", "ctf chip")
	_check(MatchRules.chip_text({}) == "", "no rules, no chip")
	for mutator: String in MatchRules.MUTATORS:
		var chip: String = MatchRules.chip_text(MatchRules.parse({"mode": "ffa", "mutators": [mutator]}))
		_check(not chip.contains("MUTATOR_"), "every mutator has a label: " + chip)
	_check(MatchRules.team_score_line({"union": 3.0, "coalition": 5}) == "UNION 3 : 5 FREE COALITION", "side score line")
	for bad: Variant in [null, {}, {"union": -1, "coalition": 0}, {"union": 1.5, "coalition": 0}, {"union": "3", "coalition": 1}]:
		_check(MatchRules.team_score_line(bad) == "", "bad side scores show nothing: " + str(bad))
	_check(MatchRules.team_short("union") == "UNION" and MatchRules.team_short("coalition") == "FREE", "side chips")
	_check(MatchRules.team_name("coalition") == "The Free Coalition", "side name")
	_check(MatchRules.valid_team("union") == "union" and MatchRules.valid_team("office") == "" and MatchRules.valid_team(3) == "", "only two sides")
	_check(MatchRules.team_label_color("union") == MatchRules.UNION_LABEL and MatchRules.team_label_color("coalition") == MatchRules.COALITION_LABEL, "side colours")
	_check(MatchRules.team_body_color("union").get_luminance() < MatchRules.team_body_color("coalition").get_luminance(), "Union plate darker than coalition bone")


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
	for bad: Dictionary in [{}, {"kind": "ace"}, {"kind": "first_blood", "variant": 3}, {"kind": "first_blood", "variant": -1}, {"kind": 4}]:
		_check(MatchRules.reaction_line(bad) == "", "unknown reactions stay silent: " + str(bad))


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
	var round_line: Label = hud.get("round_label")
	_check(chip.get_parent() == round_line.get_parent() and chip.get_index() == round_line.get_index() + 1, "mode chip follows the round line in the HUD stack")
	hud.call("set_match_rules", MatchRules.parse({"mode": "tdm", "mutators": ["rail-only"]}))
	hud.call("set_team_scores", {"union": 3, "coalition": 5})
	hud.call("sync_scores_from_players", [
		{"name": "Dead Air Dan", "score": 2, "team": "union"},
		{"name": "Nightfall", "score": 4, "team": "coalition", "behavior": "Defensive"},
		{"name": "Static Kid", "score": 1, "team": "coalition"},
	])
	_check(chip.visible and chip.text == "TEAM DEATHMATCH // RAIL ONLY\nUNION 3 : 5 FREE COALITION", "mode chip carries the rules and the side score: " + chip.text)
	var board: String = hud.get("scoreboard").text
	var lines: PackedStringArray = board.strip_edges().split("\n")
	_check(lines.size() == 4, "side score plus three rows: " + board)
	_check(lines[0] == "UNION 3 : 5 FREE COALITION", "side score leads the scoreboard: " + lines[0])
	_check(lines[1] == "1.*[FREE] Nightfall [DEF]: 4", "leader row carries the side chip: " + lines[1])
	_check(lines[2] == "2. [UNION] Dead Air Dan: 2", "second row: " + lines[2])
	hud.call("set_match_rules", MatchRules.parse({"mode": "ctf", "mutators": []}))
	hud.call("set_league_identity", "Contested Frequency", "Arena Duel")
	var league_line: String = hud.get("mode_label").text
	_check(league_line.begins_with("CONTESTED FREQUENCY") and not league_line.contains("ARENA DUEL"), "ctf does not advertise the older arena playlist: " + league_line)
	var flags: Array = [
		{"team": "union", "status": "carried", "carrier": "a1"},
		{"team": "coalition", "status": "dropped", "return_ticks": 39, "position": [10.0, 0.0, -10.0]},
	]
	hud.call("set_ctf_state", flags, {"union": 1.0, "coalition": 2.0}, 3.0,
		[{"id": "a1", "name": "Dead Air Dan", "x": 0.0, "y": 0.0, "z": 0.0}], "a1")
	_check(chip.text.contains("CAPTURES U 1 : 2 FREE / 3 TO WIN"), "ctf score and win target: " + chip.text)
	_check(chip.text.contains("UNION FLAG CARRIED BY Dead Air Dan  //  FREE FLAG DOWN 2S, 14M NE"), "carrier and dropped bearing: " + chip.text)
	_check(hud.get("scoreboard").text.begins_with("FRAGS (CAPTURES WIN)"), "fighter frag rows are secondary to captures")
	await process_frame
	var ctf_chip_bounds: Rect2 = chip.get_global_rect()
	var ctf_panel_bounds: Rect2 = hud.get_node("Panel").get_global_rect()
	_check(ctf_chip_bounds.end.x <= ctf_panel_bounds.end.x and ctf_chip_bounds.end.y <= ctf_panel_bounds.end.y, "ctf status fits inside the HUD panel")
	var home_flags: Array = [
		{"team": "union", "status": "carried", "carrier": "a1", "stand": [-70.0, 0.0, 0.0], "position": [0.0, 0.0, 0.0]},
		{"team": "coalition", "status": "home", "stand": [70.0, 0.0, 0.0], "position": [70.0, 0.0, 0.0]},
	]
	hud.call("set_ctf_state", home_flags, {"union": 1.0, "coalition": 2.0}, 3.0, [
		{"id": "a1", "name": "Dead Air Dan", "team": "coalition", "x": 0.0, "y": 0.0, "z": 0.0},
		{"id": "b2", "name": "Nightfall", "team": "union", "x": 0.0, "y": 0.0, "z": -14.0},
	], "a1")
	_check(chip.text.contains("UNION FLAG CARRIED BY Dead Air Dan  //  FREE FLAG HOME 70M E"), "carrier return bearing: " + chip.text)
	hud.call("set_ctf_state", home_flags, {"union": 1.0, "coalition": 2.0}, 3.0, [
		{"id": "a1", "name": "Dead Air Dan", "team": "coalition", "x": 0.0, "y": 0.0, "z": 0.0},
		{"id": "b2", "name": "Nightfall", "team": "union", "x": 0.0, "y": 0.0, "z": -14.0},
	], "b2")
	_check(chip.text.contains("UNION FLAG CARRIED BY Dead Air Dan, 14M S  //  FREE FLAG HOME"), "chase bearing: " + chip.text)
	await process_frame
	var compass_bounds: Rect2 = chip.get_global_rect()
	_check(compass_bounds.end.x <= ctf_panel_bounds.end.x and compass_bounds.end.y <= ctf_panel_bounds.end.y, "a compass line still fits the HUD panel")
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
	var panel_bounds: Rect2 = hud.get_node("Panel").get_global_rect()
	_check(chip.text.contains("RAIL ONLY") and chip.text.contains("TWO LIVES") and chip.text.contains("LIVES 2"), "combined rules and lives stay in the chip")
	_check(chip_bounds.end.x <= panel_bounds.end.x and chip_bounds.end.y <= panel_bounds.end.y, "combined rule chip fits inside the HUD panel")
	hud.call("set_match_rules", MatchRules.parse({"mode": "ffa", "mutators": ["two-lives"], "lives": 2}))
	hud.call("set_own_lives", 1)
	_check(chip.text == "FREE FOR ALL // TWO LIVES\nLIVES 1", "lives line under two lives: " + chip.text)
	hud.call("set_own_lives", 0)
	_check(chip.text.ends_with("OUT OF LIVES. WATCHING UNTIL THE ROUND ENDS."), "an eliminated player is told why: " + chip.text)
	hud.call("sync_scores_from_players", [{"name": "Dead Air Dan", "score": 2}])
	_check(not hud.get("scoreboard").text.contains("[UNION]"), "free-for-all rows carry no side")
	hud.call("show_host_reaction", {"kind": "golden_rail", "variant": 2, "player": "Aunt Linda"})
	hud.call("set_match_rules", {})
	_check(not chip.visible, "a campaign map clears the chip")
	hud.call("set_followed_weapon", "Rail", "Nightfall", "", "coalition")
	var follow: Label = hud.get("weapon_label")
	_check(follow.text.begins_with("[FREE] FOLLOWING: Nightfall"), "spectators see the followed side: " + follow.text)
	hud.queue_free()
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
	_check(body.modulate.get_luminance() > 0.85, "coalition body reads bone: " + str(body.modulate))
	state.erase("team")
	state["golden"] = true
	pawn.call("update_state", state, 3)
	_check(pawn.get("player_color") == own, "a sideless fighter keeps its own colour")
	_check(label.modulate == MatchRules.GOLD, "the golden holder's plate glows gold")
	_check(body.modulate.r > body.modulate.b, "the golden holder's body glows warm")
	pawn.queue_free()
	await process_frame
