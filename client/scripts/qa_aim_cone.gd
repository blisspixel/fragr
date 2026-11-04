extends "res://scripts/qa_tour.gd"

## Ordinary live input, retaining the private facts behind each rendered ring.
## Use qa/aim-cone.json with a bot-free full-arsenal match.
var _aim_samples: Array[Dictionary] = []
var _record_aim: bool = false


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
	var open: bool = _aim_samples.any(func(sample: Dictionary) -> bool: return int(sample.get("cone_microradians", 0)) > 0)
	if _aim_samples.size() < frames or (state.get("aim_open", false) and not open):
		push_error("qa_aim_cone: capture did not observe its promised server cone")
		_failed = true
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
		sample["ring_visible"] = reticle.is_visible_in_tree()
		sample["pip_position"] = [reticle.global_position.x, reticle.global_position.y]
		_aim_samples.append(sample)
	return super._grab()
