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
	await _check_pawn()
	if _failures == 0:
		print("test_remote_presentation: PASS buffered transforms, jitter, stale hold, lifecycle, cadence and live pawn")
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
	_check((middle["position"] as Vector3).distance_to(Vector3(0.125, 0.1, 0.0)) < 0.00001,
		"position uses bracketed ticks at a 100 ms render delay")
	_check(absf(wrapf(float(middle["yaw"]), -PI, PI)) < 0.00001 and absf(float(middle["pitch"])) < 0.00001,
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


func _check_frame_rates() -> void:
	for hz: int in [30, 60, 144]:
		var timeline: RemotePresentation = RemotePresentation.new()
		var next_tick: int = 0
		for frame: int in range(hz + 1):
			var elapsed: float = float(frame) / float(hz)
			var now: int = 1000000 + roundi(elapsed * 1000000.0)
			while next_tick <= floori(elapsed * 20.0 + 0.000001):
				timeline.accept(100 + next_tick, Vector3(float(next_tick) * 0.25, 0, 0),
					float(next_tick) * 0.02, 0.0, true, 1000000 + next_tick * 50000)
				next_tick += 1
			var rendered: Dictionary = timeline.sample(now)
			var expected: float = maxf(0.0, elapsed - 0.1) * 5.0
			_check(absf((rendered["position"] as Vector3).x - expected) < 0.00001,
				"constant movement has the same buffered trajectory at %d Hz, frame %d" % [hz, frame])


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
