class_name M15MissionState
extends RefCounted

## Civic Pressure Valve facts bind the connected stadium bout and its three worlds.
const MAP_ID: int = 1015
const OBJECTIVES: Array[String] = ["pen_armed", "pen_cleared", "blade_lesson_won", "wardens_cleared", "broadcast_secured", "bout_won"]
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]
const ENTRANTS: Array[int] = [4, 12, 44, 71]

static func map_error(info: Dictionary) -> String:
	if not MapGeometry.validation_error(info).is_empty() or info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	for key: String in ["mission", "m02_objectives", "m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11", "m12", "m13", "m14"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and info["m02_side_ward"] != false:
		return MissionState.INVALID
	var g: Variant = info.get("m15")
	if not M03MissionState._exact(g, ["objectives", "departure", "boarding", "arming_crate", "booth_terminal", "tunnel_closed", "gates_open"]) \
		or not g["tunnel_closed"] is bool or not g["gates_open"] is bool \
		or not g["objectives"] is Array or g["objectives"].size() != OBJECTIVES.size():
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	var decorations: Array = info["presentation"]["decorations"]
	# Objective 0: pen_armed (use arming crate)
	if not M16MissionState._use(g["objectives"][0], OBJECTIVES[0], g["arming_crate"], decorations, half, ["terminal", "lift_control"]):
		return MissionState.INVALID
	# Objective 1..3, 5: Arrival
	for idx: int in [1, 2, 3, 5]:
		if not M06MissionState._arrival(g["objectives"][idx], OBJECTIVES[idx], half):
			return MissionState.INVALID
	# Objective 4: broadcast_secured (use booth terminal)
	if not M16MissionState._use(g["objectives"][4], OBJECTIVES[4], g["booth_terminal"], decorations, half, ["terminal", "lift_control"]):
		return MissionState.INVALID
	if not M03MissionState._region(g["boarding"], half) \
		or not M04MissionState._control(g["departure"], decorations, half, ["terminal", "lift_control"]) \
		or not M03MissionState._inside(g["departure"]["approach"], g["boarding"]):
		return MissionState.INVALID
	if not M04MissionState._control(g["arming_crate"], decorations, half, ["terminal", "lift_control"]) \
		or not M04MissionState._control(g["booth_terminal"], decorations, half, ["terminal", "lift_control"]):
		return MissionState.INVALID
	return ""

static func geometry_for(info: Dictionary) -> Dictionary:
	return {
		"id": MissionState.M15_ID,
		"map_id": MAP_ID,
		"half_extent": float(info["half_extent"]),
		"m15": info["m15"].duplicate(true),
		"solids": info["solids"].duplicate(true),
		"presentation": info["presentation"].duplicate(true)
	}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M15_ID or second.get("id") != MissionState.M15_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or not first.get("m15") is Dictionary or not second.get("m15") is Dictionary:
		return false
	var before: Dictionary = first["m15"].duplicate(true)
	var after: Dictionary = second["m15"].duplicate(true)
	for flag: String in ["tunnel_closed", "gates_open"]:
		before.erase(flag)
		after.erase(flag)
	return before == after

static func challenge_error(value: Variant) -> String:
	if not M03MissionState._exact(value, ["pen_armed", "blade_wave_won", "entrants_preserved"]):
		return MissionState.INVALID
	for key: String in value:
		if not value[key] is bool:
			return MissionState.INVALID
	return MissionState.INVALID if value["blade_wave_won"] and not value["pen_armed"] else ""

static func brief_completed(value: Dictionary, difficulty: String) -> bool:
	return value["pen_armed"] and (difficulty == "assisted" or (value["blade_wave_won"] and (difficulty != "severe" or value["entrants_preserved"])))

static func facts_error(value: Variant, phase: String, tick: int) -> String:
	var keys: Array[String] = ["completed", "challenges", "tunnel_closed", "gates_open", "broadcast_taken", "wave", "armed_entrants", "fallen_entrants"]
	if value is Dictionary and value.has("current"):
		keys.append("current")
	if phase not in PHASES or not EquipmentState.integer(tick, EquipmentState.MAX_EXACT_INTEGER) \
		or not M03MissionState._exact(value, keys) or not value["completed"] is Array \
		or not challenge_error(value["challenges"]).is_empty() \
		or not value["tunnel_closed"] is bool or not value["gates_open"] is bool or not value["broadcast_taken"] is bool \
		or not EquipmentState.integer(value["wave"], 5) \
		or not value["armed_entrants"] is Array or not value["fallen_entrants"] is Array:
		return MissionState.INVALID
	var n: int = value["completed"].size()
	var order: Array[String] = OBJECTIVES.duplicate()
	order.append("party_departed")
	var c: Dictionary = value["challenges"]
	if n > 7 or (phase == "departed") != (n == 7) or value.has("current") != (n < 7) \
		or c["pen_armed"] != (n >= 1) \
		or (n < 2 if value["tunnel_closed"] else n >= 3) \
		or value["broadcast_taken"] != (n >= 5) \
		or value["gates_open"] != (n >= 6):
		return MissionState.INVALID
	for index: int in range(n):
		if value["completed"][index] != order[index]:
			return MissionState.INVALID
	if n < 7:
		if n in [0, 4, 6]:
			if not M03MissionState._exact(value["current"], ["id", "action"]) or value["current"]["id"] != order[n] \
				or not M03MissionState._exact(value["current"]["action"], ["kind", "target"]) or value["current"]["action"]["kind"] != "use":
				return MissionState.INVALID
		else:
			if not M06MissionState._arrival(value["current"], order[n], 512.0):
				return MissionState.INVALID
	if phase == "briefing" and (n != 0 or c != {"pen_armed": false, "blade_wave_won": false, "entrants_preserved": true} \
		or value["tunnel_closed"] or value["gates_open"] or value["broadcast_taken"] or value["wave"] != 0 \
		or not value["armed_entrants"].is_empty() or not value["fallen_entrants"].is_empty()):
		return MissionState.INVALID
	return ""

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m15"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not M03MissionState._exact(value, keys) or value["id"] != MissionState.M15_ID \
		or geometry.get("id") != MissionState.M15_ID or not geometry.get("m15") is Dictionary \
		or not MissionState.valid_rules(value["rules"]) \
		or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 \
		or not EquipmentState.integer(value["changed_at"], int(message["tick"])) \
		or not value["party"] is Array or value["party"].size() > 4 \
		or not value["prompts"] is Array or value["prompts"].size() > value["party"].size() \
		or not facts_error(value["m15"], str(value["phase"]), int(message["tick"])).is_empty():
		return MissionState.INVALID
	var g: Dictionary = geometry["m15"]
	var p: Dictionary = value["m15"]
	if p["tunnel_closed"] != g["tunnel_closed"] or p["gates_open"] != g["gates_open"]:
		return MissionState.INVALID
	var n: int = p["completed"].size()
	if n < 7:
		var expected: Dictionary = g["objectives"][n] if n < 6 else {"id": "party_departed", "action": {"kind": "use", "target": g["departure"]}}
		if p["current"] != expected:
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
	var all_aboard: bool = not party.is_empty()
	for member: Dictionary in party.values():
		all_aboard = all_aboard and member["ready"] and member["alive"] and member["aboard"]
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or prompt["kind"] != "objective_use" \
			or value["phase"] != "in_progress" or n not in [0, 4, 6] \
			or (n == 6 and not all_aboard) or not party.has(prompt["player_id"]) or prompt["player_id"] in prompted:
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M15_ID or int(message["tick"]) < int(previous["tick"]) \
			or int(value["attempt"]) < int(old["attempt"]) or value["rules"] != old["rules"] \
			or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		if value["attempt"] == old["attempt"]:
			var before: Dictionary = old["m15"]
			if n < before["completed"].size() or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or int(value["changed_at"]) < int(old["changed_at"]) or p["wave"] < before["wave"]:
				return MissionState.INVALID
			for key: String in ["tunnel_closed", "gates_open", "broadcast_taken"]:
				if before[key] and not p[key]:
					return MissionState.INVALID
			for key: String in ["pen_armed", "blade_wave_won"]:
				if before["challenges"][key] and not p["challenges"][key]:
					return MissionState.INVALID
			if not before["challenges"]["entrants_preserved"] and p["challenges"]["entrants_preserved"]:
				return MissionState.INVALID
	return ""
