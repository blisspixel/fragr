extends SceneTree

# Headless checks on the frame counter: the summary math, the readout text,
# mode changes through the settings store and through the console.
# Run: godot --path client --headless --script res://scripts/test_performance_overlay.gd

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_performance_overlay: " + message)

func _run() -> void:
	# Ninety-nine 10 ms frames and one 50 ms frame: the mean is 10.4 ms and the
	# slowest one percent is that one frame, so the 1% low is 20 fps.
	var intervals: PackedFloat32Array = PackedFloat32Array()
	for _index: int in range(99):
		intervals.append(0.010)
	intervals.append(0.050)
	var summary: Dictionary = PerformanceOverlay.summarize(intervals)
	_check(is_equal_approx(float(summary["frame_ms"]), 10.4), "mean frame time is the average interval")
	_check(absf(float(summary["fps"]) - 1.0 / 0.0104) < 0.01, "fps is the reciprocal of the mean interval")
	_check(absf(float(summary["low_fps"]) - 20.0) < 0.01, "1% low averages the slowest one percent of frames")
	var empty: Dictionary = PerformanceOverlay.summarize(PackedFloat32Array())
	_check(float(empty["fps"]) == 0.0 and float(empty["low_fps"]) == 0.0, "an empty sample reports zeros")

	_check(PerformanceOverlay.format(PerformanceOverlay.FPS, summary) == "96 FPS", "mode 1 shows only the frame rate")
	_check(PerformanceOverlay.format(PerformanceOverlay.DETAIL, summary) == "96 FPS  10.4 MS  1% LOW 20", "mode 2 adds frame time and the 1% low")
	_check(PerformanceOverlay.format(PerformanceOverlay.OFF, summary).is_empty(), "off shows nothing")

	var path: String = "user://test-performance-overlay-%d.cfg" % OS.get_process_id()
	var preferences: FragrSettings = FragrSettings.new(path)
	_check(int(preferences.get_value("video", "show_fps")) == 0, "the counter is off by default")
	var overlay: PerformanceOverlay = PerformanceOverlay.new()
	overlay.preferences = preferences
	root.add_child(overlay)
	_check(overlay.mode() == PerformanceOverlay.OFF and not overlay.visible and not overlay.is_processing(), "an off counter is hidden and idle")

	overlay.record(-1.0)
	overlay.record(NAN)
	overlay.record(0.0)
	_check(overlay.samples().is_empty(), "non-positive and non-finite intervals are dropped")
	overlay.record(30.0)
	_check(overlay.samples().size() == 1 and is_equal_approx(overlay.samples()[0], PerformanceOverlay.MAX_INTERVAL_SECONDS), "a stall is clamped, not dropped")
	for _index: int in range(PerformanceOverlay.WINDOW_FRAMES + 5):
		overlay.record(0.004)
	_check(overlay.samples().size() == PerformanceOverlay.WINDOW_FRAMES, "the sample window is bounded")

	var candidate: FragrSettings = preferences.draft()
	candidate.set_value("video", "show_fps", 2)
	_check(preferences.commit(candidate) == OK, "the settings store commits the counter mode")
	_check(overlay.mode() == PerformanceOverlay.DETAIL and overlay.visible and overlay.is_processing(), "a committed mode reaches a live counter")
	_check(overlay.samples().is_empty(), "changing mode starts a fresh sample")

	candidate = preferences.draft()
	candidate.set_value("video", "show_fps", 9)
	_check(int(candidate.get_value("video", "show_fps")) == 0, "an unknown mode falls back to the default")
	overlay.set_mode(7)
	_check(overlay.mode() == PerformanceOverlay.OFF and not overlay.visible, "an unknown mode on the node turns the counter off")

	# Let a few real frames pass so the readout actually draws.
	overlay.set_mode(PerformanceOverlay.FPS)
	var started: int = Time.get_ticks_msec()
	while overlay.text().is_empty() and Time.get_ticks_msec() - started < 3000:
		await process_frame
	_check(overlay.text().ends_with(" FPS"), "a live counter draws a frame rate within a few frames")

	var console: FragrConsole = FragrConsole.new()
	console.preferences = preferences
	root.add_child(console)
	console.run("cl_showfps 1")
	_check(int(preferences.get_value("video", "show_fps")) == 1 and overlay.mode() == PerformanceOverlay.FPS, "cl_showfps saves the mode and the counter follows")
	console.run("cl_showfps 0")
	_check(int(preferences.get_value("video", "show_fps")) == 0 and not overlay.visible, "cl_showfps 0 hides the counter")
	console.run("cl_showfps 5")
	console.run("showfps nonsense")
	_check(int(preferences.get_value("video", "show_fps")) == 0, "invalid console values leave the setting alone")
	var reloaded: FragrSettings = FragrSettings.new(path)
	reloaded.load_from_disk()
	_check(int(reloaded.get_value("video", "show_fps")) == 0, "the console choice persists through the settings file")

	console.free()
	overlay.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures == 0:
		print("test_performance_overlay: PASS summary, readout, settings and console modes")
		quit(0)
	else:
		push_error("test_performance_overlay: FAIL (%d)" % _failures)
		quit(1)
