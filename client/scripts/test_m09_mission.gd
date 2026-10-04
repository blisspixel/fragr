extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000000009"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m09_mission: " + message)

static func fixture_map(opened: bool = false) -> Dictionary:
	var objectives: Array[Dictionary] = []
	for index: int in M09MissionState.ARRIVALS:
		var x: float = -30.0 + index * 5.0
		objectives.append({"id": M09MissionState.OBJECTIVES[index], "action": {"kind": "arrival", "feet": [x, 0, 0], "region": {"min": [x - 1, 0, -1], "max": [x + 1, 2, 1]}}})
	var crew: Array[Dictionary] = []
	for index: int in range(M09MissionState.CREW.size()):
		crew.append({"id": M09MissionState.CREW[index], "route": [[-10 + index, 0, -12], [-2 + index, 0, 10]], "held_until": [0, 7]})
	return {"type": "map_info", "map_id": 1009, "map_name": "Passenger Manifest", "geometry_version": 2, "half_extent": 50,
		"solids": [
			{"min_x": -1, "max_x": 1, "min_z": 6, "max_z": 7, "bottom": 4 if opened else 0, "top": 7 if opened else 3},
			{"min_x": -2, "max_x": 2, "min_z": -10, "max_z": -9, "bottom": 0, "top": 3},
			{"min_x": -2, "max_x": 2, "min_z": 12, "max_z": 13, "bottom": 0, "top": 3}],
		"presentation": {"ground": "concrete", "solids": ["service_steel", "enamel", "enamel"], "decorations": [
			{"solid": 1, "face": "north", "center": [0, 0], "size": [1, 1], "kind": "lift_control"},
			{"solid": 2, "face": "north", "center": [0, 0], "size": [1, 1], "kind": "lift_control"}]},
		"m09": {"objectives": objectives, "crew_release": {"decoration": 0, "approach": [0, 0, -12]},
			"crew": crew, "departure": {"decoration": 1, "approach": [0, 0, 10]},
			"boarding": {"min": [-4, 0, 8], "max": [4, 2, 12]}, "companion_start": [-4, 0, -20], "hatch": 0, "hatch_open": opened}}

static func fixture_state(info: Dictionary, done: int = 0, cast: Array[String] = []) -> Dictionary:
	var crew: Array[Dictionary] = []
	for definition: Dictionary in info["m09"]["crew"]:
		if definition["id"] in ["edda", "splice"] and definition["id"] not in cast:
			continue
		crew.append({"id": definition["id"], "feet": definition["route"][0], "aboard": false})
	var completed: Array = M09MissionState.OBJECTIVES.slice(0, mini(done, 8))
	if done == 9:
		completed.append("party_departed")
	var facts: Dictionary = {"completed": completed, "crew_released": done >= 3, "crew": crew, "hatch_open": done >= 7, "charge_falls": 0}
	if done < 9:
		facts["current"] = M09MissionState.step(info["m09"], done)
	return {"type": "mission", "tick": 40, "state": {"id": MissionState.M09_ID, "rules": {"difficulty": "standard", "revision": 3},
		"attempt": 1, "phase": "departed" if done == 9 else "in_progress", "changed_at": 10,
		"party": [{"id": PLAYER, "name": "Visitor", "ready": true, "alive": true, "aboard": done >= 8}], "prompts": [], "m09": facts}}

func _run() -> void:
	var info: Dictionary = fixture_map()
	_check(MissionState.map_error(info).is_empty(), "the closed berth is registered")
	var geometry: Dictionary = MissionState.geometry_for(info)
	var first: Dictionary = fixture_state(info)
	_check(MissionState.validation_error(first, geometry).is_empty(), "first fight binds the berth")
	var casts: Array[Array] = [[], ["edda"], ["splice"], ["edda", "splice"]]
	for raw_cast: Array in casts:
		var cast: Array[String] = []
		cast.assign(raw_cast)
		_check(MissionState.validation_error(fixture_state(info, 0, cast), geometry).is_empty(), "recorded optional cast accepted: " + str(cast))
	var bad: Dictionary = info.duplicate(true)
	bad["m08"] = {}
	_check(not MissionState.map_error(bad).is_empty(), "mixed mission map refused")
	bad = info.duplicate(true)
	bad["m09"]["hatch_open"] = true
	_check(not MissionState.map_error(bad).is_empty(), "an open flag cannot replace physical clearance")
	bad = info.duplicate(true)
	bad["m09"]["crew"][0]["held_until"][1] = 2
	_check(not MissionState.map_error(bad).is_empty(), "crew cannot move before actual release")
	bad = first.duplicate(true)
	bad["state"]["m09"]["crew"][0]["feet"][0] += 0.5
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "a forged crew location is refused")
	bad = first.duplicate(true)
	bad["state"]["m09"]["crew"][0]["id"] = "enforcer"
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "human enemy is not a rescued crew member")
	bad = fixture_state(info, 3)
	bad["state"]["m09"]["crew"][0]["feet"] = info["m09"]["crew"][0]["route"][1]
	bad["state"]["m09"]["crew"][0]["aboard"] = true
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "held route segments cannot be skipped")
	var opened: Dictionary = fixture_map(true)
	var opened_geometry: Dictionary = MissionState.geometry_for(opened)
	var current: Dictionary = fixture_state(opened, 7)
	_check(M09MissionState.same_contract(geometry, opened_geometry), "the raised hatch preserves the static berth")
	_check(not MissionState.validation_error(current, geometry).is_empty(), "new facts require the changed map first")
	_check(MissionState.validation_error(current, opened_geometry, first).is_empty(), "matching raised map accepts the facts")
	_check(not MissionState.validation_error(first, geometry, current).is_empty(), "an attempt cannot rewind")
	var unknown: Dictionary = first.duplicate(true)
	unknown["state"]["m09"]["carried_archive"] = {"kind": "historical_unrecorded"}
	_check(MissionState.validation_error(unknown, geometry).is_empty(), "historical archive choices remain unknown")
	bad = unknown.duplicate(true)
	bad["state"]["m09"]["carried_archive"]["captives_evacuated"] = false
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "unknown history cannot invent a result")
	bad = unknown.duplicate(true)
	bad["state"]["m09"]["carried_archive"] = {"kind": "recorded", "custody_released": false, "recovered_mind_secured": true, "captives_evacuated": true}
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "evacuation requires recorded release")
	_check(not MissionState.validation_error(first, geometry, unknown).is_empty(), "retry cannot erase carried history")
	var departure: Dictionary = fixture_state(opened, 8)
	departure["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	_check(MissionState.validation_error(departure, opened_geometry).is_empty(), "ready living aboard party can use the exit")
	bad = departure.duplicate(true)
	bad["state"]["party"][0]["alive"] = false
	bad["state"]["party"][0]["aboard"] = false
	_check(not MissionState.validation_error(bad, opened_geometry).is_empty(), "dead party cannot own an exit prompt")
	bad = departure.duplicate(true)
	bad["state"]["rules"]["difficulty"] = "severe"
	_check(MissionState.validation_error(bad, opened_geometry).is_empty(), "zero falls cannot block the optional Severe challenge's departure")
	bad["state"]["m09"]["charge_falls"] = 1
	_check(MissionState.validation_error(bad, opened_geometry).is_empty(), "actual optional challenge evidence remains valid")
	_check(MissionState.validation_error(fixture_state(opened, 9), opened_geometry).is_empty(), "real terminal prefix is accepted")
	var berth: M09Berth = M09Berth.new()
	root.add_child(berth)
	berth.configure_map(info)
	berth.apply_state(fixture_state(info, 0, ["edda", "splice"])["state"])
	_check(berth.state_applied == 1 and berth._crew.size() == 5, "only actual carried cast is shown")
	var tern: Sprite3D = berth._crew["tern"]
	var earlier_position: Vector3 = tern.position
	berth.apply_state(bad["state"])
	_check(tern.position == earlier_position and berth.state_applied == 1, "mismatched hatch facts cannot steer presentation")
	berth.configure_map(opened)
	var walking: Dictionary = fixture_state(opened, 7, ["edda", "splice"])
	walking["state"]["m09"]["crew"][0]["feet"] = opened["m09"]["crew"][0]["route"][1]
	walking["state"]["m09"]["crew"][0]["aboard"] = true
	berth.apply_state(walking["state"])
	_check(berth._crew["tern"].position == Vector3(-2, EnemyAnimation.CENTRE_HEIGHT, 10), "presented feet follow the recorded route")
	berth._process(0.05)
	berth.clear_map()
	_check(berth._crew.is_empty() and berth._geometry.is_empty() and berth.get_child_count() == 0, "map retirement removes every passenger")
	berth.queue_free()
	var hud: MissionHud = MissionHud.new()
	root.add_child(hud)
	hud.apply(fixture_state(info, 2)["state"], PLAYER)
	_check(hud._copy.text == tr("M09_OBJECTIVE_CREW_FREED") and not hud._copy.text.contains("M09_"), "crew progress uses keyed copy")
	hud.apply(departure["state"], PLAYER)
	_check(hud.prompt_text == tr("M09_USE_DEPARTURE"), "only the actual exit prompt shows departure")
	var optional: Dictionary = departure["state"].duplicate(true)
	optional["rules"]["difficulty"] = "severe"
	hud.apply(optional, PLAYER)
	_check(hud._evac_badge.visible and hud._evac_badge.text == tr("M09_OPTIONAL_FALL") and hud.prompt_text == tr("M09_USE_DEPARTURE"), "optional challenge remains visible without hiding the usable exit")
	optional["m09"]["charge_falls"] = 1
	hud.apply(optional, PLAYER)
	_check(hud._evac_badge.text == tr("M09_OPTIONAL_FALL_DONE"), "only actual fall evidence completes the optional badge")
	hud.apply(departure["state"], PLAYER)
	_check(not hud._evac_badge.visible, "Standard does not inherit the Severe optional badge")
	hud.queue_free()
	_check(StoryScene.exists("m09_arrival") and StoryScene.exists("l09_l10") and StoryScene.BEFORE_MISSION.get(MissionState.M09_ID) == "m09_arrival", "arrival and departure reuse the story boundary")
	_check(LocalMatch.MISSION_GAMEPLAY.get(MissionState.M09_ID) == 34 and LocalMatch.NEXT_MISSION == "common_carrier", "the berth is playable and M10 stays pending")
	await process_frame
	await process_frame
	if failures == 0:
		print("test_m09_mission: PASS")
	quit(0 if failures == 0 else 1)
