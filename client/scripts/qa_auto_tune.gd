extends SceneTree

## A real auto settings run through the menu, in a rendered window, with
## isolated settings and results: the first-launch card, the live readout,
## the result card, and the report. Timing on a busy machine is diagnostic
## only; the tuner's logic is proven by test_auto_tune.gd. Never forces
## frames: an occluded window must fail the measurement.
##
## LOCALEXCEPTION_QA_DIR=<dir> godot --path client --script res://scripts/qa_auto_tune.gd
## Optional user args: --card-only (the first-launch card, then quit);
## --results-only (the saved qa-report.json's result card and the first-launch
## card at exact 1920x1080 and Steam Deck 1280x800 sizes, in SubViewports so a
## tiling window manager cannot change them).
var directory: String
var failures: Array[String] = []
var report: Dictionary = {}

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	_run.call_deferred()

func _check(ok: bool, reason: String) -> bool:
	if not ok:
		failures.append(reason)
		push_error("qa_auto_tune: " + reason)
	return ok

func _until(predicate: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func _shot(file: String) -> void:
	for _frame: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(file))

func _run() -> void:
	directory = OS.get_environment("LOCALEXCEPTION_QA_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		push_error("qa_auto_tune requires a rendered window and LOCALEXCEPTION_QA_DIR")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	if "--results-only" in OS.get_cmdline_user_args():
		await _preview()
		return
	var settings_path: String = directory.path_join("settings.cfg")
	set_meta("localexception_settings_path", settings_path)
	set_meta("localexception_records_path", directory.path_join("records"))
	set_meta("localexception_benchmark_dir", directory.path_join("results"))
	set_meta("localexception_server_book_path", directory.path_join("servers.cfg"))
	OS.set_environment("LOCALEXCEPTION_RUN_DIR", directory.path_join("runs"))
	var preferences: LocalExceptionSettings = LocalExceptionSettings.new(settings_path)
	preferences.set_value("video", "display_mode", 0)
	preferences.set_value("audio", "master", 0.0)
	preferences.save_to_disk()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	# The card shows for a fresh settings file; force it past the automation guard.
	set_meta(&"localexception_tune_offer_force", true)
	change_scene_to_file("res://scenes/boot_menu.tscn")
	await process_frame
	await process_frame
	var menu: Control = current_scene as Control
	_check(menu.find_child("TuneOfferCard", true, false) != null, "a fresh settings file shows the first-launch card")
	await _shot("01-first-launch-card.png")
	if "--card-only" in OS.get_cmdline_user_args():
		await _finish()
		return
	var start: Button = menu.find_child("TuneOfferStart", true, false) as Button
	if not _check(start != null, "the card has Start now"):
		await _finish()
		return
	remove_meta(&"localexception_tune_offer_force")
	start.pressed.emit()
	if not _check(await _until(func() -> bool: return root.get_node_or_null("GameManager") != null, 30), "Start runs the owned local match"):
		await _finish()
		return
	var game: Node = root.get_node("GameManager")
	if not _check(await _until(func() -> bool: return game.get_node_or_null("BenchmarkRun") != null, 30), "the world reveal starts the tune"):
		await _finish()
		return
	var run: BenchmarkRun = game.get_node("BenchmarkRun") as BenchmarkRun
	var shots: Dictionary = {}
	var last: String = ""
	var since: int = Time.get_ticks_msec()
	var started: int = Time.get_ticks_msec()
	var deadline: int = Time.get_ticks_msec() + 240000
	while run.final_report.is_empty() and Time.get_ticks_msec() < deadline:
		var current: String = "%s-%d" % [run.phase, run.preset_index]
		if current != last:
			print("qa_auto_tune phase ", current, " ", run.progress().get("headline", ""))
			last = current
			since = Time.get_ticks_msec()
		if not shots.has(run.phase) and Time.get_ticks_msec() - since > 2500 and run.phase in ["capturing", "priming", "scoring"]:
			shots[run.phase] = true
			_check(run.tuner != null and (root.get_node("LocalHost") as LocalHost).state == LocalHost.State.RUNNING or run.phase == "capturing", "the local server keeps running while candidates are scored")
			await _shot("02-run-%s.png" % run.phase)
		await process_frame
	report = run.final_report.duplicate(true)
	report["qa_wall_seconds"] = float(Time.get_ticks_msec() - started) / 1000.0
	_check(str(report.get("state", "")) == "complete", "the tune completed: " + str(report.get("error", "")))
	if str(report.get("state", "")) == "complete":
		_check(report.get("auto_tune") is Dictionary and not (report["auto_tune"]["lines"] as Array).is_empty(), "the report carries the plain-words result")
		var saved: LocalExceptionSettings = LocalExceptionSettings.new(settings_path)
		saved.load_from_disk()
		_check((saved.get_value("video", "tune") as Dictionary).get("source") == "measured", "the choice is saved")
		await _shot("03-result-card.png")
		print("qa_auto_tune result:\n  ", "\n  ".join(PackedStringArray(report["auto_tune"]["lines"])))
		for row: Variant in report["auto_tune"]["result"]["candidates"]:
			print("qa_auto_tune candidate %s low1 %.1f gpu %.2f ms share %.2f %s" % [row["label"], row["low_1_count_fps"], row["gpu_ms_mean"], row["gpu_slow_share"], row["outcome"]])
	game._on_leave_requested()
	await _finish()

func _preview() -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("qa-report.json")))
	if not saved is Dictionary or not (saved as Dictionary).get("auto_tune") is Dictionary:
		push_error("qa_auto_tune: --results-only needs a completed qa-report.json")
		quit(1)
		return
	# _finish writes qa-report.json back; keep the run's report in it.
	report = (saved as Dictionary).duplicate(true)
	set_meta("localexception_settings_path", directory.path_join("preview-settings.cfg"))
	set_meta("localexception_records_path", directory.path_join("preview-records"))
	set_meta("localexception_server_book_path", directory.path_join("preview-servers.cfg"))
	set_meta(&"localexception_tune_offer_force", true)
	var port: SubViewport = SubViewport.new()
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	port.size_2d_override_stretch = true
	root.add_child(port)
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 800)]:
		port.size = size
		var aspect: float = float(size.x) / float(size.y)
		port.size_2d_override = Vector2i(roundi(1080.0 * aspect), 1080) if aspect >= 1920.0 / 1080.0 else Vector2i(1920, roundi(1920.0 / aspect))
		var tag: String = "%dx%d" % [size.x, size.y]
		var view: BenchmarkResults = BenchmarkResults.new()
		view.report = saved
		port.add_child(view)
		await _port_shot(port, "preview-%s-result.png" % tag)
		for button: Node in view.find_child("Actions", true, false).get_children():
			var rect: Rect2 = (button as Control).get_global_rect()
			_check(Rect2(Vector2.ZERO, Vector2(port.size_2d_override)).encloses(rect), "%s %s fits" % [tag, button.name])
		view.queue_free()
		await process_frame
		if has_meta(&"localexception_tune_offered"):
			remove_meta(&"localexception_tune_offered")
		var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
		port.add_child(menu)
		await process_frame
		await _port_shot(port, "preview-%s-card.png" % tag)
		var card: Control = menu.find_child("TuneOfferCard", true, false) as Control
		_check(card != null and Rect2(Vector2.ZERO, Vector2(port.size_2d_override)).encloses(card.get_global_rect()), tag + " card fits")
		menu.queue_free()
		await process_frame
	await _finish()

func _port_shot(port: SubViewport, file: String) -> void:
	for _frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	port.get_texture().get_image().save_png(directory.path_join(file))

func _finish() -> void:
	report["qa_failures"] = failures
	var file: FileAccess = FileAccess.open(directory.path_join("qa-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	var host: LocalHost = root.get_node_or_null("LocalHost") as LocalHost
	if host != null:
		host.stop()
		await _until(func() -> bool: return host.state not in [LocalHost.State.RUNNING, LocalHost.State.STARTING, LocalHost.State.STOPPING], 5)
	await process_frame
	print("qa_auto_tune: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
