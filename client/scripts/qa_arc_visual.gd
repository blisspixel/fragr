extends "res://scripts/qa_tour.gd"

## Retain the original Arc entry point while sharing ordinary reload capture
## with every magazine gun. All inspect the same accepted private loadout
## deadline, and each sample also records the HUD reload line and bar.
var _reload_samples: Array[Dictionary] = []

func _capture_strip(state: Dictionary, frames: int, file_name: String) -> void:
	if state.get("trigger", "") != "reload":
		await super._capture_strip(state, frames, file_name)
		return
	var manager: Node = _game_manager()
	var network: Node = manager.get("net_client")
	var before: Dictionary = network.get("equipment").duplicate(true)
	var weapon: String = str(state.get("weapon", "Arc"))
	if not EquipmentState.MAGAZINE_SIZES.has(weapon.to_lower()) or before.get("selected", "") != weapon.to_lower():
		push_error("qa_arc_visual: reload strip requires its actually owned selected weapon")
		_failed = true
		return
	var starts_before: int = int(manager.get("reload_start_cue_count"))
	var finishes_before: int = int(manager.get("reload_complete_cue_count"))
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
	# A long reload can outlast the strip; wait for its authoritative finish.
	var finish_by: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < finish_by and EquipmentState.magazine(network.get("equipment"), weapon.to_lower()).has("ready_at"):
		await process_frame
	await process_frame
	var after: Dictionary = network.get("equipment").duplicate(true)
	var cues: Dictionary = {"start": int(manager.get("reload_start_cue_count")) - starts_before, "complete": int(manager.get("reload_complete_cue_count")) - finishes_before}
	if EquipmentState.shots(after, weapon) <= EquipmentState.shots(before, weapon) or cues["start"] != 1 or cues["complete"] != 1:
		push_error("qa_arc_visual: ordinary reload did not show one accepted start and one authoritative finish")
		_failed = true
	var pool: String = str(EquipmentState.POOLS[weapon.to_lower()])
	if EquipmentState.ammo(before, pool) != EquipmentState.ammo(after, pool):
		push_error("qa_arc_visual: reload changed the finite ammunition total")
		_failed = true
	var report: FileAccess = FileAccess.open(_out_dir.path_join(weapon.to_lower()+"-reload-observation.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"ordinary_key":"R", "before":before, "acknowledged":acknowledged, "after":after, "cues":cues, "samples":_reload_samples}, "\t") + "\n")

func _probe_active(probe: Node, state: Dictionary) -> bool:
	if state.get("trigger", "") == "reload" and probe is TextureRect and probe.name == "FpWeapon":
		var manager: Node = _game_manager()
		var network: Node = manager.get("net_client")
		var hud: Node = _find_hud()
		var weapon: String = str(state.get("weapon", "Arc"))
		var depth: float = hud.fp_reload_motion.depth * WeaponArt.reload_dip(weapon)
		# The Arc and the modelled guns show reload frames; the rest dip.
		var posed: bool = probe.texture == WeaponArt.ARC_RELOAD if weapon == "Arc" else (probe.texture in WeaponArt.BAKED[weapon]["reload"] if WeaponArt.BAKED.has(weapon) else depth > 0.05)
		var pending: bool = probe.visible and posed
		var equipment_hud: EquipmentHud = hud.get("equipment_hud")
		var tick: int = int(manager.get("latest_snapshot").get("tick", 0))
		_reload_samples.append({"tick":tick, "reload_pose":pending, "reload_depth":depth, "held_y":probe.position.y, "texture":probe.texture.resource_path if probe.texture != null else "", "hud_line":equipment_hud.reload_label.text if equipment_hud.reload_label.visible else "", "hud_progress":equipment_hud.reload.progress(equipment_hud.tick), "start_cues":manager.get("reload_start_cue_count"), "complete_cues":manager.get("reload_complete_cue_count"), "request_to_accept_usec":equipment_hud.reload.last_request_to_accept_usec, "accept_to_cue_usec":equipment_hud.reload.last_accept_to_cue_usec, "equipment":network.get("equipment").duplicate(true)})
		return pending
	return super._probe_active(probe, state)
