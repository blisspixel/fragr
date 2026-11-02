extends SceneTree

## No Forwarding Address golden-slice dressing: an authored-layout guard keyed
## on geometry that never moves, dressed rooms, warm local lamps and the
## floodlights, merged props, no words, no red or cyan light, no collision of
## its own, a district that survives the freight gate lifting and a tram that
## follows the server's tram along the trench.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m05_dressing: " + message)

static func _solid(low: Vector3, high: Vector3) -> Dictionary:
	return {"min_x": low.x, "max_x": high.x, "bottom": low.y, "top": high.y, "min_z": low.z, "max_z": high.z}

static func _info(map_id: int = 1005, chassis_x: float = 3.0, half: float = 40.0) -> Dictionary:
	return {"map_id": map_id, "map_name": "No Forwarding Address", "half_extent": half, "solids": [
		_solid(Vector3(-30, 0, -36), Vector3(-7, 4, -20)),
		_solid(Vector3(7, 0, -36), Vector3(30, 4, -20)),
		_solid(Vector3(-7, 3.75, -29), Vector3(7, 4, -26)),
		_solid(Vector3(-23, 0, -16), Vector3(18, 4, -15.5)),
		_solid(Vector3(chassis_x, 0, -13), Vector3(7, 2.5, -7)),
		_solid(Vector3(-1.5, 0, 4), Vector3(1.5, 1, 8)),
		_solid(Vector3(-40, 0, 33.5), Vector3(-15, 3, 34)),
		_solid(Vector3(-15, 0, 33.5), Vector3(15, 3, 34)),
		_solid(Vector3(-12, 0.5, 36), Vector3(2, 3, 39.5)),
	], "m05": {"tram": {"start": [0, 0, 6], "end": [0, 0, 28]}}}

static func _state(tram_z: float) -> Dictionary:
	return {"id": MissionState.M05_ID, "m05": {"tram": {"feet": [0.0, 0.0, tram_z]}}}

func _run() -> void:
	_expect(M05Dressing.layout(_info()), "the authored roofs and trench layout is recognized")
	_expect(not M05Dressing.layout(_info(1004)), "another mission never receives the M05 dressing")
	_expect(not M05Dressing.layout(_info(1005, 2.0)), "a reused id with a moved chassis gets no floating props")
	_expect(not M05Dressing.layout(_info(1005, 3.0, 50.0)), "a resized district gets no misplaced streets")
	_expect(not M05Dressing.layout({"map_id": 1005}), "a malformed map is refused")
	_expect(not M04Dressing.authored(_info()), "Level 4's dressing never claims the Level 5 map")
	var town: M05Dressing = M05Dressing.new()
	root.add_child(town)
	town.configure_map(_info(1005, 2.0))
	_expect(town.get_child_count() == 0 and not town.active(), "unrecognized layouts stay bare")
	town.configure_map(_info())
	var expected: Array[String] = ["StreetSouth", "StreetWest", "StreetEast", "FreightYard", "Ground", "Roofs", "Tanks", "Bridge", "Crane", "Workshop", "PaintBay", "LoadingPen", "ServiceBay", "MarketStrip", "Trench", "Freight", "Carrier", "Tram", "FreightGate"]
	for room: String in expected:
		_expect(room in town.rooms and town.has_node(room), "room dressed: " + room)
	_expect(town.lamps >= 14, "practical light on the roof, market, workshop, trench, platform and carrier, found %d" % town.lamps)
	var floods: int = 0
	for light: Node in town.find_children("*", "Light3D", true, false):
		var lamp: Light3D = light as Light3D
		var colour: Color = lamp.light_color
		_expect(not lamp.shadow_enabled, "presenter lights never add shadow maps: " + lamp.name)
		_expect(not (colour.r > 0.7 and colour.g < 0.3 and colour.b < 0.3), "no red light outside Union attack tells: " + lamp.name)
		_expect(not (colour.b > colour.r + 0.15 and colour.g > colour.r + 0.1), "no Inheritance cyan light: " + lamp.name)
		_expect(colour.r >= colour.b, "Low Water's practical light is warm: " + lamp.name)
		if lamp is OmniLight3D:
			_expect((lamp as OmniLight3D).omni_range <= 9.0, "presenter lamps stay local: " + lamp.name)
		if lamp is SpotLight3D:
			floods += 1
			_expect((lamp as SpotLight3D).spot_range <= 32.0, "the floodlights reach the ramp, not the whole district: " + lamp.name)
	_expect(floods == 2, "two floodlights over the freight platform, found %d" % floods)
	for node: Node in town.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	_expect(town.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing never adds a body; the server owns every solid")
	_expect(town.find_children("*", "WorldSign", true, false).is_empty() and town.find_children("*", "Label3D", true, false).is_empty(), "the dressing tells its story without words")
	for room: String in town.rooms:
		var props: Node = town.get_node(room).get_node_or_null("Props")
		_expect(props != null and props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
	# The tram's livery waits for a state, then follows the server's tram.
	var tram: Node3D = town.tram_room
	_expect(tram != null and not tram.visible, "the tram livery waits for the server's tram")
	_expect(town.gate_room != null and town.gate_room.visible and is_zero_approx(town.gate_room.position.y), "the gate's cladding sits on the closed gate")
	town.apply_state(_state(6.0))
	_expect(tram.visible and is_zero_approx(tram.position.z), "the tram livery sits on the docked tram")
	town.apply_state(_state(17.5))
	_expect(tram.visible and is_equal_approx(tram.position.z, 11.5), "the tram livery rides the trench with the server's tram")
	town.apply_state({"id": MissionState.M05_ID, "m05": {"tram": {"feet": [0.0, 0.0]}}})
	_expect(not tram.visible, "a malformed tram fact hides the livery rather than guessing")
	town.apply_state({"id": "m04"})
	_expect(not tram.visible, "another mission's state never shows the tram")
	town.configure_map(_info())
	_expect(town.rooms.size() == expected.size() and town.get_child_count() == expected.size(), "a repeated MapInfo keeps one set of rooms")
	# The freight gate lifting re-sends MapInfo with the gate raised, and the
	# tram's own solid may arrive moved: the district stays dressed through
	# both (Level 4 once lost its streets keying on a moving solid).
	var lifted: Dictionary = _info()
	lifted["solids"][7] = _solid(Vector3(-15, 3.2, 33.5), Vector3(15, 6.2, 34))
	lifted["solids"][5] = _solid(Vector3(-1.5, 0, 26), Vector3(1.5, 1, 30))
	_expect(M05Dressing.layout(lifted), "the lifted gate and a moved tram keep the authored layout")
	var before: Node = town.get_node("Roofs")
	town.configure_map(lifted)
	_expect(town.active() and town.get_child_count() == expected.size() and town.get_node("Roofs") == before, "the dressing survives the gate lifting without a rebuild")
	_expect(not tram.visible, "a re-sent map hides the tram until the next state, as the tram's own box does")
	_expect(town.gate_room != null and town.gate_room.visible and is_equal_approx(town.gate_room.position.y, 3.2), "the gate's cladding rises with the server's gate solid")
	town.apply_state(_state(28.0))
	_expect(tram.visible and is_equal_approx(tram.position.z, 22.0), "the next state places the tram again")
	town.configure_map(_info(1004))
	_expect(not town.active() and town.tram_room == null, "another map clears the M05 dressing")
	await process_frame
	_expect(town.get_child_count() == 0, "cleared rooms leave the tree")
	town.apply_state(_state(10.0))
	town.queue_free()
	await process_frame
	var preset: ArenaSky.Preset = ArenaSky.preset_for("No Forwarding Address")
	var level4: ArenaSky.Preset = ArenaSky.preset_for("Notice to Vacate")
	var shared: ArenaSky.Preset = ArenaSky.preset_for("Low Water")
	_expect(preset.key_rotation_degrees.x > -30.0 and preset.key_rotation_degrees.x < -10.0 and preset.key_color.r > preset.key_color.b,
		"No Forwarding Address keeps Level 4's low warm afternoon sun")
	_expect(preset.key_rotation_degrees.x > level4.key_rotation_degrees.x, "ten minutes on, the sun is a little lower than Level 4's")
	_expect(is_equal_approx(preset.view_fill_energy, level4.view_fill_energy) and preset.key_rotation_degrees != shared.key_rotation_degrees and preset.key_color != shared.key_color, "Level 4 actor fill is kept, apart from the multiplayer town's evening")
	if failures == 0:
		print("test_m05_dressing: PASS layout guard on fixed geometry, nineteen dressed rooms, warm lamps and floodlights, merged props, no words, no bodies, gate-lift survival and the rising gate, the riding tram and the afternoon sun")
	quit(0 if failures == 0 else 1)
