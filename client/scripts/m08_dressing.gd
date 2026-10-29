class_name M08Dressing
extends M06Dressing

## Custodian of Record's golden-slice dressing
## (docs/campaign/l08-custodian-of-record.md, docs/design/moon.md). The
## server owns every solid; like the port's and the town's dressing this
## presenter only restyles the solid views and furnishes them: surfaces by
## use, flush fittings, small possessions against walls or on tops, overhead
## runs above head height and practical light. A body that could stop a pawn
## or a shot is never added.
##
## The archive is not the port and not the town. The port is issued bone-grey
## shell and cargo light; the town is lived paint under curfew floods. The
## archive is an institution that has stood a long time: institutional green
## enamel with a brass pinline, green linoleum, olive steel cabinets with
## brass card holders, green-shaded pendant lamps over every desk and the
## brass pneumatic tubes that carry a person's file from desk to desk.
## Evidence and captivity share the building. The hall's drawers and the
## lower gallery's box shelves hold records; the register boards hold faces,
## each with the same small red stamp; the confiscation bins at intake, the
## lost-property shelves and the bays hold what people had. The Union's own
## light is the cold issued fixture at the checkpoint, over the custody
## platforms and in the freight lane; everywhere a clerk sits it is warm.
## The cooling ring is pale frosted steel under neutral light, never cyan.

const ARCHIVE_MAP_ID: int = 1008
const PROD: String = "res://assets/environment/production/"
## The archive's footprint, the entry checkpoint, both stair towers and the
## freight lane [min_x, min_z, size].
const ARCHIVE: Rect2 = Rect2(-20, -20, 40, 40)
const FOOTPRINT: Array[Rect2] = [Rect2(-21, -21, 42, 42), Rect2(-8, -39, 16, 18), Rect2(-32, -9, 11, 20),
	Rect2(21, -11, 11, 18), Rect2(-12, 21, 24, 18)]
## Institutional colours: enamel, the dado band, brass and cabinet steel. All
## mid values, so a black-and-red guard reads against any of them. Never
## black with red, never matte off-white, never cyan.
const ENAMEL: Color = Color("8b8f7e")
const DADO: Color = Color("4f6a58")
const BRASS: Color = Color("a08446")
const CABINET: Color = Color("5f6853")
const DRAWER: Color = Color("6b7560")
const CARD: Color = Color("c4b994")
const LAMP_SHADE: Color = Color("3f5a48")
const BOXES: Array[Color] = [Color("9c7c52"), Color("8a6a48"), Color("a58a5c"), Color("7d6a4e"), Color("94805e")]
## What people had: bags, coats and bundles in their own colours.
const BELONGINGS: Array[Color] = [Color("b5652e"), Color("6f8a4e"), Color("c49a3c"), Color("8a3a58"),
	Color("4f6f8a"), Color("a8552c"), Color("7c5a8c"), Color("5f7a64"), Color("9c7c45")]
## Mid portrait tones on the register cards.
const FACES: Array[Color] = [Color("8a6a52"), Color("6e5a4a"), Color("9a7a60"), Color("5e5a56"), Color("7a6a5a"), Color("a08068")]
const PHOSPHOR: Color = Color("e0a850")
const ISSUED: Color = Color(0.90, 0.94, 0.95)
const PENDANT: Color = Color(1.0, 0.82, 0.58)
const REGIONS: Array[String] = ["Checkpoint", "HallSouth", "HallNorth", "Shaft", "LowerSouth", "LowerNorth", "LowerWest",
	"LowerEast", "UpperSouth", "Ring", "UpperEast", "Bridge", "WestTower", "EastTower", "Freight"]

static var _archive_surfaces: Dictionary[String, ShaderMaterial] = {}
var _rooms_by_name: Dictionary[String, Node3D] = {}
## The maintenance screen's line under the freight car, for the review test.
var noise_screen: WorldSign

func clear_map() -> void:
	_rooms_by_name.clear()
	noise_screen = null
	super.clear_map()

## Custodian of Record's own authored layout only, keyed on walls that never
## move: the checkpoint walls, the archive's ring walls, both stair towers
## and the freight lane. The seal, the custody machine and its support nodes
## move when the server re-sends the map, so none of them is a key. A custom
## map reusing the id with different structure gets no dressing.
static func archive_layout(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != ARCHIVE_MAP_ID or not info.get("solids") is Array:
		return false
	var wanted: Array = [
		[Vector3(-8, 0, -38), Vector3(-7, 4, -21)],
		[Vector3(-21, 0, -21), Vector3(-4, 9, -20)],
		[Vector3(11, 0, 20), Vector3(21, 9, 21)],
		[Vector3(-21, 0, 8), Vector3(-20, 9, 20)],
		[Vector3(20, 0, 4), Vector3(21, 9, 20)],
		[Vector3(-32, 0, -9), Vector3(-31, 6.3, 11)],
		[Vector3(31, 0, -11), Vector3(32, 9, 7)],
		[Vector3(-12, 0, 38), Vector3(12, 9, 39)],
		[Vector3(-16, 3, -12), Vector3(-12, 4.1, -11)],
	]
	for pair: Array in wanted:
		if M06Workmanship._host(info["solids"], pair[0], pair[1]).is_empty():
			return false
	return true

# --- surfaces ---------------------------------------------------------------

## Restyle the server's solid views by use: green enamel walls with a brass
## pinline, linoleum decks over dark coffered undersides, olive desks,
## galvanised rails and screens, issued steel stairs and platforms, frosted
## cooling pipes, the custody machine in dark issued steel and freight paint
## in the lane, plus a tiled floor that keeps its own lights.
static func restyle_archive(cover: Node3D, info: Dictionary, views: Array[MeshInstance3D]) -> void:
	if not archive_layout(info) or not info.get("presentation") is Dictionary:
		return
	var solids: Array = info["solids"]
	var surfaces: Array = info["presentation"].get("solids", [])
	if surfaces.size() != solids.size() or views.size() != solids.size():
		return
	for index: int in range(solids.size()):
		if not solids[index] is Dictionary or not is_instance_valid(views[index]):
			continue
		var box: AABB = _bounds(solids[index])
		var role: String = archive_role(box, str(surfaces[index]))
		if role == "crate" or role == "car":
			views[index].material_override = freight_paint(FREIGHT[_hash(box.get_center()) % FREIGHT.size()] if role == "crate" else Color("68724f"))
		else:
			views[index].material_override = archive_surface(role)
	var floor: MeshInstance3D = cover.get_node_or_null("MapFloor") as MeshInstance3D
	if floor != null:
		floor.visible = false
	var ground: Node3D = Node3D.new()
	ground.name = "M08Floors"
	cover.add_child(ground)
	for rect: Rect2 in FOOTPRINT:
		var x: float = rect.position.x
		while x < rect.end.x - 0.01:
			var width: float = minf(FLOOR_TILE, rect.end.x - x)
			var z: float = rect.position.y
			while z < rect.end.y - 0.01:
				var depth: float = minf(FLOOR_TILE, rect.end.y - z)
				var centre: Vector3 = Vector3(x + width * 0.5, 0.0, z + depth * 0.5)
				var finish: String = "lino" if ARCHIVE.has_point(Vector2(centre.x, centre.z)) else ("lane" if centre.z > 21.0 else "deck")
				_plane(ground, "ArchiveFloor%d" % ground.get_child_count(), centre, Vector2(width, depth), archive_surface(finish))
				z += depth
			x += width
	# Dark coffered ceilings under both gallery decks, so the linoleum on top
	# never shows through overhead.
	var ring: Array[Rect2] = [Rect2(-20, -20, 40, 14), Rect2(-20, -6, 14, 12), Rect2(6, -6, 14, 12)]
	for level: float in [2.69, 5.69]:
		var rects: Array[Rect2] = ring.duplicate()
		if level < 3.0:
			rects.append(Rect2(-20, 6, 40, 14))
		else:
			rects.append_array([Rect2(-20, 6, 16, 14), Rect2(6, 6, 14, 14)])
		for rect: Rect2 in rects:
			var cx: float = rect.position.x
			while cx < rect.end.x - 0.01:
				var width: float = minf(FLOOR_TILE, rect.end.x - cx)
				var cz: float = rect.position.y
				while cz < rect.end.y - 0.01:
					var depth: float = minf(FLOOR_TILE, rect.end.y - cz)
					var tile: MeshInstance3D = _plane(ground, "ArchiveCeiling%d" % ground.get_child_count(), Vector3(cx + width * 0.5, level, cz + depth * 0.5),
						Vector2(width, depth), archive_surface("coffer"))
					tile.rotation.x = PI
					cz += depth
				cx += width
	ArenaSky.mark_world(ground)

## A solid's visual role from its registered surface and where it stands.
static func archive_role(box: AABB, surface: String) -> String:
	var low: Vector3 = box.position
	var high: Vector3 = box.end
	var centre: Vector3 = box.get_center()
	var thin: float = minf(box.size.x, box.size.z)
	match surface:
		"enamel":
			if box.size.y <= 0.35 and low.y >= 3.9:
				return "ceiling"
			if centre.z > 21.0:
				return "lane_wall"
			if high.z <= -20.99:
				return "checkpoint"
			return "archive"
		"records_tile":
			if box.size.y <= 0.35:
				return "slab"
			return "desk"
		"lift_panel":
			if box.size.x <= 0.81 and box.size.z <= 0.81:
				return "machine"
			if box.size.y >= 2.9 or (thin <= 0.31 and low.y >= 8.9):
				return "seal"
			if box.size.y >= 2.1 and thin >= 0.99:
				return "cabinet"
			return "panel"
	# Issued steel.
	if absf(centre.x) < 3.1 and absf(centre.z) < 3.1 and box.size.x >= 3.5:
		return "machine"
	if centre.z >= 34.0 and box.size.x >= 5.9:
		return "car"
	if centre.z > 25.0 and absf(centre.x) < 5.5:
		return "crate"
	if is_equal_approx(box.size.x, 1.0) and is_equal_approx(box.size.z, 1.0) and low.y >= 5.9:
		return "pipe"
	if low.y >= 5.65 and high.y <= 6.05 and box.size.x >= 9.0:
		return "bridge"
	if absf(centre.x) <= 6.4 and absf(centre.z) <= 6.4 and thin <= 0.31:
		return "screen" if box.size.y >= 2.6 else "rail"
	if thin <= 0.31 and box.size.y <= 1.25:
		return "rail"
	if centre.z > 21.0 or low.x <= -21.0 or high.x >= 21.0:
		return "stair"
	if (low.x >= 3.4 and high.z <= -20.9) or (low.x >= 13.9 and low.z >= 13.9) or low.x <= -20.0 and box.size.y <= 2.5:
		return "cage"
	if high.z >= 20.0 and absf(centre.x) > 5.0 and box.size.y >= 5.9:
		return "archive"
	if thin <= 0.41:
		return "rail"
	return "platform"

static func archive_surface(role: String) -> ShaderMaterial:
	if _archive_surfaces.has(role):
		return _archive_surfaces[role]
	var material: ShaderMaterial
	match role:
		"archive":
			# Institutional enamel: a green dado band at each deck under a
			# brass pinline that never glows.
			material = _material(ENAMEL, PROD + "archive_plaster.png", PROD + "archive_floor.png", 2, DADO, 0.18)
			material.set_shader_parameter("warning_color", BRASS)
			material.set_shader_parameter("deck_spacing", 3.0)
			material.set_shader_parameter("panel_size", 3.0)
			material.set_shader_parameter("sector_variation", 0.04)
		"checkpoint":
			# Intake is the Union's issued front: colder grey enamel, ochre pinline.
			material = _material(Color("7d817e"), PROD + "lunar_plaster.png", MOON + "moon_worn_deck.png", 2, Color("5a605e"), 0.14)
			material.set_shader_parameter("warning_color", OCHRE)
			material.set_shader_parameter("deck_spacing", 4.0)
			material.set_shader_parameter("panel_size", 2.5)
		"lane_wall":
			material = _material(Color("75736b"), PROD + "lunar_concrete.png", PROD + "lunar_concrete.png", 1, Color("5e5b54"), 0.35)
			material.set_shader_parameter("panel_size", 3.0)
		"coffer":
			material = _material(Color("4d524e"), PROD + "archive_steel.png", PROD + "archive_steel.png", 3, Color("434845"), 0.35)
			material.set_shader_parameter("panel_size", 2.0)
		"ceiling":
			material = _material(Color("454a47"), PROD + "archive_steel.png", PROD + "archive_steel.png", 3, Color("3c403e"), 0.4)
			material.set_shader_parameter("panel_size", 3.0)
		"slab":
			# Green linoleum on top, dark coffered steel underneath.
			material = _material(Color("5f6b58"), PROD + "archive_steel.png", PROD + "archive_floor.png", 1, Color("4a5446"), 0.4)
			material.set_shader_parameter("tile_floor_strength", 0.35)
			material.set_shader_parameter("panel_size", 3.0)
			material.set_shader_parameter("macro_variation", 0.05)
		"lino":
			material = _material(Color("5f6b58"), PROD + "archive_floor.png", PROD + "archive_floor.png", 1, Color("4a5446"), 0.35)
			material.set_shader_parameter("panel_size", 3.0)
			material.set_shader_parameter("macro_variation", 0.05)
		"deck":
			material = _material(Color("6c6f6b"), MOON + "moon_worn_deck.png", MOON + "moon_worn_deck.png", 1, Color("5a5d5a"), 0.45)
			material.set_shader_parameter("panel_size", 2.0)
		"lane":
			material = _material(Color("6e6c66"), PROD + "lunar_concrete.png", PROD + "lunar_concrete.png", 1, Color("5e5b54"), 0.4)
			material.set_shader_parameter("panel_size", 3.0)
			material.set_shader_parameter("macro_variation", 0.06)
		"desk":
			# Olive steel desks with green linoleum tops.
			material = _material(Color("6a6650"), PROD + "lunar_steel.png", PROD + "archive_floor.png", 3, Color("5a5744"), 0.3)
			material.set_shader_parameter("panel_size", 1.0)
		"rail":
			material = _material(Color("6e726d"), PROD + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, OCHRE, 0.3)
			material.set_shader_parameter("panel_size", 1.2)
		"screen":
			material = _material(Color("5e635f"), PROD + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, Color("50554f"), 0.4)
			material.set_shader_parameter("panel_size", 1.35)
		"stair":
			material = _material(Color("676a66"), PROD + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, OCHRE, 0.45)
			material.set_shader_parameter("panel_size", 1.0)
		"cage":
			material = _material(Color("62665f"), PROD + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, Color("575b55"), 0.35)
			material.set_shader_parameter("panel_size", 0.75)
		"platform":
			material = _material(Color("555b5a"), PROD + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, Color("6f6a58"), 0.3)
			material.set_shader_parameter("panel_size", 1.0)
		"bridge":
			material = _material(Color("5c605d"), PROD + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, Color("50544f"), 0.45)
			material.set_shader_parameter("panel_size", 1.0)
		"machine":
			# The custody machine and its nodes: dark issued steel, no paint
			# that glows; the presenter's node lamps carry the target read.
			material = _material(Color("3e4344"), MOON + "moon_union_service.png", PROD + "lunar_steel.png", 3, Color("5c6264"), 0.5)
			material.set_shader_parameter("panel_size", 1.0)
		"pipe":
			material = _material(Color("8a9192"), PROD + "lunar_steel.png", PROD + "lunar_steel.png", 3, Color("7a8182"), 0.2)
			material.set_shader_parameter("panel_size", 0.75)
		"seal":
			material = _material(Color("5a5d5b"), PROD + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, OCHRE, 0.4)
			material.set_shader_parameter("panel_size", 1.0)
		"cabinet":
			material = _material(Color("6e777b"), PROD + "lunar_steel.png", PROD + "lunar_steel.png", 3, Color("5f686c"), 0.3)
			material.set_shader_parameter("panel_size", 0.55)
		_:
			material = _material(Color("55595a"), PROD + "lunar_steel.png", PROD + "lunar_steel.png", 3, Color("4c5051"), 0.4)
	_archive_surfaces[role] = material
	return material

# --- rooms ------------------------------------------------------------------

func configure_map(info: Dictionary) -> void:
	if active() and archive_layout(info):
		return
	clear_map()
	if not archive_layout(info):
		return
	for label: String in REGIONS:
		_rooms_by_name[label] = _room(label)
	_build_checkpoint()
	_build_hall()
	_build_lost_property()
	_build_shaft()
	_build_lower()
	_build_bays()
	_build_alcove()
	_build_upper()
	_build_ring()
	_build_bridge()
	_build_towers()
	_build_freight()
	for room: Node3D in _unattached:
		_finish(room)
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

func _mat(key: String, tint: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	return _shape.material("m08_" + key, tint, metallic, roughness)

## The room a world point belongs to, so each merged mesh stays local and
## carries its own nearby lights.
static func region(p: Vector3) -> String:
	if p.z < -20.5:
		return "Checkpoint"
	if p.z > 21.0:
		return "Freight"
	if p.x < -20.5:
		return "WestTower"
	if p.x > 20.5:
		return "EastTower"
	if absf(p.x) < 6.3 and absf(p.z) < 6.3:
		return "Shaft"
	if p.y < 2.7:
		return "HallSouth" if p.z < 0.0 else "HallNorth"
	if p.y < 5.7:
		if p.z < -6.0:
			return "LowerSouth"
		if p.z > 6.0:
			return "LowerNorth"
		return "LowerWest" if p.x < 0.0 else "LowerEast"
	if p.x < -6.0:
		return "Ring"
	if p.z < -6.0:
		return "UpperSouth"
	if p.z > 6.0:
		return "Bridge"
	return "UpperEast"

func _at(p: Vector3) -> Node3D:
	return _props(_rooms_by_name[region(p)])

func _room_at(p: Vector3) -> Node3D:
	return _rooms_by_name[region(p)]

func _piece(label: String, size: Vector3, finish: Material, at: Vector3) -> MeshInstance3D:
	return _block(_at(at), label, size, finish, at)

func _rod(label: String, a: Vector3, b: Vector3, radius: float, finish: StandardMaterial3D, segments: int = 6) -> MeshInstance3D:
	return _shape.rod(_at((a + b) * 0.5), label, a, b, radius, finish, segments)

## A box standing on `base` against a wall whose room side faces `outward`:
## `w` along the wall, `h` up, `d` out into the room.
func _flush(label: String, finish: Material, base: Vector3, outward: Vector3, w: float, h: float, d: float) -> MeshInstance3D:
	var size: Vector3 = Vector3(d, h, w) if absf(outward.x) > 0.5 else Vector3(w, h, d)
	return _piece(label, size, finish, base + outward * (d * 0.5) + Vector3(0, h * 0.5, 0))

## Runs along a wall: +x on the south wall, -x on the north, -z on the
## west and +z on the east.
static func _along(outward: Vector3) -> Vector3:
	return Vector3(outward.z, 0, -outward.x)

## A green-shaded pendant over a desk or an aisle: cable, shade, a warm bulb
## and a short warm pool. The archive's light is where people sit.
func _pendant(at: Vector3, ceiling: float, energy: float = 1.5, reach: float = 7.5) -> OmniLight3D:
	energy *= 1.6
	reach = minf(reach + 1.0, 9.0)
	var shade: StandardMaterial3D = _mat("pendant_shade", LAMP_SHADE, 0.3, 0.6)
	var cable: StandardMaterial3D = _mat("pendant_cable", Color("2f3231"), 0.3, 0.7)
	var cone: MeshInstance3D = _shape.lathe(_at(at), "PendantShade", PackedVector2Array([Vector2(0.0, 0.06), Vector2(0.07, 0.1), Vector2(0.17, 0.25)]), shade, at + Vector3(0, 0.15, 0), 10)
	cone.rotation.x = PI * 0.5
	_piece("PendantCap", Vector3(0.14, 0.04, 0.14), shade, at + Vector3(0, 0.16, 0))
	_piece("PendantBulb", Vector3(0.12, 0.08, 0.12), _glow("pendant_bulb", Color("ffd9a0"), 2.4), at + Vector3(0, 0.02, 0))
	if ceiling > at.y + 0.2:
		_rod("PendantCable", at + Vector3(0, 0.15, 0), Vector3(at.x, ceiling, at.z), 0.01, cable, 4)
	var light: OmniLight3D = _omni(_room_at(at), "PendantLamp", at + Vector3(0, -0.12, 0), PENDANT, energy, reach)
	# A flatter falloff so each desk sits in a visible warm pool.
	light.omni_attenuation = 0.9
	return light

## A bank of four-drawer olive cabinets along a wall: drawer fronts, brass
## pulls and a pale card in every holder. Each drawer is somebody's file.
func _cabinets(start: Vector3, outward: Vector3, count: int, seed_value: int) -> void:
	var along: Vector3 = _along(outward)
	var body: StandardMaterial3D = _mat("cabinet", CABINET, 0.2, 0.7)
	var front: StandardMaterial3D = _mat("drawer", DRAWER, 0.2, 0.65)
	var brass: StandardMaterial3D = _mat("brass", BRASS, 0.5, 0.5)
	var card: StandardMaterial3D = _mat("card", CARD)
	var pulled: StandardMaterial3D = _mat("drawer_dark", Color("4b5343"), 0.2, 0.7)
	for index: int in range(count):
		var base: Vector3 = start + along * (0.95 * float(index) + 0.45)
		_flush("RecordsCabinet", body, base, outward, 0.9, 1.5, 0.42)
		for drawer: int in range(4):
			var y: float = 0.22 + float(drawer) * 0.35
			var open: bool = (seed_value + index * 7 + drawer * 3) % 23 == 0
			var depth: float = 0.2 if open else 0.02
			_flush("CabinetDrawer", pulled if open else front, base + Vector3(0, y - 0.14, 0) + outward * 0.42, outward, 0.8, 0.3, depth)
			_flush("DrawerCard", card, base + Vector3(0, y + 0.04, 0) + outward * (0.42 + depth), outward, 0.16, 0.07, 0.01)
			_flush("DrawerPull", brass, base + Vector3(0, y - 0.06, 0) + outward * (0.42 + depth), outward, 0.2, 0.03, 0.03)

## Open steel shelving of archive boxes, a pale label on each box.
func _shelving(start: Vector3, outward: Vector3, length: float, seed_value: int) -> void:
	var along: Vector3 = _along(outward)
	var steel: StandardMaterial3D = _mat("shelf_steel", Color("5c605a"), 0.4, 0.6)
	var label: StandardMaterial3D = _mat("card", CARD)
	var uprights: int = maxi(2, int(length / 1.2) + 1)
	var step: float = length / float(uprights - 1)
	for index: int in range(uprights):
		_flush("ShelfUpright", steel, start + along * (step * float(index)), outward, 0.05, 2.3, 0.5)
	for level: int in range(4):
		var y: float = 0.15 + float(level) * 0.55
		_flush("Shelf", steel, start + along * (length * 0.5) + Vector3(0, y, 0), outward, length, 0.03, 0.5)
		var x: float = 0.1
		var count: int = 0
		while x < length - 0.45:
			var pick: int = (seed_value + level * 13 + count * 7) % 11
			var width: float = 0.32 + float(pick % 3) * 0.05
			if pick != 4:
				var at: Vector3 = start + along * (x + width * 0.5) + Vector3(0, y + 0.03, 0)
				var tint: Color = BOXES[(seed_value + level + count) % BOXES.size()]
				_flush("ArchiveBox", _mat("box_%s" % tint.to_html(false), tint, 0.0, 0.9), at, outward, width - 0.03, 0.3, 0.38)
				_flush("BoxLabel", label, at + Vector3(0, 0.12, 0) + outward * 0.38, outward, 0.12, 0.06, 0.005)
			x += width
			count += 1

## A register board: rows of small cards, a portrait square and the same red
## stamp on each. How a person becomes a registered asset, without a word.
func _register(centre: Vector3, outward: Vector3, columns: int, rows: int, seed_value: int) -> void:
	var along: Vector3 = _along(outward)
	var board: StandardMaterial3D = _mat("register_board", Color("5a5040"), 0.0, 0.9)
	var card: StandardMaterial3D = _mat("card", CARD)
	var stamp: StandardMaterial3D = _mat("red_tag", SEAL_RED)
	var width: float = float(columns) * 0.3 + 0.2
	var height: float = float(rows) * 0.36 + 0.2
	_flush("RegisterBoard", board, centre - Vector3(0, height * 0.5, 0), outward, width, height, 0.03)
	for column: int in range(columns):
		for row: int in range(rows):
			var at: Vector3 = centre + along * (-width * 0.5 + 0.25 + float(column) * 0.3) + Vector3(0, height * 0.5 - 0.3 - float(row) * 0.36, 0) + outward * 0.03
			if (seed_value + column * 5 + row * 3) % 9 == 0:
				continue
			_flush("RegisterCard", card, at - Vector3(0, 0.14, 0), outward, 0.22, 0.3, 0.008)
			var face: Color = FACES[(seed_value + column + row * 2) % FACES.size()]
			_flush("RegisterFace", _mat("face_%s" % face.to_html(false), face), at - Vector3(0, 0.0, 0) + along * -0.03, outward, 0.1, 0.12, 0.012)
			_flush("RegisterStamp", stamp, at - Vector3(0, 0.1, 0) + along * 0.05, outward, 0.06, 0.05, 0.014)

## Desk work on an existing desk top: a terminal with a warm phosphor face, a
## stamp rack, trays of forms and a card file.
func _desk_top(top: Vector3, along_x: bool, seed_value: int) -> void:
	var case: StandardMaterial3D = _mat("terminal_case", Color("6a6656"), 0.2, 0.7)
	var screen: StandardMaterial3D = _glow("phosphor", PHOSPHOR.darkened(0.35), 0.9)
	var paper: StandardMaterial3D = _mat("paper", Color("c8bfa0"))
	var tray: StandardMaterial3D = _mat("tray", Color("4e5446"), 0.3, 0.6)
	var ink: StandardMaterial3D = _mat("stamp_ink", Color("2f2c2a"))
	var axis: Vector3 = Vector3.RIGHT if along_x else Vector3.BACK
	var t: Vector3 = top + axis * (0.6 if seed_value % 2 == 0 else -0.6)
	_piece("Terminal", Vector3(0.42, 0.36, 0.4), case, t + Vector3(0, 0.18, 0))
	var face: Vector3 = Vector3(0, 0, 0.21) if along_x else Vector3(0.21, 0, 0)
	_piece("TerminalScreen", Vector3(0.3, 0.22, 0.01) if along_x else Vector3(0.01, 0.22, 0.3), screen, t + Vector3(0, 0.2, 0) + face * (1.0 if seed_value % 3 != 0 else -1.0))
	var p: Vector3 = top - axis * 0.15
	_piece("FormTray", Vector3(0.36, 0.05, 0.28), tray, p + Vector3(0, 0.025, 0))
	_piece("Forms", Vector3(0.3, 0.04, 0.22), paper, p + Vector3(0, 0.06, 0))
	_piece("FormTray", Vector3(0.36, 0.05, 0.28), tray, p + Vector3(0, 0.1, 0))
	var s: Vector3 = top - axis * 0.55
	_piece("StampRack", Vector3(0.24, 0.04, 0.1), tray, s + Vector3(0, 0.02, 0))
	for index: int in range(3):
		_piece("Stamp", Vector3(0.04, 0.09, 0.04), ink, s + Vector3(-0.07 + index * 0.07, 0.085, 0))
	_piece("CardFile", Vector3(0.18, 0.12, 0.3), _mat("card_file", Color("7a5f42")), top + axis * -0.95 + Vector3(0, 0.06, 0))

## A brass pneumatic tube run overhead: the archive's own circulation.
func _tube(points: Array[Vector3]) -> void:
	var brass: StandardMaterial3D = _mat("tube_brass", Color("8f7744"), 0.55, 0.45)
	var clamp: StandardMaterial3D = _mat("tube_clamp", Color("3f4240"), 0.4, 0.6)
	for index: int in range(points.size() - 1):
		_rod("PneumaticTube", points[index], points[index + 1], 0.045, brass)
		var span: Vector3 = points[index + 1] - points[index]
		var clamps: int = int(span.length() / 2.5)
		for c: int in range(1, clamps):
			_piece("TubeClamp", Vector3(0.14, 0.12, 0.14), clamp, points[index] + span * (float(c) / float(clamps)))

## A tube station: the drop where a canister lands at a desk.
func _tube_station(at: Vector3, ceiling: float) -> void:
	var brass: StandardMaterial3D = _mat("tube_brass", Color("8f7744"), 0.55, 0.45)
	_rod("TubeDrop", Vector3(at.x, ceiling - 0.15, at.z), at + Vector3(0, 0.3, 0), 0.045, brass)
	_piece("TubeReceiver", Vector3(0.24, 0.36, 0.24), _mat("tube_receiver", Color("5a5e52"), 0.3, 0.6), at + Vector3(0, 0.12, 0))
	_piece("Canister", Vector3(0.1, 0.22, 0.1), brass, at + Vector3(0.0, 0.36, 0.17))

# --- checkpoint -------------------------------------------------------------

## Intake: painted queue lanes to the desk, the confiscation bins along the
## west wall, a form rack on the east wall, the Union's two banners and a
## camera at the hall opening, and cold issued pools over the queue.
func _build_checkpoint() -> void:
	var room: Node3D = _rooms_by_name["Checkpoint"]
	var props: Node3D = _props(room)
	var paint: StandardMaterial3D = _mat("lane_paint", Color("a89462"))
	for x: float in [-2.6, 0.0, 2.6]:
		_paint_line(props, Vector3(x, 0, -37.5), Vector3(x, 0, -27.0), 0.08, paint)
	for x: float in [-1.3, 1.3]:
		for z: float in [-27.2, -29.4, -31.6]:
			_block(props, "StandHere", Vector3(0.7, 0.006, 0.18), paint, Vector3(x, 0.004, z))
	_desk_top(Vector3(0, 1.1, -25.8), true, 1)
	_desk_top(Vector3(-1.9, 1.1, -25.8), true, 4)
	_pendant(Vector3(-1.0, 3.3, -25.4), 4.0, 1.3, 6.0)
	# Confiscation bins: open-top crates against the west wall, each full of
	# somebody's things, each with a red destruction tag.
	for index: int in range(5):
		var base: Vector3 = Vector3(-7.0, 0, -36.5 + float(index) * 1.6)
		_flush("ConfiscationBin", _mat("bin", Color("575d55"), 0.3, 0.6), base, Vector3.RIGHT, 1.3, 0.75, 0.6)
		for item: int in range(3):
			var tint: Color = BELONGINGS[(index * 3 + item) % BELONGINGS.size()]
			var size: Vector3 = [Vector3(0.35, 0.2, 0.4), Vector3(0.5, 0.15, 0.3), Vector3(0.25, 0.25, 0.25)][item]
			var bag: MeshInstance3D = _block(props, "Belonging", size, _mat("belonging_%s" % tint.to_html(false), tint, 0.0, 0.9),
				base + Vector3(0.3, 0.76 + size.y * 0.3, -0.4 + float(item) * 0.4))
			bag.rotation.y = float(index + item) * 0.4
		_red_tag(props, base + Vector3(0.62, 0.55, 0.3), "east")
	# The east wall's rack of blank forms.
	var rack: StandardMaterial3D = _mat("form_rack", Color("5f644f"), 0.2, 0.7)
	var paper: StandardMaterial3D = _mat("paper", Color("c8bfa0"))
	_flush("FormRack", rack, Vector3(7.0, 1.0, -34.0), Vector3.LEFT, 2.4, 1.2, 0.18)
	for column: int in range(6):
		for row: int in range(3):
			_flush("FormStack", paper, Vector3(7.0, 1.12 + float(row) * 0.38, -35.0 + float(column) * 0.4), Vector3.LEFT, 0.28, 0.22, 0.2)
	# Two black banners with the original red seal flank the hall opening.
	for x: float in [-6.0, 6.0]:
		_banner_south(props, Vector3(x, 0, -21.0))
	# A camera over the opening, its small red optic is Union hardware.
	var arm: StandardMaterial3D = _mat("camera_arm", Color("2f3132"), 0.4, 0.6)
	_rod("CameraArm", Vector3(4.6, 3.95, -21.05), Vector3(4.2, 3.6, -21.6), 0.03, arm)
	_piece("CameraBody", Vector3(0.22, 0.2, 0.42), arm, Vector3(4.15, 3.5, -21.75))
	_piece("CameraOptic", Vector3(0.06, 0.06, 0.02), _glow("camera_optic", Color("c43a32"), 1.2), Vector3(4.15, 3.5, -21.97))
	for z: float in [-35.0, -30.0, -24.0]:
		_pool(room, Vector3(0, 3.7, z), 1.7, 8.0, 44.0, 4.0)
	_dust(props, Vector3(0, 0, -37.6), Vector2(5.0, 0.9), 14, 3)

func _banner_south(props: Node3D, wall: Vector3) -> void:
	var cloth: StandardMaterial3D = _mat("banner_black", Color("1e2022"), 0.0, 0.95)
	var seal: StandardMaterial3D = _mat("red_tag", SEAL_RED)
	var pole: StandardMaterial3D = _mat("banner_pole", Color("4a4c4a"), 0.5, 0.5)
	_block(props, "BannerPole", Vector3(1.3, 0.05, 0.05), pole, wall + Vector3(0, 3.75, -0.08))
	_block(props, "Banner", Vector3(1.1, 2.5, 0.02), cloth, wall + Vector3(0, 2.45, -0.06))
	_block(props, "BannerSeal", Vector3(0.5, 0.5, 0.01), seal, wall + Vector3(0, 2.9, -0.075))
	_block(props, "BannerSealCore", Vector3(0.24, 0.24, 0.01), cloth, wall + Vector3(0, 2.9, -0.082))

# --- records hall -----------------------------------------------------------

## The records hall: drawers on every outer wall in runs, register boards
## between the runs, desk work on every desk under a green pendant, brass
## tubes overhead and painted queue lanes from the opening to the desks.
func _build_hall() -> void:
	# Cabinet runs [start, outward, count], gaps hold boards and stations.
	var runs: Array = [
		[Vector3(-19.8, 0, -20), Vector3.BACK, 5], [Vector3(-12.6, 0, -20), Vector3.BACK, 7],
		[Vector3(5.2, 0, -20), Vector3.BACK, 7], [Vector3(13.6, 0, -20), Vector3.BACK, 6],
		[Vector3(8.0, 0, 20), Vector3.FORWARD, 8],
		[Vector3(-3.4, 0, 20), Vector3.FORWARD, 7], [Vector3(-12.4, 0, 20), Vector3.FORWARD, 7],
		[Vector3(-20, 0, 19.8), Vector3.RIGHT, 6], [Vector3(-20, 0, 12.0), Vector3.RIGHT, 7],
		[Vector3(-20, 0, 2.6), Vector3.RIGHT, 5], [Vector3(-20, 0, -8.2), Vector3.RIGHT, 5],
		[Vector3(20, 0, -19.8), Vector3.LEFT, 6], [Vector3(20, 0, -12.0), Vector3.LEFT, 7],
		[Vector3(20, 0, -2.6), Vector3.LEFT, 6], [Vector3(20, 0, 6.6), Vector3.LEFT, 7],
	]
	for index: int in range(runs.size()):
		var run: Array = runs[index]
		_cabinets(run[0], run[1], run[2], index * 5)
	# Register boards over the gaps between runs.
	for board: Array in [[Vector3(-14.6, 2.0, -19.97), Vector3.BACK], [Vector3(11.8, 2.0, -19.97), Vector3.BACK],
		[Vector3(-19.97, 2.0, -1.2), Vector3.RIGHT], [Vector3(19.97, 2.0, 4.6), Vector3.LEFT],
		[Vector3(0.0, 2.0, 19.97), Vector3.FORWARD], [Vector3(-19.97, 2.0, 10.4), Vector3.RIGHT]]:
		_register(board[0], board[1], 5, 2, int(board[0].x + board[0].z))
	# Desk work on the six hall desks.
	_desk_top(Vector3(-12.5, 1.1, -13.5), true, 0)
	_desk_top(Vector3(12.5, 1.1, -13.5), true, 1)
	_desk_top(Vector3(-13.5, 1.1, 4.0), false, 2)
	_desk_top(Vector3(13.5, 1.1, -2.0), false, 3)
	_desk_top(Vector3(-1.8, 1.1, 12.5), true, 4)
	_desk_top(Vector3(1.9, 1.1, 12.5), true, 5)
	_desk_top(Vector3(10.5, 1.1, 9.5), true, 6)
	# Green pendants over each desk and along the aisles.
	for at: Vector3 in [Vector3(-12.5, 2.25, -13.5), Vector3(12.5, 2.25, -13.5), Vector3(-13.5, 2.25, 4.0),
		Vector3(13.5, 2.25, -2.0), Vector3(0, 2.25, 12.5), Vector3(10.5, 2.25, 9.5),
		Vector3(-15.5, 2.25, -4.5), Vector3(15.5, 2.25, 13.0), Vector3(-15.5, 2.25, 15.5), Vector3(0, 2.25, -15.5),
		Vector3(-6.5, 2.25, 16.5), Vector3(15.5, 2.25, -16.5), Vector3(-17, 2.25, -17)]:
		_pendant(at, 2.7, 1.5, 7.5)
	# Brass tubes along the ceiling, round the hall and down to the desks.
	var y: float = 2.52
	_tube([Vector3(-17, y, -17), Vector3(17, y, -17), Vector3(17, y, 17), Vector3(-17, y, 17), Vector3(-17, y, -17)])
	for station: Vector3 in [Vector3(-11.3, 1.1, -13.5), Vector3(11.3, 1.1, -13.5), Vector3(-13.5, 1.1, 5.4),
		Vector3(13.5, 1.1, -0.6), Vector3(3.6, 1.1, 12.5)]:
		var drop: Vector3 = Vector3(station.x, y, station.z)
		var ring: Vector3 = drop
		if absf(station.z) > absf(station.x):
			ring.z = 17.0 * signf(station.z)
		else:
			ring.x = 17.0 * signf(station.x)
		_tube([ring, drop])
		_tube_station(station, 2.7)
	# Queue lanes from the opening to the first desks.
	var hall: Node3D = _props(_rooms_by_name["HallSouth"])
	var paint: StandardMaterial3D = _mat("lane_paint", Color("a89462"))
	_paint_line(hall, Vector3(-3.6, 0, -19.6), Vector3(-11.0, 0, -14.6), 0.08, paint)
	_paint_line(hall, Vector3(3.6, 0, -19.6), Vector3(11.0, 0, -14.6), 0.08, paint)
	for x: float in [-12.5, 12.5]:
		_block(hall, "StandHere", Vector3(0.7, 0.006, 0.18), paint, Vector3(x, 0.004, -14.6))
	# Filing carts parked in the gaps, a few files riding on each.
	for cart: Array in [[Vector3(-8.4, 0, -19.4), true], [Vector3(-19.4, 0, -5.0), false], [Vector3(4.6, 0, 19.4), true]]:
		_cart(cart[0], cart[1])

func _cart(at: Vector3, along_x: bool) -> void:
	var steel: StandardMaterial3D = _mat("shelf_steel", Color("5c605a"), 0.4, 0.6)
	var size: Vector3 = Vector3(0.9, 0.04, 0.45) if along_x else Vector3(0.45, 0.04, 0.9)
	for y: float in [0.25, 0.75]:
		_piece("CartShelf", size, steel, at + Vector3(0, y, 0))
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var offset: Vector3 = Vector3(corner.x * (size.x * 0.5 - 0.03), 0, corner.y * (size.z * 0.5 - 0.03))
		_piece("CartPost", Vector3(0.03, 0.8, 0.03), steel, at + offset + Vector3(0, 0.45, 0))
		_piece("CartWheel", Vector3(0.06, 0.08, 0.06), _mat("rubber", Color("2a2b2a")), at + offset + Vector3(0, 0.04, 0))
	for index: int in range(3):
		var tint: Color = BOXES[index % BOXES.size()]
		_piece("CartFile", Vector3(0.22, 0.28, 0.32) if along_x else Vector3(0.32, 0.28, 0.22), _mat("box_%s" % tint.to_html(false), tint, 0.0, 0.9),
			at + (Vector3(-0.28 + index * 0.28, 0.91, 0) if along_x else Vector3(0, 0.91, -0.28 + index * 0.28)))

## Lost property: what the archive kept from people, on shelves and tagged.
func _build_lost_property() -> void:
	var props: Node3D = _props(_rooms_by_name["HallNorth"])
	var steel: StandardMaterial3D = _mat("shelf_steel", Color("5c605a"), 0.4, 0.6)
	_flush("PropertyShelf", steel, Vector3(17.2, 1.2, 20.0), Vector3.FORWARD, 5.2, 0.03, 0.45)
	_flush("PropertyShelf", steel, Vector3(17.2, 1.8, 20.0), Vector3.FORWARD, 5.2, 0.03, 0.45)
	for index: int in range(9):
		var tint: Color = BELONGINGS[index % BELONGINGS.size()]
		var finish: StandardMaterial3D = _mat("belonging_%s" % tint.to_html(false), tint, 0.0, 0.9)
		var x: float = 15.0 + float(index % 5) * 1.0
		var y: float = 1.23 if index < 5 else 1.83
		_flush("TaggedBag", finish, Vector3(x, y, 20.0), Vector3.FORWARD, 0.5, 0.32 + float(index % 3) * 0.06, 0.34)
		_red_tag(props, Vector3(x + 0.18, y + 0.12, 19.6), "south")
	# A pair of boots, a guitar case and a child's toy under the shelves.
	var leather: StandardMaterial3D = _mat("leather", Color("6a4a32"), 0.0, 0.8)
	for x: float in [15.2, 15.45]:
		_block(props, "Boot", Vector3(0.14, 0.24, 0.3), leather, Vector3(x, 0.12, 19.5))
	var case: MeshInstance3D = _block(props, "InstrumentCase", Vector3(0.38, 1.0, 0.14), _mat("case_green", Color("4f6a4e"), 0.0, 0.8), Vector3(19.6, 0.5, 18.4))
	case.rotation.z = 0.2
	_block(props, "ToyBlock", Vector3(0.16, 0.16, 0.16), _mat("toy_yellow", Color("c49a3c")), Vector3(16.6, 0.08, 19.2))
	_block(props, "ToyBlock", Vector3(0.14, 0.14, 0.14), _mat("toy_blue", Color("4f6f8a")), Vector3(16.8, 0.07, 19.0))
	_pendant(Vector3(17.0, 2.25, 17.0), 2.7, 1.2, 6.0)

# --- the shaft ----------------------------------------------------------------

## The shaft through every floor: ribbed screens and rails, a hoist frame
## under the roof, gantry beams carrying the machine's chain and a cold work
## light down the well, the only cold light inside the galleries.
func _build_shaft() -> void:
	var room: Node3D = _rooms_by_name["Shaft"]
	var beam: StandardMaterial3D = _mat("gantry", Color("4a4f4c"), 0.5, 0.5)
	var hazard: StandardMaterial3D = _mat("chevron_ochre", OCHRE)
	for x: float in [-1.2, 1.2]:
		_piece("GantryBeam", Vector3(0.3, 0.4, 12.6), beam, Vector3(x, 8.75, 0))
	_piece("GantryCross", Vector3(2.7, 0.3, 0.5), beam, Vector3(0, 8.6, 0))
	for z: float in [-6.15, 6.15]:
		_piece("ShaftEdge", Vector3(12.6, 0.12, 0.2), hazard, Vector3(0, 9.0 - 0.07, z))
	# Ribs down the inside of the hall screens.
	var rib: StandardMaterial3D = _mat("screen_rib", Color("4c514e"), 0.4, 0.6)
	for along: float in [-4.5, -1.5, 1.5, 4.5]:
		_piece("ScreenRib", Vector3(0.08, 2.6, 0.06), rib, Vector3(along, 1.3, 5.95))
		_piece("ScreenRib", Vector3(0.06, 2.6, 0.08), rib, Vector3(-5.95, 1.3, along))
		_piece("ScreenRib", Vector3(0.06, 2.6, 0.08), rib, Vector3(5.95, 1.3, along))
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_pool(room, Vector3(corner.x * 4.0, 8.55, corner.y * 4.0), 1.4, 12.0, 30.0, 9.0)
	# The shaft floor: drain grate and the scuffs of things set down hard.
	var props: Node3D = _props(room)
	_block(props, "ShaftDrain", Vector3(1.2, 0.006, 1.2), _mat("drain", Color("3a3d3b"), 0.4, 0.6), Vector3(0, 0.004, 0))
	_chevrons(props, Vector3(0, 0, -5.4), true, 10.0, 0.4)

# --- lower gallery ------------------------------------------------------------

## The lower gallery: box shelving on the outer walls, the registry desk's
## ledgers and register, pendants and the brass tubes at gallery height.
func _build_lower() -> void:
	var y: float = 3.0
	for run: Array in [[Vector3(-19.6, y, -20), Vector3.BACK, 9.0], [Vector3(9.6, y, -20), Vector3.BACK, 10.0],
		[Vector3(-20, y, -14.0), Vector3.RIGHT, 5.6], [Vector3(-20, y, 3.0), Vector3.RIGHT, 12.0],
		[Vector3(20, y, -19.6), Vector3.LEFT, 10.0], [Vector3(20, y, -2.6), Vector3.LEFT, 8.0],
		[Vector3(20, y, 8.0), Vector3.LEFT, 11.0], [Vector3(19.0, y, 20), Vector3.FORWARD, 10.0], [Vector3(7.5, y, 20), Vector3.FORWARD, 12.0]]:
		_shelving(run[0], run[1], run[2], int(run[0].x * 3.0 + run[0].z))
	# The registry: ledgers, a stamp and the register on the wall behind Renn.
	var props: Node3D = _props(_rooms_by_name["LowerSouth"])
	var ledger: StandardMaterial3D = _mat("ledger", Color("5a3a2a"), 0.0, 0.8)
	for index: int in range(3):
		_block(props, "Ledger", Vector3(0.36, 0.06, 0.26), ledger, Vector3(-15.3, 4.13 + index * 0.065, -11.5))
	_desk_top(Vector3(-13.6, 4.1, -11.5), true, 3)
	_register(Vector3(-14.0, 5.0, -19.97), Vector3.BACK, 8, 2, 11)
	for at: Vector3 in [Vector3(-14, 5.25, -11.5), Vector3(-6, 5.25, -15), Vector3(8, 5.25, -15), Vector3(16, 5.25, -12),
		Vector3(-15, 5.25, 0), Vector3(15, 5.25, 2), Vector3(-2, 5.25, 15), Vector3(12, 5.25, 14)]:
		_pendant(at, 5.7, 1.5, 7.5)
	_tube([Vector3(-17, 5.52, -17), Vector3(17, 5.52, -17), Vector3(17, 5.52, 17), Vector3(-6, 5.52, 17)])
	_tube([Vector3(-17, 5.52, -17), Vector3(-17, 5.52, 8)])
	_tube([Vector3(-17, 5.52, -11.5), Vector3(-15.8, 5.52, -11.5)])
	_tube_station(Vector3(-15.8, 4.1, -11.5), 5.7)

## The lower custody bays: fold-down bunks on the south wall, each with a
## folded patched blanket, a cup and shoes; a drawing pinned above one, a
## meal cloth on another, the bay numbers as plain plates.
func _build_bays() -> void:
	var y: float = 3.0
	var steel: StandardMaterial3D = _mat("bunk_steel", Color("5c605a"), 0.4, 0.6)
	var plate: StandardMaterial3D = _mat("bay_plate", Color("8a8a78"))
	var cup: StandardMaterial3D = _mat("cup", Color("7a6a52"), 0.2, 0.6)
	for index: int in range(4):
		var x: float = -7.5 + float(index) * 5.0
		if absf(x) < 1.5:
			x += 2.5 * signf(x if x != 0.0 else 1.0)
		var base: Vector3 = Vector3(x, y, -20.0)
		_flush("BayBunk", steel, base + Vector3(0, 0.45, 0), Vector3.BACK, 1.9, 0.08, 0.7)
		for side: float in [-0.9, 0.9]:
			_rod("BunkChain", base + Vector3(side, 1.35, 0.02), base + Vector3(side, 0.53, 0.66), 0.012, steel, 4)
		var tint: Color = BELONGINGS[(index * 2 + 1) % BELONGINGS.size()]
		_flush("FoldedBlanket", _mat("blanket_%s" % tint.to_html(false), tint, 0.0, 0.95), base + Vector3(-0.4, 0.53, 0.05), Vector3.BACK, 0.7, 0.12, 0.5)
		_flush("Cup", cup, base + Vector3(0.5, 0.53, 0.2), Vector3.BACK, 0.08, 0.1, 0.08)
		_flush("Shoes", _mat("leather", Color("6a4a32"), 0.0, 0.8), base + Vector3(0.3 - index * 0.1, 0.0, 0.25), Vector3.BACK, 0.3, 0.1, 0.28)
		_flush("BayPlate", plate, base + Vector3(0, 2.15, 0), Vector3.BACK, 0.5, 0.18, 0.02)
		_flush("BayRail", steel, base + Vector3(0, 2.4, 0), Vector3.BACK, 2.4, 0.06, 0.12)
	var props: Node3D = _props(_rooms_by_name["LowerSouth"])
	var bag: StandardMaterial3D = _mat("belonging_%s" % BELONGINGS[3].to_html(false), BELONGINGS[3], 0.0, 0.9)
	_block(props, "Bundle", Vector3(0.5, 0.3, 0.35), bag, Vector3(6.6, 3.15, -19.5))
	_pool(_rooms_by_name["LowerSouth"], Vector3(0, 5.5, -18.2), 1.3, 7.0, 44.0, 5.7)

## The mine lesson: the equipment cage's mesh front over the rack, a hazard
## band at the alcove mouth, a work lamp inside and a calm, evenly lit
## corridor floor so a stuck charge and its lamp read at a glance.
func _build_alcove() -> void:
	var room: Node3D = _rooms_by_name["LowerNorth"]
	var props: Node3D = _props(room)
	var wire: StandardMaterial3D = _mat("cage_wire", Color("4c514e"), 0.5, 0.5)
	for z: float in [13.1, 13.5, 13.9, 14.3, 14.7, 15.1, 15.5, 15.9]:
		_block(props, "CageWire", Vector3(0.02, 2.3, 0.02), wire, Vector3(-19.33, 4.2, z))
	for y: float in [3.2, 4.0, 4.8, 5.35]:
		_block(props, "CageBar", Vector3(0.03, 0.04, 3.0), wire, Vector3(-19.33, y, 14.5))
	var crate: StandardMaterial3D = _mat("charge_crate", Color("5d6a52"), 0.2, 0.7)
	_block(props, "ChargeCrate", Vector3(0.7, 0.35, 0.5), crate, Vector3(-19.4, 3.18, 12.4))
	_block(props, "ChargeCrate", Vector3(0.6, 0.3, 0.45), crate, Vector3(-19.4, 3.5, 12.4))
	_chevrons(props, Vector3(-12.0, 3.0, 14.0), false, 4.0, 0.3)
	_lamp(room, Vector3(-16.5, 5.3, 14.0), 1.5, 6.5, 5.7)
	_pool(room, Vector3(-10.0, 5.5, 15.5), 1.6, 7.0, 44.0, 5.7)

# --- upper gallery ------------------------------------------------------------

## The upper gallery: the custody platforms under issued inspection arms and
## cold pools, the Union's light; restraint frames standing open on the
## south wall beside the bay shutters.
func _build_upper() -> void:
	var room: Node3D = _rooms_by_name["UpperSouth"]
	var arm: StandardMaterial3D = _mat("inspection_arm", Color("464b49"), 0.5, 0.5)
	for platform: Vector3 in [Vector3(10.5, 7.2, -11), Vector3(15, 7.4, -1.5), Vector3(-0.5, 7.2, -14)]:
		var top: Vector3 = Vector3(platform.x, 8.85, platform.z)
		_rod("InspectionMast", top, top + Vector3(0, -0.6, 0), 0.05, arm)
		_rod("InspectionArm", top + Vector3(0, -0.6, 0), top + Vector3(0.9, -0.9, 0), 0.04, arm)
		_piece("InspectionHead", Vector3(0.3, 0.2, 0.3), arm, top + Vector3(0.95, -1.0, 0))
		_pool(_room_at(platform), Vector3(platform.x, 8.6, platform.z), 1.5, 8.0, 40.0, 9.0)
	var props: Node3D = _props(room)
	var frame: StandardMaterial3D = _mat("restraint", Color("4f5452"), 0.5, 0.5)
	for x: float in [-3.0, 0.5]:
		_flush("RestraintFrame", frame, Vector3(x, 6.0, -20.0), Vector3.BACK, 0.08, 2.0, 0.08)
		_flush("RestraintFrame", frame, Vector3(x + 0.8, 6.0, -20.0), Vector3.BACK, 0.08, 2.0, 0.08)
		_flush("RestraintCuff", frame, Vector3(x + 0.4, 7.4, -20.0), Vector3.BACK, 0.9, 0.08, 0.14)
		var open: MeshInstance3D = _block(props, "OpenCuff", Vector3(0.3, 0.06, 0.06), frame, Vector3(x + 0.4, 6.6, -19.8))
		open.rotation.z = 0.6
	# The custody floor is the Union's: cold issued light, no warm pendants,
	# so its black-and-red guards stay black under it.
	for at: Vector3 in [Vector3(4, 8.6, -16), Vector3(16, 8.6, -9), Vector3(14, 8.6, 3), Vector3(5, 8.6, -9)]:
		_pool(_room_at(at), at, 1.3, 9.0, 44.0, 9.0)
	_tube([Vector3(-4, 8.55, -18), Vector3(18, 8.55, -18), Vector3(18, 8.55, 4)])

## The cooling ring: horizontal pipe runs on the outer wall and overhead to
## each column, valve wheels, frost on the cold steel and drip trays, under
## neutral pools. Orrin's cabinet sits in the run's coldest stretch.
func _build_ring() -> void:
	var room: Node3D = _rooms_by_name["Ring"]
	var props: Node3D = _props(room)
	var pipe: StandardMaterial3D = _mat("cooling_pipe", Color("848b8c"), 0.5, 0.45)
	var frost: StandardMaterial3D = _mat("frost", Color("b9bdb8"), 0.0, 0.95)
	var valve: StandardMaterial3D = _mat("valve", Color("7a5a3a"), 0.4, 0.5)
	for height: float in [8.3, 8.65]:
		_rod("CoolingRun", Vector3(-19.75, height, -19.5), Vector3(-19.75, height, -5.0), 0.11, pipe)
		_rod("CoolingRun", Vector3(-19.75, height, 1.0), Vector3(-19.75, height, 19.5), 0.11, pipe)
		_rod("CoolingRun", Vector3(-19.5, height, -19.75), Vector3(-6.5, height, -19.75), 0.11, pipe)
	for column: Vector3 in [Vector3(-15.5, 0, -15.5), Vector3(-11.5, 0, -9.5), Vector3(-15.5, 0, -1.5), Vector3(-11.5, 0, 3.5)]:
		_rod("CoolingFeed", Vector3(column.x, 8.75, column.z), Vector3(-19.75, 8.75, column.z), 0.08, pipe)
		var wheel: MeshInstance3D = _shape.cylinder(props, "ValveWheel", 0.18, 0.04, valve, Vector3(column.x + 0.55, 7.2, column.z), 10)
		wheel.rotation.y = PI * 0.5
		_block(props, "ValveStem", Vector3(0.06, 0.06, 0.06), valve, Vector3(column.x + 0.52, 7.2, column.z))
		_block(props, "Frost", Vector3(1.04, 0.5, 1.04), frost, Vector3(column.x, 6.4, column.z))
		_block(props, "DripTray", Vector3(1.3, 0.04, 1.3), _mat("tray", Color("4e5446"), 0.3, 0.6), Vector3(column.x, 6.02, column.z))
	_block(props, "Frost", Vector3(0.04, 0.6, 3.0), frost, Vector3(-19.0, 6.4, -2.0))
	for at: Vector3 in [Vector3(-13.5, 8.6, -16), Vector3(-13.5, 8.6, -5), Vector3(-13.5, 8.6, 6), Vector3(-13.5, 8.6, 15)]:
		_pool(_room_at(at), at, 1.2, 8.0, 44.0, 9.0)
	_tube([Vector3(-6.5, 8.4, 18.0), Vector3(-17.5, 8.4, 18.0)])
	_shelving(Vector3(-20, 6.0, 18.5), Vector3.RIGHT, 10.0, 41)

## The machinery bridge: deck plates and kick strips on the bridge, the
## evidence desk's transfer files under its own pendant, and a crate stamped
## with a foundry's ochre mark beside it.
func _build_bridge() -> void:
	var room: Node3D = _rooms_by_name["Bridge"]
	var props: Node3D = _props(room)
	var kick: StandardMaterial3D = _mat("chevron_ochre", OCHRE)
	_block(props, "KickStrip", Vector3(10.0, 0.08, 0.06), kick, Vector3(1.0, 6.04, 6.05))
	_desk_top(Vector3(13.5, 7.1, 9.5), true, 2)
	var paper: StandardMaterial3D = _mat("paper", Color("c8bfa0"))
	for index: int in range(4):
		var file: MeshInstance3D = _block(props, "TransferFile", Vector3(0.24, 0.03, 0.32), _mat("box_%s" % BOXES[index].to_html(false), BOXES[index], 0.0, 0.9),
			Vector3(12.4 + index * 0.05, 7.12 + index * 0.03, 9.5))
		file.rotation.y = float(index) * 0.15
	_block(props, "LooseForm", Vector3(0.21, 0.005, 0.29), paper, Vector3(14.6, 7.11, 9.6))
	var crate: StandardMaterial3D = _mat("mars_crate", Color("8a5a3c"), 0.1, 0.8)
	_block(props, "FoundryCrate", Vector3(0.8, 0.6, 0.6), crate, Vector3(16.3, 6.3, 9.6))
	_block(props, "FoundryMark", Vector3(0.3, 0.3, 0.01), _mat("foundry_mark", Color("c49a3c")), Vector3(16.3, 6.35, 9.29))
	_pendant(Vector3(13.5, 8.3, 9.5), 9.0, 1.5, 7.0)
	_pendant(Vector3(-12, 8.4, 14), 9.0, 1.2, 7.0)
	_pool(room, Vector3(1.0, 8.6, 15.5), 1.4, 9.0, 44.0, 9.0)
	_shelving(Vector3(20, 6.0, 11.0), Vector3.LEFT, 8.0, 17)

# --- towers and freight -------------------------------------------------------

func _build_towers() -> void:
	var nosing: StandardMaterial3D = _mat("chevron_ochre", OCHRE)
	for step: int in range(6):
		_piece("StairNosing", Vector3(4.0, 0.02, 0.08), nosing, Vector3(-28.0, 0.5 + step * 0.5 + 0.01, -2.96 + step))
		_piece("StairNosing", Vector3(4.0, 0.02, 0.08), nosing, Vector3(28.0, 3.5 + step * 0.5 + 0.01, -3.96 + step))
	_lamp(_rooms_by_name["WestTower"], Vector3(-26.5, 5.6, -6.0), 1.6, 7.0, 6.3)
	_lamp(_rooms_by_name["WestTower"], Vector3(-26.0, 5.6, 6.0), 1.4, 7.0, 6.3)
	_lamp(_rooms_by_name["EastTower"], Vector3(26.5, 8.2, -7.0), 1.6, 7.0, 9.0)
	_lamp(_rooms_by_name["EastTower"], Vector3(25.0, 8.2, 4.0), 1.4, 7.0, 9.0)
	var props: Node3D = _props(_rooms_by_name["WestTower"])
	_dust(props, Vector3(-28, 0, -6), Vector2(3.0, 2.0), 8, 5)

## The freight lane: rails in the floor to a portal in the north wall where
## the car came in, chevrons at the boarding line, cold high-bay pools and the
## maintenance screen over the car that reads "Authorized noise. No action
## required." whether or not anything can be heard.
func _build_freight() -> void:
	var room: Node3D = _rooms_by_name["Freight"]
	var props: Node3D = _props(room)
	var rail: StandardMaterial3D = _mat("rail_steel", Color("6c6e6a"), 0.6, 0.4)
	for x: float in [-1.6, 1.6]:
		_block(props, "CarRail", Vector3(0.1, 0.02, 9.0), rail, Vector3(x, 0.01, 33.5))
	for z: float in [29.5, 30.5, 31.5, 32.5, 33.5]:
		_block(props, "RailTie", Vector3(4.0, 0.012, 0.25), _mat("tie", Color("4a4a46")), Vector3(0, 0.006, z))
	# The portal the car came through: a dark recess frame in the north wall.
	var dark: StandardMaterial3D = _mat("portal_dark", Color("161818"), 0.0, 1.0)
	var frame: StandardMaterial3D = _mat("portal_frame", Color("55584f"), 0.4, 0.6)
	_block(props, "Portal", Vector3(6.4, 3.0, 0.02), dark, Vector3(0, 1.5, 37.98))
	_block(props, "PortalHeader", Vector3(7.0, 0.3, 0.12), frame, Vector3(0, 3.15, 37.94))
	for x: float in [-3.35, 3.35]:
		_block(props, "PortalJamb", Vector3(0.3, 3.0, 0.12), frame, Vector3(x, 1.5, 37.94))
	_chevrons(props, Vector3(0, 0, 30.4), true, 8.0, 0.4)
	_dust(props, Vector3(0, 0, 37.0), Vector2(7.0, 1.2), 16, 9)
	# Bundles of the people waiting by the lane.
	for index: int in range(4):
		var tint: Color = BELONGINGS[(index * 2 + 3) % BELONGINGS.size()]
		_block(props, "WaitingBundle", Vector3(0.45, 0.28, 0.32), _mat("belonging_%s" % tint.to_html(false), tint, 0.0, 0.9),
			Vector3(-4.6 + index * 0.55 + (6.0 if index > 1 else 0.0), 0.14, 26.4))
	for z: float in [25.0, 31.0, 36.0]:
		_pool(room, Vector3(0, 8.6, z), 1.6, 11.0, 40.0, 9.0)
	_noise_screen()

func _noise_screen() -> void:
	var room: Node3D = _rooms_by_name["Freight"]
	var props: Node3D = _props(room)
	var bezel: StandardMaterial3D = _mat("terminal_case", Color("6a6656"), 0.2, 0.7)
	# The panel spans x -2..2, y 3.4..4.6 on the wall's room face at z 37.5.
	_block(props, "NoiseBezel", Vector3(3.8, 1.1, 0.04), bezel, Vector3(0, 4.0, 37.47))
	var screen: MeshInstance3D = MoonBackdrop._piece(room, "NoiseScreen", Vector3(0, 4.05, 37.44), Vector3(3.5, 0.82, 0.01),
		_glow("noise_screen", Color("2a2418"), 0.4))
	screen.name = "NoiseScreen"
	noise_screen = WorldSign.new()
	noise_screen.name = "NoiseCopy"
	noise_screen.configure("WORLD_M08_AUTHORIZED_NOISE", Vector2(3.3, 0.56), PHOSPHOR)
	noise_screen.transform = Transform3D(MapDecoration.face_basis("north"), Vector3(0, 4.12, 37.43))
	room.add_child(noise_screen)
	# The repeating timing under the text: three short and one long, drawn.
	var tick: StandardMaterial3D = _glow("noise_tick", PHOSPHOR.darkened(0.25), 1.2)
	# Read from the lane the screen's left is world +x.
	var x: float = 0.6
	for width: float in [0.12, 0.12, 0.12, 0.5]:
		_block(props, "NoiseTick", Vector3(width, 0.06, 0.01), tick, Vector3(x - width * 0.5, 3.78, 37.43))
		x -= width + 0.12
