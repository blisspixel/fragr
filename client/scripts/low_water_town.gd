class_name LowWaterTown
extends Node3D

## The multiplayer Low Water (map 8): the free district on an evening before
## the wipe, with a Union checkpoint across the south bank. The town's own
## dressing (LowWaterDressing in its "day" mood) paints the homes, terraces,
## clinic and depot, the stopped tram, the awnings, the tank and the street
## lamps on the server's exact solids; this adds the trench rails and wire,
## the market clock's faces and the bunting strung from it to the lamps.
##
## Presentation only. Every lit lamp, painted face and hanging string stands
## on a server solid or hangs overhead; nothing here is collision, cover or a
## floor, and a solid that moved simply stays undressed.
const TownDressing = preload("res://scripts/low_water_dressing.gd")

const STREET: float = 3.0
## [low, high, face, paint, ground] on the server's solids (low_water.rs).
const FACES: Array[Dictionary] = [
	# Corner homes: a door face onto their bank and shopfronts to the trench.
	{"low": Vector3(-40, 3, -28), "high": Vector3(-34, 9, -19), "face": "east", "paint": 0, "ground": "doors"},
	{"low": Vector3(-40, 3, -28), "high": Vector3(-34, 9, -19), "face": "south", "paint": 0, "ground": "shops"},
	{"low": Vector3(-40, 3, 18), "high": Vector3(-34, 9, 28), "face": "east", "paint": 1, "ground": "doors"},
	{"low": Vector3(-40, 3, 18), "high": Vector3(-34, 9, 28), "face": "north", "paint": 1, "ground": "shops"},
	{"low": Vector3(34, 3, -28), "high": Vector3(40, 9, -19), "face": "west", "paint": 5, "ground": "doors"},
	{"low": Vector3(34, 3, -28), "high": Vector3(40, 9, -19), "face": "south", "paint": 5, "ground": "shops"},
	{"low": Vector3(34, 3, 18), "high": Vector3(40, 9, 28), "face": "west", "paint": 6, "ground": "doors"},
	{"low": Vector3(34, 3, 18), "high": Vector3(40, 9, 28), "face": "north", "paint": 6, "ground": "shops"},
	# The clinic wing and the depot shed.
	{"low": Vector3(-39, 3, 10), "high": Vector3(-34, 7, 17), "face": "east", "paint": 2, "ground": "doors"},
	{"low": Vector3(-39, 3, 10), "high": Vector3(-34, 7, 17), "face": "north", "paint": 2, "ground": "doors"},
	{"low": Vector3(34, 3, 10), "high": Vector3(39, 7, 17), "face": "west", "paint": 4, "ground": "shops"},
	# The back terraces, fronts and gable ends onto the spawn yards.
	{"low": Vector3(-32, 3, -42), "high": Vector3(-14, 9.5, -36), "face": "south", "paint": 3, "ground": "doors"},
	{"low": Vector3(-32, 3, -42), "high": Vector3(-14, 9.5, -36), "face": "east", "paint": 3, "ground": "doors"},
	{"low": Vector3(14, 3, -42), "high": Vector3(32, 9.5, -36), "face": "south", "paint": 2, "ground": "shops"},
	{"low": Vector3(14, 3, -42), "high": Vector3(32, 9.5, -36), "face": "west", "paint": 2, "ground": "doors"},
	{"low": Vector3(-32, 3, 36), "high": Vector3(-14, 9.5, 42), "face": "north", "paint": 4, "ground": "shops"},
	{"low": Vector3(-32, 3, 36), "high": Vector3(-14, 9.5, 42), "face": "east", "paint": 4, "ground": "doors"},
	{"low": Vector3(14, 3, 36), "high": Vector3(32, 9.5, 42), "face": "north", "paint": 0, "ground": "doors"},
	{"low": Vector3(14, 3, 36), "high": Vector3(32, 9.5, 42), "face": "west", "paint": 0, "ground": "doors"},
]
const BUILDINGS: Array[Dictionary] = [
	{"low": Vector3(-40, 3, -28), "high": Vector3(-34, 9, -19)},
	{"low": Vector3(-40, 3, 18), "high": Vector3(-34, 9, 28)},
	{"low": Vector3(34, 3, -28), "high": Vector3(40, 9, -19)},
	{"low": Vector3(34, 3, 18), "high": Vector3(40, 9, 28)},
	{"low": Vector3(-32, 3, -42), "high": Vector3(-14, 9.5, -36)},
	{"low": Vector3(14, 3, -42), "high": Vector3(32, 9.5, -36)},
	{"low": Vector3(-32, 3, 36), "high": Vector3(-14, 9.5, 42)},
	{"low": Vector3(14, 3, 36), "high": Vector3(32, 9.5, 42)},
]
const TRAM: Dictionary = {"low": Vector3(-17, 0, -4), "high": Vector3(-5, 2.5, 0.4)}
const AWNINGS: Array[Dictionary] = [
	{"low": Vector3(-17, 5.6, -23), "high": Vector3(-11, 5.9, -17)},
	{"low": Vector3(-16, 5.6, 13), "high": Vector3(-10, 5.9, 19)},
	{"low": Vector3(18, 5.6, 20), "high": Vector3(26, 5.9, 25.5)},
]
const TANKS: Array[Dictionary] = [
	{"low": Vector3(14, 5, -24), "high": Vector3(18, 9, -20), "ladder": "west"},
]
## Lamp posts (server LAMPS), each arm reaching over the trench.
const LAMPS: Array[Dictionary] = [
	{"at": Vector2(-8, -5.2), "reach": Vector3(0, 0, 1), "state": "lit"},
	{"at": Vector2(16, -5.2), "reach": Vector3(0, 0, 1), "state": "lit"},
	{"at": Vector2(-4, 5.2), "reach": Vector3(0, 0, -1), "state": "interrupted"},
	{"at": Vector2(16.5, 5.2), "reach": Vector3(0, 0, -1), "state": "lit"},
]
const LAMP_TOP: float = STREET + 6.4
## The market clock (server solid) and its bunting.
const CLOCK_LOW: Vector3 = Vector3(-3, 3, 9)
const CLOCK_HIGH: Vector3 = Vector3(3, 8, 12)
const FLAGS: Array[Color] = [Color("d2a03c"), Color("4f8a6c"), Color("c46a3c"), Color("e2d6b4"), Color("3f6f8f")]

var dressing: TownDressing
var _flicker: Array[Dictionary] = []
var _clock: float = 0.0

## True when the map is the multiplayer town and the dressing applied.
static func applies(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != 8 or str(info.get("map_name", "")).strip_edges().to_lower() != "low water":
		return false
	for key: String in ["m04", "m05", "m19", "epilogue", "mission"]:
		if info.get(key) is Dictionary:
			return false
	return true

func build(info: Dictionary) -> void:
	name = "LowWaterTown"
	add_to_group(&"low_water_town")
	var lamps: Array = []
	for lamp: Dictionary in LAMPS:
		var at: Vector2 = lamp["at"]
		lamps.append({"low": Vector3(at.x - 0.15, STREET, at.y - 0.15), "high": Vector3(at.x + 0.15, LAMP_TOP, at.y + 0.15),
			"reach": lamp["reach"], "state": lamp["state"]})
	var aerials: Array = [BUILDINGS[0], BUILDINGS[3], BUILDINGS[5], BUILDINGS[6]]
	dressing = TownDressing.new()
	dressing.mood = "day"
	dressing.layout = {
		"faces": FACES, "trams": [TRAM], "awnings": AWNINGS, "tanks": TANKS, "lamps": lamps,
		"roofs": BUILDINGS, "aerials": aerials, "planters": [], "wells": [],
		# The tram line runs the trench's length, its wire under the bridges.
		"rails": [{"with": TRAM, "from": Vector3(-42, 0, -1.8), "to": Vector3(42, 0, -1.8),
			"wall_a": -4.0, "wall_b": 4.0, "wire": 2.45}],
	}
	dressing.build(self, info)
	_flicker = dressing.flicker
	var solids: Array = info.get("solids", [])
	if not TownDressing._find(solids, CLOCK_LOW, CLOCK_HIGH).is_empty():
		_build_clock()
		_build_bunting()
	for building: Dictionary in BUILDINGS:
		if not TownDressing._find(solids, building["low"], building["high"]).is_empty():
			_roof(building["low"], building["high"])
	_build_market()
	_build_kerbs()

## Two dials near the clock's top, north and south, lit from behind.
func _build_clock() -> void:
	var face: StandardMaterial3D = StandardMaterial3D.new()
	face.albedo_color = Color("efe2c2")
	face.emission_enabled = true
	face.emission = Color("ffd9a0")
	face.emission_energy_multiplier = 0.55
	face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var rim: StandardMaterial3D = StandardMaterial3D.new()
	rim.albedo_color = Color("2b2620")
	rim.roughness = 0.9
	var centre: Vector3 = (CLOCK_LOW + CLOCK_HIGH) * 0.5
	for side: float in [-1.0, 1.0]:
		var z: float = centre.z + side * ((CLOCK_HIGH.z - CLOCK_LOW.z) * 0.5 + 0.03)
		var at: Vector3 = Vector3(centre.x, CLOCK_HIGH.y - 1.2, z)
		var dial: MeshInstance3D = MeshInstance3D.new()
		var disc: CylinderMesh = CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.04
		disc.radial_segments = 16
		dial.mesh = disc
		dial.material_override = face
		dial.position = at
		dial.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		add_child(dial)
		var ring: MeshInstance3D = MeshInstance3D.new()
		var band: CylinderMesh = CylinderMesh.new()
		band.top_radius = 1.12
		band.bottom_radius = 1.12
		band.height = 0.03
		band.radial_segments = 16
		ring.mesh = band
		ring.material_override = rim
		ring.position = at - Vector3(0, 0, side * 0.01)
		ring.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		add_child(ring)
		# Twenty to seven: the market's evening.
		for hand: Array in [[0.75, 0.08, -2.1], [0.5, 0.11, 0.35]]:
			var arm: MeshInstance3D = TownDressing._box_view(self, Vector3(float(hand[1]), float(hand[0]), 0.02), at + Vector3(0, 0, side * 0.04), rim)
			arm.rotation.z = float(hand[2])
			arm.position += Vector3(-sin(float(hand[2])), cos(float(hand[2])), 0.0) * float(hand[0]) * 0.5

## Flag strings from the clock's top to each lamp head, sagging overhead.
func _build_bunting() -> void:
	var cloth: Array[StandardMaterial3D] = []
	for colour: Color in FLAGS:
		var flag: StandardMaterial3D = StandardMaterial3D.new()
		flag.albedo_color = colour
		flag.cull_mode = BaseMaterial3D.CULL_DISABLED
		flag.roughness = 1.0
		cloth.append(flag)
	var cord: StandardMaterial3D = StandardMaterial3D.new()
	cord.albedo_color = Color("2b2620")
	var top: Vector3 = Vector3(0.0, CLOCK_HIGH.y + 0.2, (CLOCK_LOW.z + CLOCK_HIGH.z) * 0.5)
	var index: int = 0
	for lamp: Dictionary in LAMPS:
		var at: Vector2 = lamp["at"]
		var end: Vector3 = Vector3(at.x, LAMP_TOP - 0.2, at.y)
		var length: float = top.distance_to(end)
		var count: int = int(length / 0.9)
		for step: int in range(1, count):
			var t: float = float(step) / float(count)
			var point: Vector3 = top.lerp(end, t) - Vector3(0.0, sin(t * PI) * 1.1, 0.0)
			var flag: MeshInstance3D = MeshInstance3D.new()
			var quad: PrismMesh = PrismMesh.new()
			quad.size = Vector3(0.36, 0.42, 0.02)
			flag.mesh = quad
			flag.material_override = cloth[(index + step) % cloth.size()]
			flag.position = point - Vector3(0.0, 0.22, 0.0)
			flag.rotation = Vector3(PI, atan2(end.x - top.x, end.z - top.z) + PI * 0.5, 0.0)
			add_child(flag)
		var string: MeshInstance3D = TownDressing._box_view(self, Vector3(0.02, 0.02, length), (top + end) * 0.5 - Vector3(0.0, 0.7, 0.0), cord)
		string.look_at_from_position(string.position, end - Vector3(0.0, 0.7, 0.0), Vector3.UP)
		index += 1

func _process(delta: float) -> void:
	_clock += delta
	for lamp: Dictionary in _flicker:
		var on: bool = fmod(_clock * float(lamp["rate"]) + float(lamp["phase"]), 1.0) > float(lamp["duty"])
		(lamp["mesh"] as MeshInstance3D).material_override = lamp["lit"] if on else lamp["dark"]
		if lamp.get("light") is Light3D:
			(lamp["light"] as Light3D).light_energy = float(lamp["energy"]) if on else 0.0

## A flat roof's membrane over the whole top, under the dressing's patches,
## so a roof reads as a roof from a deck and from above, not as paving.
func _roof(low: Vector3, high: Vector3) -> void:
	var membrane: StandardMaterial3D = StandardMaterial3D.new()
	membrane.albedo_color = Color("5d5249")
	membrane.roughness = 1.0
	var view: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(high.x - low.x - 0.1, high.z - low.z - 0.1)
	view.mesh = plane
	view.material_override = membrane
	view.position = Vector3((low.x + high.x) * 0.5, high.y + 0.002, (low.z + high.z) * 0.5)
	add_child(view)

## Market goods laid out on cloths by the stall, the canopy and the stop:
## flat on the street, never cover.
const CLOTHS: Array[Dictionary] = [
	{"at": Vector2(-13.5, -14.5), "size": Vector2(2.4, 1.6), "colour": Color("8a4f3a")},
	{"at": Vector2(-19.5, -12.0), "size": Vector2(1.8, 1.8), "colour": Color("4f6a5c")},
	{"at": Vector2(-13.0, 21.5), "size": Vector2(2.2, 1.4), "colour": Color("b08a4a")},
	{"at": Vector2(5.0, -8.5), "size": Vector2(2.0, 1.5), "colour": Color("6a5a8a")},
	{"at": Vector2(24.5, 11.5), "size": Vector2(2.0, 1.6), "colour": Color("8a6a3a")},
]
const GOODS: Array[Color] = [Color("d9b45a"), Color("b8553a"), Color("6f9a5a"), Color("d8cfb4"), Color("8c6a4a")]

func _build_market() -> void:
	var index: int = 0
	for cloth: Dictionary in CLOTHS:
		var at: Vector2 = cloth["at"]
		var size: Vector2 = cloth["size"]
		var fabric: StandardMaterial3D = StandardMaterial3D.new()
		fabric.albedo_color = cloth["colour"]
		fabric.roughness = 1.0
		var view: MeshInstance3D = MeshInstance3D.new()
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = size
		view.mesh = plane
		view.material_override = fabric
		view.position = Vector3(at.x, STREET + 0.012, at.y)
		add_child(view)
		# Small goods in rows: fruit, tins, folded cloth, under a hand high.
		for row: int in range(2):
			for column: int in range(4):
				var item: StandardMaterial3D = StandardMaterial3D.new()
				item.albedo_color = GOODS[(index + row * 3 + column) % GOODS.size()]
				var u: float = -size.x * 0.5 + 0.3 + float(column) * (size.x - 0.6) / 3.0
				var v: float = (-0.25 if row == 0 else 0.25) * size.y
				var height: float = 0.08 + 0.04 * float((index + column) % 3)
				TownDressing._box_view(self, Vector3(0.28, height, 0.22), Vector3(at.x + u, STREET + 0.012 + height * 0.5, at.y + v), item)
		index += 1

## Dressed kerb stones along both banks' trench edges, and a granite band
## where the tram stops: flat paving, a step-coloured edge to read the drop.
func _build_kerbs() -> void:
	var stone: StandardMaterial3D = StandardMaterial3D.new()
	stone.albedo_color = Color("8f877a")
	stone.roughness = 1.0
	for z: float in [-4.45, 4.45]:
		for span: Vector2 in [Vector2(-42.0, -32.0), Vector2(-28.0, 28.0), Vector2(32.0, 42.0)]:
			var view: MeshInstance3D = MeshInstance3D.new()
			var plane: PlaneMesh = PlaneMesh.new()
			plane.size = Vector2(span.y - span.x, 0.9)
			view.mesh = plane
			view.material_override = stone
			view.position = Vector3((span.x + span.y) * 0.5, STREET + 0.008, z)
			add_child(view)
