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
	var phase_started: int = Time.get_ticks_msec()
	var shots: Dictionary = {}
	var deadline: int = Time.get_ticks_msec() + 145000
	while run.final_report.is_empty() and Time.get_ticks_msec() < deadline:
		var current_phase: String = "%s-%d" % [run.phase, run.preset_index]
		if current_phase != last_phase:
			print("qa_benchmark phase ", current_phase)
			last_phase = current_phase
			phase_started = Time.get_ticks_msec()
		# One still a few seconds into every phase: what the player sees mid-run.
		if not shots.has(current_phase) and Time.get_ticks_msec() - phase_started > 3000 and run.phase in ["capturing", "priming", "scoring"]:
			shots[current_phase] = true
			_check_scene(run, current_phase)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join("run-%s.png" % current_phase))
		await process_frame
	report = run.final_report.duplicate(true)
	_check(str(report.get("state", "")) == "complete", "all preset measurements completed: " + str(report.get("error", "")))
	if str(report.get("state", "")) == "complete":
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
		_check(row_frames_match(report), "saved frame intervals reproduce every preset's figures")
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("02-results.png"))
		var details: Button = game.find_child("BenchmarkDetails", true, false) as Button
		if _check(details != null, "results offer details"):
			details.pressed.emit()
			for _frame: int in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join("03-results-details.png"))
	await _finish()

## While the benchmark runs: no match chrome, no followed fighter hidden for an
## eye view, and the benchmark HUD on screen with a state and live numbers.
func _check_scene(run: BenchmarkRun, label: String) -> void:
	_check(not game.hud.visible, "%s: match HUD hidden" % label)
	_check(not game.camera.is_observing_first_person() and game.camera.get_followed_target() == null, "%s: the orbit follows nobody" % label)
	for pawn: Node in game.players.values():
		if is_instance_valid(pawn):
			_check(not bool(pawn.get("is_local_fp")), "%s: every fighter is drawn (%s)" % [label, pawn.get("player_name")])
	_check(run.hud != null and run.hud.visible and not (run.hud.find_child("Headline", true, false) as Label).text.is_empty(), "%s: benchmark HUD shows its state" % label)
	_check(not run.hud.live().is_empty(), "%s: live frame rate is reported" % label)

static func row_frames_match(document: Dictionary) -> bool:
	var parsed: Variant = JSON.parse_string(JSON.stringify(document))
	for row: Dictionary in parsed["runs"]:
		var intervals: PackedFloat32Array = PackedFloat32Array()
		for value: Variant in row["frame_us"]:
			intervals.append(float(value) / 1000000.0)
		var again: Dictionary = FrameStats.report(intervals)
		for key: String in ["fps", "low_1_count_fps", "p99_ms", "over_33_count", "count"]:
			if not is_equal_approx(float(again[key]), float(row[key])):
				return false
	return true

## The setup page, the running HUD and the results at exact window sizes, from
## a completed run's saved report. Each size renders into a SubViewport of that
## many pixels with the project's canvas_items/expand stretch, so a tiling
## window manager cannot substitute its own size. One PNG per state.
func _preview_results() -> void:
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("qa-report.json")))
	if not saved is Dictionary or str(saved.get("state", "")) != "complete":
		push_error("qa_benchmark: results preview requires a completed saved run")
		quit(1)
		return
	set_meta("fragr_settings_path", directory.path_join("preview-settings.cfg"))
	set_meta("fragr_records_path", directory.path_join("preview-records"))
	set_meta("fragr_server_book_path", directory.path_join("preview-servers.cfg"))
	var port: SubViewport = SubViewport.new()
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	port.size_2d_override_stretch = true
	port.transparent_bg = false
	root.add_child(port)
	var stopped: Dictionary = {"schema_version": BenchmarkRun.SCHEMA_VERSION, "state": "failed", "interrupted": "scoring", "interrupted_preset": "Balanced", "finished_presets": ["Performance"], "runs": [],
		"error": "The window size changed. Run again to compare the same resolution."}
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(2560, 1080)]:
		port.size = size
		port.size_2d_override = logical_size(size)
		var tag: String = "%dx%d" % [size.x, size.y]
		var menu: Control = load("res://scenes/boot_menu.tscn").instantiate()
		port.add_child(menu)
		await process_frame
		await menu._show("benchmark")
		await _shoot(port, "layout-%s-menu.png" % tag)
		_check_inside(port, menu.find_child("BenchmarkSetup", true, false) as Control, tag + " setup card")
		_check_inside(port, menu.find_child("CompareBenchmark", true, false) as Control, tag + " compare button")
		menu.queue_free()
		await process_frame
		for style: Array in [["s100", HudStyle.new()], ["s150-large", HudStyle.new(1.5, FragrSettings.TEXT_LARGE)]]:
			var counter: PerformanceOverlay = PerformanceOverlay.new()
			port.add_child(counter)
			counter.set_mode(PerformanceOverlay.DETAIL)
			counter.get_node("FrameCounter").text = PerformanceOverlay.format(PerformanceOverlay.DETAIL, {"fps": 999.0, "frame_ms": 16.7, "low_fps": 888.0})
			var hud: BenchmarkHud = BenchmarkHud.new()
			hud.reserved_query = func() -> Array: return [counter.occupied_region()]
			port.add_child(hud)
			hud.apply_style(style[1])
			for _frame: int in range(240):
				hud.push_interval(1.0 / 144.0)
			hud.show_progress({"state": "priming", "headline": "WARMING UP PERFORMANCE", "detail": "Not scored. Shaders and caches settle first. 6 s left.",
				"overall": 0.31, "marks": PackedFloat32Array([0.25, 0.5, 0.75]), "steps": PackedStringArray(["Record", "Performance", "Balanced", "High"]),
				"step": 1, "elapsed_s": 37.0, "remaining_s": 77.0, "scored_frames": 0, "scored_s": 0.0})
			await _shoot(port, "layout-%s-hud-%s.png" % [tag, style[0]])
			if tag == "1920x1080" and style[0] == "s100":
				_measure_overhead(hud)
			var plates: Dictionary = hud.occupied()
			var drawn: Rect2 = HudRegions.text_bounds(counter.get_node("FrameCounter"))
			for key: String in plates:
				_check(Rect2(Vector2.ZERO, Vector2(port.size_2d_override)).encloses(plates[key]), "%s %s HUD %s stays in view" % [tag, style[0], key])
				_check(not (plates[key] as Rect2).intersects(drawn), "%s %s HUD %s clears the frame counter" % [tag, style[0], key])
			_check(not (plates["status"] as Rect2).intersects(plates["live"]) and not (plates["hint"] as Rect2).intersects(plates["status"]) and not (plates["hint"] as Rect2).intersects(plates["live"]), "%s %s HUD plates apart" % [tag, style[0]])
			hud.queue_free()
			counter.queue_free()
			await process_frame
		for state: Array in [["results", saved, false], ["results-details", saved, true], ["stopped", stopped, false]]:
			var view: BenchmarkResults = BenchmarkResults.new()
			view.report = state[1]
			view.directory = directory.path_join("results")
			port.add_child(view)
			await process_frame
			if state[2]:
				(view.find_child("BenchmarkDetails", true, false) as Button).pressed.emit()
				for _frame: int in range(3):
					await process_frame
			await _shoot(port, "layout-%s-%s.png" % [tag, state[0]])
			for button: Node in view.find_child("Actions", true, false).get_children():
				_check_inside(port, button as Control, "%s %s %s" % [tag, state[0], button.name])
			# Opening details scrolls the cards away on purpose; check them unscrolled.
			if state[0] == "stopped":
				_check_inside(port, view.find_child("StoppedCard", true, false) as Control, tag + " stopped card")
			var cards: Node = view.find_child("Presets", true, false) if not state[2] else null
			if cards != null:
				for card: Node in cards.get_children():
					_check_inside(port, card as Control, "%s %s %s" % [tag, state[0], card.name])
			view.queue_free()
			await process_frame
	port.queue_free()
	await process_frame
	print("qa_benchmark: ", "PASS layout" if failures.is_empty() else "FAIL layout")
	quit(0 if failures.is_empty() else 1)

## Script cost of the benchmark readout on this machine: one frame's interval
## (every drawn frame) and one refresh (four times a second, which also lays
## the plates out). Drawing the plates is part of the measured frame and is not
## separated here.
func _measure_overhead(hud: BenchmarkHud) -> void:
	var progress: Dictionary = {"state": "scoring", "headline": "MEASURING BALANCED", "detail": "Scored. 9 s left for this preset.",
		"overall": 0.7, "marks": PackedFloat32Array([0.25, 0.5, 0.75]), "steps": PackedStringArray(["Record", "Performance", "Balanced", "High"]),
		"step": 2, "elapsed_s": 80.0, "remaining_s": 37.0, "scored_frames": 1500, "scored_s": 11.0}
	var started: int = Time.get_ticks_usec()
	for frame: int in range(20000):
		hud.push_interval(0.007 + 0.0001 * float(frame % 7))
	var push_us: float = float(Time.get_ticks_usec() - started) / 20000.0
	started = Time.get_ticks_usec()
	for refresh: int in range(400):
		progress["elapsed_s"] = 80.0 + float(refresh)
		progress["scored_frames"] = 1500 + refresh
		hud.show_progress(progress)
	var refresh_us: float = float(Time.get_ticks_usec() - started) / 400.0
	print("qa_benchmark overhead: push_interval %.2f us per frame, show_progress %.1f us per refresh (%.1f us per second at 4 Hz)" % [push_us, refresh_us, refresh_us * 4.0])

static func logical_size(window: Vector2i) -> Vector2i:
	var aspect: float = float(window.x) / float(window.y)
	if aspect >= 1920.0 / 1080.0:
		return Vector2i(roundi(1080.0 * aspect), 1080)
	return Vector2i(1920, roundi(1920.0 / aspect))

func _shoot(port: SubViewport, file: String) -> void:
	for _frame: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	port.get_texture().get_image().save_png(directory.path_join(file))

func _check_inside(port: SubViewport, control: Control, label: String) -> void:
	if not _check(control != null and control.is_visible_in_tree(), label + " is shown"):
		return
	_check(Rect2(Vector2.ZERO, Vector2(port.size_2d_override)).encloses(control.get_global_rect()), "%s fits the view: %s" % [label, control.get_global_rect()])

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
