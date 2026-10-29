class_name M10Dressing
extends M06Dressing

## Common Carrier's golden-slice dressing (docs/campaign/l10-common-carrier.md,
## docs/design/space.md). The server owns every solid; this presenter only
## restyles the solid views and furnishes them: surfaces by use, flush wall
## fittings, small possessions against walls or on tops, overhead runs under
## the deck plates, the space outside the window and practical light. A body
## that could stop a pawn or a shot is never added.
##
## The ship is the free side's home, borrowed and mended. Gunmetal ribs frame
## the hull on every deck; the stair trunks are worn bone pressure walls with
## their doors latched open. Each deck has its own life: the cargo deck is
## lashed freight, handling lanes and service machinery under caged work
## lamps; the crew deck is where the rescued people sleep, eat and repair
## each other, in their own colours, under a string of warm bulbs; the
## command deck is quieter, cable trays and harnesses around the pilot's
## consoles and the long window. A painted shape marks each deck at its stair
## trunks so the ship reads without words: a square below, a circle for the
## crew, a triangle for command. The freight shaft, ochre-edged under its
## hoist, is visible from all three. Outside the window are the stars and
## the custody tender riding alongside: black hull, one red seal.

const SHIP_MAP_ID: int = 1010
## How far the lashed crates stand proud of their cargo solid.
const CRATE_PROUD: float = 0.03
## Deck floors and the underside of the plate above each (lower, crew, command).
const DECKS: Array[Vector2] = [Vector2(2.0, 4.6), Vector2(4.8, 7.4), Vector2(7.6, 10.1)]
## Personal colours the people aboard chose: mid values, never black with
## red, never matte off-white, never cyan.
const KIT: Array[Color] = [Color("b5652e"), Color("6f8a4e"), Color("c49a3c"), Color("8a3a58"),
	Color("4f6f8a"), Color("a8552c"), Color("7c5a8c"), Color("9c7c45"), Color("5f7a64")]
const BONE: Color = Color("ad9d80")
const GUNMETAL: Color = Color("5a605d")
const RIB: Color = Color("4c5350")
const AMBER: Color = Color(1.0, 0.72, 0.38)
const REGIONS: Array[String] = ["ForwardHold", "Service", "AftHold", "WestTrunk", "EastTrunk", "Shaft",
	"CrewFore", "CrewAft", "Command", "AftGallery", "Outside"]

static var _ship_surfaces: Dictionary[String, ShaderMaterial] = {}
var _rooms_by_name: Dictionary[String, Node3D] = {}

func clear_map() -> void:
	_rooms_by_name.clear()
	super.clear_map()

## Common Carrier's own authored layout only, keyed on walls and plates that
## never move: the hull, the fore window, both stair trunk walls, the lower
## floor and the deck plates either side of the freight shaft. A custom map
## reusing the id with different structure gets no dressing.
static func ship_layout(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != SHIP_MAP_ID or not info.get("solids") is Array or not info.get("m10") is Dictionary:
		return false
	var wanted: Array = [
		[Vector3(-8, 1.7, -18), Vector3(8, 2, 18)],
		[Vector3(-8, 0, -18), Vector3(-7.8, 10.4, 18)],
		[Vector3(7.8, 0, -18), Vector3(8, 10.4, 18)],
		[Vector3(-7.8, 0, 17.8), Vector3(7.8, 10.4, 18)],
		[Vector3(-4, 8.05, -18), Vector3(4, 9.55, -17.8)],
		[Vector3(-3.55, 2, -13), Vector3(-3.25, 10.1, -2.7)],
		[Vector3(3.35, 2, 2.7), Vector3(3.65, 10.1, 13)],
		[Vector3(-2, 4.6, -17.8), Vector3(2, 4.8, -3)],
		[Vector3(-2, 7.4, 5), Vector3(2, 7.6, 17.8)],
	]
	for pair: Array in wanted:
		if M06Workmanship._host(info["solids"], pair[0], pair[1]).is_empty():
			return false
	return true

# --- surfaces ---------------------------------------------------------------

## Restyle the server's solid views by use, and fill the two cargo stacks
## with lashed crates that occupy exactly their solids.
static func restyle_ship(cover: Node3D, info: Dictionary, views: Array[MeshInstance3D]) -> void:
	if not ship_layout(info) or not info.get("presentation") is Dictionary:
		return
	var solids: Array = info["solids"]
	var surfaces: Array = info["presentation"].get("solids", [])
	if surfaces.size() != solids.size() or views.size() != solids.size():
		return
	var freight: Node3D = Node3D.new()
	freight.name = "M10Freight"
	cover.add_child(freight)
	for index: int in range(solids.size()):
		if not solids[index] is Dictionary or not is_instance_valid(views[index]):
			continue
		var box: AABB = _bounds(solids[index])
		var role: String = ship_role(box, str(surfaces[index]))
		if role == "glass":
			views[index].material_override = window_glass()
		elif role == "cargo":
			# The solid's own view stays as the physical fallback. Under the
			# crates it shrinks to a dark core that reads as the shadowed gaps
			# between them; the crates stand a little proud of the solid.
			if _lash(freight, box.grow(CRATE_PROUD)):
				views[index].material_override = ship_surface("cargo_gap")
				views[index].scale = Vector3(0.7, 0.9, 0.7)
				views[index].position.y -= box.size.y * 0.05
			else:
				views[index].material_override = freight_paint(FREIGHT[_hash(box.get_center()) % FREIGHT.size()])
		else:
			views[index].material_override = ship_surface(role)
	ArenaSky.mark_world(freight)

## Clear pressure glass: a faint neutral film, so the black outside stays
## black and the tender and stars read through it.
static func window_glass() -> StandardMaterial3D:
	var pane: StandardMaterial3D = glass()
	pane.albedo_color = Color(0.55, 0.57, 0.55, 0.07)
	return pane

## A solid's visual role from its registered surface and where it stands.
static func ship_role(box: AABB, surface: String) -> String:
	var low: Vector3 = box.position
	var high: Vector3 = box.end
	var span: float = maxf(box.size.x, box.size.z)
	if surface == "inspection_glass":
		return "glass"
	if surface == "records_tile":
		return "galley"
	if surface == "enamel":
		if low.y >= 10.0:
			return "roof"
		# The pressure hull rises from the keel; the window frame sits in it.
		if low.y < 0.5 and box.size.y >= 7.0 or low.y >= 8.0:
			return "hull"
		if box.size.y >= 7.0:
			return "bone"
		if low.y >= 4.7 and box.size.y >= 2.0:
			return "cabin"
		if low.y <= 2.05 and box.size.y >= 1.5:
			return "cargo"
		return "furnish"
	if surface == "lift_panel":
		if box.size.y <= 1.0 and minf(box.size.x, box.size.z) <= 0.2:
			return "rail"
		if low.y <= 2.05 and box.size.y >= 1.5:
			return "power"
		return "console"
	# Service steel.
	if box.size.y >= 7.0:
		return "steel"
	if box.size.y >= 1.5:
		return "coolant"
	if box.size.y <= 0.31 and span >= 3.0:
		if is_equal_approx(low.y, 1.7):
			return "floor_low"
		if absf(low.y - 4.6) < 0.01:
			return "deck_crew"
		if absf(low.y - 7.4) < 0.01:
			return "deck_command"
	if box.size.y <= 0.31:
		return "tread"
	return "steel"

static func ship_surface(role: String) -> ShaderMaterial:
	if _ship_surfaces.has(role):
		return _ship_surfaces[role]
	var material: ShaderMaterial
	match role:
		"hull":
			# Gunmetal hull plate between the ribs, ribbed every three metres.
			material = _material(GUNMETAL, PRODUCTION + "ship_steel.png", PRODUCTION + "ship_floor.png", 3, Color("6b6f68"), 0.42)
			material.set_shader_parameter("panel_size", 3.0)
		"roof":
			material = _material(Color("4b504e"), PRODUCTION + "ship_steel.png", PRODUCTION + "ship_steel.png", 1, Color("434846"), 0.4)
		"bone":
			# Worn bone pressure paint, warm and mid valued: a lived ship's
			# trunk walls, never the Inheritance's matte off-white.
			material = _material(BONE, PRODUCTION + "ship_enamel.png", PRODUCTION + "ship_floor.png", 1, Color("8e7e62"), 0.12)
			material.set_shader_parameter("panel_size", 2.6)
		"cabin":
			material = _material(Color("9f9076"), PRODUCTION + "ship_enamel.png", PRODUCTION + "ship_floor.png", 1, Color("85775e"), 0.12)
			material.set_shader_parameter("panel_size", 2.6)
		"steel":
			material = _material(Color("4a4f4c"), PRODUCTION + "ship_steel.png", PRODUCTION + "ship_floor.png", 3, Color("5d625e"), 0.45)
		"floor_low":
			# The cargo deck: open grating over the bilge.
			material = _material(Color("55574f"), PRODUCTION + "ship_steel.png", PRODUCTION + "ship_floor.png", 1, Color("45473f"), 0.38)
			material.set_shader_parameter("macro_variation", 0.05)
		"deck_crew":
			# The crew deck's worn plate above, the cargo deck's ceiling below.
			material = _material(Color("615b4f"), PRODUCTION + "ship_steel.png", MOON + "moon_worn_deck.png", 1, Color("4e4a41"), 0.3)
			material.set_shader_parameter("macro_variation", 0.04)
		"deck_command":
			material = _material(Color("5d5c55"), PRODUCTION + "ship_steel.png", PRODUCTION + "ship_floor.png", 1, Color("4b4a44"), 0.3)
		"tread":
			material = _material(Color("4f5350"), PRODUCTION + "ship_steel.png", PRODUCTION + "ship_floor.png", 1, OCHRE, 0.5)
		"power":
			material = _material(Color("56604f"), PRODUCTION + "ship_enamel.png", PRODUCTION + "ship_steel.png", 3, OCHRE, 0.3)
			material.set_shader_parameter("panel_size", 0.9)
		"coolant":
			material = _material(Color("5f7a6a"), PRODUCTION + "ship_steel.png", PRODUCTION + "ship_steel.png", 3, Color("6f8a74"), 0.25)
			material.set_shader_parameter("panel_size", 0.9)
		"rail":
			material = _material(OCHRE, PRODUCTION + "ship_steel.png", PRODUCTION + "ship_steel.png", 1, Color("7a6436"), 0.2)
		"cargo_gap":
			material = _material(Color("2f302b"), PRODUCTION + "ship_steel.png", PRODUCTION + "ship_steel.png", 1, Color("2a2b27"), 0.3)
			material.set_shader_parameter("markings_enabled", false)
		"galley":
			material = _material(Color("6e6a5c"), PRODUCTION + "ship_ceramic.png", PRODUCTION + "ship_ceramic.png", 4, Color("5a564a"), 0.25)
		_:
			material = _material(Color("4e5450"), PRODUCTION + "ship_steel.png", PRODUCTION + "ship_floor.png", 1, Color("5e625d"), 0.4)
	material.set_shader_parameter("base_shade", 0.0)
	_ship_surfaces[role] = material
	return material

## Fill a lashed cargo solid with prepared supply crates, three across, two
## high and two deep, with ratchet straps over the stack. False, leaving the
## box, when the crates cannot fill it.
static func _lash(parent: Node3D, box: AABB) -> bool:
	var along_x: bool = box.size.x >= box.size.z
	var columns: int = 3
	var cell: Vector3 = Vector3(box.size.x / (columns if along_x else 2), box.size.y / 2.0, box.size.z / (2 if along_x else columns))
	var probe: Node3D = CampaignProps.instance("supply_crate")
	if probe == null:
		return false
	var fits: bool = CampaignProps.fit_scale(CampaignProps.model_bounds(probe), cell - Vector3(0.02, 0.0, 0.02), 0.0 if along_x else 90.0) != Vector3.ZERO
	probe.free()
	if not fits:
		return false
	var placed: Array[Node3D] = []
	for column: int in range(columns):
		for row: int in range(2):
			for deep: int in range(2):
				var low: Vector3 = box.position + Vector3(cell.x * (column if along_x else deep), cell.y * row, cell.z * (deep if along_x else column))
				var yaw: float = (0.0 if (column + row + deep) % 2 == 0 else 180.0) + (0.0 if along_x else 90.0)
				var crate: Node3D = CampaignProps.place(parent, "supply_crate", low + Vector3(0.01, 0.0, 0.01), low + cell - Vector3(0.01, 0.0, 0.01), yaw)
				if crate == null:
					for node: Node3D in placed:
						node.queue_free()
					return false
				placed.append(crate)
	var strap: StandardMaterial3D = MoonBackdrop._material(Color("a8552c"))
	var buckle: StandardMaterial3D = MoonBackdrop._material(Color("3a3d3c"))
	var centre: Vector3 = box.get_center()
	for step: float in [0.22, 0.5, 0.78]:
		if along_x:
			var x: float = box.position.x + box.size.x * step
			MoonBackdrop._piece(parent, "CargoStrapTop", Vector3(x, box.end.y + 0.012, centre.z), Vector3(0.07, 0.02, box.size.z + 0.04), strap)
			for face: float in [-1.0, 1.0]:
				MoonBackdrop._piece(parent, "CargoStrapSide", Vector3(x, centre.y, centre.z + face * (box.size.z * 0.5 + 0.012)), Vector3(0.07, box.size.y, 0.02), strap)
			MoonBackdrop._piece(parent, "CargoBuckle", Vector3(x, centre.y + 0.2, box.position.z - 0.03), Vector3(0.12, 0.16, 0.04), buckle)
		else:
			var z: float = box.position.z + box.size.z * step
			MoonBackdrop._piece(parent, "CargoStrapTop", Vector3(centre.x, box.end.y + 0.012, z), Vector3(box.size.x + 0.04, 0.02, 0.07), strap)
			for face: float in [-1.0, 1.0]:
				MoonBackdrop._piece(parent, "CargoStrapSide", Vector3(centre.x + face * (box.size.x * 0.5 + 0.012), centre.y, z), Vector3(0.02, box.size.y, 0.07), strap)
			MoonBackdrop._piece(parent, "CargoBuckle", Vector3(box.end.x + 0.03, centre.y + 0.2, z), Vector3(0.04, 0.16, 0.12), buckle)
	return true

# --- rooms ------------------------------------------------------------------

func configure_map(info: Dictionary) -> void:
	if active() and ship_layout(info):
		return
	clear_map()
	if not ship_layout(info):
		return
	for label: String in REGIONS:
		_rooms_by_name[label] = _room(label)
	_build_ribs()
	_build_trunks()
	_build_shaft()
	_build_forward_hold()
	_build_service()
	_build_aft_hold()
	_build_crew_fore()
	_build_crew_aft()
	_build_command()
	_build_aft_gallery()
	_build_outside()
	for room: Node3D in _unattached:
		_finish(room)
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

func _mat(key: String, tint: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	return _shape.material("m10_" + key, tint, metallic, roughness)

## The room a world point belongs to, so each merged mesh stays local.
static func region(p: Vector3) -> String:
	if absf(p.x) > 8.0 or absf(p.z) > 18.0 or p.y > 10.4:
		return "Outside"
	if p.x < -3.25 and p.z > -16.0 and p.z < -2.7:
		return "WestTrunk"
	if p.x > 3.35 and p.z > 2.7 and p.z < 16.0:
		return "EastTrunk"
	if absf(p.x) < 2.0 and p.z > -3.0 and p.z < 5.0:
		return "Shaft"
	if p.y < 4.6:
		return "ForwardHold" if p.z < -3.0 else ("Service" if p.z < 10.0 else "AftHold")
	if p.y < 7.4:
		return "CrewFore" if p.z < -3.0 else "CrewAft"
	return "Command" if p.z < -3.0 else "AftGallery"

func _at(p: Vector3) -> Node3D:
	return _props(_rooms_by_name[region(p)])

func _room_at(p: Vector3) -> Node3D:
	return _rooms_by_name[region(p)]

func _piece(label: String, size: Vector3, finish: Material, at: Vector3) -> MeshInstance3D:
	return _block(_at(at), label, size, finish, at)

func _rod(label: String, a: Vector3, b: Vector3, radius: float, finish: StandardMaterial3D, segments: int = 6) -> MeshInstance3D:
	return _shape.rod(_at((a + b) * 0.5), label, a, b, radius, finish, segments)

## Goods are prepared models; they stay out of the merged fixture mesh.
func _goods(p: Vector3) -> Node3D:
	var room: Node3D = _room_at(p)
	var goods: Node3D = room.get_node_or_null("Goods") as Node3D
	if goods == null:
		goods = Node3D.new()
		goods.name = "Goods"
		room.add_child(goods)
	return goods

func _stand(prop: String, feet: Vector3, yaw: float, scale: float = 1.0) -> void:
	CampaignProps.stand(_goods(feet), prop, feet, yaw, scale)

## A hanging caged work lamp under a deck plate.
func _work_lamp(at: Vector3, ceiling: float, energy: float = 1.6, reach: float = 7.0) -> void:
	_lamp(_room_at(at), at, energy, reach, ceiling)

## A warm small light with its own little glowing source.
func _glim(at: Vector3, tint: Color, energy: float, reach: float, size: Vector3 = Vector3(0.08, 0.08, 0.08)) -> void:
	_piece("Glim", size, _glow("glim_%s" % tint.to_html(false), tint.lightened(0.2), 2.4), at)
	_omni(_room_at(at), "Glim%d" % lamps, at, tint, energy, reach)

# --- ribs and runs --------------------------------------------------------

## Gunmetal ribs up both hull sides and transverse beams under every plate,
## every three metres, broken around the open shaft and the stair trunks.
func _build_ribs() -> void:
	var rib: StandardMaterial3D = _mat("rib", RIB, 0.3, 0.6)
	var bolt: StandardMaterial3D = _mat("rib_bolt", Color("6c6a62"), 0.4, 0.5)
	var z: float = -16.5
	while z <= 16.6:
		for deck: Vector2 in DECKS:
			var height: float = deck.y - deck.x
			for side: float in [-1.0, 1.0]:
				if side < 0.0 and z > -16.0 and z < -2.7 or side > 0.0 and z > 2.7 and z < 16.0:
					continue
				var x: float = side * 7.72
				_piece("HullRib", Vector3(0.16, height, 0.3), rib, Vector3(x, deck.x + height * 0.5, z))
				_piece("RibKnee", Vector3(0.3, 0.3, 0.3), rib, Vector3(side * 7.65, deck.y - 0.15, z))
				for y: float in [deck.x + 0.5, deck.x + 1.5]:
					_piece("RibBolt", Vector3(0.04, 0.05, 0.05), bolt, Vector3(side * 7.62, y, z + 0.09))
			for span: Vector2 in _beam_spans(z):
				_piece("DeckBeam", Vector3(span.y - span.x, 0.12, 0.22), rib, Vector3((span.x + span.y) * 0.5, deck.y - 0.06, z))
		z += 3.0

## The open x ranges a transverse beam may cross at `z`.
static func _beam_spans(z: float) -> Array[Vector2]:
	var low: float = -7.8
	var high: float = 7.8
	if z > -16.0 and z < -2.7:
		low = -3.25
	if z > 2.7 and z < 16.0:
		high = 3.35
	if z > -3.0 and z < 5.0:
		return [Vector2(low, -2.0), Vector2(2.0, high)]
	return [Vector2(low, high)]

# --- stair trunks: bone pressure doors latched open, deck shapes ---------------

func _build_trunks() -> void:
	var leaf: StandardMaterial3D = _mat("door_bone", BONE.darkened(0.04), 0.1, 0.75)
	var gasket: StandardMaterial3D = _mat("door_gasket", Color("2e302e"), 0.0, 0.9)
	var dog: StandardMaterial3D = _mat("door_dog", OCHRE, 0.3, 0.6)
	var frame: StandardMaterial3D = _mat("door_frame", Color("8f7a58"), 0.2, 0.7)
	var plate: StandardMaterial3D = _mat("deck_plate", Color("2f3331"), 0.2, 0.7)
	var mark: StandardMaterial3D = _mat("deck_mark", Color("d0b47e"), 0.0, 0.8)
	for index: int in range(DECKS.size()):
		var deck: Vector2 = DECKS[index]
		var top: float = minf(deck.x + 2.25, deck.y - 0.02)
		for side: float in [-1.0, 1.0]:
			# West trunk opens east at z -16..-13; east trunk opens west at z 13..16.
			var wall_x: float = -3.25 if side < 0.0 else 3.35
			var normal: float = 1.0 if side < 0.0 else -1.0
			var hinge_z: float = -13.0 if side < 0.0 else 13.0
			var away: float = 1.0 if side < 0.0 else -1.0
			var leaf_x: float = wall_x + normal * 0.05
			var leaf_z: float = hinge_z + away * 0.85
			_piece("PressureDoor", Vector3(0.07, top - deck.x - 0.1, 1.5), leaf, Vector3(leaf_x, (deck.x + 0.05 + top) * 0.5, leaf_z))
			_piece("DoorGasket", Vector3(0.075, top - deck.x - 0.04, 0.06), gasket, Vector3(leaf_x, (deck.x + top) * 0.5, leaf_z - 0.76))
			_piece("DoorGasket", Vector3(0.075, top - deck.x - 0.04, 0.06), gasket, Vector3(leaf_x, (deck.x + top) * 0.5, leaf_z + 0.76))
			_piece("DoorWindow", Vector3(0.08, 0.32, 0.32), gasket, Vector3(leaf_x, deck.x + 1.62, leaf_z))
			for y: float in [deck.x + 0.55, deck.x + 1.05]:
				_piece("DoorDog", Vector3(0.1, 0.06, 0.22), dog, Vector3(leaf_x + normal * 0.05, y, leaf_z + away * 0.55))
			_piece("DoorHinge", Vector3(0.12, 0.2, 0.1), gasket, Vector3(leaf_x, deck.x + 0.4, hinge_z + away * 0.06))
			_piece("DoorHinge", Vector3(0.12, 0.2, 0.1), gasket, Vector3(leaf_x, top - 0.4, hinge_z + away * 0.06))
			# The frame header under the plate above, across the opening.
			var span_z: float = (-16.0 + -13.0) * 0.5 if side < 0.0 else (13.0 + 16.0) * 0.5
			_piece("DoorHeader", Vector3(0.22, 0.2, 3.0), frame, Vector3(wall_x + normal * -0.1, deck.y - 0.1, span_z))
			_piece("DoorJamb", Vector3(0.36, top - deck.x, 0.06), frame, Vector3(wall_x - normal * 0.15, (deck.x + top) * 0.5, hinge_z + away * -0.03))
			# The deck's painted shape at eye height beside the opening.
			var at: Vector3 = Vector3(wall_x + normal * 0.012, deck.x + 1.75, hinge_z + away * 2.15)
			_piece("DeckPlate", Vector3(0.02, 0.56, 0.56), plate, at)
			_deck_shape(index, at + Vector3(normal * 0.008, 0, 0), mark)
			_paint_line(_at(at), Vector3(wall_x + normal * 0.6, deck.x, hinge_z), Vector3(wall_x + normal * 0.6, deck.x, hinge_z - away * 3.0), 0.08, _mat("lane_ochre", OCHRE))

## Square for the cargo deck, circle for the crew, triangle for command.
func _deck_shape(index: int, at: Vector3, finish: StandardMaterial3D) -> void:
	var props: Node3D = _at(at)
	if index == 0:
		_block(props, "DeckSquare", Vector3(0.02, 0.32, 0.32), finish, at)
	elif index == 1:
		var disc: MeshInstance3D = _shape.cylinder(props, "DeckCircle", 0.19, 0.02, finish, at, 16)
		disc.rotation.y = PI * 0.5
	else:
		_shape.prism(props, "DeckTriangle", PackedVector2Array([Vector2(-0.2, -0.17), Vector2(0.2, -0.17), Vector2(0.0, 0.2)]), 0.02, finish, at, 0.0)

# --- the freight shaft --------------------------------------------------------

func _build_shaft() -> void:
	var beam: StandardMaterial3D = _mat("hoist_beam", Color("4a4433"), 0.4, 0.6)
	var hook: StandardMaterial3D = _mat("hoist_hook", OCHRE, 0.4, 0.5)
	var chain: StandardMaterial3D = _mat("hoist_chain", Color("3a3b38"), 0.6, 0.5)
	_piece("HoistRail", Vector3(0.3, 0.16, 8.6), beam, Vector3(0, 9.98, 1.0))
	_piece("HoistTrolley", Vector3(0.5, 0.25, 0.6), hook, Vector3(0, 9.8, 1.4))
	_rod("HoistChain", Vector3(0.0, 9.7, 1.4), Vector3(0.0, 8.85, 1.4), 0.025, chain)
	_piece("HoistBlock", Vector3(0.32, 0.36, 0.22), hook, Vector3(0, 8.7, 1.4))
	_rod("HoistHook", Vector3(0.0, 8.52, 1.4), Vector3(0.0, 8.3, 1.52), 0.035, hook)
	# A warm flood from under the roof down the whole shaft.
	var light: SpotLight3D = SpotLight3D.new()
	light.name = "ShaftFlood"
	light.position = Vector3(0, 9.85, 0.4)
	light.rotation.x = -PI * 0.5
	light.light_color = Color(1.0, 0.84, 0.62)
	light.light_energy = 3.2
	light.light_specular = 0.1
	light.spot_range = 9.5
	light.spot_angle = 30.0
	light.spot_attenuation = 0.7
	light.shadow_enabled = false
	_rooms_by_name["Shaft"].add_child(light)
	lamps += 1
	_piece("ShaftLampHood", Vector3(0.6, 0.14, 0.6), beam, Vector3(0, 9.98, 0.4))
	_piece("ShaftLampLens", Vector3(0.44, 0.02, 0.44), _glow("shaft_lens", Color(1.0, 0.78, 0.5), 1.4), Vector3(0, 9.9, 0.4))
	# Hazard edges round the opening on both upper decks, and the landing
	# square on the cargo deck floor where loads come down.
	for deck: Vector2 in [DECKS[1], DECKS[2]]:
		var y: float = deck.x
		_hazard_edge(Vector3(0, y, -3.17), true, 4.0)
		_hazard_edge(Vector3(0, y, 5.17), true, 4.0)
		for side: float in [-1.0, 1.0]:
			_hazard_edge(Vector3(side * 2.17, y, 1.0), false, 8.0)
	var lane: StandardMaterial3D = _mat("lane_ochre", OCHRE)
	for line: Array in [[Vector3(-1.9, 2.0, -2.9), Vector3(1.9, 2.0, -2.9)], [Vector3(-1.9, 2.0, 4.9), Vector3(1.9, 2.0, 4.9)],
		[Vector3(-1.9, 2.0, -2.9), Vector3(-1.9, 2.0, 4.9)], [Vector3(1.9, 2.0, -2.9), Vector3(1.9, 2.0, 4.9)]]:
		_paint_line(_at(Vector3(0, 2.0, 1.0)), line[0], line[1], 0.12, lane)

## Painted edge stripes on a deck plate along an open drop: ochre and dark
## blocks, flush on the plate.
func _hazard_edge(centre: Vector3, along_x: bool, length: float) -> void:
	var paint: StandardMaterial3D = _mat("lane_ochre", OCHRE)
	var dark: StandardMaterial3D = _mat("chevron_dark", Color("2a2b2a"))
	var count: int = int(length / 0.3)
	for index: int in range(count):
		var offset: float = -length * 0.5 + 0.15 + float(index) * 0.3
		var at: Vector3 = centre + (Vector3(offset, 0.004, 0) if along_x else Vector3(0, 0.004, offset))
		_piece("HazardBlock", Vector3(0.3, 0.006, 0.26) if along_x else Vector3(0.26, 0.006, 0.3), paint if index % 2 == 0 else dark, at)

# --- cargo deck ---------------------------------------------------------------

func _build_forward_hold() -> void:
	var lane: StandardMaterial3D = _mat("lane_ochre", OCHRE)
	for x: float in [-1.75, 1.75]:
		_paint_line(_at(Vector3(x, 2.0, -10.0)), Vector3(x, 2.0, -17.4), Vector3(x, 2.0, -3.3), 0.1, lane)
	_chevrons(_at(Vector3(0, 2.0, -17.0)), Vector3(0.0, 2.0, -17.45), true, 3.2, 0.5)
	# The stock locker on the fore bulkhead behind the cargo stock.
	var shell: StandardMaterial3D = _mat("locker_olive", Color("5f6a4f"), 0.3, 0.7)
	var inside: StandardMaterial3D = _mat("locker_inside", Color("2c2f2c"), 0.2, 0.9)
	_piece("StockLocker", Vector3(2.8, 1.9, 0.08), inside, Vector3(3.9, 2.95, -17.76))
	for x: float in [2.5, 5.3]:
		_piece("LockerSide", Vector3(0.06, 1.9, 0.38), shell, Vector3(x, 2.95, -17.61))
	_piece("LockerTop", Vector3(2.86, 0.06, 0.4), shell, Vector3(3.9, 3.92, -17.6))
	for y: float in [2.55, 3.25]:
		_piece("LockerShelf", Vector3(2.74, 0.04, 0.34), shell, Vector3(3.9, y, -17.62))
	for index: int in range(5):
		_crate(_at(Vector3(3, 3, -17.6)), Vector3(2.75 + index * 0.52, 3.27, -17.62), Vector3(0.36, 0.26, 0.28), KIT[(index * 2) % KIT.size()].darkened(0.15))
	# A cargo net on the starboard hull holding the passengers' bags.
	var net: StandardMaterial3D = _mat("cargo_net", Color("7a6a50"), 0.0, 0.9)
	for z: float in [-10.0, -7.5]:
		_stand("duffel", Vector3(7.5, 2.0, z), 90.0, 0.9)
		_stand("hard_luggage", Vector3(7.45, 2.0, z + 1.1), 90.0)
	var x_net: float = 7.15
	var row: float = 2.2
	while row <= 3.6:
		_rod("NetCord", Vector3(x_net, row, -10.8), Vector3(x_net, row, -5.9), 0.012, net, 4)
		row += 0.35
	var col: float = -10.8
	while col <= -5.8:
		_rod("NetCord", Vector3(x_net, 2.05, col), Vector3(x_net, 3.8, col), 0.012, net, 4)
		col += 0.45
	for z: float in [-10.8, -5.9]:
		_rod("NetTie", Vector3(x_net, 3.8, z), Vector3(7.75, 4.1, z), 0.015, net, 4)
	_pipes(Vector3(7.6, 0, -17.5), Vector3(7.6, 0, 2.6), 2.0)
	_work_lamp(Vector3(0.0, 4.15, -14.5), 4.6, 1.8, 7.5)
	_work_lamp(Vector3(0.0, 4.15, -7.5), 4.6, 1.6, 7.0)
	_work_lamp(Vector3(5.5, 4.2, -8.0), 4.6, 1.2, 5.5)

## Two pipe runs along a hull side: coolant low, warm water high, with
## brackets and valve wheels.
func _pipes(from: Vector3, to: Vector3, floor: float) -> void:
	var coolant: StandardMaterial3D = _mat("pipe_coolant", Color("5f7a64"), 0.3, 0.6)
	var hot: StandardMaterial3D = _mat("pipe_hot", Color("8a5636"), 0.3, 0.6)
	var bracket: StandardMaterial3D = _mat("pipe_bracket", Color("3a3d3c"), 0.4, 0.6)
	var wheel: StandardMaterial3D = _mat("valve_wheel", OCHRE, 0.3, 0.6)
	var low: float = floor + 0.75
	var high: float = floor + 2.25
	_rod("PipeCoolant", Vector3(from.x, low, from.z), Vector3(to.x, low, to.z), 0.07, coolant, 8)
	_rod("PipeHot", Vector3(from.x, high, from.z), Vector3(to.x, high, to.z), 0.06, hot, 8)
	var length: float = from.distance_to(to)
	var steps: int = maxi(1, int(length / 2.5))
	for index: int in range(steps + 1):
		var at: Vector3 = from.lerp(to, float(index) / float(steps))
		_piece("PipeBracket", Vector3(0.36, 0.06, 0.06), bracket, Vector3(at.x, low, at.z))
		_piece("PipeBracket", Vector3(0.36, 0.06, 0.06), bracket, Vector3(at.x, high, at.z))
		if index % 3 == 1:
			var disc: MeshInstance3D = _shape.cylinder(_at(at + Vector3(0, low, 0)), "ValveWheel", 0.13, 0.03, wheel, Vector3(at.x - signf(at.x) * 0.12, low, at.z + 0.3), 10)
			disc.rotation.y = PI * 0.5

func _build_service() -> void:
	# The power bank: conduits into the plate above, gauges and amber lamps.
	var conduit: StandardMaterial3D = _mat("conduit", Color("3d403c"), 0.4, 0.6)
	var gauge: StandardMaterial3D = _mat("gauge_face", Color("c6b38a"), 0.0, 0.7)
	var rim: StandardMaterial3D = _mat("gauge_rim", Color("2c2e2c"), 0.5, 0.5)
	for x: float in [3.1, 3.8, 4.5]:
		_rod("PowerConduit", Vector3(x, 3.8, 1.2), Vector3(x, 4.6, 1.2), 0.07, conduit, 8)
	for z: float in [0.5, 1.25, 2.0]:
		var face: MeshInstance3D = _shape.cylinder(_at(Vector3(2.8, 3.3, z)), "Gauge", 0.11, 0.03, rim, Vector3(2.78, 3.3, z), 12)
		face.rotation.y = PI * 0.5
		_piece("GaugeFace", Vector3(0.01, 0.15, 0.15), gauge, Vector3(2.76, 3.3, z))
		_piece("GaugeNeedle", Vector3(0.012, 0.09, 0.012), rim, Vector3(2.755, 3.32, z + 0.02))
	for z: float in [0.3, 2.2]:
		_glim(Vector3(2.76, 2.7, z), AMBER, 0.5, 2.5, Vector3(0.03, 0.06, 0.06))
	_chevrons(_at(Vector3(2.5, 2.0, 1.25)), Vector3(2.55, 2.0, 1.25), false, 2.5, 0.3)
	# The coolant bank: risers into the plate above and along to the hull.
	var coolant: StandardMaterial3D = _mat("pipe_coolant", Color("5f7a64"), 0.3, 0.6)
	for x: float in [-4.4, -3.4]:
		_rod("CoolantRiser", Vector3(x, 3.8, 10.15), Vector3(x, 4.3, 10.15), 0.09, coolant, 8)
		_rod("CoolantRun", Vector3(x, 4.3, 10.15), Vector3(-7.55, 4.3, 10.15 + (x + 3.9) * 0.6), 0.08, coolant, 8)
	_piece("CoolantPlate", Vector3(1.6, 0.04, 1.5), _mat("coolant_cap", Color("4d6556"), 0.3, 0.6), Vector3(-3.9, 3.82, 10.15))
	_glim(Vector3(-3.9, 3.9, 10.15), AMBER, 0.4, 2.2, Vector3(0.06, 0.06, 0.06))
	_pipes(Vector3(-7.6, 0, -2.4), Vector3(-7.6, 0, 17.4), 2.0)
	# Oil stains and a drip tray where people work on the machinery.
	var oil: StandardMaterial3D = _mat("oil", Color("47453e"), 0.2, 0.5)
	for patch: Vector3 in [Vector3(2.4, 2.0, 0.6), Vector3(2.2, 2.0, 2.1), Vector3(-2.7, 2.0, 9.6), Vector3(-5.6, 2.0, 4.0)]:
		var stain: MeshInstance3D = _piece("OilStain", Vector3(0.55, 0.004, 0.38), oil, patch + Vector3(0, 0.004, 0))
		stain.rotation.y = patch.z
	_piece("DripTray", Vector3(0.8, 0.03, 0.5), _mat("drip_tray", Color("4a4d4a"), 0.4, 0.5), Vector3(-5.2, 2.015, 10.1))
	_work_lamp(Vector3(-4.5, 4.2, 2.5), 4.6, 1.6, 7.0)
	_work_lamp(Vector3(0.0, 4.2, 7.5), 4.6, 1.5, 6.5)
	_work_lamp(Vector3(5.6, 4.2, -0.5), 4.6, 1.2, 5.0)

func _build_aft_hold() -> void:
	# The outer cargo door on the aft bulkhead, dogged shut, bone paint worn
	# through at the handles.
	var leaf: StandardMaterial3D = _mat("door_bone", BONE.darkened(0.04), 0.1, 0.75)
	var frame: StandardMaterial3D = _mat("door_frame", Color("8f7a58"), 0.2, 0.7)
	var dog: StandardMaterial3D = _mat("door_dog", OCHRE, 0.3, 0.6)
	var gasket: StandardMaterial3D = _mat("door_gasket", Color("2e302e"), 0.0, 0.9)
	_piece("CargoDoorFrame", Vector3(5.6, 2.45, 0.06), frame, Vector3(-0.5, 3.24, 17.77))
	_piece("CargoDoor", Vector3(5.2, 2.2, 0.08), leaf, Vector3(-0.5, 3.2, 17.74))
	_piece("CargoDoorSeam", Vector3(0.05, 2.2, 0.09), gasket, Vector3(-0.5, 3.2, 17.735))
	for x: float in [-2.9, 1.9]:
		for y: float in [2.6, 3.8]:
			_piece("CargoDog", Vector3(0.3, 0.08, 0.1), dog, Vector3(x, y, 17.68))
	_chevrons(_at(Vector3(-0.5, 2.0, 17.2)), Vector3(-0.5, 2.0, 17.45), true, 5.2, 0.4)
	# The passengers' luggage tied along the port hull.
	var tag: StandardMaterial3D = _mat("luggage_tag", Color("c49a3c"))
	var spots: Array[Vector3] = [Vector3(-7.35, 2.0, 11.0), Vector3(-7.35, 2.0, 11.8), Vector3(-7.35, 2.0, 12.6), Vector3(-7.35, 2.0, 14.0), Vector3(-7.35, 2.0, 16.6)]
	for index: int in range(spots.size()):
		_stand("hard_luggage" if index % 2 == 0 else "duffel", spots[index], 90.0, 0.95)
		_piece("LuggageTag", Vector3(0.03, 0.08, 0.05), tag if index % 2 == 0 else _mat("luggage_tag_b", KIT[index]), spots[index] + Vector3(0.3, 0.3, 0.2))
	_stand("hard_luggage", Vector3(-7.35, 2.255, 11.0), 90.0, 0.9)
	_stand("duffel", Vector3(-7.35, 2.26, 14.0), 80.0, 0.8)
	_stand("supply_crate", Vector3(-7.25, 2.0, 15.3), 0.0, 0.9)
	_work_lamp(Vector3(0.0, 4.2, 14.0), 4.6, 1.7, 7.0)
	_work_lamp(Vector3(-5.0, 4.2, 15.5), 4.6, 1.1, 5.0)

# --- crew deck ----------------------------------------------------------------

## A floor rug in two colours, flush on the plate.
func _rug(centre: Vector3, size: Vector2, base: Color, stripe: Color) -> void:
	var weave: Color = base.darkened(0.25)
	var border: Color = stripe.darkened(0.2)
	_piece("Rug", Vector3(size.x, 0.008, size.y), _mat("rug_%s" % weave.to_html(false), weave, 0.0, 1.0), centre + Vector3(0, 0.005, 0))
	var trim: StandardMaterial3D = _mat("rug_%s" % border.to_html(false), border, 0.0, 1.0)
	for side: float in [-1.0, 1.0]:
		_piece("RugBorder", Vector3(size.x - 0.1, 0.006, 0.09), trim, centre + Vector3(0, 0.01, side * (size.y * 0.5 - 0.12)))
		_piece("RugBorder", Vector3(0.09, 0.006, size.y - 0.1), trim, centre + Vector3(side * (size.x * 0.5 - 0.12), 0.01, 0))
	var motif: StandardMaterial3D = _mat("rug_%s" % stripe.darkened(0.35).to_html(false), stripe.darkened(0.35), 0.0, 1.0)
	var steps: int = int(maxf(size.x, size.y) / 0.6)
	for index: int in range(steps):
		var t: float = (float(index) + 0.5) / float(steps) - 0.5
		var at: Vector3 = centre + (Vector3(t * (size.x - 0.5), 0.011, 0) if size.x >= size.y else Vector3(0, 0.011, t * (size.y - 0.5)))
		var diamond: MeshInstance3D = _piece("RugMotif", Vector3(0.22, 0.006, 0.22), motif, at)
		diamond.rotation.y = PI * 0.25

## A bedroll along a hull wall, long axis along z: mattress, blanket,
## pillow and a few things kept beside it.
func _bedroll(at: Vector3, tint: Color, index: int) -> void:
	var mattress: StandardMaterial3D = _mat("mattress", Color("7b725f"), 0.0, 1.0)
	var pillow: StandardMaterial3D = _mat("pillow", Color("b7a98a"), 0.0, 1.0)
	_piece("Mattress", Vector3(0.75, 0.1, 1.85), mattress, at + Vector3(0, 0.05, 0))
	_piece("Blanket", Vector3(0.78, 0.05, 1.2), _mat("blanket_%s" % tint.to_html(false), tint, 0.0, 1.0), at + Vector3(0, 0.12, 0.3))
	_piece("Pillow", Vector3(0.5, 0.1, 0.3), pillow, at + Vector3(0, 0.14, -0.7))
	if index % 2 == 0:
		_piece("Lantern", Vector3(0.12, 0.2, 0.12), _mat("lantern", Color("3e403c"), 0.4, 0.5), at + Vector3(0.5, 0.1, -0.85))
		_glim(at + Vector3(0.5, 0.24, -0.85), Color(1.0, 0.7, 0.42), 0.35, 2.2, Vector3(0.06, 0.06, 0.06))
	else:
		_piece("Book", Vector3(0.16, 0.04, 0.22), _mat("book_%d" % (index % 3), KIT[(index + 3) % KIT.size()]), at + Vector3(0.48, 0.02, -0.6))
		_piece("Mug", Vector3(0.08, 0.1, 0.08), _mat("mug", Color("8a3a58"), 0.1, 0.6), at + Vector3(0.48, 0.05, -0.85))

## Things pinned to a wall facing `normal_x`: photographs, drawings and
## stickers in the residents' colours, a shelf with jars and hooks with coats.
func _wall_of_life(x: float, normal_x: float, floor: float, from_z: float, to_z: float, seed_value: int) -> void:
	var z: float = from_z
	var index: int = seed_value
	while z < to_z - 0.3:
		var tint: Color = KIT[index % KIT.size()]
		var paper: Color = Color("c2b28e") if index % 3 != 0 else tint.lightened(0.15)
		var size: Vector2 = Vector2(0.22 + float(index % 3) * 0.06, 0.18 + float((index * 7) % 4) * 0.04)
		var y: float = floor + 1.5 + float((index * 5) % 5) * 0.12
		_piece("Pinned", Vector3(0.012, size.y, size.x), _mat("paper_%s" % paper.to_html(false), paper, 0.0, 0.95), Vector3(x + normal_x * 0.008, y, z))
		_piece("PinnedMark", Vector3(0.014, size.y * 0.4, size.x * 0.5), _mat("ink_%s" % tint.to_html(false), tint.darkened(0.2), 0.0, 0.95), Vector3(x + normal_x * 0.01, y + 0.02, z - 0.02))
		z += size.x + 0.12 + float(index % 2) * 0.2
		index += 1
	var shelf: StandardMaterial3D = _mat("shelf_wood", Color("7a5a3a"), 0.0, 0.85)
	var mid: float = (from_z + to_z) * 0.5
	_piece("Shelf", Vector3(0.26, 0.04, 1.2), shelf, Vector3(x + normal_x * 0.13, floor + 1.3, mid))
	for jar: int in range(4):
		var colour: Color = KIT[(jar + seed_value) % KIT.size()]
		_shape.cylinder(_at(Vector3(x, floor + 1.4, mid)), "Jar", 0.05, 0.16, _mat("jar_%s" % colour.to_html(false), colour, 0.1, 0.5), Vector3(x + normal_x * 0.13, floor + 1.4, mid - 0.45 + jar * 0.3), 8).rotation.x = PI * 0.5
	var hook: StandardMaterial3D = _mat("hook", Color("3a3d3c"), 0.5, 0.5)
	for coat: int in range(3):
		var cz: float = mid + 0.9 + coat * 0.42
		if cz > to_z - 0.2:
			break
		var colour: Color = KIT[(coat * 4 + seed_value) % KIT.size()]
		_piece("Hook", Vector3(0.1, 0.03, 0.03), hook, Vector3(x + normal_x * 0.05, floor + 1.75, cz))
		_piece("Coat", Vector3(0.1, 0.75, 0.36), _mat("coat_%s" % colour.to_html(false), colour.darkened(0.1), 0.0, 1.0), Vector3(x + normal_x * 0.07, floor + 1.35, cz))

## A string of warm bulbs under a deck plate between two points.
func _bulbs(from: Vector3, to: Vector3, count: int, lights: int) -> void:
	var cable: StandardMaterial3D = _mat("bulb_cable", Color("2c2c2a"), 0.0, 0.8)
	var bulb: StandardMaterial3D = _glow("string_bulb", Color(1.0, 0.7, 0.4), 1.3)
	var sag: Vector3 = Vector3(0, -0.12, 0)
	var previous: Vector3 = from
	for index: int in range(1, count + 1):
		var t: float = float(index) / float(count)
		var at: Vector3 = from.lerp(to, t) + sag * sin(t * PI)
		_rod("BulbCable", previous, at, 0.008, cable, 4)
		previous = at
		if index < count:
			_piece("Bulb", Vector3(0.035, 0.05, 0.035), bulb, at - Vector3(0, 0.04, 0))
	for index: int in range(lights):
		var at: Vector3 = from.lerp(to, (float(index) + 0.5) / float(lights)) + Vector3(0, -0.25, 0)
		_omni(_room_at(at), "StringLight%d" % lamps, at, Color(1.0, 0.8, 0.55), 0.9, 6.0)

func _build_crew_fore() -> void:
	# Rugs where people sit, the berth curtain, the repair corner and the galley.
	_rug(Vector3(0.0, 4.8, -12.0), Vector2(1.8, 2.6), Color("8a5a3c"), Color("c49a3c"))
	_rug(Vector3(-0.3, 4.8, -6.6), Vector2(1.6, 2.2), Color("566474"), Color("a8552c"))
	var curtain: StandardMaterial3D = _mat("berth_curtain", Color("6f8a4e"), 0.0, 1.0)
	_rod("CurtainRail", Vector3(4.2, 7.2, -15.3), Vector3(4.2, 7.2, -12.3), 0.015, _mat("hook", Color("3a3d3c"), 0.5, 0.5), 4)
	for index: int in range(4):
		# Drawn back against the aft berth wall, clear of the doorway.
		_piece("CurtainFold", Vector3(0.06, 2.1, 0.12), curtain, Vector3(4.24 - (index % 2) * 0.05, 6.15, -12.8 + index * 0.12))
	_glim(Vector3(7.65, 6.4, -14.0), Color(1.0, 0.72, 0.45), 0.6, 3.2, Vector3(0.06, 0.1, 0.1))
	_wall_of_life(-3.25, 1.0, 4.8, -10.4, -3.3, 1)
	# The repair corner: a tool board on the hull and an articulated lamp.
	var board: StandardMaterial3D = _mat("tool_board", Color("6b5a44"), 0.0, 0.9)
	var tool: StandardMaterial3D = _mat("tool", Color("4a4d4a"), 0.6, 0.4)
	_piece("ToolBoard", Vector3(0.03, 0.9, 1.6), board, Vector3(7.77, 6.35, -9.3))
	for index: int in range(6):
		_piece("Tool", Vector3(0.03, 0.22 + (index % 3) * 0.08, 0.05), tool, Vector3(7.74, 6.35 + (index % 2) * 0.2, -9.9 + index * 0.24))
	_piece("SparePlate", Vector3(0.36, 0.03, 0.22), _mat("spare_plate", Color("a8552c"), 0.2, 0.7), Vector3(5.6, 5.73, -9.25))
	_piece("SparePlate", Vector3(0.3, 0.03, 0.18), _mat("spare_plate_b", Color("b7aa86"), 0.2, 0.7), Vector3(6.2, 5.73, -9.15))
	_rod("BenchLampArm", Vector3(6.6, 5.9, -9.65), Vector3(6.2, 6.6, -9.35), 0.02, tool, 4)
	_glim(Vector3(6.1, 6.55, -9.3), Color(1.0, 0.78, 0.5), 1.1, 3.8, Vector3(0.14, 0.08, 0.14))
	# The galley: shelves of supplies on the hull, pots and a water drum.
	var shelf: StandardMaterial3D = _mat("shelf_wood", Color("7a5a3a"), 0.0, 0.85)
	for y: float in [6.2, 6.75]:
		_piece("GalleyShelf", Vector3(0.3, 0.04, 2.6), shelf, Vector3(7.63, y, -5.1))
		for can: int in range(7):
			var colour: Color = KIT[(can * 2 + int(y * 10.0)) % KIT.size()]
			_shape.cylinder(_at(Vector3(7.6, y, -5.1)), "Tin", 0.055, 0.15, _mat("tin_%s" % colour.to_html(false), colour, 0.3, 0.5), Vector3(7.62, y + 0.1, -6.2 + can * 0.36), 8).rotation.x = PI * 0.5
	for index: int in range(3):
		_piece("Pot", Vector3(0.22, 0.16, 0.22), _mat("pot", Color("6a655c"), 0.6, 0.4), Vector3(7.6, 7.0, -3.9 - index * 0.35))
	_glim(Vector3(6.0, 7.1, -5.15), Color(1.0, 0.8, 0.52), 1.3, 4.5, Vector3(0.12, 0.08, 0.12))
	# The surplus locker between bench and galley: a six under a cargo sticker.
	var locker: StandardMaterial3D = _mat("surplus_locker", Color("6b6f58"), 0.3, 0.7)
	_piece("SurplusLocker", Vector3(0.3, 1.8, 1.1), locker, Vector3(7.65, 5.7, -7.0))
	_piece("LockerSeam", Vector3(0.31, 1.7, 0.02), _mat("door_gasket", Color("2e302e"), 0.0, 0.9), Vector3(7.65, 5.7, -7.0))
	_piece("CargoSticker", Vector3(0.012, 0.16, 0.24), _mat("sticker", Color("c49a3c")), Vector3(7.495, 6.25, -7.25))
	_six(Vector3(7.492, 6.0, -7.25), -1.0, _mat("six_paint", Color("b5652e")))
	_bulbs(Vector3(-2.6, 7.32, -16.5), Vector3(-2.6, 7.32, -3.3), 14, 2)
	_bulbs(Vector3(2.6, 7.32, -16.5), Vector3(2.6, 7.32, -3.3), 14, 2)

## The small hand-drawn six, five pixels high, on a face whose normal is
## `normal_x` along x.
func _six(at: Vector3, normal_x: float, finish: StandardMaterial3D) -> void:
	var rows: Array[String] = ["111", "100", "111", "101", "111"]
	for row: int in range(rows.size()):
		for col: int in range(3):
			if rows[row][col] == "1":
				_piece("Six", Vector3(0.012, 0.03, 0.03), finish, at + Vector3(normal_x * 0.002, 0.06 - row * 0.03, (col - 1) * 0.03 * -normal_x))

func _build_crew_aft() -> void:
	var tints: Array[Color] = [Color("8a3a58"), Color("6f8a4e"), Color("4f6f8a"), Color("c49a3c"), Color("7c5a8c"), Color("a8552c"), Color("5f7a64")]
	var z: float = -1.9
	var index: int = 0
	while z < 16.0:
		_bedroll(Vector3(-7.3, 4.8, z + 0.95), tints[index % tints.size()], index)
		# Each sleeper's own hanging on the hull behind their bedroll.
		var hanging: Color = tints[(index + 3) % tints.size()].darkened(0.1)
		_piece("Hanging", Vector3(0.02, 1.3, 1.3), _mat("hanging_%s" % hanging.to_html(false), hanging, 0.0, 1.0), Vector3(-7.6, 5.75, z + 0.95))
		_piece("HangingRod", Vector3(0.03, 0.03, 1.4), _mat("hook", Color("3a3d3c"), 0.5, 0.5), Vector3(-7.6, 6.42, z + 0.95))
		if index % 3 != 1:
			_stand("duffel" if index % 2 == 0 else "hard_luggage", Vector3(-7.32, 4.8, z + 2.1), 90.0, 0.7)
		z += 2.35
		index += 1
	# Washing on a line under the plate, hung clear of anyone's head.
	var line: StandardMaterial3D = _mat("washing_line", Color("8a8270"), 0.0, 0.9)
	_rod("WashingLine", Vector3(-5.6, 7.2, -2.4), Vector3(-5.6, 7.2, 16.6), 0.014, line, 4)
	var cloth_z: float = -1.6
	var hung: int = 0
	while cloth_z < 16.0:
		var colour: Color = KIT[(hung * 5 + 2) % KIT.size()]
		var width: float = 0.3 + (hung % 3) * 0.08
		_piece("Washing", Vector3(0.02, 0.3, width), _mat("washing_%s" % colour.to_html(false), colour.darkened(0.08), 0.0, 1.0), Vector3(-5.6, 7.04, cloth_z))
		for peg: float in [-0.4, 0.4]:
			_piece("Peg", Vector3(0.03, 0.05, 0.02), _mat("peg", Color("8a6a44")), Vector3(-5.6, 7.19, cloth_z + peg * width))
		cloth_z += 0.7 + float(hung % 4) * 0.35
		hung += 1
	_rug(Vector3(0.0, 4.8, 11.0), Vector2(2.2, 3.0), Color("7c5a8c"), Color("c49a3c"))
	_rug(Vector3(-5.2, 4.8, 6.0), Vector2(1.6, 2.4), Color("9c7c45"), Color("5f7a64"))
	_wall_of_life(3.35, -1.0, 4.8, 5.4, 10.3, 4)
	# A patchwork quilt hung on the aft bulkhead, every square someone's.
	var square: float = 0.42
	for row: int in range(4):
		for col: int in range(12):
			var colour: Color = KIT[(row * 5 + col * 3 + (col >> 1)) % KIT.size()]
			if (row + col) % 4 == 0:
				colour = Color("b7a98a")
			_piece("QuiltSquare", Vector3(square - 0.02, square - 0.02, 0.02), _mat("quilt_%s" % colour.to_html(false), colour, 0.0, 1.0),
				Vector3(-2.3 + col * square, 5.45 + row * square, 17.77))
	_bulbs(Vector3(-2.6, 7.32, 5.4), Vector3(-2.6, 7.32, 17.4), 13, 2)
	_bulbs(Vector3(-4.0, 7.32, -2.4), Vector3(-4.0, 7.32, 16.6), 18, 2)
	_glim(Vector3(1.5, 6.6, 17.7), Color(1.0, 0.76, 0.48), 0.8, 4.0, Vector3(0.1, 0.14, 0.06))

# --- command deck --------------------------------------------------------------

func _build_command() -> void:
	var frame: StandardMaterial3D = _mat("window_frame", Color("6f6450"), 0.3, 0.6)
	for x: float in [-1.33, 1.33]:
		_piece("WindowMullion", Vector3(0.1, 1.5, 0.1), frame, Vector3(x, 8.8, -17.75))
	_piece("WindowSill", Vector3(8.4, 0.12, 0.3), frame, Vector3(0, 7.99, -17.7))
	_piece("WindowHead", Vector3(8.4, 0.12, 0.2), frame, Vector3(0, 9.6, -17.75))
	# Cable trays overhead and the pilot's harnesses on the starboard hull.
	var tray: StandardMaterial3D = _mat("cable_tray", Color("454a47"), 0.4, 0.6)
	var cable: StandardMaterial3D = _mat("cable_bundle", Color("2f312f"), 0.0, 0.8)
	for x: float in [-1.0, 1.0]:
		_piece("CableTray", Vector3(0.4, 0.06, 13.5), tray, Vector3(x, 9.95, -10.1))
		_piece("CableBundle", Vector3(0.3, 0.08, 13.4), cable, Vector3(x, 10.0, -10.1))
	var harness: StandardMaterial3D = _mat("harness", Color("4f6f8a"), 0.0, 0.9)
	var buckle: StandardMaterial3D = _mat("door_dog", OCHRE, 0.3, 0.6)
	for index: int in range(3):
		var z: float = -12.0 + index * 0.7
		_piece("HarnessHook", Vector3(0.12, 0.04, 0.04), _mat("hook", Color("3a3d3c"), 0.5, 0.5), Vector3(7.72, 9.5, z))
		_piece("Harness", Vector3(0.05, 0.9, 0.08), harness if index != 1 else _mat("harness_b", Color("b5652e"), 0.0, 0.9), Vector3(7.7, 9.0, z - 0.1))
		_piece("Harness", Vector3(0.05, 0.9, 0.08), harness if index != 1 else _mat("harness_b", Color("b5652e"), 0.0, 0.9), Vector3(7.7, 9.0, z + 0.1))
		_piece("HarnessBuckle", Vector3(0.06, 0.08, 0.14), buckle, Vector3(7.69, 8.75, z))
	# The route chart on the trunk wall: two worlds and the line between,
	# drawn by hand. No words.
	var chart: StandardMaterial3D = _mat("chart_paper", Color("b9a780"), 0.0, 0.95)
	var ink: StandardMaterial3D = _mat("chart_ink", Color("3b3a34"), 0.0, 0.95)
	_piece("RouteChart", Vector3(0.015, 0.9, 1.5), chart, Vector3(-3.24, 8.85, -8.5))
	var moon: MeshInstance3D = _shape.cylinder(_at(Vector3(-3.2, 8.9, -9.0)), "ChartMoon", 0.1, 0.01, _mat("chart_grey", Color("7d7a70"), 0.0, 0.9), Vector3(-3.225, 8.95, -9.0), 10)
	moon.rotation.y = PI * 0.5
	var mars: MeshInstance3D = _shape.cylinder(_at(Vector3(-3.2, 8.9, -8.0)), "ChartMars", 0.14, 0.01, _mat("chart_rust", Color("a8552c"), 0.0, 0.9), Vector3(-3.225, 8.75, -7.95), 10)
	mars.rotation.y = PI * 0.5
	for step: int in range(6):
		var t: float = float(step) / 5.0
		_piece("ChartDash", Vector3(0.012, 0.025, 0.06), ink, Vector3(-3.226, 8.93 - t * 0.17 + sin(t * PI) * 0.12, -8.88 + t * 0.78))
	_six(Vector3(-3.226, 8.48, -7.88), 1.0, ink)
	# The crew cubby under the fore bulkhead: a cot, a note, a small lamp.
	_piece("Cot", Vector3(2.2, 0.36, 0.62), _mat("cot_frame", Color("4a4d4a"), 0.4, 0.6), Vector3(-6.3, 7.78, -17.45))
	_piece("CotBlanket", Vector3(2.0, 0.08, 0.6), _mat("blanket_%s" % Color("8a3a58").to_html(false), Color("8a3a58"), 0.0, 1.0), Vector3(-6.4, 8.0, -17.45))
	_piece("CotPillow", Vector3(0.45, 0.1, 0.4), _mat("pillow", Color("b7a98a"), 0.0, 1.0), Vector3(-7.25, 8.06, -17.45))
	_piece("TernNote", Vector3(0.24, 0.3, 0.012), _mat("paper_c2b28e", Color("c2b28e"), 0.0, 0.95), Vector3(-5.6, 8.9, -17.79))
	for line: int in range(4):
		_piece("NoteLine", Vector3(0.16 - (line % 2) * 0.05, 0.012, 0.014), ink, Vector3(-5.62, 8.98 - line * 0.05, -17.785))
	_piece("NoteSix", Vector3(0.03, 0.05, 0.015), _mat("six_paint", Color("b5652e")), Vector3(-5.5, 8.8, -17.783))
	_rod("CubbyCurtainRail", Vector3(-7.6, 9.9, -16.9), Vector3(-4.2, 9.9, -16.9), 0.012, _mat("hook", Color("3a3d3c"), 0.5, 0.5), 4)
	for index: int in range(3):
		_piece("CubbyCurtain", Vector3(0.1, 1.4, 0.05), _mat("berth_curtain_b", Color("9c7c45"), 0.0, 1.0), Vector3(-7.68 + index * 0.1, 9.2, -16.92))
	_glim(Vector3(-4.9, 8.75, -17.7), Color(1.0, 0.7, 0.42), 0.6, 3.0, Vector3(0.08, 0.1, 0.06))
	# Warm console glow and two caged lamps along the approach.
	_omni(_rooms_by_name["Command"], "ConsoleGlow", Vector3(2.5, 8.8, -16.0), AMBER, 0.8, 3.5)
	_work_lamp(Vector3(0.0, 9.75, -13.0), 10.1, 1.4, 6.5)
	_work_lamp(Vector3(0.0, 9.75, -6.5), 10.1, 1.3, 6.0)
	_work_lamp(Vector3(5.6, 9.75, -10.0), 10.1, 0.9, 5.0)

func _build_aft_gallery() -> void:
	# Work suits hung on the port hull in their owners' colours.
	var visor: StandardMaterial3D = _mat("suit_visor", Color("2a2c2c"), 0.6, 0.3)
	var hook: StandardMaterial3D = _mat("hook", Color("3a3d3c"), 0.5, 0.5)
	for index: int in range(4):
		var z: float = 2.0 + index * 1.1
		var tint: Color = KIT[(index * 3 + 1) % KIT.size()]
		var cloth: StandardMaterial3D = _mat("suit_cloth_%s" % tint.to_html(false), tint.darkened(0.25), 0.0, 0.9)
		var x: float = -7.55
		_piece("SuitHook", Vector3(0.2, 0.05, 0.05), hook, Vector3(-7.7, 9.6, z))
		_piece("SuitTorso", Vector3(0.3, 0.7, 0.5), cloth, Vector3(x, 9.05, z))
		_piece("SuitPanel", Vector3(0.02, 0.4, 0.3), _mat("suit_patch", Color("6b6a5e"), 0.0, 0.85), Vector3(x + 0.16, 9.1, z))
		_shape.cylinder(_at(Vector3(x, 9.55, z)), "SuitHelmet", 0.16, 0.28, cloth, Vector3(x, 9.58, z), 10)
		_piece("SuitVisor", Vector3(0.03, 0.13, 0.22), visor, Vector3(x + 0.16, 9.58, z))
		for side: float in [-1.0, 1.0]:
			_piece("SuitArm", Vector3(0.13, 0.6, 0.13), cloth, Vector3(x, 8.9, z + side * 0.31))
			_piece("SuitLeg", Vector3(0.15, 0.75, 0.15), cloth, Vector3(x, 8.32, z + side * 0.11))
	# A mended hull: a riveted patch on the aft bulkhead with weld beads.
	var patch: StandardMaterial3D = _mat("hull_patch", Color("6a6a60"), 0.4, 0.6)
	var weld: StandardMaterial3D = _mat("weld", Color("4a4438"), 0.3, 0.7)
	_piece("HullPatch", Vector3(1.8, 1.3, 0.04), patch, Vector3(-4.8, 8.9, 17.77))
	for edge: Array in [[Vector3(1.86, 0.04, 0.05), Vector3(-4.8, 9.56, 17.75)], [Vector3(1.86, 0.04, 0.05), Vector3(-4.8, 8.24, 17.75)],
		[Vector3(0.04, 1.36, 0.05), Vector3(-5.73, 8.9, 17.75)], [Vector3(0.04, 1.36, 0.05), Vector3(-3.87, 8.9, 17.75)]]:
		_piece("WeldBead", edge[0], weld, edge[1])
	for index: int in range(8):
		_piece("Rivet", Vector3(0.04, 0.04, 0.03), weld, Vector3(-5.6 + index * 0.23, 9.45, 17.74))
	# Water bladders strapped flat to the aft bulkhead, and spare panels.
	for index: int in range(3):
		_piece("WaterBladder", Vector3(0.7, 1.0, 0.24), _mat("bladder", Color("5f6b5e"), 0.1, 0.6), Vector3(0.0 + index * 0.85, 8.15, 17.66))
		_piece("BladderStrap", Vector3(0.74, 0.06, 0.26), _mat("cargo_strap", Color("a8552c"), 0.0, 0.9), Vector3(0.0 + index * 0.85, 8.4, 17.66))
	_work_lamp(Vector3(0.0, 9.75, 11.0), 10.1, 1.4, 6.5)
	_work_lamp(Vector3(-5.2, 9.75, 4.0), 10.1, 1.2, 6.0)
	_work_lamp(Vector3(-5.2, 9.75, 14.5), 10.1, 1.0, 5.5)

# --- outside the window -----------------------------------------------------------

## Stars and the custody tender riding alongside: a black hull with one red
## seal, far enough out that only the long window frames it. Unlit and
## fog-free so it stays crisp against the dark.
func _build_outside() -> void:
	var props: Node3D = _props(_rooms_by_name["Outside"])
	var star: StandardMaterial3D = MoonBackdrop._material(Color("e8e2d2"), true)
	star.disable_fog = true
	var dim: StandardMaterial3D = MoonBackdrop._material(Color("8f8a7e"), true)
	dim.disable_fog = true
	var seed_value: int = 1010
	for index: int in range(220):
		seed_value = (seed_value * 1103515245 + 12345) % 2147483648
		var u: float = float(seed_value % 1000) / 1000.0
		var v: float = float((seed_value >> 10) % 1000) / 1000.0
		var size: float = 0.25 if index % 7 == 0 else 0.14
		_block(props, "Star", Vector3(size, size, 0.05), star if index % 3 == 0 else dim, Vector3(-70.0 + u * 140.0, -20.0 + v * 55.0, -90.0))
	# Unlit dark grey reads as a black hull against true black.
	var hull: StandardMaterial3D = MoonBackdrop._material(Color("101112"), true)
	hull.disable_fog = true
	var plate: StandardMaterial3D = MoonBackdrop._material(Color("17181a"), true)
	plate.disable_fog = true
	var port: StandardMaterial3D = MoonBackdrop._material(Color("8f8a7e"), true)
	port.disable_fog = true
	var seal: StandardMaterial3D = MoonBackdrop._material(Color("8c1a1e"), true)
	seal.disable_fog = true
	var running: StandardMaterial3D = MoonBackdrop._material(Color("a3262a"), true)
	running.disable_fog = true
	var bow: Vector3 = Vector3(-14.0, 6.0, -62.0)
	_block(props, "TenderHull", Vector3(9.0, 6.0, 34.0), hull, bow + Vector3(0, 0, -17.0))
	_block(props, "TenderBridge", Vector3(5.0, 3.0, 8.0), plate, bow + Vector3(0.5, 4.2, -10.0))
	_block(props, "TenderBow", Vector3(7.0, 4.4, 4.0), plate, bow + Vector3(0, -0.2, 1.8))
	for index: int in range(6):
		_block(props, "TenderRib", Vector3(9.2, 6.2, 0.4), plate, bow + Vector3(0, 0, -3.0 - index * 5.0))
	var disc: MeshInstance3D = _shape.cylinder(props, "TenderSeal", 1.3, 0.1, seal, bow + Vector3(4.56, 0.6, -8.0), 16)
	disc.rotation.y = PI * 0.5
	for z: float in [-2.0, -20.0, -32.0]:
		_block(props, "TenderRunningLight", Vector3(0.3, 0.3, 0.3), running, bow + Vector3(4.6, -2.6, z))
	for index: int in range(5):
		_block(props, "TenderPort", Vector3(0.1, 0.35, 0.6), port, bow + Vector3(3.06, 4.4, -7.5 - index * 1.1))
