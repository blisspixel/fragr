extends SceneTree

const PLAYER: String = "00000000-0000-0000-0000-000000000002"
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m03_mission: " + message)

func _map(shutdown: bool = false) -> Dictionary:
	return {"type": "map_info", "map_id": 1003, "map_name": "Scheduled Service: rail yard prototype", "geometry_version": 2, "half_extent": 40,
		"solids": [{"min_x": -1, "max_x": 1, "bottom": 0 if shutdown else 4, "top": 1 if shutdown else 5, "min_z": 2 if shutdown else 0, "max_z": 4 if shutdown else 1},
			{"min_x": 4, "max_x": 6, "bottom": 0, "top": 1.2, "min_z": 6, "max_z": 7}],
		"presentation": {"ground": "concrete", "solids": ["service_steel", "lift_panel"], "decorations": [
			{"solid": 1, "face": "north", "center": [0, 0], "size": [1.6, 0.8], "kind": "lift_control"}]},
		"m03": {"mast": {"solid": 0, "approach": [0, 0, -3], "aim": [0, 4.5, 0.5]}, "mast_shutdown": shutdown,
			"departure": {"decoration": 0, "approach": [5, 0, 5]}, "boarding": {"min": [2, 0, 3], "max": [8, 2, 10]},
			"companion_start": [0, 0, -10], "cars": [{"id": "platform_car", "release": {"min": [8, 0, -2], "max": [12, 1, 2]},
				"held": [[10, 0, 0], [11, 0, 0]], "safe": [[10, 0, 10], [11, 0, 10]]}]}}

func _state(info: Dictionary, hp: int = 40, secured: bool = false, train: bool = false, phase: String = "in_progress", freed: bool = false, attempt: int = 1, tick: int = 20) -> Dictionary:
	var progress: Dictionary = {"mast_hp": hp, "mast_secured": secured, "train_secured": train,
		"cars": [{"id": "platform_car", "released": freed, "captives": info["m03"]["cars"][0]["safe" if freed else "held"].duplicate(true)}]}
	if phase != "departed":
		progress["current"] = {"id": "mast_disabled", "action": {"kind": "shoot", "solid": 0, "approach": [0, 0, -3], "aim": [0, 4.5, 0.5]}} if hp > 0 else {"id": "party_departed", "action": {"kind": "use", "target": info["m03"]["departure"].duplicate(true)}}
	return {"type": "mission", "tick": tick, "state": {"id": MissionState.M03_ID, "rules": {"difficulty": "standard", "revision": MissionState.RULES_REVISION}, "attempt": attempt,
		"phase": phase, "changed_at": 10, "m03": progress,
		"party": [{"id": PLAYER, "name": "Walker", "ready": phase != "briefing", "alive": true, "aboard": hp == 0 and train}], "prompts": []}}

func _invalid(message: Dictionary, geometry: Dictionary, description: String, previous: Dictionary = {}) -> void:
	_check(not MissionState.validation_error(message, geometry, previous).is_empty(), description)

func _run() -> void:
	var info: Dictionary = _map()
	var fallen: Dictionary = _map(true)
	_check(MapGeometry.validation_error(info).is_empty() and MissionState.map_error(info).is_empty(), "intact M03 MapInfo validates")
	_check(MapGeometry.validation_error(fallen).is_empty() and MissionState.map_error(fallen).is_empty(), "fallen mast retains original aim in its bound contract")
	var geometry: Dictionary = MissionState.geometry_for(info)
	var fallen_geometry: Dictionary = MissionState.geometry_for(fallen)
	_check(M03MissionState.same_contract(geometry, fallen_geometry), "mast world handoff retains static target and car contract")
	var replaced: Dictionary = fallen_geometry.duplicate(true)
	replaced["m03"]["departure"]["approach"] = [6, 0, 5]
	_check(not M03MissionState.same_contract(geometry, replaced), "same-map replacement cannot rebind its departure")
	for patch: Dictionary in [{"mast_shutdown": 1}, {"mast_shutdown": null}, {"extra": true}, {"cars": "bad"}, {"companion_start": [INF, 0, 0]},
		{"boarding": {"min": [0, 0, 0], "max": [0, 1, 1]}}, {"departure": {"decoration": 99, "approach": [5, 0, 5]}},
		{"mast": {"solid": 99, "approach": [0, 0, -3], "aim": [0, 4.5, 0.5]}}, {"mast": {"solid": 0, "approach": [0, 0, -3], "aim": [20, 4.5, 0.5]}}]:
		var bad: Dictionary = info.duplicate(true)
		bad["m03"].merge(patch, true)
		_check(not MissionState.map_error(bad).is_empty(), "malformed M03 map refused: " + str(patch))
	for patch: Dictionary in [{"map_id": 1002}, {"mission": {}}, {"m02_objectives": 3}, {"m03": null}]:
		var bad: Dictionary = info.duplicate(true)
		bad.merge(patch, true)
		_check(not MissionState.map_error(bad).is_empty(), "mixed or missing M03 map identity refused")
	var duplicate: Dictionary = info.duplicate(true)
	duplicate["m03"]["cars"].append(duplicate["m03"]["cars"][0].duplicate(true))
	_check(not MissionState.map_error(duplicate).is_empty(), "duplicate car IDs refused")
	duplicate["m03"]["cars"].resize(5)
	_check(not MissionState.map_error(duplicate).is_empty(), "unbounded car list refused")
	var message: Dictionary = _state(info)
	_check(MissionState.validation_error(message, geometry).is_empty(), "real-shaped intact Shoot goal validates")
	_check(MissionState.validation_error(_state(info, 40, false, false, "briefing"), geometry).is_empty(), "unread arrival state validates")
	for patch: Dictionary in [{"id": MissionState.M02_ID}, {"phase": "reach_lift"}, {"attempt": 0}, {"changed_at": 21}, {"extra": 1}, {"m02": {}}, {"party": [null]}, {"rules": {"difficulty": "standard", "revision": 1}}]:
		var bad: Dictionary = message.duplicate(true)
		bad["state"].merge(patch, true)
		_invalid(bad, geometry, "malformed outer state refused: " + str(patch))
	for patch: Dictionary in [{"mast_hp": 41}, {"mast_hp": -1}, {"mast_hp": true}, {"mast_hp": 39}, {"mast_secured": 1}, {"train_secured": null}, {"extra": 1}, {"cars": []}, {"current": null}]:
		var bad: Dictionary = message.duplicate(true)
		bad["state"]["m03"].merge(patch, true)
		_invalid(bad, geometry, "malformed progress refused: " + str(patch))
	for patch: Dictionary in [{"solid": 1}, {"kind": "use"}, {"aim": [0, 4.5, 0.6]}, {"approach": [0, 0, -2]}, {"extra": 1}]:
		var bad: Dictionary = message.duplicate(true)
		bad["state"]["m03"]["current"]["action"].merge(patch, true)
		_invalid(bad, geometry, "Shoot goal must match its registered target exactly")
	for patch: Dictionary in [{"id": "other"}, {"released": 1}, {"captives": [[NAN, 0, 0], [11, 0, 0]]}, {"captives": [[10, 0, 1], [11, 0, 0]]}]:
		var bad: Dictionary = message.duplicate(true)
		bad["state"]["m03"]["cars"][0].merge(patch, true)
		_invalid(bad, geometry, "captive poses bind to held or released map feet")
	var freed: Dictionary = _state(info, 40, true, false, "in_progress", true, 1, 30)
	_check(MissionState.validation_error(freed, geometry, message).is_empty(), "automatic local car release validates before mast damage")
	var walking: Dictionary = freed.duplicate(true)
	walking["state"]["m03"]["cars"][0]["captives"] = [[10, 0, 5], [11, 0, 0]]
	_check(MissionState.validation_error(walking, geometry, message).is_empty(), "released captives may stand or walk anywhere along their authoritative escape segment")
	for feet: Array in [[10.1, 0, 5], [10, 0.1, 5], [10, 0, 11], [41, 0, 5]]:
		var bad: Dictionary = walking.duplicate(true)
		bad["state"]["m03"]["cars"][0]["captives"][0] = feet
		_invalid(bad, geometry, "released captive cannot leave its route or playable bounds")
	var diagonal: Dictionary = info.duplicate(true)
	diagonal["m03"]["cars"][0]["safe"][0] = [20, 0, 10]
	var diagonal_geometry: Dictionary = MissionState.geometry_for(diagonal)
	var off_segment: Dictionary = _state(diagonal, 40, true, false, "in_progress", true)
	off_segment["state"]["m03"]["cars"][0]["captives"][0] = [10, 0, 10]
	_invalid(off_segment, diagonal_geometry, "axis-aligned bounding box alone does not prove the diagonal escape segment")
	_invalid(message, geometry, "late mission tick refused", freed)
	var backwards: Dictionary = _state(info, 40, true, false, "in_progress", false, 1, 31)
	_invalid(backwards, geometry, "released car cannot be recaptured within an attempt", freed)
	var damaged: Dictionary = _state(info, 20, true, false, "in_progress", true, 1, 32)
	_check(MissionState.validation_error(damaged, geometry, freed).is_empty(), "resolved pod damage validates")
	_invalid(_state(info, 40, true, false, "in_progress", true, 1, 33), geometry, "pod health cannot increase within one attempt", damaged)
	var disabled: Dictionary = _state(fallen, 0, true, false, "in_progress", true, 1, 34)
	_check(MissionState.validation_error(disabled, fallen_geometry, damaged).is_empty(), "shutdown map accepts exact shared departure goal")
	_invalid(disabled, geometry, "mast shutdown facts cannot arrive on the intact world")
	_invalid(message, fallen_geometry, "intact facts cannot arrive on the fallen world")
	var retry: Dictionary = _state(info, 40, false, false, "briefing", false, 2, 35)
	_check(MissionState.validation_error(retry, geometry, disabled).is_empty(), "new authoritative attempt resets mast and car outcomes")
	var run: Dictionary = message.duplicate(true)
	run["state"]["run"] = {"id": "00000000-0000-0000-0000-000000000003", "status": "playing", "continues": 2, "level_start_continues": 2}
	_check(MissionState.validation_error(run, geometry).is_empty(), "durable M03 begins at the retained episode allowance")
	var continued: Dictionary = retry.duplicate(true)
	continued["state"]["run"] = run["state"]["run"].duplicate(true)
	continued["state"]["run"]["continues"] = 1
	_check(MissionState.validation_error(continued, geometry, run).is_empty(), "shared durable retry consumes one continue")
	continued["state"]["run"]["continues"] = 2
	_invalid(continued, geometry, "retry cannot refill the retained level allowance", run)
	var ready: Dictionary = _state(fallen, 0, true, true, "in_progress", false, 1, 36)
	ready["state"]["prompts"] = [{"player_id": PLAYER, "kind": "objective_use"}]
	_check(MissionState.validation_error(ready, fallen_geometry).is_empty(), "legal local Use departs with optional cars still held")
	for patch: Dictionary in [{"alive": false}, {"ready": false}, {"aboard": false}, {"name": "bad\nname"}]:
		var bad: Dictionary = ready.duplicate(true)
		bad["state"]["party"][0].merge(patch, true)
		_invalid(bad, fallen_geometry, "train Use requires the actual ready living boarded party")
	var too_soon: Dictionary = message.duplicate(true)
	too_soon["state"]["prompts"] = ready["state"]["prompts"]
	_invalid(too_soon, geometry, "no mast Use prompt can substitute for a shot")
	var departed: Dictionary = _state(fallen, 0, true, true, "departed", false, 1, 37)
	_check(MissionState.validation_error(departed, fallen_geometry, ready).is_empty(), "departure does not require optional car release")
	var restart_phase: Dictionary = ready.duplicate(true)
	restart_phase["tick"] = 38
	_invalid(restart_phase, fallen_geometry, "terminal phase cannot regress", departed)
	await _hud(message, freed, disabled, ready, departed)
	_network(info, fallen, message, disabled)
	await _mast_notice(info, fallen)
	await _yard(info, fallen, freed, disabled)
	if failures == 0:
		print("test_m03_mission: PASS map-bound Shoot/Use, captive routes, monotonic progress, retry, party prompts, HUD and yard")
	quit(0 if failures == 0 else 1)

func _hud(message: Dictionary, freed: Dictionary, disabled: Dictionary, ready: Dictionary, departed: Dictionary) -> void:
	var display: MissionHud = MissionHud.new()
	root.add_child(display)
	await process_frame
	display.apply(message["state"], PLAYER)
	_check(display._copy.text == tr("M03_OBJECTIVE_CLEAR_MAST") and display.prompt_text.is_empty(), "HUD introduces guarded mast without a fabricated Use prompt")
	display._process(MissionHud.STAGE_SECONDS + 0.1)
	_check(not display._card.visible, "objective card leaves the aiming view")
	display.apply(message["state"], PLAYER)
	_check(not display._card.visible, "repeated state cannot restage the same objective")
	var quiet_state: Dictionary = display.state.duplicate(true)
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "letters")
	display._process(0.0)
	_check(not display._card.visible and is_zero_approx(display._stage_left) and display.state == quiet_state,
		"device refresh preserves an expired objective stage and unchanged mission facts")
	InputDevice.reset()
	display.apply(freed["state"], PLAYER)
	_check(display._card.visible and display._copy.text == tr("M03_OBJECTIVE_SHOOT_MAST"), "cleared mast defenders stage a shooting instruction")
	_check(display._evac_badge.text == "CARS FREED: 1/1" and display._evac_badge.visible, "car badge reflects authoritative release")
	display._process(MissionHud.STAGE_SECONDS + 0.1)
	_check(not display._card.visible and not display._evac_badge.visible, "an unchanged status line leaves the view with the objective card")
	display.apply(freed["state"], PLAYER)
	_check(not display._evac_badge.visible, "repeating the same status does not restage it")
	display.apply(disabled["state"], PLAYER)
	_check(display._copy.text == tr("M03_OBJECTIVE_CLEAR_TRAIN"), "mast shutdown stages final fight")
	display.apply(ready["state"], PLAYER)
	_check(not display._card.visible and display.prompt_text == "F: TAKE THE TRAIN TO LOW WATER", "legal owner prompt replaces the staged objective")
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "letters")
	display._process(0.0)
	_check(display.prompt_text == "B: TAKE THE TRAIN TO LOW WATER", "M03 prompt follows the current controller without new state")
	InputDevice.reset()
	display._process(0.0)
	display.apply(ready["state"], "")
	_check(display.prompt_text.is_empty() and display._copy.text == tr("M03_OBJECTIVE_BOARD_TRAIN"), "spectator cannot use another party member's departure prompt")
	var translated: Translation = Translation.new()
	translated.locale = "de"
	translated.add_message("M03_OBJECTIVE_BOARD_TRAIN", "ZUM ZUG")
	TranslationServer.add_translation(translated)
	TranslationServer.set_locale("de")
	await process_frame
	_check(display._copy.text == "ZUM ZUG", "existing M03 HUD refreshes on locale change")
	TranslationServer.set_locale("en")
	TranslationServer.remove_translation(translated)
	await process_frame
	display.apply(departed["state"], PLAYER)
	_check(display._card.visible and display._copy.text.contains("TRAIN IS HEADING HOME") and not display._copy.text.contains("SAVED"), "development departure never promises a durable save")
	_check(display._copy.text == "THE TRAIN IS HEADING HOME\nESC: RETURN TO MENU",
		"departure resolves its pause token to the actual keyboard binding")
	display._process(0.25)
	var departure_left: float = display._stage_left
	var departure_state: Dictionary = display.state.duplicate(true)
	InputDevice.force(InputDevice.Kind.GAMEPAD, "gamepad", "letters")
	display._process(0.0)
	_check(display._copy.text == "THE TRAIN IS HEADING HOME\nMENU: RETURN TO MENU",
		"departure changes to the active gamepad menu button without another mission packet")
	_check(display._stage_left == departure_left and display._card.visible and display.state == departure_state,
		"departure device refresh preserves its countdown, visibility and authoritative facts")
	InputDevice.reset()
	display._process(0.0)
	_check(display._copy.text == "THE TRAIN IS HEADING HOME\nESC: RETURN TO MENU" and display._stage_left == departure_left,
		"departure changes back to keyboard without restarting the stage")
	var fallen: Dictionary = message["state"].duplicate(true)
	fallen["party"][0]["alive"] = false
	fallen["run"] = {"id": "00000000-0000-0000-0000-000000000003", "status": "continue", "continues": 1, "level_start_continues": 1}
	display.apply(fallen, PLAYER)
	_check(display._recovery.visible and display.recovery_text.to_lower().contains("continue"), "M03 uses shared fallen-run recovery choice")
	display.apply({}, "")
	_check(not display.visible and display.prompt_text.is_empty(), "map teardown clears M03 HUD")
	display.queue_free()
	await process_frame

func _network(info: Dictionary, fallen: Dictionary, message: Dictionary, disabled: Dictionary) -> void:
	var network: Node = load("res://scripts/net_client.gd").new()
	var facts: Array[Dictionary] = []
	var errors: Array[String] = []
	network.mission_received.connect(func(state: Dictionary) -> void: facts.append(state))
	network.server_error.connect(func(error: String) -> void: errors.append(error))
	network._handle_message(JSON.stringify(info))
	network._handle_message(JSON.stringify(message))
	_check(errors.is_empty() and network.mission.get("state", {}).get("id") == MissionState.M03_ID,
		"actual JSON network boundary admits M03 facts")
	network._handle_message(JSON.stringify(fallen))
	_check(network.mission.is_empty() and facts.back().is_empty(), "mast MapInfo handoff clears stale Shoot presentation before new facts")
	network._handle_message(JSON.stringify(disabled))
	_check(errors.is_empty() and network.mission["state"]["m03"]["current"]["action"]["kind"] == "use", "ordered fallen MapInfo then mission accepts shared Use goal")
	var replaced: Dictionary = fallen.duplicate(true)
	replaced["m03"]["departure"]["approach"] = [6, 0, 5]
	network._handle_message(JSON.stringify(replaced))
	_check(errors.size() == 1 and network.mission.is_empty(), "same-map contract replacement closes the actual connection boundary")
	network.free()

func _mast_notice(info: Dictionary, fallen: Dictionary) -> void:
	var display: MissionHud = MissionHud.new()
	var feed: CombatFeed = CombatFeed.new()
	root.add_child(display)
	root.add_child(feed)
	feed.set_campaign(true)
	var lines: Array[String] = []
	display.notice_requested.connect(func(text: String) -> void:
		lines.append(text)
		feed.push(text))
	var network: Node = load("res://scripts/net_client.gd").new()
	network.mission_received.connect(func(state: Dictionary) -> void: display.apply(state, PLAYER))
	network._handle_message(JSON.stringify(info))
	network._handle_message(JSON.stringify(_state(info, 40, true)))
	_check(lines.is_empty(), "intact mast does not emit Mara's warning")
	network._handle_message(JSON.stringify(fallen))
	_check(display.state.is_empty() and lines.is_empty(), "mast world handoff is not a warning before authoritative shutdown")
	network._handle_message(JSON.stringify(_state(fallen, 0, true, false, "in_progress", false, 1, 21)))
	_check(lines == ["Mara: Low Water, this is Mara. Go now."], "real mast-health transition emits the accepted warning immediately")
	_check(feed._entries.size() == 1 and feed._entries[0].label.text == lines[0]
		and feed.anchor_left == 0.0 and feed.anchor_top == 1.0,
		"warning uses the existing nonblocking campaign corner notice feed")
	network._handle_message(JSON.stringify(_state(fallen, 0, true, true, "in_progress", false, 1, 22)))
	network._handle_message(JSON.stringify(fallen))
	network._handle_message(JSON.stringify(_state(fallen, 0, true, true, "in_progress", false, 1, 23)))
	_check(lines.size() == 1, "repeated shutdown facts and redundant MapInfo cannot replay the warning")
	feed._process(CombatFeed.LIFETIME + 0.1)
	_check(feed._entries.is_empty(), "warning expires through the existing bounded notice lifetime")
	network._handle_message(JSON.stringify(info))
	network._handle_message(JSON.stringify(_state(info, 40, false, false, "briefing", false, 2, 24)))
	network._handle_message(JSON.stringify(_state(info, 40, true, false, "in_progress", false, 2, 25)))
	network._handle_message(JSON.stringify(fallen))
	network._handle_message(JSON.stringify(_state(fallen, 0, true, false, "in_progress", false, 2, 26)))
	_check(lines.size() == 2, "authoritative retry arms one new mast warning")
	display.reset_notices()
	display.apply(_state(fallen, 0, true)["state"], PLAYER)
	_check(lines.size() == 2, "joining an already fallen mast does not invent a transition")
	display.reset_notices()
	display.apply(_state(info, 40, true)["state"], PLAYER)
	display.apply(_state(fallen, 0, true)["state"], PLAYER)
	_check(lines.size() == 3, "disconnect reset permits a fresh session with the same attempt identity")
	network.free()
	display.queue_free()
	feed.queue_free()
	await process_frame

func _yard(info: Dictionary, fallen: Dictionary, freed: Dictionary, disabled: Dictionary) -> void:
	var yard: M03Yard = M03Yard.new()
	root.add_child(yard)
	yard.configure_map(info)
	_check(yard._views.size() == 1 and yard._views["platform_car"].size() == 2,
		"yard creates the exact two captive body views for a registered car")
	var pair: Array = yard._views["platform_car"]
	_check(pair[0].texture != null and pair[1].texture != null and pair[0].texture != pair[1].texture,
		"held pair uses existing human and embodied-agent atlases")
	for index: int in range(2):
		var held: Array = info["m03"]["cars"][0]["held"][index]
		var feet: Vector3 = Vector3(float(held[0]), float(held[1]), float(held[2]))
		_check(pair[index].position.is_equal_approx(feet + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT),
			"captives begin at server-authored held feet")
		_check(pair[index].texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
			"captive atlases retain nearest filtering")
	_check(yard._mast.position.is_equal_approx(Vector3(0.0, 4.5, -0.035)),
		"mast lamp attaches to the registered pod solid rather than the goal approach")
	_check(yard._seals["platform_car"].visible and yard._seals["platform_car"].get_child_count() == 2,
		"held car has one restraint for each captive")
	_pod(yard, Vector3(0.0, 4.5, 0.5), Vector3(2.012, 1.012, 1.012), Color("ed4d30"))
	yard._process(0.4)
	_check(pair[0].frame < PlayerBody.IDLE_FRAMES and is_zero_approx(float(pair[0].get_meta("walked"))),
		"held captive breathes at rest without invented walking distance")
	var walking: Dictionary = freed["state"].duplicate(true)
	walking["m03"]["cars"][0]["captives"] = [[10, 0, 0.2], [11, 0, 0]]
	yard.apply_state(walking)
	yard._process(0.0)
	_check(is_equal_approx(float(pair[0].get_meta("walked")), 0.2)
		and pair[0].frame == PlayerBody.frame(yard._clock, 0.2, 2.0)
		and pair[0].frame >= PlayerBody.IDLE_FRAMES and pair[1].frame < PlayerBody.IDLE_FRAMES,
		"only the captive whose authoritative feet moved uses distance-driven gait")
	walking["m03"]["cars"][0]["captives"][0] = [10, 0, 0.4]
	yard.apply_state(walking)
	yard._process(0.0)
	_check(is_equal_approx(float(pair[0].get_meta("walked")), 0.4)
		and pair[0].frame == PlayerBody.frame(yard._clock, 0.4, 2.0),
		"subsequent server displacement advances gait by the real travelled distance")
	var move_time: int = int(pair[0].get_meta("last_move_ms"))
	var rest_position: Vector3 = pair[0].position
	while Time.get_ticks_msec() - move_time < 180:
		await create_timer(0.01).timeout
	yard.apply_state(walking)
	yard._process(0.0)
	_check(pair[0].frame < PlayerBody.IDLE_FRAMES and pair[0].position == rest_position
		and int(pair[0].get_meta("last_move_ms")) == move_time
		and is_equal_approx(float(pair[0].get_meta("walked")), 0.4),
		"a stationary repeated sample cannot prolong gait past the bounded movement hint or predict new feet")
	yard.apply_state(freed["state"])
	_check(not yard._seals["platform_car"].visible, "authoritative car release hides restraints")
	for index: int in range(2):
		var safe: Array = freed["state"]["m03"]["cars"][0]["captives"][index]
		var feet: Vector3 = Vector3(float(safe[0]), float(safe[1]), float(safe[2]))
		_check(pair[index].position.is_equal_approx(feet + Vector3.UP * EnemyAnimation.CENTRE_HEIGHT),
			"released bodies use the actual server captive feet")
	var corrupted: Dictionary = freed["state"].duplicate(true)
	corrupted["m03"]["cars"][0]["captives"][0] = [NAN, 0, 0]
	var before: Vector3 = pair[0].position
	var distance_before: float = float(pair[0].get_meta("walked"))
	move_time = int(pair[0].get_meta("last_move_ms"))
	yard.apply_state(corrupted)
	_check(pair[0].position == before and not yard._seals["platform_car"].visible,
		"malformed facts cannot move captive views or restore restraints")
	_check(float(pair[0].get_meta("walked")) == distance_before and int(pair[0].get_meta("last_move_ms")) == move_time,
		"malformed facts cannot advance or refresh captive gait")
	yard._process(0.4)
	_check(pair[0].frame == PlayerBody.frame(yard._clock, 10.0, 2.0),
		"authoritative endpoint retains the full walked distance rather than a local velocity guess")
	yard.configure_map(fallen)
	_check(yard._mast.position.is_equal_approx(Vector3(0.0, 0.5, 1.965)),
		"shutdown rebuild positions the lamp on the current fallen solid")
	var material: StandardMaterial3D = yard._mast.material_override
	_check(material.albedo_color.is_equal_approx(Color("86332b")), "shutdown world uses the inactive mast lamp")
	_pod(yard, Vector3(0.0, 0.5, 3.0), Vector3(2.012, 1.012, 2.012), Color("86332b"))
	var rebuilt_pair: Array = yard._views["platform_car"]
	yard._process(0.0)
	_check(is_zero_approx(float(rebuilt_pair[0].get_meta("walked")))
		and rebuilt_pair[0].frame < PlayerBody.IDLE_FRAMES,
		"world reconfiguration removes previous movement history")
	yard.apply_state(disabled["state"])
	_check(not yard._seals["platform_car"].visible, "same car outcome reapplies after mast world reconfiguration")
	yard.configure_map({})
	_check(yard._geometry.is_empty() and yard._views.is_empty() and yard._mast == null and yard.get_child_count() == 0,
		"non-M03 map tears down captive and mast presentation")
	yard.configure_map(info)
	var bad_map: Dictionary = info.duplicate(true)
	bad_map["m03"]["mast"]["solid"] = 999
	yard.configure_map(bad_map)
	_check(yard._geometry.is_empty() and yard.get_child_count() == 0, "malformed replacement map cleans prior presentation")
	yard.queue_free()
	await process_frame

func _pod(yard: M03Yard, center: Vector3, extent: Vector3, color: Color) -> void:
	var shell: MeshInstance3D = yard._root.get_node("RegisteredPodShell")
	var mesh: BoxMesh = shell.mesh
	var material: StandardMaterial3D = shell.material_override
	_check(shell.position.is_equal_approx(center) and mesh.size.is_equal_approx(extent),
		"pod shell follows the registered collision volume with only the bounded surface offset")
	_check(shell.layers == ArenaSky.WORLD_LAYERS and material == yard._mast.material_override
		and material.albedo_color.is_equal_approx(color) and material.emission.is_equal_approx(color),
		"pod shell shares active-red or fallen-muted mast material on the world lighting layer")
