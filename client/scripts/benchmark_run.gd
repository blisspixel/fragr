extends Node
class_name BenchmarkRun

## One recorded local bot match and the same camera for every graphics preset.
## The warm-up is discarded. Frames are whole: a frame that starts during the
## warm-up is not scored, and scoring stops once the kept frames add up to the
## window. Recording a new run can produce a different fight.
##
## The run owns its HUD (BenchmarkHud): state, overall progress and a live
## frame rate. The match HUD is hidden by the match manager for the whole run.

signal finished(report: Dictionary)
signal dismissed
signal again_requested(compare_all: bool)

const PRIME_SECONDS: float = 8.0
const SCORE_SECONDS: float = 20.0
const CAPTURE_SECONDS: float = float(BenchmarkCapture.DURATION_TICKS) / 20.0
const SCHEMA_VERSION: int = 3
## Bump when the measured scene changes, so older results never compare as equal.
const WORKLOAD_ID: String = "arena-duel-tdm-10-bots-28s-orbit-match-hud-hidden"
## Bump when what a frame interval measures, or how a figure is computed, changes.
const METRIC_VERSION: int = 1
## A saved result larger than this is not read back for comparison.
const MAX_RESULT_BYTES: int = 32 * 1024 * 1024
const MAX_HISTORY_FILES: int = 64
## Tree metas the menu reads on return: run the same benchmark again, or say
## that the last one was cancelled.
const AGAIN_META: StringName = &"fragr_benchmark_again"
const CANCELLED_META: StringName = &"fragr_benchmark_cancelled"

var phase: String = "idle"
var camera: Node3D = null
var manager: Node = null
var preferences: FragrSettings = null
var compare_all: bool = false
var render_settings: FragrSettings = null
## Returns Array[Rect2]: other layers' text the benchmark HUD must clear.
var reserved_query: Callable
var capture: BenchmarkCapture = BenchmarkCapture.new()
var results: Array[Dictionary] = []
var presets: Array[int] = []
var preset_index: int = 0
var final_report: Dictionary = {}
var output_directory: String = ""
var saved_basename: String = ""
var hud: BenchmarkHud = null
var _since_start: float = 0.0
var _scored_elapsed: float = 0.0
var _scored: PackedFloat32Array = PackedFloat32Array()
var _scored_us: PackedInt64Array = PackedInt64Array()
var _last_usec: int = -1
var _results_view: BenchmarkResults = null
var _output_size: Vector2i = Vector2i.ZERO
var _run_started_usec: int = 0
var _capture_started_usec: int = 0
var _preparing_started_usec: int = 0
var _since_refresh: float = 0.0
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
	var compare: Variant = meta.get("benchmark_compare", false)
	return {"benchmark": true, "host": host, "benchmark_compare": typeof(compare) == TYPE_BOOL and bool(compare)}

static func present_uncapped() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

static func restore_presentation(settings: FragrSettings) -> void:
	if settings == null:
		return
	settings.apply_video()

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

## Content seconds a run plays, before loading and preset switches: the
## recording plus warm-up and scored time for each preset.
static func nominal_seconds(preset_count: int) -> float:
	return CAPTURE_SECONDS + float(preset_count) * (PRIME_SECONDS + SCORE_SECONDS)

func begin() -> void:
	_run_started_usec = Time.get_ticks_usec()
	_ensure_hud()
	if manager != null:
		_start_capture()
		return
	# Without a match manager there is nothing to record: the headless checks
	# drive the measurement clock directly through `advance`.
	if presets.is_empty():
		presets.append(1 if preferences == null else int(preferences.get_value("video", "quality")))
	_begin_measurement()

func _records() -> bool:
	return manager != null

## The step names the HUD lists: the recording, then each preset.
func steps() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray(["Record"]) if _records() else PackedStringArray()
	for quality: int in presets:
		names.append(preset_label(quality))
	return names

## Where the run is now, for the HUD and the checks. Times are nominal content
## seconds; loading between presets is not counted, so the remaining time is
## an estimate and is labelled "about". A preparing step does not advance.
func progress() -> Dictionary:
	var names: PackedStringArray = steps()
	var offset: int = 1 if _records() else 0
	var per_preset: float = PRIME_SECONDS + SCORE_SECONDS
	var total: float = (CAPTURE_SECONDS if _records() else 0.0) + per_preset * float(presets.size())
	var label: String = preset_label(presets[mini(preset_index, presets.size() - 1)]).to_upper() if not presets.is_empty() else ""
	var step: int = names.size()
	var into: float = 0.0
	var headline: String = "FINISHING"
	var detail: String = "Saving the results."
	match phase:
		"idle":
			step = 0
			headline = "STARTING"
			detail = "Not scored."
		"capturing":
			step = 0
			into = clampf(capture.elapsed(), 0.0, CAPTURE_SECONDS)
			headline = "RECORDING THE FIGHT"
			detail = "Not scored. Ten bots fight once. Every preset replays this same fight. %d s left." % ceili(CAPTURE_SECONDS - into - 0.001)
		"preparing":
			step = offset + preset_index
			headline = "LOADING " + label
			detail = "Not scored. Rebuilding the scene at this preset."
		"priming":
			step = offset + preset_index
			into = clampf(_since_start, 0.0, PRIME_SECONDS)
			headline = "WARMING UP " + label
			detail = "Not scored. Shaders and caches settle first. %d s left." % ceili(PRIME_SECONDS - into - 0.001)
		"scoring":
			step = offset + preset_index
			into = PRIME_SECONDS + clampf(_scored_elapsed, 0.0, SCORE_SECONDS)
			headline = "MEASURING " + label
			detail = "Scored. %d s left for this preset." % ceili(SCORE_SECONDS - (into - PRIME_SECONDS) - 0.001)
	step = mini(step, names.size())
	var before: float = (CAPTURE_SECONDS if _records() and step > 0 else 0.0) + per_preset * float(maxi(0, step - offset))
	var done: float = minf(total, before + into)
	var marks: PackedFloat32Array = PackedFloat32Array()
	var edge: float = 0.0
	for index: int in range(names.size() - 1):
		edge += CAPTURE_SECONDS if _records() and index == 0 else per_preset
		marks.append(edge / total if total > 0.0 else 0.0)
	return {
		"state": phase,
		"steps": names,
		"step": step,
		"headline": headline,
		"detail": detail,
		"overall": done / total if total > 0.0 else 0.0,
		"marks": marks,
		"remaining_s": maxf(0.0, total - done),
		"elapsed_s": float(Time.get_ticks_usec() - _run_started_usec) / 1000000.0 if _run_started_usec > 0 else 0.0,
		"scored_frames": _scored.size() if phase == "scoring" else 0,
		"scored_s": _scored_elapsed if phase == "scoring" else 0.0,
	}

func _begin_measurement() -> void:
	phase = "priming"
	_since_start = 0.0
	_scored_elapsed = 0.0
	_scored = PackedFloat32Array()
	_scored_us = PackedInt64Array()
	_last_usec = Time.get_ticks_usec()
	_ensure_hud()
	hud.reset_live()
	_refresh_hud()
	if camera != null:
		BenchmarkCamera.apply(camera, 0.0)
	set_process(true)

## Advance the measurement clock by one whole drawn frame, in seconds.
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
			_refresh_hud()
		return
	phase = "scoring"
	_scored.append(interval)
	_scored_us.append(roundi(interval * 1000000.0))
	_scored_elapsed += interval
	if _scored_elapsed >= SCORE_SECONDS:
		_preset_finished(FrameStats.report(_scored))

## The finished report, the saved files' folder and the actions a player has
## next. The live HUD leaves; the results own the screen.
func show_results(report: Dictionary) -> void:
	if hud != null:
		hud.visible = false
	if _results_view != null:
		_results_view.queue_free()
	_results_view = BenchmarkResults.new()
	_results_view.report = report
	_results_view.directory = output_directory
	_results_view.saved_basename = saved_basename
	_results_view.dismissed.connect(func() -> void: dismissed.emit())
	_results_view.again_requested.connect(func() -> void: again_requested.emit(compare_all))
	add_child(_results_view)

func _process(delta: float) -> void:
	if manager != null and _output_size != Vector2i.ZERO and phase in ["capturing", "preparing", "priming", "scoring"] and get_window().size != _output_size:
		_fail("The window size changed. Run again to compare the same resolution.")
		return
	_since_refresh += maxf(delta, 0.0)
	if _since_refresh >= BenchmarkHud.REFRESH_SECONDS:
		_since_refresh = 0.0
		_refresh_hud()
	if phase == "preparing":
		if Time.get_ticks_usec() - _preparing_started_usec > 5000000:
			_fail("The preset did not load in time. Keep the game window visible, then run the benchmark again.")
		return
	if phase == "capturing":
		if Time.get_ticks_usec() - _capture_started_usec > 45000000:
			_fail("The local match did not finish loading. Please run the benchmark again.")
		elif camera != null:
			BenchmarkCamera.apply(camera, capture.elapsed())
		return
	if phase != "priming" and phase != "scoring":
		return
	if manager != null:
		if Time.get_ticks_usec() - _last_usec > 2000000:
			_fail("Frames stopped for two seconds. Keep the game window visible, then run the benchmark again.")
		return
	_measure_drawn_frame()

func _measure_drawn_frame() -> void:
	if phase not in ["capturing", "priming", "scoring"]:
		return
	var now: int = Time.get_ticks_usec()
	if _last_usec < 0:
		_last_usec = now
		return
	var interval: float = float(now - _last_usec) / 1000000.0
	_last_usec = now
	if hud != null:
		hud.push_interval(interval)
	advance(interval)

func _ensure_hud() -> void:
	if hud != null:
		return
	hud = BenchmarkHud.new()
	hud.style = HudStyle.from_settings(preferences) if preferences != null else HudStyle.new()
	hud.reserved_query = reserved_query
	add_child(hud)

func _refresh_hud() -> void:
	if hud != null and hud.visible:
		hud.show_progress(progress())

func _start_capture() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Open a game window to measure graphics performance.")
		return
	if preferences == null:
		_fail("The benchmark could not read your graphics settings.")
		return
	presets.clear()
	if compare_all:
		presets.assign([0, 1, 2])
	else:
		presets.append(int(preferences.get_value("video", "quality")))
	capture.map_info = manager.current_map_info.duplicate(true)
	_output_size = get_window().size
	phase = "capturing"
	_capture_started_usec = Time.get_ticks_usec()
	_last_usec = -1
	preferences.changed.connect(_on_preferences_changed)
	RenderingServer.frame_post_draw.connect(_measure_drawn_frame)
	manager.net_client.snapshot_received.connect(_capture_snapshot)
	_capture_snapshot(manager.latest_snapshot)
	_refresh_hud()
	set_process(true)

func _capture_snapshot(snapshot: Dictionary) -> void:
	if phase != "capturing":
		return
	capture.accept(snapshot)
	if not capture.error.is_empty():
		_fail(capture.error)
	elif capture.complete():
		phase = "preparing"
		_preparing_started_usec = Time.get_ticks_usec()
		_refresh_hud()
		_finish_capture.call_deferred()

func _on_preferences_changed() -> void:
	if phase in ["capturing", "preparing", "priming", "scoring"]:
		_fail("Settings changed during the benchmark. Run again for a consistent comparison.")

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
	if not is_inside_tree() or phase != "preparing":
		return
	_preparing_started_usec = Time.get_ticks_usec()
	set_process(true)
	_refresh_hud()
	render_settings = preferences.draft()
	render_settings.set_value("video", "quality", presets[preset_index])
	manager._clear_world()
	manager.hud.reset_host_chrome()
	manager.ended_podium_shown = false
	manager._on_map_info(capture.map_info.duplicate(true))
	manager._apply_render_preferences()
	present_uncapped()
	capture.rewind()
	for snapshot: Dictionary in capture.due(0.0):
		manager._on_snapshot_received(snapshot)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or phase != "preparing":
		return
	if get_window().size != _output_size:
		_fail("The window size changed. Run again to compare the same resolution.")
		return
	_begin_measurement()

func _preset_finished(summary: Dictionary) -> void:
	var quality: int = presets[preset_index]
	summary["preset"] = preset_label(quality)
	summary["quality"] = quality
	summary["replay_sha256"] = capture.digest
	summary["replayed_snapshots"] = capture.cursor
	var output: Vector2i = _output_size if _output_size != Vector2i.ZERO else get_window().size
	summary["output_size"] = [output.x, output.y]
	var world_size: Vector2i = Vector2i(Vector2(output) * get_viewport().scaling_3d_scale)
	summary["world_size"] = [world_size.x, world_size.y]
	var measured: FragrSettings = render_settings if render_settings != null else preferences
	summary["settings"] = measured._values["video"].duplicate(true) if measured != null else {}
	summary["settings"]["vsync"] = false
	summary["settings"]["fps_cap"] = 0
	# Every scored interval in whole microseconds, as measured. FrameStats on
	# these values reproduces every figure above and the result timeline.
	summary["frame_us"] = Array(_scored_us)
	results.append(summary)
	preset_index += 1
	if preset_index < presets.size():
		phase = "preparing"
		_preparing_started_usec = Time.get_ticks_usec()
		if manager == null:
			_begin_measurement()
		else:
			_refresh_hud()
			_begin_preset.call_deferred()
		return
	phase = "done"
	set_process(false)
	_restore()
	final_report = {"schema_version": SCHEMA_VERSION, "state": "complete", "created_utc": Time.get_datetime_string_from_system(true),
		"workload": {"id": WORKLOAD_ID, "description": "Arena Duel, ten bots, one recorded authoritative match replayed for each preset",
			"map_id": 1, "bots": 10, "capture_seconds": CAPTURE_SECONDS, "camera": "orbit radius %d m, height %d m, one turn per %d s" % [
				int(BenchmarkCamera.RADIUS), int(BenchmarkCamera.HEIGHT), int(BenchmarkCamera.ORBIT_SECONDS)], "match_hud": "hidden"},
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"graphics_api": RenderingServer.get_video_adapter_api_version(), "engine": Engine.get_version_info()["string"],
		"build": "debug" if OS.is_debug_build() else "release", "os": OS.get_name(),
		"measurement": "RenderingServer.frame_post_draw cadence, uncapped, vertical sync disabled", "metric_version": METRIC_VERSION,
		"warmup_seconds": PRIME_SECONDS, "score_seconds": SCORE_SECONDS,
		"low_1_definition": "1000 / mean(slowest ceil(frame_count * 0.01) frame times in milliseconds)",
		"percentile_definition": "inclusive linear rank (count - 1) * percentile / 100",
		"capture": {"sha256": capture.digest, "snapshots": capture.frames.size(), "bytes": capture.bytes,
			"first_tick": capture.first_tick, "last_tick": capture.last_tick}, "runs": results}
	final_report["compatibility"] = compatibility(final_report)
	final_report["save_error"] = _save_report(final_report)
	finished.emit(final_report)

## What two results must share before their numbers are compared across runs:
## the workload and metric versions, engine and build, the system and graphics
## path, the output size, and each preset's world size and settings. A match
## does not make two recordings the same fight; it rules out comparing unlike runs.
static func compatibility(document: Dictionary) -> Dictionary:
	var rows: Array = []
	var output: Variant = []
	for row: Variant in document.get("runs", []):
		if row is Dictionary:
			rows.append({"quality": row.get("quality"), "world_size": row.get("world_size"), "settings": row.get("settings")})
			output = row.get("output_size")
	var workload_id: Variant = document.get("workload", {}).get("id") if document.get("workload") is Dictionary else null
	return {"schema_version": document.get("schema_version"), "workload": workload_id, "metric_version": document.get("metric_version"),
		"engine": document.get("engine"), "build": document.get("build"), "os": document.get("os"),
		"renderer": document.get("renderer"), "driver": document.get("driver"), "adapter": document.get("adapter"),
		"graphics_api": document.get("graphics_api"), "output_size": output, "runs": rows}

## One canonical text for a compatibility key, whether it came from memory or
## from a saved file: JSON numbers read back as floats, so both sides pass
## through the same parse before comparison.
static func compatibility_text(key: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(key)), "", true)

## The most recent earlier saved result in `directory` whose compatibility key
## matches `document`, or an empty dictionary. Bounded: it reads at most
## MAX_HISTORY_FILES files, skips any over MAX_RESULT_BYTES or not a complete
## result of this schema, and never the file named `skip_basename`.
static func previous_compatible(directory: String, document: Dictionary, skip_basename: String) -> Dictionary:
	if directory.is_empty() or not document.has("compatibility"):
		return {}
	var names: PackedStringArray = PackedStringArray()
	for file: String in DirAccess.get_files_at(directory):
		if file.begins_with("benchmark-") and file.ends_with(".json") and file.get_basename() != skip_basename:
			names.append(file)
	names.sort()
	names.reverse()
	var wanted: String = compatibility_text(document["compatibility"])
	var created: String = str(document.get("created_utc", ""))
	for index: int in range(mini(names.size(), MAX_HISTORY_FILES)):
		var path: String = directory.path_join(names[index])
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > MAX_RESULT_BYTES:
			continue
		var json: JSON = JSON.new()
		var parsed: Error = json.parse(file.get_as_text())
		file.close()
		if parsed != OK or not json.data is Dictionary:
			continue
		var earlier: Dictionary = json.data
		var schema: Variant = earlier.get("schema_version")
		if not (schema is float or schema is int) or int(schema) != SCHEMA_VERSION or earlier.get("state") != "complete" or not earlier.get("runs") is Array:
			continue
		if not created.is_empty() and str(earlier.get("created_utc", "")) >= created:
			continue
		if compatibility_text(earlier.get("compatibility")) == wanted:
			return earlier
	return {}

func _restore() -> void:
	if _restored:
		return
	_restored = true
	render_settings = null
	if is_instance_valid(manager) and manager.is_inside_tree():
		manager._apply_render_preferences()
	restore_presentation(preferences)

func _exit_tree() -> void:
	phase = "done"
	set_process(false)
	if RenderingServer.frame_post_draw.is_connected(_measure_drawn_frame):
		RenderingServer.frame_post_draw.disconnect(_measure_drawn_frame)
	_restore()

func _fail(message: String) -> void:
	var interrupted: String = phase
	phase = "done"
	set_process(false)
	_restore()
	if is_instance_valid(manager) and manager.get("net_client") != null:
		if manager.net_client.snapshot_received.is_connected(_capture_snapshot):
			manager.net_client.snapshot_received.disconnect(_capture_snapshot)
		manager.net_client.disconnect_from_server()
	var host: LocalHost = get_tree().root.get_node_or_null("LocalHost") as LocalHost
	if host != null:
		host.stop()
	# A stopped run has no result: the presets it finished are named, not scored.
	var finished_presets: Array = []
	for row: Dictionary in results:
		finished_presets.append(row.get("preset"))
	final_report = {"schema_version": SCHEMA_VERSION, "state": "failed", "error": message, "interrupted": interrupted,
		"finished_presets": finished_presets, "runs": []}
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
	saved_basename = filename
	return ""
