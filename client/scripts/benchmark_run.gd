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
var manager: Node = null
var preferences: FragrSettings = null
var compare_all: bool = false
var render_settings: FragrSettings = null
var capture: BenchmarkCapture = BenchmarkCapture.new()
var results: Array[Dictionary] = []
var presets: Array[int] = []
var preset_index: int = 0
var final_report: Dictionary = {}
var output_directory: String = ""
var _output_size: Vector2i = Vector2i.ZERO
var _capture_started_usec: int = 0
var _restored: bool = false

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

static func boot_for(game_url: String, all_presets: bool = false) -> Dictionary:
	return {"mode": "spectate", "host": game_url, "benchmark": true, "benchmark_compare": all_presets}

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
	return {"benchmark": true, "host": host, "benchmark_compare": meta.get("benchmark_compare") == true}

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
	if manager != null:
		_start_capture()
		return
	_begin_measurement()

func _begin_measurement() -> void:
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
	if manager != null:
		for snapshot: Dictionary in capture.due(_since_start):
			manager._on_snapshot_received(snapshot)
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
		var summary: Dictionary = FrameStats.report(_scored)
		if manager == null:
			finished.emit(summary)
		else:
			_preset_finished(summary)
		return
	_refresh_banner()

func show_score(report: Dictionary, settings: FragrSettings) -> void:
	if report.has("runs") or report.has("error"):
		if _banner != null:
			_banner.text = ""
		if _score != null:
			_score.queue_free()
		var results_view: BenchmarkResults = BenchmarkResults.new()
		results_view.report = report
		results_view.directory = output_directory
		results_view.dismissed.connect(func() -> void: dismissed.emit())
		_score = results_view
		add_child(results_view)
		return
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
	if phase == "capturing":
		if Time.get_ticks_usec() - _capture_started_usec > 45000000:
			_fail("The local match did not finish loading. Please run the benchmark again.")
		else:
			if camera != null:
				BenchmarkCamera.apply(camera, capture.elapsed())
			_refresh_banner()
		return
	if phase != "priming" and phase != "scoring":
		return
	if manager != null and get_window().size != _output_size:
		_fail("The window size changed. Run again to compare the same resolution.")
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
	if phase == "capturing":
		_banner.text = "Preparing one match for every preset. %d s left. Esc returns to menu." % ceili(maxf(0.0, PRIME_SECONDS + SCORE_SECONDS - capture.elapsed()))
	elif phase == "priming":
		var left: int = ceili(maxf(0.0, PRIME_SECONDS - _since_start))
		_banner.text = "Warming up. %d s left. Esc returns to the menu." % left
	elif phase == "scoring":
		var left: int = ceili(maxf(0.0, SCORE_SECONDS - _scored_elapsed))
		_banner.text = "Scoring. %d s left. Esc returns to the menu." % left
	else:
		_banner.text = ""
	if manager != null and phase in ["priming", "scoring"]:
		_banner.text = "%s (%d/%d)  |  " % [preset_label(presets[preset_index]), preset_index + 1, presets.size()] + _banner.text

func _start_capture() -> void:
	_ensure_banner()
	if DisplayServer.get_name() == "headless":
		_fail("Open a game window to measure graphics performance.")
		return
	if preferences == null:
		_fail("The benchmark could not read your graphics settings.")
		return
	presets = [0, 1, 2] if compare_all else [int(preferences.get_value("video", "quality"))]
	capture.map_info = manager.current_map_info.duplicate(true)
	phase = "capturing"
	_capture_started_usec = Time.get_ticks_usec()
	manager.net_client.snapshot_received.connect(_capture_snapshot)
	_capture_snapshot(manager.latest_snapshot)
	_refresh_banner()
	set_process(true)

func _capture_snapshot(snapshot: Dictionary) -> void:
	if phase != "capturing":
		return
	capture.accept(snapshot)
	if not capture.error.is_empty():
		_fail(capture.error)
	elif capture.complete():
		phase = "preparing"
		_finish_capture.call_deferred()

func _finish_capture() -> void:
	if not is_inside_tree() or phase != "preparing":
		return
	if manager.net_client.snapshot_received.is_connected(_capture_snapshot):
		manager.net_client.snapshot_received.disconnect(_capture_snapshot)
	manager.net_client.disconnect_from_server()
	var host: LocalHost = get_tree().root.get_node_or_null("LocalHost") as LocalHost
	if host != null:
		host.stop()
	await get_tree().process_frame
	_begin_preset()

func _begin_preset() -> void:
	phase = "preparing"
	render_settings = preferences.draft()
	render_settings.set_value("video", "quality", presets[preset_index])
	manager._clear_world()
	manager._on_map_info(capture.map_info.duplicate(true))
	manager._apply_render_preferences()
	present_uncapped()
	capture.rewind()
	for snapshot: Dictionary in capture.due(0.0):
		manager._on_snapshot_received(snapshot)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	_output_size = get_window().size
	_begin_measurement()

func _preset_finished(summary: Dictionary) -> void:
	summary["preset"] = preset_label(presets[preset_index])
	summary["quality"] = presets[preset_index]
	summary["replay_sha256"] = capture.digest
	summary["replayed_snapshots"] = capture.cursor
	summary["output_size"] = [_output_size.x, _output_size.y]
	var world_size: Vector2i = Vector2i(Vector2(_output_size) * get_viewport().scaling_3d_scale)
	summary["world_size"] = [world_size.x, world_size.y]
	summary["settings"] = render_settings._values["video"].duplicate(true)
	results.append(summary)
	preset_index += 1
	if preset_index < presets.size():
		_begin_preset.call_deferred()
		return
	_restore()
	final_report = {"schema_version": 2, "created_utc": Time.get_datetime_string_from_system(true),
		"workload": "Arena Duel, ten bots, one recorded authoritative match", "map_id": 1, "bots": 10,
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"graphics_api": RenderingServer.get_video_adapter_api_version(), "engine": Engine.get_version_info()["string"],
		"os": OS.get_name(), "measurement": "whole rendered frame cadence, uncapped, vertical sync disabled",
		"warmup_seconds": PRIME_SECONDS, "score_seconds": SCORE_SECONDS,
		"low_1_definition": "1000 / mean(slowest ceil(frame_count * 0.01) frame times in milliseconds)",
		"percentile_definition": "inclusive linear rank (count - 1) * percentile / 100",
		"capture": {"sha256": capture.digest, "snapshots": capture.frames.size(), "bytes": capture.bytes,
			"first_tick": capture.first_tick, "last_tick": capture.last_tick}, "runs": results}
	var saved: String = _save_report(final_report)
	final_report["save_error"] = saved
	finished.emit(final_report)

func _restore() -> void:
	if _restored:
		return
	_restored = true
	render_settings = null
	if is_instance_valid(manager):
		manager._apply_render_preferences()
	restore_presentation(preferences)

func _exit_tree() -> void:
	_restore()

func _fail(message: String) -> void:
	phase = "done"
	set_process(false)
	_restore()
	final_report = {"schema_version": 2, "error": message, "runs": []}
	finished.emit(final_report)

static func csv(document: Dictionary) -> String:
	var lines: PackedStringArray = ["preset,average_fps,low_1_fps,p50_ms,p95_ms,p99_ms,max_ms,frames_33ms_plus,frames_50ms_plus,frames,seconds,output_width,output_height,world_width,world_height,renderer,adapter,replay_sha256"]
	for row: Dictionary in document.get("runs", []):
		var cells: Array = [row["preset"], row["fps"], row["low_1_count_fps"], row["median_ms"], row["p95_ms"], row["p99_ms"], row["max_ms"], row["over_33_count"], row["over_50_count"], row["count"], row["elapsed_s"], row["output_size"][0], row["output_size"][1], row["world_size"][0], row["world_size"][1], document["renderer"], document["adapter"], row["replay_sha256"]]
		var encoded: PackedStringArray = []
		for value: Variant in cells:
			encoded.append('"' + str(value).replace('"', '""') + '"')
		lines.append(",".join(encoded))
	return "\n".join(lines) + "\n"

func _save_report(document: Dictionary) -> String:
	output_directory = str(get_tree().get_meta("fragr_benchmark_dir", "user://benchmarks"))
	output_directory = ProjectSettings.globalize_path(output_directory)
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		return "Results could not be saved."
	var filename: String = "benchmark-" + str(document["created_utc"]).replace(":", "").replace("-", "") + "-%d" % OS.get_process_id()
	for extension: String in ["json", "csv"]:
		var file: FileAccess = FileAccess.open(output_directory.path_join(filename + "." + extension), FileAccess.WRITE)
		if file == null:
			return "Results could not be saved."
		file.store_string(JSON.stringify(document, "\t") + "\n" if extension == "json" else csv(document))
		file.flush()
		if file.get_error() != OK:
			file.close()
			return "Results could not be saved."
		file.close()
	return ""
