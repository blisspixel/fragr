extends SceneTree

## Planned Works readers against the server's own wire receipts: both worlds,
## every mission transition of a Standard route, and snapshots carrying a
## preparing strip, a worked strip and a thrusting pack. Forgeries close.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m19_mission_state: " + message)

func _run() -> void:
	var native: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m19_native.json"))
	if not native is Dictionary or native.get("maps", []).size() != 2:
		push_error("test_m19_mission_state: missing native Planned Works receipts")
		quit(1)
		return
	var maps: Array = native["maps"]
	for info: Dictionary in maps:
		_check(MissionState.map_error(info).is_empty(), "native world rejected: " + MissionState.map_error(info))
	var closed: Dictionary = MissionState.geometry_for(maps[0])
	var open: Dictionary = MissionState.geometry_for(maps[1])
	_check(not closed["m19"]["gate_open"] and open["m19"]["gate_open"], "the second world opens the waterworks")
	_check(M19MissionState.same_contract(closed, open), "the gate opening keeps the static contract")
	var moved: Dictionary = maps[0].duplicate(true)
	moved["m19"]["jet_hops"][0]["landing"][1] += 0.5
	_check(not M19MissionState.same_contract(closed, MissionState.geometry_for(moved)), "a moved hop is a changed contract")
	var forged_map: Dictionary = maps[0].duplicate(true)
	forged_map["m19"]["objectives"].pop_back()
	_check(not MissionState.map_error(forged_map).is_empty(), "a missing objective is rejected")
	forged_map = maps[0].duplicate(true)
	forged_map["m19"]["jetpack_ceiling"] = 40.0
	_check(not MissionState.map_error(forged_map).is_empty(), "an absurd ceiling is rejected")

	var hud := MissionHud.new()
	root.add_child(hud)
	await process_frame
	var previous: Dictionary = {}
	var seen_objectives: Dictionary = {}
	for receipt: Dictionary in native["missions"]:
		var message: Dictionary = receipt["message"]
		var geometry: Dictionary = MissionState.geometry_for(maps[int(receipt["map_index"])])
		var reason: String = MissionState.validation_error(message, geometry, previous)
		_check(reason.is_empty(), "native mission rejected at tick %d: %s" % [message["tick"], reason])
		var state: Dictionary = message["state"]
		hud.apply(state, str(state["party"][0]["id"]))
		var copy: String = hud._copy.text
		_check(not copy.is_empty() and not copy.contains("M19_"), "objective copy resolves at tick %d: %s" % [message["tick"], copy])
		if state["m19"].get("current") is Dictionary:
			seen_objectives[state["m19"]["current"]["id"]] = true
		var progress: Dictionary = state["m19"]
		var n: int = progress["completed"].size()
		var forged: Dictionary = message.duplicate(true)
		forged["state"]["m19"]["completed"].append("forged")
		_check(not MissionState.validation_error(forged, geometry).is_empty(), "forged progression accepted")
		if n >= 1:
			forged = message.duplicate(true)
			forged["state"]["m19"]["jetpack_taken"] = false
			_check(not MissionState.validation_error(forged, geometry).is_empty(), "a used stores counter without a pack accepted")
		if n < 6:
			forged = message.duplicate(true)
			forged["state"]["m19"]["latch_departed"] = true
			_check(not MissionState.validation_error(forged, geometry).is_empty(), "an early Latch departure accepted")
		if n < 8:
			forged = message.duplicate(true)
			forged["state"]["m19"]["gate_open"] = true
			_check(not MissionState.validation_error(forged, geometry).is_empty(), "an early open gate accepted")
		forged = message.duplicate(true)
		forged["state"]["m19"]["challenges"]["extra"] = true
		_check(not MissionState.validation_error(forged, geometry).is_empty(), "an unknown challenge accepted")
		forged = message.duplicate(true)
		forged["state"]["m19"]["brief_completed"] = not progress["brief_completed"]
		_check(not MissionState.validation_error(forged, geometry).is_empty(), "a mismatched brief accepted")
		if not state["prompts"].is_empty():
			_check(hud._server_template == tr("M19_USE_STORES" if progress["completed"].is_empty() else "M19_USE_WATERWORKS"), "the use prompt names its control")
		previous = message
	_check(seen_objectives.size() == M19MissionState.OBJECTIVES.size() + 1, "every objective became current: %s" % [seen_objectives.keys()])
	_check(previous["state"]["phase"] == "departed", "the route departs")
	var regressed: Dictionary = native["missions"][4]["message"].duplicate(true)
	_check(not MissionState.validation_error(regressed, open, previous).is_empty(), "a regression after departure accepted")

	# Snapshots: strips and packs.
	var phases: Dictionary = {}
	for receipt: Dictionary in native["snapshots"]:
		var snapshot: Dictionary = receipt["message"]
		_check(ActorState.validation_error(snapshot).is_empty(), "native snapshot actors rejected: " + ActorState.validation_error(snapshot))
		_check(WorksFacts.validation_error(snapshot).is_empty(), "native works facts rejected at tick %d" % snapshot["tick"])
		for strip: Dictionary in snapshot.get("paver_strips", []):
			phases["working" if strip["working"] else "preparing"] = snapshot
		for pack: Dictionary in snapshot.get("jetpacks", []):
			if pack["thrusting"]:
				phases["thrusting"] = snapshot
	_check(phases.has("preparing") and phases.has("working") and phases.has("thrusting"), "receipts cover preparation, work and thrust")
	var worked: Dictionary = phases.get("working", {})
	if not worked.is_empty():
		var strip: Dictionary = worked["paver_strips"][0]
		var bad: Dictionary = worked.duplicate(true)
		bad["paver_strips"][0]["half_width"] = 4.0
		_check(not WorksFacts.validation_error(bad).is_empty(), "a widened strip accepted")
		bad = worked.duplicate(true)
		bad["paver_strips"][0]["working"] = false
		_check(not WorksFacts.validation_error(bad).is_empty(), "a strip disagreeing with its Paver's phase accepted")
		bad = worked.duplicate(true)
		bad["paver_strips"].append(bad["paver_strips"][0].duplicate(true))
		_check(not WorksFacts.validation_error(bad).is_empty(), "a Paver with two strips accepted")
		bad = worked.duplicate(true)
		bad["paver_strips"][0]["length"] = 40.0
		_check(not WorksFacts.validation_error(bad).is_empty(), "an unbounded strip accepted")
		var origin: Vector3 = Vector3(strip["origin"][0], strip["origin"][1], strip["origin"][2])
		var forward: Vector3 = Vector3(cos(float(strip["yaw"])), 0.0, sin(float(strip["yaw"])))
		_check(WorksFacts.inside(strip, origin + forward * 5.0), "a body down the strip is inside")
		_check(not WorksFacts.inside(strip, origin + forward * 5.0 + Vector3(-forward.z, 0.0, forward.x) * 2.0), "a lateral step clears the strip")
		_check(not WorksFacts.inside(strip, origin + forward * 5.0 + Vector3.UP * 4.0), "another floor is never worked")
	var thrust: Dictionary = phases.get("thrusting", {})
	if not thrust.is_empty():
		var bad: Dictionary = thrust.duplicate(true)
		bad["jetpacks"][0]["fuel"] = JetMovement.FUEL_MAX + 1
		_check(not WorksFacts.validation_error(bad).is_empty(), "overfilled fuel accepted")
		bad = thrust.duplicate(true)
		bad["jetpacks"][0]["player_id"] = "00000000-0000-0000-0000-00000000dead"
		_check(not WorksFacts.validation_error(bad).is_empty(), "a pack on nobody accepted")

	# The presenter builds, follows the route's facts and draws the strips.
	var works := M19Works.new()
	root.add_child(works)
	await process_frame
	works.configure_map(maps[0])
	_check(works.active() and works.find_child("WorkMarks", true, false) != null, "the static work marks are laid")
	_check(works.find_child("RiverAndPier", true, false) != null and works.find_child("ClerkInBlack", true, false) != null, "the river, pier and concourse dressing build")
	# The Clerk stays recognisably Union while he carries the stretcher.
	var clerk: Node3D = works.find_child("ClerkInBlack", true, false) as Node3D
	var armband: MeshInstance3D = clerk.get_node_or_null("Armband") as MeshInstance3D
	var collar: MeshInstance3D = clerk.get_node_or_null("ClerkCollar") as MeshInstance3D
	_check(armband != null and (armband.material_override as StandardMaterial3D).albedo_color.r > 0.4
		and (armband.material_override as StandardMaterial3D).albedo_color.g < 0.2
		and (collar.material_override as StandardMaterial3D).albedo_color.get_luminance() < 0.3,
		"the Clerk carries a red armband and a dark steel collar")
	# Free people read as individuals in mid values, never dark uniform rows.
	var coats: Dictionary[Color, bool] = {}
	var dark_coats: int = 0
	var walkers: int = 0
	for node: Node in works.find_child("ConcourseCrowd", true, false).find_children("Coat", "MeshInstance3D", true, false):
		if node.get_parent().name == "ClerkInBlack":
			continue
		var colour: Color = ((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
		coats[colour] = true
		walkers += 1
		if colour.v < 0.3:
			dark_coats += 1
	_check(walkers >= 20 and coats.size() >= 8 and dark_coats == 0, "the concourse crowd is varied and mid-valued: %d people, %d coats, %d dark" % [walkers, coats.size(), dark_coats])
	var agents: Array[Node] = works.find_children("FreeAgent", "Node3D", true, false)
	_check(not agents.is_empty(), "free agents walk among the people")
	for agent: Node in agents:
		var screen: StandardMaterial3D = (agent.get_node("Screen") as MeshInstance3D).material_override as StandardMaterial3D
		_check(screen.emission_enabled and screen.emission.r > screen.emission.b * 1.5, "a free agent's screen glows warm, never cyan or red optics")
	_check(works.find_children("SparePack*", "Node3D", true, false).size() == 4, "spare packs hang on the stores racks")
	var knots: Array[Node] = works.find_children("PierKnot*", "Node3D", true, false)
	_check(knots.size() >= 5 and works.find_children("HandLamp", "MeshInstance3D", true, false).size() >= 3,
		"the pier waits in knots under hand lamps")
	# Latch's face burns warm phosphor under the night key, beside the lamp.
	var eyes: StandardMaterial3D = works._latch._eyes.material_override as StandardMaterial3D
	_check(eyes.emission.r > eyes.emission.b * 1.5 and works.find_child("TankLamp", true, false) != null,
		"Latch's screen is warm phosphor and a lamp burns on the tank")
	var town: Node3D = works.find_child("TownDressing", true, false) as Node3D
	_check(town != null and int(town.get_meta("faces", 0)) == M19Works.TownDressing.FACES.size() \
		and int(town.get_meta("tanks", 0)) == 2 and int(town.get_meta("lamps", 0)) == 3,
		"every authored street face, both roof tanks and the three street lamps are dressed")
	# A layout whose solids moved receives no guessed windows.
	var shifted: Dictionary = maps[0].duplicate(true)
	for solid: Dictionary in shifted["solids"]:
		solid["min_x"] = float(solid["min_x"]) + 0.5
		solid["max_x"] = float(solid["max_x"]) + 0.5
	var guessed: Node3D = M19Works.TownDressing.new().build(Node3D.new(), shifted)
	_check(int(guessed.get_meta("faces", -1)) == 0 and int(guessed.get_meta("tanks", -1)) == 0, "a moved layout is left undressed")
	guessed.get_parent().free()
	var notices: Array[String] = []
	works.notice_requested.connect(func(text: String) -> void: notices.append(text))
	for receipt: Dictionary in native["missions"]:
		works.apply_state(receipt["message"]["state"])
		if receipt["message"]["state"]["m19"]["completed"].size() == 5:
			_check(works._latch_mode == "tank", "Latch waits on the tank while the party climbs")
		await process_frame
	_check(notices.has(tr("M19_CROSSING_CLEARED")) and notices.has(tr("M19_WATERWORKS_OPEN")), "route notices fire once each: %s" % [notices])
	_check(works._fired.has("latch_lines"), "Latch's tank lines play")
	_check(works._latch_seated and works._latch.position.is_equal_approx(M19Works.TANK_SEAT), "Latch sits on the tank rim for the first lines")
	_check(works._latch._screen.transform.origin.y < 1.25, "the seated head and screen sit lower than a standing Latch")
	for _line: int in range(M19Works.TANK_LINES.size() - 1):
		works._advance_lines(M19Works.LINE_SECONDS + 0.1)
	works._advance_latch(0.1)
	_check(works._line_key == M19Works.TANK_LINES[M19Works.TANK_LINES.size() - 1] and not works._latch_seated, "Latch stands up to say they are going")
	for _line: int in range(2):
		works._advance_lines(M19Works.LINE_SECONDS + 0.1)
	_check(works._latch_mode == "running", "Latch leaves once the three lines end")
	var perch: Vector3 = works._latch.position
	for _step: int in range(12):
		works._advance_latch(0.1)
	_check(works._latch.position.distance_to(perch) > 1.0 and works._latch.position.y < perch.y, "Latch drops off the tank and runs")
	for _step: int in range(600):
		works._advance_latch(0.1)
	_check(not works._latch.visible, "Latch goes through the waterworks alone")
	var retry: Dictionary = native["missions"][0]["message"]["state"].duplicate(true)
	retry["attempt"] = int(retry["attempt"]) + 1
	works.apply_state(retry)
	_check(works._fired.is_empty() and works._latch_mode == "concourse", "a retry restarts the level's story")
	if not worked.is_empty():
		works.local_id = str(worked["jetpacks"][0]["player_id"]) if not worked.get("jetpacks", []).is_empty() else ""
		works.apply_snapshot(worked)
		_check(works.strips._strips.size() == 1, "the worked strip is drawn")
		await process_frame
		var empty: Dictionary = worked.duplicate(true)
		empty["tick"] = int(worked["tick"]) + 1
		empty["paver_strips"] = []
		works.apply_snapshot(empty)
		_check(works.strips._strips.is_empty(), "a finished strip is retired")
	if not thrust.is_empty():
		works.local_id = str(thrust["jetpacks"][0]["player_id"])
		works.apply_snapshot(thrust)
		_check(works._gauge.visible, "the local fuel gauge shows while a pack is worn")

	# The placeholder rigs pose from authoritative windows.
	var rig := PaverRig.new()
	root.add_child(rig)
	rig.present({"phase": "windup", "phase_started": 10, "phase_ends": 54}, 32, 0.0)
	_check(rig.phase == "windup" and rig.progress > 0.45 and rig.progress < 0.55, "the preparation tell follows its window")
	rig.present({"phase": "firing", "phase_started": 54, "phase_ends": 66}, 58, 0.0)
	_check(rig.phase == "firing", "the work pose follows the firing window")
	# Restoration indicators are the Inheritance's muted cyan, never warm or white.
	for part: String in ["ProjectorLens", "WorkLamp", "RecoveryVent"]:
		var lit: MeshInstance3D = rig.find_child(part, true, false) as MeshInstance3D
		var colour: Color = (lit.material_override as StandardMaterial3D).albedo_color
		_check(colour.is_equal_approx(PaverRig.WORK_CYAN) or colour.is_equal_approx(PaverRig.DARK), "%s is muted cyan or ink, not a warm lamp" % part)
	rig.present({"phase": "recovery", "phase_started": 66, "phase_ends": 80}, 70, 0.0)
	var vent: StandardMaterial3D = (rig.find_child("RecoveryVent", true, false) as MeshInstance3D).material_override as StandardMaterial3D
	_check(vent.emission.is_equal_approx(PaverRig.WORK_CYAN), "the recovery vent glows muted cyan")
	rig.queue_free()
	var pack := JetpackRig.new()
	root.add_child(pack)
	pack.apply({"fuel": 30, "thrusting": true}, float(JetMovement.FUEL_MAX))
	_check(pack.thrusting and is_equal_approx(pack.fuel_fraction, 0.5), "the pack reads fuel and thrust")
	_check(pack.model != null and pack.model.find_child("NozzleLeft", true, false) != null and pack.model.find_child("NozzleRight", true, false) != null,
		"the worn pack is the prepared model with both nozzle anchors")
	_check(pack._flames.size() == 2 and pack.find_child("Gauge", true, false) != null,
		"the prepared pack keeps two flames and its fuel gauge")
	pack.queue_free()
	_check(StoryScene.exists(StoryScene.BEFORE_MISSION[MissionState.M19_ID]), "the arrival page exists")
	works.clear_map()
	works.queue_free()
	hud.queue_free()
	await process_frame
	if failures == 0:
		print("test_m19_mission_state: PASS")
	quit(0 if failures == 0 else 1)
