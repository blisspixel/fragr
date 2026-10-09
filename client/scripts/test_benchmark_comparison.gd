extends SceneTree

var failures: Array[String] = []

class RestoreProbe extends Node:
	var restored: int = 0
	func _apply_render_preferences() -> void:
		restored += 1

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _near(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) < 0.001, label + " got " + str(actual))

func _run() -> void:
	var frames: PackedFloat32Array = []
	for _frame: int in range(100):
		frames.append(0.01)
	frames.append(0.05)
	var report: Dictionary = FrameStats.report(frames)
	_near(report.low_1_count_fps, 1000.0 / 30.0, "101 frames keep the slowest two for the 1% low")
	_near(report.fps, 101.0 / 1.05, "average FPS is frame count over total time")
	var boundary: Dictionary = FrameStats.report(PackedFloat32Array([0.032, 0.033, 0.050, 0.060]))
	_check(boundary.over_33_count == 3 and boundary.over_50_count == 2, "threshold counts include exactly33 and50 ms despite float storage")
	_near(boundary.median_ms, 41.5, "even median interpolates central samples")
	_near(boundary.p95_ms, 58.5, "p95 uses inclusive linear interpolation")
	_near(boundary.p99_ms, 59.7, "p99 uses inclusive linear interpolation")
	_near(boundary.max_ms, 60.0, "largest actual frame retained")
	_check(FrameStats.report(PackedFloat32Array([0, NAN, INF])).count == 0, "invalid intervals cannot create FPS")

	var capture: BenchmarkCapture = BenchmarkCapture.new()
	var source: Dictionary = {"tick": 100, "map_id": 1, "players": [{"x": 1.0}]}
	_check(capture.accept(source), "capture accepts first authoritative snapshot")
	source.players[0].x = 50.0
	_check(capture.frames[0].players[0].x == 1.0, "recorded world does not alias live dictionaries")
	_check(not capture.accept({"tick": 100}), "duplicate ticks do not duplicate effects")
	for tick: int in range(101, 661):
		capture.accept({"tick": tick, "map_id": 1, "players": [], "shot_results": [{"marker": tick}] if tick % 7 == 0 else []})
	_check(capture.complete() and capture.frames.size() == 561 and capture.digest.length() == 64, "28-second capture is bounded and has a retained digest")
	var original: String = JSON.stringify(capture.due(28.0))
	_check(capture.cursor == 561, "playback delivers every recorded snapshot in order")
	for _preset: int in range(3):
		capture.rewind()
		_check(JSON.stringify(capture.due(28.0)) == original, "each quality replays exactly the same resolved facts")
	capture.rewind()
	var early: Array[Dictionary] = capture.due(0.049)
	_check(early.size() == 1, "a future20Hz snapshot waits for its recorded timestamp")
	early[0].players[0].x = -20.0
	_check(capture.frames[0].players[0].x == 1.0, "presenter cannot mutate the retained capture")
	var gap: BenchmarkCapture = BenchmarkCapture.new()
	gap.accept({"tick": 1})
	gap.accept({"tick": 20})
	_check(not gap.error.is_empty() and not gap.complete(), "missing sustained capture cannot masquerade as a complete workload")
	var bounded: BenchmarkCapture = BenchmarkCapture.new()
	bounded.bytes = BenchmarkCapture.MAX_BYTES
	_check(not bounded.accept({"tick": 1}) and not bounded.error.is_empty(), "memory bound refuses excess before storing it")

	var path: String = "user://benchmark-comparison-test-%d.cfg" % OS.get_process_id()
	var prefs: FragrSettings = FragrSettings.new(path)
	prefs.set_value("video", "quality", 1)
	prefs.set_value("video", "fps_cap", 45)
	var run: BenchmarkRun = BenchmarkRun.new()
	var owner: RestoreProbe = RestoreProbe.new()
	root.add_child(owner)
	owner.add_child(run)
	run.manager = owner
	run.preferences = prefs
	run.render_settings = prefs.draft()
	run.render_settings.set_value("video", "quality", 2)
	BenchmarkRun.present_uncapped()
	_check(prefs.get_value("video", "quality") == 1, "comparison draft cannot overwrite chosen preset")
	run._restore()
	run._restore()
	_check(owner.restored == 1 and run.render_settings == null and Engine.max_fps == 45, "completion/cancellation restores quality and cap exactly once")
	_check(not FileAccess.file_exists(path), "comparison does not write preferences")
	_check(BenchmarkRun.read_boot(BenchmarkRun.boot_for("ws://127.0.0.1:12345", true)).benchmark_compare, "comparison choice reaches the shared benchmark boot")
	_check(not BenchmarkRun.read_boot({"benchmark": true, "host": "local", "benchmark_compare": "true"}).benchmark_compare, "only a boolean enables comparison")

	report["preset"] = "High"
	report["quality"] = 2
	report["replay_sha256"] = capture.digest
	report["output_size"] = [1280, 720]
	report["world_size"] = [1280, 720]
	var document: Dictionary = {"created_utc": "2026-10-06T12:00:00", "runs": [report], "renderer": "gl_compatibility", "adapter": 'Adapter, "Name"'}
	var csv: String = BenchmarkRun.csv(document)
	_check(csv.contains("low_1_fps,p50_ms,p95_ms,p99_ms,max_ms") and csv.contains('"Adapter, ""Name"""') and csv.contains(capture.digest), "CSV keeps required metrics, escaped metadata and replay identity")
	var result_dir: String = "user://benchmark-result-test-%d" % OS.get_process_id()
	set_meta("fragr_benchmark_dir", result_dir)
	_check(run._save_report(document).is_empty(), "local result writer succeeds in isolated directory")
	var basename: String = result_dir.path_join("benchmark-20261006T120000-%d" % OS.get_process_id())
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(basename + ".json"))
	_check(saved is Dictionary and saved.runs[0].replay_sha256 == capture.digest, "saved JSON retains the exact workload identity")
	_check(FileAccess.get_file_as_string(basename + ".csv") == csv, "saved CSV matches the reported comparison")
	for extension: String in ["json", "csv"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(basename + "." + extension))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(result_dir))
	var cancelled: BenchmarkRun = BenchmarkRun.new()
	owner.add_child(cancelled)
	cancelled.manager = owner
	cancelled.preferences = prefs
	cancelled.render_settings = prefs.draft()
	BenchmarkRun.present_uncapped()
	owner.remove_child(cancelled)
	cancelled.free()
	_check(owner.restored == 2 and Engine.max_fps == 45, "leaving the scene during comparison restores saved pacing")
	var console: FragrConsole = FragrConsole.new()
	console.preferences = prefs
	root.add_child(console)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	var manager: Node = load("res://scripts/game_manager.gd").new()
	manager.console = console
	manager.hud = hud
	hud.set_weapon_finish("oxide")
	console.set_open(true)
	manager._prepare_benchmark_presentation()
	_check(not console.is_open() and not console.is_processing_unhandled_input(), "benchmark closes and disables console input before capture")
	_check(hud._weapon_finish == "standard", "benchmark resets personal gun paint before capture")
	manager.free()
	console.queue_free()
	hud.show_warmup_bumper("Warmup", 2, [])
	_check(hud.warmup_tv_active, "retained-state fixture starts with a real warmup card")
	hud.set_round_info("Active", 30, 0)
	_check(not hud.warmup_tv_active and not hud.warmup_tv.visible, "an authoritative Active snapshot clears the card without a RoundStart event")
	hud.queue_free()
	var interrupted: BenchmarkRun = BenchmarkRun.new()
	owner.add_child(interrupted)
	interrupted.manager = owner
	interrupted.preferences = prefs
	interrupted.phase = "scoring"
	interrupted._on_preferences_changed()
	_check(interrupted.final_report.has("error") and interrupted.phase == "done", "external preferences changes invalidate a comparison instead of mislabeling capped samples")
	var resized: BenchmarkRun = BenchmarkRun.new()
	owner.add_child(resized)
	resized.manager = owner
	resized.preferences = prefs
	resized.phase = "preparing"
	resized._output_size = root.size + Vector2i(1, 0)
	resized._process(0.0)
	_check(resized.final_report.has("error") and resized.phase == "done", "resizing between presets invalidates the same-resolution comparison")
	owner.queue_free()
	await process_frame
	for problem: String in failures:
		push_error("test_benchmark_comparison: " + problem)
	print("test_benchmark_comparison: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
