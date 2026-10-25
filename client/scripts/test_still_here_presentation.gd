extends SceneTree

## Still Here presentation from the native lifecycle fixture: the people the
## run brought stand in both worlds and the ones it did not are specific
## absences, never graves; lines are heard only by the walker; the board's
## fragment fits the board on a level baseline; the turn card waits for the
## server's world; the coda credits only who this run saw again and ends.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_still_here_presentation: " + message)

static func _ids(geometry: Dictionary, refuge: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for person: Dictionary in EpilogueMissionState.people(geometry, refuge):
		result.append(str(person["id"]))
	return result

func _run() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/epilogue_lifecycle.json"))
	if not fixture is Dictionary or not fixture.get("messages") is Array:
		push_error("test_still_here_presentation: missing native lifecycle fixture")
		quit(1)
		return
	var messages: Array = fixture["messages"]
	var first: Dictionary = fixture["map_info"]
	var later_info: Dictionary = fixture["map_info_later"]
	var refuge_view: StillHereRefuge = StillHereRefuge.new()
	root.add_child(refuge_view)
	var hidden: Array = []
	refuge_view.solids_hidden.connect(func(indices: Array[int]) -> void:
		hidden.clear()
		hidden.append_array(indices))
	refuge_view.configure_map(first)
	await process_frame
	for index: int in first["epilogue"]["later_only"]:
		_check(index in hidden, "a later-only solid is not drawn in the first light: %d" % index)
	var spoken: Array[String] = []
	_check(refuge_view.caption != null, "the presenter owns a speaker caption")
	refuge_view.caption.line_said.connect(func(text: String) -> void: spoken.append(text))

	# Everyone the run brought, in the first light.
	var everyone: Dictionary = messages[0]["state"]["epilogue"]["refuge"]
	refuge_view.apply_state(messages[0]["state"])
	var expected: Array[String] = _ids(first["epilogue"], everyone)
	_check(refuge_view.people.size() == expected.size(), "one figure per present person: %d of %d" % [refuge_view.people.size(), expected.size()])
	for who: String in ["edda", "splice", "orrin", "sorrel", "latch", "mara", "tern", "ascender", "kneeler", "car_family_a"]:
		_check(refuge_view.people.has(who), who + " stands in the first light")
	_check(not refuge_view.people["car_family_a"].find_children("CarTag", "MeshInstance3D", true, false).is_empty(), "the recall car family still wears its tags")
	_check(not refuge_view.people["mara"].find_children("RouteCase", "BoneAttachment3D", true, false).is_empty(), "Mara carries her route case")
	_check(refuge_view.people["splice"] is SpliceCharacter, "Splice stands in their own body, not a recoloured stand-in")
	_check(not refuge_view.people.has("lamp_keeper"), "Edda lit the lamp herself")
	_check(refuge_view.find_children("NamedNote*", "MeshInstance3D", true, false).is_empty(), "nobody this run saw again is on the missing board")
	var children: int = 0
	for person: Dictionary in first["epilogue"]["people"]:
		if person["pose"] == "child" and refuge_view.people.has(person["id"]):
			var child: SkinnedCharacter = refuge_view.people[person["id"]] as SkinnedCharacter
			_check(child != null and child.kind == "human", "a child is a human child, never a small agent: " + str(person["id"]))
			children += 1
	_check(children > 0, "the first light has children in it")

	# A run that brought nobody: stand-ins fill the gaps, the board names who.
	# A world never changes who the run brought, so this is its own court.
	var nobody: Dictionary = {}
	for key: String in EpilogueMissionState.SURVIVORS:
		nobody[key] = false
	var alone: Dictionary = messages[0]["state"].duplicate(true)
	alone["epilogue"]["refuge"] = nobody
	var empty_view: StillHereRefuge = StillHereRefuge.new()
	root.add_child(empty_view)
	empty_view.configure_map(first)
	empty_view.apply_state(alone)
	await process_frame
	_check(empty_view.people.has("lamp_keeper") and not empty_view.people.has("edda"), "somebody else lit the lamp")
	_check(empty_view.people.has("mechanic") and not empty_view.people.has("splice"), "somebody else is at the motor")
	_check(not empty_view.people.has("car_family_a"), "nobody from the recall cars")
	_check(empty_view.find_children("NamedNote*", "MeshInstance3D", true, false).size() == 4, "four named notes on the board")
	_check(empty_view.find_children("*Grave*", "", true, false).is_empty(), "never a grave")
	empty_view.queue_free()
	await process_frame

	# Lines are heard by the walker in first person, not a passing camera.
	var eye: Camera3D = Camera3D.new()
	root.add_child(eye)
	eye.current = true
	var mara: Node3D = refuge_view.people["mara"]
	eye.global_position = mara.global_position + Vector3(1.0, 1.5, 0.0)
	refuge_view.hearing = false
	for _frame: int in range(6):
		await process_frame
	_check(refuge_view.caption.showing().is_empty() and spoken.is_empty(), "a spectator camera hears nothing")
	refuge_view.hearing = true
	for _frame: int in range(6):
		await process_frame
	_check(not refuge_view.caption.showing().is_empty(), "the walker hears Mara")

	# The world turns: the later court, the board shows the ferry.
	var placard: Label3D = refuge_view.people["entrant_b"].find_child("EntrantNumber", true, false) as Label3D
	var worn: String = placard.text if placard != null else ""
	refuge_view.configure_map(later_info)
	var later_message: Dictionary = {}
	for message: Dictionary in messages:
		if message["state"]["epilogue"]["later"]:
			later_message = message
			break
	refuge_view.apply_state(later_message["state"])
	await process_frame
	for index: int in later_info["epilogue"]["aftermath_only"]:
		_check(index in hidden, "an aftermath-only solid is not drawn years later: %d" % index)
	_check(refuge_view.people.size() == _ids(later_info["epilogue"], everyone).size(), "the later court is its own people")
	_check(refuge_view.people.has("sorrel"), "Sorrel drives the tram years later")
	var nailed: Array[Node] = refuge_view.find_children("EntrantNumber", "Label3D", true, false)
	_check(not worn.is_empty() and nailed.size() == 1 and (nailed[0] as Label3D).text == worn,
		"the number over the door years later is the one an entrant wore the morning after")
	var lines: Array[Node] = refuge_view.find_children("BoardLine*", "Label3D", true, false)
	_check(lines.size() == 4, "four board lines")
	var timetable: Array[String] = []
	for node: Node in lines:
		timetable.append((node as Label3D).text)
	_check(TranslationServer.translate("STILL_HERE_BOARD_PIER") in timetable, "the board times the ferry")
	_check((lines[0] as Label3D).modulate == StillHereRefuge.FERRY_TEXT, "the ferry is timed in the refuge's warm amber")

	# The fragment fits the board, level, at one size; then the ferry again.
	refuge_view.show_fragment(true)
	var board_width: float = float(refuge_view.get("_ferry_width"))
	var size: float = -1.0
	var showing: Array[String] = []
	for node: Node in lines:
		var line: Label3D = node
		_check(is_zero_approx(line.rotation.z) and is_zero_approx(line.global_rotation.z), "board text is level")
		if not line.visible:
			continue
		showing.append(line.text)
		var wide: float = WorldSign.FONT.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, line.font_size).x * line.pixel_size
		_check(wide <= board_width + 0.001, "a fragment line runs off the board: " + line.text)
		_check(size < 0.0 or is_equal_approx(size, line.pixel_size), "one size for the fragment")
		size = line.pixel_size
	# The canonical two lines and nothing else: no verdict, no stamp that
	# settles whether anything was forecast.
	var canonical: Array[String] = [TranslationServer.translate("STILL_HERE_BOARD_FRAGMENT_A"), TranslationServer.translate("STILL_HERE_BOARD_FRAGMENT_B")]
	_check(showing == canonical, "the fragment is the two lines alone: %s" % [showing])
	for node: Node in lines:
		if (node as Label3D).visible:
			_check((node as Label3D).modulate == StillHereRefuge.DISPLAY_TEXT, "the fragment comes back in the pier's display voice")
	refuge_view.show_fragment(false)
	_check((lines[0] as Label3D).text == TranslationServer.translate("STILL_HERE_BOARD_PIER"), "the ferry again")

	# Latch is asked the score: one line, after the bench.
	spoken.clear()
	refuge_view.caption.clear()
	refuge_view.apply_state(messages.back()["state"])
	for _frame: int in range(3):
		await process_frame
	_check(refuge_view.caption.showing() == TranslationServer.translate("STILL_HERE_LINE_LATCH_SCORE"), "Latch stopped counting")

	# The turn's cover waits for the server's world before it lifts.
	var turn: StillHereTurn = StillHereTurn.new()
	var covered: Array[bool] = []
	turn.covered.connect(func() -> void: covered.append(true))
	root.add_child(turn)
	await process_frame
	turn._process(6.0)
	_check(turn.covering() and covered.size() == 1, "the cover darkens the court and says so once")
	turn._process(6.0)
	_check(turn.covering(), "the cover never lifts before the world turns")
	turn.world_turned()
	for _step: int in range(8):
		turn._process(0.5)
	_check(not turn.covering(), "the cover lifts on the later world")
	turn.queue_free()
	# With the elapsed-time page open, the cover holds until the reader is done.
	var paged: StillHereTurn = StillHereTurn.new()
	paged.covered.connect(func() -> void: paged.page_opened())
	root.add_child(paged)
	await process_frame
	paged._process(1.0)
	paged.world_turned()
	for _step: int in range(12):
		paged._process(0.5)
	_check(paged.covering(), "the cover holds while the page is open")
	paged.page_closed()
	for _step: int in range(8):
		paged._process(0.5)
	_check(not paged.covering(), "the cover lifts once the page is read")
	paged.queue_free()

	# The coda: the fragment, the ring, the credits, then it ends.
	var named: String = "\n".join(StillHereCoda.credits(everyone))
	var bare: String = "\n".join(StillHereCoda.credits(nobody))
	for who: String in ["EDDA", "SPLICE", "ORRIN", "SORREL"]:
		var name: String = TranslationServer.translate("STILL_HERE_NAME_" + who)
		_check(name in named, who + " credited when the run saw them again")
		_check(name not in bare, who + " never credited when it did not")
	_check(TranslationServer.translate("STILL_HERE_NAME_LATCH") in bare, "Latch always")
	var coda: StillHereCoda = StillHereCoda.new()
	coda.refuge = refuge_view
	var ended: Array[bool] = []
	coda.finished.connect(func() -> void: ended.append(true))
	root.add_child(coda)
	await process_frame
	coda._process(StillHereCoda.FRAGMENT_AT + 0.5)
	_check(refuge_view.fragment, "the board speaks once in the coda")
	coda._process(StillHereCoda.FRAGMENT_END - StillHereCoda.FRAGMENT_AT)
	_check(not refuge_view.fragment, "and then times the ferry again")
	for _step: int in range(200):
		if not ended.is_empty():
			break
		coda._process(0.5)
	_check(ended.size() == 1, "the coda ends")
	coda.queue_free()

	# The other ending: no epilogue title, no names it never saw again, the
	# same two lines on black, the anomaly, and it ends.
	var last: Array[String] = StillHereCoda.credits_for(StillHereCoda.EXHAUSTION, everyone)
	_check(TranslationServer.translate("STILL_HERE_CREDITS_TITLE") not in last, "the exhaustion credits claim no walk")
	for who: String in ["EDDA", "SPLICE", "ORRIN", "SORREL"]:
		_check(TranslationServer.translate("STILL_HERE_NAME_" + who) not in "\n".join(last), who + " is not named by an ending that never reached the refuge")
	_check(TranslationServer.translate("STILL_HERE_NAME_LATCH") in "\n".join(last), "Latch in either ending")
	var other: StillHereCoda = StillHereCoda.new()
	other.ending = StillHereCoda.EXHAUSTION
	var closed: Array[bool] = []
	other.finished.connect(func() -> void: closed.append(true))
	root.add_child(other)
	await process_frame
	other._process(StillHereCoda.EXHAUSTION_FRAGMENT_AT + 1.0)
	var veil: ColorRect = other.get_node("Veil")
	var words: Label = other.get_node("Fragment")
	_check(veil.color.a == 1.0 and other.fragment_showing(), "the exhaustion fragment shows on black")
	_check(words.text == "%s\n%s" % [TranslationServer.translate("STILL_HERE_BOARD_FRAGMENT_A"), TranslationServer.translate("STILL_HERE_BOARD_FRAGMENT_B")], "the same two lines, nothing more")
	_check(words.get_theme_color("font_color") == StillHereRefuge.DISPLAY_TEXT, "in the pier display's voice")
	other._process(StillHereCoda.EXHAUSTION_SPACE_AT - StillHereCoda.EXHAUSTION_FRAGMENT_AT)
	_check(not other.fragment_showing() and (other.get_node("DeepSpace") as Control).visible, "then the anomaly")
	for _step: int in range(200):
		if not closed.is_empty():
			break
		other._process(0.5)
	_check(closed.size() == 1, "the exhaustion coda ends")
	other.queue_free()

	# Only a durable run that runs out of continues in levels 18 to 20 gets
	# that ending, once, and its pages close on the exhaustion coda.
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var owned: LocalMatch = LocalMatch.new()
	manager.local_match = owned
	manager.is_human_player = true
	owned.set("_run_mode", "resume")
	var failed: Dictionary = {"id": MissionState.M20_ID, "run": {"status": "failed"}}
	manager._present_wipe_failure({"id": MissionState.M10_ID, "run": {"status": "failed"}})
	_check(not manager._wipe_failure_started, "a failure before the wipe is not the wipe's ending")
	manager._present_wipe_failure({"id": MissionState.M20_ID, "run": {"status": "continue"}})
	_check(not manager._wipe_failure_started, "a continue is not an ending")
	owned.set("_run_mode", "")
	manager._present_wipe_failure(failed)
	_check(not manager._wipe_failure_started, "a development child has no run to end")
	owned.set("_run_mode", "resume")
	for wipe: String in [MissionState.M18_ID, MissionState.M19_ID]:
		_check(wipe in StoryScene.WIPE_LEVELS, wipe + " is a wipe level")
	manager._present_wipe_failure(failed)
	_check(manager._wipe_failure_started, "a durable run out of continues in the wipe ends here")
	manager._close_wipe_failure_pages()
	var closing: StillHereCoda = manager.wipe_failure_coda
	_check(closing != null and closing.ending == StillHereCoda.EXHAUSTION, "its pages close on the exhaustion coda")
	manager.free()
	owned.free()

	eye.queue_free()
	refuge_view.clear_map()
	refuge_view.queue_free()
	await process_frame
	if failures == 0:
		print("test_still_here_presentation: PASS")
	quit(1 if failures > 0 else 0)
