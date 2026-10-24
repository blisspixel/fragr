class_name MoveStep
extends RefCounted
## The shared movement step, mirrored line for line from server/src/movement.rs.
## Pure functions over dictionaries: no nodes, no physics server, no randomness.
## The headless harness test_move_golden.gd checks the fighter model against
## both golden files (20 Hz live, 60 Hz). LocalPrediction runs fighter_step for
## an arena participant (Ack version 2) and live_step, the immediate step, for
## a campaign participant (version 1); authored actors use live_step too.

## Fighter feel, frozen 2026-10-23. server/src/movement.rs owns these values
## and their reasons; both golden files record them and the harness refuses
## vectors made with anything else.
const TOP_SPEED: float = 6.0
const GROUND_ACCEL: float = 15.0
const FRICTION: float = 12.0
const STOP_SPEED: float = 2.0
const AIR_ACCEL: float = 2.0
const AIR_SPEED_CAP: float = 7.5
const DODGE_SPEED: float = 9.0
const DODGE_UP: float = 3.5
const DODGE_COOLDOWN_TICKS: int = 15
## The campaign pace: authored actors' gaits are shares of it, and a campaign
## participant keeps the immediate step at it (Ack version 1).
const ACTOR_REFERENCE_SPEED: float = 5.0
const RADIUS: float = 0.5
const DT_60HZ: float = 1.0 / 60.0
const DT_LIVE: float = 1.0 / 20.0
const GROUND_Y: float = 0.0
## How far a fighter climbs or drops without leaving the ground.
const STEP_UP: float = 0.6
const CONTACT_EPSILON: float = 0.0001
## The top a solid gets when nobody says otherwise: higher than a jump reaches.
const WALL_TOP: float = 4.5
## How far above its feet a fighter's shot line sits.
const EYE_HEIGHT: float = 1.6
const BODY_HEIGHT: float = 1.8
## Crouch clearance. Three quarters of a standing fighter.
const DUCK_HEIGHT: float = 1.35
## The standing eye sits 0.2 m under the crown. The short body keeps that gap.
const DUCK_EYE_HEIGHT: float = 1.15
## Horizontal speed while the body is short, as a fraction of the chosen speed.
const DUCK_SPEED_SCALE: float = 0.34
const GRAVITY: float = 22.0
const JUMP_SPEED: float = 7.0


static func make_state(x: float, z: float, yaw: float) -> Dictionary:
	return {"x": x, "z": z, "y": GROUND_Y, "vx": 0.0, "vz": 0.0, "vy": 0.0, "yaw": yaw}


static func make_input(forward: bool, back: bool, left: bool, right: bool, yaw: float, speed_scale: float = 1.0) -> Dictionary:
	return {"forward": forward, "back": back, "left": left, "right": right, "jump": false, "dodge": false, "yaw": yaw, "speed_scale": speed_scale}


static func solid_from_center(cx: float, cz: float, half_x: float, half_z: float, top: float = WALL_TOP) -> Dictionary:
	return {"min_x": cx - half_x, "max_x": cx + half_x, "min_z": cz - half_z, "max_z": cz + half_z, "top": top}


static func solid_top(solid: Dictionary) -> float:
	return float(solid.get("top", WALL_TOP))


static func solid_bottom(solid: Dictionary) -> float:
	return float(solid.get("bottom", GROUND_Y))


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


## Grounded clearance, with feet one step below climb. Airborne callers supply
## the actual foot height through arena_blocked_body_at.
static func arena_blocked_at(arena: Dictionary, x: float, z: float, climb: float) -> bool:
	return arena_blocked_body_at(arena, x, z, climb - STEP_UP, climb)


static func arena_blocked_body_at(arena: Dictionary, x: float, z: float, feet: float, climb: float, height: float = BODY_HEIGHT) -> bool:
	for solid: Dictionary in arena["solids"]:
		if solid_top(solid) > climb and solid_bottom(solid) < feet + height - CONTACT_EPSILON and solid_blocks(solid, x, z, RADIUS):
			return true
	return false


static func arena_blocked_motion(arena: Dictionary, from: Vector2, to: Vector2, climb: float) -> bool:
	return arena_blocked_body_motion(arena, from, to, climb - STEP_UP, climb, true)


static func arena_blocked_body_motion(arena: Dictionary, from: Vector2, to: Vector2, feet: float, climb: float, was_grounded: bool, height: float = BODY_HEIGHT) -> bool:
	var support: float = arena_support_height(arena, to.x, to.y, climb)
	var next_feet: float = support if was_grounded and feet - support <= STEP_UP else feet
	for solid: Dictionary in arena["solids"]:
		if solid_top(solid) <= climb or solid_bottom(solid) >= next_feet + height - CONTACT_EPSILON:
			continue
		if solid_bottom(solid) >= feet + height - CONTACT_EPSILON:
			# Stepping into a slab is not recovery from an existing overlap.
			if solid_blocks(solid, to.x, to.y, RADIUS):
				return true
		elif solid_blocks_motion(solid, from, to, RADIUS):
			return true
	return false


static func arena_ceiling_height(arena: Dictionary, x: float, z: float, feet: float, height: float = BODY_HEIGHT) -> float:
	var ceiling: float = INF
	for solid: Dictionary in arena["solids"]:
		var bottom: float = solid_bottom(solid)
		if bottom >= feet + height - CONTACT_EPSILON and solid_blocks(solid, x, z, RADIUS):
			ceiling = minf(ceiling, bottom)
	return ceiling


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


## The authored-actor step. The caller has already chosen effective speed,
## yaw and any latched jump edge. Horizontal velocity changes immediately.
static func live_step(state: Dictionary, input: Dictionary, speed: float, dt: float, arena: Dictionary) -> Dictionary:
	return live_step_with_height(state, input, speed, dt, arena, BODY_HEIGHT)


## The live step at a chosen body height. Standing callers keep `live_step`.
static func live_step_with_height(state: Dictionary, input: Dictionary, speed: float, dt: float, arena: Dictionary, height: float) -> Dictionary:
	var yaw: float = normalize_yaw(float(input.get("yaw", 0.0)))
	var wish: Vector2 = wish_dir(input, yaw)
	var moving: Dictionary = state.duplicate()
	moving["vx"] = wish.x * speed
	moving["vz"] = wish.y * speed
	moving["yaw"] = yaw
	return integrate_with_height(moving, bool(input.get("jump", false)), dt, arena, height)


## One participant step, mirroring movement::fighter_step_with_height: yaw
## and wish; grounded test on the old position; a dodge, or ground friction
## and acceleration unless jumping, or capped air acceleration; then the
## shared integration. `speed` is the wish speed before `speed_scale`.
static func fighter_step(state: Dictionary, input: Dictionary, speed: float, dt: float, arena: Dictionary) -> Dictionary:
	return fighter_step_with_height(state, input, speed, dt, arena, BODY_HEIGHT)


static func fighter_step_with_height(state: Dictionary, input: Dictionary, speed: float, dt: float, arena: Dictionary, height: float) -> Dictionary:
	var yaw: float = normalize_yaw(float(input.get("yaw", 0.0)))
	var wish: Vector2 = wish_dir(input, yaw)
	var scale: float = float(input.get("speed_scale", 1.0))
	scale = clampf(scale, 0.0, 1.0) if is_finite(scale) else 1.0
	var wish_speed: float = maxf(speed, 0.0) * scale if is_finite(speed) else 0.0
	dt = maxf(dt, 0.0) if is_finite(dt) else 0.0
	var velocity: Vector2 = Vector2.ZERO
	if is_finite(float(state["vx"])) and is_finite(float(state["vz"])):
		velocity = Vector2(float(state["vx"]), float(state["vz"]))
	var state_y: float = float(state.get("y", GROUND_Y))
	var floor_y: float = arena_support_height(arena, float(state["x"]), float(state["z"]), state_y)
	var on_floor: bool = grounded(state_y, floor_y, float(state.get("vy", 0.0)))
	var jump: bool = bool(input.get("jump", false))
	var launch: float = JUMP_SPEED if jump else -1.0
	if on_floor and bool(input.get("dodge", false)) and wish != Vector2.ZERO:
		velocity = wish * DODGE_SPEED
		launch = DODGE_UP
	elif on_floor and not jump:
		velocity = friction(velocity, dt)
		velocity = accelerate(velocity, wish, wish_speed, GROUND_ACCEL, dt)
	else:
		var before: float = velocity.length()
		velocity = accelerate(velocity, wish, wish_speed, AIR_ACCEL, dt)
		var limit: float = maxf(before, AIR_SPEED_CAP)
		var after: float = velocity.length()
		if after > limit:
			velocity = velocity * (limit / after)
	var moving: Dictionary = state.duplicate()
	moving["vx"] = velocity.x
	moving["vz"] = velocity.y
	moving["yaw"] = yaw
	return launch_with_height(moving, launch, dt, arena, height)


## Mirror of movement::dodge_applies, for the caller's cooldown.
static func dodge_applies(state: Dictionary, input: Dictionary, arena: Dictionary) -> bool:
	if not bool(input.get("dodge", false)):
		return false
	if wish_dir(input, normalize_yaw(float(input.get("yaw", 0.0)))) == Vector2.ZERO:
		return false
	var state_y: float = float(state.get("y", GROUND_Y))
	return grounded(state_y, arena_support_height(arena, float(state["x"]), float(state["z"]), state_y), float(state.get("vy", 0.0)))


## Quake and Source ground friction.
static func friction(velocity: Vector2, dt: float) -> Vector2:
	var speed: float = velocity.length()
	if speed < 0.01:
		return Vector2.ZERO
	var drop: float = maxf(speed, STOP_SPEED) * FRICTION * dt
	return velocity * (maxf(speed - drop, 0.0) / speed)


## Quake and Source acceleration toward the wish speed along the wish direction.
static func accelerate(velocity: Vector2, wish: Vector2, wish_speed: float, accel: float, dt: float) -> Vector2:
	if wish == Vector2.ZERO or wish_speed <= 0.0:
		return velocity
	var room: float = wish_speed - velocity.dot(wish)
	if room <= 0.0:
		return velocity
	return velocity + wish * minf(accel * dt * wish_speed, room)


## Resolve chosen velocity, jumping and gravity through the same path as the
## live server. Acceleration is a caller decision, not a collision rule.
static func integrate(state: Dictionary, jump: bool, dt: float, arena: Dictionary) -> Dictionary:
	return integrate_with_height(state, jump, dt, arena, BODY_HEIGHT)


## Registered low actor profiles share the server's support and ceiling path.
static func integrate_with_height(state: Dictionary, jump: bool, dt: float, arena: Dictionary, height: float) -> Dictionary:
	return launch_with_height(state, JUMP_SPEED if jump else -1.0, dt, arena, height)


## integrate_with_height with the upward speed a grounded body leaves the floor
## at: a jump's, a dodge's, or a negative value for none.
static func launch_with_height(state: Dictionary, launch: float, dt: float, arena: Dictionary, height: float) -> Dictionary:
	var vx: float = float(state["vx"])
	var vz: float = float(state["vz"])
	var yaw: float = float(state["yaw"])

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
	if not arena_blocked_body_motion(arena, Vector2(old_x, old_z), Vector2(nx, nz), state_y, climb, was_grounded, height):
		x = nx
		z = nz
	elif not arena_blocked_body_motion(arena, Vector2(old_x, old_z), Vector2(nx, old_z), state_y, climb, was_grounded, height):
		vz = 0.0
		x = nx
		z = old_z
	elif not arena_blocked_body_motion(arena, Vector2(old_x, old_z), Vector2(old_x, nz), state_y, climb, was_grounded, height):
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
		if launch >= 0.0:
			vy = launch
	else:
		vy -= GRAVITY * dt
	var ceiling: float = arena_ceiling_height(arena, x, z, y, height)
	y += vy * dt
	if vy > 0.0 and y + height > ceiling:
		y = ceiling - height
		vy = 0.0
	# Swept landing: anything the fall passed through on the way down counts.
	var landing: float = arena_support_height(arena, x, z, maxf(state_y, y))
	if y <= landing:
		y = landing
		if vy < 0.0:
			vy = 0.0

	return {"x": x, "z": z, "y": y, "vx": vx, "vz": vz, "vy": vy, "yaw": yaw}
