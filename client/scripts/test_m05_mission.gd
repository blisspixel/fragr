extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000000002"
var failures: int = 0

class ManagerProbe extends "res://scripts/game_manager.gd":
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://m05-mission-%d.cfg" % OS.get_process_id())
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m05_mission: " + message)

func _map() -> Dictionary:
	var objectives: Array[Dictionary] = []
	for index: int in range(6):
		var x: float = -20.0 + index * 6.0
		objectives.append({"id": M05MissionState.OBJECTIVES[index], "action": {"kind": "arrival", "feet": [x, 0, 0], "region": {"min": [x - 1, 0, -1], "max": [x + 1, 2, 1]}}})
	var info: Dictionary = {"type": "map_info", "map_id": 1005, "geometry_version": 2, "map_name": "No Forwarding Address", "half_extent": 40,
		"solids": [{"min_x": -1.5, "max_x": 1.5, "min_z": 4, "max_z": 8, "bottom": 0, "top": 1}, {"min_x": 9, "max_x": 11, "min_z": 24, "max_z": 25, "top": 1.2}],
		"presentation": {"ground": "concrete", "solids": ["service_steel", "lift_panel"], "decorations": [{"solid": 1, "face": "north", "center": [0, 0], "size": [1.5, 0.8], "kind": "m05_ship_departure"}]},
		"m05": {"freight_open": false, "rescue": {"release": {"min": [1, 0, 6], "max": [7, 2, 12]}, "captives": [{"id": "splice", "held": [3, 0, 8], "route": [[3, 0, 8], [3, 0, 23], [10, 0, 23]]}]},
		"objectives": objectives, "departure": {"decoration": 0, "approach": [10, 0, 23]}, "boarding": {"min": [8, 0, 20], "max": [12, 2, 24]}, "companion_start": [-25, 0, 0],
		"tram": {"solid": 0, "start": [0, 0, 6], "end": [0, 0, 28], "speed": 1.2, "activation": {"min": [-5, 0, 3], "max": [5, 3, 9]}}}}

	for index: int in range(1, 3):
		var x: float = 3.0 + index
		info["m05"]["rescue"]["captives"].append({"id": M05MissionState.WORKERS[index], "held": [x, 0, 8], "route": [[x, 0, 8], [x, 0, 23], [10.0 + index * 0.5, 0, 23]]})
	return info

func _state(info: Dictionary, count: int = 0, released: bool = false, tick: int = 20) -> Dictionary:
	var current: Dictionary = info["m05"]["objectives"][count] if count < 6 else {"id": "party_departed", "action": {"kind": "use", "target": info["m05"]["departure"]}}
	return {"type": "mission", "tick": tick, "state": {"id": MissionState.M05_ID, "rules": {"difficulty": "standard", "revision": MissionState.RULES_REVISION}, "attempt": 1, "phase": "in_progress", "changed_at": 10,
		"party": [{"id": PLAYER, "name": "Traveller", "ready": true, "alive": true, "aboard": count == 6}], "prompts": [],
		"m05": {"completed": M05MissionState.OBJECTIVES.slice(0, count), "current": current, "workshop_secured": released, "group_released": released,
		"captives": [{"id": "splice", "feet": [3, 0, 8]}, {"id": "workshop_agent_a", "feet": [4, 0, 8]}, {"id": "workshop_agent_b", "feet": [5, 0, 8]}], "freight_open": info["m05"]["freight_open"], "tram": {"phase": "boarding" if released else "parked", "feet": [0, 0, 6], "tick": tick},
		"carried_recall_cars": ["platform_car"], "carried_patients": ["edda_team_a"], "carried_photos": 2}}}

func _run() -> void:
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m05_tram_vectors.json"))
	for sample: Dictionary in vectors["cases"]:
		var vector_body: Dictionary = vectors["body"].duplicate()
		vector_body.merge(sample["body"], true)
		_check(M05Tram.supported(vector_body, vectors["tram"], sample["jump"]) == sample["supported"], "shared support golden: " + sample["name"])
		var result: Dictionary = M05Tram.carried(vector_body, float(sample["delta"]), {"half": vectors["half"], "solids": sample["solids"]})
		_check(result.is_empty() if sample["carried_z"] == null else not result.is_empty() and absf(float(result["z"]) - float(sample["carried_z"])) < 0.0001, "shared carry golden: " + sample["name"])
	var info: Dictionary = _map()
	_check(MissionState.map_error(info).is_empty(), "registered M05 geometry accepted")
	for order: Array in [["workshop_agent_a", "splice", "workshop_agent_b"], ["splice", "unknown", "workshop_agent_b"], ["splice", "splice", "workshop_agent_b"]]:
		var bad: Dictionary = info.duplicate(true)
		for index: int in range(3):
			bad["m05"]["rescue"]["captives"][index]["id"] = order[index]
		_check(not MissionState.map_error(bad).is_empty(), "stable authored worker order rejects reordered, unknown and duplicate IDs")
	var geometry: Dictionary = MissionState.geometry_for(info)
	var state: Dictionary = _state(info)
	_check(MissionState.validation_error(state, geometry).is_empty(), "exact mission facts accepted")
	for field: String in ["speed", "solid", "start"]:
		var bad: Dictionary = info.duplicate(true)
		bad["m05"]["tram"][field] = NAN
		_check(not MissionState.map_error(bad).is_empty(), "malformed tram refused: " + field)
	var released: Dictionary = _state(info, 3, true, 21)
	released["state"]["m05"]["captives"][0]["feet"] = [3, 0, 14]
	_check(MissionState.validation_error(released, geometry, state).is_empty(), "actual intermediate walking captive accepted")
	var invalid: Dictionary = released.duplicate(true)
	invalid["state"]["m05"]["captives"][0]["feet"] = [4, 0, 14]
	_check(not MissionState.validation_error(invalid, geometry).is_empty(), "off-route captive rejected")
	invalid = released.duplicate(true)
	invalid["state"]["m05"]["carried_photos"] = 3
	_check(not MissionState.validation_error(invalid, geometry, state).is_empty(), "retained campaign outcomes cannot be rewritten")
	invalid = released.duplicate(true)
	invalid["state"]["m05"]["tram"] = {"phase": "moving", "feet": [0, 0, 9], "tick": 22}
	_check(not MissionState.validation_error(invalid, geometry, released).is_empty(), "same-tick travel cannot exceed authored platform speed")
	var opened: Dictionary = info.duplicate(true)
	opened["m05"]["freight_open"] = true
	var open_geometry: Dictionary = MissionState.geometry_for(opened)
	_check(M05MissionState.same_contract(geometry, open_geometry), "prepared gate handoff preserves immutable binding")
	var departed: Dictionary = _state(opened, 6, true, 30)
	departed["state"]["phase"] = "departed"
	departed["state"]["m05"]["completed"].append("party_departed")
	departed["state"]["m05"].erase("current")
	departed["state"]["m05"]["captives"][0]["feet"] = [3, 0, 14]
	_check(MissionState.validation_error(departed, open_geometry, released).is_empty(), "departure requires no optional captive timing")
	_check(MissionHud.workers_aboard(departed["state"], opened["m05"]["boarding"]) == 0, "released is not inferred aboard")
	departed["state"]["m05"]["captives"][0]["feet"] = [10, 0, 23]
	_check(MissionHud.workers_aboard(departed["state"], opened["m05"]["boarding"]) == 1, "aboard comes from actual server feet")
	var preview: Dictionary = _state(opened, 6, true, 30)
	preview["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	var network: Node = load("res://scripts/net_client.gd").new()
	network.player_id = PLAYER
	network.mission = preview
	network.mission_geometry = open_geometry
	var manager: ManagerProbe = ManagerProbe.new()
	network.name = "NetClient"
	manager.add_child(network)
	for label: String in ["HUD", "Arena", "SpectatorCamera", "AudioPlayers"]:
		var child: Node = CanvasLayer.new() if label == "HUD" else Node.new()
		child.name = label
		manager.add_child(child)
	for label: String in ["FragSound", "RoundStartSound", "RoundEndSound"]:
		var sound: AudioStreamPlayer = AudioStreamPlayer.new()
		sound.name = label
		manager.get_node("AudioPlayers").add_child(sound)
	root.add_child(manager)
	_check(manager._offer_m05_departure() and manager.controls_blocked() and not manager.pending_interact, "first physical Use opens review without sending departure")
	await process_frame
	_check(manager.departure_review is CanvasLayer and manager.departure_review.layer > manager.hud.layer,
		"passenger controls render above the live HUD prompt instead of overlapping its cancel line")
	_check(manager.departure_review._copy.get_parsed_text().contains("Freed, not aboard") and manager.departure_review._copy.get_parsed_text().contains("Splice"), "actual passenger review names freed versus aboard truthfully")
	manager._close_departure_review()
	_check(not manager.pending_interact, "cancel has no authority side effect")
	manager._offer_m05_departure()
	var press: InputEventKey = InputEventKey.new()
	press.physical_keycode = KEY_F
	press.pressed = true
	Input.action_press("interact")
	manager.departure_review._process(0.0)
	manager.departure_review._input(press)
	_check(not manager.pending_interact, "held opening Use cannot confirm the passenger modal")
	Input.action_release("interact")
	manager.departure_review._process(0.0)
	manager.departure_review._input(press)
	_check(manager.pending_interact, "released then fresh physical Use confirms through the actual modal signal and queues only existing Action")
	manager.pending_interact = false
	manager._offer_m05_departure()
	network.mission["state"]["prompts"] = []
	manager._confirm_m05_departure()
	_check(not manager.pending_interact, "stale prompt cannot queue departure after cancellation or party movement")
	manager.queue_free()
	var body: Dictionary = MoveStep.make_state(0, 6, 0)
	body["y"] = 1.0
	var solid: Dictionary = info["solids"][0]
	_check(M05Tram.supported(body, solid, false) and not M05Tram.supported(body, solid, true), "standing full footprint supported, rising jump detaches")
	var other: Dictionary = {"half": 40.0, "solids": []}
	_check(is_equal_approx(float(M05Tram.carried(body, 0.06, other)["z"]), 6.06), "real per-tick platform carry")
	other["solids"] = [{"min_x": -3, "max_x": 3, "min_z": 3, "max_z": 9, "bottom": 2.75, "top": 3.5}]
	_check(M05Tram.carried(body, 0.06, other).is_empty(), "full 1.8 m body ceiling refuses carry")
	var predictor: LocalPrediction = LocalPrediction.new()
	predictor.configure_map(info)
	var ride: Dictionary = _state(info, 3, true, 40)["state"]
	ride["m05"]["tram"] = {"phase": "moving", "feet": [0, 0, 6], "tick": 40}
	predictor.apply_m05(ride)
	var neutral: Dictionary = MoveStep.make_input(false, false, false, false, 0)
	var predicted: Dictionary = predictor._step(body, {"tick": 41, "input": neutral, "speed": 5.0})
	_check(absf(float(predicted["z"]) - 6.06) < 0.0001 and absf(float(predicted["y"]) - 1.0) < 0.0001, "live LocalPrediction carries supported rider before ordinary movement")
	neutral["jump"] = true
	predicted = predictor._step(body, {"tick": 41, "input": neutral, "speed": 5.0})
	_check(absf(float(predicted["z"]) - 6.0) < 0.0001 and float(predicted["y"]) > 1.0, "actual prediction jump detaches rather than carrying")
	_check(absf(float(predictor._tram_feet(90)[2]) - 6.18) < 0.0001, "platform extrapolation shares the three-tick prediction ceiling")
	ride["attempt"] = 2
	ride["m05"]["tram"] = {"phase": "parked", "feet": [0, 0, 6], "tick": 50}
	predictor.apply_m05(ride)
	_check(predictor._tram_samples.size() == 1 and float(predictor._tram_feet(51)[2]) == 6.0, "retry clears prior moving platform timeline")
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	cover.apply_m05(released["state"])
	_check(cover._solid_views[0].visible and cover._solid_views[0].position.z == 6, "registered mesh at authoritative lower-center baseline")
	released["state"]["m05"]["tram"] = {"phase": "moving", "feet": [0, 0, 6.6], "tick": 31}
	cover.apply_m05(released["state"])
	_check(is_equal_approx(cover._solid_views[0].position.z, 6.6), "same actual body follows authoritative tram pose")
	cover.apply_m05({})
	_check(not cover._solid_views[0].visible, "gate handoff hides stale body until fresh facts")
	cover.queue_free()
	var town: M05Town = M05Town.new()
	root.add_child(town)
	town.configure_map(info)
	_check(town._views.size() == 2 and town._splice != null and town._splice.rigid != null and town._splice.strip == null, "named Splice uses the rigid source beside two unnamed synthetic workers")
	_check(town._splice.position == Vector3(3, 0, 8), "held named figure is registered at server feet")
	town.apply_state(released["state"])
	_check(town._splice.position == Vector3(3, 0, 14), "named worker follows actual server feet")
	var invalid_people: Dictionary = released["state"].duplicate(true)
	invalid_people["m05"]["captives"][0]["feet"] = [NAN, 0, 14]
	town.apply_state(invalid_people)
	_check(town._splice.position == Vector3(3, 0, 14), "invalid state cannot move the named figure")
	town.configure_map({})
	_check(town._views.is_empty() and town._splice == null and town._root == null, "malformed or other map retires every named and unnamed fixture")
	var lamp_info: Dictionary = info.duplicate(true)
	lamp_info["solids"].append({"min_x": -30, "max_x": -29.6, "min_z": -10, "max_z": 0, "bottom": 0, "top": 4})
	lamp_info["presentation"]["solids"].append("service_steel")
	town.configure_map(lamp_info)
	var lamps: Array[Node] = town.find_children("WorkshopRepairPool", "OmniLight3D", true, false)
	_check(lamps.size() == 1, "actual registered workshop wall creates one bounded practical pool")
	var preferences: FragrSettings = FragrSettings.new(str(get_meta("fragr_settings_path")))
	preferences.set_value("video", "quality", 1)
	RenderQuality.apply_practicals(town, preferences)
	_check(lamps.size() == 1 and (lamps[0] as OmniLight3D).shadow_enabled, "newly created practical receives Balanced shadow policy")
	preferences.set_value("video", "quality", 0)
	RenderQuality.apply_practicals(town, preferences)
	_check(lamps.size() == 1 and not (lamps[0] as OmniLight3D).shadow_enabled, "Performance preserves the light pool while dropping its shadow")
	town.queue_free()
	await process_frame
	if failures == 0:
		print("test_m05_mission: PASS strict contract, carry retention, walking/aboard distinction, tram support/sweep and actual mesh")
	quit(0 if failures == 0 else 1)
