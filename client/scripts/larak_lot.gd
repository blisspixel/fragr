class_name LarakLot
extends Node3D

## Larak Lot's presentation: the landmarks, light plan and set dressing of the
## car park on map 1, an old black-budget range nobody will sign off, with the
## power still on, where the league settles debts. The server's solids stay the only collision;
## everything here is paint, fixtures and scenery. Some plain boxes (the
## wrecks, THE STACK, the toll booths, the bookmaker's kiosk, the hung
## cruiser) are redrawn inside their own volume, as prepared models or built
## from parts, so a shot still stops exactly where it looks like it should.
##
## Coordinates follow `server/src/maps/larak_lot.rs`. A part whose host solid
## is missing from the MapInfo is skipped rather than drawn in mid-air.

const FONT: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")
const EARTH: String = "res://assets/environment/earth/"
const PRODUCTION: String = "res://assets/environment/production/"
## Prepared venue props (tools/larak_props_20261024.json): pixel-painted
## models, each standing on its floor centre with its front toward +Z, drawn
## inside the volume a server solid already holds or flat to a wall.
const PROPS: String = "res://assets/models/larak/"
const PROP_NAMES: Array[String] = ["bookmaker_kiosk", "burned_sedan", "car_stack", "clamped_sedan",
	"coffee_machine", "crane_hook", "pay_machine", "stands_bell", "toll_booth"]
## Pay machine: depth off the wall, and the blank plate and screen on its
## face (x from its centre, y from its foot).
const PAY_DEPTH: float = 0.488
const PAY_PLATE: Vector2 = Vector2(-0.01, 0.59)
const PAY_PLATE_SIZE: Vector2 = Vector2(0.54, 0.28)
const PAY_SCREEN: Vector2 = Vector2(-0.065, 1.3)
const PAY_SCREEN_SIZE: Vector2 = Vector2(0.46, 0.26)
## Bookmaker's kiosk: the slate on each end (world z, height off the deck).
const KIOSK_SLATE: Vector2 = Vector2(17.9, 1.36)
const KIOSK_SLATE_SIZE: Vector2 = Vector2(1.1, 1.0)
## Coffee machine: depth off the cabin, its blank approval plate and the
## notice over its smoked panel (x from its centre in its own frame).
const COFFEE_DEPTH: float = 0.496
const COFFEE_PLATE: Vector2 = Vector2(0.255, 1.335)
const COFFEE_PLATE_SIZE: Vector2 = Vector2(0.19, 0.15)
const COFFEE_NOTICE: Vector2 = Vector2(-0.09, 1.12)
const COFFEE_NOTICE_SIZE: Vector2 = Vector2(0.42, 0.16)
## Wall machines (the pay machines and the coffee machine) are set this far
## into the concrete they stand against, so no more than 30 cm stands proud:
## dressing a fighter brushes past, never cover the server does not have.
const WALL_INSET: float = 0.2
## The Stands bell: top of its wall plate, and its depth off the wall
## (x) and height (y) including the pull rope, whose end hangs two metres
## over the bettors' deck.
const BELL_TOP: float = 5.6
const BELL_SIZE: Vector2 = Vector2(1.724, 2.1)
## The podium pallets stand on the bookmaker's roof.
const PODIUM_BASE: float = 4.3
## The crane hook block: its top in the hung cruiser's frame, and its work
## lamp faces (x either side, y up from the hook's tip, z).
const HOOK_TOP: float = 3.85
const HOOK_HEIGHT: float = 1.5
const HOOK_LAMPS: Array[Vector3] = [Vector3(0.49, 0.82, -0.07), Vector3(0.49, 1.0, -0.07), Vector3(0.49, 1.19, -0.07)]

## Walking levels, mirrored from the server.
const PIT: float = 0.0
const LEVEL_1: float = 1.5
const LEVEL_2: float = 3.0
const LEVEL_3: float = 4.5
const ROOF: float = 6.0
const RAIL_LANDING: float = 0.5

## Light plan (the other four are the registered strip lights).
const SODIUM: Color = Color("ffb35c")
## Sodium orange, hue about 28 degrees: outside the red band reserved for
## Union optics and attack tells.
const NEON: Color = Color("ff8c2e")
## The Repossession's light bar, re-lensed by the league in warm amber.
const LEAGUE_AMBER: Color = Color("ffae42")
const FLUORESCENT: Color = Color("e1ebe5")
const WORK_WHITE: Color = Color("f2efe4")

## Paint.
const LINE_PAINT: Color = Color("d8cf9f")
const HAZARD_YELLOW: Color = Color("c9a23a")
const HAZARD_BLACK: Color = Color("1d1b19")
## League paint stays warm and hand-mixed, and out of the Union's red band:
## ember, mustard, rust, stained canvas and cream, with a few tribe colours.
const SPRAY: Color = Color("e0782e")
const CHALK: Color = Color("e9e6da")
const UNION_BLACK: Color = Color("1e2124")
## Issued plates, one step lighter than the black body.
const UNION_STEEL: Color = Color("3a3f43")
const UNION_RED: Color = Color("8e2420")
const LEAGUE_EMBER: Color = Color("cf6f2a")
const LEAGUE_MUSTARD: Color = Color("d6a23e")
const LEAGUE_RUST: Color = Color("7c4529")
const LEAGUE_CANVAS: Color = Color("b49a68")
const LEAGUE_CREAM: Color = Color("ead7a6")
const TAG_MAGENTA: Color = Color("c0508e")
## Small lettering only.
const LEAGUE_BONE: Color = Color("ddd3bd")
## Group the presenter joins, so a match can tell it about the Plate.
const GROUP: StringName = &"larak_lot"
const PLATE_ID: String = "larak_custody_plate"
const RAIL_ID: String = "larak_rail"
const ROCKET_ID: String = "larak_rocket_pit"
## WeaponPickup.STAGE_GROUP: pickups look here for their pad's seat.
const PICKUP_STAGE: StringName = &"pickup_stage"

## The decal atlas (tools/bake_larak_decals.gd): every cell is laid at its
## own size at 16 texels per metre, so a mark shares the decks' pixel grain.
const DECAL_ATLAS: String = "res://assets/environment/larak/decals.png"
const DECAL_ATLAS_SIZE: Vector2i = Vector2i(256, 128)
const DECAL_CELLS: Dictionary[String, Rect2i] = {
	"oil_0": Rect2i(0, 0, 32, 24), "oil_1": Rect2i(32, 0, 24, 18), "oil_2": Rect2i(56, 0, 16, 12),
	"scorch_0": Rect2i(72, 0, 24, 24), "scorch_1": Rect2i(96, 0, 18, 16), "scorch_pad": Rect2i(128, 0, 56, 56),
	"skid_0": Rect2i(0, 32, 20, 4), "skid_1": Rect2i(0, 40, 20, 4), "burn_0": Rect2i(0, 48, 28, 6),
	"slip_0": Rect2i(32, 32, 3, 4), "slip_1": Rect2i(36, 32, 4, 3), "slip_2": Rect2i(41, 32, 3, 4), "ticket_0": Rect2i(45, 32, 3, 4),
	"tag_0": Rect2i(0, 64, 40, 20), "tag_1": Rect2i(40, 64, 32, 18), "tag_2": Rect2i(72, 64, 24, 24), "drips_0": Rect2i(96, 64, 32, 16),
}

## The pad kit. Every pad sits in a recessed ring with a warm light pool;
## the Rail stands on a steel dais, the Plate on the league's pedestal and the
## Rocket in a blast cradle in the Pit. Each is low enough to walk over
## (`test_larak_surfaces.gd` holds every visible body to a server solid, or to
## under a shin's height off its floor), and its top is the item's seat.
const PAD_RING_RADIUS: float = 0.78
const POOL_PIXELS: int = 36
const RAIL_DAIS: float = 0.08
const PLATE_PEDESTAL: float = 0.12
const ROCKET_CRADLE: float = 0.05
## Light pools stay warm: amber for the guns and supplies, a hotter sodium for
## the three power pads. Never red (Union tells) or cyan (the Inheritance).
const POOL_WARM: Color = Color(1.0, 0.72, 0.38)
const POOL_POWER: Color = Color(1.0, 0.8, 0.46)

var _solids: Array = []
var _views: Array[MeshInstance3D] = []
var _materials: Dictionary[String, Material] = {}
var _batches: Dictionary[String, SurfaceTool] = {}
var _atlas_tool: SurfaceTool
var _bodies: Array[Dictionary] = []
## Pad ids already staged, so a pickup recreated on the same pad reuses its kit.
var _staged_pads: Dictionary[String, float] = {}
var _batch_materials: Dictionary[String, Material] = {}
var _clock: float = 0.0
var _cruiser: Node3D
var _light_bar: OmniLight3D
var _bar_lens: MeshInstance3D
## Seconds left on the light bar's one warm flare after a Plate claim.
var _plate_flare: float = 0.0
var _toll_arm: Node3D
var _office_windows: Array[MeshInstance3D] = []
var _neon_light: OmniLight3D
var _neon_letters: Array[Label3D] = []
var _train: Node3D
## At most six reading stops including the LARAK neon and the van's mark. Small canon marks are kept
## separately; the cars, tent, crane and deck colours carry the other places.
const READING_STOPS: Array[String] = ["WORLD_LARAK_PIT",
	"WORLD_LARAK_LOW_RAMP", "WORLD_LARAK_SIGNATURE"]
const CANON_MARKS: Array[String] = ["WORLD_LARAK_SIX", "WORLD_LARAK_67", "WORLD_LARAK_ARTICLE_7"]
var _reading_stops: Dictionary[String, bool] = {}

func build(info: Dictionary, views: Array[MeshInstance3D]) -> void:
	name = "LarakLot"
	add_to_group(GROUP)
	# Pickups ask this presenter what their pads stand on (`stage_pickup`).
	add_to_group(PICKUP_STAGE)
	_solids = info.get("solids", [])
	_views = views
	_surfaces()
	_structure()
	_grime()
	_floor_paint()
	_hazard_edges()
	_tread_nosing()
	_vehicles()
	_toll()
	_lane_and_ramp()
	_pit_and_stands()
	_impound_and_crane()
	_gallery_and_spiral()
	_roof()
	_repossession()
	_larak_sign()
	_level_numbers()
	_stands_rows()
	_floor_stencils()
	_wet_and_worn()
	_height_bars()
	_range_still_runs()
	_office_block()
	_office_paper()
	_free_marks()
	_revival()
	_bell_and_podium()
	_transit()
	_flush_batches()
	call_deferred("_retint_practicals")

func _process(delta: float) -> void:
	if not is_finite(delta):
		return
	_clock = fmod(_clock + maxf(delta, 0.0), 240.0)
	if is_instance_valid(_cruiser):
		# The hook turns the cruiser a little on its cable.
		_cruiser.rotation.y = sin(_clock * TAU / 47.0) * 0.16
	if is_instance_valid(_light_bar):
		# The league re-lensed the bar in amber and wired it to a slow
		# breath. It flares once, warm, when somebody takes the Plate: never
		# red, which belongs to Union optics and attack tells.
		_plate_flare = maxf(_plate_flare - maxf(delta, 0.0), 0.0)
		var breath: float = 0.5 + 0.5 * sin(_clock * TAU / 3.2)
		var flare: float = sin(_plate_flare / 1.2 * PI) if _plate_flare > 0.0 else 0.0
		_light_bar.light_energy = 0.9 + breath * 0.5 + flare * 3.2
		_bar_lens.transparency = 0.0
		(_bar_lens.material_override as StandardMaterial3D).emission_energy_multiplier = 1.2 + breath * 0.8 + flare * 4.0
	if is_instance_valid(_toll_arm):
		# The last working barrier arm still lifts and drops on a timer for a
		# car that never comes: the range runs on a schedule nobody stopped.
		var cycle: float = fmod(_clock, 11.0)
		var lift: float = clampf((cycle - 6.0) / 0.8, 0.0, 1.0) - clampf((cycle - 9.4) / 0.8, 0.0, 1.0)
		_toll_arm.rotation.z = lift * 1.35
	if not _office_windows.is_empty():
		# The office block over the north wall lights a floor at a time, as if
		# following somebody up the stairs, then goes dark again.
		var climb: float = fmod(_clock, 26.0)
		for index: int in range(_office_windows.size()):
			var floor_index: int = int(_office_windows[index].get_meta("floor", 0))
			var on: float = 2.0 + float(floor_index) * 1.6
			_office_windows[index].visible = climb > on and climb < on + 3.4
	if not _neon_letters.is_empty():
		# The K has a bad transformer: it drops out for a beat now and then,
		# so the sign often reads LARA.
		var phase: float = fmod(_clock, 5.3)
		var k_on: bool = not (phase > 3.9 and phase < 4.6) and not (phase > 4.75 and phase < 4.85)
		_neon_letters[4].visible = k_on
		if is_instance_valid(_neon_light):
			_neon_light.light_energy = 2.6 if k_on else 2.2
	if is_instance_valid(_train):
		# A transit train crosses the viaduct beyond the Stands every so often.
		var run: float = fmod(_clock, 34.0)
		_train.visible = run < 9.0
		_train.position.x = lerpf(-120.0, 120.0, run / 9.0)

## ---------------------------------------------------------------------------
## Lookup
## ---------------------------------------------------------------------------

func _solid_index(min_x: float, min_z: float, max_x: float, max_z: float, top: float) -> int:
	for index: int in range(_solids.size()):
		var s: Dictionary = _solids[index]
		if absf(float(s["min_x"]) - min_x) < 0.01 and absf(float(s["min_z"]) - min_z) < 0.01 \
			and absf(float(s["max_x"]) - max_x) < 0.01 and absf(float(s["max_z"]) - max_z) < 0.01 \
			and absf(float(s.get("top", MoveStep.WALL_TOP)) - top) < 0.01:
			return index
	return -1

## Hide a plain box that this presenter redraws. False when it is not there.
func _replace(min_x: float, min_z: float, max_x: float, max_z: float, top: float) -> bool:
	var index: int = _solid_index(min_x, min_z, max_x, max_z, top)
	if index < 0:
		return false
	if index < _views.size() and is_instance_valid(_views[index]):
		_views[index].visible = false
	return true

## The highest top at or under `ceiling` covering (x, z), or zero.
func _support(x: float, z: float, ceiling: float) -> float:
	var best: float = 0.0
	for s: Dictionary in _solids:
		var top: float = float(s.get("top", MoveStep.WALL_TOP))
		if top <= ceiling + 0.0001 and top > best and x >= float(s["min_x"]) and x <= float(s["max_x"]) \
			and z >= float(s["min_z"]) and z <= float(s["max_z"]):
			best = top
	return best

## ---------------------------------------------------------------------------
## Materials and batching
## ---------------------------------------------------------------------------

## A painted part. A textured one is world-triplanar at the lot's one texel
## density, whatever the tile's size, so a banner, a plate and a deck share
## the same pixel grain (`test_larak_surfaces.gd` holds every material to it).
func _mat(key: String, color: Color, texture: String = "", emission: float = 0.0) -> Material:
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.metallic_specular = 0.2
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if not texture.is_empty():
		var tile: Texture2D = EnvironmentTextures.texture_at(texture)
		if tile != null:
			material.albedo_texture = tile
			material.uv1_triplanar = true
			material.uv1_world_triplanar = true
			material.uv1_scale = Vector3.ONE * ArenaMaterials.TEXELS_PER_METRE / float(tile.get_width())
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	_materials[key] = material
	return material

func _decal(key: String, color: Color, alpha: float = 1.0) -> Material:
	if _materials.has(key):
		return _materials[key]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(color, alpha)
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_materials[key] = material
	return material

## Queue a static box into its material's batch. Batches become one mesh each.
func _box(key: String, material: Material, center: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO) -> void:
	if not _batches.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = tool
		_batch_materials[key] = material
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var basis: Basis = Basis.from_euler(rotation)
	_batches[key].append_from(mesh, 0, Transform3D(basis, center))
	_record(key, Transform3D(basis, center) * AABB(-size * 0.5, size))

func _cylinder(key: String, material: Material, center: Vector3, radius: float, height: float, rotation: Vector3 = Vector3.ZERO, sides: int = 10) -> void:
	if not _batches.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = tool
		_batch_materials[key] = material
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	_batches[key].append_from(mesh, 0, Transform3D(Basis.from_euler(rotation), center))
	_record(key, Transform3D(Basis.from_euler(rotation), center) * AABB(Vector3(-radius, -height * 0.5, -radius), Vector3(radius * 2.0, height, radius * 2.0)))

## Batched bodies, kept by bounds so `visible_bodies` can name each one a
## batch merged away. Paint and decals lie flat and are not bodies.
func _record(key: String, bounds: AABB) -> void:
	if not key.begins_with("paint") and not key.begins_with("decal"):
		_bodies.append({"name": key, "aabb": bounds})

## Every drawn body in the lot, by world bounds: each batched box and drum,
## every part and prepared prop. `test_larak_surfaces.gd` holds each one to a
## server solid, or to lying flat, sitting overhead or hugging a wall, so
## nothing a fighter sees looks like cover that is not there.
func visible_bodies() -> Array[Dictionary]:
	var bodies: Array[Dictionary] = []
	for body: Dictionary in _bodies:
		bodies.append({"name": body["name"], "aabb": global_transform * (body["aabb"] as AABB)})
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		var shape: GeometryInstance3D = node as GeometryInstance3D
		if shape.name.begins_with("Batch_") or not shape.is_visible_in_tree() or shape is Label3D:
			continue
		var bounds: AABB = shape.get_aabb()
		if bounds.size.length() <= 0.0:
			continue
		bodies.append({"name": str(shape.get_path()), "aabb": shape.global_transform * bounds})
	return bodies

## The atlas material: crisp cells, alpha-stepped, lit like the deck under it.
func _atlas_material() -> Material:
	if _materials.has("decal_atlas"):
		return _materials["decal_atlas"]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = load(DECAL_ATLAS) as Texture2D
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	material.metallic_specular = 0.0
	_materials["decal_atlas"] = material
	return material

## Lay one atlas cell at its own size (its pixels at 16 per metre), centred
## on `center`: flat on a floor turned by `yaw`, or upright on a wall facing
## `normal`. Into the shared batch unless `tool` names another.
func _atlas(cell: String, center: Vector3, yaw: float = 0.0, normal: Vector3 = Vector3.UP, tool: SurfaceTool = null) -> void:
	if not DECAL_CELLS.has(cell):
		return
	if tool == null:
		if _atlas_tool == null:
			_atlas_tool = SurfaceTool.new()
			_atlas_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool = _atlas_tool
	var rect: Rect2i = DECAL_CELLS[cell]
	var size: Vector2 = Vector2(rect.size) / ArenaMaterials.TEXELS_PER_METRE
	var across: Vector3
	var down: Vector3
	if normal.is_equal_approx(Vector3.UP):
		across = Vector3(cos(yaw), 0.0, -sin(yaw))
		down = Vector3(sin(yaw), 0.0, cos(yaw))
	else:
		across = Vector3.UP.cross(normal).normalized()
		down = Vector3.DOWN
	var uv0: Vector2 = Vector2(rect.position) / Vector2(DECAL_ATLAS_SIZE)
	var uv1: Vector2 = Vector2(rect.end) / Vector2(DECAL_ATLAS_SIZE)
	var corners: Array[Vector3] = [
		center - across * size.x * 0.5 - down * size.y * 0.5, center + across * size.x * 0.5 - down * size.y * 0.5,
		center + across * size.x * 0.5 + down * size.y * 0.5, center - across * size.x * 0.5 + down * size.y * 0.5]
	var uvs: Array[Vector2] = [uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]
	for corner: int in [0, 1, 2, 0, 2, 3]:
		tool.set_normal(normal)
		tool.set_uv(uvs[corner])
		tool.add_vertex(corners[corner])

func _flush_atlas(tool: SurfaceTool, node_name: String) -> MeshInstance3D:
	if tool == null:
		return null
	var mesh: ArrayMesh = tool.commit()
	if mesh.get_surface_count() == 0:
		return null
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = _atlas_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

## A flat paint mark lying on a floor at `y`.
func _floor_mark(key: String, material: Material, x: float, z: float, y: float, size_x: float, size_z: float, yaw: float = 0.0) -> void:
	_box(key, material, Vector3(x, y + 0.012, z), Vector3(size_x, 0.01, size_z), Vector3(0.0, yaw, 0.0))

func _flush_batches() -> void:
	for key: String in _batches:
		var tool: SurfaceTool = _batches[key]
		tool.generate_normals()
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "Batch_" + key
		node.mesh = tool.commit()
		node.material_override = _batch_materials[key]
		if key.begins_with("paint") or key.begins_with("decal"):
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	_batches.clear()
	_batch_materials.clear()
	_flush_atlas(_atlas_tool, "Batch_decal_atlas")
	_atlas_tool = null

## A keyed world sign, flat on a face. `basis` points the text's +Z outward.
func _sign(key: String, center: Vector3, yaw: float, size: Vector2, ink: Color, backing: Color = Color(0, 0, 0, 0), glow: float = 0.0) -> Label3D:
	if key not in CANON_MARKS:
		if key not in READING_STOPS or _reading_stops.has(key):
			# The bookmaker still keeps a slate, but it reads as bets and
			# tally strokes rather than paragraphs addressed to the player.
			if key in ["WORLD_LARAK_LEDGER", "WORLD_LARAK_LEDGER_2", "WORLD_LARAK_ODDS"]:
				_betting_slate(center, yaw, size)
			return null
		_reading_stops[key] = true
	if backing.a > 0.0:
		var plate: MeshInstance3D = MeshInstance3D.new()
		var quad: QuadMesh = QuadMesh.new()
		quad.size = size
		plate.mesh = quad
		plate.material_override = _decal("plate_%s" % backing.to_html(), backing)
		plate.position = center
		plate.rotation.y = yaw
		add_child(plate)
	var label: WorldSign = WorldSign.new()
	label.configure(key, size * Vector2(0.9, 0.82), ink)
	label.position = center + Basis.from_euler(Vector3(0.0, yaw, 0.0)).z * 0.01
	label.rotation.y = yaw
	if glow > 0.0:
		label.modulate = Color(ink.r * glow, ink.g * glow, ink.b * glow, 1.0)
	add_child(label)
	return label

func _betting_slate(center: Vector3, yaw: float, size: Vector2) -> void:
	var basis: Basis = Basis.from_euler(Vector3(0.0, yaw, 0.0))
	var slate: Material = _mat("betting_slate", Color("253028"))
	var chalk: Material = _mat("betting_chalk", Color("afa88c"))
	_box("betting_slate", slate, center, Vector3(size.x, size.y, 0.012), Vector3(0.0, yaw, 0.0))
	for row: int in range(3):
		for stroke: int in range(3 + row):
			var local: Vector3 = Vector3(-size.x * 0.34 + float(stroke) * size.x * 0.12,
				size.y * (0.28 - float(row) * 0.28), 0.012)
			_box("betting_chalk", chalk, center + basis * local,
				Vector3(minf(size.x * 0.018, 0.035), size.y * 0.13, 0.006), Vector3(0.0, yaw, -0.12))

## ---------------------------------------------------------------------------
## The building: coping, level colours, drive lanes, services
## ---------------------------------------------------------------------------

## Level colours, the car park's own wayfinding: green for 1, ochre for 2,
## blue for 3 and violet for the Roof (red stays with Union optics).
const LEVEL_COLORS: Dictionary[String, Color] = {
	"1": Color("4f8a6c"), "2": Color("b8892f"), "3": Color("57709e"), "R": Color("7a5a9a"),
}

## The surface class of a solid. Steel is tread, or a raised deck (the
## Bridge, the Toll canopy) whose beam is structural concrete. Of the cast
## concrete, the shear walls and the Low Ramp's sight screen are heavier
## structure, a ground box no taller than a deck edge is a kerb (its tyre rub
## at the foot of each 1.5 m band), and the rest is tall wall. Every concrete
## class tops out in the same deck concrete.
static func surface_class(solid: Dictionary, steel: bool = false) -> String:
	var min_x: float = float(solid["min_x"])
	var max_x: float = float(solid["max_x"])
	var min_z: float = float(solid["min_z"])
	var max_z: float = float(solid["max_z"])
	var top: float = float(solid.get("top", MoveStep.WALL_TOP))
	var bottom: float = float(solid.get("bottom", 0.0))
	if steel:
		return "slab" if bottom > 0.0 else "ramp"
	var shear: bool = absf(top - 4.6) < 0.01 and (max_x - min_x) < 0.7 and minf(absf(min_x + 10.6), absf(min_x - 10.0)) < 0.01
	var screen: bool = absf(top - 4.0) < 0.01 and absf(min_z - 1.5) < 0.01 and absf(max_z - 2.0) < 0.01
	if shear or screen:
		return "shear"
	if bottom <= 0.0 and top <= 1.6:
		return "kerb"
	return "wall"

## Kerbs and shear walls take their own class on the concrete the material
## pass already tiled; the boundary bands outside the shell match the walls.
func _surfaces() -> void:
	var wall: ShaderMaterial = ArenaMaterials.larak_class("wall")
	var ramp: ShaderMaterial = ArenaMaterials.larak_class("ramp")
	if wall == null or ramp == null:
		return
	for index: int in range(mini(_solids.size(), _views.size())):
		var view: MeshInstance3D = _views[index]
		if not is_instance_valid(view) or not view.material_override in [wall, ramp]:
			continue
		var material: ShaderMaterial = ArenaMaterials.larak_class(surface_class(_solids[index], view.material_override == ramp))
		if material != null:
			view.material_override = material
	var cover: Node = get_parent()
	for side: int in range(4):
		var boundary: MeshInstance3D = cover.get_node_or_null("MapBoundary%d" % side) as MeshInstance3D if cover != null else null
		if boundary != null:
			boundary.material_override = wall

func _structure() -> void:
	# Gravel and coping on the shell tops, so the walls read as a building
	# from the spectator camera rather than as slabs of floor.
	var gravel: Material = _mat("shell_top", Color("77726a"), EARTH + "earth_roof_tar_patches.png")
	var coping: Material = _mat("coping", Color("9b958a"), PRODUCTION + "scrap_trim.png")
	for s: Dictionary in _solids:
		var top: float = float(s.get("top", MoveStep.WALL_TOP))
		var min_x: float = float(s["min_x"])
		var max_x: float = float(s["max_x"])
		var min_z: float = float(s["min_z"])
		var max_z: float = float(s["max_z"])
		var outside: bool = min_x >= 35.9 or max_x <= -35.9 or min_z >= 27.9 or max_z <= -27.9
		if not outside or top < 7.0:
			continue
		var center: Vector3 = Vector3((min_x + max_x) * 0.5, top + 0.01, (min_z + max_z) * 0.5)
		_box("shell_top", gravel, center, Vector3(max_x - min_x, 0.02, max_z - min_z))
		# Coping along the lot side of each band.
		if min_x >= 35.9:
			_box("coping", coping, Vector3(min_x + 0.25, top + 0.12, center.z), Vector3(0.5, 0.24, max_z - min_z))
		elif max_x <= -35.9:
			_box("coping", coping, Vector3(max_x - 0.25, top + 0.12, center.z), Vector3(0.5, 0.24, max_z - min_z))
		elif min_z >= 27.9:
			_box("coping", coping, Vector3(center.x, top + 0.12, min_z + 0.25), Vector3(max_x - min_x, 0.24, 0.5))
		else:
			_box("coping", coping, Vector3(center.x, top + 0.12, max_z - 0.25), Vector3(max_x - min_x, 0.24, 0.5))
	# Level bands painted round the walls at each deck's waist height.
	_band("1", Vector3(-35.99, LEVEL_1 + 0.9, 12.0), Vector3(0.02, 0.6, 32.0))
	_band("1", Vector3(35.99, LEVEL_1 + 0.9, 23.0), Vector3(0.02, 0.6, 10.0))
	_band("1", Vector3(0.0, LEVEL_1 + 0.9, 27.99), Vector3(72.0, 0.6, 0.02))
	# The shear walls either side of the Stands, both faces, round the doors.
	for x: float in [-10.62, -9.98, 9.98, 10.62]:
		for span: Vector2 in [Vector2(14.0, 19.0), Vector2(22.0, 28.0)]:
			_band("1", Vector3(x, LEVEL_1 + 0.9, (span.x + span.y) * 0.5), Vector3(0.02, 0.6, span.y - span.x))
	_band("2", Vector3(-23.0, LEVEL_2 + 0.9, -27.99), Vector3(26.0, 0.6, 0.02))
	_band("2", Vector3(-35.99, LEVEL_2 + 0.9, -16.0), Vector3(0.02, 0.6, 24.0))
	_band("3", Vector3(-3.0, LEVEL_3 + 0.9, -27.99), Vector3(6.0, 0.6, 0.02))
	_band("R", Vector3(20.0, ROOF + 1.0, -27.99), Vector3(32.0, 0.4, 0.02))
	_band("R", Vector3(35.99, ROOF + 1.0, -19.0), Vector3(0.02, 0.4, 18.0))
	# Drive lanes: darker worn asphalt down the middle of each level's aisle.
	var asphalt: Material = _decal("decal_asphalt", Color("2b2927"), 0.55)
	_floor_mark("decal_asphalt", asphalt, -29.0, 12.0, LEVEL_1 - 0.004, 5.0, 32.0)
	_floor_mark("decal_asphalt", asphalt, 25.0, 12.0, LEVEL_1 - 0.004, 22.0, 4.5)
	_floor_mark("decal_asphalt", asphalt, -13.5, 19.0, LEVEL_1 - 0.004, 7.0, 18.0)
	for x: float in [-27.0, -21.0, -15.0]:
		_floor_mark("decal_asphalt", asphalt, x, -15.0, LEVEL_2 - 0.004, 3.4, 22.0)
		_floor_mark("paint_line", _decal("paint_line", LINE_PAINT), x, -11.2, LEVEL_2, 3.0, 0.25)
	_floor_mark("decal_roof_lane", _decal("decal_roof_lane", Color("2b2927"), 0.28), 20.0, -14.0, ROOF - 0.002, 18.0, 4.0)
	# Services under the bay soffits: conduit and a cable tray, well overhead.
	var conduit: Material = _mat("conduit", Color("5a5f5c"), EARTH + "earth_workshop_patched_steel.png")
	_box("conduit", conduit, Vector3(-35.6, 4.35, 18.0), Vector3(0.18, 0.18, 20.0))
	_box("conduit", conduit, Vector3(-35.6, 4.05, 18.0), Vector3(0.12, 0.12, 20.0))
	_box("conduit", conduit, Vector3(25.0, 4.45, 27.6), Vector3(22.0, 0.18, 0.18))
	_box("conduit", conduit, Vector3(25.0, 4.35, 12.4), Vector3(22.0, 0.12, 0.3))
	_box("conduit", conduit, Vector3(-23.0, 8.6, -27.6), Vector3(26.0, 0.2, 0.2))

## Water streaks down the concrete from every slab edge and wall top: the
## building has leaked for years. Deterministic, so every client agrees.
func _grime() -> void:
	var stain: Material = _decal("decal_stain", Color("17140f"), 0.38)
	# face: fixed coordinate, axis along (true = x), span, top, bottom, normal sign
	var faces: Array = [
		[-35.98, false, Vector2(-28.0, 28.0), 9.0, LEVEL_1, 1.0],
		[35.98, false, Vector2(-10.0, 28.0), 9.0, LEVEL_1, -1.0],
		[27.98, true, Vector2(-36.0, 36.0), 9.0, LEVEL_1, -1.0],
		[-27.98, true, Vector2(-36.0, 4.0), 9.0, LEVEL_2, 1.0],
		[-9.98, true, Vector2(-10.0, 10.0), LEVEL_3, PIT, 1.0],
		[9.98, false, Vector2(-10.0, 0.0), LEVEL_2, PIT, -1.0],
		[-9.98, false, Vector2(-28.0, -4.0), LEVEL_2, 1.5, -1.0],
	]
	for face: Array in faces:
		var fixed: float = face[0]
		var along_x: bool = face[1]
		var span: Vector2 = face[2]
		var top: float = face[3]
		var bottom: float = face[4]
		var t: float = span.x + 0.6
		var seed: int = int(absf(fixed) * 13.0) + (7 if along_x else 3)
		while t < span.y - 0.6:
			seed = (seed * 1103515245 + 12345) & 0x7fffffff
			var width: float = 0.25 + float(seed % 9) * 0.12
			var length: float = minf(top - bottom - 0.2, 1.2 + float((seed >> 5) % 7) * 0.6)
			var y: float = top - length * 0.5 - 0.05
			var center: Vector3 = Vector3(t, y, fixed) if along_x else Vector3(fixed, y, t)
			var size: Vector3 = Vector3(width, length, 0.01) if along_x else Vector3(0.01, length, width)
			_box("decal_stain", stain, center, size)
			t += 1.4 + float((seed >> 9) % 5) * 1.1

func _band(level: String, center: Vector3, size: Vector3) -> void:
	_box("paint_level_" + level, _decal("paint_level_" + level, LEVEL_COLORS[level]), center, size)

## ---------------------------------------------------------------------------
## Paint on the floors
## ---------------------------------------------------------------------------

func _floor_paint() -> void:
	var line: Material = _decal("paint_line", LINE_PAINT)
	var worn: Material = _decal("decal_worn", Color("2a2622"), 0.55)
	# Bay lines: the lot's own grid, still there under the league's paint.
	for i: int in range(10):
		var z: float = -2.0 + float(i) * 2.8
		if z < 21.0:
			_floor_mark("paint_line", line, -33.5, z, LEVEL_1, 5.0, 0.12)
	for i: int in range(12):
		var x: float = 5.0 + float(i) * 2.6
		if x < 23.5 or x > 28.0:
			_floor_mark("paint_line", line, x, -25.5, ROOF, 0.12, 5.0)
	for i: int in range(8):
		_floor_mark("paint_line", line, 14.5 + float(i) * 2.6, 9.0, LEVEL_1, 0.12, 5.0)
	# Faded drive arrows round the decks: the old one-way spiral of the lot.
	for at: Vector3 in [Vector3(-30.5, LEVEL_1, 4.0), Vector3(-30.5, LEVEL_1, 12.0), Vector3(22.0, LEVEL_1, 4.0), Vector3(-22.0, LEVEL_2, -7.0), Vector3(20.0, ROOF, -14.0)]:
		_arrow(at)
	# Tyre burns and scorch: the Pit is where the league's cars did doughnuts
	# before the bays fell in, and where it burns its debts now.
	for i: int in range(14):
		var a: float = float(i) * 0.45
		_atlas("burn_0", Vector3(cos(a) * 4.2 - 1.0, PIT + 0.006, sin(a) * 3.4 + 1.0), a + PI * 0.5)
	for at: Vector2 in [Vector2(-5.5, -6.0), Vector2(6.0, 5.0), Vector2(-2.0, 7.0), Vector2(3.0, -8.0)]:
		_floor_mark("decal_worn", worn, at.x, at.y, PIT + 0.004, 2.4, 1.8, at.x)
	# Oil where cars stood for years, on every deck.
	var spills: Array[Vector3] = [Vector3(-32.0, LEVEL_1, 9.0), Vector3(-29.0, LEVEL_1, 1.0), Vector3(18.0, LEVEL_1, 14.0),
		Vector3(31.0, LEVEL_1, 5.0), Vector3(-26.0, LEVEL_2, -22.0), Vector3(22.0, ROOF, -22.0), Vector3(-5.0, LEVEL_1, 14.0),
		Vector3(-33.5, LEVEL_1, 14.6), Vector3(-33.0, LEVEL_1, 20.0), Vector3(17.0, LEVEL_1, 9.6), Vector3(22.6, LEVEL_1, 9.4),
		Vector3(30.0, LEVEL_1, 9.2), Vector3(-21.0, LEVEL_2, -19.5), Vector3(-27.0, LEVEL_2, -8.5), Vector3(10.0, ROOF, -25.4),
		Vector3(18.0, ROOF, -25.6), Vector3(26.0, LEVEL_2, -7.0), Vector3(14.0, ROOF, -12.4)]
	for index: int in range(spills.size()):
		var at: Vector3 = spills[index]
		if absf(_support(at.x, at.z, at.y + 0.01) - at.y) < 0.01:
			_atlas("oil_%d" % (index % 3), Vector3(at.x, at.y + 0.008, at.z), at.x * 0.7)
	# The Settlement Circle round the origin, the jammer ring's radius, with
	# tally marks where the bay numbers used to be.
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = "SettlementCircle"
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 6.2
	torus.outer_radius = 6.65
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.03, 1.0)
	ring.position = Vector3(0.0, 0.016, 0.0)
	ring.material_override = _decal("paint_ember", LEAGUE_EMBER)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	for i: int in range(23):
		var a: float = float(i) * TAU / 23.0
		_floor_mark("paint_chalk", _decal("paint_chalk", CHALK), cos(a) * 7.2, sin(a) * 7.2, PIT, 0.1, 0.55, -a)
	# Drain grates in the wet Pit floor.
	var grate: Material = _mat("grate", Color("2a2c2b"), EARTH + "earth_service_dark_tread.png")
	for at: Vector2 in [Vector2(-7.5, 7.0), Vector2(7.5, -7.5), Vector2(0.0, 8.5)]:
		_box("grate", grate, Vector3(at.x, 0.01, at.y), Vector3(1.2, 0.02, 0.6))
	# The Roof: tar patches over a leaking deck.
	var tar: Material = _mat("tar", Color("f2ede4"), EARTH + "earth_roof_tar_patches.png")
	for patch: Vector4 in [Vector4(9.0, -24.5, 6.0, 5.0), Vector4(21.0, -22.0, 7.0, 4.0), Vector4(16.0, -14.0, 5.0, 6.0),
			Vector4(28.0, -12.5, 8.0, 4.0), Vector4(33.0, -25.0, 4.0, 5.0)]:
		_box("tar", tar, Vector3(patch.x, ROOF + 0.006, patch.y), Vector3(patch.z, 0.01, patch.w))
	# The valet circle painted round the Plate.
	var valet: MeshInstance3D = MeshInstance3D.new()
	var circle: TorusMesh = TorusMesh.new()
	circle.inner_radius = 2.4
	circle.outer_radius = 2.7
	circle.rings = 32
	circle.ring_segments = 4
	valet.mesh = circle
	valet.scale = Vector3(1.0, 0.03, 1.0)
	valet.position = Vector3(31.0, ROOF + 0.016, -22.0)
	valet.material_override = _decal("paint_hazard", HAZARD_YELLOW)
	valet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(valet)

func _arrow(at: Vector3) -> void:
	var paint: Material = _decal("paint_arrow", Color("b9b08c"), 0.7)
	_floor_mark("paint_arrow", paint, at.x, at.z, at.y + 0.002, 0.35, 2.4)
	_floor_mark("paint_arrow", paint, at.x - 0.35, at.z - 1.0, at.y + 0.002, 0.3, 1.0, 0.7)
	_floor_mark("paint_arrow", paint, at.x + 0.35, at.z - 1.0, at.y + 0.002, 0.3, 1.0, -0.7)

## Yellow-and-black stripes on every deck edge with a real drop below it, so a
## ledge reads at a glance from above and the stair beside it reads from below.
func _hazard_edges() -> void:
	var yellow: Material = _decal("paint_hazard", HAZARD_YELLOW)
	var black: Material = _decal("paint_hazard_black", HAZARD_BLACK)
	for s: Dictionary in _solids:
		var top: float = float(s.get("top", MoveStep.WALL_TOP))
		var bottom: float = float(s.get("bottom", MoveStep.GROUND_Y))
		var min_x: float = float(s["min_x"])
		var max_x: float = float(s["max_x"])
		var min_z: float = float(s["min_z"])
		var max_z: float = float(s["max_z"])
		# Only walking decks: a wreck or a kiosk top is not a ledge.
		if not [LEVEL_1, LEVEL_2, LEVEL_3, ROOF].has(top) or (max_x - min_x) < 3.0 or (max_z - min_z) < 2.9:
			continue
		if bottom > 0.0 and absf(top - LEVEL_2) > 0.01:
			continue
		for edge: int in range(4):
			var along_x: bool = edge < 2
			var fixed: float = [min_z, max_z, min_x, max_x][edge]
			var out: float = -0.3 if edge % 2 == 0 else 0.3
			var lo: float = min_x if along_x else min_z
			var hi: float = max_x if along_x else max_z
			var t: float = lo
			while t < hi - 0.01:
				var step: float = minf(1.0, hi - t)
				var mid: float = t + step * 0.5
				var probe_x: float = mid if along_x else fixed + out
				var probe_z: float = fixed + out if along_x else mid
				var below: float = _support(probe_x, probe_z, top + 0.01)
				var inside_x: float = mid if along_x else fixed - out * 0.6
				var inside_z: float = fixed - out * 0.6 if along_x else mid
				if top - below > 0.9 and _support(inside_x, inside_z, top + 0.01) >= top - 0.01:
					var stripe: Material = yellow if int(floor(mid)) % 2 == 0 else black
					var key: String = "paint_hazard" if stripe == yellow else "paint_hazard_black"
					if along_x:
						_floor_mark(key, stripe, mid, fixed - out * 0.5, top, step, 0.3)
					else:
						_floor_mark(key, stripe, fixed - out * 0.5, mid, top, 0.3, step)
				t += step

## Treads get a yellow nosing on every riser edge and chevrons up the flight.
func _tread_nosing() -> void:
	var nosing: Material = _decal("paint_hazard", HAZARD_YELLOW)
	for s: Dictionary in _solids:
		var top: float = float(s.get("top", MoveStep.WALL_TOP))
		var min_x: float = float(s["min_x"])
		var max_x: float = float(s["max_x"])
		var min_z: float = float(s["min_z"])
		var max_z: float = float(s["max_z"])
		var depth: float = minf(max_x - min_x, max_z - min_z)
		if top > 6.0 or top < 0.4 or absf(depth - 2.0) > 0.05 or fmod(top, 0.5) > 0.01:
			continue
		if float(s.get("bottom", 0.0)) > 0.0:
			continue
		for edge: int in range(4):
			var along_x: bool = edge < 2
			var fixed: float = [min_z, max_z, min_x, max_x][edge]
			var out: float = -0.25 if edge % 2 == 0 else 0.25
			var mid: float = (min_x + max_x) * 0.5 if along_x else (min_z + max_z) * 0.5
			var length: float = (max_x - min_x) if along_x else (max_z - min_z)
			var probe_x: float = mid if along_x else fixed + out
			var probe_z: float = fixed + out if along_x else mid
			var below: float = _support(probe_x, probe_z, top + 0.01)
			if top - below < 0.3 or top - below > 0.7:
				continue
			if along_x:
				_floor_mark("paint_hazard", nosing, mid, fixed - out * 0.6, top, length - 0.2, 0.18)
			else:
				_floor_mark("paint_hazard", nosing, fixed - out * 0.6, mid, top, 0.18, length - 0.2)

## ---------------------------------------------------------------------------
## Vehicles: each redrawn inside its own collision volume
## ---------------------------------------------------------------------------

func _vehicles() -> void:
	if _replace(-34.0, 22.0, -31.8, 27.0, 3.7):
		_van(Vector3(-32.9, LEVEL_1, 24.5), Vector3(2.2, 2.2, 5.0), false, "union")
	# The wreck that went into the Pit nose first when the bays fell, and
	# two more burnt out on the Roof: civilian bodies, lamps dead.
	if _replace(2.0, -4.0, 6.4, -2.0, 1.4):
		_prop("burned_sedan", Vector3(4.2, PIT, -3.0), 0.0, self, 0.05)
	if _replace(-15.0, -26.0, -11.0, -24.0, 4.4):
		_car(Vector3(-13.0, LEVEL_2, -25.0), Vector3(4.0, 1.4, 2.0), true, "union_slashed")
	# Civilian cars clamped and caged in the Impound, awaiting an order.
	for x: float in [16.0, 23.0]:
		if _replace(x, 19.0, x + 4.4, 21.0, 2.9):
			_prop("clamped_sedan", Vector3(x + 2.2, LEVEL_1, 20.0), 0.0 if x < 20.0 else PI)
			_cage(Vector3(x + 2.2, LEVEL_1, 20.0), Vector3(4.4, 1.4, 2.0))
	if _replace(14.0, -25.0, 18.4, -23.0, 7.4):
		_prop("burned_sedan", Vector3(16.2, ROOF, -24.0), PI)
	if _replace(30.0, -26.0, 34.4, -24.0, 7.4):
		_prop("burned_sedan", Vector3(32.2, ROOF, -25.0), 0.0)
	if _replace(19.0, -17.0, 21.2, -12.0, 8.2):
		_van(Vector3(20.1, ROOF, -14.5), Vector3(2.2, 2.2, 5.0), true, "union")
	# THE STACK: crushed cars piled on burnt tow trucks, two piles side by
	# side across the 4.4 x 5 m solid, turned against each other.
	if _replace(4.0, 3.0, 8.4, 8.0, 3.2):
		_prop("car_stack", Vector3(5.1, PIT, 5.5), 0.0)
		_prop("car_stack", Vector3(7.3, PIT, 5.5), PI)
	if _replace(24.0, -6.0, 26.0, -3.0, 4.4):
		_drum(Vector3(25.0, LEVEL_2, -4.5))

## A sedan from boxes: body, cabin, glass, wheels and lamps. `size` is the
## footprint (length, height, width); `along_x` lays the length on world x.
func _car(base: Vector3, size: Vector3, along_x: bool, style: String, tilt: float = 0.0) -> void:
	var body_color: Color = UNION_BLACK if style.begins_with("union") else Color("6b6150")
	var root: Node3D = Node3D.new()
	root.name = "Car"
	root.position = base
	root.rotation = Vector3(0.0, 0.0 if along_x else PI * 0.5, tilt)
	add_child(root)
	var length: float = size.x
	var height: float = size.y
	var width: float = size.z
	var body: Material = _mat("car_" + style, body_color)
	var glass: Material = _mat("car_glass", Color("15191c"))
	var tyre: Material = _mat("tyre", Color("151515"))
	var lamp: Material = _mat("lamp_white", Color("e9e2c4"), "", 0.6)
	# Dead tail lamps: dark lenses, never a lit red point at body height,
	# which would read like a Union optic in Episode 0.
	var red: Material = _mat("lamp_red_dead", Color("4a1c18"))
	var wheel_y: float = 0.36 if style != "union_slashed" else 0.24
	var lower: float = 0.32
	var waist: float = height * 0.62
	_part(root, body, Vector3(0.0, (lower + waist) * 0.5, 0.0), Vector3(length, waist - lower, width))
	_part(root, body, Vector3(-length * 0.04, (waist + height) * 0.5, 0.0), Vector3(length * 0.52, height - waist, width * 0.88))
	_part(root, glass, Vector3(-length * 0.04, (waist + height) * 0.5 + 0.02, 0.0), Vector3(length * 0.48, (height - waist) * 0.72, width * 0.9))
	_part(root, lamp, Vector3(length * 0.5, waist - 0.12, width * 0.32), Vector3(0.05, 0.12, 0.3))
	_part(root, lamp, Vector3(length * 0.5, waist - 0.12, -width * 0.32), Vector3(0.05, 0.12, 0.3))
	_part(root, red, Vector3(-length * 0.5, waist - 0.12, width * 0.34), Vector3(0.05, 0.1, 0.26))
	_part(root, red, Vector3(-length * 0.5, waist - 0.12, -width * 0.34), Vector3(0.05, 0.1, 0.26))
	for fx: float in [-0.32, 0.32]:
		for fz: float in [-0.5, 0.5]:
			var wheel: MeshInstance3D = MeshInstance3D.new()
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = 0.36
			cylinder.bottom_radius = 0.36
			cylinder.height = 0.26
			cylinder.radial_segments = 8
			wheel.mesh = cylinder
			wheel.material_override = tyre
			wheel.position = Vector3(fx * length, wheel_y, fz * (width - 0.22))
			wheel.rotation.x = PI * 0.5
			if style == "union_slashed":
				wheel.scale = Vector3(1.0, 1.0, 0.62)
			root.add_child(wheel)
	if style.begins_with("union"):
		# Union issue: a narrow red waist line, kept thin so no wreck reads
		# like a Union body's red tell, and a dead light bar.
		_part(root, _mat("union_band", UNION_RED), Vector3(0.0, waist - 0.05, 0.0), Vector3(length + 0.01, 0.06, width + 0.01))
		_part(root, _mat("bar_dead", Color("3a2222")), Vector3(-length * 0.04, height + 0.06, 0.0), Vector3(0.3, 0.1, width * 0.7))

func _van(base: Vector3, size: Vector3, on_side: bool, style: String) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Van"
	root.position = base
	add_child(root)
	var body: Material = _mat("van_" + style, UNION_BLACK if style == "union" else Color("6a6658"))
	var glass: Material = _mat("car_glass", Color("15191c"))
	var tyre: Material = _mat("tyre", Color("151515"))
	var band: Material = _mat("union_band", UNION_RED)
	if not on_side:
		# Standing, long axis on z, bonnet to the north.
		_part(root, body, Vector3(0.0, 1.25, 0.2), Vector3(size.x, 1.8, size.z - 0.4))
		_part(root, body, Vector3(0.0, 0.85, -size.z * 0.5 + 0.2), Vector3(size.x, 0.9, 0.4))
		_part(root, glass, Vector3(0.0, 1.75, -size.z * 0.5 + 0.38), Vector3(size.x * 0.9, 0.6, 0.02))
		_part(root, band, Vector3(0.0, 1.2, 0.2), Vector3(size.x + 0.01, 0.08, size.z - 0.38))
		for z: float in [-1.6, 1.6]:
			for x: float in [-1.0, 1.0]:
				_wheel(root, tyre, Vector3(x * (size.x * 0.5 - 0.1), 0.38, z), true)
	else:
		# On its side: the roof faces west, the wheels east. The waist band
		# now stands on end round the body; the issued door plates face the
		# sky, and the roof with its dead light bar faces the Roof deck.
		var bone: Material = _mat("union_plate", UNION_STEEL, PRODUCTION + "union_steel.png")
		var west: float = -(size.x - 0.3) * 0.5
		_part(root, body, Vector3(0.0, size.y * 0.5, 0.0), Vector3(size.x - 0.3, size.y, size.z))
		_part(root, band, Vector3(-0.1, size.y * 0.5, 0.0), Vector3(0.08, size.y + 0.02, size.z + 0.02))
		_part(root, bone, Vector3(0.45, size.y + 0.005, 0.2), Vector3(0.9, 0.02, size.z * 0.6))
		_part(root, bone, Vector3(0.45, 0.005, 0.2), Vector3(0.9, 0.02, size.z * 0.6))
		# The roof plate faces the Roof deck now, crossed by the red band and
		# scuffed where the van went over.
		_part(root, bone, Vector3(west - 0.01, size.y * 0.5, 0.25), Vector3(0.02, size.y - 0.25, size.z - 0.9))
		_part(root, band, Vector3(west - 0.02, size.y * 0.5, 0.25), Vector3(0.02, 0.08, size.z - 0.9))
		_part(root, _mat("van_scuff", Color("3b3632")), Vector3(west - 0.025, 0.45, 0.9), Vector3(0.02, 0.5, 2.2))
		_part(root, _mat("van_scuff", Color("3b3632")), Vector3(west - 0.025, size.y - 0.55, -0.6), Vector3(0.02, 0.35, 1.4))
		# Roof: rack rails, the dead light bar with its lenses, and the spray.
		var rail: Material = _mat("seat_rail", Color("4b4f4c"), EARTH + "earth_workshop_patched_steel.png")
		for y: float in [0.45, size.y - 0.45]:
			_part(root, rail, Vector3(west - 0.06, y, 0.0), Vector3(0.08, 0.08, size.z * 0.8))
		_part(root, _mat("bar_dead", Color("3a2222")), Vector3(west - 0.1, size.y * 0.5, -1.4), Vector3(0.18, size.y * 0.66, 0.34))
		# Both lenses dead and dark: smashed, not lit.
		_part(root, _mat("lens_dead", Color("2a1c1a")), Vector3(west - 0.2, size.y * 0.5 + 0.38, -1.4), Vector3(0.04, 0.6, 0.3))
		_part(root, _mat("lens_dead", Color("2a1c1a")), Vector3(west - 0.2, size.y * 0.5 - 0.38, -1.4), Vector3(0.04, 0.6, 0.3))
		var spray: Label3D = WorldSign.new()
		(spray as WorldSign).configure("WORLD_LARAK_REPOSSESSED", Vector2(2.6, 1.0), SPRAY)
		spray.position = Vector3(west - 0.04, size.y * 0.5 + 0.45, 0.9)
		spray.rotation = Vector3(0.0, -PI * 0.5, 0.0)
		root.add_child(spray)
		# Windscreen and lamps at the north end, rear doors with the seal south.
		_part(root, glass, Vector3(-0.35, size.y * 0.5, -size.z * 0.5 - 0.01), Vector3(1.0, size.y * 0.8, 0.02))
		_part(root, _mat("lamp_white", Color("e9e2c4"), "", 0.6), Vector3(0.6, 0.35, -size.z * 0.5 - 0.02), Vector3(0.2, 0.3, 0.02))
		_part(root, _mat("lamp_white", Color("e9e2c4"), "", 0.6), Vector3(0.6, size.y - 0.35, -size.z * 0.5 - 0.02), Vector3(0.2, 0.3, 0.02))
		_part(root, bone, Vector3(0.0, size.y * 0.5, size.z * 0.5 + 0.01), Vector3(size.x - 0.5, size.y - 0.3, 0.02))
		_part(root, band, Vector3(-0.1, size.y * 0.5, size.z * 0.5 + 0.02), Vector3(0.08, size.y - 0.3, 0.02))
		for z: float in [-1.6, 1.6]:
			for y: float in [0.45, 1.75]:
				_wheel(root, tyre, Vector3(size.x * 0.5 - 0.12, y, z), false)

func _wheel(parent: Node3D, tyre: Material, at: Vector3, upright: bool) -> void:
	var wheel: MeshInstance3D = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.38
	cylinder.bottom_radius = 0.38
	cylinder.height = 0.26
	cylinder.radial_segments = 8
	wheel.mesh = cylinder
	wheel.material_override = tyre
	wheel.position = at
	wheel.rotation = Vector3(0.0, 0.0, PI * 0.5) if upright else Vector3(0.0, 0.0, PI * 0.5)
	parent.add_child(wheel)

## A prepared prop on its floor centre `at`, turned by `yaw`. Its painted
## clusters stay crisp at any distance. Null, with an error, when the asset
## is missing from the build.
func _prop(prop: String, at: Vector3, yaw: float, parent: Node3D = self, tilt: float = 0.0) -> Node3D:
	var scene: PackedScene = load(PROPS + prop + ".glb") as PackedScene
	var node: Node3D = scene.instantiate() as Node3D if scene != null else null
	if node == null:
		push_error("larak_lot: missing prop " + prop)
		return null
	node.name = prop.to_pascal_case()
	node.position = at
	node.rotation = Vector3(0.0, yaw, tilt)
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var surface: MeshInstance3D = child as MeshInstance3D
		for index: int in range(surface.get_surface_override_material_count()):
			var finish: BaseMaterial3D = surface.get_active_material(index) as BaseMaterial3D
			if finish != null:
				finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	node.add_to_group(&"larak_prop")
	parent.add_child(node)
	return node

func _part(parent: Node3D, material: Material, center: Vector3, size: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = center
	node.material_override = material
	parent.add_child(node)
	return node

func _cage(base: Vector3, size: Vector3) -> void:
	var bar: Material = _mat("cage_bar", Color("4b4f4c"), EARTH + "earth_workshop_patched_steel.png")
	var top: float = 1.4
	for x: float in [-0.5, -0.25, 0.0, 0.25, 0.5]:
		for z: float in [-0.5, 0.5]:
			_box("cage_bar", bar, base + Vector3(x * size.x, top * 0.5, z * size.z), Vector3(0.06, top, 0.06))
	for z: float in [-0.5, 0.5]:
		_box("cage_bar", bar, base + Vector3(0.0, top, z * size.z), Vector3(size.x, 0.06, 0.06))
		_box("cage_bar", bar, base + Vector3(0.0, top * 0.55, z * size.z), Vector3(size.x, 0.05, 0.05))
	for x: float in [-0.5, 0.5]:
		_box("cage_bar", bar, base + Vector3(x * size.x, top, 0.0), Vector3(0.06, 0.06, size.z))
	_box("cage_bar", bar, base + Vector3(0.0, top, 0.0), Vector3(size.x, 0.05, 0.05))

func _drum(base: Vector3) -> void:
	var wood: Material = _mat("drum_wood", Color("6b5236"))
	var cable: Material = _mat("drum_cable", Color("202224"))
	_cylinder("drum_wood", wood, base + Vector3(0.0, 0.7, -1.35), 0.7, 0.12, Vector3(PI * 0.5, 0.0, 0.0), 12)
	_cylinder("drum_wood", wood, base + Vector3(0.0, 0.7, 1.35), 0.7, 0.12, Vector3(PI * 0.5, 0.0, 0.0), 12)
	_cylinder("drum_cable", cable, base + Vector3(0.0, 0.7, 0.0), 0.55, 2.6, Vector3(PI * 0.5, 0.0, 0.0), 12)

## ---------------------------------------------------------------------------
## Quarters
## ---------------------------------------------------------------------------

func _toll() -> void:
	var arm_yellow: Material = _mat("arm_yellow", HAZARD_YELLOW)
	var arm_black: Material = _mat("arm_black", HAZARD_BLACK)
	for index: int in range(3):
		var x: float = [-30.0, -24.0, -18.0][index]
		# The old cashier booths, filling their solids: grey-green enamel
		# under the league's ember and mustard spray, dark glass, a flat cap,
		# and on the lane end the Office's seal, cut through with a blade.
		if _replace(x - 1.0, -17.0, x + 1.0, -13.0, 5.8):
			_prop("toll_booth", Vector3(x, LEVEL_2, -15.0), 0.0)
		# Barrier arms: hazard striped, two snapped short, and the east one
		# still on its motor. Each motor sits in its booth's lane-end corner,
		# inside the booth's own solid; only the thin arm reaches the lane.
		_box("arm_black", arm_black, Vector3(x + 0.85, 4.05, -13.15), Vector3(0.3, 0.3, 0.3))
		if index < 2:
			_box("arm_yellow", arm_yellow, Vector3(x + 1.3, 4.4, -12.94), Vector3(0.8, 0.12, 0.12), Vector3(0.0, 0.0, 1.1 if index == 1 else 0.7))
	_toll_arm = Node3D.new()
	_toll_arm.name = "TollArm"
	_toll_arm.position = Vector3(-17.0, 4.12, -12.94)
	add_child(_toll_arm)
	for i: int in range(3):
		_part(_toll_arm, arm_yellow if i % 2 == 0 else arm_black, Vector3(0.15 + float(i) * 0.3, 0.0, 0.0), Vector3(0.3, 0.12, 0.12))
	_sign("WORLD_LARAK_TOLL_ONE_LIFE", Vector3(-11.5, 4.6, -27.98), 0.0, Vector2(3.6, 2.2), LEAGUE_CREAM, Color("231c1a"))
	_sign("WORLD_LARAK_NOT_METERED", Vector3(-7.0, 5.15, -27.97), 0.0, Vector2(3.2, 0.6), SPRAY)
	_sign("WORLD_LARAK_FARE_PAID", Vector3(-35.98, 4.4, -10.5), PI * 0.5, Vector2(3.0, 1.2), LEAGUE_CREAM, Color("3a3e3b"))
	_directory(Vector3(-35.98, 4.55, -6.3), PI * 0.5)
	# Dead pay machines, every one signed by Larak; one still asks to be paid.
	for x: float in [-34.0, -31.5, -21.0]:
		_pay_machine(Vector3(x, LEVEL_2, -28.0), x == -31.5)
	_callout("WORLD_LARAK_TOLL", Vector3(-35.98, 5.3, -18.0), PI * 0.5, Vector2(4.0, 1.4), 0)
	_callout("WORLD_LARAK_BOOTHS", Vector3(-24.0, 5.2, -12.98), 0.0, Vector2(1.8, 0.5), 1)

## A pay machine with its back to a north wall at `wall` (the wall's foot,
## centred on the machine). Larak's approval is pasted on its blank plate;
## a dead one has its screen dark, the live one still asks to be paid.
func _pay_machine(wall: Vector3, live: bool) -> Node3D:
	var machine: Node3D = _prop("pay_machine", wall + Vector3(0.0, 0.0, PAY_DEPTH * 0.5 - WALL_INSET), 0.0)
	var face: float = wall.z + PAY_DEPTH - WALL_INSET + 0.008
	_sign("WORLD_LARAK_SIGNATURE", Vector3(wall.x + PAY_PLATE.x, wall.y + PAY_PLATE.y, face), 0.0, PAY_PLATE_SIZE, Color("1b1d1c"), Color("c9c2a8"))
	var screen: Vector3 = Vector3(wall.x + PAY_SCREEN.x, wall.y + PAY_SCREEN.y, face)
	if live:
		# Still powered: a warm amber panel with the request in dark segments.
		_box("pay_screen_live", _mat("pay_screen_live", Color("ffb347"), "", 1.2), screen - Vector3(0.0, 0.0, 0.004), Vector3(PAY_SCREEN_SIZE.x, PAY_SCREEN_SIZE.y, 0.01))
		_sign("WORLD_LARAK_PLEASE_PAY", screen, 0.0, PAY_SCREEN_SIZE, Color("2a1806"))
	else:
		_box("pay_screen_dead", _mat("pay_screen_dead", Color("1f1a14")), screen - Vector3(0.0, 0.0, 0.004), Vector3(PAY_SCREEN_SIZE.x, PAY_SCREEN_SIZE.y, 0.01))
	return machine

func _lane_and_ramp() -> void:
	# The Lane is the old street entry: the facility's own plate, still
	# naming the officer who signed for it, and the directory that admits
	# four levels.
	_sign("WORLD_LARAK_FACILITY", Vector3(-35.98, 3.4, 6.4), PI * 0.5, Vector2(2.2, 1.4), Color("23262a"), Color("a9aca6"))
	_callout("WORLD_LARAK_LANE", Vector3(-35.98, 3.6, 3.4), PI * 0.5, Vector2(3.0, 1.0), 2)
	_directory(Vector3(-22.0, 2.95, 1.48), PI)
	_sign("WORLD_LARAK_DECOMMISSION", Vector3(-35.98, 2.75, 12.6), PI * 0.5, Vector2(1.5, 0.8), Color("2a1f12"), Color("8c6c34"))
	# The Office's paper, and the league's reply under it.
	_sign("WORLD_LARAK_NOT_ON_RECORD", Vector3(-35.98, 3.4, 16.4), PI * 0.5, Vector2(2.8, 1.3), UNION_BLACK, Color("d8d0b4"))
	_seal(Vector3(-35.975, 3.85, 17.55), PI * 0.5, 0.2, true)
	_sign("WORLD_LARAK_NEITHER", Vector3(-35.97, 2.45, 16.2), PI * 0.5, Vector2(2.4, 0.6), SPRAY)
	_callout("WORLD_LARAK_LOW_RAMP", Vector3(-15.0, 2.6, 1.48), PI, Vector2(2.0, 0.6), 0)
	_sign("WORLD_LARAK_PAY_DOOR", Vector3(-23.5, 2.75, 10.52), 0.0, Vector2(3.2, 0.6), HAZARD_YELLOW, Color("222222"))
	# Inside the tunnel: the landing is not a level, whatever the sign at the
	# top says, and somebody has lettered Article Seven's reply on the wall.
	_sign("WORLD_LARAK_HALFWAY", Vector3(-23.6, 2.05, 9.98), PI, Vector2(3.6, 0.8), LEAGUE_CREAM)
	_sign("WORLD_LARAK_COGNITION", Vector3(-19.4, 2.2, 2.02), 0.0, Vector2(5.2, 0.5), LEAGUE_MUSTARD)
	var chevron: Material = _decal("paint_chevron", LEAGUE_EMBER, 0.85)
	for z: float in [4.0, 8.0]:
		for step: int in range(2):
			var x: float = -18.6 + float(step) * 1.1
			_floor_mark("paint_chevron", chevron, x, z - 0.32, RAIL_LANDING, 0.9, 0.16, -0.6)
			_floor_mark("paint_chevron", chevron, x, z + 0.32, RAIL_LANDING, 0.9, 0.16, 0.6)
	# Minus one at the bottom: on the tunnel mouth and the Pit's walls.
	_sign("WORLD_LARAK_LEVEL_MINUS_1", Vector3(-12.0, 0.8, 2.02), 0.0, Vector2(1.5, 1.2), SPRAY)
	_sign("WORLD_LARAK_LEVEL_MINUS_1", Vector3(9.98, 1.6, -4.5), -PI * 0.5, Vector2(1.8, 2.0), SPRAY)
	_floor_sign("WORLD_LARAK_LEVEL_MINUS_1", Vector3(-12.6, PIT, 6.0), PI * 0.5, Vector2(2.6, 3.4), Color(0.88, 0.47, 0.18, 0.8))
	# Sodium fittings along the Lane bay soffit and a cold tube in the tunnel.
	var sodium: Material = _mat("lamp_sodium", SODIUM, "", 3.0)
	for z: float in [12.0, 18.0, 24.0]:
		_box("lamp_sodium", sodium, Vector3(-31.0, 4.55, z), Vector3(0.25, 0.08, 1.4))
	var tube: Material = _mat("lamp_tube", FLUORESCENT, "", 2.5)
	var dead: Material = _mat("lamp_dead", Color("4a4f4c"))
	_box("lamp_tube", tube, Vector3(-21.0, 2.96, 6.0), Vector3(1.6, 0.06, 0.12))
	_box("lamp_tube", tube, Vector3(-17.0, 2.96, 6.0), Vector3(1.6, 0.06, 0.12))
	_box("lamp_dead", dead, Vector3(-19.0, 2.96, 6.0), Vector3(1.6, 0.06, 0.12))
	# League extension cables strung along the bay soffit, tapping the
	# facility's own supply: the power was never cut.
	var cable: Material = _mat("cable", Color("1c1c1e"))
	_box("cable", cable, Vector3(-27.2, 4.4, 18.0), Vector3(0.05, 0.05, 20.0))

func _pit_and_stands() -> void:
	# The LEDGER WALL: chalk debts on the Pit's north face under the Bridge.
	_sign("WORLD_LARAK_LEDGER", Vector3(-4.0, 1.4, -9.98), 0.0, Vector2(7.5, 2.2), CHALK, Color("232624"))
	_sign("WORLD_LARAK_LEDGER_2", Vector3(5.0, 1.4, -9.98), 0.0, Vector2(6.0, 2.2), CHALK, Color("232624"))
	_sign("WORLD_LARAK_PIT", Vector3(0.0, 0.03, 4.4), 0.0, Vector2(4.0, 1.2), Color("c9c3ad"))
	# Bleachers: pallets and car seats on the Stands, backs to the viaduct.
	var pallet: Material = _mat("pallet", Color("8a6f4c"))
	for row: int in range(2):
		var y: float = 0.5 + float(row) * 0.5
		for i: int in range(9):
			var x: float = -9.0 + float(i) * 2.0 + float(row)
			if x > 3.5 and x < 9.0 and row == 0:
				continue
			_box("pallet", pallet, Vector3(x, y + 0.03, 7.0 + float(row) * 2.0), Vector3(1.6, 0.06, 1.4))
	var seat: Material = _mat("car_seat", Color("3c2a28"))
	for i: int in range(12):
		var x: float = -9.0 + float(i) * 1.6
		if absf(x) < 3.0:
			continue
		_box("car_seat", seat, Vector3(x, LEVEL_1 + 0.75, 27.88), Vector3(0.6, 0.9, 0.22))
	_callout("WORLD_LARAK_STANDS", Vector3(-6.0, 3.9, 27.97), PI, Vector2(4.0, 1.2), 1)
	# The creed, once and large, where the Office is thinnest.
	_sign("WORLD_LARAK_CREED", Vector3(2.0, 6.6, 27.97), PI, Vector2(11.5, 1.8), LEAGUE_MUSTARD)
	# The bookmaker's kiosk, hatch to the Pit under its striped awning, the
	# night's odds chalked on the slates at both ends.
	if _replace(-2.0, 16.0, 2.0, 19.0, 4.3):
		_prop("bookmaker_kiosk", Vector3(0.0, LEVEL_1, 17.5), PI)
		for side: float in [-1.0, 1.0]:
			_sign("WORLD_LARAK_ODDS", Vector3(side * (2.0 + 0.012), LEVEL_1 + KIOSK_SLATE.y, KIOSK_SLATE.x), side * PI * 0.5, KIOSK_SLATE_SIZE, CHALK)
	# The tote board running back to the viaduct: the night's book, both faces.
	_sign("WORLD_LARAK_LEDGER_2", Vector3(-0.62, 3.0, 23.5), -PI * 0.5, Vector2(5.0, 1.8), CHALK, Color("1f2a24"))
	_sign("WORLD_LARAK_ODDS", Vector3(0.62, 3.0, 23.5), PI * 0.5, Vector2(5.0, 1.8), CHALK, Color("1f2a24"))
	_sign("WORLD_LARAK_67", Vector3(2.02, 2.05, 18.6), PI * 0.5, Vector2(0.16, 0.1), Color("9a948a"))
	# League banners hang off the Gallery front over the Pit.
	for x: float in [-7.5, 7.5]:
		_banner(Vector3(x, 3.2, -9.97), 0.0, Vector2(2.4, 2.4))

func _impound_and_crane() -> void:
	_callout("WORLD_LARAK_IMPOUND", Vector3(35.98, 3.4, 4.0), -PI * 0.5, Vector2(4.0, 1.2), 2)
	_directory(Vector3(10.62, 3.45, 16.5), PI * 0.5)
	_sign("WORLD_LARAK_RELEASE_BY_ORDER", Vector3(18.2, 3.3, 20.0), 0.0, Vector2(2.6, 0.6), UNION_BLACK, Color("d9d2b8"))
	# A Hangar Candy sticker slapped beside the Office's release tag.
	_sign("WORLD_LARAK_TAG_DENIED", Vector3(20.02, 3.3, 20.01), 0.0, Vector2(1.0, 0.34), Color("e9e4d8"), Color("141414"))
	_callout("WORLD_LARAK_STAIR_B", Vector3(29.98, 3.6, 2.0), -PI * 0.5, Vector2(2.6, 0.9), 0)
	_callout("WORLD_LARAK_CRANE", Vector3(17.0, 2.3, 0.02), 0.0, Vector2(3.2, 0.9), 3)
	_sign("WORLD_LARAK_FIRE_STAIR", Vector3(15.0, 4.4, -9.98), 0.0, Vector2(3.2, 0.7), HAZARD_YELLOW)
	var sodium: Material = _mat("lamp_sodium", SODIUM, "", 3.0)
	for x: float in [18.0, 24.0, 32.0]:
		_box("lamp_sodium", sodium, Vector3(x, 4.55, 18.0), Vector3(1.4, 0.08, 0.25))
	# The league's back office: a window and a door on the cabin, and the
	# coffee machine Larak signed for, set out by the door.
	var window: Material = _mat("office_window", Color("e8c27a"), "", 1.4)
	_box("office_window", window, Vector3(28.98, 3.1, 25.0), Vector3(0.04, 0.8, 1.8))
	_box("office_door", _mat("office_door", Color("4b3b2c")), Vector3(32.0, 2.6, 22.98), Vector3(1.0, 2.1, 0.04))
	# Its back to the cabin, its face to the lot: Larak's approval on the
	# blank plate, and the league's own notice taped over the smoked panel.
	_prop("coffee_machine", Vector3(30.2, LEVEL_1, 23.0 - COFFEE_DEPTH * 0.5 + WALL_INSET), PI)
	var face: float = 23.0 - COFFEE_DEPTH + WALL_INSET - 0.008
	_sign("WORLD_LARAK_COFFEE", Vector3(30.2 - COFFEE_PLATE.x, LEVEL_1 + COFFEE_PLATE.y, face), PI, COFFEE_PLATE_SIZE, Color("1b1d1c"), Color("c9c2a8"))
	_sign("WORLD_LARAK_OUT_OF_ORDER", Vector3(30.2 - COFFEE_NOTICE.x, LEVEL_1 + COFFEE_NOTICE.y, face), PI, COFFEE_NOTICE_SIZE, Color("2a2a2a"), Color("e3dcc4"))
	# A Night Watch grid stencil on a bay column.
	_sign("WORLD_LARAK_TAG_GRID", Vector3(28.0, 2.5, 15.68), PI, Vector2(0.5, 0.4), Color("c8c4b8"))

func _gallery_and_spiral() -> void:
	# The giant league banner on the Spiral wall.
	_banner(Vector3(-16.0, 6.2, -27.97), 0.0, Vector2(4.6, 5.0))
	_callout("WORLD_LARAK_SPIRAL", Vector3(-8.0, 4.3, -27.98), 0.0, Vector2(1.8, 0.55), 2)
	_callout("WORLD_LARAK_GALLERY", Vector3(-9.98, 4.0, -15.0), -PI * 0.5, Vector2(3.0, 0.8), 0)
	_sign("WORLD_LARAK_BRIDGE", Vector3(-6.0, 2.8, -4.98), 0.0, Vector2(2.2, 0.32), HAZARD_YELLOW)
	# Hangar Candy leave their watermark on the Gallery front.
	_sign("WORLD_LARAK_TAG_DENIED", Vector3(2.6, 3.95, -9.97), 0.0, Vector2(1.2, 0.36), Color("e9e4d8"), Color("141414"))

## A league callout board: hand-painted lettering on a board in one of the
## league's warm colours, so the quarters read without bone-white placards.
func _callout(key: String, center: Vector3, yaw: float, size: Vector2, style: int) -> void:
	var boards: Array[Color] = [LEAGUE_EMBER, LEAGUE_MUSTARD, LEAGUE_RUST, LEAGUE_CANVAS]
	var inks: Array[Color] = [Color("1c1612"), Color("201a12"), LEAGUE_CREAM, Color("3a2416")]
	var pick: int = posmod(style, boards.size())
	_sign(key, center, yaw, size, inks[pick], boards[pick])

## The lot's own directory at each entry: four levels admitted, and level 1
## named the lowest, a ramp's length above the one nobody numbered.
func _directory(center: Vector3, yaw: float) -> void:
	_sign("WORLD_LARAK_DIRECTORY", center, yaw, Vector2(2.4, 1.3), Color("e0dccb"), Color("2c4a3a"))

## A Union seal on a face: a black disc, a red ring and, on a freed one, the
## knife cut straight through it. There is no replacement mark.
func _seal(center: Vector3, yaw: float, radius: float, cut: bool) -> void:
	var basis: Basis = Basis.from_euler(Vector3(0.0, yaw, 0.0))
	var facing: Vector3 = Vector3(PI * 0.5, yaw, 0.0)
	_cylinder("seal_black", _mat("seal_black", UNION_BLACK), center + basis.z * 0.006, radius, 0.01, facing, 14)
	_cylinder("seal_red", _mat("union_band", UNION_RED), center + basis.z * 0.003, radius * 1.18, 0.01, facing, 14)
	_cylinder("seal_steel", _mat("seal_steel", Color("8d9092")), center + basis.z * 0.009, radius * 0.45, 0.01, facing, 10)
	if cut:
		_box("seal_cut", _mat("seal_cut", Color("c9c6be")), center + basis.z * 0.014, Vector3(radius * 2.9, 0.035, 0.01), Vector3(0.0, yaw, 0.85))

func _banner(center: Vector3, yaw: float, size: Vector2) -> void:
	var cloth: Material = _mat("banner_canvas", LEAGUE_CANVAS, PRODUCTION + "detail_yard_fabric.png")
	var ember: Material = _mat("banner_ember", LEAGUE_EMBER)
	var rust: Material = _mat("banner_rust", LEAGUE_RUST)
	var basis: Basis = Basis.from_euler(Vector3(0.0, yaw, 0.0))
	_box("banner_canvas", cloth, center + basis.z * 0.02, Vector3(size.x, size.y, 0.03), Vector3(0.0, yaw, 0.0))
	_box("banner_ember", ember, center + basis.z * 0.04 + Vector3(0.0, size.y * 0.32, 0.0), Vector3(size.x * 0.96, size.y * 0.12, 0.02), Vector3(0.0, yaw, 0.0))
	_box("banner_rust", rust, center + basis.z * 0.04, Vector3(size.x * 0.18, size.y * 0.5, 0.02), Vector3(0.0, yaw, 0.0))
	_box("banner_ember", ember, center + basis.z * 0.04 - Vector3(0.0, size.y * 0.32, 0.0), Vector3(size.x * 0.96, size.y * 0.06, 0.02), Vector3(0.0, yaw, 0.0))

## ---------------------------------------------------------------------------
## Canon dressing: the range that still runs, the Office's paper, free marks
## ---------------------------------------------------------------------------

## The range nobody decommissioned: an old brass plaque still waiting on a
## signature, and the motto plate the Office left, intact and unmocked.
func _range_still_runs() -> void:
	_sign("WORLD_LARAK_MOTTO", Vector3(-22.0, 6.55, -27.97), 0.0, Vector2(4.4, 0.7), Color("a7abad"), UNION_BLACK)
	_seal(Vector3(-24.7, 6.55, -27.965), 0.0, 0.26, false)
	_sign("WORLD_LARAK_NOT_COMPLIANT", Vector3(-24.0, 4.45, -27.97), 0.0, Vector2(2.6, 1.5), UNION_BLACK, Color("d8d0b4"))

## An approval plate on the first booth ground back to bare scarred metal.
## The Office's seal on each booth, cut through with a blade, is painted on
## the booth model's lane end.
func _office_paper() -> void:
	var bare: Material = _mat("plate_ground", Color("b9b5aa"), PRODUCTION + "union_steel.png")
	_box("plate_ground", bare, Vector3(-30.0, 4.4, -17.012), Vector3(0.7, 0.4, 0.01))
	var scratch: Material = _decal("decal_scratch", Color("ece8de"), 0.9)
	for i: int in range(4):
		_box("decal_scratch", scratch, Vector3(-30.0 + float(i) * 0.12 - 0.18, 4.4, -17.02), Vector3(0.5, 0.012, 0.005), Vector3(0.0, 0.0, 0.3 + float(i) * 0.25))
	# A Static Kids tag on the middle booth: the name with its vowels gone.
	_sign("WORLD_LARAK_TAG_STATIC", Vector3(-24.0, 3.75, -17.012), PI, Vector2(1.7, 0.5), TAG_MAGENTA)

## Free marks: six in a circle on three columns, each painted by somebody
## different, Article Seven crossed out on the Toll canopy, and the Gulf
## Breeze corner where two textures do not quite line up.
func _free_marks() -> void:
	_six(Vector3(-27.02, 2.7, 14.0), -PI * 0.5, 0.42, LEAGUE_CREAM)
	_six(Vector3(20.0, 2.6, 15.68), PI, 0.26, LEAGUE_EMBER)
	_sign("WORLD_LARAK_TAG_GRID", Vector3(-27.02, 2.6, 22.0), -PI * 0.5, Vector2(0.7, 0.5), Color("c8c4b8"))
	_sign("WORLD_LARAK_ARTICLE_7", Vector3(-23.0, 6.8, -9.98), 0.0, Vector2(2.6, 0.32), LEAGUE_CREAM)
	_box("paint_strike", _decal("paint_strike", SPRAY), Vector3(-23.0, 6.8, -9.97), Vector3(2.5, 0.06, 0.01), Vector3(0.0, 0.0, 0.08))
	# Gulf Breeze: a wall panel set 4 cm proud and a hand off true, with the
	# coordinates chalked beside it and the smallest six of the three.
	# Two tiles of the stairwell's own wall, a few centimetres proud and a
	# few degrees off true, with their grout lines showing the twist.
	var panel: Material = _mat("offset_panel", Color("5d6c66"))
	var grout: Material = _mat("offset_grout", Color("3f5a4f"))
	for tile: int in range(2):
		var z: float = -3.0 + float(tile) * 1.62
		var tilt: float = 0.05 + float(tile) * 0.035
		_box("offset_panel", panel, Vector3(29.95 - float(tile) * 0.02, 4.3, z), Vector3(0.04, 1.5, 1.5), Vector3(tilt, 0.0, 0.0))
		for edge: float in [-0.76, 0.76]:
			_box("offset_grout", grout, Vector3(29.925 - float(tile) * 0.02, 4.3, z) + Vector3(0.0, edge * cos(tilt), -edge * sin(tilt)), Vector3(0.02, 0.05, 1.56), Vector3(tilt, 0.0, 0.0))
			_box("offset_grout", grout, Vector3(29.925 - float(tile) * 0.02, 4.3, z) + Vector3(0.0, edge * sin(tilt), edge * cos(tilt)), Vector3(0.02, 1.56, 0.05), Vector3(tilt, 0.0, 0.0))
	_sign("WORLD_LARAK_TAG_COORDS", Vector3(29.9, 3.3, -2.2), -PI * 0.5, Vector2(2.2, 0.45), CHALK)
	_six(Vector3(29.9, 4.0, -0.3), -PI * 0.5, 0.18, CHALK)

## The numeral six inside a circle: legally nothing, the most illegal thing
## in the Perimeter.
func _six(center: Vector3, yaw: float, radius: float, ink: Color) -> void:
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = radius * 0.82
	torus.outer_radius = radius
	torus.rings = 20
	torus.ring_segments = 3
	ring.mesh = torus
	ring.material_override = _decal("paint_six_%s" % ink.to_html(false), ink)
	ring.position = center
	ring.rotation = Vector3(PI * 0.5, yaw, 0.0)
	ring.rotation_order = EULER_ORDER_YXZ
	ring.scale = Vector3(1.0, 0.04, 1.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_sign("WORLD_LARAK_SIX", center, yaw, Vector2(radius * 1.1, radius * 1.2), ink)

## AUNT LINDA'S TENT REVIVAL on level three: a nightly service where people
## and machines worship together. The canvas, the pulpit made from a dead pay
## machine, the hymn board, the chairs and the prayer card all sit flat to the
## north wall above the Spiral landing, so none of it reads as cover.
func _revival() -> void:
	var canvas: Material = _mat("revival_canvas", Color("b38f5a"), PRODUCTION + "detail_yard_fabric.png")
	var stripe: Material = _mat("revival_stripe", Color("8a3f2c"))
	_box("revival_canvas", canvas, Vector3(-3.0, 7.2, -26.8), Vector3(6.0, 0.08, 2.4), Vector3(-0.22, 0.0, 0.0))
	for i: int in range(4):
		_box("revival_stripe", stripe, Vector3(-5.25 + float(i) * 1.5, 7.21, -26.8), Vector3(0.5, 0.085, 2.42), Vector3(-0.22, 0.0, 0.0))
	_box("revival_canvas", canvas, Vector3(-3.0, 6.88, -25.65), Vector3(6.0, 0.56, 0.04))
	# The name is lettered on the awning's valance, where the whole Pit reads
	# it under the bulbs, rather than on the wall the awning hides.
	_sign("WORLD_LARAK_REVIVAL", Vector3(-3.0, 6.88, -25.62), 0.0, Vector2(5.8, 0.5), Color("f2dfa6"), Color("4a2a3a"))
	var bulb: Material = _mat("bulb", Color("ffd9a0"), "", 2.4)
	for i: int in range(9):
		_box("bulb", bulb, Vector3(-6.0 + float(i) * 0.75, 7.55 - absf(float(i) - 4.0) * 0.06, -25.62), Vector3(0.1, 0.1, 0.1))
	# The pulpit: a dead pay machine, Larak's signature still on it, the hand
	# bell on top and a network cable over it for a stole.
	_pay_machine(Vector3(-3.0, LEVEL_3, -28.0), false)
	var brass: Material = _mat("bell_brass", Color("a07a34"), "", 0.0)
	_cylinder("bell_brass", brass, Vector3(-3.1, LEVEL_3 + 1.7, -27.82), 0.09, 0.16, Vector3.ZERO, 10)
	_box("bell_brass", brass, Vector3(-3.1, LEVEL_3 + 1.83, -27.82), Vector3(0.03, 0.12, 0.03))
	var stole: Material = _mat("stole_cable", Color("d4b13c"))
	var front: float = -28.0 + PAY_DEPTH - WALL_INSET + 0.02
	_box("stole_cable", stole, Vector3(-2.66, LEVEL_3 + 1.25, front), Vector3(0.04, 0.75, 0.03), Vector3(0.0, 0.0, 0.08))
	_box("stole_cable", stole, Vector3(-2.8, LEVEL_3 + 1.62, front - 0.13), Vector3(0.3, 0.04, 0.22))
	# The hymn board and the prayer card, pinned beside it.
	_sign("WORLD_LARAK_HYMNS", Vector3(-5.1, 5.75, -27.97), 0.0, Vector2(1.5, 1.7), LEAGUE_CREAM, Color("3a2a1e"))
	_sign("WORLD_LARAK_PRAYER", Vector3(-1.3, 5.95, -27.965), 0.0, Vector2(0.62, 0.42), Color("2a2420"), Color("e6dcc0"))
	# Folding chairs hung flat on the wall, and a crate of fish oil on a
	# shelf above them, all over head height.
	var chair: Material = _mat("revival_chair", Color("5d625e"), EARTH + "earth_workshop_patched_steel.png")
	for i: int in range(4):
		var x: float = -0.4 + float(i) * 0.12
		_box("revival_chair", chair, Vector3(x - 0.2, 6.75, -27.94 + float(i) * 0.02), Vector3(0.44, 0.78, 0.02))
	_box("crate", _mat("crate", Color("6b5236")), Vector3(-5.2, 6.98, -27.8), Vector3(0.7, 0.32, 0.36))
	_box("shelf", _mat("shelf", Color("3e3328")), Vector3(-5.2, 6.8, -27.82), Vector3(0.9, 0.04, 0.4))
	_sign("WORLD_LARAK_FISH_OIL", Vector3(-5.2, 6.98, -27.615), 0.0, Vector2(0.6, 0.18), Color("e8dcb8"))

## The bell at the Stands: a scavenged school bell on a bracket off the
## viaduct wall with its pull rope, over head height. Everything stops for
## it between rounds; today it hangs as a prop. And the podium: three
## stacked pallets on the bookmaker's roof, where the whole lot can see them.
func _bell_and_podium() -> void:
	# The brass bell on its iron bracket, 1.7 m out from the viaduct wall,
	# its rope ending well over the bettors' heads.
	_prop("stands_bell", Vector3(-9.3, BELL_TOP - BELL_SIZE.y, 28.0 - BELL_SIZE.x * 0.5), PI)
	var pallet: Material = _mat("pallet", Color("8a6f4c"))
	for step: int in range(3):
		var x: float = [-1.3, 0.0, 1.3][step]
		var stack: int = [2, 3, 1][step]
		for level: int in range(stack):
			_box("pallet", pallet, Vector3(x, PODIUM_BASE + 0.06 + float(level) * 0.14, 17.4), Vector3(1.1, 0.12, 0.9))
		_sign("WORLD_LARAK_PODIUM_%d" % [2, 1, 3][step], Vector3(x, PODIUM_BASE + 0.04 + float(stack) * 0.07, 16.94), PI, Vector2(0.4, 0.13 * float(stack)), LEAGUE_CREAM)

func _roof() -> void:
	# Sodium mast heads: one carries the Roof's raking light.
	var sodium: Material = _mat("lamp_sodium", SODIUM, "", 3.0)
	var steel: Material = _mat("mast_steel", Color("3e4140"))
	for at: Vector2 in [Vector2(12.0, -26.5), Vector2(35.0, -19.0)]:
		_box("mast_steel", steel, Vector3(at.x, 12.1, at.y), Vector3(1.4, 0.18, 0.5))
		_box("lamp_sodium", sodium, Vector3(at.x, 11.98, at.y), Vector3(1.2, 0.08, 0.36))
	var mast: OmniLight3D = OmniLight3D.new()
	mast.name = "RoofMast"
	mast.position = Vector3(35.0, 11.4, -19.0)
	mast.light_color = SODIUM
	mast.light_energy = 6.5
	mast.omni_range = 30.0
	mast.omni_attenuation = 1.1
	mast.shadow_enabled = true
	mast.add_to_group(ArenaSky.PRACTICAL_GROUP)
	add_child(mast)
	_sign("WORLD_LARAK_ROOF", Vector3(9.0, ROOF + 0.03, -22.0), 0.0, Vector2(5.0, 1.6), Color("e2dccb"))
	_sign("WORLD_LARAK_VALET", Vector3(31.0, ROOF + 0.03, -18.8), 0.0, Vector2(2.4, 0.6), HAZARD_YELLOW)
	# Lay the two floor stencils flat.
	for child: Node in get_children():
		if child is WorldSign and (child as WorldSign).message_key in ["WORLD_LARAK_ROOF", "WORLD_LARAK_VALET", "WORLD_LARAK_PIT"]:
			(child as Node3D).rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	# Hazard paint on the valet barriers.
	var stripe: Material = _mat("barrier_stripe", HAZARD_YELLOW)
	_box("barrier_stripe", stripe, Vector3(25.5, 7.05, -25.0), Vector3(1.02, 0.18, 4.02))
	_box("barrier_stripe", stripe, Vector3(25.5, 7.05, -18.5), Vector3(1.02, 0.18, 5.02))
	_box("barrier_stripe", stripe, Vector3(29.0, 7.05, -16.5), Vector3(6.02, 0.18, 1.02))

## ---------------------------------------------------------------------------
## Landmarks
## ---------------------------------------------------------------------------

## THE REPOSSESSION: a Union Compliance cruiser hung nose-down from a tower
## crane hook over the Pit, wrapped in a league banner, lit from below by the
## work floods on the hook. Union issue: a black body, dark steel plates one
## step lighter, a narrow deep-red band and one seal, cut through by the
## league. The light bar is re-lensed in league amber. The crane mast stands
## outside the north-east corner; its jib crosses the Roof.
func _repossession() -> void:
	if not _replace(-1.0, -0.9, 1.0, 0.9, 14.5):
		return
	_cruiser = Node3D.new()
	_cruiser.name = "Repossession"
	_cruiser.position = Vector3(0.0, 12.25, 0.0)
	add_child(_cruiser)
	var hung: Node3D = Node3D.new()
	hung.rotation = Vector3(0.0, 0.0, -PI * 0.5)
	hung.position = Vector3(0.0, 0.0, 0.0)
	_cruiser.add_child(hung)
	# Build the car in its own frame (length on x), centred, then hang it.
	var car: Node3D = Node3D.new()
	car.position = Vector3(0.0, -0.7, 0.0)
	hung.add_child(car)
	var body: Material = _mat("car_union", UNION_BLACK)
	var glass: Material = _mat("car_glass", Color("15191c"))
	var band: Material = _mat("union_band", UNION_RED)
	var plate: Material = _mat("union_plate", UNION_STEEL, PRODUCTION + "union_steel.png")
	_part(car, body, Vector3(0.0, 0.5, 0.0), Vector3(4.4, 0.55, 1.8))
	_part(car, body, Vector3(-0.15, 1.05, 0.0), Vector3(2.3, 0.55, 1.6))
	_part(car, glass, Vector3(-0.15, 1.07, 0.0), Vector3(2.1, 0.4, 1.64))
	_part(car, band, Vector3(0.0, 0.72, 0.0), Vector3(4.41, 0.06, 1.81))
	# Issued door plates, one step lighter than the body, and a seal on each
	# front door with the league's knife cut through it.
	_part(car, plate, Vector3(0.25, 0.46, 0.0), Vector3(1.9, 0.34, 1.83))
	for side: float in [-1.0, 1.0]:
		var seal: MeshInstance3D = _part(car, _mat("seal_black", UNION_BLACK), Vector3(0.75, 0.46, side * 0.92), Vector3(0.3, 0.3, 0.02))
		seal.rotation.z = PI * 0.25
		_part(car, band, Vector3(0.75, 0.46, side * 0.925), Vector3(0.16, 0.16, 0.02))
		var cut: MeshInstance3D = _part(car, _mat("seal_cut", Color("c9c6be")), Vector3(0.75, 0.46, side * 0.935), Vector3(0.52, 0.035, 0.02))
		cut.rotation.z = 0.7
	_part(car, _mat("chrome", Color("9a9c9a")), Vector3(2.21, 0.35, 0.0), Vector3(0.08, 0.2, 1.84))
	_part(car, _mat("chrome", Color("9a9c9a")), Vector3(-2.21, 0.35, 0.0), Vector3(0.08, 0.2, 1.84))
	for fx: float in [-1.4, 1.4]:
		for fz: float in [-0.8, 0.8]:
			_part(car, _mat("tyre", Color("151515")), Vector3(fx, 0.25, fz), Vector3(0.7, 0.7, 0.22))
	# League banner wrapped round the boot.
	_part(car, _mat("banner_canvas", LEAGUE_CANVAS, PRODUCTION + "detail_yard_fabric.png"), Vector3(-1.75, 0.7, 0.0), Vector3(0.9, 1.0, 1.84))
	_part(car, _mat("banner_ember", LEAGUE_EMBER), Vector3(-1.75, 0.7, 0.0), Vector3(0.25, 1.02, 1.86))
	# The light bar, both lenses swapped for league amber.
	var lens: StandardMaterial3D = _mat("bar_amber", LEAGUE_AMBER, "", 1.6).duplicate() as StandardMaterial3D
	_bar_lens = _part(car, lens, Vector3(-0.15, 1.38, 0.0), Vector3(0.3, 0.12, 1.3))
	_light_bar = OmniLight3D.new()
	_light_bar.name = "LightBar"
	_light_bar.light_color = LEAGUE_AMBER
	_light_bar.position = Vector3(-0.15, 1.6, 0.0)
	_light_bar.light_energy = 1.2
	_light_bar.omni_range = 9.0
	_light_bar.omni_attenuation = 1.6
	_light_bar.shadow_enabled = false
	car.add_child(_light_bar)
	# The hook block with its sheaves and forged hook, the chains, and the
	# work lamps lit in the block's own housings.
	var iron: Material = _mat("hook_iron", Color("2f2c2a"))
	_prop("crane_hook", Vector3(0.0, HOOK_TOP - HOOK_HEIGHT, 0.0), 0.0, _cruiser)
	for corner: Vector2 in [Vector2(0.75, 0.7), Vector2(-0.75, 0.7), Vector2(0.75, -0.7), Vector2(-0.75, -0.7)]:
		var chain: MeshInstance3D = _part(_cruiser, iron, Vector3(corner.x * 0.5, 2.4, corner.y * 0.5), Vector3(0.05, 0.75, 0.05))
		chain.rotation = Vector3(corner.y * 0.5, 0.0, -corner.x * 0.5)
	var work: Material = _mat("work_light", WORK_WHITE, "", 5.0)
	for lamp: Vector3 in HOOK_LAMPS:
		for side: float in [-1.0, 1.0]:
			_part(_cruiser, work, Vector3(side * lamp.x, HOOK_TOP - HOOK_HEIGHT + lamp.y, lamp.z), Vector3(0.03, 0.1, 0.16))
	var flood: SpotLight3D = SpotLight3D.new()
	flood.name = "PitFlood"
	flood.position = Vector3(0.0, 3.0, 0.0)
	flood.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	flood.light_color = WORK_WHITE
	flood.light_energy = 7.0
	flood.spot_range = 24.0
	flood.spot_angle = 42.0
	flood.spot_attenuation = 0.9
	flood.shadow_enabled = true
	flood.add_to_group(ArenaSky.PRACTICAL_GROUP)
	_cruiser.add_child(flood)
	# Cable up to the trolley, and the crane itself.
	var cable: Material = _mat("cable", Color("1c1c1e"))
	_box("cable", cable, Vector3(0.0, 22.0, 0.0), Vector3(0.07, 12.0, 0.07))
	_crane(cable)

func _crane(cable: Material) -> void:
	var paint: Material = _mat("crane_yellow", Color("b9902e"), EARTH + "earth_workshop_patched_steel.png")
	var mast_at: Vector3 = Vector3(47.0, 0.0, -46.0)
	var height: float = 30.0
	for corner: Vector2 in [Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(-0.8, 0.8), Vector2(0.8, 0.8)]:
		_box("crane_yellow", paint, mast_at + Vector3(corner.x, height * 0.5, corner.y), Vector3(0.22, height, 0.22))
	for i: int in range(10):
		var y: float = 1.5 + float(i) * 3.0
		_box("crane_yellow", paint, mast_at + Vector3(0.0, y, -0.8), Vector3(1.6, 0.12, 0.12), Vector3(0.0, 0.0, 0.9 if i % 2 == 0 else -0.9))
		_box("crane_yellow", paint, mast_at + Vector3(-0.8, y, 0.0), Vector3(0.12, 0.12, 1.6), Vector3(0.9 if i % 2 == 0 else -0.9, 0.0, 0.0))
	# The jib: from the mast top over the Pit and a little past it.
	var top: Vector3 = mast_at + Vector3(0.0, height + 1.0, 0.0)
	var tip: Vector3 = Vector3(-6.0, height + 1.0, 6.0)
	var along: Vector3 = tip - top
	var yaw: float = atan2(-along.z, along.x)
	var length: float = along.length()
	var mid: Vector3 = (top + tip) * 0.5
	for offset: float in [-0.6, 0.6]:
		var side: Vector3 = Vector3(along.z, 0.0, -along.x).normalized() * offset
		_box("crane_yellow", paint, mid + side, Vector3(length, 0.2, 0.2), Vector3(0.0, yaw, 0.0))
	_box("crane_yellow", paint, mid + Vector3(0.0, 1.3, 0.0), Vector3(length, 0.18, 0.18), Vector3(0.0, yaw, 0.0))
	var steps: int = int(length / 3.0)
	for i: int in range(steps):
		var at: Vector3 = top + along * (float(i) + 0.5) / float(steps)
		_box("crane_yellow", paint, at + Vector3(0.0, 0.65, 0.0), Vector3(0.12, 1.4, 0.12), Vector3(0.0, yaw, 0.6 if i % 2 == 0 else -0.6))
	# Counter-jib with its concrete weights, the cab and an aviation lamp.
	var back: Vector3 = top - along.normalized() * 14.0
	_box("crane_yellow", paint, (top + back) * 0.5, Vector3(14.0, 0.3, 1.4), Vector3(0.0, yaw, 0.0))
	_box("crane_weight", _mat("crane_weight", Color("6d6a62"), PRODUCTION + "yard_concrete.png"), back + Vector3(0.0, -1.2, 0.0), Vector3(3.0, 2.4, 2.0), Vector3(0.0, yaw, 0.0))
	_box("crane_cab", _mat("crane_cab", Color("c49a3a")), top + Vector3(0.0, -1.6, 0.0) + along.normalized() * 1.6, Vector3(2.2, 2.0, 2.0), Vector3(0.0, yaw, 0.0))
	_box("lamp_red", _mat("aviation", Color("ff3022"), "", 6.0), top + Vector3(0.0, 3.2, 0.0), Vector3(0.3, 0.3, 0.3))
	_box("crane_yellow", paint, top + Vector3(0.0, 1.6, 0.0), Vector3(0.3, 3.2, 0.3))
	# The trolley above the hook.
	_box("crane_cab", _mat("crane_cab", Color("c49a3a")), Vector3(0.0, height + 0.6, 0.0), Vector3(1.2, 0.6, 1.4))

## THE LARAK SIGN: a vertical blade on the east wall band behind the valet
## circle. Sodium-orange neon spells the procurement officer's name; the K
## has a bad transformer. Under it, the lot's LEVEL FULL board, re-lettered
## with the night's debts. League extension cables run up to it from the
## stairwell: the facility's supply was never cut, and the bill goes to a
## site with no name.
func _larak_sign() -> void:
	var frame: Material = _mat("sign_frame", Color("2a2624"), PRODUCTION + "scrap_steel.png")
	_box("sign_frame", frame, Vector3(37.0, 13.7, -20.0), Vector3(0.5, 12.2, 5.0))
	var tube_back: Material = _mat("sign_back", Color("3c1a12"))
	_box("sign_back", tube_back, Vector3(36.74, 13.7, -20.0), Vector3(0.02, 11.8, 4.6))
	# A border of bulbs, so the blade reads from the far corner of the lot.
	var bulb: Material = _mat("sign_bulb", Color("ffd08a"), "", 3.5)
	for i: int in range(24):
		var y: float = 8.0 + float(i) * 0.48
		_box("sign_bulb", bulb, Vector3(36.7, y, -22.25), Vector3(0.08, 0.16, 0.16))
		_box("sign_bulb", bulb, Vector3(36.7, y, -17.75), Vector3(0.08, 0.16, 0.16))
	for i: int in range(10):
		var z: float = -22.25 + float(i) * 0.5
		_box("sign_bulb", bulb, Vector3(36.7, 19.55, z), Vector3(0.08, 0.16, 0.16))
		_box("sign_bulb", bulb, Vector3(36.7, 7.85, z), Vector3(0.08, 0.16, 0.16))
	var letters: String = WorldSign.localized("WORLD_LARAK_NEON")
	if letters.is_empty():
		letters = "LARAK"
	for i: int in range(mini(letters.length(), 5)):
		var label: Label3D = Label3D.new()
		label.name = "Neon%d" % i
		label.text = letters[i]
		label.font = FONT
		label.font_size = 64
		label.pixel_size = 0.036
		label.outline_size = 0
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		label.double_sided = false
		label.modulate = Color(NEON.r * 3.0, NEON.g * 2.4, NEON.b * 2.0, 1.0)
		label.position = Vector3(36.72, 17.9 - float(i) * 2.2, -20.0)
		label.rotation.y = -PI * 0.5
		add_child(label)
		_neon_letters.append(label)
	# The dead tube: the second A burns at half.
	if _neon_letters.size() > 3:
		_neon_letters[3].modulate = Color(NEON.r * 1.2, NEON.g * 0.8, NEON.b * 0.7, 1.0)
	_neon_light = OmniLight3D.new()
	_neon_light.name = "LarakNeon"
	_neon_light.position = Vector3(35.0, 13.0, -20.0)
	_neon_light.light_color = NEON
	_neon_light.light_energy = 2.6
	_neon_light.omni_range = 20.0
	_neon_light.omni_attenuation = 1.3
	_neon_light.shadow_enabled = false
	add_child(_neon_light)
	_sign("WORLD_LARAK_LEVEL_FULL", Vector3(35.98, 6.85, -20.0), -PI * 0.5, Vector2(3.8, 1.3), Color("e9e2c8"), Color("1d3328"))
	var cable: Material = _mat("cable", Color("1c1c1e"))
	for i: int in range(3):
		var a: Vector3 = Vector3(31.0, 7.7, -9.5)
		var b: Vector3 = Vector3(36.6, 9.0 + float(i) * 0.9, -18.4)
		var sag: Vector3 = (a + b) * 0.5 + Vector3(0.0, -0.9 - float(i) * 0.2, 0.0)
		_stretch(cable, a, sag, 0.04)
		_stretch(cable, sag, b, 0.04)

func _stretch(material: Material, a: Vector3, b: Vector3, thickness: float) -> void:
	var along: Vector3 = b - a
	var length: float = along.length()
	if length < 0.01:
		return
	var basis: Basis = Basis.looking_at(along.normalized(), Vector3.UP if absf(along.normalized().y) < 0.99 else Vector3.RIGHT)
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(thickness, thickness, length)
	if not _batches.has("cable"):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches["cable"] = tool
		_batch_materials["cable"] = material
	_batches["cable"].append_from(mesh, 0, Transform3D(basis, (a + b) * 0.5))

## The office block over the north wall: dark, except that its corridor
## lights come on a floor at a time as if following somebody up the stairs.
## Emissive panes only, in front of the backdrop's dark facade.
func _office_block() -> void:
	var lit: Material = _mat("office_lit", Color("f2d7a0"), "", 2.0)
	for row: int in range(5):
		for pane: int in range(3):
			var node: MeshInstance3D = _part(self, lit, Vector3(-36.0 + float(row + pane) * 3.4, 11.5 + float(row) * 3.0, -38.92), Vector3(1.4, 1.1, 0.04))
			node.set_meta("floor", row)
			node.visible = false
			_office_windows.append(node)

## The Plate was claimed: the light bar flares once, warm.
func plate_claimed() -> void:
	_plate_flare = 1.2

## ---------------------------------------------------------------------------
## The pad kit
## ---------------------------------------------------------------------------

## A pickup asks what its pad stands on (WeaponPickup's stage group). The
## first ask builds the pad's kit at the floor the server put it on, so the
## kit follows the server's pads rather than a second copy of their table:
## the Rocket's cradle exists only where the Rocket is laid. Returns the
## seat's height over that floor.
func stage_pickup(id: String, kind: String, _weapon: String, floor_at: Vector3) -> float:
	if _staged_pads.has(id):
		return _staged_pads[id]
	var seat: float = {RAIL_ID: RAIL_DAIS, PLATE_ID: PLATE_PEDESTAL, ROCKET_ID: ROCKET_CRADLE}.get(id, 0.0)
	var power: bool = seat > 0.0
	var kit: Node3D = Node3D.new()
	kit.name = "Pad_" + id.validate_node_name()
	kit.position = to_local(floor_at)
	add_child(kit)
	var marks: SurfaceTool = SurfaceTool.new()
	marks.begin(Mesh.PRIMITIVE_TRIANGLES)
	match id:
		RAIL_ID:
			_rail_dais(kit)
			_atlas("scorch_1", Vector3(1.1, 0.008, 0.7), 0.6, Vector3.UP, marks)
		PLATE_ID:
			_plate_pedestal(kit)
		ROCKET_ID:
			_atlas("scorch_pad", Vector3(0.0, 0.008, 0.0), 0.3, Vector3.UP, marks)
			_rocket_cradle(kit)
		_:
			if kind == "weapon":
				_atlas("scorch_1", Vector3(-0.9, 0.008, 0.55), float(id.length()), Vector3.UP, marks)
	_pad_ring(kit, seat)
	_pad_pool(kit, seat, power)
	var drawn: MeshInstance3D = _flush_atlas(marks, "PadMarks")
	if drawn != null:
		drawn.reparent(kit, false)
	_staged_pads[id] = seat
	return seat

## The recessed ring every pad sits in: a dark well inside a worn steel lip,
## with a thin warm lamp strip round the well.
func _pad_ring(kit: Node3D, seat: float) -> void:
	var well: MeshInstance3D = MeshInstance3D.new()
	well.name = "Well"
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = PAD_RING_RADIUS - 0.12
	disc.bottom_radius = PAD_RING_RADIUS - 0.12
	disc.height = 0.01
	disc.radial_segments = 24
	disc.rings = 1
	well.mesh = disc
	well.position = Vector3(0.0, seat + 0.004, 0.0)
	well.material_override = _mat("pad_well", Color("24221f"))
	well.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.add_child(well)
	var lip: MeshInstance3D = _flat_ring("Lip", PAD_RING_RADIUS - 0.12, PAD_RING_RADIUS, seat + 0.008, ArenaMaterials.larak_class("ramp"))
	kit.add_child(lip)
	var lamp: MeshInstance3D = _flat_ring("Lamp", PAD_RING_RADIUS - 0.17, PAD_RING_RADIUS - 0.13, seat + 0.009, _mat("pad_lamp", Color("ffc67a"), "", 1.1))
	kit.add_child(lamp)

## A flat annulus on a floor, one texel proud.
func _flat_ring(node_name: String, inner: float, outer: float, y: float, material: Material) -> MeshInstance3D:
	var ring: MeshInstance3D = MeshInstance3D.new()
	ring.name = node_name
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 32
	torus.ring_segments = 4
	ring.mesh = torus
	# The torus's tube is as tall as it is wide; flatten it to a 12 mm lip.
	ring.scale = Vector3(1.0, 0.012 / maxf(outer - inner, 0.01), 1.0)
	ring.position = Vector3(0.0, y, 0.0)
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring

static var _pool_texture: Texture2D

## The light pool round a pad: warm light laid on the deck in stepped rings,
## additive, so the floor under it brightens rather than being painted over.
## No light node: the venue's light budget stays with its fixtures.
func _pad_pool(kit: Node3D, seat: float, power: bool) -> void:
	if _pool_texture == null:
		var image: Image = Image.create(POOL_PIXELS, POOL_PIXELS, false, Image.FORMAT_RGBA8)
		var half: float = float(POOL_PIXELS) * 0.5
		for y: int in range(POOL_PIXELS):
			for x: int in range(POOL_PIXELS):
				var d: float = Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half).length() / half
				var alpha: float = 0.0 if d >= 1.0 else floorf((1.0 - d) * 4.0 + 0.6) / 4.0
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
		_pool_texture = ImageTexture.create_from_image(image)
	var key: String = "pad_pool_power" if power else "pad_pool"
	if not _materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_texture = _pool_texture
		material.albedo_color = Color(POOL_POWER if power else POOL_WARM, 0.26 if power else 0.16)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_materials[key] = material
	var pool: MeshInstance3D = MeshInstance3D.new()
	pool.name = "Pool"
	var quad: PlaneMesh = PlaneMesh.new()
	quad.size = Vector2.ONE * float(POOL_PIXELS) / ArenaMaterials.TEXELS_PER_METRE
	pool.mesh = quad
	pool.position = Vector3(0.0, maxf(seat, 0.0) + 0.014, 0.0)
	pool.material_override = _materials[key]
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.add_child(pool)

## The Rail's dais at the foot of the Low Ramp: a low octagon of tread plate
## with a hazard lip, the one gun in the lot that gets a stage.
func _rail_dais(kit: Node3D) -> void:
	var dais: MeshInstance3D = MeshInstance3D.new()
	dais.name = "Dais"
	var octagon: CylinderMesh = CylinderMesh.new()
	octagon.top_radius = 1.05
	octagon.bottom_radius = 1.1
	octagon.height = RAIL_DAIS
	octagon.radial_segments = 8
	octagon.rings = 1
	dais.mesh = octagon
	dais.position = Vector3(0.0, RAIL_DAIS * 0.5, 0.0)
	dais.rotation.y = PI / 8.0
	dais.material_override = ArenaMaterials.larak_class("ramp")
	kit.add_child(dais)
	kit.add_child(_flat_ring("HazardLip", 0.95, 1.05, RAIL_DAIS + 0.002, _decal("paint_hazard", HAZARD_YELLOW)))

## The Plate's pedestal in the valet circle: a steel road plate the league
## dropped on two sleepers, its edges sprayed in league ember.
func _plate_pedestal(kit: Node3D) -> void:
	var sleeper: Material = _mat("pedestal_sleeper", Color("4b3b2c"))
	for side: float in [-0.45, 0.45]:
		var block: MeshInstance3D = _part(kit, sleeper, Vector3(side, (PLATE_PEDESTAL - 0.04) * 0.5, 0.0), Vector3(0.24, PLATE_PEDESTAL - 0.04, 1.3))
		block.name = "Sleeper"
	var plate: MeshInstance3D = _part(kit, ArenaMaterials.larak_class("ramp"), Vector3(0.0, PLATE_PEDESTAL - 0.02, 0.0), Vector3(1.4, 0.04, 1.4))
	plate.name = "RoadPlate"
	var ember: Material = _decal("paint_ember", LEAGUE_EMBER)
	for edge: Vector3 in [Vector3(0.0, 0.0, 0.66), Vector3(0.0, 0.0, -0.66)]:
		var spray: MeshInstance3D = _part(kit, ember, edge + Vector3(0.0, PLATE_PEDESTAL + 0.002, 0.0), Vector3(1.3, 0.004, 0.06))
		spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## The Rocket's cradle behind the Stack: a scorched steel blast tub, the rim
## at shin height, the launcher seated on its floor.
func _rocket_cradle(kit: Node3D) -> void:
	var rim: MeshInstance3D = MeshInstance3D.new()
	rim.name = "Rim"
	var tube: CylinderMesh = CylinderMesh.new()
	tube.top_radius = 1.0
	tube.bottom_radius = 1.06
	tube.height = 0.16
	tube.radial_segments = 12
	tube.rings = 1
	tube.cap_top = false
	tube.cap_bottom = false
	rim.mesh = tube
	rim.position = Vector3(0.0, 0.08, 0.0)
	var steel: Material = ArenaMaterials.larak_class("ramp")
	rim.material_override = steel
	kit.add_child(rim)
	var floor_plate: MeshInstance3D = MeshInstance3D.new()
	floor_plate.name = "TubFloor"
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = ROCKET_CRADLE
	disc.radial_segments = 12
	disc.rings = 1
	floor_plate.mesh = disc
	floor_plate.position = Vector3(0.0, ROCKET_CRADLE * 0.5, 0.0)
	floor_plate.material_override = _mat("cradle_floor", Color("2c2a28"))
	kit.add_child(floor_plate)
	kit.add_child(_flat_ring("RimLip", 0.98, 1.08, 0.165, _decal("paint_hazard", HAZARD_YELLOW)))

## A transit train on the viaduct beyond the Stands: four lit carriages that
## sweep past every half minute. Emissive only; it spends no light budget.
func _transit() -> void:
	_train = Node3D.new()
	_train.name = "Transit"
	_train.position = Vector3(-120.0, 14.7, 47.0)
	_train.visible = false
	add_child(_train)
	var shell: Material = _mat("train_shell", Color("3c4146"))
	var window: Material = _mat("train_window", Color("f3d79a"), "", 2.2)
	for car: int in range(4):
		var x: float = float(car) * -13.5
		_part(_train, shell, Vector3(x, 1.5, 0.0), Vector3(13.0, 3.0, 3.0))
		for pane: int in range(6):
			_part(_train, window, Vector3(x - 5.0 + float(pane) * 2.0, 1.9, -1.52), Vector3(1.3, 0.8, 0.04))

## Painted level numbers, three metres tall, in each quarter's colour.
func _level_numbers() -> void:
	_sign("WORLD_LARAK_LEVEL_1", Vector3(-35.97, 3.4, 9.0), PI * 0.5, Vector2(2.0, 3.0), Color("6fa58a"))
	_sign("WORLD_LARAK_LEVEL_2", Vector3(-27.0, 5.8, -27.97), 0.0, Vector2(2.0, 3.0), Color("d0a24a"))
	_sign("WORLD_LARAK_LEVEL_3", Vector3(2.5, 7.6, -27.97), 0.0, Vector2(1.6, 2.4), Color("8a9ec9"))
	_sign("WORLD_LARAK_LEVEL_1", Vector3(35.97, 3.4, 14.0), -PI * 0.5, Vector2(2.0, 3.0), Color("6fa58a"))
	_sign("WORLD_LARAK_LEVEL_1", Vector3(6.0, 3.4, 27.97), PI, Vector2(2.0, 3.0), Color("6fa58a"))

## The bettors' front rows on the Stands: car seats bolted to a concrete
## kerb, facing the Pit, with a steel rail along their backs. Each row fills
## its own collision box, so a shot stops where the seats are.
func _stands_rows() -> void:
	var kerb: Material = ArenaMaterials.larak_class("kerb")
	if kerb == null:
		kerb = _mat("kerb", Color("8a857b"), PRODUCTION + "yard_concrete.png")
	var rail: Material = _mat("seat_rail", Color("4b4f4c"), EARTH + "earth_workshop_patched_steel.png")
	var fabrics: Array[Color] = [Color("5a2a26"), Color("3b3d42"), Color("7a6448"), Color("2f3a34"), Color("6b2f2a")]
	for center_x: float in [-6.5, 6.5]:
		if not _replace(center_x - 2.5, 12.6, center_x + 2.5, 13.4, LEVEL_1 + 0.9):
			continue
		_box("kerb", kerb, Vector3(center_x, LEVEL_1 + 0.2, 13.0), Vector3(5.0, 0.4, 0.8))
		for i: int in range(6):
			var x: float = center_x - 2.08 + float(i) * 0.83
			var key: String = "seat_%d" % ((i + int(center_x)) % fabrics.size() + fabrics.size())
			var fabric: Material = _mat(key, fabrics[(i + int(absf(center_x))) % fabrics.size()], PRODUCTION + "detail_yard_fabric.png")
			_box(key, fabric, Vector3(x, LEVEL_1 + 0.5, 12.95), Vector3(0.74, 0.2, 0.7))
			_box(key, fabric, Vector3(x, LEVEL_1 + 0.68, 13.24), Vector3(0.74, 0.44, 0.14), Vector3(-0.12, 0.0, 0.0))
			_box(key, fabric, Vector3(x, LEVEL_1 + 0.86, 13.28), Vector3(0.4, 0.12, 0.1))
		_box("seat_rail", rail, Vector3(center_x, LEVEL_1 + 0.88, 13.36), Vector3(5.0, 0.06, 0.06))
		for post: float in [-2.45, 0.0, 2.45]:
			_box("seat_rail", rail, Vector3(center_x + post, LEVEL_1 + 0.62, 13.36), Vector3(0.06, 0.5, 0.06))

## Painted level numbers flat on the decks, the size a driver reads through a
## windscreen: wayfinding on floors that would otherwise be one flat colour.
func _floor_stencils() -> void:
	var worn: float = 0.85
	_floor_sign("WORLD_LARAK_LEVEL_1", Vector3(-31.0, LEVEL_1, 6.5), 0.0, Vector2(3.0, 4.2), Color(0.44, 0.65, 0.54, worn))
	_floor_sign("WORLD_LARAK_LEVEL_1", Vector3(-4.5, LEVEL_1, 20.5), 0.0, Vector2(3.0, 4.2), Color(0.44, 0.65, 0.54, worn))
	_floor_sign("WORLD_LARAK_LEVEL_1", Vector3(18.0, LEVEL_1, 5.0), -PI * 0.5, Vector2(3.0, 4.2), Color(0.44, 0.65, 0.54, worn))
	_floor_sign("WORLD_LARAK_LEVEL_2", Vector3(-30.0, LEVEL_2, -23.0), 0.0, Vector2(3.0, 4.2), Color(0.82, 0.64, 0.29, worn))
	_floor_sign("WORLD_LARAK_LEVEL_2", Vector3(20.0, LEVEL_2, -5.0), -PI * 0.5, Vector2(2.6, 3.6), Color(0.82, 0.64, 0.29, worn))
	_floor_sign("WORLD_LARAK_LEVEL_3", Vector3(4.0, LEVEL_3, -15.5), PI, Vector2(3.0, 4.2), Color(0.54, 0.62, 0.79, worn))
	# The league paints over the Union's wayfinding with its own instructions.
	_floor_sign("WORLD_LARAK_STENCIL_SETTLE", Vector3(-16.0, LEVEL_1, 22.0), PI * 0.5, Vector2(4.6, 1.2), Color(0.85, 0.45, 0.17, 0.8))
	_floor_sign("WORLD_LARAK_STENCIL_SETTLE", Vector3(27.0, LEVEL_1, 14.5), 0.0, Vector2(4.6, 1.2), Color(0.85, 0.45, 0.17, 0.8))
	_floor_sign("WORLD_LARAK_STENCIL_NO_PARKING", Vector3(-22.0, LEVEL_2, -6.5), 0.0, Vector2(4.4, 1.0), Color(0.85, 0.81, 0.62, 0.7))

func _floor_sign(key: String, center: Vector3, yaw: float, size: Vector2, ink: Color) -> void:
	# Coloured lane bars reinforce each deck without another reading stop.
	var paint: Material = _decal("paint_route_" + key, ink)
	_floor_mark("paint_route_" + key, paint, center.x, center.z,
		center.y + 0.022, size.x, minf(size.y, 0.16), yaw)

## Water, tyres and paper: the Pit's standing puddles under the floods, skid
## marks where cars were driven in anger, and betting slips blown across the
## Stands and into the Pit. All paint, deterministic so every client agrees.
func _wet_and_worn() -> void:
	var puddle: StandardMaterial3D = StandardMaterial3D.new()
	puddle.albedo_color = Color(0.1, 0.1, 0.11, 0.42)
	puddle.roughness = 0.12
	puddle.metallic = 0.15
	puddle.metallic_specular = 0.8
	puddle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_materials["decal_puddle"] = puddle
	for pool: Vector4 in [Vector4(-3.0, 2.5, 3.2, 2.0), Vector4(-1.8, 3.4, 1.6, 1.4), Vector4(5.0, -6.5, 2.6, 1.8),
			Vector4(-4.5, -3.0, 1.4, 2.6), Vector4(1.5, 4.8, 3.0, 1.0), Vector4(-13.0, 5.5, 2.2, 3.0),
			Vector4(-19.5, 8.5, 1.8, 1.0), Vector4(-30.0, 1.0, 2.4, 1.6)]:
		var floor_y: float = _support(pool.x, pool.y, 2.0)
		_floor_mark("decal_puddle", puddle, pool.x, pool.y, floor_y + 0.006, pool.z, pool.w, pool.x * 0.3)
	var seed: int = 4177
	# Start x, z, heading and length: the marks follow a lazy arc and stop
	# wherever the deck under them changes level.
	for path: Vector4 in [Vector4(-29.0, 20.0, -1.9, 14.0), Vector4(-29.0, 4.0, -2.0, 9.0), Vector4(17.0, 4.0, 1.9, 12.0),
			Vector4(27.0, 14.0, -1.9, 9.0), Vector4(-6.0, 22.0, -2.6, 7.0), Vector4(8.0, -21.0, 0.3, 11.0),
			Vector4(-33.0, -21.0, 0.9, 9.0)]:
		var floor_y: float = _support(path.x, path.y, 6.5)
		var heading: float = path.z
		var at: Vector2 = Vector2(path.x, path.y)
		var t: float = 0.0
		while t < path.w:
			seed = (seed * 1103515245 + 12345) & 0x7fffffff
			heading += 0.06
			var forward: Vector2 = Vector2(cos(heading), sin(heading))
			var side: Vector2 = Vector2(-forward.y, forward.x) * 0.8
			for pair: float in [-1.0, 1.0]:
				var mark: Vector2 = at + side * pair
				if absf(_support(mark.x, mark.y, floor_y + 0.01) - floor_y) < 0.01:
					_atlas("skid_%d" % (seed % 2), Vector3(mark.x, floor_y + 0.007, mark.y), -heading)
			var step: float = 1.1 + float(seed % 3) * 0.05
			at += forward * step
			t += step
	for i: int in range(140):
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var x: float = -10.0 + float(seed % 2000) / 100.0
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var z: float = 2.0 + float(seed % 2400) / 100.0
		var floor_y: float = _support(x, z, 2.0)
		# Keep slips off the kiosk and its tote board.
		if (absf(x) < 2.2 and z > 15.8 and z < 19.2) or (absf(x) < 0.8 and z > 18.8):
			continue
		var paper: String = "ticket_0" if i % 5 == 0 else "slip_%d" % (i % 3)
		_atlas(paper, Vector3(x, floor_y + 0.009, z), float(seed % 628) / 100.0)
	# Scorch where debts were burned on the decks above.
	var burned: Array[Vector3] = [Vector3(-24.0, LEVEL_2, -21.5), Vector3(18.5, LEVEL_1, 11.0), Vector3(-30.0, LEVEL_1, 19.0), Vector3(14.5, ROOF, -15.0)]
	for index: int in range(burned.size()):
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var at: Vector3 = burned[index]
		_atlas("scorch_%d" % (index % 2), Vector3(at.x, at.y + 0.008, at.z), float(seed % 628) / 100.0)
	# League tags sprayed where the crowd stands: the Pit's east retaining
	# face, between the Ledger boards, and the bays' back walls. Shapes, never
	# words.
	for tag: Array in [["tag_0", Vector3(9.97, 1.0, -8.0), Vector3.LEFT], ["tag_1", Vector3(9.97, 0.9, -1.6), Vector3.LEFT],
			["drips_0", Vector3(0.9, 0.55, -9.97), Vector3.BACK], ["tag_2", Vector3(-15.5, 3.3, 27.98), Vector3.FORWARD],
			["drips_0", Vector3(24.0, 3.3, 27.98), Vector3.FORWARD]]:
		_atlas(str(tag[0]), tag[1], 0.0, tag[2])

## Headroom bars hung at the mouths of the covered bays, the oldest sign in
## any car park. They hang just under the soffit, well over any head.
func _height_bars() -> void:
	var yellow: Material = _mat("bar_yellow", HAZARD_YELLOW)
	var black: Material = _mat("bar_black", HAZARD_BLACK)
	var chain: Material = _mat("hook_iron", Color("2f2c2a"))
	for bar: Array in [[Vector2(-36.0, -26.0), 8.2, true], [Vector2(14.0, 36.0), 12.2, true]]:
		var span: Vector2 = bar[0]
		var z: float = bar[1]
		var y: float = 4.32
		var x: float = span.x + 0.5
		var stripe: int = 0
		while x < span.y - 0.5:
			_box("bar_yellow" if stripe % 2 == 0 else "bar_black", yellow if stripe % 2 == 0 else black, Vector3(x + 0.4, y, z), Vector3(0.8, 0.22, 0.14))
			x += 0.8
			stripe += 1
		for end: float in [span.x + 1.0, span.y - 1.0]:
			_box("hook_iron", chain, Vector3(end, (y + 4.6) * 0.5, z), Vector3(0.04, 4.6 - y, 0.04))
		_sign("WORLD_LARAK_HEADROOM", Vector3((span.x + span.y) * 0.5, y, z - 0.08), PI, Vector2(3.2, 0.2), Color("1d1b19"))

## The registered strip lights burn the venue's sodium; the Low Ramp tunnel's
## is a cold fluorescent with the Rail glowing at the end of it.
func _retint_practicals() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var lid: int = _solid_index(-24.0, 2.0, -14.0, 10.0, 3.4)
	for child: Node in parent.get_children():
		if child.has_meta("host_solid") and int(child.get_meta("host_solid")) == lid:
			var practical: OmniLight3D = child.get_node_or_null("Practical") as OmniLight3D
			if practical != null:
				practical.light_color = FLUORESCENT
				practical.light_energy = 2.2
				practical.omni_range = 10.0
