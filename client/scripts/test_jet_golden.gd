extends SceneTree
## Replays the native jetpack vectors through the GDScript mirror.

func _initialize() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/jetpack_vectors.json"))
	if not data is Dictionary or data.get("version") != 1 or not data.get("cases") is Array or data["cases"].is_empty():
		push_error("jetpack goldens: missing native vectors")
		quit(1)
		return
	var failures: int = 0
	var maximum: float = 0.0
	var steps: int = 0
	if int(data["fuel_max"]) != JetMovement.FUEL_MAX or int(data["refill_per_tick"]) != JetMovement.REFILL_PER_TICK \
		or not is_equal_approx(float(data["thrust"]), JetMovement.THRUST) or not is_equal_approx(float(data["max_rise"]), JetMovement.MAX_RISE):
		push_error("jetpack goldens: constants disagree with the mirror")
		failures += 1
	for case: Dictionary in data["cases"]:
		var state: Dictionary = case["start"].duplicate(true)
		var fuel: int = int(case["fuel"])
		for index: int in range(case["inputs"].size()):
			var input: Dictionary = case["inputs"][index]
			var moved: Dictionary = JetMovement.live_step(state, input, float(case["speed"]), float(data["dt"]), case["arena"], MoveStep.BODY_HEIGHT, fuel, float(case["ceiling"]))
			var expected: Dictionary = case["expected"][index]
			fuel = int(moved["fuel"])
			state = {"x": moved["x"], "y": moved["y"], "z": moved["z"], "vx": moved["vx"], "vy": moved["vy"], "vz": moved["vz"], "yaw": moved["yaw"]}
			var drift: float = 0.0
			for key: String in ["x", "y", "z", "vx", "vy", "vz"]:
				drift = maxf(drift, absf(float(state[key]) - float(expected["state"][key])))
			maximum = maxf(maximum, drift)
			steps += 1
			if drift > 0.001 or fuel != int(expected["fuel"]) or bool(moved["thrusting"]) != bool(expected["thrusting"]):
				failures += 1
				push_error("jetpack golden %s step %d drift %.8f fuel %d/%d" % [case["name"], index, drift, fuel, int(expected["fuel"])])
				break
	print("test_jet_golden: %s, %d cases, %d steps, maximum error %.8f" % ["PASS" if failures == 0 else "FAIL", data["cases"].size(), steps, maximum])
	quit(0 if failures == 0 else 1)
