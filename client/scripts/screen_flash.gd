class_name ScreenFlash
extends Control

## Bounded screen flash presenter.
## Shared rolling budget of at most 3 admissions per second across all producers
## (damage, spawn, nods, episode outcomes, warmup, podium) under Reduced mode.
## Off completely suppresses flashes. Full retains standard intensity.
## Never uses full-screen washes or magenta.

const BUDGET_PER_SECOND: int = 3
const ROLLING_WINDOW_SEC: float = 1.0
const MAX_REDUCED_ALPHA: float = 0.24
const MAX_FULL_ALPHA: float = 0.50

var flash_mode: int = FragrSettings.FLASHES_REDUCED
var active: bool = false
var current_reason: String = ""
var current_color: Color = MenuTheme.DANGER
var current_duration: float = 0.25
var remaining_time: float = 0.0
var time_source: Callable = Callable()

var _history: Array[float] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	if get_tree() != null and get_tree().has_meta("fragr_flash_history"):
		var saved = get_tree().get_meta("fragr_flash_history")
		if saved is Array:
			_history.clear()
			for t in saved:
				_history.append(float(t))

func _now() -> float:
	if time_source.is_valid():
		return float(time_source.call())
	return float(Time.get_ticks_msec()) * 0.001

func set_flash_mode(mode: int) -> void:
	flash_mode = clampi(mode, FragrSettings.FLASHES_FULL, FragrSettings.FLASHES_OFF)
	if flash_mode == FragrSettings.FLASHES_OFF:
		active = false
		visible = false
		remaining_time = 0.0
		queue_redraw()
	elif flash_mode == FragrSettings.FLASHES_REDUCED and active:
		queue_redraw()

func prune_history(now: float) -> void:
	var threshold: float = now - ROLLING_WINDOW_SEC
	while not _history.is_empty() and _history[0] < threshold:
		_history.pop_front()
	if get_tree() != null:
		get_tree().set_meta("fragr_flash_history", _history)

## Trigger a flash impulse. Returns true if admitted and presented.
func trigger(reason: String, color: Color, duration: float = 0.25) -> bool:
	if flash_mode == FragrSettings.FLASHES_OFF:
		active = false
		visible = false
		remaining_time = 0.0
		queue_redraw()
		return false

	var now: float = _now()
	prune_history(now)

	if flash_mode == FragrSettings.FLASHES_REDUCED:
		if _history.size() >= BUDGET_PER_SECOND:
			# Rate limit exceeded. Rejected impulses do not restart or extend.
			return false

	_history.append(now)
	if get_tree() != null:
		get_tree().set_meta("fragr_flash_history", _history)

	current_reason = reason
	current_color = color
	# Magenta is strictly forbidden in the UI palette.
	if current_color.r > 0.5 and current_color.b > 0.5 and current_color.g < 0.25:
		current_color = MenuTheme.DANGER
	current_duration = maxf(0.05, duration)
	remaining_time = current_duration
	active = true
	visible = true
	queue_redraw()
	return true

func _process(delta: float) -> void:
	if not active:
		if visible:
			visible = false
			queue_redraw()
		return

	remaining_time -= delta
	if remaining_time <= 0.0:
		active = false
		visible = false
		remaining_time = 0.0
	queue_redraw()

func _draw() -> void:
	if not active or flash_mode == FragrSettings.FLASHES_OFF:
		return

	var rect: Rect2 = get_viewport_rect()
	var progress: float = clampf(remaining_time / current_duration, 0.0, 1.0)
	var max_alpha: float = MAX_REDUCED_ALPHA if flash_mode == FragrSettings.FLASHES_REDUCED else MAX_FULL_ALPHA
	var alpha: float = progress * max_alpha

	var draw_col: Color = current_color
	draw_col.a = alpha

	# Exact 2-physical-pixel perimeter frame along viewport edges
	var border_px: float = 2.0
	var w: float = rect.size.x
	var h: float = rect.size.y

	# Top
	draw_rect(Rect2(0, 0, w, border_px), draw_col)
	# Bottom
	draw_rect(Rect2(0, h - border_px, w, border_px), draw_col)
	# Left
	draw_rect(Rect2(0, border_px, border_px, h - border_px * 2.0), draw_col)
	# Right
	draw_rect(Rect2(w - border_px, border_px, border_px, h - border_px * 2.0), draw_col)

	# In Full mode or for stronger cues, draw a secondary 4px stepped falloff
	if flash_mode == FragrSettings.FLASHES_FULL:
		var inner_col: Color = draw_col
		inner_col.a = alpha * 0.4
		draw_rect(Rect2(border_px, border_px, w - border_px * 2.0, 4.0), inner_col)
		draw_rect(Rect2(border_px, h - border_px - 4.0, w - border_px * 2.0, 4.0), inner_col)
		draw_rect(Rect2(border_px, border_px + 4.0, 4.0, h - (border_px + 4.0) * 2.0), inner_col)
		draw_rect(Rect2(w - border_px - 4.0, border_px + 4.0, 4.0, h - (border_px + 4.0) * 2.0), inner_col)
