extends "res://scripts/qa_tour.gd"

## Ordinary mission inputs with current named-skin/feet observations.
## M10 starts from the same labelled historical finite-carry fixture as its gate.
var _owned: LocalMatch
var _crew_mission: String = "m09"
var _cast_samples: Array[Dictionary] = []
var _last_cast_ms: int = -1000

func _run() -> void:
	var directory: String = OS.get_environment("FRAGR_QA_DIR")
	_crew_mission = OS.get_environment("FRAGR_LIVE_CREW_MISSION")
	if not directory.is_absolute_path() or _crew_mission not in ["m09", "m10"]:
		push_error("live_crew_tour: absolute output and m09/m10 mission required")
		quit(1)
		return
	var run_directory: String = directory.path_join("run")
	if DirAccess.make_dir_recursive_absolute(run_directory) != OK:
		quit(1)
		return
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	if _crew_mission == "m10" and not _write_carry_fixture(run_directory):
		quit(1)
		return
	_owned = LocalMatch.for_tree(self)
	var mission_id: String = MissionState.M09_ID if _crew_mission == "m09" else MissionState.M10_ID
	var mode: String = "" if _crew_mission == "m09" else "resume"
	if not _owned.start_mission("standard", mode, mission_id):
		push_error("live_crew_tour: owned mission start refused")
		quit(1)
		return
	var deadline: int = Time.get_ticks_msec() + 25000
	while _owned.state == LocalMatch.State.STARTING and Time.get_ticks_msec() < deadline:
		await process_frame
	if _owned.state != LocalMatch.State.RUNNING:
		push_error("live_crew_tour: owned mission did not become ready")
		_owned.stop()
		quit(1)
		return
	set_meta("fragr_boot", {"mode": "campaign", "host": _owned.url, "run_mode": "resume" if _crew_mission == "m10" else "new", "play_arrival": true})
	await super._run()

func _load_manifest() -> Dictionary:
	var path: String = "res://qa/m09_passenger_manifest.json" if _crew_mission == "m09" else "res://qa/m10_common_carrier.json"
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary

func _process(delta: float) -> bool:
	super._process(delta)
	if paused or Time.get_ticks_msec() - _last_cast_ms < 50 or _cast_samples.size() >= 10000:
		return false
	var figure: CivilianFigure = _tern()
	var game: Node = _game_manager()
	if figure != null and figure.skin != null and game != null:
		_last_cast_ms = Time.get_ticks_msec()
		var rig: Skeleton3D = figure.skin.skeleton
		var leg: Quaternion = rig.get_bone_pose_rotation(rig.find_bone("LeftLeg"))
		_cast_samples.append({"tick": game.latest_snapshot.get("tick", 0),
			"feet": [figure.position.x, figure.position.y, figure.position.z],
			"walked": figure._walked, "moving_age": figure._moving_age,
			"leg_rotation": [leg.x, leg.y, leg.z, leg.w]})
	return false

func _tern() -> CivilianFigure:
	var game: Node = _game_manager()
	if game == null:
		return null
	if game.current_map_id == 1009 and game.m09_berth != null:
		return game.m09_berth._crew.get("tern") as CivilianFigure
	if game.current_map_id == 1010 and game.m10_ship != null:
		return game.m10_ship._figures.get("tern") as CivilianFigure
	return null

func _observed_state() -> Dictionary:
	var report: Dictionary = super._observed_state()
	var figure: CivilianFigure = _tern()
	var game: Node = _game_manager()
	if game != null and game.current_map_id in [1009, 1010] and figure == null:
		push_error("live_crew_tour: current mission omitted its named Tern figure")
		_failed = true
	if figure != null:
		if figure.skin == null or figure.skin.kind != "tern" or figure.strip != null:
			push_error("live_crew_tour: current Tern is missing the named live skin")
			_failed = true
		else:
			var accepted: Array = []
			if _crew_mission == "m09":
				for person: Dictionary in report.get("m09", {}).get("crew", []):
					if person["id"] == "tern":
						accepted = person["feet"]
			else:
				accepted = report.get("m10", {}).get("pilot", [])
			if accepted.size() != 3 or figure.position.distance_to(Vector3(accepted[0], accepted[1], accepted[2])) > 0.00001:
				push_error("live_crew_tour: named figure diverged from accepted mission feet")
				_failed = true
			report["live_tern"] = {"source": SkinnedCharacter.SOURCES["tern"],
				"feet": [figure.position.x, figure.position.y, figure.position.z],
				"walked": figure._walked, "facing": figure.rotation.y}
	return report

func _write_manifest(tour: Dictionary) -> void:
	super._write_manifest(tour)
	var file: FileAccess = FileAccess.open(_out_dir.path_join("live-cast.json"), FileAccess.WRITE)
	if file == null:
		push_error("live_crew_tour: cannot retain cast samples")
		_failed = true
		return
	file.store_string(JSON.stringify({"schema": 1, "mission": _crew_mission,
		"scope": "M09 development child" if _crew_mission == "m09" else "M10 canonical promotion of labelled v12 finite-carry fixture",
		"native_sha256": _owned.server_sha256, "source_sha256": FileAccess.get_sha256(SkinnedCharacter.SOURCES["tern"]),
		"samples": _cast_samples}, "\t"))
	file.close()

func _retire_scene() -> void:
	await super._retire_scene()
	_owned.stop()
	var deadline: int = Time.get_ticks_msec() + 5000
	while _owned.state == LocalMatch.State.STOPPING and Time.get_ticks_msec() < deadline:
		await process_frame
	if _owned.state != LocalMatch.State.IDLE:
		push_error("live_crew_tour: owned child did not stop")
		_failed = true

func _write_carry_fixture(directory: String) -> bool:
	var content: Array[int] = []
	for byte: int in FileAccess.get_sha256("res://../server/maps/m09_passenger_manifest.json").hex_decode():
		content.append(byte)
	var fixture: Dictionary = {"version": 12, "id": "0dc7302e-c024-4ccc-aac7-19e2aa908ce8", "starting_continues": 3,
		"remaining_continues": 1, "level_start_continues": 1, "body": "synthetic",
		"rules": {"difficulty": "standard", "revision": 3}, "content_sha256": content,
		"m03_outcome": {"liberated_cars": ["roof_car"]},
		"m04_outcome": {"rescued_patients": ["edda_team_a"], "photos_completed": 2},
		"m05_outcome": {"released_workers": ["splice", "workshop_agent_a", "workshop_agent_b"], "evacuated_workers": ["splice"]},
		"m06_outcome": {"prisoner_route_marked": true},
		"m08_outcome": {"kind": "recorded", "custody_released": true, "recovered_mind_secured": true, "captives_evacuated": true},
		"m09_outcome": {"kind": "recorded", "released_crew": ["tern", "berth_crew_a", "berth_crew_b", "edda", "splice"], "aboard_at_departure": []},
		"step": {"kind": "awaiting_mission", "completed_mission": "passenger_manifest", "next_mission": "common_carrier",
			"exit": {"hp": 39, "armor": 17, "equipment": {"selected": "sniper", "weapons": ["fists", "flechette", "scatter", "sniper"],
				"ammo": [{"pool": "bullets", "rounds": 76}, {"pool": "shells", "rounds": 32}, {"pool": "cells", "rounds": 1}],
				"grenades": 2, "proximity_mines": 3, "personal_claims": ["cold_cabinet"]}}}}
	var file: FileAccess = FileAccess.open(directory.path_join("run.json"), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(fixture) + "\n  \n")
	file.close()
	return true
