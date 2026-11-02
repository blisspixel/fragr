extends SceneTree

## Still Here reader: the native walk is accepted in order, the world turns
## only forward, and forged progress, early turns, invented survivors and
## bodies that disagree with the run are refused.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_epilogue_mission_state: " + message)

func _rejected(message: Dictionary, geometry: Dictionary, why: String) -> void:
	_check(not MissionState.validation_error(message, geometry, {}).is_empty(), why)

func _run() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/epilogue_lifecycle.json"))
	if not fixture is Dictionary or not fixture.get("messages") is Array:
		push_error("test_epilogue_mission_state: missing native lifecycle fixture")
		quit(1)
		return
	var first: Dictionary = fixture["map_info"]
	var later: Dictionary = fixture["map_info_later"]
	_check(MissionState.map_error(first).is_empty(), "native aftermath map rejected")
	_check(MissionState.map_error(later).is_empty(), "native later map rejected")
	_check(MissionState.id_for_map(first) == MissionState.STILL_HERE_ID, "map identity")
	_check(first["map_name"] == EpilogueMissionState.NAME and later["map_name"] == EpilogueMissionState.LATER_NAME, "world names")
	var first_geometry: Dictionary = MissionState.geometry_for(first)
	var later_geometry: Dictionary = MissionState.geometry_for(later)
	_check(EpilogueMissionState.same_contract(first_geometry, later_geometry), "the world may turn")
	_check(not EpilogueMissionState.same_contract(later_geometry, first_geometry), "the world never turns back")
	_check(first["solids"].size() == later["solids"].size(), "decoration indices hold across the turn")

	# Map contract refusals.
	var bad: Dictionary = first.duplicate(true)
	bad["m20"] = {}
	_check(not MissionState.map_error(bad).is_empty(), "the epilogue cannot share another mission map")
	bad = first.duplicate(true)
	bad["epilogue"]["people"].append(bad["epilogue"]["people"][0].duplicate(true))
	_check(not MissionState.map_error(bad).is_empty(), "a person twice in one world")
	bad = first.duplicate(true)
	bad["epilogue"]["people"][0]["pose"] = "aim"
	_check(not MissionState.map_error(bad).is_empty(), "an unknown pose")
	bad = first.duplicate(true)
	bad["epilogue"]["people"][1]["requires"] = "everyone"
	_check(not MissionState.map_error(bad).is_empty(), "an unknown survivor")
	bad = first.duplicate(true)
	bad["epilogue"]["ferry_board"] = int(bad["epilogue"]["latch"]["decoration"])
	_check(not MissionState.map_error(bad).is_empty(), "the board must be its own panel")

	var previous: Dictionary = {}
	var saw: Dictionary = {}
	for message: Dictionary in fixture["messages"]:
		var facts: Dictionary = message["state"]["epilogue"]
		var geometry: Dictionary = later_geometry if facts["later"] else first_geometry
		var problem: String = MissionState.validation_error(message, geometry, previous)
		_check(problem.is_empty(), "native message rejected at tick %d: %s" % [int(message["tick"]), problem])
		saw[facts["completed"].size()] = true
		_check(message["state"].get("run") == null, "the epilogue keeps no run")
		var forged: Dictionary = message.duplicate(true)
		forged["state"]["epilogue"]["completed"].append("forged")
		_rejected(forged, geometry, "forged progress accepted")
		forged = message.duplicate(true)
		forged["state"]["epilogue"]["refuge"]["everyone"] = true
		_rejected(forged, geometry, "an invented survivor")
		forged = message.duplicate(true)
		forged["state"]["epilogue"]["refuge"]["orrin"] = not facts["refuge"]["orrin"]
		_rejected(forged, geometry, "bodies that disagree with the run")
		forged = message.duplicate(true)
		forged["state"]["epilogue"]["blocking"].pop_back()
		_rejected(forged, geometry, "a missing body")
		forged = message.duplicate(true)
		forged["state"]["epilogue"]["later"] = not facts["later"]
		_rejected(forged, geometry, "the turn disagrees with the world")
		_rejected(message, later_geometry if not facts["later"] else first_geometry, "facts read against the other world")
		if facts.has("turning_at"):
			forged = message.duplicate(true)
			forged["state"]["epilogue"]["turning_at"] = int(message["tick"]) + 1
			_rejected(forged, geometry, "a turn from the future")
			if facts["later"]:
				forged = message.duplicate(true)
				forged["state"]["epilogue"]["turning_at"] = int(message["tick"]) - EpilogueMissionState.TURN_TICKS + 1
				_rejected(forged, geometry, "the world turned early")
		else:
			forged = message.duplicate(true)
			forged["state"]["epilogue"]["turning_at"] = int(message["tick"])
			_rejected(forged, geometry, "a turn before the ledger")
		previous = message
	for count: int in [0, 1, 2, 3]:
		_check(saw.has(count), "the walk passed %d completed" % count)
	var last: Dictionary = fixture["messages"].back()
	_check(last["state"]["phase"] == "departed", "the walk ends on the bench")
	# The run brought everyone: every named survivor stands in both worlds.
	var refuge: Dictionary = last["state"]["epilogue"]["refuge"]
	for who: String in ["edda", "splice", "orrin", "sorrel"]:
		_check(EpilogueMissionState.people(later_geometry["epilogue"], refuge).any(func(p: Dictionary) -> bool: return p["id"] == who), who + " years later")
	var nobody: Dictionary = {}
	for key: String in EpilogueMissionState.SURVIVORS:
		nobody[key] = false
	var stand_ins: Array = EpilogueMissionState.people(first_geometry["epilogue"], nobody).map(func(p: Dictionary) -> String: return p["id"])
	_check("lamp_keeper" in stand_ins and "edda" not in stand_ins, "somebody else lit the lamp")
	if failures == 0:
		print("test_epilogue_mission_state: PASS")
	quit(1 if failures > 0 else 0)
