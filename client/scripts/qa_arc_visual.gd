extends "res://scripts/qa_tour.gd"

## Retain the original Arc entry point while sharing ordinary reload capture
## with Rocket. Both inspect the same accepted private loadout deadline.
var _reload_samples: Array[Dictionary] = []

func _capture_strip(state: Dictionary, frames: int, file_name: String) -> void:
	if state.get("trigger", "") != "reload":
		await super._capture_strip(state, frames, file_name)
		return
	var manager: Node = _game_manager()
	var network: Node = manager.get("net_client")
	var before: Dictionary = network.get("equipment").duplicate(true)
	var weapon: String = str(state.get("weapon", "Arc"))
	if weapon not in ["Arc", "Rocket"] or before.get("selected", "") != weapon.to_lower():
		push_error("qa_arc_visual: reload strip requires its actually owned selected weapon")
		_failed = true
		return
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_R
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	var deadline: int = Time.get_ticks_msec() + 5000
	var acknowledged: Dictionary = {}
	while Time.get_ticks_msec() < deadline:
		var loadout: Dictionary = network.get("equipment")
		var tick: int = int(manager.get("latest_snapshot").get("tick", 0))
		if WeaponArt.reload_deadline(weapon, loadout, tick) > tick:
			acknowledged = loadout.duplicate(true)
			break
		await process_frame
	if acknowledged.is_empty():
		push_error("qa_arc_visual: ordinary R never received an actual unfinished reload")
		_failed = true
		return
	_reload_samples.clear()
	# Keep the first actual rendered reload pose. Three generic lead draws can
	# consume the entire short Rocket reload on a software renderer.
	var probe: Node = get_root().find_child(str(state.get("probe","FpWeapon")),true,false)
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		if probe != null and _probe_active(probe,state):
			break
	await super._capture_strip(state, frames, file_name)
	var after: Dictionary = network.get("equipment").duplicate(true)
	var pool: String = str(EquipmentState.POOLS[weapon.to_lower()])
	if EquipmentState.ammo(before, pool) != EquipmentState.ammo(after, pool):
		push_error("qa_arc_visual: reload changed the finite ammunition total")
		_failed = true
	var report: FileAccess = FileAccess.open(_out_dir.path_join(weapon.to_lower()+"-reload-observation.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"ordinary_key":"R", "before":before, "acknowledged":acknowledged, "after":after, "samples":_reload_samples}, "\t") + "\n")

func _probe_active(probe: Node, state: Dictionary) -> bool:
	if state.get("trigger", "") == "reload" and probe is TextureRect and probe.name == "FpWeapon":
		var manager: Node = _game_manager()
		var network: Node = manager.get("net_client")
		var hud: Node = _find_hud()
		var depth: float = hud.fp_reload_motion.depth if state.get("weapon") == "Rocket" else 0.0
		var pending: bool = probe.visible and (depth > 0.05 if state.get("weapon") == "Rocket" else probe.texture == WeaponArt.ARC_RELOAD)
		_reload_samples.append({"tick":int(manager.get("latest_snapshot").get("tick", 0)), "reload_pose":pending, "reload_depth":depth, "held_y":probe.position.y, "texture":probe.texture.resource_path if probe.texture != null else "", "equipment":network.get("equipment").duplicate(true)})
		return pending
	return super._probe_active(probe, state)
