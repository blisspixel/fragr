extends Node
class_name BenchmarkRun

## One scored scene: a fixed camera over a live local bot match.
## The warm-up is discarded. Frames are whole: a frame that starts during the
## warm-up is not scored, and scoring stops once the kept frames add up to the
## window. This is not the nine-scene showcase. A live match is a different
## fight every run, so the numbers to compare are the frame times.

signal finished(report: Dictionary)
signal dismissed

const PRIME_SECONDS: float = 8.0
const SCORE_SECONDS: float = 20.0
const LIVE_NOTE: String = "This run watches a live local match. Compare the frame times, not the fight."

var phase: String = "idle"
var camera: Node3D = null
var _since_start: float = 0.0
var _scored_elapsed: float = 0.0
var _scored: PackedFloat32Array = PackedFloat32Array()
var _last_usec: int = -1
var _banner: Label = null
var _score: CanvasLayer = null

static func workload() -> Dictionary:
	return {
		"mode": "tdm",
		"map_id": 1,
		"bots": 10,
		"bot_policy": "fixed",
		"fill_target": 0,
		"lan": false,
		"port": 0,
	}

static func boot_for(game_url: String) -> Dictionary:
	return {"mode": "spectate", "host": game_url, "benchmark": true}

## A benchmark boot is a spectator of the match this menu just started.
static func read_boot(meta: Variant) -> Dictionary:
	if typeof(meta) != TYPE_DICTIONARY:
		return {}
	var flag: Variant = meta.get("benchmark")
	if typeof(flag) != TYPE_BOOL or (flag as bool) != true:
		return {}
	var host: String = str(meta.get("host", "")).strip_edges()
	if host.is_empty():
		return {}
	return {"benchmark": true, "host": host}

static func present_uncapped() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

static func restore_presentation(settings: FragrSettings) -> void:
	if settings == null:
		return
	settings.apply_video()

static func saved_pace(vsync_on: bool, fps_cap: int) -> String:
	var cap_text: String = "uncapped" if fps_cap <= 0 else "%d fps" % fps_cap
	return "Saved settings: vertical sync %s, frame cap %s. This run turned both off." % [
		"on" if vsync_on else "off", cap_text]

static func preset_label(quality: int) -> String:
	match quality:
		0:
			return "Performance"
		1:
			return "Balanced"
		2:
			return "High"
		_:
			return "Preset %d" % quality

static func presentation(report: Dictionary, pace: String, preset: String, adapter: String) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Arena Duel, ten bots, fixed camera. Preset: %s." % preset)
	lines.append(pace)
	if int(report.get("count", 0)) <= 0:
		lines.append(FrameStats.EMPTY_VERDICT)
		lines.append(LIVE_NOTE)
		lines.append(adapter)
		return lines
	lines.append("%.1f s scored after %.1f s warm-up." % [float(report["elapsed_s"]), PRIME_SECONDS])
	lines.append("%d frames, %.1f ms average, %d fps." % [
		int(report["count"]), float(report["mean_ms"]), roundi(float(report["fps"]))])
	lines.append("Median %.1f ms. 99th %.1f ms. 99th / median %.2f." % [
		float(report["median_ms"]), float(report["p99_ms"]), float(report["smoothness"])])
	lines.append("1 percent low, worst frames by count: %d fps." % roundi(float(report["low_1_count_fps"])))
	lines.append("1 percent low, worst frames by time: %d fps." % roundi(float(report["low_1_time_fps"])))
	lines.append("1 percent low, 99th percentile: %d fps." % roundi(float(report["low_1_percentile_fps"])))
	lines.append("0.1 percent low, worst frames by count: %d fps." % roundi(float(report["low_01_count_fps"])))
	lines.append("0.1 percent low, worst frames by time: %d fps." % roundi(float(report["low_01_time_fps"])))
	lines.append("0.1 percent low, 99.9th percentile: %d fps." % roundi(float(report["low_01_percentile_fps"])))
	lines.append("Time at or above 33 ms: %.1f%%. At or above 50 ms: %.1f%%." % [
		float(report["over_33_share"]) * 100.0, float(report["over_50_share"]) * 100.0])
	lines.append("Stutters against the trailing second: %d. Largest jump: %.1f ms." % [
		int(report["stutter_count"]), float(report["stutter_max_ms"])])
	lines.append(FrameStats.verdict(report))
	lines.append(LIVE_NOTE)
	lines.append(adapter)
	return lines

func begin() -> void:
	phase = "priming"
	_since_start = 0.0
	_scored_elapsed = 0.0
	_scored = PackedFloat32Array()
	_last_usec = Time.get_ticks_usec()
	_ensure_banner()
	_refresh_banner()
	if camera != null:
		BenchmarkCamera.apply(camera, 0.0)
	set_process(true)

func advance(interval: float) -> void:
	if phase != "priming" and phase != "scoring":
		return
	if not is_finite(interval) or interval <= 0.0:
		return
	var started_at: float = _since_start
	_since_start += interval
	if camera != null:
		BenchmarkCamera.apply(camera, _since_start)
	if started_at < PRIME_SECONDS:
		if _since_start >= PRIME_SECONDS:
			phase = "scoring"
		_refresh_banner()
		return
	phase = "scoring"
	_scored.append(interval)
	_scored_elapsed += interval
	if _scored_elapsed >= SCORE_SECONDS:
		phase = "done"
		set_process(false)
		_refresh_banner()
		finished.emit(FrameStats.report(_scored))
		return
	_refresh_banner()

func show_score(report: Dictionary, settings: FragrSettings) -> void:
	if _banner != null:
		_banner.text = ""
	if _score != null:
		_score.queue_free()
	var pace: String = saved_pace(false, 0)
	var preset: String = "Balanced"
	if settings != null:
		pace = saved_pace(bool(settings.get_value("video", "vsync")), int(settings.get_value("video", "fps_cap")))
		preset = preset_label(int(settings.get_value("video", "quality")))
	var adapter: String = RenderingServer.get_video_adapter_name()
	if adapter.is_empty():
		adapter = "No graphics adapter reported."
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "BenchmarkScoreLayer"
	layer.layer = 120
	_score = layer
	add_child(layer)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.05, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 64)
	margin.add_theme_constant_override("margin_right", 64)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var label: Label = Label.new()
	label.name = "BenchmarkScore"
	label.text = "\n".join(presentation(report, pace, preset, adapter))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", MenuTheme.BONE)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 3)
	column.add_child(label)
	var back: Button = Button.new()
	back.name = "BenchmarkBack"
	back.text = "Back to menu"
	back.custom_minimum_size = Vector2(280.0, 48.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_override("font", MenuTheme.FONT)
	back.pressed.connect(func() -> void: dismissed.emit())
	column.add_child(back)

func _process(_delta: float) -> void:
	if phase != "priming" and phase != "scoring":
		return
	var now: int = Time.get_ticks_usec()
	if _last_usec < 0:
		_last_usec = now
		return
	var interval: float = float(now - _last_usec) / 1000000.0
	_last_usec = now
	advance(interval)

func _ensure_banner() -> void:
	if _banner != null:
		return
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "BenchmarkBannerLayer"
	layer.layer = 80
	add_child(layer)
	var label: Label = Label.new()
	label.name = "BenchmarkBanner"
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.offset_left = -420.0
	label.offset_right = 420.0
	label.offset_top = 12.0
	label.offset_bottom = 40.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", MenuTheme.FONT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", MenuTheme.BONE)
	label.add_theme_color_override("font_outline_color", MenuTheme.INK)
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	_banner = label

func _refresh_banner() -> void:
	if _banner == null:
		return
	if phase == "priming":
		var left: int = ceili(maxf(0.0, PRIME_SECONDS - _since_start))
		_banner.text = "Warming up. %d s left. Esc returns to the menu." % left
	elif phase == "scoring":
		var left: int = ceili(maxf(0.0, SCORE_SECONDS - _scored_elapsed))
		_banner.text = "Scoring. %d s left. Esc returns to the menu." % left
	else:
		_banner.text = ""
