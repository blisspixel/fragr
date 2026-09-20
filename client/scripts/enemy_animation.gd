class_name EnemyAnimation
extends RefCounted

## Presentation layout shared with the offline baker. No combat transitions here.
const TILE: int = 160
const COLUMNS: int = 18
const DIRECTIONS: int = 8
const VIEW_SIZE: float = 3.0
const CENTRE_HEIGHT: float = 0.9
const TICK_SECONDS: float = 0.05
const MAX_EXTRAPOLATION: float = 0.1
const STRIDE_METRES: float = 1.6
const DEATH_SECONDS: float = 0.7

const CLIPS: Array[Dictionary] = [
	{"action":"idle", "unarmed":false, "count":1},
	{"action":"walk", "unarmed":false, "count":8},
	{"action":"raise", "unarmed":false, "count":4},
	{"action":"fire", "unarmed":false, "count":2},
	{"action":"recover", "unarmed":false, "count":3},
	{"action":"hit", "unarmed":false, "count":2},
	{"action":"death", "unarmed":false, "count":7},
	{"action":"idle", "unarmed":true, "count":1},
	{"action":"walk", "unarmed":true, "count":8},
	{"action":"raise", "unarmed":true, "count":4},
	{"action":"fire", "unarmed":true, "count":2},
	{"action":"recover", "unarmed":true, "count":3},
	{"action":"hit", "unarmed":true, "count":2},
	{"action":"death", "unarmed":true, "count":7},
]

static func poses() -> int:
	var total: int = 0
	for clip: Dictionary in CLIPS:
		total += int(clip["count"])
	return total

static func rows() -> int:
	return ceili(float(poses() * DIRECTIONS) / COLUMNS)

static func pose_frame(action: String, unarmed: bool, progress: float) -> int:
	var offset: int = 0
	for clip: Dictionary in CLIPS:
		var count: int = int(clip["count"])
		if clip["action"] == action and bool(clip["unarmed"]) == unarmed:
			return offset + mini(int(clampf(progress, 0.0, 1.0) * count), count - 1)
		offset += count
	push_error("enemy_animation: unknown clip")
	return 0

## The baker rotates a +Z-facing model in 45 degree increments in front of a
## fixed camera. Runtime facing uses the server's +X/atan2 convention.
static func direction(yaw: float, to_camera: Vector3) -> int:
	if Vector2(to_camera.x, to_camera.z).length_squared() < 0.0001:
		return 0
	var relative: float = atan2(to_camera.z, to_camera.x) - yaw
	return posmod(roundi(relative * DIRECTIONS / TAU), DIRECTIONS)

static func frame(actor: Dictionary, weapon: String, tick: int, elapsed: float,
		travel: float, shot_age: float, facing: int) -> int:
	var phase: String = actor["phase"]
	var age: float = maxf(0.0, float(tick - int(actor["phase_started"])) * TICK_SECONDS)
	age += clampf(elapsed, 0.0, MAX_EXTRAPOLATION)
	var duration: float = maxf(TICK_SECONDS,
		float(int(actor["phase_ends"]) - int(actor["phase_started"])) * TICK_SECONDS)
	var unarmed: bool = weapon == "Fists"
	var action: String = "idle"
	var progress: float = 0.0
	match phase:
		"dead":
			action = "death"
			progress = age / DEATH_SECONDS
		"hit":
			action = "hit"
			progress = age / duration
		"windup":
			action = "raise"
			progress = age / duration
		"firing", "recovery":
			if shot_age < 0.1:
				action = "fire"
				progress = shot_age / 0.1
			elif phase == "firing":
				action = "raise"
				progress = 1.0
			else:
				action = "recover"
				progress = age / duration
		"moving":
			action = "walk"
			progress = fposmod(travel / STRIDE_METRES, 1.0)
	return posmod(facing, DIRECTIONS) * poses() + pose_frame(action, unarmed, progress)
