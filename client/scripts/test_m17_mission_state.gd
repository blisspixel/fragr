extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000001717"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m17_mission_state: " + message)

static func fixture_map() -> Dictionary:
	var solids: Array = [
		{"min_x": -28.0, "max_x": -24.0, "min_z": -14.0, "max_z": -11.0, "bottom": 0.0, "top": 1.1},
		{"min_x": -25.0, "max_x": -23.0, "min_z": 15.0, "max_z": 17.0, "bottom": 0.0, "top": 1.2},
		{"min_x": -3.0, "max_x": 3.0, "min_z": 30.0, "max_z": 33.0, "bottom": 0.0, "top": 1.2},
		{"min_x": 30.0, "max_x": 44.0, "min_z": 0.0, "max_z": 44.0, "bottom": 0.0, "top": 4.5},
	]
	var decorations: Array = [
		{"solid": 0, "face": "south", "center": [0, 0], "size": [0.6, 0.4], "kind": "terminal"},
		{"solid": 1, "face": "south", "center": [0, 0], "size": [0.6, 0.4], "kind": "terminal"},
		{"solid": 2, "face": "north", "center": [0, 0], "size": [1.5, 0.6], "kind": "terminal"},
		{"solid": 3, "face": "west", "center": [16, -0.5], "size": [0.8, 0.6], "kind": "terminal"},
	]
	var kessel_desk: Dictionary = {"decoration": 0, "approach": [-26.0, 0.0, -9.5]}
	var core_override: Dictionary = {"decoration": 1, "approach": [-24.0, 0.0, 18.5]}
	var voss_rostrum: Dictionary = {"decoration": 2, "approach": [0.0, 0.0, 28.5]}
	var departure: Dictionary = {"decoration": 3, "approach": [28.5, 0.0, 38.0]}
	var objectives: Array = [
		{"id": "approach_breached", "action": {"kind": "arrival", "region": {"min": [-6.0, 0.0, -22.0], "max": [6.0, 4.0, -14.0]}, "feet": [0.0, 0.0, -17.0]}},
		{"id": "hall_secured", "action": {"kind": "arrival", "region": {"min": [-16.0, 0.0, -18.0], "max": [16.0, 4.0, -2.0]}, "feet": [0.0, 0.0, -10.0]}},
		{"id": "kessel_secured", "action": {"kind": "use", "target": kessel_desk}},
		{"id": "core_unsealed", "action": {"kind": "use", "target": core_override}},
		{"id": "core_defeated", "action": {"kind": "arrival", "region": {"min": [-12.0, 0.0, 20.0], "max": [12.0, 4.0, 32.0]}, "feet": [0.0, 0.0, 26.0]}},
		{"id": "voss_captured", "action": {"kind": "use", "target": voss_rostrum}},
	]
	return {
		"type": "map_info",
		"map_id": 1017,
		"map_name": "Peace Without Interruption",
		"geometry_version": 2,
		"half_extent": 48.0,
		"solids": solids,
		"presentation": {
			"ground": "concrete",
			"solids": ["enamel", "service_steel", "records_tile", "enamel"],
			"decorations": decorations,
		},
		"m17": {
			"objectives": objectives,
			"departure": departure,
			"boarding": {"min": [20.0, 0.0, 34.0], "max": [29.5, 4.5, 42.0]},
			"kessel_desk": kessel_desk,
			"core_override": core_override,
			"voss_rostrum": voss_rostrum,
			"core_unsealed": false,
			"voss_captured": false,
		}
	}

static func fixture_state(info: Dictionary, stage: int = 0, tick: int = 10) -> Dictionary:
	var order: Array[String] = M17MissionState.OBJECTIVES.duplicate()
	order.append("party_departed")
	var progress: Dictionary = {
		"completed": order.slice(0, stage),
		"challenges": {
			"approach_breached": stage >= 1,
			"kessel_secured": stage >= 3,
			"core_defeated": stage >= 5,
			"voss_captured": stage >= 6,
		},
		"core_unsealed": stage >= 4,
		"voss_captured": stage >= 6,
		"kessel_secured": stage >= 3,
		"brief_completed": stage >= 5,
		"custody_started": tick - 5 if stage >= 6 else null,
	}
	if stage < 6:
		progress["current"] = info["m17"]["objectives"][stage].duplicate(true)
	elif stage == 6:
		progress["current"] = {"id": "party_departed", "action": {"kind": "use", "target": info["m17"]["departure"].duplicate(true)}}
	return {
		"type": "mission",
		"tick": tick,
		"state": {
			"id": MissionState.M17_ID,
			"rules": {"difficulty": "standard", "revision": 4},
			"attempt": 1,
			"phase": "departed" if stage == 7 else "in_progress",
			"changed_at": tick,
			"party": [{"id": PLAYER, "name": "Office runner", "ready": true, "alive": true, "aboard": stage >= 6}],
			"prompts": [],
			"m17": progress,
		}
	}

static func figure_row(id: String, kind: String, at: Vector3) -> Dictionary:
	return {"id": id, "name": "Voss" if kind == "voss" else "Coalition", "x": at.x, "y": at.y + 1.5, "z": at.z, "yaw": 0.0,
		"hp": 100, "weapon": "Fists", "campaign": {"side": "figure", "kind": kind}}

## Voss's custody: the server's tick, its order against the capture, the
## staged figures in the snapshot, and lines said once from the start only.
func _custody(info: Dictionary, geometry: Dictionary) -> void:
	var matching: Dictionary = geometry.duplicate(true)
	matching["m17"]["core_unsealed"] = true
	var waiting: Dictionary = fixture_state(info, 5, 80)
	waiting["state"]["m17"]["custody_started"] = 70
	_check(MissionState.validation_error(waiting, matching).is_empty(), "custody under way before she is taken validates")
	var early: Dictionary = fixture_state(info, 4, 80)
	early["state"]["m17"]["custody_started"] = 70
	_check(not MissionState.validation_error(early, matching).is_empty(), "custody before the core falls is refused")
	var future: Dictionary = fixture_state(info, 5, 80)
	future["state"]["m17"]["custody_started"] = 81
	_check(not MissionState.validation_error(future, matching).is_empty(), "custody from the future is refused")
	var taken: Dictionary = fixture_state(info, 6, 90)
	taken["state"]["m17"]["custody_started"] = null
	var captured: Dictionary = matching.duplicate(true)
	captured["m17"]["voss_captured"] = true
	_check(not MissionState.validation_error(taken, captured).is_empty(), "a capture without custody is refused")
	var missing: Dictionary = fixture_state(info, 5, 80)
	missing["state"]["m17"].erase("custody_started")
	_check(not MissionState.validation_error(missing, matching).is_empty(), "custody_started is required")

	# Staged figures cross the actor boundary; extra or armed ones do not.
	var rows: Array = [
		figure_row("v", "voss", Vector3(4.2, 0, 31.6)),
		figure_row("a", "coalition", Vector3(23, 0, 25.6)),
		figure_row("b", "coalition", Vector3(23, 0, 28.4)),
	]
	_check(ActorState.validation_error({"tick": 100, "players": rows}).is_empty(), "Voss and two coalition people validate")
	_check(ActorState.participants(rows).is_empty(), "figures are never participants")
	var two: Array = rows.duplicate(true)
	two.append(figure_row("w", "voss", Vector3(0, 0, 0)))
	_check(not ActorState.validation_error({"tick": 100, "players": two}).is_empty(), "a second Voss is refused")
	var armed: Array = rows.duplicate(true)
	armed[1]["weapon"] = "Tack"
	_check(not ActorState.validation_error({"tick": 100, "players": armed}).is_empty(), "an armed figure is refused")
	var odd: Array = rows.duplicate(true)
	odd[0]["campaign"]["kind"] = "chancellor"
	_check(not ActorState.validation_error({"tick": 100, "players": odd}).is_empty(), "an unknown figure is refused")

	var presenter: M17Office = M17Office.new()
	root.add_child(presenter)
	presenter.configure_map(info)
	_check(presenter.has_node("ChamberScreenCaption"), "the chamber screen carries its official caption")
	var said: Array[String] = []
	presenter.caption.line_said.connect(func(text: String) -> void: said.append(text))
	presenter.apply_state(waiting["state"])
	presenter.apply_snapshot({"tick": 71.0, "players": rows})
	_check(presenter.figure_count() == 3, "the presenter dresses Voss and both coalition people")
	_check(said.size() == M17Office.VOSS_LINES.size() and said[2] == tr("M17_VOSS_RUN_IT"), "Voss says her three lines once, from the start")
	presenter.apply_snapshot({"tick": 90.0, "players": rows})
	_check(said.size() == M17Office.VOSS_LINES.size(), "the lines are not said twice")
	presenter.apply_snapshot({"tick": 91.0, "players": [rows[0]]})
	_check(presenter.figure_count() == 1, "a figure gone from the snapshot is gone from the room")
	# A retry: nobody has come for her yet; the next custody speaks again.
	var retry: Dictionary = fixture_state(info, 5, 200)["state"]
	retry["attempt"] = 2
	presenter.apply_state(retry)
	retry["m17"]["custody_started"] = 210
	presenter.apply_state(retry)
	presenter.apply_snapshot({"tick": 212.0, "players": rows})
	_check(said.size() == M17Office.VOSS_LINES.size() * 2, "a retried custody is said again")
	presenter.clear_map()
	# Seen first long after it began (a late join), nothing is restaged.
	presenter.configure_map(info)
	var late_said: Array[String] = []
	presenter.caption.line_said.connect(func(text: String) -> void: late_said.append(text))
	presenter.apply_state(waiting["state"])
	presenter.apply_snapshot({"tick": 70.0 + M17Office.LATE_TICKS, "players": rows})
	_check(late_said.is_empty(), "a late joiner sees the custody but hears no lines")
	presenter.queue_free()

func _run() -> void:
	var info: Dictionary = fixture_map()
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "fixture office map crosses client boundary")
	var geometry: Dictionary = MissionState.geometry_for(info)
	_check(geometry.get("id") == MissionState.M17_ID, "geometry_for produces M17 geometry")

	var unsealed_info: Dictionary = info.duplicate(true)
	unsealed_info["m17"]["core_unsealed"] = true
	var unsealed_geometry: Dictionary = MissionState.geometry_for(unsealed_info)
	_check(M17MissionState.same_contract(geometry, unsealed_geometry), "core_unsealed flag change preserves contract")

	var modified_info: Dictionary = info.duplicate(true)
	modified_info["m17"]["boarding"]["max"][0] += 5.0
	var modified_geometry: Dictionary = MissionState.geometry_for(modified_info)
	_check(not M17MissionState.same_contract(geometry, modified_geometry), "boarding change alters contract")

	for stage: int in range(8):
		var msg: Dictionary = fixture_state(info, stage, 10 + stage * 10)
		var matching: Dictionary = geometry.duplicate(true)
		matching["m17"]["core_unsealed"] = stage >= 4
		matching["m17"]["voss_captured"] = stage >= 6
		_check(MissionState.validation_error(msg, matching).is_empty(), "valid stage %d validates" % stage)
		if stage >= 4:
			_check(not MissionState.validation_error(msg, geometry).is_empty(), "changed stage waits for matching map")

	var briefing: Dictionary = fixture_state(info, 0, 5)
	briefing["state"]["phase"] = "briefing"
	briefing["state"]["party"] = []
	_check(MissionState.validation_error(briefing, geometry).is_empty(), "briefing state validates")

	var premature_core: Dictionary = fixture_state(info, 0, 10)
	premature_core["state"]["m17"]["challenges"]["core_defeated"] = true
	premature_core["state"]["m17"]["challenges"]["approach_breached"] = false
	_check(not MissionState.validation_error(premature_core, geometry).is_empty(), "core defeat without approach breach rejected")

	var presenter: M17Office = M17Office.new()
	var hud: MissionHud = MissionHud.new()
	hud.geometry = geometry
	for stage: int in [1, 3, 4, 5, 6]:
		var optional: Dictionary = fixture_state(info, stage, 100)["state"]["m17"]
		optional["kessel_secured"] = false
		optional["challenges"]["kessel_secured"] = false
		var desk: Array = info["m17"]["kessel_desk"]["approach"]
		hud.feet = Vector3(desk[0], desk[1], desk[2])
		_check(hud._m17_use_label(optional) == hud._catalog("M17_USE_KESSEL"), "optional Kessel use retains its target label at stage %d" % stage)
		if stage == 3:
			var control: Array = info["m17"]["core_override"]["approach"]
			hud.feet = Vector3(control[0], control[1], control[2])
			_check(hud._m17_use_label(optional) == hud._catalog("M17_USE_CORE"), "same stage names the actual nearby core control")
	hud.free()
	presenter.configure_map(info)
	var notices: Array[String] = []
	presenter.notice_requested.connect(func(text: String) -> void: notices.append(text))
	presenter.apply_state(fixture_state(info, 3, 30)["state"])
	_check(presenter._kessel_secured and notices.size() == 1, "presenter fires kessel secured notice")
	presenter.apply_state(fixture_state(info, 4, 40)["state"])
	_check(presenter._core_unsealed and notices.size() == 2, "presenter fires core unsealed notice")
	_check(presenter._bulkhead_lights.size() == 4 and presenter._bulkhead_lights.all(func(lamp: MeshInstance3D) -> bool: return (lamp.material_override as StandardMaterial3D).albedo_color == Color("2ed158")), "gallery bulkhead lamps turn green with the override")
	presenter.apply_state(fixture_state(info, 6, 60)["state"])
	_check(presenter._voss_captured and notices.size() == 2, "Voss's capture is the walk out, not a banner")
	presenter.clear_map()
	presenter.free()
	_custody(info, geometry)

	if failures > 0:
		push_error("test_m17_mission_state FAILED with %d failures" % failures)
		quit(1)
	else:
		print("test_m17_mission_state: PASS native facts, office sequence and rooftop departure")
		quit(0)
