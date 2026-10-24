class_name M19MissionState
extends RefCounted

## Planned Works facts bind the evacuation concourse, changed Low Water and the
## tram trench to the accepted map: eight ordered objectives, the coalition
## jetpack, Latch's departure and the waterworks gate. Validation grants no
## local mission authority.
const MAP_ID: int = 1019
const OBJECTIVES: Array[String] = [
	"concourse_stores",
	"broken_stair",
	"concourse_crossing",
	"tram_street",
	"market_strips",
	"water_tanks",
	"roof_loop",
	"tram_trench",
]
const USES: Array[int] = [0]
const DEPARTURE_OBJECTIVE_ID: String = "party_departed"
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const MAX_LATCH_ROUTE: int = 12
const MAX_WORK_MARKS: int = 48
const MAX_JET_HOPS: int = 4
const STORES_KINDS: Array[String] = ["m19_stores_counter"]
const DEPARTURE_KINDS: Array[String] = ["m19_waterworks"]
const CHALLENGES: Array[String] = ["crossing_cleared", "paver_interrupted", "strip_struck"]

static func map_error(info: Dictionary) -> String:
	if not MapGeometry.validation_error(info).is_empty() or info.get("map_id") != MAP_ID \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	for key: String in ["mission", "m02_objectives", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12", "m13", "m14", "m15", "m16", "m17", "m18"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and info["m02_side_ward"] != false:
		return MissionState.INVALID
	var g: Variant = info.get("m19")
	if not M03MissionState._exact(g, ["objectives", "departure", "boarding", "stores", "jetpack_ceiling", "latch_route", "work_marks", "jet_hops", "gate_open"]) \
		or not g["gate_open"] is bool or not g["objectives"] is Array or g["objectives"].size() != OBJECTIVES.size():
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	var decorations: Array = info["presentation"]["decorations"]
	for index: int in range(OBJECTIVES.size()):
		var objective: Variant = g["objectives"][index]
		if index in USES:
			if not M03MissionState._exact(objective, ["id", "action"]) or objective["id"] != OBJECTIVES[index] \
				or not M03MissionState._exact(objective["action"], ["kind", "target"]) \
				or objective["action"]["kind"] != "use" or objective["action"]["target"] != g["stores"]:
				return MissionState.INVALID
		elif not M06MissionState._arrival(objective, OBJECTIVES[index], half):
			return MissionState.INVALID
	if not M04MissionState._control(g["stores"], decorations, half, STORES_KINDS) \
		or not M04MissionState._control(g["departure"], decorations, half, DEPARTURE_KINDS) \
		or not M03MissionState._region(g["boarding"], half) \
		or not M03MissionState._inside(g["departure"]["approach"], g["boarding"]):
		return MissionState.INVALID
	var ceiling: Variant = g["jetpack_ceiling"]
	if not (ceiling is int or ceiling is float) or not is_finite(float(ceiling)) or float(ceiling) < 4.0 or float(ceiling) > 32.0:
		return MissionState.INVALID
	if not g["latch_route"] is Array or g["latch_route"].size() < 2 or g["latch_route"].size() > MAX_LATCH_ROUTE:
		return MissionState.INVALID
	for point: Variant in g["latch_route"]:
		if not MissionState._point(point, half):
			return MissionState.INVALID
	if not g["work_marks"] is Array or g["work_marks"].size() > MAX_WORK_MARKS:
		return MissionState.INVALID
	for mark: Variant in g["work_marks"]:
		if not work_mark_valid(mark, half):
			return MissionState.INVALID
	if not g["jet_hops"] is Array or g["jet_hops"].is_empty() or g["jet_hops"].size() > MAX_JET_HOPS:
		return MissionState.INVALID
	for hop: Variant in g["jet_hops"]:
		if not M03MissionState._exact(hop, ["launch", "landing"]) or not MissionState._point(hop["launch"], half) \
			or not MissionState._point(hop["landing"], half) or float(hop["landing"][1]) + 1.0 > float(ceiling):
			return MissionState.INVALID
	return ""

static func work_mark_valid(mark: Variant, half: float) -> bool:
	if not M03MissionState._exact(mark, ["min", "max", "y"]) or not mark["min"] is Array or not mark["max"] is Array \
		or mark["min"].size() != 2 or mark["max"].size() != 2 or not (mark["y"] is int or mark["y"] is float):
		return false
	for axis: int in range(2):
		for value: Variant in [mark["min"][axis], mark["max"][axis]]:
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > half:
				return false
		if float(mark["min"][axis]) >= float(mark["max"][axis]):
			return false
	return is_finite(float(mark["y"])) and float(mark["y"]) >= 0.0 and float(mark["y"]) <= 64.0

static func geometry_for(info: Dictionary) -> Dictionary:
	return {
		"id": MissionState.M19_ID,
		"map_id": MAP_ID,
		"half_extent": float(info["half_extent"]),
		"m19": info["m19"].duplicate(true),
		"solids": info["solids"].duplicate(true),
		"presentation": info["presentation"].duplicate(true),
	}

## The static contract survives the waterworks gate opening.
static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M19_ID or second.get("id") != MissionState.M19_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or not first.get("m19") is Dictionary or not second.get("m19") is Dictionary:
		return false
	var before: Dictionary = first["m19"].duplicate(true)
	var after: Dictionary = second["m19"].duplicate(true)
	before.erase("gate_open")
	after.erase("gate_open")
	return before == after

static func challenge_error(value: Variant) -> String:
	if not M03MissionState._exact(value, CHALLENGES):
		return MissionState.INVALID
	for key: String in CHALLENGES:
		if not value[key] is bool:
			return MissionState.INVALID
	return ""

## Assisted clears the crossing; Standard adds a Paver put out mid-preparation;
## Severe adds no work-strip damage.
static func brief_completed(value: Dictionary, difficulty: String) -> bool:
	return value["crossing_cleared"] and (difficulty == "assisted" \
		or (value["paver_interrupted"] and (difficulty != "severe" or not value["strip_struck"])))

static func facts_error(value: Variant, phase: String, tick: int) -> String:
	var keys: Array[String] = ["completed", "challenges", "jetpack_taken", "latch_departed", "gate_open", "brief_completed"]
	if value is Dictionary and value.has("current"):
		keys.append("current")
	if not M03MissionState._exact(value, keys):
		return MissionState.INVALID
	if not MissionState.ordered_facts_error(value, OBJECTIVES, USES, phase, tick).is_empty():
		return MissionState.INVALID
	for key: String in ["jetpack_taken", "latch_departed", "gate_open", "brief_completed"]:
		if not value[key] is bool:
			return MissionState.INVALID
	var challenge_problem: String = challenge_error(value.get("challenges"))
	if not challenge_problem.is_empty():
		return challenge_problem
	var n: int = value["completed"].size()
	if value["jetpack_taken"] != (n >= 1) or value["challenges"]["crossing_cleared"] != (n >= 3) \
		or value["latch_departed"] != (n >= 6) or value["gate_open"] != (n >= 8):
		return MissionState.INVALID
	if phase == "briefing" and (value["challenges"]["paver_interrupted"] or value["challenges"]["strip_struck"]):
		return MissionState.INVALID
	return ""

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not message.get("state") is Dictionary:
		return MissionState.INVALID
	var value: Dictionary = message["state"]
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m19"]
	if value.has("run"):
		keys.append("run")
	if geometry.get("id") != MissionState.M19_ID or value.get("id") != MissionState.M19_ID \
		or not M03MissionState._exact(value, keys) or not geometry.get("m19") is Dictionary \
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
	var facts: Variant = value.get("m19")
	var problem: String = facts_error(facts, value["phase"], int(message["tick"]))
	if not problem.is_empty():
		return problem
	if facts["brief_completed"] != brief_completed(facts["challenges"], value["rules"]["difficulty"]):
		return MissionState.INVALID
	var g: Dictionary = geometry["m19"]
	var n: int = facts["completed"].size()
	if n <= OBJECTIVES.size():
		var expected: Dictionary = g["objectives"][n] if n < OBJECTIVES.size() else {"id": DEPARTURE_OBJECTIVE_ID, "action": {"kind": "use", "target": g["departure"]}}
		if facts.get("current") != expected:
			return MissionState.INVALID
	if facts["gate_open"] != g["gate_open"]:
		return MissionState.INVALID
	var allowed: bool = value["phase"] == "in_progress" and ((n == 0 and not facts["jetpack_taken"]) or (n == OBJECTIVES.size() and all_aboard))
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or prompt["kind"] != "objective_use" \
			or not allowed or not party.has(prompt["player_id"]) or not party[prompt["player_id"]]["alive"] \
			or not party[prompt["player_id"]]["ready"] or prompt["player_id"] in prompted:
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != value["id"]:
			return MissionState.INVALID
		if value["attempt"] == old["attempt"]:
			var before: Dictionary = old["m19"]
			if n < before["completed"].size() or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or value["changed_at"] < old["changed_at"]:
				return MissionState.INVALID
			for fact: String in ["jetpack_taken", "latch_departed", "gate_open"]:
				if before[fact] and not facts[fact]:
					return MissionState.INVALID
			for fact: String in CHALLENGES:
				if before["challenges"][fact] and not facts["challenges"][fact]:
					return MissionState.INVALID
	return ""
