class_name M04Dressing
extends Node3D

## Notice to Vacate's golden-slice dressing (docs/campaign/l04-notice-to-vacate.md,
## docs/design/earth.md "M04 Low Water"). The server owns every solid; this
## presenter only furnishes them: flush paint and relief on registered faces,
## small possessions on existing tops, things leaning in a wall's own
## clearance, overhead runs above head height and practical light. A body that
## could stop a pawn or a shot is never added here.
##
## The story is told without words. Low Water is a lived-in street of homes
## over shops, and this afternoon every shutter is coming down. Belongings wait
## on the tram stop bench and at the top of the roof stair. The stalls are half
## packed into their own crates. The clinic is bright, clean and calm, with
## its patients' drawings on the wall. Three test colours are painted on the
## tram for the vote. In the court the meal is still on the table and the
## washing is still on the lines.

const Geometry = preload("res://scripts/model_geometry.gd")
const MAP_ID: int = 1004
const HALF_EXTENT: float = 40.0
const WALL: float = 39.5
const WALL_TOP: float = 8.0
const BAY: float = 3.2
## Worn plaster in Low Water's own colours (docs/design/earth.md): terracotta,
## sage, warm plaster, ochre and umber. Never a matte off-white base.
const PAINTS: Array[Color] = [Color("b0765a"), Color("8fa595"), Color("c4a888"), Color("bf9a60"), Color("ae8778"), Color("9eab8a"), Color("98785f"), Color("7f9a98")]
## Personal colours: curtains, washing and possessions. Warm and varied.
const PERSONAL: Array[Color] = [Color("b5652e"), Color("6f8a4e"), Color("c49a3c"), Color("8a3a58"), Color("4f6f8a"), Color("a8552c"), Color("7c5a8c"), Color("d0b48a")]
const SHUTTERS: Array[Color] = [Color("6f7d76"), Color("7d6c5a"), Color("5f7277"), Color("8a7a52")]
const WARM_LAMP: Color = Color(1.0, 0.8, 0.56)
const CLINIC_LAMP: Color = Color(1.0, 0.93, 0.82)
const KEY_SOLIDS: Array = [
	[Vector3(-3, 0, -17), Vector3(3, 3, -16.5)],
	# The clinic switch post, not the shutter: the shutter is a gate whose
	# solid moves when it opens, and the dressing must survive that MapInfo.
	[Vector3(-22.5, 0, -2.5), Vector3(-22, 2.5, -1)],
	[Vector3(25, 0, -15), Vector3(32, 2.5, -9)],
	[Vector3(-13, 0, 10), Vector3(-5, 0.8, 11.5)],
	[Vector3(-3, 0.7, 27), Vector3(3, 0.9, 30)],
	[Vector3(7, 0, 29), Vector3(9, 1.2, 31)],
	[Vector3(22, 0, -32), Vector3(34, 4, -31.5)],
]

var _shape: RefCounted = Geometry.new()
var _unattached: Array[Node3D] = []
var _paint: Dictionary[String, ShaderMaterial] = {}
## Rooms built for the current map, and the presenter lamps they carry.
var rooms: Array[String] = []
var lamps: int = 0

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

## Notice to Vacate's own authored layout only. A custom map reusing the id
## with different furniture gets no dressing rather than floating props.
static func authored(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != MAP_ID or not info.get("solids") is Array:
		return false
	if not is_equal_approx(float(info.get("half_extent", 0.0)), HALF_EXTENT):
		return false
	var found: int = 0
	for raw: Variant in info["solids"]:
		if not raw is Dictionary:
			continue
		var solid: Dictionary = raw
		var low: Vector3 = Vector3(float(solid.get("min_x", 0.0)), float(solid.get("bottom", 0.0)), float(solid.get("min_z", 0.0)))
		var high: Vector3 = Vector3(float(solid.get("max_x", 0.0)), float(solid.get("top", 0.0)), float(solid.get("max_z", 0.0)))
		for pair: Array in KEY_SOLIDS:
			if low.is_equal_approx(pair[0]) and high.is_equal_approx(pair[1]):
				found += 1
	return found == KEY_SOLIDS.size()

func configure_map(info: Dictionary) -> void:
	if active() and authored(info):
		return
	clear_map()
	if not authored(info):
		return
	_build_streets()
	_build_paving()
	_build_tram_stop()
	_build_square()
	_build_market()
	_build_repair_bench()
	_build_clinic()
	_build_tram_street()
	_build_workshop()
	_build_court()
	_build_roof_exit()
	# Final layers before attachment; see M01Intake for the Forward+ reason.
	for room: Node3D in _unattached:
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

# --- shared builders -------------------------------------------------------

func _room(label: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = label
	_unattached.append(node)
	rooms.append(label)
	return node

## One merged mesh per room keeps draw calls low and each room's light list
## local, which the Compatibility renderer's per-object limit needs.
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

func _mat(key: String, tint: Color, metallic: float = 0.0, roughness: float = 0.85) -> StandardMaterial3D:
	return _shape.material("m04d_" + key, tint, metallic, roughness)

func _glow(key: String, tint: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = _mat(key, tint)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	return material

## Low Water's own plaster, enamel or tile shader in a chosen colour, cached
## per colour so a whole street merges into a handful of surfaces.
func _surface(surface: String, tint: Color, panel: float = 0.0, contrast: float = -1.0) -> ShaderMaterial:
	var key: String = "%s_%s_%.2f_%.2f" % [surface, tint.to_html(false), panel, contrast]
	if _paint.has(key):
		return _paint[key]
	var finish: ShaderMaterial = ArenaMaterials.authored(surface, "low_water") as ShaderMaterial
	finish.set_shader_parameter("surface_color", tint)
	finish.set_shader_parameter("markings_enabled", false)
	finish.set_shader_parameter("tile_strength", 0.3)
	if panel > 0.0:
		finish.set_shader_parameter("panel_size", panel)
	if contrast >= 0.0:
		finish.set_shader_parameter("panel_contrast", contrast)
	_paint[key] = finish
	return finish

## A reviewed environment tile laid in world space, so a large sheet keeps
## the same texel density as the walls around it.
func _tiled(key: String, path: String, tint: Color, metres: float = 2.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = _mat("tiled_%s_%s" % [key, tint.to_html(false)], tint, 0.0, 0.92)
	material.albedo_texture = EnvironmentTextures.texture_at(path)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / metres
	return material

## Painted boards: bench fronts, the tram stop seat, the shed cladding.
func _boards(tint: Color) -> StandardMaterial3D:
	return _tiled("boards", EnvironmentTextures.VENUE_WALLS + "holdfast_painted_boards.png", tint, 1.6)

func _block(props: Node3D, label: String, size: Vector3, finish: Material, at: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = finish
	node.position = at
	props.add_child(node)
	return node

## The basis of a vertical face whose outward normal is `out`.
static func _face(out: Vector3) -> Basis:
	return Basis(Vector3.UP.cross(out).normalized(), Vector3.UP, out)

## A flat sheet flush on a face: paint, glass, posters. Never a body.
func _sheet(props: Node3D, label: String, size: Vector2, finish: Material, at: Vector3, out: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = finish
	node.transform = Transform3D(_face(out) if absf(out.y) < 0.5 else MapDecoration.face_basis("up"), at)
	props.add_child(node)
	return node

## A box standing proud of a face: `size` is along the face, up, and out.
func _relief(props: Node3D, label: String, size: Vector3, finish: Material, at: Vector3, out: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = _block(props, label, size, finish, at + out * size.z * 0.5)
	node.basis = _face(out)
	return node

## Thin flush floor paint or overlay. Large overlays sit lowest, under the
## puddles (ArenaWater.HEIGHT) and the small marks above them.
func _floor(props: Node3D, label: String, low: Vector2, high: Vector2, finish: Material, height: float = 0.008) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = high - low
	node.mesh = mesh
	node.material_override = finish
	node.position = Vector3((low.x + high.x) * 0.5, height, (low.y + high.y) * 0.5)
	props.add_child(node)
	return node

func _omni(room: Node3D, label: String, at: Vector3, colour: Color, energy: float, reach: float) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "%s%d" % [label, lamps]
	light.position = at
	light.light_color = colour
	light.light_energy = energy
	light.light_specular = 0.1
	light.omni_range = reach
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 34.0
	light.distance_fade_length = 8.0
	room.add_child(light)
	lamps += 1
	return light

## A warm bulb under a tin shade on a cable: market, bench and workshop.
func _hanging_lamp(room: Node3D, at: Vector3, cable_to: float, energy: float = 1.4, reach: float = 6.0) -> OmniLight3D:
	var props: Node3D = _props(room)
	var shade: StandardMaterial3D = _mat("tin_shade", Color("5d6a62"), 0.4, 0.6)
	_shape.lathe(props, "LampShade", PackedVector2Array([Vector2(-0.05, 0.0), Vector2(-0.05, 0.08), Vector2(0.0, 0.1), Vector2(0.14, 0.24), Vector2(0.14, 0.0)]), shade, at + Vector3(0, -0.04, 0), 10).rotation.x = PI * 0.5
	_shape.cylinder(props, "LampBulb", 0.05, 0.1, _glow("warm_bulb", Color("ffd79a"), 2.6), at + Vector3(0, -0.12, 0), 8).rotation.x = PI * 0.5
	if cable_to > at.y:
		_shape.rod(props, "LampCable", at + Vector3(0, 0.06, 0), Vector3(at.x, cable_to, at.z), 0.01, _mat("cable", Color("232526"), 0.0, 0.7), 4)
	return _omni(room, "HangingLamp", at + Vector3(0, -0.2, 0), WARM_LAMP, energy, reach)

## A bracket lamp on a wall: bulb in a cage, no light of its own unless asked.
func _wall_lamp(props: Node3D, at: Vector3, out: Vector3) -> void:
	var iron: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	_shape.rod(props, "LampBracket", at, at + out * 0.35 + Vector3(0, 0.12, 0), 0.02, iron, 5)
	_shape.cylinder(props, "LampHood", 0.13, 0.08, iron, at + out * 0.38 + Vector3(0, 0.1, 0), 10).rotation.x = PI * 0.5
	_shape.cylinder(props, "LampGlobe", 0.07, 0.12, _glow("wall_bulb", Color("ffd394"), 2.2), at + out * 0.38, 8).rotation.x = PI * 0.5

## A sagging cable between two points, with optional hanging bulbs.
func _festoon(props: Node3D, from: Vector3, to: Vector3, sag: float, bulbs: int) -> void:
	var points: PackedVector3Array = []
	for step: int in range(13):
		var t: float = float(step) / 12.0
		points.append(from.lerp(to, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0))
	_shape.pipe(props, "Festoon", points, 0.012, _mat("cable", Color("232526"), 0.0, 0.7))
	var bulb: StandardMaterial3D = _glow("festoon_bulb", Color("ffcf86"), 2.4)
	for index: int in range(bulbs):
		var t: float = (float(index) + 0.5) / float(bulbs)
		var at: Vector3 = from.lerp(to, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t) - 0.08, 0)
		_shape.cylinder(props, "FestoonBulb", 0.045, 0.09, bulb, at, 6).rotation.x = PI * 0.5

## A washing line with clothes pegged along it, kept above head height.
func _washing(props: Node3D, from: Vector3, to: Vector3, sag: float, seed_value: int, keep: Vector2 = Vector2(-INF, INF)) -> void:
	var points: PackedVector3Array = []
	for step: int in range(13):
		var t: float = float(step) / 12.0
		points.append(from.lerp(to, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0))
	_shape.pipe(props, "WashingLine", points, 0.008, _mat("line", Color("d9cfb8"), 0.0, 0.9))
	var count: int = int(from.distance_to(to) / 0.8)
	for index: int in range(count):
		if (index * 7 + seed_value) % 5 >= 2:
			continue
		var t: float = (float(index) + 0.5) / float(count)
		var at: Vector3 = from.lerp(to, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0)
		var along: float = at.x if absf(to.x - from.x) > absf(to.z - from.z) else at.z
		if along < keep.x or along > keep.y:
			continue
		var tint: Color = PERSONAL[(index * 3 + seed_value) % PERSONAL.size()].lerp(Color("cfc6b0"), 0.35)
		var tall: float = 0.3 + float((index + seed_value) % 3) * 0.14
		var wide: float = 0.3 + float((index * 5 + seed_value) % 3) * 0.1
		var cloth: MeshInstance3D = _block(props, "Washing", Vector3(wide, tall, 0.02), _mat("washing_%s" % tint.to_html(false), tint, 0.0, 0.95), at + Vector3(0, -tall * 0.5, 0))
		cloth.basis = Basis(Vector3.UP, atan2(to.x - from.x, to.z - from.z) + PI * 0.5)

func _crate(props: Node3D, at: Vector3, size: Vector3, tint: Color = Color("8d6c43"), yaw: float = 0.0) -> void:
	var wood: StandardMaterial3D = _mat("crate_%s" % tint.to_html(false), tint, 0.0, 0.9)
	var slat: StandardMaterial3D = _mat("crate_slat_%s" % tint.to_html(false), tint.darkened(0.25), 0.0, 0.9)
	var box: MeshInstance3D = _block(props, "Crate", size, wood, at + Vector3(0, size.y * 0.5, 0))
	box.rotation.y = yaw
	var band: MeshInstance3D = _block(props, "CrateBand", Vector3(size.x + 0.01, 0.05, size.z + 0.01), slat, at + Vector3(0, size.y * 0.72, 0))
	band.rotation.y = yaw
	var low: MeshInstance3D = _block(props, "CrateBand", Vector3(size.x + 0.01, 0.05, size.z + 0.01), slat, at + Vector3(0, size.y * 0.25, 0))
	low.rotation.y = yaw

## A tied bundle of belongings: cloth over a soft shape, a strap around it.
func _bundle(props: Node3D, at: Vector3, size: Vector3, tint: Color, yaw: float = 0.0) -> void:
	var cloth: StandardMaterial3D = _mat("bundle_%s" % tint.to_html(false), tint, 0.0, 0.95)
	var strap: StandardMaterial3D = _mat("strap", Color("4a3626"), 0.0, 0.8)
	var body: MeshInstance3D = _shape.hull(props, "Bundle", PackedVector3Array([Vector3(0, size.x * 0.3, size.z * 0.3), Vector3(size.y * 0.15, size.x * 0.5, size.z * 0.5), Vector3(size.y * 0.85, size.x * 0.5, size.z * 0.5), Vector3(size.y, size.x * 0.25, size.z * 0.3)]), cloth, at, 10)
	body.rotation.y = yaw
	var tie: MeshInstance3D = _block(props, "BundleStrap", Vector3(size.x + 0.02, 0.04, 0.06), strap, at + Vector3(0, size.y * 0.5, 0))
	tie.rotation.y = yaw

## A hard suitcase with a handle, standing or lying.
func _suitcase(props: Node3D, at: Vector3, size: Vector3, tint: Color, yaw: float = 0.0) -> void:
	var shell: StandardMaterial3D = _mat("case_%s" % tint.to_html(false), tint, 0.1, 0.7)
	var trim: StandardMaterial3D = _mat("case_trim", Color("3a3330"), 0.3, 0.6)
	var body: MeshInstance3D = _block(props, "Suitcase", size, shell, at + Vector3(0, size.y * 0.5, 0))
	body.rotation.y = yaw
	var rim: MeshInstance3D = _block(props, "SuitcaseRim", Vector3(size.x + 0.01, 0.03, size.z + 0.01), trim, at + Vector3(0, size.y * 0.5, 0))
	rim.rotation.y = yaw
	var handle: MeshInstance3D = _block(props, "SuitcaseHandle", Vector3(0.16, 0.04, 0.03), trim, at + Vector3(0, size.y + 0.02, 0))
	handle.rotation.y = yaw

func _pot_plant(props: Node3D, at: Vector3, scale_value: float, seed_value: int) -> void:
	var clay: StandardMaterial3D = _mat("terracotta_pot", Color("a76343"), 0.0, 0.8)
	var leaf: StandardMaterial3D = _mat("leaf_%d" % (seed_value % 3), [Color("5e7a44"), Color("74884e"), Color("4f6a3c")][seed_value % 3], 0.0, 0.9)
	_shape.lathe(props, "PlantPot", PackedVector2Array([Vector2(0.0, 0.1 * scale_value), Vector2(0.24 * scale_value, 0.13 * scale_value), Vector2(0.28 * scale_value, 0.16 * scale_value), Vector2(0.28 * scale_value, 0.0)]), clay, at, 10).rotation.x = -PI * 0.5
	for index: int in range(5):
		var angle: float = TAU * float(index + seed_value) / 5.0
		var tip: Vector3 = at + Vector3(cos(angle) * 0.2 * scale_value, (0.42 + float((index + seed_value) % 3) * 0.08) * scale_value, sin(angle) * 0.2 * scale_value)
		var blade: MeshInstance3D = _block(props, "Leaf", Vector3(0.12, 0.2, 0.05) * scale_value, leaf, tip)
		blade.basis = Basis.looking_at(Vector3(cos(angle), 0.6, sin(angle)).normalized(), Vector3.UP)
	_block(props, "Foliage", Vector3(0.28, 0.22, 0.28) * scale_value, leaf, at + Vector3(0, 0.38 * scale_value, 0))

# --- the street: homes over shops on every boundary face ----------------------

func _build_streets() -> void:
	# Each boundary wall becomes a row of homes over shops (docs/design/earth.md
	# "homes above repair stalls"). Shops have their shutters down today.
	var south: Node3D = _room("StreetSouth")
	_facade(_props(south), Vector3(WALL, 0, -WALL), Vector3.LEFT, Vector3.BACK, WALL * 2.0, WALL_TOP, 3, true)
	_finish(south)
	var north: Node3D = _room("StreetNorth")
	_facade(_props(north), Vector3(-WALL, 0, WALL), Vector3.RIGHT, Vector3.FORWARD, WALL * 2.0, WALL_TOP, 11, true)
	_finish(north)
	var west: Node3D = _room("StreetWest")
	_facade(_props(west), Vector3(-WALL, 0, -WALL), Vector3.BACK, Vector3.RIGHT, WALL * 2.0, WALL_TOP, 5, true)
	_finish(west)
	var east: Node3D = _room("StreetEast")
	var props: Node3D = _props(east)
	_facade(props, Vector3(WALL, 0, WALL), Vector3.FORWARD, Vector3.LEFT, WALL * 2.0, WALL_TOP, 8, true, Vector2(WALL + 9.4, WALL + 14.6))
	# The tram's tunnel portal where the rails leave the district.
	var dark: StandardMaterial3D = _mat("portal_dark", Color("15171a"), 0.0, 1.0)
	var stone: StandardMaterial3D = _mat("portal_stone", Color("8f8273"), 0.0, 0.9)
	_sheet(props, "TramPortal", Vector2(5.0, 3.9), dark, Vector3(WALL - 0.015, 1.95, -12.0), Vector3.LEFT)
	_relief(props, "PortalLintel", Vector3(5.8, 0.5, 0.14), stone, Vector3(WALL, 4.15, -12.0), Vector3.LEFT)
	for side: float in [-1.0, 1.0]:
		_relief(props, "PortalJamb", Vector3(0.4, 3.9, 0.12), stone, Vector3(WALL, 1.95, -12.0 + side * 2.7), Vector3.LEFT)
	_finish(east)

## One row of buildings along a wall face. `origin` is the face at ground at
## the start of the run, `along` the run direction and `out` the face normal.
## `skip` keeps a stretch of the ground floor clear (a portal).
func _facade(props: Node3D, origin: Vector3, along: Vector3, out: Vector3, length: float, top: float, seed_value: int, upper: bool, skip: Vector2 = Vector2(INF, -INF)) -> void:
	var widths: Array[float] = [9.6, 6.4, 12.8, 6.4, 9.6, 3.2 * 2.0]
	var start: float = 0.0
	var building: int = 0
	var iron: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	var pipe: StandardMaterial3D = _mat("drainpipe", Color("4f5a55"), 0.3, 0.6)
	while start < length - 0.5:
		var width: float = minf(widths[(building + seed_value) % widths.size()], length - start)
		var tint: Color = PAINTS[(building * 3 + seed_value) % PAINTS.size()]
		var height: float = top - float((building + seed_value) % 3) * 0.35
		var middle: float = start + width * 0.5
		var centre: Vector3 = origin + along * middle
		# Broad plaster in the building's own colour, then a darker plinth.
		_sheet(props, "FacadePaint", Vector2(width - 0.02, height), _surface("enamel", tint), centre + Vector3(0, height * 0.5, 0) + out * 0.012, out)
		_sheet(props, "FacadePlinth", Vector2(width - 0.02, 0.45), _surface("concrete", tint.darkened(0.35)), centre + Vector3(0, 0.225, 0) + out * 0.016, out)
		_relief(props, "Parapet", Vector3(width, 0.16, 0.14), _mat("parapet_%s" % tint.to_html(false), tint.darkened(0.15)), centre + Vector3(0, height - 0.08, 0), out)
		if upper:
			_relief(props, "Cornice", Vector3(width, 0.14, 0.12), _mat("cornice_%s" % tint.to_html(false), tint.lightened(0.12)), centre + Vector3(0, 3.3, 0), out)
		var bays: int = maxi(1, int(round(width / BAY)))
		var bay_width: float = width / float(bays)
		for bay: int in range(bays):
			var s: float = start + bay_width * (float(bay) + 0.5)
			var hash_value: int = (seed_value * 7 + building * 13 + bay * 5) % 12
			var at: Vector3 = origin + along * s
			var clear: bool = s < skip.x - 1.6 or s > skip.y + 1.6
			if clear:
				_ground_bay(props, at, out, bay_width, hash_value, tint)
			if upper:
				if clear:
					_window(props, at + Vector3(0, 4.35, 0), out, Vector2(1.1, 1.4), hash_value, tint)
				if height > 7.0:
					_window(props, at + Vector3(0, 6.55, 0), out, Vector2(0.9, 0.85), hash_value + 5, tint)
				if hash_value == 7 and clear:
					_balcony(props, at + Vector3(0, 3.5, 0), out, hash_value + building)
		if building % 3 == 1 and upper:
			_wall_lamp(props, origin + along * (start + 0.6) + Vector3(0, 3.0, 0) + out * 0.02, out)
		# A downpipe at the party wall.
		var edge: Vector3 = origin + along * (start + width) + out * 0.09
		if start + width < length - 0.5:
			_shape.rod(props, "Downpipe", edge + Vector3(0, height - 0.15, 0), edge + Vector3(0, 0.2, 0), 0.05, pipe, 6)
			_shape.rod(props, "DownpipeShoe", edge + Vector3(0, 0.2, 0), edge + out * 0.16 + Vector3(0, 0.06, 0), 0.05, pipe, 6)
			for bracket: float in [1.5, 3.8, 6.2]:
				if bracket < height:
					_relief(props, "PipeClip", Vector3(0.14, 0.04, 0.09), iron, edge - out * 0.09 + Vector3(0, bracket, 0), out)
		start += width
		building += 1

## The ground floor of one bay: a shop shutter pulled down, a door, a shop
## window or a window boarded for leaving.
func _ground_bay(props: Node3D, at: Vector3, out: Vector3, width: float, hash_value: int, tint: Color) -> void:
	var frame: StandardMaterial3D = _mat("frame_dark", Color("3b3430"), 0.0, 0.8)
	var wood: StandardMaterial3D = _mat("door_wood", Color("6e4e34"), 0.0, 0.85)
	var glass: StandardMaterial3D = _mat("glass_dark", Color("2b3634"), 0.2, 0.35)
	var side: Vector3 = Vector3.UP.cross(out).normalized()
	match hash_value % 6:
		0, 1, 4:
			var steel: Color = SHUTTERS[hash_value % SHUTTERS.size()]
			var shutter_width: float = minf(width - 0.6, 2.6)
			_sheet(props, "ShutterFrame", Vector2(shutter_width + 0.24, 2.62), frame, at + Vector3(0, 1.31, 0) + out * 0.02, out)
			_sheet(props, "Shutter", Vector2(shutter_width, 2.45), _surface("service_steel", steel, 0.25, 0.6), at + Vector3(0, 1.25, 0) + out * 0.026, out)
			var slat: StandardMaterial3D = _mat("shutter_slat_%s" % steel.to_html(false), steel.darkened(0.3), 0.3, 0.6)
			for row: int in range(6):
				_relief(props, "ShutterSlat", Vector3(shutter_width, 0.035, 0.012), slat, at + Vector3(0, 0.3 + float(row) * 0.4, 0) + out * 0.026, out)
			_relief(props, "ShutterBox", Vector3(shutter_width + 0.3, 0.28, 0.22), _mat("shutter_box", steel.darkened(0.15), 0.3, 0.6), at + Vector3(0, 2.75, 0), out)
			_relief(props, "Padlock", Vector3(0.08, 0.1, 0.05), _mat("brass", Color("9a7d3e"), 0.6, 0.4), at + Vector3(0.0, 0.12, 0) + out * 0.03, out)
			if hash_value == 4:
				# A canvas awning rolled tight over the closed shop.
				var canvas: StandardMaterial3D = _mat("awning_roll_%d" % (hash_value % 4), PERSONAL[(hash_value * 3) % PERSONAL.size()], 0.0, 0.95)
				var roll: MeshInstance3D = _shape.cylinder(props, "AwningRoll", 0.11, shutter_width + 0.2, canvas, at + Vector3(0, 3.05, 0) + out * 0.2, 10)
				roll.basis = Basis(Quaternion(Vector3.BACK, side))
		2, 5:
			# A shop window with a door beside it; the window is lit within.
			var lit: bool = hash_value == 5
			_sheet(props, "ShopFrame", Vector2(1.75, 1.55), frame, at + Vector3(0, 1.55, 0) + side * -0.45 + out * 0.02, out)
			_sheet(props, "ShopGlass", Vector2(1.55, 1.35), _glow("shop_lit", Color("d9a466"), 0.7) if lit else glass, at + Vector3(0, 1.55, 0) + side * -0.45 + out * 0.026, out)
			_relief(props, "ShopSill", Vector3(1.8, 0.08, 0.16), _mat("sill_%s" % tint.to_html(false), tint.lightened(0.15)), at + Vector3(0, 0.82, 0) + side * -0.45, out)
			_sheet(props, "DoorFrame", Vector2(1.0, 2.25), frame, at + Vector3(0, 1.125, 0) + side * 0.95 + out * 0.02, out)
			_sheet(props, "Door", Vector2(0.86, 2.15), wood, at + Vector3(0, 1.075, 0) + side * 0.95 + out * 0.028, out)
			_relief(props, "DoorStep", Vector3(1.1, 0.06, 0.26), _mat("step_stone", Color("8d8577")), at + Vector3(0, 0.03, 0) + side * 0.95, out)
		3:
			_sheet(props, "DoorFrame", Vector2(1.1, 2.35), frame, at + Vector3(0, 1.175, 0) + out * 0.02, out)
			_sheet(props, "Door", Vector2(0.95, 2.2), _mat("door_paint_%d" % (hash_value % 3), PERSONAL[(hash_value + 2) % PERSONAL.size()].darkened(0.2), 0.0, 0.8), at + Vector3(0, 1.1, 0) + out * 0.028, out)
			_relief(props, "DoorStep", Vector3(1.2, 0.06, 0.26), _mat("step_stone", Color("8d8577")), at + Vector3(0, 0.03, 0), out)
			_sheet(props, "Fanlight", Vector2(0.95, 0.3), glass, at + Vector3(0, 2.5, 0) + out * 0.026, out)
	if hash_value % 6 == 3 or hash_value == 11:
		# Boarded for leaving: planks nailed across a ground window.
		var plank: StandardMaterial3D = _mat("plank", Color("8b6c48"), 0.0, 0.9)
		var spot: Vector3 = at + side * (width * 0.5 - 0.8) + Vector3(0, 1.5, 0)
		_sheet(props, "BoardedGlass", Vector2(1.0, 1.2), glass, spot + out * 0.02, out)
		for index: int in range(3):
			var board: MeshInstance3D = _relief(props, "Board", Vector3(1.25, 0.16, 0.03), plank, spot + Vector3(0, -0.4 + float(index) * 0.4, 0), out)
			board.rotate_object_local(Vector3.BACK, float(index - 1) * 0.12)

## An upper window: dark or lit glass, frame, sill, curtains and sometimes
## open shutters, a flower box or a heat exchanger.
func _window(props: Node3D, at: Vector3, out: Vector3, size: Vector2, hash_value: int, tint: Color) -> void:
	var frame: StandardMaterial3D = _mat("window_frame", Color("e0d3b8").darkened(0.15), 0.0, 0.8)
	var side: Vector3 = Vector3.UP.cross(out).normalized()
	var lit: bool = hash_value % 5 == 1
	var glass: Material = _glow("window_lit", Color("e9b874"), 0.55) if lit else _mat("glass_dark", Color("2b3634"), 0.2, 0.35)
	_sheet(props, "WindowGlass", size, glass, at + out * 0.02, out)
	var curtain: StandardMaterial3D = _mat("curtain_%d" % (hash_value % PERSONAL.size()), PERSONAL[hash_value % PERSONAL.size()].lightened(0.1), 0.0, 0.95)
	for edge: float in [-1.0, 1.0]:
		_sheet(props, "Curtain", Vector2(size.x * 0.24, size.y * 0.92), curtain, at + side * edge * size.x * 0.36 + out * 0.024, out)
		_relief(props, "WindowFrame", Vector3(0.07, size.y + 0.1, 0.05), frame, at + side * edge * (size.x * 0.5 + 0.03), out)
	_relief(props, "WindowHead", Vector3(size.x + 0.2, 0.08, 0.06), frame, at + Vector3(0, size.y * 0.5 + 0.04, 0), out)
	_relief(props, "WindowSill", Vector3(size.x + 0.26, 0.07, 0.15), frame, at + Vector3(0, -size.y * 0.5 - 0.03, 0), out)
	if hash_value % 3 == 0:
		var leaf: StandardMaterial3D = _mat("window_shutter_%d" % (hash_value % 4), [Color("6f8a6a"), Color("8a6a4a"), Color("5e7a86"), Color("9a7a52")][hash_value % 4], 0.0, 0.85)
		for edge: float in [-1.0, 1.0]:
			_relief(props, "WindowShutter", Vector3(size.x * 0.5, size.y, 0.03), leaf, at + side * edge * (size.x * 0.78), out)
	if hash_value % 4 == 1:
		var box: StandardMaterial3D = _mat("flower_box", Color("7a5a3a"), 0.0, 0.85)
		var green: StandardMaterial3D = _mat("box_green", Color("5f7a45"), 0.0, 0.9)
		var bloom: StandardMaterial3D = _mat("box_bloom_%d" % (hash_value % 3), [Color("c4703a"), Color("c9a23c"), Color("a64a5a")][hash_value % 3], 0.0, 0.9)
		_relief(props, "FlowerBox", Vector3(size.x, 0.18, 0.22), box, at + Vector3(0, -size.y * 0.5 - 0.16, 0), out)
		for index: int in range(4):
			var spot: Vector3 = at + side * (-size.x * 0.36 + float(index) * size.x * 0.24) + Vector3(0, -size.y * 0.5 - 0.02, 0) + out * 0.12
			_block(props, "BoxGreen", Vector3(0.18, 0.16, 0.14), green if index % 2 == 0 else bloom, spot)
	elif hash_value % 4 == 2 and size.y > 1.0:
		_relief(props, "HeatBox", Vector3(0.6, 0.42, 0.3), _mat("heat_box", Color("9a9a8e"), 0.3, 0.6), at + side * size.x * 0.2 + Vector3(0, -size.y * 0.5 - 0.42, 0), out)

## A shallow balcony slab with railings, a pot and something airing.
func _balcony(props: Node3D, at: Vector3, out: Vector3, seed_value: int) -> void:
	var iron: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	var slab: StandardMaterial3D = _mat("balcony_slab", Color("8e8576"), 0.0, 0.9)
	var side: Vector3 = Vector3.UP.cross(out).normalized()
	_relief(props, "BalconySlab", Vector3(2.0, 0.12, 0.7), slab, at, out)
	for index: int in range(9):
		var post: Vector3 = at + side * (-0.95 + float(index) * 0.2375) + out * 0.66
		_shape.rod(props, "BalconyPost", post + Vector3(0, 0.06, 0), post + Vector3(0, 0.95, 0), 0.012, iron, 4)
	_shape.rod(props, "BalconyRail", at + side * -0.98 + out * 0.66 + Vector3(0, 0.95, 0), at + side * 0.98 + out * 0.66 + Vector3(0, 0.95, 0), 0.02, iron, 5)
	var rug: Color = PERSONAL[seed_value % PERSONAL.size()]
	_relief(props, "AiringRug", Vector3(1.0, 0.6, 0.02), _mat("rug_%s" % rug.to_html(false), rug, 0.0, 0.95), at + Vector3(0, 0.66, 0) + out * 0.67 + side * 0.3, out)
	_pot_plant(props, at + Vector3(0, 0.06, 0) + out * 0.3 + side * -0.65, 0.8, seed_value)

# --- paving: the district's ground, broken into its uses ----------------------

func _build_paving() -> void:
	var room: Node3D = _room("Paving")
	var props: Node3D = _props(room)
	# Setts: small warm stones laid across the square and the market, so the
	# town floor reads as a street rather than one poured slab.
	_floor(props, "Setts", Vector2(-22.0, -35.6), Vector2(WALL - 0.02, 15.98), _surface("concrete", Color("847a6d"), 0.5, 0.85))
	# A darker worn band where everyone walks from the stop to the board.
	_floor(props, "WornPath", Vector2(-2.2, -35.6), Vector2(2.2, -17.0), _surface("concrete", Color("6f675d"), 0.5, 0.7), 0.0085)
	_floor(props, "WorkshopSlab", Vector2(22.5, -31.5), Vector2(33.5, -18.5), _surface("concrete", Color("6a6760"), 4.0, 0.3), 0.009)
	# The tram street: dark worn asphalt with the rails set in it.
	_floor(props, "TramStreet", Vector2(14.0, -17.0), Vector2(WALL - 0.02, -7.5), _surface("concrete", Color("5c5a55"), 4.0, 0.25), 0.009)
	_floor(props, "StopKerb", Vector2(-WALL + 0.02, -36.2), Vector2(WALL - 0.02, -35.75), _surface("concrete", Color("b6ab95"), 1.0, 0.6), 0.009)
	_floor(props, "StopLine", Vector2(-WALL + 0.02, -39.48), Vector2(WALL - 0.02, -36.2), _surface("concrete", Color("5f5d57"), 4.0, 0.25))
	# The habitation court: terracotta tile everyone has swept.
	_floor(props, "CourtTile", Vector2(-19.5, 17.0), Vector2(19.5, 39.0), _surface("concrete", Color("9a7462"), 1.0, 0.6))
	# The clinic: pale sage tile, the cleanest floor in the district.
	_floor(props, "ClinicTile", Vector2(-34.5, -7.5), Vector2(-22.5, 13.5), _tiled("clinic_floor", EnvironmentTextures.EARTH + "earth_intake_green_tile.png", Color("eef0e2"), 2.0))
	var rail: StandardMaterial3D = _mat("rail_steel", Color("8e8f8a"), 0.7, 0.35)
	var groove: StandardMaterial3D = _mat("rail_groove", Color("2a2928"), 0.0, 1.0)
	for z: float in [-13.2, -10.8]:
		_floor(props, "TramRail", Vector2(14.0, z - 0.04), Vector2(WALL - 0.02, z + 0.04), rail, 0.012)
		_floor(props, "RailGroove", Vector2(14.0, z + 0.04), Vector2(WALL - 0.02, z + 0.1), groove, 0.011)
	for z: float in [-38.4, -37.0]:
		_floor(props, "StopRail", Vector2(-WALL + 0.02, z - 0.04), Vector2(WALL - 0.02, z + 0.04), rail, 0.012)
		_floor(props, "RailGroove", Vector2(-WALL + 0.02, z + 0.04), Vector2(WALL - 0.02, z + 0.1), groove, 0.011)
	# A painted platform edge line along the stop.
	_floor(props, "PlatformLine", Vector2(-WALL + 0.02, -35.72), Vector2(WALL - 0.02, -35.6), _mat("road_paint", Color("c9a23c"), 0.0, 0.9), 0.011)
	# Drains, covers and the gutter channel down the middle of the market.
	var channel: StandardMaterial3D = _mat("gutter", Color("4b4a46"), 0.0, 0.9)
	_floor(props, "Gutter", Vector2(-0.18, -9.5), Vector2(0.18, 15.5), channel, 0.011)
	for at: Vector2 in [Vector2(0, -8), Vector2(0, 1), Vector2(0, 13), Vector2(-14, -13.5), Vector2(16, -20), Vector2(-11, 21), Vector2(4, 33)]:
		_drain(props, Vector3(at.x, 0.0, at.y))
	for at: Vector2 in [Vector2(-10, -24), Vector2(9, -27), Vector2(30, 6), Vector2(-14, 14)]:
		_manhole(props, Vector3(at.x, 0.0, at.y))
	# Leaflets of the notice, dropped and trodden in across the square.
	var leaflet: StandardMaterial3D = _mat("leaflet", Color("e2dccb"), 0.0, 0.95)
	for index: int in range(26):
		var x: float = -12.0 + fmod(float(index) * 7.37, 24.0)
		var z: float = -30.0 + fmod(float(index) * 4.91, 20.0)
		var sheet: MeshInstance3D = _floor(props, "Leaflet", Vector2(x - 0.11, z - 0.15), Vector2(x + 0.11, z + 0.15), leaflet, 0.013)
		sheet.rotation.y = float(index) * 1.31
	# Chalk squares a child drew in the court, and wheel ruts by the tram.
	var chalk: StandardMaterial3D = _mat("chalk", Color("e6dfcc"), 0.0, 0.95)
	for index: int in range(7):
		var z: float = 18.5 + float(index) * 0.7
		for x: float in ([-1.5] if index % 3 != 1 else [-1.85, -1.15]):
			var low: Vector2 = Vector2(x - 0.35, z)
			var high: Vector2 = Vector2(x + 0.35, z + 0.7)
			_floor(props, "Chalk", low, Vector2(low.x + 0.04, high.y), chalk, 0.013)
			_floor(props, "Chalk", Vector2(high.x - 0.04, low.y), high, chalk, 0.013)
			_floor(props, "Chalk", low, Vector2(high.x, low.y + 0.04), chalk, 0.013)
			_floor(props, "Chalk", Vector2(low.x, high.y - 0.04), high, chalk, 0.013)
	_finish(room)

func _drain(props: Node3D, at: Vector3) -> void:
	var grate: StandardMaterial3D = _mat("drain_grate", Color("1c1d1f"), 0.5, 0.6)
	var bar: StandardMaterial3D = _mat("drain_bar", Color("55534c"), 0.6, 0.5)
	_block(props, "Drain", Vector3(0.6, 0.006, 0.4), grate, at + Vector3(0, 0.012, 0))
	for index: int in range(6):
		_block(props, "DrainBar", Vector3(0.04, 0.008, 0.36), bar, at + Vector3(-0.25 + float(index) * 0.1, 0.014, 0))

func _manhole(props: Node3D, at: Vector3) -> void:
	var iron: StandardMaterial3D = _mat("manhole", Color("3d3b37"), 0.6, 0.55)
	var ring: StandardMaterial3D = _mat("manhole_ring", Color("26262a"), 0.5, 0.6)
	_shape.cylinder(props, "ManholeRing", 0.42, 0.006, ring, at + Vector3(0, 0.011, 0), 16).rotation.x = PI * 0.5
	_shape.cylinder(props, "Manhole", 0.36, 0.006, iron, at + Vector3(0, 0.013, 0), 16).rotation.x = PI * 0.5

# --- the tram stop: belongings waiting for a tram ----------------------------

func _build_tram_stop() -> void:
	var room: Node3D = _room("TramStop")
	var props: Node3D = _props(room)
	var top: float = 0.8
	# The stop's seat is slatted boards on all sides.
	for face: Array in [[Vector3.FORWARD, 4.0, Vector3(-5, 0, -35)], [Vector3.BACK, 4.0, Vector3(-5, 0, -33)], [Vector3.LEFT, 2.0, Vector3(-7, 0, -34)], [Vector3.RIGHT, 2.0, Vector3(-3, 0, -34)]]:
		var out: Vector3 = face[0]
		_sheet(props, "SeatBoards", Vector2(float(face[1]) - 0.02, top - 0.02), _boards(Color("8d7a62")), (face[2] as Vector3) + Vector3(0, top * 0.5, 0) + out * 0.006, out)
	_floor(props, "SeatTop", Vector2(-6.99, -34.99), Vector2(-3.01, -33.01), _boards(Color("8d7a62")), top + 0.004)
	# On the bench (-7..-3, z -35..-33): suitcases, a tied bundle, a birdcage,
	# a lamp with its shade still on and a box of plates.
	_suitcase(props, Vector3(-6.4, top, -34.4), Vector3(0.62, 0.42, 0.22), Color("7a3a22"), 0.1)
	_suitcase(props, Vector3(-5.7, top, -33.7), Vector3(0.5, 0.2, 0.36), Color("4f6f8a"), -0.2)
	_bundle(props, Vector3(-4.9, top, -34.3), Vector3(0.5, 0.45, 0.4), PERSONAL[3], 0.3)
	_crate(props, Vector3(-3.7, top, -33.8), Vector3(0.5, 0.32, 0.4), Color("9a7a52"), 0.15)
	var plate: StandardMaterial3D = _mat("plate", Color("d8cfb6"), 0.0, 0.5)
	for index: int in range(4):
		_shape.cylinder(props, "Plate", 0.12, 0.02, plate, Vector3(-3.75 + float(index % 2) * 0.12, top + 0.34 + float(index) * 0.022, -33.8), 12).rotation.x = PI * 0.5
	var wire: StandardMaterial3D = _mat("cage_wire", Color("b39a5e"), 0.6, 0.4)
	var cage: Vector3 = Vector3(-4.3, top, -34.55)
	for index: int in range(8):
		var angle: float = TAU * float(index) / 8.0
		_shape.rod(props, "CageWire", cage + Vector3(cos(angle) * 0.14, 0.02, sin(angle) * 0.14), cage + Vector3(cos(angle) * 0.08, 0.42, sin(angle) * 0.08), 0.006, wire, 3)
	_shape.cylinder(props, "CageBase", 0.16, 0.04, _mat("cage_base", Color("6e4e34")), cage + Vector3(0, 0.02, 0), 10).rotation.x = PI * 0.5
	var lamp: Vector3 = Vector3(-6.75, top, -33.5)
	_shape.cylinder(props, "StandardLampPole", 0.02, 0.9, _mat("brass", Color("9a7d3e"), 0.6, 0.4), lamp + Vector3(0, 0.45, 0), 6).rotation.x = PI * 0.5
	_shape.lathe(props, "StandardLampShade", PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.0, 0.16), Vector2(0.2, 0.1), Vector2(0.2, 0.0)]), _mat("shade_cloth", Color("c49a3c"), 0.0, 0.95), lamp + Vector3(0, 0.75, 0), 10).rotation.x = -PI * 0.5
	# Against the court's market wall, inside its clearance: a rolled
	# mattress, a bicycle and boxes carried down from the homes above.
	var face: float = 16.0
	_bundle(props, Vector3(-15.5, 0.0, face - 0.33), Vector3(1.6, 0.5, 0.5), Color("bcae8e"), PI * 0.5)
	_crate(props, Vector3(-17.4, 0.0, face - 0.3), Vector3(0.7, 0.55, 0.5), Color("8d6c43"))
	_crate(props, Vector3(-17.4, 0.55, face - 0.3), Vector3(0.55, 0.4, 0.45), Color("9a7a52"), 0.12)
	_bicycle(props, Vector3(11.0, 0.0, face - 0.22), Vector3.RIGHT, PERSONAL[5])
	_crate(props, Vector3(14.0, 0.0, face - 0.3), Vector3(0.8, 0.6, 0.5), Color("7a6a50"))
	_suitcase(props, Vector3(14.9, 0.0, face - 0.18), Vector3(0.6, 0.7, 0.24), Color("6f8a4e"))
	_finish(room)

## A bicycle leaning flat against a wall: two wheels and a frame, no body.
func _bicycle(props: Node3D, at: Vector3, along: Vector3, paint: Color) -> void:
	var tyre: StandardMaterial3D = _mat("tyre", Color("1d1d1f"), 0.0, 0.9)
	var frame: StandardMaterial3D = _mat("bike_%s" % paint.to_html(false), paint, 0.3, 0.5)
	var front: Vector3 = at + along * 0.52 + Vector3(0, 0.34, 0)
	var back: Vector3 = at - along * 0.52 + Vector3(0, 0.34, 0)
	for wheel: Vector3 in [front, back]:
		var points: PackedVector3Array = []
		for step: int in range(17):
			var angle: float = TAU * float(step) / 16.0
			points.append(wheel + along * cos(angle) * 0.33 + Vector3(0, sin(angle) * 0.33, 0))
		_shape.pipe(props, "Wheel", points, 0.022, tyre)
	var seat: Vector3 = at - along * 0.15 + Vector3(0, 0.85, 0)
	var bars: Vector3 = at + along * 0.4 + Vector3(0, 0.95, 0)
	var crank: Vector3 = at + Vector3(0, 0.32, 0)
	for pair: Array in [[back, crank], [crank, seat], [seat, back], [crank, bars], [seat, bars], [bars, front]]:
		_shape.rod(props, "BikeFrame", pair[0], pair[1], 0.018, frame, 5)
	var saddle: MeshInstance3D = _block(props, "Saddle", Vector3(0.22, 0.05, 0.1), _mat("saddle", Color("3a2a20")), seat + Vector3(0, 0.04, 0))
	saddle.basis = Basis(Vector3.UP, atan2(along.x, along.z) + PI * 0.5)

# --- the square: the notice board --------------------------------------------

func _build_square() -> void:
	var room: Node3D = _room("Square")
	var props: Node3D = _props(room)
	# The board (-3..3, z -17..-16.5). On its back, facing the market, the
	# neighbourhood's own pinned papers: drawings, a lost cat, lessons offered.
	var back: Vector3 = Vector3(0, 0, -16.5)
	var papers: Array[Color] = [Color("e2dccb"), Color("d8c9a0"), Color("c9d6c0"), Color("e6c9b0"), Color("d0d8dc")]
	for index: int in range(14):
		var x: float = -2.5 + fmod(float(index) * 1.73, 5.0)
		var y: float = 0.55 + fmod(float(index) * 0.67, 2.1)
		var size: Vector2 = Vector2(0.32 + float(index % 3) * 0.08, 0.42 + float(index % 2) * 0.1)
		var sheet: MeshInstance3D = _sheet(props, "PinnedPaper", size, _mat("paper_%d" % (index % papers.size()), papers[index % papers.size()], 0.0, 0.95), back + Vector3(x, y, 0.008 + float(index) * 0.0004), Vector3.BACK)
		sheet.rotate_object_local(Vector3.BACK, float(index % 5 - 2) * 0.06)
		# A small drawing on some: a coloured shape, never words.
		if index % 3 == 0:
			_sheet(props, "Drawing", size * 0.45, _mat("drawing_%d" % (index % PERSONAL.size()), PERSONAL[index % PERSONAL.size()], 0.0, 0.9), back + Vector3(x, y + 0.04, 0.0145 + float(index) * 0.0004), Vector3.BACK)
		_block(props, "Pin", Vector3(0.03, 0.03, 0.02), _mat("pin_red", Color("a64a3a")), back + Vector3(x, y + size.y * 0.42, 0.02))
	# On the front, the old notices the new one was pasted over, torn at the
	# edges, and a small Union seal stamped at the top.
	var front: Vector3 = Vector3(0, 0, -17.0)
	for index: int in range(8):
		var x: float = -2.85 if index % 2 == 0 else 2.85
		var y: float = 0.4 + floorf(float(index) / 2.0) * 0.7
		_sheet(props, "OldNotice", Vector2(0.24, 0.5), _mat("old_notice", Color("bdb59c"), 0.0, 0.95), front + Vector3(x, y, -0.006), Vector3.FORWARD)
	_sheet(props, "UnionSeal", Vector2(0.3, 0.3), _seal_material(), front + Vector3(2.35, 0.42, -0.012), Vector3.FORWARD)
	# The Clerk's paste bucket and brush at the board's foot, in its clearance.
	var bucket: StandardMaterial3D = _mat("paste_bucket", Color("2c2d32"), 0.4, 0.5)
	_shape.lathe(props, "PasteBucket", PackedVector2Array([Vector2(0.0, 0.13), Vector2(0.3, 0.15), Vector2(0.3, 0.0)]), bucket, Vector3(3.35, 0.0, -17.25), 12).rotation.x = -PI * 0.5
	_shape.cylinder(props, "Paste", 0.135, 0.01, _mat("paste", Color("d7d2bf"), 0.0, 0.4), Vector3(3.35, 0.27, -17.25), 12).rotation.x = PI * 0.5
	_shape.rod(props, "PasteBrush", Vector3(3.35, 0.25, -17.25), Vector3(3.5, 0.62, -17.1), 0.018, _mat("brush_handle", Color("1e1e22")), 5)
	# A dropped tote and spilled oranges where the neighbours scattered.
	var tote: StandardMaterial3D = _mat("tote", PERSONAL[1], 0.0, 0.95)
	_block(props, "DroppedTote", Vector3(0.42, 0.06, 0.34), tote, Vector3(-5.6, 0.03, -21.4)).rotation.y = 0.6
	var orange: StandardMaterial3D = _mat("orange", Color("d07a2a"), 0.0, 0.7)
	for index: int in range(5):
		_shape.cylinder(props, "Orange", 0.045, 0.08, orange, Vector3(-5.2 + float(index) * 0.23, 0.045, -21.0 + float(index % 2) * 0.2), 8)
	_finish(room)

func _seal_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = M01IntakeArt.texture("emblem")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	return material

# --- the market: four stalls being packed ------------------------------------

## [bench low, bench high, awning far edge z, trade]. Benches sit on the
## awning's south edge; the open side faces the loop.
const STALLS: Array = [
	[Vector3(-15, 0, -7), Vector3(-9, 0.7, -6), -2.0, "noodles"],
	[Vector3(-15, 0, 2), Vector3(-9, 0.7, 3), 7.0, "radios"],
	[Vector3(7, 0, -7), Vector3(13, 0.7, -6), -2.0, "cloth"],
	[Vector3(7, 0, 2), Vector3(13, 0.7, 3), 7.0, "greens"],
]

func _build_market() -> void:
	var room: Node3D = _room("Market")
	var props: Node3D = _props(room)
	for stall: Array in STALLS:
		var low: Vector3 = stall[0]
		var high: Vector3 = stall[1]
		var far: float = stall[2]
		_stall(room, props, low, high, far, stall[3])
	# Festoon lights strung between the stalls across the loop.
	for z: float in [-2.05, 2.05, 6.95, -6.95]:
		_festoon(props, Vector3(-9.0, 3.0, z), Vector3(7.0, 3.0, z), 0.25, 10)
	_festoon(props, Vector3(-9.0, 3.0, -2.05), Vector3(-9.0, 3.0, 2.05), 0.12, 3)
	_festoon(props, Vector3(7.0, 3.0, -2.05), Vector3(7.0, 3.0, 2.05), 0.12, 3)
	# The three cover boxes are stacked crates of packed goods.
	for cover: Array in [[Vector3(15, 0, -1), Vector3(18, 1, 2)], [Vector3(-2, 0, -6), Vector3(1, 0.8, -4)], [Vector3(-2, 0, 8), Vector3(1, 0.8, 10)], [Vector3(-18, 0, -6), Vector3(-16, 1, -3)]]:
		_crate_faces(props, cover[0], cover[1])
	# The service treads up to the awnings are the stallholders' own stacked
	# crates and pallets, climbing toward the noodle stall's roof.
	for step: int in range(6):
		_crate_faces(props, Vector3(-21.0 + float(step) * 2.0, 0, -12), Vector3(-19.0 + float(step) * 2.0, 0.5 * float(step + 1), -10))
	# On top of them, the last things packed.
	_bundle(props, Vector3(16.0, 1.0, 0.0), Vector3(0.6, 0.4, 0.45), PERSONAL[0], 0.4)
	_suitcase(props, Vector3(17.2, 1.0, 1.1), Vector3(0.55, 0.22, 0.38), Color("8a3a58"), -0.3)
	_crate(props, Vector3(-1.2, 0.8, -5.2), Vector3(0.5, 0.35, 0.42), Color("9a7a52"), 0.2)
	_pot_plant(props, Vector3(0.3, 0.8, 9.2), 1.0, 2)
	_bundle(props, Vector3(-1.0, 0.8, 8.9), Vector3(0.5, 0.35, 0.4), PERSONAL[6], -0.5)
	_finish(room)

## Plank relief on every side face of a registered cover box: a stack of
## crates, the joints at the right heights. Flush, so the box stays the box.
func _crate_faces(props: Node3D, low: Vector3, high: Vector3) -> void:
	var wood: StandardMaterial3D = _tiled("crate_wood", "res://assets/models/finishes/wood.png", Color("a07c50"), 1.0)
	var joint: StandardMaterial3D = _mat("crate_joint", Color("5a432c"), 0.0, 0.9)
	var centre: Vector3 = (low + high) * 0.5
	var size: Vector3 = high - low
	for face: Array in [[Vector3.FORWARD, size.x, low.z], [Vector3.BACK, size.x, high.z], [Vector3.LEFT, size.z, low.x], [Vector3.RIGHT, size.z, high.x]]:
		var out: Vector3 = face[0]
		var span: float = face[1]
		var plane: float = face[2]
		var base: Vector3 = Vector3(centre.x, 0, plane) if absf(out.z) > 0.5 else Vector3(plane, 0, centre.z)
		_sheet(props, "CrateFace", Vector2(span - 0.02, size.y - 0.02), wood, base + Vector3(0, size.y * 0.5, 0) + out * 0.006, out)
		var side: Vector3 = Vector3.UP.cross(out).normalized()
		for row: int in range(1, int(size.y / 0.25)):
			_relief(props, "CrateJoint", Vector3(span - 0.02, 0.025, 0.008), joint, base + Vector3(0, float(row) * 0.25, 0), out)
		for column: int in range(1, int(span / 0.75) + 1):
			var s: float = -span * 0.5 + float(column) * span / float(int(span / 0.75) + 1)
			_relief(props, "CrateCorner", Vector3(0.06, size.y - 0.02, 0.012), joint, base + side * s + Vector3(0, size.y * 0.5, 0), out)
	_floor(props, "CrateTop", Vector2(low.x + 0.01, low.z + 0.01), Vector2(high.x - 0.01, high.z - 0.01), wood, high.y + 0.004)

func _stall(room: Node3D, props: Node3D, low: Vector3, high: Vector3, far: float, trade: String) -> void:
	var top: float = high.y
	var mid: float = (low.x + high.x) * 0.5
	var bench_z: float = (low.z + high.z) * 0.5
	var open: float = signf(far - bench_z)
	# Plank front and cloth over the bench top.
	_sheet(props, "BenchFront", Vector2(high.x - low.x - 0.02, top - 0.02), _boards(Color("a5825c")), Vector3(mid, top * 0.5, high.z if open > 0.0 else low.z) + Vector3(0, 0, open * 0.006), Vector3(0, 0, open))
	var cloth_tint: Color = {"noodles": Color("b5652e"), "radios": Color("4f6f8a"), "cloth": Color("8a3a58"), "greens": Color("6f8a4e")}[trade]
	_floor(props, "BenchCloth", Vector2(low.x + 0.05, low.z + 0.05), Vector2(high.x - 0.05, high.z - 0.05), _mat("bench_cloth_%s" % trade, cloth_tint, 0.0, 0.95), top + 0.004)
	_sheet(props, "ClothDrop", Vector2(high.x - low.x - 0.1, 0.3), _mat("bench_cloth_%s" % trade, cloth_tint, 0.0, 0.95), Vector3(mid, top - 0.15, (high.z if open > 0.0 else low.z) + open * 0.01), Vector3(0, 0, open))
	# The awning's valance along its open edge, and its canvas underside.
	var canvas: StandardMaterial3D = _mat("valance_%s" % trade, cloth_tint.lightened(0.18), 0.0, 0.95)
	for index: int in range(10):
		var x: float = low.x + 0.3 + float(index) * (high.x - low.x - 0.6) / 9.0
		_block(props, "Valance", Vector3(0.5, 0.26, 0.02), canvas if index % 2 == 0 else _mat("valance_light", Color("d8c8a0"), 0.0, 0.95), Vector3(x, 2.68, far + open * 0.02))
	# A lamp under the awning over the bench, where the stallholder works.
	_hanging_lamp(room, Vector3(mid, 2.55, bench_z + open * 0.4), 2.8, 1.5, 6.5)
	match trade:
		"noodles":
			# A two-burner stove, a stock pot, stacked bowls and the six on the pole.
			var steel: StandardMaterial3D = _mat("stove_steel", Color("4a4f4d"), 0.5, 0.5)
			_block(props, "Stove", Vector3(0.8, 0.14, 0.5), steel, Vector3(low.x + 1.0, top + 0.07, bench_z))
			_shape.cylinder(props, "StockPot", 0.22, 0.34, _mat("pot_steel", Color("8e8f8a"), 0.7, 0.3), Vector3(low.x + 0.85, top + 0.31, bench_z), 14).rotation.x = PI * 0.5
			for index: int in range(4):
				_shape.lathe(props, "Bowl", PackedVector2Array([Vector2(0.0, 0.05), Vector2(0.08, 0.1), Vector2(0.1, 0.1), Vector2(0.06, 0.02), Vector2(0.06, 0.0)]), _mat("bowl", Color("d8cfae"), 0.0, 0.5), Vector3(low.x + 2.0 + float(index % 2) * 0.24, top + floorf(float(index) / 2.0) * 0.06, bench_z), 10).rotation.x = -PI * 0.5
			_crate(props, Vector3(low.x + 3.4, top, bench_z), Vector3(0.6, 0.35, 0.45), Color("9a7a52"))
			_crate(props, Vector3(low.x + 4.6, top, bench_z), Vector3(0.6, 0.35, 0.45), Color("8d6c43"), 0.1)
			for index: int in range(5):
				_shape.cylinder(props, "HangingLadle", 0.012, 0.36, steel, Vector3(low.x + 2.2 + float(index) * 0.32, 2.58, bench_z), 4).rotation.x = PI * 0.5
		"radios":
			# Radios, a small CRT and coiled leads: half of it boxed already.
			for index: int in range(3):
				var x: float = low.x + 0.7 + float(index) * 0.65
				var tint: Color = [Color("6e4e34"), Color("7d6c5a"), Color("4f5a55")][index]
				_block(props, "Radio", Vector3(0.42, 0.26, 0.2), _mat("radio_%d" % index, tint, 0.2, 0.6), Vector3(x, top + 0.13, bench_z))
				_block(props, "RadioGrille", Vector3(0.2, 0.16, 0.01), _mat("grille", Color("2b2a28")), Vector3(x - 0.08, top + 0.13, bench_z + open * 0.105))
			_block(props, "CRT", Vector3(0.48, 0.42, 0.42), _mat("crt_case", Color("b0a58a"), 0.1, 0.6), Vector3(low.x + 2.8, top + 0.21, bench_z))
			_block(props, "CRTScreen", Vector3(0.36, 0.3, 0.01), _glow("crt_phosphor", Color("c9a45a"), 0.8), Vector3(low.x + 2.8, top + 0.23, bench_z + open * 0.215))
			_crate(props, Vector3(low.x + 3.8, top, bench_z), Vector3(0.7, 0.4, 0.5), Color("8d6c43"))
			_crate(props, Vector3(low.x + 4.9, top, bench_z), Vector3(0.6, 0.3, 0.45), Color("7a6a50"), -0.1)
			var lead: StandardMaterial3D = _mat("cable", Color("232526"), 0.0, 0.7)
			for index: int in range(6):
				var x: float = low.x + 1.2 + float(index) * 0.55
				_festoon(props, Vector3(x, 2.78, bench_z - 0.15), Vector3(x + 0.35, 2.78, bench_z + 0.15), 0.18, 0)
			_shape.cylinder(props, "CableCoil", 0.14, 0.06, lead, Vector3(low.x + 5.6, top + 0.03, bench_z), 12).rotation.x = PI * 0.5
		"cloth":
			# Folded bolts on the bench and garments hung from the awning.
			for index: int in range(6):
				var tint: Color = PERSONAL[(index * 2 + 1) % PERSONAL.size()]
				_block(props, "ClothBolt", Vector3(0.5, 0.08 + float(index % 3) * 0.04, 0.4), _mat("bolt_%d" % index, tint, 0.0, 0.95), Vector3(low.x + 0.5 + float(index) * 0.55, top + 0.06 + float(index % 3) * 0.02, bench_z))
			for index: int in range(7):
				var tint: Color = PERSONAL[(index * 3 + 2) % PERSONAL.size()]
				_block(props, "HungGarment", Vector3(0.42, 0.55, 0.03), _mat("garment_%d" % index, tint.darkened(0.05), 0.0, 0.95), Vector3(low.x + 0.6 + float(index) * 0.78, 2.45, bench_z))
			_bundle(props, Vector3(low.x + 4.6, top, bench_z), Vector3(0.7, 0.4, 0.45), Color("bcae8e"), 0.2)
		"greens":
			# Crates of greens and water jugs, and a hand scale.
			for index: int in range(4):
				var x: float = low.x + 0.6 + float(index) * 0.7
				_crate(props, Vector3(x, top, bench_z), Vector3(0.6, 0.22, 0.45), Color("9a7a52"))
				_block(props, "Greens", Vector3(0.52, 0.1, 0.38), _mat("greens_%d" % (index % 2), [Color("5e7a44"), Color("8a9a4a")][index % 2], 0.0, 0.9), Vector3(x, top + 0.26, bench_z))
			for index: int in range(3):
				_shape.cylinder(props, "WaterJug", 0.12, 0.38, _mat("jug", Color("7f9a98"), 0.1, 0.4), Vector3(low.x + 3.8 + float(index) * 0.3, top + 0.19, bench_z), 10).rotation.x = PI * 0.5
			_block(props, "ScaleBase", Vector3(0.3, 0.06, 0.24), _mat("brass", Color("9a7d3e"), 0.6, 0.4), Vector3(low.x + 5.3, top + 0.03, bench_z))
			_shape.cylinder(props, "ScalePan", 0.16, 0.02, _mat("brass", Color("9a7d3e"), 0.6, 0.4), Vector3(low.x + 5.3, top + 0.2, bench_z), 10).rotation.x = PI * 0.5

# --- the repair bench: the charging argument -----------------------------------

func _build_repair_bench() -> void:
	var room: Node3D = _room("RepairBench")
	var props: Node3D = _props(room)
	var top: float = 0.8
	# Plank front facing the market and a pegboard on the sign post's west face.
	_sheet(props, "BenchFront", Vector2(7.98, 0.78), _boards(Color("8f7a62")), Vector3(-9.0, 0.4, 9.994), Vector3.FORWARD)
	var board: StandardMaterial3D = _mat("pegboard", Color("9a8466"), 0.0, 0.9)
	_sheet(props, "Pegboard", Vector2(1.3, 1.8), board, Vector3(-5.508, 1.95, 10.75), Vector3.LEFT)
	var tool: StandardMaterial3D = _mat("tool_steel", Color("5a5f5c"), 0.6, 0.45)
	var grip: StandardMaterial3D = _mat("tool_grip", Color("a64a3a"), 0.0, 0.7)
	for index: int in range(7):
		var z: float = 10.25 + fmod(float(index) * 0.37, 1.0)
		var y: float = 1.3 + float(index) * 0.18
		_relief(props, "HungTool", Vector3(0.05, 0.32, 0.03), tool, Vector3(-5.51, y, z), Vector3.LEFT)
		_relief(props, "ToolGrip", Vector3(0.06, 0.12, 0.035), grip if index % 2 == 0 else _mat("tool_grip_b", Color("4f6f8a")), Vector3(-5.51, y - 0.2, z), Vector3.LEFT)
	# Two devices on two chargers, leads crossed: the argument made visible.
	var device: StandardMaterial3D = _mat("device", Color("2b2f31"), 0.3, 0.5)
	for x: float in [-11.6, -10.9]:
		_block(props, "ChargingDevice", Vector3(0.16, 0.02, 0.28), device, Vector3(x, top + 0.01, 10.4))
		_block(props, "DeviceScreen", Vector3(0.12, 0.004, 0.2), _glow("device_screen", Color("c9a45a"), 0.6), Vector3(x, top + 0.022, 10.4))
	_block(props, "Lantern", Vector3(0.2, 0.32, 0.2), _mat("lantern", Color("6f8a4e"), 0.3, 0.5), Vector3(-7.4, top + 0.16, 11.1))
	_crate(props, Vector3(-5.85, top, 11.0), Vector3(0.45, 0.3, 0.4), Color("8d6c43"))
	# A work lamp on a gooseneck arm from the sign post out over the bench.
	_shape.rod(props, "LampArm", Vector3(-5.5, 2.9, 10.75), Vector3(-8.6, 2.85, 10.75), 0.03, _mat("iron", Color("2f3231"), 0.4, 0.6), 6)
	_shape.rod(props, "LampStay", Vector3(-5.5, 2.3, 10.75), Vector3(-6.8, 2.88, 10.75), 0.018, _mat("iron", Color("2f3231"), 0.4, 0.6), 4)
	_hanging_lamp(room, Vector3(-8.6, 2.55, 10.75), 2.85, 1.7, 6.5)
	_finish(room)

# --- the clinic: bright, clean and calm -----------------------------------------

func _build_clinic() -> void:
	var room: Node3D = _room("Clinic")
	var props: Node3D = _props(room)
	# Inside, warm bone plaster over a washable sage dado, and a pale ceiling.
	var plaster: StandardMaterial3D = _tiled("clinic_plaster", "res://assets/models/finishes/enamel.png", Color("e4dac2"), 1.5)
	var dado: StandardMaterial3D = _tiled("clinic_dado", "res://assets/models/finishes/enamel.png", Color("98ab94"), 1.5)
	var rail: StandardMaterial3D = _mat("dado_rail", Color("7d6a52"), 0.0, 0.8)
	for wall: Array in [[Vector3(-34.5, 0, 3.0), Vector3.RIGHT, 21.0], [Vector3(-28.5, 0, -7.5), Vector3.BACK, 12.0], [Vector3(-28.5, 0, 13.5), Vector3.FORWARD, 12.0], [Vector3(-22.5, 0, -3.75), Vector3.LEFT, 7.5], [Vector3(-22.5, 0, 8.75), Vector3.LEFT, 9.5]]:
		var at: Vector3 = wall[0]
		var out: Vector3 = wall[1]
		var span: float = wall[2]
		_sheet(props, "ClinicPlaster", Vector2(span - 0.02, 2.88), plaster, at + Vector3(0, 2.55, 0) + out * 0.008, out)
		_sheet(props, "ClinicDado", Vector2(span - 0.02, 1.1), dado, at + Vector3(0, 0.56, 0) + out * 0.008, out)
		_relief(props, "DadoRail", Vector3(span - 0.02, 0.06, 0.03), rail, at + Vector3(0, 1.12, 0), out)
	# The street windows from inside: afternoon light through net curtains.
	var daylight: StandardMaterial3D = _glow("clinic_daylight", Color("e8dcc0"), 0.7)
	var net: StandardMaterial3D = _mat("net_curtain", Color("efe8d8"), 0.0, 0.95)
	for z: float in [-6.0, -4.0, 6.5, 9.5, 12.0]:
		_sheet(props, "InnerWindow", Vector2(1.4, 1.2), daylight, Vector3(-22.512, 1.9, z), Vector3.LEFT)
		_sheet(props, "NetCurtain", Vector2(1.3, 0.55), net, Vector3(-22.516, 2.18, z), Vector3.LEFT)
		_relief(props, "InnerSill", Vector3(1.6, 0.06, 0.14), _mat("window_frame", Color("e0d3b8").darkened(0.15), 0.0, 0.8), Vector3(-22.5, 1.27, z), Vector3.LEFT)
	var ceiling: MeshInstance3D = _floor(props, "ClinicCeiling", Vector2(-34.5, -7.5), Vector2(-22.5, 13.5), _tiled("clinic_ceiling", "res://assets/models/finishes/enamel.png", Color("ece4d0"), 2.0), 3.992)
	ceiling.rotation.x = PI
	# Pendant lamps in a row down the ward, bright and warm-white.
	var shade: StandardMaterial3D = _mat("clinic_shade", Color("dcd4bc"), 0.1, 0.6)
	var bulb: StandardMaterial3D = _glow("clinic_bulb", Color("fff0d6"), 2.8)
	for z: float in [-4.0, 1.0, 6.0, 11.0]:
		var at: Vector3 = Vector3(-29.0, 3.2, z)
		_shape.rod(props, "PendantCord", at, Vector3(at.x, 4.0, at.z), 0.01, _mat("cable", Color("232526"), 0.0, 0.7), 4)
		_shape.lathe(props, "PendantShade", PackedVector2Array([Vector2(-0.04, 0.0), Vector2(-0.04, 0.06), Vector2(0.0, 0.08), Vector2(0.24, 0.22), Vector2(0.24, 0.0)]), shade, at, 12).rotation.x = PI * 0.5
		_shape.cylinder(props, "PendantBulb", 0.06, 0.1, bulb, at + Vector3(0, -0.12, 0), 8).rotation.x = PI * 0.5
		_omni(room, "ClinicPendant", at + Vector3(0, -0.25, 0), CLINIC_LAMP, 2.1, 8.5)
	# Privacy curtains on rails above each bed, drawn back to the wall.
	var curtain_rail: StandardMaterial3D = _mat("curtain_rail", Color("8e8f8a"), 0.6, 0.4)
	var curtain: StandardMaterial3D = _mat("privacy_curtain", Color("d8cfb6"), 0.0, 0.95)
	var fold: StandardMaterial3D = _mat("privacy_fold", Color("c2b89c"), 0.0, 0.95)
	for z: float in [-2.45, 6.45]:
		_shape.rod(props, "CurtainRail", Vector3(-34.48, 3.1, z), Vector3(-29.6, 3.1, z), 0.02, curtain_rail, 5)
		for index: int in range(4):
			_block(props, "DrawnCurtain", Vector3(0.14, 2.5, 0.08 + float(index % 2) * 0.04), curtain if index % 2 == 0 else fold, Vector3(-34.38 + float(index) * 0.13, 1.82, z))
	# An IV stand at each bed's head, tucked against the wall.
	var steel: StandardMaterial3D = _mat("iv_steel", Color("b8b8b0"), 0.6, 0.4)
	for z: float in [-5.4, 9.4]:
		var foot: Vector3 = Vector3(-33.9, 0.0, z)
		_shape.rod(props, "IVPole", foot, foot + Vector3(0, 1.9, 0), 0.015, steel, 5)
		_shape.rod(props, "IVArm", foot + Vector3(-0.15, 1.85, 0), foot + Vector3(0.15, 1.85, 0), 0.01, steel, 4)
		_block(props, "IVBag", Vector3(0.1, 0.18, 0.04), _mat("iv_bag", Color("d9dccc"), 0.0, 0.3), foot + Vector3(0.12, 1.7, 0))
		for leg: int in range(3):
			var angle: float = TAU * float(leg) / 3.0
			_shape.rod(props, "IVFoot", foot + Vector3(0, 0.06, 0), foot + Vector3(cos(angle) * 0.2, 0.01, sin(angle) * 0.2), 0.012, steel, 4)
	# Shelves on the west wall beside the care board: jars, boxes, linen.
	var shelf: StandardMaterial3D = _mat("clinic_shelf", Color("c9bfa4"), 0.0, 0.7)
	for y: float in [1.3, 1.8, 2.3]:
		_relief(props, "ClinicShelf", Vector3(2.8, 0.04, 0.3), shelf, Vector3(-34.5, y, 5.6), Vector3.RIGHT)
		for index: int in range(6):
			var z: float = 4.4 + float(index) * 0.45
			var tint: Color = [Color("6f8a6a"), Color("d8cfae"), Color("a76343"), Color("7f9a98")][(index + int(y * 10.0)) % 4]
			if index % 3 == 2:
				_block(props, "ShelfBox", Vector3(0.22, 0.2, 0.3), _mat("shelf_box_%d" % (index % 2), tint, 0.0, 0.8), Vector3(-34.33, y + 0.12, z))
			else:
				_shape.cylinder(props, "ShelfJar", 0.07, 0.2, _mat("shelf_jar_%s" % tint.to_html(false), tint, 0.0, 0.4), Vector3(-34.33, y + 0.12, z), 8).rotation.x = PI * 0.5
	# The care board: cork, with a card per patient and coloured pins for who
	# is moving with whom. Cards and pins, no writing at reading distance.
	_sheet(props, "CareCork", Vector2(3.9, 1.9), _mat("cork", Color("9a7a52"), 0.0, 0.95), Vector3(-33.994, 2.0, 1.0), Vector3.RIGHT)
	for index: int in range(12):
		var z: float = -0.55 + float(index % 6) * 0.62
		var y: float = 2.45 - floorf(float(index) / 6.0) * 0.8
		_sheet(props, "CareCard", Vector2(0.42, 0.32), _mat("paper_%d" % (index % 3), [Color("e2dccb"), Color("d8c9a0"), Color("c9d6c0")][index % 3], 0.0, 0.95), Vector3(-33.99, y, z), Vector3.RIGHT)
		_relief(props, "CarePin", Vector3(0.04, 0.04, 0.02), _mat("pin_%d" % (index % 3), [Color("6f8a4e"), Color("4f6f8a"), Color("c49a3c")][index % 3]), Vector3(-33.99, y + 0.12, z), Vector3.RIGHT)
	# A medicine cabinet on the south wall and a sink below it.
	var cabinet: StandardMaterial3D = _mat("cabinet", Color("dcd4bc"), 0.1, 0.5)
	_relief(props, "MedicineCabinet", Vector3(1.2, 0.9, 0.22), cabinet, Vector3(-27.0, 1.75, -7.5), Vector3.BACK)
	_relief(props, "CabinetDoorLine", Vector3(0.02, 0.86, 0.004), _mat("cabinet_line", Color("8e8f8a")), Vector3(-27.0, 1.75, -7.28), Vector3.BACK)
	_relief(props, "CabinetMark", Vector3(0.22, 0.22, 0.004), _mat("cabinet_mark", Color("6f8a6a")), Vector3(-27.0, 1.95, -7.278), Vector3.BACK)
	_relief(props, "Sink", Vector3(0.7, 0.18, 0.42), _mat("sink", Color("e0dcd0"), 0.2, 0.3), Vector3(-25.2, 0.92, -7.5), Vector3.BACK)
	# Patients' drawings on the north wall over the counter: the market, the
	# tram, a cat, the water tanks. Coloured paper, no words.
	var papers: Array[Color] = [Color("e2dccb"), Color("d8c9a0"), Color("c9d6c0"), Color("e6c9b0")]
	for index: int in range(8):
		var x: float = -31.5 + float(index) * 0.85
		var y: float = 1.95 + float(index % 2) * 0.55
		_sheet(props, "Drawing", Vector2(0.55, 0.42), _mat("drawing_paper_%d" % (index % 4), papers[index % 4], 0.0, 0.95), Vector3(x, y, 13.488), Vector3.FORWARD)
		_sheet(props, "DrawingMark", Vector2(0.3, 0.16), _mat("drawing_%d" % (index % PERSONAL.size()), PERSONAL[(index * 3) % PERSONAL.size()], 0.0, 0.9), Vector3(x + 0.04, y - 0.06, 13.484), Vector3.FORWARD)
		_sheet(props, "DrawingSky", Vector2(0.45, 0.08), _mat("drawing_sky", Color("7f9ab0"), 0.0, 0.9), Vector3(x, y + 0.13, 13.484), Vector3.FORWARD)
	# On the counter: Edda's satchels packed to move, a kettle, a plant, a radio.
	var counter: float = 0.9
	_bundle(props, Vector3(-31.2, counter, 12.2), Vector3(0.55, 0.32, 0.36), Color("8a6a4a"), 0.2)
	_bundle(props, Vector3(-30.5, counter, 12.35), Vector3(0.5, 0.3, 0.34), Color("6e4e34"), -0.1)
	_shape.cylinder(props, "Kettle", 0.1, 0.22, _mat("kettle", Color("6f8a6a"), 0.5, 0.4), Vector3(-26.0, counter + 0.11, 12.3), 10).rotation.x = PI * 0.5
	_pot_plant(props, Vector3(-25.5, counter, 12.6), 0.9, 1)
	_block(props, "CounterRadio", Vector3(0.36, 0.2, 0.16), _mat("radio_0", Color("6e4e34"), 0.2, 0.6), Vector3(-27.2, counter + 0.1, 12.8))
	# A folded stretcher leaning by the door, inside the wall's clearance.
	_relief(props, "FoldedStretcher", Vector3(0.5, 2.0, 0.12), _mat("stretcher", Color("6f7d76"), 0.3, 0.6), Vector3(-23.1, 1.0, -7.5), Vector3.BACK).rotate_object_local(Vector3.BACK, 0.08)
	# A woven rug between the beds and the door.
	_floor(props, "ClinicRug", Vector2(-28.2, 0.6), Vector2(-25.6, 3.4), _mat("clinic_rug", Color("8a4a32"), 0.0, 0.95), 0.012)
	_floor(props, "ClinicRugField", Vector2(-28.0, 0.8), Vector2(-25.8, 3.2), _mat("clinic_rug_inner", Color("9a8a5e"), 0.0, 0.95), 0.013)
	for index: int in range(3):
		_floor(props, "ClinicRugStripe", Vector2(-27.8 + float(index) * 0.75, 0.8), Vector2(-27.6 + float(index) * 0.75, 3.2), _mat("clinic_rug", Color("8a4a32"), 0.0, 0.95), 0.014)
	_build_clinic_front(room, props)
	_finish(room)

## Outside the clinic: windows lit from inside, planters at the wall, a lamp
## over the shutter and a painted hand holding a sprout on the south wall.
func _build_clinic_front(room: Node3D, props: Node3D) -> void:
	var frame: StandardMaterial3D = _mat("window_frame", Color("e0d3b8").darkened(0.15), 0.0, 0.8)
	var lit: StandardMaterial3D = _glow("clinic_window", Color("f0dcb0"), 0.9)
	# The clinic's own sage plaster, kept clear of the switch on its post.
	var sage: ShaderMaterial = _surface("enamel", Color("9fae96"))
	for span: Vector2 in [Vector2(-8.0, -2.6), Vector2(-0.9, 0.0), Vector2(4.0, 14.0)]:
		_sheet(props, "ClinicRender", Vector2(span.y - span.x - 0.02, 3.98), sage, Vector3(-21.992, 2.0, (span.x + span.y) * 0.5), Vector3.RIGHT)
		_sheet(props, "ClinicPlinth", Vector2(span.y - span.x - 0.02, 0.4), _surface("concrete", Color("6f7a68")), Vector3(-21.99, 0.2, (span.x + span.y) * 0.5), Vector3.RIGHT)
	_sheet(props, "ClinicRender", Vector2(12.98, 3.98), sage, Vector3(-28.5, 2.0, -8.003), Vector3.FORWARD)
	for z: float in [-6.0, -4.0, 6.5, 9.5, 12.0]:
		_sheet(props, "ClinicWindow", Vector2(1.4, 1.2), lit, Vector3(-21.985, 1.9, z), Vector3.RIGHT)
		_relief(props, "ClinicSill", Vector3(1.6, 0.07, 0.15), frame, Vector3(-22.0, 1.27, z), Vector3.RIGHT)
		_relief(props, "ClinicHead", Vector3(1.6, 0.07, 0.06), frame, Vector3(-22.0, 2.53, z), Vector3.RIGHT)
		for edge: float in [-0.73, 0.73]:
			_relief(props, "ClinicJamb", Vector3(0.07, 1.3, 0.05), frame, Vector3(-22.0, 1.9, z + edge), Vector3.RIGHT)
	for z: float in [-7.0, 5.0, 13.0]:
		_pot_plant(props, Vector3(-21.72, 0.0, z), 0.95, int(z + 10.0))
	_wall_lamp(props, Vector3(-22.0, 3.5, 2.0), Vector3.RIGHT)
	_omni(room, "ClinicDoorLamp", Vector3(-21.4, 3.3, 2.0), WARM_LAMP, 1.4, 6.0)
	# The south wall faces the square: a hand holding a sprout, painted large.
	var out: Vector3 = Vector3.FORWARD
	var hand: StandardMaterial3D = _mat("mural_hand", Color("c49a6a"), 0.0, 0.9)
	var sprout: StandardMaterial3D = _mat("mural_sprout", Color("6f8a4e"), 0.0, 0.9)
	var ground: StandardMaterial3D = _mat("mural_ground", Color("8fa595"), 0.0, 0.9)
	var at: Vector3 = Vector3(-28.5, 0.0, -8.006)
	_sheet(props, "MuralGround", Vector2(5.0, 3.0), ground, at + Vector3(0, 2.0, 0), out)
	_sheet(props, "MuralPalm", Vector2(1.8, 0.7), hand, at + Vector3(0, 1.3, -0.003), out)
	for index: int in range(4):
		_sheet(props, "MuralFinger", Vector2(0.28, 0.6), hand, at + Vector3(-0.66 + float(index) * 0.36, 1.86, -0.003), out)
	_sheet(props, "MuralThumb", Vector2(0.55, 0.26), hand, at + Vector3(1.05, 1.5, -0.003), out)
	_sheet(props, "MuralStem", Vector2(0.1, 1.0), sprout, at + Vector3(0, 2.2, -0.004), out)
	for side: float in [-1.0, 1.0]:
		var leaf: MeshInstance3D = _sheet(props, "MuralLeaf", Vector2(0.55, 0.24), sprout, at + Vector3(side * 0.28, 2.55 + side * 0.08, -0.004), out)
		leaf.rotate_object_local(Vector3.BACK, side * 0.4)

# --- the tram street and the tram -------------------------------------------

func _build_tram_street() -> void:
	var room: Node3D = _room("TramStreet")
	var props: Node3D = _props(room)
	# The tram's old livery: terracotta below, cream above, a dark window band
	# and a skirt, on every face of the registered cab.
	var cream: StandardMaterial3D = _mat("tram_cream", Color("d2c19a"), 0.1, 0.6)
	var terracotta: StandardMaterial3D = _mat("tram_terracotta", Color("9a5038"), 0.1, 0.6)
	var skirt: StandardMaterial3D = _mat("tram_skirt", Color("33302c"), 0.3, 0.6)
	var tram_glass: StandardMaterial3D = _mat("tram_glass", Color("2a3433"), 0.3, 0.3)
	for face: Array in [[Vector3.BACK, 7.0, Vector3(28.5, 0, -9)], [Vector3.FORWARD, 7.0, Vector3(28.5, 0, -15)], [Vector3.RIGHT, 6.0, Vector3(32, 0, -12)], [Vector3.LEFT, 6.0, Vector3(25, 0, -12)]]:
		var out: Vector3 = face[0]
		var span: float = face[1]
		var base: Vector3 = face[2]
		var side: Vector3 = Vector3.UP.cross(out).normalized()
		_sheet(props, "TramCream", Vector2(span - 0.02, 1.58), cream, base + Vector3(0, 1.7, 0) + out * 0.003, out)
		_sheet(props, "TramLower", Vector2(span - 0.02, 0.66), terracotta, base + Vector3(0, 0.58, 0) + out * 0.003, out)
		_sheet(props, "TramSkirt", Vector2(span - 0.02, 0.25), skirt, base + Vector3(0, 0.125, 0) + out * 0.004, out)
		if span > 6.5:
			for index: int in range(5):
				_sheet(props, "TramWindow", Vector2(0.95, 0.75), tram_glass, base + side * (-2.6 + float(index) * 1.25) + Vector3(0, 1.68, 0) + out * 0.005, out)
		else:
			# The ends: one wide windscreen, two headlamps and a bumper.
			if out.x > 0.0:
				_sheet(props, "TramWindscreen", Vector2(4.4, 0.8), tram_glass, base + Vector3(0, 1.7, 0) + out * 0.005, out)
			for edge: float in [-2.2, 2.2]:
				_sheet(props, "TramHeadlamp", Vector2(0.3, 0.22), _glow("tram_lamp", Color("e8d6a8"), 0.4), base + side * edge + Vector3(0, 0.75, 0) + out * 0.006, out)
			_relief(props, "TramBumper", Vector3(span - 0.4, 0.14, 0.12), skirt, base + Vector3(0, 0.32, 0), out)
	_sheet(props, "TramDoor", Vector2(1.1, 2.0), _mat("tram_door", Color("8a7a5a"), 0.2, 0.6), Vector3(25.65, 1.05, -8.994), Vector3.BACK)
	# The tram (cab 25..32, z -15..-9). Its south flank carries three test
	# colours for the vote, and the green has already started at one end.
	var swatches: Array[Color] = [Color("6f8a4e"), Color("4f6f8a"), Color("a64a3a")]
	for index: int in range(3):
		_sheet(props, "PaintSwatch", Vector2(0.9, 0.7), _mat("swatch_%d" % index, swatches[index], 0.0, 0.7), Vector3(26.8 + float(index) * 1.1, 0.8, -8.994), Vector3.BACK)
	_sheet(props, "FreshGreen", Vector2(2.2, 0.98), _mat("tram_green", Color("6f8a4e"), 0.0, 0.6), Vector3(30.8, 0.74, -8.993), Vector3.BACK)
	for index: int in range(5):
		_sheet(props, "PaintDrip", Vector2(0.05, 0.18 + float(index % 3) * 0.1), _mat("tram_green", Color("6f8a4e"), 0.0, 0.6), Vector3(29.8 + float(index) * 0.22, 0.16, -8.992), Vector3.BACK)
	# A stepladder folded flat against the tram, paint tins on the roof.
	var ladder: StandardMaterial3D = _mat("ladder", Color("9a8a6a"), 0.3, 0.6)
	for edge: float in [-0.22, 0.22]:
		_shape.rod(props, "LadderRail", Vector3(29.3 + edge, 0.0, -8.8), Vector3(29.3 + edge, 2.4, -8.95), 0.025, ladder, 4)
	for rung: int in range(6):
		var y: float = 0.3 + float(rung) * 0.38
		_shape.rod(props, "LadderRung", Vector3(29.08, y, -8.8 - y * 0.06), Vector3(29.52, y, -8.8 - y * 0.06), 0.015, ladder, 4)
	for index: int in range(3):
		_shape.cylinder(props, "PaintTin", 0.11, 0.2, _mat("swatch_%d" % index, swatches[index], 0.3, 0.5), Vector3(26.0 + float(index) * 0.35, 3.1, -9.2), 10).rotation.x = PI * 0.5
	# A pantograph folded down on the tram roof.
	var iron: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	_shape.rod(props, "Pantograph", Vector3(28.0, 3.0, -12.0), Vector3(29.4, 3.35, -12.0), 0.03, iron, 5)
	_shape.rod(props, "Pantograph", Vector3(29.4, 3.35, -12.0), Vector3(30.6, 3.05, -12.0), 0.03, iron, 5)
	_block(props, "PantographShoe", Vector3(0.1, 0.06, 1.4), iron, Vector3(29.4, 3.4, -12.0))
	_finish(room)

# --- the tram workshop and its gantry crane -------------------------------------

func _build_workshop() -> void:
	var room: Node3D = _room("Workshop")
	var props: Node3D = _props(room)
	var iron: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	var ochre: StandardMaterial3D = _mat("gantry_ochre", Color("b0843e"), 0.4, 0.6)
	# The gantry crane on the workshop roof: the landmark at the end of the
	# street, its beam reaching out over the tram.
	for x: float in [23.0, 33.0]:
		for z: float in [-31.0, -19.0]:
			_shape.rod(props, "GantryLeg", Vector3(x, 4.35, z), Vector3(x, 8.6, -25.0 + (z + 25.0) * 0.2), 0.12, ochre, 6)
		_block(props, "GantryHead", Vector3(0.5, 0.4, 3.0), ochre, Vector3(x, 8.8, -25.0))
	_block(props, "GantryBeam", Vector3(16.0, 0.5, 0.4), ochre, Vector3(25.0, 9.1, -25.0))
	_block(props, "GantryBeamB", Vector3(16.0, 0.5, 0.4), ochre, Vector3(25.0, 9.1, -24.0))
	_block(props, "Trolley", Vector3(0.9, 0.45, 1.6), iron, Vector3(19.0, 8.7, -24.5))
	_shape.rod(props, "HoistChain", Vector3(19.0, 8.5, -24.5), Vector3(19.0, 6.2, -24.5), 0.03, iron, 4)
	_shape.lathe(props, "Hook", PackedVector2Array([Vector2(0.0, 0.1), Vector2(0.18, 0.06), Vector2(0.18, 0.0)]), iron, Vector3(19.0, 6.1, -24.5), 8).rotation.x = PI * 0.5
	# Corrugated cladding on the shed's outer faces, a clerestory under the
	# eaves, and the same cladding inside. The sign's wall keeps its board.
	var cladding: StandardMaterial3D = _tiled("shed_cladding", EnvironmentTextures.PRODUCTION + "low_water_steel.png", Color("c4ccbc"), 1.5)
	var inside: StandardMaterial3D = _tiled("shed_inside", EnvironmentTextures.PRODUCTION + "low_water_steel.png", Color("e0d6c0"), 1.5)
	var clerestory: StandardMaterial3D = _mat("glass_dark", Color("2b3634"), 0.2, 0.35)
	for wall: Array in [[Vector3(28, 0, -32), Vector3.FORWARD, 12.0, cladding], [Vector3(34, 0, -25), Vector3.RIGHT, 14.0, cladding], [Vector3(22, 0, -20), Vector3.LEFT, 4.0, cladding], [Vector3(28, 0, -18), Vector3.BACK, 12.0, cladding],
			[Vector3(28, 0, -31.5), Vector3.BACK, 11.0, inside], [Vector3(33.5, 0, -25), Vector3.LEFT, 13.0, inside], [Vector3(28, 0, -18.5), Vector3.FORWARD, 11.0, inside], [Vector3(22.5, 0, -28.75), Vector3.RIGHT, 5.5, inside], [Vector3(22.5, 0, -20.25), Vector3.RIGHT, 3.5, inside]]:
		var out: Vector3 = wall[1]
		_sheet(props, "Cladding", Vector2(float(wall[2]) - 0.02, 3.98), wall[3], (wall[0] as Vector3) + Vector3(0, 2.0, 0) + out * 0.004, out)
		if wall[3] == cladding and float(wall[2]) > 5.0 and out != Vector3.BACK:
			var side: Vector3 = Vector3.UP.cross(out).normalized()
			var rib: StandardMaterial3D = _mat("cladding_rib", Color("6c7468"), 0.3, 0.6)
			for index: int in range(int(float(wall[2]) / 0.5)):
				_relief(props, "CladdingRib", Vector3(0.05, 3.0, 0.025), rib, (wall[0] as Vector3) + side * (-float(wall[2]) * 0.5 + 0.25 + float(index) * 0.5) + Vector3(0, 1.55, 0), out)
			for index: int in range(int(float(wall[2]) / 2.4)):
				_sheet(props, "Clerestory", Vector2(1.6, 0.45), clerestory, (wall[0] as Vector3) + side * (-float(wall[2]) * 0.5 + 1.2 + float(index) * 2.4) + Vector3(0, 3.45, 0) + out * 0.012, out)
	# The south face over the tram: big shed doors, closed, rails ending there.
	var door: StandardMaterial3D = _mat("shed_door", Color("5f7277"), 0.3, 0.6)
	_sheet(props, "ShedDoors", Vector2(7.0, 3.6), door, Vector3(28.5, 1.8, -17.994), Vector3.BACK)
	for index: int in range(9):
		_relief(props, "ShedRib", Vector3(0.08, 3.5, 0.03), _mat("shed_rib", Color("4a5a5e"), 0.3, 0.6), Vector3(25.2 + float(index) * 0.83, 1.8, -18.0), Vector3.BACK)
	# Inside: a shelf of tins and tools round the walls, wheels leaning, a
	# hoist rail, and the work lamps on.
	var shelf: StandardMaterial3D = _mat("work_shelf", Color("6e4e34"), 0.0, 0.85)
	for y: float in [1.0, 1.7]:
		_relief(props, "WorkShelf", Vector3(9.0, 0.05, 0.38), shelf, Vector3(28.0, y, -31.5), Vector3.BACK)
		for index: int in range(12):
			var x: float = 23.8 + float(index) * 0.75
			var tint: Color = [Color("6f8a4e"), Color("4f6f8a"), Color("a64a3a"), Color("8e8f8a")][(index + int(y)) % 4]
			_shape.cylinder(props, "ShelfTin", 0.1, 0.2, _mat("swatch_tin_%s" % tint.to_html(false), tint, 0.3, 0.5), Vector3(x, y + 0.13, -31.3), 8).rotation.x = PI * 0.5
	var wheel: StandardMaterial3D = _mat("tram_wheel", Color("3d3b37"), 0.7, 0.4)
	for z: float in [-29.5, -28.4]:
		var spot: Vector3 = Vector3(33.27, 0.45, z)
		_shape.cylinder(props, "TramWheel", 0.45, 0.14, wheel, spot, 16).rotation.y = PI * 0.5
	_shape.rod(props, "HoistRail", Vector3(23.0, 3.6, -25.0), Vector3(33.2, 3.6, -25.0), 0.06, iron, 6)
	_shape.rod(props, "HoistChain", Vector3(26.0, 3.55, -25.0), Vector3(26.0, 2.6, -25.0), 0.02, iron, 4)
	var floor_oil: StandardMaterial3D = _mat("oil_stain", Color("3a3836"), 0.0, 0.7)
	for at: Vector2 in [Vector2(26.0, -25.3), Vector2(30.5, -21.0), Vector2(24.2, -29.0)]:
		_floor(props, "OilStain", at - Vector2(0.7, 0.45), at + Vector2(0.7, 0.45), floor_oil, 0.012)
	# The east wall, seen through the doorway: a tool board over a narrow
	# shelf of the three vote colours, a trolley wheel and coiled hose.
	_sheet(props, "ToolBoard", Vector2(3.2, 1.4), _boards(Color("8f7a62")), Vector3(33.488, 1.9, -24.0), Vector3.LEFT)
	var tool: StandardMaterial3D = _mat("tool_steel", Color("5a5f5c"), 0.6, 0.45)
	for index: int in range(9):
		var z: float = -25.4 + float(index) * 0.34
		_relief(props, "BoardTool", Vector3(0.05, 0.3 + float(index % 3) * 0.12, 0.03), tool, Vector3(33.48, 2.0, z), Vector3.LEFT)
	_relief(props, "ColourShelf", Vector3(3.0, 0.05, 0.3), shelf, Vector3(33.5, 1.0, -24.0), Vector3.LEFT)
	for index: int in range(6):
		var tint: Color = [Color("6f8a4e"), Color("4f6f8a"), Color("a64a3a")][index % 3]
		_shape.cylinder(props, "VoteTin", 0.1, 0.2, _mat("swatch_tin_%s" % tint.to_html(false), tint, 0.3, 0.5), Vector3(33.33, 1.13, -25.2 + float(index) * 0.45), 8).rotation.x = PI * 0.5
	_shape.cylinder(props, "HoseCoil", 0.32, 0.1, _mat("hose", Color("3a4a3a"), 0.0, 0.7), Vector3(33.42, 0.6, -21.2), 14).rotation.y = PI * 0.5
	# The locker the vote paint lives in: issued steel, its six in three colours.
	var locker: StandardMaterial3D = _mat("locker_steel", Color("5f7277"), 0.4, 0.5)
	for face: Array in [[Vector3.BACK, Vector3(28, 0, -24.5), 1.0], [Vector3.FORWARD, Vector3(28, 0, -25), 1.0], [Vector3.LEFT, Vector3(27.5, 0, -24.75), 0.5], [Vector3.RIGHT, Vector3(28.5, 0, -24.75), 0.5]]:
		var out: Vector3 = face[0]
		_sheet(props, "LockerSteel", Vector2(float(face[2]) - 0.01, 1.98), locker, (face[1] as Vector3) + Vector3(0, 1.0, 0) + out * 0.004, out)
	# The shed roof's underside: purlins over the same cladding.
	var underside: MeshInstance3D = _floor(props, "ShedCeiling", Vector2(22.5, -31.5), Vector2(33.5, -18.5), inside, 3.992)
	underside.rotation.x = PI
	for index: int in range(6):
		_block(props, "Purlin", Vector3(11.0, 0.14, 0.1), iron, Vector3(28.0, 3.9, -30.5 + float(index) * 2.2))
	_hanging_lamp(room, Vector3(26.0, 3.1, -28.0), 3.95, 2.4, 7.5)
	_hanging_lamp(room, Vector3(30.5, 3.1, -22.0), 3.95, 2.4, 7.5)
	_hanging_lamp(room, Vector3(31.5, 3.1, -26.5), 3.95, 1.8, 6.0)
	_finish(room)

# --- the habitation court ------------------------------------------------------

func _build_court() -> void:
	var room: Node3D = _room("Court")
	var props: Node3D = _props(room)
	# The market faces of the court's south blocks: shops over the loop.
	_facade(props, Vector3(-20, 0, 16), Vector3.RIGHT, Vector3.FORWARD, 12.0, 4.0, 2, false)
	_facade(props, Vector3(8, 0, 16), Vector3.RIGHT, Vector3.FORWARD, 12.0, 4.0, 6, false)
	# Homes under the balconies: doors and windows at ground level on the
	# three back walls, and front doors on the balconies between the windows.
	for z: float in [19.0, 25.0, 30.0]:
		_home_door(props, Vector3(-19.5, 0.0, z), Vector3.RIGHT, int(z))
		_home_door(props, Vector3(19.5, 0.0, z + 1.0), Vector3.LEFT, int(z) + 1)
	for z: float in [18.9, 24.2, 30.3]:
		_home_door(props, Vector3(-19.5, 3.0, z), Vector3.RIGHT, int(z) + 2)
	for z: float in [19.6, 24.8, 30.8]:
		_home_door(props, Vector3(19.5, 3.0, z), Vector3.LEFT, int(z) + 3)
	for x: float in [-14.0, -7.0, 0.3, 7.5]:
		_home_door(props, Vector3(x, 0.0, 39.0), Vector3.FORWARD, int(x) + 20)
		_home_door(props, Vector3(x, 3.0, 39.0), Vector3.FORWARD, int(x) + 23)
	# The court sides of the south blocks: ground-floor homes facing the yard.
	_facade(props, Vector3(-8, 0, 17), Vector3.LEFT, Vector3.BACK, 11.5, 4.0, 9, false)
	_facade(props, Vector3(19.5, 0, 17), Vector3.LEFT, Vector3.BACK, 11.5, 4.0, 4, false)
	# The roof stair (x 12..15, z 18..34): rendered concrete risers and a
	# worn ochre nosing on every tread.
	var render: StandardMaterial3D = _tiled("stair_render", EnvironmentTextures.EARTH + "earth_yard_cast_concrete.png", Color("9a8a78"), 2.0)
	var nosing: StandardMaterial3D = _mat("tread_nosing", Color("b0843e"), 0.0, 0.8)
	for step: int in range(8):
		var z0: float = 18.0 + float(step) * 2.0
		var top: float = 0.5 * float(step + 1)
		_sheet(props, "StairSide", Vector2(1.98, top - 0.01), render, Vector3(11.994, top * 0.5, z0 + 1.0), Vector3.LEFT)
		_sheet(props, "StairRiser", Vector2(2.98, 0.49), render, Vector3(13.5, top - 0.25, z0 - 0.006), Vector3.FORWARD)
		_floor(props, "TreadNosing", Vector2(12.02, z0 + 0.01), Vector2(14.98, z0 + 0.09), nosing, top + 0.006)
	# Pots on the balconies against the back walls, in the walls' clearance.
	for z: float in [20.4, 26.0, 29.6]:
		_pot_plant(props, Vector3(-18.72, 3.0, z), 1.0, int(z))
		_pot_plant(props, Vector3(18.72, 3.0, z - 0.8), 0.9, int(z) + 1)
	for x: float in [-16.5, -9.0, -1.8, 5.8]:
		_pot_plant(props, Vector3(x, 3.0, 37.72), 1.0, int(x) + 4)
	# Bicycles leaning on the court's inner south wall.
	_bicycle(props, Vector3(-16.0, 0.0, 17.22), Vector3.RIGHT, PERSONAL[0])
	_bicycle(props, Vector3(15.2, 0.0, 17.22), Vector3.RIGHT, PERSONAL[4])
	# Washing on lines from the west wall top to the east, high over the yard.
	for z: float in [21.0, 25.0, 29.0]:
		for x: float in [-19.75, 19.75]:
			_shape.rod(props, "LinePost", Vector3(x, 5.0, z), Vector3(x, 5.45, z), 0.025, _mat("iron", Color("2f3231"), 0.4, 0.6), 4)
		_washing(props, Vector3(-19.75, 5.4, z), Vector3(19.75, 5.4, z), 0.55, int(z), Vector2(-14.0, 14.0))
	# Stools tucked under the meal table, inside its footprint.
	var stool: StandardMaterial3D = _mat("stool", Color("7a5a3a"), 0.0, 0.85)
	for x: float in [-1.9, -0.6, 0.7, 2.0]:
		for z: float in [27.6, 29.4]:
			if absf(x - 0.7) < 0.1 and z > 29.0:
				continue
			_shape.cylinder(props, "Stool", 0.17, 0.04, stool, Vector3(x, 0.44, z), 10).rotation.x = PI * 0.5
			for leg: int in range(3):
				var angle: float = TAU * float(leg) / 3.0 + x
				_shape.rod(props, "StoolLeg", Vector3(x, 0.42, z), Vector3(x + cos(angle) * 0.14, 0.0, z + sin(angle) * 0.14), 0.016, stool, 4)
	# A cloth runner down the table under the meal.
	_floor(props, "TableRunner", Vector2(-2.6, 28.2), Vector2(2.6, 28.8), _mat("table_runner", Color("a8552c"), 0.0, 0.95), 0.903)
	# The Union field printer: black case, red seal band, a battery case and
	# photographs fanned out. It is the only Union object in the court.
	var black: StandardMaterial3D = _mat("union_black", Color("1e1e22"), 0.3, 0.55)
	var red: StandardMaterial3D = _mat("union_red", Color("8c1a1e"), 0.2, 0.7)
	var shell: StandardMaterial3D = _mat("union_case", Color("2c2d32"), 0.4, 0.5)
	for face: Array in [[Vector3.FORWARD, Vector3(8, 0, 29)], [Vector3.BACK, Vector3(8, 0, 31)], [Vector3.LEFT, Vector3(7, 0, 30)], [Vector3.RIGHT, Vector3(9, 0, 30)]]:
		var out: Vector3 = face[0]
		_sheet(props, "PrinterCase", Vector2(1.98, 1.18), shell, (face[1] as Vector3) + Vector3(0, 0.6, 0) + out * 0.005, out)
	_floor(props, "PrinterLid", Vector2(7.01, 29.01), Vector2(8.99, 30.99), shell, 1.203)
	_sheet(props, "PrinterSlot", Vector2(1.2, 0.08), black, Vector3(8, 1.05, 28.992), Vector3.FORWARD)
	_relief(props, "PrinterBand", Vector3(2.0, 0.08, 0.01), red, Vector3(8.0, 1.0, 31.0), Vector3.BACK)
	_relief(props, "PrinterBand", Vector3(2.0, 0.08, 0.01), red, Vector3(8.0, 1.0, 29.0), Vector3.FORWARD)
	_block(props, "BatteryCase", Vector3(0.6, 0.3, 0.4), black, Vector3(8.5, 1.35, 30.6))
	_shape.pipe(props, "PrinterLead", PackedVector3Array([Vector3(8.3, 1.3, 30.6), Vector3(8.0, 1.22, 30.4), Vector3(7.7, 1.21, 30.1)]), 0.015, _mat("cable", Color("232526"), 0.0, 0.7))
	var photo: StandardMaterial3D = _mat("photo", Color("8a8f8c"), 0.0, 0.6)
	for index: int in range(6):
		var sheet: MeshInstance3D = _floor(props, "Photograph", Vector2(7.2 + float(index) * 0.13, 29.1 + float(index % 2) * 0.07), Vector2(7.42 + float(index) * 0.13, 29.38 + float(index % 2) * 0.07), photo, 1.205 + float(index) * 0.002)
		sheet.rotation.y = float(index - 2) * 0.12
	# Balcony lamps where the court gets its evening light.
	for at: Array in [[Vector3(-19.5, 4.6, 23.0), Vector3.RIGHT], [Vector3(19.5, 4.6, 28.0), Vector3.LEFT], [Vector3(-2.0, 4.6, 39.0), Vector3.FORWARD]]:
		_wall_lamp(props, at[0], at[1])
		_omni(room, "BalconyLamp", at[0] + (at[1] as Vector3) * 0.5 - Vector3(0, 0.3, 0), WARM_LAMP, 1.3, 8.0)
	_finish(room)

## A home's front door with its frame, step and a mat; `at` is the face at
## the door's sill.
func _home_door(props: Node3D, at: Vector3, out: Vector3, seed_value: int) -> void:
	var frame: StandardMaterial3D = _mat("frame_dark", Color("3b3430"), 0.0, 0.8)
	var paint: Color = PERSONAL[absi(seed_value) % PERSONAL.size()].darkened(0.15)
	_sheet(props, "HomeDoorFrame", Vector2(1.1, 2.15), frame, at + Vector3(0, 1.075, 0) + out * 0.014, out)
	_sheet(props, "HomeDoor", Vector2(0.92, 2.02), _mat("home_door_%s" % paint.to_html(false), paint, 0.0, 0.8), at + Vector3(0, 1.01, 0) + out * 0.02, out)
	var side: Vector3 = Vector3.UP.cross(out).normalized()
	_relief(props, "DoorKnob", Vector3(0.06, 0.06, 0.05), _mat("brass", Color("9a7d3e"), 0.6, 0.4), at + Vector3(0, 1.0, 0) + side * 0.33 + out * 0.02, out)
	_floor(props, "DoorMat", Vector2(0, 0), Vector2(0.8, 0.5), _mat("door_mat_%d" % (absi(seed_value) % 3), [Color("8a6a4a"), Color("6f8a6a"), Color("a8552c")][absi(seed_value) % 3], 0.0, 0.95), 0.0).position = at + out * 0.3 + Vector3(0, 0.012, 0)
	# Hand-painted numbers would be words; a small personal tile marks the
	# home instead.
	_sheet(props, "HomeTile", Vector2(0.18, 0.18), _mat("home_tile_%d" % (absi(seed_value) % 4), [Color("4f6f8a"), Color("c49a3c"), Color("8a3a58"), Color("6f8a4e")][absi(seed_value) % 4], 0.0, 0.5), at + Vector3(0, 2.3, 0) + side * -0.7 + out * 0.016, out)

# --- the roof stair's top: where the neighbours leave from ----------------------

func _build_roof_exit() -> void:
	var room: Node3D = _room("RoofExit")
	var props: Node3D = _props(room)
	var deck: float = 4.0
	# Belongings piled against the boundary wall at the deck's back edge.
	_suitcase(props, Vector3(11.8, deck, 38.75), Vector3(0.6, 0.6, 0.24), Color("7a3a22"))
	_bundle(props, Vector3(12.7, deck, 38.7), Vector3(0.6, 0.45, 0.45), PERSONAL[2], 0.1)
	_crate(props, Vector3(13.6, deck, 38.72), Vector3(0.6, 0.45, 0.45), Color("8d6c43"))
	_bundle(props, Vector3(13.6, deck + 0.45, 38.72), Vector3(0.45, 0.35, 0.35), PERSONAL[6], -0.3)
	_suitcase(props, Vector3(14.5, deck, 38.78), Vector3(0.5, 0.75, 0.2), Color("4f6f8a"))
	_bicycle(props, Vector3(15.0, deck, 38.85), Vector3.LEFT, PERSONAL[1])
	# A roof hatch frame and the warm lamp over the departure control.
	_floor(props, "RoofHatch", Vector2(11.4, 34.4), Vector2(12.6, 35.6), _mat("hatch", Color("4a4f4d"), 0.0, 0.95), deck + 0.012)
	_wall_lamp(props, Vector3(15.5, 5.85, 36.5), Vector3.LEFT)
	_omni(room, "DepartureLamp", Vector3(15.0, 5.6, 36.5), WARM_LAMP, 1.4, 6.5)
	_finish(room)
