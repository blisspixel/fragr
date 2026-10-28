class_name M06Dressing
extends Node3D

## Port of Entry's golden-slice dressing (docs/campaign/l06-port-of-entry.md,
## docs/design/moon.md). The server owns every solid; this presenter only
## restyles their views and furnishes them: surface materials by use, flush
## wall fittings, paint, small possessions on existing tops or against walls,
## overhead runs above head height, the lunar apron outside the glass and
## practical light. A body that could stop a pawn or a shot is never added.
##
## The story is told without words. The crew's own suits hang in the dock by
## the ship-side lock, with grey dust drifted over its sill. Freight arrives
## in practical, many-coloured containers under a gantry crane; the Union's
## issued steel is the bulkhead, the cage and the desks, with small red seals
## and nothing that glows red. The confiscation cage keeps what it took from
## people, tagged, under one hard light on the Railgun. Customs is a quiet,
## competent queue: painted lanes, stamped forms, desk lamps, and the
## Chancellor's welcome loop on hanging screens. Outside, the apron is pale
## dust and dark rock under a hard sun, Earth over the gantry.

const Geometry = preload("res://scripts/model_geometry.gd")
const SURFACE: Shader = preload("res://assets/shaders/arena_surface.gdshader")
const MAP_ID: int = 1006
const MOON: String = "res://assets/environment/moon/surfaces/"
const PRODUCTION: String = "res://assets/environment/production/"
## Interior floor rectangles [min_x, min_z, max_x, max_z]: the freight hall
## and dock, customs and the service branch, and the transit pad.
const INTERIOR: Array[Rect2] = [Rect2(-43, -45, 82, 51), Rect2(-43, 6, 68, 35), Rect2(-10, 41, 20, 5)]
## Floor tiles stay small so each carries its own light list (Compatibility
## lights at most eight lights per object).
const FLOOR_TILE: float = 8.0
## Practical freight paint: warm and varied, mid values so a black Union body
## reads against it. Never black with red, never matte off-white, never cyan.
const FREIGHT: Array[Color] = [Color("8a5a3c"), Color("9c7c45"), Color("68724f"), Color("566474"),
	Color("857d6b"), Color("a36a3e"), Color("7a6a52"), Color("5f6b5e")]
## Personal colour the crew and passengers own.
const PERSONAL: Array[Color] = [Color("b5652e"), Color("6f8a4e"), Color("c49a3c"), Color("8a3a58"),
	Color("4f6f8a"), Color("a8552c"), Color("7c5a8c")]
const OCHRE: Color = Color("9a7f45")
const SEAL_RED: Color = Color("8c1a1e")
const COLD: Color = Color(0.90, 0.95, 0.96)
const WARM: Color = Color(1.0, 0.78, 0.52)

var _shape: RefCounted = Geometry.new()
var _unattached: Array[Node3D] = []
## Rooms built for the current map, and the presenter lamps they carry.
var rooms: Array[String] = []
var lamps: int = 0
static var _surfaces: Dictionary[String, ShaderMaterial] = {}

func clear_map() -> void:
	rooms.clear()
	lamps = 0
	for room: Node3D in _unattached:
		room.free()
	_unattached.clear()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func active() -> bool:
	return not rooms.is_empty()

## Port of Entry's own authored layout only. A custom map reusing the id with
## different structure gets no dressing rather than floating props.
static func authored(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != MAP_ID or not info.get("solids") is Array:
		return false
	var wanted: Array = [
		[Vector3(-42, 6, -44), Vector3(-21, 6.3, -29)],
		[Vector3(-25, 0, -16), Vector3(25, 3, -15)],
		[Vector3(-34, 0, -14), Vector3(-33, 2.8, -8)],
		[Vector3(-35, 0.9, 10), Vector3(-34, 4.5, 25)],
		[Vector3(-12, 0, 15), Vector3(-8, 0.9, 18)],
		[Vector3(-15, 0, 30), Vector3(-14, 2.8, 33)],
		[Vector3(-9, 0, 45), Vector3(9, 7.1, 46)],
	]
	var found: int = 0
	for pair: Array in wanted:
		if not M06Workmanship._host(info["solids"], pair[0], pair[1]).is_empty():
			found += 1
	return found == wanted.size()

static func _bounds(solid: Dictionary) -> AABB:
	var low: Vector3 = Vector3(float(solid.get("min_x", 0.0)), MoveStep.solid_bottom(solid), float(solid.get("min_z", 0.0)))
	var high: Vector3 = Vector3(float(solid.get("max_x", 0.0)), MoveStep.solid_top(solid), float(solid.get("max_z", 0.0)))
	return AABB(low, high - low)

# --- surfaces ---------------------------------------------------------------

## Restyle the server's solid views by use: shell, ceiling, issued steel,
## freight, gallery steel, desks and panels, plus a lit lunar apron outside
## the shell and a tiled interior floor in place of the single plane.
static func restyle(cover: Node3D, info: Dictionary, views: Array[MeshInstance3D]) -> void:
	if not authored(info) or not info.get("presentation") is Dictionary:
		return
	var solids: Array = info["solids"]
	var surfaces: Array = info["presentation"].get("solids", [])
	if surfaces.size() != solids.size() or views.size() != solids.size():
		return
	var freight: Node3D = Node3D.new()
	freight.name = "M06Freight"
	for index: int in range(solids.size()):
		if not solids[index] is Dictionary or not is_instance_valid(views[index]):
			continue
		var box: AABB = _bounds(solids[index])
		var role: String = role_for(box, str(surfaces[index]))
		if role == "glass":
			views[index].material_override = glass()
		elif role == "cargo":
			var tint: Color = FREIGHT[_hash(box.get_center()) % FREIGHT.size()]
			views[index].material_override = freight_paint(tint)
			if maxf(box.size.x, box.size.z) > 7.0:
				_containers(freight, box)
		else:
			views[index].material_override = surface(role)
	cover.add_child(freight)
	var floor: MeshInstance3D = cover.get_node_or_null("MapFloor") as MeshInstance3D
	if floor != null:
		floor.visible = false
	_floors(cover)
	ArenaSky.mark_world(freight)

## A solid's visual role from its registered surface and its shape.
static func role_for(box: AABB, surface: String) -> String:
	var low: Vector3 = box.position
	var high: Vector3 = box.end
	var span: float = maxf(box.size.x, box.size.z)
	var depth: float = minf(box.size.x, box.size.z)
	match surface:
		"inspection_glass": return "glass"
		"records_tile": return "desk"
		"lift_panel": return "panel"
	if low.y >= 4.6 and box.size.y <= 1.5 and depth >= 0.9 and span >= 2.5:
		return "ceiling"
	if surface == "enamel":
		if low.y >= 4.0 and box.size.y <= 1.0:
			return "steel"
		if box.size.y >= 4.4 or (depth <= 1.05 and span >= 8.0) or (high.y >= 5.5 and depth <= 1.05):
			return "shell"
		return "furnish"
	# Issued steel: the dock bulkhead and its header, the confiscation cage,
	# the freight sill under the window, the gantry legs and the valve.
	if is_equal_approx(low.z, -30.0) and is_equal_approx(high.z, -29.0):
		return "union"
	if is_equal_approx(low.x, -34.0) and is_equal_approx(high.x, -33.0):
		return "union"
	if low.x <= -42.5 or low.y > 0.5 and low.y < 2.0 or is_equal_approx(low.x, -40.0):
		return "steel"
	if low.y >= 2.4 or (is_equal_approx(box.size.z, 1.0) and is_equal_approx(box.size.x, 5.0)):
		return "gallery"
	return "cargo"

static func surface(role: String) -> ShaderMaterial:
	if _surfaces.has(role):
		return _surfaces[role]
	var material: ShaderMaterial
	match role:
		"shell":
			# Weathered pressure shell, bone-grey with dark seams, one faded
			# ochre service band; light enough that a black uniform reads.
			material = _material(Color("a49e8c"), MOON + "moon_pressure_bone.png", MOON + "moon_worn_deck.png", 2, Color("948c78"), 0.38)
			material.set_shader_parameter("deck_spacing", 7.1)
			material.set_shader_parameter("warning_color", OCHRE)
		"ceiling":
			material = _material(Color("555a5b"), PRODUCTION + "lunar_steel.png", PRODUCTION + "archive_steel.png", 3, Color("464b4c"), 0.35)
			material.set_shader_parameter("panel_size", 3.0)
		"union":
			# Issued black steel, plates one step lighter; no red paint here.
			material = _material(Color("43484b"), MOON + "moon_union_service.png", MOON + "moon_worn_deck.png", 3, Color("56575e"), 0.55)
		"steel":
			material = _material(Color("4f5555"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, Color("5e6462"), 0.45)
		"gallery":
			# Grated walkway steel with worn ochre edge paint.
			material = _material(Color("4c5254"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, OCHRE, 0.5)
		"desk":
			material = _material(Color("4e5844"), PRODUCTION + "archive_ceramic.png", PRODUCTION + "archive_ceramic.png", 4, Color("3e4637"), 0.35)
		"panel":
			material = _material(Color("4a5052"), MOON + "moon_union_service.png", MOON + "moon_worn_deck.png", 5, Color("c8b88a"), 0.4)
		"floor":
			material = _material(Color("a29f94"), MOON + "moon_worn_deck.png", MOON + "moon_worn_deck.png", 1, Color("6e6b62"), 0.5)
			material.set_shader_parameter("tile_floor_strength", 0.4)
			material.set_shader_parameter("macro_variation", 0.05)
		"apron":
			material = _material(Color("5c5a54"), MOON + "moon_regolith.png", MOON + "moon_regolith.png", 0, Color("5c5a54"), 0.35)
			material.set_shader_parameter("markings_enabled", false)
			material.set_shader_parameter("tile_floor_strength", 0.35)
			material.set_shader_parameter("macro_variation", 0.08)
		"basalt":
			material = _material(Color("3a3e3d"), MOON + "moon_basalt.png", MOON + "moon_basalt.png", 0, Color("3a3e3d"), 0.8)
			material.set_shader_parameter("markings_enabled", false)
			material.set_shader_parameter("tile_floor_strength", 0.8)
		_:
			# Small pressure-shell furniture and fittings.
			material = _material(Color("aaa391"), MOON + "moon_pressure_bone.png", MOON + "moon_worn_deck.png", 2, Color("9b9380"), 0.3)
			material.set_shader_parameter("warning_color", OCHRE)
	_surfaces[role] = material
	return material

static func freight_paint(tint: Color) -> ShaderMaterial:
	var key: String = "freight_" + tint.to_html(false)
	if _surfaces.has(key):
		return _surfaces[key]
	var material: ShaderMaterial = _material(tint, PRODUCTION + "ship_steel.png", PRODUCTION + "ship_floor.png", 0, tint.darkened(0.3), 0.42)
	material.set_shader_parameter("markings_enabled", false)
	material.set_shader_parameter("sector_variation", 0.05)
	material.set_shader_parameter("tile_repeat_pixels", 64.0)
	_surfaces[key] = material
	return material

static func glass() -> StandardMaterial3D:
	# Neutral pressure glass: no blue space tint over the lunar view.
	var pane: StandardMaterial3D = StandardMaterial3D.new()
	pane.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pane.albedo_color = Color(0.60, 0.63, 0.61, 0.2)
	pane.roughness = 0.85
	pane.metallic_specular = 0.0
	pane.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return pane

static func _material(base: Color, wall: String, top: String, style: int, accent: Color, strength: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("surface_color", base)
	material.set_shader_parameter("accent_color", accent)
	material.set_shader_parameter("warning_color", accent)
	material.set_shader_parameter("surface_style", style)
	material.set_shader_parameter("trim_glow", 0.0)
	material.set_shader_parameter("panel_size", 2.0)
	material.set_shader_parameter("sector_variation", 0.06)
	var wall_texture: Texture2D = EnvironmentTextures.texture_at(wall)
	var top_texture: Texture2D = EnvironmentTextures.texture_at(top)
	if wall_texture != null and top_texture != null:
		material.set_shader_parameter("tile_enabled", true)
		material.set_shader_parameter("tile_wall", wall_texture)
		material.set_shader_parameter("tile_floor", top_texture)
		material.set_shader_parameter("tile_strength", strength)
		material.set_shader_parameter("tile_floor_strength", strength)
		material.set_shader_parameter("tile_repeat_pixels", 128.0)
	return material

static func _hash(at: Vector3) -> int:
	return absi(int(floor(at.x * 7.0)) * 73 + int(floor(at.z * 3.0)) * 151 + int(floor(at.y * 5.0)) * 37)

## A long freight lane reads as a row of separate containers: each wraps its
## stretch of the solid a few millimetres proud, with a seam between them and
## locking bars at one end. Collision is the solid underneath.
static func _containers(parent: Node3D, box: AABB) -> void:
	var along_x: bool = box.size.x >= box.size.z
	var length: float = box.size.x if along_x else box.size.z
	var count: int = maxi(1, roundi(length / 6.1))
	var step: float = length / float(count)
	var bar: StandardMaterial3D = MoonBackdrop._material(Color("2b2f30"))
	var seed_value: int = _hash(box.get_center())
	for index: int in range(count):
		var tint: Color = FREIGHT[(seed_value + index * 3) % FREIGHT.size()]
		var start: float = (box.position.x if along_x else box.position.z) + step * float(index)
		var centre: Vector3 = box.get_center()
		var size: Vector3 = box.size + Vector3(0.03, 0.015, 0.03)
		if along_x:
			centre.x = start + step * 0.5
			size.x = step - 0.12
		else:
			centre.z = start + step * 0.5
			size.z = step - 0.12
		centre.y = box.position.y + size.y * 0.5
		var container: MeshInstance3D = MoonBackdrop._piece(parent, "FreightContainer%d" % parent.get_child_count(), centre, size, freight_paint(tint))
		container.set_meta("m06_host", box)
		# Locking bars on the door end, both faces.
		for face: float in [-1.0, 1.0]:
			for bar_index: int in range(4):
				var offset: float = start + 0.35 + float(bar_index) * 0.32
				var at: Vector3 = Vector3(offset, centre.y - 0.05, centre.z + face * (size.z * 0.5 + 0.012)) if along_x \
					else Vector3(centre.x + face * (size.x * 0.5 + 0.012), centre.y - 0.05, offset)
				var rod: Vector3 = Vector3(0.06, size.y - 0.4, 0.02) if along_x else Vector3(0.02, size.y - 0.4, 0.06)
				MoonBackdrop._piece(parent, "ContainerLockBar", at, rod, bar)

## The interior floor in tiles and the lunar apron outside the shell.
static func _floors(cover: Node3D) -> void:
	var floors: Node3D = Node3D.new()
	floors.name = "M06Floors"
	cover.add_child(floors)
	for rect: Rect2 in INTERIOR:
		var x: float = rect.position.x
		while x < rect.end.x - 0.01:
			var width: float = minf(FLOOR_TILE, rect.end.x - x)
			var z: float = rect.position.y
			while z < rect.end.y - 0.01:
				var depth: float = minf(FLOOR_TILE, rect.end.y - z)
				_plane(floors, "PortFloor%d" % floors.get_child_count(), Vector3(x + width * 0.5, 0.0, z + depth * 0.5), Vector2(width, depth), surface("floor"))
				z += depth
			x += width
	var far: float = 320.0
	for rect: Rect2 in [Rect2(-far, -far, far - 43, far * 2), Rect2(-43, -far, far + 43, far - 45),
		Rect2(39, -45, far - 39, 51), Rect2(25, 6, far - 25, far - 6), Rect2(-43, 41, 33, far - 41),
		Rect2(10, 41, 15, far - 41), Rect2(-10, 46, 20, far - 46)]:
		_plane(floors, "LunarApron%d" % floors.get_child_count(), Vector3(rect.get_center().x, -0.01, rect.get_center().y), rect.size, surface("apron"))
	ArenaSky.mark_world(floors)

static func _plane(parent: Node3D, label: String, at: Vector3, size: Vector2, finish: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = finish
	parent.add_child(node)
	return node

# --- rooms ------------------------------------------------------------------

func configure_map(info: Dictionary) -> void:
	if active() and authored(info):
		return
	clear_map()
	if not authored(info):
		return
	_build_dock()
	_build_freight()
	_build_cage()
	_build_loading()
	_build_service()
	_build_customs()
	_build_exit()
	_build_apron()
	for room: Node3D in _unattached:
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

func _room(label: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = label
	_unattached.append(node)
	rooms.append(label)
	return node

func _finish(room: Node3D) -> void:
	var props: Node3D = room.get_node_or_null("Props") as Node3D
	if props != null and props.get_child_count() > 0:
		_shape.merge(props)

func _props(room: Node3D) -> Node3D:
	var props: Node3D = room.get_node_or_null("Props") as Node3D
	if props == null:
		props = Node3D.new()
		props.name = "Props"
		room.add_child(props)
	return props

func _mat(key: String, tint: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	return _shape.material("m06_" + key, tint, metallic, roughness)

func _glow(key: String, tint: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = _mat(key, tint)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	return material

func _block(props: Node3D, label: String, size: Vector3, finish: Material, at: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MoonBackdrop._piece(props, label, at, size, finish)
	return node

func _picture(parent: Node3D, label: String, image: Texture2D, size: Vector2, at: Vector3, face: String, glow: float = 0.0) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = image
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	if glow > 0.0:
		material.emission_enabled = true
		material.emission_texture = image
		material.emission_energy_multiplier = glow
	node.material_override = material
	node.transform = Transform3D(MapDecoration.face_basis(face), at)
	parent.add_child(node)
	return node

func _omni(room: Node3D, label: String, at: Vector3, colour: Color, energy: float, reach: float) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = label
	light.position = at
	light.light_color = colour
	light.light_energy = energy
	light.light_specular = 0.1
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 40.0
	light.distance_fade_length = 10.0
	room.add_child(light)
	lamps += 1
	return light

## A warm caged service lamp where people work: bulb, cage, cable and a short light.
func _lamp(room: Node3D, at: Vector3, energy: float = 1.8, reach: float = 6.5, cable_to: float = 6.0) -> OmniLight3D:
	var props: Node3D = _props(room)
	var cage: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	_shape.cylinder(props, "LampBulb", 0.075, 0.16, _glow("lamp_bulb", WARM.lightened(0.25), 2.6), at, 10).rotation.x = PI * 0.5
	_shape.cylinder(props, "LampShade", 0.17, 0.05, cage, at + Vector3(0, 0.1, 0), 12).rotation.x = PI * 0.5
	for side: int in range(4):
		var angle: float = TAU * float(side) / 4.0
		var offset: Vector3 = Vector3(cos(angle), 0, sin(angle)) * 0.11
		_shape.rod(props, "LampCage", at + offset + Vector3(0, 0.09, 0), at + offset * 0.6 + Vector3(0, -0.12, 0), 0.008, cage, 4)
	if cable_to > at.y:
		_shape.rod(props, "LampCable", at + Vector3(0, 0.12, 0), Vector3(at.x, cable_to, at.z), 0.012, cage, 4)
	return _omni(room, "ServiceLamp", at + Vector3(0, -0.12, 0), WARM, energy, reach)

## A cold issued high-bay fixture: a hood on two drop rods and a hard pool.
func _pool(room: Node3D, at: Vector3, energy: float, reach: float = 7.0, angle: float = 42.0, ceiling: float = 6.2) -> SpotLight3D:
	var props: Node3D = _props(room)
	var hood: StandardMaterial3D = _mat("fixture_hood", Color("2c2d32"), 0.5, 0.5)
	var rod: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	_block(props, "FixtureHood", Vector3(1.1, 0.16, 0.5), hood, at + Vector3(0, 0.08, 0))
	_block(props, "FixtureLens", Vector3(0.98, 0.02, 0.38), _glow("fixture_lens", Color("e6eeee"), 2.2), at + Vector3(0, -0.005, 0))
	if ceiling > at.y + 0.2:
		for side: float in [-1.0, 1.0]:
			_shape.rod(props, "FixtureDrop", at + Vector3(side * 0.4, 0.16, 0), Vector3(at.x + side * 0.4, ceiling, at.z), 0.014, rod, 4)
	var light: SpotLight3D = SpotLight3D.new()
	light.name = "FixturePool%d" % lamps
	light.position = at + Vector3(0, -0.05, 0)
	light.rotation.x = -PI * 0.5
	light.light_color = COLD
	light.light_energy = energy * 1.3
	light.light_specular = 0.15
	light.spot_range = reach
	light.spot_angle = angle
	light.spot_angle_attenuation = 0.6
	light.spot_attenuation = 0.8
	light.shadow_enabled = false
	room.add_child(light)
	lamps += 1
	return light

## Thin floor paint, flush on the floor. Never a body.
func _paint_line(props: Node3D, from: Vector3, to: Vector3, width: float, finish: Material) -> void:
	var span: Vector3 = to - from
	var line: MeshInstance3D = _block(props, "FloorPaint", Vector3(width, 0.006, span.length()), finish, (from + to) * 0.5 + Vector3(0, 0.004, 0))
	line.rotation.y = atan2(span.x, span.z)

func _chevrons(props: Node3D, centre: Vector3, along_x: bool, length: float, depth: float) -> void:
	var dark: StandardMaterial3D = _mat("chevron_dark", Color("2a2b2a"))
	var paint: StandardMaterial3D = _mat("chevron_ochre", OCHRE)
	_block(props, "HazardBand", Vector3(length, 0.005, depth) if along_x else Vector3(depth, 0.005, length), dark, centre + Vector3(0, 0.003, 0))
	var count: int = int(length / 0.6)
	for index: int in range(count):
		var offset: float = -length * 0.5 + 0.3 + float(index) * 0.6
		var stripe: MeshInstance3D = _block(props, "HazardStripe", Vector3(0.22, 0.006, depth * 1.2), paint,
			centre + (Vector3(offset, 0.004, 0) if along_x else Vector3(0, 0.004, offset)))
		stripe.rotation.y = (PI * 0.25) if along_x else (PI * 0.75)
		stripe.scale = Vector3(1, 1, 0.82)

## Pale dust drifted at a threshold: overlapping flat patches, never a slope.
func _dust(props: Node3D, centre: Vector3, spread: Vector2, count: int, seed_value: int) -> void:
	var dust: StandardMaterial3D = _mat("threshold_dust", Color("8f8b80"), 0.0, 1.0)
	var fine: StandardMaterial3D = _mat("threshold_dust_fine", Color("817d73"), 0.0, 1.0)
	for index: int in range(count):
		var u: float = float((seed_value * 31 + index * 17) % 100) / 100.0 - 0.5
		var v: float = float((seed_value * 13 + index * 29) % 100) / 100.0 - 0.5
		var size: Vector3 = Vector3(0.3 + float((index * 7 + seed_value) % 5) * 0.14, 0.004, 0.2 + float((index * 3 + seed_value) % 4) * 0.1)
		var patch: MeshInstance3D = _block(props, "DustDrift", size, dust if index % 3 != 0 else fine,
			centre + Vector3(u * spread.x, 0.003 + float(index) * 0.0004, v * spread.y))
		patch.rotation.y = float((index * 11 + seed_value) % 9) * 0.35

func _crate(props: Node3D, at: Vector3, size: Vector3, tint: Color) -> void:
	_block(props, "Crate", size, _mat("crate_%s" % tint.to_html(false), tint, 0.1, 0.8), at + Vector3(0, size.y * 0.5, 0))
	_block(props, "CrateBand", Vector3(size.x + 0.02, 0.06, size.z + 0.02), _mat("crate_band", Color("2f3233"), 0.4, 0.6), at + Vector3(0, size.y * 0.72, 0))

func _red_tag(props: Node3D, at: Vector3, face: String) -> void:
	var basis: Basis = MapDecoration.face_basis(face)
	var tag: MeshInstance3D = _block(props, "DestructionTag", Vector3(0.12, 0.18, 0.006), _mat("red_tag", SEAL_RED), at)
	tag.basis = basis
	var string: MeshInstance3D = _block(props, "TagString", Vector3(0.01, 0.12, 0.004), _mat("tag_string", Color("c9c1aa")), at + Vector3(0, 0.14, 0))
	string.basis = basis

# --- dock bay: the crew's side of the ship-side lock -------------------------

func _build_dock() -> void:
	var room: Node3D = _room("Dock")
	var props: Node3D = _props(room)
	var steel: StandardMaterial3D = _mat("issued_steel", Color("3a3e40"), 0.4, 0.6)
	var frame: StandardMaterial3D = _mat("lock_frame", Color("5a605f"), 0.4, 0.6)
	var seal: StandardMaterial3D = _mat("lock_seal", Color("232526"), 0.0, 0.9)
	# The ship-side cargo lock in the south shell, closed behind the party.
	var lock_x: float = -31.0
	var face_z: float = -43.985
	_block(props, "CargoLockLeaf", Vector3(5.6, 4.4, 0.03), steel, Vector3(lock_x, 2.2, face_z + 0.015))
	_block(props, "CargoLockSplit", Vector3(0.06, 4.4, 0.04), seal, Vector3(lock_x, 2.2, face_z + 0.03))
	for side: float in [-1.0, 1.0]:
		_block(props, "CargoLockJamb", Vector3(0.45, 4.9, 0.12), frame, Vector3(lock_x + side * 3.05, 2.45, face_z + 0.06))
		for y: float in [0.6, 1.6, 2.6, 3.6]:
			_block(props, "LockDog", Vector3(0.22, 0.12, 0.08), _mat("lock_dog", Color("8e8775"), 0.3, 0.6), Vector3(lock_x + side * 2.65, y, face_z + 0.07))
	_block(props, "CargoLockHeader", Vector3(6.55, 0.5, 0.14), frame, Vector3(lock_x, 4.65, face_z + 0.07))
	for index: int in range(9):
		var stripe: MeshInstance3D = _block(props, "LockHazard", Vector3(0.18, 0.62, 0.01), _mat("chevron_ochre", OCHRE), Vector3(lock_x - 2.6 + float(index) * 0.65, 4.65, face_z + 0.145))
		stripe.rotation.z = PI * 0.22
	# A small lit porthole: the passengers are still aboard, behind it.
	_shape.cylinder(props, "LockPortRim", 0.32, 0.06, frame, Vector3(lock_x + 1.4, 2.9, face_z + 0.05), 12).rotation.x = PI * 0.5
	_shape.cylinder(props, "LockPortGlass", 0.24, 0.02, _glow("porthole", Color("e8c48a"), 1.4), Vector3(lock_x + 1.4, 2.9, face_z + 0.08), 12).rotation.x = PI * 0.5
	# Dust trap grate and the grey dust tracked in over the sill.
	var grate: StandardMaterial3D = _mat("drain_grate", Color("1c1d1f"), 0.5, 0.6)
	var grate_bar: StandardMaterial3D = _mat("drain_bar", Color("4a4c4c"), 0.6, 0.5)
	_block(props, "DustTrap", Vector3(5.4, 0.008, 1.6), grate, Vector3(lock_x, 0.004, -42.9))
	for index: int in range(18):
		_block(props, "DustTrapBar", Vector3(0.05, 0.01, 1.5), grate_bar, Vector3(lock_x - 2.55 + float(index) * 0.3, 0.007, -42.9))
	_dust(props, Vector3(lock_x, 0, -41.2), Vector2(5.0, 2.6), 14, 3)
	_dust(props, Vector3(lock_x + 0.6, 0, -38.5), Vector2(1.6, 4.0), 6, 7)
	_chevrons(props, Vector3(lock_x, 0, -41.8), true, 6.0, 0.35)
	_pool(room, Vector3(lock_x, 5.6, -41.5), 3.2, 7.0, 40.0, 6.0)
	# The crew's own suits on the west shell, each patched in its owner's colour.
	for index: int in range(4):
		var z: float = -42.6 + float(index) * 1.05
		_suit(props, Vector3(-41.82, 0, z), PERSONAL[(index * 2 + 1) % PERSONAL.size()], index)
	_lamp(room, Vector3(-40.6, 3.6, -41.0), 1.6, 6.0, 6.0)
	# Crew lockers on the east wall: personal colour, stickers, one left open.
	for index: int in range(6):
		var z: float = -42.8 + float(index) * 0.62
		var tint: Color = PERSONAL[index % PERSONAL.size()].darkened(0.15)
		_block(props, "CrewLocker", Vector3(0.42, 2.0, 0.58), _mat("locker_%d" % index, tint, 0.2, 0.7), Vector3(-21.22, 1.0, z))
		_block(props, "LockerVent", Vector3(0.01, 0.12, 0.36), _mat("locker_vent", Color("262728")), Vector3(-21.435, 1.7, z))
		if index % 2 == 0:
			_block(props, "LockerSticker", Vector3(0.01, 0.14, 0.14), _mat("sticker_%d" % index, PERSONAL[(index + 3) % PERSONAL.size()].lightened(0.25)), Vector3(-21.437, 1.25, z + 0.08))
	_block(props, "LockerTop", Vector3(0.46, 0.05, 3.8), _mat("locker_top", Color("4a4d4c"), 0.3, 0.6), Vector3(-21.22, 2.025, -41.25))
	_lamp(room, Vector3(-22.0, 3.4, -40.0), 1.5, 6.0, 6.0)
	# The dust declaration station at the control panel: a brush rack.
	var brush: StandardMaterial3D = _mat("brush", Color("6b5a3c"))
	for index: int in range(3):
		_shape.rod(props, "DustBrush", Vector3(-41.9, 0.95, -37.2 + float(index) * 0.22), Vector3(-41.9, 1.62, -37.2 + float(index) * 0.22), 0.025, brush, 6)
	_block(props, "BrushRack", Vector3(0.1, 0.06, 0.8), steel, Vector3(-41.95, 1.6, -37.0))
	_pool(room, Vector3(-31.0, 5.6, -35.0), 2.4, 7.0, 42.0, 6.0)
	_finish(room)

## A pressure suit hanging on a wall hook: torso, helmet, limp arms and legs.
func _suit(props: Node3D, at: Vector3, tint: Color, index: int) -> void:
	var cloth: StandardMaterial3D = _mat("suit_cloth", Color("8b8678"), 0.0, 0.9)
	var patch: StandardMaterial3D = _mat("suit_patch_%s" % tint.to_html(false), tint, 0.0, 0.85)
	var visor: StandardMaterial3D = _mat("suit_visor", Color("2a2c2c"), 0.6, 0.3)
	var x: float = at.x + 0.22
	_block(props, "SuitHook", Vector3(0.2, 0.05, 0.05), _mat("lamp_cage", Color("2f3030"), 0.4, 0.6), Vector3(at.x + 0.1, 2.45, at.z))
	_block(props, "SuitTorso", Vector3(0.34, 0.72, 0.5), cloth, Vector3(x, 1.75, at.z))
	_block(props, "SuitPanel", Vector3(0.02, 0.42, 0.32), patch, Vector3(x + 0.18, 1.8, at.z))
	_shape.cylinder(props, "SuitHelmet", 0.17, 0.3, cloth, Vector3(x, 2.3, at.z), 10)
	_block(props, "SuitVisor", Vector3(0.03, 0.14, 0.24), visor, Vector3(x + 0.17, 2.3, at.z))
	for side: float in [-1.0, 1.0]:
		_block(props, "SuitArm", Vector3(0.14, 0.62, 0.14), cloth, Vector3(x, 1.6, at.z + side * 0.32))
		_block(props, "SuitLeg", Vector3(0.16, 0.8, 0.16), cloth, Vector3(x, 0.98, at.z + side * 0.12))
		_block(props, "SuitBoot", Vector3(0.24, 0.16, 0.18), _mat("suit_boot", Color("3e3b35")), Vector3(x + 0.03, 0.52, at.z + side * 0.12))
	if index % 2 == 1:
		_block(props, "SuitRepairTape", Vector3(0.02, 0.1, 0.2), _mat("repair_tape", Color("c49a3c")), Vector3(x + 0.18, 1.45, at.z - 0.05))

# --- freight hall --------------------------------------------------------------

func _build_freight() -> void:
	var room: Node3D = _room("Freight")
	var props: Node3D = _props(room)
	var steel: StandardMaterial3D = _mat("crane_steel", Color("6d6a5c"), 0.4, 0.6)
	var dark: StandardMaterial3D = _mat("crane_dark", Color("343839"), 0.4, 0.6)
	# The gantry crane's runway rails under the roof and its bridge, above
	# every walkway and the crane overlook.
	for z: float in [-28.2, 4.2]:
		_block(props, "CraneRunway", Vector3(58, 0.3, 0.35), dark, Vector3(7, 5.75, z))
	_block(props, "CraneBridge", Vector3(0.7, 0.55, 32.4), steel, Vector3(9.0, 5.45, -12.0))
	_block(props, "CraneBridgeWeb", Vector3(0.2, 0.25, 32.0), dark, Vector3(9.0, 5.05, -12.0))
	for index: int in range(12):
		var stripe: MeshInstance3D = _block(props, "CraneStripe", Vector3(0.72, 0.2, 0.5), _mat("chevron_ochre", OCHRE), Vector3(9.0, 5.45, -27.0 + float(index) * 2.7))
		stripe.scale = Vector3(1.01, 1.01, 1.0)
	_block(props, "CraneTrolley", Vector3(1.4, 0.6, 1.2), dark, Vector3(9.0, 4.95, -20.5))
	_shape.rod(props, "HoistCable", Vector3(8.85, 4.6, -20.5), Vector3(8.85, 3.95, -20.5), 0.02, dark, 4)
	_shape.rod(props, "HoistCable", Vector3(9.15, 4.6, -20.5), Vector3(9.15, 3.95, -20.5), 0.02, dark, 4)
	_block(props, "HookBlock", Vector3(0.45, 0.5, 0.3), _mat("hook_block", OCHRE.darkened(0.1), 0.3, 0.6), Vector3(9.0, 3.75, -20.5))
	# Painted handling lanes along the aisles and the rail lane's long line.
	var lane: StandardMaterial3D = _mat("lane_paint", Color("a08a52"), 0.0, 0.95)
	for z: float in [-27.2, -17.0, -13.9, -8.1, -4.9, 3.9]:
		var x: float = -30.0
		while x < 36.0:
			_paint_line(props, Vector3(x, 0, z), Vector3(x + 2.4, 0, z), 0.12, lane)
			x += 3.2
	# Wheel-worn dust down the middle of each aisle.
	var tracks: StandardMaterial3D = _mat("track_wear", Color("5d5b54"), 0.0, 1.0)
	for z: float in [-22.6, -22.0, 0.4, 1.0]:
		_paint_line(props, Vector3(-28, 0, z), Vector3(36, 0, z), 0.3, tracks)
	_dust(props, Vector3(-30.5, 0, -28.2), Vector2(7.0, 1.6), 10, 11)
	# High-bay pools in a rhythm along the three aisles.
	for x: float in [-28.0, -12.0, 4.0, 20.0, 33.0]:
		_pool(room, Vector3(x, 5.6, -22.5), 2.6, 7.0, 44.0, 6.2)
	for x: float in [-16.0, 2.0, 18.0]:
		_pool(room, Vector3(x, 5.6, -10.8), 2.0, 7.0, 40.0, 6.2)
	for x: float in [-10.0, 6.0, 30.0]:
		_pool(room, Vector3(x, 5.6, 0.5), 2.4, 7.0, 44.0, 6.2)
	# Earth over the gantry: let the window side read cool and quiet.
	_omni(room, "WindowSpill", Vector3(-40.5, 3.2, -17.0), Color(0.82, 0.86, 0.9), 0.9, 9.0)
	# The scale station's warm desk light.
	_lamp(room, Vector3(8.0, 3.4, -24.4), 1.5, 5.5, 6.2)
	_finish(room)

# --- confiscation cage: what the port took ------------------------------------

func _build_cage() -> void:
	var room: Node3D = _room("Cage")
	var props: Node3D = _props(room)
	var mesh_steel: StandardMaterial3D = _mat("cage_mesh", Color("595f5e"), 0.5, 0.5)
	var post: StandardMaterial3D = _mat("issued_steel", Color("3a3e40"), 0.4, 0.6)
	# A mesh roof over the cage bay at 2.9 m with its posts against the lanes.
	var low: Vector3 = Vector3(-33.0, 2.9, -15.0)
	var high: Vector3 = Vector3(-31.2, 2.96, -7.0)
	_block(props, "CageRoofFrame", Vector3(high.x - low.x, 0.06, 0.08), post, Vector3((low.x + high.x) * 0.5, 2.93, low.z + 0.04))
	_block(props, "CageRoofFrame", Vector3(high.x - low.x, 0.06, 0.08), post, Vector3((low.x + high.x) * 0.5, 2.93, high.z - 0.04))
	_block(props, "CageRoofEdge", Vector3(0.08, 0.06, high.z - low.z), post, Vector3(high.x, 2.93, (low.z + high.z) * 0.5))
	for index: int in range(16):
		_block(props, "CageRoofBar", Vector3(high.x - low.x, 0.025, 0.025), mesh_steel, Vector3((low.x + high.x) * 0.5, 2.92, low.z + 0.25 + float(index) * 0.5))
	# Mesh panels flush on the lane faces either side of the bay.
	for z: float in [-14.985, -7.015]:
		for index: int in range(10):
			_block(props, "CageMeshBar", Vector3(0.025, 2.7, 0.012), mesh_steel, Vector3(-33.85 + float(index) * 0.3, 1.45, z))
		for y: float in [0.3, 1.2, 2.1, 2.75]:
			_block(props, "CageMeshRail", Vector3(2.8, 0.03, 0.014), mesh_steel, Vector3(-32.5, y, z))
	# Confiscated possessions in the back corners, each tagged for destruction.
	var pile: Array = [[Vector3(-32.7, 0, -14.4), "hard_luggage", 0.0], [Vector3(-32.6, 0, -7.6), "duffel", 90.0]]
	for row: Array in pile:
		var placed: Node3D = CampaignProps.stand(props.get_parent() as Node3D, str(row[1]), row[0], float(row[2]), 0.9)
		if placed != null:
			placed.name = "Confiscated" + str(row[1]).to_pascal_case()
	_crate(props, Vector3(-32.65, 0, -13.5), Vector3(0.55, 0.5, 0.6), PERSONAL[2])
	_crate(props, Vector3(-32.65, 0.5, -13.5), Vector3(0.45, 0.3, 0.5), PERSONAL[4])
	# A guitar case and a stack of hand-painted body panels taken at the gate.
	_block(props, "GuitarCase", Vector3(0.14, 1.05, 0.38), _mat("guitar_case", Color("5b3b2a")), Vector3(-33.0, 0.55, -8.4))
	for index: int in range(4):
		_block(props, "PersonalPanel", Vector3(0.05, 0.62, 0.5), _mat("personal_panel_%d" % index, PERSONAL[(index * 3) % PERSONAL.size()]), Vector3(-32.95 + float(index) * 0.06, 0.32, -9.3))
	for at: Vector3 in [Vector3(-32.38, 0.75, -14.4), Vector3(-32.18, 0.5, -13.5), Vector3(-32.85, 0.9, -8.4), Vector3(-32.7, 0.62, -9.3)]:
		_red_tag(props, at, "east")
	# One hard light on the Railgun.
	_pool(room, Vector3(-29.6, 5.6, -11.0), 3.4, 6.5, 30.0, 6.2)
	_finish(room)

# --- loading bay ---------------------------------------------------------------

func _build_loading() -> void:
	var room: Node3D = _room("Loading")
	var props: Node3D = _props(room)
	_chevrons(props, Vector3(31.0, 0, -5.4), true, 13.5, 0.4)
	# The outer roller door in the east shell, stopped short of the floor,
	# with the apron's light under it and dust blown in.
	var door: StandardMaterial3D = _mat("roller_door", Color("6b6f6a"), 0.3, 0.7)
	var slat: StandardMaterial3D = _mat("roller_slat", Color("4d514f"), 0.3, 0.7)
	_block(props, "RollerDoor", Vector3(0.03, 3.5, 5.0), door, Vector3(37.985, 2.15, 0.0))
	for index: int in range(14):
		_block(props, "RollerSlat", Vector3(0.02, 0.04, 5.0), slat, Vector3(37.965, 0.6 + float(index) * 0.25, 0.0))
	_block(props, "DoorDaylight", Vector3(0.02, 0.38, 5.0), _glow("door_daylight", Color("dedbd0"), 1.6), Vector3(37.99, 0.19, 0.0))
	_dust(props, Vector3(36.6, 0, 0.0), Vector2(2.4, 4.6), 10, 17)
	_omni(room, "DoorDaylightSpill", Vector3(37.2, 0.4, 0.0), Color(0.92, 0.94, 0.94), 1.2, 5.0)
	# Hoist chains above head height and a warm work lamp over the crate.
	var chain: StandardMaterial3D = _mat("chain", Color("3a3c3b"), 0.6, 0.5)
	for x: float in [27.0, 33.5]:
		_shape.rod(props, "HoistChain", Vector3(x, 6.2, -2.5), Vector3(x, 4.2, -2.5), 0.03, chain, 4)
		_block(props, "HoistHook", Vector3(0.18, 0.28, 0.08), _mat("hook_block", OCHRE.darkened(0.1), 0.3, 0.6), Vector3(x, 4.05, -2.5))
	_lamp(room, Vector3(30.0, 3.8, -2.5), 1.8, 6.5, 6.2)
	_pool(room, Vector3(32.0, 5.6, 2.5), 2.2, 7.0, 42.0, 6.2)
	_finish(room)

# --- service branch --------------------------------------------------------------

func _build_service() -> void:
	var room: Node3D = _room("Service")
	var props: Node3D = _props(room)
	var pipe_a: StandardMaterial3D = _mat("pipe_grey", Color("6c716c"), 0.4, 0.6)
	var pipe_b: StandardMaterial3D = _mat("pipe_ochre", Color("8a7442"), 0.3, 0.6)
	var bracket: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	# Pipe runs along the corridor's north wall, above head height.
	for row: int in range(3):
		var y: float = 4.3 + float(row) * 0.32
		var finish: StandardMaterial3D = pipe_b if row == 1 else pipe_a
		_shape.rod(props, "ServicePipe", Vector3(-33.9, y, 24.82 - float(row) * 0.04), Vector3(-25.1, y, 24.82 - float(row) * 0.04), 0.09, finish, 8)
	for x: float in [-33.2, -30.0, -27.0, -25.6]:
		_block(props, "PipeBracket", Vector3(0.06, 1.1, 0.3), bracket, Vector3(x, 4.62, 24.86))
	# A valve wheel at reach height on its own drop.
	_shape.rod(props, "ValveDrop", Vector3(-27.6, 4.3, 24.8), Vector3(-27.6, 1.6, 24.8), 0.05, pipe_a, 8)
	_shape.cylinder(props, "ValveWheel", 0.26, 0.04, _mat("valve_wheel", Color("8c3a2a")), Vector3(-27.6, 1.55, 24.62), 10).rotation.x = PI * 0.5
	# Pipes above the family glass lintel and over the cache valve.
	for row: int in range(2):
		_shape.rod(props, "LintelPipe", Vector3(-33.8, 5.0 + float(row) * 0.3, 10.2), Vector3(-33.8, 5.0 + float(row) * 0.3, 24.8), 0.08, pipe_a, 8)
	_shape.rod(props, "CachePipe", Vector3(-39.5, 2.6, 3.0), Vector3(-39.5, 5.8, 3.0), 0.1, pipe_b, 8)
	# Drains and warm lamps; the family room carries its own light.
	var grate: StandardMaterial3D = _mat("drain_grate", Color("1c1d1f"), 0.5, 0.6)
	for z: float in [12.0, 20.0]:
		_block(props, "Drain", Vector3(0.5, 0.008, 0.5), grate, Vector3(-27.0, 0.004, z))
	_lamp(room, Vector3(-28.0, 3.9, 12.5), 1.7, 6.5, 5.8)
	_lamp(room, Vector3(-28.0, 3.9, 21.5), 1.7, 6.5, 5.8)
	_lamp(room, Vector3(-37.0, 3.6, 4.6), 1.6, 6.0, 6.2)
	# Glass-side planters the residents keep: soil trays with low green.
	var soil: StandardMaterial3D = _mat("soil", Color("4a3b2c"))
	var leaf: StandardMaterial3D = _mat("leaf", Color("74884e"))
	for z: float in [11.4, 23.6]:
		_block(props, "PlanterTray", Vector3(0.7, 0.4, 1.2), _mat("planter", Color("8a6a4a")), Vector3(-35.6, 0.2, z))
		_block(props, "PlanterSoil", Vector3(0.6, 0.02, 1.1), soil, Vector3(-35.6, 0.41, z))
		for leaf_index: int in range(4):
			_block(props, "PlanterLeaf", Vector3(0.16, 0.24 + float(leaf_index % 2) * 0.14, 0.16), leaf, Vector3(-35.6 + (float(leaf_index % 2) - 0.5) * 0.25, 0.56, z - 0.4 + float(leaf_index) * 0.27))
	_finish(room)

# --- customs ---------------------------------------------------------------------

func _build_customs() -> void:
	var room: Node3D = _room("Customs")
	var props: Node3D = _props(room)
	# Gallery edges painted, and pools under the galleries' soffits.
	var edge: StandardMaterial3D = _mat("chevron_ochre", OCHRE)
	for x: float in [-15.99, 15.99]:
		_block(props, "GalleryEdgePaint", Vector3(0.012, 0.12, 30.0), edge, Vector3(x, 2.94, 21.0))
	_block(props, "GalleryEdgePaint", Vector3(32.0, 0.12, 0.012), edge, Vector3(0, 2.94, 29.99))
	for z: float in [10.0, 22.0]:
		_omni(room, "GallerySoffitLamp", Vector3(-18.5, 2.3, z), COLD, 1.1, 5.5)
		_omni(room, "GallerySoffitLamp", Vector3(18.5, 2.3, z), COLD, 1.1, 5.5)
	# Queue lanes painted between the islands toward the desks.
	var lane: StandardMaterial3D = _mat("lane_paint", Color("a08a52"), 0.0, 0.95)
	for x: float in [-7.0, -2.0, 2.0, 7.0]:
		_paint_line(props, Vector3(x, 0, 19.5), Vector3(x, 0, 29.0), 0.1, lane)
	for z: float in [20.5, 27.5]:
		for x: float in [-4.5, 0.0, 4.5]:
			_block(props, "StandHereMark", Vector3(0.7, 0.005, 0.5), _mat("stand_mark", Color("b8ad86"), 0.0, 0.95), Vector3(x, 0.004, z))
	# Hard pools over the inspection desks and the queue.
	for x: float in [-10.0, 10.0]:
		_pool(room, Vector3(x, 5.8, 16.5), 3.0, 7.0, 36.0, 6.8)
	_pool(room, Vector3(0.0, 5.8, 24.5), 2.4, 7.0, 44.0, 6.8)
	_pool(room, Vector3(0.0, 5.8, 12.0), 2.0, 7.0, 44.0, 6.8)
	# Desk work: stamped forms, a stamp rack, a desk lamp, a confiscation tray.
	for x: float in [-10.0, 10.0]:
		var paper: StandardMaterial3D = _mat("paper", Color("e3dccb"), 0.0, 0.95)
		var form: StandardMaterial3D = _mat("form_green", Color("b8c4a6"), 0.0, 0.95)
		for index: int in range(5):
			var piece: MeshInstance3D = _block(props, "FormStack", Vector3(0.24, 0.02 + float(index % 3) * 0.01, 0.32), form if index % 2 == 0 else paper,
				Vector3(x - 1.2 + float(index) * 0.5, 0.92, 15.6 + float(index % 2) * 0.2))
			piece.rotation.y = float(index - 2) * 0.08
		_block(props, "StampRack", Vector3(0.4, 0.08, 0.14), _mat("issued_steel", Color("3a3e40"), 0.4, 0.6), Vector3(x + 1.2, 0.94, 17.4))
		for index: int in range(3):
			_shape.cylinder(props, "Stamp", 0.035, 0.12, _mat("stamp", Color("2f2f30"), 0.2, 0.6), Vector3(x + 1.08 + float(index) * 0.12, 1.04, 17.4), 8)
		_block(props, "ConfiscationTray", Vector3(0.7, 0.08, 0.45), _mat("tray", Color("5a605f"), 0.4, 0.6), Vector3(x + 0.2, 0.94, 17.2))
		for index: int in range(3):
			_block(props, "TrayPossession", Vector3(0.14, 0.06, 0.1), _mat("possession_%d" % index, PERSONAL[(index * 2 + (0 if x < 0 else 1)) % PERSONAL.size()]), Vector3(x + 0.0 + float(index) * 0.2, 1.0, 17.2))
		_desk_lamp(room, Vector3(x - 1.5, 0.9, 17.5), Vector3(x - 0.8, 0.9, 16.0))
	# The Chancellor's welcome loop on two hanging screens over the hall.
	var loop: Texture2D = welcome_screen()
	for at: Vector3 in [Vector3(-4.5, 4.6, 13.0), Vector3(4.5, 4.6, 13.0)]:
		_hung_screen(room, props, loop, at)
	# Union seals: two tall black banners high on the north wall, above the exit.
	for x: float in [-13.5, 13.5]:
		_banner(props, Vector3(x, 4.6, 39.985))
	# Duty-free kiosk: rows of identical tax-exempt compliance goods.
	_duty_free(room, props)
	_finish(room)

## A small desk lamp standing on a top, angled toward the work.
func _desk_lamp(room: Node3D, base: Vector3, toward: Vector3) -> void:
	var props: Node3D = _props(room)
	var arm: StandardMaterial3D = _mat("desk_lamp", Color("3d4441"), 0.35, 0.6)
	_shape.cylinder(props, "DeskLampBase", 0.1, 0.03, arm, base + Vector3(0, 0.015, 0), 10).rotation.x = PI * 0.5
	var elbow: Vector3 = base + Vector3(0, 0.38, 0) + (toward - base).normalized() * -0.05
	var head: Vector3 = elbow + (Vector3(toward.x, elbow.y, toward.z) - elbow).normalized() * 0.28 + Vector3(0, 0.04, 0)
	_shape.rod(props, "DeskLampArm", base, elbow, 0.012, arm, 6)
	_shape.rod(props, "DeskLampArm", elbow, head, 0.012, arm, 6)
	_shape.cylinder(props, "DeskLampShade", 0.09, 0.14, _mat("desk_lamp_shade", Color("4e5844"), 0.2, 0.7), head, 10).rotation.x = PI * 0.5
	_shape.cylinder(props, "DeskLampBulb", 0.05, 0.03, _glow("desk_bulb", Color("ffd9a0"), 2.4), head + Vector3(0, -0.08, 0), 8).rotation.x = PI * 0.5
	var light: OmniLight3D = _omni(room, "DeskLamp", head + Vector3(0, -0.15, 0), WARM, 1.3, 3.6)
	light.omni_attenuation = 1.8

func _hung_screen(room: Node3D, props: Node3D, loop: Texture2D, at: Vector3) -> void:
	var housing: StandardMaterial3D = _mat("screen_housing", Color("2c2e30"), 0.4, 0.6)
	_block(props, "ScreenHousing", Vector3(2.3, 1.45, 0.3), housing, at)
	for side: float in [-0.8, 0.8]:
		_shape.rod(props, "ScreenDrop", at + Vector3(side, 0.72, 0), Vector3(at.x + side, 6.8, at.z), 0.02, housing, 4)
	_picture(room, "WelcomeLoopSouth%d" % int(at.x + 10.0), loop, Vector2(2.0, 1.25), at + Vector3(0, 0, 0.152), "south", 0.7)
	_picture(room, "WelcomeLoopNorth%d" % int(at.x + 10.0), loop, Vector2(2.0, 1.25), at + Vector3(0, 0, -0.152), "north", 0.7)

## The welcome loop: the Chancellor at a podium between two seal banners, a
## crowd's raised hands, and an unreadable caption bar. No words.
static func welcome_screen() -> Texture2D:
	var image: Image = Image.create(64, 40, false, Image.FORMAT_RGB8)
	image.fill(Color("1d2624"))
	var ink: Color = Color("101414")
	var bone: Color = Color("d8cfb8")
	var red: Color = Color("a3262a")
	var steel: Color = Color("4a5052")
	# Banner pair either side.
	for x: int in [6, 51]:
		image.fill_rect(Rect2i(x, 3, 7, 22), ink)
		image.fill_rect(Rect2i(x + 2, 8, 3, 3), red)
		image.fill_rect(Rect2i(x + 3, 11, 1, 6), red)
	# The Chancellor: severe black coat, steel collar, red seal and armband.
	image.fill_rect(Rect2i(27, 6, 10, 2), Color("2a2a2c"))
	image.fill_rect(Rect2i(28, 8, 8, 6), bone)
	image.fill_rect(Rect2i(29, 10, 2, 1), ink)
	image.fill_rect(Rect2i(33, 10, 2, 1), ink)
	image.fill_rect(Rect2i(26, 14, 12, 2), steel)
	image.fill_rect(Rect2i(24, 16, 16, 12), ink)
	image.fill_rect(Rect2i(34, 18, 2, 2), red)
	image.fill_rect(Rect2i(24, 19, 3, 2), red)
	# The podium.
	image.fill_rect(Rect2i(22, 24, 20, 8), steel)
	image.fill_rect(Rect2i(29, 26, 6, 4), Color("2a2f30"))
	# Raised hands of the crowd along the bottom.
	for x: int in range(2, 62, 5):
		image.fill_rect(Rect2i(x, 33, 3, 3), Color("3c4442"))
		if x % 3 == 0:
			image.fill_rect(Rect2i(x + 1, 30, 1, 3), Color("8f8670"))
	# The caption bar, dashes too small to read.
	image.fill_rect(Rect2i(0, 37, 64, 3), Color("0c0f0f"))
	for x: int in range(3, 60, 4):
		image.fill_rect(Rect2i(x, 38, 2 + (x % 3), 1), bone.darkened(0.2))
	return ImageTexture.create_from_image(image)

func _banner(props: Node3D, at: Vector3) -> void:
	var cloth: StandardMaterial3D = _mat("banner_cloth", Color("1c1c20"), 0.0, 0.95)
	var seal: StandardMaterial3D = _mat("banner_seal", SEAL_RED, 0.0, 0.9)
	_block(props, "BannerRod", Vector3(1.9, 0.06, 0.06), _mat("issued_steel", Color("3a3e40"), 0.4, 0.6), at + Vector3(0, 2.0, -0.05))
	_block(props, "Banner", Vector3(1.6, 3.9, 0.02), cloth, at + Vector3(0, 0.05, -0.02))
	# An original seal: an open ring over a single upright bar.
	for index: int in range(10):
		var angle: float = TAU * float(index) / 10.0
		_block(props, "BannerRing", Vector3(0.2, 0.08, 0.01), seal, at + Vector3(cos(angle) * 0.42, 0.8 + sin(angle) * 0.42, -0.035)).rotation.z = angle + PI * 0.5
	_block(props, "BannerBar", Vector3(0.12, 1.5, 0.01), seal, at + Vector3(0, -0.3, -0.035))

func _duty_free(room: Node3D, props: Node3D) -> void:
	# The kiosk faces east at x = -14. A shallow shelf rack flush on its face
	# and an awning above head height.
	var shelf: StandardMaterial3D = _mat("kiosk_shelf", Color("4a4f50"), 0.3, 0.6)
	var goods: StandardMaterial3D = _mat("compliance_goods", Color("8b8f8c"), 0.1, 0.7)
	var seal: StandardMaterial3D = _mat("goods_seal", SEAL_RED)
	# Two rows above the shutter's scratched six, which stays clear.
	for row: int in range(2):
		var y: float = 1.9 + float(row) * 0.36
		_block(props, "KioskShelf", Vector3(0.22, 0.03, 2.6), shelf, Vector3(-13.89, y, 31.5))
		for index: int in range(8):
			var z: float = 30.42 + float(index) * 0.31
			_block(props, "ComplianceBox", Vector3(0.16, 0.22, 0.2), goods, Vector3(-13.9, y + 0.125, z))
			_block(props, "ComplianceSeal", Vector3(0.006, 0.05, 0.05), seal, Vector3(-13.818, y + 0.15, z))
	_block(props, "KioskAwning", Vector3(1.0, 0.06, 3.2), _mat("awning", Color("6a5a40")), Vector3(-13.5, 2.62, 31.5))
	_block(props, "KioskLightStrip", Vector3(0.05, 0.03, 2.8), _glow("kiosk_strip", Color("ffe0b0"), 1.8), Vector3(-13.1, 2.58, 31.5))
	_omni(room, "KioskLamp", Vector3(-13.0, 2.4, 31.5), WARM, 1.6, 5.0)

# --- exit hall and transit ---------------------------------------------------------

func _build_exit() -> void:
	var room: Node3D = _room("Exit")
	var props: Node3D = _props(room)
	# The transit tunnel mouth on the end wall: a dark recess read by its rings.
	var void_finish: StandardMaterial3D = _mat("tunnel_void", Color("0e1011"), 0.0, 1.0)
	var ring: StandardMaterial3D = _mat("tunnel_ring", Color("5a605f"), 0.4, 0.6)
	_block(props, "TunnelMouth", Vector3(6.0, 3.6, 0.01), void_finish, Vector3(0, 1.8, 44.985))
	for index: int in range(3):
		var inset: float = float(index) * 0.45
		var width: float = 6.0 - inset * 2.0
		var height: float = 3.6 - inset
		var y: float = height * 0.5
		var z: float = 44.975 - float(index) * 0.002
		var tone: StandardMaterial3D = ring if index == 0 else _mat("tunnel_ring_%d" % index, Color("5a605f").darkened(0.25 * float(index)), 0.4, 0.6)
		_block(props, "TunnelRingTop", Vector3(width, 0.14, 0.012), tone, Vector3(0, height - 0.07, z))
		_block(props, "TunnelRingSide", Vector3(0.14, height, 0.012), tone, Vector3(-width * 0.5 + 0.07, y, z))
		_block(props, "TunnelRingSide", Vector3(0.14, height, 0.012), tone, Vector3(width * 0.5 - 0.07, y, z))
	# Receding tunnel lamps painted into the dark: small warm dots.
	for index: int in range(4):
		_block(props, "TunnelLampDot", Vector3(0.22 - float(index) * 0.04, 0.06, 0.008), _glow("tunnel_lamp", Color("e8d2a2"), 2.0), Vector3(0, 3.0 - float(index) * 0.32, 44.972))
	_chevrons(props, Vector3(0, 0, 43.5), true, 7.0, 0.35)
	_pool(room, Vector3(0, 5.8, 42.5), 2.6, 7.0, 44.0, 6.8)
	# Warm lamps inside the declaration booths, cold pools over the crest.
	for x: float in [-10.5, 10.5]:
		_lamp(room, Vector3(x, 3.3, 36.5), 1.4, 5.0, 6.8)
	_pool(room, Vector3(0, 5.8, 35.5), 2.4, 7.0, 44.0, 6.8)
	_finish(room)

# --- the apron outside the glass ------------------------------------------------------

func _build_apron() -> void:
	var room: Node3D = _room("Apron")
	var props: Node3D = _props(room)
	var basalt: ShaderMaterial = surface("basalt")
	var dark: StandardMaterial3D = _mat("crane_dark", Color("343839"), 0.4, 0.6)
	# The backdrop's freight gantry beam (x -53, z -26 to -8) gets its safety
	# paint and a working trolley, with a container lowered on the cable.
	for index: int in range(8):
		_block(props, "GantryBeamStripe", Vector3(1.44, 0.84, 1.0), _mat("chevron_ochre", OCHRE), Vector3(-53.0, 5.6, -25.6 + float(index) * 2.45))
	_block(props, "GantryTrolley", Vector3(1.8, 0.6, 1.6), dark, Vector3(-53.0, 4.9, -22.0))
	_shape.rod(props, "GantryCable", Vector3(-53.0, 4.6, -22.0), Vector3(-53.0, 3.4, -22.0), 0.04, dark, 4)
	_block(props, "HangingContainer", Vector3(2.4, 2.2, 5.0), freight_paint(FREIGHT[5]), Vector3(-53.0, 2.3, -22.0))
	for row: Array in [[Vector3(-52.0, 1.3, -38.0), 0], [Vector3(-52.0, 3.9, -38.0), 2], [Vector3(-55.0, 1.3, 6.0), 3], [Vector3(-66.0, 1.3, -25.0), 1], [Vector3(-66.0, 1.3, -9.0), 6]]:
		_block(props, "ApronContainer", Vector3(2.4, 2.6, 6.0), freight_paint(FREIGHT[int(row[1])]), row[0])
	# Landing pad lights and rock outcrops, and a berm of dark basalt.
	for index: int in range(7):
		_block(props, "PadLight", Vector3(0.25, 0.12, 0.25), _glow("pad_light", Color("ffd79a"), 2.4), Vector3(-75.0, 0.06, -40.0 + float(index) * 8.0))
	for row: Array in [[Vector3(-90, 2.4, -50), Vector3(14, 4.8, 9), 0.4], [Vector3(-96, 1.6, 10), Vector3(10, 3.2, 7), -0.3], [Vector3(-84, 1.2, -6), Vector3(6, 2.4, 5), 0.8], [Vector3(70, 2.0, 2), Vector3(12, 4.0, 8), 0.2], [Vector3(84, 2.6, 40), Vector3(14, 5.2, 10), -0.5]]:
		var rock: MeshInstance3D = _block(props, "BasaltOutcrop", row[1], basalt, row[0])
		rock.rotation.y = float(row[2])
	# Tow tracks to the impound cradle beyond the customs glass.
	var track: StandardMaterial3D = _mat("tow_track", Color("6e6a60"), 0.0, 1.0)
	for z: float in [21.6, 25.9]:
		_paint_line(props, Vector3(27.0, -0.005, z), Vector3(56.0, -0.005, z), 0.5, track)
	# A hard, low sun on the apron from the west, and the far side lit softer.
	for row: Array in [[Vector3(-80.0, 18.0, -16.0), 1.6, 40.0]]:
		var sun: OmniLight3D = _omni(room, "ApronSun", row[0], Color(1.0, 0.98, 0.94), float(row[1]), float(row[2]))
		sun.distance_fade_enabled = false
		sun.omni_attenuation = 0.8
	_finish(room)
