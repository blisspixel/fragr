class_name M03MissionState
extends RefCounted

## Scheduled Service mirrors protocol/mission.rs. Facts grant no client authority.
const MAP_ID: int = 1003
const MAST_HP: int = 40
const MAX_CARS: int = 4
const CAPTIVE_ROUTE_EPSILON: float = 0.05
const PHASES: Array[String] = ["briefing", "in_progress", "departed"]

static func _exact(value: Variant, keys: Array[String]) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true

static func _region(value: Variant, half: float) -> bool:
	if not _exact(value, ["min", "max"]) or not MissionState._point(value["min"], half) or not MissionState._point(value["max"], half):
		return false
	for axis: int in range(3):
		if float(value["min"][axis]) >= float(value["max"][axis]):
			return false
	return true

static func _inside(point: Array, region: Dictionary) -> bool:
	for axis: int in range(3):
		if float(point[axis]) < float(region["min"][axis]) or float(point[axis]) > float(region["max"][axis]):
			return false
	return true

static func _pair(value: Variant, half: float) -> bool:
	return value is Array and value.size() == 2 and MissionState._point(value[0], half) and MissionState._point(value[1], half)

static func _same_point(first: Array, second: Array) -> bool:
	for axis: int in range(3):
		if absf(float(first[axis]) - float(second[axis])) > 0.01:
			return false
	return true

static func _released_point(point: Array, held: Array, safe: Array) -> bool:
	var start: Vector3 = Vector3(float(held[0]), float(held[1]), float(held[2]))
	var end: Vector3 = Vector3(float(safe[0]), float(safe[1]), float(safe[2]))
	var current: Vector3 = Vector3(float(point[0]), float(point[1]), float(point[2]))
	var route: Vector3 = end - start
	var fraction: float = clampf((current - start).dot(route) / route.length_squared(), 0.0, 1.0) if route.length_squared() > 0.0 else 0.0
	return current.distance_to(start + route * fraction) <= CAPTIVE_ROUTE_EPSILON

static func map_error(info: Dictionary) -> String:
	var value: Variant = info.get("m03")
	if not _exact(value, ["mast", "mast_shutdown", "departure", "boarding", "cars", "companion_start"]) \
		or info.get("map_id") != MAP_ID or info.get("geometry_version") != 2 \
		or info.get("mission") != null or info.get("m02_objectives") != null or info.has("m04") or info.get("m02_side_ward", false) != false \
		or not MapGeometry._number(info.get("half_extent")) or not info.get("solids") is Array \
		or not info.get("presentation") is Dictionary or not info["presentation"].get("decorations") is Array:
		return MissionState.INVALID
	var half: float = float(info["half_extent"])
	var mast: Variant = value["mast"]
	var solids: Array = info["solids"]
	if half < 2.0 or half > MapGeometry.MAX_HALF or not value["mast_shutdown"] is bool \
		or not _exact(mast, ["solid", "approach", "aim"]) or solids.is_empty() \
		or not EquipmentState.integer(mast["solid"], solids.size() - 1) \
		or not MissionState._point(mast["approach"], half) or not MissionState._point(mast["aim"], half) \
		or not _region(value["boarding"], half) or not MissionState._point(value["companion_start"], half):
		return MissionState.INVALID
	# The original aim remains the contract after the pod falls elsewhere.
	if not value["mast_shutdown"]:
		var solid: Variant = solids[int(mast["solid"])]
		if not solid is Dictionary:
			return MissionState.INVALID
		var bounds: Dictionary = {"min": [solid.get("min_x"), solid.get("bottom"), solid.get("min_z")],
			"max": [solid.get("max_x"), solid.get("top"), solid.get("max_z")]}
		if not _region(bounds, MapGeometry.MAX_HALF * 2.0) or not _inside(mast["aim"], bounds):
			return MissionState.INVALID
	var departure: Variant = value["departure"]
	var decorations: Array = info["presentation"]["decorations"]
	if not _exact(departure, ["decoration", "approach"]) or decorations.is_empty() \
		or not EquipmentState.integer(departure["decoration"], decorations.size() - 1) \
		or not decorations[int(departure["decoration"])] is Dictionary \
		or decorations[int(departure["decoration"])].get("kind") not in ["lift_control", "m03_board_train"] \
		or not MissionState._point(departure["approach"], half) or not _inside(departure["approach"], value["boarding"]) \
		or not value["cars"] is Array or value["cars"].is_empty() or value["cars"].size() > MAX_CARS:
		return MissionState.INVALID
	var ids: Array[String] = []
	for car: Variant in value["cars"]:
		if not _exact(car, ["id", "release", "held", "safe"]) or not MissionState.valid_objective_id(car["id"]) \
			or car["id"] in ids or not _region(car["release"], half) or not _pair(car["held"], half) or not _pair(car["safe"], half):
			return MissionState.INVALID
		ids.append(car["id"])
		for person: int in range(2):
			if absf(float(car["held"][person][1]) - float(car["safe"][person][1])) > 0.01:
				return MissionState.INVALID
	return ""

static func geometry_for(info: Dictionary) -> Dictionary:
	return {"id": MissionState.M03_ID, "map_id": int(info["map_id"]), "half_extent": float(info["half_extent"]), "m03": info["m03"].duplicate(true)}

## MapInfo can replace the mast world, but cannot replace its bound mission.
static func same_contract(first: Dictionary, second: Dictionary) -> bool:
	if first.get("id") != MissionState.M03_ID or second.get("id") != MissionState.M03_ID \
		or first.get("map_id") != second.get("map_id") or first.get("half_extent") != second.get("half_extent") \
		or not first.get("m03") is Dictionary or not second.get("m03") is Dictionary:
		return false
	var before: Dictionary = first["m03"].duplicate(true)
	var after: Dictionary = second["m03"].duplicate(true)
	before.erase("mast_shutdown")
	after.erase("mast_shutdown")
	return before == after

static func validation_error(message: Dictionary, geometry: Dictionary, previous: Dictionary = {}) -> String:
	var value: Variant = message.get("state")
	var keys: Array[String] = ["id", "rules", "attempt", "phase", "changed_at", "party", "prompts", "m03"]
	if value is Dictionary and value.has("run"):
		keys.append("run")
	if not EquipmentState.integer(message.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not _exact(value, keys) or value["id"] != MissionState.M03_ID or geometry.get("id") != MissionState.M03_ID \
		or not geometry.get("m03") is Dictionary or not MissionState.valid_rules(value["rules"]) \
		or not value["phase"] is String or value["phase"] not in PHASES \
		or not EquipmentState.integer(value["attempt"], 4294967295) or int(value["attempt"]) < 1 \
		or not EquipmentState.integer(value["changed_at"], int(message["tick"])) \
		or not value["party"] is Array or value["party"].size() > 4 \
		or not value["prompts"] is Array or value["prompts"].size() > value["party"].size():
		return MissionState.INVALID
	var progress: Variant = value["m03"]
	var departed: bool = value["phase"] == "departed"
	var progress_keys: Array[String] = ["mast_hp", "mast_secured", "train_secured", "cars"]
	if not departed:
		progress_keys.append("current")
	if not _exact(progress, progress_keys) \
		or not EquipmentState.integer(progress["mast_hp"], MAST_HP) \
		or not progress["mast_secured"] is bool or not progress["train_secured"] is bool \
		or not progress["cars"] is Array or progress["cars"].size() != geometry["m03"]["cars"].size() \
		or (int(progress["mast_hp"]) == 0) != geometry["m03"]["mast_shutdown"] \
		or (int(progress["mast_hp"]) < MAST_HP and not progress["mast_secured"]) \
		or (departed and (int(progress["mast_hp"]) != 0 or not progress["train_secured"])):
		return MissionState.INVALID
	if value["phase"] == "briefing" and (int(progress["mast_hp"]) != MAST_HP or progress["mast_secured"] or progress["train_secured"]):
		return MissionState.INVALID
	if not departed:
		var current: Variant = progress["current"]
		if not _exact(current, ["id", "action"]):
			return MissionState.INVALID
		var expected: Dictionary
		if int(progress["mast_hp"]) > 0:
			var mast: Dictionary = geometry["m03"]["mast"]
			expected = {"id": "mast_disabled", "action": {"kind": "shoot", "solid": mast["solid"], "approach": mast["approach"], "aim": mast["aim"]}}
		else:
			expected = {"id": "party_departed", "action": {"kind": "use", "target": geometry["m03"]["departure"]}}
		if current != expected:
			return MissionState.INVALID
	for index: int in range(progress["cars"].size()):
		var car: Variant = progress["cars"][index]
		var bound: Dictionary = geometry["m03"]["cars"][index]
		if not _exact(car, ["id", "released", "captives"]) or car["id"] != bound["id"] or not car["released"] is bool \
			or not _pair(car["captives"], float(geometry["half_extent"])) or (value["phase"] == "briefing" and car["released"]):
			return MissionState.INVALID
		for person: int in range(2):
			var valid: bool = _released_point(car["captives"][person], bound["held"][person], bound["safe"][person]) if car["released"] else _same_point(car["captives"][person], bound["held"][person])
			if not valid:
				return MissionState.INVALID
	var party: Dictionary = {}
	var aboard: bool = not value["party"].is_empty()
	for member: Variant in value["party"]:
		if not _exact(member, ["id", "name", "ready", "alive", "aboard"]) or not MissionState._uuid(member["id"]) \
			or party.has(member["id"]) or not member["name"] is String or member["name"].is_empty() or member["name"].length() > 48 \
			or not member["ready"] is bool or not member["alive"] is bool or not member["aboard"] is bool \
			or (member["aboard"] and (not member["alive"] or not member["ready"] or value["phase"] == "briefing")):
			return MissionState.INVALID
		for character: String in member["name"]:
			var code: int = character.unicode_at(0)
			if code < 32 or (code >= 127 and code <= 159):
				return MissionState.INVALID
		party[member["id"]] = member
		aboard = aboard and member["alive"] and member["ready"] and member["aboard"]
	if value.has("run") and not MissionState.valid_run(value):
		return MissionState.INVALID
	var prompted: Array[String] = []
	for prompt: Variant in value["prompts"]:
		if value["phase"] != "in_progress" or int(progress["mast_hp"]) != 0 or not progress["train_secured"] or not aboard \
			or not _exact(prompt, ["player_id", "kind"]) or prompt["kind"] != "objective_use" \
			or not prompt["player_id"] is String or not party.has(prompt["player_id"]) or prompt["player_id"] in prompted:
			return MissionState.INVALID
		prompted.append(prompt["player_id"])
	if not previous.is_empty():
		var old: Dictionary = previous["state"]
		if old.get("id") != MissionState.M03_ID or int(message["tick"]) < int(previous["tick"]) \
			or int(value["attempt"]) < int(old["attempt"]) or value["rules"] != old["rules"] \
			or not MissionState.run_follows(value.get("run"), old.get("run")):
			return MissionState.INVALID
		if int(value["attempt"]) == int(old["attempt"]):
			var before: Dictionary = old["m03"]
			if int(progress["mast_hp"]) > int(before["mast_hp"]) or int(value["changed_at"]) < int(old["changed_at"]) \
				or PHASES.find(value["phase"]) < PHASES.find(old["phase"]) \
				or (before["mast_secured"] and not progress["mast_secured"]) or (before["train_secured"] and not progress["train_secured"]):
				return MissionState.INVALID
			for index: int in range(progress["cars"].size()):
				if before["cars"][index]["released"] and not progress["cars"][index]["released"]:
					return MissionState.INVALID
	return ""
