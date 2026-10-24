class_name M20MissionState
extends RefCounted

## Local Exception facts bind the waterworks crossing, the pier hold clock,
## the refuge barricade and the reprieve to the accepted map. Validation
## grants no local authority: the countdown is derived from server ticks.
const MAP_ID: int = 1020
const OBJECTIVES: Array[String] = [
	"sluice_crossing",
	"crew_crossing",
	"pier_arrival",
	"pier_hold",
	"last_six",
]
const DEPARTURE_OBJECTIVE_ID: String = "party_departed"
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const CREW: int = 3
const CREW_PHASES: Array[String] = ["working", "crossing", "arrived"]
const SIX_MINUTES: int = 7200
const REFUGE_INTEGRITY: int = 100
const REFUGE_BASE: int = 400
const MAX_FREED: int = 400
const CONTROL_KINDS: Array[String] = ["m20_crossing_control"]

static func map_error(info: Dictionary) -> String:
	if not MapGeometry.validation_error(info).is_empty() or info.get("map_id") != MAP_ID \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	for key: String in ["mission", "m02_objectives", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12", "m13", "m14", "m15", "m16", "m17", "m18"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and info["m02_side_ward"] != false:
		return MissionState.INVALID
	var g: Variant = info.get("m20")
	if not M03MissionState._exact(g, ["objectives", "departure", "boarding", "refuge_line", "harbour_display", "breath_ticks", "turn_ticks", "hold_ticks", "gate_open"]) \
		or not g["gate_open"] is bool or not g["objectives"] is Array or g["objectives"].size() != OBJECTIVES.size():
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	var decorations: Array = info["presentation"]["decorations"]
	for index: int in range(OBJECTIVES.size()):
		if not M06MissionState._arrival(g["objectives"][index], OBJECTIVES[index], half):
			return MissionState.INVALID
	if not M03MissionState._region(g["boarding"], half) or not M03MissionState._region(g["refuge_line"], half) \
		or not M04MissionState._control(g["departure"], decorations, half, CONTROL_KINDS) \
		or not M03MissionState._inside(g["departure"]["approach"], g["boarding"]):
		return MissionState.INVALID
	if not EquipmentState.integer(g["harbour_display"], decorations.size() - 1) \
		or decorations[int(g["harbour_display"])].get("kind") != "m20_harbour_display":
		return MissionState.INVALID
	for key: String in ["breath_ticks", "turn_ticks", "hold_ticks"]:
		if not EquipmentState.integer(g[key], 24000):
			return MissionState.INVALID
	var breath: int = int(g["breath_ticks"])
	var turn: int = int(g["turn_ticks"])
	var hold: int = int(g["hold_ticks"])
	if breath < 200 or breath > 1200 or turn < 600 or turn >= hold or hold - turn != SIX_MINUTES:
		return MissionState.INVALID
	return ""

static func geometry_for(info: Dictionary) -> Dictionary:
	return {
		"id": MissionState.M20_ID,
		"map_id": MAP_ID,
		"half_extent": float(info["half_extent"]),
		"m20": info["m20"].duplicate(true),
		"solids": info["solids"].duplicate(true),
		"presentation": info["presentation"].duplicate(true)
	}

## The static contract: only the gate may open between accepted maps.
static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M20_ID or second.get("id") != MissionState.M20_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or not first.get("m20") is Dictionary or not second.get("m20") is Dictionary:
		return false
	if first["m20"]["gate_open"] and not second["m20"]["gate_open"]:
		return false
	var before: Dictionary = first["m20"].duplicate(true)
	var after: Dictionary = second["m20"].duplicate(true)
	before.erase("gate_open")
	after.erase("gate_open")
	return before == after

## (clock start, turn, reprieve) ticks from the quay arrival, or empty.
static func clock(geometry: Dictionary, facts: Dictionary) -> Array[int]:
	var reached: Variant = facts.get("pier_reached_at")
	if reached == null or not geometry.get("m20") is Dictionary:
		return []
	var g: Dictionary = geometry["m20"]
	var start: int = int(reached) + int(g["breath_ticks"])
	return [start, start + int(g["turn_ticks"]), start + int(g["hold_ticks"])]

## Seconds left on the pier clock at `tick`, or -1 before the clock runs.
static func seconds_left(geometry: Dictionary, facts: Dictionary, tick: int) -> int:
	var spans: Array[int] = clock(geometry, facts)
	if spans.is_empty() or tick < spans[0] or facts.get("reprieve_at") != null:
		return -1
	return maxi(0, ceili(float(spans[2] - tick) / 20.0))

static func challenge_error(value: Variant) -> String:
	if not M03MissionState._exact(value, ["crew_crossed", "mark_broken", "refuge_held"]):
		return MissionState.INVALID
	for key: String in value:
		if not value[key] is bool:
			return MissionState.INVALID
	return ""

static func brief_completed(value: Dictionary, difficulty: String) -> bool:
	return value["crew_crossed"] and (difficulty == "assisted" or (value["mark_broken"] and (difficulty != "severe" or value["refuge_held"])))

static func refuge_error(value: Variant) -> String:
	if not M03MissionState._exact(value, ["persons", "edda", "splice", "orrin", "sorrel"]) \
		or not EquipmentState.integer(value["persons"], REFUGE_BASE + MAX_FREED) or int(value["persons"]) < REFUGE_BASE:
		return MissionState.INVALID
	for key: String in ["edda", "splice", "orrin", "sorrel"]:
		if not value[key] is bool:
			return MissionState.INVALID
	return ""

static func facts_error(value: Variant, geometry: Dictionary, phase: String, tick: int) -> String:
	var keys: Array[String] = ["completed", "challenges", "crew", "refuge_integrity", "display_lit", "gate_open", "refuge", "brief_completed"]
	if value is Dictionary:
		for optional: String in ["current", "pier_reached_at", "reprieve_at", "latch"]:
			if value.has(optional):
				keys.append(optional)
	if not M03MissionState._exact(value, keys):
		return MissionState.INVALID
	if not MissionState.ordered_facts_error(value, OBJECTIVES, [], phase, tick).is_empty():
		return MissionState.INVALID
	for key: String in ["display_lit", "gate_open", "brief_completed"]:
		if not value[key] is bool:
			return MissionState.INVALID
	if not challenge_error(value.get("challenges")).is_empty() or not refuge_error(value.get("refuge")).is_empty() \
		or not EquipmentState.integer(value["refuge_integrity"], REFUGE_INTEGRITY):
		return MissionState.INVALID
	var half: float = float(geometry.get("half_extent", 64.0))
	var n: int = value["completed"].size()
	if not value["crew"] is Array or value["crew"].size() != CREW:
		return MissionState.INVALID
	var crossed: bool = true
	for member: Variant in value["crew"]:
		if not M03MissionState._exact(member, ["phase", "feet"]) or not member["phase"] is String \
			or member["phase"] not in CREW_PHASES or not MissionState._point(member["feet"], half) \
			or (n < 2) != (member["phase"] == "working"):
			return MissionState.INVALID
		crossed = crossed and member["phase"] == "arrived"
	var reached: Variant = value.get("pier_reached_at")
	var reprieve: Variant = value.get("reprieve_at")
	if value["challenges"]["crew_crossed"] != crossed or value["challenges"]["refuge_held"] != (int(value["refuge_integrity"]) > 0) \
		or (n >= 3) != (reached != null) or (n >= 4) != value["display_lit"] or (n >= 5) != (reprieve != null) \
		or value.has("latch") != (reprieve != null) or (value["gate_open"] and reprieve == null):
		return MissionState.INVALID
	if reached != null and (not EquipmentState.integer(reached, tick)):
		return MissionState.INVALID
	if value.has("latch") and not MissionState._point(value["latch"], half):
		return MissionState.INVALID
	var spans: Array[int] = clock(geometry, value)
	if not spans.is_empty():
		if (value["display_lit"] and tick < spans[1]) or (reprieve != null and (not EquipmentState.integer(reprieve, tick) or int(reprieve) != spans[2])):
			return MissionState.INVALID
	if phase == "briefing" and (n != 0 or int(value["refuge_integrity"]) != REFUGE_INTEGRITY or value["challenges"]["mark_broken"]):
		return MissionState.INVALID
	if phase == "departed" and not value["gate_open"]:
		return MissionState.INVALID
	if n <= OBJECTIVES.size():
		var expected: Dictionary = geometry["m20"]["objectives"][n] if n < OBJECTIVES.size() \
			else {"id": DEPARTURE_OBJECTIVE_ID, "action": {"kind": "use", "target": geometry["m20"]["departure"]}}
		if value.get("current") != expected:
			return MissionState.INVALID
	if value["gate_open"] != geometry["m20"]["gate_open"]:
		return MissionState.INVALID
	return ""

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not message.get("state") is Dictionary:
		return MissionState.INVALID
	var value: Dictionary = message["state"]
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m20"]
	if value.has("run"):
		keys.append("run")
	if geometry.get("id") != MissionState.M20_ID or value.get("id") != MissionState.M20_ID \
		or not M03MissionState._exact(value, keys) \
		or not MissionState.valid_rules(value.get("rules")) \
		or not value.get("phase") is String or value["phase"] not in PHASES \
		or not EquipmentState.integer(value.get("attempt"), 4294967295) or int(value["attempt"]) == 0 \
		or not EquipmentState.integer(value.get("changed_at"), int(message["tick"])) \
		or not value.get("party") is Array or value["party"].size() > 4 \
		or not value.get("prompts") is Array or value["prompts"].size() > value["party"].size():
		return MissionState.INVALID
	if value.has("run") and not MissionState.valid_run(value):
		return MissionState.INVALID
	if not previous.is_empty() and (int(value["attempt"]) < int(previous["state"]["attempt"]) \
		or int(message["tick"]) < int(previous["tick"]) or value["rules"] != previous["state"]["rules"] \
		or not MissionState.run_follows(value.get("run"), previous["state"].get("run"))):
		return MissionState.INVALID
	var party: Dictionary = {}
	var all_aboard: bool = not value["party"].is_empty()
	for member: Variant in value["party"]:
		if not member is Dictionary or member.size() != 5 or not MissionState._uuid(member.get("id")) \
			or party.has(member["id"]) or not member.get("name") is String \
			or member["name"].is_empty() or member["name"].length() > 48 \
			or not member.get("ready") is bool or not member.get("alive") is bool or not member.get("aboard") is bool \
			or (member["aboard"] and (not member["alive"] or not member["ready"] or value["phase"] == "briefing")):
			return MissionState.INVALID
		for character: String in member["name"]:
			var code: int = character.unicode_at(0)
			if code < 32 or (code >= 127 and code <= 159):
				return MissionState.INVALID
		party[member["id"]] = member
		all_aboard = all_aboard and member["ready"] and member["alive"] and member["aboard"]
	var problem: String = facts_error(value["m20"], geometry, value["phase"], int(message["tick"]))
	if not problem.is_empty():
		return problem
	var facts: Dictionary = value["m20"]
	if facts["brief_completed"] != brief_completed(facts["challenges"], value["rules"]["difficulty"]):
		return MissionState.INVALID
	var departing: bool = value["phase"] == "in_progress" and facts["completed"].size() == OBJECTIVES.size() \
		and facts["gate_open"] and all_aboard
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or not MissionState._uuid(prompt.get("player_id")) \
			or prompt["kind"] != "objective_use" or not departing or not party.has(prompt["player_id"]) \
			or prompt["player_id"] in prompted:
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != value["id"]:
			return MissionState.INVALID
		if value["attempt"] == old["attempt"]:
			var before: Dictionary = old["m20"]
			if facts["completed"].size() < before["completed"].size() \
				or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or int(value["changed_at"]) < int(old["changed_at"]) \
				or int(facts["refuge_integrity"]) > int(before["refuge_integrity"]) \
				or (before["gate_open"] and not facts["gate_open"]) \
				or (before.get("pier_reached_at") != null and before["pier_reached_at"] != facts.get("pier_reached_at")) \
				or (before.get("reprieve_at") != null and before["reprieve_at"] != facts.get("reprieve_at")):
				return MissionState.INVALID
			for fact: String in ["crew_crossed", "mark_broken"]:
				if before["challenges"][fact] and not facts["challenges"][fact]:
					return MissionState.INVALID
			if not before["challenges"]["refuge_held"] and facts["challenges"]["refuge_held"]:
				return MissionState.INVALID
	return ""
