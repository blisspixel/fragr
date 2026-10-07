class_name M11MissionState
extends RefCounted

## Tender facts stay authoritative. Capability 38 includes deliberate charges.
const MAP_ID: int = 1011
const SIGNAL_TICKS: int = 1200
const OBJECTIVES: Array[String] = ["armory_found", "spine_secured", "holds_secured", "records_secured", "counter_boarders_secured", "bridge_secured"]
const DEPARTURE: String = "party_departed"
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]

static func map_error(info: Dictionary) -> String:
	if info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 \
		or info.get("mission") != null or info.get("m02_objectives") != null \
		or not MapGeometry._number(info.get("half_extent")) \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	for key: String in ["m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and (not info["m02_side_ward"] is bool or info["m02_side_ward"]):
		return MissionState.INVALID
	return map_value_error(info.get("m11"), float(info["half_extent"]), info["presentation"]["decorations"])

static func geometry_for(info: Dictionary) -> Dictionary:
	return {"id": MissionState.M11_ID, "map_id": int(info["map_id"]),
		"half_extent": float(info["half_extent"]), "m11": info["m11"].duplicate(true),
		"solids": info["solids"].duplicate(true), "presentation": info["presentation"].duplicate(true)}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	return first.get("id") == MissionState.M11_ID and second.get("id") == MissionState.M11_ID \
		and first.get("map_id") == second.get("map_id") and first.get("half_extent") == second.get("half_extent") \
		and first.get("m11") is Dictionary and second.get("m11") is Dictionary and first["m11"] == second["m11"] \
		and first.get("solids") == second.get("solids") and first.get("presentation") == second.get("presentation")

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m11"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not M03MissionState._exact(value, keys) or value["id"] != MissionState.M11_ID \
		or geometry.get("id") != MissionState.M11_ID or not geometry.get("m11") is Dictionary \
		or not MissionState.valid_rules(value["rules"]) or value["phase"] not in PHASES \
		or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 \
		or not EquipmentState.integer(value["changed_at"], int(message["tick"])) \
		or not value["party"] is Array or value["party"].size() > 4 \
		or not value["prompts"] is Array or value["prompts"].size() > value["party"].size() \
		or not facts_error(value["m11"], str(value["phase"]), int(message["tick"])).is_empty():
		return MissionState.INVALID
	var bound: Dictionary = geometry["m11"]
	var progress: Dictionary = value["m11"]
	var completed: Array = progress["completed"]
	if value["phase"] != "departed":
		var expected: Dictionary = bound["objectives"][completed.size()] if completed.size() < OBJECTIVES.size() else {
			"id": DEPARTURE, "action": {"kind": "use", "target": bound["departure"]}}
		if progress["current"] != expected:
			return MissionState.INVALID
	var party: Dictionary = {}
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
	if value.has("run") and not MissionState.valid_run(value):
		return MissionState.INVALID
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or prompt["kind"] != "objective_use" \
			or value["phase"] != "in_progress" or not party.has(prompt["player_id"]) \
			or prompt["player_id"] in prompted or not party[prompt["player_id"]]["alive"] or not party[prompt["player_id"]]["ready"] \
			or completed.size() < 3:
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M11_ID or int(message["tick"]) < int(previous["tick"]) \
			or int(value["attempt"]) < int(old["attempt"]) or value["rules"] != old["rules"] \
			or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		if int(value["attempt"]) == int(old["attempt"]):
			var before: Dictionary = old["m11"]
			if completed.size() < before["completed"].size() or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or int(value["changed_at"]) < int(old["changed_at"]):
				return MissionState.INVALID
			var challenges: Dictionary = progress["challenges"]
			var prior: Dictionary = before["challenges"]
			for key: String in ["transfer_released", "records_read"]:
				if prior[key] and not challenges[key]:
					return MissionState.INVALID
			if int(challenges["counter_boarder_blast_kills"]) < int(prior["counter_boarder_blast_kills"]):
				return MissionState.INVALID
			for key: String in ["counter_boarding_started", "signal_due", "bridge_taken_at"]:
				if prior.has(key) and challenges.get(key) != prior[key]:
					return MissionState.INVALID
	return ""

static func map_value_error(value: Variant, half: float, decorations: Array) -> String:
	if not M03MissionState._exact(value, ["objectives", "transfer_release", "records_document", "departure", "boarding", "companion_start", "transfer_people"]) \
		or not is_finite(half) or half < 2.0 or half > MapGeometry.MAX_HALF \
		or not value["objectives"] is Array or value["objectives"].size() != OBJECTIVES.size() \
		or not M03MissionState._region(value["boarding"], half) \
		or not MissionState._point(value["companion_start"], half) \
		or not value["transfer_people"] is Array or value["transfer_people"].size() != 3:
		return MissionState.INVALID
	for index: int in range(OBJECTIVES.size()):
		if not M06MissionState._arrival(value["objectives"][index], OBJECTIVES[index], half):
			return MissionState.INVALID
	var targets: Array[String] = ["transfer_release", "records_document", "departure"]
	var kinds: Array[String] = ["m11_transfer_release", "m11_records_document", "m11_stern_release"]
	var seen: Array[int] = []
	for index: int in range(targets.size()):
		var target: Variant = value[targets[index]]
		if not M04MissionState._control(target, decorations, half, [kinds[index]]) \
			or int(target["decoration"]) in seen:
			return MissionState.INVALID
		seen.append(int(target["decoration"]))
	if not M03MissionState._inside(value["departure"]["approach"], value["boarding"]):
		return MissionState.INVALID
	var people: Array = value["transfer_people"]
	for index: int in range(people.size()):
		if not MissionState._point(people[index], half):
			return MissionState.INVALID
		for prior: int in range(index):
			var dx: float = float(people[index][0]) - float(people[prior][0])
			var dz: float = float(people[index][2]) - float(people[prior][2])
			if Vector2(dx, dz).length() < MoveStep.RADIUS * 2.0:
				return MissionState.INVALID
	return ""

static func challenge_error(value: Variant, tick: int) -> String:
	var keys: Array[String] = ["transfer_released", "records_read", "counter_boarder_blast_kills"]
	if value is Dictionary:
		for optional: String in ["counter_boarding_started", "signal_due", "bridge_taken_at"]:
			if value.has(optional):
				keys.append(optional)
	if not M03MissionState._exact(value, keys) or not value["transfer_released"] is bool \
		or not value["records_read"] is bool or not EquipmentState.integer(value["counter_boarder_blast_kills"], 6):
		return MissionState.INVALID
	var started: bool = value.has("counter_boarding_started")
	if started != value.has("signal_due"):
		return MissionState.INVALID
	if started:
		if not EquipmentState.integer(value["counter_boarding_started"], tick) \
			or not EquipmentState.integer(value["signal_due"], EquipmentState.MAX_EXACT_INTEGER) \
			or int(value["signal_due"]) != int(value["counter_boarding_started"]) + SIGNAL_TICKS:
			return MissionState.INVALID
	elif int(value["counter_boarder_blast_kills"]) != 0 or value.has("bridge_taken_at"):
		return MissionState.INVALID
	if value.has("bridge_taken_at"):
		if not EquipmentState.integer(value["bridge_taken_at"], tick) \
			or int(value["bridge_taken_at"]) < int(value["counter_boarding_started"]):
			return MissionState.INVALID
	return ""

static func brief_completed(challenges: Dictionary, difficulty: String) -> bool:
	return challenges.get("transfer_released", false) \
		and (difficulty == "assisted" or int(challenges.get("counter_boarder_blast_kills", 0)) >= 3) \
		and (difficulty != "severe" or (challenges.has("bridge_taken_at") and challenges.has("signal_due") \
			and int(challenges["bridge_taken_at"]) < int(challenges["signal_due"])))

static func facts_error(value: Variant, phase: String, tick: int) -> String:
	if phase not in PHASES or tick < 0 or tick > EquipmentState.MAX_EXACT_INTEGER:
		return MissionState.INVALID
	var keys: Array[String] = ["completed", "challenges"]
	if value is Dictionary and value.has("current"):
		keys.append("current")
	if not M03MissionState._exact(value, keys) or not value["completed"] is Array \
		or not challenge_error(value["challenges"], tick).is_empty():
		return MissionState.INVALID
	var completed: Array = value["completed"]
	var count: int = completed.size()
	var challenges: Dictionary = value["challenges"]
	var order: Array[String] = OBJECTIVES.duplicate()
	order.append(DEPARTURE)
	if count > order.size() or (phase == "departed") != (count == order.size()) \
		or value.has("current") != (count <= OBJECTIVES.size()) \
		or (phase == "briefing" and (count != 0 or challenges["transfer_released"] or challenges["records_read"] \
			or int(challenges["counter_boarder_blast_kills"]) != 0 or challenges.has("counter_boarding_started"))) \
		or (challenges.has("counter_boarding_started") and count < 3) \
		or (count >= 5 and not challenges.has("counter_boarding_started")) \
		or challenges.has("bridge_taken_at") != (count >= 6) \
		or (challenges["records_read"] and count < 4) or (challenges["transfer_released"] and count < 3):
		return MissionState.INVALID
	for index: int in range(count):
		if completed[index] != order[index]:
			return MissionState.INVALID
	if count < OBJECTIVES.size():
		if not M06MissionState._arrival(value["current"], OBJECTIVES[count], MapGeometry.MAX_HALF * 2.0):
			return MissionState.INVALID
	elif count == OBJECTIVES.size():
		var current: Variant = value["current"]
		if not M03MissionState._exact(current, ["id", "action"]) or current["id"] != DEPARTURE \
			or not M03MissionState._exact(current["action"], ["kind", "target"]) or current["action"]["kind"] != "use" \
			or not M03MissionState._exact(current["action"]["target"], ["decoration", "approach"]) \
			or not EquipmentState.integer(current["action"]["target"]["decoration"], MapDecoration.MAX_DETAILS - 1) \
			or not MissionState._point(current["action"]["target"]["approach"], MapGeometry.MAX_HALF * 2.0):
			return MissionState.INVALID
	return ""
