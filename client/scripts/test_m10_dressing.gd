extends SceneTree

## Common Carrier golden-slice dressing: authored-layout guard keyed on hull,
## trunk walls and deck plates that never move; a re-sent map keeping one set
## of rooms; every deck dressed; local warm lamps with no red or cyan light;
## no words and no collision of its own; the outside kept outside the hull;
## solid views restyled by use with no glowing paint, nothing in the Union's
## black and red, and bone trunk walls that never read as matte off-white;
## both cargo stacks drawn as crates a few centimetres proud of their
## solids, whose own views stay as the physical fallback.
const ROOMS: Array[String] = ["ForwardHold", "Service", "AftHold", "WestTrunk", "EastTrunk", "Shaft",
	"CrewFore", "CrewAft", "Command", "AftGallery", "Outside"]
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m10_dressing: " + message)

static func authored_info() -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m10_common_carrier.json"))
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
	# The wire shape of the mission facts: arrivals as actions, and the
	# departure panel as a presentation decoration named by index.
	var authored: Dictionary = source["m10"]
	var panel: Dictionary = authored["departure"]["panel"].duplicate(true)
	panel["solid"] = index_of[panel["solid"]]
	decorations.append(panel)
	var objectives: Array = []
	for objective: Dictionary in authored["objectives"]:
		objectives.append({"id": objective["id"], "action": {"kind": "arrival", "feet": objective["approach"], "region": objective["arrival"]}})
	var m10: Dictionary = {"objectives": objectives, "departure": {"decoration": decorations.size() - 1, "approach": authored["departure"]["approach"]},
		"boarding": authored["departure"]["boarding"], "pilot": authored["pilot"], "companion_start": authored["companion_start"], "passengers": authored["passengers"]}
	return {"type": "map_info", "geometry_version": 2, "map_id": source["map_id"], "map_name": source["name"],
		"half_extent": source["half_extent"], "solids": solids, "m10": m10,
		"presentation": {"ground": source.get("ground", "concrete"), "solids": surfaces, "decorations": decorations}}

static func _reserved(colour: Color) -> bool:
	var black_red: bool = colour.v <= 0.3
	var off_white: bool = colour.v >= 0.8 and colour.s <= 0.15
	var cyan: bool = colour.s > 0.25 and colour.h * 360.0 >= 165.0 and colour.h * 360.0 <= 200.0
	return black_red or off_white or cyan

func _run() -> void:
	var info: Dictionary = authored_info()
	_expect(M10Dressing.ship_layout(info), "the authored ship layout is recognized")
	var other: Dictionary = info.duplicate(true)
	other["map_id"] = 1011
	_expect(not M10Dressing.ship_layout(other), "another ship mission never receives the carrier dressing")
	var moved: Dictionary = info.duplicate(true)
	for solid: Dictionary in moved["solids"]:
		if is_equal_approx(float(solid["min_x"]), -3.55) and is_equal_approx(float(solid["min_z"]), -13.0):
			solid["max_z"] = -4.0
	_expect(not M10Dressing.ship_layout(moved), "a reused id with a moved trunk wall gets no floating props")
	_expect(not M10Dressing.ship_layout({"map_id": 1010}), "a malformed map is refused")
	var bare: Dictionary = info.duplicate(true)
	bare.erase("m10")
	_expect(not M10Dressing.ship_layout(bare), "a map without its mission facts stays bare")
	for colour: Color in M10Dressing.KIT + [M10Dressing.BONE, M10Dressing.GUNMETAL]:
		_expect(not _reserved(colour), "personal, bone and gunmetal paint avoid the reserved faction reads: " + colour.to_html(false))
	_expect(M10Dressing.BONE.s >= 0.18 and M10Dressing.BONE.v < 0.8 and M10Dressing.BONE.h * 360.0 >= 25.0 and M10Dressing.BONE.h * 360.0 <= 50.0, "bone pressure paint is warm, not Inheritance off-white")
	var ship: M10Dressing = M10Dressing.new()
	root.add_child(ship)
	ship.configure_map(moved)
	_expect(ship.get_child_count() == 0 and not ship.active(), "unrecognized layouts stay bare")
	ship.configure_map(info)
	for room: String in ROOMS:
		_expect(room in ship.rooms and ship.has_node(room), "room dressed: " + room)
	_expect(ship.lamps >= 30, "practical light shapes every deck, found %d" % ship.lamps)
	_expect(ship.find_children("ShaftFlood", "SpotLight3D", true, false).size() == 1, "the freight shaft has its flood")
	for light: Node in ship.find_children("*", "Light3D", true, false):
		var lamp: Light3D = light as Light3D
		var colour: Color = lamp.light_color
		_expect(not lamp.shadow_enabled, "presenter lights never add shadow maps: " + lamp.name)
		_expect(not (colour.r > 0.7 and colour.g < 0.3 and colour.b < 0.3), "no red light outside Union attack tells: " + lamp.name)
		_expect(not (colour.b > colour.r + 0.15 and colour.g > colour.r + 0.1), "no Inheritance cyan light: " + lamp.name)
		_expect(colour.r >= colour.b, "ship light is warm: " + lamp.name)
		_expect(M10Dressing.region(lamp.global_position) != "Outside", "every lamp is aboard: " + lamp.name)
		if lamp is OmniLight3D:
			_expect((lamp as OmniLight3D).omni_range <= 9.5, "presenter lamps stay local: " + lamp.name)
		if lamp is SpotLight3D:
			_expect((lamp as SpotLight3D).spot_range <= 14.0 and (lamp as SpotLight3D).spot_angle <= 45.0, "floods stay bounded: " + lamp.name)
	for node: Node in ship.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	_expect(ship.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing never adds a body; the server owns every solid")
	_expect(ship.find_children("*", "Label3D", true, false).is_empty(), "the dressing tells its story without words")
	for room: String in ship.rooms:
		var props: Node = ship.get_node(room).get_node_or_null("Props")
		_expect(props != null and props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
	var outside: Node3D = ship.get_node("Outside") as Node3D
	var mesh: MeshInstance3D = outside.get_node("Props").get_child(0) as MeshInstance3D
	var bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
	_expect(bounds.end.z < -18.0, "stars and the tender lie beyond the window, not inside the hull")
	var crew: Node3D = ship.get_node("CrewAft") as Node3D
	_expect(crew.find_children("*", "OmniLight3D", true, false).size() >= 3, "the crew deck keeps its own warm lights")
	# A re-sent MapInfo for the same layout keeps one set of rooms.
	ship.configure_map(info.duplicate(true))
	_expect(ship.rooms.size() == ROOMS.size() and ship.get_child_count() == ROOMS.size(), "a re-sent map keeps one set of rooms")
	ship.configure_map(other)
	_expect(not ship.active(), "another map clears the ship dressing")
	await process_frame
	_expect(ship.get_child_count() == 0, "cleared rooms leave the tree")
	ship.queue_free()
	await _check_ship_node(info)
	await _check_restyle(info)
	if failures == 0:
		print("test_m10_dressing: PASS static-hull guard, re-sent map, eleven dressed regions, warm lamps without red or cyan, no words or bodies, outside beyond the glass, surfaces by use and lashed crates on their solids")
	quit(0 if failures == 0 else 1)

## The ship presenter keeps one dressing across a re-sent map, even when a
## solid the guard does not key on changes; it creates nothing off-map or
## for a refused map, and drops the dressing for a different map.
func _check_ship_node(info: Dictionary) -> void:
	var presenter: M10Ship = M10Ship.new()
	root.add_child(presenter)
	presenter.configure_map({"type": "map_info", "map_id": 1, "map_name": "Scrap", "solids": []})
	_expect(presenter.dressing == null and presenter.get_child_count() == 0, "an ordinary map creates no ship dressing")
	var refused: Dictionary = info.duplicate(true)
	refused["m10"].erase("departure")
	_expect(not MissionState.map_error(refused).is_empty(), "the refused fixture really is refused")
	presenter.configure_map(refused)
	_expect(presenter.dressing == null and presenter.get_child_count() == 0, "a refused ship map gets no dressing")
	_expect(MissionState.map_error(info).is_empty(), "the authored fixture passes the mission boundary")
	presenter.configure_map(info)
	_expect(presenter.dressing != null and presenter.dressing.active(), "the ship presenter dresses its own map")
	var first: Node = presenter.dressing.get_node_or_null("CrewAft")
	presenter.configure_map(info.duplicate(true))
	_expect(presenter.dressing.get_node_or_null("CrewAft") == first and first != null, "an identical re-sent map never rebuilds the dressing")
	var nudged: Dictionary = info.duplicate(true)
	var moved_any: bool = false
	for solid: Dictionary in nudged["solids"]:
		if is_equal_approx(float(solid["min_x"]), -4.8) and is_equal_approx(float(solid["min_z"]), 9.3):
			solid["top"] = 3.6
			moved_any = true
	_expect(moved_any, "the coolant bank exists to change")
	_expect(M10Dressing.ship_layout(nudged), "a solid off the guard leaves the layout recognized")
	presenter.configure_map(nudged)
	var dressings: Array[Node] = presenter.find_children("ShipDressing*", "", false, false)
	_expect(dressings.size() == 1 and presenter.dressing.get_node_or_null("CrewAft") == first, "a re-send with a changed non-key solid keeps one dressing")
	_expect(presenter.dressing.rooms.size() == ROOMS.size(), "the kept dressing is not duplicated")
	var other: Dictionary = info.duplicate(true)
	for solid: Dictionary in other["solids"]:
		if is_equal_approx(float(solid["min_x"]), -3.55) and is_equal_approx(float(solid["min_z"]), -13.0):
			solid["max_z"] = -4.0
	presenter.configure_map(other)
	_expect(presenter.dressing == null and presenter.get_child_count() == 0, "a different layout removes the dressing")
	presenter.configure_map(info)
	presenter.clear_map()
	_expect(presenter.dressing == null and presenter.get_child_count() == 0, "leaving the map removes the dressing")
	presenter.queue_free()
	await process_frame

func _check_restyle(info: Dictionary) -> void:
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	_expect(cover._solid_views.size() == info["solids"].size(), "every solid keeps its view")
	var roles: Dictionary = {}
	var lashed: int = 0
	for index: int in range(info["solids"].size()):
		var view: MeshInstance3D = cover._solid_views[index]
		var material: Material = view.material_override
		var box: AABB = M10Dressing._bounds(info["solids"][index])
		var surface: String = str(info["presentation"]["solids"][index])
		var role: String = M10Dressing.ship_role(box, surface)
		roles[role] = true
		if role == "glass":
			_expect(material is StandardMaterial3D and (material as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "the window stays transparent")
			continue
		if role == "cargo":
			_expect(view.visible, "a cargo solid keeps its physical view under the crates")
			if (material as ShaderMaterial) == M10Dressing.ship_surface("cargo_gap"):
				lashed += 1
				_expect(view.scale.x < 1.0 and view.scale.z < 1.0, "the lashed solid's view shrinks inside its crates")
		_expect(material is ShaderMaterial, "solid %d is restyled" % index)
		if material is ShaderMaterial:
			var shader: ShaderMaterial = material
			_expect(float(shader.get_shader_parameter("trim_glow")) == 0.0, "no solid's paint emits light: solid %d" % index)
			if surface == "service_steel":
				_expect(shader.get_shader_parameter("tile_enabled") == true, "working steel keeps its reviewed tile: solid %d" % index)
			var base: Color = shader.get_shader_parameter("surface_color")
			var accent: Color = shader.get_shader_parameter("accent_color")
			var union_livery: bool = base.v <= 0.3 and accent.s > 0.5 and (accent.h < 0.06 or accent.h > 0.94)
			_expect(not union_livery, "no solid wears the Union's black and red: solid %d (%s)" % [index, role])
			_expect(not (base.v >= 0.8 and base.s <= 0.15), "no solid reads as matte off-white: solid %d (%s)" % [index, role])
	for role: String in ["hull", "roof", "bone", "cabin", "steel", "floor_low", "deck_crew", "deck_command", "tread",
		"power", "coolant", "rail", "galley", "console", "cargo", "glass"]:
		_expect(roles.has(role), "the ship uses its %s surface" % role)
	_expect(lashed == 2, "both cargo stacks are drawn as lashed crates, found %d" % lashed)
	var crates: Array[Node] = _crates(cover)
	_expect(crates.size() == 24, "two stacks of twelve crates, found %d" % crates.size())
	for crate: Node in crates:
		var box: AABB = crate.get_meta("box")
		var inside: bool = false
		for solid: Variant in info["solids"]:
			var host: AABB = M10Dressing._bounds(solid)
			if M10Dressing.ship_role(host, "enamel") == "cargo" and host.grow(M10Dressing.CRATE_PROUD + 0.001).encloses(box):
				inside = true
		_expect(inside, "every crate stays within a few centimetres of its cargo solid")
	_expect(cover.find_children("*", "CollisionObject3D", true, false).is_empty(), "restyling adds no bodies")
	var plain: Dictionary = info.duplicate(true)
	plain["map_id"] = 1011
	cover.apply_map_info(plain)
	await process_frame
	_expect(_crates(cover).is_empty(), "another map gets no carrier crates")
	cover.queue_free()
	await process_frame

static func _crates(cover: Node) -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in cover.get_tree().get_nodes_in_group(CampaignProps.GROUP):
		if cover.is_ancestor_of(node) and node.get_meta("prop", "") == "supply_crate" and not node.is_queued_for_deletion():
			found.append(node)
	return found
