extends SceneTree

func _initialize() -> void:
	var vectors: Array = []
	for path: String in ["res://golden/vehicle_vectors.json", "res://golden/water_air_vectors.json"]:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary or data.get("version") != 1 or not data.get("vectors") is Array or data.vectors.is_empty():
			push_error("vehicle goldens: missing native vectors " + path)
			quit(1)
			return
		vectors.append_array(data.vectors)
	var failed: int = 0
	var maximum: float = 0.0
	for vector: Dictionary in vectors:
		var state: Dictionary = vector.initial.duplicate(true)
		for _index: int in range(int(vector.steps)):
			state = VehicleMediumStep.step(str(vector.kind), state, vector.input, float(vector.dt), vector.arena, vector.water_regions) if vector.has("kind") else VehicleStep.step(state, vector.input, float(vector.dt), vector.arena)
		var drift: float = GrenadeFacts.vector(state.position).distance_to(GrenadeFacts.vector(vector.expected.position))
		for key: String in ["yaw", "speed", "vy"]:
			drift = maxf(drift, absf(float(state[key]) - float(vector.expected[key])))
		maximum = maxf(maximum, drift)
		if drift > 0.001:
			failed += 1
			push_error("vehicle golden %s drift %.8f" % [vector.name, drift])
	print("test_vehicle_golden: %s, %d vectors, maximum error %.8f" % ["PASS" if failed == 0 else "FAIL", vectors.size(), maximum])
	quit(0 if failed == 0 else 1)
