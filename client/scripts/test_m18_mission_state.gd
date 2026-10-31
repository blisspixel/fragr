extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000001818"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m18_mission_state: " + message)

static func fixture_map() -> Dictionary:
	var solids: Array = [
		{"min_x": -38.0, "max_x": -34.0, "min_z": 1.0, "max_z": 4.0, "bottom": 0.0, "top": 1.1},
		{"min_x": 32.0, "max_x": 36.0, "min_z": -2.0, "max_z": 2.0, "bottom": 6.0, "top": 7.1},
		{"min_x": 60.0, "max_x": 62.0, "min_z": -4.0, "max_z": 4.0, "bottom": 4.5, "top": 9.0},
		{"min_x": 66.0, "max_x": 70.0, "min_z": -36.0, "max_z": 36.0, "bottom": 0.0, "top": 9.0},
	]
	var decorations: Array = [
		{"solid": 0, "face": "north", "center": [0, 0.2], "size": [1.0, 0.6], "kind": "terminal"},
		{"solid": 1, "face": "north", "center": [0, 0.2], "size": [1.5, 0.6], "kind": "terminal"},
		{"solid": 2, "face": "west", "center": [0, 0.2], "size": [1.2, 0.8], "kind": "terminal"},
	]
	var depot_station: Dictionary = {"decoration": 0, "approach": [-36.0, 0.0, 0.0]}
	var overlook_console: Dictionary = {"decoration": 1, "approach": [34.0, 6.0, -3.0]}
	var departure: Dictionary = {"decoration": 2, "approach": [61.0, 4.5, 0.0]}
	var objectives: Array = [
		{"id": "aid_checkin", "action": {"kind": "use", "target": depot_station}},
		{"id": "square_defense", "action": {"kind": "arrival", "region": {"min": [-50.0, 0.0, -20.0], "max": [-25.0, 4.0, 20.0]}, "feet": [-35.0, 0.0, 0.0]}},
		{"id": "collector_breach", "action": {"kind": "arrival", "region": {"min": [-18.0, 0.0, -10.0], "max": [4.0, 4.0, 10.0]}, "feet": [-8.0, 0.0, 0.0]}},
		{"id": "service_ascent", "action": {"kind": "arrival", "region": {"min": [10.0, 0.0, 12.0], "max": [26.0, 6.0, 28.0]}, "feet": [18.0, 3.0, 20.0]}},
		{"id": "overlook_recon", "action": {"kind": "use", "target": overlook_console}},
		{"id": "concourse_evac", "action": {"kind": "arrival", "region": {"min": [50.0, 4.5, -12.0], "max": [64.0, 8.0, 12.0]}, "feet": [58.0, 4.5, 0.0]}},
	]
	return {
		"type": "map_info",
		"map_id": 1018,
		"map_name": "All Systems Normal",
		"geometry_version": 2,
		"half_extent": 70.0,
		"solids": solids,
		"presentation": {
			"ground": "concrete",
			"solids": ["concrete", "records_tile", "service_steel", "concrete"],
			"decorations": decorations,
		},
		"m18": {
			"objectives": objectives,
			"departure": departure,
			"boarding": {"min": [60.0, 4.5, -4.0], "max": [66.0, 8.0, 4.0]},
			"depot_station": depot_station,
			"overlook_console": overlook_console,
			"roadblock_active": false,
			"concourse_evac_completed": false,
		}
	}

static func fixture_state(info: Dictionary, stage: int = 0, tick: int = 10) -> Dictionary:
	var order: Array[String] = M18MissionState.OBJECTIVES.duplicate()
	order.append("party_departed")
	var challenges: Dictionary = {
		"aid_delivered": stage >= 1,
		"square_defended": stage >= 2,
		"collector_neutralized": stage >= 3,
		"overlook_witnessed": stage >= 5,
		"concourse_secured": stage >= 6,
	}
	var progress: Dictionary = {
		"completed": order.slice(0, stage),
		"challenges": challenges,
		"roadblock_active": stage >= 3,
		"aid_delivered": stage >= 1,
		"overlook_witnessed": stage >= 5,
		"concourse_secured": stage >= 6,
		"brief_completed": M18MissionState.brief_completed(challenges, "standard"),
		"turn_started": 5 if stage >= 1 else null,
	}
	if stage < 6:
		progress["current"] = info["m18"]["objectives"][stage].duplicate(true)
	elif stage == 6:
		progress["current"] = {"id": "party_departed", "action": {"kind": "use", "target": info["m18"]["departure"].duplicate(true)}}
	return {
		"type": "mission",
		"tick": tick,
		"state": {
			"id": MissionState.M18_ID,
			"rules": {"difficulty": "standard", "revision": 4},
			"attempt": 1,
			"phase": "departed" if stage == 7 else "in_progress",
			"changed_at": tick,
			"party": [{"id": PLAYER, "name": "Transit runner", "ready": true, "alive": true, "aboard": stage >= 6}],
			"prompts": [],
			"m18": progress,
		}
	}

func _run() -> void:
	var info: Dictionary = fixture_map()
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "fixture transit map crosses client boundary")
	var geometry: Dictionary = MissionState.geometry_for(info)
	_check(geometry.get("id") == MissionState.M18_ID, "geometry_for produces M18 geometry")

	var modified_flags: Dictionary = info.duplicate(true)
	modified_flags["m18"]["roadblock_active"] = true
	modified_flags["m18"]["concourse_evac_completed"] = true
	var modified_flags_geometry: Dictionary = MissionState.geometry_for(modified_flags)
	_check(M18MissionState.same_contract(geometry, modified_flags_geometry), "roadblock and concourse flag changes preserve contract")

	var modified_info: Dictionary = info.duplicate(true)
	modified_info["m18"]["boarding"]["max"][0] += 5.0
	var modified_geometry: Dictionary = MissionState.geometry_for(modified_info)
	_check(not M18MissionState.same_contract(geometry, modified_geometry), "boarding change alters contract")

	for stage: int in range(8):
		var msg: Dictionary = fixture_state(info, stage, 10 + stage * 10)
		var matching: Dictionary = geometry.duplicate(true)
		matching["m18"]["roadblock_active"] = stage >= 3
		matching["m18"]["concourse_evac_completed"] = stage >= 6
		_check(MissionState.validation_error(msg, matching).is_empty(), "valid stage %d validates" % stage)
		if stage >= 3:
			_check(not MissionState.validation_error(msg, geometry).is_empty(), "changed stage waits for matching map")

	var briefing: Dictionary = fixture_state(info, 0, 5)
	briefing["state"]["phase"] = "briefing"
	briefing["state"]["party"] = []
	_check(MissionState.validation_error(briefing, geometry).is_empty(), "briefing state validates")

	var premature_concourse: Dictionary = fixture_state(info, 0, 10)
	premature_concourse["state"]["m18"]["challenges"]["concourse_secured"] = true
	premature_concourse["state"]["m18"]["challenges"]["square_defended"] = false
	_check(not MissionState.validation_error(premature_concourse, geometry).is_empty(), "concourse security without square defense rejected")

	var unturned: Dictionary = fixture_state(info, 1, 10)
	unturned["state"]["m18"]["turn_started"] = null
	_check(not MissionState.validation_error(unturned, geometry).is_empty(), "a delivery without its turn is rejected")
	var early_turn: Dictionary = fixture_state(info, 0, 10)
	early_turn["state"]["m18"]["turn_started"] = 4
	_check(not MissionState.validation_error(early_turn, geometry).is_empty(), "a turn before the delivery is rejected")
	var future_turn: Dictionary = fixture_state(info, 1, 10)
	future_turn["state"]["m18"]["turn_started"] = 11
	_check(not MissionState.validation_error(future_turn, geometry).is_empty(), "a turn ahead of the clock is rejected")

	var presenter: M18Transit = M18Transit.new()
	presenter.configure_map(info)
	var notices: Array[String] = []
	var cues: Array[String] = []
	var hushes: Array[bool] = []
	var lines: Array[String] = []
	var faces: Array[String] = []
	presenter.notice_requested.connect(func(text: String) -> void: notices.append(text))
	presenter.story_cue.connect(func(slot: String) -> void: cues.append(slot))
	presenter.hush.connect(func(on: bool) -> void: hushes.append(on))
	presenter.caption.line_said.connect(func(text: String) -> void: lines.append(text))
	presenter.latch_expression.connect(func(expression: String) -> void: faces.append(expression))
	presenter.apply_state(fixture_state(info, 0, 4)["state"])
	_check(lines == [tr("M18_LATCH_CURSED"), tr("M18_LATCH_CONTRACT")] and hushes.is_empty(), "the morning opens on Latch's joke and no silence")
	presenter.apply_state(fixture_state(info, 1, 10)["state"])
	_check(notices.size() == 1, "presenter fires the delivery notice")
	# The turn on the snapshot clock: the air goes at once, the supervisor
	# calls after the heads come round, the air and Latch come back after.
	presenter.apply_snapshot({"tick": 5.0})
	_check(hushes == [true] and presenter.hushed(), "the turn takes the air at its first tick")
	_check(EnemyView.signal_window == Vector2i(5 + M18Transit.HEADS_TURN_TICKS, 5 + M18Transit.TURN_TICKS), "the bots carry the rhythm from the heads-turn tick")
	presenter.apply_snapshot({"tick": 5.0 + M18Transit.SUPERVISOR_TICKS - 1})
	_check(lines.size() == 2, "nobody speaks before the supervisor notices")
	presenter.apply_snapshot({"tick": 5.0 + M18Transit.SUPERVISOR_TICKS})
	_check(lines.size() == 3 and lines[2] == tr("M18_SUPERVISOR_RESPOND"), "the supervisor gets no answer")
	presenter.apply_snapshot({"tick": 5.0 + M18Transit.TURN_TICKS})
	_check(hushes == [true, false] and not presenter.hushed(), "the air comes back when the turn ends")
	_check(faces == ["concerned"], "Latch looks at the party, concerned, and stays so")
	_check(cues == ["cue-l18"], "the turn's score cue plays after the silence, once")
	_check(lines.slice(3) == [tr("M18_LATCH_ALL_AT_ONCE"), tr("M18_LATCH_STILL_HERE")], "Latch speaks after the turn, and is still Latch")
	_check(EnemyView.signal_window == Vector2i(-1, -1), "the rhythm ends with the turn")
	presenter.apply_snapshot({"tick": 5.0 + M18Transit.TURN_TICKS + 40})
	_check(cues.size() == 1 and hushes.size() == 2, "the turn presents once")
	presenter.apply_state(fixture_state(info, 2, 20)["state"])
	presenter.apply_state(fixture_state(info, 3, 30)["state"])
	presenter.apply_state(fixture_state(info, 5, 50)["state"])
	presenter.apply_state(fixture_state(info, 6, 60)["state"])
	_check(notices.size() == 5, "presenter fires each later notice once")
	# A retry starts the morning over and the turn can play again.
	var retry: Dictionary = fixture_state(info, 0, 70)["state"]
	retry["attempt"] = 2
	presenter.apply_state(retry)
	_check(lines[lines.size() - 2] == tr("M18_LATCH_CURSED"), "a retry starts the morning over")
	_check(faces == ["concerned", ""], "a retry lets Latch's face go")
	presenter.clear_map()
	# A late join past the turn restages nothing of it.
	var late: M18Transit = M18Transit.new()
	late.configure_map(info)
	var late_hush: Array[bool] = []
	late.hush.connect(func(on: bool) -> void: late_hush.append(on))
	late.apply_state(fixture_state(info, 2, 200)["state"])
	late.apply_snapshot({"tick": 200.0})
	_check(late_hush.is_empty() and EnemyView.signal_window == Vector2i(-1, -1), "a late join past the turn stays out of it")
	late.clear_map()
	late.free()
	presenter.free()

	if failures > 0:
		push_error("test_m18_mission_state FAILED with %d failures" % failures)
		quit(1)
	else:
		print("test_m18_mission_state: PASS native facts, transit sequence and concourse departure")
		quit(0)
