extends SceneTree

## M02 client boundary: the optional MapInfo marker, the `m02` mission field,
## the one-line HUD, gate world rebuilds and the console beacon.
class CaptureNetwork extends "res://scripts/net_client.gd":
	var sent: Array[Dictionary] = []
	func send_json(data: Dictionary) -> void:
		sent.append(data.duplicate(true))

const PLAYER: String = "00000000-0000-0000-0000-000000000002"
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m02_mission: " + message)

## The shape of the bundled graybox wire, reduced to one gate and one console.
func _map(gate_bottom: float = 0.0) -> Dictionary:
	return {"type": "map_info", "map_id": 1002, "map_name": "Persons Unknown: ward graybox", "geometry_version": 2,
		"half_extent": 8, "m02_objectives": 3,
		"solids": [{"min_x": -3, "max_x": -1, "bottom": 0, "top": 1.2, "min_z": -2, "max_z": -1},
			{"min_x": -2, "max_x": 2, "bottom": gate_bottom, "top": gate_bottom + 4, "min_z": 1, "max_z": 2}],
		"presentation": {"ground": "concrete", "solids": ["service_steel", "lift_panel"], "decorations": [
			{"solid": 0, "face": "north", "center": [0, 0], "size": [1.6, 0.8], "kind": "terminal"}]}}

func _state(completed: Array, current: Variant, phase: String = "in_progress", prompts: Array = [], attempt: int = 1, tick: int = 20, secured: bool = false) -> Dictionary:
	var progress: Dictionary = {"completed": completed, "total": 3, "gate_mask": 1 if completed.size() >= 2 else 0, "ward_secured": secured}
	if current != null:
		progress["current"] = current
	return {"type": "mission", "tick": tick, "state": {"id": "persons_unknown", "rules": {"difficulty": "standard", "revision": 2},
		"attempt": attempt, "phase": phase, "changed_at": 0,
		"party": [{"id": PLAYER, "name": "Walker", "ready": phase != "briefing", "alive": true, "aboard": phase == "departed"}],
		"prompts": prompts, "m02": progress}}

func _arrival(id: String, z: float) -> Dictionary:
	return {"id": id, "action": {"kind": "arrival", "region": {"min": [-1, 0, z - 1], "max": [1, 1, z + 1]}, "feet": [0, 0, z]}}

func _use() -> Dictionary:
	return {"id": "companion_released", "action": {"kind": "use", "target": {"decoration": 0, "approach": [-2, 0, -3.5]}}}

func _run() -> void:
	var info: Dictionary = _map()
	_expect(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "M02 marker is valid")
	for patch: Dictionary in [{"m02_objectives": 0}, {"m02_objectives": 9}, {"m02_objectives": 1.5}, {"m02_objectives": "3"},
		{"mission": {"id": "recall_notice"}}, {"presentation": null}]:
		var bad: Dictionary = info.duplicate(true)
		bad.merge(patch, true)
		_expect(not MissionState.map_error(bad).is_empty(), "invalid M02 marker rejected: " + str(patch))
	var geometry: Dictionary = MissionState.geometry_for(info)
	_expect(geometry.get("id") == MissionState.M02_ID and geometry.get("total") == 3, "marker binds the objective count")
	var first: Dictionary = _state([], _arrival("ward_reached", -4))
	var ward_fight: Dictionary = _state(["ward_reached"], _use())
	var use: Dictionary = _state(["ward_reached"], _use(), "in_progress", [{"player_id": PLAYER, "kind": "objective_use"}], 1, 20, true)
	var exit: Dictionary = _state(["ward_reached", "companion_released"], _arrival("party_departed", 4), "in_progress", [], 1, 21, true)
	var done: Dictionary = _state(["ward_reached", "companion_released", "party_departed"], null, "departed", [], 1, 22, true)
	for valid: Dictionary in [first, ward_fight, use, exit, done]:
		_expect(MissionState.validation_error(valid, geometry).is_empty(), "valid M02 state accepted: " + str(valid["state"]["m02"]))
	var briefing: Dictionary = _state([], _arrival("ward_reached", -4), "briefing")
	_expect(MissionState.validation_error(briefing, geometry).is_empty(), "briefing waits on the first objective")
	var invalid: Array[Dictionary] = []
	for patch: Dictionary in [{"phase": "find_transfer"}, {"run": {"id": PLAYER, "status": "playing", "continues": 3}},
		{"prompts": [{"player_id": PLAYER, "kind": "transfer_record"}]}, {"attempt": 0}, {"script": true}]:
		var bad: Dictionary = use.duplicate(true)
		bad["state"].merge(patch, true)
		invalid.append(bad)
	for patch: Dictionary in [{"total": 4}, {"gate_mask": 8}, {"ward_secured": 1}, {"completed": ["ward_reached", "ward_reached"]},
		{"completed": ["Ward Reached"]}, {"current": null}, {"extra": 1}]:
		var bad: Dictionary = use.duplicate(true)
		bad["state"]["m02"].merge(patch, true)
		invalid.append(bad)
	var arrival_prompt: Dictionary = first.duplicate(true)
	arrival_prompt["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	invalid.append(arrival_prompt)
	var early_prompt: Dictionary = ward_fight.duplicate(true)
	early_prompt["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	invalid.append(early_prompt)
	var missing_fact: Dictionary = ward_fight.duplicate(true)
	missing_fact["state"]["m02"].erase("ward_secured")
	invalid.append(missing_fact)
	var premature_win: Dictionary = briefing.duplicate(true)
	premature_win["state"]["m02"]["ward_secured"] = true
	invalid.append(premature_win)
	var release_without_win: Dictionary = exit.duplicate(true)
	release_without_win["state"]["m02"]["ward_secured"] = false
	invalid.append(release_without_win)
	var wrong_panel: Dictionary = use.duplicate(true)
	wrong_panel["state"]["m02"]["current"]["action"]["target"]["decoration"] = 1
	invalid.append(wrong_panel)
	var outside: Dictionary = first.duplicate(true)
	outside["state"]["m02"]["current"]["action"]["feet"] = [0, 0, 2]
	invalid.append(outside)
	var early_exit: Dictionary = _state(["ward_reached"], _arrival("party_departed", 4))
	invalid.append(early_exit)
	var briefed_progress: Dictionary = _state(["ward_reached"], _use(), "briefing")
	invalid.append(briefed_progress)
	for bad: Dictionary in invalid:
		_expect(not MissionState.validation_error(bad, geometry).is_empty(), "invalid M02 state rejected: " + JSON.stringify(bad["state"]))
	_expect(not MissionState.validation_error(first, {"id": MissionState.ID}).is_empty(), "M02 state cannot use M01 geometry")
	var m01_like: Dictionary = use.duplicate(true)
	m01_like["state"]["id"] = "recall_notice"
	_expect(not MissionState.validation_error(m01_like, geometry).is_empty(), "M01 id cannot claim M02 geometry")
	_expect(not MissionState.validation_error(first, geometry, use).is_empty(), "progress cannot rewind within an attempt")
	_expect(not MissionState.validation_error(ward_fight, geometry, use).is_empty(), "ward victory cannot rewind within an attempt")
	var retry: Dictionary = _state([], _arrival("ward_reached", -4), "in_progress", [], 2, 30)
	_expect(MissionState.validation_error(retry, geometry, exit).is_empty(), "a retry restarts at the first objective")
	await _durable(geometry, first, done)
	await _network(info)
	_hud(first, ward_fight, use, exit, done)
	_readable(info)
	if failures == 0:
		print("test_m02_mission: PASS capability 17 ward fact, strict progress, gate map refresh, HUD and catalog keys")
	quit(0 if failures == 0 else 1)

func _durable(geometry: Dictionary, first: Dictionary, done: Dictionary) -> void:
	var live: Dictionary = first.duplicate(true)
	live["state"]["run"] = {"id": PLAYER, "status": "playing", "continues": 2, "level_start_continues": 2}
	_expect(MissionState.validation_error(live, geometry).is_empty(), "M02 durable entry starts at attempt one with carried allowance")
	var no_allowance: Dictionary = live.duplicate(true)
	no_allowance["state"]["run"]["continues"] = 0
	no_allowance["state"]["run"]["level_start_continues"] = 0
	_expect(MissionState.validation_error(no_allowance, geometry).is_empty(), "M02 can start with no remaining continues")
	var fallen: Dictionary = live.duplicate(true)
	fallen["tick"] = 21
	fallen["state"]["run"]["status"] = "continue"
	fallen["state"]["party"][0]["alive"] = false
	_expect(MissionState.validation_error(fallen, geometry, live).is_empty(), "M02 death offers a continue without spending it")
	var retry: Dictionary = live.duplicate(true)
	retry["tick"] = 22
	retry["state"]["attempt"] = 2
	retry["state"]["run"]["continues"] = 1
	_expect(MissionState.validation_error(retry, geometry, fallen).is_empty(), "M02 retry spends one shared continue and resets this level")
	var bad: Dictionary = retry.duplicate(true)
	bad["state"]["run"]["level_start_continues"] = 3
	_expect(not MissionState.validation_error(bad, geometry, fallen).is_empty(), "level baseline cannot change inside M02")
	bad = live.duplicate(true)
	bad["state"]["run"].erase("level_start_continues")
	_expect(not MissionState.validation_error(bad, geometry).is_empty(), "live M02 rejects old three-key run state")
	var completed: Dictionary = done.duplicate(true)
	completed["state"]["run"] = {"id": PLAYER, "status": "complete", "continues": 2, "level_start_continues": 2}
	_expect(MissionState.validation_error(completed, geometry).is_empty(), "M02 departure completes the durable run step")
	var hud: MissionHud = MissionHud.new()
	root.add_child(hud)
	hud.apply(live["state"], PLAYER)
	_expect(hud._run_badge.visible and hud._run_badge.text == "ATTEMPT 1  /  2 CONTINUES", "M02 shows the current level attempt and shared allowance")
	hud.apply(fallen["state"], PLAYER)
	_expect(hud._recovery.visible and hud.recovery_text.contains("ENTER"), "M02 offers the same explicit continue choice")
	hud.apply(first["state"], PLAYER)
	_expect(not hud._run_badge.visible and not hud._recovery.visible, "development M02 keeps the run UI hidden")
	hud.queue_free()

func _network(info: Dictionary) -> void:
	var network: CaptureNetwork = CaptureNetwork.new()
	network._handle_message(JSON.stringify(info))
	network._handle_message(JSON.stringify(_state([], _arrival("ward_reached", -4), "briefing", [], 1, 5)))
	_expect(network.mission.get("state", {}).get("phase") == "briefing", "network accepts the M02 briefing")
	network.connection_state = WebSocketPeer.STATE_OPEN
	network.player_id = PLAYER
	_expect(network.send_mission_ready() and network.sent.back() == {"type": "mission_ready", "id": "persons_unknown", "attempt": 1},
		"readiness names the M02 mission and attempt")
	network._handle_message(JSON.stringify(_state(["ward_reached"], _use(), "in_progress", [], 1, 20, true)))
	# A gate change resends MapInfo with the raised solid, then the new state.
	network._handle_message(JSON.stringify(_map(3.0)))
	_expect(network.mission.is_empty() and network.mission_geometry.get("id") == MissionState.M02_ID, "gate MapInfo keeps the M02 contract")
	network._handle_message(JSON.stringify(_state(["ward_reached", "companion_released"], _arrival("party_departed", 4), "in_progress", [], 1, 22, true)))
	_expect(network.mission.get("state", {}).get("m02", {}).get("gate_mask") == 1, "the opened world accepts the next objective")
	network._handle_message(JSON.stringify(_map(3.0)))
	network._handle_message(JSON.stringify(_state([], _arrival("ward_reached", -4), "in_progress", [], 1, 25)))
	_expect(network.mission.is_empty() and network.mission_geometry.is_empty(), "a gate refresh cannot hide rewound progress")
	var fresh: CaptureNetwork = CaptureNetwork.new()
	fresh._handle_message(JSON.stringify(info))
	fresh._handle_message(JSON.stringify(_state(["ward_reached", "companion_released"], _arrival("party_departed", 4), "in_progress", [], 1, 30, true)))
	_expect(fresh.mission.get("state", {}).get("m02", {}).get("gate_mask") == 1, "a late reader accepts current progress")
	fresh.player_id = PLAYER
	var manager: Node = load("res://scripts/game_manager.gd").new()
	manager.net_client = fresh
	manager.is_human_player = true
	manager.current_map_info = info
	manager._awaiting_map = false
	manager._opening_finished = true
	_expect(manager._mission_map(), "the M02 marker is a mission map")
	_expect(not manager._mission_controls_blocked(), "a ready M02 member plays")
	fresh.mission["state"]["phase"] = "briefing"
	_expect(manager._mission_controls_blocked(), "the M02 briefing still holds input")
	manager.free()
	fresh.free()
	network.free()
	await process_frame

func _hud(first: Dictionary, ward_fight: Dictionary, use: Dictionary, exit: Dictionary, done: Dictionary) -> void:
	var hud: MissionHud = MissionHud.new()
	root.add_child(hud)
	hud.apply(first["state"], PLAYER)
	_expect(_lines(hud) == 1 and hud._copy.text == tr("M02_OBJECTIVE_WARD_REACHED"), "ward approach shows one line: " + hud._copy.text)
	hud._process(MissionHud.STAGE_SECONDS + 0.1)
	_expect(_lines(hud) == 0, "the objective line leaves after the stage")
	hud.apply(ward_fight["state"], PLAYER)
	_expect(_lines(hud) == 1 and hud._copy.text == tr("M02_OBJECTIVE_COMPANION_RELEASED") and not hud._prompt.visible,
		"ward guards block the restraint prompt")
	hud.apply(use["state"], PLAYER)
	_expect(_lines(hud) == 1 and hud._copy.text == tr("M02_OBJECTIVE_COMPANION_SECURED") and hud._prompt.visible
		and hud.prompt_text == InputGlyphs.plain(tr("M02_USE_COMPANION_RELEASED")) and hud.prompt_text == "F: OPEN LATCH'S RESTRAINT",
		"a legal use shows only the prompt: " + hud.prompt_text)
	hud.apply(use["state"], "00000000-0000-0000-0000-000000000009")
	_expect(not hud._prompt.visible, "another participant's prompt stays private")
	hud.apply(exit["state"], PLAYER)
	_expect(_lines(hud) == 1 and hud._copy.text == tr("M02_OBJECTIVE_PARTY_DEPARTED"), "the exit objective replaces the use line")
	hud.apply(done["state"], PLAYER)
	hud._process(MissionHud.STAGE_SECONDS + 0.1)
	_expect(_lines(hud) == 1 and hud._copy.text == InputGlyphs.plain(tr("M02_DEPARTED")) and hud._copy.text == "OUT. ESC TO LEAVE.", "departure keeps one line")
	var unknown: Dictionary = use["state"].duplicate(true)
	unknown["m02"]["current"]["id"] = "later_objective"
	unknown["prompts"] = []
	hud.apply(unknown, PLAYER)
	_expect(hud._copy.text == tr("M02_OBJECTIVE_UNKNOWN"), "an unregistered objective uses neutral copy")
	for key: String in ["M02_OBJECTIVE_WARD_REACHED", "M02_OBJECTIVE_COMPANION_RELEASED", "M02_OBJECTIVE_COMPANION_SECURED",
		"M02_OBJECTIVE_PARTY_DEPARTED", "M02_OBJECTIVE_UNKNOWN",
		"M02_USE_CONSOLE", "M02_USE_COMPANION_RELEASED", "M02_WAITING", "M02_DEPARTED",
		"MISSION_M02_GRAYBOX", "MENU_M02_DEVELOPMENT", "MENU_EXIT_DEVELOPMENT"]:
		_expect(tr(key) != key and not tr(key).contains("\n"), "localized single line: " + key)
	hud.queue_free()

func _lines(hud: MissionHud) -> int:
	var count: int = 0
	if hud.visible and hud._card.visible and not hud._copy.text.is_empty():
		count += hud._copy.text.count("\n") + 1
	if hud.visible and hud._prompt.visible and not hud.prompt_text.is_empty():
		count += hud.prompt_text.count("\n") + 1
	return count


## Controls read without English: lamps are registered pictograms, every keyed
## string exists, and a raised gate produces a positioned sound.
func _readable(info: Dictionary) -> void:
	var lamps: Array = [
		{"solid": 1, "face": "north", "center": [0, 0], "size": [0.8, 0.8], "kind": "gate_locked"},
		{"solid": 0, "face": "north", "center": [0, 0], "size": [0.5, 0.5], "kind": "gate_open"}]
	_expect(MapDecoration.validation_error(lamps, info["solids"]).is_empty(), "gate lamps are registered kinds")
	var parent: Node3D = Node3D.new()
	root.add_child(parent)
	ArenaDecoration.build(parent, info["solids"], lamps)
	var locked: MeshInstance3D = parent.get_node("Detail_0_gate_locked")
	var opened: MeshInstance3D = parent.get_node("Detail_1_gate_open")
	_expect((locked.material_override as ShaderMaterial).get_shader_parameter("style") == 7
		and (opened.material_override as ShaderMaterial).get_shader_parameter("style") == 8, "locked and open lamps draw distinct pictograms")
	_expect(locked.get_node_or_null("Copy") == null and opened.get_node_or_null("Copy") == null, "lamps carry no text")
	parent.queue_free()
	_expect(WorldSign.localized("NOT_A_REGISTERED_KEY").is_empty(), "a missing key yields no copy instead of the raw key")
	var keys: Array[String] = []
	keys.append_array(ArenaDecoration.SIGN_KEYS.values())
	for id: String in MissionHud.M02_KNOWN:
		keys.append(MissionHud.objective_key(id))
		keys.append(MissionHud.use_key(id))
	for key: String in keys:
		_expect(not WorldSign.localized(key).is_empty(), "catalog has world or HUD key: " + key)
