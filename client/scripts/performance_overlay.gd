extends CanvasLayer
class_name PerformanceOverlay

## The frame counter in the top right corner, in the tradition of
## Counter-Strike's cl_showfps. It is off by default and switched from the
## Display settings page or the console. Mode 1 shows frames per second. Mode 2
## adds the average frame time and the 1% low, the frame rate across the
## slowest one in a hundred recent frames, which is the number that says whether a
## hitch is real.
##
## It measures wall-clock intervals between drawn frames rather than the
## process delta, so time scale and pause cannot flatter it, and it never
## touches the match. The boot menu and the match manager each mount one,
## beside their console.

const OFF: int = 0
const FPS: int = 1
const DETAIL: int = 2
const MODES: Array[int] = [OFF, FPS, DETAIL]
## Rolling sample for the average and the 1% low: a few seconds at most rates.
const WINDOW_FRAMES: int = 600
const REFRESH_SECONDS: float = 0.25
## A frame interval past this is a stall, a load or a debugger stop; it still
## counts, but one absurd value must not make the readout unreadable.
const MAX_INTERVAL_SECONDS: float = 1.0

var preferences: FragrSettings

var _mode: int = OFF
var _label: Label = null
var _intervals: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _count: int = 0
var _last_usec: int = -1
var _since_refresh: float = 0.0

func _ready() -> void:
	layer = 127 # Just under the console, above every HUD and menu layer.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_intervals.resize(WINDOW_FRAMES)
	_label = Label.new()
	_label.name = "FrameCounter"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.anchor_left = 1.0
	_label.anchor_right = 1.0
	_label.offset_left = -360.0
	_label.offset_right = -8.0
	_label.offset_top = 2.0
	_label.offset_bottom = 19.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_override("font", MenuTheme.FONT)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", MenuTheme.BONE)
	_label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	_label.add_theme_constant_override("outline_size", 3)
	add_child(_label)
	if preferences != null:
		preferences.changed.connect(apply_preferences)
	apply_preferences()

func apply_preferences() -> void:
	var mode: Variant = OFF if preferences == null else preferences.get_value("video", "show_fps")
	set_mode(int(mode) if mode is int else OFF)

func mode() -> int:
	return _mode

func text() -> String:
	return "" if _label == null else _label.text

func set_mode(value: int) -> void:
	_mode = value if value in MODES else OFF
	visible = _mode != OFF
	set_process(_mode != OFF)
	_count = 0
	_next = 0
	_last_usec = -1
	_since_refresh = 0.0
	if _label != null:
		_label.text = ""

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _last_usec >= 0:
		var interval: float = float(now - _last_usec) / 1000000.0
		record(interval)
		_since_refresh += interval
		if _since_refresh >= REFRESH_SECONDS:
			_since_refresh = 0.0
			_label.text = format(_mode, summarize(samples()))
	_last_usec = now

## Adds one frame interval in seconds. Non-positive or non-finite values are
## measurement noise from a clock that did not advance and are dropped.
func record(interval: float) -> void:
	if not is_finite(interval) or interval <= 0.0:
		return
	_intervals[_next] = minf(interval, MAX_INTERVAL_SECONDS)
	_next = (_next + 1) % WINDOW_FRAMES
	_count = mini(_count + 1, WINDOW_FRAMES)

func samples() -> PackedFloat32Array:
	if _count < WINDOW_FRAMES:
		return _intervals.slice(0, _count)
	return _intervals.duplicate()

## Average frames per second, average frame time in milliseconds, and the 1%
## low: the rate over the slowest one percent of frames, at least one frame,
## as frame-time tools report it. Empty input gives zeros so the first refresh
## never divides by nothing.
static func summarize(intervals: PackedFloat32Array) -> Dictionary:
	if intervals.is_empty():
		return {"fps": 0.0, "frame_ms": 0.0, "low_fps": 0.0}
	var total: float = 0.0
	for interval: float in intervals:
		total += interval
	var mean: float = total / float(intervals.size())
	var sorted: PackedFloat32Array = intervals.duplicate()
	sorted.sort()
	var slow_count: int = maxi(1, floori(float(sorted.size()) / 100.0))
	var slow_total: float = 0.0
	for index: int in range(sorted.size() - slow_count, sorted.size()):
		slow_total += sorted[index]
	var slow: float = slow_total / float(slow_count)
	return {
		"fps": 1.0 / mean,
		"frame_ms": mean * 1000.0,
		"low_fps": 1.0 / slow,
	}

static func format(mode_value: int, summary: Dictionary) -> String:
	var fps: int = roundi(float(summary.get("fps", 0.0)))
	if mode_value == FPS:
		return "%d FPS" % fps
	if mode_value == DETAIL:
		return "%d FPS  %.1f MS  1%% LOW %d" % [
			fps,
			float(summary.get("frame_ms", 0.0)),
			roundi(float(summary.get("low_fps", 0.0))),
		]
	return ""
