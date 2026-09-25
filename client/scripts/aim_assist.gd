extends RefCounted
class_name AimAssist

## Aim help for keyboard-only and gamepad look, in the spirit of Doom's
## vertical autoaim and GoldenEye's gentle pull. It only moves the yaw and
## pitch this client already sends. The server still resolves every shot with
## its own geometry and rules, so nothing here adds hit forgiveness, and a
## player who looks with the mouse is never touched.
##
## Keyboard: pitch eases toward a visible hostile near the crosshair's
## horizontal line, and yaw is pulled gently inside a small cone.
## Gamepad: stick look slows near a hostile, and yaw and pitch get a mild pull
## while the player is actively moving or looking. Never a snap or a lock.

enum Level { OFF, LIGHT, STANDARD }

## Angles in radians, pulls as exponential rates per second.
const TUNING: Dictionary = {
	Level.LIGHT: {
		"vertical_cone": 0.07,   # 4 degrees either side for vertical autoaim
		"cone": 0.035,           # 2 degrees either side for yaw pull
		"key_yaw_pull": 2.0,
		"key_pitch_pull": 6.0,
		"pad_pull": 1.2,
		"friction": 0.7,
	},
	Level.STANDARD: {
		"vertical_cone": 0.105,  # 6 degrees
		"cone": 0.07,            # 4 degrees
		"key_yaw_pull": 3.5,
		"key_pitch_pull": 9.0,
		"pad_pull": 2.2,
		"friction": 0.5,
	},
}
## Farther than this nobody gets help. Roughly the long M01 hall.
const MAX_RANGE: float = 40.0
## A fighter's body radius, from the server's collision cylinder.
const BODY_RADIUS: float = 0.5
const BODY_HEIGHT: float = 1.8
## Server positions sit this far above the feet.
const SERVER_REFERENCE_Y: float = 1.5

static func level_from(value: Variant) -> Level:
	if value is int and int(value) in [Level.OFF, Level.LIGHT, Level.STANDARD]:
		return int(value) as Level
	return Level.OFF

## Mouse look is never assisted. Only keyboard or gamepad look sources are.
static func enabled_for(level: Level, look_source: String) -> bool:
	return level != Level.OFF and look_source in ["keyboard", "gamepad"]

## Body centre of a fighter at a server position.
static func body_centre(server_position: Vector3) -> Vector3:
	return server_position + Vector3(0.0, BODY_HEIGHT * 0.5 - SERVER_REFERENCE_Y, 0.0)

## Server yaw and pitch from one point to another. Matches combat::aim_at.
static func aim_at(origin: Vector3, target: Vector3) -> Vector2:
	var delta: Vector3 = target - origin
	var horizontal: float = Vector2(delta.x, delta.z).length()
	return Vector2(wrapf(atan2(delta.z, delta.x), 0.0, TAU), clampf(atan2(delta.y, horizontal), -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT))

## True when nothing solid lies between two points. Mirrors the slab test in
## combat::line_of_sight over the same MapInfo solids, so help never reaches
## through cover the server would stop a shot on.
static func line_of_sight(origin: Vector3, target: Vector3, solids: Array) -> bool:
	var delta: Vector3 = target - origin
	var length: float = delta.length()
	if not delta.is_finite():
		return false
	if length <= 0.0:
		return true
	var direction: Vector3 = delta / length
	for entry: Variant in solids:
		if not entry is Dictionary:
			continue
		var solid: Dictionary = entry
		var low: Vector3 = Vector3(float(solid.get("min_x", 0.0)), float(solid.get("bottom", MoveStep.GROUND_Y)), float(solid.get("min_z", 0.0)))
		var high: Vector3 = Vector3(float(solid.get("max_x", 0.0)), float(solid.get("top", MoveStep.WALL_TOP)), float(solid.get("max_z", 0.0)))
		var hit: float = _slab_distance(origin, direction, low, high, length)
		if hit >= 0.0 and hit < length:
			return false
	return true

static func _slab_distance(origin: Vector3, direction: Vector3, low: Vector3, high: Vector3, range_limit: float) -> float:
	var near: float = 0.0
	var far: float = range_limit
	for axis: int in range(3):
		var o: float = origin[axis]
		var d: float = direction[axis]
		if absf(d) < 1e-9:
			if o < low[axis] or o > high[axis]:
				return -1.0
			continue
		var t1: float = (low[axis] - o) / d
		var t2: float = (high[axis] - o) / d
		near = maxf(near, minf(t1, t2))
		far = minf(far, maxf(t1, t2))
		if near > far:
			return -1.0
	return near

## Signed shortest angle from `from` to `to`.
static func angle_to(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)

## The hostile the assist would help with, or an empty dictionary. Candidates
## must be in range, visible, and within the vertical-autoaim cone of the
## current yaw; the one nearest the crosshair horizontally wins. The cone
## widens by the target's own angular radius, so a close enemy is not missed
## for being wide.
static func pick(eye: Vector3, yaw: float, pitch: float, targets: Array, solids: Array, level: Level) -> Dictionary:
	if level == Level.OFF or not TUNING.has(level):
		return {}
	var tuning: Dictionary = TUNING[level]
	var best: Dictionary = {}
	for entry: Variant in targets:
		if not entry is Vector3:
			continue
		var target: Vector3 = entry
		var distance: float = eye.distance_to(target)
		if not is_finite(distance) or distance <= 0.01 or distance > MAX_RANGE:
			continue
		var angles: Vector2 = aim_at(eye, target)
		var yaw_error: float = angle_to(yaw, angles.x)
		var body: float = atan2(BODY_RADIUS, distance)
		if absf(yaw_error) > float(tuning["vertical_cone"]) + body:
			continue
		if not line_of_sight(eye, target, solids):
			continue
		if best.is_empty() or absf(yaw_error) < absf(float(best["yaw_error"])):
			best = {"target": target, "yaw": angles.x, "pitch": angles.y, "yaw_error": yaw_error, "pitch_error": angles.y - pitch, "body": body, "distance": distance}
	return best

## Keyboard help for one frame: vertical autoaim toward the picked target,
## and a gentle yaw pull while it sits in the smaller cone. Returns the new
## yaw and pitch as a Vector2.
static func keyboard_step(yaw: float, pitch: float, picked: Dictionary, level: Level, delta: float) -> Vector2:
	if picked.is_empty() or not TUNING.has(level) or delta <= 0.0:
		return Vector2(yaw, pitch)
	var tuning: Dictionary = TUNING[level]
	var pitch_error: float = float(picked["pitch"]) - pitch
	pitch += pitch_error * (1.0 - exp(-float(tuning["key_pitch_pull"]) * delta))
	var yaw_error: float = float(picked["yaw_error"])
	if absf(yaw_error) <= float(tuning["cone"]) + float(picked["body"]):
		yaw += yaw_error * (1.0 - exp(-float(tuning["key_yaw_pull"]) * delta))
	return Vector2(wrapf(yaw, 0.0, TAU), clampf(pitch, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT))

## Gamepad slowdown near a hostile: a multiplier on stick look rates.
static func friction(picked: Dictionary, level: Level) -> float:
	if picked.is_empty() or not TUNING.has(level):
		return 1.0
	var tuning: Dictionary = TUNING[level]
	var pitch_error: float = absf(float(picked.get("pitch_error", 0.0)))
	if absf(float(picked["yaw_error"])) <= float(tuning["cone"]) + float(picked["body"]) and pitch_error <= float(tuning["vertical_cone"]) + float(picked["body"]):
		return float(tuning["friction"])
	return 1.0

## Gamepad pull for one frame, only while the player is steering. Milder than
## the keyboard's, and only inside the small cone on both axes.
static func pad_step(yaw: float, pitch: float, picked: Dictionary, level: Level, steering: bool, delta: float) -> Vector2:
	if picked.is_empty() or not steering or not TUNING.has(level) or delta <= 0.0:
		return Vector2(yaw, pitch)
	var tuning: Dictionary = TUNING[level]
	var yaw_error: float = float(picked["yaw_error"])
	var pitch_error: float = float(picked["pitch"]) - pitch
	var cone: float = float(tuning["cone"]) + float(picked["body"])
	if absf(yaw_error) > cone or absf(pitch_error) > float(tuning["vertical_cone"]) + float(picked["body"]):
		return Vector2(yaw, pitch)
	var blend: float = 1.0 - exp(-float(tuning["pad_pull"]) * delta)
	return Vector2(wrapf(yaw + yaw_error * blend, 0.0, TAU), clampf(pitch + pitch_error * blend, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT))
