class_name M07Dressing
extends M06Dressing

## Declared Goods' golden-slice dressing (docs/campaign/l07-declared-goods.md,
## docs/design/moon.md). The server owns every solid; like the port's
## dressing this presenter only restyles the solid views and furnishes them:
## surfaces by use, flush frontage, small possessions against walls or on
## tops, overhead lines above head height, scenery outside the playable
## square and practical light. A body that could stop a pawn or a shot is
## never added.
##
## The town is not the port. The port is issued bone-grey shell and cargo
## light; the habitation ring is old, lived and painted by the people who
## live in it, block by block, in faded personal colours. The low sun sits
## behind the town wall, so the streets lie in long shade under the dome and
## the only hard light inside is the Union's: cold curfew floods on brackets
## and the post's own pools. Every door carries the same small red
## registration seal. Washing hangs over the ring street, water tanks and
## masts stand on the roofs, the market is covered for the night, and a
## child's chalk game is still on the alley floor. Out of the town the crater
## cut is hard sun on pale regolith and dark basalt, with weathered radiation
## shields and the marksmen's platforms on the rim, each a lit stage against
## a pale blast screen so a black body and its glint read across the cut.

const TOWN_MAP_ID: int = 1007
const PROD: String = "res://assets/environment/production/"
## The town's playable street area [min_x, min_z, size]: everything south of
## the crater cut inside the town wall.
const TOWN: Rect2 = Rect2(-70, -70, 116, 70)
## Faded house paint, block by block: mid values so a black-and-red guard
## reads against any of them. Never black with red, never matte off-white,
## never cyan.
const HOUSE: Array[Color] = [Color("8d7f6a"), Color("7d8774"), Color("917564"), Color("767d86"),
	Color("968862"), Color("837889"), Color("88806f"), Color("6f8079")]
## Door, curtain, washing and window-box colours the residents chose.
const HOMES: Array[Color] = [Color("a8552c"), Color("6f8a4e"), Color("c49a3c"), Color("8a3a58"),
	Color("4f6f8a"), Color("b5652e"), Color("7c5a8c"), Color("9c7c45"), Color("5f7a64")]
const LEAF: Color = Color("74884e")
const LEAF_DARK: Color = Color("3a4c2e")
const CHALK: Color = Color("c4bfb2")
const FLOOD: Color = Color(0.86, 0.92, 0.95)
## The marksmen's rim positions (x, z), from the authored window lesson and
## crater cut encounters.
const RIM_STAGES: Array[Vector2] = [Vector2(-30, 59.5), Vector2(-14, 59.5), Vector2(-6, 61), Vector2(2, 59.5), Vector2(18, 59.5), Vector2(32, 59.5)]
const RIM_TOP: float = 9.0
const REGIONS: Array[String] = ["Tunnel", "RingWest", "RingEast", "Plaza", "SideStreet", "Square", "Post",
	"CutSouth", "CutNorth", "Rim", "Depot", "Crater"]

static var _town_surfaces: Dictionary[String, ShaderMaterial] = {}
var _rooms_by_name: Dictionary[String, Node3D] = {}
var _boxes: Array[AABB] = []

func clear_map() -> void:
	_rooms_by_name.clear()
	_boxes.clear()
	super.clear_map()

## Declared Goods' own authored layout only, keyed on walls that never move:
## the town wall, the market vault, the curfew post's rack and window sill,
## both cut walls, the rim and the depot deck. A custom map reusing the id
## with different structure gets no dressing rather than floating props.
static func town_layout(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != TOWN_MAP_ID or not info.get("solids") is Array:
		return false
	var wanted: Array = [
		[Vector3(-72, 0, -72), Vector3(46, 10, -70)],
		[Vector3(-6, 0, -31), Vector3(8, 4.3, -25)],
		[Vector3(-2, 0, -1.3), Vector3(1, 2.2, -0.5)],
		[Vector3(-8, 0, -0.5), Vector3(-4, 5.45, 0)],
		[Vector3(-40, 0, 0), Vector3(-36, 14, 68)],
		[Vector3(44, 0, 0), Vector3(48, 14, 48)],
		[Vector3(-36, 0, 58), Vector3(44, 9, 66)],
		[Vector3(44, 0, 48), Vector3(70, 9, 70)],
	]
	for pair: Array in wanted:
		if M06Workmanship._host(info["solids"], pair[0], pair[1]).is_empty():
			return false
	return true

# --- surfaces ---------------------------------------------------------------

## Restyle the server's solid views by use: house frontage block by block,
## the curfew post and depot in issued steel, market furniture, the cut's
## regolith, basalt and radiation shields, plus the paved town floor and the
## lunar ground outside the walls.
static func restyle_town(cover: Node3D, info: Dictionary, views: Array[MeshInstance3D]) -> void:
	if not town_layout(info) or not info.get("presentation") is Dictionary:
		return
	var solids: Array = info["solids"]
	var surfaces: Array = info["presentation"].get("solids", [])
	if surfaces.size() != solids.size() or views.size() != solids.size():
		return
	for index: int in range(solids.size()):
		if not solids[index] is Dictionary or not is_instance_valid(views[index]):
			continue
		var box: AABB = _bounds(solids[index])
		var role: String = town_role(box, str(surfaces[index]))
		if role == "glass":
			views[index].material_override = glass()
		elif role == "house":
			views[index].material_override = house_paint(HOUSE[_hash(box.get_center()) % HOUSE.size()])
		elif role == "goods":
			views[index].material_override = freight_paint(FREIGHT[_hash(box.get_center()) % FREIGHT.size()])
		else:
			views[index].material_override = town_surface(role)
	var floor: MeshInstance3D = cover.get_node_or_null("MapFloor") as MeshInstance3D
	if floor != null:
		floor.visible = false
	var ground: Node3D = Node3D.new()
	ground.name = "M07Ground"
	cover.add_child(ground)
	var x: float = TOWN.position.x
	while x < TOWN.end.x - 0.01:
		var width: float = minf(FLOOR_TILE, TOWN.end.x - x)
		var z: float = TOWN.position.y
		while z < TOWN.end.y - 0.01:
			var depth: float = minf(FLOOR_TILE, TOWN.end.y - z)
			_plane(ground, "TownPaving%d" % ground.get_child_count(), Vector3(x + width * 0.5, 0.0, z + depth * 0.5), Vector2(width, depth), town_surface("paving"))
			z += depth
		x += width
	var far: float = 320.0
	for rect: Rect2 in [Rect2(-far, -far, far - 70, far * 2), Rect2(-70, -far, far + 70, far - 70),
		Rect2(46, -70, far - 46, far + 70), Rect2(-70, 0, 116, far)]:
		_plane(ground, "LunarGround%d" % ground.get_child_count(), Vector3(rect.get_center().x, -0.01, rect.get_center().y), rect.size, surface("apron"))
	ArenaSky.mark_world(ground)

## A solid's visual role from its registered surface and where it stands.
static func town_role(box: AABB, surface: String) -> String:
	var low: Vector3 = box.position
	var high: Vector3 = box.end
	var centre: Vector3 = box.get_center()
	if surface == "inspection_glass":
		return "glass"
	if centre.z > 0.0:
		# The crater cut, its rim and the depot.
		if low.x >= 44.0 and low.z >= 46.0:
			return "panel" if surface == "lift_panel" and box.size.y < 2.0 and is_equal_approx(low.x, 66.0) else ("goods" if surface == "lift_panel" else "depot")
		if surface == "lift_panel":
			return "marker" if box.size.x <= 0.6 else "goods"
		if surface == "service_steel":
			if box.size.x <= 1.01 or box.size.z <= 1.01:
				return "stair"
			return "shield"
		if is_equal_approx(low.z, 58.0) and is_equal_approx(high.z, 66.0):
			return "rim"
		if low.y >= 3.9:
			return "berm"
		if box.size.y >= 13.0 and (is_equal_approx(low.z, 66.0) or is_equal_approx(low.z, 70.0)):
			return "rim_back"
		if box.size.y >= 13.0:
			return "crater"
		return "regolith"
	# The town.
	if surface == "service_steel":
		if low.x >= -14.01 and high.x <= 2.01 and low.z >= -10.01:
			return "post"
		if box.size.y >= 4.0:
			return "vault"
		if box.size.y <= 1.3:
			return "barrier"
		return "kiosk"
	if surface == "lift_panel":
		if low.x <= -60.0 and low.z <= -66.0:
			return "car"
		if low.y >= 3.4:
			return "steel"
		if box.size.y <= 1.15 and box.size.x >= 2.9:
			return "stall"
		if box.size.y >= 3.4:
			return "kiosk"
		return "goods"
	if surface == "concrete" and box.size.y <= 4.5:
		return "stone"
	if low.y >= 4.9 and box.size.y <= 0.5:
		return "ceiling"
	if box.size.y >= 5.5 or low.y >= 2.7:
		return "house"
	return "porch"

static func town_surface(role: String) -> ShaderMaterial:
	if _town_surfaces.has(role):
		return _town_surfaces[role]
	var material: ShaderMaterial
	match role:
		"post":
			# Issued steel, one step lighter than a Union body so a black
			# Clerk in front of it still reads; ribbed plates, no red paint.
			material = _material(Color("62676a"), MOON + "moon_union_service.png", MOON + "moon_worn_deck.png", 3, Color("777c7e"), 0.45)
			material.set_shader_parameter("panel_size", 1.5)
		"depot":
			material = _material(Color("55595c"), MOON + "moon_union_service.png", MOON + "moon_worn_deck.png", 3, Color("6c7073"), 0.5)
		"vault":
			# The market's own strongroom: old riveted steel, warm and patched.
			material = _material(Color("6b6153"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, Color("7a6a52"), 0.25)
		"kiosk":
			material = _material(Color("5c665d"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, Color("6c766b"), 0.2)
		"barrier":
			material = _material(Color("4e5254"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, OCHRE, 0.4)
		"stall":
			material = _material(Color("6e5c48"), MOON + "moon_civilian_fabric.png", MOON + "moon_repair_plate.png", 0, Color("6a5a44"), 0.2)
			material.set_shader_parameter("markings_enabled", false)
		"car":
			material = _material(Color("5f6e62"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 2, Color("9a7f45"), 0.35)
			material.set_shader_parameter("deck_spacing", 3.2)
		"steel":
			material = _material(Color("5a5f5f"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, Color("6a6f6c"), 0.45)
		"stone":
			material = _material(Color("85806f"), PROD + "lunar_concrete.png", PROD + "lunar_concrete.png", 1, Color("6e6a5c"), 0.35)
		"ceiling":
			material = _material(Color("4c5050"), PRODUCTION + "lunar_steel.png", PRODUCTION + "archive_steel.png", 3, Color("3f4343"), 0.35)
		"porch":
			material = _material(Color("807868"), PROD + "lunar_plaster.png", MOON + "moon_worn_deck.png", 1, Color("6f6858"), 0.3)
		"paving":
			material = _material(Color("77736a"), MOON + "moon_worn_deck.png", PROD + "lunar_concrete.png", 1, Color("5e5b54"), 0.35)
			material.set_shader_parameter("panel_size", 2.0)
			material.set_shader_parameter("macro_variation", 0.06)
		"regolith":
			material = _material(Color("67645d"), MOON + "moon_basalt.png", MOON + "moon_regolith.png", 0, Color("67645d"), 0.14)
			material.set_shader_parameter("markings_enabled", false)
			material.set_shader_parameter("macro_variation", 0.08)
		"berm":
			# Compacted regolith heaped and bladed into a wall.
			material = _material(Color("6b675f"), MOON + "moon_basalt.png", MOON + "moon_regolith.png", 0, Color("6b675f"), 0.16)
			material.set_shader_parameter("markings_enabled", false)
			material.set_shader_parameter("macro_variation", 0.08)
		"crater":
			material = _material(Color("3e4242"), MOON + "moon_basalt.png", MOON + "moon_regolith.png", 0, Color("3e4242"), 0.5)
			material.set_shader_parameter("tile_floor_strength", 0.16)
			material.set_shader_parameter("markings_enabled", false)
		"rim":
			material = _material(Color("4a4c4a"), MOON + "moon_basalt.png", MOON + "moon_regolith.png", 0, Color("4a4c4a"), 0.5)
			material.set_shader_parameter("tile_floor_strength", 0.16)
			material.set_shader_parameter("markings_enabled", false)
		"rim_back":
			# A pale retaining face behind the platforms: lunar dust over
			# concrete, light enough that a black marksman stands out on it.
			material = _material(Color("6f6b62"), MOON + "moon_basalt.png", MOON + "moon_regolith.png", 1, Color("5c5850"), 0.14)
		"shield":
			# Weathered radiation shielding: galvanised plates, ochre edge
			# plates, never Union black or red.
			material = _material(Color("555952"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, OCHRE, 0.25)
			material.set_shader_parameter("panel_size", 1.6)
		"stair":
			material = _material(Color("5d6261"), PRODUCTION + "lunar_steel.png", MOON + "moon_worn_deck.png", 3, OCHRE, 0.45)
		"marker":
			material = _material(OCHRE, MOON + "moon_repair_plate.png", MOON + "moon_repair_plate.png", 0, OCHRE, 0.3)
		_:
			material = surface(role)
	_town_surfaces[role] = material
	return material

## One block's own paint: faded enamel over plaster with a painted dado in a
## darker shade of the same colour, storey after storey.
static func house_paint(tint: Color) -> ShaderMaterial:
	var key: String = "house_" + tint.to_html(false)
	if _town_surfaces.has(key):
		return _town_surfaces[key]
	var material: ShaderMaterial = _material(tint, PROD + "lunar_plaster.png", MOON + "moon_worn_deck.png", 2, tint.darkened(0.22), 0.14)
	material.set_shader_parameter("deck_spacing", 4.0)
	material.set_shader_parameter("warning_color", tint.darkened(0.4))
	material.set_shader_parameter("panel_size", 2.5)
	material.set_shader_parameter("sector_variation", 0.04)
	_town_surfaces[key] = material
	return material

# --- rooms ------------------------------------------------------------------

func configure_map(info: Dictionary) -> void:
	if active() and town_layout(info):
		return
	clear_map()
	if not town_layout(info):
		return
	for solid: Variant in info["solids"]:
		_boxes.append(_bounds(solid))
	for label: String in REGIONS:
		_rooms_by_name[label] = _room(label)
	_facades(info)
	_build_tunnel()
	_build_ring()
	_build_market()
	_build_side_street()
	_build_square()
	_build_post()
	_build_cut()
	_build_rim()
	_build_depot()
	_build_crater()
	for room: Node3D in _unattached:
		_finish(room)
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

func _mat(key: String, tint: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	return _shape.material("m07_" + key, tint, metallic, roughness)

## The room a world point belongs to, so each merged mesh stays local and
## carries its own nearby lights.
static func region(p: Vector3) -> String:
	if p.x < -72.0 or p.x > 72.0 or p.z > 72.0 or p.z < -72.0:
		return "Crater"
	if p.x >= 44.0 and p.z >= 46.0:
		return "Depot"
	if p.z >= 56.0:
		return "Rim"
	if p.z >= 28.0:
		return "CutNorth"
	if p.z >= 0.0:
		return "CutSouth"
	if p.x < -56.0 and p.z < -57.0:
		return "Tunnel"
	if p.z < -36.0:
		return "RingWest" if p.x < -18.0 else "RingEast"
	if p.z < -20.0 and p.x > -31.0:
		return "Plaza"
	if p.x < -31.0:
		return "SideStreet"
	if p.x > -14.5 and p.x < 2.5 and p.z > -8.5:
		return "Post"
	return "Square"

func _at(p: Vector3) -> Node3D:
	return _props(_rooms_by_name[region(p)])

func _room_at(p: Vector3) -> Node3D:
	return _rooms_by_name[region(p)]

func _piece(label: String, size: Vector3, finish: Material, at: Vector3) -> MeshInstance3D:
	return _block(_at(at), label, size, finish, at)

func _rod(label: String, a: Vector3, b: Vector3, radius: float, finish: StandardMaterial3D, segments: int = 6) -> MeshInstance3D:
	return _shape.rod(_at((a + b) * 0.5), label, a, b, radius, finish, segments)

## A Union curfew flood on a wall bracket: arm, hood, cold lens and a hard
## spot aimed down and out over the street.
func _flood(wall: Vector3, outward: Vector3, energy: float = 2.6, reach: float = 13.0, angle: float = 38.0) -> SpotLight3D:
	var arm: StandardMaterial3D = _mat("flood_arm", Color("2f3132"), 0.4, 0.6)
	var hood: StandardMaterial3D = _mat("fixture_hood", Color("2c2d32"), 0.5, 0.5)
	var head: Vector3 = wall + outward * 1.1
	_rod("FloodArm", wall + Vector3(0, 0.3, 0), head + Vector3(0, 0.15, 0), 0.04, arm)
	_piece("FloodPlate", Vector3(0.3, 0.5, 0.3), arm, wall + outward * 0.1 + Vector3(0, 0.2, 0))
	var hood_node: MeshInstance3D = _piece("FloodHood", Vector3(0.55, 0.32, 0.55), hood, head + Vector3(0, 0.1, 0))
	hood_node.rotation.y = atan2(outward.x, outward.z)
	_piece("FloodLens", Vector3(0.44, 0.02, 0.44), _glow("flood_lens", Color("e6eeee"), 2.4), head - Vector3(0, 0.07, 0))
	var light: SpotLight3D = SpotLight3D.new()
	light.name = "CurfewFlood%d" % lamps
	light.position = head - Vector3(0, 0.12, 0)
	var target: Vector3 = head + outward * 4.5 - Vector3(0, head.y, 0)
	light.look_at_from_position(light.position, target, Vector3.UP if absf(outward.y) < 0.9 else Vector3.FORWARD)
	light.light_color = FLOOD
	light.light_energy = energy
	light.light_specular = 0.12
	light.spot_range = reach
	light.spot_angle = angle
	light.spot_angle_attenuation = 0.7
	light.spot_attenuation = 0.9
	light.shadow_enabled = false
	_room_at(head).add_child(light)
	lamps += 1
	return light

# --- frontage: doors, windows, pipes and roofs on every street face ---------

func _facades(info: Dictionary) -> void:
	var solids: Array = info["solids"]
	var surfaces: Array = info["presentation"]["solids"]
	var occupied: Dictionary = {}
	for detail: Variant in info["presentation"].get("decorations", []):
		if not detail is Dictionary or not detail.has_all(["solid", "face", "center", "size"]):
			continue
		var host_index: int = int(detail["solid"])
		if host_index < 0 or host_index >= solids.size():
			continue
		var placed: Transform3D = MapDecoration.placement(solids[host_index], detail)
		var key: String = "%d:%s" % [host_index, str(detail["face"])]
		var along: float = placed.origin.x if str(detail["face"]) in ["north", "south"] else placed.origin.z
		var half: float = float(detail["size"][0]) * 0.5 + 0.5
		if not occupied.has(key):
			occupied[key] = []
		occupied[key].append(Vector2(along - half, along + half))
	for index: int in range(solids.size()):
		var box: AABB = _boxes[index]
		var role: String = town_role(box, str(surfaces[index]))
		if role != "house" or box.position.y > 0.1 or box.get_center().z > 0.0:
			continue
		var tint: Color = HOUSE[_hash(box.get_center()) % HOUSE.size()]
		for face: String in ["north", "south", "west", "east"]:
			var runs: Array[Vector2] = _exposed_runs(box, face)
			for run: Vector2 in runs:
				_frontage(box, face, run, occupied.get("%d:%s" % [index, face], []), tint, index)

## The street-facing stretches of one face: samples just outside the face at
## knee height that are inside the town and inside no other solid.
func _exposed_runs(box: AABB, face: String) -> Array[Vector2]:
	var runs: Array[Vector2] = []
	var along_x: bool = face in ["north", "south"]
	var start: float = box.position.x if along_x else box.position.z
	var finish: float = box.end.x if along_x else box.end.z
	var strip: AABB = AABB(_face_point(box, face, start, 1.0) + _outward(face) * 0.6, Vector3.ZERO).expand(_face_point(box, face, finish, 1.0) + _outward(face) * 0.6).grow(0.2)
	var near: Array[AABB] = []
	for other: AABB in _boxes:
		if other.intersects(strip):
			near.append(other)
	var run_start: float = INF
	var t: float = start + 0.5
	while t <= finish - 0.5 + 0.001:
		var probe: Vector3 = _face_point(box, face, t, 1.0) + _outward(face) * 0.6
		var open: bool = TOWN.has_point(Vector2(probe.x, probe.z))
		if open:
			for other: AABB in near:
				if other.grow(0.01).has_point(probe):
					open = false
					break
		if open and run_start == INF:
			run_start = t - 0.5
		elif not open and run_start != INF:
			runs.append(Vector2(run_start, t - 0.5))
			run_start = INF
		t += 1.0
	if run_start != INF:
		runs.append(Vector2(run_start, minf(t - 0.5, finish)))
	return runs

static func _outward(face: String) -> Vector3:
	match face:
		"north": return Vector3.FORWARD
		"south": return Vector3.BACK
		"west": return Vector3.LEFT
		_: return Vector3.RIGHT

static func _face_point(box: AABB, face: String, along: float, y: float) -> Vector3:
	match face:
		"north": return Vector3(along, y, box.position.z)
		"south": return Vector3(along, y, box.end.z)
		"west": return Vector3(box.position.x, y, along)
		_: return Vector3(box.end.x, y, along)

func _frontage(box: AABB, face: String, run: Vector2, taken: Array, tint: Color, seed_value: int) -> void:
	var out: Vector3 = _outward(face)
	var along_x: bool = face in ["north", "south"]
	var span: Vector3 = Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var top: float = box.end.y
	var length: float = run.y - run.x
	if length < 1.5:
		return
	var trim: StandardMaterial3D = _mat("trim_%s" % tint.to_html(false), tint.darkened(0.35), 0.1, 0.8)
	var pipe: StandardMaterial3D = _mat("conduit", Color("575b58"), 0.4, 0.6)
	var middle: float = (run.x + run.y) * 0.5
	# Cornice along the roof line and a service conduit between storeys.
	_piece("Cornice", (span * length) + Vector3(0, 0.22, 0) + (Vector3(0, 0, 0.28) if along_x else Vector3(0.28, 0, 0)),
		trim, _face_point(box, face, middle, top - 0.18) + out * 0.13)
	if top >= 5.5:
		var a: Vector3 = _face_point(box, face, run.x + 0.3, 3.9) + out * 0.12
		var b: Vector3 = _face_point(box, face, run.y - 0.3, 3.9) + out * 0.12
		_rod("Conduit", a, b, 0.05, pipe)
		var bracket: float = run.x + 1.0
		while bracket < run.y - 0.5:
			_piece("ConduitBracket", Vector3(0.06, 0.16, 0.06) + out.abs() * 0.1, pipe, _face_point(box, face, bracket, 3.9) + out * 0.06)
			bracket += 2.5
		var drop: float = run.x + 0.6
		while drop < run.y - 0.3:
			_rod("Downpipe", _face_point(box, face, drop, 0.15) + out * 0.1, _face_point(box, face, drop, top - 0.3) + out * 0.1, 0.06, pipe)
			drop += 13.0
	# Doors where no shutter or notice stands.
	var free: Array[Vector2] = [run]
	for interval: Variant in taken:
		var cut: Vector2 = interval
		var next: Array[Vector2] = []
		for piece: Vector2 in free:
			if cut.y <= piece.x or cut.x >= piece.y:
				next.append(piece)
				continue
			if cut.x > piece.x:
				next.append(Vector2(piece.x, cut.x))
			if cut.y < piece.y:
				next.append(Vector2(cut.y, piece.y))
		free = next
	var count: int = 0
	for gap: Vector2 in free:
		if gap.y - gap.x < 2.3:
			continue
		var at: float = gap.x + 1.15
		while at <= gap.y - 1.15:
			_door(box, face, at, HOMES[(seed_value * 5 + count * 3) % HOMES.size()], count + seed_value)
			if top >= 5.5:
				_window(box, face, at, 4.9, seed_value + count * 7)
			count += 1
			at += 6.5
	# Upper storeys: dark windows, some with curtains or a window box.
	var rows: Array[float] = []
	if top >= 7.5:
		rows.append(6.45)
	if top >= 9.5:
		rows.append(8.25)
	for y: float in rows:
		var at: float = run.x + 1.4
		var step: int = 0
		while at <= run.y - 1.0:
			var variant: int = seed_value * 11 + step * 5 + int(y)
			if variant % 5 != 2:
				_window(box, face, at, y, variant)
			at += 3.6 + float(variant % 3) * 0.5
			step += 1
	# Roof clutter set back from the street edge: tanks, vents and masts.
	if top >= 5.5 and length >= 6.0:
		var at: float = run.x + 3.0 + float(seed_value % 4)
		var step: int = 0
		while at <= run.y - 2.0:
			var base: Vector3 = _face_point(box, face, at, top) - out * 1.8
			match (step + seed_value) % 3:
				0:
					_tank(base, tint)
				1:
					_piece("RoofVent", Vector3(0.7, 1.2, 0.7), _mat("vent", Color("5a5c58"), 0.3, 0.7), base + Vector3(0, 0.6, 0))
					_piece("RoofVentCap", Vector3(0.95, 0.1, 0.95), _mat("vent_cap", Color("43464a"), 0.3, 0.7), base + Vector3(0, 1.25, 0))
				_:
					_rod("RoofMast", base, base + Vector3(0, 3.2, 0), 0.035, _mat("mast", Color("4a4c4a"), 0.4, 0.6))
					_rod("RoofMastArm", base + Vector3(-0.5, 2.8, 0), base + Vector3(0.5, 2.8, 0), 0.02, _mat("mast", Color("4a4c4a"), 0.4, 0.6))
			at += 9.0 + float((seed_value + step) % 3) * 2.0
			step += 1

func _door(box: AABB, face: String, along: float, colour: Color, variant: int) -> void:
	var out: Vector3 = _outward(face)
	var along_x: bool = face in ["north", "south"]
	var span: Vector3 = Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var depth: Vector3 = out.abs()
	var frame: StandardMaterial3D = _mat("door_frame", Color("3f413f"), 0.3, 0.7)
	var leaf: StandardMaterial3D = _mat("door_%s" % colour.to_html(false), colour.darkened(0.2), 0.1, 0.75)
	var base: Vector3 = _face_point(box, face, along, 0.0)
	_piece("DoorFrame", span * 1.5 + Vector3(0, 2.55, 0) + depth * 0.05, frame, base + Vector3(0, 1.275, 0) + out * 0.025)
	_piece("DoorLeaf", span * 1.2 + Vector3(0, 2.3, 0) + depth * 0.05, leaf, base + Vector3(0, 1.15, 0) + out * 0.05)
	_piece("DoorHandle", span * 0.06 + Vector3(0, 0.22, 0) + depth * 0.05, _mat("handle", Color("8e8775"), 0.5, 0.5), base + span * 0.45 + Vector3(0, 1.05, 0) + out * 0.09)
	# Every household is on the register: one small red seal on every door.
	_piece("RegistrationSeal", span * 0.14 + Vector3(0, 0.14, 0) + depth * 0.01, _mat("registration_seal", SEAL_RED), base - span * 0.1 + Vector3(0, 1.62, 0) + out * 0.08)
	_piece("DoorStep", span * 1.5 + Vector3(0, 0.03, 0) + depth * 0.32, _mat("door_step", Color("5e5a50")), base + Vector3(0, 0.015, 0) + out * 0.16)
	# What people keep at the threshold: a mat, a pot, boots, a crate.
	match variant % 4:
		0:
			_piece("DoorMat", span * 0.9 + Vector3(0, 0.012, 0) + depth * 0.5, _mat("mat_%d" % (variant % 3), HOMES[(variant + 2) % HOMES.size()].darkened(0.3)), base + Vector3(0, 0.036, 0) + out * 0.62)
		1:
			var pot: Vector3 = base + span * 1.05 + out * 0.25
			_piece("DoorPot", Vector3(0.32, 0.36, 0.32), _mat("pot", Color("7a4a32"), 0.0, 0.9), pot + Vector3(0, 0.18, 0))
			_piece("DoorPotLeaves", Vector3(0.4, 0.3, 0.4), _mat("leaf", LEAF), pot + Vector3(0, 0.5, 0))
		2:
			var boots: Vector3 = base - span * 1.0 + out * 0.2
			for side: float in [-0.09, 0.09]:
				_piece("DoorBoot", Vector3(0.12, 0.22, 0.12) + depth * 0.12, _mat("boot", Color("3e3b35")), boots + span * side + Vector3(0, 0.11, 0))
		_:
			_crate(_at(base), base + span * 1.1 + out * 0.3, Vector3(0.45, 0.4, 0.4), HOMES[(variant + 4) % HOMES.size()].darkened(0.1))
	# The doorway lamp is dark under curfew.
	_piece("DoorLamp", Vector3(0.18, 0.12, 0.18), _mat("dark_lamp", Color("2a2b2b"), 0.2, 0.5), base + Vector3(0, 2.75, 0) + out * 0.18)

func _window(box: AABB, face: String, along: float, y: float, variant: int) -> void:
	var out: Vector3 = _outward(face)
	var along_x: bool = face in ["north", "south"]
	var span: Vector3 = Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var depth: Vector3 = out.abs()
	var base: Vector3 = _face_point(box, face, along, y)
	_piece("WindowFrame", span * 1.15 + Vector3(0, 1.05, 0) + depth * 0.04, _mat("window_frame", Color("45474a"), 0.3, 0.7), base + out * 0.02)
	_piece("WindowGlass", span * 0.95 + Vector3(0, 0.85, 0) + depth * 0.04, _mat("window_dark", Color("15191c"), 0.6, 0.3), base + out * 0.03)
	_piece("WindowSill", span * 1.25 + Vector3(0, 0.06, 0) + depth * 0.16, _mat("window_sill", Color("6a665c")), base - Vector3(0, 0.55, 0) + out * 0.08)
	if variant % 3 == 0:
		# A curtain drawn behind the dark pane, in the household's colour.
		_piece("Curtain", span * 0.42 + Vector3(0, 0.8, 0) + depth * 0.01, _mat("curtain_%d" % (variant % HOMES.size()), HOMES[variant % HOMES.size()].darkened(0.45)), base - span * 0.24 + out * 0.055)
	if variant % 4 == 1:
		var box_at: Vector3 = base - Vector3(0, 0.72, 0) + out * 0.2
		_piece("WindowBox", span * 1.0 + Vector3(0, 0.22, 0) + depth * 0.26, _mat("window_box", Color("6b5440"), 0.0, 0.9), box_at)
		for leaf: int in range(3):
			_piece("WindowGreens", span * 0.26 + Vector3(0, 0.2 + float(leaf % 2) * 0.08, 0) + depth * 0.2,
				_mat("leaf" if leaf % 2 == 0 else "leaf_dark", LEAF if leaf % 2 == 0 else LEAF_DARK), box_at + span * (float(leaf) - 1.0) * 0.32 + Vector3(0, 0.2, 0))

func _tank(base: Vector3, tint: Color) -> void:
	var legs: StandardMaterial3D = _mat("tank_leg", Color("3f4240"), 0.4, 0.6)
	for corner: Vector2 in [Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(-0.6, 0.6), Vector2(0.6, 0.6)]:
		_rod("TankLeg", base + Vector3(corner.x, 0, corner.y), base + Vector3(corner.x * 0.8, 0.7, corner.y * 0.8), 0.04, legs)
	var body: MeshInstance3D = _shape.cylinder(_at(base), "WaterTank", 0.95, 1.7, _mat("tank_%s" % tint.to_html(false), tint.lightened(0.08), 0.2, 0.7), base + Vector3(0, 1.55, 0), 12)
	body.rotation.x = PI * 0.5
	_piece("TankBand", Vector3(1.96, 0.1, 1.96), legs, base + Vector3(0, 1.9, 0))

# --- tunnel: the transit car and the tunnel mouth ----------------------------

func _build_tunnel() -> void:
	var room: Node3D = _rooms_by_name["Tunnel"]
	var props: Node3D = _props(room)
	var frame: StandardMaterial3D = _mat("lock_frame", Color("5a605f"), 0.4, 0.6)
	# The car's windows and doors on the platform side, lit warm and empty.
	for index: int in range(5):
		var x: float = -68.8 + float(index) * 1.9
		_block(props, "CarWindow", Vector3(1.2, 0.7, 0.03), _glow("car_window", Color("cdb88e"), 0.7), Vector3(x, 2.25, -66.485))
		_block(props, "CarWindowFrame", Vector3(1.32, 0.08, 0.04), frame, Vector3(x, 2.64, -66.48))
	_block(props, "CarDoor", Vector3(1.4, 2.6, 0.03), _mat("car_door", Color("4b574e"), 0.3, 0.6), Vector3(-61.2, 1.4, -66.485))
	_block(props, "CarDoorGap", Vector3(0.05, 2.6, 0.035), _mat("lock_seal", Color("232526")), Vector3(-61.2, 1.4, -66.48))
	_block(props, "CarRoofLamp", Vector3(5.0, 0.06, 0.2), _glow("car_strip", Color("ffe0b0"), 1.2), Vector3(-65.0, 3.15, -66.5))
	_omni(room, "CarSpill", Vector3(-65.0, 2.4, -65.6), WARM, 0.9, 5.0)
	# The tunnel mouth: header and pilasters of a pressure frame, door leaves
	# parked in their slots, and the dust trap underfoot.
	_block(props, "MouthHeader", Vector3(0.5, 0.6, 12.0), frame, Vector3(-55.8, 4.7, -64.0))
	for z: float in [-69.88, -58.12]:
		_block(props, "MouthJamb", Vector3(0.5, 5.0, 0.24), frame, Vector3(-55.8, 2.5, z))
		for y: float in [0.8, 2.0, 3.2]:
			_block(props, "MouthDog", Vector3(0.22, 0.14, 0.08), _mat("lock_dog", Color("8e8775"), 0.3, 0.6), Vector3(-55.8, y, z + (0.16 if z < -64 else -0.16)))
	for index: int in range(10):
		var stripe: MeshInstance3D = _block(props, "MouthHazard", Vector3(0.02, 0.5, 0.18), _mat("chevron_ochre", OCHRE), Vector3(-55.54, 4.7, -68.9 + float(index) * 1.2))
		stripe.rotation.x = PI * 0.22
	var grate: StandardMaterial3D = _mat("drain_grate", Color("303235"), 0.5, 0.6)
	_block(props, "DustTrap", Vector3(1.6, 0.008, 11.0), grate, Vector3(-56.6, 0.004, -64.0))
	for index: int in range(30):
		_block(props, "DustTrapBar", Vector3(1.5, 0.01, 0.07), _mat("drain_bar", Color("6a6c69"), 0.6, 0.5), Vector3(-56.6, 0.007, -69.3 + float(index) * 0.36))
	_dust(props, Vector3(-58.5, 0, -64.0), Vector2(3.0, 9.0), 12, 5)
	_pool(room, Vector3(-62.0, 4.8, -62.0), 1.8, 6.0, 44.0, 5.0)

# --- the ring street: washing, floods and covered stalls -----------------------

func _build_ring() -> void:
	# Washing lines across the street above head height, frontage to frontage.
	var line: StandardMaterial3D = _mat("line", Color("8a8678"), 0.0, 0.9)
	var lines: Array = [[-49.0, -70.0, -54.0, 5.9], [-37.0, -70.0, -54.0, 6.1], [-19.0, -70.0, -54.0, 5.8], [-7.0, -70.0, -54.0, 6.0],
		[3.0, -70.0, -54.0, 5.9], [24.0, -46.0, -45.0, 5.8]]
	for index: int in range(lines.size()):
		var row: Array = lines[index]
		var a: Vector3
		var b: Vector3
		if index < lines.size() - 1:
			a = Vector3(float(row[0]), float(row[3]), float(row[1]) + 0.1)
			b = Vector3(float(row[0]) + 1.5, float(row[3]), float(row[2]) - 0.1)
		else:
			# Across the bend, wall to wall.
			a = Vector3(14.05, float(row[3]), float(row[1]))
			b = Vector3(31.95, float(row[3]) + 0.3, float(row[2]))
		_rod("WashingLine", a, b, 0.025, line, 4)
		var pegs: int = 5 + index % 3
		for peg: int in range(pegs):
			var t: float = (float(peg) + 0.7) / (float(pegs) + 0.4)
			var at: Vector3 = a.lerp(b, t) - Vector3(0, 0.06 + sin(t * PI) * 0.25, 0)
			var colour: Color = HOMES[(index * 4 + peg * 3) % HOMES.size()]
			var size: Vector3 = Vector3(0.45 + float((peg + index) % 3) * 0.2, 0.7 + float((peg * 7 + index) % 4) * 0.18, 0.02)
			var cloth: MeshInstance3D = _piece("Washing", size, _mat("washing_%s" % colour.to_html(false), colour.lightened(0.05), 0.0, 0.95), at - Vector3(0, size.y * 0.5 - 0.02, 0))
			cloth.rotation.y = atan2(b.x - a.x, b.z - a.z) + PI * 0.5
			var peg_node: MeshInstance3D = _piece("WashingPeg", Vector3(0.04, 0.08, 0.04), _mat("peg", Color("b8a888")), at + Vector3(0, 0.02, 0))
			peg_node.rotation.y = cloth.rotation.y
	# Union curfew floods down the ring, high on the frontage.
	for x: float in [-44.0, -24.0, -4.0]:
		_flood(Vector3(x, 6.7, -54.0), Vector3.FORWARD)
	_flood(Vector3(14.0, 6.7, -44.0), Vector3.RIGHT, 2.4)
	_flood(Vector3(32.0, 6.7, -58.0), Vector3.LEFT, 2.4)
	# Stalls covered for the night: tarps over goods, roped down.
	for stall: Vector3 in [Vector3(-44.5, 1.1, -68.75), Vector3(-36.5, 1.1, -55.25), Vector3(-22.5, 1.1, -68.75),
		Vector3(-10.5, 1.1, -55.25), Vector3(-0.5, 1.1, -68.75), Vector3(7.5, 1.1, -55.25)]:
		_covered_goods(stall, int(stall.x))
	# Planter of the ring: kept greens in a concrete box.
	_greens(Vector3(-14.5, 1.0, -62.5), Vector2(2.6, 2.6))
	# Wheel wear and tracked dust down the middle of the ring.
	var wear: StandardMaterial3D = _mat("track_wear", Color("5f5c55"), 0.0, 1.0)
	for z: float in [-63.2, -61.0]:
		_paint_line(_at(Vector3(-30, 0, z)), Vector3(-54, 0, z), Vector3(-18.5, 0, z), 0.3, wear)
		_paint_line(_at(Vector3(0, 0, z)), Vector3(-18.0, 0, z), Vector3(20, 0, z), 0.3, wear)
	_dust(_at(Vector3(-52, 0, -62)), Vector3(-52, 0, -62), Vector2(4.0, 8.0), 10, 9)

func _covered_goods(top: Vector3, variant: int) -> void:
	var tarp: Color = [Color("5f6b5e"), Color("7a6a52"), Color("566474"), Color("8a5a3c")][posmod(variant, 4)]
	_piece("StallTarp", Vector3(2.3, 0.34, 1.0), _mat("tarp_%s" % tarp.to_html(false), tarp, 0.0, 0.95), top + Vector3(0, 0.28, 0))
	_piece("StallTarpFold", Vector3(2.36, 0.06, 1.06), _mat("tarp_fold_%s" % tarp.to_html(false), tarp.darkened(0.2), 0.0, 0.95), top + Vector3(0, 0.46, 0))
	for x: float in [-0.7, 0.7]:
		_piece("StallRope", Vector3(0.03, 0.4, 1.08), _mat("rope", Color("8a7a58")), top + Vector3(x, 0.28, 0))

func _greens(top: Vector3, size: Vector2) -> void:
	var soil: StandardMaterial3D = _mat("soil", Color("3e3428"), 0.0, 1.0)
	_piece("PlanterSoil", Vector3(size.x - 0.2, 0.04, size.y - 0.2), soil, top + Vector3(0, 0.02, 0))
	for index: int in range(7):
		var u: float = float((index * 37) % 10) / 10.0 - 0.45
		var v: float = float((index * 53) % 10) / 10.0 - 0.45
		_piece("PlanterGreens", Vector3(0.36, 0.28 + float(index % 3) * 0.1, 0.36), _mat("leaf" if index % 2 == 0 else "leaf_dark", LEAF if index % 2 == 0 else LEAF_DARK),
			top + Vector3(u * (size.x - 0.6), 0.16, v * (size.y - 0.6)))

# --- market vault plaza ------------------------------------------------------------

func _build_market() -> void:
	# The market's strongroom door on the street side, sealed by order: a red
	# seal strip across the wheel and a tag on the hasp.
	var steel: StandardMaterial3D = _mat("vault_door", Color("6e675a"), 0.5, 0.5)
	var dark: StandardMaterial3D = _mat("vault_dark", Color("2f2f2c"), 0.4, 0.6)
	var door: Vector3 = Vector3(1.0, 1.7, -31.0)
	_shape.cylinder(_at(door), "VaultDoor", 1.35, 0.12, steel, door + Vector3(0, 0, -0.06), 20)
	_shape.cylinder(_at(door), "VaultDoorRim", 1.5, 0.06, dark, door + Vector3(0, 0, -0.02), 20)
	for spoke: int in range(4):
		var angle: float = TAU * float(spoke) / 8.0
		var arm: MeshInstance3D = _piece("VaultWheel", Vector3(1.3, 0.08, 0.06), dark, door + Vector3(0, 0, -0.17))
		arm.rotation.z = angle
	_piece("VaultHinge", Vector3(0.3, 1.8, 0.2), dark, door + Vector3(1.55, 0, -0.1))
	_piece("VaultSealStrip", Vector3(3.0, 0.16, 0.012), _mat("seal_strip", SEAL_RED), door + Vector3(0, 0.1, -0.21))
	_red_tag(_at(door), door + Vector3(-1.1, -0.4, -0.22), "north")
	# The barriers are the Union's: hazard faces toward the market.
	for z: float in [-29.75, -26.25]:
		for side: float in [-1.0, 1.0]:
			_hazard_face(Vector3(11.5 + side * 0.505, 0.6, z), Vector3(0, 0, 1), 2.3)
	_hazard_face(Vector3(4.5, 0.6, -24.0 + 0.505 * -1.0), Vector3(1, 0, 0), 2.8)
	_hazard_face(Vector3(4.5, 0.6, -23.0 + 0.505), Vector3(1, 0, 0), 2.8)
	# The weigh booth: a service window with its shutter down and a ledger shelf.
	_piece("BoothShutter", Vector3(2.4, 0.9, 0.04), _mat("shutter", Color("2b2f31")), Vector3(-8.5, 1.6, -26.98))
	for rib: int in range(4):
		_piece("BoothShutterRib", Vector3(2.4, 0.04, 0.02), _mat("shutter_rib", Color("1b1e1f")), Vector3(-8.5, 1.25 + float(rib) * 0.22, -26.955))
	_piece("BoothLedge", Vector3(2.6, 0.06, 0.3), _mat("booth_ledge", Color("6a5a44")), Vector3(-8.5, 1.1, -26.85))
	_piece("BoothAwning", Vector3(3.0, 0.06, 0.9), _mat("awning", Color("6a5a40")), Vector3(-8.5, 2.5, -26.55))
	# Covered stalls on the plaza.
	for stall: Vector3 in [Vector3(21.5, 1.1, -33.75), Vector3(21.5, 1.1, -22.25), Vector3(-22.5, 1.1, -33.75)]:
		_covered_goods(stall, int(stall.z))
	_greens(Vector3(-18.5, 1.0, -22.0), Vector2(3.0, 2.0))
	# Floods over the plaza, and the vault's own work lamp over the door.
	_flood(Vector3(-4.0, 6.7, -36.0), Vector3.BACK, 2.6)
	_flood(Vector3(22.0, 5.0, -20.0), Vector3.FORWARD, 2.4)
	_flood(Vector3(-16.0, 5.0, -20.0), Vector3.FORWARD, 2.2)
	_rod("VaultLampArm", Vector3(1.0, 3.75, -31.0), Vector3(1.0, 3.75, -31.6), 0.025, _mat("lamp_cage", Color("2f3030"), 0.4, 0.6))
	_lamp(_rooms_by_name["Plaza"], Vector3(1.0, 3.55, -31.6), 1.3, 5.0, 0.0)

## Painted hazard chevrons on one face of a low barrier.
func _hazard_face(centre: Vector3, along: Vector3, length: float) -> void:
	var dark: StandardMaterial3D = _mat("chevron_dark", Color("2a2b2a"))
	var paint: StandardMaterial3D = _mat("chevron_ochre", OCHRE)
	var thin: Vector3 = Vector3(0.01, 0.0, 0.0) if along.z > 0.5 else Vector3(0, 0, 0.01)
	_piece("BarrierBand", along * length + Vector3(0, 0.36, 0) + thin, dark, centre)
	var count: int = int(length / 0.5)
	for index: int in range(count):
		var stripe: MeshInstance3D = _piece("BarrierStripe", along * 0.16 + Vector3(0, 0.42, 0) + thin * 1.2, paint, centre + along * (-length * 0.5 + 0.25 + float(index) * 0.5))
		if along.z > 0.5:
			stripe.rotation.x = PI * 0.25
		else:
			stripe.rotation.z = PI * 0.25
		stripe.scale = Vector3(1, 0.8, 1)

# --- side street, the window and the chalk alley ------------------------------------

func _build_side_street() -> void:
	# Beside the lit window: her chair at the door, a planter and a bicycle
	# wheel hung on a hook, things a neighbour keeps.
	_greens(Vector3(-41.75, 0.45, -22.4), Vector2(0.5, 1.4))
	_piece("PlanterBox", Vector3(0.5, 0.45, 1.4), _mat("window_box", Color("6b5440"), 0.0, 0.9), Vector3(-41.75, 0.225, -22.4))
	_piece("PlanterBox", Vector3(0.5, 0.45, 1.4), _mat("window_box", Color("6b5440"), 0.0, 0.9), Vector3(-41.75, 0.225, -16.9))
	_greens(Vector3(-41.75, 0.45, -16.9), Vector2(0.5, 1.4))
	var wheel: Vector3 = Vector3(-41.95, 1.9, -25.2)
	_shape.cylinder(_at(wheel), "HungWheel", 0.34, 0.04, _mat("tyre", Color("2a2a28"), 0.0, 0.9), wheel, 14).rotation.y = PI * 0.5
	_shape.cylinder(_at(wheel), "HungWheelHub", 0.06, 0.08, _mat("handle", Color("8e8775"), 0.5, 0.5), wheel, 8).rotation.y = PI * 0.5
	# A child's game chalked on the dead-end alley floor and a ball left by it.
	var chalk: StandardMaterial3D = _mat("chalk", CHALK, 0.0, 1.0)
	var hop: Array = [[-44.0, -10.0], [-45.0, -10.0], [-46.0, -10.6], [-46.0, -9.4], [-47.0, -10.0], [-48.0, -10.6], [-48.0, -9.4], [-49.0, -10.0]]
	for cell: Array in hop:
		var centre: Vector3 = Vector3(float(cell[0]), 0.006, float(cell[1]))
		for edge: Array in [[Vector3(0, 0, -0.48), Vector3(0.96, 0.004, 0.04)], [Vector3(0, 0, 0.48), Vector3(0.96, 0.004, 0.04)],
			[Vector3(-0.48, 0, 0), Vector3(0.04, 0.004, 0.96)], [Vector3(0.48, 0, 0), Vector3(0.04, 0.004, 0.96)]]:
			_piece("ChalkGame", edge[1], chalk, centre + edge[0])
	_shape.cylinder(_at(Vector3(-43.2, 0.13, -8.6)), "Ball", 0.13, 0.26, _mat("ball", Color("b5652e")), Vector3(-43.2, 0.13, -8.6), 10)
	# Chalk on the alley wall: a sun and a row of figures holding hands.
	var wall_x: float = -49.985
	for ray: int in range(8):
		var angle: float = TAU * float(ray) / 8.0
		var ray_node: MeshInstance3D = _piece("ChalkSun", Vector3(0.008, 0.04, 0.16), chalk, Vector3(wall_x, 0.8 + sin(angle) * 0.24, -11.62 + cos(angle) * 0.24))
		ray_node.rotation.x = -angle
	_piece("ChalkSunDisc", Vector3(0.008, 0.16, 0.16), chalk, Vector3(wall_x, 0.8, -11.62))
	for figure: int in range(4):
		var z: float = -9.9 + float(figure) * 0.42
		var tall: float = 0.5 if figure % 2 == 0 else 0.38
		_piece("ChalkFigure", Vector3(0.008, tall, 0.04), chalk, Vector3(wall_x, 0.55 + tall * 0.5, z))
		_piece("ChalkHead", Vector3(0.008, 0.12, 0.12), chalk, Vector3(wall_x, 0.62 + tall, z))
		_piece("ChalkArms", Vector3(0.008, 0.04, 0.42), chalk, Vector3(wall_x, 0.55 + tall * 0.75, z + 0.21))
	# Side street floods, one over the window end, one by the square.
	_flood(Vector3(-36.0, 6.2, -8.0), Vector3.FORWARD, 2.0, 12.0)
	_flood(Vector3(-42.0, 6.0, -25.0), Vector3.RIGHT, 1.8, 12.0)

# --- the square and the curfew post -----------------------------------------------

func _build_square() -> void:
	var props_at: Vector3 = Vector3(-10, 0, -12)
	# Dry stalks in the square's planters: nobody may tend them after hours.
	for planter: Vector3 in [Vector3(-24.5, 1.0, -11.25), Vector3(-14.5, 1.0, -14.25)]:
		_piece("PlanterSoil", Vector3(2.8, 0.04, 1.3), _mat("soil", Color("3e3428"), 0.0, 1.0), planter + Vector3(0, 0.02, 0))
		for stalk: int in range(6):
			_rod("DryStalk", planter + Vector3(-1.1 + float(stalk) * 0.44, 0.02, -0.3 + float(stalk % 3) * 0.3),
				planter + Vector3(-1.0 + float(stalk) * 0.44, 0.55 + float(stalk % 2) * 0.2, -0.25 + float(stalk % 3) * 0.3), 0.015, _mat("stalk", Color("7a6a48")))
	# The post's face to the square: two tall black banners with the seal,
	# and cold floods at its corners lighting the gate.
	_banner(_at(props_at), Vector3(-12.6, 4.9, -8.0))
	_banner(_at(props_at), Vector3(0.6, 4.9, -8.0))
	_flood(Vector3(-14.0, 6.6, -8.0), Vector3(-0.45, 0, -0.9).normalized(), 2.8, 14.0, 40.0)
	_flood(Vector3(2.0, 6.6, -8.0), Vector3(0.45, 0, -0.9).normalized(), 2.8, 14.0, 40.0)
	_flood(Vector3(14.0, 5.8, -10.0), Vector3.LEFT, 2.0, 12.0)
	# Painted stand-here marks before the post gate: the queue the town keeps.
	var paint: StandardMaterial3D = _mat("lane_paint", Color("a08a52"), 0.0, 0.95)
	for index: int in range(4):
		var z: float = -10.4 - float(index) * 1.3
		_piece("QueueMark", Vector3(0.9, 0.006, 0.12), paint, Vector3(-6.0, 0.004, z))
	_paint_line(_at(Vector3(-8.4, 0, -12)), Vector3(-8.4, 0, -9.0), Vector3(-8.4, 0, -15.0), 0.1, paint)
	_paint_line(_at(Vector3(-3.6, 0, -12)), Vector3(-3.6, 0, -9.0), Vector3(-3.6, 0, -15.0), 0.1, paint)

func _build_post() -> void:
	var room: Node3D = _rooms_by_name["Post"]
	var props: Node3D = _props(room)
	var steel: StandardMaterial3D = _mat("issued_steel", Color("3a3e40"), 0.4, 0.6)
	# The register: the wall of household cards inside the post, each with a
	# small square portrait and a red stamp. This is what the town is.
	_block(props, "RegisterBoard", Vector3(0.04, 1.5, 5.2), _mat("register_board", Color("4a4d4c"), 0.2, 0.7), Vector3(-13.47, 1.75, -4.0))
	var card: StandardMaterial3D = _mat("register_card", Color("b8b09a"), 0.0, 0.95)
	var face: StandardMaterial3D = _mat("register_face", Color("5c5448"), 0.0, 0.95)
	var stamp: StandardMaterial3D = _mat("registration_seal", SEAL_RED)
	for row: int in range(4):
		for column: int in range(11):
			if (row * 11 + column) % 13 == 7:
				continue
			var at: Vector3 = Vector3(-13.44, 1.2 + float(row) * 0.34, -6.3 + float(column) * 0.44)
			_block(props, "RegisterCard", Vector3(0.01, 0.26, 0.34), card, at)
			_block(props, "RegisterFace", Vector3(0.012, 0.12, 0.1), face, at + Vector3(0, 0.03, -0.09))
			_block(props, "RegisterStamp", Vector3(0.012, 0.07, 0.07), stamp, at + Vector3(0, -0.06, 0.09))
	# Filing cabinets against the inner wall, one drawer pulled.
	for index: int in range(3):
		var z: float = -6.9 + float(index) * 0.62
		_block(props, "FilingCabinet", Vector3(0.6, 1.3, 0.55), steel, Vector3(-13.15, 0.65, z))
		for drawer: int in range(3):
			_block(props, "CabinetPull", Vector3(0.02, 0.04, 0.18), _mat("handle", Color("8e8775"), 0.5, 0.5), Vector3(-12.84, 0.3 + float(drawer) * 0.4, z))
	_block(props, "OpenDrawer", Vector3(0.45, 0.32, 0.5), steel, Vector3(-12.6, 0.9, -5.66))
	# A wall desk under a cold pool, stamps and a stack of forms.
	_block(props, "WallDesk", Vector3(0.7, 0.06, 2.4), _mat("desk_top", Color("4e5844"), 0.1, 0.7), Vector3(-13.15, 0.95, -1.9))
	_block(props, "DeskBracket", Vector3(0.5, 0.3, 0.06), steel, Vector3(-13.25, 0.8, -2.9))
	_block(props, "DeskBracket", Vector3(0.5, 0.3, 0.06), steel, Vector3(-13.25, 0.8, -0.9))
	for index: int in range(3):
		_block(props, "FormStack", Vector3(0.3, 0.05 + float(index) * 0.03, 0.22), _mat("forms", Color("cfc6ad"), 0.0, 0.95), Vector3(-13.1, 1.0 + float(index) * 0.015, -2.6 + float(index) * 0.4))
	_block(props, "Stamp", Vector3(0.08, 0.12, 0.08), steel, Vector3(-13.0, 1.04, -1.2))
	_pool(room, Vector3(-11.0, 3.0, -4.0), 2.0, 5.0, 44.0, 3.2)
	_pool(room, Vector3(-3.0, 3.0, -4.0), 2.0, 5.0, 44.0, 3.2)
	# Upstairs: the guards' corner, a cot and a flask by the window.
	_block(props, "Cot", Vector3(0.8, 0.4, 2.0), _mat("cot", Color("4b5047"), 0.1, 0.8), Vector3(-13.0, 3.7, -5.6))
	_block(props, "CotBlanket", Vector3(0.82, 0.06, 1.3), _mat("blanket", Color("3e4038"), 0.0, 0.95), Vector3(-13.0, 3.93, -5.3))
	_block(props, "Flask", Vector3(0.1, 0.3, 0.1), steel, Vector3(-7.75, 4.15, -0.75))
	_block(props, "Cup", Vector3(0.08, 0.1, 0.08), _mat("cup", Color("8b8f8c")), Vector3(-7.55, 4.05, -0.7))
	_pool(room, Vector3(-9.5, 6.8, -4.5), 1.6, 5.0, 44.0, 7.0)
	# More confiscated long arms leaned at the rack's ends, each tagged, and
	# a crate of seized tools against the wall: the Sniper is one of many.
	var stock: StandardMaterial3D = _mat("rifle_stock", Color("5a4532"), 0.1, 0.8)
	var barrel: StandardMaterial3D = _mat("rifle_barrel", Color("2f3132"), 0.5, 0.5)
	for row: Array in [[1.08, -1.1], [1.08, -0.75], [-2.08, -1.1], [-2.08, -0.75]]:
		var x: float = float(row[0])
		var z: float = float(row[1])
		var lean: float = 0.12 if x > 0.0 else -0.12
		_shape.rod(props, "SeizedRifleStock", Vector3(x + lean, 0.05, z), Vector3(x + lean * 0.55, 0.75, z), 0.045, stock, 6)
		_shape.rod(props, "SeizedRifleBarrel", Vector3(x + lean * 0.55, 0.75, z), Vector3(x, 1.75, z), 0.02, barrel, 6)
		_red_tag(props, Vector3(x + lean * 0.4, 0.95, z - 0.06), "north")
	_crate(props, Vector3(-2.75, 0.0, -0.8), Vector3(0.6, 0.42, 0.5), Color("6a5a40"))
	for index: int in range(3):
		_block(props, "SeizedTool", Vector3(0.08, 0.3, 0.06), _mat("seized_tool_%d" % index, HOMES[index * 2], 0.3, 0.6), Vector3(-2.95 + float(index) * 0.18, 0.55, -0.8))
	_red_tag(props, Vector3(-2.75, 0.3, -1.06), "north")

# --- the crater cut -------------------------------------------------------------

func _build_cut() -> void:
	# Hazard paint and footing on the face of every radiation shield toward
	# the town, dust drifted against them, cables across the floor.
	var shields: Array = [[Vector3(-2, 4, 12), Vector3(14, 7.8, 13.5)], [Vector3(-24, 4, 24), Vector3(-7.5, 7.8, 25.5)],
		[Vector3(24, 4, 26), Vector3(30, 7.3, 27.5)], [Vector3(-8, 4, 36), Vector3(8, 7.8, 37.5)], [Vector3(-26, 4, 46), Vector3(-10, 7.8, 47.5)]]
	var foot: StandardMaterial3D = _mat("shield_foot", Color("4a4d4a"), 0.4, 0.6)
	for pair: Array in shields:
		var low: Vector3 = pair[0]
		var high: Vector3 = pair[1]
		var length: float = high.x - low.x
		var centre_x: float = (low.x + high.x) * 0.5
		var face_z: float = low.z - 0.006
		_chevrons(_at(Vector3(centre_x, 4, face_z)), Vector3(centre_x, 4.0, face_z - 0.4), true, length, 0.3)
		_piece("ShieldFoot", Vector3(length, 0.3, 0.12), foot, Vector3(centre_x, 4.15, face_z - 0.06))
		var post: float = low.x + 0.4
		while post < high.x - 0.2:
			_piece("ShieldRib", Vector3(0.14, high.y - 4.0, 0.08), foot, Vector3(post, (4.0 + high.y) * 0.5, face_z - 0.04))
			post += 2.6
		_dust(_at(Vector3(centre_x, 4, face_z)), Vector3(centre_x, 4.0, face_z - 0.7), Vector2(length * 0.8, 0.9), 9, int(centre_x))
	# Power cable from the rim down the cut, flat on the regolith.
	var cable: StandardMaterial3D = _mat("cable", Color("232425"), 0.2, 0.7)
	var cable_path: Array[Vector3] = [Vector3(-35.5, 4.02, 4.0), Vector3(-35.5, 4.02, 20.0), Vector3(-33.0, 4.02, 30.0), Vector3(-35.5, 4.02, 44.0), Vector3(-35.5, 4.02, 57.8)]
	for index: int in range(cable_path.size() - 1):
		_rod("FloorCable", cable_path[index], cable_path[index + 1], 0.05, cable, 5)
	# Rocks and dust at the foot of the crater walls, against the walls only.
	var basalt: ShaderMaterial = town_surface("crater")
	for row: Array in [[Vector3(-35.7, 4.35, 15.0), Vector3(0.6, 0.7, 2.4)], [Vector3(-35.7, 4.3, 33.0), Vector3(0.6, 0.6, 1.8)],
		[Vector3(43.7, 4.35, 18.0), Vector3(0.6, 0.7, 2.6)], [Vector3(43.7, 4.35, 38.0), Vector3(0.6, 0.7, 2.0)], [Vector3(-35.7, 4.4, 52.0), Vector3(0.6, 0.8, 2.0)]]:
		_piece("WallTalus", row[1], basalt, row[0])
	for spot: Vector3 in [Vector3(-30, 4, 4), Vector3(0, 4, 20), Vector3(20, 4, 33), Vector3(-15, 4, 42), Vector3(30, 4, 52), Vector3(10, 4, 54)]:
		_dust(_at(spot), spot, Vector2(5.0, 3.0), 7, int(spot.z))
	# Tracks of the shield haulers up the cut.
	var track: StandardMaterial3D = _mat("tow_track", Color("6e6a60"), 0.0, 1.0)
	for x: float in [18.6, 20.4]:
		_paint_line(_at(Vector3(x, 4, 30)), Vector3(x, 4.0, 2.0), Vector3(x, 4.0, 22.0), 0.45, track)
		_paint_line(_at(Vector3(x, 4, 30)), Vector3(x + 15.0, 4.0, 39.0), Vector3(x + 18.0, 4.0, 47.0), 0.45, track)

# --- the rim: the marksmen's lit stages ---------------------------------------------

func _build_rim() -> void:
	var room: Node3D = _rooms_by_name["Rim"]
	var props: Node3D = _props(room)
	var deck: StandardMaterial3D = _mat("platform_deck", Color("5d6261"), 0.4, 0.6)
	var rail: StandardMaterial3D = _mat("platform_rail", Color("3e4142"), 0.4, 0.6)
	var screen: StandardMaterial3D = _mat("blast_screen", Color("7b786f"), 0.1, 0.85)
	var edge: StandardMaterial3D = _mat("chevron_ochre", OCHRE)
	for stage: Vector2 in RIM_STAGES:
		var x: float = stage.x
		var rim_z: float = stage.y
		# A deck plate flush on the rim, a rail behind it, and a pale blast
		# screen behind that so the black body and its glint stand out.
		_block(props, "PlatformDeck", Vector3(2.6, 0.02, 2.4), deck, Vector3(x, RIM_TOP + 0.01, rim_z + 0.4))
		_block(props, "PlatformEdge", Vector3(2.6, 0.022, 0.12), edge, Vector3(x, RIM_TOP + 0.012, rim_z - 0.75))
		for side: float in [-1.2, 0.0, 1.2]:
			_shape.rod(props, "PlatformPost", Vector3(x + side, RIM_TOP, rim_z + 1.6), Vector3(x + side, RIM_TOP + 1.05, rim_z + 1.6), 0.03, rail, 5)
		_shape.rod(props, "PlatformRail", Vector3(x - 1.25, RIM_TOP + 1.05, rim_z + 1.6), Vector3(x + 1.25, RIM_TOP + 1.05, rim_z + 1.6), 0.03, rail, 5)
		_block(props, "BlastScreen", Vector3(3.2, 3.4, 0.1), screen, Vector3(x, RIM_TOP + 1.7, rim_z + 3.2))
		_block(props, "BlastScreenEdge", Vector3(3.3, 0.14, 0.12), edge, Vector3(x, RIM_TOP + 3.43, rim_z + 3.2))
		_block(props, "BlastScreenFoot", Vector3(3.3, 0.3, 0.4), rail, Vector3(x, RIM_TOP + 0.15, rim_z + 3.2))
		_shape.rod(props, "StageMast", Vector3(x + 1.5, RIM_TOP, rim_z + 3.0), Vector3(x + 1.5, RIM_TOP + 4.6, rim_z + 3.0), 0.05, rail, 6)
		_shape.rod(props, "StageArm", Vector3(x + 1.5, RIM_TOP + 4.6, rim_z + 3.0), Vector3(x + 0.6, RIM_TOP + 4.6, rim_z + 1.6), 0.04, rail, 6)
		_block(props, "StageHood", Vector3(0.6, 0.3, 0.6), _mat("fixture_hood", Color("2c2d32"), 0.5, 0.5), Vector3(x + 0.6, RIM_TOP + 4.5, rim_z + 1.6))
		_block(props, "StageLens", Vector3(0.48, 0.02, 0.48), _glow("flood_lens", Color("e6eeee"), 2.4), Vector3(x + 0.6, RIM_TOP + 4.34, rim_z + 1.6))
		var light: SpotLight3D = SpotLight3D.new()
		light.name = "StageLight%d" % lamps
		light.position = Vector3(x + 0.6, RIM_TOP + 4.3, rim_z + 1.6)
		light.look_at_from_position(light.position, Vector3(x, RIM_TOP + 0.5, rim_z - 0.6), Vector3.UP)
		light.light_color = FLOOD
		light.light_energy = 2.4
		light.light_specular = 0.1
		light.spot_range = 7.0
		light.spot_angle = 36.0
		light.spot_angle_attenuation = 0.7
		light.shadow_enabled = false
		room.add_child(light)
		lamps += 1
	# Cable trays along the rim between the stages.
	_block(props, "RimCableTray", Vector3(78.0, 0.1, 0.3), rail, Vector3(4.0, RIM_TOP + 0.05, 64.6))
	_dust(props, Vector3(-20, RIM_TOP, 63.5), Vector2(20.0, 2.5), 10, 17)
	_dust(props, Vector3(20, RIM_TOP, 63.5), Vector2(20.0, 2.5), 10, 23)

# --- the depot's freight approach ---------------------------------------------------

func _build_depot() -> void:
	var room: Node3D = _rooms_by_name["Depot"]
	var props: Node3D = _props(room)
	var frame: StandardMaterial3D = _mat("issued_steel", Color("3a3e40"), 0.4, 0.6)
	# The freight intake door in the depot's east wall, shut, with its chevrons.
	var door_x: float = 69.985
	_block(props, "IntakeDoor", Vector3(0.03, 4.6, 7.0), _mat("intake_door", Color("4a4f52"), 0.4, 0.6), Vector3(door_x, 11.3, 60.0))
	for index: int in range(6):
		_block(props, "IntakeSlat", Vector3(0.035, 0.06, 6.9), _mat("intake_slat", Color("33373a"), 0.4, 0.6), Vector3(door_x - 0.005, 9.6 + float(index) * 0.75, 60.0))
	_block(props, "IntakeHeader", Vector3(0.2, 0.6, 7.8), frame, Vector3(door_x - 0.1, 13.9, 60.0))
	for z: float in [56.3, 63.7]:
		_block(props, "IntakeJamb", Vector3(0.2, 4.9, 0.4), frame, Vector3(door_x - 0.1, 11.45, z))
	for index: int in range(10):
		var stripe: MeshInstance3D = _block(props, "IntakeHazard", Vector3(0.012, 0.5, 0.18), _mat("chevron_ochre", OCHRE), Vector3(door_x - 0.21, 13.9, 56.9 + float(index) * 0.7))
		stripe.rotation.x = PI * 0.22
	# Two seals either side of the intake, on the wall the party walks to.
	for z: float in [52.5, 67.5]:
		_banner_turned(props, Vector3(door_x - 0.01, 12.4, z))
	_chevrons(props, Vector3(67.5, RIM_TOP, 60.0), false, 7.0, 0.35)
	_flood(Vector3(70.0, 14.6, 60.0), Vector3.LEFT, 2.6, 13.0)
	_flood(Vector3(70.0, 14.2, 50.5), Vector3.LEFT, 2.0, 12.0)
	_dust(props, Vector3(52.0, RIM_TOP, 60.0), Vector2(8.0, 10.0), 10, 31)

## The port's banner turned to hang on a wall that faces -x.
func _banner_turned(props: Node3D, at: Vector3) -> void:
	var holder: Node3D = Node3D.new()
	_banner(holder, Vector3.ZERO)
	var turn: Transform3D = Transform3D(Basis(Vector3.UP, PI * 0.5), at)
	for child: Node in holder.get_children():
		var piece: Node3D = child
		holder.remove_child(piece)
		piece.transform = turn * piece.transform
		props.add_child(piece)
	holder.free()


# --- outside the walls: the crater's rim ---------------------------------------------

func _build_crater() -> void:
	# The crater wall rises beyond the cut on both sides and ahead, a nearer
	# shoulder of dusty basalt in front of a darker, higher rim, so the town
	# reads as sitting in a crater rather than under an empty black sky. The
	# port side drops lower, under Earth.
	var far: StandardMaterial3D = _mat("ridge_far", Color("27292a"), 0.0, 1.0)
	var near: StandardMaterial3D = _mat("ridge_near", Color("3c3d39"), 0.0, 1.0)
	_ridge("CraterRimWest", Vector3(-104, 0, -60), Vector3.BACK, 190.0, 30.0, 26.0, 26.0, far, 3)
	_ridge("CraterShoulderWest", Vector3(-82, 0, -40), Vector3.BACK, 140.0, 14.0, 15.0, 12.0, near, 7)
	_ridge("CraterRimEast", Vector3(104, 0, -60), Vector3.BACK, 190.0, 30.0, 26.0, 28.0, far, 11)
	_ridge("CraterShoulderEast", Vector3(84, 0, -40), Vector3.BACK, 130.0, 14.0, 15.0, 12.0, near, 13)
	_ridge("CraterRimNorth", Vector3(-130, 0, 108), Vector3.RIGHT, 260.0, 30.0, 30.0, 30.0, far, 17)
	_ridge("CraterShoulderNorth", Vector3(-110, 0, 86), Vector3.RIGHT, 220.0, 12.0, 14.0, 10.0, near, 19)
	_ridge("CraterRimSouth", Vector3(-160, 0, -170), Vector3.RIGHT, 320.0, 30.0, 10.0, 14.0, far, 23)

## A jagged ridge: a side outline of peaks along `along`, extruded `depth`
## across it, standing on the lunar ground outside the playable square.
func _ridge(label: String, start: Vector3, along: Vector3, length: float, depth: float, base: float, rise: float, finish: StandardMaterial3D, seed_value: int) -> void:
	var outline: PackedVector2Array = [Vector2(0, -0.5)]
	var steps: int = maxi(4, int(length / 9.0))
	for index: int in range(steps + 1):
		var t: float = float(index) / float(steps)
		var noise: float = fposmod(sin(float(index * 12 + seed_value) * 12.9898) * 43758.5453, 1.0)
		var swell: float = sin(t * PI) * 0.6 + 0.4
		outline.append(Vector2(t * length, base * swell + rise * noise * swell))
	outline.append(Vector2(length, -0.5))
	outline.reverse()
	var node: MeshInstance3D = _shape.prism(_props(_rooms_by_name["Crater"]), label, outline, depth, finish, start)
	node.rotation.y = atan2(along.x, along.z)
