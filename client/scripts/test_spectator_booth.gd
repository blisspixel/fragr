extends SceneTree

## The booth: booth facts at the client boundary, the watcher's panel, the
## director's cuts, the nameplate's health bar and the kill glyph fallback.

const A: String = "00000000-0000-0000-0000-00000000000a"
const B: String = "00000000-0000-0000-0000-00000000000b"
const C: String = "00000000-0000-0000-0000-00000000000c"

class Fighter extends Node3D:
	var player_id: String = ""
	var hp: int = 100
	func set_local_fp(_enabled: bool) -> void:
		pass

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_spectator_booth: " + message)

func _facts() -> Dictionary:
	return {"type": "spectator_facts", "tick": 400, "spree_step": 5,
		"pads": [{"id": "rail", "kind": "weapon", "weapon": "Rail", "power": true, "back_in": 40},
			{"id": "scatter_b", "kind": "weapon", "weapon": "Scatter", "power": true, "back_in": 300},
			{"id": "health", "kind": "health", "back_in": 100}],
		"plate": {"id": "plate", "up": false, "back_in": 520},
		"sprees": [{"id": A, "frags": 6}, {"id": B, "frags": 2}],
		"chains": [{"id": C, "frags": 3, "open_for": 31}]}

func _snapshot() -> Dictionary:
	return {"pickups": [
			{"id": "plate", "kind": "plate", "x": 31.0, "y": 9.4, "z": -22.0, "available": false},
			{"id": "rail", "kind": "weapon", "weapon": "Rail", "x": -20.0, "y": 1.4, "z": 6.0, "available": false},
			{"id": "scatter_a", "kind": "weapon", "weapon": "Scatter", "x": -21.0, "y": 4.4, "z": -15.0, "available": true},
			{"id": "scatter_b", "kind": "weapon", "weapon": "Scatter", "x": 4.0, "y": 4.4, "z": 2.0, "available": false},
			{"id": "flechette", "kind": "weapon", "weapon": "Flechette", "x": 0.0, "y": 0.4, "z": 0.0, "available": true},
			{"id": "armor", "kind": "armor", "x": 0.0, "y": 4.4, "z": -6.5, "available": true},
			{"id": "health", "kind": "health", "x": 0.0, "y": 4.4, "z": 7.0, "available": false}],
		"players": [{"id": A, "name": "Nightfall"}, {"id": B, "name": "Aunt Linda"}, {"id": C, "name": "Static Kid"}]}

func _run() -> void:
	_check_boundary()
	_check_panel()
	_check_director()
	_check_nameplate()
	_check_feed_and_board()
	# Let queued frees land before the exit leak check.
	for frame: int in range(3):
		await process_frame
	if _failures == 0:
		print("test_spectator_booth: PASS boundary, panel, director, nameplate bar, kill glyphs")
		quit(0)
	else:
		quit(1)

func _check_boundary() -> void:
	var facts: Dictionary = SpectatorFacts.parse(_facts())
	_check(not facts.is_empty() and facts.tick == 400 and facts.pads.size() == 3 and facts.pads[0].power, "valid booth facts parse")
	_check(facts.plate.back_in == 520 and facts.plate.holder == "" and not facts.plate.up, "a down plate keeps its clock and no wearer")
	_check(facts.sprees[0].id == A and facts.chains[0].open_for == 31, "runs keep their ids and window")
	var quiet: Dictionary = SpectatorFacts.parse({"type": "spectator_facts", "tick": 1, "spree_step": 3})
	_check(not quiet.is_empty() and quiet.pads.is_empty() and quiet.plate.is_empty(), "omitted lists read as empty")
	var refusals: Array = []
	var unknown: Dictionary = _facts()
	unknown["hp"] = [100]
	refusals.append(unknown)
	var bad_id: Dictionary = _facts()
	bad_id["sprees"] = [{"id": "nightfall", "frags": 6}]
	refusals.append(bad_id)
	var negative: Dictionary = _facts()
	negative["pads"] = [{"id": "rail", "kind": "weapon", "back_in": -1}]
	refusals.append(negative)
	var extra: Dictionary = _facts()
	extra["pads"] = [{"id": "rail", "kind": "weapon", "back_in": 4, "x": 1}]
	refusals.append(extra)
	var half_holder: Dictionary = _facts()
	half_holder["plate"] = {"id": "plate", "up": false, "holder": A}
	refusals.append(half_holder)
	var flood: Dictionary = _facts()
	var many: Array = []
	for index: int in range(SpectatorFacts.MAX_PADS + 1):
		many.append({"id": "p%d" % index, "kind": "health", "back_in": 4})
	flood["pads"] = many
	refusals.append(flood)
	for refused: Dictionary in refusals:
		_check(SpectatorFacts.parse(refused).is_empty(), "malformed booth facts are refused: " + str(refused).left(120))
	# A fighter's client drops the booth even if a server sent it.
	var net: Node = load("res://scripts/net_client.gd").new()
	var heard: Array = []
	net.spectator_facts_received.connect(func(parsed: Dictionary) -> void: heard.append(parsed))
	net._handle_message(JSON.stringify(_facts()))
	_check(heard.size() == 1, "a watcher hears the booth")
	net.player_id = A
	net._handle_message(JSON.stringify(_facts()))
	_check(heard.size() == 1, "a fighter never hears the booth")
	net.free()

func _check_panel() -> void:
	var panel := SpectatorPanel.new()
	root.add_child(panel)
	panel.set_region(Rect2(20, 120, 400, 600))
	panel.observe_snapshot(_snapshot())
	panel.observe_facts(SpectatorFacts.parse(_facts()))
	panel.clock_override_ms = 0
	var rows: Array[Dictionary] = panel.rows()
	var keys: Array = rows.map(func(row: Dictionary) -> String: return str(row.key))
	_check(keys == ["plate", "Rail", "Scatter", "armor", "heading", "run:" + A, "chain:" + C], "panel rows in caster order: " + str(keys))
	_check(rows[0].value == "0:26" and rows[0].tone == "wait", "the Plate counts down from its clock: " + str(rows[0]))
	_check(rows[1].value == "0:02" and rows[1].tone == "soon", "a power pad about to return is marked soon: " + str(rows[1]))
	_check(rows[2].value == "UP" and rows[2].tone == "up", "a gun with any copy up reads up")
	_check(rows[4].label == "RAMPAGE" and rows[5].label == "NIGHTFALL" and rows[5].value == "6", "the run names its tier, callsign and frags: " + str(rows.slice(4)))
	_check(rows[6].label == "STATIC KID" and rows[6].value == "TRIPLE", "an open chain off the runs is its own row")
	_check(not keys.has("run:" + B), "a two-frag run stays off the panel")
	panel.clock_override_ms = 1500
	_check(panel.rows()[1].value == "0:01" and panel.rows()[0].value == "0:25", "clocks count down between messages")
	var worn: Dictionary = SpectatorFacts.parse(_facts())
	worn.plate = {"id": "plate", "up": false, "back_in": 500, "holder": B, "armor": 143}
	panel.observe_facts(worn)
	panel.clock_override_ms = 0
	_check(panel.rows()[0].label == "AUNT LINDA" and panel.rows()[0].value == "143" and panel.rows()[0].tone == "held", "the wearer and the plated armour lead")
	var stale: Dictionary = SpectatorFacts.parse(_facts())
	stale.tick = 10
	panel.observe_facts(stale)
	_check(panel.rows()[0].label == "AUNT LINDA", "older facts never replace newer ones")
	panel.clock_override_ms = SpectatorPanel.STALE_MS + 1
	_check(panel.rows().is_empty(), "a booth that stopped talking hides")
	panel.clock_override_ms = 0
	panel.watching = true
	panel._process(1.0)
	_check(panel.visible and panel.get_node("Rows").get_child_count() == 7, "a watcher sees the rows")
	for row: Node in panel.get_node("Rows").get_children():
		var plate: Control = row as Control
		_check(Rect2(panel.global_position, Vector2(400, 600)).encloses(plate.get_global_rect()) or plate.size.x <= 400.0, "rows stay in their column")
		for label: Node in plate.find_children("*", "Label", true, false):
			_check((label as Label).uppercase and (label as Label).get_theme_font("font") == MenuTheme.FONT, "every booth word is Silkscreen in capitals")
			_check(is_zero_approx((label as Label).rotation), "booth words sit level")
	var long_run: Dictionary = SpectatorFacts.parse(_facts())
	long_run.chains = [{"id": A, "frags": 2, "open_for": 30}]
	panel._names[A] = "Second Sighting"
	panel.observe_facts(long_run)
	panel._process(1.0)
	var run_row: Node = panel.get_node("Rows").get_child(5)
	_check((run_row.get_node("Content/Value") as Label).text == "DOUBLE 6" and (run_row.get_node("Content/Label") as Label).text == "S. SIGHTING",
		"a long callsign beside a chain is shortened, not cut: " + (run_row.get_node("Content/Label") as Label).text)
	panel.watching = false
	panel._process(1.0)
	_check(not panel.visible, "a fighter never sees the booth panel")
	panel.watching = true
	panel.set_covered(true)
	panel._process(1.0)
	_check(not panel.visible, "a card covers the booth")
	panel.queue_free()

func _check_director() -> void:
	var camera: Node3D = load("res://scripts/spectator_cam.gd").new()
	var fighters: Array = []
	var spots: Array[Vector3] = [Vector3(-19, 1.5, 6), Vector3(10, 1.5, 10), Vector3(30, 9.5, -20)]
	var ids: Array[String] = [A, B, C]
	for index: int in range(3):
		var fighter := Fighter.new()
		fighter.player_id = ids[index]
		fighter.position = spots[index]
		root.add_child(fighter)
		fighters.append(fighter)
	root.add_child(camera)
	camera.set_available_targets(fighters)
	camera.follow_target_index = 1
	var pickups: Array = _snapshot().pickups
	var quiet: Dictionary = SpectatorFacts.parse({"type": "spectator_facts", "tick": 1, "spree_step": 5})
	camera.director_observe_facts(quiet, pickups)
	_check(camera.follow_target_index == 1 and camera.director_reason == "", "a quiet booth makes no cut")
	# A Rail returning in two seconds with a fighter beside it.
	var rail: Dictionary = SpectatorFacts.parse({"type": "spectator_facts", "tick": 2, "spree_step": 5,
		"pads": [{"id": "rail", "kind": "weapon", "weapon": "Rail", "power": true, "back_in": 40}]})
	camera.director_observe_facts(rail, pickups)
	_check(camera.get_followed_target() == fighters[0] and camera.director_reason == "power", "the director cuts to the fighter by a returning power pad")
	# A spree is a smaller moment and waits out the power cut's hold.
	var spree: Dictionary = SpectatorFacts.parse({"type": "spectator_facts", "tick": 3, "spree_step": 5,
		"sprees": [{"id": B, "frags": 5}]})
	camera.director_observe_facts(spree, pickups)
	_check(camera.get_followed_target() == fighters[0], "a smaller cue never cuts into a bigger one's hold")
	# A multikill is bigger and cuts in.
	var chain: Dictionary = SpectatorFacts.parse({"type": "spectator_facts", "tick": 4, "spree_step": 5,
		"chains": [{"id": C, "frags": 2, "open_for": 50}]})
	camera.director_observe_facts(chain, pickups)
	_check(camera.get_followed_target() == fighters[2] and camera.director_reason == "multikill", "a multikill cuts in")
	camera.director_observe_facts(chain, pickups)
	_check(camera.director_reason == "multikill", "the same chain is not cut to twice")
	camera._process(10.0)
	camera.director_observe_frag({"weapon": "rocket"}, B)
	_check(camera.get_followed_target() == fighters[1] and camera.director_reason == "rocket", "a Rocket frag cuts to its shooter")
	camera._process(10.0)
	camera.director_observe_frag({"weapon": "rail"}, A)
	_check(camera.get_followed_target() == fighters[1], "an ordinary frag is not a director cue")
	# The watcher takes the camera: the director rests.
	camera.director_rest()
	camera.director_observe_frag({"weapon": "rocket"}, A)
	_check(camera.get_followed_target() == fighters[1], "a resting director never cuts")
	camera._process(spectator_rest_seconds(camera) + 0.1)
	camera.fp_mode = true
	camera.director_observe_frag({"weapon": "rocket"}, A)
	_check(not camera.director_can_cut(), "a joined fighter's camera is never directed")
	camera.fp_mode = false
	camera.director_observe_frag({"weapon": "rocket"}, "absent")
	_check(camera.get_followed_target() == fighters[1], "a fighter not on the field is not cut to")
	# Far from every fighter, a returning pad is no fight.
	camera._process(10.0)
	var lonely: Dictionary = SpectatorFacts.parse({"type": "spectator_facts", "tick": 9, "spree_step": 5,
		"plate": {"id": "plate", "up": false, "back_in": 20}})
	fighters[2].position = Vector3(-30, 1.5, 30)
	camera.director_observe_facts(lonely, pickups)
	_check(camera.director_reason == "rocket", "a pad nobody is near makes no cut")
	camera.queue_free()
	for fighter: Node in fighters:
		fighter.queue_free()

static func spectator_rest_seconds(camera: Node3D) -> float:
	return float((camera.get_script() as Script).get_script_constant_map()["DIRECTOR_REST_SECONDS"])

func _check_nameplate() -> void:
	_check(NameplateLayout.vitals_cells(100, 0) == Vector3i(40, 0, 0), "full health fills the bar")
	_check(NameplateLayout.vitals_cells(1, 50).x == 1 and NameplateLayout.vitals_cells(1, 50).y == 20, "a living fighter always shows a sliver")
	_check(NameplateLayout.vitals_cells(0, 0).x == 0, "a dead fighter shows none")
	_check(NameplateLayout.vitals_cells(100, 150) == Vector3i(40, 40, 20), "plated armour is its own run of cells")
	var label := Label3D.new()
	root.add_child(label)
	var bar: Sprite3D = NameplateLayout.vitals_bar(label)
	_check(NameplateLayout.vitals_bar(label) == bar, "the bar is made once")
	NameplateLayout.style_plate(label)
	_check(label.no_depth_test and bar.no_depth_test, "plate words and bar are never cut by geometry")
	NameplateLayout.paint_vitals(bar, 40, 120)
	_check(bar.get_meta("vitals") == Vector2i(40, 120), "the bar repaints for new vitals")
	var image: Image = NameplateLayout.vitals_image(40, 120)
	_check(image.get_size() == Vector2i(NameplateLayout.BAR_CELLS), "the bar is pixel cells")
	_check(image.get_pixel(1, 1).is_equal_approx(NameplateLayout.BAR_HURT), "low health is ember, never red")
	_check(image.get_pixel(30, 1).is_equal_approx(NameplateLayout.BAR_EMPTY), "spent health reads as empty steel")
	_check(image.get_pixel(1, 4).is_equal_approx(NameplateLayout.BAR_PLATED), "plated armour shows")
	_check(image.get_pixel(0, 0).is_equal_approx(NameplateLayout.BAR_INK), "the bar is rimmed in ink")
	for x: int in range(image.get_width()):
		for y: int in range(image.get_height()):
			var pixel: Color = image.get_pixel(x, y)
			_check(not (pixel.r > 0.7 and pixel.g < 0.3 and pixel.b < 0.3), "no Union red on a nameplate")
	_check(NameplateLayout.plate_text("Aunt Linda", "Balanced", " +3") == "Aunt Linda [BAL] +3", "words keep the true chip, no health text")
	label.queue_free()

func _check_feed_and_board() -> void:
	_check(FragFeed.kill_glyph("Unsupported") == null and not FragFeed.is_kill_icon("Unsupported"), "a gun without art is spelled out")
	for art: String in WeaponArt.KILL_ICON:
		_check(FragFeed.kill_glyph(art) == WeaponArt.KILL_ICON[art] and FragFeed.is_kill_icon(art), "a dedicated kill icon wins over the profile: " + art)
		_check(WeaponArt.KILL_ICON[art].get_size() == Vector2(48, 16), "kill icons are 48 by 16: " + art)
	for art: String in WeaponArt.PROFILE:
		_check(FragFeed.is_kill_icon(art), "every gun with a held profile has its own kill icon: " + art)
	_check(ScoreboardPlate.ping_text({"ping": 42}) == "42" and ScoreboardPlate.ping_text({}) == "--", "the board's ping cell")
