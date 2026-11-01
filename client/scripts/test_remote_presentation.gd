extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_remote_presentation: " + message)


func _run() -> void:
	_check_timeline()
	_check_discontinuities()
	_check_frame_rates()
	_check_adaptive_buffer()
	_check_shared_clock()
	_check_golden()
	await _check_pawn()
	if _failures == 0:
		print("test_remote_presentation: PASS buffered transforms, jitter, stale hold, lifecycle, cadence, adaptive buffer, shared clock, Rust golden and live pawn")
	quit(0 if _failures == 0 else 1)


func _check_timeline() -> void:
	var timeline: RemotePresentation = RemotePresentation.new()
	_check(timeline.sample(0).is_empty(), "empty history has no fabricated position")
	_check(timeline.accept(100, Vector3.ZERO, TAU - 0.1, -0.4, true, 1000000), "first state accepted")
	_check(timeline.discontinuity and timeline.sample(1000000)["position"] == Vector3.ZERO,
		"first state snaps instead of flying from the origin")
	timeline.accept(101, Vector3(0.25, 0.2, 0.0), 0.1, 0.4, true, 1050000)
	timeline.accept(102, Vector3(0.5, 0.4, 0.0), 0.3, 0.6, true, 1100000)
	var middle: Dictionary = timeline.sample(1125000)
	# Two ticks at the first frame, narrowed by 0.5 ticks a second since.
	var render: float = 102.5 - (RemotePresentation.START_BUFFER_TICKS - RemotePresentation.NARROW_PER_SECOND * 0.125)
	var weight: float = render - 100.0
	_check(absf(float(middle["tick"]) - render) < 0.00001
		and (middle["position"] as Vector3).distance_to(Vector3(0.25 * weight, 0.2 * weight, 0.0)) < 0.00001,
		"position uses bracketed ticks at the slewing render delay")
	_check(absf(wrapf(float(middle["yaw"]), -PI, PI) - (-0.1 + 0.2 * weight)) < 0.00001
		and absf(float(middle["pitch"]) - (-0.4 + 0.8 * weight)) < 0.00001,
		"yaw follows its shortest arc and pitch shares positional time")
	_check(not timeline.accept(102, Vector3(50, 0, 0), 2.0, 0.0, true, 1130000)
		and not timeline.accept(101, Vector3(50, 0, 0), 2.0, 0.0, true, 1130000),
		"duplicate and older ticks cannot rewrite presentation")
	_check(not timeline.accept(103, Vector3(INF, 0, 0), 0.0, 0.0, true, 1150000)
		and not timeline.accept(103, Vector3.ZERO, NAN, 0.0, true, 1150000)
		and not timeline.accept(-1, Vector3.ZERO, 0.0, 0.0, true, 1150000),
		"invalid transforms and ticks stay outside history")
	_check(timeline.sample(3000000)["position"] == Vector3(0.5, 0.4, 0.0),
		"missing snapshots freeze at the newest fact without extrapolation")
	timeline.reset()
	# Ordered TCP snapshots may arrive in a burst; receive spacing is not sim time.
	for tick: int in range(100, 105):
		var arrival: int = 1000000 + (tick - 100) * 50000
		if tick >= 103:
			arrival = 1250000
		timeline.accept(tick, Vector3(float(tick - 100), 0, 0), 0.0, 0.0, true, arrival)
	_check(is_equal_approx((timeline.sample(1275000)["position"] as Vector3).x, 3.5),
		"burst arrival spacing does not flatten motion between stamped ticks")
	var forward: float = float(timeline.sample(1280000)["tick"])
	_check(float(timeline.sample(1200000)["tick"]) >= forward, "a clock estimate cannot rewind rendered time")
	for tick: int in range(105, 180):
		timeline.accept(tick, Vector3(float(tick - 100), 0, 0), 0.0, 0.0, true,
			1000000 + (tick - 100) * 50000)
	_check(timeline.samples.size() == RemotePresentation.MAX_SAMPLES
		and timeline.arrival_offsets.size() == RemotePresentation.MAX_SAMPLES,
		"both transform and clock histories remain bounded")
	timeline.reset()
	_check(timeline.samples.is_empty() and timeline.arrival_offsets.is_empty(), "MapInfo reset clears both histories")
	_check(timeline.accept(1, Vector3(7, 1.5, 8), 1.0, 0.0, true, 10000000)
		and timeline.sample(10000000)["position"] == Vector3(7, 1.5, 8),
		"explicit reset admits a restarted server tick without old motion")


func _check_discontinuities() -> void:
	var timeline: RemotePresentation = RemotePresentation.new()
	timeline.accept(10, Vector3.ZERO, 0.0, 0.0, true, 1000000)
	timeline.accept(11, Vector3(0.2, 0, 0), 0.0, 0.0, true, 1050000)
	timeline.accept(12, Vector3(0.4, 0, 0), 0.0, 0.0, false, 1100000)
	_check(timeline.discontinuity and timeline.samples.size() == 1
		and timeline.sample(1100000)["position"] == Vector3(0.4, 0, 0), "death snaps to the corpse")
	timeline.accept(13, Vector3(0.6, 0, 0), 0.0, 0.0, true, 1150000)
	_check(timeline.discontinuity and timeline.sample(1150000)["position"] == Vector3(0.6, 0, 0),
		"nearby respawn also snaps instead of reusing the corpse path")
	timeline.accept(14, Vector3(9, 0, 0), 2.0, 0.2, true, 1200000)
	_check(timeline.discontinuity and timeline.sample(1200000)["position"] == Vector3(9, 0, 0), "teleport clears prior motion")
	timeline.accept(30, Vector3(9.2, 0, 0), 2.0, 0.2, true, 2000000)
	_check(timeline.discontinuity and timeline.samples.size() == 1, "long starvation recovers at the latest fact")


## Constant motion at three frame rates draws the same trajectory: the
## buffer slews by wall time, so it is the same at the same moment whatever
## the frame rate, starting at two ticks and narrowing to 1.2.
func _check_frame_rates() -> void:
	for hz: int in [30, 60, 144]:
		var timeline: RemotePresentation = RemotePresentation.new()
		var next_tick: int = 0
		for frame: int in range(hz * 3 + 1):
			var elapsed: float = float(frame) / float(hz)
			var now: int = 1000000 + roundi(elapsed * 1000000.0)
			while next_tick <= floori(elapsed * 20.0 + 0.000001):
				timeline.accept(100 + next_tick, Vector3(float(next_tick) * 0.25, 0, 0),
					float(next_tick) * 0.02, 0.0, true, 1000000 + next_tick * 50000)
				next_tick += 1
			var rendered: Dictionary = timeline.sample(now)
			var buffer: float = maxf(RemotePresentation.MIN_BUFFER_TICKS,
				RemotePresentation.START_BUFFER_TICKS - RemotePresentation.NARROW_PER_SECOND * float(now - 1000000) / 1000000.0)
			var expected: float = maxf(0.0, float(now - 1000000) / 50000.0 - buffer) * 0.25
			_check(absf((rendered["position"] as Vector3).x - expected) < 0.00001,
				"constant movement has the same buffered trajectory at %d Hz, frame %d" % [hz, frame])
			_check(absf(timeline.buffer_ticks - buffer) < 0.000001, "buffer slews by wall time at %d Hz" % hz)


## A steady link settles at 60 ms; a run of late snapshots widens toward two
## ticks without the drawn clock stepping back; calm narrows it again.
func _check_adaptive_buffer() -> void:
	var timeline: RemotePresentation = RemotePresentation.new()
	_check(timeline.target_buffer_ticks() == RemotePresentation.START_BUFFER_TICKS
		and is_nan(timeline.desired_tick(0)), "no arrivals: the safe two ticks and no clock")
	var now: int = 2000000
	var next_tick: int = 0
	var last_view: float = -1.0
	var backward: bool = false
	var widest: float = 0.0
	var at_two_seconds: float = 0.0
	while now < 8000000:
		while true:
			var late: int = 300000 if next_tick == 50 else 0
			var arrival: int = 2000000 + next_tick * 50000 + late
			if next_tick > 50 and next_tick < 56:
				arrival = maxi(arrival, 2000000 + 50 * 50000 + 300000)
			if arrival > now:
				break
			timeline.observe(100 + next_tick, arrival)
			next_tick += 1
		var view: float = timeline.view_tick(now)
		backward = backward or view < last_view
		last_view = view
		if now >= 4000000 and at_two_seconds == 0.0:
			at_two_seconds = timeline.buffer_ticks
		widest = maxf(widest, timeline.buffer_ticks)
		now += 16667
	_check(is_equal_approx(at_two_seconds, RemotePresentation.MIN_BUFFER_TICKS),
		"a steady link draws 1.2 ticks (60 ms) behind: %f" % at_two_seconds)
	_check(widest > 1.9 and widest <= RemotePresentation.MAX_BUFFER_TICKS, "a stall widens toward two ticks: %f" % widest)
	_check(timeline.buffer_ticks < 1.3, "a calm link narrows again: %f" % timeline.buffer_ticks)
	_check(not backward, "slewing never draws time backwards")


## Pawns draw at the shared clock's tick, which is what an Action reports.
func _check_shared_clock() -> void:
	var clock: RemotePresentation = RemotePresentation.new()
	var pawn: RemotePresentation = RemotePresentation.new()
	pawn.clock = clock
	# The pawn's first snapshot came late; the clock knows the early schedule.
	for tick: int in range(10, 40):
		clock.observe(tick, tick * 50000 + 1000)
	pawn.accept(38, Vector3(0, 0, 0), 0.0, 0.0, true, 38 * 50000 + 40000)
	pawn.accept(39, Vector3(1, 0, 0), 0.0, 0.0, true, 39 * 50000 + 1000)
	var now: int = 40 * 50000 + 30000
	var shown: Dictionary = pawn.sample(now)
	var reported: float = clock.view_tick(now)
	_check(absf(float(shown["tick"]) - reported) < 0.000001,
		"a pawn draws at the clock's view tick (%f, %f)" % [float(shown["tick"]), reported])
	pawn.reset()
	_check(pawn.clock == clock, "a pawn reset keeps the shared clock")


## Replays client/golden/presentation_vectors.json from the Rust mirror.
func _check_golden() -> void:
	var file: FileAccess = FileAccess.open("res://golden/presentation_vectors.json", FileAccess.READ)
	if file == null:
		_check(false, "presentation golden opens")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_check(false, "presentation golden is an object")
		return
	var golden: Dictionary = parsed
	_check(int(golden.get("version", 0)) == 1, "presentation golden version 1")
	var constants: Dictionary = golden.get("constants", {})
	_check(int(constants.get("tick_usec", 0)) == RemotePresentation.TICK_USEC
		and float(constants.get("min_buffer_ticks", 0.0)) == RemotePresentation.MIN_BUFFER_TICKS
		and float(constants.get("max_buffer_ticks", 0.0)) == RemotePresentation.MAX_BUFFER_TICKS
		and float(constants.get("start_buffer_ticks", 0.0)) == RemotePresentation.START_BUFFER_TICKS
		and float(constants.get("widen_per_second", 0.0)) == RemotePresentation.WIDEN_PER_SECOND
		and float(constants.get("narrow_per_second", 0.0)) == RemotePresentation.NARROW_PER_SECOND
		and float(constants.get("jitter_quantile", 0.0)) == RemotePresentation.JITTER_QUANTILE
		and int(constants.get("max_samples", 0)) == RemotePresentation.MAX_SAMPLES,
		"presentation golden constants match the client")
	var cases: Array = golden.get("cases", [])
	_check(cases.size() == 4, "presentation golden has its four cases")
	for entry: Variant in cases:
		if not entry is Dictionary:
			_check(false, "presentation golden case is an object")
			continue
		var case: Dictionary = entry
		var name: String = str(case.get("name", "?"))
		var arrivals: Array = case.get("arrivals", [])
		var frames: Array = case.get("frames", [])
		var clock: RemotePresentation = RemotePresentation.new()
		var next: int = 0
		var mismatch: String = ""
		for frame: Variant in frames:
			var row: Array = frame
			var now: int = int(row[0])
			while next < arrivals.size() and int(arrivals[next][1]) <= now:
				clock.observe(int(arrivals[next][0]), int(arrivals[next][1]))
				next += 1
			var view: float = clock.view_tick(now)
			if mismatch.is_empty() and (absf(view - float(row[1])) > 0.000001
					or absf(clock.buffer_ticks - float(row[2])) > 0.000001):
				mismatch = "%s at %d: view %f want %f, buffer %f want %f" % [name, now, view,
					float(row[1]), clock.buffer_ticks, float(row[2])]
		_check(not frames.is_empty() and mismatch.is_empty(), "golden %s replays: %s" % [name, mismatch])


func _check_pawn() -> void:
	var pawn: Node3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(pawn)
	pawn.set_process(false)
	pawn.call("set_player_data", "remote", "Remote")
	var state: Dictionary = {"id": "remote", "name": "Remote", "x": 4.0, "y": 1.5,
		"z": 2.0, "yaw": 0.8, "pitch": 0.2, "hp": 100, "weapon": "Tack"}
	pawn.call("update_state", state, 10)
	_check(pawn.position == Vector3(4, 1.5, 2), "live pawn snaps its first authoritative state")
	state["x"] = 4.25
	state["yaw"] = 1.2
	state["pitch"] = 0.4
	pawn.call("update_state", state, 11)
	pawn.call("_process", 1.0 / 60.0)
	_check(pawn.position.x < 4.25 and float(pawn.get("presentation_yaw")) < 1.2
		and float(pawn.get("presentation_pitch")) < 0.4,
		"live pawn buffers position and aim together instead of adopting fresh aim")
	pawn.call("set_predicted_position", Vector3(8, 1.5, 2), 5.0)
	pawn.call("_process", 1.0 / 60.0)
	_check(pawn.position == Vector3(8, 1.5, 2) and float(pawn.get("presentation_speed")) == 5.0,
		"local prediction has precedence over the remote timeline")
	pawn.call("clear_predicted_position")
	_check(pawn.position == Vector3(4.25, 1.5, 2)
		and (pawn.get("remote_presentation") as RemotePresentation).samples.is_empty(),
		"prediction fallback discards buffered motion before adopting authority")
	state["x"] = 4.5
	state["hp"] = 0
	pawn.call("update_state", state, 12)
	_check(pawn.position == Vector3(4.5, 1.5, 2), "live death never drags the corpse behind")
	state["hp"] = 100
	state["x"] = 4.6
	pawn.call("update_state", state, 13)
	_check(is_equal_approx(pawn.position.x, 4.6), "live nearby respawn snaps immediately")
	pawn.call("reset_remote_presentation")
	_check((pawn.get("remote_presentation") as RemotePresentation).samples.is_empty(),
		"MapInfo integration seam clears live participant history")
	pawn.queue_free()
	await process_frame
