extends "res://scripts/qa_tour.gd"

var _arc_reload_samples: Array[Dictionary] = []

func _capture_strip(state: Dictionary, frames: int, file_name: String) -> void:
	if state.get("trigger", "") != "reload":
		await super._capture_strip(state, frames, file_name)
		return
	var manager: Node = _game_manager()
	var network: Node = manager.get("net_client")
	var before: Dictionary = network.get("equipment").duplicate(true)
	if before.get("selected", "") != "arc":
		push_error("qa_arc_visual: reload strip requires the actually owned selected Arc")
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
		if WeaponArt.reload_frame("Arc", loadout, tick) != null:
			acknowledged = loadout.duplicate(true)
			break
		await process_frame
	if acknowledged.is_empty():
		push_error("qa_arc_visual: ordinary R never received an actual unfinished capacitor reload")
		_failed = true
		return
	_arc_reload_samples.clear()
	await super._capture_strip(state, frames, file_name)
	var after: Dictionary = network.get("equipment").duplicate(true)
	if EquipmentState.ammo(before, "cells") != EquipmentState.ammo(after, "cells"):
		push_error("qa_arc_visual: reload changed the finite Cells total")
		_failed = true
	var report: FileAccess = FileAccess.open(_out_dir.path_join("arc-reload-observation.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"ordinary_key":"R", "before":before, "acknowledged":acknowledged, "after":after, "samples":_arc_reload_samples}, "\t") + "\n")

func _probe_active(probe: Node, state: Dictionary) -> bool:
	if state.get("trigger", "") == "reload" and probe is TextureRect and probe.name == "FpWeapon":
		var manager: Node = _game_manager()
		var network: Node = manager.get("net_client")
		var pending: bool = probe.visible and probe.texture == WeaponArt.ARC_RELOAD
		_arc_reload_samples.append({"tick":int(manager.get("latest_snapshot").get("tick", 0)), "reload_pose":pending, "texture":probe.texture.resource_path if probe.texture != null else "", "equipment":network.get("equipment").duplicate(true)})
		return pending
	return super._probe_active(probe, state)
