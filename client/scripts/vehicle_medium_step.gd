class_name VehicleMediumStep
extends RefCounted

## Mirror of vehicles/water_air.rs. Water regions and chassis dimensions are
## server facts. This supplies preview motion, never crash or drowning damage.
const BOAT_DRAFT: float = 0.6
const FLIGHT_CEILING: float = 60.0

static func _f(value: float) -> float:
	return Vector2(value, 0).x

static func _yaw(value: float) -> float:
	return _f(fposmod(_f(value), _f(TAU)))

static func dimensions(kind: String) -> Vector3:
	match kind:
		"boat": return Vector3(2.4, 1.1, 1.6)
		"light_aircraft": return Vector3(4.0, 4.6, 1.8)
	return Vector3(1.9, 0.95, 1.35)

static func surface_at(water: Array, x: float, z: float) -> Dictionary:
	for region: Dictionary in water:
		if x >= float(region.min[0]) and x <= float(region.max[0]) and z >= float(region.min[1]) and z <= float(region.max[1]):
			return {"level": float(region.level), "depth": float(region.depth)}
	return {}

static func clear_kind(kind: String, position: Vector3, yaw: float, arena: Dictionary) -> bool:
	if kind == "jeep":
		return VehicleStep.clear_body(position, yaw, arena)
	if not position.is_finite() or not is_finite(yaw):
		return false
	var size: Vector3 = dimensions(kind)
	var extent_x: float = absf(cos(yaw)) * size.x + absf(sin(yaw)) * size.y
	var extent_z: float = absf(sin(yaw)) * size.x + absf(cos(yaw)) * size.y
	if absf(position.x) + extent_x > float(arena.half) or absf(position.z) + extent_z > float(arena.half):
		return false
	var bottom: float = position.y - BOAT_DRAFT if kind == "boat" else position.y + 0.3
	for solid: Dictionary in arena.solids:
		if MoveStep.solid_top(solid) > bottom + MoveStep.CONTACT_EPSILON \
			and MoveStep.solid_bottom(solid) < position.y + VehicleStep.CLEARANCE_HEIGHT - MoveStep.CONTACT_EPSILON \
			and float(solid.max_x) > position.x - extent_x and float(solid.min_x) < position.x + extent_x \
			and float(solid.max_z) > position.z - extent_z and float(solid.min_z) < position.z + extent_z:
			return false
	return true

static func _boat_support(position: Vector3, yaw: float, water: Array) -> Dictionary:
	var center: Dictionary = surface_at(water, position.x, position.z)
	if center.is_empty():
		return {}
	var size: Vector3 = dimensions("boat")
	for x: float in [-size.x, 0.0, size.x]:
		for z: float in [-size.y, size.y]:
			var point: Vector3 = VehicleStep.local_point(position, yaw, Vector3(x, 0, z))
			var support: Dictionary = surface_at(water, point.x, point.z)
			if support.is_empty() or float(support.depth) < BOAT_DRAFT or absf(float(support.level) - float(center.level)) > 0.01:
				return {}
	return center

static func step(kind: String, motion: Dictionary, input: Dictionary, dt: float, arena: Dictionary, water: Array) -> Dictionary:
	var state: Dictionary = motion.duplicate(true)
	if kind == "jeep":
		var next: Dictionary = VehicleStep.step(state, input, dt, arena)
		var surface: Dictionary = surface_at(water, float(next.position[0]), float(next.position[2]))
		if not surface.is_empty() and float(next.position[1]) < float(surface.level) + 0.3:
			state.speed = 0.0
			return state
		return next
	var position: Vector3 = GrenadeFacts.vector(state.position)
	if not is_finite(dt) or dt <= 0.0 or dt > 0.05 or not position.is_finite() or not is_finite(float(state.yaw)) or not is_finite(float(state.speed)) or not is_finite(float(state.vy)):
		return state
	return _boat(state, input, dt, arena, water) if kind == "boat" else _plane(state, input, dt, arena, water)

static func _boat(state: Dictionary, input: Dictionary, dt: float, arena: Dictionary, water: Array) -> Dictionary:
	var throttle: int = int(bool(input.get("forward", false))) - int(bool(input.get("back", false)))
	var brake: bool = bool(input.get("brake", false))
	var target: float = 0.0 if brake else 14.0 if throttle > 0 else -4.0 if throttle < 0 else 0.0
	var rate: float = 12.0 if brake else 1.5 if throttle == 0 else 6.0 if float(state.speed) * throttle < 0 else 4.0
	state.speed = clampf(float(state.speed) + clampf(target - float(state.speed), -rate * dt, rate * dt), -4.0, 14.0)
	var turn: int = int(bool(input.get("right", false))) - int(bool(input.get("left", false)))
	var angular: float = turn * 0.8 * clampf(float(state.speed) / 3.0, -1.0, 1.0) / (1.0 + absf(float(state.speed)) * 0.04)
	var steps: int = maxi(ceili(absf(float(state.speed)) * dt / 0.1), 4)
	var slice: float = dt / steps
	for _index: int in range(steps):
		var yaw: float = _yaw(float(state.yaw) + _f(angular * slice))
		var position: Vector3 = GrenadeFacts.vector(state.position) + Vector3(cos(yaw) * float(state.speed) * slice, 0, sin(yaw) * float(state.speed) * slice)
		var surface: Dictionary = _boat_support(position, yaw, water)
		if surface.is_empty():
			state.speed = 0.0
			break
		position.y = float(surface.level)
		if not clear_kind("boat", position, yaw, arena):
			state.speed = 0.0
			break
		state.position = [position.x, position.y, position.z]
		state.yaw = yaw
		state.vy = 0.0
	return state

static func _plane(state: Dictionary, input: Dictionary, dt: float, arena: Dictionary, water: Array) -> Dictionary:
	var forward: bool = bool(input.get("forward", false))
	var back: bool = bool(input.get("back", false))
	var target: float = 0.0 if back else 32.0 if forward else 0.0
	var rate: float = 8.0 if back else 6.0 if forward else 1.0
	state.speed = clampf(float(state.speed) + clampf(target - float(state.speed), -rate * dt, rate * dt), 0.0, 32.0)
	var turn: int = int(bool(input.get("right", false))) - int(bool(input.get("left", false)))
	var angular: float = turn * 0.85 * clampf(float(state.speed) / 5.0, 0.0, 1.0) / (1.0 + float(state.speed) * 0.02)
	var steps: int = clampi(ceili((absf(float(state.speed)) + absf(float(state.vy))) * dt / 0.1), 4, 32)
	var slice: float = dt / steps
	for _index: int in range(steps):
		var yaw: float = _yaw(float(state.yaw) + _f(angular * slice))
		var position: Vector3 = GrenadeFacts.vector(state.position) + Vector3(cos(yaw) * float(state.speed) * slice, 0, sin(yaw) * float(state.speed) * slice)
		var surface: Dictionary = surface_at(water, position.x, position.z)
		var ground: float = MoveStep.arena_support_height(arena, position.x, position.z, float(state.position[1]) + 0.3)
		if float(state.speed) >= 12.0:
			var target_vy: float = (int(bool(input.get("brake", false))) - int(bool(input.get("descend", false)))) * 6.0
			state.vy = float(state.vy) + clampf(target_vy - float(state.vy), -8.0 * slice, 8.0 * slice)
		else:
			state.vy = float(state.vy) - MoveStep.GRAVITY * slice
		position.y += float(state.vy) * slice
		if position.y > FLIGHT_CEILING:
			position.y = FLIGHT_CEILING
			state.vy = minf(float(state.vy), 0.0)
		if not surface.is_empty():
			if position.y <= float(surface.level) + 0.1:
				position.y = float(surface.level)
				state.position = [position.x, position.y, position.z]
				state.speed = 0.0
				state.vy = 0.0
				break
		elif position.y <= ground:
			if float(state.vy) < -4.0:
				state.speed = 0.0
			position.y = ground
			state.vy = 0.0
		if not clear_kind("light_aircraft", position, yaw, arena):
			state.speed = 0.0
			break
		state.position = [position.x, position.y, position.z]
		state.yaw = yaw
	return state
