class_name M08NeutralBodies
extends RefCounted

## Mirror of the non-wire archive neutral layout. Registered surfaces and
## accepted mission facts own placement; these are not damageable pawns.
const KEYS: Array[String] = ["m08/renn", "m08/captive/0", "m08/captive/1", "m08/captive/2", "m08/captive/3"]
const PANELS: Array[String] = ["m08_registry", "m08_bay_release", "m08_freight_departure"]

static func layout(info: Dictionary) -> Dictionary:
	if not MapGeometry.validation_error(info).is_empty() or not info.get("presentation") is Dictionary:
		return {}
	var frames: Dictionary[String, Transform3D] = {}
	var floors: Dictionary[String, float] = {}
	for detail: Dictionary in info["presentation"]["decorations"]:
		var kind: String = str(detail["kind"])
		if kind not in PANELS:
			continue
		if frames.has(kind):
			return {}
		var host: Dictionary = info["solids"][int(detail["solid"])]
		frames[kind] = MapDecoration.placement(host, detail)
		floors[kind] = MoveStep.solid_bottom(host)
	if frames.size() != PANELS.size():
		return {}
	var registry: Transform3D = frames[PANELS[0]]
	# Match the server's measured 2 cm desk-clearance correction.
	var renn: Vector3 = registry.origin - registry.basis.z * 1.52 - registry.basis.x * 0.6
	renn.y = floors[PANELS[0]]
	var held: Array[Vector3] = []
	var released: Array[Vector3] = []
	var bays: Transform3D = frames[PANELS[1]]
	var lane: Transform3D = frames[PANELS[2]]
	for index: int in range(4):
		var captive: Vector3 = bays.origin + bays.basis.z * 0.8 + bays.basis.x * (-4.5 + index * 3.0)
		captive.y = floors[PANELS[1]]
		held.append(captive)
		var waiting: Vector3 = lane.origin + lane.basis.z * 2.5 + Vector3([-2.49, -1.0, 1.0, 2.49][index], 0.0, -3.5)
		waiting.y = 0.0
		released.append(waiting)
	var all_feet: Array[Vector3] = [renn]
	all_feet.append_array(held)
	all_feet.append_array(released)
	var half: float = float(info["half_extent"])
	for feet: Vector3 in all_feet:
		if not feet.is_finite() or absf(feet.x) > half or absf(feet.z) > half or feet.y < 0.0 or feet.y > 512.0:
			return {}
	return {"renn": renn, "held": held, "released": released}

static func people(bound: Dictionary, joined: bool, released: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if bound.is_empty():
		return result
	if joined:
		result.append({"key": KEYS[0], "feet": bound["renn"]})
	var feet: Array = bound["released" if released else "held"]
	for index: int in range(4):
		result.append({"key": KEYS[index + 1], "feet": feet[index]})
	return result
