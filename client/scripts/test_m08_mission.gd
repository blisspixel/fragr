extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000000008"
const NET = preload("res://scripts/net_client.gd")
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://m08-mission-%d.cfg" % OS.get_process_id())
	_run.call_deferred()

func _finalize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(get_meta("fragr_settings_path"))))

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m08_mission: " + message)

static func _arrival(id: String, x: float, y: float = 0.0) -> Dictionary:
	return {"id": id, "action": {"kind": "arrival", "feet": [x, y, 0],
		"region": {"min": [x - 1, y, -1], "max": [x + 1, y + 2, 1]}}}

static func _box(min_x: float, max_x: float, min_z: float, max_z: float, bottom: float, top: float) -> Dictionary:
	return {"min_x": min_x, "max_x": max_x, "min_z": min_z, "max_z": max_z, "bottom": bottom, "top": top}

## A compact archive contract: machine, seal, four nodes and the freight car.
static func fixture_map(seal_open: bool = false, fallen: bool = false) -> Dictionary:
	var objectives: Array[Dictionary] = []
	for index: int in range(M08MissionState.ARRIVALS.size()):
		objectives.append(_arrival(M08MissionState.OBJECTIVES[M08MissionState.ARRIVALS[index]], -30.0 + index * 6.0))
	var solids: Array = [_box(-2, 2, -2, 2, 6.6, 8.6), _box(-6.3, -6, -16, -12, 6, 9)]
	var nodes: Array = []
	for corner: Vector2 in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var x: float = corner.x * 4.6
		var z: float = corner.y * 4.6
		solids.append(_box(x - 0.4, x + 0.4, z - 0.4, z + 0.4, 7, 7.8))
		nodes.append({"solid": solids.size() - 1, "approach": [x, 6, z + 4.0 * corner.y], "aim": [x, 7.4, z]})
	solids.append(_box(-3, 3, 34, 37.5, 0, 2.4))
	return {"type": "map_info", "map_id": 1008, "map_name": "Custodian of Record", "geometry_version": 2, "half_extent": 40,
		"solids": solids,
		"presentation": {"ground": "concrete", "solids": ["service_steel", "lift_panel", "lift_panel", "lift_panel", "lift_panel", "lift_panel", "service_steel"],
			"decorations": [
				{"solid": 6, "face": "north", "center": [0, 0], "size": [1.4, 1], "kind": "m08_freight_departure"},
				{"solid": 1, "face": "east", "center": [0, 0.5], "size": [1.2, 1], "kind": "m08_seal_open" if seal_open else "m08_seal_locked"},
				{"solid": 6, "face": "south", "center": [0, 0], "size": [3, 1], "kind": "m08_authorized_noise"},
				{"solid": 6, "face": "north", "center": [0, 0], "size": [2.6, 0.9], "kind": "m08_registry"},
				{"solid": 6, "face": "south", "center": [0, 0], "size": [1.6, 1.2], "kind": "m08_bay_release"}]},
		"m08": {"objectives": objectives, "nodes": nodes, "machine": 0, "seal": 1,
			"bays": _arrival(M08MissionState.BAYS, 10, 3), "cabinet": _arrival(M08MissionState.CABINET, 14, 6),
			"departure": {"decoration": 0, "approach": [0, 0, 32.5]},
			"boarding": {"min": [-4, 0, 30.5], "max": [4, 2, 34]}, "companion_start": [-3, 0, -34],
			"seal_open": seal_open, "machine_fallen": fallen}}

static func fixture_state(info: Dictionary, done: int = 0, extra: Dictionary = {}) -> Dictionary:
	var hp: Array = [50, 50, 50, 50] if done <= M08MissionState.MACHINE_STEP else [0, 0, 0, 0]
	var facts: Dictionary = {"completed": M08MissionState.OBJECTIVES.slice(0, done), "node_hp": hp,
		"seal_open": done > 3, "machine_fallen": done > M08MissionState.MACHINE_STEP,
		"custodian_joined": done >= 2, "custody_released": false, "recovered_mind_secured": false,
		"transfer_evidence": done > 5, "captives_evacuated": false}
	facts.merge(extra, true)
	facts["current"] = M08MissionState.step(info["m08"], done, facts["node_hp"])
	return {"type": "mission", "tick": 40, "state": {"id": MissionState.M08_ID, "rules": {"difficulty": "standard", "revision": 3},
		"attempt": 1, "phase": "in_progress", "changed_at": 10,
		"party": [{"id": PLAYER, "name": "Visitor", "ready": true, "alive": true, "aboard": done == 7}], "prompts": [],
		"m08": facts}}

func _run() -> void:
	var info: Dictionary = fixture_map()
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "the archive contract is accepted")
	var geometry: Dictionary = MissionState.geometry_for(info)
	_check(geometry.get("id") == MissionState.M08_ID, "the archive binds its own mission id")
	_check(MissionState.validation_error(fixture_state(info), geometry).is_empty(), "a fresh archive attempt is accepted")
	var bad: Dictionary = info.duplicate(true)
	bad["m06"] = {}
	_check(not MissionState.map_error(bad).is_empty(), "a mixed mission envelope is refused")
	bad = info.duplicate(true)
	bad["m08"]["nodes"][1]["solid"] = bad["m08"]["nodes"][0]["solid"]
	_check(not MissionState.map_error(bad).is_empty(), "two nodes cannot share a solid")
	bad = info.duplicate(true)
	bad["m08"]["machine"] = 1
	_check(not MissionState.map_error(bad).is_empty(), "the machine is not the seal")
	bad = info.duplicate(true)
	bad["m08"]["machine_fallen"] = true
	_check(not MissionState.map_error(bad).is_empty(), "the machine cannot fall behind a closed seal")
	bad = info.duplicate(true)
	bad["presentation"]["decorations"][0]["kind"] = "lift_control"
	_check(not MissionState.map_error(bad).is_empty(), "the departure is the registered freight control")
	bad = info.duplicate(true)
	bad["map_id"] = 1006
	_check(not MissionState.map_error(bad).is_empty(), "the archive is map 1008")
	# The machine step: the seal is lifted and the next intact node is the target.
	var lifted: Dictionary = fixture_map(true)
	var lifted_geometry: Dictionary = MissionState.geometry_for(lifted)
	var machine: Dictionary = fixture_state(lifted, 4)
	_check(MissionState.validation_error(machine, lifted_geometry).is_empty(), "the machine step names the first node")
	_check(machine["state"]["m08"]["current"]["action"]["kind"] == "shoot", "nodes are shot, not used")
	var hurt: Dictionary = fixture_state(lifted, 4, {"node_hp": [0, 30, 50, 50]})
	_check(MissionState.validation_error(hurt, lifted_geometry).is_empty()
		and hurt["state"]["m08"]["current"]["action"]["solid"] == lifted["m08"]["nodes"][1]["solid"], "a broken node passes the target on")
	_check(not MissionState.validation_error(machine, geometry).is_empty(), "facts must agree with the bound stage")
	for patch: Dictionary in [{"node_hp": [10, 50, 50, 50]}, {"seal_open": true}, {"custodian_joined": true},
			{"custody_released": true}, {"captives_evacuated": true}, {"transfer_evidence": true}]:
		_check(not MissionState.validation_error(fixture_state(info, 0, patch), geometry).is_empty(), "forged fact refused: " + str(patch))
	var released: Dictionary = fixture_state(lifted, 4, {"custody_released": true, "recovered_mind_secured": true})
	_check(MissionState.validation_error(released, lifted_geometry).is_empty(), "optional rescues follow the lifted seal")
	var stale: Dictionary = fixture_state(lifted, 4)
	stale["state"]["m08"]["current"] = lifted["m08"]["objectives"][2]
	_check(not MissionState.validation_error(stale, lifted_geometry).is_empty(), "a forged current objective is refused")
	var regressed: Dictionary = fixture_state(lifted, 4, {"node_hp": [0, 50, 50, 50]})
	_check(not MissionState.validation_error(regressed, lifted_geometry, hurt).is_empty(), "a node never heals inside an attempt")
	_check(M08MissionState.same_contract(MissionState.geometry_for(info), lifted_geometry), "only the stage flags move between stages")
	var moved: Dictionary = fixture_map(true)
	moved["m08"]["companion_start"] = [0, 0, -34]
	_check(not M08MissionState.same_contract(lifted_geometry, MissionState.geometry_for(moved)), "the static contract cannot move")
	# HUD lines read keyed copy, with the mine key glyph in the lesson.
	var hud: MissionHud = MissionHud.new()
	root.add_child(hud)
	hud.player_id = PLAYER
	hud.apply(fixture_state(info, 2)["state"], PLAYER)
	_check(not hud._copy.text.is_empty() and not hud._copy.text.contains("{mine}") and not hud._copy.text.contains("M08_"), "the mine lesson line is keyed and shows the key")
	_check(not hud._evac_badge.visible, "optional rescues stay quiet before the seal lifts")
	hud.apply(released["state"], PLAYER)
	_check(hud._evac_badge.visible and hud._evac_badge.text.contains(tr("M08_BAYS_RELEASED")), "released bays read after the seal lifts")
	hud.queue_free()
	# The archive presenter follows the same facts.
	var archive: M08Archive = M08Archive.new()
	root.add_child(archive)
	archive.configure_map(lifted)
	_check(archive.node_lamps.size() == 4 and archive.node_arms.size() == 4, "four glowing nodes hold the machine")
	_check(archive.noise_lamp != null, "the authorized noise panel has its rhythm lamp")
	archive.apply_state(hurt["state"])
	_check(archive.state_applied == 1, "validated facts reach the presenter")
	var fallen_info: Dictionary = fixture_map(true, true)
	archive.apply_state(fixture_state(fallen_info, 6)["state"])
	_check(archive.falling != null and not archive.node_arms[0].visible, "the machine drops once its last node breaks")
	archive._process(M08Archive.FALL_SECONDS + 0.1)
	_check(archive.falling == null, "the falling machine settles on the shaft floor")
	archive._process(0.05)
	archive.clear_map()
	_check(archive.node_lamps.is_empty() and archive.get_child_count() == 0, "clearing the map removes the archive dressing")
	archive.queue_free()
	_check(StoryScene.BEFORE_MISSION.get(MissionState.M08_ID) == "m08_arrival" and StoryScene.exists("m08_arrival")
		and StoryScene.AFTER_MISSION.get(MissionState.M08_ID) == "l08_l09" and StoryScene.exists("l08_l09"), "keyed arrival and departure pages exist")
	_check(tr("MISSION_M08_TITLE") != "MISSION_M08_TITLE" and tr("WORLD_M08_AUTHORIZED_NOISE") != "WORLD_M08_AUTHORIZED_NOISE", "archive words are keyed")
	_check(LocalMatch.MISSION_GAMEPLAY.get(MissionState.M08_ID) == 31 and NET.GAMEPLAY_VERSION == 36, "the archive retains capability 31 while the client supports the Repeater contract")
	await process_frame
	if failures == 0:
		print("test_m08_mission: PASS strict archive contract, stage flags, node targets, rescues, HUD, presenter and pages")
	quit(0 if failures == 0 else 1)
