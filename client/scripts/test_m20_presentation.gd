extends SceneTree

## Local Exception presentation from the native lifecycle fixture: the pier
## crowd is many different people in knots, never one issued jacket or a
## reserved faction look; the harbour display changes only its closure line
## at the reprieve while the tower answers; the HUD strip leaves rather than
## reading STOPPED; no notice narrates the pier, and Latch speaks once.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_m20_presentation: " + message)

static func _reserved(colour: Color) -> bool:
	# Union red, restoration cyan and a matte off-white base are never a
	# free person's dominant colour.
	var union_red: bool = colour.r > colour.g * 2.2 and colour.r > colour.b * 2.2 and colour.r > 0.35
	var cyan: bool = colour.b > colour.r * 1.4 and colour.g > colour.r * 1.4 and absf(colour.g - colour.b) < 0.12
	var bone: bool = colour.v > 0.78 and colour.s < 0.15
	return union_red or cyan or bone

func _run() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://golden/m20_lifecycle.json"))
	if not fixture is Dictionary or not fixture.get("messages") is Array:
		push_error("test_m20_presentation: missing native lifecycle fixture")
		quit(1)
		return
	var works: M20Waterworks = M20Waterworks.new()
	root.add_child(works)
	var notices: Array[String] = []
	works.notice_requested.connect(func(text: String) -> void: notices.append(text))
	works.configure_map(fixture["map_info"])
	await process_frame
	var spoken: Array[String] = []
	_check(works.caption != null and works.strips != null, "the presenter owns a speaker caption and the Paver strips")
	if works.caption != null:
		works.caption.line_said.connect(func(text: String) -> void: spoken.append(text))

	# The crowd: knots of distinct people, children and people sitting among
	# them, warm personal light on synthetics, and no reserved faction look.
	var people: Array[Node] = works.find_children("Refugee*", "", false, false)
	_check(people.size() >= 80, "four hundred people read as a crowd, not a handful: %d" % people.size())
	var coats: Dictionary[String, bool] = {}
	var roles: Dictionary[String, int] = {}
	var reserved: int = 0
	var lamps: int = 0
	for person: Node in people:
		var role: String = str(person.get_meta("crowd_role", ""))
		roles[role] = roles.get(role, 0) + 1
		if person is SkinnedCharacter:
			var skin: SkinnedCharacter = person
			if skin.source_body.find_child("FaceLamp", true, false) != null:
				lamps += 1
			for node: Node in skin.source_body.find_children("*", "MeshInstance3D", true, false):
				var part: MeshInstance3D = node
				if part.material_override != null:
					continue  # a carried bundle or a face light, not the body
				var material: ShaderMaterial = part.get_surface_override_material(0) as ShaderMaterial
				_check(material != null and material.shader == CrowdLook.OUTFIT_SHADER, "every crowd body wears its own outfit")
				if material != null:
					var coat: Color = material.get_shader_parameter("coat")
					coats[coat.to_html(false)] = true
					if _reserved(coat):
						reserved += 1
	_check(coats.size() >= 10, "many different coats, not one jacket: %d" % coats.size())
	_check(reserved == 0, "no crowd coat is Union red, restoration cyan or matte off-white")
	for role: String in ["standing", "child", "sitting", "synthetic", "carrying"]:
		_check(roles.get(role, 0) >= 3, "the crowd includes people %s" % role)
	_check(lamps == roles.get("synthetic", 0) and lamps > 0, "each free synthetic carries a warm face light")
	for colour: Color in M20Waterworks.FACE_LAMPS:
		_check(colour.r >= colour.b and not _reserved(colour), "face light is warm")
	# Light at height is amber, never a red optic.
	for node_name: String in ["MastLamp", "Beacon"]:
		var lamp: MeshInstance3D = works.find_child(node_name, true, false) as MeshInstance3D
		_check(lamp != null, node_name + " exists")
		if lamp != null:
			var colour: Color = (lamp.material_override as StandardMaterial3D).albedo_color
			_check(colour.g > colour.r * 0.5 and colour.r > colour.b, node_name + " burns amber, not red")

	# The lifecycle: the display, the tower, the strip and the notices.
	var strip: M20HoldStrip = M20HoldStrip.new()
	root.add_child(strip)
	await process_frame
	var display_line: Label3D = works.find_child("DisplayLine3", true, false) as Label3D
	var talkers: Array[MeshInstance3D] = works._tower_talkers
	var stairs: Array[MeshInstance3D] = works._tower_stair
	_check(display_line != null and talkers.size() == 2 and stairs.size() == 6, "display, talkers and stair exist")
	var saw_turn: bool = false
	var saw_reprieve: bool = false
	var opened: bool = false
	for message: Dictionary in fixture["messages"]:
		var state: Dictionary = message["state"]
		var facts: Dictionary = state["m20"]
		if facts["gate_open"] and not opened:
			# The gate-open world is a new MapInfo, as GameManager delivers it.
			opened = true
			works.configure_map(fixture["map_info_open"])
			await process_frame
			_check(works.caption != null, "the reopened presenter keeps a caption")
			if works.caption != null:
				works.caption.line_said.connect(func(text: String) -> void: spoken.append(text))
			display_line = works.find_child("DisplayLine3", true, false) as Label3D
			talkers = works._tower_talkers
			stairs = works._tower_stair
		works.apply_state(state)
		strip.apply(state, MissionState.geometry_for(fixture["map_info_open"] if facts["gate_open"] else fixture["map_info"]))
		strip.set_tick(int(message["tick"]))
		var reprieve: bool = facts.has("reprieve_at")
		if facts["display_lit"] and not reprieve:
			saw_turn = true
			_check(display_line.visible and display_line.text == tr("M20_DISPLAY_CLOSES"), "the turn states the closure")
			_check((talkers[0] as Node3D).visible and not (stairs[0] as Node3D).visible, "they are still talking at the turn")
		if reprieve:
			saw_reprieve = true
			_check(display_line.text == tr("M20_DISPLAY_EXCEPTED"), "the reprieve changes only the closure line")
			_check(not (talkers[0] as Node3D).visible and (stairs[0] as Node3D).visible, "the tower answers the reprieve")
			_check(not strip.visible, "the HUD strip leaves at the reprieve; no stopped timer")
	_check(saw_turn and saw_reprieve, "fixture covers the turn and the reprieve")
	_check(not notices.has(tr("M20_NOTICE_PIER")), "no notice narrates the pier")
	for line: String in notices:
		_check(not line.contains("Held them") and not line.contains("very polite"), "no spoken line arrives as a notice banner")
	var latch: Array[String] = []
	for line: String in spoken:
		if line == tr("M20_LATCH_EVEN"):
			latch.append(line)
	_check(latch.size() == 1 and latch[0].begins_with("Latch: ") and latch[0] != latch[0].to_upper(), "Latch speaks once, on the caption, in sentence case with a speaker label")
	_check(not StoryScene.BEFORE_MISSION.has(MissionState.M20_ID), "no page in: the clock carries straight on")
	var departure: Dictionary = StoryScene.load_scene(StoryScene.AFTER_MISSION[MissionState.M20_ID])
	for shot: Dictionary in departure.get("shots", []):
		_check(not shot.has("speaker_key"), "Latch's line is not repeated in the departure scene")
	strip.queue_free()
	works.queue_free()
	await process_frame
	if failures > 0:
		push_error("test_m20_presentation FAILED with %d failures" % failures)
		quit(1)
	else:
		print("test_m20_presentation: PASS refuge crowd, display exception, tower, strip and Latch's one line")
		quit(0)
