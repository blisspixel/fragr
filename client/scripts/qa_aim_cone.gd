extends "res://scripts/qa_tour.gd"

## Ordinary live input, retaining the private facts behind each rendered ring.
## Use qa/aim-cone.json with a bot-free full-arsenal match.
var _aim_samples: Array[Dictionary] = []
var _record_aim: bool = false
var _pip_reference: Vector2 = Vector2.INF


## Check presentation as well as authority: a server cone alone cannot prove
## that the player saw its ring. Burst onset may still include rested frames.
static func sample_error(samples: Array[Dictionary], state: Dictionary, frames: int, pip_reference: Vector2 = Vector2.INF) -> String:
	if samples.size() < frames or samples.is_empty():
		return "capture did not retain every requested frame"
	var expected: String = str(state.get("weapon", "")).replace("_", "").to_lower()
	if expected.is_empty():
		return "capture has no expected weapon"
	var opened: bool = false
	var centre: Vector2 = pip_reference
	for sample: Dictionary in samples:
		if str(sample.get("weapon", "")).replace("_", "").to_lower() != expected:
			return "capture observed another weapon"
		if sample.get("reticle_visible") != true:
			return "the authoritative reticle was hidden"
		var radius: Variant = sample.get("ring_radius_pixels")
		if not (radius is int or radius is float) or not is_finite(float(radius)) or float(radius) < 0.0:
			return "capture has no finite ring radius"
		if sample.get("ring_visible") != (float(radius) > 4.0):
			return "ring visibility disagrees with its drawable radius"
		var pip: Variant = sample.get("pip_position")
		if not pip is Array or pip.size() != 2:
			return "capture has no pip position"
		for coordinate: Variant in pip:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
				return "capture has no finite pip position"
		var position: Vector2 = Vector2(float(pip[0]), float(pip[1]))
		if not centre.is_finite():
			centre = position
		if not position.is_equal_approx(centre):
			return "the reference pip moved"
		if not EquipmentState.integer(sample.get("cone_microradians"), AimState.MAX_CONE):
			return "capture has no authoritative cone"
		var cone: int = int(sample["cone_microradians"])
		if (cone == 0) != (float(radius) == 0.0):
			return "ring radius does not reflect the server cone"
		if state.get("aim_rest", false) and (cone != 0 or sample.has("raise_ready_at") or float(radius) != 0.0):
			return "rest capture did not remain exact and ready"
		opened = opened or cone > 0
	if state.get("aim_open", false) and not opened:
		return "capture never observed an open server cone"
	return ""


func _capture_strip(state: Dictionary, frames: int, file_name: String) -> void:
	var manager: Node = _game_manager()
	var network: Node = manager.get("net_client")
	if state.get("aim_rest", false):
		var deadline: int = Time.get_ticks_msec() + 5000
		var rested: bool = false
		while Time.get_ticks_msec() < deadline:
			var aim: Dictionary = network.get("aim")
			if not aim.is_empty() and aim.get("cone_microradians") == 0 and not aim.has("raise_ready_at"):
				rested = true
				break
			await process_frame
		if not rested:
			push_error("qa_aim_cone: the server never reported rested aim")
			_failed = true
			return
	_aim_samples.clear()
	_record_aim = true
	await super._capture_strip(state, frames, file_name)
	_record_aim = false
	var problem: String = sample_error(_aim_samples, state, frames, _pip_reference)
	if not problem.is_empty():
		push_error("qa_aim_cone: " + problem)
		_failed = true
	elif not _pip_reference.is_finite():
		var pip: Array = _aim_samples[0]["pip_position"]
		_pip_reference = Vector2(float(pip[0]), float(pip[1]))
	var output: FileAccess = FileAccess.open(_out_dir.path_join(file_name.trim_suffix(".png") + ".json"), FileAccess.WRITE)
	if output == null:
		_failed = true
	else:
		output.store_string(JSON.stringify(_aim_samples, "\t") + "\n")
		output.close()


func _grab() -> Image:
	if _record_aim:
		var manager: Node = _game_manager()
		var network: Node = manager.get("net_client")
		var aim: Dictionary = network.get("aim")
		var sample: Dictionary = aim.duplicate(true)
		var hud: Node = manager.get("hud")
		var reticle: AimReticle = hud.get("aim_reticle")
		sample["ring_radius_pixels"] = reticle.radius
		sample["reticle_visible"] = reticle.is_visible_in_tree()
		sample["ring_visible"] = reticle.is_visible_in_tree() and reticle.radius > 4.0
		sample["pip_position"] = [reticle.global_position.x, reticle.global_position.y]
		_aim_samples.append(sample)
	return super._grab()
