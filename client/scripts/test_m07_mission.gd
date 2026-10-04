extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000000002"
var failures: int = 0
var _retiring_chimes: Array[WeakRef] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "user://m07-mission-%d.cfg" % OS.get_process_id())
	_run.call_deferred()

func _finalize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(get_meta("fragr_settings_path"))))

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m07_mission: " + message)

static func _arrival(id: String, x: float) -> Dictionary:
	return {"id": id, "action": {"kind": "arrival", "feet": [x, 0, 0],
		"region": {"min": [x - 1, 0, -1], "max": [x + 1, 2, 1]}}}

static func fixture_map() -> Dictionary:
	var objectives: Array[Dictionary] = []
	for index: int in range(5):
		objectives.append(_arrival(M07MissionState.OBJECTIVES[index], -20.0 + index * 6.0))
	return {"type": "map_info", "map_id": 1007, "map_name": "Declared Goods", "geometry_version": 2, "half_extent": 48,
		"solids": [{"min_x": -35, "max_x": -30, "min_z": 10, "max_z": 12, "bottom": 1.0, "top": 4.0},
			{"min_x": 9, "max_x": 11, "min_z": 24, "max_z": 25, "top": 2.0},
			{"min_x": -10, "max_x": -6, "min_z": -12, "max_z": -10, "top": 3.0},
			{"min_x": 0, "max_x": 4, "min_z": -30, "max_z": -26, "top": 1.0}],
		"presentation": {"ground": "service_steel", "solids": ["concrete", "lift_panel", "concrete", "concrete"], "decorations": [
			{"solid": 1, "face": "north", "center": [0, 0], "size": [1.5, 0.8], "kind": "m07_depot_freight"},
			{"solid": 0, "face": "south", "center": [0, -0.3], "size": [4.6, 2.2], "kind": "m07_shutter_row"},
			{"solid": 0, "face": "east", "center": [0, 0.8], "size": [1.2, 1.1], "kind": "m07_window_figure"},
			{"solid": 2, "face": "south", "center": [-1, 1.0], "size": [0.6, 0.6], "kind": "m07_curfew_lamp"},
			{"solid": 2, "face": "south", "center": [1, 1.0], "size": [0.6, 0.6], "kind": "m07_curfew_lamp"},
			{"solid": 2, "face": "north", "center": [0, 1.0], "size": [0.6, 0.6], "kind": "m07_curfew_lamp"},
			{"solid": 3, "face": "up", "center": [0, 0], "size": [3.2, 2.4], "kind": "m07_market_stall"},
			{"solid": 2, "face": "east", "center": [0, 0], "size": [1.4, 0.8], "kind": "m07_curfew_notice"}]},
		"m07": {"objectives": objectives,
			"departure": {"decoration": 0, "approach": [10, 0, 23]},
			"boarding": {"min": [8, 0, 20], "max": [12, 2, 24]}, "companion_start": [-25, 0, 0]}}

static func fixture_state(info: Dictionary, count: int = 0, tick: int = 20) -> Dictionary:
	return {"type": "mission", "tick": tick, "state": {"id": MissionState.M07_ID, "rules": {"difficulty": "standard", "revision": 3},
		"attempt": 1, "phase": "in_progress", "changed_at": 10,
		"party": [{"id": PLAYER, "name": "Traveller", "ready": true, "alive": true, "aboard": count == 5}], "prompts": [],
		"m07": {"completed": M07MissionState.OBJECTIVES.slice(0, count), "current": info["m07"]["objectives"][count] if count < 5 else {
			"id": "party_departed", "action": {"kind": "use", "target": info["m07"]["departure"]}},
			"carried_recall_cars": ["roof_car", "platform_car"], "carried_patients": ["edda_team_a"], "carried_photos": 2,
			"carried_released_workers": ["workshop_agent_b", "splice", "workshop_agent_a"], "carried_evacuated_workers": ["workshop_agent_a", "splice"],
			"carried_prisoner_route_marked": true}}}

func _run() -> void:
	var info: Dictionary = fixture_map()
	var geometry: Dictionary = MissionState.geometry_for(info)
	var first: Dictionary = fixture_state(info)
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "town envelope with five ordered objectives accepted")
	_check(MissionState.validation_error(first, geometry).is_empty(), "carried M03 to M06 outcomes ride the town wire")
	for field: String in ["m08", "m06", "m05", "m04", "m03"]:
		var conflicting: Dictionary = info.duplicate(true)
		conflicting[field] = {}
		_check(not MissionState.map_error(conflicting).is_empty(), "mixed mission envelope rejected: " + field)
	var bad: Dictionary = info.duplicate(true)
	bad["m07"]["objectives"][1]["id"] = "ring_cleared"
	_check(not MissionState.map_error(bad).is_empty(), "duplicate objective cannot replace the plaza")
	bad = info.duplicate(true)
	bad["map_id"] = 1006
	_check(not MissionState.map_error(bad).is_empty(), "town facts are bound to their map")
	bad = info.duplicate(true)
	bad["solids"][0]["max_z"] = 13
	_check(not M07MissionState.same_contract(geometry, MissionState.geometry_for(bad)), "static town cannot replace collision under retained facts")
	for patch: Dictionary in [{"completed": ["plaza_cleared"]}, {"carried_prisoner_route_marked": "true"},
		{"carried_released_workers": ["splice"]}, {"carried_evacuated_workers": ["unknown"]},
		{"carried_patients": ["edda_team_a", "edda_team_a"]}, {"carried_photos": -1}, {"current": null}]:
		bad = first.duplicate(true)
		bad["state"]["m07"].merge(patch, true)
		_check(not MissionState.validation_error(bad, geometry).is_empty(), "strict town facts refuse " + str(patch))
	var post: Dictionary = fixture_state(info, 3, 21)
	_check(MissionState.validation_error(post, geometry, first).is_empty(), "ordered progress through the curfew post")
	bad = post.duplicate(true)
	bad["state"]["m07"]["carried_prisoner_route_marked"] = false
	_check(not MissionState.validation_error(bad, geometry, first).is_empty(), "progress cannot forget the M06 route outcome")
	bad = first.duplicate(true)
	bad["tick"] = 19
	_check(not MissionState.validation_error(bad, geometry, first).is_empty(), "out-of-order mission facts rejected")
	var retry: Dictionary = fixture_state(info, 0, 22)
	retry["state"]["attempt"] = 2
	retry["state"]["phase"] = "briefing"
	_check(MissionState.validation_error(retry, geometry, post).is_empty(), "retry resets the prefix and retains carried outcomes")
	var end: Dictionary = fixture_state(info, 5, 30)
	end["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	_check(MissionState.validation_error(end, geometry, post).is_empty(), "freight prompt requires the cleared cut and a ready living party")
	bad = end.duplicate(true)
	bad["state"]["party"][0]["aboard"] = false
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "departure refuses an absent party member")
	bad = fixture_state(info, 4, 30)
	bad["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	_check(not MissionState.validation_error(bad, geometry).is_empty(), "no freight prompt before the cut is clear")
	end["state"]["phase"] = "departed"
	end["state"]["prompts"] = []
	end["state"]["m07"]["completed"].append("party_departed")
	end["state"]["m07"].erase("current")
	_check(MissionState.validation_error(end, geometry, post).is_empty(), "resolved departure omits current and keeps carried choices")
	_check(not M07MissionState.lamps_lit(first["state"]["m07"]) and M07MissionState.lamps_lit(post["state"]["m07"]), "lamps follow the authoritative post clear")
	await _presentation(info, first, post, end)
	if failures == 0:
		print("test_m07_mission: PASS strict town facts/carry/retry, HUD objectives and freight prompt, lamp line, chime, window figure and presenter lifecycle")
	quit(0 if failures == 0 else 1)

func _presentation(info: Dictionary, first: Dictionary, post: Dictionary, end: Dictionary) -> void:
	var hud: MissionHud = MissionHud.new()
	root.add_child(hud)
	hud.apply(first["state"], PLAYER)
	_check(hud._copy.text == tr("M07_OBJECTIVE_RING_CLEARED") and not hud._evac_badge.visible, "HUD follows the authoritative first objective")
	hud.apply(post["state"], PLAYER)
	_check(hud._copy.text == tr("M07_OBJECTIVE_WINDOW_CLEARED"), "HUD names the roof window lesson after the post")
	var prompt: Dictionary = fixture_state(info, 5, 31)
	prompt["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	hud.apply(prompt["state"], PLAYER)
	_check(hud.prompt_text.contains(tr("M07_USE_FREIGHT")), "freight intake prompt is localized: " + hud.prompt_text)
	hud.apply(end["state"], PLAYER)
	_check(hud._copy.text == InputGlyphs.plain(tr("M07_DEPARTED")), "departure copy resolves")
	var town: M07Town = M07Town.new()
	root.add_child(town)
	var notices: Array[String] = []
	town.notice_requested.connect(func(copy: String) -> void: notices.append(copy))
	town.configure_map(info)
	_check(town._root != null and town.lamps.size() == 3 and town.lamps_lit_count == 0, "three curfew lamps start dark")
	_check(town._root.find_child("ShutterRow", true, false) != null and town._root.find_child("MarketAwning", true, false) != null,
		"shutters and a market awning present their registered faces")
	_check(town._root.find_child("DepotRadialTower", true, false) != null and town._root.find_child("PressureDomeShell", true, false) != null
		and town._root.find_child("PortBehind", true, false) != null, "depot tower, pressure dome and the port behind stand outside play")
	_check(town.figure != null and town.figure.find_child("Resident", true, false) is Sprite3D, "the silent window figure is a presentation sprite")
	_check(town.chime != null and town.chime.stream != null and town.chime.stream.resource_path == L07Assets.CURFEW_CHIME_SOUND,
		"curfew chime uses its committed sound")
	var tower: MeshInstance3D = town._root.find_child("TowerShaft", true, false) as MeshInstance3D
	_check(tower != null and tower.global_position.x > float(info["half_extent"]), "the depot tower stands beyond the playable square")
	town.apply_state(first["state"])
	town._process(0.0)
	_check(town.chime_count == 1 and notices == [tr("WORLD_M07_CURFEW_PA")], "the first chime reads the PA line once")
	_track_chime(town)
	await create_timer(0.1).timeout
	town._process(M07Town.CHIME_SECONDS * 0.5)
	_check(town.chime_count == 1, "no second chime before the interval")
	town._process(M07Town.CHIME_SECONDS * 0.5)
	_check(town.chime_count == 2 and notices.size() == 1, "chime repeats every thirty seconds without repeating the PA text")
	_track_chime(town)
	await create_timer(0.1).timeout
	town.apply_state(post["state"])
	_check(town.lamps_lit_count == 1 and notices.back() == tr("WORLD_M07_LATCH_LINE"), "a real post clear lights the first lamp and gives Latch's line")
	var light: OmniLight3D = town.lamps[0]["light"]
	_check(light.visible and not (town.lamps[1]["light"] as OmniLight3D).visible, "lamps light one by one")
	town._process(M07Town.LAMP_INTERVAL)
	_check(town.lamps_lit_count == 2, "second lamp follows the interval")
	town._process(M07Town.LAMP_INTERVAL * 2.0)
	_check(town.lamps_lit_count == 3, "the line finishes toward the cut")
	town.apply_state(post["state"])
	_check(notices.count(tr("WORLD_M07_LATCH_LINE")) == 1, "redundant facts do not replay Latch's line")
	var retry: Dictionary = first["state"].duplicate(true)
	retry["attempt"] = 2
	town.apply_state(retry)
	_check(town.lamps_lit_count == 0, "a retry restores the dark street")
	var hand: Vector3 = town.figure_hand.position
	town.listener_position = town._figure_origin + Vector3(3, 0, 0)
	town._animate_figure(0.3)
	_check(town.figure_active and town.figure_hand.position != hand, "near the window she taps the glass")
	town._animate_figure(1.3)
	_check(town.figure_hand.position.z > hand.z, "then points along the side street")
	var joiner: M07Town = M07Town.new()
	root.add_child(joiner)
	joiner.configure_map(info)
	joiner.apply_state(post["state"])
	_check(joiner.lamps_lit_count == 3, "joining after the post shows the finished lamp line at once")
	# Retire any playback the automatic presenter process started, including a
	# late join's first chime, before dropping the corresponding nodes.
	_track_chime(town)
	_track_chime(joiner)
	town.configure_map({})
	_check(town._root == null and town.lamps.is_empty() and town.figure == null and town.chime_count == 0, "map handoff clears the town")
	town.configure_map(MissionState.geometry_for(info))
	_check(town._root == null, "a geometry projection is not a map envelope")
	hud.queue_free()
	town.queue_free()
	joiner.queue_free()
	await process_frame
	# Mixer retirement is independent of process frames. Observe the actual
	# release as the rendered tour does, instead of guessing a fixed delay.
	var deadline: int = Time.get_ticks_msec() + 2000
	while not _retiring_chimes.is_empty() and Time.get_ticks_msec() < deadline:
		for index: int in range(_retiring_chimes.size() - 1, -1, -1):
			if _chime_retired(_retiring_chimes[index]):
				_retiring_chimes.remove_at(index)
		if not _retiring_chimes.is_empty():
			await create_timer(0.01).timeout
	_check(_retiring_chimes.is_empty(), "stopped chime playbacks retire before process exit")

func _track_chime(town: M07Town) -> void:
	if is_instance_valid(town.chime) and town.chime.has_stream_playback():
		_retiring_chimes.append(weakref(town.chime.get_stream_playback()))

static func _chime_retired(reference: WeakRef) -> bool:
	return reference.get_ref() == null
