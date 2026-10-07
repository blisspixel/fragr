extends SceneTree

func _initialize() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/water_vectors.json"))
	if not data is Dictionary or data.get("version") != 1 or not data.get("vectors") is Array or data.vectors.is_empty():
		push_error("water goldens: missing native vectors")
		quit(1)
		return
	var failures: int = 0
	var maximum: float = 0.0
	for vector: Dictionary in data.vectors:
		var arena: Dictionary = vector.arena.duplicate(true)
		arena["water_regions"] = vector.water_regions
		var actual: Dictionary = vector.initial.duplicate(true)
		for _step: int in range(int(vector.steps)):
			actual = WaterMovement.live_step(actual, vector.input, float(vector.speed), float(vector.dt), arena, float(vector.body_height))
		var drift: float = 0.0
		for key: String in ["x", "y", "z", "vx", "vy", "vz"]:
			drift = maxf(drift, absf(float(actual[key]) - float(vector.expected[key])))
		maximum = maxf(maximum, drift)
		if drift > 0.001:
			failures += 1
			push_error("water golden %s drift %.8f" % [vector.name, drift])
	print("test_water_golden: %s, %d vectors, maximum error %.8f" % ["PASS" if failures == 0 else "FAIL", data.vectors.size(), maximum])
	quit(0 if failures == 0 else 1)
