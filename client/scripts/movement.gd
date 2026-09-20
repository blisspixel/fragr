class_name MoveStep
extends RefCounted
## The shared movement step, mirrored line for line from server/src/movement.rs.
## Pure functions over dictionaries: no nodes, no physics server, no randomness.
## The headless harness test_move_golden.gd proves this mirror matches the
## Rust step against client/golden/move_vectors.json. Change the model in Rust,
## regenerate the vectors, then bring this file into line.

const RADIUS: float = 0.5
const TOP_SPEED: float = 5.0
const TAU_ACCEL: float = 0.06
const TAU_DECEL: float = 0.04
const DT_60HZ: float = 1.0 / 60.0
const GROUND_Y: float = 0.0
## How far a fighter climbs or drops without leaving the ground.
const STEP_UP: float = 0.6
const CONTACT_EPSILON: float = 0.0001
## The top a solid gets when nobody says otherwise: higher than a jump reaches.
const WALL_TOP: float = 4.5
## How far above its feet a fighter's shot line sits.
const EYE_HEIGHT: float = 1.6
const GRAVITY: float = 22.0
const JUMP_SPEED: float = 7.0


static func make_state(x: float, z: float, yaw: float) -> Dictionary:
	return {"x": x, "z": z, "y": GROUND_Y, "vx": 0.0, "vz": 0.0, "vy": 0.0, "yaw": yaw}


static func make_input(forward: bool, back: bool, left: bool, right: bool, yaw: float, speed_scale: float = 1.0) -> Dictionary:
	return {"forward": forward, "back": back, "left": left, "right": right, "jump": false, "yaw": yaw, "speed_scale": speed_scale}


static func solid_from_center(cx: float, cz: float, half_x: float, half_z: float, top: float = WALL_TOP) -> Dictionary:
	return {"min_x": cx - half_x, "max_x": cx + half_x, "min_z": cz - half_z, "max_z": cz + half_z, "top": top}


static func solid_top(solid: Dictionary) -> float:
	return float(solid.get("top", WALL_TOP))


static func solid_blocks(solid: Dictionary, x: float, z: float, radius: float) -> bool:
	return (
		x >= solid["min_x"] - radius
		and x <= solid["max_x"] + radius
		and z >= solid["min_z"] - radius
		and z <= solid["max_z"] + radius
	)


## Mirror the Rust escape rule for a body overlapping a ledge during a fall.
static func solid_blocks_motion(solid: Dictionary, from: Vector2, to: Vector2, radius: float) -> bool:
	if not solid_blocks(solid, to.x, to.y, radius):
		return false
	if not solid_blocks(solid, from.x, from.y, radius):
		return true
	var depths: Array[float] = [
		from.x - (float(solid["min_x"]) - radius),
		float(solid["max_x"]) + radius - from.x,
		from.y - (float(solid["min_z"]) - radius),
		float(solid["max_z"]) + radius - from.y,
	]
	var nearest: float = minf(minf(depths[0], depths[1]), minf(depths[2], depths[3]))
	return not (
		(depths[0] == nearest and to.x < from.x)
		or (depths[1] == nearest and to.x > from.x)
		or (depths[2] == nearest and to.y < from.y)
		or (depths[3] == nearest and to.y > from.y)
	)


## The point itself over the solid, not the circle around it: a fighter is held
## up by what is under its feet, not by what is beside it.
static func solid_covers(solid: Dictionary, x: float, z: float) -> bool:
	return (
		x >= solid["min_x"]
		and x <= solid["max_x"]
		and z >= solid["min_z"]
		and z <= solid["max_z"]
	)


static func arena_blocked(arena: Dictionary, x: float, z: float) -> bool:
	return arena_blocked_at(arena, x, z, GROUND_Y + STEP_UP)


## Blocked for a fighter that can reach up to `climb`. Anything at or below
## that height is walked onto instead of walked into.
static func arena_blocked_at(arena: Dictionary, x: float, z: float, climb: float) -> bool:
	for solid: Dictionary in arena["solids"]:
		if solid_top(solid) > climb and solid_blocks(solid, x, z, RADIUS):
			return true
	return false


static func arena_blocked_motion(arena: Dictionary, from: Vector2, to: Vector2, climb: float) -> bool:
	for solid: Dictionary in arena["solids"]:
		if solid_top(solid) > climb and solid_blocks_motion(solid, from, to, RADIUS):
			return true
	return false


## The highest surface at (x, z) no higher than `ceiling`, or the base floor.
static func arena_support_height(arena: Dictionary, x: float, z: float, ceiling: float) -> float:
	var best: float = GROUND_Y
	for solid: Dictionary in arena["solids"]:
		var top: float = solid_top(solid)
		if top <= ceiling + CONTACT_EPSILON and top > best and solid_covers(solid, x, z):
			best = top
	return best


## How high a fighter at `feet` with `floor` under it can climb. Standing, a
## step above the floor; airborne, wherever the feet are, so a jump clears
## exactly what it rises over and no more.
static func climb_height(feet: float, floor_y: float, vy: float) -> float:
	if grounded(feet, floor_y, vy):
		return floor_y + STEP_UP
	return feet


static func grounded(feet: float, floor_y: float, vy: float) -> bool:
	return feet <= floor_y + CONTACT_EPSILON and vy <= 0.0


static func arena_clamp(arena: Dictionary, x: float, z: float) -> Vector2:
	var limit: float = float(arena["half"]) - RADIUS
	return Vector2(clampf(x, -limit, limit), clampf(z, -limit, limit))


static func normalize_yaw(yaw: float) -> float:
	if not is_finite(yaw):
		return 0.0
	var two_pi: float = 2.0 * PI
	var y: float = fmod(yaw, two_pi)
	if y < 0.0:
		y += two_pi
	if y >= two_pi:
		y -= two_pi
	return y


static func wish_dir(input: Dictionary, yaw: float) -> Vector2:
	var dx: float = 0.0
	var dz: float = 0.0
	if input.get("forward", false):
		dx += cos(yaw)
		dz += sin(yaw)
	if input.get("back", false):
		dx -= cos(yaw)
		dz -= sin(yaw)
	if input.get("left", false):
		dx += cos(yaw - PI / 2.0)
		dz += sin(yaw - PI / 2.0)
	if input.get("right", false):
		dx += cos(yaw + PI / 2.0)
		dz += sin(yaw + PI / 2.0)
	var len: float = sqrt(dx * dx + dz * dz)
	if len > 0.0:
		return Vector2(dx / len, dz / len)
	return Vector2.ZERO


## Advance one fighter by dt seconds. Same order as the Rust step: yaw, wish,
## velocity approach, the floor under the old position, integrate, clamp,
## axis-separated slide with the blocked axis velocity zeroed, then the
## vertical against the floor under the new position.
static func step(state: Dictionary, input: Dictionary, dt: float, arena: Dictionary) -> Dictionary:
	var yaw: float = normalize_yaw(float(input.get("yaw", 0.0)))
	var wish: Vector2 = wish_dir(input, yaw)
	var scale: float = float(input.get("speed_scale", 1.0))
	if not is_finite(scale):
		scale = 1.0
	scale = clampf(scale, 0.0, 1.0)
	var target_x: float = wish.x * TOP_SPEED * scale
	var target_z: float = wish.y * TOP_SPEED * scale

	var vx: float = float(state["vx"])
	var vz: float = float(state["vz"])
	var current_speed: float = sqrt(vx * vx + vz * vz)
	var target_speed: float = sqrt(target_x * target_x + target_z * target_z)
	var tau: float = TAU_ACCEL if target_speed > current_speed else TAU_DECEL
	var blend: float = minf(dt / tau, 1.0)
	vx = vx + (target_x - vx) * blend
	vz = vz + (target_z - vz) * blend

	var old_x: float = float(state["x"])
	var old_z: float = float(state["z"])
	var clamped: Vector2 = arena_clamp(arena, old_x + vx * dt, old_z + vz * dt)
	var nx: float = clamped.x
	var nz: float = clamped.y

	# What is under the fighter now, and therefore how high it can climb into
	# the next square. Mirrors movement.rs exactly.
	var state_y: float = float(state.get("y", GROUND_Y))
	var state_vy: float = float(state.get("vy", 0.0))
	var floor_y: float = arena_support_height(arena, old_x, old_z, state_y)
	var was_grounded: bool = grounded(state_y, floor_y, state_vy)
	var climb: float = climb_height(state_y, floor_y, state_vy)

	var x: float
	var z: float
	if not arena_blocked_motion(arena, Vector2(old_x, old_z), Vector2(nx, nz), climb):
		x = nx
		z = nz
	elif not arena_blocked_motion(arena, Vector2(old_x, old_z), Vector2(nx, old_z), climb):
		vz = 0.0
		x = nx
		z = old_z
	elif not arena_blocked_motion(arena, Vector2(old_x, old_z), Vector2(old_x, nz), climb):
		vx = 0.0
		x = old_x
		z = nz
	else:
		vx = 0.0
		vz = 0.0
		var stay: Vector2 = arena_clamp(arena, old_x, old_z)
		x = stay.x
		z = stay.y

	# Vertical, against the floor under where the fighter ended up. Up to a
	# step is snapped to, in either direction; a bigger drop is a fall.
	var support: float = arena_support_height(arena, x, z, climb)
	var vy: float = state_vy
	var y: float = state_y
	var on_ground: bool = grounded(y, support, state_vy) or (was_grounded and y - support <= STEP_UP)
	if on_ground:
		y = support
		vy = 0.0
		if bool(input.get("jump", false)):
			vy = JUMP_SPEED
	else:
		vy -= GRAVITY * dt
	y += vy * dt
	# Swept landing: anything the fall passed through on the way down counts.
	var landing: float = arena_support_height(arena, x, z, maxf(state_y, y))
	if y <= landing:
		y = landing
		if vy < 0.0:
			vy = 0.0

	return {"x": x, "z": z, "y": y, "vx": vx, "vz": vz, "vy": vy, "yaw": yaw}
