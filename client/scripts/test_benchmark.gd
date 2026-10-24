extends SceneTree

# Headless checks for the frame-time report, the fixed camera, the run's
# progress and HUD, the results screen and the Benchmark page.
# Run: godot --path client --headless --script res://scripts/test_benchmark.gd

var _failures: int = 0
var _result_dir: String = ""

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_benchmark: " + message)

func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.02, "%s (got %s, expected %s)" % [message, actual, expected])

## Every Label and Button uses a UI face at a sanctioned size.
func _inspect_type(node: Node, where: String) -> void:
	if node is Label or node is Button:
		var control: Control = node as Control
		var font: Font = control.get_theme_font("font")
		var size: int = control.get_theme_font_size("font_size")
		_check(font == MenuTheme.FONT or font == MenuTheme.DISPLAY_FONT, "%s %s owns its UI face" % [where, node.name])
		_check(size in (MenuTheme.DISPLAY_SIZES if font == MenuTheme.DISPLAY_FONT else MenuTheme.PIXEL_SIZES), "%s %s uses the intended scale (%d)" % [where, node.name, size])
	for child: Node in node.get_children():
		_inspect_type(child, where)

func _run() -> void:
	_result_dir = ProjectSettings.globalize_path("user://test-benchmark-results-%d" % OS.get_process_id())
	set_meta("fragr_benchmark_dir", _result_dir)
	_frame_stats()
	_camera()
	await _measurement()
	await _hud_layout()
	await _results_view()
	_history()
	await _menu()
	_remove_dir(_result_dir)
	if _failures == 0:
		print("test_benchmark: PASS")
		quit(0)
	else:
		push_error("test_benchmark: FAIL (%d)" % _failures)
		quit(1)

func _frame_stats() -> void:
	var intervals: PackedFloat32Array = PackedFloat32Array()
	for _index: int in range(99):
		intervals.append(0.010)
	intervals.append(0.050)
	var summary: Dictionary = FrameStats.report(intervals)
	_check(int(summary["count"]) == 100 and int(summary["dropped"]) == 0, "every positive frame counts")
	_near(float(summary["elapsed_s"]), 1.04, "elapsed time is the sum of the frames")
	_near(float(summary["fps"]), 100.0 / 1.04, "fps is the frame count over elapsed time")
	_check(absf(float(summary["fps"]) - 100.0 / 1.04) < absf(float(summary["fps"]) - 98.4), "average FPS is not the mean of per-frame rates")
	_near(float(summary["mean_ms"]), 10.4, "mean frame time is the average interval")
	_near(float(summary["median_ms"]), 10.0, "median stays with the common frame")
	_near(float(summary["p99_ms"]), 10.4, "the 99th percentile barely reaches the hitch")
	_near(float(summary["min_ms"]), 10.0, "the fastest frame is kept")
	_near(float(summary["max_ms"]), 50.0, "the slowest frame is kept")
	_near(float(summary["low_1_count_fps"]), 20.0, "1 percent low by count averages the slowest frames")
	_check(absf(float(summary["low_1_count_fps"]) - 1000.0 / float(summary["p99_ms"])) > 50.0, "the 1% low is not the inverted 99th percentile")
	_near(float(summary["over_33_share"]), 0.050 / 1.04, "a frame at or above 33 ms counts its whole duration")
	_check(int(summary["over_33_count"]) == 1, "the one hitch is a slow frame")
	_check(int(summary["stutter_count"]) == 1, "one hitch against the trailing second counts once")
	# The saved report keeps every FrameStats field, so each stays pinned.
	_near(float(summary["smoothness"]), 1.04, "smoothness is the 99th percentile over the median")
	_near(float(summary["low_1_time_fps"]), 20.0, "1 percent low by time uses the slowest duration")
	_near(float(summary["low_1_percentile_fps"]), 1.0 / 0.0104, "1 percent low by percentile inverts the 99th")
	_near(float(summary["over_50_share"]), 0.050 / 1.04, "a frame at 50 ms counts as a stall")
	_near(float(summary["stutter_max_ms"]), 40.0, "the largest jump is the step into the hitch")
	_near(float(summary["mad_ms"]), 0.0, "one hitch does not move the median absolute deviation")
	var dirty: PackedFloat32Array = PackedFloat32Array([0.0, -0.2, NAN, INF])
	var empty: Dictionary = FrameStats.report(dirty)
	_check(int(empty["count"]) == 0 and int(empty["dropped"]) == 4 and float(empty["fps"]) == 0.0, "a clock that did not advance yields no FPS and no NaN")
	var one: Dictionary = FrameStats.report(PackedFloat32Array([0.02]))
	_check(int(one["count"]) == 1 and is_finite(float(one["p99_ms"])) and is_finite(float(one["low_1_count_fps"])), "one frame has finite figures")

func _camera() -> void:
	var origin: Dictionary = BenchmarkCamera.pose(0.0)
	var quarter: Dictionary = BenchmarkCamera.pose(5.0)
	_check((origin["position"] as Vector3).is_equal_approx(Vector3(BenchmarkCamera.RADIUS, BenchmarkCamera.HEIGHT, 0.0)), "the orbit starts on the positive X side")
	_check((quarter["position"] as Vector3).is_equal_approx(Vector3(0.0, BenchmarkCamera.HEIGHT, BenchmarkCamera.RADIUS)), "five seconds is a quarter turn")
	_check((BenchmarkCamera.pose(5.0)["position"] as Vector3).is_equal_approx(quarter["position"]), "the same timestamp is the same pose")
	_check((quarter["look"] as Vector3).is_equal_approx(BenchmarkCamera.LOOK), "the camera looks at the arena")
	var body: Node3D = Node3D.new()
	root.add_child(body)
	BenchmarkCamera.apply(body, 5.0)
	_check(body.global_position.is_equal_approx(quarter["position"]), "applying the pose moves the camera")
	body.free()

func _measurement() -> void:
	var run: BenchmarkRun = BenchmarkRun.new()
	run.presets.assign([0, 2])
	root.add_child(run)
	var reports: Array = []
	run.finished.connect(func(report: Dictionary) -> void: reports.append(report))
	run.begin()
	run.set_process(false)
	_check(run.hud != null and run.hud.is_inside_tree(), "the run owns its HUD")
	var view: Dictionary = run.progress()
	_check(view["state"] == "priming" and str(view["headline"]).begins_with("WARMING UP PERFORMANCE"), "the warm-up names the preset: " + str(view["headline"]))
	_check(str(view["detail"]).begins_with("Not scored."), "the warm-up says it is not scored")
	_check(view["steps"] == PackedStringArray(["Performance", "High"]) and int(view["step"]) == 0, "steps list each preset")
	_near(float(view["remaining_s"]), 2.0 * (BenchmarkRun.PRIME_SECONDS + BenchmarkRun.SCORE_SECONDS), "remaining time covers both presets")
	var headline: Label = run.hud.find_child("Headline", true, false) as Label
	_check(headline != null and headline.text == view["headline"], "the HUD shows the state")
	var last: float = -1.0
	var monotonic: bool = true
	for _prime: int in range(16):
		run.advance(0.5)
		var overall: float = float(run.progress()["overall"])
		monotonic = monotonic and overall >= last
		last = overall
	_check(run.phase == "scoring" and reports.is_empty(), "the warm-up is discarded")
	view = run.progress()
	_check(str(view["headline"]) == "MEASURING PERFORMANCE" and str(view["detail"]).begins_with("Scored."), "scoring is labelled scored")
	for _score_frame: int in range(39):
		run.advance(0.5)
		monotonic = monotonic and float(run.progress()["overall"]) >= last
		last = float(run.progress()["overall"])
	_check(int(run.progress()["scored_frames"]) == 39, "the running summary counts scored frames")
	run.advance(0.5)
	_check(monotonic, "overall progress never goes backwards")
	_check(run.results.size() == 1 and run.phase == "priming" and run.preset_index == 1, "the second preset starts after the first")
	_check(int(run.progress()["step"]) == 1 and str(run.progress()["headline"]).ends_with("HIGH"), "the step moves to the next preset")
	for _frame: int in range(16 + 30):
		run.advance(0.5)
	# One real hitch inside the scored window stays in the result.
	run.advance(2.0)
	for _frame: int in range(6):
		run.advance(0.5)
	_check(reports.size() == 1, "the run finishes once")
	var report: Dictionary = reports[0] if not reports.is_empty() else {}
	_check(report.get("state") == "complete" and int(report.get("schema_version", 0)) == BenchmarkRun.SCHEMA_VERSION, "a finished run is complete")
	var rows: Array = report.get("runs", [])
	_check(rows.size() == 2, "both presets are reported")
	if rows.size() == 2:
		_check(int(rows[0]["count"]) == 40 and int(rows[1]["count"]) == 37, "only frames that start after the warm-up are scored")
		_near(float(rows[1]["max_ms"]), 2000.0, "a hitch inside the scored window is kept")
		_near(float(rows[0]["elapsed_s"]), 20.0, "the scored frames add up to the window")
		_check((rows[0]["frame_us"] as Array).size() == int(rows[0]["count"]), "every scored interval is kept")
		# Exported data reproduces the displayed figures.
		var parsed: Variant = JSON.parse_string(JSON.stringify(report))
		var reread: PackedFloat32Array = PackedFloat32Array()
		for value: Variant in parsed["runs"][1]["frame_us"]:
			reread.append(float(value) / 1000000.0)
		var again: Dictionary = FrameStats.report(reread)
		for key: String in ["fps", "low_1_count_fps", "p99_ms", "over_33_count", "count", "max_ms"]:
			_check(is_equal_approx(float(again[key]), float(rows[1][key])), "saved intervals reproduce %s" % key)
		_check(rows[1]["preset"] == "High" and int(rows[1]["quality"]) == 2, "rows name their preset")
	_check(report.get("compatibility") is Dictionary and report["compatibility"]["workload"] == BenchmarkRun.WORKLOAD_ID, "the report carries its compatibility key")
	_check(str(report.get("save_error", "x")).is_empty() and FileAccess.file_exists(_result_dir.path_join(run.saved_basename + ".json")), "the result saves where the tree says")
	run.advance(0.5)
	_check(reports.size() == 1, "a finished run does not keep scoring")
	run.show_results(report)
	_check(not run.hud.visible and run.find_child("BenchmarkScoreLayer", true, false) != null, "results replace the live HUD")
	run.queue_free()
	await process_frame
	# A stopped run has no figures.
	var stopped: BenchmarkRun = BenchmarkRun.new()
	root.add_child(stopped)
	stopped.presets.assign([1])
	stopped.begin()
	stopped.set_process(false)
	var failed: Array = []
	stopped.finished.connect(func(report: Dictionary) -> void: failed.append(report))
	for _frame: int in range(20):
		stopped.advance(0.5)
	stopped._fail("Settings changed during the benchmark. Run again for a consistent comparison.")
	_check(failed.size() == 1 and failed[0]["state"] == "failed" and (failed[0]["runs"] as Array).is_empty() and failed[0]["interrupted"] == "scoring", "an interrupted run reports where it stopped and no result")
	stopped.queue_free()
	await process_frame

func _hud_layout() -> void:
	var port: SubViewport = SubViewport.new()
	port.size_2d_override_stretch = true
	root.add_child(port)
	# Lambdas capture locals by value; the array is shared.
	var reserved: Array = [Rect2()]
	var hud: BenchmarkHud = BenchmarkHud.new()
	hud.reserved_query = func() -> Array: return [reserved[0], Rect2(0, 0, INF, 4), "not a rect"]
	port.add_child(hud)
	await process_frame
	for frame: int in range(120):
		hud.push_interval(1.0 / 120.0)
	var live: Dictionary = hud.live()
	_near(float(live.get("fps", 0.0)), 120.0, "live FPS is frames over seconds in the window")
	_check(float(live.get("seconds", 9.0)) <= 1.01, "the live window is about the last second")
	hud.push_interval(NAN)
	hud.push_interval(-1.0)
	_check(is_equal_approx(float(hud.live()["fps"]), float(live["fps"])), "invalid intervals do not reach the live readout")
	hud.reset_live()
	_check(hud.live().is_empty() and (hud.find_child("LiveFps", true, false) as Label).text == "-- FPS", "a reset readout shows no number rather than zero")
	var progress: Dictionary = {"state": "scoring", "headline": "WARMING UP PERFORMANCE", "detail": "Not scored. Shaders and caches settle first. 8 s left.",
		"overall": 0.4, "marks": PackedFloat32Array([0.25, 0.5, 0.75]), "steps": PackedStringArray(["Record", "Performance", "Balanced", "High"]),
		"step": 1, "elapsed_s": 64.0, "remaining_s": 48.0, "scored_frames": 2810, "scored_s": 19.9}
	hud.show_progress(progress)
	_check((hud.find_child("Totals", true, false) as Label).text == "1:04 ELAPSED // ABOUT 0:48 LEFT", "totals read elapsed and an estimate")
	_check((hud.find_child("Scored", true, false) as Label).text == "141 FPS AVERAGE\n2810 FRAMES SCORED", "the running summary is frames over scored time")
	_inspect_type(hud, "hud")
	var cases: Array = [
		[Vector2i(1920, 1080), HudStyle.new(1.0, FragrSettings.TEXT_STANDARD)],
		[Vector2i(1920, 1080), HudStyle.new(1.5, FragrSettings.TEXT_LARGE)],
		[Vector2i(1920, 1080), HudStyle.new(0.75, FragrSettings.TEXT_STANDARD)],
		[Vector2i(2520, 1080), HudStyle.new(1.0, FragrSettings.TEXT_STANDARD)],
		[Vector2i(1920, 2473), HudStyle.new(1.5, FragrSettings.TEXT_LARGE)],
	]
	for case: Array in cases:
		for counter: Rect2 in [Rect2(), Rect2(1400, 2, 512, 31), Rect2(0, 0, 3000, 40)]:
			var logical: Vector2i = case[0]
			port.size = logical
			port.size_2d_override = logical
			reserved[0] = counter
			hud.apply_style(case[1])
			hud.show_progress(progress)
			await process_frame
			hud.show_progress(progress)
			var drawn: Dictionary = hud.occupied()
			var view: Rect2 = Rect2(Vector2.ZERO, Vector2(logical))
			var tag: String = "%s scale %.2f text %d counter %s" % [logical, case[1].scale, case[1].text_size, counter]
			for key: String in drawn:
				_check(view.encloses(drawn[key]), "%s stays in view: %s" % [key, tag])
				_check(not counter.has_area() or not counter.intersects(drawn[key]) or key == "hint", "%s clears the frame counter: %s" % [key, tag])
			_check(not drawn["status"].intersects(drawn["live"]), "status and live plates do not overlap: " + tag)
			_check(not drawn["hint"].intersects(drawn["status"]) and not drawn["hint"].intersects(drawn["live"]), "the cancel hint clears the plates: " + tag)
	port.queue_free()
	await process_frame

func _sample_report() -> Dictionary:
	var runs: Array = []
	for quality: int in [0, 1, 2]:
		var frames: PackedFloat32Array = PackedFloat32Array()
		var us: Array = []
		for index: int in range(2000):
			var interval: float = 0.004 + 0.002 * float(quality) + (0.045 if index == 900 else 0.0)
			frames.append(interval)
			us.append(roundi(interval * 1000000.0))
		var row: Dictionary = FrameStats.report(frames)
		row.merge({"preset": BenchmarkRun.preset_label(quality), "quality": quality, "frame_us": us, "output_size": [1920, 1080],
			"world_size": [1920, 1080], "settings": {"quality": quality, "render_scale": 1.0}, "replay_sha256": "ab"})
		runs.append(row)
	var report: Dictionary = {"schema_version": BenchmarkRun.SCHEMA_VERSION, "state": "complete", "created_utc": "2026-10-23T22:00:00",
		"workload": {"id": BenchmarkRun.WORKLOAD_ID}, "renderer": "forward_plus", "driver": "vulkan", "adapter": "Test Adapter",
		"graphics_api": "1.4", "engine": "4.7.2-stable", "build": "release", "os": "Linux", "metric_version": BenchmarkRun.METRIC_VERSION,
		"warmup_seconds": 8.0, "score_seconds": 20.0, "capture": {"snapshots": 561, "sha256": "ab"}, "runs": runs, "save_error": ""}
	report["compatibility"] = BenchmarkRun.compatibility(report)
	return report

func _results_view() -> void:
	var report: Dictionary = _sample_report()
	var view: BenchmarkResults = BenchmarkResults.new()
	view.report = report
	view.directory = _result_dir
	view.saved_basename = "benchmark-none"
	root.add_child(view)
	await process_frame
	var outcome: Label = view.find_child("Outcome", true, false) as Label
	_check(outcome != null and outcome.text == "BENCHMARK COMPLETE", "a finished run leads with complete")
	_check(view.find_child("Presets", true, false).get_child_count() == 3, "one card per preset")
	var average: Label = view.find_child("Preset1", true, false).find_child("Average", true, false) as Label
	_check(average != null and average.text == "%d FPS" % roundi(float(report["runs"][1]["fps"])), "each card leads with average FPS")
	var details: Control = view.find_child("DetailsPanel", true, false) as Control
	_check(details != null and not details.visible, "details start folded")
	for action: String in ["BenchmarkAgain", "BenchmarkCopy", "BenchmarkFolder", "BenchmarkDetails", "BenchmarkBack"]:
		var button: Button = view.find_child(action, true, false) as Button
		_check(button != null and not view.find_child("Body", true, false).is_ancestor_of(button), "%s sits outside the scrolled body" % action)
	(view.find_child("BenchmarkDetails", true, false) as Button).pressed.emit()
	_check(details.visible, "details open on request")
	var detail_copy: String = ""
	for label: Node in details.find_children("*", "Label", true, false):
		detail_copy += (label as Label).text + "\n"
	_check(detail_copy.contains("Performance preset: no MSAA") and detail_copy.contains("Balanced preset: MSAA 2x") and detail_copy.contains("High preset: MSAA 4x"), "details name what each preset changes")
	_check(detail_copy.contains("Forward+ renderer") and not detail_copy.contains("forward_plus"), "details name the renderer in player words")
	_check(RenderQuality.preset_features(2, "forward_plus", {"upscaling": 2, "pixel_scale": 0}, Vector2i(1920, 1080)).begins_with("no MSAA"), "FSR 2 turns MSAA off, and the description says so")
	_check(RenderQuality.preset_features(1, "mobile", {}, Vector2i(1920, 1080)).contains("ambient occlusion off"), "no ambient occlusion where the renderer has none")
	var timeline: BenchmarkChart = view.find_child("Timeline", true, false) as BenchmarkChart
	_check(timeline != null and timeline.ceiling_ms >= maxf(40.0, float(report["runs"][2]["p95_ms"]) * 2.0) and timeline.ceiling_ms > 1000.0 / 30.0, "the timeline scale holds twice the slowest p95 and both guides")
	var spans: PackedVector2Array = BenchmarkChart.envelope(report["runs"][0]["frame_us"], 100, 20.0)
	var widest: float = 0.0
	for span: Vector2 in spans:
		widest = maxf(widest, span.y)
	_near(widest, float(report["runs"][0]["max_ms"]), "the timeline keeps the single hitch")
	var summary: String = view.summary_text()
	_check(summary.contains("Balanced: %d fps average" % roundi(float(report["runs"][1]["fps"]))) and summary.contains("Test Adapter"), "the copied summary names figures and system")
	_inspect_type(view, "results")
	var signals: Array = []
	view.again_requested.connect(func() -> void: signals.append("again"))
	view.dismissed.connect(func() -> void: signals.append("back"))
	(view.find_child("BenchmarkAgain", true, false) as Button).pressed.emit()
	(view.find_child("BenchmarkBack", true, false) as Button).pressed.emit()
	_check(signals == ["again", "back"], "run again and back reach their owners")
	view.queue_free()
	var stopped: BenchmarkResults = BenchmarkResults.new()
	stopped.report = {"schema_version": BenchmarkRun.SCHEMA_VERSION, "state": "failed", "error": "The window size changed.", "finished_presets": ["Performance"], "runs": []}
	root.add_child(stopped)
	await process_frame
	_check((stopped.find_child("Outcome", true, false) as Label).text == "BENCHMARK STOPPED", "a stopped run says stopped")
	_check(stopped.find_child("Presets", true, false) == null and stopped.find_child("BenchmarkCopy", true, false) == null, "a stopped run shows no figures or copy")
	_check(stopped.find_child("BenchmarkAgain", true, false) != null and stopped.find_child("BenchmarkBack", true, false) != null, "a stopped run can run again or go back")
	_inspect_type(stopped, "stopped")
	stopped.queue_free()
	var unsaved: BenchmarkResults = BenchmarkResults.new()
	var kept: Dictionary = _sample_report()
	kept["save_error"] = "Results could not be saved."
	unsaved.report = kept
	unsaved.directory = _result_dir
	root.add_child(unsaved)
	await process_frame
	_check((unsaved.find_child("Notice", true, false) as Label).text.begins_with("Results could not be saved.") and unsaved.find_child("Presets", true, false) != null, "a save failure is visible beside the in-memory result")
	_check(unsaved.find_child("BenchmarkFolder", true, false) == null, "no folder button without saved files")
	unsaved.queue_free()
	await process_frame

func _history() -> void:
	var directory: String = _result_dir.path_join("history")
	DirAccess.make_dir_recursive_absolute(directory)
	var current: Dictionary = _sample_report()
	var older: Dictionary = _sample_report()
	older["created_utc"] = "2026-10-22T10:00:00"
	var unlike: Dictionary = _sample_report()
	unlike["created_utc"] = "2026-10-23T12:00:00"
	unlike["adapter"] = "Other Adapter"
	unlike["compatibility"] = BenchmarkRun.compatibility(unlike)
	for pair: Array in [["benchmark-20261022T100000-1.json", older], ["benchmark-20261023T120000-1.json", unlike], ["benchmark-junk.json", "not json {"]]:
		var file: FileAccess = FileAccess.open(directory.path_join(pair[0]), FileAccess.WRITE)
		file.store_string(JSON.stringify(pair[1]) if pair[1] is Dictionary else str(pair[1]))
		file.close()
	var found: Dictionary = BenchmarkRun.previous_compatible(directory, current, "benchmark-20261023T220000-1")
	_check(found.get("created_utc") == "2026-10-22T10:00:00", "the last compatible run is found past an unlike and a broken file")
	var faster: Dictionary = _sample_report()
	faster["runs"][1]["settings"]["render_scale"] = 0.5
	faster["compatibility"] = BenchmarkRun.compatibility(faster)
	_check(BenchmarkRun.previous_compatible(directory, faster, "").is_empty(), "different preset settings never compare")
	var view: BenchmarkResults = BenchmarkResults.new()
	view.report = current
	view.previous = found
	_check(view.summary_text().length() > 0, "a comparison does not change the summary")
	view.free()
	_remove_dir(directory)

func _menu() -> void:
	var path: String = "user://test-benchmark-%d.cfg" % OS.get_process_id()
	var preferences: FragrSettings = FragrSettings.new(path)
	preferences.set_value("video", "fps_cap", 45)
	preferences.set_value("video", "vsync", true)
	BenchmarkRun.present_uncapped()
	_check(Engine.max_fps == 0, "the scored run turns the frame cap off")
	_check(int(preferences.get_value("video", "fps_cap")) == 45 and bool(preferences.get_value("video", "vsync")), "the saved pace is not overwritten")
	BenchmarkRun.restore_presentation(preferences)
	_check(Engine.max_fps == 45, "leaving the run restores the saved frame cap")
	_check(BenchmarkRun.preset_label(2) == "High", "preset 2 is High")
	_check(is_equal_approx(BenchmarkRun.nominal_seconds(3), 112.0) and is_equal_approx(BenchmarkRun.nominal_seconds(1), 56.0), "nominal durations follow the documented windows")
	var workload: Dictionary = BenchmarkRun.workload()
	_check(LocalHost.valid_settings(workload), "the benchmark workload is a legal local host")
	var joined: String = " ".join(LocalHost.arguments_for(workload))
	_check(joined.contains("127.0.0.1:0") and joined.contains("--bots 10") and not joined.contains("6767") and not joined.contains("0.0.0.0"), "the benchmark binds a free loopback port")
	var boot: Dictionary = BenchmarkRun.boot_for("ws://127.0.0.1:43123")
	_check(BenchmarkRun.read_boot(boot)["host"] == "ws://127.0.0.1:43123", "a benchmark boot keeps its own host")
	_check(BenchmarkRun.read_boot({"mode": "spectate", "host": "ws://127.0.0.1:6767", "benchmark": "true"}).is_empty(), "a spectate boot is not a benchmark")

	var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
	menu.set("_settings", FragrSettings.new(path))
	root.add_child(menu)
	await process_frame
	await menu._show("main")
	var benchmark_button: Button = menu.find_child("Benchmark", true, false) as Button
	_check(benchmark_button != null and benchmark_button.text == "BENCHMARK", "the main menu has Benchmark")
	var first: Button = null
	for child: Node in (menu.get("_root") as Node).get_children():
		if child is Button:
			first = child as Button
			break
	_check(first != null and first.text == "SINGLE PLAYER", "Benchmark does not take the first focus")
	await menu._show("benchmark")
	var run_button: Button = menu.find_child("RunBenchmark", true, false) as Button
	_check(run_button != null and run_button.text == "RUN CURRENT PRESET (BALANCED)", "the benchmark page names the current preset: " + (run_button.text if run_button != null else ""))
	var compare_button: Button = menu.find_child("CompareBenchmark", true, false) as Button
	_check(compare_button != null and compare_button.text == "COMPARE ALL THREE", "the benchmark page can compare every preset")
	var setup: Control = menu.find_child("BenchmarkSetup", true, false) as Control
	var copy: String = ""
	if setup != null:
		for label: Node in setup.find_children("*", "Label", true, false):
			copy += (label as Label).text + "\n"
	_check(copy.contains("SCORED") and copy.contains("20 s per preset") and copy.contains("8 s of warm-up") and copy.contains("about 1 minute") and copy.contains("about 2 minutes"), "the setup card states windows and durations")
	_check(copy.contains("V-sync and the frame cap are off") and copy.contains("JSON and CSV"), "the setup card states temporary pacing and the saved files")
	_check(menu.find_child("BenchmarkScope", true, false) != null, "the page separates this from server and capacity tests")
	_inspect_type(menu, "menu")
	menu._cancel_benchmark()
	await process_frame
	_check(menu.get("_page") == "main" and not bool(menu.get("_benchmark_pending")), "cancel returns to the main menu without a pending match")
	menu.queue_free()
	await process_frame
	set_meta(BenchmarkRun.CANCELLED_META, true)
	var returned: Control = load("res://scenes/boot_menu.tscn").instantiate()
	returned.set("_settings", FragrSettings.new(path))
	root.add_child(returned)
	await process_frame
	var notice: Label = returned.find_child("BenchmarkNotice", true, false) as Label
	_check(returned.get("_page") == "benchmark" and notice != null and notice.text.begins_with("Benchmark cancelled.") and not has_meta(BenchmarkRun.CANCELLED_META), "a cancelled run returns to the benchmark page and says so")
	returned.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _remove_dir(path: String) -> void:
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
