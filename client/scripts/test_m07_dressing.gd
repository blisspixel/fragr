extends SceneTree

## Declared Goods golden-slice dressing: authored-layout guard keyed on walls
## that never move, a re-sent map keeping one set of rooms, every region
## dressed, local lamps and floods with no red or cyan light, no words and no
## collision of its own; solid views restyled by use with no glowing paint and
## nothing in the Union's black-and-red livery, house and goods paint clear of
## the reserved faction reads, a lit stage behind every rim marksman, and a
## paved town floor in tiles that keep their own lights.
const ROOMS: Array[String] = ["Tunnel", "RingWest", "RingEast", "Plaza", "SideStreet", "Square", "Post",
	"CutSouth", "CutNorth", "Rim", "Depot", "Crater"]
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m07_dressing: " + message)

static func authored_info() -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m07_declared_goods.json"))
	if not source is Dictionary:
		return {}
	var solids: Array = []
	var surfaces: Array = []
	var index_of: Dictionary = {}
	for solid: Dictionary in source["solids"]:
		index_of[solid["id"]] = solids.size()
		solids.append({"min_x": solid["min"][0], "max_x": solid["max"][0], "min_z": solid["min"][2], "max_z": solid["max"][2],
			"bottom": solid["min"][1], "top": solid["max"][1]})
		surfaces.append(solid.get("surface", "concrete"))
	var decorations: Array = []
	for detail: Dictionary in source["decorations"]:
		var placed: Dictionary = detail.duplicate(true)
		placed["solid"] = index_of[detail["solid"]]
		decorations.append(placed)
	return {"type": "map_info", "geometry_version": 2, "map_id": source["map_id"], "map_name": source["name"],
		"half_extent": source["half_extent"], "solids": solids, "m07": source["m07"],
		"presentation": {"ground": source.get("ground", "concrete"), "solids": surfaces, "decorations": decorations}}

static func _reserved(colour: Color) -> bool:
	var black_red: bool = colour.v <= 0.3
	var off_white: bool = colour.v >= 0.8 and colour.s <= 0.15
	var cyan: bool = colour.s > 0.25 and colour.h * 360.0 >= 165.0 and colour.h * 360.0 <= 200.0
	return black_red or off_white or cyan

func _run() -> void:
	var info: Dictionary = authored_info()
	_expect(M07Dressing.town_layout(info), "the authored town layout is recognized")
	_expect(not M06Dressing.authored(info), "the town never receives the port dressing")
	var other: Dictionary = info.duplicate(true)
	other["map_id"] = 1006
	_expect(not M07Dressing.town_layout(other), "another lunar mission never receives the town dressing")
	var moved: Dictionary = info.duplicate(true)
	for solid: Dictionary in moved["solids"]:
		if is_equal_approx(float(solid["min_x"]), -6.0) and is_equal_approx(float(solid["min_z"]), -31.0):
			solid["max_x"] = 7.0
	_expect(not M07Dressing.town_layout(moved), "a reused id with a moved vault gets no floating props")
	_expect(not M07Dressing.town_layout({"map_id": 1007}), "a malformed map is refused")
	for colour: Color in M07Dressing.HOUSE + M07Dressing.HOMES:
		_expect(not _reserved(colour), "house and household paint avoid the reserved faction reads: " + colour.to_html(false))
	var town: M07Dressing = M07Dressing.new()
	root.add_child(town)
	town.configure_map(moved)
	_expect(town.get_child_count() == 0 and not town.active(), "unrecognized layouts stay bare")
	town.configure_map(info)
	for room: String in ROOMS:
		_expect(room in town.rooms and town.has_node(room), "room dressed: " + room)
	_expect(town.lamps >= 24, "practical light and curfew floods shape the town, found %d" % town.lamps)
	_expect(town.find_children("CurfewFlood*", "SpotLight3D", true, false).size() >= 12, "the Union's cold floods light the streets")
	_expect(town.find_children("StageLight*", "SpotLight3D", true, false).size() == M07Dressing.RIM_STAGES.size(), "every rim marksman has a lit stage")
	for light: Node in town.find_children("*", "Light3D", true, false):
		var lamp: Light3D = light as Light3D
		var colour: Color = lamp.light_color
		_expect(not lamp.shadow_enabled, "presenter lights never add shadow maps: " + lamp.name)
		_expect(not (colour.r > 0.7 and colour.g < 0.3 and colour.b < 0.3), "no red light outside Union attack tells: " + lamp.name)
		_expect(not (colour.b > colour.r + 0.15 and colour.g > colour.r + 0.1), "no Inheritance cyan light: " + lamp.name)
		if lamp is OmniLight3D:
			_expect((lamp as OmniLight3D).omni_range <= 9.5, "presenter lamps stay local: " + lamp.name)
		if lamp is SpotLight3D:
			_expect((lamp as SpotLight3D).spot_range <= 14.0 and (lamp as SpotLight3D).spot_angle <= 45.0, "floods and pools stay bounded: " + lamp.name)
	for node: Node in town.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	_expect(town.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing never adds a body; the server owns every solid")
	_expect(town.find_children("*", "Label3D", true, false).is_empty(), "the dressing tells its story without words")
	for room: String in town.rooms:
		var props: Node = town.get_node(room).get_node_or_null("Props")
		_expect(props != null and props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
	# A re-sent MapInfo for the same layout keeps one set of rooms.
	town.configure_map(info.duplicate(true))
	_expect(town.rooms.size() == ROOMS.size() and town.get_child_count() == ROOMS.size(), "a re-sent map keeps one set of rooms")
	town.configure_map(other)
	_expect(not town.active(), "another map clears the town dressing")
	await process_frame
	_expect(town.get_child_count() == 0, "cleared rooms leave the tree")
	town.queue_free()
	await _check_restyle(info)
	if failures == 0:
		print("test_m07_dressing: PASS static-wall guard, re-sent map, twelve dressed regions, floods and stages without red or cyan, no words or bodies, surfaces by use and a paved floor")
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
		var box: AABB = M07Dressing._bounds(info["solids"][index])
		var role: String = M07Dressing.town_role(box, str(info["presentation"]["solids"][index]))
		roles[role] = true
		if role == "glass":
			_expect(material is StandardMaterial3D and (material as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "the window stays transparent")
			continue
		_expect(material is ShaderMaterial, "solid %d is restyled" % index)
		if material is ShaderMaterial:
			var shader: ShaderMaterial = material
			_expect(float(shader.get_shader_parameter("trim_glow")) == 0.0, "no solid's paint emits light: solid %d" % index)
			var base: Color = shader.get_shader_parameter("surface_color")
			var accent: Color = shader.get_shader_parameter("accent_color")
			var union_livery: bool = base.v <= 0.3 and accent.s > 0.5 and (accent.h < 0.06 or accent.h > 0.94)
			_expect(not union_livery, "no solid wears the Union's black and red: solid %d (%s)" % [index, role])
	for role: String in ["house", "porch", "ceiling", "car", "stall", "goods", "kiosk", "vault", "barrier", "post", "stone", "steel",
		"regolith", "berm", "crater", "rim", "rim_back", "shield", "stair", "marker", "depot", "panel", "glass"]:
		_expect(roles.has(role), "the town uses its %s surface" % role)
	_expect(M07Dressing.town_role(AABB(Vector3(4, 4, 22), Vector3(12, 3.8, 2)), "concrete") == "berm", "a cut berm is compacted regolith")
	_expect(M07Dressing.town_role(AABB(Vector3(-14, 0, -8), Vector3(6, 7, 0.5)), "service_steel") == "post", "the curfew post is issued steel")
	_expect(not (cover.get_node("MapFloor") as Node3D).visible, "the single floor plane gives way to paving")
	var tiles: Array[Node] = cover.find_children("*TownPaving*", "MeshInstance3D", true, false)
	_expect(tiles.size() >= 100, "the town floor is paved in tiles, found %d" % tiles.size())
	for tile: Node in tiles:
		var size: Vector2 = ((tile as MeshInstance3D).mesh as PlaneMesh).size
		_expect(size.x <= M06Dressing.FLOOR_TILE + 0.01 and size.y <= M06Dressing.FLOOR_TILE + 0.01, "paving tiles stay small enough to carry their own lights")
	_expect(cover.find_children("*LunarGround*", "MeshInstance3D", true, false).size() == 4, "the lunar ground surrounds the town")
	_expect(cover.find_children("*", "CollisionObject3D", true, false).is_empty(), "restyling adds no bodies")
	var bare: Dictionary = info.duplicate(true)
	bare["map_id"] = 1008
	cover.apply_map_info(bare)
	_expect((cover.get_node("MapFloor") as Node3D).visible and cover.find_children("*TownPaving*", "MeshInstance3D", true, false).is_empty(), "another map keeps its plain floor")
	cover.queue_free()
	await process_frame

