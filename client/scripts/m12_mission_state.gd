class_name M12MissionState
extends RefCounted

## Habitat facts stay authoritative. Capability 44 includes shelter, pumps and aid.
const MAP_ID: int = 1012
const PUMP_HEALTH: int = 100
const OBJECTIVES: Array[String] = ["market_secured", "arc_found", "greenhouse_secured", "shelter_route_secured", "aid_force_arrived", "coalition_commitment"]
const DEPARTURE: String = "party_departed"
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]

static func map_error(info: Dictionary) -> String:
	if info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 \
		or info.get("mission") != null or info.get("m02_objectives") != null \
		or not MapGeometry._number(info.get("half_extent")) \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	for key: String in ["m03", "m04", "m05", "m06", "m07", "m08", "m09", "m10", "m11"]:
		if info.has(key):
			return MissionState.INVALID
	if info.has("m02_side_ward") and (not info["m02_side_ward"] is bool or info["m02_side_ward"]):
		return MissionState.INVALID
	return map_value_error(info.get("m12"), float(info["half_extent"]), info["presentation"]["decorations"], info.get("solids", []))

static func geometry_for(info: Dictionary) -> Dictionary:
	return {"id": MissionState.M12_ID, "map_id": int(info["map_id"]),
		"half_extent": float(info["half_extent"]), "m12": info["m12"].duplicate(true),
		"solids": info["solids"].duplicate(true), "presentation": info["presentation"].duplicate(true)}

static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M12_ID or second.get("id") != MissionState.M12_ID or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") or first.get("presentation") != second.get("presentation"):
		return false
	var a: Dictionary = first["m12"].duplicate(true)
	var b: Dictionary = second["m12"].duplicate(true)
	var old_open: bool = a["shelter_open"]
	var new_open: bool = b["shelter_open"]
	a.erase("shelter_open")
	b.erase("shelter_open")
	if a != b:
		return false
	var old_solids: Array = first["solids"].duplicate(true)
	var new_solids: Array = second["solids"].duplicate(true)
	var door: int = int(a["shelter_door"])
	if old_open == new_open:
		return old_solids == new_solids
	var old_door: Dictionary = old_solids[door]
	var new_door: Dictionary = new_solids[door]
	var closed: Dictionary = new_door if old_open else old_door
	var opened: Dictionary = old_door if old_open else new_door
	if absf(float(opened["bottom"]) - float(closed["top"]) - 1.2) > 0.001 or absf((float(opened["top"]) - float(opened["bottom"])) - (float(closed["top"]) - float(closed["bottom"]))) > 0.001:
		return false
	old_door["bottom"] = new_door["bottom"]
	old_door["top"] = new_door["top"]
	return old_solids == new_solids

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m12"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not M03MissionState._exact(value, keys) or value["id"] != MissionState.M12_ID \
		or geometry.get("id") != MissionState.M12_ID or not geometry.get("m12") is Dictionary \
		or not MissionState.valid_rules(value["rules"]) or value["phase"] not in PHASES \
		or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 \
		or not EquipmentState.integer(value["changed_at"], int(message["tick"])) \
		or not value["party"] is Array or value["party"].size() > 4 \
		or not value["prompts"] is Array or value["prompts"].size() > value["party"].size() \
		or not facts_error(value["m12"], str(value["phase"]), int(message["tick"])).is_empty():
		return MissionState.INVALID
	var bound: Dictionary = geometry["m12"]
	var progress: Dictionary = value["m12"]
	var completed: Array = progress["completed"]
	if progress["challenges"]["shelter_opened"] != bound["shelter_open"]:
		return MissionState.INVALID
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
	var all_aboard: bool = not party.is_empty()
	for member: Dictionary in party.values():
		all_aboard = all_aboard and member["ready"] and member["alive"] and member["aboard"]
	var challenges_now: Dictionary = progress["challenges"]
	var count: int = completed.size()
	var use_available: bool = (count >= 3 and not challenges_now["workers_released"]) or (count >= 4 and not challenges_now["shelter_opened"]) or count == 5 or (count == 6 and all_aboard)
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if not M03MissionState._exact(prompt, ["player_id", "kind"]) or prompt["kind"] != "objective_use" \
			or value["phase"] != "in_progress" or not party.has(prompt["player_id"]) \
			or prompt["player_id"] in prompted or not party[prompt["player_id"]]["alive"] or not party[prompt["player_id"]]["ready"] \
			or not use_available:
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M12_ID or int(message["tick"]) < int(previous["tick"]) \
			or int(value["attempt"]) < int(old["attempt"]) or value["rules"] != old["rules"] \
			or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		if int(value["attempt"]) == int(old["attempt"]):
			var before: Dictionary = old["m12"]
			if completed.size() < before["completed"].size() or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or int(value["changed_at"]) < int(old["changed_at"]):
				return MissionState.INVALID
			var challenges: Dictionary = progress["challenges"]
			var prior: Dictionary = before["challenges"]
			for pump: int in range(2):
				if int(challenges["pump_health"][pump]) > int(prior["pump_health"][pump]):
					return MissionState.INVALID
			if not before["aid_vehicle_ids"].is_empty() and before["aid_vehicle_ids"] != progress["aid_vehicle_ids"]:
				return MissionState.INVALID
			for key: String in ["shelter_opened", "workers_released"]:
				if prior[key] and not challenges[key]:
					return MissionState.INVALID
			if int(challenges["assessor_wreck_union_kills"]) < int(prior["assessor_wreck_union_kills"]):
				return MissionState.INVALID
			for key: String in ["first_pump_damage_at", "shelter_route_secured_at"]:
				if prior.has(key) and challenges.get(key) != prior[key]:
					return MissionState.INVALID
	return ""


static func map_value_error(value: Variant, half: float, decorations: Array, solids: Array) -> String:
	if not M03MissionState._exact(value, ["objectives","shelter_release","worker_release","commitment","departure","boarding","shelter_door","shelter_open","shelter_people","workers","pumps","aid_vehicles"]) or not is_finite(half) or half < 2.0 or half > MapGeometry.MAX_HALF or not value["objectives"] is Array or value["objectives"].size() != 6 or not M03MissionState._region(value["boarding"],half) or not value["shelter_open"] is bool or not EquipmentState.integer(value["shelter_door"],solids.size()-1):
		return MissionState.INVALID
	for index: int in range(5):
		if not M06MissionState._arrival(value["objectives"][index],OBJECTIVES[index],half):
			return MissionState.INVALID
	if value["objectives"][5] != {"id":OBJECTIVES[5],"action":{"kind":"use","target":value["commitment"]}}:
		return MissionState.INVALID
	var controls: Array[int] = []
	for key: String in ["shelter_release","worker_release","commitment","departure"]:
		if not M04MissionState._control(value[key],decorations,half,["terminal"]) or int(value[key]["decoration"]) in controls:
			return MissionState.INVALID
		controls.append(int(value[key]["decoration"]))
	if not M03MissionState._inside(value["departure"]["approach"],value["boarding"]):
		return MissionState.INVALID
	for group: String in ["shelter_people","workers"]:
		if not value[group] is Array or value[group].size() != 3:
			return MissionState.INVALID
		for index: int in range(3):
			var feet: Variant = value[group][index]
			if not MissionState._point(feet,half):
				return MissionState.INVALID
			for prior: int in range(index):
				var old: Array = value[group][prior]
				if Vector2(float(feet[0])-float(old[0]),float(feet[2])-float(old[2])).length() < MoveStep.RADIUS*2.0:
					return MissionState.INVALID
	if not value["pumps"] is Array or value["pumps"].size() != 2 or not value["aid_vehicles"] is Array or value["aid_vehicles"].size() != 2:
		return MissionState.INVALID
	var hosts: Array[int] = [int(value["shelter_door"])]
	for index: int in range(2):
		var pump: Variant = value["pumps"][index]
		if not M03MissionState._exact(pump,["id","solids","health"]) or pump["id"] != ["west","east"][index] or pump["health"] != 100 or not pump["solids"] is Array or pump["solids"].size() != 3:
			return MissionState.INVALID
		for host: Variant in pump["solids"]:
			if not EquipmentState.integer(host,solids.size()-1) or int(host) in hosts:
				return MissionState.INVALID
			hosts.append(int(host))
		var aid: Variant = value["aid_vehicles"][index]
		if not M03MissionState._exact(aid,["feet","yaw"]) or not MissionState._point(aid["feet"],half) or not MapGeometry._number(aid["yaw"]) or float(aid["yaw"]) < 0.0 or float(aid["yaw"]) >= TAU:
			return MissionState.INVALID
	return ""

static func challenge_error(value: Variant, tick: int) -> String:
	var keys: Array[String] = ["shelter_opened","workers_released","pump_health","assessor_wreck_union_kills"]
	if value is Dictionary:
		for key: String in ["first_pump_damage_at","shelter_route_secured_at"]:
			if value.has(key):
				keys.append(key)
	if not M03MissionState._exact(value,keys) or not value["shelter_opened"] is bool or not value["workers_released"] is bool or not value["pump_health"] is Array or value["pump_health"].size() != 2 or not EquipmentState.integer(value["assessor_wreck_union_kills"],3):
		return MissionState.INVALID
	for hp: Variant in value["pump_health"]:
		if not EquipmentState.integer(hp,100):
			return MissionState.INVALID
	for key: String in ["first_pump_damage_at","shelter_route_secured_at"]:
		if value.has(key) and not EquipmentState.integer(value[key],tick):
			return MissionState.INVALID
	if value.has("first_pump_damage_at") != (int(value["pump_health"][0]) != 100 or int(value["pump_health"][1]) != 100) or (value["shelter_opened"] and not value.has("shelter_route_secured_at")):
		return MissionState.INVALID
	return ""

static func pumps_intact_at_route_secure(challenges: Dictionary) -> bool:
	return challenges.has("shelter_route_secured_at") and (not challenges.has("first_pump_damage_at") or int(challenges["first_pump_damage_at"]) > int(challenges["shelter_route_secured_at"]))

static func brief_completed(challenges: Dictionary, difficulty: String) -> bool:
	return challenges.has("shelter_route_secured_at") and (difficulty == "assisted" or int(challenges.get("assessor_wreck_union_kills",0)) > 0) and (difficulty != "severe" or pumps_intact_at_route_secure(challenges))

static func facts_error(value: Variant, phase: String, tick: int) -> String:
	if phase not in PHASES or tick < 0 or tick > EquipmentState.MAX_EXACT_INTEGER:
		return MissionState.INVALID
	var keys: Array[String] = ["completed","challenges","aid_vehicle_ids"]
	if value is Dictionary and value.has("current"):
		keys.append("current")
	if not M03MissionState._exact(value,keys) or not value["completed"] is Array or not challenge_error(value["challenges"],tick).is_empty() or not value["aid_vehicle_ids"] is Array:
		return MissionState.INVALID
	var count: int = value["completed"].size()
	var c: Dictionary = value["challenges"]
	var order: Array[String] = OBJECTIVES.duplicate()
	order.append(DEPARTURE)
	if count > 7 or (phase == "departed") != (count == 7) or value.has("current") != (count <= 6) or c.has("shelter_route_secured_at") != (count >= 4) or (c["workers_released"] and count < 3) or (phase == "briefing" and (count != 0 or c["shelter_opened"] or c["workers_released"] or int(c["pump_health"][0]) != 100 or int(c["pump_health"][1]) != 100 or int(c["assessor_wreck_union_kills"]) != 0)):
		return MissionState.INVALID
	for index: int in range(count):
		if value["completed"][index] != order[index]:
			return MissionState.INVALID
	var aid: Array = value["aid_vehicle_ids"]
	if aid.size() != (2 if count >= 5 else 0):
		return MissionState.INVALID
	for index: int in range(aid.size()):
		if not EquipmentState.integer(aid[index],4294967295) or int(aid[index]) == 0 or aid.slice(0,index).has(aid[index]):
			return MissionState.INVALID
	if count < 5:
		if not M06MissionState._arrival(value["current"],OBJECTIVES[count],MapGeometry.MAX_HALF*2.0):
			return MissionState.INVALID
	elif count <= 6:
		var current: Variant = value["current"]
		if not M03MissionState._exact(current,["id","action"]) or current["id"] != order[count] or not M03MissionState._exact(current["action"],["kind","target"]) or current["action"]["kind"] != "use" or not M03MissionState._exact(current["action"]["target"],["decoration","approach"]) or not EquipmentState.integer(current["action"]["target"]["decoration"],MapDecoration.MAX_DETAILS-1) or not MissionState._point(current["action"]["target"]["approach"],MapGeometry.MAX_HALF*2.0):
			return MissionState.INVALID
	return ""
