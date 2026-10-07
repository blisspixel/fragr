class_name WaterMovement
extends RefCounted

const SWIM_DRAFT: float = 0.9
const SWIM_SPEED: float = 3.2

static func at(regions: Array, x: float, z: float) -> Dictionary:
	for region: Dictionary in regions:
		if x >= region["min"][0] and x <= region["max"][0] and z >= region["min"][1] and z <= region["max"][1]:
			return region
	return {}

static func live_step(state: Dictionary, input: Dictionary, speed: float, dt: float, arena: Dictionary, height: float) -> Dictionary:
	var regions: Array = arena.get("water_regions", [])
	if regions.is_empty():
		return MoveStep.live_step_with_height(state, input, speed, dt, arena, height)
	var water: Dictionary = at(regions, float(state["x"]), float(state["z"]))
	var swimming: bool = not water.is_empty() and float(state["y"]) < float(water["level"]) - 0.25 and MoveStep.arena_support_height(arena, float(state["x"]), float(state["z"]), float(state["y"]) + MoveStep.STEP_UP) < float(water["level"]) - SWIM_DRAFT
	# The same temporary support surfaces let ordinary collision own shore steps.
	var supported: Dictionary = arena.duplicate(true)
	for region: Dictionary in regions:
		var top: float = float(region["level"]) - SWIM_DRAFT
		var bottom: float = float(region["level"]) - float(region["depth"])
		if top > bottom:
			supported["solids"].append({"min_x": region["min"][0], "max_x": region["max"][0], "min_z": region["min"][1], "max_z": region["max"][1], "bottom": bottom, "top": top})
	state = state.duplicate()
	if not water.is_empty():
		var surface_feet: float = float(water["level"]) - SWIM_DRAFT
		if float(state["y"]) < surface_feet and not MoveStep.arena_blocked_body_at(arena, float(state["x"]), float(state["z"]), surface_feet, surface_feet):
			state["y"] = surface_feet
			state["vy"] = maxf(float(state["vy"]), 0.0)
	var moved: Dictionary = MoveStep.live_step_with_height(state, input, minf(speed, SWIM_SPEED) if swimming else speed, dt, supported, height)
	water = at(regions, float(moved["x"]), float(moved["z"]))
	if not water.is_empty():
		var surface_feet: float = float(water["level"]) - SWIM_DRAFT
		var floor_y: float = MoveStep.arena_support_height(arena, float(moved["x"]), float(moved["z"]), float(moved["y"]) + MoveStep.STEP_UP)
		if floor_y < surface_feet and float(moved["y"]) < surface_feet and not MoveStep.arena_blocked_body_at(arena, float(moved["x"]), float(moved["z"]), surface_feet, surface_feet):
			moved["y"] = surface_feet
			moved["vy"] = 0.0
	return moved
