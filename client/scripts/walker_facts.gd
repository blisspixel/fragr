class_name WalkerFacts
extends RefCounted

## Registered machinery, translated from the same authored solids as the server.
const INVALID: String = "Invalid Walker facts."
const PHASES: Array[String] = ["dormant", "stomp_warning", "stomp", "artillery_warning", "artillery", "relocating", "recovery", "disabled"]
const MAX_HP: int = 900
const STOMP_RADIUS: float = 7.0
const SHELL_RADIUS: float = 3.0
const DURATIONS: Dictionary[String,int] = {"dormant":0,"stomp_warning":32,"stomp":4,"artillery_warning":40,"artillery":16,"relocating":400,"recovery":60,"disabled":0}

static func point(value: Variant) -> bool:
	return GrenadeFacts.point(value) and absf(float(value[0])) <= 512.0 \
		and float(value[1]) >= 0.0 and float(value[1]) <= 512.0 and absf(float(value[2])) <= 512.0

static func region(value: Variant, half: float) -> bool:
	if not M03MissionState._exact(value, ["min", "max"]) or not point(value["min"]) or not point(value["max"]):
		return false
	for axis: int in range(3):
		if float(value["min"][axis]) >= float(value["max"][axis]):
			return false
		if axis != 1 and (float(value["min"][axis]) < -half or float(value["max"][axis]) > half):
			return false
	return true

static func contains(bounds: Dictionary, value: Array) -> bool:
	for axis: int in range(3):
		if float(value[axis]) < float(bounds["min"][axis]) or float(value[axis]) > float(bounds["max"][axis]):
			return false
	return true

static func map_error(info: Dictionary) -> String:
	var value: Variant = info.get("walker")
	if value == null:
		return INVALID if info.has("walker") else ""
	if not M03MissionState._exact(value, ["solids", "stations", "activation", "arena", "approach"]) \
		or not info.get("solids") is Array or not MapGeometry._number(info.get("half_extent")):
		return INVALID
	var half: float = float(info["half_extent"])
	if not region(value["activation"], half) or not region(value["arena"], half) \
		or not point(value["approach"]) or not contains(value["arena"], value["approach"]) \
		or not value["solids"] is Array or value["solids"].size() != 5 \
		or not value["stations"] is Array or value["stations"].size() != 3:
		return INVALID
	if not contains(value["arena"],value["activation"]["min"]) or not contains(value["arena"],value["activation"]["max"]) \
		or float(value["arena"]["max"][0])-float(value["arena"]["min"][0]) > 120.0 \
		or float(value["arena"]["max"][2])-float(value["arena"]["min"][2]) > 120.0:
		return INVALID
	var seen: Array[int] = []
	for index: Variant in value["solids"]:
		if not EquipmentState.integer(index, info["solids"].size() - 1) or int(index) in seen:
			return INVALID
		seen.append(int(index))
	var presentation: Variant = info.get("presentation",{})
	if presentation is Dictionary:
		var decorations: Variant = presentation.get("decorations",[])
		if decorations is Array:
			for decoration: Variant in decorations:
				if decoration is Dictionary and EquipmentState.integer(decoration.get("solid"),info["solids"].size()-1) \
					and int(decoration["solid"]) in seen:
					return INVALID
	var stations: Array[Vector3] = []
	for station: Variant in value["stations"]:
		if not point(station) or float(station[1]) != 0.0 or not contains(value["arena"], station):
			return INVALID
		var at: Vector3 = GrenadeFacts.vector(station)
		if at in stations:
			return INVALID
		stations.append(at)
	var torso: Variant = info["solids"][seen[0]]
	if not _solid(torso) or float(torso.get("bottom",0.0)) < 3.0 or float(torso.get("top",MoveStep.WALL_TOP)) > 12.0 \
		or float(torso.get("top",MoveStep.WALL_TOP)) - float(torso.get("bottom",0.0)) < 1.0:
		return INVALID
	var origin: Array = value["stations"][0]
	if float(origin[0]) < float(torso["min_x"]) or float(origin[0]) > float(torso["max_x"]) \
		or float(origin[2]) < float(torso["min_z"]) or float(origin[2]) > float(torso["max_z"]):
		return INVALID
	for index: int in range(5):
		var solid: Variant = info["solids"][seen[index]]
		if not _solid(solid):
			return INVALID
		if index > 0 and (float(solid.get("bottom",0.0)) != 0.0 or float(solid.get("top",MoveStep.WALL_TOP)) < 2.0 or float(solid.get("top",MoveStep.WALL_TOP)) > float(torso["bottom"])):
			return INVALID
		for station: Variant in value["stations"]:
			var translated: Dictionary = translated_solid(info, seen[index], station)
			if not contains(value["arena"], [translated["min_x"], translated["bottom"], translated["min_z"]]) \
				or not contains(value["arena"], [translated["max_x"], translated["top"], translated["max_z"]]):
				return INVALID
	return ""

static func _solid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: String in ["min_x", "max_x", "min_z", "max_z"]:
		if not MapGeometry._number(value.get(key)):
			return false
	if not MapGeometry._number(value.get("bottom",0.0)) or not MapGeometry._number(value.get("top",MoveStep.WALL_TOP)):
		return false
	return float(value["min_x"]) < float(value["max_x"]) and float(value["min_z"]) < float(value["max_z"]) \
		and float(value.get("bottom",0.0)) >= 0.0 and float(value.get("bottom",0.0)) < float(value.get("top",MoveStep.WALL_TOP))

static func translated_solid(info: Dictionary, index: int, feet: Array) -> Dictionary:
	var solid: Dictionary = info["solids"][index].duplicate(true)
	solid["bottom"] = float(solid.get("bottom",0.0))
	solid["top"] = float(solid.get("top",MoveStep.WALL_TOP))
	var start: Array = info["walker"]["stations"][0]
	var dx: float = float(feet[0]) - float(start[0])
	var dz: float = float(feet[2]) - float(start[2])
	for key: String in ["min_x", "max_x"]:
		solid[key] = float(solid[key]) + dx
	for key: String in ["min_z", "max_z"]:
		solid[key] = float(solid[key]) + dz
	return solid

static func validation_error(snapshot: Dictionary, info: Dictionary = {}) -> String:
	var value: Variant = snapshot.get("walker")
	if value == null:
		return INVALID if snapshot.has("walker") or info.get("walker") is Dictionary else ""
	if not M03MissionState._exact(value, ["hp", "stage", "phase", "phase_started", "phase_ends", "feet", "target", "artillery_targets", "shells_left", "shells"]) \
		or not EquipmentState.integer(snapshot.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
		or not EquipmentState.integer(value["hp"], MAX_HP) or not MapGeometry._integer(value["stage"], 1, 3) \
		or not value["phase"] is String or value["phase"] not in PHASES \
		or not EquipmentState.integer(value["phase_started"], int(snapshot["tick"])) \
		or not EquipmentState.integer(value["phase_ends"], EquipmentState.MAX_EXACT_INTEGER) \
		or int(value["phase_ends"]) < int(value["phase_started"]) \
		or int(value["phase_ends"]) - int(value["phase_started"]) > 400 \
		or not point(value["feet"]) or not point(value["target"]) \
		or not value["artillery_targets"] is Array or value["artillery_targets"].size() != 3 \
		or not EquipmentState.integer(value["shells_left"], 36) \
		or not value["shells"] is Array or value["shells"].size() > 6 \
		or (int(value["hp"]) == 0) != (value["phase"] == "disabled"):
		return INVALID
	var expected_stage: int = 1 if int(value["hp"]) > 600 else 2 if int(value["hp"]) > 300 else 3
	var duration: int = DURATIONS[value["phase"]]
	if int(value["stage"]) != expected_stage or float(value["feet"][1]) != 0.0 \
		or int(value["phase_ends"])-int(value["phase_started"]) != duration \
		or (duration > 0 and int(value["phase_ends"]) <= int(snapshot["tick"])) \
		or value["shells"].size()+int(value["shells_left"]) > 36:
		return INVALID
	if value["phase"] == "dormant" and (int(value["hp"]) != MAX_HP or int(value["phase_started"]) != 0 or int(value["shells_left"]) != 36 or not value["shells"].is_empty()):
		return INVALID
	for target: Variant in value["artillery_targets"]:
		if not point(target):
			return INVALID
	var ids: Array[int] = []
	for shell: Variant in value["shells"]:
		if not M03MissionState._exact(shell, ["id", "position", "velocity", "age_ticks"]) \
			or not MapGeometry._integer(shell["id"], 1, 4294967295) or int(shell["id"]) in ids \
			or not point(shell["position"]) or not GrenadeFacts.point(shell["velocity"]) \
			or not EquipmentState.integer(shell["age_ticks"], 99):
			return INVALID
		for component: Variant in shell["velocity"]:
			if absf(float(component)) > 128.0:
				return INVALID
		ids.append(int(shell["id"]))
	if not info.is_empty():
		if not info.get("walker") is Dictionary or not map_error(info).is_empty() \
			or snapshot.get("map_id") != info.get("map_id"):
			return INVALID
		var geometry: Dictionary = info["walker"]
		if float(value["feet"][1]) != 0.0 or not contains(geometry["arena"], value["feet"]):
			return INVALID
		for index: Variant in geometry["solids"]:
			var solid: Dictionary = translated_solid(info, int(index), value["feet"])
			if not contains(geometry["arena"], [solid["min_x"],solid["bottom"],solid["min_z"]]) \
				or not contains(geometry["arena"], [solid["max_x"],solid["top"],solid["max_z"]]):
				return INVALID
	return ""
