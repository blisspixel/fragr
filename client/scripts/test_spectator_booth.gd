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
	set_meta("localexception_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_spectator_booth: " + message)

func _facts() -> Dictionary:
	return {"type": "spectator_facts", "tick": 400, "spree_step": 5,
		"pads": [{"id": "rail", "kind": "weapon", "weapon": "Rail", "power": true, "back_in": 40, "clock": 300},
			{"id": "scatter_b", "kind": "weapon", "weapon": "Scatter", "power": true, "back_in": 300, "clock": 300},
			{"id": "health", "kind": "health", "back_in": 100, "clock": 300}],
		"plate": {"id": "plate", "up": false, "back_in": 520, "clock": 700},
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
	_check(facts.plate.back_in == 520 and facts.plate.clock == 700 and facts.plate.holder == "" and not facts.plate.up, "a down plate keeps its clocks and no wearer")
	_check(facts.pads[0].clock == 300, "a pad carries its whole return clock")
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
	negative["pads"] = [{"id": "rail", "kind": "weapon", "back_in": -1, "clock": 300}]
	refusals.append(negative)
	var extra: Dictionary = _facts()
	extra["pads"] = [{"id": "rail", "kind": "weapon", "back_in": 4, "clock": 300, "x": 1}]
	refusals.append(extra)
	var no_clock: Dictionary = _facts()
	no_clock["pads"] = [{"id": "rail", "kind": "weapon", "back_in": 4}]
	refusals.append(no_clock)
	var bad_plate_clock: Dictionary = _facts()
	bad_plate_clock["plate"] = {"id": "plate", "up": false, "back_in": 4, "clock": -2}
	refusals.append(bad_plate_clock)
	var half_holder: Dictionary = _facts()
	half_holder["plate"] = {"id": "plate", "up": false, "holder": A}
	refusals.append(half_holder)
	var flood: Dictionary = _facts()
	var many: Array = []
	for index: int in range(SpectatorFacts.MAX_PADS + 1):
		many.append({"id": "p%d" % index, "kind": "health", "back_in": 4, "clock": 300})
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
	var region := Rect2(600, 90, 720, 400)
	panel.set_region(region)
	panel.observe_snapshot(_snapshot())
	panel.observe_facts(SpectatorFacts.parse(_facts()))
	panel.clock_override_ms = 0
	# Default: power items always, an ordinary pad only in its last seconds.
	var tiles: Array[Dictionary] = panel.tiles(false)
	var keys: Array = tiles.map(func(tile: Dictionary) -> String: return str(tile.key))
	_check(keys == ["plate", "Rail", "health"], "power items lead and only a returning ordinary pad joins: " + str(keys))
	_check(tiles[0].value == "0:26" and tiles[0].tone == "wait" and is_equal_approx(tiles[0].left, 26.0 / 35.0), "the Plate counts down round its ring: " + str(tiles[0]))
	_check(tiles[1].value == "0:02" and tiles[1].tone == "soon" and is_equal_approx(tiles[1].left, 2.0 / 15.0), "a power pad about to return is marked soon: " + str(tiles[1]))
	_check(tiles[2].value == "0:05" and tiles[2].tone == "soon" and not tiles[2].power, "health returning in five seconds earns a tile")
	_check(not keys.has("Scatter") and not keys.has("armor") and not keys.has("Flechette"), "ordinary pads that are up stay off the default strip")
	# Expanded while the scoreboard is held: every kind of pad on the map.
	var all: Array = panel.tiles(true).map(func(tile: Dictionary) -> String: return str(tile.key))
	_check(all == ["plate", "Rail", "Scatter", "Flechette", "armor", "health"], "the expanded strip shows every pad kind in order: " + str(all))
	_check(panel.tiles(true)[2].value == "UP" and panel.tiles(true)[2].tone == "up" and is_zero_approx(panel.tiles(true)[2].left), "a gun with any copy up reads up with a full ring")
	panel.clock_override_ms = 1500
	_check(panel.tiles(false)[1].value == "0:01" and panel.tiles(false)[0].value == "0:25", "clocks count down between messages")
	panel.clock_override_ms = 0
	panel.observe_facts(SpectatorFacts.parse(_facts()))
	var far: Dictionary = SpectatorFacts.parse(_facts())
	far.tick = 401
	far.pads[2].back_in = 200
	panel.observe_facts(far)
	_check(not panel.tiles(false).map(func(tile: Dictionary) -> String: return str(tile.key)).has("health"), "ordinary pads far from returning stay off")
	# The notes: runs by tier, an open chain on its own.
	var lines: Array[Dictionary] = panel.notes()
	_check(lines.size() == 2 and lines[0].text == "RAMPAGE: NIGHTFALL 6" and lines[0].tone == "run", "the run names its tier, callsign and frags: " + str(lines))
	_check(lines[1].text == "STATIC KID TRIPLE", "an open chain off the runs is its own note: " + str(lines))
	var worn: Dictionary = SpectatorFacts.parse(_facts())
	worn.tick = 402
	worn.plate = {"id": "plate", "up": false, "back_in": 500, "clock": 700, "holder": B, "armor": 143}
	panel.observe_facts(worn)
	_check(panel.tiles(false)[0].value == "143" and panel.tiles(false)[0].tone == "held", "the worn Plate shows its armour in gold")
	_check(panel.notes()[0].text == "PLATE: AUNT LINDA" and panel.notes()[0].tone == "held", "the wearer leads the notes")
	var stale: Dictionary = SpectatorFacts.parse(_facts())
	stale.tick = 10
	panel.observe_facts(stale)
	_check(panel.tiles(false)[0].tone == "held", "older facts never replace newer ones")
	panel.clock_override_ms = SpectatorPanel.STALE_MS + 1
	_check(panel.tiles(true).is_empty() and panel.notes().is_empty(), "a booth that stopped talking hides")
	panel.clock_override_ms = 0
	panel.watching = true
	panel._process(1.0)
	var strip: Node = panel.get_node("Rows")
	_check(panel.visible and strip.get_child_count() == 3, "a watcher sees one tile per shown pad: " + str(strip.get_child_count()))
	_check((panel.get_node("Heading") as Label).text == "PADS", "the strip says what it is")
	_check(region.encloses(panel.get_global_rect()), "the strip stays in its column: " + str(panel.get_global_rect()))
	_check(absf(panel.get_global_rect().get_center().x - region.get_center().x) <= 1.0, "the strip is centred under the scoreline")
	for label: Node in panel.find_children("*", "Label", true, false):
		_check((label as Label).uppercase and (label as Label).get_theme_font("font") == MenuTheme.FONT, "every booth word is Silkscreen in capitals")
		_check(is_zero_approx((label as Label).rotation), "booth words sit level")
	var ring: Control = strip.get_child(0).get_node("Ring")
	_check(ring.size.x >= 40.0 and is_zero_approx(ring.rotation), "the ring is a level icon tile")
	panel.set_expanded(true)
	panel._process(1.0)
	_check(strip.get_child_count() == 6 and (panel.get_node("Heading") as Label).text == "ALL PADS", "holding the scoreboard expands the strip")
	_check(region.encloses(panel.get_global_rect()), "the expanded strip still fits its column: " + str(panel.get_global_rect()))
	panel.set_expanded(false)
	var long_run: Dictionary = SpectatorFacts.parse(_facts())
	long_run.tick = 403
	long_run.chains = [{"id": A, "frags": 2, "open_for": 30}]
	panel._names[A] = "Second Sighting"
	panel.observe_facts(long_run)
	_check(panel.notes()[0].text == "RAMPAGE: SECOND SIGHTING 6 DOUBLE", "a run with an open chain says both at once: " + str(panel.notes()))
	panel.watching = false
	panel._process(1.0)
	_check(not panel.visible, "a fighter never sees the booth strip")
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
		"pads": [{"id": "rail", "kind": "weapon", "weapon": "Rail", "power": true, "back_in": 40, "clock": 300}]})
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
