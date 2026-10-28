extends SceneTree

## Notice to Vacate golden-slice dressing: authored-layout guard, dressed
## rooms and streets, local warm lamps, merged props, no words, no red or cyan
## light and no collision of its own.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m04_dressing: " + message)

static func _solid(low: Vector3, high: Vector3) -> Dictionary:
	return {"min_x": low.x, "max_x": high.x, "bottom": low.y, "top": high.y, "min_z": low.z, "max_z": high.z}

static func _info(map_id: int = 1004, cab_x: float = 25.0, half: float = 40.0) -> Dictionary:
	return {"map_id": map_id, "map_name": "Notice to Vacate", "half_extent": half, "solids": [
		_solid(Vector3(-3, 0, -17), Vector3(3, 3, -16.5)),
		_solid(Vector3(-22.5, 0, 0), Vector3(-22, 2.7, 4)),
		_solid(Vector3(cab_x, 0, -15), Vector3(32, 2.5, -9)),
		_solid(Vector3(-13, 0, 10), Vector3(-5, 0.8, 11.5)),
		_solid(Vector3(-3, 0.7, 27), Vector3(3, 0.9, 30)),
		_solid(Vector3(7, 0, 29), Vector3(9, 1.2, 31)),
		_solid(Vector3(22, 0, -32), Vector3(34, 4, -31.5)),
	]}

func _run() -> void:
	_expect(M04Dressing.authored(_info()), "the authored Low Water layout is recognized")
	_expect(not M04Dressing.authored(_info(1005)), "another mission never receives the M04 dressing")
	_expect(not M04Dressing.authored(_info(1004, 24.0)), "a reused id with a moved tram gets no floating props")
	_expect(not M04Dressing.authored(_info(1004, 25.0, 50.0)), "a resized district gets no misplaced street facades")
	_expect(not M04Dressing.authored({"map_id": 1004}), "a malformed map is refused")
	var town: M04Dressing = M04Dressing.new()
	root.add_child(town)
	town.configure_map(_info(1004, 24.0))
	_expect(town.get_child_count() == 0 and not town.active(), "unrecognized layouts stay bare")
	town.configure_map(_info())
	var expected: Array[String] = ["StreetSouth", "StreetNorth", "StreetWest", "StreetEast", "Paving", "TramStop", "Square", "Market", "RepairBench", "Clinic", "TramStreet", "Workshop", "Court", "RoofExit"]
	for room: String in expected:
		_expect(room in town.rooms and town.has_node(room), "room dressed: " + room)
	_expect(town.lamps >= 14, "practical light at the stalls, bench, clinic, workshop and court, found %d" % town.lamps)
	for light: Node in town.find_children("*", "Light3D", true, false):
		var lamp: Light3D = light as Light3D
		var colour: Color = lamp.light_color
		_expect(not lamp.shadow_enabled, "presenter lights never add shadow maps: " + lamp.name)
		_expect(not (colour.r > 0.7 and colour.g < 0.3 and colour.b < 0.3), "no red light outside Union attack tells: " + lamp.name)
		_expect(not (colour.b > colour.r + 0.15 and colour.g > colour.r + 0.1), "no Inheritance cyan light: " + lamp.name)
		_expect(colour.r >= colour.b, "Low Water's practical light is warm: " + lamp.name)
		if lamp is OmniLight3D:
			_expect((lamp as OmniLight3D).omni_range <= 9.0, "presenter lamps stay local: " + lamp.name)
	_expect(town.find_children("*ClinicPendant*","OmniLight3D", true, false).size() == 4, "the clinic is bright and calm under its pendants")
	for node: Node in town.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	_expect(town.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing never adds a body; the server owns every solid")
	_expect(town.find_children("*", "WorldSign", true, false).is_empty() and town.find_children("*", "Label3D", true, false).is_empty(), "the dressing tells its story without words")
	for room: String in town.rooms:
		var props: Node = town.get_node(room).get_node_or_null("Props")
		_expect(props != null and props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
	town.configure_map(_info())
	_expect(town.rooms.size() == expected.size() and town.get_child_count() == expected.size(), "a repeated MapInfo keeps one set of rooms")
	town.configure_map(_info(1005))
	_expect(not town.active(), "another map clears the M04 dressing")
	await process_frame
	_expect(town.get_child_count() == 0, "cleared rooms leave the tree")
	town.queue_free()
	await process_frame
	var preset: ArenaSky.Preset = ArenaSky.preset_for("Notice to Vacate")
	var shared: ArenaSky.Preset = ArenaSky.preset_for("Low Water")
	_expect(preset.key_rotation_degrees.x > -30.0 and preset.key_rotation_degrees.x < -10.0 and preset.key_color.r > preset.key_color.b,
		"Notice to Vacate keeps its low warm late-afternoon sun")
	_expect(preset.view_fill_energy > 0.0 and shared.key_rotation_degrees == Vector3.ZERO, "the M04 light plan stays its own; the shared Low Water sky is unchanged")
	if failures == 0:
		print("test_m04_dressing: PASS authored guard, fourteen dressed rooms, warm local lamps, merged props, no words, no bodies and the late-afternoon sun")
	quit(0 if failures == 0 else 1)
