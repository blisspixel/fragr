extends SceneTree

var failures: int = 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m11_mission_state: " + message)

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m11_fact_vectors.json"))
	_check(parsed is Array and parsed.size() == 32, "shared vectors are present and complete")
	if not parsed is Array:
		quit(1); return
	for entry: Dictionary in parsed:
		var accepted: bool = M11MissionState.facts_error(entry["state"], entry["phase"], int(entry["tick"])).is_empty()
		_check(accepted == entry["valid"], str(entry["id"]) + " has the expected acceptance")
		if entry.has("briefs"):
			for difficulty: String in entry["briefs"]:
				_check(M11MissionState.brief_completed(entry["state"]["challenges"], difficulty) == entry["briefs"][difficulty], str(entry["id"]) + " derives " + difficulty)
	var objectives: Array[Dictionary] = []
	for id: String in M11MissionState.OBJECTIVES:
		objectives.append({"id": id, "action": {"kind": "arrival", "region": {"min": [-1, 0, -1], "max": [1, 1, 1]}, "feet": [0, 0, 0]}})
	var map_value: Dictionary = {"objectives": objectives, "transfer_release": {"decoration": 0, "approach": [0, 0, 0]}, \
		"records_document": {"decoration": 1, "approach": [0, 0, 0]}, "departure": {"decoration": 2, "approach": [0, 0, 0]}, \
		"boarding": {"min": [-1, 0, -1], "max": [1, 1, 1]}, "companion_start": [0, 0, 0], "transfer_people": [[3, 0, 0], [5, 0, 0], [7, 0, 0]]}
	var panels: Array = [{"kind": "m11_transfer_release"}, {"kind": "m11_records_document"}, {"kind": "m11_stern_release"}]
	_check(M11MissionState.map_value_error(map_value, 20.0, panels).is_empty(), "registered tender targets bind in order")
	var bad: Dictionary = map_value.duplicate(true)
	bad["departure"]["decoration"] = 0
	_check(not M11MissionState.map_value_error(bad, 20.0, panels).is_empty(), "departure cannot use transfer target")
	bad = map_value.duplicate(true); bad["transfer_people"][1] = bad["transfer_people"][0]
	_check(not M11MissionState.map_value_error(bad, 20.0, panels).is_empty(), "transfer body spacing cannot overlap")
	_check(not M11MissionState.map_value_error(map_value, 257.0, panels).is_empty(), "map extent retains the geometry boundary")
	bad = map_value.duplicate(true); bad["transfer_people"][0] = [0, -0.01, 0]
	_check(not M11MissionState.map_value_error(bad, 20.0, panels).is_empty(), "below-floor person refuses")
	if failures == 0:
		print("test_m11_mission_state: PASS strict objectives, unsigned results, actual clocks and optional briefs")
	quit(0 if failures == 0 else 1)
