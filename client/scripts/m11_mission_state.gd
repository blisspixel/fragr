class_name M11MissionState
extends RefCounted

## Incomplete tender boundary. Capability 37 is reserved, not admitted by this file.
const MAP_ID: int = 1011
const SIGNAL_TICKS: int = 1200
const OBJECTIVES: Array[String] = ["armory_found", "spine_secured", "holds_secured", "records_secured", "counter_boarders_secured", "bridge_secured"]
const DEPARTURE: String = "party_departed"
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]

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
