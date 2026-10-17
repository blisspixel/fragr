extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000001414"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m14_mission_state: " + message)

static func state_at(info: Dictionary, stage: int = 0, tick: int = 10) -> Dictionary:
	var order: Array[String] = M14MissionState.OBJECTIVES.duplicate()
	order.append("party_departed")
	var progress: Dictionary = {"completed": order.slice(0, stage), "challenges": {"depot_secured": stage >= 2, "walker_disabled": stage >= 5, "jeep_preserved": true, "on_foot": true}, "jeep_id": 1, "support_stage": 2 if stage >= 5 else 0, "first_cycle_complete": stage >= 5, "machine_fallen": stage >= 5}
	if stage < 7:
		progress["current"] = info["m14"]["objectives"][stage].duplicate(true) if stage < 6 else {"id": "party_departed", "action": {"kind": "use", "target": info["m14"]["departure"].duplicate(true)}}
	return {"type": "mission", "tick": tick, "state": {"id": MissionState.M14_ID, "rules": {"difficulty": "standard", "revision": 4}, "attempt": 1, "phase": "departed" if stage == 7 else "in_progress", "changed_at": tick, "party": [{"id": PLAYER, "name": "Launch visitor", "ready": true, "alive": true, "aboard": stage >= 6}], "prompts": [], "m14": progress}}

func _run() -> void:
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m14_fact_vectors.json"))
	var intact: Dictionary = vectors["map_info"]
	var fallen: Dictionary = vectors["fallen_map_info"]
	_check(MissionState.map_error(intact).is_empty(), "native intact map crosses client boundary")
	_check(MissionState.map_error(fallen).is_empty(), "native fallen map crosses client boundary")
	_check(ArenaCover.venue_for(intact) == "launch_works" and ArenaSky.preset_for(intact["map_name"]).ambient_color == ArenaSky.mars_launch().ambient_color, "connected launch works retain Mars materials and lighting")
	var initial_geometry: Dictionary = MissionState.geometry_for(intact)
	var fallen_geometry: Dictionary = MissionState.geometry_for(fallen)
	_check(M14MissionState.same_contract(initial_geometry, fallen_geometry), "actual native fallen handoff retains immutable launch contract")
	_check(M14MissionState.same_contract(fallen_geometry, initial_geometry), "retry can restore intact world through same registered contract")
	for entry: Dictionary in vectors["valid"]:
		var geometry: Dictionary = fallen_geometry if entry["state"]["m14"]["machine_fallen"] else initial_geometry
		_check(MissionState.validation_error(entry, geometry).is_empty(), "native accepts " + str(entry["name"]))
		var sample_network: Node = preload("res://scripts/net_client.gd").new()
		var sample_errors: Array[String] = []
		var sample_snapshots: Array[Dictionary] = []
		sample_network.server_error.connect(func(reason: String) -> void: sample_errors.append(reason))
		sample_network.snapshot_received.connect(func(value: Dictionary) -> void: sample_snapshots.append(value))
		sample_network._handle_message(JSON.stringify(fallen if entry["state"]["m14"]["machine_fallen"] else intact))
		sample_network._handle_message(JSON.stringify({"type": "mission", "tick": entry["tick"], "state": entry["state"]}))
		var snapshot: Dictionary = entry["snapshot"].duplicate(true)
		snapshot["type"] = "snapshot"
		sample_network._handle_message(JSON.stringify(snapshot))
		_check(sample_errors.is_empty() and sample_snapshots.size() == 1, "actual full native snapshot crosses live client boundary: " + str(entry["name"]) + " " + str(sample_errors))
		sample_network.free()
	for entry: Dictionary in vectors["invalid"]:
		var geometry: Dictionary = fallen_geometry if entry["state"]["m14"].get("machine_fallen") == true else initial_geometry
		_check(not MissionState.validation_error(entry, geometry).is_empty(), "native rejects " + str(entry["name"]))
	for stage: int in range(8):
		var geometry: Dictionary = fallen_geometry if stage >= 5 else initial_geometry
		_check(MissionState.validation_error(state_at(intact, stage), geometry).is_empty(), "ordered objective " + str(stage))
	var start: Dictionary = state_at(intact)
	start["state"]["phase"] = "briefing"
	start["state"]["party"] = []
	_check(MissionState.validation_error(start, initial_geometry).is_empty(), "wire-decoded briefing accepts exact zero facts")
	var active: Dictionary = state_at(intact, 4, 20)
	var support: Dictionary = active.duplicate(true)
	support["state"]["m14"]["support_stage"] = 1
	_check(not MissionState.validation_error(support, initial_geometry).is_empty(), "live support cannot precede the first complete teaching cycle")
	support["state"]["m14"]["first_cycle_complete"] = true
	_check(MissionState.validation_error(support, initial_geometry).is_empty(), "support can follow the actual solo cycle")
	var disabled: Dictionary = active.duplicate(true)
	disabled["state"]["m14"]["challenges"]["walker_disabled"] = true
	disabled["state"]["m14"]["support_stage"] = 1
	_check(MissionState.validation_error(disabled, initial_geometry).is_empty(), "early disable retains support order while committed shells drain")
	var down: Dictionary = state_at(intact, 5, 30)
	_check(not MissionState.validation_error(down, initial_geometry, disabled).is_empty(), "fallen facts cannot arrive before fallen collision")
	_check(MissionState.validation_error(down, fallen_geometry, disabled).is_empty(), "fallen collision enables the actual resolved handoff")
	for key: String in ["jeep_preserved", "on_foot"]:
		var drift: Dictionary = down.duplicate(true)
		drift["state"]["m14"]["challenges"][key] = false
		_check(not MissionState.validation_error(drift, fallen_geometry, disabled).is_empty(), "disable freezes " + key + " receipt")
		var lost: Dictionary = active.duplicate(true)
		lost["state"]["m14"]["challenges"][key] = false
		_check(MissionState.validation_error(lost, initial_geometry, active).is_empty(), "active fight records actual " + key + " loss")
		_check(not MissionState.validation_error(active, initial_geometry, lost).is_empty(), "same attempt cannot erase " + key + " loss")
	var retry: Dictionary = state_at(intact, 0, 31)
	retry["state"]["attempt"] = 2
	_check(MissionState.validation_error(retry, initial_geometry, down).is_empty(), "fresh attempt restores mission through accepted intact geometry")
	retry["state"]["attempt"] = 1
	_check(not MissionState.validation_error(retry, initial_geometry, down).is_empty(), "same attempt cannot rewind resolved progress")
	var ready: Dictionary = state_at(intact, 6, 40)
	ready["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	_check(MissionState.validation_error(ready, fallen_geometry).is_empty(), "fresh supported party can receive departure prompt")
	ready["state"]["party"][0]["aboard"] = false
	_check(not MissionState.validation_error(ready, fallen_geometry).is_empty(), "off-board party cannot receive departure prompt")
	for key: String in ["walker_solids", "departure", "jeep"]:
		var broken: Dictionary = intact.duplicate(true)
		broken["m14"][key] = null
		_check(not MissionState.map_error(broken).is_empty(), "reject malformed registered " + key)
	var changed: Dictionary = fallen.duplicate(true)
	changed["solids"][int(changed["m14"]["walker_solids"][2])]["min_x"] += 0.2
	_check(not MissionState.map_error(changed).is_empty(), "fallen legs cannot move independently from accepted template")
	changed = fallen.duplicate(true)
	changed["solids"][int(changed["m14"]["walker_solids"][0])]["top"] = 1.8
	_check(not MissionState.map_error(changed).is_empty(), "fallen hull cannot quietly change collision height")
	changed = fallen_geometry.duplicate(true)
	changed["m14"]["jeep"]["yaw"] += 0.1
	_check(not M14MissionState.same_contract(initial_geometry, changed), "map handoff cannot rebind jeep placement")
	var network: Node = preload("res://scripts/net_client.gd").new()
	var errors: Array[String] = []
	var accepted: Array[Dictionary] = []
	network.server_error.connect(func(reason: String) -> void: errors.append(reason))
	network.mission_received.connect(func(value: Dictionary) -> void: accepted.append(value))
	network._handle_message(JSON.stringify(intact))
	network._handle_message(JSON.stringify(active))
	network._handle_message(JSON.stringify(disabled))
	network._handle_message(JSON.stringify(fallen))
	_check(errors.is_empty() and network.mission.is_empty() and network.walker_geometry.is_empty(), "fallen MapInfo clears active mission and live Walker binding until fresh facts")
	network._handle_message(JSON.stringify(down))
	_check(errors.is_empty() and accepted.back().get("m14", {}).get("machine_fallen") == true and accepted.back()["m14"]["completed"] == down["state"]["m14"]["completed"], "fresh fallen state reaches live network boundary")
	network._handle_message(JSON.stringify(active))
	_check(errors.size() == 1 and network.mission.is_empty(), "stale intact facts close the live boundary")
	network.free()
	var retry_network: Node = preload("res://scripts/net_client.gd").new()
	var retry_errors: Array[String] = []
	retry_network.server_error.connect(func(reason: String) -> void: retry_errors.append(reason))
	retry_network._handle_message(JSON.stringify(intact))
	retry_network._handle_message(JSON.stringify(fallen))
	retry_network._handle_message(JSON.stringify(intact))
	_check(retry_errors.is_empty() and not retry_network.walker_geometry.is_empty(), "exact original intact retry remains accepted")
	retry_network._handle_message(JSON.stringify(fallen))
	var rebound: Dictionary = intact.duplicate(true)
	rebound["walker"]["stations"][1][0] += 0.1
	_check(MissionState.map_error(rebound).is_empty(), "altered retry fixture is individually valid geometry")
	retry_network._handle_message(JSON.stringify(rebound))
	_check(retry_errors.size() == 1 and retry_network._m14_intact_geometry.is_empty(), "retry cannot rebind the original Walker station path and disconnect retires baseline")
	retry_network._handle_message(JSON.stringify(intact))
	retry_network._handle_message(JSON.stringify(fallen))
	rebound = intact.duplicate(true)
	rebound["solids"][int(rebound["walker"]["solids"][0])]["max_x"] += 0.1
	_check(MissionState.map_error(rebound).is_empty(), "altered retry body is individually valid geometry")
	retry_network._handle_message(JSON.stringify(rebound))
	_check(retry_errors.size() == 2, "retry cannot rebind original body collision even with unchanged station path")
	retry_network.free()
	var late_network: Node = preload("res://scripts/net_client.gd").new()
	var late_errors: Array[String] = []
	late_network.server_error.connect(func(reason: String) -> void: late_errors.append(reason))
	late_network._handle_message(JSON.stringify(fallen))
	late_network._handle_message(JSON.stringify(down))
	late_network._handle_message(JSON.stringify(intact))
	retry["state"]["attempt"] = 2
	late_network._handle_message(JSON.stringify(retry))
	_check(late_errors.is_empty() and not late_network._m14_intact_geometry.is_empty(), "late spectator can observe fallen world then bind its first actual intact retry")
	late_network.free()
	var hud := MissionHud.new()
	root.add_child(hud)
	hud.apply(active["state"], PLAYER)
	_check(hud._copy.text == tr("M14_OBJECTIVE_WALKER_DISABLED"), "HUD names the actual required fight")
	hud.apply(down["state"], PLAYER)
	_check(hud._evac_badge.text == tr("M14_MACHINE_FALLEN") and hud._copy.text == tr("M14_OBJECTIVE_GANTRY_SECURED"), "fallen receipt and next destination remain separate readable cues")
	hud.queue_free()
	_check(LocalMatch.MISSION_GAMEPLAY.get(MissionState.M14_ID) == 49 and LocalMatch.NEXT_MISSION == "freedom_of_movement", "practice capability and pending boundary agree")
	_check(StoryScene.exists("m14_arrival") and StoryScene.AFTER_MISSION.get(MissionState.M14_ID) == "l14_l15", "arrival and departure retain shared story player")
	await process_frame
	if failures == 0:
		print("test_m14_mission_state: PASS native facts, ordered teaching, fallen handoff, stale refusal, retries and frontend")
	quit(0 if failures == 0 else 1)
