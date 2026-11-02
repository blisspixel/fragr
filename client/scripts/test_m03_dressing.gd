extends SceneTree

## Scheduled Service golden-slice dressing: authored-layout guard, the dressed
## yard rooms, local lamps with no red or cyan light, merged props, no words,
## no bodies, and the mast's dressing following the server's fallen solids.
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m03_dressing: " + message)

static func _solid(low: Vector3, high: Vector3) -> Dictionary:
	return {"min_x": low.x, "max_x": high.x, "bottom": low.y, "top": high.y, "min_z": low.z, "max_z": high.z}

static func _info(map_id: int = 1003, desk_x: float = 24.0, shutdown: bool = false) -> Dictionary:
	var solids: Array = [
		_solid(Vector3(18, 0, 11), Vector3(27, 2.5, 23)),
		_solid(Vector3(19, 2.5, 19), Vector3(26, 3.5, 23)),
		_solid(Vector3(-11, 0, 29), Vector3(-5, 2.2, 38)),
		_solid(Vector3(-27, 0, -36), Vector3(-25, 4, -35.5)),
		_solid(Vector3(-25, 0, 3), Vector3(-22, 0.8, 5)),
		_solid(Vector3(desk_x, 0, -30), Vector3(26, 0.8, -27)),
		_solid(Vector3(5, 0, -27), Vector3(11, 3, -15)),
	]
	if shutdown:
		solids.append(_solid(Vector3(19, 3.5, 19.25), Vector3(25, 4.5, 20.25)))
		solids.append(_solid(Vector3(24.2, 3.5, 21.2), Vector3(25.8, 5.1, 22.8)))
	else:
		solids.append(_solid(Vector3(21.5, 2.5, 16.5), Vector3(22.5, 7, 17.5)))
		solids.append(_solid(Vector3(21.2, 7, 16.2), Vector3(22.8, 8, 17.8)))
	return {"map_id": map_id, "map_name": "Scheduled Service", "solids": solids, "m03": {"mast_shutdown": shutdown}}

func _mast_bounds(yard: M03Dressing) -> AABB:
	var mast: Node3D = yard.get_node("Mast") as Node3D
	var mesh: MeshInstance3D = mast.get_node("Props").get_child(0) as MeshInstance3D
	return mesh.global_transform * mesh.get_aabb()

func _run() -> void:
	_expect(M03Dressing.authored(_info()), "the authored yard layout is recognized")
	_expect(M03Dressing.authored(_info(1003, 24.0, true)), "the yard stays recognized after the mast falls")
	_expect(not M03Dressing.authored(_info(1002)), "another mission never receives the yard dressing")
	_expect(not M03Dressing.authored(_info(1003, 23.5)), "a reused id with a moved desk gets no floating props")
	_expect(not M03Dressing.authored({"map_id": 1003}), "a malformed map is refused")
	var yard: M03Dressing = M03Dressing.new()
	root.add_child(yard)
	yard.configure_map(_info(1003, 23.5))
	_expect(yard.get_child_count() == 0 and not yard.active(), "unrecognized layouts stay bare")
	yard.configure_map(_info())
	var expected: Array[String] = ["Perimeter", "Complex", "Country", "Tracks", "Platform", "Cars", "Board", "Office", "Hut", "Mast", "SignalBox", "Gantry", "Locomotive"]
	for room: String in expected:
		_expect(room in yard.rooms and yard.has_node(room), "room dressed: " + room)
	_expect(yard.lamps >= 12, "practical light marks where people work, found %d" % yard.lamps)
	for light: Node in yard.find_children("*", "Light3D", true, false):
		var lamp: Light3D = light as Light3D
		var colour: Color = lamp.light_color
		_expect(not lamp.shadow_enabled, "presenter lights never add shadow maps: " + lamp.name)
		_expect(not (colour.r > 0.7 and colour.g < 0.3 and colour.b < 0.3), "no red light outside Union attack tells: " + lamp.name)
		_expect(not (colour.b > colour.r + 0.15 and colour.g > colour.r + 0.1), "no Inheritance cyan light: " + lamp.name)
		if lamp is OmniLight3D:
			_expect((lamp as OmniLight3D).omni_range <= 9.5, "presenter lamps stay local: " + lamp.name)
	for node: Node in yard.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	_expect(yard.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing never adds a body; the server owns every solid")
	_expect(yard.find_children("*", "WorldSign", true, false).is_empty() and yard.find_children("*", "Label3D", true, false).is_empty(), "the dressing tells its story without words")
	for room: String in yard.rooms:
		var props: Node = yard.get_node(room).get_node_or_null("Props")
		_expect(props != null and props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
	# The standing mast rises well above the yard, over its column.
	var standing: AABB = _mast_bounds(yard)
	_expect(standing.end.y > 18.0 and standing.position.x > 20.0 and standing.end.x < 24.5, "the standing lattice rises over the column and reads from the whole yard")
	yard.configure_map(_info())
	_expect(yard.rooms.size() == expected.size() and yard.get_child_count() == expected.size(), "a repeated MapInfo keeps one set of rooms")
	# The fallen mast arrives as a new MapInfo; only the mast's dressing changes.
	var cars: Node = yard.get_node("Cars")
	yard.configure_map(_info(1003, 24.0, true))
	await process_frame
	_expect(yard.mast_down() and yard.get_node("Cars") == cars, "the fallen mast rebuilds only the mast")
	_expect(yard.find_children("Mast", "Node3D", false, false).size() == 1, "exactly one mast dressing after the fall")
	var fallen: AABB = _mast_bounds(yard)
	var footprint: AABB = AABB(Vector3(18.5, 3.4, 18.9), Vector3(7.8, 2.9, 4.2))
	_expect(footprint.encloses(fallen), "the fallen lattice stays on the fallen column and pod: %s" % fallen)
	yard.configure_map(_info(1002))
	_expect(not yard.active(), "another map clears the yard dressing")
	await process_frame
	_expect(yard.get_child_count() == 0, "cleared rooms leave the tree")
	yard.queue_free()
	await process_frame
	if failures == 0:
		print("test_m03_dressing: PASS authored guard, thirteen dressed rooms, local lamps, merged props, no words, no bodies and a mast that falls with its solids")
	quit(0 if failures == 0 else 1)
