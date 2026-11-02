extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000001616"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m16_mission_state: " + message)

static func fixture_map() -> Dictionary:
	var solids: Array = [
		{"min_x": 35.0, "max_x": 39.0, "min_z": -4.0, "max_z": 4.0, "bottom": 0.0, "top": 4.0},
		{"min_x": 5.0, "max_x": 8.0, "min_z": -15.0, "max_z": -12.0, "bottom": 0.0, "top": 2.4},
	]
	var decorations: Array = [
		{"solid": 0, "face": "south", "center": [0, 0], "size": [1.0, 2.0], "kind": "lift_control"},
		{"solid": 1, "face": "south", "center": [0, 0], "size": [0.8, 0.8], "kind": "terminal"},
	]
	var departure: Dictionary = {"decoration": 0, "approach": [37.0, 0.0, 0.0]}
	var bus_release: Dictionary = {"decoration": 1, "approach": [6.5, 0.0, -11.5]}
	var objectives: Array = [
		{"id": "ride_started", "action": {"kind": "arrival", "region": {"min": [-36.0, 0.0, -4.0], "max": [-24.0, 3.0, 4.0]}, "feet": [-30.0, 0.0, 0.0]}},
		{"id": "barricade_broken", "action": {"kind": "arrival", "region": {"min": [-15.0, 0.0, -4.0], "max": [-5.0, 3.0, 4.0]}, "feet": [-9.5, 0.0, 0.0]}},
		{"id": "green_wave_triggered", "action": {"kind": "arrival", "region": {"min": [5.0, 0.0, -4.0], "max": [15.0, 3.0, 4.0]}, "feet": [10.5, 0.0, 0.0]}},
		{"id": "bus_freed", "action": {"kind": "use", "target": bus_release}},
		{"id": "forecourt_secured", "action": {"kind": "arrival", "region": {"min": [20.0, 0.0, -14.0], "max": [35.0, 4.0, 14.0]}, "feet": [26.5, 0.0, 0.0]}},
		{"id": "doors_reached", "action": {"kind": "arrival", "region": {"min": [35.0, 0.0, -4.0], "max": [39.0, 4.0, 4.0]}, "feet": [37.0, 0.0, 0.0]}},
	]
	return {
		"type": "map_info",
		"map_id": 1016,
		"map_name": "Freedom of Movement",
		"geometry_version": 2,
		"half_extent": 48.0,
		"solids": solids,
		"presentation": {
			"ground": "concrete",
			"solids": ["enamel", "service_steel"],
			"decorations": decorations,
		},
		"m16": {
			"objectives": objectives,
			"departure": departure,
			"boarding": {"min": [35.0, 0.0, -4.0], "max": [39.0, 4.0, 4.0]},
			"bus_release": bus_release,
			"motorcycle": {"feet": [-38.0, 0.0, 0.0], "yaw": 0.0},
			"checkpoint_lifted": false,
			"doors_open": false,
		}
	}

static func fixture_state(info: Dictionary, stage: int = 0, tick: int = 10) -> Dictionary:
	var order: Array[String] = M16MissionState.OBJECTIVES.duplicate()
	order.append("party_departed")
	var progress: Dictionary = {
		"completed": order.slice(0, stage),
		"challenges": {
			"ride_started": stage >= 1,
			"green_wave_triggered": stage >= 3,
			"bus_freed": stage >= 4,
		},
		"checkpoint_lifted": stage >= 3,
		"doors_open": stage >= 6,
		"bus_freed": stage >= 4,
		"forecourt_secured": stage >= 5,
	}
	if stage < 6:
		progress["current"] = info["m16"]["objectives"][stage].duplicate(true)
	elif stage == 6:
		progress["current"] = {"id": "party_departed", "action": {"kind": "use", "target": info["m16"]["departure"].duplicate(true)}}
	return {
		"type": "mission",
		"tick": tick,
		"state": {
			"id": MissionState.M16_ID,
			"rules": {"difficulty": "standard", "revision": 4},
			"attempt": 1,
			"phase": "departed" if stage == 7 else "in_progress",
			"changed_at": tick,
			"party": [{"id": PLAYER, "name": "Avenue rider", "ready": true, "alive": true, "aboard": stage >= 6}],
			"prompts": [],
			"m16": progress,
		}
	}

func _run() -> void:
	var info: Dictionary = fixture_map()
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "fixture avenue map crosses client boundary")
	var geometry: Dictionary = MissionState.geometry_for(info)
	_check(geometry.get("id") == MissionState.M16_ID, "geometry_for produces M16 geometry")

	var lifted_info: Dictionary = info.duplicate(true)
	lifted_info["m16"]["checkpoint_lifted"] = true
	var lifted_geometry: Dictionary = MissionState.geometry_for(lifted_info)
	_check(M16MissionState.same_contract(geometry, lifted_geometry), "checkpoint_lifted flag change preserves contract")

	var modified_info: Dictionary = info.duplicate(true)
	modified_info["m16"]["boarding"]["max"][0] += 5.0
	var modified_geometry: Dictionary = MissionState.geometry_for(modified_info)
	_check(not M16MissionState.same_contract(geometry, modified_geometry), "boarding change alters contract")

	for stage: int in range(8):
		var msg: Dictionary = fixture_state(info, stage, 10 + stage * 10)
		var matching: Dictionary = geometry.duplicate(true)
		matching["m16"]["checkpoint_lifted"] = stage >= 3
		matching["m16"]["doors_open"] = stage >= 6
		_check(MissionState.validation_error(msg, matching).is_empty(), "valid stage %d validates" % stage)
		if stage >= 3:
			_check(not MissionState.validation_error(msg, geometry).is_empty(), "changed stage waits for matching map")

	var briefing: Dictionary = fixture_state(info, 0, 5)
	briefing["state"]["phase"] = "briefing"
	briefing["state"]["party"] = []
	_check(MissionState.validation_error(briefing, geometry).is_empty(), "briefing state validates")

	var premature_green: Dictionary = fixture_state(info, 0, 10)
	premature_green["state"]["m16"]["challenges"]["green_wave_triggered"] = true
	premature_green["state"]["m16"]["challenges"]["ride_started"] = false
	_check(not MissionState.validation_error(premature_green, geometry).is_empty(), "green wave without ride start rejected")

	var departed_no_doors: Dictionary = fixture_state(info, 7, 100)
	departed_no_doors["state"]["m16"]["doors_open"] = false
	_check(not MissionState.validation_error(departed_no_doors, geometry).is_empty(), "departed without open doors rejected")

	var presenter: M16Avenue = M16Avenue.new()
	presenter.configure_map(info)
	var notices: Array[String] = []
	presenter.notice_requested.connect(func(text: String) -> void: notices.append(text))
	presenter.apply_state(fixture_state(info, 3, 30)["state"])
	_check(presenter._checkpoint_lifted and notices.size() == 2 and notices[1] == tr("M16_MARA_NOT_US"), "presenter fires checkpoint lifted notice, then Mara: that wasn't us")
	presenter.apply_state(fixture_state(info, 4, 40)["state"])
	_check(presenter._bus_freed and notices.size() == 3, "presenter fires bus freed notice")
	presenter.apply_state(fixture_state(info, 6, 60)["state"])
	_check(presenter._doors_open and notices.size() == 4, "presenter fires chamber doors notice once each, Mara once")
	presenter.clear_map()
	presenter.free()

	if failures > 0:
		push_error("test_m16_mission_state FAILED with %d failures" % failures)
		quit(1)
	else:
		print("test_m16_mission_state: PASS native facts, motorcycle movement and chamber departure")
		quit(0)
