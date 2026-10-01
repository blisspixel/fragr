class_name M05Tram
extends RefCounted

const SUPPORT_EPSILON: float = 0.05

## Mirror of mission/m05/platform.rs. This changes presentation prediction only.
static func supported(body: Dictionary, solid: Dictionary, jumping: bool) -> bool:
	return not jumping and absf(float(body["vy"])) <= 0.001 \
		and absf(float(body["y"]) - MoveStep.solid_top(solid)) <= SUPPORT_EPSILON \
		and float(body["x"]) >= float(solid["min_x"]) and float(body["x"]) <= float(solid["max_x"]) \
		and float(body["z"]) >= float(solid["min_z"]) and float(body["z"]) <= float(solid["max_z"])

static func carried(body: Dictionary, delta_z: float, other: Dictionary) -> Dictionary:
	if not is_finite(delta_z) or absf(delta_z) > 0.0751:
		return {}
	var to: float = float(body["z"]) + delta_z
	if absf(float(body["x"])) > float(other["half"]) - MoveStep.RADIUS or absf(to) > float(other["half"]) - MoveStep.RADIUS:
		return {}
	for solid: Dictionary in other["solids"]:
		if float(body["x"]) + MoveStep.RADIUS > float(solid["min_x"]) and float(body["x"]) - MoveStep.RADIUS < float(solid["max_x"]) \
			and minf(float(body["z"]), to) - MoveStep.RADIUS < float(solid["max_z"]) \
			and maxf(float(body["z"]), to) + MoveStep.RADIUS > float(solid["min_z"]) \
			and float(body["y"]) + MoveStep.BODY_HEIGHT > MoveStep.solid_bottom(solid) and float(body["y"]) < MoveStep.solid_top(solid):
			return {}
	var result: Dictionary = body.duplicate()
	result["z"] = to
	return result

static func solid_at(geometry: Dictionary, feet: Array) -> Dictionary:
	var solid: Dictionary = geometry["tram_solid"].duplicate()
	var delta: float = float(feet[2]) - float(geometry["m05"]["tram"]["start"][2])
	solid["min_z"] = float(solid["min_z"]) + delta
	solid["max_z"] = float(solid["max_z"]) + delta
	return solid
