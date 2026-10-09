extends "res://scripts/qa_tour.gd"

## Canonical finite carry and ordinary mission inputs, observing named skin only.
var _owned: LocalMatch
var _mission: String = ""
var _eligible: bool = false
var _samples: Array[Dictionary] = []
var _frames: Array[Dictionary] = []
var _last_sample_ms: int = -1000
var _last_frame_ms: int = -1000
var _capturing: bool = false

func _run() -> void:
	var directory: String = OS.get_environment("FRAGR_QA_DIR")
	_mission = OS.get_environment("FRAGR_EDDA_MISSION")
	var carry: String = OS.get_environment("FRAGR_EDDA_CARRY")
	if not directory.is_absolute_path() or _mission not in ["m09", "m10"] or carry not in ["eligible", "omitted"]:
		push_error("edda_live_tour: absolute output, m09/m10 and eligible/omitted carry required")
		quit(1)
		return
	_eligible = carry == "eligible"
	var directory_run: String = directory.path_join("run")
	if DirAccess.make_dir_recursive_absolute(directory_run) != OK or not _write_fixture(directory_run):
		quit(1)
		return
	OS.set_environment("FRAGR_RUN_DIR", directory_run)
	_owned = LocalMatch.for_tree(self)
	if not _owned.start_mission("standard", "resume", MissionState.M09_ID if _mission == "m09" else MissionState.M10_ID):
		push_error("edda_live_tour: owned saved-run promotion refused")
		quit(1)
		return
	var deadline: int = Time.get_ticks_msec() + 25000
	while _owned.state == LocalMatch.State.STARTING and Time.get_ticks_msec() < deadline:
		await process_frame
	if _owned.state != LocalMatch.State.RUNNING:
		push_error("edda_live_tour: child did not become ready")
		_owned.stop()
		quit(1)
		return
	set_meta("fragr_boot", {"mode":"campaign", "host":_owned.url, "run_mode":"resume", "play_arrival":true})
	await super._run()

func _load_manifest() -> Dictionary:
	var path: String = "res://qa/m09_passenger_manifest.json" if _mission == "m09" else "res://qa/m10_common_carrier.json"
	var tour: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	if not _eligible:
		tour.states = tour.states.slice(0, 2)
	elif _mission == "m09":
		# Same player position and input route. Look at the actual office start,
		# then retain a timed view of autonomous departure after ordinary Use.
		var review: Dictionary = {"name":"m09_edda_player_height", "camera":"first_person", "look_at":[-27, 5.0, -21], "strip_frames":8, "strip_interval_seconds":0.15}
		tour.states.insert(10, review)
		tour.states.insert(9, {"name":"m09_edda_calm_player_height", "camera":"first_person", "look_at":[-27, 5.0, -21]})
	else:
		var review: Dictionary = {"name":"m10_edda_player_height", "camera":"first_person", "look_at":[2, 5.8, -14], "strip_frames":4, "strip_interval_seconds":0.2}
		tour.states.insert(2, review)
	return tour

func _edda() -> CivilianFigure:
	var game: Node = _game_manager()
	if game == null:
		return null
	if game.current_map_id == 1009 and game.m09_berth != null:
		return game.m09_berth._crew.get("edda") as CivilianFigure
	if game.current_map_id == 1010 and game.m10_ship != null:
		return game.m10_ship._figures.get("edda") as CivilianFigure
	return null

func _process(delta: float) -> bool:
	super._process(delta)
	var now: int = Time.get_ticks_msec()
	if paused or now - _last_sample_ms < 50 or _samples.size() >= 12000:
		return false
	var game: Node = _game_manager()
	var figure: CivilianFigure = _edda()
	if game == null or figure == null or figure.skin == null:
		return false
	_last_sample_ms = now
	var rig: Skeleton3D = figure.skin.skeleton
	var leg: Quaternion = rig.get_bone_pose_rotation(rig.find_bone("LeftLeg"))
	var row: Dictionary = {"tick":game.latest_snapshot.get("tick", 0), "feet":[figure.position.x, figure.position.y, figure.position.z], "walked":figure._walked, "moving_age":figure._moving_age, "leg_rotation":[leg.x, leg.y, leg.z, leg.w]}
	_samples.append(row)
	if not _capturing and _frames.size() < 96 and now - _last_frame_ms >= 200 and figure._moving_age < 0.15:
		_last_frame_ms = now
		_capturing = true
		_capture_motion.call_deferred(row.duplicate(true))
	return false

func _capture_motion(row: Dictionary) -> void:
	await RenderingServer.frame_post_draw
	if _out_dir.is_empty() or _game_manager() == null:
		_capturing = false
		return
	var image: Image = _grab()
	var filename: String = "edda_motion_%03d.png" % _frames.size()
	if image == null or image.save_png(_out_dir.path_join(filename)) != OK:
		_failed = true
	else:
		row["file"] = filename
		_frames.append(row)
	_capturing = false

func _observed_state() -> Dictionary:
	var report: Dictionary = super._observed_state()
	var facts: Dictionary = report.get(_mission, {})
	var people: Array = facts.get("crew" if _mission == "m09" else "passengers", [])
	var accepted: Array = []
	for person: Dictionary in people:
		if person.id == "edda":
			accepted = person.feet
	var figure: CivilianFigure = _edda()
	if not facts.is_empty():
		if (accepted.size() == 3) != _eligible or (figure != null) != _eligible:
			push_error("edda_live_tour: actual mission cast differs from labelled carry")
			_failed = true
		if figure != null:
			if figure.skin == null or figure.skin.kind != "edda" or figure.strip != null or accepted.size() != 3 or figure.position.distance_to(Vector3(accepted[0], accepted[1], accepted[2])) > 0.00001:
				push_error("edda_live_tour: named skin or accepted feet mismatch")
				_failed = true
			report["live_edda"] = {"source":SkinnedCharacter.SOURCES.edda, "feet":accepted, "walked":figure._walked, "moving_age":figure._moving_age}
		else:
			report["live_edda"] = {"present":false}
	return report

func _write_manifest(tour: Dictionary) -> void:
	super._write_manifest(tour)
	var file: FileAccess = FileAccess.open(_out_dir.path_join("live-edda.json"), FileAccess.WRITE)
	if file == null:
		_failed = true
		return
	file.store_string(JSON.stringify({"schema":1, "mission":_mission, "carry":"eligible" if _eligible else "omitted", "scope":"labelled historical finite carry, canonical native promotion, ordinary input; frames may be off-camera", "native_sha256":_owned.server_sha256, "source_sha256":FileAccess.get_sha256(SkinnedCharacter.SOURCES.edda), "samples":_samples, "motion_frames":_frames}, "\t") + "\n")
	file.close()

func _retire_scene() -> void:
	if _eligible:
		var travelled: bool = false
		var skin_moved: bool = false
		var rested: bool = false
		for row: Dictionary in _samples:
			travelled = travelled or row.walked > 0.01
			rested = rested or row.moving_age >= 0.15
			if not _samples.is_empty():
				var first: Array = _samples[0].leg_rotation
				var current: Array = row.leg_rotation
				skin_moved = skin_moved or absf(Quaternion(first[0], first[1], first[2], first[3]).dot(Quaternion(current[0], current[1], current[2], current[3]))) < 0.9999
		if _samples.is_empty() or not rested or (_mission == "m09" and (not travelled or not skin_moved)) or (_mission == "m10" and travelled):
			push_error("edda_live_tour: ordinary skin samples lack required movement/rest contract")
			_failed = true
	await super._retire_scene()
	_owned.stop()
	var deadline: int = Time.get_ticks_msec() + 5000
	while _owned.state == LocalMatch.State.STOPPING and Time.get_ticks_msec() < deadline:
		await process_frame
	if _owned.state != LocalMatch.State.IDLE:
		push_error("edda_live_tour: owned child did not retire")
		_failed = true
	else:
		print("edda_live_tour: owned child IDLE; ", "FAIL" if _failed else "PASS")

func _write_fixture(directory: String) -> bool:
	var hash: Array[int] = []
	var map_path: String = "res://../server/maps/m08_custodian_of_record.json" if _mission == "m09" else "res://../server/maps/m09_passenger_manifest.json"
	for byte: int in FileAccess.get_sha256(map_path).hex_decode():
		hash.append(byte)
	var fixture: Dictionary = {"version":9 if _mission == "m09" else (12 if _eligible else 11), "id":"40000000-0000-4000-8000-00000000edda", "starting_continues":3, "remaining_continues":1, "level_start_continues":1, "body":"synthetic", "rules":{"difficulty":"standard", "revision":3}, "content_sha256":hash,
		"m03_outcome":{"liberated_cars":["roof_car"]}, "m04_outcome":{"rescued_patients":["edda_team_a"] if _eligible or _mission == "m10" else [], "photos_completed":2},
		"m05_outcome":{"released_workers":["splice", "workshop_agent_a", "workshop_agent_b"], "evacuated_workers":["splice"]}, "m06_outcome":{"prisoner_route_marked":true},
		"step":{"kind":"awaiting_mission", "completed_mission":"custodian_of_record" if _mission == "m09" else "passenger_manifest", "next_mission":"passenger_manifest" if _mission == "m09" else "common_carrier",
			"exit":{"hp":39, "armor":17, "equipment":{"selected":"sniper", "weapons":["fists", "flechette", "scatter", "sniper"], "ammo":[{"pool":"bullets", "rounds":76}, {"pool":"shells", "rounds":32}, {"pool":"cells", "rounds":1}], "grenades":2, "proximity_mines":3, "personal_claims":["cold_cabinet"]}}}}
	if _mission == "m10":
		fixture.m08_outcome = {"kind":"recorded", "custody_released":true, "recovered_mind_secured":true, "captives_evacuated":true}
		if _eligible:
			fixture.m09_outcome = {"kind":"recorded", "released_crew":["tern", "berth_crew_a", "berth_crew_b", "edda", "splice"], "aboard_at_departure":[]}
	var source: String = JSON.stringify(fixture) + "\n  \n"
	for filename: String in [directory.path_join("run.json"), directory.get_base_dir().path_join("historical-input.json")]:
		var file: FileAccess = FileAccess.open(filename, FileAccess.WRITE)
		if file == null or not file.store_string(source):
			return false
		file.close()
	return true
