extends SceneTree

## Larak Lot's surfaces at one texel density, and nothing drawn that looks
## like cover the server does not have. Built from the server's own MapInfo
## (client/golden/larak_lot_map_info.json, held to the server by
## `larak_client_golden_is_the_server_map_info`).
##
## Texel density: every surface class reads its 64 px tile one texel to one
## world texel on the 16 per metre grid; every textured part the presenter
## paints is world-triplanar at 16 per metre; every decal cell and light pool
## is laid at its own pixel size over 16.
##
## Visible mesh has solid: every body the presenter draws (each batched box,
## part, pad kit and prepared prop) lies inside a server solid, lies flat
## (no more than a shin's height over its floor), hangs overhead, hugs a wall,
## stands outside the lot, or is a thin rail, cable or arm a body passes.

const GOLDEN: String = "res://golden/larak_lot_map_info.json"
const TEXELS: float = 16.0
## A body this low over its floor is a kerb lip, a pad or a plinth, not cover.
const SHIN: float = 0.25
## A body whose underside is this high over its floor hangs over any head.
const OVERHEAD: float = 2.0
## A body this close to a solid's face, and no deeper, is mounted on it.
const WALL_HUG: float = 0.3
## Thinner than this across, it is a rail, cable, barrier arm or pole:
## nothing a fighter could hide behind.
const THIN: float = 0.13
## A prop's bounds may overhang its solid by this much (a tilted wreck, a
## booth's kerb lip): the shot still stops where the body is.
const OVERHANG: float = 0.15
## Over this height nothing is in reach: the Roof plus a rocket jump and a
## body's height.
const OUT_OF_REACH: float = 11.0
## The floors a fighter walks on. A body resting on any other top (the
## bookmaker's roof) stands where nobody goes.
const LEVELS: Array[float] = [0.0, 0.5, 1.5, 3.0, 4.5, 6.0]
## The server's pads the kit stages: id, kind, floor position.
const PADS: Array = [
	["larak_rail", "weapon", Vector3(-20.0, 0.5, 6.0)],
	["larak_custody_plate", "plate", Vector3(31.0, 6.0, -22.0)],
	["larak_rocket_pit", "weapon", Vector3(7.5, 0.0, 2.0)],
	["larak_scatter_booths", "weapon", Vector3(-21.0, 3.0, -15.0)],
	["larak_flechette_pit", "weapon", Vector3(-4.0, 0.0, 4.0)],
	["larak_health_toll", "health", Vector3(-33.0, 3.0, -7.0)],
	["larak_armor_bridge", "armor", Vector3(0.0, 3.0, -6.5)],
]

var _failures: int = 0
var _solids: Array = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_larak_surfaces: " + message)

func _run() -> void:
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	_check(info is Dictionary and MapGeometry.validation_error(info).is_empty(), "the golden is a valid MapInfo")
	if not info is Dictionary:
		quit(1)
		return
	_solids = info["solids"]
	var arena: Node3D = Node3D.new()
	root.add_child(arena)
	var cover: ArenaCover = ArenaCover.new()
	arena.add_child(cover)
	cover.apply_map_info(info)
	await process_frame
	var lot: LarakLot = cover.get_node_or_null("LarakLot") as LarakLot
	_check(lot != null, "the presenter is built for map 1")
	if lot == null:
		quit(1)
		return
	_check(lot.is_in_group(LarakLot.PICKUP_STAGE), "the presenter stages the pads")
	for pad: Array in PADS:
		var seat: float = lot.stage_pickup(str(pad[0]), str(pad[1]), "", pad[2])
		var again: float = lot.stage_pickup(str(pad[0]), str(pad[1]), "", pad[2])
		_check(seat == again and seat >= 0.0 and seat < SHIN, "pad %s seats at a step's height (%f)" % [pad[0], seat])
	_check(is_equal_approx(lot.stage_pickup("larak_rail", "weapon", "", Vector3.ZERO), LarakLot.RAIL_DAIS)
		and is_equal_approx(lot.stage_pickup("larak_custody_plate", "plate", "", Vector3.ZERO), LarakLot.PLATE_PEDESTAL)
		and is_equal_approx(lot.stage_pickup("larak_rocket_pit", "weapon", "", Vector3.ZERO), LarakLot.ROCKET_CRADLE),
		"the Rail's dais, the Plate's pedestal and the Rocket's cradle are their seats")
	_check(lot.find_children("Pad_*", "Node3D", false, false).size() == PADS.size(), "one kit per pad, built once")
	await process_frame
	_texel_density(cover, lot)
	var reading_keys: Array[String] = []
	for node: Node in lot.find_children("*", "WorldSign", true, false):
		var sign: WorldSign = node as WorldSign
		if sign.message_key not in LarakLot.CANON_MARKS:
			reading_keys.append(sign.message_key)
	_check(reading_keys.size() <= 5, "at most five short signs plus the LARAK neon: " + str(reading_keys))
	_check(reading_keys.count("WORLD_LARAK_REPOSSESSED") == 1, "the overturned van keeps its repossession mark")
	for key: String in LarakLot.READING_STOPS:
		_check(reading_keys.count(key) == 1, "one placement for " + key)
	_pools_stay_warm(lot)
	_visible_bodies_have_solids(lot)
	_check(lot.find_children("*", "Light3D", true, false).size() == 4, "the pad kit spends no light budget")
	arena.queue_free()
	await process_frame
	if _failures == 0:
		print("test_larak_surfaces: PASS surface classes, parts, decals and pools at 16 texels per metre; every visible body has a solid or lies flat, overhead or on a wall")
	quit(0 if _failures == 0 else 1)

func _texel_density(cover: ArenaCover, lot: LarakLot) -> void:
	for id: String in ArenaMaterials.LARAK_CLASSES:
		var material: ShaderMaterial = ArenaMaterials.larak_class(id)
		_check(material != null, "class %s has its tiles" % id)
		if material == null:
			continue
		var top: Texture2D = material.get_shader_parameter("tile_floor")
		var side: Texture2D = material.get_shader_parameter("tile_wall")
		_check(material.get_shader_parameter("tile_albedo") == true and material.get_shader_parameter("markings_enabled") == false,
			"class %s is tile albedo with no procedural marks" % id)
		_check(top.get_width() == top.get_height() and top.get_size() == side.get_size()
			and is_equal_approx(float(material.get_shader_parameter("tile_repeat_pixels")), float(top.get_width())),
			"class %s reads its tile one texel per world texel" % id)
		var image: Image = top.get_image()
		_check(image != null and not image.has_mipmaps(), "class %s tile has no mipmaps" % id)
		if id != "stairwell":
			_check(top.get_width() == 64, "class %s is a 64 px tile, a 4 m repeat" % id)
	var drawn: int = 0
	for index: int in range(_solids.size()):
		var view: MeshInstance3D = cover.get_node_or_null("Solid_%d" % index) as MeshInstance3D
		if view == null or not view.visible:
			continue
		drawn += 1
		var material: ShaderMaterial = view.material_override as ShaderMaterial
		_check(material != null and material.get_shader_parameter("tile_albedo") == true, "solid %d is drawn by a surface class" % index)
	_check(drawn > 60, "most of the lot's solids are drawn (%d)" % drawn)
	var ground: MeshInstance3D = cover.get_node_or_null("MapFloor") as MeshInstance3D
	_check(ground != null and ground.material_override == ArenaMaterials.larak_class("pit"), "the Pit floor is its own class")
	for name: String in ["kerb", "shear", "slab"]:
		var used: bool = false
		for index: int in range(_solids.size()):
			var view: MeshInstance3D = cover.get_node_or_null("Solid_%d" % index) as MeshInstance3D
			used = used or (view != null and view.material_override == ArenaMaterials.larak_class(name))
		_check(used, "class %s is on the lot" % name)
	var props: Array[Node] = lot.get_tree().get_nodes_in_group(&"larak_prop")
	for node: Node in lot.find_children("*", "GeometryInstance3D", true, false):
		if props.any(func(prop: Node) -> bool: return prop.is_ancestor_of(node)):
			continue
		var shape: GeometryInstance3D = node as GeometryInstance3D
		var material: Material = shape.material_override
		if material is StandardMaterial3D and (material as StandardMaterial3D).albedo_texture != null:
			var paint: StandardMaterial3D = material
			var width: float = float(paint.albedo_texture.get_width())
			if paint.uv1_world_triplanar:
				_check(is_equal_approx(width * paint.uv1_scale.x, TEXELS), "%s paints at 16 texels per metre (%.1f)" % [shape.name, width * paint.uv1_scale.x])
			elif shape is MeshInstance3D and (shape as MeshInstance3D).mesh is PlaneMesh:
				var plane: PlaneMesh = (shape as MeshInstance3D).mesh
				_check(is_equal_approx(plane.size.x * TEXELS * shape.scale.x, width), "%s lays its %d px at 16 per metre" % [shape.name, int(width)])
			elif shape is MeshInstance3D and paint.albedo_texture.resource_path == LarakLot.DECAL_ATLAS:
				_atlas_density(shape as MeshInstance3D)
			else:
				_check(false, "%s has a texture with no texel density" % shape.name)

## Each decal triangle: atlas texels over world metres is 16 along every edge.
func _atlas_density(shape: MeshInstance3D) -> void:
	var arrays: Array = shape.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var atlas: Vector2 = Vector2(LarakLot.DECAL_ATLAS_SIZE)
	var worst: float = 0.0
	for index: int in range(0, points.size(), 3):
		for edge: int in range(3):
			var a: int = index + edge
			var b: int = index + (edge + 1) % 3
			var metres: float = (points[b] - points[a]).length()
			var texels: float = ((uvs[b] - uvs[a]) * atlas).length()
			if metres > 0.001:
				worst = maxf(worst, absf(texels / metres - TEXELS))
	_check(points.size() >= 3 and worst < 0.01, "%s lays every atlas cell at 16 texels per metre (off by %f)" % [shape.name, worst])

## The pad light pools are warm: never Union red, never Inheritance cyan.
func _pools_stay_warm(lot: LarakLot) -> void:
	var pools: int = 0
	for node: Node in lot.find_children("Pool", "MeshInstance3D", true, false):
		var paint: StandardMaterial3D = (node as MeshInstance3D).material_override as StandardMaterial3D
		var hue: float = paint.albedo_color.h * 360.0
		_check(hue > 22.0 and hue < 60.0, "a pad pool burns warm amber (%.0f degrees)" % hue)
		pools += 1
	_check(pools == PADS.size(), "every pad has its light pool")

## The highest solid top at or under `height` covering (x, z), or zero.
func _floor_under(x: float, z: float, height: float) -> float:
	var best: float = 0.0
	for s: Dictionary in _solids:
		var top: float = float(s.get("top", MoveStep.WALL_TOP))
		if top <= height + 0.001 and top > best and x >= float(s["min_x"]) and x <= float(s["max_x"]) \
			and z >= float(s["min_z"]) and z <= float(s["max_z"]):
			best = top
	return best

func _solid_box(s: Dictionary, grow: float) -> AABB:
	var bottom: float = float(s.get("bottom", 0.0))
	var top: float = float(s.get("top", MoveStep.WALL_TOP))
	return AABB(Vector3(float(s["min_x"]) - grow, bottom - OVERHANG, float(s["min_z"]) - grow),
		Vector3(float(s["max_x"]) - float(s["min_x"]) + grow * 2.0, top - bottom + OVERHANG * 2.0, float(s["max_z"]) - float(s["min_z"]) + grow * 2.0))

func _visible_bodies_have_solids(lot: LarakLot) -> void:
	var bodies: Array[Dictionary] = lot.visible_bodies()
	_check(bodies.size() > 200, "the presenter reports its bodies (%d)" % bodies.size())
	var loose: Array[String] = _loose(bodies)
	_check(loose.is_empty(), "%d visible bodies look like cover with no solid:\n  %s" % [loose.size(), "\n  ".join(loose)])
	# The check catches what it is for: a crate dropped in the open Pit, a
	# drum stood out from a wall, and a machine standing half a metre proud.
	var planted: Array[Dictionary] = [
		{"name": "crate", "aabb": AABB(Vector3(-5.0, 0.0, -2.0), Vector3(1.0, 1.0, 1.0))},
		{"name": "drum", "aabb": AABB(Vector3(-35.0, 1.5, 4.0), Vector3(0.6, 0.9, 0.6))},
		{"name": "machine", "aabb": AABB(Vector3(-31.0, 3.0, -28.0), Vector3(0.8, 1.6, 0.5))},
	]
	_check(_loose(planted).size() == planted.size(), "free-standing bodies with no solid are caught")

func _loose(bodies: Array[Dictionary]) -> Array[String]:
	var loose: Array[String] = []
	for body: Dictionary in bodies:
		var box: AABB = body["aabb"]
		var centre: Vector3 = box.get_center()
		var floor_y: float = _floor_under(centre.x, centre.z, box.position.y + 0.05)
		if box.end.y - floor_y <= SHIN or box.position.y - floor_y >= OVERHEAD or box.position.y >= OUT_OF_REACH:
			continue
		if box.end.x <= -35.9 or box.position.x >= 35.9 or box.end.z <= -27.9 or box.position.z >= 27.9:
			continue
		if minf(box.size.x, box.size.z) <= THIN:
			continue
		if not LEVELS.any(func(level: float) -> bool: return absf(level - floor_y) < 0.05):
			continue
		var held: bool = false
		for s: Dictionary in _solids:
			if _solid_box(s, OVERHANG).encloses(box):
				held = true
				break
			# Mounted on a face: standing proud of the solid by no more than
			# WALL_HUG anywhere, and no higher or lower than the solid.
			if _solid_box(s, WALL_HUG).encloses(box) \
				and box.position.y >= float(s.get("bottom", 0.0)) - 0.05 and box.end.y <= float(s.get("top", MoveStep.WALL_TOP)) + 0.05:
				held = true
				break
		if not held:
			loose.append("%s at %s size %s" % [body["name"], box.position.snappedf(0.01), box.size.snappedf(0.01)])
	return loose
