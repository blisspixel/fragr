class_name JammerAnimation
extends RefCounted

## The dish follows server phases. A held tell never launches a client attack.
const TILE: int = 160
const COLUMNS: int = 18
const DIRECTIONS: int = 8
const VIEW_SIZE: float = 3.0
const CENTRE_HEIGHT: float = 0.9
const DEATH_SECONDS: float = 0.65
const CLIPS: Array[Dictionary] = [
	{"action":"idle", "count":2},
	{"action":"unfold", "count":5},
	{"action":"pulse", "count":3},
	{"action":"fold", "count":4},
	{"action":"hit", "count":2},
	{"action":"death", "count":5},
]

static func poses() -> int:
	var total: int = 0
	for clip: Dictionary in CLIPS:
		total += int(clip["count"])
	return total

static func rows() -> int:
	return ceili(float(poses() * DIRECTIONS) / COLUMNS)

static func pose_frame(action: String, progress: float) -> int:
	var offset: int = 0
	for clip: Dictionary in CLIPS:
		var count: int = int(clip["count"])
		if clip["action"] == action:
			return offset + mini(int(clampf(progress, 0.0, 1.0) * count), count - 1)
		offset += count
	push_error("jammer_animation: unknown clip")
	return 0

static func frame(actor: Dictionary, tick: int, elapsed: float, facing: int) -> int:
	var phase: String = actor["phase"]
	var age: float = maxf(0.0, float(tick - int(actor["phase_started"])) * EnemyAnimation.TICK_SECONDS)
	age += clampf(elapsed, 0.0, EnemyAnimation.MAX_EXTRAPOLATION)
	var duration: float = maxf(EnemyAnimation.TICK_SECONDS,
		float(int(actor["phase_ends"]) - int(actor["phase_started"])) * EnemyAnimation.TICK_SECONDS)
	var action: String = "idle"
	var progress: float = 0.0
	match phase:
		"windup":
			action = "unfold"
			progress = age / duration
		"firing":
			action = "pulse"
			progress = age / duration
		"recovery":
			action = "fold"
			progress = age / duration
		"hit":
			action = "hit"
			progress = age / duration
		"dead":
			action = "death"
			progress = age / DEATH_SECONDS
	return posmod(facing, DIRECTIONS) * poses() + pose_frame(action, progress)
