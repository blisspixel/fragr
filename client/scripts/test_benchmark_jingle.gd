extends SceneTree

## Headless gate for Crackpot's benchmark certificate (BenchmarkJingle): it
## sings once when a completed run reaches the results screen, never for a
## stopped run and never outside the benchmark results, on the Announcer bus
## so the Announcer volume and Off cover it, and the take picker saves to the
## one settings file and survives a restart.
## Run: godot --path client --headless --script res://scripts/test_benchmark_jingle.gd

var _failures: int = 0
var _path: String = ""


func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_benchmark_jingle: " + message)


func _run() -> void:
	# Jingle players leave the tree playing; their MP3 decoders release only after
	# a mixer turn, so retire them before the harness exits.
	var retirement: ClientRetirement = ClientRetirement.for_tree(self)
	_path = "user://test-benchmark-jingle-%d.cfg" % OS.get_process_id()
	set_meta("localexception_settings_path", _path)
	set_meta("localexception_benchmark_dir", ProjectSettings.globalize_path("user://test-benchmark-jingle-results-%d" % OS.get_process_id()))
	_check_setting()
	_check_takes()
	await _check_completion()
	await _check_announcer_off()
	await _check_stopped()
	await _check_picker()
	_check_only_results_sing()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))
	_check(await retirement.drain(), "every jingle decoder retires before the harness exits")
	if _failures == 0:
		print("test_benchmark_jingle: PASS")
	quit(0 if _failures == 0 else 1)


func _check_setting() -> void:
	var preferences: LocalExceptionSettings = LocalExceptionSettings.new(_path)
	_check(BenchmarkJingle.chosen_take(preferences) == "1a", "the default take is concept 1 take A")
	for bad: Variant in ["9z", "1A", 2, null, ["1b"]]:
		preferences.set_value("audio", "benchmark_jingle", bad)
		_check(BenchmarkJingle.chosen_take(preferences) == "1a", "an unknown take falls back to 1A: " + str(bad))
	preferences.set_value("audio", "benchmark_jingle", "2b")
	_check(preferences.save_to_disk() == OK, "the take saves")
	var reloaded: LocalExceptionSettings = LocalExceptionSettings.new(_path)
	reloaded.load_from_disk()
	_check(BenchmarkJingle.chosen_take(reloaded) == "2b", "the take survives a restart")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func _check_takes() -> void:
	_check(BenchmarkJingle.TAKES.size() == 6, "six take ids: three lyrics, two takes each")
	_check(not BenchmarkJingle.shipped_takes().is_empty(), "at least one take ships")
	for take: String in BenchmarkJingle.shipped_takes():
		var path: String = BenchmarkJingle.take_path(take)
		_check(ResourceLoader.exists(path), "take %s ships at %s" % [take, path])
		var clip: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
		_check(clip != null and clip.get_length() > 4.0 and clip.get_length() < 10.0, "take %s is a few seconds long" % take)
		_check(not BenchmarkJingle.lyric(take).is_empty(), "take %s has a caption" % take)
		_check(BenchmarkJingle.MEASURED_LUFS.has(take) and absf(BenchmarkJingle.gain_db(take)) < 12.0, "take %s has a measured level" % take)
	_check(BenchmarkJingle.label("3b") == "3B", "picker labels read 3B")
	_check(BenchmarkJingle.lyric("1a") == BenchmarkJingle.lyric("1b"), "both takes of a concept sing the same words")


func _report(state: String) -> Dictionary:
	var runs: Array = []
	if state == "complete":
		for quality: int in [1, 2, 3]:
			var frames: PackedFloat32Array = PackedFloat32Array()
			var us: Array = []
			for index: int in range(600):
				var interval: float = 0.005 + 0.002 * float(quality - 1)
				frames.append(interval)
				us.append(roundi(interval * 1000000.0))
			var row: Dictionary = FrameStats.report(frames)
			row.merge({"preset": BenchmarkRun.preset_label(quality), "quality": quality, "frame_us": us, "output_size": [1920, 1080],
				"world_size": [1920, 1080], "settings": {"quality": quality, "render_scale": 1.0}, "replay_sha256": "ab"})
			runs.append(row)
	var report: Dictionary = {"schema_version": BenchmarkRun.SCHEMA_VERSION, "state": state, "created_utc": "2026-10-31T12:00:00",
		"workload": {"id": BenchmarkRun.WORKLOAD_ID}, "renderer": "forward_plus", "driver": "vulkan", "adapter": "Test Adapter",
		"graphics_api": "1.4", "engine": "4.7.2-stable", "build": "release", "os": "Linux", "display_server": "X11", "metric_version": BenchmarkRun.METRIC_VERSION,
		"warmup_seconds": 8.0, "score_seconds": 20.0, "capture": {"snapshots": 561, "sha256": "ab"}, "runs": runs, "save_error": ""}
	if state != "complete":
		report.merge({"interrupted": "scoring", "interrupted_preset": "Balanced", "finished_presets": ["Performance"], "error": "Stopped."})
	report["compatibility"] = BenchmarkRun.compatibility(report)
	return report


func _view(state: String, announcer: int) -> BenchmarkResults:
	var preferences: LocalExceptionSettings = LocalExceptionSettings.new(_path)
	preferences.load_from_disk()
	preferences.set_value("audio", "announcer", announcer)
	var view: BenchmarkResults = BenchmarkResults.new()
	view.report = _report(state)
	view.preferences = preferences
	root.add_child(view)
	return view


## The caption and everything above it sit on a level baseline.
func _level(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if current is Control and not is_zero_approx((current as Control).rotation):
			return false
		current = current.get_parent()
	return true


func _check_completion() -> void:
	var view: BenchmarkResults = _view("complete", LocalExceptionSettings.ANNOUNCER_ON)
	await process_frame
	var jingle: BenchmarkJingle = view.jingle
	_check(jingle != null and jingle.is_inside_tree(), "a completed run gets the jingle")
	if jingle == null:
		view.queue_free()
		return
	_check(view.completion_sung == 1, "completion sings exactly once")
	var expected: String = BenchmarkJingle.chosen_take(view.preferences)
	_check(expected == "1a" or not "1a" in BenchmarkJingle.shipped_takes(), "with no pick, concept 1 take A plays while it ships")
	_check(jingle.playing and jingle.take == expected, "the default take plays: " + jingle.take)
	_check(jingle.bus == &"Announcer", "the jingle sings on the Announcer bus: " + str(jingle.bus))
	_check(is_equal_approx(jingle.volume_db, BenchmarkJingle.gain_db(expected)), "the take is levelled to its measured loudness")
	var caption: Label = view.find_child("JingleCaption", true, false) as Label
	_check(caption != null and caption.text.contains(BenchmarkJingle.lyric(expected)), "the caption shows the lyric")
	_check(caption != null and _level(caption), "the caption is level")
	_check((view.find_child("JingleSpeaker", true, false) as Label).text == "CRACKPOT", "the caption names its singer")
	for _frame: int in range(10):
		await process_frame
	_check(view.completion_sung == 1, "the jingle never repeats on its own")
	# The Announcer volume is the level control: zero mutes the bus it sings on.
	var bus: int = AudioServer.get_bus_index(jingle.bus)
	view.preferences.set_value("audio", "announcer_volume", 0.0)
	view.preferences.apply_audio()
	_check(AudioServer.is_bus_mute(bus), "Announcer volume zero mutes the jingle's bus")
	view.preferences.set_value("audio", "announcer_volume", 0.6)
	view.preferences.apply_audio()
	_check(not AudioServer.is_bus_mute(bus) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(bus)), 0.6), "the Announcer volume sets the jingle's level")
	view.queue_free()
	await process_frame


func _check_announcer_off() -> void:
	var view: BenchmarkResults = _view("complete", LocalExceptionSettings.ANNOUNCER_OFF)
	await process_frame
	_check(view.completion_sung == 0 and view.jingle != null and not view.jingle.playing, "Announcer Off keeps the jingle silent")
	var caption: Label = view.find_child("JingleCaption", true, false) as Label
	_check(caption != null and caption.text.contains("Announcer is Off"), "the caption says why it is silent")
	view.pick_jingle("2a")
	_check(not view.jingle.playing, "a pick stays silent while the Announcer is Off")
	view.queue_free()
	await process_frame
	_check(BenchmarkJingle.allowed(_report("complete"), LocalExceptionSettings.ANNOUNCER_BIG_MOMENTS), "Big moments only still sings: a finished benchmark is one")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func _check_stopped() -> void:
	var view: BenchmarkResults = _view("failed", LocalExceptionSettings.ANNOUNCER_ON)
	await process_frame
	_check(view.jingle == null and view.find_child("Jingle", true, false) == null, "a stopped run has no jingle")
	_check(not BenchmarkJingle.allowed(_report("failed"), LocalExceptionSettings.ANNOUNCER_ON), "only a completed run is allowed to sing")
	_check(not BenchmarkJingle.allowed({"state": "complete", "runs": []}, LocalExceptionSettings.ANNOUNCER_ON), "a run without figures does not sing")
	view.queue_free()
	await process_frame


func _check_picker() -> void:
	var view: BenchmarkResults = _view("complete", LocalExceptionSettings.ANNOUNCER_ON)
	await process_frame
	var pick: Button = view.find_child("JinglePick", true, false) as Button
	var shipped: Array[String] = BenchmarkJingle.shipped_takes()
	_check(pick != null and pick.visible == (shipped.size() > 1), "the picker shows only while there is a choice")
	_check(pick != null and pick.get_parent() == view.find_child("Actions", true, false), "the picker sits in the actions row, where focus stays")
	if pick == null or shipped.size() < 2:
		view.queue_free()
		await process_frame
		return
	_check(pick.text == "JINGLE " + BenchmarkJingle.label(shipped[0]) and _level(pick), "the picker names the take upright: " + pick.text)
	var sung: Array[String] = []
	view.jingle.sang.connect(func(take: String, _seconds: float) -> void: sung.append(take))
	pick.pressed.emit()
	_check(sung == ([shipped[1]] as Array[String]) and view.jingle.take == shipped[1] and view.jingle.playing, "a press sings the next take: " + str(sung))
	_check(pick.text == "JINGLE " + BenchmarkJingle.label(shipped[1]), "the picker follows the take")
	var caption: Label = view.find_child("JingleCaption", true, false) as Label
	_check(caption.text.contains(BenchmarkJingle.lyric(shipped[1])), "the caption follows the pick")
	for _press: int in range(shipped.size() - 1):
		pick.pressed.emit()
	_check(sung.size() == shipped.size() and sung.back() == shipped[0], "every take is heard once and the picker comes back round: " + str(sung))
	var last: String = shipped.back()
	view.pick_jingle(last)
	var reloaded: LocalExceptionSettings = LocalExceptionSettings.new(_path)
	reloaded.load_from_disk()
	_check(BenchmarkJingle.chosen_take(reloaded) == last, "the pick is saved in the settings file")
	_check(view.completion_sung == 1, "picking never counts as another completion")
	view.queue_free()
	await process_frame
	var again: BenchmarkResults = _view("complete", LocalExceptionSettings.ANNOUNCER_ON)
	await process_frame
	_check(again.jingle.take == last and (again.find_child("JinglePick", true, false) as Button).text.ends_with(BenchmarkJingle.label(last)), "the next run sings the saved pick")
	again.queue_free()
	await process_frame


## The certificate belongs to the benchmark results alone: no match, HUD or
## menu script creates one.
func _check_only_results_sing() -> void:
	var owners: Array[String] = []
	for file: String in DirAccess.get_files_at("res://scripts"):
		if not file.ends_with(".gd") or file.begins_with("test_") or file == "benchmark_jingle.gd":
			continue
		if FileAccess.get_file_as_string("res://scripts/" + file).contains("BenchmarkJingle.new("):
			owners.append(file)
	_check(owners == (["benchmark_results.gd"] as Array[String]), "only the benchmark results create the jingle: " + str(owners))
