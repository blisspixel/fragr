class_name BenchmarkChart
extends Control

## Frame time across each preset's scored window, one row per preset on one
## shared scale so rows compare by eye. Every scored frame is drawn: each pixel
## column spans the fastest to the slowest frame that ended inside it, and a
## line joins each column's slowest frame, so a single hitch stays visible
## however many frames share the column. Frames above the scale's ceiling are
## drawn to the top edge and marked there in red. Guides mark 16.7 ms (60 FPS)
## and 33.3 ms (30 FPS); the scale always shows both.

const ROW_HEIGHT: float = 116.0
## Below this the guide labels and the scale label would meet.
const MIN_ROW_HEIGHT: float = 72.0
const ROW_GAP: float = 10.0
const LABEL_WIDTH: float = 250.0
const AXIS_HEIGHT: float = 40.0
const SCALE_WIDTH: float = 120.0
## Candidate ceilings in milliseconds; the smallest that holds twice the
## slowest preset's 95th percentile is used, so ordinary frames fill the row
## and rarer spikes are clipped and marked rather than flattening the rest.
const CEILINGS: Array[float] = [40.0, 50.0, 75.0, 100.0, 150.0, 200.0, 400.0]
const GUIDES: Array[Vector2] = [Vector2(1000.0 / 60.0, 60.0), Vector2(1000.0 / 30.0, 30.0)]
const SERIES: Array[Color] = [MenuTheme.EMBER, MenuTheme.CYAN, MenuTheme.BONE]

var runs: Array = []
## Plot height of one preset row; the results page fits it to the window.
var row_height: float = ROW_HEIGHT
var ceiling_ms: float = 50.0
var seconds: float = 20.0
var font_size: int = MenuTheme.BODY

static func series_color(index: int) -> Color:
	return SERIES[index % SERIES.size()]

## Rows read `preset`, `p95_ms` and the measured `frame_us` of each run.
func set_runs(value: Array, window_seconds: float) -> void:
	runs = value
	seconds = maxf(window_seconds, 0.001)
	ceiling_ms = ceiling_for(value)
	custom_minimum_size.y = float(value.size()) * (row_height + ROW_GAP) + AXIS_HEIGHT
	queue_redraw()

static func ceiling_for(value: Array) -> float:
	var slowest: float = 0.0
	for row: Variant in value:
		if row is Dictionary:
			slowest = maxf(slowest, float(row.get("p95_ms", 0.0)))
	for candidate: float in CEILINGS:
		if candidate >= slowest * 2.0:
			return candidate
	return CEILINGS[CEILINGS.size() - 1]

## Per pixel column, the fastest and slowest frame (milliseconds) on screen
## during it; x is -1 for a column no frame covers. A frame covers the columns
## from its start to its end, so a long hitch is a plateau as wide as the time
## it held the screen, not a lone point where it ended.
static func envelope(frame_us: Array, columns: int, window_seconds: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(maxi(columns, 0))
	out.fill(Vector2(-1.0, -1.0))
	if columns <= 0 or window_seconds <= 0.0:
		return out
	var elapsed: float = 0.0
	var per_column: float = window_seconds / float(columns)
	for value: Variant in frame_us:
		if not (value is int or value is float):
			continue
		var interval: float = float(value) / 1000000.0
		if not is_finite(interval) or interval <= 0.0:
			continue
		var first: int = clampi(int(elapsed / per_column), 0, columns - 1)
		elapsed += interval
		var last: int = clampi(int(elapsed / per_column), 0, columns - 1)
		var ms: float = interval * 1000.0
		for column: int in range(first, last + 1):
			var span: Vector2 = out[column]
			out[column] = Vector2(ms, ms) if span.x < 0.0 else Vector2(minf(span.x, ms), maxf(span.y, ms))
	return out

func _draw() -> void:
	var plot_x: float = LABEL_WIDTH
	var plot_w: float = maxf(1.0, size.x - LABEL_WIDTH - SCALE_WIDTH)
	var font: Font = MenuTheme.FONT
	var line_h: float = font.get_height(font_size)
	for index: int in runs.size():
		var row: Dictionary = runs[index] if runs[index] is Dictionary else {}
		var top: float = float(index) * (row_height + ROW_GAP)
		var plot: Rect2 = Rect2(plot_x, top, plot_w, row_height)
		var colour: Color = series_color(index)
		draw_rect(plot, MenuTheme.INSET)
		draw_rect(Rect2(0.0, top, 8.0, row_height), colour)
		draw_string(font, Vector2(20.0, top + (row_height + line_h) * 0.5 - 4.0), str(row.get("preset", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 28.0, font_size, MenuTheme.BONE)
		for guide: Vector2 in GUIDES:
			var gy: float = _y(plot, guide.x)
			_dashed(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), MenuTheme.MUTED)
			# 30 FPS labels above its line and 60 FPS below, so a tall scale
			# that brings the lines together never stacks the two labels.
			var baseline: float = gy - 4.0 if guide.y < 45.0 else gy + line_h - 4.0
			baseline = clampf(baseline, plot.position.y + line_h - 4.0, plot.end.y)
			draw_string(font, Vector2(plot.end.x + 10.0, baseline), "%d FPS" % int(guide.y), HORIZONTAL_ALIGNMENT_LEFT, SCALE_WIDTH - 12.0, font_size, MenuTheme.MUTED)
		var columns: int = int(plot.size.x / 2.0)
		var spans: PackedVector2Array = envelope(row.get("frame_us", []), columns, seconds)
		var slowest: PackedVector2Array = PackedVector2Array()
		var band: Color = MenuTheme.alpha(colour, 0.45)
		for column: int in spans.size():
			var span: Vector2 = spans[column]
			if span.x < 0.0:
				continue
			var x: float = plot.position.x + float(column) * 2.0 + 1.0
			var low: float = _y(plot, minf(span.x, ceiling_ms))
			var high: float = _y(plot, minf(span.y, ceiling_ms))
			draw_line(Vector2(x, low + 1.0), Vector2(x, high - 1.0), band, 2.0)
			slowest.append(Vector2(x, high))
			if span.y > ceiling_ms:
				draw_rect(Rect2(x - 3.0, plot.position.y, 6.0, 6.0), MenuTheme.DANGER)
		if slowest.size() >= 2:
			draw_polyline(slowest, colour, 2.0)
		draw_rect(plot, MenuTheme.EDGE, false, 2.0)
	var axis_y: float = float(runs.size()) * (row_height + ROW_GAP)
	var marks: int = 4
	for mark: int in range(marks + 1):
		var at: float = seconds * float(mark) / float(marks)
		var x: float = plot_x + plot_w * float(mark) / float(marks)
		var text: String = "%d S" % roundi(at)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(clampf(x - width * 0.5, plot_x, plot_x + plot_w - width), axis_y + line_h), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MenuTheme.MUTED)

func _y(plot: Rect2, ms: float) -> float:
	return plot.end.y - plot.size.y * clampf(ms / ceiling_ms, 0.0, 1.0)

func _dashed(from: Vector2, to: Vector2, colour: Color) -> void:
	var x: float = from.x
	while x < to.x:
		draw_line(Vector2(x, from.y), Vector2(minf(x + 10.0, to.x), from.y), colour, 2.0)
		x += 18.0
