extends SceneTree

## Custodian of Record golden-slice dressing: an authored-layout guard keyed
## on walls that never move, so the lifted seal and the fallen machine keep
## one dressed archive; every region dressed; warm pendants and cold issued
## pools with no red or cyan light; the maintenance screen's line; no bodies;
## solid views restyled by use with no glowing paint and nothing in the
## Union's black-and-red livery; personal and institutional paint clear of
## the reserved faction reads, and a floor in tiles that keep their own lights.
const ROOMS: Array[String] = ["Checkpoint", "HallSouth", "HallNorth", "Shaft", "LowerSouth", "LowerNorth", "LowerWest",
	"LowerEast", "UpperSouth", "Ring", "UpperEast", "Bridge", "WestTower", "EastTower", "Freight"]
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_m08_dressing: " + message)

static func authored_info() -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../server/maps/m08_custodian_of_record.json"))
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
		"half_extent": source["half_extent"], "solids": solids, "m08": {"index_of": index_of},
		"presentation": {"ground": source.get("ground", "concrete"), "solids": surfaces, "decorations": decorations}}

## The server's re-sent stages: the seal lifted into the lintel, then the
## machine and its four nodes dropped to the shaft floor.
static func staged(info: Dictionary, fallen: bool) -> Dictionary:
	var result: Dictionary = info.duplicate(true)
	var index_of: Dictionary = info["m08"]["index_of"]
	var seal: Dictionary = result["solids"][index_of["upper_seal"]]
	seal["bottom"] = 8.95
	if fallen:
		var machine: Dictionary = result["solids"][index_of["custody_machine"]]
		machine.merge({"min_x": -2.5, "max_x": 2.5, "min_z": -2.5, "max_z": 2.5, "bottom": 0.0, "top": 1.5}, true)
		for node: String in ["node_north_west", "node_north_east", "node_south_east", "node_south_west"]:
			var solid: Dictionary = result["solids"][index_of[node]]
			solid["bottom"] = 0.0
			solid["top"] = 0.5
	return result

static func _reserved(colour: Color) -> bool:
	var black_red: bool = colour.v <= 0.3
	var off_white: bool = colour.v >= 0.8 and colour.s <= 0.15
	var cyan: bool = colour.s > 0.25 and colour.h * 360.0 >= 165.0 and colour.h * 360.0 <= 200.0
	return black_red or off_white or cyan

func _run() -> void:
	var info: Dictionary = authored_info()
	_expect(M08Dressing.archive_layout(info), "the authored archive layout is recognized")
	_expect(not M07Dressing.town_layout(info) and not M06Dressing.authored(info), "the archive never receives the port or town dressing")
	var other: Dictionary = info.duplicate(true)
	other["map_id"] = 1007
	_expect(not M08Dressing.archive_layout(other), "another lunar mission never receives the archive dressing")
	var moved: Dictionary = info.duplicate(true)
	moved["solids"][info["m08"]["index_of"]["ring_south_west"]]["max_x"] = -5.0
	_expect(not M08Dressing.archive_layout(moved), "a reused id with a moved ring wall gets no floating props")
	_expect(not M08Dressing.archive_layout({"map_id": 1008}), "a malformed map is refused")
	var opened: Dictionary = staged(info, false)
	var fallen: Dictionary = staged(info, true)
	_expect(M08Dressing.archive_layout(opened) and M08Dressing.archive_layout(fallen), "the lifted seal and the fallen machine keep the layout")
	for colour: Color in M08Dressing.BELONGINGS + M08Dressing.BOXES + M08Dressing.FACES + M08Archive.CAPTIVE_TINTS + \
		[M08Dressing.ENAMEL, M08Dressing.DADO, M08Dressing.BRASS, M08Dressing.CABINET, M08Dressing.DRAWER, M08Dressing.LAMP_SHADE]:
		_expect(not _reserved(colour), "archive and personal paint avoid the reserved faction reads: " + colour.to_html(false))
	var archive: M08Dressing = M08Dressing.new()
	root.add_child(archive)
	archive.configure_map(moved)
	_expect(archive.get_child_count() == 0 and not archive.active(), "unrecognized layouts stay bare")
	archive.configure_map(info)
	for room: String in ROOMS:
		_expect(room in archive.rooms and archive.has_node(room), "room dressed: " + room)
	_expect(archive.lamps >= 40, "pendants and pools shape the archive, found %d" % archive.lamps)
	var pendants: int = 0
	for light: Node in archive.find_children("*", "OmniLight3D", true, false):
		pendants += int((light as OmniLight3D).light_color == M08Dressing.PENDANT)
	_expect(pendants >= 25, "green-shaded pendants light where people sit, found %d" % pendants)
	for light: Node in archive.find_children("*", "Light3D", true, false):
		var lamp: Light3D = light as Light3D
		var colour: Color = lamp.light_color
		_expect(not lamp.shadow_enabled, "presenter lights never add shadow maps: " + lamp.name)
		_expect(not (colour.r > 0.7 and colour.g < 0.3 and colour.b < 0.3), "no red light outside Union attack tells: " + lamp.name)
		_expect(not (colour.b > colour.r + 0.15 and colour.g > colour.r + 0.1), "no Inheritance cyan light: " + lamp.name)
		if lamp is OmniLight3D:
			_expect((lamp as OmniLight3D).omni_range <= 9.5, "presenter lamps stay local: " + lamp.name)
		if lamp is SpotLight3D:
			_expect((lamp as SpotLight3D).spot_range <= 14.0 and (lamp as SpotLight3D).spot_angle <= 45.0, "pools stay bounded: " + lamp.name)
	for node: Node in archive.find_children("*", "VisualInstance3D", true, false):
		_expect(((node as VisualInstance3D).layers & ArenaSky.ACTOR_LAYERS) == 0, "dressing stays off the actor fill layer: " + node.name)
	_expect(archive.find_children("*", "CollisionObject3D", true, false).is_empty(), "dressing never adds a body; the server owns every solid")
	var words: Array[Node] = archive.find_children("*", "Label3D", true, false)
	_expect(words.size() == 1 and words[0] == archive.noise_screen, "the maintenance screen is the dressing's only line")
	_expect(is_instance_valid(archive.noise_screen) and archive.noise_screen.message_key == "WORLD_M08_AUTHORIZED_NOISE" \
		and archive.noise_screen.text == tr("WORLD_M08_AUTHORIZED_NOISE"), "the screen reads the authorized-noise line with sound muted")
	for room: String in archive.rooms:
		var props: Node = archive.get_node(room).get_node_or_null("Props")
		_expect(props != null and props.get_child_count() == 1, "each room's static props merge into one mesh: " + room)
	# Re-sent MapInfo for the same layout, including the seal and the machine
	# stages, keeps one set of rooms and rebuilds nothing.
	var first: Node = archive.get_node("HallSouth")
	for resent: Dictionary in [info.duplicate(true), opened, fallen]:
		archive.configure_map(resent)
		_expect(archive.rooms.size() == ROOMS.size() and archive.get_child_count() == ROOMS.size(), "a re-sent map keeps one set of rooms")
	_expect(archive.get_node("HallSouth") == first, "the fallen machine never wipes the dressing")
	archive.configure_map(other)
	_expect(not archive.active(), "another map clears the archive dressing")
	await process_frame
	_expect(archive.get_child_count() == 0, "cleared rooms leave the tree")
	archive.queue_free()
	await _check_restyle(info)
	await _check_restyle(fallen)
	if failures == 0:
		print("test_m08_dressing: PASS static-wall guard through seal and fall, re-sent map, fifteen dressed regions, warm pendants and cold pools without red or cyan, one screen line and no bodies, surfaces by use and a tiled floor")
	quit(0 if failures == 0 else 1)

func _check_restyle(info: Dictionary) -> void:
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	_expect(cover._solid_views.size() == info["solids"].size(), "every solid keeps its view")
	var roles: Dictionary = {}
	var index_of: Dictionary = info["m08"]["index_of"]
	for index: int in range(info["solids"].size()):
		var view: MeshInstance3D = cover._solid_views[index]
		var material: Material = view.material_override
		var box: AABB = M08Dressing._bounds(info["solids"][index])
		var role: String = M08Dressing.archive_role(box, str(info["presentation"]["solids"][index]))
		roles[role] = true
		_expect(material is ShaderMaterial, "solid %d is restyled" % index)
		if material is ShaderMaterial:
			var shader: ShaderMaterial = material
			_expect(float(shader.get_shader_parameter("trim_glow")) == 0.0, "no solid's paint emits light: solid %d (%s)" % [index, role])
			var base: Color = shader.get_shader_parameter("surface_color")
			var accent: Color = shader.get_shader_parameter("accent_color")
			var warning: Color = shader.get_shader_parameter("warning_color")
			for paint: Color in [accent, warning]:
				var red: bool = paint.s > 0.5 and (paint.h < 0.06 or paint.h > 0.94)
				_expect(not (base.v <= 0.3 and red), "no solid wears the Union's black and red: solid %d (%s)" % [index, role])
				_expect(not red, "no red pinline on the archive's surfaces: solid %d (%s)" % [index, role])
			_expect(not (base.v >= 0.8 and base.s <= 0.15), "no solid reads as Inheritance off-white: solid %d (%s)" % [index, role])
	for role: String in ["archive", "checkpoint", "lane_wall", "ceiling", "slab", "desk", "rail", "screen", "stair", "cage",
		"platform", "bridge", "machine", "pipe", "seal", "cabinet", "panel", "car", "crate"]:
		_expect(roles.has(role), "the archive uses its %s surface" % role)
	for pair: Array in [["custody_machine", "machine"], ["node_south_west", "machine"], ["upper_seal", "seal"], ["cold_cabinet", "cabinet"],
		["cooling_pipe_middle", "pipe"], ["machinery_bridge", "bridge"], ["hall_screen_west", "screen"], ["freight_car", "car"],
		["west_stair_3", "stair"], ["registry_desk", "desk"], ["upper_slab_south", "slab"], ["archive_roof", "ceiling"]]:
		var solid: int = index_of[pair[0]]
		_expect(M08Dressing.archive_role(M08Dressing._bounds(info["solids"][solid]), str(info["presentation"]["solids"][solid])) == pair[1],
			"%s is restyled as %s" % pair)
	_expect(not (cover.get_node("MapFloor") as Node3D).visible, "the single floor plane gives way to tiles")
	var tiles: Array[Node] = cover.find_children("*ArchiveFloor*", "MeshInstance3D", true, false)
	_expect(tiles.size() >= 60, "the archive floor is laid in tiles, found %d" % tiles.size())
	for tile: Node in tiles:
		var size: Vector2 = ((tile as MeshInstance3D).mesh as PlaneMesh).size
		_expect(size.x <= M06Dressing.FLOOR_TILE + 0.01 and size.y <= M06Dressing.FLOOR_TILE + 0.01, "floor tiles stay small enough to carry their own lights")
	_expect(cover.find_children("*", "CollisionObject3D", true, false).is_empty(), "restyling adds no bodies")
	var bare: Dictionary = info.duplicate(true)
	bare["map_id"] = 1009
	cover.apply_map_info(bare)
	_expect((cover.get_node("MapFloor") as Node3D).visible and cover.find_children("*ArchiveFloor*", "MeshInstance3D", true, false).is_empty(), "another map keeps its plain floor")
	cover.queue_free()
	await process_frame
