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
	var ffa: Dictionary = MatchRules.parse({"mode": "ffa", "name": "Free-for-all"})
	_check(ffa.get("mutators") == [] and ffa.get("lives") == 0 and not MatchRules.teams(ffa), "plain ffa parses with defaults")
	for bad: Variant in [null, "tdm", {}, {"mode": "ctf"}, {"mode": 1}, {"mode": "ffa", "mutators": "rail-only"},
			{"mode": "ffa", "friendly_fire": "yes"}, {"mode": "ffa", "lives": 0}, {"mode": "ffa", "lives": 1.5},
			{"mode": "ffa", "lives": 99}, {"mode": "ffa", "lives": "2"}]:
		_check(MatchRules.parse(bad).is_empty(), "malformed rules are refused: " + str(bad))


func _check_labels() -> void:
	var tdm: Dictionary = MatchRules.parse({"mode": "tdm", "mutators": ["rail-only", "two-lives"], "friendly_fire": true, "lives": 2})
	_check(MatchRules.chip_text(tdm) == "TEAM DEATHMATCH // RAIL ONLY + TWO LIVES + FRIENDLY FIRE", "tdm chip: " + MatchRules.chip_text(tdm))
	_check(MatchRules.chip_text(MatchRules.parse({"mode": "ffa"})) == "FREE FOR ALL", "ffa chip")
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
	hud.call("set_own_lives", 2)
	_check(not chip.text.contains("LIVES"), "no lives line without limited lives")
	hud.call("set_match_rules", MatchRules.parse({"mode": "ffa", "mutators": ["two-lives"], "lives": 2}))
	hud.call("set_own_lives", 1)
	_check(chip.text == "FREE FOR ALL // TWO LIVES\nLIVES 1", "lives line under two lives: " + chip.text)
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
