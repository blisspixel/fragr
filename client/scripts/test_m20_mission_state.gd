extends SceneTree

## Local Exception reader: the native lifecycle fixture is accepted in order,
## and forged progress, clocks, barricades, crews and discs are refused.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m20_mission_state: " + message)

func _rejected(message: Dictionary, geometry: Dictionary, previous: Dictionary, why: String) -> void:
	_check(not MissionState.validation_error(message, geometry, previous).is_empty(), why)

func _run() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m20_lifecycle.json"))
	if not fixture is Dictionary or not fixture.get("messages") is Array:
		push_error("test_m20_mission_state: missing native lifecycle fixture")
		quit(1)
		return
	var shut: Dictionary = fixture["map_info"]
	var opened: Dictionary = fixture["map_info_open"]
	_check(MissionState.map_error(shut).is_empty(), "native shut map rejected")
	_check(MissionState.map_error(opened).is_empty(), "native open map rejected")
	_check(MissionState.id_for_map(shut) == MissionState.M20_ID, "map identity")
	var shut_geometry: Dictionary = MissionState.geometry_for(shut)
	var open_geometry: Dictionary = MissionState.geometry_for(opened)
	_check(M20MissionState.same_contract(shut_geometry, open_geometry), "the gate may open")
	_check(not M20MissionState.same_contract(open_geometry, shut_geometry), "the gate never shuts again")
	# Map contract refusals.
	var bad: Dictionary = shut.duplicate(true)
	bad["m20"]["hold_ticks"] = int(bad["m20"]["hold_ticks"]) + 20
	_check(not MissionState.map_error(bad).is_empty(), "a clock that is not six minutes after the turn")
	bad = shut.duplicate(true)
	bad["m20"]["harbour_display"] = int(bad["m20"]["departure"]["decoration"])
	_check(not MissionState.map_error(bad).is_empty(), "the display must be the registered panel")
	bad = shut.duplicate(true)
	bad["m18"] = {}
	_check(not MissionState.map_error(bad).is_empty(), "M20 cannot share another mission map")
	bad = shut.duplicate(true)
	bad["m20"]["objectives"].pop_back()
	_check(not MissionState.map_error(bad).is_empty(), "five ordered objectives")

	var previous: Dictionary = {}
	var saw: Dictionary = {}
	for message: Dictionary in fixture["messages"]:
		var facts: Dictionary = message["state"]["m20"]
		var geometry: Dictionary = open_geometry if facts["gate_open"] else shut_geometry
		var problem: String = MissionState.validation_error(message, geometry, previous)
		_check(problem.is_empty(), "native message rejected at tick %d" % int(message["tick"]))
		saw[facts["completed"].size()] = true
		# Forgeries of every kind against this exact accepted message.
		var forged: Dictionary = message.duplicate(true)
		forged["state"]["m20"]["completed"].append("forged")
		_rejected(forged, geometry, {}, "forged progress accepted")
		forged = message.duplicate(true)
		forged["state"]["m20"]["refuge_integrity"] = 101
		_rejected(forged, geometry, {}, "barricade above its limit")
		forged = message.duplicate(true)
		forged["state"]["m20"]["challenges"]["refuge_held"] = not facts["challenges"]["refuge_held"]
		_rejected(forged, geometry, {}, "held barricade disagrees with integrity")
		forged = message.duplicate(true)
		forged["state"]["m20"]["crew"].pop_back()
		_rejected(forged, geometry, {}, "a missing crew member")
		forged = message.duplicate(true)
		forged["state"]["m20"]["brief_completed"] = not facts["brief_completed"]
		_rejected(forged, geometry, {}, "brief disagrees with difficulty")
		forged = message.duplicate(true)
		forged["state"]["m20"]["refuge"]["persons"] = 399
		_rejected(forged, geometry, {}, "the refuge is never fewer than four hundred")
		if facts.has("pier_reached_at"):
			forged = message.duplicate(true)
			forged["state"]["m20"]["pier_reached_at"] = int(message["tick"]) + 1
			_rejected(forged, geometry, {}, "a future quay arrival")
		if facts["display_lit"]:
			forged = message.duplicate(true)
			forged["state"]["m20"]["pier_reached_at"] = int(facts["pier_reached_at"]) + 40
			_rejected(forged, geometry, {}, "display lit before its turn")
		if facts.has("reprieve_at"):
			forged = message.duplicate(true)
			forged["state"]["m20"]["reprieve_at"] = int(facts["reprieve_at"]) - 1
			_rejected(forged, geometry, {}, "a reprieve off the authored clock")
			forged = message.duplicate(true)
			forged["state"]["m20"].erase("latch")
			_rejected(forged, geometry, {}, "the reprieve brings Latch back")
		if not message["state"]["prompts"].is_empty():
			forged = message.duplicate(true)
			forged["state"]["prompts"][0]["kind"] = "transfer_record"
			_rejected(forged, geometry, {}, "forged prompt kind")
		if not previous.is_empty() and int(previous["state"]["m20"]["refuge_integrity"]) > int(facts["refuge_integrity"]):
			_rejected(previous, geometry, message, "a worn barricade never repairs within an attempt")
		previous = message
	for stage: int in range(7):
		_check(saw.has(stage), "fixture covers completed count %d" % stage)
	var last: Dictionary = fixture["messages"].back()
	_check(last["state"]["phase"] == "departed", "fixture ends departed")

	# The pier clock is derived, never sent per tick.
	var during: Dictionary = {}
	for message: Dictionary in fixture["messages"]:
		if message["state"]["m20"]["completed"].size() == 3 and message["state"]["m20"].has("pier_reached_at"):
			during = message
	_check(not during.is_empty(), "a hold message exists")
	if not during.is_empty():
		var facts: Dictionary = during["state"]["m20"]
		var spans: Array[int] = M20MissionState.clock(shut_geometry, facts)
		_check(spans.size() == 3 and spans[2] - spans[1] == M20MissionState.SIX_MINUTES, "six minutes after the turn")
		_check(M20MissionState.seconds_left(shut_geometry, facts, spans[0] - 1) == -1, "no clock during the breath")
		_check(M20MissionState.seconds_left(shut_geometry, facts, spans[1]) == 360, "the turn leaves six minutes")
		_check(M20MissionState.seconds_left(shut_geometry, facts, spans[2]) == 0, "the clock ends at the reprieve")

	# Surveyor discs: a native live disc is accepted, forgeries refused.
	var snapshot: Dictionary = fixture["mark_snapshot"]
	_check(SurveyorMarks.validation_error(snapshot).is_empty(), "native disc rejected")
	_check(ActorState.validation_error(snapshot).is_empty(), "native Surveyor actor rejected")
	var forged_snapshot: Dictionary = snapshot.duplicate(true)
	forged_snapshot["surveyor_marks"][0]["radius"] = 6.0
	_check(not SurveyorMarks.validation_error(forged_snapshot).is_empty(), "a widened disc")
	forged_snapshot = snapshot.duplicate(true)
	forged_snapshot["surveyor_marks"][0]["id"] = "00000000-0000-0000-0000-00000000dead"
	_check(not SurveyorMarks.validation_error(forged_snapshot).is_empty(), "a disc without its Surveyor")
	forged_snapshot = snapshot.duplicate(true)
	forged_snapshot["surveyor_marks"][0]["until"] = forged_snapshot["surveyor_marks"][0]["since"]
	_check(not SurveyorMarks.validation_error(forged_snapshot).is_empty(), "a disc with no lifetime")
	forged_snapshot = snapshot.duplicate(true)
	forged_snapshot["surveyor_marks"].append(forged_snapshot["surveyor_marks"][0])
	_check(not SurveyorMarks.validation_error(forged_snapshot).is_empty(), "two discs from one lens")

	# The presenters accept the same facts without authority.
	var marks: SurveyorMarks = SurveyorMarks.new()
	root.add_child(marks)
	marks.apply_snapshot(snapshot)
	_check(marks.marks.size() == 1, "the disc is drawn")
	await process_frame
	snapshot["tick"] = int(snapshot["tick"]) + 1
	snapshot["surveyor_marks"] = []
	marks.apply_snapshot(snapshot)
	_check(marks.marks.is_empty(), "a lapsed disc is retired")
	marks.queue_free()
	var rig: SurveyorRig = SurveyorRig.new()
	root.add_child(rig)
	rig.present({"phase": "windup", "phase_started": 10, "phase_ends": 46}, 28, 0.0)
	_check(rig.aperture > 0.4 and rig.aperture < 0.6, "the lens opens through the tell")
	rig.present({"phase": "firing", "phase_started": 46, "phase_ends": 146}, 60, 0.0)
	_check(is_equal_approx(rig.aperture, 1.0), "the lens is wide while projecting")
	rig.present({"phase": "idle", "phase_started": 1, "phase_ends": 1}, 60, 0.0)
	_check(is_zero_approx(rig.aperture), "the shutter is closed while scanning")
	_check(rig.placeholder == not ResourceLoader.exists(SurveyorRig.SOURCE_SCENE), "the swap seam picks the delivered model")
	var glass: Node3D = rig.find_child("LensGlass", true, false) as Node3D
	_check(glass != null and absf(glass.global_position.y - rig.global_position.y - SurveyorRig.LENS_HEIGHT) < 0.08
		and SurveyorRig.LENS_HEIGHT < 1.8, "the lens sits at the mark's origin inside the 1.8 m body")
	rig.queue_free()
	await process_frame
	if failures > 0:
		push_error("test_m20_mission_state FAILED with %d failures" % failures)
		quit(1)
	else:
		print("test_m20_mission_state: PASS native refuge clock, crew, barricade, reprieve and Surveyor discs")
		quit(0)
