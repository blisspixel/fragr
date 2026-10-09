extends SceneTree

var failures: Array[String] = []
const LOCAL_ID: String = "00000000-0000-0000-0000-000000000001"
const PEER_ID: String = "00000000-0000-0000-0000-000000000002"


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


func _snapshot(at_tick: int, peer_x: float = 1.1, collidable: bool = true) -> Dictionary:
	return {"tick": at_tick, "players": [
		{"id": LOCAL_ID, "name": "Meat", "x": 0.0, "y": 1.5, "z": 0.0, "hp": 100},
		{"id": PEER_ID, "name": "Probe", "x": peer_x, "y": 1.5, "z": 0.0, "hp": 100, "collidable": collidable}]}


func _check_contacts(map: Dictionary) -> void:
	var tangent_pose: Dictionary = MoveStep.make_state(1.0, 0.0, 0.0)
	var tangent_input: Dictionary = _action(1, false)
	tangent_input["right"] = true
	var tangent_obstacles: Dictionary = ActorContact.read_snapshot(_snapshot(100, 2.1), {})
	var tangent_step: Dictionary = {"input": tangent_input, "speed": 5.0, "body_key": LOCAL_ID,
		"blockers": [tangent_obstacles["bodies"][1]]}
	var tangent_arena: Dictionary = {"half": map["half_extent"], "solids": map["solids"].duplicate(true)}
	var kernel: Dictionary = MoveStep.live_step(tangent_pose, tangent_input, 5.0, MoveStep.DT_LIVE, tangent_arena)
	var unchanged: Dictionary = LocalPrediction._contact_step(tangent_pose, tangent_step, tangent_arena)
	_check(unchanged["x"] == kernel["x"] and unchanged["z"] == kernel["z"] and
		unchanged["vx"] == kernel["vx"] and unchanged["vz"] == kernel["vz"],
		"nearby untouched body preserves the kernel endpoint and exact selected velocity")
	var predictor: LocalPrediction = LocalPrediction.new()
	predictor.configure_map(map)
	predictor.accept_ack(_ack(0, 100), 1000000)
	var incoming: Dictionary = _snapshot(100)
	predictor.accept_snapshot(incoming, LOCAL_ID, {}, 1000000)
	incoming["players"][1]["x"] = 8.0
	predictor.record_action(_action(1), 1000001, true)
	_check(absf(float(predictor.state["x"]) - 0.1) < 0.001 and absf(float(predictor.state["vx"]) - 2.0) < 0.02,
		"fresh snapshot blocks approach with actual accepted velocity and isolated source")
	predictor.advance(1050000)
	_check(absf(float(predictor.state["x"]) - 0.1) < 0.001 and absf(float(predictor.state["vx"])) < 0.001,
		"held movement remains outside living peer radius")
	var removed: Dictionary = _snapshot(101)
	removed["players"].pop_back()
	predictor.accept_snapshot(removed, LOCAL_ID, {}, 1050000)
	predictor.accept_ack(_ack(1, 101, 1, 0.1), 1050001)
	_check(predictor.steps.size() == 1 and absf(float(predictor.state["x"]) - 0.1) < 0.001,
		"peer removal does not rewrite already captured speculative replay")
	predictor.advance(1100000)
	_check(absf(float(predictor.state["x"]) - 0.35) < 0.001,
		"new step uses authoritative removal and stops retaining the departed peer")
	var slider: LocalPrediction = LocalPrediction.new()
	slider.configure_map(map)
	slider.accept_ack(_ack(0, 200), 2000000)
	slider.accept_snapshot(_snapshot(200), LOCAL_ID, {}, 2000000)
	var diagonal: Dictionary = _action(1)
	diagonal["right"] = true
	slider.record_action(diagonal, 2000001, true)
	_check(float(slider.state["z"]) > 0.1 and Vector2(float(slider.state["x"]) - 1.1, float(slider.state["z"])).length() >= 0.9999,
		"speculative glancing movement keeps positive tangent progress")
	var inactive: LocalPrediction = LocalPrediction.new()
	inactive.configure_map(map)
	inactive.accept_ack(_ack(0, 300), 3000000)
	inactive.accept_snapshot(_snapshot(300, 1.1, false), LOCAL_ID, {}, 3000000)
	inactive.record_action(_action(1), 3000001, true)
	_check(absf(float(inactive.state["x"]) - 0.25) < 0.001,
		"server noncollidable fact removes a living detached obstacle")
	var stale: LocalPrediction = LocalPrediction.new()
	stale.configure_map(map)
	stale.accept_ack(_ack(0, 400), 4000000)
	stale.accept_snapshot(_snapshot(400), LOCAL_ID, {}, 4000000)
	stale.accept_ack(_ack(0, 401), 4250000)
	stale.record_action(_action(1), 4250001, true)
	_check(not stale.active() and stale.steps.is_empty() and stale.fallback_reason == "contact_stale",
		"stale wall-clock obstacles suspend speculation rather than crossing bodies")
	stale.accept_ack(_ack(0, 402), 4300000)
	_check(not stale.active(), "fresh Ack alone cannot bypass required fresh collision facts")
	stale.accept_snapshot(_snapshot(402), LOCAL_ID, {}, 4300001)
	stale.record_action(_action(1), 4300002, true)
	_check(stale.active() and absf(float(stale.state["x"]) - 0.1) < 0.001,
		"fresh Ack then snapshot resumes bounded contact prediction")
	var old_tick: LocalPrediction = LocalPrediction.new()
	old_tick.configure_map(map)
	old_tick.accept_ack(_ack(0, 510), 5100000)
	old_tick.accept_snapshot(_snapshot(500), LOCAL_ID, {}, 5100000)
	old_tick.record_action(_action(1), 5100001, true)
	_check(not old_tick.active() and old_tick.steps.is_empty(),
		"old server-tick obstacles suspend speculation despite recent arrival")
	for at_tick: int in range(511, 530):
		old_tick.accept_snapshot(_snapshot(at_tick), LOCAL_ID, {}, 5100000)
	_check(old_tick._contact_samples.size() == LocalPrediction.MAX_STEPS + 1,
		"contact snapshot retention is bounded to the speculative horizon")
	old_tick.accept_snapshot(_snapshot(515), LOCAL_ID, {}, 5100000)
	_check(int(old_tick._contact_samples.back()["tick"]) == 529,
		"out-of-order snapshot cannot restore removed old obstacles")
	var invalid: Dictionary = _snapshot(530)
	invalid["players"][1]["collidable"] = "false"
	old_tick.accept_snapshot(invalid, LOCAL_ID, {}, 5100000)
	_check(not old_tick.contact_error.is_empty() and old_tick._contact_samples.is_empty(),
		"invalid collision fact clears guessed blockers and remains observable")
	old_tick.accept_ack(_ack(0, 530), 5300000)
	_check(not old_tick.active(), "invalid snapshot keeps collision requirement through Ack recovery")
	old_tick.accept_snapshot(_snapshot(530), LOCAL_ID, {}, 5300001)
	_check(old_tick.active(), "valid snapshot after fresh Ack recovers an invalid contact boundary")
	var horizon: LocalPrediction = LocalPrediction.new()
	horizon.configure_map(map)
	horizon.accept_ack(_ack(0, 600), 6000000)
	horizon.accept_snapshot(_snapshot(600), LOCAL_ID, {}, 6000000)
	horizon.record_action(_action(1), 6000001, true)
	horizon.advance(6050000)
	horizon.accept_ack(_ack(1, 601, 1, 0.1), 6060000)
	horizon.advance(6100000)
	horizon.advance(6150000)
	_check(not horizon.active() and horizon.fallback_reason == "contact_stale" and horizon.steps.is_empty(),
		"advancing beyond fresh obstacle tick horizon returns to authoritative presentation")
	horizon.accept_snapshot(_snapshot(602), LOCAL_ID, {}, 6150001)
	horizon.accept_ack(_ack(1, 602, 1, 0.1), 6150002)
	_check(horizon.active(), "snapshot-before-Ack packet order also resumes contact prediction")
	for reason: String in ["death", "role", "disconnect"]:
		predictor.accept_snapshot(_snapshot(102), LOCAL_ID, {}, 1100000)
		predictor.reset(reason)
		_check(predictor._contact_samples.is_empty() and predictor._contact_player_id.is_empty() and predictor.steps.is_empty(),
			"contact history clears on " + reason)
	predictor.accept_snapshot(_snapshot(102), LOCAL_ID, {}, 1100000)
	predictor.configure_map(map)
	_check(predictor._contact_samples.is_empty(), "new map clears speculative collision roster")
	var far_bodies: Array[Dictionary] = []
	for index: int in range(64):
		far_bodies.append(ActorContact.stationary(str(index), Vector3(8.0, 0.0, 8.0)))
	far_bodies.append(ActorContact.stationary(PEER_ID, Vector3(1.1, 0.0, 0.0)))
	_check(LocalPrediction._near_contacts(MoveStep.make_state(0.0, 0.0, 0.0), 0.25, far_bodies).size() == 1,
		"far roster is pruned before pairwise speculative resolution")
	var rider: LocalPrediction = LocalPrediction.new()
	var tram: Dictionary = {"min_x": -1.5, "max_x": 1.5, "min_z": 4.0, "max_z": 8.0, "bottom": 0.0, "top": 1.0}
	rider.arena = {"half": 40.0, "solids": [tram]}
	rider._tram_geometry = {"tram_solid": tram, "m05": {"tram": {"solid": 0, "start": [0, 0, 6], "end": [0, 0, 28], "speed": 1.2}}}
	rider._tram_samples = [{"tick": 40, "phase": "moving", "feet": [0, 0, 6]}]
	var pose: Dictionary = MoveStep.make_state(0.0, 6.0, 0.0)
	pose["y"] = 1.0
	var carry_step: Dictionary = {"tick": 41, "input": _action(1), "speed": 5.0, "body_key": LOCAL_ID,
		"blockers": [ActorContact.stationary(PEER_ID, Vector3(1.03, 1.0, 6.06))]}
	var carried_contact: Dictionary = rider._step(pose, carry_step)
	_check(absf(float(carried_contact["x"]) - 0.03) < 0.001 and absf(float(carried_contact["z"]) - 6.06) < 0.001 and float(carried_contact["y"]) == 1.0,
		"tram walking contact starts at carried feet and retains actual moving support")
	carry_step["input"] = _action(1, false)
	carry_step["blockers"] = [ActorContact.stationary(PEER_ID, Vector3(0.0, 1.0, 7.03))]
	var blocked_carry: Dictionary = rider._step(pose, carry_step)
	_check(absf(float(blocked_carry["z"]) - 6.0) < 0.001 and float(blocked_carry["y"]) == 1.0,
		"blocked speculative carry keeps old tram world rather than crossing a static body")


func _initialize() -> void:
	var predictor: LocalPrediction = LocalPrediction.new()
	var map: Dictionary = {"map_id": 1, "geometry_version": 2, "half_extent": 10.0,
		"solids": []}
	_check_contacts(map)
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
	_check(predictor.correction_max_tick == 12 and predictor.correction_max_usec == 1100000 and
		is_equal_approx(predictor.correction_max_server_position.x, 0.3),
		"largest correction retains its authoritative tick, time and position")
	_check(predictor.correction_percentile(0.99) >= predictor.correction_percentile(0.50),
		"bounded correction samples report ordered percentiles")
	predictor.clear_measurements()
	_check(predictor.active() and predictor.correction_count == 0 and predictor.correction_max_tick == -1,
		"diagnostic reset preserves live prediction while clearing prior-window samples")
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
	var delayed: LocalPrediction = LocalPrediction.new()
	delayed.configure_map(map)
	delayed.accept_ack(_ack(10, 100), 10000000)
	delayed.record_action(_action(19), 10000000, false)
	_check(delayed.first_recorded_seq == -1,
		"failed send does not establish a replay history fence")
	delayed.record_action(_action(20), 10000001, true)
	delayed.accept_ack(_ack(11, 101, 1, 0.25), 10050000)
	_check(delayed.active() and delayed.fallback_count == 0 and delayed.ack_seq == 11,
		"late Ack for a pre-tracking Action keeps prediction active")
	delayed.accept_ack(_ack(19, 102, 1, 0.5), 10100000)
	_check(delayed.active() and delayed.fallback_count == 0,
		"successive delayed pre-tracking Acks preserve the bootstrap boundary")
	delayed.accept_ack(_ack(21, 103, 1, 0.75), 10150000)
	_check(not delayed.active() and delayed.fallback_reason == "unknown_seq",
		"unknown Action newer than tracked history still disables replay")
	delayed.configure_map(map)
	delayed.accept_ack(_ack(10, 200), 20000000)
	delayed.record_action(_action(20), 20000001, true)
	delayed.accept_ack(_ack(10, 201, 2), 20050000)
	delayed.record_action(_action(30), 20050001, true)
	delayed.accept_ack(_ack(21, 202, 2), 20100000)
	_check(delayed.active() and delayed.fallback_count == 0,
		"new epoch clears the old sample fence before delayed Acks")
	delayed.configure_map(map)
	delayed.accept_ack(_ack(4294967290, 300), 30000000)
	delayed.record_action(_action(2), 30000001, true)
	delayed.accept_ack(_ack(4294967295, 301), 30050000)
	_check(delayed.active() and delayed.fallback_count == 0,
		"delayed pre-tracking Ack crosses Action sequence wrap")
	delayed.accept_ack(_ack(3, 302), 30100000)
	_check(not delayed.active() and delayed.fallback_reason == "unknown_seq",
		"unknown wrapped Action newer than history still disables replay")
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
	var smooth: LocalPrediction = LocalPrediction.new()
	smooth.configure_map(map)
	smooth.accept_ack(_ack(0, 70), 7000000)
	smooth.record_action(_action(1), 7000001, true)
	var committed_steps: int = smooth.steps.size()
	var committed_x: float = smooth.presented_position().x
	_check(is_equal_approx(smooth.presented_position(7000001).x, committed_x),
		"the first render sample starts on the committed pose")
	var midway: float = smooth.presented_position(7025001).x
	_check(midway > committed_x + 0.1 and midway < committed_x + 0.15,
		"walking advances inside the open tick")
	_check(smooth.steps.size() == committed_steps and is_equal_approx(smooth.presented_position().x, committed_x),
		"render samples do not record a speculative step")
	var crouch: LocalPrediction = LocalPrediction.new()
	crouch.configure_map(map)
	crouch.accept_ack(_ack(0, 72), 7200000)
	var ducked_action: Dictionary = _action(1)
	ducked_action["duck"] = true
	crouch.record_action(ducked_action, 7200001, true)
	_check(absf(float(crouch.state["x"]) - 5.0 * MoveStep.DUCK_SPEED_SCALE * MoveStep.DT_LIVE) < 0.02,
		"a ducked step is the short walk")
	_check(crouch.presented_ducking(7200001), "the render pose starts short")
	crouch.record_action(_action(2), 7250001, true)
	_check(not bool(crouch.state.get("ducking", true)), "release in the open stands")
	var blocked: LocalPrediction = LocalPrediction.new()
	blocked.configure_map(cover)
	blocked.accept_ack(_ack(0, 71), 7100000)
	blocked.record_action(_action(1), 7100001, true)
	blocked.presented_position(7100001)
	_check(is_equal_approx(blocked.presented_position(7125001).x, 0.0),
		"a blocked render sample stays on the solid")
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
	var contact_net: Node = load("res://scripts/net_client.gd").new()
	contact_net.player_id = LOCAL_ID
	manager.net_client = contact_net
	manager._update_prediction_contacts(_snapshot(80))
	_check(manager.local_prediction._contact_samples.size() == 1,
		"manager connects actual snapshot and local identity to contact prediction")
	manager._reset_prediction_for_connection("connected")
	_check(not manager.local_prediction.active() and manager.local_prediction.steps.is_empty()
		and manager._adopt_local_spawn_snapshot and not manager.pending_jump and not manager.pending_interact,
		"automatic resume discards old input before new connection actions")
	_check(manager.local_prediction._contact_samples.is_empty(), "manager connection reset clears captured contacts")
	contact_net.free()
	manager.free()
	if failures.is_empty():
		print("test_local_prediction: PASS")
		quit(0)
	else:
		for failure: String in failures:
			printerr("test_local_prediction: FAIL " + failure)
		quit(1)
