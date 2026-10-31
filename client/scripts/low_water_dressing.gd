extends RefCounted

## Low Water's homes, one dressing for every level that walks its streets.
## Planned Works (the default layout and mood) is the town at night: domestic
## paint, windows mostly dark with a few still lit and one or two catching and
## dropping, doors and shop shutters, and the survey marks the machines
## painted on the doors they plan to take. The roof tanks from level 5 are
## sectional steel tanks with their ladders and hatches, and the tram street
## lamps burn, flicker or stay dead. Still Here passes its own layout and the
## mood of the first light or of years later: the same homes, broken and
## boarded the morning after, glazed and planted years on.
##
## Everything here is flush relief on registered solids: the deepest part
## stands 0.08 m off its wall and nothing becomes collision, cover or a floor.
## A face is dressed only when its exact authored solid is present, so a
## custom layout never receives guessed windows.
const Geometry = preload("res://scripts/model_geometry.gd")

const FLOOR_HEIGHT: float = 3.2
const BAY: float = 3.2
const PAINT_OFFSET: float = 0.006
## Facade paint that stays Low Water at night: the warm plaster of level 4,
## the green and the terracotta, all under a cool moon.
## Worn plaster in its own colours, a step darker and warmer than a
## restoration machine's matte off-white, so a Paver always stands out of a
## Low Water wall in value as well as shape.
const PAINTS: Array[Color] = [Color("8e7658"), Color("5e7a70"), Color("94806c"), Color("8a5e48"), Color("74785e"), Color("7c6a58"), Color("586e70")]
const LIT: Color = Color("ffc787")
const DIM: Color = Color("a87a48")
const SURVEY: Color = Color("e6e4da")

## [solid low, solid high, face, paint, ground floor, optional world span along
## the face, optional lowest dressed height]. Faces follow MapDecoration's
## bases: north is the solid's -Z face and south its +Z face.
const FACES: Array[Dictionary] = [
	{"low": Vector3(-28, 0, -40), "high": Vector3(-12, 9.6, -23), "face": "south", "paint": 0, "ground": "shops"},
	{"low": Vector3(-9, 0, -40), "high": Vector3(10, 9.6, -23), "face": "south", "paint": 3, "ground": "doors"},
	{"low": Vector3(-12, 0, -40), "high": Vector3(-9, 9.6, -28), "face": "south", "paint": 6, "ground": "doors"},
	{"low": Vector3(-28, 0, -9), "high": Vector3(-17, 9.6, 12), "face": "north", "paint": 1, "ground": "shops"},
	{"low": Vector3(-28, 0, -9), "high": Vector3(-17, 9.6, 12), "face": "south", "paint": 2, "ground": "doors"},
	{"low": Vector3(-14, 0, -9), "high": Vector3(-4, 9.6, 12), "face": "north", "paint": 5, "ground": "shops"},
	{"low": Vector3(-14, 0, -9), "high": Vector3(-4, 9.6, 12), "face": "east", "paint": 4, "ground": "doors"},
	{"low": Vector3(-14, 0, -9), "high": Vector3(-4, 9.6, 12), "face": "south", "paint": 0, "ground": "doors"},
	{"low": Vector3(-17, 0, -4), "high": Vector3(-14, 9.6, 12), "face": "north", "paint": 3, "ground": "doors"},
	{"low": Vector3(-17, 0, -4), "high": Vector3(-14, 9.6, 12), "face": "south", "paint": 6, "ground": "doors"},
	{"low": Vector3(10, 0, -40), "high": Vector3(42, 10.2, 12), "face": "west", "paint": 6, "ground": "shops", "span": Vector2(-23, 12)},
	{"low": Vector3(10, 0, -40), "high": Vector3(42, 10.2, 12), "face": "south", "paint": 2, "ground": "shops"},
	{"low": Vector3(42, 0, 12), "high": Vector3(46, 9.6, 38), "face": "west", "paint": 1, "ground": "shops"},
	{"low": Vector3(-60, 0, 16), "high": Vector3(-30, 6, 52), "face": "east", "paint": 3, "ground": "doors", "span": Vector2(16, 38)},
	{"low": Vector3(-60, 0, 16), "high": Vector3(-30, 6, 52), "face": "south", "paint": 5, "ground": "doors"},
	{"low": Vector3(-30, 0, 38), "high": Vector3(-2, 6, 52), "face": "north", "paint": 0, "ground": "doors"},
	{"low": Vector3(-30, 0, 38), "high": Vector3(-2, 6, 52), "face": "south", "paint": 4, "ground": "doors"},
	{"low": Vector3(-30, 0, 38), "high": Vector3(-2, 6, 52), "face": "east", "paint": 2, "ground": "doors"},
	{"low": Vector3(4, 0, 38), "high": Vector3(24, 6.5, 52), "face": "north", "paint": 1, "ground": "shops"},
	{"low": Vector3(4, 0, 38), "high": Vector3(24, 6.5, 52), "face": "south", "paint": 3, "ground": "doors"},
	{"low": Vector3(4, 0, 38), "high": Vector3(24, 6.5, 52), "face": "west", "paint": 5, "ground": "doors"},
	{"low": Vector3(4, 0, 38), "high": Vector3(24, 6.5, 52), "face": "east", "paint": 0, "ground": "doors"},
	{"low": Vector3(-60, 0, 4), "high": Vector3(-30, 9.6, 16), "face": "south", "paint": 2, "ground": "none", "from": 6.0},
	# The tram trench: wet retaining walls, buttresses and bulkhead lamps.
	{"low": Vector3(46, 0, 16), "high": Vector3(48, 10.5, 42), "face": "east", "paint": 0, "ground": "retaining"},
	{"low": Vector3(46, 0, 46), "high": Vector3(48, 10.5, 60), "face": "east", "paint": 0, "ground": "retaining"},
	{"low": Vector3(46, 3, 42), "high": Vector3(48, 10.5, 46), "face": "east", "paint": 0, "ground": "retaining"},
	{"low": Vector3(58, 0, 16), "high": Vector3(60, 10.5, 60), "face": "west", "paint": 0, "ground": "retaining"},
	{"low": Vector3(48, 0, 16), "high": Vector3(58, 10.5, 18), "face": "south", "paint": 0, "ground": "retaining"},
	# Their backs, seen over the workshop roof and from the riverside.
	{"low": Vector3(46, 0, 16), "high": Vector3(48, 10.5, 42), "face": "west", "paint": 0, "ground": "retaining", "lamps": false},
	{"low": Vector3(46, 0, 46), "high": Vector3(48, 10.5, 60), "face": "west", "paint": 0, "ground": "retaining", "lamps": false},
	{"low": Vector3(46, 3, 42), "high": Vector3(48, 10.5, 46), "face": "west", "paint": 0, "ground": "retaining", "lamps": false},
	{"low": Vector3(48, 0, 16), "high": Vector3(58, 10.5, 18), "face": "north", "paint": 0, "ground": "retaining", "lamps": false},
	# The concourse inside: tiled dado, wayfinding bands and the night in the clerestory.
	{"low": Vector3(-60, 0, -36), "high": Vector3(-28, 11, -34), "face": "south", "paint": 0, "ground": "concourse", "span": Vector2(-58, -30)},
	{"low": Vector3(-60, 0, 2), "high": Vector3(-28, 11, 4), "face": "north", "paint": 0, "ground": "concourse", "span": Vector2(-58, -30)},
	{"low": Vector3(-60, 0, -34), "high": Vector3(-58, 11, 2), "face": "east", "paint": 0, "ground": "concourse"},
	{"low": Vector3(-30, 0, -34), "high": Vector3(-28, 11, -20), "face": "west", "paint": 0, "ground": "concourse"},
	{"low": Vector3(-30, 0, -12), "high": Vector3(-28, 11, 2), "face": "west", "paint": 0, "ground": "concourse"},
	{"low": Vector3(-30, 4.2, -20), "high": Vector3(-28, 11, -12), "face": "west", "paint": 0, "ground": "concourse"},
	# Splice's workshop: inside, the bench wall and tool boards; outside, shutters.
	{"low": Vector3(26, 0, 38), "high": Vector3(34, 5.6, 38.6), "face": "south", "paint": 0, "ground": "workshop"},
	{"low": Vector3(38, 0, 38), "high": Vector3(46, 5.6, 38.6), "face": "south", "paint": 0, "ground": "workshop"},
	{"low": Vector3(26, 0, 51.4), "high": Vector3(30, 5.6, 52), "face": "north", "paint": 0, "ground": "workshop"},
	{"low": Vector3(33, 0, 51.4), "high": Vector3(46, 5.6, 52), "face": "north", "paint": 0, "ground": "workshop"},
	{"low": Vector3(26, 0, 38.6), "high": Vector3(26.6, 5.6, 51.4), "face": "east", "paint": 0, "ground": "workshop"},
	{"low": Vector3(45.4, 0, 46), "high": Vector3(46, 5.6, 51.4), "face": "west", "paint": 0, "ground": "workshop"},
	{"low": Vector3(26, 0, 38), "high": Vector3(34, 5.6, 38.6), "face": "north", "paint": 4, "ground": "shops"},
	{"low": Vector3(38, 0, 38), "high": Vector3(46, 5.6, 38.6), "face": "north", "paint": 4, "ground": "shops"},
	{"low": Vector3(33, 0, 51.4), "high": Vector3(46, 5.6, 52), "face": "south", "paint": 4, "ground": "shops"},
	# Its street front onto the tram street.
	{"low": Vector3(-30, 0, -34), "high": Vector3(-28, 11, -20), "face": "east", "paint": 0, "ground": "retaining", "span": Vector2(-23, -20)},
	{"low": Vector3(-30, 0, -12), "high": Vector3(-28, 11, 2), "face": "east", "paint": 0, "ground": "retaining", "span": Vector2(-12, -9)},
	{"low": Vector3(-30, 4.2, -20), "high": Vector3(-28, 11, -12), "face": "east", "paint": 0, "ground": "retaining"},
]
## Trams left where they stopped: the street's stalled car and Splice's.
const TRAMS: Array[Dictionary] = [
	{"low": Vector3(-24, 0, -21), "high": Vector3(-15, 3.2, -18)},
	{"low": Vector3(38, 0, 47), "high": Vector3(44, 2.4, 50.4)},
]
## The market awnings from level 4: the same striped canvas, faded, its hem
## hanging over the stalls nobody is keeping.
const AWNINGS: Array[Dictionary] = [
	{"low": Vector3(-3, 2.6, 17.5), "high": Vector3(3, 2.8, 21.5)},
	{"low": Vector3(9, 2.6, 27.5), "high": Vector3(15, 2.8, 31.5)},
	{"low": Vector3(19, 2.6, 17.5), "high": Vector3(25, 2.8, 21.5)},
	{"low": Vector3(29, 2.6, 27.5), "high": Vector3(35, 2.8, 31.5)},
]
const CANVAS: Array[Color] = [Color("bead80"), Color("965b42"), Color("6e8980"), Color("ae985e")]
## Street planters nobody watered this week, and the market well.
const PLANTERS: Array[Dictionary] = [
	{"low": Vector3(8, 0, 13), "high": Vector3(11, 1.2, 14.2)},
	{"low": Vector3(-7, 0, 13), "high": Vector3(-4, 1.2, 14.2)},
]
const WELL: Dictionary = {"low": Vector3(21, 0, 24), "high": Vector3(24, 1, 27)}
## Walkable roofs: tar patches and flashing break the membrane up.
const ROOFS: Array[Dictionary] = [
	{"low": Vector3(-60, 0, 16), "high": Vector3(-30, 6, 52)},
	{"low": Vector3(-30, 0, 38), "high": Vector3(-2, 6, 52)},
	{"low": Vector3(4, 0, 38), "high": Vector3(24, 6.5, 52)},
]
## Aerials on the tank roof's chimneys and stairhouse.
const AERIALS: Array[Dictionary] = [
	{"low": Vector3(-36, 6, 18), "high": Vector3(-34, 7.4, 20)},
	{"low": Vector3(-54, 6, 32), "high": Vector3(-52, 7.4, 34)},
	{"low": Vector3(-58, 6, 42), "high": Vector3(-53, 7.8, 48)},
]
const TANKS: Array[Dictionary] = [
	{"low": Vector3(-50, 6, 22), "high": Vector3(-46, 9.6, 26), "ladder": "west"},
	{"low": Vector3(-42, 6, 36), "high": Vector3(-38, 9.6, 40), "ladder": "north"},
]
## Tram street lamps: lit, interrupted and dead. The arm reaches over the road.
const LAMPS: Array[Dictionary] = [
	{"low": Vector3(-19.15, 0, -9.75), "high": Vector3(-18.85, 6.4, -9.45), "reach": Vector3(0, 0, -1), "state": "lit"},
	{"low": Vector3(-7.15, 0, -22.55), "high": Vector3(-6.85, 6.4, -22.25), "reach": Vector3(0, 0, 1), "state": "interrupted"},
	{"low": Vector3(4.85, 0, -9.75), "high": Vector3(5.15, 6.4, -9.45), "reach": Vector3(0, 0, -1), "state": "dead"},
]
## At most this many lit windows throw light onto the street.
const WINDOW_LIGHTS: int = 9
## The rails and wires of Planned Works: under the stalled car, and down the
## trench. Each runs only when its `with` solid is present.
const RAILS: Array[Dictionary] = [
	{"with": {"low": Vector3(-24, 0, -21), "high": Vector3(-15, 3.2, -18)}, "from": Vector3(-28, 0, -19.5), "to": Vector3(10, 0, -19.5), "wall_a": -23.0, "wall_b": -9.0, "wire": 6.4},
	{"with": {"low": Vector3(58, 0, 16), "high": Vector3(60, 10.5, 60)}, "from": Vector3(53, 0, 18), "to": Vector3(53, 0, 52), "wall_a": 48.0, "wall_b": 58.0, "wire": 7.2},
]
const MOODS: Array[String] = ["night_works", "aftermath", "later", "day"]

var _geometry: RefCounted = Geometry.new()
var _tools: Dictionary[String, SurfaceTool] = {}
var _materials: Dictionary[String, Material] = {}
var _avoid: Array[Rect2] = []
var _seed: int = 0
var _window_lights: int = 0
var root: Node3D
## Interrupted lights for the presenter: {mesh, lit, dark, light?, energy, rate, phase, duty}.
var flicker: Array[Dictionary] = []
## Another level's streets: any of faces, trams, awnings, planters, wells,
## roofs, aerials, tanks, lamps and rails, in the shapes the constants use.
## Empty keeps Planned Works.
var layout: Dictionary = {}
## night_works (Planned Works), aftermath (the first light after the wipe),
## later (the same street years on) or day (the multiplayer town before the
## wipe: lived in, shops open, windows glazed, nothing climbing the walls).
var mood: String = "night_works"

func _list(key: String, fallback: Array) -> Array:
	var value: Variant = layout.get(key)
	return value if value is Array else fallback

func build(parent: Node3D, info: Dictionary) -> Node3D:
	root = Node3D.new()
	root.name = "TownDressing"
	parent.add_child(root)
	if mood not in MOODS:
		mood = "night_works"
	var solids: Array = info.get("solids", [])
	var decorations: Array = info.get("presentation", {}).get("decorations", []) if info.get("presentation") is Dictionary else []
	var dressed: int = 0
	var faces: Array = _list("faces", FACES)
	for index: int in range(faces.size()):
		var face: Dictionary = faces[index]
		var solid: Dictionary = _find(solids, face["low"], face["high"])
		if solid.is_empty():
			continue
		_seed = index * 31 + 7
		_face(solid, face, _decorations_on(solids, solid, decorations, str(face["face"])))
		dressed += 1
	var tanks: int = 0
	for tank: Dictionary in _list("tanks", TANKS):
		var solid: Dictionary = _find(solids, tank["low"], tank["high"])
		if not solid.is_empty():
			_tank(tank, _decorations_on(solids, solid, decorations, ""))
			tanks += 1
	var lamps: int = 0
	for lamp: Dictionary in _list("lamps", LAMPS):
		if not _find(solids, lamp["low"], lamp["high"]).is_empty():
			_lamp(lamp)
			lamps += 1
	var trams: int = 0
	for tram: Dictionary in _list("trams", TRAMS):
		# A prepared tram model fills its own solid; its faces need no paint.
		if not _find(solids, tram["low"], tram["high"]).is_empty() and not CampaignProps.replaces(info, tram["low"], tram["high"]):
			_tram(tram["low"], tram["high"], str(tram.get("cab", "")))
			trams += 1
	var awnings: Array = _list("awnings", AWNINGS)
	for index: int in range(awnings.size()):
		var awning: Dictionary = awnings[index]
		if not _find(solids, awning["low"], awning["high"]).is_empty():
			_awning(awning["low"], awning["high"], index)
	for planter: Dictionary in _list("planters", PLANTERS):
		if not _find(solids, planter["low"], planter["high"]).is_empty():
			_planter(planter["low"], planter["high"])
	for well: Dictionary in _list("wells", [WELL]):
		if not _find(solids, well["low"], well["high"]).is_empty():
			_well(well["low"], well["high"])
	for roof: Dictionary in _list("roofs", ROOFS):
		if not _find(solids, roof["low"], roof["high"]).is_empty():
			var corner: Vector3 = roof["low"]
			_seed = int(absf(corner.x * 13.0 + corner.z))
			_roof(corner, roof["high"])
	for aerial: Dictionary in _list("aerials", AERIALS):
		if not _find(solids, aerial["low"], aerial["high"]).is_empty():
			_aerial(aerial["low"], aerial["high"])
	# Street-running rails and their overhead wire.
	for rail: Dictionary in _list("rails", RAILS):
		var anchor: Dictionary = rail["with"]
		if not _find(solids, anchor["low"], anchor["high"]).is_empty():
			_rails(rail["from"], rail["to"], float(rail["wall_a"]), float(rail["wall_b"]), float(rail["wire"]))
	_commit()
	root.set_meta("faces", dressed)
	root.set_meta("tanks", tanks)
	root.set_meta("trams", trams)
	root.set_meta("lamps", lamps)
	return root

static func _find(solids: Array, low: Vector3, high: Vector3) -> Dictionary:
	for raw: Variant in solids:
		if not raw is Dictionary:
			continue
		var solid: Dictionary = raw
		if Vector3(float(solid["min_x"]), float(solid.get("bottom", 0.0)), float(solid["min_z"])).is_equal_approx(low) \
				and Vector3(float(solid["max_x"]), float(solid.get("top", 4.0)), float(solid["max_z"])).is_equal_approx(high):
			return solid
	return {}

## Registered signs on this face stay readable: windows and doors avoid them.
static func _decorations_on(solids: Array, solid: Dictionary, decorations: Array, face: String) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for raw: Variant in decorations:
		if not raw is Dictionary:
			continue
		var detail: Dictionary = raw
		var host: int = int(detail.get("solid", -1))
		if host < 0 or host >= solids.size() or solids[host] != solid or (not face.is_empty() and detail.get("face") != face):
			continue
		var centre: Vector2 = Vector2(float(detail["center"][0]), float(detail["center"][1]))
		var size: Vector2 = Vector2(float(detail["size"][0]), float(detail["size"][1]))
		result.append(Rect2(centre - size * 0.5 - Vector2(0.4, 0.4), size + Vector2(0.8, 0.8)))
	return result

func _roll(modulo: int) -> int:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return (_seed >> 8) % modulo

# --- Surfaces -----------------------------------------------------------------

func _material(key: String) -> Material:
	if _materials.has(key):
		return _materials[key]
	var result: Material
	if key.begins_with("tint"):
		var tinted: ShaderMaterial = ArenaMaterials.authored("enamel", "low_water") as ShaderMaterial
		tinted.set_shader_parameter("surface_color", Color(key.substr(4)))
		tinted.set_shader_parameter("markings_enabled", false)
		tinted.set_shader_parameter("detail_enabled", false)
		tinted.set_shader_parameter("tile_strength", 0.45)
		result = tinted
	elif key.begins_with("paint"):
		var colour: Color = PAINTS[int(key.substr(5, 1))]
		# The morning after: soot and dust over every wall. Years on:
		# fresh limewash over the same colours.
		if mood == "aftermath":
			colour = colour.darkened(0.14).lerp(Color("6c6a64"), 0.18)
		elif mood == "later":
			colour = colour.lightened(0.12)
		if key.ends_with("dark"):
			colour = colour.darkened(0.32)
		elif key.ends_with("trim"):
			colour = colour.darkened(0.16)
		var finish: ShaderMaterial = ArenaMaterials.authored("enamel", "low_water") as ShaderMaterial
		finish.set_shader_parameter("surface_color", colour)
		finish.set_shader_parameter("markings_enabled", false)
		finish.set_shader_parameter("detail_enabled", false)
		finish.set_shader_parameter("tile_strength", 0.3)
		result = finish
	else:
		var standard: StandardMaterial3D = StandardMaterial3D.new()
		standard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		standard.roughness = 0.92
		match key:
			"frame": standard.albedo_color = Color("2b2824")
			"glass":
				standard.albedo_color = Color("2c3c44") if mood in ["later", "day"] else Color("141b20")
				standard.roughness = 0.28
				standard.metallic_specular = 0.7
			"void": standard.albedo_color = Color("0b0c0d")
			"plank": standard.albedo_color = Color("7a6346")
			"plank_dark": standard.albedo_color = Color("5a4834")
			"shard":
				standard.albedo_color = Color("44535a")
				standard.roughness = 0.2
				standard.metallic_specular = 0.8
			"leaf": standard.albedo_color = Color("4f7a3e")
			"leaf_dark": standard.albedo_color = Color("37592e")
			"bloom_a": standard.albedo_color = Color("d8a23c")
			"bloom_b": standard.albedo_color = Color("c4644a")
			"bloom_c": standard.albedo_color = Color("e8dcc0")
			"box": standard.albedo_color = Color("6a5038")
			"fresh_door_a": standard.albedo_color = Color("3f6f62")
			"fresh_door_b": standard.albedo_color = Color("8e4a34")
			"fresh_door_c": standard.albedo_color = Color("34506e")
			"brass": standard.albedo_color = Color("b48a3e")
			"lit", "lit_dark":
				standard.albedo_color = LIT if key == "lit" else Color("141b20")
				standard.emission_enabled = true
				standard.emission = LIT
				standard.emission_energy_multiplier = 1.5 if key == "lit" else 0.0
			"dim":
				standard.albedo_color = DIM
				standard.emission_enabled = true
				standard.emission = DIM
				standard.emission_energy_multiplier = 0.7
			"curtain": standard.albedo_color = Color("6d3f33")
			"shutter": standard.albedo_color = Color("5e4b39")
			"slat": standard.albedo_color = Color("3c3027")
			"door": standard.albedo_color = Color("5b4636")
			"panel": standard.albedo_color = Color("47372b")
			"roller": standard.albedo_color = Color("5f6763")
			"rib": standard.albedo_color = Color("3d4441")
			"fascia": standard.albedo_color = Color("2f3a37")
			"sill": standard.albedo_color = Color("8b8576")
			"pipe": standard.albedo_color = Color("3b4240")
			"tank": standard.albedo_color = Color("5f7f7a")
			"flange": standard.albedo_color = Color("47615d")
			"rust": standard.albedo_color = Color("7a4a30")
			"iron": standard.albedo_color = Color("262b2b")
			"canvas0", "canvas1", "canvas2", "canvas3":
				standard.albedo_color = CANVAS[int(key.substr(6))].darkened(0.12)
			"soil": standard.albedo_color = Color("3a2e25")
			"stalk": standard.albedo_color = Color("6f6a48")
			"water":
				standard.albedo_color = Color("16262c")
				standard.roughness = 0.12
				standard.metallic_specular = 0.9
			"tar": standard.albedo_color = Color("4a5053")
			"tar_old": standard.albedo_color = Color("565b5c")
			"flashing": standard.albedo_color = Color("5d625f")
			"night":
				standard.albedo_color = Color("0f1724")
				standard.roughness = 0.25
				standard.metallic_specular = 0.8
			"way_amber": standard.albedo_color = Color("c98a3a")
			"way_green": standard.albedo_color = Color("3f7f62")
			"tram_glass": standard.albedo_color = Color("2b4446")
			"survey":
				standard.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				standard.albedo_color = SURVEY
			"bulb", "bulb_dark":
				standard.albedo_color = Color("ffd59a") if key == "bulb" else Color("3b3730")
				standard.emission_enabled = key == "bulb"
				standard.emission = Color("ffd59a")
				standard.emission_energy_multiplier = 5.0
			_: standard.albedo_color = Color.MAGENTA
		result = standard
	_materials[key] = result
	return result

func _tool(key: String) -> SurfaceTool:
	if not _tools.has(key):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(_material(key))
		_tools[key] = tool
	return _tools[key]

func _commit() -> void:
	if _tools.is_empty():
		return
	var mesh: ArrayMesh = ArrayMesh.new()
	for key: String in _tools.keys():
		_tools[key].commit(mesh)
	var view: MeshInstance3D = MeshInstance3D.new()
	view.name = "TownReliefMesh"
	view.mesh = mesh
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(view)
	_tools.clear()

## A raised rectangle on a face: front plus four returns.
func _slab(tool: SurfaceTool, basis: Basis, origin: Vector3, u0: float, v0: float, u1: float, v1: float, near: float, far: float) -> void:
	var a: Vector3 = origin + basis.x * u0 + basis.y * v0
	var b: Vector3 = origin + basis.x * u1 + basis.y * v0
	var c: Vector3 = origin + basis.x * u1 + basis.y * v1
	var d: Vector3 = origin + basis.x * u0 + basis.y * v1
	var out: Vector3 = basis.z * far
	_geometry.quad(tool, a + out, b + out, c + out, d + out, basis.z)
	if far - near < 0.002:
		return
	var back: Vector3 = basis.z * near
	_geometry.quad(tool, a + back, b + back, b + out, a + out, -basis.y)
	_geometry.quad(tool, d + back, c + back, c + out, d + out, basis.y)
	_geometry.quad(tool, a + back, d + back, d + out, a + out, -basis.x)
	_geometry.quad(tool, b + back, c + back, c + out, b + out, basis.x)

# --- Facades ------------------------------------------------------------------

func _face(solid: Dictionary, face: Dictionary, avoid: Array[Rect2]) -> void:
	_avoid = avoid
	var basis: Basis = MapDecoration.face_basis(str(face["face"]))
	var low: Vector3 = Vector3(float(solid["min_x"]), float(solid.get("bottom", 0.0)), float(solid["min_z"]))
	var high: Vector3 = Vector3(float(solid["max_x"]), float(solid.get("top", 4.0)), float(solid["max_z"]))
	var size: Vector3 = high - low
	var centre: Vector3 = (low + high) * 0.5
	var half_depth: float = absf(basis.z.dot(size)) * 0.5
	var width: float = absf(basis.x.dot(size))
	var height: float = size.y
	# Face origin: the centre of the face, then u along basis.x, v up from the face centre.
	var origin: Vector3 = centre + basis.z * half_depth
	var u0: float = -width * 0.5
	var u1: float = width * 0.5
	if face.has("span"):
		var span: Vector2 = face["span"]
		var axis: Vector3 = basis.x
		var ends: Array[float] = []
		for value: float in [span.x, span.y]:
			var point: Vector3 = centre
			if absf(axis.x) > 0.5:
				point.x = value
			else:
				point.z = value
			ends.append(axis.dot(point - centre))
		u0 = maxf(u0, minf(ends[0], ends[1]))
		u1 = minf(u1, maxf(ends[0], ends[1]))
	var v_low: float = -height * 0.5 + float(face.get("from", 0.0))
	var v_top: float = height * 0.5
	var paint: int = int(face["paint"])
	var key: String = "paint%d" % paint
	match str(face["ground"]):
		"retaining":
			_retaining(basis, origin, u0, u1, v_low, v_top, bool(face.get("lamps", true)))
			return
		"concourse":
			_concourse(basis, origin, u0, u1, v_low, v_top)
			return
		"workshop":
			_workshop(basis, origin, u0, u1, v_low, v_top)
			return
	# Broad domestic paint over the institutional bays.
	_slab(_tool(key), basis, origin, u0, v_low, u1, v_top, 0.0, PAINT_OFFSET)
	# Plinth, floor bands and the cornice that makes the mass a roofline.
	if face.get("from", 0.0) == 0.0:
		_slab(_tool(key + "dark"), basis, origin, u0, v_low, u1, v_low + 0.55, 0.0, 0.014)
	var floors: int = maxi(1, int(floor((height - float(face.get("from", 0.0))) / FLOOR_HEIGHT + 0.15)))
	for level: int in range(1, floors):
		var band: float = v_low + float(level) * FLOOR_HEIGHT
		_slab(_tool(key + "trim"), basis, origin, u0, band - 0.06, u1, band + 0.06, 0.0, 0.02)
	_slab(_tool(key + "dark"), basis, origin, u0, v_top - 0.32, u1, v_top, 0.0, 0.05)
	# Rain pipes at the ends of each long face.
	for end: float in [u0 + 0.35, u1 - 0.35]:
		_slab(_tool("pipe"), basis, origin, end - 0.06, v_low, end + 0.06, v_top - 0.32, 0.0, 0.08)
	var bays: int = maxi(1, int(floor((u1 - u0 - 1.2) / BAY)))
	var used: float = float(bays) * BAY
	var start: float = (u0 + u1) * 0.5 - used * 0.5 + BAY * 0.5
	if mood == "later" and face.get("from", 0.0) == 0.0:
		# Something climbs every long wall now; nobody cut it back.
		for vine: int in range(maxi(1, bays / 3)):
			var at: float = start + BAY * 0.5 + float(vine * 3) * BAY
			if at < u1 - 0.6:
				_vine(basis, origin, at, v_low, minf(height - 0.6, 3.2 + float((vine * 7 + _seed) % 4) * 1.1))
	for bay: int in range(bays):
		var u: float = start + float(bay) * BAY
		var ground: String = str(face["ground"])
		if face.get("from", 0.0) == 0.0 and ground != "none":
			_ground_bay(basis, origin, u, v_low, ground, paint)
		for level: int in range(1 if face.get("from", 0.0) == 0.0 else 0, floors):
			var sill: float = v_low + float(level) * FLOOR_HEIGHT + 0.9
			if sill + 1.5 > v_top - 0.4:
				continue
			_window(basis, origin, u, sill, level)

func _blocked(rect: Rect2) -> bool:
	for avoid: Rect2 in _avoid:
		if avoid.intersects(rect):
			return true
	return false

func _window(basis: Basis, origin: Vector3, u: float, sill: float, level: int) -> void:
	var w: float = 1.15
	var h: float = 1.45
	if _blocked(Rect2(u - w * 0.5, sill, w, h)):
		return
	var roll: int = _roll(100)
	_slab(_tool("frame"), basis, origin, u - w * 0.5 - 0.1, sill - 0.08, u + w * 0.5 + 0.1, sill + h + 0.1, 0.0, 0.03)
	_slab(_tool("sill"), basis, origin, u - w * 0.5 - 0.16, sill - 0.14, u + w * 0.5 + 0.16, sill - 0.02, 0.0, 0.07)
	if mood == "aftermath":
		_window_aftermath(basis, origin, u, sill, level, w, h, roll)
		return
	if mood in ["later", "day"]:
		_window_later(basis, origin, u, sill, w, h, roll)
		return
	if roll < 15:
		# Still lit: somebody stayed, or left the lamp on.
		var glass: String = "lit"
		var flickers: bool = roll < 2
		if flickers:
			_flicker_window(basis, origin, u, sill, w, h, level)
		else:
			_slab(_tool(glass), basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.034)
			if roll % 3 == 0:
				_slab(_tool("curtain"), basis, origin, u - w * 0.5, sill + h * 0.55, u - w * 0.12, sill + h, 0.0, 0.036)
			_window_light(basis, origin, u, sill, level, 0.9)
	elif roll < 21:
		_slab(_tool("dim"), basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.034)
	elif roll < 38:
		# Shutters closed by whoever left.
		_slab(_tool("shutter"), basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.05)
		for slat: int in range(6):
			var y: float = sill + 0.12 + float(slat) * 0.22
			_slab(_tool("slat"), basis, origin, u - w * 0.5 + 0.05, y, u + w * 0.5 - 0.05, y + 0.05, 0.05, 0.056)
		_slab(_tool("slat"), basis, origin, u - 0.02, sill, u + 0.02, sill + h, 0.05, 0.058)
	else:
		_slab(_tool("glass"), basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.034)
		_slab(_tool("frame"), basis, origin, u - 0.03, sill, u + 0.03, sill + h, 0.034, 0.04)
		_slab(_tool("frame"), basis, origin, u - w * 0.5, sill + h * 0.62, u + w * 0.5, sill + h * 0.62 + 0.05, 0.034, 0.04)

## The morning after: a few lamps lit by people inside, panes blown in,
## windows boarded with what was to hand, shutters pulled to.
func _window_aftermath(basis: Basis, origin: Vector3, u: float, sill: float, level: int, w: float, h: float, roll: int) -> void:
	if roll < 9:
		_slab(_tool("lit"), basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.034)
		_slab(_tool("curtain"), basis, origin, u - w * 0.5, sill + h * 0.5, u - w * 0.1, sill + h, 0.0, 0.036)
		_window_light(basis, origin, u, sill, level, 0.7)
	elif roll < 30:
		# Blown in: the dark room behind and what is left of the pane.
		_slab(_tool("void"), basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.02)
		_slab(_tool("shard"), basis, origin, u - w * 0.5, sill + h * 0.62, u - w * 0.18, sill + h, 0.02, 0.034)
		_slab(_tool("shard"), basis, origin, u + w * 0.22, sill, u + w * 0.5, sill + h * 0.3, 0.02, 0.034)
		_slab(_tool("frame"), basis, origin, u - 0.03, sill, u + 0.03, sill + h, 0.034, 0.04)
	elif roll < 46:
		# Boarded with mismatched planks over the dark.
		_slab(_tool("void"), basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.02)
		for plank: int in range(3):
			var y: float = sill + 0.16 + float(plank) * 0.46
			_slab(_tool("plank" if plank % 2 == 0 else "plank_dark"), basis, origin, u - w * 0.5 - 0.12, y, u + w * 0.5 + 0.12, y + 0.24, 0.04, 0.07)
	elif roll < 64:
		_slab(_tool("shutter"), basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.05)
		for slat: int in range(6):
			var y: float = sill + 0.12 + float(slat) * 0.22
			_slab(_tool("slat"), basis, origin, u - w * 0.5 + 0.05, y, u + w * 0.5 - 0.05, y + 0.05, 0.05, 0.056)
	else:
		_slab(_tool("glass"), basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.034)
		_slab(_tool("frame"), basis, origin, u - 0.03, sill, u + 0.03, sill + h, 0.034, 0.04)

## Years on: glazed again, shutters thrown open in fresh paint, curtains and
## window boxes, nothing boarded.
func _window_later(basis: Basis, origin: Vector3, u: float, sill: float, w: float, h: float, roll: int) -> void:
	_slab(_tool("glass"), basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.034)
	_slab(_tool("frame"), basis, origin, u - 0.03, sill, u + 0.03, sill + h, 0.034, 0.04)
	_slab(_tool("frame"), basis, origin, u - w * 0.5, sill + h * 0.62, u + w * 0.5, sill + h * 0.62 + 0.05, 0.034, 0.04)
	if roll < 40:
		# Open shutters folded back against the wall either side.
		var leaf: String = ["fresh_door_a", "fresh_door_b", "fresh_door_c"][roll % 3]
		for side: float in [-1.0, 1.0]:
			var edge: float = u + side * (w * 0.5 + 0.12)
			_slab(_tool(leaf), basis, origin, minf(edge, edge + side * 0.55), sill - 0.02, maxf(edge, edge + side * 0.55), sill + h + 0.02, 0.0, 0.05)
	if roll % 3 == 0:
		_slab(_tool("curtain"), basis, origin, u - w * 0.5, sill + h * 0.45, u - w * 0.16, sill + h, 0.034, 0.036)
	if roll % 4 != 1:
		# A window box: soil, leaves, and a little colour.
		_slab(_tool("box"), basis, origin, u - w * 0.5 - 0.05, sill - 0.32, u + w * 0.5 + 0.05, sill - 0.08, 0.0, 0.26)
		for sprig: int in range(6):
			var x: float = u - w * 0.42 + float(sprig) * w * 0.17
			var tall: float = 0.14 + 0.06 * float((sprig * 3 + roll) % 4)
			_slab(_tool("leaf" if sprig % 2 == 0 else "leaf_dark"), basis, origin, x - 0.07, sill - 0.1, x + 0.07, sill - 0.1 + tall, 0.04, 0.22)
			if (sprig + roll) % 3 == 0:
				_slab(_tool(["bloom_a", "bloom_b", "bloom_c"][(sprig + roll) % 3]), basis, origin, x - 0.05, sill - 0.12 + tall, x + 0.05, sill - 0.02 + tall, 0.08, 0.2)

func _window_light(basis: Basis, origin: Vector3, u: float, sill: float, level: int, energy: float) -> OmniLight3D:
	if _window_lights >= WINDOW_LIGHTS or level > 1:
		return null
	_window_lights += 1
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "WindowSpill"
	light.light_color = Color("ffbf7a")
	light.light_energy = energy
	light.omni_range = 6.5
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = origin + basis.x * u + basis.y * (sill + 0.6) + basis.z * 1.2
	root.add_child(light)
	return light

func _flicker_window(basis: Basis, origin: Vector3, u: float, sill: float, w: float, h: float, level: int) -> void:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_slab(tool, basis, origin, u - w * 0.5, sill, u + w * 0.5, sill + h, 0.0, 0.034)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "InterruptedWindow"
	mesh.mesh = tool.commit()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	var light: OmniLight3D = _window_light(basis, origin, u, sill, level, 0.9)
	var entry: Dictionary = {"mesh": mesh, "lit": _material("lit"), "dark": _material("lit_dark"),
		"rate": 0.23 + 0.11 * float(flicker.size()), "phase": 0.37 * float(flicker.size()), "duty": 0.22, "energy": 0.9}
	if light != null:
		entry["light"] = light
	flicker.append(entry)

func _ground_bay(basis: Basis, origin: Vector3, u: float, v_low: float, ground: String, paint: int) -> void:
	var roll: int = _roll(100)
	if mood != "night_works":
		_ground_bay_after(basis, origin, u, v_low, ground, paint, roll)
		return
	var shop: bool = ground == "shops" and roll < 60
	if ground == "doors" and roll >= 50:
		# Not every ground bay is a door: a ground-floor room, its window low.
		_window(basis, origin, u, v_low + 0.95, 0)
		return
	var rect: Rect2 = Rect2(u - 1.4, v_low, 2.8, 3.0) if shop else Rect2(u - 0.7, v_low, 1.4, 2.5)
	if _blocked(rect):
		return
	if shop:
		# A rolled-down shutter under a dark fascia: closed for the works.
		_slab(_tool("fascia"), basis, origin, u - 1.45, v_low + 2.55, u + 1.45, v_low + 3.0, 0.0, 0.06)
		_slab(_tool("roller"), basis, origin, u - 1.3, v_low + 0.02, u + 1.3, v_low + 2.5, 0.0, 0.03)
		for rib: int in range(14):
			var y: float = v_low + 0.12 + float(rib) * 0.17
			_slab(_tool("rib"), basis, origin, u - 1.3, y, u + 1.3, y + 0.035, 0.03, 0.036)
		if roll % 4 == 1:
			_slab(_tool("rust"), basis, origin, u - 1.3, v_low + 0.02, u - 0.5, v_low + 0.5, 0.03, 0.038)
		if roll % 2 == 0:
			_survey(basis, origin, u + 0.6, v_low + 1.5)
		return
	# A front door with its frame, a step and sometimes the white survey mark.
	_slab(_tool("frame"), basis, origin, u - 0.66, v_low, u + 0.66, v_low + 2.42, 0.0, 0.035)
	_slab(_tool("door"), basis, origin, u - 0.54, v_low + 0.06, u + 0.54, v_low + 2.3, 0.0, 0.025)
	for panel: Array in [[-0.42, 0.25, -0.06, 1.05], [0.06, 0.25, 0.42, 1.05], [-0.42, 1.2, -0.06, 1.85], [0.06, 1.2, 0.42, 1.85]]:
		_slab(_tool("panel"), basis, origin, u + float(panel[0]), v_low + float(panel[1]), u + float(panel[2]), v_low + float(panel[3]), 0.025, 0.028)
	_slab(_tool("sill"), basis, origin, u - 0.75, v_low, u + 0.75, v_low + 0.12, 0.0, 0.08)
	_slab(_tool("paint%dtrim" % paint), basis, origin, u - 0.25, v_low + 1.95, u + 0.25, v_low + 2.15, 0.025, 0.03)
	if roll < 55:
		_survey(basis, origin, u + 1.15, v_low + 1.4)
	elif roll < 75:
		# A lit fanlight: someone is still inside.
		_slab(_tool("lit"), basis, origin, u - 0.4, v_low + 2.0, u + 0.4, v_low + 2.26, 0.025, 0.03)

## Doors and shopfronts the morning after and years on. No survey marks: the
## machines walked around this place.
func _ground_bay_after(basis: Basis, origin: Vector3, u: float, v_low: float, ground: String, paint: int, roll: int) -> void:
	var shop: bool = ground == "shops" and roll < 60
	if ground == "doors" and roll >= 50:
		_window(basis, origin, u, v_low + 0.95, 0)
		return
	var rect: Rect2 = Rect2(u - 1.4, v_low, 2.8, 3.0) if shop else Rect2(u - 0.7, v_low, 1.4, 2.5)
	if _blocked(rect):
		return
	if shop:
		_slab(_tool("fascia"), basis, origin, u - 1.45, v_low + 2.55, u + 1.45, v_low + 3.0, 0.0, 0.06)
		if mood == "aftermath":
			# Jammed half up: a dark gap under a bent shutter.
			_slab(_tool("void"), basis, origin, u - 1.3, v_low + 0.02, u + 1.3, v_low + 0.9, 0.0, 0.02)
			_slab(_tool("roller"), basis, origin, u - 1.3, v_low + 0.9, u + 1.3, v_low + 2.5, 0.0, 0.03)
			for rib: int in range(9):
				var y: float = v_low + 1.0 + float(rib) * 0.17
				_slab(_tool("rib"), basis, origin, u - 1.3, y, u + 1.3, y + 0.035, 0.03, 0.036)
		else:
			# Open for business: glass, a striped blind and a door in fresh paint.
			_slab(_tool("glass"), basis, origin, u - 1.3, v_low + 0.5, u + 0.4, v_low + 2.4, 0.0, 0.03)
			_slab(_tool("box"), basis, origin, u - 1.3, v_low + 0.02, u + 0.4, v_low + 0.5, 0.0, 0.06)
			_slab(_tool(["fresh_door_a", "fresh_door_b", "fresh_door_c"][roll % 3]), basis, origin, u + 0.55, v_low + 0.06, u + 1.3, v_low + 2.4, 0.0, 0.03)
			for stripe: int in range(6):
				var x: float = u - 1.45 + float(stripe) * 0.48
				_slab(_tool("canvas%d" % (stripe % 2 * 2 + roll % 2)), basis, origin, x, v_low + 2.3, x + 0.48, v_low + 2.55, 0.06, 0.32)
		return
	_slab(_tool("frame"), basis, origin, u - 0.66, v_low, u + 0.66, v_low + 2.42, 0.0, 0.035)
	if mood == "aftermath" and roll < 22:
		# Left open on the way out, or kicked in.
		_slab(_tool("void"), basis, origin, u - 0.54, v_low + 0.06, u + 0.54, v_low + 2.3, 0.0, 0.025)
	else:
		var door: String = "door" if mood == "aftermath" else ["fresh_door_a", "fresh_door_b", "fresh_door_c"][roll % 3]
		_slab(_tool(door), basis, origin, u - 0.54, v_low + 0.06, u + 0.54, v_low + 2.3, 0.0, 0.025)
		for panel: Array in [[-0.42, 0.25, -0.06, 1.05], [0.06, 0.25, 0.42, 1.05], [-0.42, 1.2, -0.06, 1.85], [0.06, 1.2, 0.42, 1.85]]:
			_slab(_tool("panel" if mood == "aftermath" else door), basis, origin, u + float(panel[0]), v_low + float(panel[1]), u + float(panel[2]), v_low + float(panel[3]), 0.025, 0.028)
		if mood == "later":
			_slab(_tool("brass"), basis, origin, u + 0.32, v_low + 1.0, u + 0.4, v_low + 1.12, 0.028, 0.05)
	_slab(_tool("sill"), basis, origin, u - 0.75, v_low, u + 0.75, v_low + 0.12, 0.0, 0.08)
	_slab(_tool("paint%dtrim" % paint), basis, origin, u - 0.25, v_low + 1.95, u + 0.25, v_low + 2.15, 0.025, 0.03)

## A climbing plant up a wall years on: a stem and leaf clusters, flush.
func _vine(basis: Basis, origin: Vector3, u: float, v_low: float, height: float) -> void:
	if _blocked(Rect2(u - 0.5, v_low, 1.0, height)):
		return
	_slab(_tool("leaf_dark"), basis, origin, u - 0.04, v_low, u + 0.04, v_low + height, 0.0, 0.03)
	var clusters: int = int(height / 0.42)
	for index: int in range(clusters):
		var y: float = v_low + 0.2 + float(index) * 0.42
		var spread: float = 0.18 + 0.12 * float((index * 5 + _seed) % 3)
		var side: float = -1.0 if index % 2 == 0 else 1.0
		_slab(_tool("leaf" if index % 3 else "leaf_dark"), basis, origin, u + minf(0.0, side * spread), y, u + maxf(0.0, side * spread), y + 0.3, 0.01, 0.06)

## The machines' survey mark: a white box with a cross, sprayed beside a door.
func _survey(basis: Basis, origin: Vector3, u: float, v: float) -> void:
	if _blocked(Rect2(u - 0.45, v - 0.45, 0.9, 0.9)):
		return
	var tool: SurfaceTool = _tool("survey")
	var s: float = 0.4
	var t: float = 0.05
	var out: float = 0.04
	for edge: Array in [[-s, -s, s, -s + t], [-s, s - t, s, s], [-s, -s, -s + t, s], [s - t, -s, s, s]]:
		_slab(tool, basis, origin, u + float(edge[0]), v + float(edge[1]), u + float(edge[2]), v + float(edge[3]), out, out)
	for diagonal: float in [1.0, -1.0]:
		var a: Vector3 = origin + basis.x * (u - s) + basis.y * (v - s * diagonal) + basis.z * out
		var b: Vector3 = origin + basis.x * (u + s) + basis.y * (v + s * diagonal) + basis.z * out
		var across: Vector3 = basis.z.cross(b - a).normalized() * t * 0.5
		_geometry.quad(tool, a - across, b - across, b + across, a + across, basis.z)

# --- Roof tanks -----------------------------------------------------------------

## A sectional steel tank, the kind level 5's roofs carried: bolted panels with
## raised flanges, a base frame, a ladder to the hatch and an overflow pipe.
func _tank(tank: Dictionary, avoid: Array[Rect2]) -> void:
	var low: Vector3 = tank["low"]
	var high: Vector3 = tank["high"]
	var centre: Vector3 = (low + high) * 0.5
	var size: Vector3 = high - low
	for face: String in ["north", "south", "east", "west"]:
		var basis: Basis = MapDecoration.face_basis(face)
		var origin: Vector3 = centre + basis.z * absf(basis.z.dot(size)) * 0.5
		var width: float = absf(basis.x.dot(size))
		var hv: float = size.y * 0.5
		var none: Array[Rect2] = []
		_avoid = avoid if face == "east" else none
		_slab(_tool("tank"), basis, origin, -width * 0.5, -hv, width * 0.5, hv, 0.0, PAINT_OFFSET)
		_slab(_tool("iron"), basis, origin, -width * 0.5, -hv, width * 0.5, -hv + 0.35, 0.0, 0.04)
		for seam: int in range(1, 3):
			var v: float = -hv + float(seam) * size.y / 3.0
			_flange(basis, origin, Rect2(-width * 0.5, v - 0.03, width, 0.06))
		for seam: int in range(1, 3):
			var u: float = -width * 0.5 + float(seam) * width / 3.0
			_flange(basis, origin, Rect2(u - 0.03, -hv + 0.35, 0.06, size.y - 0.35))
		_slab(_tool("flange"), basis, origin, -width * 0.5, hv - 0.08, width * 0.5, hv, 0.0, 0.05)
		if face == str(tank["ladder"]):
			for rail: float in [-0.25, 0.25]:
				_slab(_tool("iron"), basis, origin, rail - 0.03, -hv, rail + 0.03, hv + 0.6, 0.06, 0.08)
			for rung: int in range(int(size.y / 0.32)):
				var y: float = -hv + 0.3 + float(rung) * 0.32
				_slab(_tool("iron"), basis, origin, -0.25, y, 0.25, y + 0.03, 0.06, 0.075)
		if face == "south":
			_slab(_tool("rust"), basis, origin, width * 0.18, -hv + 0.35, width * 0.24, hv - 0.4, 0.006, 0.01)
			_slab(_tool("pipe"), basis, origin, -width * 0.3, -hv, -width * 0.3 + 0.12, hv - 0.2, 0.0, 0.08)
	# The roof hatch, flush, where Latch sat with their legs over the edge.
	var top: Basis = MapDecoration.face_basis("up")
	var lid: Vector3 = centre + Vector3(0.0, size.y * 0.5, 0.0)
	_slab(_tool("tank"), top, lid, -size.x * 0.5, -size.z * 0.5, size.x * 0.5, size.z * 0.5, 0.0, PAINT_OFFSET)
	_slab(_tool("flange"), top, lid, -0.55, -0.55, 0.55, 0.55, 0.0, 0.04)

func _flange(basis: Basis, origin: Vector3, rect: Rect2) -> void:
	if _blocked(rect):
		return
	_slab(_tool("flange"), basis, origin, rect.position.x, rect.position.y, rect.end.x, rect.end.y, 0.0, 0.035)

# --- Retaining walls and the concourse --------------------------------------------

## The trench and the concourse's street front: dark wet concrete, a damp band
## at the foot, buttresses, a coping and bulkhead lamps, some of them dead.
func _retaining(basis: Basis, origin: Vector3, u0: float, u1: float, v_low: float, v_top: float, lamps_wanted: bool = true) -> void:
	var grounded: bool = v_low < -4.0
	_slab(_tool("tint5a615d"), basis, origin, u0, v_low, u1, v_top, 0.0, PAINT_OFFSET)
	if grounded:
		_slab(_tool("tint3c4542"), basis, origin, u0, v_low, u1, v_low + 1.3, 0.0, 0.01)
	_slab(_tool("tint7c827d"), basis, origin, u0, v_top - 0.45, u1, v_top, 0.0, 0.07)
	var count: int = maxi(1, int(floor((u1 - u0) / 4.5)))
	var step: float = (u1 - u0) / float(count)
	for index: int in range(count + 1):
		var u: float = clampf(u0 + float(index) * step, u0 + 0.35, u1 - 0.35)
		if _blocked(Rect2(u - 0.35, v_low, 0.7, v_top - v_low)):
			continue
		_slab(_tool("tint4f5653"), basis, origin, u - 0.35, v_low, u + 0.35, v_top - 0.45, 0.0, 0.08)
		if grounded and u + 1.0 < u1:
			# Weep holes and the rust run under them.
			_slab(_tool("rust"), basis, origin, u + 0.9, v_low + 0.5, u + 1.0, v_low + 1.6, 0.0, 0.012)
	# A back face hidden behind other solids carries no lamp: an unshadowed
	# light there would glow through the wall in front of it.
	if not grounded or not lamps_wanted or u1 - u0 < 6.0:
		return
	var lamps: int = maxi(1, int(floor((u1 - u0) / 9.0)))
	for index: int in range(lamps):
		var u: float = u0 + (float(index) + 0.5) * (u1 - u0) / float(lamps)
		var v: float = v_low + 4.3
		if _blocked(Rect2(u - 0.4, v - 0.3, 0.8, 0.6)):
			continue
		var lit: bool = _roll(100) < 62
		_slab(_tool("iron"), basis, origin, u - 0.3, v - 0.18, u + 0.3, v + 0.18, 0.0, 0.08)
		_slab(_tool("lit" if lit else "lit_dark"), basis, origin, u - 0.22, v - 0.1, u + 0.22, v + 0.1, 0.08, 0.1)
		if lit:
			var light: OmniLight3D = OmniLight3D.new()
			light.name = "Bulkhead"
			light.light_color = Color("ffcf94")
			light.light_energy = 1.5
			light.omni_range = 8.5
			light.omni_attenuation = 1.2
			light.shadow_enabled = false
			light.position = origin + basis.x * u + basis.y * v + basis.z * 0.5
			root.add_child(light)

## Inside the concourse: a tiled dado, wayfinding bands that still point to the
## pier, and the night outside the clerestory.
func _concourse(basis: Basis, origin: Vector3, u0: float, u1: float, v_low: float, v_top: float) -> void:
	_slab(_tool("tintb3ad99"), basis, origin, u0, v_low, u1, v_top, 0.0, PAINT_OFFSET)
	if v_low < -4.0:
		_slab(_tool("tint2f4b48"), basis, origin, u0, v_low, u1, v_low + 1.5, 0.0, 0.012)
		_slab(_tool("tint1f3130"), basis, origin, u0, v_low + 1.5, u1, v_low + 1.62, 0.0, 0.02)
		_slab(_tool("way_amber"), basis, origin, u0, v_low + 2.35, u1, v_low + 2.49, 0.0, 0.016)
		_slab(_tool("way_green"), basis, origin, u0, v_low + 2.6, u1, v_low + 2.74, 0.0, 0.016)
	# Clerestory: tall night windows under the roof.
	var top: float = v_top - 1.2
	var count: int = maxi(1, int(floor((u1 - u0) / 4.0)))
	var step: float = (u1 - u0) / float(count)
	for index: int in range(count):
		var u: float = u0 + (float(index) + 0.5) * step
		if _blocked(Rect2(u - 1.0, top - 2.6, 2.0, 2.6)):
			continue
		_slab(_tool("frame"), basis, origin, u - 1.05, top - 2.65, u + 1.05, top + 0.05, 0.0, 0.03)
		_slab(_tool("night"), basis, origin, u - 0.95, top - 2.55, u + 0.95, top - 0.05, 0.0, 0.034)
		for mullion: float in [-0.32, 0.32]:
			_slab(_tool("frame"), basis, origin, u + mullion - 0.03, top - 2.55, u + mullion + 0.03, top - 0.05, 0.034, 0.04)
		_slab(_tool("frame"), basis, origin, u - 0.95, top - 1.0, u + 0.95, top - 0.94, 0.034, 0.04)

## Splice's workshop inside: oil-dark lower wall, pale upper paint, tool
## boards with the shapes of the tools that were taken, and a work lamp.
func _workshop(basis: Basis, origin: Vector3, u0: float, u1: float, v_low: float, v_top: float) -> void:
	_slab(_tool("tint8d8673"), basis, origin, u0, v_low, u1, v_top, 0.0, PAINT_OFFSET)
	_slab(_tool("tint4a463c"), basis, origin, u0, v_low, u1, v_low + 1.2, 0.0, 0.01)
	_slab(_tool("tint2f2c27"), basis, origin, u0, v_low + 1.2, u1, v_low + 1.28, 0.0, 0.016)
	var boards: int = int(floor((u1 - u0) / 2.6))
	for index: int in range(boards):
		var u: float = u0 + (float(index) + 0.5) * (u1 - u0) / float(boards)
		var v: float = v_low + 1.55
		if _blocked(Rect2(u - 0.9, v, 1.8, 1.2)):
			continue
		_slab(_tool("shutter"), basis, origin, u - 0.85, v, u + 0.85, v + 1.15, 0.0, 0.03)
		# Painted tool outlines; most of the tools are gone.
		for tool: int in range(5):
			var x: float = u - 0.65 + float(tool) * 0.32
			var tall: float = 0.35 + 0.12 * float((tool * 7 + index) % 4)
			_slab(_tool("sill"), basis, origin, x, v + 0.2, x + 0.08, v + 0.2 + tall, 0.03, 0.034)
			if (tool + index) % 3 == 0:
				_slab(_tool("iron"), basis, origin, x - 0.02, v + 0.18, x + 0.1, v + 0.22 + tall, 0.034, 0.06)
	if u1 - u0 > 6.0:
		var lamp: Vector3 = origin + basis.x * ((u0 + u1) * 0.5) + basis.y * (v_low + 3.1)
		_slab(_tool("iron"), basis, origin, (u0 + u1) * 0.5 - 0.25, v_low + 3.0, (u0 + u1) * 0.5 + 0.25, v_low + 3.2, 0.0, 0.25)
		_slab(_tool("lit"), basis, origin, (u0 + u1) * 0.5 - 0.2, v_low + 2.98, (u0 + u1) * 0.5 + 0.2, v_low + 3.0, 0.05, 0.24)
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "WorkLamp"
		light.light_color = Color("ffd7a0")
		light.light_energy = 1.3
		light.omni_range = 7.0
		light.shadow_enabled = false
		light.position = lamp + basis.z * 0.6
		root.add_child(light)

# --- Trams, rails, wires and aerials ----------------------------------------------

## A tram car left where it stopped: cream and green livery, a band of
## windows, a cab windscreen with its lamp out and the pantograph folded.
## `cab` names an end face whose windscreen stays open for a presenter that
## glazes it and furnishes the cab behind it; empty keeps every end shut.
func _tram(low: Vector3, high: Vector3, cab: String = "") -> void:
	var centre: Vector3 = (low + high) * 0.5
	var size: Vector3 = high - low
	_avoid = []
	for face: String in ["north", "south", "east", "west"]:
		var basis: Basis = MapDecoration.face_basis(face)
		var origin: Vector3 = centre + basis.z * absf(basis.z.dot(size)) * 0.5
		var w: float = absf(basis.x.dot(size)) * 0.5
		var h: float = size.y * 0.5
		# Cream over green, the colour the vote carried. Grimed the morning
		# after; repainted, still green, years on.
		var cream: String = "tintc9bd9a" if mood == "night_works" else ("tint8f8670" if mood == "aftermath" else "tinte4d8b4")
		var green: String = "tint3f6f62" if mood == "night_works" else ("tint2f4a42" if mood == "aftermath" else "tint3f7f62")
		var band_low: float = -h + size.y * 0.45
		var band_high: float = h - size.y * 0.12
		if face == cab:
			# Cream round an open windscreen, which the presenter glazes.
			_slab(_tool(cream), basis, origin, -w, -h, w, band_low, 0.0, PAINT_OFFSET)
			_slab(_tool(cream), basis, origin, -w, band_high, w, h, 0.0, PAINT_OFFSET)
			_slab(_tool(cream), basis, origin, -w, band_low, -w + 0.2, band_high, 0.0, PAINT_OFFSET)
			_slab(_tool(cream), basis, origin, w - 0.2, band_low, w, band_high, 0.0, PAINT_OFFSET)
		else:
			_slab(_tool(cream), basis, origin, -w, -h, w, h, 0.0, PAINT_OFFSET)
		_slab(_tool(green), basis, origin, -w, -h, w, -h + size.y * 0.32, 0.0, 0.01)
		_slab(_tool("iron"), basis, origin, -w, -h, w, -h + 0.25, 0.0, 0.03)
		if w > 2.5:
			var panes: int = int(floor(w * 2.0 / 1.3))
			var pitch: float = w * 2.0 / float(panes)
			for pane: int in range(panes):
				var u: float = -w + (float(pane) + 0.5) * pitch
				_slab(_tool("tram_glass"), basis, origin, u - pitch * 0.4, band_low, u + pitch * 0.4, band_high, 0.0, 0.02)
		else:
			if face != cab:
				_slab(_tool("tram_glass"), basis, origin, -w + 0.2, band_low, w - 0.2, band_high, 0.0, 0.02)
			_slab(_tool("lit_dark"), basis, origin, -0.2, -h + 0.45, 0.2, -h + 0.7, 0.0, 0.05)
	var up: Basis = MapDecoration.face_basis("up")
	var lid: Vector3 = centre + Vector3(0.0, size.y * 0.5, 0.0)
	_slab(_tool("tint5a4e44" if mood == "day" else "tint7d4434"), up, lid, -size.x * 0.5, -size.z * 0.5, size.x * 0.5, size.z * 0.5, 0.0, PAINT_OFFSET)
	_slab(_tool("iron"), up, lid, -0.6, -0.5, 0.6, 0.5, 0.0, 0.12)
	_slab(_tool("iron"), up, lid, -0.04, -0.04, size.x * 0.3, 0.04, 0.12, 0.2)

## Grooved rails flush in the road, under any work mark, and the overhead wire
## with its span wires to the walls.
func _rails(from: Vector3, to: Vector3, wall_a: float, wall_b: float, wire_height: float) -> void:
	var along: Vector3 = (to - from).normalized()
	var side: Vector3 = Vector3(-along.z, 0.0, along.x)
	var tool: SurfaceTool = _tool("iron")
	for gauge: float in [-0.72, 0.72]:
		var a: Vector3 = from + side * gauge + Vector3(0.0, 0.012, 0.0)
		var b: Vector3 = to + side * gauge + Vector3(0.0, 0.012, 0.0)
		_geometry.quad(tool, a - side * 0.05, b - side * 0.05, b + side * 0.05, a + side * 0.05, Vector3.UP)
	var length: float = from.distance_to(to)
	var wire: Node3D = Node3D.new()
	wire.name = "OverheadWire"
	root.add_child(wire)
	var lift: Vector3 = Vector3(0.0, wire_height, 0.0)
	var contact: MeshInstance3D = _box_view(wire, Vector3(0.04, 0.04, length), (from + to) * 0.5 + lift, _material("iron"))
	contact.look_at_from_position(contact.position, to + lift, Vector3.UP)
	var spans: int = maxi(1, int(floor(length / 9.0)))
	for index: int in range(spans + 1):
		var at: Vector3 = from + along * (float(index) * length / float(spans))
		var a: Vector3 = at
		var b: Vector3 = at
		if absf(side.x) > 0.5:
			a.x = wall_a
			b.x = wall_b
		else:
			a.z = wall_a
			b.z = wall_b
		var high: Vector3 = lift + Vector3(0.0, 0.35, 0.0)
		var span: MeshInstance3D = _box_view(wire, Vector3(0.03, 0.03, a.distance_to(b)), (a + b) * 0.5 + high, _material("iron"))
		span.look_at_from_position(span.position, b + high, Vector3.UP)
		_box_view(wire, Vector3(0.03, 0.4, 0.03), at + lift + Vector3(0.0, 0.17, 0.0), _material("iron"))

## Striped canvas over an awning solid and a scalloped hem on its long edges.
func _awning(low: Vector3, high: Vector3, index: int) -> void:
	var size: Vector3 = high - low
	var centre: Vector3 = (low + high) * 0.5
	var up: Basis = MapDecoration.face_basis("up")
	var lid: Vector3 = centre + Vector3(0.0, size.y * 0.5, 0.0)
	_avoid = []
	var stripes: int = 8
	var width: float = size.x / float(stripes)
	for stripe: int in range(stripes):
		var key: String = "canvas%d" % ((index + stripe % 2 * 2) % CANVAS.size())
		var u: float = -size.x * 0.5 + float(stripe) * width
		_slab(_tool(key), up, lid, u, -size.z * 0.5, u + width, size.z * 0.5, 0.0, PAINT_OFFSET)
		for face: String in ["north", "south"]:
			var basis: Basis = MapDecoration.face_basis(face)
			var origin: Vector3 = centre + basis.z * size.z * 0.5
			var along: float = u + width * 0.5
			# The hem hangs a little below the awning, cut in scallops.
			var a: float = along * basis.x.dot(Vector3.RIGHT)
			_slab(_tool(key), basis, origin, a - width * 0.5, -size.y * 0.5 - 0.28, a + width * 0.5, size.y * 0.5, 0.0, 0.012)
			_slab(_tool(key), basis, origin, a - width * 0.25, -size.y * 0.5 - 0.4, a + width * 0.25, -size.y * 0.5 - 0.28, 0.0, 0.012)

## Soil and dry stalks in a planter; the stems stand only a hand high.
func _planter(low: Vector3, high: Vector3) -> void:
	var up: Basis = MapDecoration.face_basis("up")
	var size: Vector3 = high - low
	var lid: Vector3 = (low + high) * 0.5 + Vector3(0.0, size.y * 0.5, 0.0)
	_avoid = []
	_slab(_tool("soil"), up, lid, -size.x * 0.5 + 0.12, -size.z * 0.5 + 0.12, size.x * 0.5 - 0.12, size.z * 0.5 - 0.12, 0.0, 0.01)
	if mood in ["later", "day"]:
		# Planted and watered: leaves, a few flowers.
		for index: int in range(14):
			var u: float = -size.x * 0.5 + 0.3 + float(index % 7) * (size.x - 0.6) / 6.0
			var v: float = (-0.25 if index < 7 else 0.25) * size.z * 0.5
			var tall: float = 0.22 + 0.08 * float((index * 5) % 4)
			_slab(_tool("leaf" if index % 3 else "leaf_dark"), up, lid, u - 0.1, v - 0.1, u + 0.1, v + 0.1, 0.01, tall)
			if index % 4 == 1:
				_slab(_tool(["bloom_a", "bloom_b", "bloom_c"][index % 3]), up, lid, u - 0.06, v - 0.06, u + 0.06, v + 0.06, tall, tall + 0.08)
		return
	for index: int in range(9):
		var u: float = -size.x * 0.5 + 0.3 + float(index) * (size.x - 0.6) / 8.0
		var v: float = (0.18 if index % 2 == 0 else -0.2) * size.z * 0.5
		var tall: float = 0.18 + 0.05 * float((index * 5) % 4)
		_slab(_tool("stalk"), up, lid, u - 0.02, v - 0.02, u + 0.02, v + 0.02, 0.01, tall)

## The well: a dark still surface inside its rim.
func _well(low: Vector3, high: Vector3) -> void:
	var up: Basis = MapDecoration.face_basis("up")
	var size: Vector3 = high - low
	var lid: Vector3 = (low + high) * 0.5 + Vector3(0.0, size.y * 0.5, 0.0)
	_avoid = []
	_slab(_tool("water"), up, lid, -size.x * 0.5 + 0.3, -size.z * 0.5 + 0.3, size.x * 0.5 - 0.3, size.z * 0.5 - 0.3, 0.0, 0.008)
	_slab(_tool("iron"), up, lid, -0.04, -size.z * 0.5 + 0.3, 0.04, size.z * 0.5 - 0.3, 0.008, 0.06)

## Tar repairs on a flat roof, and the flashing along its edges.
func _roof(low: Vector3, high: Vector3) -> void:
	var up: Basis = MapDecoration.face_basis("up")
	var size: Vector3 = high - low
	var lid: Vector3 = (low + high) * 0.5 + Vector3(0.0, size.y * 0.5, 0.0)
	_avoid = []
	var patches: int = int(size.x * size.z / 90.0)
	for index: int in range(patches):
		var w: float = 1.2 + float(_roll(30)) * 0.1
		var d: float = 0.8 + float(_roll(24)) * 0.1
		var u: float = -size.x * 0.5 + 0.5 + float(_roll(1000)) / 1000.0 * (size.x - w - 1.0)
		var v: float = -size.z * 0.5 + 0.5 + float(_roll(1000)) / 1000.0 * (size.z - d - 1.0)
		_slab(_tool("tar" if index % 3 else "tar_old"), up, lid, u, v, u + w, v + d, 0.0, 0.004)
	_slab(_tool("flashing"), up, lid, -size.x * 0.5, -size.z * 0.5, size.x * 0.5, -size.z * 0.5 + 0.3, 0.0, 0.006)
	_slab(_tool("flashing"), up, lid, -size.x * 0.5, size.z * 0.5 - 0.3, size.x * 0.5, size.z * 0.5, 0.0, 0.006)
	_slab(_tool("flashing"), up, lid, -size.x * 0.5, -size.z * 0.5, -size.x * 0.5 + 0.3, size.z * 0.5, 0.0, 0.006)
	_slab(_tool("flashing"), up, lid, size.x * 0.5 - 0.3, -size.z * 0.5, size.x * 0.5, size.z * 0.5, 0.0, 0.006)

func _aerial(low: Vector3, high: Vector3) -> void:
	var node: Node3D = Node3D.new()
	node.name = "Aerial"
	node.position = Vector3(low.x + 0.4, high.y, low.z + 0.4)
	root.add_child(node)
	_box_view(node, Vector3(0.05, 1.9, 0.05), Vector3(0.0, 0.95, 0.0), _material("iron"))
	for rung: int in range(3):
		var bar: MeshInstance3D = _box_view(node, Vector3(1.1 - float(rung) * 0.25, 0.03, 0.03), Vector3(0.0, 1.2 + float(rung) * 0.28, 0.0), _material("iron"))
		bar.rotation.y = 0.6

# --- Street lamps ---------------------------------------------------------------

func _lamp(lamp: Dictionary) -> void:
	var low: Vector3 = lamp["low"]
	var high: Vector3 = lamp["high"]
	var top: Vector3 = Vector3((low.x + high.x) * 0.5, high.y, (low.z + high.z) * 0.5)
	var reach: Vector3 = lamp["reach"]
	var node: Node3D = Node3D.new()
	node.name = "StreetLamp"
	node.position = top
	root.add_child(node)
	var arm: MeshInstance3D = _box_view(node, Vector3(0.12, 0.12, 0.12) + reach.abs() * 1.4, reach * 0.75 - Vector3(0.0, 0.1, 0.0), _material("iron"))
	arm.name = "Arm"
	var head: MeshInstance3D = _box_view(node, Vector3(0.5, 0.18, 0.5), reach * 1.45 - Vector3(0.0, 0.14, 0.0), _material("iron"))
	head.name = "Head"
	var state: String = str(lamp["state"])
	var bulb: MeshInstance3D = _box_view(node, Vector3(0.36, 0.06, 0.36), reach * 1.45 - Vector3(0.0, 0.25, 0.0),
		_material("bulb_dark" if state == "dead" else "bulb"))
	bulb.name = "Bulb"
	if state == "dead":
		return
	var light: SpotLight3D = SpotLight3D.new()
	light.name = "StreetLight"
	light.light_color = Color("ffc982")
	light.light_energy = 3.2
	light.spot_range = 11.0
	light.spot_angle = 58.0
	light.spot_attenuation = 0.9
	light.shadow_enabled = true
	light.position = reach * 1.45 - Vector3(0.0, 0.32, 0.0)
	light.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	node.add_child(light)
	if state == "interrupted":
		flicker.append({"mesh": bulb, "lit": _material("bulb"), "dark": _material("bulb_dark"),
			"rate": 0.53, "phase": 0.0, "duty": 0.3, "light": light, "energy": 3.2})

static func _box_view(parent: Node3D, size: Vector3, at: Vector3, finish: Material) -> MeshInstance3D:
	var view: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	view.mesh = mesh
	view.position = at
	view.material_override = finish
	parent.add_child(view)
	return view
