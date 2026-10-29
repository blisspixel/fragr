class_name M12Dressing
extends M06Dressing

## A working pressure habitat, not an orange corridor. All detail fits on
## existing solids, walls or above heads. Rescue and aid remain server facts.
const HABITAT_ID: int = 1012
const PEOPLE_COLOURS: Array[Color] = [Color("9d653f"), Color("687e58"), Color("65758b"), Color("936477")]

static func habitat_layout(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != HABITAT_ID or not info.get("m12") is Dictionary or not info.get("solids") is Array:
		return false
	if not MapGeometry.validation_error(info).is_empty():
		return false
	for pair: Array in [
		[Vector3(-31, 0, -35), Vector3(31, 0.3, 35)],
		[Vector3(-8, 0.3, -34.7), Vector3(-7.7, 3.9, -24)],
		[Vector3(-15.3, 0.3, -24), Vector3(-15, 3.5, -14)],
		[Vector3(-6.5, 0.3, -5), Vector3(-3.5, 1.15, 0.5)],
		[Vector3(-6.5, 0.3, 16.5), Vector3(-3.5, 6.3, 20.5)],
		[Vector3(28.2, 0.3, 18), Vector3(28.5, 4.5, 30)]]:
		if M06Workmanship._host(info["solids"], pair[0], pair[1]).is_empty():
			return false
	return true

static func finish_for(box: AABB, surface: String) -> Material:
	var tint: Color = Color("a5997d")
	var accent: Color = Color("7b735e")
	var p: Vector3 = box.get_center()
	if surface == "enamel" and box.size.y < 0.4 and box.position.y > 3.0:
		return paint("service_steel", Color("818873"), Color("9b9b7c"))
	if surface == "concrete":
		tint = Color("927c65")
	elif surface == "enamel":
		if p.z < -24.0:
			tint = Color("a69877")
			accent = Color("657b6b")
		elif p.x < -6 and p.z < -13:
			tint = Color("78907c")
			accent = Color("657561")
		elif p.x > 9 and p.z < 1:
			tint = Color("7e8d8b")
		elif p.x > 16 and p.z > 17:
			tint = Color("a58b70")
			accent = Color("80664e")
	elif surface == "records_tile":
		if absf(p.x) < 7 and p.z > -6 and p.z < 11:
			tint = Color("667c49") if box.position.y > 1.1 else Color("7c6c54")
			accent = Color("4e633d")
		else:
			tint = Color("7f866e")
	elif surface == "lift_panel":
		tint = Color("71877c")
		accent = Color("a89561")
	else:
		tint = Color("6d7871")
		accent = Color("9a8757")
	return paint(surface, tint, accent)

## Retain the authored pixel tile, but remove issued red/cyan pinlines from
## civilian infrastructure. A per-map cache keeps equal finishes shared.
static var _paint: Dictionary[String, ShaderMaterial] = {}
static func paint(surface: String, tint: Color, accent: Color, venue: String = "mars_habitat") -> ShaderMaterial:
	var key: String = venue + surface + tint.to_html(false) + accent.to_html(false)
	if _paint.has(key):
		return _paint[key]
	var material: ShaderMaterial = ArenaMaterials.authored(surface, venue).duplicate() as ShaderMaterial
	material.set_shader_parameter("surface_color", tint)
	material.set_shader_parameter("accent_color", accent)
	material.set_shader_parameter("warning_color", accent)
	material.set_shader_parameter("trim_glow", 0.0)
	material.set_shader_parameter("base_shade", 0.0)
	material.set_shader_parameter("tile_strength", 0.18)
	material.set_shader_parameter("tile_floor_strength", 0.3)
	_paint[key] = material
	return material

static func restyle_habitat(cover: Node3D, info: Dictionary, views: Array[MeshInstance3D]) -> void:
	if not habitat_layout(info) or not info.get("presentation") is Dictionary:
		return
	var surfaces: Array = info["presentation"].get("solids", [])
	if surfaces.size() != views.size() or views.size() != info["solids"].size():
		return
	for index: int in range(views.size()):
		views[index].material_override = finish_for(_bounds(info["solids"][index]), str(surfaces[index]))
	var dressing := M12Dressing.new()
	dressing.name = "HabitatDressing"
	cover.add_child(dressing)
	dressing.configure_map(info)
	var foundation: AABB = AABB(Vector3(-31, 0, -35), Vector3(62, 0.3, 70))
	tile_foundation(cover, foundation, finish_for(foundation, "concrete"))

func configure_map(info: Dictionary) -> void:
	if active() and habitat_layout(info):
		return
	clear_map()
	if not habitat_layout(info):
		return
	_arrival()
	_market()
	_cultivation(info)
	_pumping()
	_shelter()
	_utility()
	for room: Node3D in _unattached:
		_finish(room)
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

func fitting(room: Node3D, label: String, at: Vector3, size: Vector3, colour: Color) -> MeshInstance3D:
	return _block(_props(room), label, size, _mat("mars_" + colour.to_html(false), colour), at)

func lamp(room: Node3D, at: Vector3, reach: float = 7.0, warm: bool = false) -> void:
	_block(_props(room), "Fixture", Vector3(0.7, 0.09, 0.25), _mat("lamp_housing", Color("57625b")), at)
	_block(_props(room), "Diffuser", Vector3(0.58, 0.035, 0.18), _glow("mars_lamp_warm" if warm else "mars_lamp", Color("e4c99c") if warm else Color("d8d9c8"), 0.8), at - Vector3(0, 0.05, 0))
	_omni(room, "WorkLight%d" % lamps, at - Vector3(0, 0.25, 0), Color(1.0, 0.85, 0.65) if warm else Color(1.0, 0.97, 0.88), 1.35, reach)

func wall_pin(room: Node3D, at: Vector3, colour: Color) -> void:
	fitting(room, "PersonalCard", at, Vector3(0.25, 0.3, 0.015), colour)
	fitting(room, "CardMark", at + Vector3(0, 0.02, -0.01), Vector3(0.13, 0.1, 0.01), colour.darkened(0.3))

func _arrival() -> void:
	var room: Node3D = _room("Arrival")
	for x: float in [-6.2, 6.2]:
		for index: int in range(5):
			var z: float = -32.1 + index * 1.0
			fitting(room, "SeatPad", Vector3(x, 0.83, z), Vector3(0.95, 0.06, 0.8), PEOPLE_COLOURS[index % 4])
			if index % 2 == 0:
				fitting(room, "TravelBag", Vector3(x, 1.04, z), Vector3(0.38, 0.35, 0.52), PEOPLE_COLOURS[(index+1)%4].darkened(0.2))
	for index: int in range(6):
		wall_pin(room, Vector3(3.2 + index*0.6, 2.1, -24.32), PEOPLE_COLOURS[index%4])
	for z: float in [-32, -27]:
		lamp(room, Vector3(0, 3.65, z), 8, true)
	# Pressure-door gasket and repaired seal sit on the existing jambs.
	for x: float in [-2.53, 2.53]:
		fitting(room, "DoorSeal", Vector3(x, 1.7, -24.34), Vector3(0.07, 2.6, 0.06), Color("555b50"))

func _market() -> void:
	var room: Node3D = _room("Market")
	# The counter is supplied, rather than another unexplained slab.
	for index: int in range(6):
		fitting(room, "CounterTin", Vector3(-14.2 + index * 0.5, 1.2, -20.97), Vector3(0.2, 0.18, 0.18), PEOPLE_COLOURS[index%4])
	for y: float in [1.8, 2.5]:
		fitting(room, "StoreShelf", Vector3(-11, y, -23.53), Vector3(6.8, 0.06, 0.28), Color("8b7652"))
		for index: int in range(14):
			fitting(room, "StockJar", Vector3(-14.1+index*0.46, y+0.16, -23.52), Vector3(0.24, 0.25, 0.2), PEOPLE_COLOURS[(index+int(y*10))%4])
	lamp(room, Vector3(-11, 3.28, -19), 7, true)
	# Colour is domestic shade fabric, held flush under the store lintel.
	for index: int in range(14):
		fitting(room, "AwningFold", Vector3(-14.7+index*0.55, 3.35, -13.92), Vector3(0.51, 0.22, 0.16), Color("a88b4c") if index%2 == 0 else Color("6a7f62"))
	lamp(room, Vector3(15, 3.25, -5), 8)
	# Maintenance tools remain on the authoritative workbench.
	for index: int in range(5):
		fitting(room, "BenchTool", Vector3(19.1, 1.19, -3.1+index*0.38), Vector3(0.3, 0.06, 0.1), Color("b19a60"))
	fitting(room, "ToolBoard", Vector3(20.37, 2.2, -2.3), Vector3(0.035, 0.9, 1.8), Color("657b6b"))
	for index: int in range(7):
		fitting(room, "HangingTool", Vector3(20.34, 2.2, -3+index*0.23), Vector3(0.025, 0.45, 0.06), Color("b2ad95"))

func _cultivation(info: Dictionary) -> void:
	var room: Node3D = _room("Greenhouse")
	# Leaves sit just above their existing solid cultivation rows, never conceal a
	# traversable flank or acquire new collision. No magical glowing crops.
	for solid: Dictionary in info["solids"]:
		var b: AABB = _bounds(solid)
		if absf(b.position.y-1.15) > 0.01 or b.size.y > 0.36 or b.size.z > 0.5:
			continue
		for index: int in range(7):
			var x: float = b.position.x+0.15+index*0.29
			for side: float in [-1, 1]:
				var leaf: MeshInstance3D = fitting(room, "CropLeaf", Vector3(x, 1.56, b.get_center().z+side*0.1), Vector3(0.25, 0.045, 0.23), Color("78904e") if index%2 == 0 else Color("5e793f"))
				leaf.rotation.z = side*0.35
	for x: float in [-6.35, 6.35]:
		for z: float in [-2.25, 7.75]:
			fitting(room, "Irrigation", Vector3(x, 1.18, z), Vector3(0.06, 0.06, 5.3), Color("9c9977"))
	for z: float in [-5.35, 2.65, 10.65]:
		lamp(room, Vector3(0, 4.25, z), 9)
		# Overhead crop shades, open sides preserve the Assessor silhouette.
		for x: float in [-5, 5]:
			fitting(room, "ShadeSlat", Vector3(x, 4.37, z), Vector3(5.4, 0.045, 0.6), Color("8e9a79"))

func _pumping() -> void:
	var room: Node3D = _room("Pumps")
	for x: float in [-5, 5]:
		for y: float in [1.0, 2.7, 4.4, 6.0]:
			fitting(room, "TankBand", Vector3(x, y, 16.47), Vector3(2.85, 0.07, 0.035), Color("b0a37e"))
		for index: int in range(8):
			fitting(room, "GaugeTick", Vector3(x+1.2, 2.7+index*0.25, 16.46), Vector3(0.16 if index%2 == 0 else 0.08, 0.035, 0.025), Color("c1b58c"))
		lamp(room, Vector3(x, 6.15, 16.3), 9)
	# Feed brackets explain where maintained water runs, not decorative rivers.
	for x: float in [-4, -2, 0, 2, 4]:
		fitting(room, "FeedClamp", Vector3(x, 5.4, 16.97), Vector3(0.08, 0.45, 0.06), Color("b0a37e"))

func _shelter() -> void:
	var room: Node3D = _room("Shelter")
	for row: int in range(3):
		for column: int in range(8):
			fitting(room, "SharedQuilt", Vector3(21.5+column*0.7, 1.4+row*0.5, 18.32), Vector3(0.67, 0.47, 0.025), PEOPLE_COLOURS[(row*3+column)%4])
	for index: int in range(9):
		wall_pin(room, Vector3(20.9+index*0.75, 2.1, 29.67), PEOPLE_COLOURS[index%4])
	# Folding bedding stays against the back wall, away from people and door.
	for index: int in range(6):
		fitting(room, "FoldedBlanket%d" % index, Vector3(28.05, 0.36+index*0.12, 20.2), Vector3(0.3, 0.12, 0.6), PEOPLE_COLOURS[index%4])
	lamp(room, Vector3(24, 4.25, 23), 8, true)
	lamp(room, Vector3(18, 2.8, 25), 6, true)
	var depot: Node3D = _room("Depot")
	lamp(depot, Vector3(-5, 4.55, 32), 7, true)
	lamp(depot, Vector3(5, 4.55, 32), 7, true)
	# Empty rack is deliberately empty until server-owned aid arrives.
	for x: float in [-8.5, -7.5, -6.5]:
		fitting(depot, "RackDivider", Vector3(x, 1.54, 33.4), Vector3(0.05, 0.06, 1.6), Color("a38b59"))

func _utility() -> void:
	var room: Node3D = _room("Utility")
	for z: float in [-14, -6, 2, 10, 18]:
		lamp(room, Vector3(-23, 3.15, z), 6)
		for y: float in [0.7, 1.8]:
			fitting(room, "PipeCollar", Vector3(-24.68, y, z), Vector3(0.04, 0.09, 1.8), Color("a59c7a"))

## Small coplanar patches each receive their local fixtures in Compatibility.
## The original foundation is retained 4 mm below, with unchanged collision.
static func tile_foundation(parent: Node3D, bounds: AABB, finish: Material) -> void:
	var host := Node3D.new()
	host.name = "LitFloor"
	parent.add_child(host)
	var x: float = bounds.position.x
	while x < bounds.end.x - 0.01:
		var width: float = minf(8.0, bounds.end.x-x)
		var z: float = bounds.position.z
		while z < bounds.end.z - 0.01:
			var depth: float = minf(8.0, bounds.end.z-z)
			_plane(host, "Tile%d" % host.get_child_count(), Vector3(x+width*0.5, bounds.end.y+0.004, z+depth*0.5), Vector2(width, depth), finish)
			z += depth
		x += width
	ArenaSky.mark_world(host)
