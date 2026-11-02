extends SceneTree

## Port of Entry golden-slice dressing: authored-layout guard, eight dressed
## rooms, local lamps and pools with no red or cyan light, no words and no
## collision of its own; solid views restyled by use with no glowing red
## steel, freight in practical paint that never reads as a faction livery,
## neutral pressure glass, and the floor tiled so each tile keeps its lights.
const ROOMS: Array[String] = ["Dock", "Freight", "Cage", "Loading", "Service", "Customs", "Exit", "Apron"]
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m06_dressing: " + message)

static func authored_info() -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m06_port_of_entry.json"))
	if not source is Dictionary:
		return {}
	var solids: Array = []
	var surfaces: Array = []
	for solid: Dictionary in source["solids"]:
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2], "max_z": solid["max"][2],
			"bottom": solid["min"][1], "top": solid["max"][1]})
		surfaces.append(solid.get("surface", "concrete"))
	return {"type": "map_info", "geometry_version": 2, "map_id": source["map_id"], "map_name": source["name"],
		"half_extent": source["half_extent"], "solids": solids, "m06": source["m06"],
		"presentation": {"ground": source.get("ground", "concrete"), "solids": surfaces, "decorations": []}}

static func _reserved(colour: Color) -> bool:
	var black_red: bool = colour.v <= 0.3
	var off_white: bool = colour.v >= 0.8 and colour.s <= 0.15
	# Blue paint is a personal colour; a teal-cyan field would read as the
	# Inheritance's working light even unlit.
	var cyan: bool = colour.s > 0.25 and colour.h * 360.0 >= 165.0 and colour.h * 360.0 <= 200.0
	return black_red or off_white or cyan

func _run() -> void:
	var info: Dictionary = authored_info()
	_expect(M06Dressing.authored(info), "the authored port layout is recognized")
	var other: Dictionary = info.duplicate(true)
	other["map_id"] = 1008
	_expect(not M06Dressing.authored(other), "another lunar mission never receives the port dressing")
	var moved: Dictionary = info.duplicate(true)
	for solid: Dictionary in moved["solids"]:
		if is_equal_approx(float(solid["min_x"]), -15.0) and is_equal_approx(float(solid["min_z"]), 30.0):
			solid["max_x"] = -14.5
	_expect(not M06Dressing.authored(moved), "a reused id with a moved kiosk gets no floating props")
	_expect(not M06Dressing.authored({"map_id": 1006}), "a malformed map is refused")
	for colour: Color in M06Dressing.FREIGHT + M06Dressing.PERSONAL:
		_expect(not _reserved(colour), "freight and personal paint avoid the reserved faction reads: " + colour.to_html(false))
	var port: M06Dressing = M06Dressing.new()
	root.add_child(port)
	port.configure_map(moved)
	_expect(port.get_child_count() == 0 and not port.active(), "unrecognized layouts stay bare")
	port.configure_map(info)
	for room: String in ROOMS:
		_expect(room in port.rooms and port.has_node(room), "room dressed: " + room)
	_expect(port.lamps >= 30, "practical light shapes every room, found %d" % port.lamps)
	var warm: int = 0
	for light: Node in port.find_children("*", "Light3D", true, false):
		var lamp: Light3D = light as Light3D
		var colour: Color = lamp.light_color
		var outside: bool = lamp.name.begins_with("ApronSun")
		_expect(not lamp.shadow_enabled, "presenter lights never add shadow maps: " + lamp.name)
		_expect(not (colour.r > 0.7 and colour.g < 0.3 and colour.b < 0.3), "no red light outside Union attack tells: " + lamp.name)
		_expect(not (colour.b > colour.r + 0.15 and colour.g > colour.r + 0.1), "no Inheritance cyan light: " + lamp.name)
		if lamp is OmniLight3D and not outside:
			_expect((lamp as OmniLight3D).omni_range <= 9.5, "presenter lamps stay local: " + lamp.name)
		if outside:
			_expect(absf(lamp.position.x) > 48.0, "the apron sun stands outside the playable square: " + lamp.name)
		if lamp is SpotLight3D:
			_expect((lamp as SpotLight3D).spot_range <= 7.0 and (lamp as SpotLight3D).spot_angle <= 45.0, "fixture pools stay bounded: " + lamp.name)
		if colour.r > colour.b + 0.2:
			warm += 1
	_expect(warm >= 10, "warm lamps mark where people work against the cold high bays, found %d" % warm)
	_expect(port.find_children("FixturePool*", "SpotLight3D", true, false).size() >= 15, "high-bay and desk pools shape the halls")
	for node: Node in port.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	_expect(port.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing never adds a body; the server owns every solid")
	_expect(port.find_children("*", "WorldSign", true, false).is_empty() and port.find_children("*", "Label3D", true, false).is_empty(), "the dressing tells its story without words")
	_expect(port.find_children("*WelcomeLoop*", "MeshInstance3D", true, false).size() == 4, "the Chancellor's welcome loop plays on both faces of two screens")
	var loop: Image = M06Dressing.welcome_screen().get_image()
	_expect(loop.get_size() == Vector2i(64, 40), "the welcome loop is a small pixel picture, not a sign")
	for room: String in port.rooms:
		var props: Node = port.get_node(room).get_node_or_null("Props")
		_expect(props != null and props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
	port.configure_map(info)
	_expect(port.rooms.size() == ROOMS.size() and port.get_child_count() == ROOMS.size(), "a repeated MapInfo keeps one set of rooms")
	port.configure_map(other)
	_expect(not port.active(), "another map clears the port dressing")
	await process_frame
	_expect(port.get_child_count() == 0, "cleared rooms leave the tree")
	port.queue_free()
	await _check_restyle(info)
	if failures == 0:
		print("test_m06_dressing: PASS authored guard, eight dressed rooms, local lamps without red or cyan, no words or bodies, surfaces by use and a tiled floor")
	quit(0 if failures == 0 else 1)

func _check_restyle(info: Dictionary) -> void:
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	_expect(cover._solid_views.size() == info["solids"].size(), "every solid keeps its view")
	var roles: Dictionary = {}
	for index: int in range(info["solids"].size()):
		var view: MeshInstance3D = cover._solid_views[index]
		var material: Material = view.material_override
		if info["presentation"]["solids"][index] == "inspection_glass":
			_expect(material is StandardMaterial3D and (material as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "pressure glass stays transparent")
			var tint: Color = (material as StandardMaterial3D).albedo_color
			_expect(absf(tint.b - tint.r) < 0.05, "pressure glass carries no blue space tint")
			continue
		_expect(material is ShaderMaterial, "solid %d is restyled" % index)
		if material is ShaderMaterial:
			_expect(float((material as ShaderMaterial).get_shader_parameter("trim_glow")) == 0.0, "no solid's paint emits light: solid %d" % index)
		var box: AABB = M06Dressing._bounds(info["solids"][index])
		roles[M06Dressing.role_for(box, str(info["presentation"]["solids"][index]))] = true
	for role: String in ["shell", "ceiling", "union", "steel", "gallery", "cargo", "desk", "panel", "furnish"]:
		_expect(roles.has(role), "the port uses its %s surface" % role)
	_expect(not (cover.get_node("MapFloor") as Node3D).visible, "the single floor plane gives way to tiles")
	var tiles: Array[Node] = cover.find_children("*PortFloor*", "MeshInstance3D", true, false)
	_expect(tiles.size() >= 60, "the interior floor is tiled, found %d" % tiles.size())
	for tile: Node in tiles:
		var size: Vector2 = ((tile as MeshInstance3D).mesh as PlaneMesh).size
		_expect(size.x <= M06Dressing.FLOOR_TILE + 0.01 and size.y <= M06Dressing.FLOOR_TILE + 0.01, "floor tiles stay small enough to carry their own lights")
	_expect(cover.find_children("*LunarApron*", "MeshInstance3D", true, false).size() == 7, "the lunar apron surrounds the shell")
	_expect(cover.find_children("*FreightContainer*", "MeshInstance3D", true, false).size() >= 10, "long freight lanes read as separate containers")
	_expect(cover.find_children("*", "CollisionObject3D", true, false).is_empty(), "restyling adds no bodies")
	var bare: Dictionary = info.duplicate(true)
	bare["map_id"] = 1008
	cover.apply_map_info(bare)
	_expect((cover.get_node("MapFloor") as Node3D).visible and cover.find_children("*PortFloor*", "MeshInstance3D", true, false).is_empty(), "another map keeps its plain floor")
	cover.queue_free()
	await process_frame
