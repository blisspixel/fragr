extends SceneTree

## Persons Unknown golden-slice dressing: authored-layout guard, eight dressed
## rooms, local warm lamps and cold fixture pools, merged props, no words, no
## red or cyan light and no collision of its own.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m02_correction: " + message)

static func _solid(low: Vector3, high: Vector3) -> Dictionary:
	return {"min_x": low.x, "max_x": high.x, "bottom": low.y, "top": high.y, "min_z": low.z, "max_z": high.z}

static func _info(map_id: int = 1002, frame_x: float = 8.0) -> Dictionary:
	return {"map_id": map_id, "map_name": "Persons Unknown", "solids": [
		_solid(Vector3(-5.5, 3.68, -32), Vector3(-4.7, 3.78, -29.5)),
		_solid(Vector3(-4, 0, -15), Vector3(0, 3.2, -13)),
		_solid(Vector3(frame_x, 0, -13), Vector3(9, 2.6, -9)),
		_solid(Vector3(-4, 0, 3), Vector3(-1, 2.2, 6)),
		_solid(Vector3(-5, 0, 19), Vector3(-3, 1.4, 21)),
		_solid(Vector3(-7, 0, 24), Vector3(7, 7, 25)),
	]}

func _run() -> void:
	_expect(M02Correction.authored(_info()), "the authored ward layout is recognized")
	_expect(not M02Correction.authored(_info(1001)), "another mission never receives the ward dressing")
	_expect(not M02Correction.authored(_info(1002, 7.5)), "a reused id with a moved frame gets no floating props")
	_expect(not M02Correction.authored({"map_id": 1002}), "a malformed map is refused")
	var ward: M02Correction = M02Correction.new()
	root.add_child(ward)
	ward.configure_map(_info(1002, 7.5))
	_expect(ward.get_child_count() == 0 and not ward.active(), "unrecognized layouts stay bare")
	ward.configure_map(_info())
	for room: String in ["Gallery", "Stair", "Service", "Antechamber", "Ward", "Floor", "SideWard", "Dock"]:
		_expect(room in ward.rooms and ward.has_node(room), "room dressed: " + room)
	_expect(ward.lamps >= 24, "practical light shapes every room, found %d" % ward.lamps)
	var warm: int = 0
	for light: Node in ward.find_children("*", "Light3D", true, false):
		var lamp: Light3D = light as Light3D
		var colour: Color = lamp.light_color
		_expect(not lamp.shadow_enabled, "presenter lights never add shadow maps: " + lamp.name)
		_expect(not (colour.r > 0.7 and colour.g < 0.3 and colour.b < 0.3), "no red light outside Union attack tells: " + lamp.name)
		_expect(not (colour.b > colour.r + 0.15 and colour.g > colour.r + 0.1), "no Inheritance cyan light: " + lamp.name)
		if lamp is OmniLight3D:
			_expect((lamp as OmniLight3D).omni_range <= 9.5, "presenter lamps stay local: " + lamp.name)
		if lamp is SpotLight3D:
			_expect((lamp as SpotLight3D).spot_range <= 7.0 and (lamp as SpotLight3D).spot_angle <= 45.0, "fixture pools stay bounded: " + lamp.name)
		if colour.r > colour.b + 0.2:
			warm += 1
	_expect(warm >= 18, "warm lamps mark where staff work against the cold strips, found %d" % warm)
	_expect(ward.find_children("FixturePool*", "SpotLight3D", true, false).size() >= 3, "hard fixture pools over the frame, the machine and the side ward")
	_expect(ward.find_children("YardDaylight", "OmniLight3D", true, false).size() == 1, "the dock's daylight is the way out")
	for node: Node in ward.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	_expect(ward.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing never adds a body; the server owns every solid")
	_expect(ward.find_children("*", "WorldSign", true, false).is_empty() and ward.find_children("*", "Label3D", true, false).is_empty(), "the dressing tells its story without words")
	for room: String in ward.rooms:
		var props: Node = ward.get_node(room).get_node_or_null("Props")
		_expect(props != null and props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
	ward.configure_map(_info())
	_expect(ward.rooms.size() == 8 and ward.get_child_count() == 8, "a repeated MapInfo keeps one set of rooms")
	ward.configure_map(_info(1001))
	_expect(not ward.active(), "another map clears the ward dressing")
	await process_frame
	_expect(ward.get_child_count() == 0, "cleared rooms leave the tree")
	ward.queue_free()
	await process_frame
	if failures == 0:
		print("test_m02_correction: PASS authored guard, eight dressed rooms, local warm lamps and cold pools, merged props, no words and no bodies")
	quit(0 if failures == 0 else 1)
