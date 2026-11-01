class_name FootstepGait
extends RefCounted

## When a fighter's feet make a sound. Presentation only, read from server
## facts: the rendered travel (from snapshot positions or local prediction)
## and the server's `airborne` flag. Pure, so the harness can walk it.
##
## A run is heard and a walk is not, the same line the server's bots hear by
## (`sim/bot_senses/hunt.rs` FOOTSTEP_SPEED): ground speed at or above
## 3.5 m/s and not crouched. Landings are as loud as steps (the CS2 lesson in
## docs/plans/fun-craft-targets.md row 18) and are heard crouched too.

## Metres a second that make footsteps.
const RUN_SPEED: float = 3.5
## Metres of running ground between footfalls: about three a second at the
## 6 m/s top speed.
const STRIDE: float = 2.0
## A run that starts puts its first foot down after this share of a stride.
const FIRST_STEP_SHARE: float = 0.5
## Shorter airtime is a step down or a bump on a ceiling, not a landing.
const MIN_AIR_SECONDS: float = 0.12
## Airtime at or above this lands at full weight; a hop lands lighter.
const FULL_LANDING_SECONDS: float = 0.4
const HOP_LANDING_DB: float = -4.0
## A jump is a take-off that rises this far within JUMP_WINDOW seconds; leaving
## a ledge falls instead, and pushes off nothing.
const JUMP_RISE: float = 0.05
const JUMP_WINDOW: float = 0.2
## Frames longer than this (a hitch, a pause) say nothing about speed.
const MAX_DELTA: float = 0.25
## A frame's travel above this is a teleport or respawn, not a stride.
const MAX_TRAVEL: float = 2.0

const NONE: String = ""
const STEP: String = "step"
const LAND: String = "land"
const JUMP: String = "jump"

var _distance: float = STRIDE * FIRST_STEP_SHARE
var _airborne: bool = false
var _air_seconds: float = 0.0
var _running: bool = false
var _rise: float = 0.0
var _jump_open: bool = false
## Level offset of the last landing, for its volume.
var landing_db: float = 0.0


func reset() -> void:
	_distance = STRIDE * FIRST_STEP_SHARE
	_airborne = false
	_air_seconds = 0.0
	_running = false
	_rise = 0.0
	_jump_open = false
	landing_db = 0.0


## Whether this speed and stance make running footsteps.
static func running(speed: float, ducking: bool) -> bool:
	return not ducking and speed >= RUN_SPEED


## One rendered frame. Returns NONE, STEP, LAND or JUMP.
func advance(delta: float, travel: float, rise: float, airborne: bool, ducking: bool, alive: bool, seated: bool) -> String:
	if not alive or seated or delta <= 0.0 or not is_finite(delta) or not is_finite(travel) or not is_finite(rise):
		reset()
		_airborne = airborne
		return NONE
	var was_airborne: bool = _airborne
	_airborne = airborne
	if airborne:
		if not was_airborne:
			_air_seconds = 0.0
			_rise = 0.0
			_jump_open = true
		_air_seconds += minf(delta, MAX_DELTA)
		_distance = STRIDE * FIRST_STEP_SHARE
		if _jump_open:
			_rise += rise
			if _rise >= JUMP_RISE:
				_jump_open = false
				return JUMP
			if _air_seconds > JUMP_WINDOW or _rise < -JUMP_RISE:
				_jump_open = false
		return NONE
	if was_airborne:
		_jump_open = false
		var air: float = _air_seconds
		_air_seconds = 0.0
		_distance = 0.0
		if air >= MIN_AIR_SECONDS:
			landing_db = 0.0 if air >= FULL_LANDING_SECONDS else HOP_LANDING_DB
			return LAND
	if delta > MAX_DELTA or travel > MAX_TRAVEL:
		return NONE
	var now_running: bool = running(travel / delta, ducking)
	if not now_running:
		_running = false
		_distance = STRIDE * FIRST_STEP_SHARE
		return NONE
	_running = true
	_distance += travel
	if _distance >= STRIDE:
		_distance = fmod(_distance, STRIDE)
		return STEP
	return NONE
