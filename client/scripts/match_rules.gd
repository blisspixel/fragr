class_name MatchRules
extends RefCounted

## The server's rule set as the client shows it: validation of
## `map_info.rules`, the mode chip, team colours and names, the side score
## line and the Host's keyed reactions. The server decides every outcome;
## this only reads and labels what it sent.

const MODES: Array[String] = ["ffa", "tdm"]
const MUTATORS: Array[String] = ["rail-only", "shotgun-only", "fists-only", "licence-to-kill", "golden-rail", "two-lives"]
const TEAMS: Array[String] = ["union", "coalition"]
const REACTIONS: Array[String] = ["first_blood", "streak_ended", "last_standing", "comeback", "golden_rail"]
const REACTION_VARIANTS: int = 3
const MAX_LIVES: int = 9

## Union: black cloth, plates one step lighter, red optics. The label carries
## the red so a dark body still reads as a side.
const UNION_LABEL: Color = Color("e23430")
const UNION_BODY: Color = Color("56575e")
## Free coalition: bone, leather and ember.
const COALITION_LABEL: Color = Color("dc8c3c")
const COALITION_BODY: Color = Color("e8e2d6")
const GOLD: Color = Color(1.0, 0.82, 0.28)


## A validated copy of `map_info.rules`, or empty when absent or malformed.
## Unknown mutator ids from a newer server are dropped rather than shown raw.
static func parse(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var raw: Dictionary = value
	var mode: Variant = raw.get("mode")
	if not mode is String or not MODES.has(mode):
		return {}
	var listed: Variant = raw.get("mutators", [])
	if not listed is Array:
		return {}
	var mutators: Array[String] = []
	for item: Variant in listed:
		if item is String and MUTATORS.has(item) and not mutators.has(item):
			mutators.append(item)
	var friendly_fire: Variant = raw.get("friendly_fire", false)
	if not friendly_fire is bool:
		return {}
	var lives: int = 0
	var raw_lives: Variant = raw.get("lives")
	if raw_lives != null:
		if not (raw_lives is int or raw_lives is float):
			return {}
		var number: float = float(raw_lives)
		if number != floorf(number) or number < 1.0 or number > float(MAX_LIVES):
			return {}
		lives = int(number)
	return {"mode": mode, "mutators": mutators, "friendly_fire": friendly_fire, "lives": lives}


static func teams(rules: Dictionary) -> bool:
	return rules.get("mode", "") == "tdm"


static func _text(key: String) -> String:
	return str(TranslationServer.translate(key))


static func _key(prefix: String, id: String) -> String:
	return prefix + id.to_upper().replace("-", "_")


## One line naming the mode and every mutator, for the chip every viewer sees.
static func chip_text(rules: Dictionary) -> String:
	if rules.is_empty():
		return ""
	var parts: PackedStringArray = []
	for mutator: String in rules.get("mutators", []):
		parts.append(_text(_key("MUTATOR_", mutator)))
	if rules.get("friendly_fire", false):
		parts.append(_text("RULES_FRIENDLY_FIRE"))
	var line: String = _text(_key("MODE_", str(rules["mode"])))
	if not parts.is_empty():
		line += " // " + " + ".join(parts)
	return line


static func valid_team(team: Variant) -> String:
	return team if team is String and TEAMS.has(team) else ""


static func team_name(team: String) -> String:
	return _text(_key("TEAM_", team)) if TEAMS.has(team) else ""


static func team_short(team: String) -> String:
	return _text(_key("TEAM_", team) + "_SHORT") if TEAMS.has(team) else ""


static func team_label_color(team: String) -> Color:
	match team:
		"union":
			return UNION_LABEL
		"coalition":
			return COALITION_LABEL
	return Color.WHITE


static func team_body_color(team: String) -> Color:
	match team:
		"union":
			return UNION_BODY
		"coalition":
			return COALITION_BODY
	return Color.WHITE


static func _count(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	var number: float = float(value)
	if number != floorf(number) or number < 0.0 or number > 1000000.0:
		return -1
	return int(number)


## "UNION 12 : 9 FREE COALITION", or empty when the scores are absent or bad.
static func team_score_line(scores: Variant) -> String:
	if not scores is Dictionary:
		return ""
	var union: int = _count(scores.get("union"))
	var coalition: int = _count(scores.get("coalition"))
	if union < 0 or coalition < 0:
		return ""
	return _text("TEAM_SCORE_LINE").format({"union": union, "coalition": coalition})


## The Host's words for a `host_reaction` event, or empty for an unknown one.
static func reaction_line(data: Dictionary) -> String:
	var kind: Variant = data.get("kind")
	if not kind is String or not REACTIONS.has(kind):
		return ""
	var variant: int = _count(data.get("variant", 0))
	if variant < 0 or variant >= REACTION_VARIANTS:
		return ""
	var key: String = "HOST_REACTION_%s_%d" % [str(kind).to_upper(), variant]
	var line: String = _text(key)
	if line == key:
		return ""
	var player: Variant = data.get("player")
	var other: Variant = data.get("other")
	return line.format({
		"player": str(player).to_upper() if player is String else "",
		"other": str(other).to_upper() if other is String else "",
		"team": team_name(valid_team(data.get("team"))).to_upper(),
	})


## Scoreboard rows as text: side score first in a team mode, then the top
## fighters with their side chip.
static func scoreboard_text(rows: Array, sides: Dictionary, score_line: String, limit: int) -> String:
	var text: String = ""
	if score_line != "":
		text += score_line + "\n"
	for i: int in range(mini(limit, rows.size())):
		var row: Dictionary = rows[i]
		var name: String = str(row.get("name", "?"))
		var kills: int = int(row.get("kills", 0))
		var chip: String = str(row.get("chip", ""))
		var side: String = team_short(str(sides.get(name, "")))
		var marker: String = "*" if i == 0 and kills > 0 else " "
		var tag: String = "[" + side + "] " if side != "" else ""
		text += str(i + 1) + "." + marker + tag + name + chip + ": " + str(kills) + "\n"
	return text
