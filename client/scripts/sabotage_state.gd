class_name SabotageState
extends RefCounted

## Sabotage as the client reads it: strict validation of `map_info.sabotage`
## and `snapshot.sabotage`, and the words the HUD and feed show. The server
## decides every plant, defuse and round; this only checks and labels.

const FORMATS: Array[String] = ["short", "match"]
const PHASES: Array[String] = ["muster", "live", "planted", "over"]
const CHARGE_STATUSES: Array[String] = ["carried", "dropped", "planted", "defused", "detonated"]
const SITES: Array[String] = ["a", "b"]
const PROGRESS: Array[String] = ["plant", "defuse"]
const EVENTS: Array[String] = [
	"live", "charge_taken", "charge_dropped", "plant_started", "plant_interrupted", "planted",
	"defuse_started", "defuse_interrupted", "defused", "detonated", "sides_swapped",
]
const REASONS: Array[String] = ["elimination", "detonation", "defused", "time"]
const MAX_CALLOUTS: int = 32
const MAX_CALLOUT_ID: int = 32
const ATTACKERS: String = "coalition"
const TICKS_PER_SECOND: int = 20
## The server's defuse reach, horizontally, for the prompt only.
const DEFUSE_REACH: float = 1.75


## Membership that tolerates any Variant: a typed array refuses a null probe.
static func _one_of(options: Array[String], value: Variant) -> bool:
	return value is String and options.has(value)


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and absf(float(value)) <= 1000000.0


static func _count(value: Variant, high: int) -> int:
	if not (value is int or value is float):
		return -1
	var number: float = float(value)
	if number != floorf(number) or number < 0.0 or number > float(high):
		return -1
	return int(number)


static func _point(value: Variant, size: int) -> bool:
	if not value is Array or value.size() != size:
		return false
	for component: Variant in value:
		if not _number(component):
			return false
	return true


static func _sides(value: Variant, high: int) -> bool:
	if not value is Dictionary:
		return false
	for side: String in MatchRules.TEAMS:
		if _count(value.get(side), high) < 0:
			return false
	return true


static func _callout_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > MAX_CALLOUT_ID:
		return false
	for character: String in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "_"):
			return false
	return true


## Empty when `map_info.sabotage` is absent or well formed.
static func map_error(info: Dictionary) -> String:
	var layout: Variant = info.get("sabotage")
	if layout == null:
		return ""
	if not layout is Dictionary:
		return "invalid sabotage layout"
	if layout.get("attackers") != ATTACKERS:
		return "invalid sabotage attackers"
	var sites: Variant = layout.get("sites")
	if not sites is Array or sites.size() != 2:
		return "invalid sabotage sites"
	for i: int in range(2):
		var site: Variant = sites[i]
		if not site is Dictionary or site.get("id") != SITES[i] or not _point(site.get("center"), 3):
			return "invalid sabotage site"
		var radius: Variant = site.get("radius")
		if not _number(radius) or float(radius) < 1.0 or float(radius) > 8.0:
			return "invalid sabotage plant radius"
	var callouts: Variant = layout.get("callouts", [])
	if not callouts is Array or callouts.size() > MAX_CALLOUTS:
		return "invalid sabotage callouts"
	for callout: Variant in callouts:
		if not callout is Dictionary or not _callout_id(callout.get("id")):
			return "invalid sabotage callout"
		if not _point(callout.get("min"), 2) or not _point(callout.get("max"), 2):
			return "invalid sabotage callout bounds"
		if float(callout["min"][0]) >= float(callout["max"][0]) or float(callout["min"][1]) >= float(callout["max"][1]):
			return "invalid sabotage callout bounds"
	return ""


## Empty when `snapshot.sabotage` is absent or well formed.
static func snapshot_error(snapshot: Dictionary) -> String:
	var state: Variant = snapshot.get("sabotage")
	if state == null:
		return ""
	if not state is Dictionary:
		return "invalid sabotage state"
	if not _one_of(FORMATS, state.get("format")) or not _one_of(PHASES, state.get("phase")):
		return "invalid sabotage phase"
	if _count(state.get("round"), 100000) < 1 or _count(state.get("period"), 100000) < 0:
		return "invalid sabotage round"
	var half: int = _count(state.get("half"), 2)
	if half < 1 or _count(state.get("half_rounds"), 1000) < 1 or _count(state.get("rounds_to_win"), 100000) < 1:
		return "invalid sabotage half"
	if not _sides(state.get("score"), 100000) or not _sides(state.get("alive"), 64):
		return "invalid sabotage score"
	if _count(state.get("clock_ticks"), 1000000) < 0:
		return "invalid sabotage clock"
	var swap: Variant = state.get("swap_after", false)
	if not swap is bool:
		return "invalid sabotage swap"
	var charge: Variant = state.get("charge")
	if charge != null:
		if not charge is Dictionary or not _one_of(CHARGE_STATUSES, charge.get("status")) or not _point(charge.get("position"), 3):
			return "invalid sabotage charge"
		var carrier: Variant = charge.get("carrier")
		var carried: bool = charge["status"] == "carried"
		if carried != (carrier is String and not carrier.is_empty()) or (not carried and carrier != null):
			return "invalid sabotage carrier"
		var site: Variant = charge.get("site")
		var placed: bool = ["planted", "defused", "detonated"].has(charge["status"])
		if placed != _one_of(SITES, site) or (not placed and site != null):
			return "invalid sabotage charge site"
	var progress: Variant = state.get("progress")
	if progress != null:
		if not progress is Dictionary or not _one_of(PROGRESS, progress.get("kind")) or not _one_of(SITES, progress.get("site")):
			return "invalid sabotage progress"
		if not progress.get("player_id") is String or str(progress["player_id"]).is_empty():
			return "invalid sabotage progress"
		var needed: int = _count(progress.get("needed"), 100000)
		var ticks: int = _count(progress.get("ticks"), 100000)
		if needed < 1 or ticks < 0 or ticks > needed:
			return "invalid sabotage progress"
	return ""


## `M:SS` from ticks, rounding up so the last second still shows 0:01.
static func clock_text(ticks: int) -> String:
	var seconds: int = ceili(float(maxi(ticks, 0)) / float(TICKS_PER_SECOND))
	return "%d:%02d" % [seconds / 60, seconds % 60]


static func _text(key: String) -> String:
	return str(TranslationServer.translate(key))


## The single HUD line: round, the viewer's job, the score and the clock. A
## `prompt` (hold Use to plant or defuse) takes the clock's place, so the line
## stays one line.
static func hud_line(state: Dictionary, viewer_team: String, prompt: String = "") -> String:
	if state.is_empty():
		return ""
	var phase: String = str(state.get("phase", ""))
	var score: Dictionary = state.get("score", {})
	var job: String = ""
	if viewer_team == ATTACKERS:
		job = _text("SABOTAGE_JOB_ATTACK")
	elif viewer_team == "union":
		job = _text("SABOTAGE_JOB_DEFEND")
	var clock: String = clock_text(int(state.get("clock_ticks", 0)))
	var key: String = "SABOTAGE_LINE_" + phase.to_upper()
	if job.is_empty():
		key += "_WATCH"
	elif not prompt.is_empty():
		key = "SABOTAGE_LINE_PROMPT"
		clock = prompt
	return _text(key).format({
		"round": int(state.get("round", 1)),
		"job": job,
		"union": int(score.get("union", 0)),
		"coalition": int(score.get("coalition", 0)),
		"clock": clock,
	})


## The Use prompt for a joined fighter at `feet`: the carrier inside a plant
## area, or a defender at the planted charge. Empty otherwise. Words only; the
## server decides whether a plant or defuse actually starts.
static func use_prompt(state: Dictionary, layout: Dictionary, viewer_id: String, viewer_team: String, feet: Vector3) -> String:
	var charge: Variant = state.get("charge")
	if not charge is Dictionary or viewer_id.is_empty():
		return ""
	if state.get("phase") == "live" and charge.get("status") == "carried" and str(charge.get("carrier", "")) == viewer_id:
		for site: Variant in layout.get("sites", []):
			if not site is Dictionary or not _point(site.get("center"), 3):
				continue
			var centre: Array = site["center"]
			if Vector2(feet.x - float(centre[0]), feet.z - float(centre[2])).length() <= float(site.get("radius", 0.0)):
				return _text("SABOTAGE_PROMPT_PLANT")
	if state.get("phase") == "planted" and viewer_team == "union" and charge.get("status") == "planted":
		var at: Array = charge.get("position", [])
		if _point(at, 3) and Vector2(feet.x - float(at[0]), feet.z - float(at[2])).length() <= DEFUSE_REACH:
			return _text("SABOTAGE_PROMPT_DEFUSE")
	return ""


## Fraction of a held Use done, 0 to 1, or -1 without one.
static func progress_fraction(state: Dictionary) -> float:
	var progress: Variant = state.get("progress")
	if not progress is Dictionary:
		return -1.0
	return clampf(float(progress.get("ticks", 0)) / maxf(float(progress.get("needed", 1)), 1.0), 0.0, 1.0)


## The charge's remaining share of its clock while planted, or -1.
static func charge_fraction(state: Dictionary, charge_ticks: int) -> float:
	if state.get("phase") != "planted":
		return -1.0
	return clampf(float(state.get("clock_ticks", 0)) / maxf(float(charge_ticks), 1.0), 0.0, 1.0)


## Whether this viewer may see where the charge is carried: the attack and
## spectators, never the defence.
static func shows_carrier(viewer_team: String) -> bool:
	return viewer_team != "union"


## The corner line for a `sabotage` event, or empty when it is not for this
## viewer or not worth a line. Carrier moves are told only to the attack.
static func event_line(data: Dictionary, viewer_team: String, layout: Dictionary = {}) -> String:
	var kind: Variant = data.get("kind")
	if not kind is String or not _one_of(EVENTS, kind):
		return ""
	if kind in ["plant_interrupted", "defuse_interrupted", "sides_swapped"]:
		return ""
	if kind in ["charge_taken", "charge_dropped"] and not shows_carrier(viewer_team):
		return ""
	var site: Variant = data.get("site")
	return _text("SABOTAGE_EVENT_" + str(kind).to_upper()).format({
		"player": str(data.get("player", "")).to_upper(),
		"site": site_name(str(site), layout) if _one_of(SITES, site) else "",
	})

## Site identity comes from the registered callout at the accepted plant centre.
static func site_name(site_id: String, layout: Dictionary = {}) -> String:
	for site: Dictionary in layout.get("sites", []):
		if site.get("id") == site_id and _point(site.get("center"), 3):
			var center: Array = site["center"]
			var callout: String = callout_at(layout, float(center[0]), float(center[2]))
			if callout in ["clinic_steps", "tram_stop"]:
				return _text("SABOTAGE_SITE_" + callout.to_upper())
	return _text("SABOTAGE_SITE_" + site_id.to_upper())


## The round card for a Sabotage `round_end`, or empty when malformed.
static func result_text(data: Dictionary, viewer_team: String) -> String:
	var result: Variant = data.get("sabotage")
	if not result is Dictionary or not _one_of(REASONS, result.get("reason")) or not _sides(result.get("score"), 100000):
		return ""
	var winner: String = MatchRules.valid_team(data.get("winning_team"))
	if winner.is_empty():
		return ""
	var score: Dictionary = result["score"]
	var lines: PackedStringArray = []
	lines.append(_text("SABOTAGE_ROUND_WINNER").format({
		"team": MatchRules.team_name(winner).to_upper(),
		"round": int(result.get("round", 1)),
	}))
	lines.append(_text("SABOTAGE_REASON_" + str(result["reason"]).to_upper()))
	lines.append(_text("SABOTAGE_ROUND_SCORE").format({"union": int(score["union"]), "coalition": int(score["coalition"])}))
	if result.get("match_over", false) == true:
		var match_winner: String = MatchRules.valid_team(result.get("match_winner"))
		if match_winner.is_empty():
			lines.append(_text("SABOTAGE_MATCH_DRAW"))
		else:
			lines.append(_text("SABOTAGE_MATCH_WINNER").format({"team": MatchRules.team_name(match_winner).to_upper()}))
	elif result.get("sides_swap", false) == true:
		lines.append(_text("SABOTAGE_SWAP_NEXT"))
	if not viewer_team.is_empty():
		lines.append(_text("SABOTAGE_YOU_WON" if viewer_team == winner else "SABOTAGE_YOU_LOST"))
	return "\n".join(lines)


## The callout id for a point, or empty: the first region that contains it.
static func callout_at(layout: Dictionary, x: float, z: float) -> String:
	for callout: Variant in layout.get("callouts", []):
		if not callout is Dictionary:
			continue
		var low: Array = callout.get("min", [])
		var high: Array = callout.get("max", [])
		if low.size() == 2 and high.size() == 2 and x >= float(low[0]) and x <= float(high[0]) and z >= float(low[1]) and z <= float(high[1]):
			return str(callout.get("id", ""))
	return ""
