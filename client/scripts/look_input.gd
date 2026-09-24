extends RefCounted
class_name LookInput

## Pure look and stick math, kept apart from the camera so the harnesses can
## assert it without a window, a mouse or a gamepad. Every rate here is per
## second and every result is integrated over the frame's delta, so the angle a
## held key or stick produces does not depend on the frame rate.

## Keyboard turning starts at a fraction of full speed and reaches it after a
## short ramp. A tap therefore nudges by well under a degree, and a hold still
## turns quickly. Doom did the same with its first few slow-turn tics.
const KEY_RAMP_SECONDS: float = 0.25
const KEY_START_FRACTION: float = 0.2
## Look up and down keys move pitch more slowly than turning moves yaw.
const KEY_PITCH_SCALE: float = 0.6
## Optional auto-centre: after this long without a look key, pitch eases home
## while the player walks.
const AUTO_CENTRE_DELAY: float = 0.6
const AUTO_CENTRE_RATE: float = 6.0

## Stick outer edge. Past it the stick counts as fully deflected, because worn
## sticks rarely report a clean 1.0.
const STICK_OUTER: float = 0.95
## Look acceleration: after the look stick has sat at its edge this long, yaw
## rate rises by up to this much, for turning round quickly.
const ACCEL_EDGE: float = 0.98
const ACCEL_SECONDS: float = 0.35
const ACCEL_BOOST: float = 0.8
## Movement quantization. The wire carries four direction bits, so a stick
## becomes eight directions with forty-five degree sectors.
const MOVE_SECTOR: float = 0.3827 # sin(22.5 degrees)
const MOVE_MIN_DEADZONE: float = 0.2

## Angle covered while a key is held from `held_before` to `held_after`
## seconds, integrated exactly so frame length never matters.
static func key_turn_angle(held_before: float, held_after: float, rate: float) -> float:
	return rate * (_ramp_integral(held_after) - _ramp_integral(held_before))

static func _ramp_integral(t: float) -> float:
	if t <= 0.0:
		return 0.0
	var ramp: float = KEY_RAMP_SECONDS
	var start: float = KEY_START_FRACTION
	if t <= ramp:
		return start * t + (1.0 - start) * t * t / (2.0 * ramp)
	return start * ramp + (1.0 - start) * ramp * 0.5 + (t - ramp)

## Radial deadzone with rescale. The stick's direction survives exactly, and
## output magnitude runs from zero at the deadzone edge to one at the outer
## edge, so there is no jump when the stick leaves the deadzone.
static func radial(stick: Vector2, deadzone: float, outer: float = STICK_OUTER) -> Vector2:
	var length: float = stick.length()
	if not stick.is_finite() or length <= deadzone or length <= 0.0:
		return Vector2.ZERO
	var span: float = maxf(outer - deadzone, 0.001)
	return stick / length * clampf((length - deadzone) / span, 0.0, 1.0)

## Response curve on the magnitude only, so diagonal aim keeps its angle.
## Exponent 1 is linear; higher gives finer control near the centre.
static func curve(stick: Vector2, exponent: float) -> Vector2:
	var length: float = stick.length()
	if length <= 0.0:
		return Vector2.ZERO
	return stick / length * pow(minf(length, 1.0), maxf(exponent, 0.1))

static func shape(stick: Vector2, deadzone: float, exponent: float) -> Vector2:
	return curve(radial(stick, deadzone), exponent)

static func accel_multiplier(edge_seconds: float, enabled: bool) -> float:
	if not enabled:
		return 1.0
	return 1.0 + ACCEL_BOOST * clampf(edge_seconds / ACCEL_SECONDS, 0.0, 1.0)

## Yaw and pitch change for one frame of stick look. Positive yaw turns right
## (server yaw grows clockwise from above); stick up looks up unless inverted.
static func stick_look(shaped: Vector2, yaw_rate: float, pitch_rate: float, invert: bool, boost: float, delta: float) -> Vector2:
	var pitch_sign: float = 1.0 if invert else -1.0
	return Vector2(shaped.x * yaw_rate * boost * delta, shaped.y * pitch_rate * pitch_sign * delta)

## Eight-way movement bits from the left stick.
static func move_bits(stick: Vector2, deadzone: float) -> Dictionary:
	var bits: Dictionary = {"forward": false, "back": false, "left": false, "right": false}
	var shaped: Vector2 = radial(stick, maxf(deadzone, MOVE_MIN_DEADZONE))
	if shaped == Vector2.ZERO:
		return bits
	var direction: Vector2 = shaped.normalized()
	bits["forward"] = direction.y < -MOVE_SECTOR
	bits["back"] = direction.y > MOVE_SECTOR
	bits["left"] = direction.x < -MOVE_SECTOR
	bits["right"] = direction.x > MOVE_SECTOR
	return bits

## Raw stick from the gamepad the player last used. `right` is the look stick.
static func read_stick(right: bool) -> Vector2:
	var device: int = InputDevice.pad_device
	if right:
		return Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	return Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))

## Pitch after one frame of auto-centre easing, frame-rate independent.
static func auto_centre(pitch: float, delta: float) -> float:
	return pitch * exp(-AUTO_CENTRE_RATE * delta)

## Centimetres of mouse travel per full turn at 0.022 degrees per count.
static func cm_per_360(sensitivity: float, counts_per_inch: float) -> float:
	var degrees_per_count: float = 0.022 * sensitivity
	if degrees_per_count <= 0.0 or counts_per_inch <= 0.0:
		return 0.0
	return (360.0 / (degrees_per_count * counts_per_inch)) * 2.54
