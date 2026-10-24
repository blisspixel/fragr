extends SceneTree

var failures: Array[String] = []
const LOCAL_ID: String = "00000000-0000-0000-0000-000000000001"
const PEER_ID: String = "00000000-0000-0000-0000-000000000002"


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _ack(seq: int, tick: int, epoch: int = 1, x: float = 0.0, applied: bool = true, vx: float = 0.0) -> Dictionary:
	return {"type": "ack", "seq": seq, "tick": tick, "x": x, "z": 0.0, "yaw": 0.0,
		"movement": {"version": 2, "epoch": epoch, "applied": applied, "y": 1.5,
			"vx": vx if applied else 0.0, "vy": 0.0, "vz": 0.0,
			"effective_speed": 5.0 if applied else 0.0, "jump_input": false, "dodge_cooldown": 0}}


## The fighter after `ticks` live ticks of forward from rest at the origin, at
## the 5 m/s these Acks report.
static func _ahead(ticks: int) -> Dictionary:
	var arena: Dictionary = {"half": 10.0, "solids": []}
	var body: Dictionary = MoveStep.make_state(0.0, 0.0, 0.0)
	for _tick: int in range(ticks):
		body = MoveStep.fighter_step(body, MoveStep.make_input(true, false, false, false, 0.0), 5.0, MoveStep.DT_LIVE, arena)
	return body


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
	var kernel: Dictionary = MoveStep.fighter_step(tangent_pose, tangent_input, 5.0, MoveStep.DT_LIVE, tangent_arena)
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
	_check(absf(float(predictor.state["x"]) - (0.1 + float(_ahead(1)["x"]))) < 0.001,
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
	_check(absf(float(inactive.state["x"]) - float(_ahead(1)["x"])) < 0.001,
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


## A closed loop against a model server on a fixed 50 ms grid: `latency` each
## way, frames every `frame_usec` with a small wobble, Actions at most every
## 8.3 ms like GameManager. Rest for three seconds so the clock settles, run
## forward for 0.6 s, release at `release_usec`, and watch the drawn eye.
func _closed_loop_stop(release_usec: int, frame_usec: int, latency: int) -> Dictionary:
	var arena: Dictionary = {"half": 40.0, "solids": []}
	var predictor: LocalPrediction = LocalPrediction.new()
	predictor.configure_map({"map_id": 1, "geometry_version": 2, "half_extent": 40.0, "solids": []})
	var body: Dictionary = MoveStep.make_state(0.0, 0.0, 0.0)
	var server_tick: int = 100
	var tick_usec: int = 1001234
	var sent: Array[Array] = []
	var acks: Array[Array] = [[tick_usec + latency, _loop_ack(0, server_tick, body)]]
	var used_seq: int = 0
	var used_forward: bool = false
	var seq: int = 0
	var last_send: int = -100000
	var now: int = 1000000
	var frame: int = 0
	var last_x: float = 0.0
	var release_x: float = NAN
	var worst_back: float = 0.0
	var peak: float = -1000.0
	while now < release_usec + 500000:
		frame += 1
		var dt: int = frame_usec + ((frame * 7919) % 5 - 2) * 500
		now += dt
		while tick_usec + 50000 <= now:
			tick_usec += 50000
			server_tick += 1
			for entry: Array in sent:
				if int(entry[0]) <= tick_usec and int(entry[1]) > used_seq:
					used_seq = int(entry[1])
					used_forward = bool(entry[2])
			body = MoveStep.fighter_step(body, MoveStep.make_input(used_forward, false, false, false, 0.0), 6.0, MoveStep.DT_LIVE, arena)
			acks.append([tick_usec + latency, _loop_ack(used_seq, server_tick, body)])
		while not acks.is_empty() and int(acks[0][0]) <= now:
			predictor.accept_ack(acks.pop_front()[1], now)
			predictor.presented_position(now)
		var forward: bool = now >= release_usec - 600000 and now < release_usec
		if now - last_send >= 8333 and not predictor.baseline.is_empty():
			seq += 1
			last_send = now
			sent.append([now + latency, seq, forward])
			predictor.record_action({"seq": seq, "forward": forward, "back": false, "left": false,
				"right": false, "jump": false, "yaw": 0.0}, now, true)
		predictor.advance(now)
		predictor.decay_visual(float(dt) / 1000000.0)
		var x: float = predictor.presented_position(now).x
		if now >= release_usec:
			if is_nan(release_x):
				release_x = last_x
			worst_back = minf(worst_back, x - last_x)
			peak = maxf(peak, x)
		last_x = x
	return {"active": predictor.active(), "back": worst_back, "overshoot": peak - float(body["x"]),
		"rest": last_x - float(body["x"]), "corrected": predictor.correction_max}


func _loop_ack(seq: int, at_tick: int, body: Dictionary) -> Dictionary:
	return {"type": "ack", "seq": seq, "tick": at_tick, "x": float(body["x"]), "z": float(body["z"]), "yaw": 0.0,
		"movement": {"version": 2, "epoch": 1, "applied": true, "y": float(body["y"]) + LocalPrediction.FLOOR_OFFSET,
			"vx": float(body["vx"]), "vy": float(body["vy"]), "vz": float(body["vz"]),
			"effective_speed": 6.0, "jump_input": false, "dodge_cooldown": 0}}


func _initialize() -> void:
	var predictor: LocalPrediction = LocalPrediction.new()
	var map: Dictionary = {"map_id": 1, "geometry_version": 2, "half_extent": 10.0,
		"solids": []}
	_check_contacts(map)
	predictor.configure_map(map)
	predictor.accept_ack(_ack(0, 10), 1000000)
	_check(predictor.active(), "complete applied Ack enables replay")
	predictor.record_action(_action(1), 1000001, true)
	var one: float = float(_ahead(1)["x"])
	var two: float = float(_ahead(2)["x"])
	_check(one > 0.1 and one < 0.25, "the first tick from rest is an acceleration, not a jump to top speed")
	_check(is_equal_approx(predictor.presented_position().x, one), "first Action predicts one 20 Hz step")
	predictor.record_action(_action(2), 1010000, true)
	_check(predictor.steps.size() == 1 and is_equal_approx(predictor.presented_position().x, one),
		"120 per second samples do not each run a step")
	predictor.advance(1050000)
	_check(predictor.steps.size() == 2 and is_equal_approx(predictor.presented_position().x, two),
		"held input advances once on next speculative tick")
	var shown_before_ack: Vector3 = predictor.presented_position(1050001)
	predictor.accept_ack(_ack(2, 11, 1, one, true, float(_ahead(1)["vx"])), 1050001)
	_check(predictor.active() and predictor.steps.size() == 1,
		"Ack removes one tick and replays the future tick")
	_check(absf(float(predictor.state["x"]) - two) < 0.0001 and predictor.correction_max < 0.0001
		and predictor.presented_position(1050001).distance_to(shown_before_ack) < 0.0001,
		"matching Ack preserves the predicted and the presented body")
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
	_check(revised.steps.size() == 1 and is_equal_approx(float(revised.state["x"]), -float(_ahead(1)["x"])),
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
	future["movement"]["version"] = 3
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
	var lag: int = LocalPrediction.PRESENT_LAG_USEC
	_check(absf(smooth.presented_position(7000000 + lag).x) < 0.0001,
		"the open tick is drawn from the state it starts at")
	_check(absf(smooth.presented_position(7010000).x) < 0.0001,
		"the eye runs half a tick behind the input clock")
	var midway: float = smooth.presented_position(7025000 + lag).x
	_check(absf(midway - committed_x * 0.5) < 0.0001,
		"walking advances through the open tick on the prediction clock")
	_check(absf(smooth.presented_position(7050000 + lag).x - committed_x) < 0.0001,
		"the tick's end is the committed pose")
	_check(smooth.steps.size() == committed_steps and is_equal_approx(smooth.presented_position().x, committed_x),
		"render samples do not record a speculative step")
	# A later Ack that disagrees moves the drawn eye by an offset that decays,
	# never by a jump.
	var drawn: Vector3 = smooth.presented_position(7050001)
	smooth.accept_ack(_ack(1, 71, 1, committed_x + 0.2, true, 0.0), 7050001)
	_check(smooth.presented_position(7050001).distance_to(drawn) < 0.0001,
		"a correction does not move the drawn eye on its own frame")
	_check(smooth.visual_offset.length() > 0.1, "the correction is held as an offset")
	var held: float = smooth.visual_offset.length()
	smooth.decay_visual(0.066)
	_check(smooth.visual_offset.length() < held * 0.11, "the offset is about gone 66 ms later")
	# A late Ack's arrival is a loose bound on the input cutoff: it never
	# drags the schedule later.
	var clock: LocalPrediction = LocalPrediction.new()
	clock.configure_map(map)
	clock.accept_ack(_ack(0, 90), 9000000)
	clock.record_action(_action(1), 9000001, true)
	clock.accept_ack(_ack(1, 91, 1, float(_ahead(1)["x"]), true, float(_ahead(1)["vx"])), 9080000)
	_check(clock._start_usec(92) <= 9050000 and clock._start_usec(92) >= 9050000 - LocalPrediction.CLOCK_SLEW_USEC,
		"a 30 ms late Ack does not drag the step schedule later")
	# Once an Ack brackets the server's input cutoff between the send times of
	# the Action its tick used and the next one, the schedule follows that.
	var cut: LocalPrediction = LocalPrediction.new()
	cut.configure_map(map)
	cut.accept_ack(_ack(0, 100), 10000000)
	cut.record_action(_action(1), 10000001, true)
	cut.record_action(_action(2), 10040000, true)
	cut.accept_ack(_ack(1, 101, 1, float(_ahead(1)["x"]), true, float(_ahead(1)["vx"])), 10050000)
	_check(cut.clock_base() == (10000001 - 101 * 50000 + 10040000 - 101 * 50000) / 2,
		"the input cutoff bracketed by two sends sets the schedule's target")
	_check(cut._start_usec(102) == 10050000 - LocalPrediction.CLOCK_SLEW_USEC,
		"the schedule slews toward a new target instead of jumping")
	# A release inside the open tick lands the predicted body short of what was
	# already drawn; the eye stands until the body catches up, never backwards.
	var guard: LocalPrediction = LocalPrediction.new()
	guard.configure_map(map)
	guard.accept_ack(_ack(0, 110, 1, 0.0, true, 5.0), 11000000)
	guard.record_action(_action(1), 11000001, true)
	var last_x: float = guard.presented_position(11030000).x
	guard.record_action(_action(2, false), 11030001, true)
	var drawn_peak: float = last_x
	var worst_step: float = 0.0
	for at: int in range(11034001, 11140000, 4000):
		guard.decay_visual(0.004)
		guard.advance(at)
		var x: float = guard.presented_position(at).x
		worst_step = minf(worst_step, x - last_x)
		drawn_peak = maxf(drawn_peak, x)
		last_x = x
	# Only the last centimetre settles back once the body is at rest.
	_check(guard.active() and worst_step > -LocalPrediction.SETTLE_SPEED * 0.004 - 0.0001 and drawn_peak - last_x < 0.015,
		"a release inside the open tick never pulls the eye backwards: step %f, settle %f" % [worst_step, drawn_peak - last_x])
	# A release late in a tick from a full run: the half-tick lag never draws
	# the eye past where the body comes to rest, so nothing settles back.
	var late: LocalPrediction = LocalPrediction.new()
	late.configure_map(map)
	late.accept_ack(_ack(0, 130, 1, 0.0, true, 5.0), 13000000)
	late.record_action(_action(1), 13000001, true)
	late.record_action(_action(2, false), 13045000, true)
	var late_x: float = late.presented_position(13045000).x
	var late_peak: float = late_x
	var late_back: float = 0.0
	for at: int in range(13049000, 13146000, 4000):
		late.decay_visual(0.004)
		late.advance(at)
		var x: float = late.presented_position(at).x
		late_back = minf(late_back, x - late_x)
		late_peak = maxf(late_peak, x)
		late_x = x
	_check(late.active() and late_back > -0.0001 and absf(late_peak - float(late.state["x"])) < 0.001 and absf(late_x - float(late.state["x"])) < 0.001,
		"a late release stops the eye where the body stops: back %f, peak %f, rest %f" % [late_back, late_peak, float(late.state["x"])])
	# Closed loop on a steady link, LAN to 80 ms round trip, 60 to 250 fps,
	# released at every phase of a tick: the input clock puts every press and
	# release in the tick the server uses, and the eye stops where the body
	# stops without stepping back.
	var loop_failures: Array[String] = []
	for latency: int in [500, 20000, 40000]:
		for frame_usec: int in [4000, 16000]:
			for phase: int in range(0, 50000, 5000):
				var loop: Dictionary = _closed_loop_stop(4500000 + phase, frame_usec, latency)
				if not loop["active"] or float(loop["corrected"]) > 0.0001 or float(loop["back"]) < -0.0003 \
						or float(loop["overshoot"]) > 0.0005 or absf(float(loop["rest"])) > 0.0005:
					loop_failures.append("%d/%d/%d %s" % [latency, frame_usec, phase, str(loop)])
	_check(loop_failures.is_empty(), "closed-loop stops land on the server's rest: %s" % str(loop_failures.slice(0, 3)))
	# A correction past the snap distance is a teleport, drawn at once even at
	# rest, never glided at the settle speed.
	var still: LocalPrediction = LocalPrediction.new()
	still.configure_map(map)
	still.accept_ack(_ack(0, 120), 12000000)
	still.record_action(_action(1, false), 12000001, true)
	still.presented_position(12010000)
	still.accept_ack(_ack(1, 121, 1, 3.0), 12050000)
	still.record_action(_action(2, false), 12050001, true)
	_check(absf(still.presented_position(12060000).x - 3.0) < 0.001, "a teleport is drawn at once")
	var crouch: LocalPrediction = LocalPrediction.new()
	crouch.configure_map(map)
	crouch.accept_ack(_ack(0, 72), 7200000)
	var ducked_action: Dictionary = _action(1)
	ducked_action["duck"] = true
	crouch.record_action(ducked_action, 7200001, true)
	_check(absf(float(crouch.state["x"]) - MoveStep.GROUND_ACCEL * MoveStep.DT_LIVE * 5.0 * MoveStep.DUCK_SPEED_SCALE * MoveStep.DT_LIVE) < 0.001,
		"a ducked step is the short walk")
	_check(crouch.presented_ducking(7200001), "the render pose starts short")
	var dodger: LocalPrediction = LocalPrediction.new()
	dodger.configure_map(map)
	dodger.accept_ack(_ack(0, 74), 7400000)
	var dodge_action: Dictionary = _action(1, false)
	dodge_action["right"] = true
	dodge_action["dodge"] = true
	dodger.record_action(dodge_action, 7400001, true)
	_check(absf(float(dodger.state["vz"]) - MoveStep.DODGE_SPEED) < 0.001 and float(dodger.state["vy"]) > 0.0
		and int(dodger.state["dodge_cooldown"]) == MoveStep.DODGE_COOLDOWN_TICKS,
		"a dodge press throws the predicted body and starts the cooldown")
	var again: Dictionary = dodge_action.duplicate()
	again["seq"] = 2
	dodger.record_action(again, 7450000, true)
	_check(not bool(dodger.steps.back()["input"]["dodge"]) or int(dodger.steps.back()["state_after"]["dodge_cooldown"]) == MoveStep.DODGE_COOLDOWN_TICKS - 1,
		"a second press inside the cooldown does not dodge again")
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
