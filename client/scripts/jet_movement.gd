class_name JetMovement
extends RefCounted
## Mirror of server/src/movement/jetpack.rs, checked by test_jet_golden.gd
## against client/golden/jetpack_vectors.json. Prediction presentation only:
## the server's Ack fuel and body always win.

const FUEL_MAX: int = 60
const REFILL_PER_TICK: int = 3
const THRUST: float = 34.0
const MAX_RISE: float = 4.5
const DEFAULT_CEILING: float = 9.0

## One live step with the pack worn. Returns the moved body with its `fuel`
## and whether this step burned thrust under `thrusting`. A short render slice
## passes `account_fuel` false: thrust shapes the pose, the tick owns the count.
static func live_step(state: Dictionary, input: Dictionary, speed: float, dt: float, arena: Dictionary, height: float, fuel: int, ceiling: float, account_fuel: bool = true) -> Dictionary:
	var held: int = mini(fuel, FUEL_MAX)
	var feet: float = float(state["y"])
	var support: float = MoveStep.arena_support_height(arena, float(state["x"]), float(state["z"]), feet)
	var airborne: bool = not MoveStep.grounded(feet, support, float(state["vy"]))
	var thrusting: bool = bool(input.get("jump", false)) and airborne and held > 0 and feet < ceiling
	var start: Dictionary = state.duplicate()
	if thrusting:
		# Integration subtracts this step's gravity afterwards; the cap is
		# stated after gravity, and thrust never slows a faster jump.
		var boosted: float = minf(float(state["vy"]) + THRUST * dt, MAX_RISE + MoveStep.GRAVITY * dt)
		start["vy"] = maxf(float(state["vy"]), boosted)
	var moved: Dictionary = WaterMovement.live_step(start, input, speed, dt, arena, height)
	if float(moved["y"]) > ceiling and float(moved["y"]) > feet:
		moved["y"] = maxf(ceiling, feet)
		moved["vy"] = minf(float(moved["vy"]), 0.0)
	var next: int = held
	if account_fuel:
		if thrusting:
			next = held - 1
		elif MoveStep.grounded(float(moved["y"]), MoveStep.arena_support_height(arena, float(moved["x"]), float(moved["z"]), float(moved["y"])), float(moved["vy"])):
			next = mini(held + REFILL_PER_TICK, FUEL_MAX)
	moved["fuel"] = next
	moved["thrusting"] = thrusting
	return moved
