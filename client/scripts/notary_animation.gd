class_name NotaryAnimation
extends RefCounted

## Frames show server phases. A held windup never becomes a client shot.
const TILE: int = 128
const COLUMNS: int = 16
const DIRECTIONS: int = 8
const VIEW_SIZE: float = 2.2
const CENTRE_HEIGHT: float = 0.35
const CLIPS: Array[Dictionary] = [
	{"action":"hover", "count":2}, {"action":"windup", "count":4},
	{"action":"fire", "count":2}, {"action":"recovery", "count":2},
	{"action":"hit", "count":1}, {"action":"tumble", "count":4},
	{"action":"wreck", "count":1},
]
static var _solids: Array[Dictionary] = []

static func configure_map(info: Dictionary) -> void:
	_solids.clear()
	for solid: Dictionary in info.get("solids", []):
		_solids.append(solid.duplicate(true))

static func support(feet: Vector3) -> float:
	var result: float = 0.0
	for solid: Dictionary in _solids:
		var top: float = float(solid.get("top", MoveStep.WALL_TOP))
		if top <= feet.y + 0.04 and feet.x >= float(solid["min_x"]) \
			and feet.x <= float(solid["max_x"]) and feet.z >= float(solid["min_z"]) \
			and feet.z <= float(solid["max_z"]):
			result = maxf(result, top)
	return result

static func poses() -> int:
	var count: int = 0
	for clip: Dictionary in CLIPS:
		count += int(clip["count"])
	return count

static func rows() -> int:
	return ceili(float(poses() * DIRECTIONS) / COLUMNS)

static func pose_frame(action: String, progress: float) -> int:
	var offset: int = 0
	for clip: Dictionary in CLIPS:
		var count: int = int(clip["count"])
		if clip["action"] == action:
			return offset + mini(int(clampf(progress, 0.0, 1.0) * count), count - 1)
		offset += count
	push_error("notary_animation: unknown clip")
	return 0

static func frame(actor: Dictionary, tick: int, elapsed: float, facing: int, landed: bool) -> int:
	var age: float = maxf(0.0, float(tick - int(actor["phase_started"])) * EnemyAnimation.TICK_SECONDS)
	age += clampf(elapsed, 0.0, EnemyAnimation.MAX_EXTRAPOLATION)
	var duration: float = maxf(EnemyAnimation.TICK_SECONDS,
		float(int(actor["phase_ends"]) - int(actor["phase_started"])) * EnemyAnimation.TICK_SECONDS)
	var action: String = "hover"
	var progress: float = fposmod(age, 0.8) / 0.8
	match actor["phase"]:
		"windup":
			action = "windup"
			progress = age / duration
		"firing":
			action = "fire"
			progress = age / duration
		"recovery":
			action = "recovery"
			progress = age / duration
		"hit":
			action = "hit"
		"dead":
			action = "wreck" if landed else "tumble"
			progress = fposmod(age, 0.6) / 0.6
	return posmod(facing, DIRECTIONS) * poses() + pose_frame(action, progress)
