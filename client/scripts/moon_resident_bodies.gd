class_name MoonResidentBodies
extends RefCounted

static func validation_error(info: Dictionary) -> String:
	if not MapGeometry.validation_error(info).is_empty():
		return "Invalid resident map geometry."
	if int(info["map_id"]) not in [1006, 1007]:
		return ""
	if not info.get("presentation") is Dictionary:
		return "Invalid resident presentation."
	var port: bool = info["map_id"] == 1006
	var kind: String = "m06_family_window" if port else "m07_window_figure"
	var count: int = 0
	for detail: Dictionary in info.get("presentation", {}).get("decorations", []):
		if detail["kind"] == kind:
			count += 1
	if count > 1 or (count == 1 and read(info).size() != (2 if port else 1)):
		return "Invalid resident panel or feet."
	return ""

## Exact static resident placements mirrored by protocol/moon_residents.rs.
static func read(info: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not MapGeometry.validation_error(info).is_empty() or not info.get("presentation") is Dictionary:
		return result
	var port: bool = info.get("map_id") == 1006
	var kind: String = "m06_family_window" if port else "m07_window_figure"
	if not port and info.get("map_id") != 1007:
		return result
	var panel: Dictionary = {}
	for detail: Dictionary in info["presentation"]["decorations"]:
		if detail["kind"] == kind:
			if not panel.is_empty():
				return []
			panel = detail
	if panel.is_empty() or panel["face"] not in ["west", "east", "north", "south"]:
		return result
	var host: Dictionary = info["solids"][int(panel["solid"]) ]
	var placed: Transform3D = MapDecoration.placement(host, panel)
	var out: Vector3 = placed.basis.z
	for index: int in range(2 if port else 1):
		var feet: Vector3
		if port:
			feet = Vector3((float(host["min_x"]) + float(host["max_x"])) * 0.5, 0.0, (float(host["min_z"]) + float(host["max_z"])) * 0.5) - out * 3.0 + Vector3(0.8, 0.0, -0.5 + index * 3.0)
		else:
			var thickness: float = absf(out.dot(MapDecoration._size(host)))
			feet = placed.origin - out * (MapDecoration.OFFSET + thickness + 0.7)
			feet.y = MoveStep.solid_bottom(host) - 1.0
		if not feet.is_finite() or absf(feet.x) > float(info["half_extent"]) or absf(feet.z) > float(info["half_extent"]) or feet.y < 0.0:
			return []
		result.append({"key": ("m06/resident/" if port else "m07/resident/") + str(index), "feet": feet})
	return result
