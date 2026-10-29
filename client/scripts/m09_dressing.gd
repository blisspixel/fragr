class_name M09Dressing
extends M06Dressing

## Passenger Manifest's golden-slice dressing (docs/campaign/l09-passenger-manifest.md,
## docs/design/moon.md, docs/design/space.md). The server owns every solid;
## like the port and the town, this presenter only restyles the solid views
## and furnishes them: surfaces by use, flush fittings, paint, small things on
## existing tops or against walls, overhead lines above head height and
## practical light. A body that could stop a pawn or a shot is never added,
## and no rail is drawn where the server has no rail: every open gantry edge
## is a real drop, and the paint says so.
##
## The berth is not the port, the town or the archive. It is one tall
## pressure hall built around a ship: bone shell walls, a glazed roof with the
## sun and Earth in it, and the cradle in the middle, where the Common Carrier
## sits in ochre chocks and clamps. The ship is Tern's: gunmetal plate and
## ribs, a bone pressure deck, an ember stripe the colour of Tern's shoulder
## panel, and passenger windows that light as people go aboard. The Union's
## part of the room is its paperwork and its lights: seal tape on every hatch,
## impound notices pasted on the plate, the impound office in issued steel and
## the control gallery's cold floods trained on the hull. The people the
## manifest lists as cargo left their bags tagged on the freight.

const BERTH_MAP_ID: int = 1009
## Gunmetal plate, a darker belly and rib, the bone pressure deck, and the
## ember of Tern's shoulder panel. Mid values: a black Union body reads
## against all of them, and nothing here is black with red or matte off-white.
const HULL: Color = Color("5f666a")
const HULL_DARK: Color = Color("484e51")
const BONE: Color = Color("a39d8b")
const EMBER: Color = Color("9c6846")
const CRADLE: Color = Color("8c7642")
## What the passengers carry: personal colour, never issued.
const BAGS: Array[Color] = [Color("8a5a3c"), Color("6f8a4e"), Color("c49a3c"), Color("8a3a58"),
	Color("4f6f8a"), Color("a8552c"), Color("7c5a8c"), Color("9c7c45")]
const REGIONS: Array[String] = ["Loading", "Office", "Stern", "GantryWest", "GantryNorth", "GantryEast", "Gallery", "Cradle", "Shell"]
## The berth's interior floor [min_x, min_z, size] and the cradle's
## footprint under the ship, painted and scorched.
const BERTH: Rect2 = Rect2(-48, -48, 96, 96)
const PIT: Rect2 = Rect2(-10, -20, 20, 44)
## Top rails on the office landing's three real guards. The gap between the
## east guards (z -32.5 to -29.5) is where a charge goes over; nothing is
## drawn across it.
const LANDING_RAILS: Array = [[Vector3(-38.0, 5.14, -35.15), Vector3(-18.0, 5.14, -35.15)],
	[Vector3(-17.85, 5.14, -35.0), Vector3(-17.85, 5.14, -32.5)], [Vector3(-17.85, 5.14, -29.5), Vector3(-17.85, 5.14, -27.0)]]

static var _berth_surfaces: Dictionary[String, ShaderMaterial] = {}
var _rooms_by_name: Dictionary[String, Node3D] = {}

func clear_map() -> void:
	_rooms_by_name.clear()
	super.clear_map()

## Passenger Manifest's own authored layout only, keyed on solids that never
## move: the berth's west shell, the office floor, the first gantry, the
## control gallery, the ship's keel, the hatch bridge and the boarding stack.
## The boarding hatch moves when it opens and is never part of the guard. A
## custom map reusing the id with different structure gets no dressing
## rather than floating props.
static func berth_layout(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != BERTH_MAP_ID or not info.get("solids") is Array:
		return false
	var wanted: Array = [
		[Vector3(-49, 0, -49), Vector3(-48, 26, 49)],
		[Vector3(-38, 0, -25), Vector3(-18, 4, -15)],
		[Vector3(-24, 5.4, -13), Vector3(-16, 6, 14)],
		[Vector3(16, 9.4, -24), Vector3(40, 10, -12)],
		[Vector3(-8, 2, -18), Vector3(8, 9, 18)],
		[Vector3(-12, 11.4, -35), Vector3(24, 12, -28)],
		[Vector3(-10, 0, -30), Vector3(10, 12, -22)],
	]
	for pair: Array in wanted:
		if M06Workmanship._host(info["solids"], pair[0], pair[1]).is_empty():
			return false
	return true

# --- surfaces ---------------------------------------------------------------

## Restyle the server's solid views by use: the bone pressure shell and its
## roof, the ship's plate, deck and engines, the ochre cradle, grated gantry
## steel, the impound office, freight and the car, plus a deck-plate floor in
## tiles with the cradle's footprint scorched under the ship.
static func restyle_berth(cover: Node3D, info: Dictionary, views: Array[MeshInstance3D]) -> void:
	if not berth_layout(info) or not info.get("presentation") is Dictionary:
		return
	var solids: Array = info["solids"]
	var surfaces: Array = info["presentation"].get("solids", [])
	if surfaces.size() != solids.size() or views.size() != solids.size():
		return
	var freight: Node3D = Node3D.new()
	freight.name = "M09Freight"
	cover.add_child(freight)
	for index: int in range(solids.size()):
		if not solids[index] is Dictionary or not is_instance_valid(views[index]):
			continue
		var box: AABB = _bounds(solids[index])
		var role: String = berth_role(box, str(surfaces[index]))
		if role == "glass":
			views[index].material_override = glass()
		elif role == "goods":
			views[index].material_override = freight_paint(FREIGHT[_hash(box.get_center()) % FREIGHT.size()])
		else:
			views[index].material_override = berth_surface(role)
	var floor: MeshInstance3D = cover.get_node_or_null("MapFloor") as MeshInstance3D
	if floor != null:
		floor.visible = false
	var ground: Node3D = Node3D.new()
	ground.name = "M09Floor"
	cover.add_child(ground)
	var x: float = BERTH.position.x
	while x < BERTH.end.x - 0.01:
		var width: float = minf(FLOOR_TILE, BERTH.end.x - x)
		var z: float = BERTH.position.y
		while z < BERTH.end.y - 0.01:
			var depth: float = minf(FLOOR_TILE, BERTH.end.y - z)
			var centre: Vector3 = Vector3(x + width * 0.5, 0.0, z + depth * 0.5)
			var pit: bool = PIT.has_point(Vector2(centre.x, centre.z))
			_plane(ground, ("CradleDeck%d" if pit else "BerthDeck%d") % ground.get_child_count(), centre, Vector2(width, depth), berth_surface("pit" if pit else "deck"))
			z += depth
		x += width
	ArenaSky.mark_world(freight)
	ArenaSky.mark_world(ground)

## A solid's visual role from its registered surface and where it stands.
static func berth_role(box: AABB, surface: String) -> String:
	var low: Vector3 = box.position
	var high: Vector3 = box.end
	var centre: Vector3 = box.get_center()
	var thin: float = minf(box.size.x, box.size.z)
	if surface == "inspection_glass":
		return "glass"
	if low.y >= 26.0 - 0.01:
		return "roof"
	if low.y >= 25.5:
		return "frame"
	if box.size.y >= 25.0:
		return "column" if box.size.x <= 2.01 and box.size.z <= 2.01 else "shell"
	# The ship: keel and stern neck, the bone pressure deck above, the bow.
	if surface == "enamel" and absf(centre.x) <= 8.0 and low.z >= -22.01 and high.z <= 23.01 and low.y >= 2.0:
		if low.y >= 9.0:
			return "deck_upper"
		return "bow" if low.z >= 18.0 else "hull"
	if surface == "service_steel" and is_equal_approx(low.y, 1.0) and absf(centre.x) >= 8.0 and absf(centre.x) <= 14.0:
		return "engine"
	if high.y <= 2.01 and low.y <= 0.01 and absf(centre.x) <= 8.0 and low.z >= -15.01 and high.z <= 21.01:
		return "cradle"
	# The boarding stack against the stern, and its hatch.
	if surface == "enamel" and absf(centre.x) <= 11.0 and centre.z >= -31.0 and centre.z <= -22.0:
		if is_equal_approx(box.size.x, 6.0) and is_equal_approx(box.size.z, 1.0):
			return "hatch"
		return "tower"
	# Stair treads, wherever they climb.
	if surface == "service_steel" and low.y <= 0.01 and thin <= 0.41 and box.size.y <= 12.3:
		return "stair"
	# The impound office: its landing rails, the customs locker, the walls.
	if centre.x >= -44.5 and centre.x <= -17.0 and centre.z >= -35.5 and centre.z <= -14.9:
		if low.y >= 3.99 and high.y <= 5.11 and thin <= 0.31:
			return "rail"
		if surface == "enamel" and low.y >= 3.99 and high.y <= 5.01:
			return "locker"
		if low.y >= 8.39:
			return "ceiling"
		if low.y <= 0.01 and high.y <= 4.01 and thin > 0.41:
			return "deck_block"
		return "office"
	if box.size.y <= 0.41 and low.y >= 8.0:
		return "ceiling"
	if box.size.x <= 1.01 and box.size.z <= 1.01 and box.size.y > 5.0:
		return "column"
	if box.size.y <= 0.61 and low.y >= 5.0:
		return "gantry"
	if low.y <= 0.01 and high.y >= 5.99 and thin >= 1.9:
		return "deck_block"
	if centre.z < -35.0 and centre.x < -12.0:
		if high.y <= 2.01 and surface == "service_steel" and centre.x < -35.0:
			return "car"
		if high.y <= 2.01:
			return "goods" if surface == "enamel" else "barrier"
		return "receiving"
	if surface == "enamel" and low.y >= 9.99 and box.size.y <= 2.01:
		return "panel"
	return "steel"

static func berth_surface(role: String) -> ShaderMaterial:
	if _berth_surfaces.has(role):
		return _berth_surfaces[role]
	var material: ShaderMaterial
	match role:
		"shell", "office", "tower":
			material = surface("shell")
		"roof":
			# The hall's roof structure: plain steel a step darker than the
			# shell, so the glazing and the sky in it are the bright shape.
			material = _material(Color("65665f"), PRODUCTION + "lunar_steel.png", PRODUCTION + "lunar_steel.png", 3, Color("56574f"), 0.3)
			material.set_shader_parameter("markings_enabled", false)
		"ceiling":
			# Shelter and canopy undersides: mid steel, so the lamps under
			# them read as light, not as holes in a black lid.
			material = _material(Color("6b6e6a"), PRODUCTION + "lunar_steel.png", PRODUCTION + "archive_steel.png", 3, Color("5a5d5a"), 0.35)
			material.set_shader_parameter("markings_enabled", false)
		"frame", "column", "receiving", "steel":
			material = surface("steel")
		"rail":
			material = _material(Color("5f6463"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, OCHRE, 0.45)
		"hull":
			# Gunmetal plate on the ship's sides: no painted service bands,
			# the ribs, stripe and windows are fittings of their own.
			material = _material(HULL, PRODUCTION + "ship_steel.png", PRODUCTION + "ship_floor.png", 3, HULL_DARK, 0.5)
			material.set_shader_parameter("markings_enabled", false)
			material.set_shader_parameter("panel_size", 3.0)
		"deck_upper":
			material = _material(BONE, MOON + "moon_pressure_bone.png", MOON + "moon_worn_deck.png", 2, Color("948c78"), 0.4)
			material.set_shader_parameter("markings_enabled", false)
		"bow":
			material = _material(HULL_DARK, PRODUCTION + "ship_steel.png", PRODUCTION + "ship_floor.png", 3, HULL, 0.5)
			material.set_shader_parameter("markings_enabled", false)
		"engine":
			material = _material(Color("4b5154"), PRODUCTION + "ship_steel.png", PRODUCTION + "ship_floor.png", 3, HULL_DARK, 0.5)
			material.set_shader_parameter("markings_enabled", false)
		"cradle":
			material = _material(CRADLE, PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, Color("5e5232"), 0.4)
			material.set_shader_parameter("warning_color", Color("2e2d2a"))
		"hatch":
			# A worn bone pressure door, the ship's own.
			material = _material(Color("a8a18d"), MOON + "moon_pressure_bone.png", MOON + "moon_worn_deck.png", 2, OCHRE, 0.35)
			material.set_shader_parameter("warning_color", OCHRE)
		"stair", "gantry":
			# Grated walkway steel a step lighter than the port's, with worn
			# ochre edge paint: a black body stands out on it from below.
			material = _material(Color("6e716d"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, OCHRE, 0.5)
		"deck_block":
			material = _material(Color("7b796f"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, Color("605e57"), 0.45)
			material.set_shader_parameter("warning_color", OCHRE)
		"locker", "barrier":
			material = surface("union")
		"car":
			material = freight_paint(Color("68724f"))
		"panel":
			material = surface("panel")
		"deck":
			material = _material(Color("9a968a"), MOON + "moon_worn_deck.png", MOON + "moon_worn_deck.png", 1, Color("716e64"), 0.5)
			material.set_shader_parameter("tile_floor_strength", 0.45)
			material.set_shader_parameter("macro_variation", 0.06)
			material.set_shader_parameter("warning_color", OCHRE)
		"pit":
			# The cradle's footprint: the same plate, darker with engine soot.
			material = _material(Color("5d5b55"), MOON + "moon_worn_deck.png", MOON + "moon_worn_deck.png", 1, Color("45433f"), 0.5)
			material.set_shader_parameter("tile_floor_strength", 0.5)
			material.set_shader_parameter("macro_variation", 0.1)
			material.set_shader_parameter("markings_enabled", false)
		_:
			material = surface("steel")
	_berth_surfaces[role] = material
	return material

# --- rooms ------------------------------------------------------------------

func configure_map(info: Dictionary) -> void:
	if active() and berth_layout(info):
		return
	clear_map()
	if not berth_layout(info):
		return
	for label: String in REGIONS:
		_rooms_by_name[label] = _room(label)
	_build_loading()
	_build_office()
	_build_stern()
	_build_ship()
	_build_cradle()
	_build_gantries()
	_build_gallery()
	_build_shell()
	for room: Node3D in _unattached:
		_finish(room)
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

func _mat(key: String, tint: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	return _shape.material("m09_" + key, tint, metallic, roughness)

## The room a world point belongs to, so each merged mesh stays local and
## carries its own nearby lights.
static func region(p: Vector3) -> String:
	if absf(p.x) > 47.0 or absf(p.z) > 47.0 or p.y > 17.0:
		return "Shell"
	if p.z < -35.0:
		return "Loading" if p.x < -12.0 else "Stern"
	if p.x < -12.0 and p.z < -14.0:
		return "Office"
	if p.z < -22.0:
		return "Stern" if p.x < 14.0 else "Gallery"
	if p.x >= 14.0 and p.z < -12.0:
		return "Gallery"
	if p.z >= 21.0:
		return "GantryNorth"
	if p.x <= -12.0:
		return "GantryWest"
	if p.x >= 15.0:
		return "GantryEast"
	return "Cradle"

func _at(p: Vector3) -> Node3D:
	return _props(_rooms_by_name[region(p)])

func _room_at(p: Vector3) -> Node3D:
	return _rooms_by_name[region(p)]

func _piece(label: String, size: Vector3, finish: Material, at: Vector3) -> MeshInstance3D:
	return _block(_at(at), label, size, finish, at)

func _rod(label: String, a: Vector3, b: Vector3, radius: float, finish: StandardMaterial3D, segments: int = 6) -> MeshInstance3D:
	return _shape.rod(_at((a + b) * 0.5), label, a, b, radius, finish, segments)

## A cold issued flood on a bracket, aimed at `target`: the Union's light.
func _flood(at: Vector3, target: Vector3, energy: float = 2.4, reach: float = 13.0, angle: float = 34.0) -> SpotLight3D:
	var hood: StandardMaterial3D = _mat("fixture_hood", Color("2c2d32"), 0.5, 0.5)
	var hood_node: MeshInstance3D = _piece("FloodHood", Vector3(0.55, 0.32, 0.55), hood, at + Vector3(0, 0.12, 0))
	hood_node.rotation.y = atan2(target.x - at.x, target.z - at.z)
	_piece("FloodLens", Vector3(0.44, 0.02, 0.44), _glow("flood_lens", Color("e6eeee"), 2.4), at - Vector3(0, 0.05, 0))
	var light: SpotLight3D = SpotLight3D.new()
	light.name = "BerthFlood%d" % lamps
	light.position = at - Vector3(0, 0.1, 0)
	light.look_at_from_position(light.position, target, Vector3.UP)
	light.light_color = COLD
	light.light_energy = energy
	light.light_specular = 0.12
	light.spot_range = reach
	light.spot_angle = angle
	light.spot_angle_attenuation = 0.7
	light.spot_attenuation = 0.9
	light.shadow_enabled = false
	_room_at(at).add_child(light)
	lamps += 1
	return light

## Ochre and black edge paint flush on a walkway's open edge: a real drop.
func _edge(from: Vector3, to: Vector3) -> void:
	var span: Vector3 = to - from
	var along_x: bool = absf(span.x) >= absf(span.z)
	var length: float = span.length()
	var centre: Vector3 = (from + to) * 0.5
	var props: Node3D = _at(centre)
	_block(props, "EdgeBand", Vector3(length, 0.006, 0.32) if along_x else Vector3(0.32, 0.006, length), _mat("chevron_dark", Color("2a2b2a")), centre + Vector3(0, 0.004, 0))
	var count: int = int(length / 0.7)
	for index: int in range(count):
		var offset: float = -length * 0.5 + 0.35 + float(index) * 0.7
		var stripe: MeshInstance3D = _block(props, "EdgeStripe", Vector3(0.24, 0.007, 0.36), _mat("chevron_ochre", OCHRE),
			centre + (Vector3(offset, 0.005, 0) if along_x else Vector3(0, 0.005, offset)))
		stripe.rotation.y = (PI * 0.25) if along_x else (PI * 0.75)
		stripe.scale = Vector3(1, 1, 0.8)

## A pasted impound notice: pale paper, a red seal block and ruled lines
## too small to read. `normal` is the face it is pasted on.
func _notice(at: Vector3, normal: Vector3, scale: float = 1.0) -> void:
	var props: Node3D = _at(at)
	var basis: Basis = Basis.looking_at(-normal, Vector3.UP if absf(normal.y) < 0.9 else Vector3.FORWARD)
	var paper: MeshInstance3D = _block(props, "ImpoundNotice", Vector3(0.62, 0.86, 0.008) * Vector3(scale, scale, 1.0), _mat("notice_paper", Color("b7ae96"), 0.0, 0.95), at + normal * 0.006)
	paper.basis = basis
	var seal: MeshInstance3D = _block(props, "NoticeSeal", Vector3(0.16, 0.16, 0.006) * Vector3(scale, scale, 1.0), _mat("notice_seal", SEAL_RED), at + normal * 0.012 + basis.y * 0.26 * scale)
	seal.basis = basis
	for line: int in range(5):
		var rule: MeshInstance3D = _block(props, "NoticeLine", Vector3(0.44, 0.022, 0.004) * Vector3(scale, scale, 1.0), _mat("notice_ink", Color("4a4740")), at + normal * 0.012 + basis.y * (0.06 - float(line) * 0.075) * scale)
		rule.basis = basis

## Union seal tape across a seam: two red strips in an X with a seal disc.
func _seal_tape(centre: Vector3, normal: Vector3, width: float, height: float) -> void:
	var props: Node3D = _at(centre)
	var basis: Basis = Basis.looking_at(-normal, Vector3.UP if absf(normal.y) < 0.9 else Vector3.FORWARD)
	var length: float = sqrt(width * width + height * height)
	var tilt: float = atan2(height, width)
	for sign_value: float in [-1.0, 1.0]:
		var strip: MeshInstance3D = _block(props, "SealTape", Vector3(length, 0.09, 0.006), _mat("seal_tape", SEAL_RED.darkened(0.1)), centre + normal * 0.01)
		strip.basis = basis * Basis(Vector3.BACK, tilt * sign_value)
	var disc: MeshInstance3D = _shape.cylinder(props, "SealDisc", 0.14, 0.012, _mat("seal_disc", SEAL_RED), centre + normal * 0.016, 10)
	disc.basis = basis * Basis(Vector3.RIGHT, PI * 0.5)

## Unlit ship glazing: dark, a little sheen, never tinted.
func glass_dark() -> StandardMaterial3D:
	return _mat("windscreen", Color("1e2324"), 0.6, 0.25)

## A passenger's bag tagged as cargo on an existing top.
func _bag(at: Vector3, colour: Color, index: int) -> void:
	var props: Node3D = _at(at)
	var size: Vector3 = Vector3(0.7, 0.36, 0.42) if index % 3 != 1 else Vector3(0.48, 0.56, 0.3)
	var bag: MeshInstance3D = _block(props, "PassengerBag", size, _mat("bag_%s" % colour.to_html(false), colour, 0.0, 0.9), at + Vector3(0, size.y * 0.5, 0))
	bag.rotation.y = float(index % 5) * 0.35
	_block(props, "BagStrap", Vector3(size.x + 0.02, 0.05, 0.08), _mat("bag_strap", Color("3a3530"), 0.0, 0.9), at + Vector3(0, size.y + 0.01, 0)).rotation.y = bag.rotation.y
	# The cargo tag: white card on a string, the passenger listed as freight.
	_block(props, "CargoTag", Vector3(0.12, 0.16, 0.006), _mat("cargo_tag", Color("b9b29c"), 0.0, 0.95), at + Vector3(size.x * 0.4, size.y * 0.7, size.z * 0.5 + 0.01)).rotation.y = bag.rotation.y

# --- the loading lanes --------------------------------------------------------

func _build_loading() -> void:
	var room: Node3D = _rooms_by_name["Loading"]
	var props: Node3D = _props(room)
	var steel: StandardMaterial3D = _mat("issued_steel", Color("3a3e40"), 0.4, 0.6)
	var frame: StandardMaterial3D = _mat("lock_frame", Color("5a605f"), 0.4, 0.6)
	var rail: StandardMaterial3D = _mat("rail_steel", Color("6c6a62"), 0.6, 0.4)
	# The freight line: two rails and their sleepers from the freight lock in
	# the west wall to where the car stopped.
	for z: float in [-45.8, -44.2]:
		_block(props, "FreightRail", Vector3(10.4, 0.05, 0.1), rail, Vector3(-38.8, 0.025, z))
	var sleeper: float = -43.6
	while sleeper < -34.0:
		_block(props, "RailSleeper", Vector3(0.24, 0.02, 2.4), _mat("sleeper", Color("3b3936"), 0.1, 0.9), Vector3(sleeper, 0.01, -45.0))
		sleeper += 0.8
	_chevrons(props, Vector3(-34.6, 0, -45.0), false, 2.6, 0.35)
	# The freight lock the car came through: a closed pressure leaf on the
	# lane face of the west bulkhead, its dogs and hazard header.
	var face_x: float = -43.985
	_block(props, "FreightLockLeaf", Vector3(0.03, 4.4, 4.4), steel, Vector3(face_x + 0.015, 2.2, -45.5))
	_block(props, "FreightLockSplit", Vector3(0.04, 4.4, 0.06), _mat("lock_seal", Color("232526"), 0.0, 0.9), Vector3(face_x + 0.03, 2.2, -45.5))
	_block(props, "FreightLockHeader", Vector3(0.14, 0.5, 4.9), frame, Vector3(face_x + 0.07, 4.65, -45.5))
	for index: int in range(7):
		var stripe: MeshInstance3D = _block(props, "LockHazard", Vector3(0.01, 0.62, 0.18), _mat("chevron_ochre", OCHRE), Vector3(face_x + 0.145, 4.65, -47.4 + float(index) * 0.62))
		stripe.rotation.x = PI * 0.22
	# The car nobody sent: bogies and couplers flush on the freight car's
	# faces, a window band, an amber destination lamp with nothing written on it.
	var bogie: StandardMaterial3D = _mat("bogie", Color("2c2e2f"), 0.5, 0.6)
	for x: float in [-41.6, -37.4]:
		for z: float in [-47.012, -42.988]:
			_block(props, "CarBogie", Vector3(2.0, 0.55, 0.03), bogie, Vector3(x, 0.32, z))
			for wheel: float in [-0.55, 0.55]:
				_shape.cylinder(props, "CarWheel", 0.3, 0.04, rail, Vector3(x + wheel, 0.3, z + (0.025 if z > -45.0 else -0.025)), 10).rotation.x = PI * 0.5
	for z: float in [-47.016, -42.984]:
		_block(props, "CarWindowBand", Vector3(6.2, 0.5, 0.02), _mat("car_window", Color("2a2f30"), 0.6, 0.3), Vector3(-39.5, 1.5, z))
		_block(props, "CarStripe", Vector3(6.6, 0.1, 0.02), _mat("chevron_ochre", OCHRE), Vector3(-39.5, 1.12, z))
	_block(props, "CarCoupler", Vector3(0.5, 0.18, 0.24), bogie, Vector3(-35.75, 0.7, -45.0))
	_block(props, "CarDestination", Vector3(0.02, 0.24, 1.2), _glow("destination", Color("d9a45a"), 1.2), Vector3(-35.988, 1.7, -45.0))
	_lamp(room, Vector3(-38.0, 5.2, -42.0), 1.6, 7.0, 8.4)
	# Freight on the lanes: the crates carry the passengers' bags, each tagged.
	var tops: Array = [[Vector3(-32.6, 2.0, -40.6), 0], [Vector3(-31.2, 2.0, -39.2), 1], [Vector3(-33.1, 2.0, -38.9), 2],
		[Vector3(-22.5, 2.0, -42.8), 3], [Vector3(-21.1, 2.0, -41.0), 4], [Vector3(-15.6, 2.0, -37.8), 5]]
	for entry: Array in tops:
		_bag(entry[0], BAGS[int(entry[1]) % BAGS.size()], int(entry[1]))
	# The berth's manifest board on the lane's east wall: rows of tags.
	var board_x: float = -13.012
	_block(props, "ManifestBoard", Vector3(0.03, 1.6, 3.2), _mat("register_board", Color("4a4d4c"), 0.2, 0.7), Vector3(board_x, 1.9, -44.0))
	for row: int in range(5):
		for column: int in range(8):
			if (row * 8 + column) % 11 == 4:
				continue
			_block(props, "ManifestTag", Vector3(0.012, 0.18, 0.26), _mat("cargo_tag", Color("b9b29c"), 0.0, 0.95), Vector3(board_x - 0.02, 1.35 + float(row) * 0.27, -45.35 + float(column) * 0.38))
	_lamp(room, Vector3(-14.0, 3.6, -44.0), 1.4, 6.0, 8.4)
	# Cold issued pools under the receiving roof.
	_pool(room, Vector3(-27.0, 8.1, -41.0), 2.2, 9.0, 44.0, 8.4)
	_pool(room, Vector3(-18.0, 8.1, -41.5), 2.0, 9.0, 44.0, 8.4)
	_dust(props, Vector3(-40.0, 0, -42.0), Vector2(5.0, 2.0), 10, 5)
	_dust(props, Vector3(-28.0, 0, -36.5), Vector2(8.0, 2.0), 8, 9)

# --- the impound office and its landing ------------------------------------

func _build_office() -> void:
	var room: Node3D = _rooms_by_name["Office"]
	var props: Node3D = _props(room)
	var steel: StandardMaterial3D = _mat("issued_steel", Color("3a3e40"), 0.4, 0.6)
	var rail: StandardMaterial3D = _mat("platform_rail", Color("3e4142"), 0.4, 0.6)
	# A top rail on the landing's real guards; none across the gap in them.
	for segment: Array in LANDING_RAILS:
		_shape.rod(props, "LandingRail", segment[0], segment[1], 0.04, rail, 5)
	# The gap: the rail's torn stubs and ochre paint at the edge, a real drop.
	for z: float in [-32.45, -29.55]:
		_shape.rod(props, "RailStub", Vector3(-17.85, 5.14, z), Vector3(-17.85, 5.0, z + (0.25 if z < -31.0 else -0.25)), 0.035, rail, 5)
	_edge(Vector3(-18.2, 4.0, -32.5), Vector3(-18.2, 4.0, -29.5))
	_dust(props, Vector3(-24.0, 4.0, -31.0), Vector2(6.0, 4.0), 8, 13)
	# The Union's flood on the landing, from the office eaves: the Enforcer's stage.
	_flood(Vector3(-24.0, 8.0, -27.4), Vector3(-23.0, 4.0, -31.0), 2.6, 9.0, 40.0)
	# The impound office. A seal banner on the west wall inside.
	_hang_banner(props, Transform3D(Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * 0.62), Vector3(-37.97, 5.6, -20.0)))
	# The restraint rail on the north wall, where the crew were held: a bar,
	# shackle pairs hanging open.
	var shackle: StandardMaterial3D = _mat("shackle", Color("6e6c66"), 0.6, 0.4)
	_block(props, "RestraintBar", Vector3(9.0, 0.08, 0.08), steel, Vector3(-30.5, 5.3, -16.05))
	for index: int in range(7):
		var x: float = -34.5 + float(index) * 1.3
		_block(props, "RestraintPlate", Vector3(0.16, 0.22, 0.03), steel, Vector3(x, 5.3, -16.02))
		_shape.rod(props, "Shackle", Vector3(x - 0.06, 5.25, -16.1), Vector3(x - 0.08, 4.92, -16.12), 0.018, shackle, 5)
		_shape.rod(props, "Shackle", Vector3(x + 0.06, 5.25, -16.1), Vector3(x + 0.1, 4.95, -16.14), 0.018, shackle, 5)
	# Filing cabinets on the east wall inside, one drawer pulled.
	for index: int in range(3):
		var z: float = -19.6 + float(index) * 0.62
		_block(props, "FilingCabinet", Vector3(0.5, 1.3, 0.55), steel, Vector3(-18.27, 4.65, z))
		for drawer: int in range(3):
			_block(props, "CabinetPull", Vector3(0.02, 0.04, 0.18), _mat("handle", Color("8e8775"), 0.5, 0.5), Vector3(-18.53, 4.3 + float(drawer) * 0.4, z))
	_block(props, "OpenDrawer", Vector3(0.42, 0.3, 0.5), steel, Vector3(-18.75, 4.95, -18.98))
	# The customs locker: an issued box with a red seal and, scratched under
	# it, a six.
	_block(props, "LockerSeal", Vector3(0.006, 0.2, 0.2), _mat("registration_seal", SEAL_RED), Vector3(-34.995, 4.72, -21.5))
	var scratch: StandardMaterial3D = _mat("scratch", Color("8f8c84"), 0.0, 0.9)
	# Seen from the office (+x), the viewer's left is +z.
	for stroke: Array in [[Vector3(-34.994, 4.36, -21.44), Vector3(0.004, 0.2, 0.025)], [Vector3(-34.994, 4.27, -21.5), Vector3(0.004, 0.025, 0.12)],
		[Vector3(-34.994, 4.32, -21.56), Vector3(0.004, 0.1, 0.025)], [Vector3(-34.994, 4.37, -21.5), Vector3(0.004, 0.025, 0.12)], [Vector3(-34.994, 4.46, -21.48), Vector3(0.004, 0.025, 0.08)]]:
		_block(props, "ScratchedSix", stroke[1], scratch, stroke[0])
	for index: int in range(3):
		_block(props, "FormStack", Vector3(0.3, 0.05 + float(index) * 0.03, 0.22), _mat("forms", Color("cfc6ad"), 0.0, 0.95), Vector3(-36.0, 5.03 + float(index) * 0.015, -22.6 + float(index) * 0.4))
	_block(props, "Stamp", Vector3(0.08, 0.12, 0.08), steel, Vector3(-35.6, 5.06, -20.6))
	# What the impound clerk took from the passengers, tagged, on the floor
	# against the west wall.
	for index: int in range(4):
		_bag(Vector3(-37.4, 4.0, -24.2 + float(index) * 0.9), BAGS[(index * 3 + 1) % BAGS.size()], index)
	_pool(room, Vector3(-33.0, 7.9, -20.5), 1.8, 6.0, 44.0, 8.0)
	_lamp(room, Vector3(-24.0, 7.5, -20.0), 1.6, 7.0, 8.0)
	# The office stair: a warm lamp at the turn.
	_lamp(room, Vector3(-41.0, 7.6, -26.0), 1.4, 6.0, 8.4)
	_lamp(room, Vector3(-41.0, 6.6, -32.0), 1.2, 6.0, 8.4)

# --- the boarding stack and the hatch bridge --------------------------------

func _build_stern() -> void:
	var room: Node3D = _rooms_by_name["Stern"]
	var props: Node3D = _props(room)
	var frame: StandardMaterial3D = _mat("lock_frame", Color("5a605f"), 0.4, 0.6)
	var pipe: StandardMaterial3D = _mat("service_pipe", Color("54605d"), 0.4, 0.6)
	# The boarding stack's lane face: service ribs, a run of pipe up to the
	# room, an ochre band at the bridge.
	var face_z: float = -30.012
	for x: float in [-8.5, -4.5, 4.5, 8.5]:
		_block(props, "StackRib", Vector3(0.3, 11.8, 0.05), frame, Vector3(x, 5.9, face_z))
	for x: float in [-6.6, -6.1]:
		_shape.rod(props, "StackPipe", Vector3(x, 0.0, face_z - 0.12), Vector3(x, 11.3, face_z - 0.12), 0.08, pipe, 6)
	_block(props, "StackBand", Vector3(20.0, 0.4, 0.04), _mat("chevron_ochre", OCHRE), Vector3(0, 10.6, face_z))
	# The hatch's frame on the jambs: hazard chevrons, dogs, seal tape and
	# pasted notices. The readable notice is on the hatch itself.
	var jamb_z: float = -31.012
	for side: float in [-1.0, 1.0]:
		_block(props, "HatchJamb", Vector3(0.3, 4.0, 0.06), frame, Vector3(side * 3.15, 14.0, jamb_z))
		for index: int in range(5):
			var stripe: MeshInstance3D = _block(props, "HatchHazard", Vector3(0.24, 0.5, 0.01), _mat("chevron_ochre", OCHRE), Vector3(side * 3.55, 12.5 + float(index) * 0.7, jamb_z - 0.02))
			stripe.rotation.z = PI * 0.22 * side
		_seal_tape(Vector3(side * 4.4, 14.3, jamb_z), Vector3.FORWARD, 1.0, 1.2)
		_notice(Vector3(side * 6.8, 14.0, jamb_z), Vector3.FORWARD)
	_dust(props, Vector3(0, 12.0, -32.5), Vector2(5.0, 2.0), 8, 17)
	# Edge paint along the hatch bridge's open sides.
	_edge(Vector3(-11.8, 12.0, -34.85), Vector3(23.8, 12.0, -34.85))
	_edge(Vector3(10.2, 12.0, -28.15), Vector3(15.8, 12.0, -28.15))
	# Warm lamps under the bridge for the lane, and over the hatch.
	_lamp(room, Vector3(0.0, 10.9, -33.0), 1.6, 8.0, 11.4)
	_lamp(room, Vector3(14.0, 10.9, -31.5), 1.4, 7.0, 11.4)
	_flood(Vector3(-8.0, 16.2, -31.5), Vector3(-1.0, 12.4, -33.0), 2.2, 9.0, 40.0)

# --- the ship ----------------------------------------------------------------

func _build_ship() -> void:
	var room: Node3D = _rooms_by_name["Cradle"]
	var props: Node3D = _props(room)
	var rib: StandardMaterial3D = _mat("hull_rib", HULL_DARK, 0.4, 0.6)
	var belly: StandardMaterial3D = _mat("hull_belly", Color("3c4144"), 0.3, 0.7)
	var ember: StandardMaterial3D = _mat("ember_stripe", EMBER, 0.1, 0.7)
	var bone: StandardMaterial3D = _mat("pressure_bone", BONE, 0.1, 0.8)
	var seam: StandardMaterial3D = _mat("hull_seam", Color("3a3f41"), 0.3, 0.7)
	for side: float in [-1.0, 1.0]:
		var x: float = side * 8.012
		# Belly band, the ember stripe, a plate seam, the gunwale under the deck.
		_block(props, "HullBelly", Vector3(0.025, 1.0, 36.0), belly, Vector3(x, 2.5, 0.0))
		_block(props, "HullEmber", Vector3(0.03, 0.34, 40.0), ember, Vector3(x + side * 0.002, 3.3, -2.0))
		_block(props, "HullSeam", Vector3(0.026, 0.05, 40.0), seam, Vector3(x, 5.6, -2.0))
		_block(props, "HullGunwale", Vector3(0.05, 0.22, 40.0), rib, Vector3(x + side * 0.01, 8.85, -2.0))
		# Gunmetal ribs every three metres along both sides.
		var z: float = -21.0
		while z <= 17.5:
			_block(props, "HullRib", Vector3(0.05, 5.8, 0.14), rib, Vector3(x + side * 0.012, 5.95, z))
			z += 3.0
		# The bow's sides carry the stripe on round.
		_block(props, "BowEmber", Vector3(0.03, 0.34, 5.0), ember, Vector3(side * 5.014, 3.3, 20.5))
		_block(props, "BowBelly", Vector3(0.025, 1.0, 5.0), belly, Vector3(side * 5.012, 2.5, 20.5))
		# The bone deck's edge over the hull.
		_block(props, "DeckEdge", Vector3(0.04, 0.14, 24.0), _mat("deck_edge", Color("7d7768"), 0.1, 0.8), Vector3(side * 5.015, 9.1, 0.0))
	# The crew door on the port side near the stern: a bone pressure door
	# under seal tape and a pasted notice.
	# The nacelles cover the stern quarter below the windows, so the door is
	# forward of them.
	_block(props, "CrewDoor", Vector3(0.03, 2.4, 1.3), bone, Vector3(-8.025, 4.0, -4.5))
	_block(props, "CrewDoorFrame", Vector3(0.04, 2.6, 0.12), rib, Vector3(-8.035, 4.0, -5.2))
	_block(props, "CrewDoorFrame", Vector3(0.04, 2.6, 0.12), rib, Vector3(-8.035, 4.0, -3.8))
	_block(props, "CrewDoorHeader", Vector3(0.04, 0.12, 1.5), rib, Vector3(-8.035, 5.32, -4.5))
	_seal_tape(Vector3(-8.035, 4.0, -4.5), Vector3.LEFT, 1.1, 2.0)
	_notice(Vector3(-8.035, 4.4, -2.6), Vector3.LEFT)
	_notice(Vector3(-8.035, 4.2, 14.6), Vector3.LEFT)
	# The cargo door on the starboard side, chevroned, sealed.
	_block(props, "CargoDoor", Vector3(0.03, 3.6, 4.2), bone, Vector3(8.02, 4.2, 0.0))
	for index: int in range(7):
		var stripe: MeshInstance3D = _block(props, "CargoDoorHazard", Vector3(0.01, 0.5, 0.2), _mat("chevron_ochre", OCHRE), Vector3(8.04, 6.2, -1.8 + float(index) * 0.6))
		stripe.rotation.x = PI * 0.22
	_block(props, "CargoDoorSplit", Vector3(0.035, 3.6, 0.05), seam, Vector3(8.025, 4.2, 0.0))
	_seal_tape(Vector3(8.04, 4.2, 0.0), Vector3.RIGHT, 1.6, 2.4)
	_notice(Vector3(8.03, 4.4, 3.0), Vector3.RIGHT)
	_notice(Vector3(8.03, 4.4, 10.5), Vector3.RIGHT)
	# The upper freight hatch on the bone deck, sealed.
	_block(props, "DeckHatch", Vector3(2.8, 0.03, 2.8), _mat("deck_hatch", Color("8e8876"), 0.2, 0.7), Vector3(0.0, 11.015, -4.0))
	_block(props, "DeckHatchRim", Vector3(3.1, 0.04, 0.12), rib, Vector3(0.0, 11.02, -5.45))
	_block(props, "DeckHatchRim", Vector3(3.1, 0.04, 0.12), rib, Vector3(0.0, 11.02, -2.55))
	_seal_tape(Vector3(0.0, 11.03, -4.0), Vector3.UP, 2.0, 2.0)
	# Deck vents and a mast with a warm navigation lamp.
	for z: float in [4.0, 7.0]:
		_block(props, "DeckVent", Vector3(1.6, 0.03, 0.8), seam, Vector3(-2.5, 11.015, z))
	# The deckhouse at the forward end of the bone deck, out of every reach
	# and every firing lane: Tern's ship has a bridge, and it is dark.
	_block(props, "Deckhouse", Vector3(5.6, 1.2, 3.2), bone, Vector3(0.0, 11.6, 9.9))
	_block(props, "DeckhouseRoof", Vector3(5.9, 0.12, 3.5), rib, Vector3(0.0, 12.26, 9.9))
	_block(props, "DeckhouseWindows", Vector3(5.0, 0.42, 0.03), glass_dark(), Vector3(0.0, 11.75, 11.515))
	for side: float in [-1.0, 1.0]:
		_block(props, "DeckhouseSideWindow", Vector3(0.03, 0.42, 2.2), glass_dark(), Vector3(side * 2.815, 11.75, 10.0))
	_block(props, "DeckhouseEmber", Vector3(5.62, 0.14, 3.22), ember, Vector3(0.0, 11.12, 9.9))
	_shape.rod(props, "NavMast", Vector3(1.8, 12.3, 9.0), Vector3(1.8, 14.2, 9.0), 0.05, rib, 6)
	_shape.rod(props, "NavYard", Vector3(1.1, 13.7, 9.0), Vector3(2.5, 13.7, 9.0), 0.03, rib, 5)
	_block(props, "NavLamp", Vector3(0.16, 0.16, 0.16), _glow("nav_lamp", Color("e2a65c"), 1.6), Vector3(1.8, 14.3, 9.0))
	# The bow: a cockpit windscreen in frames, dim, with Tern's empty seat
	# and a warm instrument glow behind it.
	var glass: StandardMaterial3D = glass_dark()
	_block(props, "Windscreen", Vector3(8.0, 1.3, 0.03), glass, Vector3(0.0, 4.9, 23.012))
	for x: float in [-4.05, -2.0, 0.0, 2.0, 4.05]:
		_block(props, "WindscreenMullion", Vector3(0.14, 1.42, 0.05), rib, Vector3(x, 4.9, 23.025))
	_block(props, "WindscreenSill", Vector3(8.3, 0.12, 0.06), rib, Vector3(0.0, 4.2, 23.03))
	_block(props, "InstrumentGlow", Vector3(2.4, 0.12, 0.02), _glow("instrument", Color("d9a45a"), 0.9), Vector3(-1.2, 4.38, 23.03))
	_block(props, "NoseEmber", Vector3(10.0, 0.34, 0.03), ember, Vector3(0.0, 3.3, 23.014))
	_block(props, "NoseBelly", Vector3(10.0, 1.0, 0.025), belly, Vector3(0.0, 2.5, 23.012))
	# Engine bells on the stern faces of both nacelles, soot below them.
	var bell: StandardMaterial3D = _mat("engine_bell", Color("6a6158"), 0.6, 0.4)
	var throat: StandardMaterial3D = _mat("engine_throat", Color("1a1b1c"), 0.2, 0.9)
	for side: float in [-1.0, 1.0]:
		_shape.cylinder(props, "EngineBell", 1.35, 0.14, bell, Vector3(side * 11.0, 3.2, -17.07), 14).rotation.x = PI * 0.5
		_shape.cylinder(props, "EngineThroat", 1.0, 0.04, throat, Vector3(side * 11.0, 3.2, -17.15), 14).rotation.x = PI * 0.5
		_block(props, "NacelleBand", Vector3(6.02, 0.3, 0.03), ember, Vector3(side * 11.0, 4.6, -17.02))
	# Umbilicals from the roof structure and the boarding stack to the ship.
	var hose: StandardMaterial3D = _mat("umbilical", Color("3a3c38"), 0.2, 0.8)
	var collar: StandardMaterial3D = _mat("chevron_ochre", OCHRE)
	for line: Array in [[Vector3(-12.4, 25.9, -6.0), Vector3(-4.2, 11.0, -7.0)], [Vector3(12.4, 25.9, 5.0), Vector3(4.2, 11.0, 6.0)],
		[Vector3(-12.4, 25.9, 10.0), Vector3(-4.2, 11.0, 9.0)]]:
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		var points: PackedVector3Array = []
		for step: int in range(9):
			var t: float = float(step) / 8.0
			var p: Vector3 = a.lerp(b, t)
			p.x += sin(t * PI) * signf(a.x) * 1.4
			points.append(p)
		_shape.pipe(_props(_rooms_by_name["Shell"]), "Umbilical", points, 0.16, hose)
		_shape.cylinder(props, "UmbilicalCollar", 0.24, 0.3, collar, b + Vector3(0, 0.15, 0), 10)
	# The ship's own work lights along the deck edge, warm.
	_lamp(room, Vector3(-6.5, 9.45, 14.0), 1.2, 6.0, 0.0)
	_lamp(room, Vector3(6.5, 9.45, -14.0), 1.2, 6.0, 0.0)

# --- the cradle -----------------------------------------------------------------

func _build_cradle() -> void:
	var room: Node3D = _rooms_by_name["Cradle"]
	var props: Node3D = _props(room)
	var paint: StandardMaterial3D = _mat("cradle_line", OCHRE, 0.0, 0.9)
	var soot: StandardMaterial3D = _mat("engine_soot", Color("2d2c2a"), 0.0, 1.0)
	# The cradle footprint painted on the deck around the ship.
	for line: Array in [[Vector3(-9.6, 0, -19.6), Vector3(-9.6, 0, 23.6)], [Vector3(9.6, 0, -19.6), Vector3(9.6, 0, 23.6)],
		[Vector3(-9.6, 0, 23.6), Vector3(9.6, 0, 23.6)]]:
		_paint_line(props, line[0], line[1], 0.22, paint)
	# Soot fanned under the engines and the stern.
	for side: float in [-1.0, 1.0]:
		for index: int in range(6):
			var patch: MeshInstance3D = _block(props, "EngineSoot", Vector3(2.6 - float(index) * 0.25, 0.005, 1.2), soot, Vector3(side * 11.0 + float(index % 3 - 1) * 0.4, 0.004 + float(index) * 0.0004, -18.0 - float(index) * 0.9))
			patch.rotation.y = float(index % 3) * 0.3 - 0.3
	# Clamp shoes at each chock and tie-down rings across the cradle floor.
	var shoe: StandardMaterial3D = _mat("clamp_shoe", Color("4a4637"), 0.4, 0.6)
	for chock: Vector3 in [Vector3(-7.0, 0, -13.5), Vector3(7.0, 0, -13.5), Vector3(-7.0, 0, 9.5), Vector3(7.0, 0, 9.5)]:
		_block(props, "ChockSaddle", Vector3(2.04, 0.12, 3.04), shoe, chock + Vector3(0, 1.94, 0))
		_block(props, "ChockFoot", Vector3(2.6, 0.08, 3.6), shoe, chock + Vector3(0, 0.04, 0))
	var ring: StandardMaterial3D = _mat("tie_ring", Color("5b5a55"), 0.6, 0.4)
	for x: float in [-3.0, 3.0]:
		for z: float in [-6.0, 2.0, 14.0]:
			_shape.cylinder(props, "TieRing", 0.22, 0.03, ring, Vector3(x, 0.015, z), 10)
	_dust(props, Vector3(0, 0, 0), Vector2(14.0, 30.0), 14, 41)
	# Under the keel it is dark; a few caged lamps on the chocks.
	_lamp(room, Vector3(-6.0, 1.85, -2.0), 1.1, 5.5, 2.0)
	_lamp(room, Vector3(6.0, 1.85, 4.0), 1.1, 5.5, 2.0)

# --- the gantries ---------------------------------------------------------------

func _build_gantries() -> void:
	# Every open edge toward the cradle is painted; nothing pretends to be a rail.
	_edge(Vector3(-16.2, 6.0, -12.8), Vector3(-16.2, 6.0, 13.8))
	_edge(Vector3(-23.8, 6.0, -12.8), Vector3(-23.8, 6.0, 13.8))
	_edge(Vector3(-15.8, 8.0, 22.2), Vector3(21.8, 8.0, 22.2))
	_edge(Vector3(-23.8, 8.0, 29.8), Vector3(21.8, 8.0, 29.8))
	_edge(Vector3(26.2, 10.0, -11.8), Vector3(26.2, 10.0, 21.8))
	_edge(Vector3(33.8, 10.0, -11.8), Vector3(33.8, 10.0, 29.8))
	_edge(Vector3(26.2, 10.0, 29.8), Vector3(33.8, 10.0, 29.8))
	# Cable trays inside the outer edges, and caged lamps under the shelters.
	var tray: StandardMaterial3D = _mat("platform_rail", Color("3e4142"), 0.4, 0.6)
	_piece("CableTray", Vector3(0.3, 0.1, 26.0), tray, Vector3(-23.4, 6.05, 0.5))
	_piece("CableTray", Vector3(36.0, 0.1, 0.3), tray, Vector3(-2.0, 8.05, 29.4))
	_piece("CableTray", Vector3(0.3, 0.1, 40.0), tray, Vector3(33.4, 10.05, 9.0))
	_lamp(_rooms_by_name["GantryWest"], Vector3(-20.0, 9.5, -8.0), 1.6, 7.0, 10.0)
	_lamp(_rooms_by_name["GantryWest"], Vector3(-20.0, 9.5, 6.0), 1.6, 7.0, 10.0)
	_lamp(_rooms_by_name["GantryNorth"], Vector3(-14.0, 11.9, 26.0), 1.6, 7.0, 12.4)
	_lamp(_rooms_by_name["GantryNorth"], Vector3(2.0, 11.9, 26.0), 1.6, 7.0, 12.4)
	_lamp(_rooms_by_name["GantryNorth"], Vector3(16.0, 11.9, 26.0), 1.6, 7.0, 12.4)
	_lamp(_rooms_by_name["GantryEast"], Vector3(30.0, 13.9, 16.0), 1.6, 7.0, 14.4)
	_lamp(_rooms_by_name["GantryEast"], Vector3(30.0, 13.9, 0.0), 1.6, 7.0, 14.4)
	# Columns: ochre bands at the foot so they read on a dark deck.
	var band: StandardMaterial3D = _mat("chevron_ochre", OCHRE)
	for column: Vector2 in [Vector2(-23.5, -0.5), Vector2(-16.5, -0.5), Vector2(-23.5, 29.5), Vector2(21.5, 29.5), Vector2(-0.5, 29.5),
		Vector2(26.5, 9.5), Vector2(33.5, 9.5), Vector2(39.5, -12.5), Vector2(-10.5, -34.5), Vector2(23.5, -34.5)]:
		_piece("ColumnBand", Vector3(1.06, 0.6, 1.06), band, Vector3(column.x, 0.5, column.y))
	# Each gantry's service post: a hose reel against the outer edge.
	var reel: StandardMaterial3D = _mat("hose_reel", Color("6b5a3c"), 0.3, 0.6)
	for spot: Vector3 in [Vector3(-23.6, 6.0, -5.0), Vector3(-10.0, 8.0, 29.6), Vector3(33.6, 10.0, 4.0)]:
		var turned: bool = absf(spot.z - 29.6) < 0.2
		var reel_node: MeshInstance3D = _shape.cylinder(_at(spot), "HoseReel", 0.36, 0.2, reel, spot + Vector3(0, 0.5, 0), 12)
		reel_node.rotation = Vector3(PI * 0.5, 0, 0) if turned else Vector3(0, 0, PI * 0.5)
	# Bags the passengers carried up, left at each landing as they boarded.
	_bag(Vector3(-23.3, 6.0, 9.0), BAGS[2], 2)
	_bag(Vector3(8.0, 8.0, 29.4), BAGS[5], 5)
	_bag(Vector3(33.4, 10.0, 26.0), BAGS[6], 6)

# --- the control gallery: the Union's high ground ---------------------------

func _build_gallery() -> void:
	var room: Node3D = _rooms_by_name["Gallery"]
	var props: Node3D = _props(room)
	var steel: StandardMaterial3D = _mat("issued_steel", Color("3a3e40"), 0.4, 0.6)
	_edge(Vector3(16.2, 10.0, -23.8), Vector3(16.2, 10.0, -12.2))
	_edge(Vector3(24.2, 10.0, -23.85), Vector3(39.8, 10.0, -23.85))
	_edge(Vector3(39.85, 10.0, -23.8), Vector3(39.85, 10.0, -12.2))
	_edge(Vector3(16.2, 10.0, -12.15), Vector3(25.8, 10.0, -12.15))
	_edge(Vector3(34.2, 10.0, -12.15), Vector3(39.8, 10.0, -12.15))
	# The impound clerk's cabinet near the gallery's south edge, tagged
	# confiscated, the stolen goods' own seal on it.
	_block(props, "ImpoundCabinet", Vector3(1.6, 1.3, 0.45), steel, Vector3(25.4, 10.65, -23.2))
	_block(props, "CabinetSeal", Vector3(0.2, 0.2, 0.006), _mat("registration_seal", SEAL_RED), Vector3(25.0, 10.95, -22.972))
	_red_tag(props, Vector3(25.8, 10.9, -22.965), "south")
	var scratch: StandardMaterial3D = _mat("scratch", Color("8f8c84"), 0.0, 0.9)
	for stroke: Array in [[Vector3(24.94, 10.56, -22.973), Vector3(0.025, 0.2, 0.004)], [Vector3(25.0, 10.47, -22.973), Vector3(0.12, 0.025, 0.004)],
		[Vector3(25.06, 10.52, -22.973), Vector3(0.025, 0.1, 0.004)], [Vector3(25.0, 10.58, -22.973), Vector3(0.12, 0.025, 0.004)], [Vector3(24.98, 10.66, -22.973), Vector3(0.08, 0.025, 0.004)]]:
		_block(props, "ScratchedSix", stroke[1], scratch, stroke[0])
	# Seal banners hung under the gallery roof, facing the cradle.
	for at: Vector3 in [Vector3(16.1, 12.0, -20.0), Vector3(16.1, 12.0, -15.0)]:
		_hang_banner(props, Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * 0.55), at))
	# The clamp control console's lit faces, issued and cold.
	_block(props, "ConsoleScreen", Vector3(0.02, 0.4, 1.2), _glow("console_screen", Color("b8c2bc"), 0.8), Vector3(18.012, 11.4, -22.0))
	_pool(room, Vector3(22.0, 14.0, -18.0), 2.0, 7.0, 44.0, 14.4)
	_pool(room, Vector3(34.0, 14.0, -18.0), 2.0, 7.0, 44.0, 14.4)
	# The gallery's floods trained on the hull.
	_flood(Vector3(16.6, 14.0, -13.0), Vector3(7.0, 7.0, -6.0), 2.4, 14.0, 34.0)
	_flood(Vector3(16.6, 14.0, -23.0), Vector3(8.0, 6.0, -16.0), 2.2, 13.0, 34.0)

# --- the shell, the roof and the sky ---------------------------------------------

func _build_shell() -> void:
	var room: Node3D = _rooms_by_name["Shell"]
	var props: Node3D = _props(room)
	# Earth over the glazed roof, and a few hard stars.
	var earth: MeshInstance3D = MeshInstance3D.new()
	earth.name = "Earth"
	var disc: QuadMesh = QuadMesh.new()
	disc.size = Vector2(26, 26)
	earth.mesh = disc
	earth.position = Vector3(6.0, 112.0, 52.0)
	var planet: StandardMaterial3D = MoonBackdrop._material(Color.WHITE, true)
	planet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	planet.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var earth_path: String = "res://assets/environment/moon/earth.png"
	if ResourceLoader.exists(earth_path):
		planet.albedo_texture = load(earth_path) as Texture2D
	earth.material_override = planet
	room.add_child(earth)
	var star: StandardMaterial3D = _glow("star", Color("d8d4c8"), 1.4)
	for index: int in range(22):
		var u: float = fposmod(sin(float(index) * 12.9898) * 43758.5453, 1.0)
		var v: float = fposmod(sin(float(index) * 78.233) * 12345.678, 1.0)
		_block(props, "Star", Vector3(0.7, 0.7, 0.7), star, Vector3(-40.0 + u * 80.0, 150.0 + v * 20.0, -60.0 + v * 140.0))
	# Pressure ribs on the long shell walls, an ochre service band at the
	# gantry heights, and two restrained seals on the north wall.
	var rib: StandardMaterial3D = _mat("shell_rib", Color("8a8473"), 0.2, 0.8)
	var band: StandardMaterial3D = _mat("chevron_ochre", OCHRE)
	for side: float in [-1.0, 1.0]:
		var x: float = side * 47.985
		var z: float = -42.0
		while z <= 42.0:
			_block(props, "ShellRib", Vector3(0.04, 25.8, 0.3), rib, Vector3(x, 12.9, z))
			z += 6.0
		_block(props, "ShellBand", Vector3(0.03, 0.5, 95.8), band, Vector3(x, 16.6, 0.0))
	for side: float in [-1.0, 1.0]:
		var z: float = side * 47.985
		var x: float = -42.0
		while x <= 42.0:
			_block(props, "ShellRib", Vector3(0.3, 25.8, 0.04), rib, Vector3(x, 12.9, z))
			x += 6.0
		_block(props, "ShellBand", Vector3(95.8, 0.5, 0.03), band, Vector3(0.0, 16.6, z))
	for x: float in [-10.0, 10.0]:
		_hang_banner(props, Transform3D(Basis.IDENTITY, Vector3(x, 19.5, 47.96)))

## The port's seal banner placed by `turn`, which may scale it: it hangs on
## a wall whose face points along the turn's -z.
func _hang_banner(props: Node3D, turn: Transform3D) -> void:
	var holder: Node3D = Node3D.new()
	_banner(holder, Vector3.ZERO)
	for child: Node in holder.get_children():
		var piece: Node3D = child
		holder.remove_child(piece)
		piece.transform = turn * piece.transform
		props.add_child(piece)
	holder.free()
