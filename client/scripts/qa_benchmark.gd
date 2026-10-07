extends SceneTree

## Real menu ingress, rendered preset comparison and isolated saved evidence.
## Never forces rendered frames: an occluded window must fail the measurement.
var game: Node
var directory: String
var failures: Array[String] = []
var before_settings: PackedByteArray
var report: Dictionary = {}

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	_run.call_deferred()

func _check(ok: bool, reason: String) -> bool:
	if not ok:
		failures.append(reason)
		push_error("qa_benchmark: " + reason)
	return ok

func _until(predicate: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func _run() -> void:
	directory = OS.get_environment("FRAGR_QA_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		push_error("qa_benchmark requires a rendered window and FRAGR_QA_DIR for isolated evidence")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	if "--results-only" in OS.get_cmdline_user_args():
		await _preview_results()
		return
	var settings_path: String = directory.path_join("settings.cfg")
	set_meta("fragr_settings_path", settings_path)
	set_meta("fragr_records_path", directory.path_join("records"))
	set_meta("fragr_benchmark_dir", directory.path_join("results"))
	set_meta("fragr_server_book_path", directory.path_join("servers.cfg"))
	OS.set_environment("FRAGR_RUN_DIR", directory.path_join("runs"))
	var preferences: FragrSettings = FragrSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	preferences.set_value("video", "quality", 1)
	preferences.set_value("video", "fps_cap", 45)
	preferences.set_value("video", "vsync", false)
	preferences.set_value("audio", "master", 0.0)
	preferences.save_to_disk()
	before_settings = FileAccess.get_file_as_bytes(settings_path)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/boot_menu.tscn")
	await process_frame
	await process_frame
	var menu: Control = current_scene as Control
	menu._show("benchmark")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("01-menu.png"))
	var compare: Button = menu.find_child("CompareBenchmark", true, false) as Button
	if not _check(compare != null, "menu exposes Compare all three"):
		await _finish()
		return
	compare.pressed.emit()
	if not _check(await _until(func() -> bool: return root.get_node_or_null("GameManager") != null, 25), "normal menu starts the owned local match"):
		await _finish()
		return
	game = root.get_node("GameManager")
	if not _check(await _until(func() -> bool: return game.get_node_or_null("BenchmarkRun") != null, 25), "normal world reveal starts benchmark"):
		await _finish()
		return
	var run: BenchmarkRun = game.get_node("BenchmarkRun") as BenchmarkRun
	_check(not game.console.is_open() and not game.console.is_processing_unhandled_input(), "benchmark prevents console settings edits during measurement")
	var last_phase: String = ""
	var deadline: int = Time.get_ticks_msec() + 145000
	while run.final_report.is_empty() and Time.get_ticks_msec() < deadline:
		var current_phase: String = "%s:%d" % [run.phase, run.preset_index]
		if current_phase != last_phase:
			print("qa_benchmark phase ", current_phase)
			last_phase = current_phase
		await process_frame
	report = run.final_report.duplicate(true)
	_check(not report.is_empty() and not report.has("error"), "all preset measurements completed: " + str(report.get("error", "")))
	if not report.is_empty() and not report.has("error"):
		_check(report.runs.size() == 3, "three preset rows are saved")
		for index: int in range(report.runs.size()):
			var row: Dictionary = report.runs[index]
			_check(row.quality == index and row.count > 0 and row.fps > 0 and row.low_1_count_fps > 0, "preset has real positive frame samples")
			_check(row.replayed_snapshots == report.capture.snapshots and row.replay_sha256 == report.capture.sha256, "every preset consumes identical recorded snapshots")
			_check(row.settings.fps_cap == 0 and not row.settings.vsync, "export records actual uncapped measurement settings")
		_check(str(report.save_error).is_empty(), "JSON and CSV persisted successfully")
		_check(FileAccess.get_file_as_bytes(settings_path) == before_settings, "settings file is byte-for-byte unchanged")
		_check(game.settings.get_value("video", "quality") == 1 and Engine.max_fps == 45 and run.render_settings == null, "quality and frame cap restored after completion")
		var host: LocalHost = root.get_node("LocalHost") as LocalHost
		_check(host.state == LocalHost.State.IDLE, "owned native host stopped before scoring")
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "automation never captured the pointer")
		_check(not game.hud.warmup_tv_active, "recorded active state clears the warmup overlay")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("02-results.png"))
	await _finish()

func _preview_results() -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("qa-report.json")))
	if not saved is Dictionary or not saved.get("runs") is Array:
		push_error("qa_benchmark: results preview requires a completed saved run")
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var view: BenchmarkResults = BenchmarkResults.new()
	view.report = saved
	view.directory = directory.path_join("results")
	root.add_child(view)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("03-results-final.png"))
	view.queue_free()
	await process_frame
	print("qa_benchmark: PASS results preview")
	quit()

func _finish() -> void:
	report["qa_failures"] = failures
	var file: FileAccess = FileAccess.open(directory.path_join("qa-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	if is_instance_valid(game):
		game._on_leave_requested()
	var host: LocalHost = root.get_node_or_null("LocalHost") as LocalHost
	if host != null:
		host.stop()
		await _until(func() -> bool: return host.state not in [LocalHost.State.RUNNING, LocalHost.State.STARTING, LocalHost.State.STOPPING], 5)
	await process_frame
	MouseCapture.release()
	print("qa_benchmark: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
