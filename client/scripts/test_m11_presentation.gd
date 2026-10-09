extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000000011"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_m11_presentation: " + message)

static func fixture_map() -> Dictionary:
	var objectives: Array[Dictionary] = []
	for id: String in M11MissionState.OBJECTIVES:
		objectives.append({"id": id, "action": {"kind": "arrival", "feet": [0, 0, 0], "region": {"min": [-1, 0, -1], "max": [1, 2, 1]}}})
	var details: Array[Dictionary] = []
	for kind: String in ["m11_transfer_release", "m11_records_document", "m11_stern_release"]:
		details.append({"solid": 0, "face": "south", "center": [float(details.size()) - 1, 0], "size": [0.6, 0.4], "kind": kind})
	return {"type": "map_info", "map_id": 1011, "map_name": "Right of Search", "geometry_version": 2, "half_extent": 20,
		"solids": [{"min_x": -3, "max_x": 3, "min_z": -4, "max_z": -3, "bottom": 0, "top": 3}],
		"presentation": {"ground": "service_steel", "solids": ["enamel"], "decorations": details},
		"m11": {"objectives": objectives, "transfer_release": {"decoration": 0, "approach": [-1, 0, -1]}, "records_document": {"decoration": 1, "approach": [0, 0, -1]},
			"departure": {"decoration": 2, "approach": [1, 0, -1]}, "boarding": {"min": [-2, 0, -2], "max": [2, 2, 0]},
			"companion_start": [-4, 0, 0], "transfer_people": [[3, 0, 0], [5, 0, 0], [7, 0, 0]]}}

static func fixture_state(info: Dictionary) -> Dictionary:
	return {"type": "mission", "tick": 50, "state": {"id": MissionState.M11_ID, "rules": {"difficulty": "standard", "revision": MissionState.RULES_REVISION}, "attempt": 1,
		"phase": "in_progress", "changed_at": 10, "party": [{"id": PLAYER, "name": "Tender visitor", "ready": true, "alive": true, "aboard": false}], "prompts": [],
		"m11": {"completed": [], "current": info["m11"]["objectives"][0].duplicate(true), "challenges": {"transfer_released": false, "records_read": false, "counter_boarder_blast_kills": 0}}}}

func _run() -> void:
	var info: Dictionary = fixture_map()
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "registered tender is accepted by shared map boundary")
	var geometry: Dictionary = MissionState.geometry_for(info)
	var first: Dictionary = fixture_state(info)
	_check(MissionState.validation_error(first, geometry).is_empty(), "shared mission dispatch admits bound M11 facts")
	var bad: Dictionary = first.duplicate(true)
	bad["state"]["m11"]["current"]["action"]["feet"][0] = 0.2
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "plausible shifted target cannot replace the authored route")
	bad = info.duplicate(true)
	bad["m10"] = {}
	_check(not MissionState.map_error(bad).is_empty(), "mixed mission maps refuse")
	var later: Dictionary = first.duplicate(true)
	later["state"]["m11"]["completed"] = M11MissionState.OBJECTIVES.slice(0, 3)
	later["state"]["m11"]["current"] = info["m11"]["objectives"][3].duplicate(true)
	later["state"]["m11"]["challenges"]["transfer_released"] = true
	_check(MissionState.validation_error(later, geometry, first).is_empty(), "actual optional transfer release is accepted")
	bad = later.duplicate(true)
	bad["state"]["m11"]["challenges"]["transfer_released"] = false
	_check(not MissionState.validation_error(bad, geometry, later).is_empty(), "release receipt cannot rewind within the attempt")
	var tender: M11Tender = M11Tender.new()
	root.add_child(tender)
	tender.configure_map(info)
	tender.apply_state(first["state"])
	_check(tender._people.size() == 3 and tender.state_applied == 1, "three anonymous people are placed from accepted geometry")
	tender.clear_map()
	_check(tender._people.is_empty() and tender.get_child_count() == 0, "map retirement clears transferred people")
	tender.queue_free()
	var hud: MissionHud = MissionHud.new()
	root.add_child(hud)
	hud.apply(first["state"], PLAYER)
	_check(hud._copy.text == tr("M11_OBJECTIVE_ARMORY_FOUND"), "HUD uses the current authoritative objective")
	hud.queue_free()
	var effects: RemoteMineEffects = RemoteMineEffects.new()
	root.add_child(effects)
	var charge: Dictionary = {"id": 11, "owner_id": PLAYER, "position": [1, 0.4, 2], "normal": [0, 1, 0], "phase": "arming", "phase_started": 10, "phase_ends": 50}
	effects.apply({"tick": 20, "remote_mines": [charge]})
	_check(effects.bodies.size() == 1 and effects.lamps_lit == 1, "actual charge has distinct body and arming lamp")
	charge["phase"] = "armed"; charge["phase_started"] = 50; charge["phase_ends"] = 50
	effects.apply({"tick": 50, "remote_mines": [charge]})
	_check(effects.phases.get(11) == "armed", "authoritative armed phase updates the body")
	charge["phase"] = "triggered"; charge["phase_started"] = 51; charge["phase_ends"] = 55
	effects.apply({"tick": 51, "remote_mines": [charge]})
	_check(effects.lamps_lit == 0, "trigger lamp follows exact server tick")
	effects.apply({"tick": 55, "remote_mines": []})
	_check(effects.bodies.is_empty(), "resolved disappearance retires charge body")
	effects.queue_free()
	var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/union/redactor-manifest.json"))
	_check(FileAccess.get_sha256("res://assets/characters/union/redactor.png") == receipt["sha256"], "Redactor atlas binds bake receipt")
	_check(FileAccess.get_sha256("res://assets/characters/union/redactor_normals.png") == receipt["normals_sha256"], "Redactor normals bind the same poses")
	_check(EnemyView.atlas_path("redactor").ends_with("/redactor.png"), "Redactor never borrows another enemy silhouette")
	_check(LocalMatch.MISSION_GAMEPLAY.get(MissionState.M11_ID) == LocalMatch.M11_GAMEPLAY and LocalMatch.M11_GAMEPLAY == 43 and StoryScene.exists("m11_arrival"), "current rules capability and story handoff are registered")
	var tender_steel: ShaderMaterial = ArenaMaterials.authored("service_steel", "right_of_search") as ShaderMaterial
	_check(tender_steel.get_shader_parameter("tile_enabled") == true and tender_steel.get_shader_parameter("trim_glow") == 0.0, "custody tender has actual quiet steel tiles")
	_check(EnvironmentTextures.path_for("enamel", "right_of_search") != EnvironmentTextures.path_for("enamel", "common_carrier"), "custody wall source differs from the civilian Carrier")
	await process_frame
	await process_frame
	if failures == 0:
		print("test_m11_presentation: PASS")
	quit(0 if failures == 0 else 1)
