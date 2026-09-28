extends SceneTree

var failures: Array[String] = []


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _ack(seq: int, tick: int, epoch: int = 1, x: float = 0.0, applied: bool = true) -> Dictionary:
	return {"type": "ack", "seq": seq, "tick": tick, "x": x, "z": 0.0, "yaw": 0.0,
		"movement": {"version": 1, "epoch": epoch, "applied": applied, "y": 1.5,
			"vx": 0.0, "vy": 0.0, "vz": 0.0,
			"effective_speed": 5.0 if applied else 0.0, "jump_input": false}}


func _action(seq: int, forward: bool = true, jump: bool = false) -> Dictionary:
	return {"seq": seq, "forward": forward, "back": false, "left": false,
		"right": false, "jump": jump, "yaw": 0.0}


func _initialize() -> void:
	var predictor: LocalPrediction = LocalPrediction.new()
	var map: Dictionary = {"map_id": 1, "geometry_version": 2, "half_extent": 10.0,
		"solids": []}
	predictor.configure_map(map)
	predictor.accept_ack(_ack(0, 10), 1000000)
	_check(predictor.active(), "complete applied Ack enables replay")
	predictor.record_action(_action(1), 1000001, true)
	_check(is_equal_approx(predictor.presented_position().x, 0.25), "first Action predicts one 20 Hz step")
	predictor.record_action(_action(2), 1010000, true)
	_check(predictor.steps.size() == 1 and is_equal_approx(predictor.presented_position().x, 0.25),
		"120 per second samples do not each run a step")
	predictor.advance(1050000)
	_check(predictor.steps.size() == 2 and is_equal_approx(predictor.presented_position().x, 0.5),
		"held input advances once on next speculative tick")
	predictor.accept_ack(_ack(2, 11, 1, 0.25), 1050001)
	_check(predictor.active() and predictor.steps.size() == 1,
		"Ack removes one tick and replays the future tick")
	_check(is_equal_approx(predictor.presented_position().x, 0.5), "matching Ack preserves the presented body")
	predictor.accept_ack(_ack(2, 12, 1, 0.3), 1100000)
	_check(predictor.correction_count == 2 and predictor.correction_max > 0.0,
		"newer tick with repeated selected sequence records correction")
	_check(predictor.correction_percentile(0.99) >= predictor.correction_percentile(0.50),
		"bounded correction samples report ordered percentiles")
	var revised: LocalPrediction = LocalPrediction.new()
	revised.configure_map(map)
	revised.accept_ack(_ack(0, 50), 5000000)
	revised.record_action(_action(1), 5000001, true)
	var reverse: Dictionary = _action(2, false)
	reverse["back"] = true
	revised.record_action(reverse, 5010000, true)
	_check(revised.steps.size() == 1 and is_equal_approx(revised.presented_position().x, -0.25),
		"newer Action revises the pending tick without adding a second step")
	var released: LocalPrediction = LocalPrediction.new()
	released.configure_map(map)
	released.accept_ack(_ack(0, 60), 6000000)
	released.record_action(_action(1, false, true), 6000001, true)
	released.advance(6050000)
	_check(released.steps.size() == 2 and bool(released.steps[0]["input"]["jump"])
		and bool(released.steps[1]["input"]["jump"]), "held jump spans two speculative ticks")
	released.record_action(_action(2, false, false), 6060000, true)
	_check(bool(released.steps[0]["input"]["jump"]) and not bool(released.steps[1]["input"]["jump"]),
		"neutral release clears an inherited jump in the latest tick")
	released.accept_ack(_ack(1, 61), 6060001)
	_check(released.steps.size() == 1 and not bool(released.steps[0]["input"]["jump"]),
		"Ack replay does not restore a consumed held jump")
	predictor.record_action(_action(3, false, true), 1100001, true)
	predictor.record_action(_action(4, false, false), 1105000, true)
	predictor.advance(1150000)
	_check(predictor.steps.size() >= 1, "jump tap remains one speculative tick")
	var jump_count: int = 0
	for step: Dictionary in predictor.steps:
		jump_count += 1 if bool(step["input"]["jump"]) else 0
	_check(jump_count == 1, "jump is not replayed as a held input")
	predictor.accept_ack(_ack(4, 13, 2), 1150001)
	_check(predictor.steps.is_empty() and predictor.visual_offset == Vector3.ZERO,
		"new epoch clears prior body's speculative path")
	predictor.record_action(_action(5), 1150002, true)
	var measured_before_fallback: int = predictor.correction_count
	predictor.accept_ack(_ack(5, 14, 2, 0.0, false), 1200000)
	_check(not predictor.active() and predictor.fallback_count == 1
		and predictor.fallback_reasons.get("inactive", 0) == 1
		and predictor.correction_count == measured_before_fallback,
		"unapplied Ack records fallback without hiding earlier corrections")
	predictor.accept_ack({"type": "ack", "seq": 4, "tick": 15, "x": 0.0, "z": 0.0, "yaw": 0.0}, 1250000)
	_check(not predictor.active(), "old server Ack keeps snapshot fallback")
	var future: Dictionary = _ack(4, 16)
	future["movement"]["version"] = 2
	predictor.accept_ack(future, 1300000)
	_check(not predictor.active(), "future movement schema keeps snapshot fallback")
	predictor.configure_map(map)
	predictor.accept_ack(_ack(4294967295, 20), 2000000)
	_check(LocalPrediction.newer_sequence(1, 4294967295), "sequence wrap remains forward")
	predictor.record_action(_action(1), 2000001, true)
	_check(predictor.active(), "wrapped Action remains replayable")
	predictor.accept_ack(_ack(2, 21), 2050000)
	_check(not predictor.active() and predictor.fallback_reason == "unknown_seq",
		"unknown newer selected Action disables guessed replay")
	predictor.configure_map(map)
	predictor.accept_ack(_ack(0, 30), 3000000)
	predictor.record_action(_action(1, false, true), 3000001, true)
	predictor.advance(3050000)
	_check(predictor.steps.size() == 2 and bool(predictor.steps[0]["input"]["jump"])
		and bool(predictor.steps[1]["input"]["jump"]),
		"a selected held jump is replayed on consecutive server ticks")
	predictor.advance(3200000)
	_check(not predictor.active(), "missing Acks bound the speculative horizon")
	predictor.configure_map(map)
	predictor.accept_ack(_ack(0, 35), 3500000)
	predictor.record_action(_action(1, false, true), 3500001, true)
	predictor.record_action(_action(2, false, true), 3510000, true)
	predictor.accept_ack(_ack(0, 36), 3550000)
	predictor.record_action(_action(3, false, false), 3550001, true)
	_check(not predictor.steps.is_empty() and bool(predictor.steps[0]["input"]["jump"]),
		"unacknowledged jump remains latched after server selected an older sample")
	var cover: Dictionary = map.duplicate(true)
	cover["solids"] = [{"min_x": 0.45, "max_x": 1.0, "min_z": -1.0, "max_z": 1.0, "top": 4.5}]
	predictor.configure_map(cover)
	predictor.accept_ack(_ack(0, 40), 4000000)
	predictor.record_action(_action(1), 4000001, true)
	_check(is_equal_approx(predictor.presented_position().x, 0.0),
		"local prediction uses the authoritative map solid for collision")
	var camera_script: GDScript = load("res://scripts/spectator_cam.gd")
	var current: Vector3 = Vector3.ZERO
	var eye: Vector3 = Vector3(0.25, 1.6, 0.0)
	_check(camera_script.fp_camera_position(current, eye, 1.0 / 60.0, true) == eye,
		"first-person camera follows the predicted body on this frame")
	_check(camera_script.fp_camera_position(current, eye, 1.0 / 60.0, false).x < eye.x,
		"snapshot fallback keeps the existing camera smoothing")
	predictor.configure_map(map)
	_check(not predictor.active() and predictor.correction_count == 0 and predictor.correction_samples.is_empty(),
		"MapInfo clears replay state and correction measurements")
	var manager: Node = load("res://scripts/game_manager.gd").new()
	manager.is_human_player = true
	manager.local_prediction.configure_map(map)
	manager.local_prediction.accept_ack(_ack(0, 80), 8000000)
	manager.local_prediction.record_action(_action(1), 8000001, true)
	manager.pending_jump = true
	manager.pending_interact = true
	manager._reset_prediction_for_connection("connected")
	_check(not manager.local_prediction.active() and manager.local_prediction.steps.is_empty()
		and manager._adopt_local_spawn_snapshot and not manager.pending_jump and not manager.pending_interact,
		"automatic resume discards old input before new connection actions")
	manager.free()
	if failures.is_empty():
		print("test_local_prediction: PASS")
		quit(0)
	else:
		for failure: String in failures:
			printerr("test_local_prediction: FAIL " + failure)
		quit(1)
