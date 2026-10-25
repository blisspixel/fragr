class_name EpilogueMissionState
extends RefCounted

## Still Here facts bind the refuge's two worlds, the people the run carried
## and the walk to the accepted map. Mirror of protocol/epilogue.rs. Nothing
## here fights or fails, and validation grants no local authority: the world
## turns, and the ending lands, only when the server says so.
const MAP_ID: int = 1021
const NAME: String = "Still Here"
const LATER_NAME: String = "Still Here, years later"
const OBJECTIVES: Array[String] = ["stay_with_latch", "years_later"]
const DEPARTURE_OBJECTIVE_ID: String = "party_departed"
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const STAGES: Array[String] = ["aftermath", "later"]
const SURVIVORS: Array[String] = ["cars", "edda", "splice", "orrin", "sorrel", "entrants", "bus"]
const POSES: Array[String] = ["stand", "sit", "child", "work", "perch", "lie"]
## People on furniture leave blocking to the furniture.
const SEATED: Array[String] = ["perch", "lie"]
const TURN_TICKS: int = 80
const MAX_PEOPLE: int = 120
const MAX_WORLD_SOLIDS: int = 32
const KEYS: Array[String] = ["latch", "arrival", "arrival_feet", "departure", "later_spawn", "later_yaw",
	"ferry_board", "people", "aftermath_only", "later_only", "later"]

static func _identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 32:
		return false
	for character: String in value:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") and character != "_":
			return false
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func person_error(value: Variant, half: float) -> String:
	var keys: Array[String] = ["id", "stage", "feet", "yaw", "pose"]
	if value is Dictionary:
		for optional: String in ["requires", "unless"]:
			if value.has(optional):
				keys.append(optional)
	if not M03MissionState._exact(value, keys) or not _identifier(value["id"]) \
		or not value["stage"] is String or value["stage"] not in STAGES \
		or not MissionState._point(value["feet"], half) or not _number(value["yaw"]) \
		or not value["pose"] is String or value["pose"] not in POSES:
		return MissionState.INVALID
	for optional: String in ["requires", "unless"]:
		if value.has(optional) and (not value[optional] is String or value[optional] not in SURVIVORS):
			return MissionState.INVALID
	if value.has("requires") and value.get("requires") == value.get("unless"):
		return MissionState.INVALID
	return ""

static func map_error(info: Dictionary) -> String:
	if not MapGeometry.validation_error(info).is_empty() or info.get("map_id") != MAP_ID \
		or info.get("map_name") not in [NAME, LATER_NAME] \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	for key: String in ["mission", "m02_objectives", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12", "m13", "m14", "m15", "m16", "m17", "m18", "m19", "m20"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and info["m02_side_ward"] != false:
		return MissionState.INVALID
	var g: Variant = info.get("epilogue")
	if not M03MissionState._exact(g, KEYS) or not g["later"] is bool \
		or (info["map_name"] == LATER_NAME) != g["later"]:
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	var decorations: Array = info["presentation"]["decorations"]
	var solids: Array = info["solids"]
	if not M04MissionState._control(g["latch"], decorations, half, ["epilogue_ledger"]) \
		or not M04MissionState._control(g["departure"], decorations, half, ["epilogue_bench"]) \
		or not M03MissionState._region(g["arrival"], half) or not MissionState._point(g["arrival_feet"], half) \
		or not M03MissionState._inside(g["arrival_feet"], g["arrival"]) \
		or not MissionState._point(g["later_spawn"], half) or not _number(g["later_yaw"]) \
		or M03MissionState._inside(g["later_spawn"], g["arrival"]):
		return MissionState.INVALID
	if not EquipmentState.integer(g["ferry_board"], decorations.size() - 1) \
		or decorations[int(g["ferry_board"])].get("kind") != "epilogue_ferry_board":
		return MissionState.INVALID
	var worlds: Dictionary = {}
	for key: String in ["aftermath_only", "later_only"]:
		if not g[key] is Array or g[key].size() > MAX_WORLD_SOLIDS:
			return MissionState.INVALID
		for index: Variant in g[key]:
			if not EquipmentState.integer(index, solids.size() - 1) or worlds.has(int(index)):
				return MissionState.INVALID
			worlds[int(index)] = key
	for detail: Variant in decorations:
		if detail is Dictionary and worlds.has(int(detail.get("solid", -1))):
			return MissionState.INVALID
	if not g["people"] is Array or g["people"].size() > MAX_PEOPLE:
		return MissionState.INVALID
	var seen: Dictionary = {}
	for person: Variant in g["people"]:
		if not person_error(person, half).is_empty():
			return MissionState.INVALID
		var key: String = "%s/%s" % [person["stage"], person["id"]]
		if seen.has(key):
			return MissionState.INVALID
		seen[key] = true
	return ""

static func geometry_for(info: Dictionary) -> Dictionary:
	return {
		"id": MissionState.STILL_HERE_ID,
		"map_id": MAP_ID,
		"map_name": str(info["map_name"]),
		"half_extent": float(info["half_extent"]),
		"epilogue": info["epilogue"].duplicate(true),
		"solids": info["solids"].duplicate(true),
		"presentation": info["presentation"].duplicate(true),
	}

## The static contract: only the world may turn, and only forward.
static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.STILL_HERE_ID or second.get("id") != MissionState.STILL_HERE_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or not first.get("epilogue") is Dictionary or not second.get("epilogue") is Dictionary:
		return false
	if first["epilogue"]["later"] and not second["epilogue"]["later"]:
		return false
	var before: Dictionary = first["epilogue"].duplicate(true)
	var after: Dictionary = second["epilogue"].duplicate(true)
	before.erase("later")
	after.erase("later")
	return before == after

static func stage_of(g: Dictionary) -> String:
	return "later" if g.get("later") == true else "aftermath"

static func has_survivor(refuge: Dictionary, who: Variant) -> bool:
	return who is String and refuge.get(who) == true

static func present(person: Dictionary, stage: String, refuge: Dictionary) -> bool:
	return person["stage"] == stage \
		and (not person.has("requires") or has_survivor(refuge, person["requires"])) \
		and (not person.has("unless") or not has_survivor(refuge, person["unless"]))

## Everyone standing in this world for this run, in authored order.
static func people(g: Dictionary, refuge: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stage: String = stage_of(g)
	for person: Dictionary in g.get("people", []):
		if present(person, stage, refuge):
			result.append(person)
	return result

## The server's contact list for this world: people not on furniture.
static func blocking(g: Dictionary, refuge: Dictionary) -> Array:
	var result: Array = []
	for person: Dictionary in people(g, refuge):
		if person["pose"] not in SEATED:
			result.append({"id": person["id"], "feet": person["feet"]})
	return result

static func refuge_error(value: Variant) -> String:
	if not M03MissionState._exact(value, SURVIVORS):
		return MissionState.INVALID
	for key: String in SURVIVORS:
		if not value[key] is bool:
			return MissionState.INVALID
	return ""

static func facts_error(value: Variant, geometry: Dictionary, phase: String, tick: int) -> String:
	var keys: Array[String] = ["completed", "refuge", "later", "blocking"]
	if value is Dictionary:
		for optional: String in ["current", "turning_at"]:
			if value.has(optional):
				keys.append(optional)
	if not M03MissionState._exact(value, keys) or not geometry.get("epilogue") is Dictionary:
		return MissionState.INVALID
	if not MissionState.ordered_facts_error(value, OBJECTIVES, [0], phase, tick).is_empty():
		return MissionState.INVALID
	if not value["later"] is bool or not refuge_error(value["refuge"]).is_empty() or not value["blocking"] is Array:
		return MissionState.INVALID
	var g: Dictionary = geometry["epilogue"]
	var n: int = value["completed"].size()
	var turning: Variant = value.get("turning_at")
	if turning != null and (not EquipmentState.integer(turning, tick)):
		return MissionState.INVALID
	if (n >= 1) != (turning != null) or (n >= 2 and not value["later"]) \
		or (value["later"] and int(turning if turning != null else tick) + TURN_TICKS > tick) \
		or (phase == "departed" and not value["later"]) or value["later"] != g["later"]:
		return MissionState.INVALID
	if n <= OBJECTIVES.size():
		var expected: Dictionary
		match n:
			0: expected = {"id": OBJECTIVES[0], "action": {"kind": "use", "target": g["latch"]}}
			1: expected = {"id": OBJECTIVES[1], "action": {"kind": "arrival", "region": g["arrival"], "feet": g["arrival_feet"]}}
			_: expected = {"id": DEPARTURE_OBJECTIVE_ID, "action": {"kind": "use", "target": g["departure"]}}
		if value.get("current") != expected:
			return MissionState.INVALID
	if value["blocking"] != blocking(g, value["refuge"]):
		return MissionState.INVALID
	return ""

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not message.get("state") is Dictionary:
		return MissionState.INVALID
	var value: Dictionary = message["state"]
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "epilogue"]
	if geometry.get("id") != MissionState.STILL_HERE_ID or value.get("id") != MissionState.STILL_HERE_ID \
		or not M03MissionState._exact(value, keys) \
		or not MissionState.valid_rules(value.get("rules")) \
		or not value.get("phase") is String or value["phase"] not in PHASES \
		or not EquipmentState.integer(value.get("attempt"), 4294967295) or int(value["attempt"]) == 0 \
		or not EquipmentState.integer(value.get("changed_at"), int(message["tick"])) \
		or not value.get("party") is Array or value["party"].size() > 4 \
		or not value.get("prompts") is Array or value["prompts"].size() > value["party"].size():
		return MissionState.INVALID
	if not previous.is_empty() and (int(value["attempt"]) < int(previous["state"]["attempt"]) \
		or int(message["tick"]) < int(previous["tick"]) or value["rules"] != previous["state"]["rules"]):
		return MissionState.INVALID
	var party: Dictionary = {}
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
	var problem: String = facts_error(value["epilogue"], geometry, value["phase"], int(message["tick"]))
	if not problem.is_empty():
		return problem
	var facts: Dictionary = value["epilogue"]
	var n: int = facts["completed"].size()
	# Beside Latch in the first light, or on the quay years later; never while
	# the world turns.
	var usable: bool = value["phase"] == "in_progress" \
		and ((n == 0 and facts.get("turning_at") == null) or (n == OBJECTIVES.size() and facts["later"]))
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or not MissionState._uuid(prompt.get("player_id")) \
			or prompt["kind"] != "objective_use" or not usable or not party.has(prompt["player_id"]) \
			or prompt["player_id"] in prompted:
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != value["id"]:
			return MissionState.INVALID
		if value["attempt"] == old["attempt"]:
			var before: Dictionary = old["epilogue"]
			if n < before["completed"].size() \
				or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or int(value["changed_at"]) < int(old["changed_at"]) \
				or (before["later"] and not facts["later"]) or before["refuge"] != facts["refuge"] \
				or (before.get("turning_at") != null and before["turning_at"] != facts.get("turning_at")):
				return MissionState.INVALID
	return ""
