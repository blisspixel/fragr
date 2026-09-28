class_name CrawlerAnimation
extends RefCounted

## A separate atlas keeps the four standing Union atlases below 4096 pixels.
## Frames are only presentation of authoritative campaign phases.
const TILE: int = 160
const COLUMNS: int = 18
const DIRECTIONS: int = 8
const VIEW_SIZE: float = 3.0
const CENTRE_HEIGHT: float = 0.9
const STRIDE_METRES: float = 0.9
const DEATH_SECONDS: float = 0.55
const CLIPS: Array[Dictionary] = [
	{"action":"idle", "count":1},
	{"action":"scuttle", "count":4},
	{"action":"crouch", "count":3},
	{"action":"leap", "count":3},
	{"action":"land", "count":2},
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
	push_error("crawler_animation: unknown clip")
	return 0

static func frame(actor: Dictionary, tick: int, elapsed: float, travel: float,
		facing: int) -> int:
	var phase: String = actor["phase"]
	var age: float = maxf(0.0, float(tick - int(actor["phase_started"])) * EnemyAnimation.TICK_SECONDS)
	age += clampf(elapsed, 0.0, EnemyAnimation.MAX_EXTRAPOLATION)
	var duration: float = maxf(EnemyAnimation.TICK_SECONDS,
		float(int(actor["phase_ends"]) - int(actor["phase_started"])) * EnemyAnimation.TICK_SECONDS)
	var action: String = "idle"
	var progress: float = 0.0
	match phase:
		"moving":
			action = "scuttle"
			progress = fposmod(travel / STRIDE_METRES, 1.0)
		"windup":
			action = "crouch"
			progress = age / duration
		"leaping", "firing":
			action = "leap"
			progress = age / duration
		"recovery":
			action = "land"
			progress = age / duration
		"hit":
			action = "hit"
			progress = age / duration
		"dead":
			action = "death"
			progress = age / DEATH_SECONDS
	return posmod(facing, DIRECTIONS) * poses() + pose_frame(action, progress)
