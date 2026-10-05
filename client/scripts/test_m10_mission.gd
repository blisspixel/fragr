extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000000010"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_m10_mission: " + message)

static func fixture_map() -> Dictionary:
	var objectives: Array[Dictionary] = []
	for index: int in range(4):
		var x: float = -12.0 + index * 5.0
		objectives.append({"id": M10MissionState.OBJECTIVES[index], "action": {"kind": "arrival", "feet": [x, 0, 0], "region": {"min": [x - 1, 0, -1], "max": [x + 1, 2, 1]}}})
	var passengers: Array[Dictionary] = []
	for i: int in range(4):
		passengers.append({"id": M10MissionState.PASSENGERS[i], "feet": [-6 + i * 3, 0, 6]})
	return {"type": "map_info", "map_id": 1010, "map_name": "Common Carrier", "geometry_version": 2, "half_extent": 24,
		"solids": [{"min_x": -2, "max_x": 2, "min_z": -2, "max_z": -1, "bottom": 0, "top": 3}],
		"presentation": {"ground": "service_steel", "solids": ["enamel"], "decorations": [{"solid": 0, "face": "north", "center": [0, 0], "size": [1, 1], "kind": "m10_ship_confirmation"}]},
		"m10": {"objectives": objectives, "departure": {"decoration": 0, "approach": [0, 0, -4]}, "boarding": {"min": [-1, 0, -5], "max": [1, 2, -3]},
			"pilot": [-4, 0, -4], "companion_start": [4, 0, -4], "passengers": passengers}}

static func fixture_state(info: Dictionary, done: int = 0, arrivals: Array[String] = []) -> Dictionary:
	var transit: Dictionary = {"kind": "historical_unrecorded"} if arrivals.is_empty() else {"kind": "recorded", "arrived_crew": arrivals.duplicate()}
	var people: Array[Dictionary] = []
	for person: Dictionary in info["m10"]["passengers"]:
		if person["id"] in arrivals:
			people.append(person.duplicate(true))
	var completed: Array = M10MissionState.OBJECTIVES.slice(0, mini(done, 4))
	if done == 5:
		completed.append("party_departed")
	var facts: Dictionary = {"completed": completed, "transit": transit, "pilot": info["m10"]["pilot"].duplicate(), "passengers": people}
	if done < 5:
		facts["current"] = info["m10"]["objectives"][done] if done < 4 else {"id": "party_departed", "action": {"kind": "use", "target": info["m10"]["departure"]}}
	return {"type": "mission", "tick": 40, "state": {"id": MissionState.M10_ID, "rules": {"difficulty": "standard", "revision": 3}, "attempt": 1, "phase": "departed" if done == 5 else "in_progress", "changed_at": 10,
		"party": [{"id": PLAYER, "name": "Ship visitor", "ready": true, "alive": true, "aboard": done >= 4}], "prompts": [], "m10": facts}}

func _run() -> void:
	var info: Dictionary = fixture_map()
	var wrong_control: Dictionary = info.duplicate(true)
	wrong_control["presentation"]["decorations"][0]["kind"] = "lift_control"
	_check(not M10MissionState.map_error(wrong_control).is_empty(), "generic lift panel cannot impersonate the ship confirmation")
	_check(MissionState.map_error(info).is_empty(), "M10 owns a separate map contract")
	var geometry: Dictionary = MissionState.geometry_for(info)
	var first: Dictionary = fixture_state(info)
	_check(MissionState.validation_error(first, geometry).is_empty(), "unknown old transit does not omit the current pilot")
	var rosters: Array[Array] = [["tern", "berth_crew_a", "berth_crew_b"], ["tern", "berth_crew_a", "berth_crew_b", "edda"], ["tern", "berth_crew_a", "berth_crew_b", "splice"], ["tern", "berth_crew_a", "berth_crew_b", "edda", "splice"]]
	for raw: Array in rosters:
		var roster: Array[String] = []
		roster.assign(raw)
		for done: int in range(6):
			_check(MissionState.validation_error(fixture_state(info, done, roster), geometry).is_empty(), "real canonical transit roster and ordered stage accepted")
	var bad: Dictionary = info.duplicate(true)
	bad["m09"] = {}
	_check(not MissionState.map_error(bad).is_empty(), "mixed berth map refused")
	bad = info.duplicate(true)
	bad["m10"]["passengers"][0]["id"] = "orrin"
	_check(not MissionState.map_error(bad).is_empty(), "a secured cabinet cannot silently introduce a restored person")
	bad = first.duplicate(true)
	bad["state"]["m10"]["passengers"].append(info["m10"]["passengers"][2])
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "unknown history cannot invent Edda aboard")
	bad = first.duplicate(true)
	bad["state"]["m10"]["transit"]["arrived_crew"] = []
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "unknown does not serialize as guessed empty arrivals")
	var known: Dictionary = fixture_state(info, 0, ["tern", "berth_crew_a", "berth_crew_b"])
	_check(not MissionState.validation_error(known, geometry, first).is_empty(), "historical missing facts cannot become recorded midway")
	bad = known.duplicate(true)
	bad["state"]["m10"]["transit"]["arrived_crew"].append("berth_crew_b")
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "duplicate arrivals refused")
	bad = known.duplicate(true)
	bad["state"]["m10"]["pilot"][0] += 0.5
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "pilot feet bind the authored map")
	bad = known.duplicate(true)
	bad["state"]["m10"]["current"] = info["m10"]["objectives"][1]
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "future encounter objective cannot be forged")
	var later: Dictionary = fixture_state(info, 2)
	_check(not MissionState.validation_error(first, geometry, later).is_empty(), "an attempt cannot rewind")
	var unknown_archive: Dictionary = first.duplicate(true)
	unknown_archive["state"]["m10"]["carried_archive"] = {"kind": "historical_unrecorded"}
	_check(MissionState.validation_error(unknown_archive, geometry).is_empty(), "archive history remains separately unknown")
	_check(not MissionState.validation_error(first, geometry, unknown_archive).is_empty(), "archive facts cannot disappear during retry")
	bad = info.duplicate(true)
	bad["m10"]["pilot"][0] += 0.5
	_check(not M10MissionState.same_contract(geometry, MissionState.geometry_for(bad)), "static pilot contract changes refused")
	var ship: M10Ship = M10Ship.new()
	root.add_child(ship)
	ship.configure_map(info)
	ship.apply_state(first["state"])
	_check(ship._figures.keys() == ["tern"], "unknown history stages only current pilot")
	var actual_pilot: Sprite3D = ship._figures["tern"]
	_check(actual_pilot.texture == load(PlayerBody.strip_path(PlayerBody.SYNTHETIC)), "current pilot retains an embodied-agent body even with unknown historical transit")
	ship.apply_state(fixture_state(info, 0, ["tern", "berth_crew_a", "berth_crew_b", "edda", "splice"])["state"])
	_check(ship._figures.size() == 5 and ship._figures.has("edda") and ship._figures.has("splice"), "only recorded actual arrivals appear")
	for id: String in ["tern", "splice"]:
		var actual_agent: Sprite3D = ship._figures[id]
		_check(actual_agent.texture == load(PlayerBody.strip_path(PlayerBody.SYNTHETIC)), id + " retains its embodied-agent body on the ship")
	for id: String in ["edda", "berth_crew_a", "berth_crew_b"]:
		var actual_human: Sprite3D = ship._figures[id]
		_check(actual_human.texture == load(PlayerBody.strip_path(PlayerBody.HUMAN)), id + " retains the human ship body fallback")
	ship.clear_map()
	_check(ship._geometry.is_empty() and ship._figures.is_empty() and ship.get_child_count() == 0, "map retirement removes all occupants")
	ship.queue_free()
	var hud: MissionHud = MissionHud.new()
	root.add_child(hud)
	hud.apply(first["state"], PLAYER)
	_check(hud._copy.text == tr("M10_OBJECTIVE_FORWARD_SECURED"), "ship objective uses keyed copy")
	var ready: Dictionary = fixture_state(info, 4)
	ready["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	hud.apply(ready["state"], PLAYER)
	_check(hud.prompt_text == InputGlyphs.plain(tr("M10_USE_DEPARTURE")), "only physical server prompt offers confirmation")
	hud.queue_free()
	_check(StoryScene.exists("m10_arrival") and StoryScene.exists("l10_l11") and StoryScene.BEFORE_MISSION.get(MissionState.M10_ID) == "m10_arrival", "story uses established dismissal/readiness seam")
	_check(LocalMatch.MISSION_GAMEPLAY.get(MissionState.M10_ID) == 36 and preload("res://scripts/net_client.gd").GAMEPLAY_VERSION == 36 and LocalMatch.NEXT_MISSION == "right_of_search", "strict capability and honest pending M11")
	await process_frame
	await process_frame
	if failures == 0:
		print("test_m10_mission: PASS")
	quit(0 if failures == 0 else 1)
