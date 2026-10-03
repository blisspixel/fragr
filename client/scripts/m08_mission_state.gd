class_name M08MissionState
extends RefCounted

## Custody archive facts are authoritative; this only validates presentation.
const MAP_ID: int = 1008
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const OBJECTIVES: Array[String] = ["hall_cleared", "lower_gallery_cleared", "mines_cleared",
	"auditor_cleared", "machine_wrecked", "evidence_taken", "exit_cleared"]
## The arrival steps in geometry order; the machine is a Shoot step.
const ARRIVALS: Array[int] = [0, 1, 2, 3, 5, 6]
const MACHINE_STEP: int = 4
const DEPARTURE: String = "party_departed"
const BAYS: String = "custody_released"
const CABINET: String = "recovered_mind_secured"
const NODES: int = 4
const NODE_HP: int = 50
const GEOMETRY_KEYS: Array[String] = ["objectives", "nodes", "machine", "seal", "bays", "cabinet",
	"departure", "boarding", "companion_start", "seal_open", "machine_fallen"]
const FACTS: Array[String] = ["completed", "node_hp", "seal_open", "machine_fallen", "custodian_joined",
	"custody_released", "recovered_mind_secured", "transfer_evidence", "captives_evacuated"]

static func map_error(info: Dictionary) -> String:
	var value: Variant = info.get("m08")
	if not M03MissionState._exact(value, GEOMETRY_KEYS) \
		or info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 \
		or info.get("mission") != null or info.get("m02_objectives") != null \
		or info.has("m03") or info.has("m04") or info.has("m05") or info.has("m06") \
		or (info.has("m02_side_ward") and (not info["m02_side_ward"] is bool or info["m02_side_ward"])) \
		or not MapGeometry._number(info.get("half_extent")) or not info.get("solids") is Array \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	var solids: int = info["solids"].size()
	if half < 2.0 or half > MapGeometry.MAX_HALF or not value["objectives"] is Array \
		or value["objectives"].size() != ARRIVALS.size() or not value["nodes"] is Array \
		or value["nodes"].size() != NODES \
		or not EquipmentState.integer(value["machine"], solids - 1) \
		or not EquipmentState.integer(value["seal"], solids - 1) \
		or not M06MissionState._arrival(value["bays"], BAYS, half) \
		or not M06MissionState._arrival(value["cabinet"], CABINET, half) \
		or not M03MissionState._region(value["boarding"], half) \
		or not M04MissionState._control(value["departure"], info["presentation"]["decorations"], half,
			["m08_freight_departure"]) \
		or not M03MissionState._inside(value["departure"]["approach"], value["boarding"]) \
		or not MissionState._point(value["companion_start"], half) \
		or not value["seal_open"] is bool or not value["machine_fallen"] is bool \
		or (value["machine_fallen"] and not value["seal_open"]):
		return MissionState.INVALID
	for index: int in range(ARRIVALS.size()):
		if not M06MissionState._arrival(value["objectives"][index], OBJECTIVES[ARRIVALS[index]], half):
			return MissionState.INVALID
	var used: Array[int] = [int(value["machine"]), int(value["seal"])]
	if used[0] == used[1]:
		return MissionState.INVALID
	for node: Variant in value["nodes"]:
		if not M03MissionState._exact(node, ["solid", "approach", "aim"]) \
			or not EquipmentState.integer(node["solid"], solids - 1) or int(node["solid"]) in used \
			or not MissionState._point(node["approach"], half) or not MissionState._point(node["aim"], half):
			return MissionState.INVALID
		used.append(int(node["solid"]))
	return ""

static func geometry_for(info: Dictionary) -> Dictionary:
	return {"id": MissionState.M08_ID, "map_id": int(info["map_id"]),
		"half_extent": float(info["half_extent"]), "m08": info["m08"].duplicate(true)}

## The static contract, with only the two stage flags free to move forward.
static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M08_ID or second.get("id") != MissionState.M08_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or not first.get("m08") is Dictionary or not second.get("m08") is Dictionary:
		return false
	var before: Dictionary = first["m08"].duplicate(true)
	var after: Dictionary = second["m08"].duplicate(true)
	for flag: String in ["seal_open", "machine_fallen"]:
		before.erase(flag)
		after.erase(flag)
	return before == after

## The chain step a validated geometry names at `index`.
static func step(bound: Dictionary, index: int, node_hp: Array) -> Dictionary:
	if index < MACHINE_STEP:
		return bound["objectives"][index]
	if index == MACHINE_STEP:
		for node: int in range(NODES):
			if int(node_hp[node]) > 0:
				var target: Dictionary = bound["nodes"][node]
				return {"id": OBJECTIVES[MACHINE_STEP], "action": {"kind": "shoot",
					"solid": target["solid"], "approach": target["approach"], "aim": target["aim"]}}
		return {}
	if index < OBJECTIVES.size():
		return bound["objectives"][index - 1]
	return {"id": DEPARTURE, "action": {"kind": "use", "target": bound["departure"]}}

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m08"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not M03MissionState._exact(value, keys) or value["id"] != MissionState.M08_ID \
		or geometry.get("id") != MissionState.M08_ID or not geometry.get("m08") is Dictionary \
		or not MissionState.valid_rules(value["rules"]) or value["phase"] not in PHASES \
		or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 \
		or not EquipmentState.integer(value["changed_at"], int(message["tick"])) \
		or not value["party"] is Array or value["party"].size() > 4 \
		or not value["prompts"] is Array or value["prompts"].size() > value["party"].size():
		return MissionState.INVALID
	var bound: Dictionary = geometry["m08"]
	var facts: Variant = value["m08"]
	var departed: bool = value["phase"] == "departed"
	var fact_keys: Array[String] = FACTS.duplicate()
	if not departed:
		fact_keys.append("current")
	if not M03MissionState._exact(facts, fact_keys) or not facts["completed"] is Array \
		or not facts["node_hp"] is Array or facts["node_hp"].size() != NODES:
		return MissionState.INVALID
	for flag: String in FACTS.slice(2):
		if not facts[flag] is bool:
			return MissionState.INVALID
	var hp: Array = facts["node_hp"]
	var broken: bool = true
	var whole: bool = true
	for left: Variant in hp:
		if not EquipmentState.integer(left, NODE_HP):
			return MissionState.INVALID
		broken = broken and int(left) == 0
		whole = whole and int(left) == NODE_HP
	var order: Array[String] = OBJECTIVES.duplicate()
	order.append(DEPARTURE)
	var completed: Array = facts["completed"]
	var done: int = completed.size()
	if done > order.size() or departed != (done == order.size()):
		return MissionState.INVALID
	for index: int in range(done):
		if completed[index] != order[index]:
			return MissionState.INVALID
	if (done < MACHINE_STEP and not whole) or (done > MACHINE_STEP) != broken \
		or facts["machine_fallen"] != (done > MACHINE_STEP) \
		or (done > 3 and not facts["seal_open"]) or (facts["seal_open"] and done < 3) \
		or facts["custodian_joined"] != (done >= 2) or facts["transfer_evidence"] != (done > 5) \
		or ((facts["custody_released"] or facts["recovered_mind_secured"]) and not facts["seal_open"]) \
		or (facts["captives_evacuated"] and not (facts["custody_released"] and departed)) \
		or facts["seal_open"] != bound["seal_open"] or facts["machine_fallen"] != bound["machine_fallen"]:
		return MissionState.INVALID
	if not departed and facts["current"] != step(bound, done, hp):
		return MissionState.INVALID
	if value["phase"] == "briefing" and (done > 0 or facts["seal_open"] or not whole \
		or facts["custody_released"] or facts["recovered_mind_secured"]):
		return MissionState.INVALID
	var party: Dictionary = {}
	var aboard: bool = not value["party"].is_empty()
	for member: Variant in value["party"]:
		if not M03MissionState._exact(member, ["id", "name", "ready", "alive", "aboard"]) \
			or not MissionState._uuid(member["id"]) or party.has(member["id"]) \
			or not member["name"] is String or member["name"].is_empty() or member["name"].length() > 48 \
			or not member["ready"] is bool or not member["alive"] is bool or not member["aboard"] is bool \
			or (member["aboard"] and (not member["ready"] or not member["alive"] or value["phase"] == "briefing")):
			return MissionState.INVALID
		for character: String in member["name"]:
			var code: int = character.unicode_at(0)
			if code < 32 or (code >= 127 and code <= 159):
				return MissionState.INVALID
		party[member["id"]] = member
		aboard = aboard and member["ready"] and member["alive"] and member["aboard"]
	if value.has("run") and not MissionState.valid_run(value):
		return MissionState.INVALID
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or prompt["kind"] != "objective_use" \
			or value["phase"] != "in_progress" or not party.has(prompt["player_id"]) \
			or prompt["player_id"] in prompted or not aboard or done != OBJECTIVES.size():
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M08_ID or int(message["tick"]) < int(previous["tick"]) \
			or int(value["attempt"]) < int(old["attempt"]) or value["rules"] != old["rules"] \
			or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		var before: Dictionary = old["m08"]
		if int(value["attempt"]) == int(old["attempt"]):
			if done < before["completed"].size() or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or int(value["changed_at"]) < int(old["changed_at"]) \
				or (before["custody_released"] and not facts["custody_released"]) \
				or (before["recovered_mind_secured"] and not facts["recovered_mind_secured"]):
				return MissionState.INVALID
			for node: int in range(NODES):
				if int(hp[node]) > int(before["node_hp"][node]):
					return MissionState.INVALID
	return ""
