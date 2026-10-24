extends SceneTree

# Headless checks on stutter diagnosis: the client recorder stays inert when
# off and bounded when on, the server tick trace reader refuses malformed
# files, and the report names the stage behind each slow frame and late
# Snapshot only when a measured share of the delay sits there.
# Run: godot --path client --headless --script res://scripts/test_stutter_trace.gd

const FRAME_US: int = 16667
const T0: int = 1000000
const UNIX0: int = 1700000000000000

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_stutter_trace: " + message)


func _run() -> void:
	_check_inert_when_off()
	_check_recording()
	_check_bounds()
	_check_prediction_observation()
	_check_save_round_trip()
	_check_tick_trace_reader()
	_check_report_attribution()
	_check_slow_median_gaps()
	_check_report_refuses_malformed_input()
	_check_remote_starvation()
	await _check_overlay_feeds_trace()
	_check_console_and_manager_paths()
	if _failures == 0:
		print("test_stutter_trace: PASS recorder, tick trace reader, attribution and hooks")
		quit(0)
	else:
		push_error("test_stutter_trace: FAIL (%d)" % _failures)
		quit(1)


func _check_inert_when_off() -> void:
	var trace: StutterTrace = StutterTrace.new()
	trace.record_frame(T0, 10, 1.0, 1.0, 5)
	trace.record_frame(T0 + FRAME_US, 10, 1.0, 1.0, 5)
	trace.record_poll(T0, 10, 1, 100)
	trace.record_snapshot(4, T0, 10)
	trace.record_ack({"seq": 1, "tick": 4}, T0)
	trace.note_view(T0, "first_person", Vector4.ZERO, 1)
	trace.mark("walk", T0)
	trace.observe_prediction(LocalPrediction.new(), T0)
	_check(trace.frame_usec.is_empty() and trace.poll_usec.is_empty() and trace.snapshot_usec.is_empty()
		and trace.ack_usec.is_empty() and trace.correction_usec.is_empty() and trace.events.is_empty(),
		"an idle trace records nothing")


func _check_recording() -> void:
	var trace: StutterTrace = StutterTrace.new()
	trace.begin(T0, UNIX0, {"role": "human"})
	trace.record_frame(T0, -1, 0.0, 0.0, 10)
	_check(trace.frame_usec.is_empty(), "the first frame only starts the clock")
	trace.note_view(T0 + 1, "first_person:a::human", Vector4(1.0, 2.0, 3.0, 0.5), 2)
	trace.record_frame(T0 + FRAME_US, 4000, 1.5, NAN, 13)
	_check(trace.frame_usec.size() == 1 and trace.frame_interval_us[0] == FRAME_US, "the second frame records its interval")
	_check(trace.frame_compiles[0] == 3, "pipeline compilations are the change in the cumulative count")
	_check(trace.frame_script_us[0] == 4000 and trace.frame_render_cpu_us[0] == 1500 and trace.frame_render_gpu_us[0] == -1,
		"script span and render times are kept; an unknown render time is -1")
	_check(trace.frame_remote_starved[0] == 2 and is_equal_approx(trace.frame_camera[3], 0.5), "the noted view rides on the next frame")
	trace.record_frame(T0 + FRAME_US, 0, 0.0, 0.0, 13)
	trace.record_frame(T0, 0, 0.0, 0.0, 13)
	_check(trace.frame_usec.size() == 1, "a clock that did not advance adds no frame")
	trace.record_frame(T0 + 60 * 1000000, 0, 0.0, 0.0, 12)
	_check(trace.frame_interval_us[1] == StutterTrace.MAX_INTERVAL_US and trace.frame_compiles[1] == 0,
		"a debugger stop is clamped and a falling counter never goes negative")
	trace.note_view(T0 + 2, "first_person:a::human", Vector4.ZERO, 0)
	trace.note_view(T0 + 3, "third_person:b::human", Vector4.ZERO, -4)
	var cameras: Array = trace.events.filter(func(e: Dictionary) -> bool: return e["kind"] == "camera")
	_check(cameras.size() == 2 and cameras[1]["from"] == "first_person:a::human" and cameras[1]["to"] == "third_person:b::human",
		"only a changed camera mode is an event")
	trace.record_poll(T0, 300, 0, 0)
	trace.record_poll(T0, 300, 2, 900)
	_check(trace.poll_usec.size() == 1 and trace.poll_packets[0] == 2, "only polls that delivered messages are kept")
	for bad: Variant in ["7", -1, 1.5, NAN, null]:
		trace.record_snapshot(bad, T0, 10)
	trace.record_snapshot(12.0, T0, 10)
	_check(trace.snapshot_tick.size() == 1 and trace.snapshot_tick[0] == 12 and int(trace.dropped.get("snapshot_ticks", 0)) == 5,
		"only whole non-negative ticks are joined; the rest are counted")
	trace.record_ack({"seq": 3}, T0)
	trace.record_ack({"seq": 3, "tick": 12}, T0)
	_check(trace.ack_seq.size() == 1 and int(trace.dropped.get("ack_fields", 0)) == 1, "an Ack without a tick is counted, not kept")
	trace.mark("   ", T0)
	trace.mark("x".repeat(200), T0)
	var marks: Array = trace.events.filter(func(e: Dictionary) -> bool: return e["kind"] == "mark")
	_check(marks[0]["label"] == "mark" and str(marks[1]["label"]).length() == StutterTrace.MAX_LABEL, "labels are trimmed and bounded")
	var saved: Dictionary = trace.stop(T0 + 5000000)
	_check(not trace.recording and int(saved["stopped_usec"]) == T0 + 5000000 and saved["context"]["role"] == "human",
		"stop keeps the window and its context")
	trace.record_frame(T0 + 70 * 1000000, 0, 0.0, 0.0, 12)
	_check(trace.frame_usec.size() == 2, "a stopped trace records nothing")
	trace.begin(T0, UNIX0)
	_check(trace.frame_usec.is_empty() and trace.events.is_empty() and trace.dropped.is_empty(), "begin starts an empty window")


func _check_bounds() -> void:
	var trace: StutterTrace = StutterTrace.new()
	trace.begin(0, UNIX0)
	trace.record_frame(1, 0, 0.0, 0.0, 0)
	for index: int in range(StutterTrace.MAX_FRAMES + 3):
		trace.record_frame(2 + index, 0, 0.0, 0.0, 0)
	_check(trace.frame_usec.size() == StutterTrace.MAX_FRAMES and int(trace.dropped["frames"]) == 3,
		"frames stop at the cap and the excess is counted")
	for index: int in range(StutterTrace.MAX_EVENTS + 2):
		trace.mark("m", index)
	_check(trace.events.size() == StutterTrace.MAX_EVENTS and int(trace.dropped["events"]) == 2, "events are bounded")
	for index: int in range(StutterTrace.MAX_TICKS + 1):
		trace.record_snapshot(index, index, 0)
	_check(trace.snapshot_usec.size() == StutterTrace.MAX_TICKS and int(trace.dropped["snapshots"]) == 1, "snapshots are bounded")


func _check_prediction_observation() -> void:
	var trace: StutterTrace = StutterTrace.new()
	var predictor: LocalPrediction = LocalPrediction.new()
	trace.begin(T0, UNIX0)
	trace.observe_prediction(predictor, T0)
	_check(trace.events.size() == 1 and trace.events[0]["kind"] == "prediction_state" and trace.events[0]["state"] == "no_ack",
		"the first observation records the starting state without inventing a reset")
	predictor.correction_count = 2
	predictor.correction_samples.assign([0.01, 0.2])
	predictor.tick = 40
	predictor.visual_offset = Vector3(0.1, 0.0, 0.0)
	trace.observe_prediction(predictor, T0 + 10)
	_check(trace.correction_m.size() == 2 and is_equal_approx(trace.correction_m[1], 0.2) and trace.correction_tick[1] == 40
		and is_equal_approx(trace.correction_offset_m[1], 0.1), "new corrections are copied once with their tick and offset")
	trace.observe_prediction(predictor, T0 + 20)
	_check(trace.correction_m.size() == 2, "an unchanged predictor adds nothing")
	predictor.reset("ack_lag")
	trace.observe_prediction(predictor, T0 + 30)
	var resets: Array = trace.events.filter(func(e: Dictionary) -> bool: return e["kind"] == "prediction_reset")
	_check(resets.is_empty(), "a reset of an inactive predictor is a state change, not a visible reset")
	predictor.fallback_count += 2
	predictor.last_fallback_reason = "ack_timeout"
	trace.observe_prediction(predictor, T0 + 40)
	resets = trace.events.filter(func(e: Dictionary) -> bool: return e["kind"] == "prediction_reset")
	_check(resets.size() == 1 and resets[0]["reason"] == "ack_timeout" and int(resets[0]["count"]) == 2,
		"resets of an active predictor are counted with the newest reason")
	predictor.clear_measurements()
	trace.observe_prediction(predictor, T0 + 50)
	predictor.correction_count = 1
	predictor.correction_samples.assign([0.03])
	trace.observe_prediction(predictor, T0 + 60)
	_check(trace.correction_m.size() == 3 and is_equal_approx(trace.correction_m[2], 0.03),
		"a cleared measurement window resynchronises instead of replaying old samples")
	trace.observe_prediction(null, T0 + 70)


func _check_save_round_trip() -> void:
	var trace: StutterTrace = StutterTrace.new()
	trace.begin(T0, UNIX0, {"video": {"vsync": false}})
	trace.record_frame(T0, -1, 0.0, 0.0, 0)
	trace.record_frame(T0 + FRAME_US, 100, 0.5, 0.5, 0)
	trace.record_snapshot(9, T0 + 10, 50)
	var saved: Dictionary = trace.stop(T0 + 2 * FRAME_US)
	var path: String = "user://test-stutter-%d/trace.json" % OS.get_process_id()
	_check(StutterTrace.save(saved, path) == OK, "a trace saves into a new directory")
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	_check(parsed is Dictionary and parsed["frames"]["camera"][0] == null, "an unknown camera sample is written as null, not NaN")
	var report: Dictionary = StutterReport.analyze(parsed)
	_check(str(report.get("error", "x")).is_empty() and int(report["session"]["frames"]["count"]) == 1
		and int(report["session"]["snapshots"]["count"]) == 1, "the saved file reads back into the report")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	# A directory where the file should be cannot be opened for writing.
	var occupied: String = "user://test-stutter-occupied-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(occupied)
	_check(StutterTrace.save(saved, occupied) != OK, "an unwritable path is reported, not ignored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(occupied))


func _tick_line(tick: int, fields: Dictionary = {}) -> String:
	var record: Dictionary = {"record": "tick", "tick": tick, "unix_us": UNIX0 + tick * 50000, "late_us": 100,
		"skipped": 0, "sim_us": 900, "measure_us": 50, "fanout_us": 60, "total_us": 1200, "clients": 1,
		"messages": 3, "bytes": 2000, "overflows": 0}
	record.merge(fields, true)
	return JSON.stringify(record)


func _header() -> String:
	return JSON.stringify({"record": "header", "version": 1, "tick_us": 50000,
		"build": {"crate_version": "0.0.0", "release": null, "commit": "unknown"}, "started_unix_us": UNIX0})


func _check_tick_trace_reader() -> void:
	var footer: String = JSON.stringify({"record": "complete", "ticks": 2, "dropped": 0, "over_budget": 0, "skipped_periods": 0})
	var good: Dictionary = StutterReport.parse_tick_trace("\n".join([_header(), _tick_line(1), _tick_line(2), footer, ""]))
	_check(str(good["error"]).is_empty() and (good["ticks"] as Dictionary).size() == 2 and not (good["complete"] as Dictionary).is_empty()
		and int(good["ticks"][2]["total_us"]) == 1200, "a complete trace reads with integer fields keyed by tick")
	var cut: Dictionary = StutterReport.parse_tick_trace("\n".join([_header(), _tick_line(1)]))
	_check(str(cut["error"]).is_empty() and (cut["complete"] as Dictionary).is_empty(), "a killed server's trace reads as incomplete")
	var cases: Dictionary = {
		"": "no header",
		_tick_line(1): "first record must be the header",
		_header().replace("\"version\":1", "\"version\":2"): "unsupported tick trace version",
		"\n".join([_header(), "{oops"]): "not a JSON object",
		"\n".join([_header(), "[1,2]"]): "not a JSON object",
		"\n".join([_header(), _tick_line(1, {"late_us": -3})]): "late_us is not a whole number",
		"\n".join([_header(), _tick_line(1, {"sim_us": 1.5})]): "sim_us is not a whole number",
		"\n".join([_header(), _tick_line(1, {"extra": 1})]): "unknown tick field",
		"\n".join([_header(), _tick_line(2), _tick_line(2)]): "ticks must increase",
		"\n".join([_header(), _tick_line(1), footer, _tick_line(2)]): "record after the completion footer",
		"\n".join([_header(), JSON.stringify({"record": "mystery"})]): "unknown record",
		"\n".join([_header(), JSON.stringify({"record": "complete", "ticks": 1})]): "footer field dropped",
		JSON.stringify({"record": "header", "version": 1, "tick_us": 0, "build": {}, "started_unix_us": 0}): "malformed header",
	}
	for text: String in cases:
		var parsed: Dictionary = StutterReport.parse_tick_trace(text)
		_check(str(parsed["error"]).contains(str(cases[text])) and (parsed["ticks"] as Dictionary).is_empty(),
			"refuses %s (got %s)" % [cases[text], parsed["error"]])


## A synthetic session with one planted cause per slow frame and late Snapshot.
func _synthetic() -> Dictionary:
	var trace: StutterTrace = StutterTrace.new()
	trace.begin(T0, UNIX0)
	var now: int = T0
	trace.record_frame(now, -1, 0.0, 0.0, 0)
	var compiles: int = 0
	var x: float = 0.0
	trace.mark("walk", T0 + 1)
	# Frame index (after the first stamp): planted slow frames.
	for frame: int in range(1, 141):
		var interval: int = FRAME_US
		var script: int = 2000
		var gpu: float = 3.0
		var view_key: String = "first_person:me::human"
		match frame:
			20:
				interval = 60000
				compiles += 2
			40:
				interval = 40000
				script = 30000
				# A poll inside the slow interval took most of it.
				trace.record_poll(now + 1000, 25000, 3, 4000)
			60:
				interval = 40000
				gpu = 35.0
			80:
				interval = 40000
				view_key = "third_person:me::human"
		if frame == 61:
			trace.mark("fight", now + 1)
		# Walk at a steady 5 m/s along x.
		x += 5.0 * float(interval) / 1000000.0
		trace.note_view(now + interval - 100, view_key, Vector4(x, 1.6, 0.0, 0.0), 1 if frame == 30 else 0)
		now += interval
		trace.record_frame(now, script, 1.0, gpu, compiles)
	# Snapshots every 50 ms, ticks 100 upward, with planted gaps.
	var server: Dictionary = {}
	var at: int = T0 + 10000
	var tick: int = 100
	for index: int in range(40):
		var gap: int = 50000
		var step: int = 1
		match index:
			5:
				gap = 150000
				step = 2
			10:
				gap = 100000
			15:
				gap = 100000
			20:
				gap = 100000
		if index > 0:
			at += gap
			tick += step
		trace.record_snapshot(tick, at, 300)
		var record: Dictionary = {"tick": tick, "unix_us": UNIX0 + (at - T0) - 2000, "late_us": 100, "skipped": 0,
			"sim_us": 900, "measure_us": 50, "fanout_us": 60, "total_us": 1200, "clients": 1, "messages": 3,
			"bytes": 2000, "overflows": 0}
		if index == 5:
			record["skipped"] = 1
		if index == 10:
			record["late_us"] = 30000
		server[tick] = record
	# Index 15 arrives after the 60 ms compile frame? No: plant a client hitch
	# that spans it by placing a slow frame across that window below.
	trace.correction_usec.append_array(PackedInt64Array([T0 + 5000, T0 + 6000]))
	trace.correction_tick.append_array(PackedInt64Array([100, 101]))
	trace.correction_m.append_array(PackedFloat32Array([0.01, 0.2]))
	trace.correction_offset_m.append_array(PackedFloat32Array([0.0, 0.0]))
	var saved: Dictionary = trace.stop(now)
	return {"client": saved, "server": {"error": "", "header": {}, "ticks": server, "complete": {}}}


func _check_report_attribution() -> void:
	var data: Dictionary = _synthetic()
	var client: Dictionary = data["client"]
	var server: Dictionary = data["server"]
	var report: Dictionary = StutterReport.analyze(client, server)
	_check(str(report["error"]).is_empty(), "a synthetic session analyses: " + str(report["error"]))
	var frames: Dictionary = report["session"]["frames"]
	_check(int(frames["count"]) == 140 and is_equal_approx(float(report["median_frame_ms"]), 16.67), "the median frame is the ordinary interval")
	_check(int(frames["spikes"]) == 4 and int(frames["hitches"]) == 1, "four planted slow frames, one past 50 ms")
	var causes: Dictionary = frames["causes"]
	_check(int(causes.get("pipeline_compile", 0)) == 1, "the compile frame is attributed to pipeline compilation")
	_check(int(causes.get("network_apply", 0)) == 1 and not causes.has("script"), "the slow poll is attributed to network apply, not generic script")
	_check(int(causes.get("render", 0)) == 1, "the slow GPU frame is attributed to render")
	_check(int(causes.get("unattributed", 0)) == 1 and int(causes.get("camera_change", 0)) == 1,
		"a slow frame with no measured stage stays unattributed, tagged with the camera change inside it")
	_check(float(frames["worst"][0]["interval_ms"]) == 60.0, "the worst frames are listed slowest first")
	var snaps: Dictionary = report["session"]["snapshots"]
	_check(int(snaps["count"]) == 40 and int(snaps["gaps"]) == 4 and int(snaps["missing_ticks"]) == 1, "four late Snapshots and one missing tick")
	var gap_causes: Dictionary = snaps["causes"]
	_check(int(gap_causes.get("server_skipped", 0)) == 1, "a tick the server never produced is a server skip")
	_check(int(gap_causes.get("server_stall", 0)) == 1, "a late server handler is a server stall")
	_check(int(gap_causes.get("delivery", 0)) == 2, "on-time server ticks with no client hitch are delivery delay")
	_check(int(snaps["delivery_samples"]) == 40 and is_equal_approx(float(snaps["same_clock_delivery_p50_ms"]), 0.8),
		"same-clock delivery joins every tick: arrival minus server send")
	var corrections: Dictionary = report["session"]["corrections"]
	_check(int(corrections["count"]) == 2 and int(corrections["visible"]) == 1 and is_equal_approx(float(corrections["max_m"]), 0.2),
		"correction size and the visible count")
	_check(int(report["session"]["camera_changes"]) == 3, "entering, leaving and returning to first person are three changes")
	_check(int(report["session"]["remote_starved_frames"]) == 1, "a starved remote frame is counted")
	var speed: Dictionary = report["session"]["camera_speed"]
	_check(is_equal_approx(float(speed["p5"]), 5.0) and is_equal_approx(float(speed["p95"]), 5.0),
		"steady walking reads as a single camera speed through every frame time")
	var main: Dictionary = report["session"]["main_thread"]
	# 139 frames at 2 ms plus one at 30 ms of script; one 25 ms poll; 40 x 0.3 ms handlers.
	var span_us: float = float(int(client["stopped_usec"]) - int(client["started_usec"]))
	_check(is_equal_approx(float(main["script_share"]), snappedf((139.0 * 2000.0 + 30000.0) / span_us, 0.001))
		and is_equal_approx(float(main["receive_share"]), snappedf(25000.0 / span_us, 0.001))
		and is_equal_approx(float(main["snapshot_handler_share"]), snappedf(12000.0 / span_us, 0.001))
		and int(main["max_messages_per_poll"]) == 3 and int(main["polls_over_two_messages"]) == 1,
		"the main thread budget splits script, receive and Snapshot handler time: " + str(main))
	var teleported: Dictionary = client.duplicate(true)
	teleported["frames"]["camera"][100 * 4] = float(teleported["frames"]["camera"][100 * 4]) + 100.0
	var moved: Dictionary = StutterReport.analyze(teleported, server)["session"]["camera_speed"]
	_check(int(moved["jumps"]) == 2 and is_equal_approx(float(moved["p95"]), 5.0),
		"a teleport and its return are counted as jumps, not as walking speed")
	var phases: Array = report["phases"]
	_check(phases.size() == 2 and phases[0]["label"] == "walk" and phases[1]["label"] == "fight", "marks split the session into phases")
	_check(int(phases[0]["frames"]["spikes"]) == 3 and int(phases[1]["frames"]["spikes"]) == 1, "each phase keeps its own spikes")
	var server_window: Dictionary = report["session"]["server"]
	_check(int(server_window["joined"]) == 40 and float(server_window["late_max_ms"]) == 30.0 and int(server_window["skipped"]) == 1,
		"server timing joins every tick between the first and last Snapshot")
	var rows: PackedStringArray = StutterReport.table(report)
	_check(rows.size() == 2 + phases.size() + 1 and rows[rows.size() - 1].begins_with("| whole session |"), "the table has one row per phase and a session total")
	# A client hitch spanning a late Snapshot is blamed on the client frame.
	var slow: Dictionary = client.duplicate(true)
	var snapshot_at: Array = slow["snapshots"]["usec"]
	var frame_at: Array = slow["frames"]["usec"]
	var gap_start: int = int(snapshot_at[14])
	var gap_end: int = int(snapshot_at[15])
	for index: int in range(frame_at.size()):
		if int(frame_at[index]) > gap_start and int(frame_at[index]) >= gap_end:
			slow["frames"]["interval_us"][index] = int(frame_at[index]) - gap_start
			break
	var hitched: Dictionary = StutterReport.analyze(slow, server)
	_check(int(hitched["session"]["snapshots"]["causes"].get("client_frame", 0)) >= 1,
		"a late arrival behind a slow client frame is the client's frame, not the network")
	var alone: Dictionary = StutterReport.analyze(client)
	_check(int(alone["session"]["snapshots"]["causes"].get("unknown", 0)) == 3 and int(alone["session"]["snapshots"]["causes"].get("missing_ticks", 0)) == 1
		and alone["session"]["server"]["joined"] == 0 and not alone["server_joined"],
		"without a server trace, late Snapshots are unknown rather than guessed")


## A throttled window draws about once a second. No frame is a spike against
## that median, yet every late Snapshot still waited for the next frame's poll.
func _check_slow_median_gaps() -> void:
	var trace: StutterTrace = StutterTrace.new()
	trace.begin(0, UNIX0)
	trace.record_frame(0, -1, 0.0, 0.0, 0)
	for frame: int in range(1, 6):
		trace.record_frame(frame * 1000000, 100, 0.0, 0.0, 0)
		trace.record_snapshot(frame * 20, frame * 1000000 + 10, 100)
	var report: Dictionary = StutterReport.analyze(trace.stop(6000000))
	var snapshots: Dictionary = report["session"]["snapshots"]
	_check(int(report["session"]["frames"]["spikes"]) == 0 and int(snapshots["gaps"]) == 4
		and int(snapshots["causes"].get("client_frame", 0)) == 4,
		"gaps behind second-long frames are the client's frames even when no frame is a spike: " + str(snapshots["causes"]))


func _check_report_refuses_malformed_input() -> void:
	var client: Dictionary = _synthetic()["client"]
	var cases: Dictionary = {}
	var wrong_version: Dictionary = client.duplicate(true)
	wrong_version["version"] = 2
	cases["wrong version"] = wrong_version
	var short: Dictionary = client.duplicate(true)
	(short["frames"]["script_us"] as Array).pop_back()
	cases["frame lists differ"] = short
	var backwards: Dictionary = client.duplicate(true)
	backwards["frames"]["usec"][3] = 0
	cases["frames go back"] = backwards
	var camera: Dictionary = client.duplicate(true)
	(camera["frames"]["camera"] as Array).pop_back()
	cases["camera length"] = camera
	var text: Dictionary = client.duplicate(true)
	text["snapshots"]["tick"][0] = "100"
	cases["text tick"] = text
	var event: Dictionary = client.duplicate(true)
	(event["events"] as Array).append({"kind": "mark"})
	cases["event without time"] = event
	var missing: Dictionary = client.duplicate(true)
	missing.erase("polls")
	cases["missing group"] = missing
	for name: String in cases:
		_check(not str(StutterReport.analyze(cases[name]).get("error", "")).is_empty(), "refuses a client trace with " + name)
	var bad_server: Dictionary = {"error": "line 2: ticks must increase", "ticks": {}}
	_check(str(StutterReport.analyze(client, bad_server)["error"]).begins_with("server trace:"), "a failed server read is not silently ignored")


func _check_remote_starvation() -> void:
	var presentation: RemotePresentation = RemotePresentation.new()
	presentation.accept(10, Vector3.ZERO, 0.0, 0.0, true, 500000)
	presentation.accept(11, Vector3.ONE, 0.0, 0.0, true, 550000)
	presentation.sample(560000)
	_check(not presentation.starved, "inside the buffer the pawn interpolates")
	presentation.sample(900000)
	_check(presentation.starved, "past the newest Snapshot the pawn holds and is starved")
	presentation.reset()
	_check(not presentation.starved, "reset clears starvation")


func _check_overlay_feeds_trace() -> void:
	var overlay: PerformanceOverlay = PerformanceOverlay.new()
	root.add_child(overlay)
	_check(not overlay.is_processing() and overlay.process_priority == PerformanceOverlay.FIRST_PRIORITY,
		"an off counter is idle and ordered first")
	overlay.set_tracing(true)
	_check(not overlay.tracing() and not overlay.is_processing(), "tracing without a trace stays off")
	var trace: StutterTrace = StutterTrace.new()
	overlay.trace = trace
	overlay.set_tracing(true)
	_check(overlay.tracing() and overlay.is_processing() and not overlay.visible, "tracing runs the hidden counter")
	for frame: int in range(4):
		await process_frame
	_check(trace.frame_usec.is_empty(), "frames reach only a recording trace")
	trace.begin(Time.get_ticks_usec(), UNIX0)
	for frame: int in range(6):
		await process_frame
	_check(trace.frame_usec.size() >= 4, "a recording trace receives drawn frames")
	var spans: Array = Array(trace.frame_script_us).slice(1)
	_check(spans.all(func(value: int) -> bool: return value >= 0), "the end marker bounds every later frame's script span")
	overlay.set_tracing(false)
	var count: int = trace.frame_usec.size()
	for frame: int in range(3):
		await process_frame
	_check(trace.frame_usec.size() == count and not overlay.is_processing(), "stopping tracing stops the frames and the counter")
	overlay.free()


func _check_console_and_manager_paths() -> void:
	var console: FragrConsole = FragrConsole.new()
	root.add_child(console)
	console.run("stutter start")
	_check(console._lines.back().contains("no match"), "the boot menu has no match to record")
	console.free()
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var lines: PackedStringArray = manager.stutter_command([] as Array[String])
	_check(lines[0] == "stutter trace off", "status reports an idle trace")
	lines = manager.stutter_command(["mark", "walk"] as Array[String])
	_check(lines[0] == "no stutter trace is recording", "a mark needs a recording")
	lines = manager.stutter_command(["stop"] as Array[String])
	_check(lines[0] == "no stutter trace is recording", "stop needs a recording")
	lines = manager.stutter_command(["sideways"] as Array[String])
	_check(lines[0].begins_with("usage:"), "an unknown verb prints usage")
	manager.free()
