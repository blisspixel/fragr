extends SceneTree

# Headless checks for the frame-time report, the fixed camera, and the Benchmark page.
# Run: godot --path client --headless --script res://scripts/test_benchmark.gd

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_benchmark: " + message)

func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.02, "%s (got %s, expected %s)" % [message, actual, expected])

func _run() -> void:
	var intervals: PackedFloat32Array = PackedFloat32Array()
	for _index: int in range(99):
		intervals.append(0.010)
	intervals.append(0.050)
	var summary: Dictionary = FrameStats.report(intervals)
	_check(int(summary["count"]) == 100 and int(summary["dropped"]) == 0, "every positive frame counts")
	_near(float(summary["elapsed_s"]), 1.04, "elapsed time is the sum of the frames")
	_near(float(summary["fps"]), 100.0 / 1.04, "fps is the frame count over elapsed time")
	_near(float(summary["mean_ms"]), 10.4, "mean frame time is the average interval")
	_near(float(summary["median_ms"]), 10.0, "median stays with the common frame")
	_near(float(summary["p99_ms"]), 10.4, "the 99th percentile barely reaches the hitch")
	_near(float(summary["smoothness"]), 1.04, "smoothness is the 99th percentile over the median")
	_near(float(summary["min_ms"]), 10.0, "the fastest frame is kept")
	_near(float(summary["max_ms"]), 50.0, "the slowest frame is kept")
	_near(float(summary["low_1_count_fps"]), 20.0, "1 percent low by count averages the slowest frames")
	_near(float(summary["low_1_time_fps"]), 20.0, "1 percent low by time uses the slowest duration")
	_near(float(summary["low_1_percentile_fps"]), 1.0 / 0.0104, "1 percent low by percentile inverts the 99th")
	_near(float(summary["over_33_share"]), 0.050 / 1.04, "a frame at or above 33 ms counts its whole duration")
	_near(float(summary["over_50_share"]), 0.050 / 1.04, "a frame at 50 ms counts as a stall")
	_check(int(summary["stutter_count"]) == 1, "one hitch against the trailing second counts once")
	_near(float(summary["stutter_max_ms"]), 40.0, "the largest jump is the step into the hitch")
	_near(float(summary["mad_ms"]), 0.0, "one hitch does not move the median absolute deviation")
	_check(FrameStats.verdict(summary) == FrameStats.HITCH_VERDICT, "a 50 ms frame in this sample is a hitch")
	_check(FrameStats.verdict({"count": 4, "median_ms": 10.0, "smoothness": 1.2, "over_33_share": 0.0}) == FrameStats.KEEPING_UP_VERDICT, "a 10 ms median without a hitch is the middle case")

	var dirty: PackedFloat32Array = PackedFloat32Array()
	dirty.append(0.0)
	dirty.append(-0.2)
	dirty.append(NAN)
	var empty: Dictionary = FrameStats.report(dirty)
	_check(int(empty["count"]) == 0 and int(empty["dropped"]) == 3, "a clock that did not advance is dropped")
	_check(FrameStats.verdict(empty) == FrameStats.EMPTY_VERDICT, "an empty run says no frames were scored")
	_check(FrameStats.verdict({"count": 4, "median_ms": 5.0, "smoothness": 1.2, "over_33_share": 0.0}) == FrameStats.FAST_VERDICT, "fast even frames name sync and the 20 Hz step")
	_check(FrameStats.verdict({"count": 4, "median_ms": 5.0, "smoothness": 2.5, "over_33_share": 0.0}) == FrameStats.HITCH_VERDICT, "a wide 99th percentile is a hitch")
	_check(FrameStats.verdict({"count": 4, "median_ms": 5.0, "smoothness": 1.1, "over_33_share": 0.02}) == FrameStats.HITCH_VERDICT, "time spent over 33 ms is a hitch")
	_check(FrameStats.verdict({"count": 4, "median_ms": 18.0, "smoothness": 1.1, "over_33_share": 0.0}) == FrameStats.SLOW_VERDICT, "a slow median is the frame itself")
	_check(FrameStats.verdict({"count": 4, "median_ms": 18.0, "smoothness": 2.5, "over_33_share": 0.0}) == FrameStats.SLOW_HITCH_VERDICT, "slow and uneven names both")

	var origin: Dictionary = BenchmarkCamera.pose(0.0)
	var quarter: Dictionary = BenchmarkCamera.pose(5.0)
	var again: Dictionary = BenchmarkCamera.pose(5.0)
	_check((origin["position"] as Vector3).is_equal_approx(Vector3(BenchmarkCamera.RADIUS, BenchmarkCamera.HEIGHT, 0.0)), "the orbit starts on the positive X side")
	_check((quarter["position"] as Vector3).is_equal_approx(Vector3(0.0, BenchmarkCamera.HEIGHT, BenchmarkCamera.RADIUS)), "five seconds is a quarter turn")
	_check((again["position"] as Vector3).is_equal_approx(quarter["position"]), "the same timestamp is the same pose")
	_check((quarter["look"] as Vector3).is_equal_approx(BenchmarkCamera.LOOK), "the camera looks at the arena")
	var body: Node3D = Node3D.new()
	root.add_child(body)
	BenchmarkCamera.apply(body, 5.0)
	_check(body.global_position.is_equal_approx(quarter["position"]), "applying the pose moves the camera")

	var run: BenchmarkRun = BenchmarkRun.new()
	root.add_child(run)
	var scored: Array = []
	run.finished.connect(func(report: Dictionary) -> void: scored.append(report))
	run.begin()
	run.set_process(false)
	run.advance(0.5)
	var banner: Label = run.get_node("BenchmarkBannerLayer/BenchmarkBanner") as Label
	_check(banner != null and banner.text.begins_with("Warming up."), "the warm-up tells you it is not scoring yet")
	for _prime: int in range(15):
		run.advance(0.5)
	_check(run.phase == "scoring" and scored.is_empty(), "the warm-up is discarded")
	for _score_frame: int in range(40):
		run.advance(0.5)
	_check(scored.size() == 1, "the scored window finishes once")
	_check(int(scored[0]["count"]) == 40, "only frames that start after the warm-up are scored")
	_near(float(scored[0]["elapsed_s"]), 20.0, "the scored frames add up to the window")
	run.advance(0.5)
	_check(scored.size() == 1 and int(scored[0]["count"]) == 40, "a finished run does not keep scoring")
	_check(banner.text.is_empty(), "the banner leaves when the score is ready")

	var pace: String = BenchmarkRun.saved_pace(false, 0)
	_check(pace == "Saved settings: vertical sync off, frame cap uncapped. This run turned both off.", "the score names the saved pace")
	_check(BenchmarkRun.preset_label(2) == "High", "preset 2 is High")
	var fast: Dictionary = {"count": 4, "elapsed_s": 20.0, "fps": 200.0, "mean_ms": 5.0, "median_ms": 5.0, "p99_ms": 6.0, "smoothness": 1.2, "low_1_count_fps": 150.0, "low_1_time_fps": 140.0, "low_1_percentile_fps": 160.0, "low_01_count_fps": 100.0, "low_01_time_fps": 90.0, "low_01_percentile_fps": 110.0, "over_33_share": 0.0, "over_50_share": 0.0, "stutter_count": 0, "stutter_max_ms": 1.0}
	var lines: PackedStringArray = BenchmarkRun.presentation(fast, pace, "High", "Test Adapter")
	var block: String = "\n".join(lines)
	_check(block.contains("Arena Duel, ten bots, fixed camera. Preset: High."), "the score names the scene and preset")
	_check(block.contains(FrameStats.FAST_VERDICT), "the score includes the fast verdict")
	_check(block.contains(BenchmarkRun.LIVE_NOTE), "the score says a live match is not the same fight twice")
	_check(block.contains("1 percent low, worst frames by count: 150 fps."), "the count-based 1 percent low is labelled")
	_check(block.contains("1 percent low, worst frames by time: 140 fps."), "the time-based 1 percent low is labelled")
	_check(block.contains("1 percent low, 99th percentile: 160 fps."), "the percentile 1 percent low is labelled")

	var path: String = "user://test-benchmark-%d.cfg" % OS.get_process_id()
	var preferences: FragrSettings = FragrSettings.new(path)
	preferences.set_value("video", "fps_cap", 45)
	preferences.set_value("video", "vsync", true)
	BenchmarkRun.present_uncapped()
	_check(Engine.max_fps == 0, "the scored run turns the frame cap off")
	_check(int(preferences.get_value("video", "fps_cap")) == 45 and bool(preferences.get_value("video", "vsync")), "the saved pace is not overwritten")
	BenchmarkRun.restore_presentation(preferences)
	_check(Engine.max_fps == 45, "leaving the run restores the saved frame cap")
	run.show_score(fast, preferences)
	var score_label: Label = run.find_child("BenchmarkScore", true, false) as Label
	_check(score_label != null and score_label.text.contains("Preset: Balanced.") and score_label.text.contains("vertical sync on, frame cap 45 fps"), "the score panel reads the saved settings")

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
	_check(run_button != null and run_button.text == "RUN CURRENT PRESET", "the benchmark page can run the current preset")
	var compare_button: Button = menu.find_child("CompareBenchmark", true, false) as Button
	_check(compare_button != null and compare_button.text == "COMPARE ALL THREE", "the benchmark page can compare every preset")
	menu._cancel_benchmark()
	await process_frame
	_check(menu.get("_page") == "main" and not bool(menu.get("_benchmark_pending")), "cancel returns to the main menu without a pending match")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures == 0:
		print("test_benchmark: PASS")
		quit(0)
	else:
		push_error("test_benchmark: FAIL (%d)" % _failures)
		quit(1)
