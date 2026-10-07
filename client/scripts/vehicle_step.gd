class_name VehicleStep
extends RefCounted

## Pure mirror of server/src/vehicles.rs. No nodes or game outcomes.
const HALF_WIDTH: float = 0.95
const BODY_TOP: float = 1.35
const CLEARANCE_HEIGHT: float = 2.75
const TOP_SPEED: float = 16.0
const REVERSE_SPEED: float = 6.0
const OFFSETS: Array[float] = [-0.95, 0.0, 0.95]

static func local_point(position: Vector3, yaw: float, local: Vector3) -> Vector3:
	return position + Vector3(local.x * cos(yaw) - local.z * sin(yaw), local.y, local.x * sin(yaw) + local.z * cos(yaw))

static func seat_feet(position: Vector3, yaw: float, seat: String, kind: String = "jeep") -> Vector3:
	var local: Vector3 = Vector3(0.2, 0.65, -0.4) if seat == "driver" else Vector3(-0.65, 0.95, 0.0)
	if kind == "boat":
		local = Vector3(-0.2, 0.65, -0.4) if seat == "driver" else Vector3(-1.0, 0.95, 0)
	elif kind == "light_aircraft":
		local = Vector3(1.45, 0.65, -0.3)
	return local_point(position, yaw, local)

static func clear_body(position: Vector3, yaw: float, arena: Dictionary) -> bool:
	if not position.is_finite() or not is_finite(yaw):
		return false
	for offset: float in OFFSETS:
		var point: Vector3 = local_point(position, yaw, Vector3(offset, 0.0, 0.0))
		if absf(point.x) > float(arena["half"]) - HALF_WIDTH or absf(point.z) > float(arena["half"]) - HALF_WIDTH:
			return false
		for solid: Dictionary in arena["solids"]:
			if MoveStep.solid_top(solid) > point.y + 0.3 + MoveStep.CONTACT_EPSILON \
				and MoveStep.solid_bottom(solid) < point.y + CLEARANCE_HEIGHT - MoveStep.CONTACT_EPSILON \
				and _blocks(solid, point):
				return false
	return true

static func _blocks(solid: Dictionary, point: Vector3) -> bool:
	# Rust expands f32 bounds. GDScript scalar subtraction is f64; round the
	# expanded edges back to f32 so contact at a thin wall takes the same step.
	var lower: Vector3 = Vector3(float(solid["min_x"]) - HALF_WIDTH, 0, float(solid["min_z"]) - HALF_WIDTH)
	var upper: Vector3 = Vector3(float(solid["max_x"]) + HALF_WIDTH, 0, float(solid["max_z"]) + HALF_WIDTH)
	return point.x >= lower.x and point.x <= upper.x and point.z >= lower.z and point.z <= upper.z

static func step(motion: Dictionary, input: Dictionary, delta: float, arena: Dictionary) -> Dictionary:
	var state: Dictionary = motion.duplicate(true)
	var position: Vector3 = GrenadeFacts.vector(state["position"])
	var yaw: float = float(state["yaw"])
	var speed: float = float(state["speed"])
	var vertical: float = float(state["vy"])
	if not is_finite(delta) or delta <= 0.0 or delta > 0.05 or not position.is_finite() \
		or not is_finite(yaw) or not is_finite(speed) or not is_finite(vertical):
		return state
	var throttle: int = int(bool(input.get("forward", false))) - int(bool(input.get("back", false)))
	var target: float = TOP_SPEED if throttle > 0 else (-REVERSE_SPEED if throttle < 0 else 0.0)
	var braking: bool = bool(input.get("brake", false))
	var rate: float = 30.0 if braking else (5.0 if throttle == 0 else (18.0 if speed * throttle < 0.0 else 8.0))
	if braking:
		target = 0.0
	speed = clampf(speed + clampf(target - speed, -rate * delta, rate * delta), -REVERSE_SPEED, TOP_SPEED)
	var turn: float = float(int(bool(input.get("right", false))) - int(bool(input.get("left", false))))
	var angular: float = turn * 1.5 * clampf(speed / 4.0, -1.0, 1.0) / (1.0 + absf(speed) * 0.07)
	var steps: int = maxi(ceili(absf(speed) * delta / 0.1), 4)
	var slice: float = delta / steps
	for index: int in range(steps):
		var next_yaw: float = fposmod(yaw + angular * slice, TAU)
		var candidate: Vector3 = position + Vector3(cos(next_yaw) * speed * slice, 0.0, sin(next_yaw) * speed * slice)
		var support: float = 0.0
		for offset: float in OFFSETS:
			var point: Vector3 = local_point(candidate, next_yaw, Vector3(offset, 0, 0))
			support = maxf(support, MoveStep.arena_support_height(arena, point.x, point.z, position.y + 0.3))
		vertical -= MoveStep.GRAVITY * slice
		candidate.y += vertical * slice
		if candidate.y <= support:
			candidate.y = support
			vertical = 0.0
		if clear_body(candidate, next_yaw, arena):
			position = candidate
			yaw = next_yaw
		else:
			speed = 0.0
			break
	state["position"] = [position.x, position.y, position.z]
	state["yaw"] = yaw
	state["speed"] = speed
	state["vy"] = vertical
	return state
