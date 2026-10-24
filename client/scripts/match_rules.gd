class_name MatchRules
extends RefCounted

## The server's rule set as the client shows it: validation of
## `map_info.rules`, the mode chip, team colours and names, the side score
## line and the Host's keyed reactions. The server decides every outcome;
## this only reads and labels what it sent.

const MODES: Array[String] = ["ffa", "tdm", "ctf", "sabotage", "conquest"]
const MUTATORS: Array[String] = ["rail-only", "shotgun-only", "fists-only", "licence-to-kill", "golden-rail", "two-lives"]
const TEAMS: Array[String] = ["union", "coalition"]
const REACTIONS: Array[String] = ["first_blood", "streak_ended", "last_standing", "comeback", "golden_rail", "larak_lot_special"]
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
## First person reads sides relative to the viewer. The faction colours stay
## on the score and on a spectator's plate.
const OURS_MARK: Color = Color("f4f0e6")
const THEIRS_MARK: Color = Color("e23430")


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
	return ["tdm", "ctf", "sabotage", "conquest"].has(rules.get("mode", ""))


static func _text(key: String) -> String:
	return str(TranslationServer.translate(key))


static func _key(prefix: String, id: String) -> String:
	return prefix + id.to_upper().replace("-", "_")


## One line naming the mode and every mutator, for the chip every viewer sees.
static func chip_text(rules: Dictionary) -> String:
	if rules.is_empty():
		return ""
	var details: String = modifier_text(rules)
	return mode_text(rules) + (" // " + details if not details.is_empty() else "")

static func mode_text(rules: Dictionary) -> String:
	return _text(_key("MODE_", str(rules["mode"]))) if not rules.is_empty() else ""

static func modifier_text(rules: Dictionary) -> String:
	var parts: PackedStringArray = []
	for mutator: String in rules.get("mutators", []):
		parts.append(_text(_key("MUTATOR_", mutator)))
	if rules.get("friendly_fire", false):
		parts.append(_text("RULES_FRIENDLY_FIRE"))
	return " + ".join(parts)


static func valid_team(team: Variant) -> String:
	return team if team is String and TEAMS.has(team) else ""


static func team_name(team: String) -> String:
	return _text(_key("TEAM_", team)) if TEAMS.has(team) else ""


static func team_short(team: String) -> String:
	return _text(_key("TEAM_", team) + "_SHORT") if TEAMS.has(team) else ""


const UNION_PLATE_DARK: Color = Color("8c1a1e")
const UNION_SHAPE_MARK: String = "■"
const COALITION_SHAPE_MARK: String = "□"


static func team_shape_mark(team: String) -> String:
	match team:
		"union":
			return UNION_SHAPE_MARK
		"coalition":
			return COALITION_SHAPE_MARK
	return ""


static func team_label_color(team: String, high_contrast: bool = false) -> Color:
	match team:
		"union":
			return UNION_LABEL
		"coalition":
			return Color("e8e2d6") if high_contrast else COALITION_LABEL
	return Color.WHITE


## "mate" when both sides match, "foe" when they differ, empty when either
## side is missing. The server still decides who may be damaged.
static func team_relation(viewer: String, other: String) -> String:
	if not TEAMS.has(viewer) or not TEAMS.has(other):
		return ""
	return "mate" if viewer == other else "foe"


static func relation_mark(relation: String) -> String:
	match relation:
		"mate":
			return _text("TEAM_OURS")
		"foe":
			return _text("TEAM_THEIRS")
	return ""


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
## fighters with their side chip. `you` marks the local callsign on the
## hold-Tab board. The corner list leaves it empty and stays on frags.
## `detailed` is the hold-Tab board, including a spectator whose name is
## not on a row.
static func scoreboard_text(rows: Array, sides: Dictionary, score_line: String, limit: int, you: String = "", detailed: bool = false) -> String:
	var text: String = ""
	if score_line != "":
		text += score_line + "\n"
	if detailed:
		text += _text("HUD_BOARD_COLUMNS") + "\n"
	for i: int in range(mini(limit, rows.size())):
		var row: Dictionary = rows[i]
		var accepted: Dictionary = row.duplicate()
		if not accepted.has("team"):
			accepted.team = sides.get(str(row.get("name", "")), "")
		var unique: int = 0
		for candidate: Dictionary in rows:
			if candidate.get("name") == you:
				unique += 1
		text += scoreboard_row(accepted, i, detailed, not you.is_empty() and unique == 1 and row.get("name") == you) + "\n"
	return text

static func scoreboard_row(row: Dictionary, index: int, detailed: bool, own: bool = false) -> String:
	var name: String = str(row.get("name", "?"))
	var kills: int = int(row.get("kills", 0))
	var side: String = team_short(valid_team(row.get("team")))
	var marker: String = "*" if index == 0 and kills > 0 else " "
	var tag: String = "[" + side + "] " if not side.is_empty() else ""
	var prefix: String = str(index + 1) + "." + marker + tag + name + str(row.get("chip", "")) + ": " + str(kills)
	if detailed:
		prefix += " frag, " + str(int(row.get("deaths", 0))) + " died, hit " + _rate(int(row.get("connects", 0)), int(row.get("attacks", 0))) + ", head " + _rate(int(row.get("heads", 0)), int(row.get("connects", 0))) + ", " + str(int(row.get("damage", 0))) + " dealt"
	return prefix + ("  YOU" if own else "")

static func _rate(numerator: int, denominator: int) -> String:
	var label: String = PlayerRecord.percent_label(numerator, denominator)
	if label == "":
		return "-"
	# The count sits beside the percent. 100.0 on one shot is not 100.0 on a hundred.
	return label + " (" + str(numerator) + "/" + str(denominator) + ")"
