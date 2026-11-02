extends RefCounted
class_name FrameGovernor

## The in-match safety valve for auto settings. It scores real play in 30 s
## windows; three windows in a row with a 1% low under the target arm one
## step, taken only at the next safe point (a death, a respawn, a checkpoint
## or a round end), never mid-fight. A step turns off or lowers one costly
## effect, least visible first (RenderQuality.GOVERNOR_ORDER). It never
## touches the world pixels, output resolution, renderer or a pinned option,
## never steps back up mid-match, and its steps last only this session.

const WINDOW_SECONDS: float = 30.0
const FAIL_WINDOWS: int = 3
## A gap this long is a load, a pause or an alt-tab, not a frame of play:
## the window starts over.
const GAP_SECONDS: float = 0.5
## After this much play on one tune, mostly failing windows advise a re-tune.
const ADVISE_SECONDS: float = 900.0

var target: int = 60
var enabled: bool = true
var renderer: String = "forward_plus"
var quality: int = RenderQuality.MEDIUM
var armed: bool = false
var windows: int = 0
var failing_windows: int = 0
var played_seconds: float = 0.0
var last_window_low_1: float = 0.0
var _streak: int = 0
var _window: PackedFloat32Array = PackedFloat32Array()
var _window_seconds: float = 0.0

## Auto settings on, the in-match valve on, and the tier not pinned.
static func allowed(preferences: LocalExceptionSettings) -> bool:
	return bool(preferences.get_value("video", "auto")) and bool(preferences.get_value("video", "governor")) and not preferences.pinned("quality")

static func for_settings(preferences: LocalExceptionSettings, current_renderer: String) -> FrameGovernor:
	var governor: FrameGovernor = FrameGovernor.new()
	governor.target = preferences.target_fps()
	governor.enabled = allowed(preferences)
	governor.renderer = current_renderer
	governor.quality = int(preferences.get_value("video", "quality"))
	return governor

## One drawn frame of play, in seconds.
func push(interval: float) -> void:
	if not enabled or not is_finite(interval) or interval <= 0.0:
		return
	if interval >= GAP_SECONDS:
		_window = PackedFloat32Array()
		_window_seconds = 0.0
		return
	_window.append(interval)
	_window_seconds += interval
	played_seconds += interval
	if _window_seconds < WINDOW_SECONDS:
		return
	var stats: Dictionary = FrameStats.report(_window)
	last_window_low_1 = float(stats.get("low_1_count_fps", 0.0))
	windows += 1
	if last_window_low_1 < float(target):
		failing_windows += 1
		_streak += 1
		if _streak >= FAIL_WINDOWS:
			armed = true
			_streak = 0
	else:
		_streak = 0
	_window = PackedFloat32Array()
	_window_seconds = 0.0

## The next step that would change what is drawn now, or "" when none is
## left (the tier is already at its floor for every governed feature).
func next_step() -> String:
	var now: Dictionary = RenderQuality.tier_spec(quality, renderer)
	for step: String in RenderQuality.GOVERNOR_ORDER:
		if RenderQuality.reductions.has(step):
			continue
		var steps: PackedStringArray = RenderQuality.reductions.duplicate()
		steps.append(step)
		var saved: PackedStringArray = RenderQuality.reductions
		RenderQuality.reductions = steps
		var after: Dictionary = RenderQuality.tier_spec(quality, renderer)
		RenderQuality.reductions = saved
		if after != now:
			return step
	return ""

## A safe point arrived. Take the armed step, if any, and return its name.
func safe_point() -> String:
	if not enabled or not armed:
		return ""
	armed = false
	var step: String = next_step()
	if step.is_empty():
		return ""
	RenderQuality.reductions.append(step)
	return step

## Most windows of long play fell short: the saved tune no longer fits.
func advise_retune() -> bool:
	return played_seconds >= ADVISE_SECONDS and windows > 0 and failing_windows * 2 > windows

## The HUD line for a step: one level sentence, no tilt.
static func notice(step: String, target_fps: int) -> String:
	var names: Dictionary = {"volumetric_fog": "volumetric fog off", "ssil": "bounce light off", "ssr": "reflections off",
		"ssao": "contact shading lowered", "practical_shadows": "lamp shadows shortened", "effects": "fewer marks and effects", "msaa": "edge smoothing lowered"}
	return "Graphics lowered: %s to hold %d." % [str(names.get(step, step)), target_fps]

## Undo every step: a new session or a re-tune starts from the tier itself.
static func clear() -> void:
	RenderQuality.reductions = PackedStringArray()
