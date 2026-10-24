extends SceneTree

## Rendered stutter diagnosis on a real local match. One human fighter plays
## a scripted session through the ordinary Action path while a StutterTrace
## records: idle, steady walking and turning, first fire, reload, death and
## respawn, the pause menu opened and closed, then walking again. Each phase
## is a mark, so the report has one row per phase.
##
## FRAGR_QA_DIR (required) receives settings, the client trace, the joined
## report and a Markdown table. FRAGR_STUTTER_HOST is "local" (default: the
## client launches the desktop host, as Host a match does) or "join"
## (FRAGR_SERVER names a separately started server). FRAGR_TICK_TRACE names
## the server half: a launched host inherits it; a separate server must be
## started with --tick-trace at the same path. FRAGR_STUTTER_VSYNC=1 turns
## vsync on; FRAGR_STUTTER_FPS_CAP sets the frame cap; FRAGR_STUTTER_MODE and
## FRAGR_STUTTER_BOTS change the hosted match; FRAGR_STUTTER_FULLSCREEN=1 uses
## the default fullscreen window. On Linux each phase also records the host
## load and the main thread's CPU and run-queue wait shares.
##
## FRAGR_STUTTER_REPORT_ONLY=1 skips the match and only rebuilds report.json
## and table.md from client-trace.json in FRAGR_QA_DIR and the FRAGR_TICK_TRACE
## file, for traces recorded elsewhere (a player's `stutter stop` file and a
## host's --tick-trace file) or after the report logic changes.
##
## This is a diagnosis, not a gate: it passes when the session ran and the
## evidence was written, whatever the numbers say. A phase that could not be
## reached (no death within its bound) is reported, never faked.

const BOUND_MS: int = 240000
const WALK_TURN_RATE: float = 1.2

var _directory: String = ""
var _manager: Node = null
var _host: LocalHost = null
var _started: int = 0
var _failed: bool = false
var _finishing: bool = false
var _phase_notes: Dictionary = {}


func _initialize() -> void:
	set_meta("fragr_automated", true)
	_started = Time.get_ticks_msec()
	MouseCapture.release()
	call_deferred("_run")


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started > BOUND_MS:
		_require(false, "session exceeded its bound")
		_finish()
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		MouseCapture.release()
	return false


func _finalize() -> void:
	MouseCapture.release()


func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error("qa_stutter: " + message)
		_failed = true
	return condition


func _until(condition: Callable, timeout_ms: int = 30000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	return condition.call()


func _run() -> void:
	_directory = OS.get_environment("FRAGR_QA_DIR")
	if not _require(not _directory.is_empty() and _directory.is_absolute_path(), "FRAGR_QA_DIR must name an absolute owned directory"):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	if OS.get_environment("FRAGR_STUTTER_REPORT_ONLY") == "1":
		quit(0 if _write_report() else 1)
		return
	set_meta("fragr_settings_path", _directory.path_join("settings.cfg"))
	set_meta("fragr_records_path", _directory.path_join("records.json"))
	var settings: FragrSettings = FragrSettings.new(_directory.path_join("settings.cfg"))
	settings.set_value("video", "display_mode", 2 if OS.get_environment("FRAGR_STUTTER_FULLSCREEN") == "1" else 0)
	settings.set_value("video", "vsync", OS.get_environment("FRAGR_STUTTER_VSYNC") == "1")
	# A frame cap leaves the main thread idle between frames; 0 keeps the default uncapped loop.
	if OS.get_environment("FRAGR_STUTTER_FPS_CAP").is_valid_int():
		settings.set_value("video", "fps_cap", OS.get_environment("FRAGR_STUTTER_FPS_CAP").to_int())
	settings.set_value("audio", "music", 0.0)
	settings.set_value("audio", "voice", 0.0)
	if not _require(settings.save_to_disk() == OK, "isolated settings save"):
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var host_mode: String = OS.get_environment("FRAGR_STUTTER_HOST")
	var url: String = OS.get_environment("FRAGR_SERVER")
	if host_mode != "join":
		host_mode = "local"
		url = await _launch_local_host()
		if url.is_empty():
			_finish()
			return
	if not _require(not url.is_empty(), "join mode needs FRAGR_SERVER"):
		_finish()
		return
	_phase_notes["host"] = host_mode
	_phase_notes["server"] = url
	set_meta("fragr_boot", {"mode": "join", "host": url})
	change_scene_to_file("res://scenes/main.tscn")
	if not _require(await _until(func() -> bool: return current_scene != null and current_scene.has_method("begin_stutter_trace")), "match scene loaded"):
		_finish()
		return
	_manager = current_scene
	if not _require(await _until(func() -> bool: return _manager.get_node_or_null("LoadingCard") == null \
			and bool(_manager.camera.fp_mode) and _alive(), 60000), "a live first-person fighter"):
		_finish()
		return
	# Let the first frames after loading settle so the session starts in play.
	await create_timer(1.0).timeout
	_phase_notes["load_before"] = _host_load()
	_require(_manager.begin_stutter_trace(), "trace starts")
	await _phase("idle", _idle)
	await _phase("walk_turn", _walk_turn.bind(10.0))
	await _phase("first_fire", _first_fire)
	await _phase("reload", _reload)
	await _phase("death_respawn", _death_respawn)
	await _phase("menu_close", _menu_close)
	await _phase("walk_after", _walk_turn.bind(6.0))
	QaCombat.release_inputs()
	_finish()


func _launch_local_host() -> String:
	_host = LocalHost.for_tree(self)
	await process_frame
	# Team deathmatch is the host menu's default mode. FRAGR_STUTTER_MODE picks another.
	var mode: String = OS.get_environment("FRAGR_STUTTER_MODE") if not OS.get_environment("FRAGR_STUTTER_MODE").is_empty() else "tdm"
	var request: Dictionary = {"mode": mode, "lan": false, "bot_policy": "fixed", "map_id": 1,
		"bots": int(OS.get_environment("FRAGR_STUTTER_BOTS")) if OS.get_environment("FRAGR_STUTTER_BOTS").is_valid_int() else 4,
		"fill_target": 0, "port": 0}
	if not _require(_host.start_host(request), "desktop host starts: " + _host.error_key):
		return ""
	if not _require(await _until(func() -> bool: return _host.state == LocalHost.State.RUNNING \
			or _host.state == LocalHost.State.FAILED, 20000) and _host.state == LocalHost.State.RUNNING,
			"desktop host ready: " + _host.error_key):
		return ""
	_phase_notes["local_host_request"] = request
	return _host.url


func _phase(label: String, body: Callable) -> void:
	if _failed or not is_instance_valid(_manager):
		return
	_manager.stutter_trace.mark(label, Time.get_ticks_usec())
	var started: int = Time.get_ticks_msec()
	var sched_before: Dictionary = _main_thread_sched()
	var note: Variant = await body.call()
	QaCombat.release_inputs()
	Input.action_release("reload")
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	var entry: Dictionary = {"seconds": seconds, "note": note, "load": _host_load()}
	var sched_after: Dictionary = _main_thread_sched()
	if not sched_before.is_empty() and not sched_after.is_empty() and seconds > 0.0:
		# Shares of the phase's wall time: running on a CPU, and runnable but waiting.
		entry["main_cpu_share"] = snappedf(float(sched_after["cpu_ns"] - sched_before["cpu_ns"]) / (seconds * 1e9), 0.001)
		entry["main_runqueue_wait_share"] = snappedf(float(sched_after["wait_ns"] - sched_before["wait_ns"]) / (seconds * 1e9), 0.001)
	_phase_notes[label] = entry


func _idle() -> Variant:
	await create_timer(3.0).timeout
	return "no input"


## Forward with a steady turn and a strafe that flips every two seconds.
func _walk_turn(seconds: float) -> Variant:
	var camera: Node = _manager.camera
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var last: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() < deadline and is_instance_valid(_manager):
		var now: int = Time.get_ticks_msec()
		camera.fp_yaw = wrapf(float(camera.fp_yaw) + WALK_TURN_RATE * float(now - last) / 1000.0, -PI, PI)
		camera.fp_pitch = 0.0
		last = now
		Input.action_press("move_forward")
		var left: bool = int((deadline - now) / 2000) % 2 == 0
		if left:
			Input.action_press("move_left")
			Input.action_release("move_right")
		else:
			Input.action_press("move_right")
			Input.action_release("move_left")
		await process_frame
	return "forward, turning %.1f rad/s, strafe flips every 2 s" % WALK_TURN_RATE


## Aim at the nearest live opponent and fire until the server reports one of
## this fighter's shots, or six seconds pass.
func _first_fire() -> Variant:
	var me_id: String = str(_manager.net_client.player_id)
	var deadline: int = Time.get_ticks_msec() + 6000
	var seen_shot: bool = false
	var last_tick: int = -1
	while Time.get_ticks_msec() < deadline and not seen_shot:
		_aim_at_nearest()
		Input.action_press("fire")
		var snapshot: Dictionary = _manager.latest_snapshot
		if int(snapshot.get("tick", -1)) != last_tick:
			last_tick = int(snapshot.get("tick", -1))
			for shot: Variant in snapshot.get("shot_results", []):
				if shot is Dictionary and str(shot.get("shooter_id", "")) == me_id:
					seen_shot = true
		await process_frame
	return "server confirmed a shot" if seen_shot else "no shot confirmed within 6 s"


func _reload() -> Variant:
	Input.action_press("reload")
	await create_timer(0.1).timeout
	Input.action_release("reload")
	var deadline: int = Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline:
		Input.action_press("move_forward")
		await process_frame
	return "reload pressed while walking"


## Walk at the nearest opponent without firing until this fighter dies, then
## wait for the respawn. Bounded; an unreached death is reported as such.
func _death_respawn() -> Variant:
	var deadline: int = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline and _alive():
		_aim_at_nearest()
		Input.action_press("move_forward")
		await process_frame
	QaCombat.release_inputs()
	if _alive():
		return "not reached: still alive after 60 s"
	_manager.stutter_trace.mark("respawn_wait", Time.get_ticks_usec())
	var respawn_deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < respawn_deadline and not _alive():
		await process_frame
	if not _alive():
		return "died; no respawn within 15 s"
	_manager.stutter_trace.mark("respawned", Time.get_ticks_usec())
	await create_timer(2.0).timeout
	return "died and respawned"


func _menu_close() -> Variant:
	var menu: Node = _manager.get("pause_menu")
	if menu == null or not menu.has_method("open"):
		return "not reached: no pause menu"
	menu.open()
	await create_timer(1.5).timeout
	menu.close()
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		Input.action_press("move_forward")
		await process_frame
	return "opened 1.5 s, closed, walked 3 s"


func _alive() -> bool:
	if not is_instance_valid(_manager) or _manager.net_client.player_id == null:
		return false
	var me: Dictionary = QaCombat.actor_by_id(_manager.latest_snapshot, str(_manager.net_client.player_id))
	return not me.is_empty() and int(me.get("hp", 0)) > 0


func _aim_at_nearest() -> void:
	var snapshot: Dictionary = _manager.latest_snapshot
	var me_id: String = str(_manager.net_client.player_id)
	var me: Dictionary = QaCombat.actor_by_id(snapshot, me_id)
	if me.is_empty():
		return
	var best: Dictionary = {}
	var best_distance: float = INF
	for actor: Variant in snapshot.get("players", []):
		if not actor is Dictionary or str(actor.get("id", "")) == me_id or not ActorState.is_participant(actor) \
				or int(actor.get("hp", 0)) <= 0:
			continue
		var distance: float = Vector2(float(actor["x"]) - float(me["x"]), float(actor["z"]) - float(me["z"])).length()
		if distance < best_distance:
			best = actor
			best_distance = distance
	if best.is_empty():
		return
	var camera: Node = _manager.camera
	camera.fp_yaw = atan2(float(best["z"]) - float(me["z"]), float(best["x"]) - float(me["x"]))
	camera.fp_pitch = clampf(atan2(float(best.get("y", 0.0)) - float(me.get("y", 0.0)), maxf(best_distance, 0.1)),
		-ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT)


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	if not is_instance_valid(_manager) or not _manager.stutter_trace.recording:
		await _stop_host()
		quit(1)
		return
	_phase_notes["load_after"] = _host_load()
	var report: Dictionary = _manager.end_stutter_trace(_directory.path_join("client-trace.json"))
	_require(int(report.get("save_error", OK)) == OK, "client trace saved")
	if is_instance_valid(_manager):
		_manager.net_client.leave_match()
	await create_timer(0.5).timeout
	await _stop_host()
	_write_report()
	if _failed:
		push_error("qa_stutter: FAIL")
		quit(1)
	else:
		print("qa_stutter: PASS evidence written to ", _directory)
		quit(0)


## Joins client-trace.json in the output directory with the server tick trace
## named by FRAGR_TICK_TRACE, then writes report.json and table.md. A report-only
## run keeps the phase notes of the report it replaces.
func _write_report() -> bool:
	var server_path: String = OS.get_environment("FRAGR_TICK_TRACE")
	var server: Dictionary = {}
	if not server_path.is_empty():
		server = StutterReport.parse_tick_trace(FileAccess.get_file_as_string(server_path))
		_require(str(server.get("error", "")).is_empty(), "server tick trace reads: " + str(server.get("error", "")))
	var client: Variant = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("client-trace.json")))
	if not _require(client is Dictionary, "client trace reads back"):
		return false
	var joined: Dictionary = StutterReport.analyze(client, server)
	if not _require(str(joined.get("error", "")).is_empty(), "report: " + str(joined.get("error", ""))):
		return false
	if _phase_notes.is_empty():
		var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join("report.json")))
		if previous is Dictionary and previous.get("phases_run") is Dictionary:
			_phase_notes = previous["phases_run"]
	joined["phases_run"] = _phase_notes
	joined["context"] = (client as Dictionary).get("context", {})
	var out: FileAccess = FileAccess.open(_directory.path_join("report.json"), FileAccess.WRITE)
	if not _require(out != null, "report.json opens"):
		return false
	out.store_string(JSON.stringify(joined, "  "))
	out.close()
	var rows: PackedStringArray = StutterReport.table(joined)
	var table: FileAccess = FileAccess.open(_directory.path_join("table.md"), FileAccess.WRITE)
	if not _require(table != null, "table.md opens"):
		return false
	table.store_string("\n".join(rows) + "\n")
	table.close()
	for row: String in rows:
		print(row)
	print("qa_stutter: phases ", JSON.stringify(_phase_notes))
	return not _failed


## Other work on the machine changes every timing here. Linux reports its
## run-queue averages; elsewhere this is recorded as unknown.
static func _host_load() -> String:
	return _proc_line("/proc/loadavg")


## Main thread scheduler totals: nanoseconds on a CPU and waiting on the run
## queue. Waiting time is contention from other work, not this game's cost.
static func _main_thread_sched() -> Dictionary:
	var fields: PackedStringArray = _proc_line("/proc/self/task/%d/schedstat" % OS.get_process_id()).split(" ", false)
	if fields.size() < 2 or not fields[0].is_valid_int() or not fields[1].is_valid_int():
		return {}
	return {"cpu_ns": fields[0].to_int(), "wait_ns": fields[1].to_int()}


## Procfs files report no size, so read one line rather than the whole file.
static func _proc_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "unknown"
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unknown"
	var line: String = file.get_line().strip_edges()
	file.close()
	return line


func _stop_host() -> void:
	if _host == null or not is_instance_valid(_host):
		return
	_host.stop()
	await _until(func() -> bool: return _host.state == LocalHost.State.IDLE or _host.state == LocalHost.State.FAILED, 5000)
