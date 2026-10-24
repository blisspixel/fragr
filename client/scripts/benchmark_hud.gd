class_name BenchmarkHud
extends CanvasLayer

## The benchmark's own readout while it runs: what is happening now, how far
## the whole run has come, and a live frame rate. The match HUD is hidden for
## the whole benchmark, so this is the only text over the measured scene.
##
## The player's frame counter (PerformanceOverlay) can still be on. Its text
## arrives through `reserved_query` as rectangles, the same shape the match HUD
## reads through `top_region_query`, and each top plate starts below any
## reservation that crosses its span (HudRegions.column_top). Nothing is shrunk
## to fit under it.
##
## Text refreshes four times a second. The live figures are a rolling window
## and are labelled as such; the result screen reports the scored window.

const REFRESH_SECONDS: float = 0.25
## Four refresh buckets: the live readout covers about the last second.
const LIVE_BUCKETS: int = 4
const MARGIN: float = 24.0
const STATUS_WIDTH: float = 760.0
const LIVE_WIDTH: float = 380.0
## Narrower than this (per 100 percent text), the status stacks above the live plate.
const STATUS_FLOOR: float = 420.0

## Overall progress: an inset bar with a notch at each step boundary.
class Meter extends Control:
	var fraction: float = 0.0
	var marks: PackedFloat32Array = PackedFloat32Array()

	func set_progress(value: float, boundaries: PackedFloat32Array) -> void:
		var clamped: float = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
		if is_equal_approx(clamped, fraction) and boundaries == marks:
			return
		fraction = clamped
		marks = boundaries
		queue_redraw()

	func _draw() -> void:
		var box: Rect2 = Rect2(Vector2.ZERO, size)
		draw_rect(box, MenuTheme.INSET)
		draw_rect(Rect2(box.position, Vector2(box.size.x * fraction, box.size.y)), MenuTheme.EMBER)
		for mark: float in marks:
			var x: float = roundf(box.size.x * mark)
			draw_rect(Rect2(x - 1.0, 0.0, 3.0, box.size.y), MenuTheme.INK)
		draw_rect(box, MenuTheme.BORDER, false, 2.0)

var style: HudStyle = HudStyle.new()
## Returns Array[Rect2]: other layers' text on this canvas (the frame counter).
var reserved_query: Callable

var _status: PanelContainer
var _headline: Label
var _detail: Label
var _meter: Meter
var _totals: Label
var _steps: HFlowContainer
var _live: PanelContainer
var _live_caption: Label
var _live_fps: Label
var _live_ms: Label
var _scored_caption: Label
var _scored: Label
var _hint: RichTextLabel
var _view: Dictionary = {}
var _bucket_frames: int = 0
var _bucket_seconds: float = 0.0
var _buckets: Array[Vector2] = []
var _layout_key: Array = []
var _refit_pending: bool = false
## What the step chips and the scored line last showed. Restyling a chip or
## recolouring a label rebuilds its theme cache, so a refresh restyles only
## when the step or the scored state actually changed.
var _steps_key: Array = []
var _scored_live: int = -1

func _ready() -> void:
	name = "BenchmarkHud"
	layer = 80
	_status = _plate("Status")
	var column: VBoxContainer = _column(_status)
	_headline = _text(column, "Headline", true)
	_detail = _text(column, "Detail")
	_meter = Meter.new()
	_meter.name = "Progress"
	column.add_child(_meter)
	_totals = _text(column, "Totals")
	_steps = HFlowContainer.new()
	_steps.name = "Steps"
	_steps.add_theme_constant_override("h_separation", 8)
	_steps.add_theme_constant_override("v_separation", 8)
	column.add_child(_steps)
	_live = _plate("Live")
	var live: VBoxContainer = _column(_live)
	_live_caption = _text(live, "LiveCaption")
	_live_caption.add_theme_color_override("font_color", MenuTheme.EMBER)
	_live_fps = _text(live, "LiveFps", true)
	_live_ms = _text(live, "LiveFrameTime")
	var rule: ColorRect = ColorRect.new()
	rule.color = MenuTheme.EDGE
	rule.custom_minimum_size = Vector2(0.0, 3.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live.add_child(rule)
	_scored_caption = _text(live, "ScoredCaption")
	_scored_caption.add_theme_color_override("font_color", MenuTheme.EMBER)
	_scored = _text(live, "Scored")
	_hint = RichTextLabel.new()
	_hint.name = "Hint"
	_hint.bbcode_enabled = false
	_hint.fit_content = true
	_hint.scroll_active = false
	_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.add_theme_color_override("font_outline_color", MenuTheme.INK)
	_hint.add_theme_color_override("default_color", MenuTheme.BONE)
	add_child(_hint)
	get_viewport().size_changed.connect(_relayout)
	for owner: Control in [_status, _live, _hint]:
		owner.minimum_size_changed.connect(_refit)
	apply_style(style)

func apply_style(next: HudStyle) -> void:
	style = next if next != null else HudStyle.new()
	if _status == null:
		return
	var body: int = style.body_font_size()
	for label: Label in [_detail, _totals, _live_caption, _live_ms, _scored_caption, _scored]:
		label.add_theme_font_size_override("font_size", body)
	_headline.add_theme_font_size_override("font_size", style.display_font_size(MenuTheme.DISPLAY_SMALL))
	_live_fps.add_theme_font_size_override("font_size", style.display_font_size(MenuTheme.DISPLAY_MEDIUM))
	_meter.custom_minimum_size = Vector2(0.0, style.scaled_size(18.0))
	_hint.add_theme_font_override("normal_font", MenuTheme.FONT)
	_hint.add_theme_font_size_override("normal_font_size", body)
	for chip: Node in _steps.get_children():
		((chip as PanelContainer).get_child(0) as Label).add_theme_font_size_override("font_size", body)
	_steps_key = []
	_layout_key = []
	_render_hint()
	_relayout()

## One drawn frame's interval in seconds, from the run's own monotonic clock.
func push_interval(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0.0:
		return
	_bucket_frames += 1
	_bucket_seconds += seconds
	if _bucket_seconds < REFRESH_SECONDS:
		return
	_buckets.append(Vector2(_bucket_frames, _bucket_seconds))
	if _buckets.size() > LIVE_BUCKETS:
		_buckets.pop_front()
	_bucket_frames = 0
	_bucket_seconds = 0.0
	_render_live()

## Forget the live window, so the load between presets is not reported as the
## first second of the next one.
func reset_live() -> void:
	_buckets.clear()
	_bucket_frames = 0
	_bucket_seconds = 0.0
	_render_live()

## Rolling frames per second and mean frame time over the live window.
func live() -> Dictionary:
	var frames: float = 0.0
	var seconds: float = 0.0
	for bucket: Vector2 in _buckets:
		frames += bucket.x
		seconds += bucket.y
	if frames <= 0.0 or seconds <= 0.0:
		return {}
	return {"fps": frames / seconds, "frame_ms": seconds / frames * 1000.0, "seconds": seconds}

## Present BenchmarkRun.progress(). Cheap enough for every refresh.
func show_progress(view: Dictionary) -> void:
	_view = view
	if _status == null:
		return
	_headline.text = str(view.get("headline", ""))
	_detail.text = str(view.get("detail", ""))
	_meter.set_progress(float(view.get("overall", 0.0)), view.get("marks", PackedFloat32Array()))
	_totals.text = "%s ELAPSED // ABOUT %s LEFT" % [clock(float(view.get("elapsed_s", 0.0))), clock(float(view.get("remaining_s", 0.0)))]
	_render_steps(view.get("steps", PackedStringArray()), int(view.get("step", 0)))
	_render_live()
	_relayout()

func _render_live() -> void:
	if _live == null:
		return
	var now: Dictionary = live()
	_live_caption.text = "LIVE // LAST SECOND"
	_live_fps.text = "%d FPS" % roundi(float(now["fps"])) if not now.is_empty() else "-- FPS"
	_live_ms.text = "%.1f MS A FRAME" % float(now["frame_ms"]) if not now.is_empty() else "-- MS A FRAME"
	var frames: int = int(_view.get("scored_frames", 0))
	var seconds: float = float(_view.get("scored_s", 0.0))
	_scored_caption.text = "THIS PRESET SO FAR"
	var scoring: bool = str(_view.get("state", "")) == "scoring" and frames > 0 and seconds > 0.0
	_scored.text = "%d FPS AVERAGE\n%d FRAMES SCORED" % [roundi(float(frames) / seconds), frames] if scoring else "NOT SCORED YET"
	if _scored_live != int(scoring):
		_scored_live = int(scoring)
		_scored.add_theme_color_override("font_color", MenuTheme.BONE if scoring else MenuTheme.MUTED)

func _render_steps(steps: Variant, current: int) -> void:
	var names: PackedStringArray = steps if steps is PackedStringArray else PackedStringArray()
	var key: Array = [names, current, style.body_font_size()]
	if key == _steps_key and _steps.get_child_count() == names.size():
		return
	_steps_key = key
	if _steps.get_child_count() != names.size():
		for child: Node in _steps.get_children():
			_steps.remove_child(child)
			child.queue_free()
		for index: int in names.size():
			var chip: PanelContainer = PanelContainer.new()
			chip.name = "Step%d" % index
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var label: Label = Label.new()
			label.add_theme_font_override("font", MenuTheme.FONT)
			label.add_theme_font_size_override("font_size", style.body_font_size())
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(label)
			_steps.add_child(chip)
	for index: int in names.size():
		var chip: PanelContainer = _steps.get_child(index) as PanelContainer
		var label: Label = chip.get_child(0) as Label
		var done: bool = index < current
		var now: bool = index == current
		label.text = names[index].to_upper()
		label.add_theme_color_override("font_color", MenuTheme.BONE if now else MenuTheme.MUTED)
		var plate: StyleBoxFlat = MenuTheme.panel(MenuTheme.SURFACE if now else MenuTheme.INSET, MenuTheme.EMBER if now else (MenuTheme.SUCCESS if done else MenuTheme.EDGE))
		plate.shadow_size = 0
		plate.shadow_offset = Vector2.ZERO
		plate.set_border_width_all(2)
		plate.border_width_bottom = 6 if done or now else 2
		plate.content_margin_left = 10
		plate.content_margin_right = 10
		plate.content_margin_top = 4
		plate.content_margin_bottom = 4
		chip.add_theme_stylebox_override("panel", plate)

func _render_hint() -> void:
	if _hint == null:
		return
	InputGlyphs.render(_hint, "{back} CANCEL // AUTOMATED CAMERA OVER A RECORDED FIGHT", style.body_font_size(), true)

## Rectangles the frame counter and any other layer report, validated: only
## finite Rect2 values with area are kept, as HudRegions does for the match HUD.
func reserved_regions() -> Array[Rect2]:
	var regions: Array[Rect2] = []
	if not reserved_query.is_valid():
		return regions
	var answer: Variant = reserved_query.call()
	if not answer is Array:
		return regions
	for value: Variant in answer:
		if value is Rect2 and (value as Rect2).has_area() and (value as Rect2).is_finite():
			regions.append(value)
	return regions

func _relayout() -> void:
	if _status == null or not is_inside_tree():
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var reserved: Array[Rect2] = reserved_regions()
	var key: Array = [view, reserved, style.scale, style.text_size, _headline.text, _detail.text, _steps.get_child_count(), _scored.text, _live_fps.text]
	if key == _layout_key:
		return
	_layout_key = key
	var margin: float = style.scaled_size(MARGIN)
	# Plates widen with the body text (HUD scale and large text), never past the view.
	var text_scale: float = float(style.body_font_size()) / float(MenuTheme.BODY)
	var live_w: float = minf(LIVE_WIDTH * text_scale, view.x - margin * 2.0)
	# The status plate gives up width first: it wraps, the live numbers do not.
	var status_w: float = minf(STATUS_WIDTH * text_scale, view.x - live_w - margin * 3.0)
	# Side by side while the status keeps a usable width; otherwise stack.
	var side_by_side: bool = status_w >= STATUS_FLOOR * text_scale
	if not side_by_side:
		status_w = minf(STATUS_WIDTH * text_scale, view.x - margin * 2.0)
	var status_x: float = margin
	_place(_status, Vector2(status_x, HudRegions.column_top(margin, status_x, status_w, reserved)), status_w)
	var live_x: float = view.x - margin - live_w if side_by_side else margin
	var live_top: float = HudRegions.column_top(margin, live_x, live_w, reserved)
	if not side_by_side:
		live_top = maxf(live_top, _status.position.y + _status.size.y + HudRegions.GAP)
	_place(_live, Vector2(live_x, live_top), live_w)
	_hint.size = Vector2(view.x - margin * 2.0, 0.0)
	_hint.position = Vector2(margin, view.y - margin - _hint.get_content_height())

func _place(plate: PanelContainer, at: Vector2, width: float) -> void:
	plate.position = at
	plate.size = Vector2(width, plate.get_combined_minimum_size().y)

## Wrapped text knows its height only after its container has given it a
## width, a sort later. When a plate's minimum then changes, lay out again so
## the plate hugs its text instead of keeping a height from an earlier width.
func _refit() -> void:
	if _refit_pending:
		return
	_refit_pending = true
	_apply_refit.call_deferred()

func _apply_refit() -> void:
	_refit_pending = false
	_layout_key = []
	_relayout()

## Bounds of every plate and the hint, in canvas coordinates, for layout checks.
func occupied() -> Dictionary:
	var out: Dictionary = {}
	if _status == null:
		return out
	out["status"] = _status.get_global_rect()
	out["live"] = _live.get_global_rect()
	out["hint"] = Rect2(_hint.global_position, Vector2(_hint.size.x, _hint.get_content_height()))
	return out

static func clock(seconds: float) -> String:
	var whole: int = maxi(0, ceili(seconds - 0.001)) if is_finite(seconds) else 0
	return "%d:%02d" % [whole / 60, whole % 60]

func _plate(node_name: String) -> PanelContainer:
	var plate: PanelContainer = PanelContainer.new()
	plate.name = node_name
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box: StyleBoxFlat = MenuTheme.panel(MenuTheme.alpha(MenuTheme.INK, 0.86), MenuTheme.EDGE)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 14
	box.content_margin_bottom = 16
	plate.add_theme_stylebox_override("panel", box)
	add_child(plate)
	return plate

func _column(plate: PanelContainer) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(column)
	return column

func _text(parent: Node, node_name: String, display: bool = false) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", MenuTheme.DISPLAY_FONT if display else MenuTheme.FONT)
	label.add_theme_color_override("font_color", MenuTheme.BONE)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 4 if display else 3)
	parent.add_child(label)
	return label
