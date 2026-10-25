class_name StillHereRefuge
extends Node3D

## Still Here presentation: the refuge at the end of Pier 4 in the first light
## after the reprieve, then the same court years later. Low Water's homes in
## the shared Low Water dressing, the people the run actually brought, the
## few lines they say when you walk past, the salvaged harbour display on the
## quay and the view back toward the waterworks and home. Every piece
## presents server facts or scenery: the people stand where the server puts
## their bodies, the world turns when the server says so, and nothing here is
## collision, cover or a control.
signal solids_hidden(indices: Array[int])

const TownDressing = preload("res://scripts/low_water_dressing.gd")
const LatchSeat = preload("res://scripts/m19_latch_seat.gd")
const Geometry = preload("res://scripts/model_geometry.gd")

const WARM: Color = Color("ffc98a")
const LAMP: Color = Color("ffd9a0")
const DISPLAY_DARK: Color = Color("121a1c")
## The harbour display's own voice on the pier in level 20. Years on the
## board times the ferry in the refuge's warm amber; the one fragment comes
## back in this colour, and nothing says why.
const DISPLAY_TEXT: Color = Color("a9d4cc")
const FERRY_TEXT: Color = Color("ffc27a")
const ORRIN: Color = Color("c89058")
const SORREL: Color = Color("a87a8a")
const MARA_COAT: Color = Color("8a4a2e")
## Lines a person says once per world when you walk within this of them.
const HEAR_DISTANCE: float = 3.4
## Some people are heard from further: Latch looks up from the ledger as you
## come into the workshop, not only once you are at the table.
const HEARING: Dictionary[String, float] = {"aftermath/latch": 5.5}
## Seated eye height on the quay bench, metres above the paving.
const SEATED_EYE: float = 1.22
## Exact authored bodies this presenter dresses or draws itself.
const SOLIDS: Dictionary[String, Array] = {
	"quay_rail_w_n": [Vector3(-30.4, 0, 3.2), Vector3(-30, 1.1, 16.4)],
	"quay_rail_w_s": [Vector3(-30.4, 0, -16.4), Vector3(-30, 1.1, -3.2)],
	"quay_rail_n": [Vector3(-30.4, 0, 16), Vector3(-20, 1.1, 16.4)],
	"quay_rail_s": [Vector3(-30.4, 0, -16.4), Vector3(-20, 1.1, -16)],
	"pier_rail_n": [Vector3(-40, 0, 3.2), Vector3(-30.4, 1.1, 3.5)],
	"pier_rail_s": [Vector3(-40, 0, -3.5), Vector3(-30.4, 1.1, -3.2)],
	"pier_barricade": [Vector3(-38.2, 0, -3.2), Vector3(-37, 1.5, 3.2)],
	"ferry_gate": [Vector3(-37.8, 0, -3.2), Vector3(-37.6, 1.1, 3.2)],
	"bench_quay": [Vector3(-26.0, 0, 4.8), Vector3(-25.4, 0.46, 7.2)],
	"ferry_board": [Vector3(-30.3, 0, 8.2), Vector3(-29.9, 3.2, 10.8)],
	"repair_table": [Vector3(24.6, 0, -9.8), Vector3(27.2, 0.9, -7.8)],
	"bench_back": [Vector3(29.2, 0, -11), Vector3(30, 0.95, -3)],
	"motor_stand": [Vector3(28.0, 0, -13.6), Vector3(29.4, 1.0, -12.2)],
	"meal_table": [Vector3(-7, 0, -6.6), Vector3(-1, 0.78, -5.4)],
	"bench_mn": [Vector3(-7, 0, -5.1), Vector3(-1, 0.45, -4.7)],
	"bench_ms": [Vector3(-7, 0, -7.3), Vector3(-1, 0.45, -6.9)],
	"empty_chair": [Vector3(-0.6, 0, -6.3), Vector3(0.0, 0.9, -5.7)],
	"standpipe": [Vector3(-12.3, 0, 3.2), Vector3(-11.7, 1.2, 3.8)],
	"fountain": [Vector3(-13.6, 0, 2.0), Vector3(-10.4, 0.6, 5.0)],
	"rubble_a": [Vector3(-0.6, 0, -14), Vector3(3.4, 1.1, -11.8)],
	"rubble_b": [Vector3(3.0, 0, 11.6), Vector3(6.2, 0.9, 14)],
	"cot_a": [Vector3(-18, 0, 9.2), Vector3(-16, 0.5, 10.0)],
	"cot_b": [Vector3(-18, 0, 11.2), Vector3(-16, 0.5, 12.0)],
	"crate_a": [Vector3(-14.4, 0, 8.4), Vector3(-13.4, 0.8, 9.4)],
	"crate_b": [Vector3(8.6, 0, -10.6), Vector3(9.6, 0.7, -9.6)],
	"crate_c": [Vector3(13.0, 0, -9.0), Vector3(14.0, 0.8, -8.0)],
	"tram_stalled": [Vector3(15.6, 0, -13), Vector3(18.4, 3.2, -1.5)],
	"tram_running": [Vector3(15.6, 0, 1.5), Vector3(18.4, 3.2, 14)],
	"stop_kiosk": [Vector3(12.4, 0, 16), Vector3(14.2, 2.6, 20)],
	"gate_post_n": [Vector3(-20.3, 0, 2.6), Vector3(-18.7, 2.8, 3.4)],
	"gate_post_s": [Vector3(-20.3, 0, -3.4), Vector3(-18.7, 2.8, -2.6)],
	"store_a": [Vector3(-19, 0, -40), Vector3(-11, 6.4, -14)],
	"planter_a": [Vector3(-18.6, 0, 6), Vector3(-17.2, 0.6, 8.6)],
	"planter_b": [Vector3(8, 0, 9.6), Vector3(11, 0.6, 11)],
}
## Bodies drawn here in their own materials, so their collision box is hidden.
const DRAWN: Array[String] = ["quay_rail_w_n", "quay_rail_w_s", "quay_rail_n", "quay_rail_s", "pier_rail_n",
	"pier_rail_s", "pier_barricade", "ferry_gate", "bench_quay", "ferry_board", "repair_table", "bench_back",
	"motor_stand", "meal_table", "bench_mn", "bench_ms", "empty_chair", "standpipe", "fountain", "rubble_a",
	"rubble_b", "cot_a", "cot_b", "crate_a", "crate_b", "crate_c", "gate_post_n", "gate_post_s"]
## The Low Water dressing for this court: [low, high, face, paint, ground,
## optional span]. Faces follow MapDecoration's bases.
const FACES: Array[Dictionary] = [
	{"low": Vector3(-19, 0, 14), "high": Vector3(-11, 6.4, 40), "face": "north", "paint": 2, "ground": "doors"},
	{"low": Vector3(-11, 0, 14), "high": Vector3(-5, 9.6, 40), "face": "north", "paint": 0, "ground": "doors"},
	{"low": Vector3(-5, 0, 14), "high": Vector3(1, 9.6, 40), "face": "north", "paint": 5, "ground": "doors"},
	{"low": Vector3(1, 0, 14), "high": Vector3(7, 6.4, 40), "face": "north", "paint": 1, "ground": "shops"},
	{"low": Vector3(7, 0, 14), "high": Vector3(12, 9.6, 40), "face": "north", "paint": 3, "ground": "doors"},
	{"low": Vector3(-19, 0, 14), "high": Vector3(-11, 6.4, 40), "face": "west", "paint": 2, "ground": "none"},
	{"low": Vector3(7, 0, 14), "high": Vector3(12, 9.6, 40), "face": "east", "paint": 3, "ground": "shops"},
	{"low": Vector3(-19, 0, -40), "high": Vector3(-11, 6.4, -14), "face": "south", "paint": 4, "ground": "shops"},
	{"low": Vector3(-11, 0, -40), "high": Vector3(-1, 6.4, -14), "face": "south", "paint": 0, "ground": "shops"},
	{"low": Vector3(-1, 0, -40), "high": Vector3(6, 9.6, -14), "face": "south", "paint": 6, "ground": "shops"},
	{"low": Vector3(6, 0, -40), "high": Vector3(12, 6.4, -14), "face": "south", "paint": 1, "ground": "shops"},
	{"low": Vector3(-19, 0, -40), "high": Vector3(-11, 6.4, -14), "face": "west", "paint": 4, "ground": "none"},
	{"low": Vector3(6, 0, -40), "high": Vector3(12, 6.4, -14), "face": "east", "paint": 1, "ground": "doors"},
	{"low": Vector3(22, 0, -1.5), "high": Vector3(31, 9.6, 30), "face": "west", "paint": 5, "ground": "doors"},
	{"low": Vector3(22, 0, -30), "high": Vector3(31, 6.4, -14.5), "face": "west", "paint": 2, "ground": "shops"},
	{"low": Vector3(12, 0, 30), "high": Vector3(40, 9.6, 40), "face": "north", "paint": 0, "ground": "shops"},
	{"low": Vector3(12, 0, -40), "high": Vector3(40, 6.4, -30), "face": "south", "paint": 3, "ground": "shops"},
	{"low": Vector3(30, 0, -14.5), "high": Vector3(31, 4.6, -1.5), "face": "west", "paint": 0, "ground": "workshop"},
	{"low": Vector3(22, 0, -1.5), "high": Vector3(31, 9.6, 30), "face": "north", "paint": 0, "ground": "workshop", "span": Vector2(22, 30)},
	{"low": Vector3(22, 0, -30), "high": Vector3(31, 6.4, -14.5), "face": "south", "paint": 0, "ground": "workshop", "span": Vector2(22, 30)},
	{"low": Vector3(-20, 0, 2.6), "high": Vector3(-19, 1.3, 16.4), "face": "west", "paint": 1, "ground": "none"},
	{"low": Vector3(-20, 0, 2.6), "high": Vector3(-19, 1.3, 16.4), "face": "east", "paint": 1, "ground": "none"},
	{"low": Vector3(-20, 0, -16.4), "high": Vector3(-19, 1.3, -2.6), "face": "west", "paint": 1, "ground": "none"},
	{"low": Vector3(-20, 0, -16.4), "high": Vector3(-19, 1.3, -2.6), "face": "east", "paint": 1, "ground": "none"},
]
const TANKS: Array[Dictionary] = [
	{"low": Vector3(-9.5, 9.6, 26), "high": Vector3(-6.5, 12.8, 29), "ladder": "north"},
	{"low": Vector3(8, 9.6, 30), "high": Vector3(11, 12.8, 33), "ladder": "west"},
	{"low": Vector3(25, 9.6, 10), "high": Vector3(28, 12.8, 13), "ladder": "west"},
]
const TRAMS: Array[Dictionary] = [
	{"low": Vector3(15.6, 0, -13), "high": Vector3(18.4, 3.2, -1.5)},
	{"low": Vector3(15.6, 0, 1.5), "high": Vector3(18.4, 3.2, 14)},
]
const PLANTERS: Array[Dictionary] = [
	{"low": Vector3(-18.6, 0, 6), "high": Vector3(-17.2, 0.6, 8.6)},
	{"low": Vector3(8, 0, 9.6), "high": Vector3(11, 0.6, 11)},
	{"low": Vector3(-17.8, 0, -12), "high": Vector3(-15.2, 0.6, -10.6)},
]
const RAILS: Array[Dictionary] = [
	{"with": {"low": Vector3(12.4, 0, 16), "high": Vector3(14.2, 2.6, 20)}, "from": Vector3(17, 0, -28.5), "to": Vector3(17, 0, 30), "wall_a": 12.0, "wall_b": 22.0, "wire": 5.8},
]
## A later face who is somebody from the first light keeps their look and
## their games number across the years.
const SAME_PERSON: Dictionary[String, String] = {"car_family": "car_family_a", "entrant": "entrant_b", "bus_gardener": "bus_b"}
## What people say, by world and person. Speaker labels are part of the copy.
const LINES: Dictionary[String, String] = {
	"aftermath/latch": "STILL_HERE_LINE_LATCH_COUNTING",
	"aftermath/tern": "STILL_HERE_LINE_TERN_WATCHING",
	"aftermath/mara": "STILL_HERE_LINE_MARA_WATER",
	"aftermath/ascender": "STILL_HERE_LINE_ASCENDER",
	"aftermath/kneeler": "STILL_HERE_LINE_KNEELER",
	"aftermath/spared": "STILL_HERE_LINE_SPARED",
	"aftermath/next_district": "STILL_HERE_LINE_NEXT_DISTRICT",
	"aftermath/edda": "STILL_HERE_LINE_EDDA_NEXT",
	"aftermath/lamp_keeper": "STILL_HERE_LINE_LAMP_KEEPER",
	"aftermath/splice": "STILL_HERE_LINE_SPLICE_CURSED",
	"aftermath/mechanic": "STILL_HERE_LINE_MECHANIC",
	"aftermath/orrin": "STILL_HERE_LINE_ORRIN_NAMES",
	"aftermath/bus_b": "STILL_HERE_LINE_BUS_WAIT",
	"aftermath/leaving": "STILL_HERE_LINE_LEAVING",
	"aftermath/car_family_a": "STILL_HERE_LINE_CAR_FAMILY",
	"later/latch": "STILL_HERE_LINE_LATCH_VIEW",
	"later/sorrel": "STILL_HERE_LINE_SORREL_DOORS",
	"later/edda": "STILL_HERE_LINE_EDDA_MORNING",
	"later/clinic_keeper": "STILL_HERE_LINE_CLINIC_KEEPER",
	"later/splice": "STILL_HERE_LINE_SPLICE_FIFTH",
	"later/tern": "STILL_HERE_LINE_TERN_FERRY",
	"later/orrin": "STILL_HERE_LINE_ORRIN_PLANTED",
	"later/mara": "STILL_HERE_LINE_MARA_VOTE",
	"later/trees": "STILL_HERE_LINE_TREES",
	"later/kitchen": "STILL_HERE_LINE_KITCHEN",
	"later/entrant": "STILL_HERE_LINE_ENTRANT",
	"later/bus_gardener": "STILL_HERE_LINE_GARDENER",
}
## Two people answer each other; the second line follows the first.
const REPLIES: Dictionary[String, String] = {
	"aftermath/spared": "aftermath/next_district",
	"later/trees": "later/kitchen",
	"later/mara": "",
}

var _shape: RefCounted = Geometry.new()
var _info: Dictionary = {}
var geometry: Dictionary = {}
var later: bool = false
var refuge: Dictionary = {}
var _static: Node3D
var _people_root: Node3D
var _absence_root: Node3D
var people: Dictionary[String, Node3D] = {}
var _spoken: Dictionary[String, bool] = {}
var caption: SpeakerCaption
var _ferry_lines: Array[Label3D] = []
## The ferry board's usable text width, metres.
var _ferry_width: float = 2.0
var _ferry_screen: StandardMaterial3D
var _ferry_light: OmniLight3D
var _lamps: Array[OmniLight3D] = []
var _fountain_material: ShaderMaterial
var _sway: Array[Node3D] = []
## Named people in their own rigid bodies, breathing on their calm clip.
var _calm: Array[SpliceCharacter] = []
var _clock: float = 0.0
var state_applied: int = 0
var departed: bool = false
## The ferry board's one fragment is showing.
var fragment: bool = false
## Lines are heard only by the human walking the court in first person;
## a spectator's free camera passing a doorway says nothing.
var hearing: bool = false
var hidden_solids: Array[int] = []

func clear_map() -> void:
	_info.clear()
	geometry.clear()
	later = false
	refuge.clear()
	people.clear()
	_spoken.clear()
	_ferry_lines.clear()
	_ferry_screen = null
	_ferry_light = null
	_lamps.clear()
	_fountain_material = null
	_sway.clear()
	_calm.clear()
	hidden_solids.clear()
	caption = null
	_static = null
	_people_root = null
	_absence_root = null
	state_applied = 0
	departed = false
	fragment = false
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func configure_map(info: Dictionary) -> void:
	# The later world arrives as a new MapInfo for the same attempt: keep who
	# the run brought, and what has already been said in that world.
	var kept: Dictionary = refuge.duplicate()
	var said: Dictionary[String, bool] = _spoken.duplicate()
	clear_map()
	if not info.get("epilogue") is Dictionary or not MissionState.map_error(info).is_empty():
		return
	_info = info.duplicate(true)
	geometry = _info["epilogue"]
	later = geometry["later"] == true
	refuge = kept
	_spoken = said
	_static = Node3D.new()
	_static.name = "Refuge"
	add_child(_static)
	caption = SpeakerCaption.new()
	caption.name = "RefugeCaptions"
	add_child(caption)
	# Lower than a mission's lines: the look hint under the crosshair stays clear.
	caption.label.offset_top = -170.0
	caption.label.offset_bottom = -110.0
	var backdrop: StillHereBackdrop = StillHereBackdrop.new()
	backdrop.build(float(info["half_extent"]), later)
	_static.add_child(backdrop)
	var town: TownDressing = TownDressing.new()
	town.mood = "later" if later else "aftermath"
	town.layout = {"faces": FACES, "tanks": TANKS, "trams": TRAMS, "planters": PLANTERS, "rails": RAILS,
		"lamps": [], "awnings": [], "wells": [], "roofs": [], "aerials": []}
	town.build(_static, info)
	_build_shared()
	if later:
		_build_later()
	else:
		_build_aftermath()
	hidden_solids = _hidden()
	solids_hidden.emit(hidden_solids)
	ArenaSky.mark_world(_static)
	if not refuge.is_empty():
		_build_people()

## Solid indices drawn here or standing only in the other world.
func _hidden() -> Array[int]:
	var result: Array[int] = []
	var solids: Array = _info["solids"]
	for index: Variant in geometry["later_only" if not later else "aftermath_only"]:
		result.append(int(index))
	for key: String in DRAWN:
		var index: int = solid_index(key)
		if index >= 0 and index not in result:
			result.append(index)
	result.sort()
	return result

func solid_index(key: String) -> int:
	if not SOLIDS.has(key) or _info.is_empty():
		return -1
	var bounds: Array = SOLIDS[key]
	var solids: Array = _info["solids"]
	for index: int in range(solids.size()):
		var solid: Dictionary = solids[index]
		if Vector3(float(solid["min_x"]), float(solid.get("bottom", 0.0)), float(solid["min_z"])).is_equal_approx(bounds[0]) \
				and Vector3(float(solid["max_x"]), float(solid.get("top", 4.0)), float(solid["max_z"])).is_equal_approx(bounds[1]):
			return index
	return -1

func _has(key: String) -> bool:
	return solid_index(key) >= 0

static func _center(key: String) -> Vector3:
	var bounds: Array = SOLIDS[key]
	return (Vector3(bounds[0]) + Vector3(bounds[1])) * 0.5

static func _size(key: String) -> Vector3:
	var bounds: Array = SOLIDS[key]
	return Vector3(bounds[1]) - Vector3(bounds[0])

# ---------------------------------------------------------------- both worlds

func _build_shared() -> void:
	var wood: StandardMaterial3D = _shape.material("refuge_table_wood", Color("8d6c43"))
	var dark_wood: StandardMaterial3D = _shape.material("refuge_bench_wood", Color("6b5236"))
	var steel: StandardMaterial3D = _shape.material("refuge_rail_steel", Color("3a4240"), 0.4, 0.6)
	var paint: StandardMaterial3D = _shape.material("refuge_rail_paint", Color("5e7a70") if later else Color("4a5650"), 0.2, 0.7)
	# Quay and pier railings: posts, a top rail and a mid rail.
	for key: String in ["quay_rail_w_n", "quay_rail_w_s", "quay_rail_n", "quay_rail_s", "pier_rail_n", "pier_rail_s"]:
		if not _has(key):
			continue
		var low: Vector3 = SOLIDS[key][0]
		var high: Vector3 = SOLIDS[key][1]
		var along_x: bool = high.x - low.x > high.z - low.z
		var length: float = (high.x - low.x) if along_x else (high.z - low.z)
		var mid: Vector3 = (low + high) * 0.5
		var size: Vector3 = Vector3(length, 0.08, 0.08) if along_x else Vector3(0.08, 0.08, length)
		_box("TopRail", Vector3(mid.x, 1.06, mid.z), size, paint)
		_box("MidRail", Vector3(mid.x, 0.55, mid.z), size, paint)
		var posts: int = int(length / 1.6) + 1
		for index: int in range(posts):
			var t: float = float(index) / float(maxi(posts - 1, 1))
			var at: Vector3 = Vector3(lerpf(low.x, high.x, t), 0.55, mid.z) if along_x else Vector3(mid.x, 0.55, lerpf(low.z, high.z, t))
			_box("RailPost", at, Vector3(0.09, 1.1, 0.09), steel)
		# A kerb at the quay edge.
		_box("QuayKerb", Vector3(mid.x, 0.07, mid.z), (Vector3(length, 0.14, 0.4) if along_x else Vector3(0.4, 0.14, length)), _material(Color("6f6c62")))
	# The meal table from the court in Low Water, carried here and splinted,
	# its benches, and the one chair nobody sits in.
	if _has("meal_table"):
		var top: Vector3 = _center("meal_table") + Vector3(0, 0.36, 0)
		_shape.block(_static, "MealTableTop", Vector3(6.0, 0.08, 1.2), wood, top)
		for leg: Vector3 in [Vector3(-2.8, 0, -0.5), Vector3(2.8, 0, -0.5), Vector3(-2.8, 0, 0.5), Vector3(2.8, 0, 0.5)]:
			_shape.block(_static, "MealTableLeg", Vector3(0.1, 0.74, 0.1), wood, _center("meal_table") + Vector3(leg.x, -0.02, leg.z))
		# The splint on the leg that broke on the way.
		_shape.block(_static, "Splint", Vector3(0.16, 0.36, 0.04), dark_wood, _center("meal_table") + Vector3(2.8, -0.1, 0.56))
		_box("SplintCord", _center("meal_table") + Vector3(2.8, -0.02, 0.585), Vector3(0.18, 0.05, 0.02), _material(Color("2f2a24")))
		_meal(top + Vector3(0, 0.04, 0))
	for key: String in ["bench_mn", "bench_ms"]:
		if _has(key):
			var at: Vector3 = _center(key)
			_shape.block(_static, "BenchSeat", Vector3(6.0, 0.06, 0.4), dark_wood, at + Vector3(0, 0.2, 0))
			for x: float in [-2.7, 0.0, 2.7]:
				_shape.block(_static, "BenchLeg", Vector3(0.08, 0.42, 0.34), dark_wood, at + Vector3(x, -0.02, 0))
	if _has("empty_chair"):
		var at: Vector3 = _center("empty_chair")
		_shape.block(_static, "EmptyChairSeat", Vector3(0.5, 0.05, 0.5), wood, at + Vector3(0, 0.02, 0))
		_shape.block(_static, "EmptyChairBack", Vector3(0.05, 0.5, 0.5), wood, at + Vector3(0.24, 0.3, 0))
		for leg: Vector2 in [Vector2(-0.2, -0.2), Vector2(0.2, -0.2), Vector2(-0.2, 0.2), Vector2(0.2, 0.2)]:
			_shape.block(_static, "EmptyChairLeg", Vector3(0.05, 0.45, 0.05), wood, at + Vector3(leg.x, -0.22, leg.y))
		# Years on someone still sets a cup at it every morning.
		if later:
			_mug(at + Vector3(-0.9, 0.36, 0.0), _material(Color("e2d8b9")))
	# The quay bench.
	if _has("bench_quay"):
		var at: Vector3 = _center("bench_quay")
		for index: int in range(4):
			_shape.block(_static, "BenchSlat", Vector3(0.12, 0.05, 2.4), dark_wood if later else _material(Color("4c4a44")), at + Vector3(-0.22 + float(index) * 0.15, 0.2, 0))
		for z: float in [-1.0, 1.0]:
			_box("BenchFoot", at + Vector3(0, -0.02, z), Vector3(0.56, 0.42, 0.08), steel)
		_shape.block(_static, "BenchBack", Vector3(0.06, 0.4, 2.4), dark_wood if later else _material(Color("4c4a44")), at + Vector3(0.3, 0.5, 0))
	# The workshop's repair table and the back bench.
	if _has("repair_table"):
		var at: Vector3 = _center("repair_table")
		var slab: StandardMaterial3D = _shape.material("refuge_steel_top", Color("6b7570"), 0.35, 0.63)
		_shape.block(_static, "RepairTop", Vector3(2.6, 0.06, 2.0), slab, at + Vector3(0, 0.42, 0))
		for leg: Vector2 in [Vector2(-1.2, -0.9), Vector2(1.2, -0.9), Vector2(-1.2, 0.9), Vector2(1.2, 0.9)]:
			_box("RepairLeg", at + Vector3(leg.x, -0.03, leg.y), Vector3(0.08, 0.84, 0.08), steel)
		_box("RepairShelf", at + Vector3(0, -0.25, 0), Vector3(2.4, 0.03, 1.8), steel)
	if _has("bench_back"):
		var at: Vector3 = _center("bench_back")
		_shape.block(_static, "BackBenchTop", Vector3(0.8, 0.06, 8.0), wood, at + Vector3(0, 0.45, 0))
		_box("BackBenchBody", at + Vector3(0, -0.04, 0), Vector3(0.76, 0.86, 7.9), _material(Color("4a463c")))
		for index: int in range(7):
			var tool: Vector3 = at + Vector3(-0.1, 0.5, -3.4 + float(index) * 1.1)
			_box("BenchTool", tool, Vector3(0.24, 0.06 + float(index % 3) * 0.05, 0.4), _material([Color("6b7570"), Color("8a5a3a"), Color("3a4240")][index % 3]))
	# The salvaged harbour display from Pier 4, on its posts at the quay.
	if _has("ferry_board"):
		_build_ferry_board()
	# The refuge gate: rendered brick pillars with stone caps and a lamp, the
	# iron leaves swung back against the wall and left there.
	var brick: StandardMaterial3D = _shape.material("refuge_gate_brick", Color("8a5e48") if later else Color("6a4a3a"))
	var cap: StandardMaterial3D = _shape.material("refuge_gate_cap", Color("a8a090") if later else Color("807a70"))
	for key: String in ["gate_post_n", "gate_post_s"]:
		if not _has(key):
			continue
		var at: Vector3 = _center(key)
		_shape.block(_static, "GatePillar", Vector3(1.5, 2.8, 0.76), brick, at)
		for course: int in range(6):
			_box("PillarCourse", at + Vector3(0, -1.2 + float(course) * 0.46, 0), Vector3(1.52, 0.03, 0.78), _material(Color("4a3a30")))
		_shape.block(_static, "PillarCap", Vector3(1.7, 0.18, 0.92), cap, at + Vector3(0, 1.49, 0))
		var head: Vector3 = at + Vector3(0, 1.82, 0)
		_box("GateLamp", head, Vector3(0.3, 0.42, 0.3), _material(Color("ffd08a"), true, 1.8) if not later else _material(Color("e8dcc0")))
		_box("GateLampCap", head + Vector3(0, 0.26, 0), Vector3(0.38, 0.08, 0.38), _material(Color("2a2420")))
		if not later:
			_lamps.append(_light("GateLight", head, Color("ffc27a"), 1.6, 7.0))
	var iron: StandardMaterial3D = _material(Color("3a403e") if not later else Color("3f6f62"))
	for side: float in [-1.0, 1.0]:
		var leaf: Node3D = Node3D.new()
		leaf.name = "GateLeaf"
		leaf.position = Vector3(-19.5, 0.0, side * 2.6)
		leaf.rotation.y = side * -1.35
		_static.add_child(leaf)
		for bar: int in range(10):
			var rod: MeshInstance3D = MeshInstance3D.new()
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3(0.05, 2.0, 0.05)
			rod.mesh = mesh
			rod.material_override = iron
			rod.position = Vector3(0.0, 1.05, -side * (0.12 + float(bar) * 0.25))
			leaf.add_child(rod)
		for rail: float in [0.25, 1.0, 1.95]:
			var bar: MeshInstance3D = MeshInstance3D.new()
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3(0.06, 0.06, 2.5)
			bar.mesh = mesh
			bar.material_override = iron
			bar.position = Vector3(0.0, rail, -side * 1.25)
			leaf.add_child(bar)
	# On the gate pillar facing the pier: the coalition's notice for the
	# reckoning it promised, pasted up in the weeks before the wipe. Years on
	# it is still there under the tram vote, the date never filled in.
	if _has("gate_post_s"):
		# Clear of the pillar's mortar courses, which stand 0.01 proud.
		var face: float = _center("gate_post_s").x - 0.775
		var paper: Color = Color("ddd3b6") if not later else Color("b8ab88")
		_notice(Vector3(face, 1.42, -3.0), Vector2(0.6, 0.66), paper, [["STILL_HERE_NOTICE_RECKONING", 0.14, Vector2(0.52, 0.24)], ["STILL_HERE_NOTICE_DATE", -0.18, Vector2(0.48, 0.09)]])
		if later:
			_notice(Vector3(face - 0.004, 2.08, -2.96), Vector2(0.5, 0.4), Color("e8dcc0"), [["STILL_HERE_NOTICE_VOTE", 0.0, Vector2(0.42, 0.24)]])
	# The clinic's sign over its door, lit: Edda's, whoever keeps it.
	_box("ClinicSignBoard", Vector3(-15.0, 2.75, 13.94), Vector3(2.6, 0.62, 0.08), _material(Color("2f3a37")))
	var sign: WorldSign = WorldSign.new()
	sign.name = "ClinicSign"
	sign.configure("WORLD_EPILOGUE_CLINIC_SIGN", Vector2(2.3, 0.44), Color("ffe0a8"))
	sign.position = Vector3(-15.0, 2.75, 13.89)
	sign.rotation.y = PI
	_static.add_child(sign)
	_lamps.append(_light("ClinicSignLight", Vector3(-15.0, 2.4, 13.2), Color("ffd8a0"), 1.2 if not later else 0.5, 5.0))
	# A work lamp under the workshop roof.
	_lamps.append(_light("WorkshopLamp", Vector3(26.0, 3.8, -8.0), Color("ffd7a0"), 1.6 if not later else 0.9, 8.0))
	for key: String in ["tram_stalled", "tram_running"]:
		if _has(key):
			_tram_detail(key)
	# The tram stop flag on its kiosk carries a timetable panel.
	if _has("stop_kiosk"):
		var at: Vector3 = _center("stop_kiosk")
		_box("KioskRoof", at + Vector3(0, 1.36, 0), Vector3(2.4, 0.12, 4.6), _material(Color("3f6f62")))

## The tram the refuge runs to Low Water: roof gear, lamps, a number, the
## doors. The morning after its pantograph is down and two windows are out.
func _tram_detail(key: String) -> void:
	var at: Vector3 = _center(key)
	var size: Vector3 = _size(key)
	var iron: StandardMaterial3D = _material(Color("262b2b"))
	var lamp: StandardMaterial3D = _material(Color("ffe0a8"), true, 1.6) if later else _material(Color("3b3730"))
	var top: float = at.y + size.y * 0.5
	_box("TramRoofRail", Vector3(at.x, top + 0.08, at.z), Vector3(1.4, 0.14, size.z - 1.0), iron)
	_box("TramResistors", Vector3(at.x, top + 0.24, at.z - 1.0), Vector3(1.0, 0.22, 2.4), _material(Color("4a4e4a")))
	var arm: MeshInstance3D = _box("Pantograph", Vector3(at.x, top + (0.9 if later else 0.32), at.z + 1.0), Vector3(1.2, 0.05, 1.6 if later else 2.4), iron)
	arm.rotation.x = -0.45 if later else -0.05
	for end: float in [-1.0, 1.0]:
		var face: float = at.z + end * (size.z * 0.5 + 0.02)
		_box("TramBumper", Vector3(at.x, 0.45, face), Vector3(size.x - 0.2, 0.22, 0.12), iron)
		for x: float in [-0.9, 0.9]:
			_box("TramLamp", Vector3(at.x + x, 0.95, face), Vector3(0.24, 0.2, 0.06), lamp)
		_box("TramNumber", Vector3(at.x, 2.1, face + end * 0.005), Vector3(0.5, 0.42, 0.02), _material(Color("e4d8b4") if later else Color("8f8670")))
	var number: WorldSign = WorldSign.new()
	number.name = "TramNumber"
	number.configure("STILL_HERE_TRAM_NUMBER", Vector2(0.42, 0.36), Color("2a2a2a"), true)
	number.position = Vector3(at.x, 2.1, at.z - (size.z * 0.5 + 0.02) - 0.015)
	number.rotation.y = PI
	_static.add_child(number)
	# Doors on the platform side.
	for z: float in [at.z - size.z * 0.25, at.z + size.z * 0.25]:
		_box("TramDoor", Vector3(at.x - size.x * 0.5 - 0.012, 1.15, z), Vector3(0.02, 2.1, 1.2), _material(Color("2f4a42") if not later else Color("3f7f62")))
		_box("TramDoorGlass", Vector3(at.x - size.x * 0.5 - 0.02, 1.55, z), Vector3(0.02, 0.9, 0.9), _material(Color("2b4446")))
	if not later:
		for z: float in [at.z - 1.2, at.z + 3.4]:
			_box("BlownPane", Vector3(at.x + size.x * 0.5 + 0.02, 2.05, z), Vector3(0.02, 0.8, 1.0), _material(Color("0b0c0d")))

func _build_ferry_board() -> void:
	var at: Vector3 = _center("ferry_board")
	var post: StandardMaterial3D = _material(Color("2f3634"))
	for z: float in [-1.15, 1.15]:
		_box("BoardPost", Vector3(at.x, 1.6, at.z + z), Vector3(0.16, 3.2, 0.16), post)
	var root: Node3D = Node3D.new()
	root.name = "FerryBoard"
	# Face east toward the quay and the bench; the decoration says where.
	var index: int = int(geometry["ferry_board"])
	var detail: Dictionary = _info["presentation"]["decorations"][index]
	var solid: Dictionary = _info["solids"][int(detail["solid"])]
	root.transform = MapDecoration.placement(solid, detail)
	_static.add_child(root)
	var size: Vector2 = Vector2(float(detail["size"][0]), float(detail["size"][1]))
	root.add_child(_quad("Bezel", Vector3(0, 0, -0.01), size + Vector2(0.3, 0.3), _material(Color("1e2224"))))
	_ferry_screen = _material(DISPLAY_DARK, true, 0.15)
	root.add_child(_quad("Screen", Vector3(0, 0, 0.0), size, _ferry_screen))
	if not later:
		# Dark the morning after, a crack across the glass.
		var crack: MeshInstance3D = _quad("Crack", Vector3(0.2, 0.1, 0.005), Vector2(1.6, 0.03), _material(Color("5c6a6c")))
		crack.rotation.z = 0.35
		root.add_child(crack)
	_ferry_width = size.x * 0.88
	for line: int in range(4):
		var label: Label3D = Label3D.new()
		label.name = "BoardLine%d" % line
		label.font = WorldSign.FONT
		label.font_size = 32
		label.pixel_size = 0.0058
		label.modulate = DISPLAY_TEXT
		label.outline_size = 0
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		label.double_sided = false
		label.position = Vector3(0, size.y * 0.34 - float(line) * size.y * 0.22, 0.012)
		label.visible = false
		root.add_child(label)
		_ferry_lines.append(label)
	_ferry_light = OmniLight3D.new()
	_ferry_light.position = Vector3(0, 0, 1.0)
	_ferry_light.light_color = DISPLAY_TEXT
	_ferry_light.light_energy = 0.0
	_ferry_light.omni_range = 6.0
	root.add_child(_ferry_light)
	show_fragment(false)

## The board years later times the ferry in the refuge's amber. Once, at the
## very end, it shows two lines in the voice it used on the pier, and then
## the ferry again. Nothing on it says who wrote them. The first light it
## stays dark.
func show_fragment(on: bool) -> void:
	fragment = on and later
	if _ferry_lines.is_empty():
		return
	var copy: Array[String] = ["", "", "", ""]
	if fragment:
		copy = ["", tr("STILL_HERE_BOARD_FRAGMENT_A"), tr("STILL_HERE_BOARD_FRAGMENT_B"), ""]
	elif later:
		copy = [tr("STILL_HERE_BOARD_PIER"), tr("STILL_HERE_BOARD_LOW_WATER"), tr("STILL_HERE_BOARD_WATERWORKS"), tr("STILL_HERE_BOARD_WEATHER")]
	# Every line fits the board at one shared size: the widest line sets it.
	var widest: float = 1.0
	for line: String in copy:
		widest = maxf(widest, WorldSign.FONT.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x)
	var ink: Color = DISPLAY_TEXT if fragment else FERRY_TEXT
	for index: int in range(_ferry_lines.size()):
		_ferry_lines[index].pixel_size = minf(0.0058, _ferry_width / widest)
		_ferry_lines[index].text = copy[index]
		_ferry_lines[index].visible = later and not copy[index].is_empty()
		_ferry_lines[index].modulate = ink
	if _ferry_light != null:
		_ferry_light.light_energy = 1.2 if later else 0.0
		_ferry_light.light_color = ink
	if _ferry_screen != null:
		_ferry_screen.emission_energy_multiplier = 0.8 if later else 0.05

## Where the ending sits: on the bench beside Latch at seated eye height,
## with Latch at one side of the view and the board over the water.
func coda_focus() -> Dictionary:
	if geometry.is_empty() or not _has("bench_quay") or not _has("ferry_board"):
		return {}
	var detail: Dictionary = _info["presentation"]["decorations"][int(geometry["departure"]["decoration"])]
	var seat: Vector3 = MapDecoration.placement(_info["solids"][int(detail["solid"])], detail).origin
	var latch: Vector3 = _center("bench_quay") + Vector3(0.0, 0.9, 1.2)
	if people.has("latch") and is_instance_valid(people["latch"]):
		latch = people["latch"].global_position + Vector3(0.0, 0.85, 0.0)
	return {"seat": Vector3(seat.x, SEATED_EYE, seat.z), "board": _center("ferry_board") + Vector3(0, 0.5, 0),
		"latch": latch, "water": Vector3(-70.0, 1.5, 4.0)}

func _meal(top: Vector3) -> void:
	var bone: StandardMaterial3D = _shape.material("refuge_bone_ceramic", Color("e2d8b9"), 0.0, 0.48)
	var clay: StandardMaterial3D = _shape.material("refuge_clay_ceramic", Color("a76343"), 0.0, 0.62)
	var sage: StandardMaterial3D = _shape.material("refuge_sage_ceramic", Color("6e8980"), 0.0, 0.6)
	var bread: StandardMaterial3D = _shape.material("refuge_bread", Color("b98a52"))
	if later:
		# Breakfast for a full table: bowls, cups, bread and a pot.
		for index: int in range(8):
			var x: float = -2.5 + float(index % 4) * 1.6
			var z: float = -0.38 if index < 4 else 0.38
			_bowl(top + Vector3(x, 0.0, z), 0.16, bone if index % 3 else clay)
			_mug(top + Vector3(x + 0.3, 0.0, z * 0.9), sage if index % 2 else bone)
		_shape.block(_static, "BreadBoard", Vector3(0.7, 0.03, 0.4), _shape.material("refuge_table_wood", Color("8d6c43")), top + Vector3(-0.6, 0.015, 0))
		_shape.hull(_static, "Loaf", PackedVector3Array([Vector3(0, 0.25, 0.1), Vector3(0.05, 0.27, 0.11), Vector3(0.11, 0.2, 0.09), Vector3(0.14, 0.07, 0.05)]), bread, top + Vector3(-0.6, 0.03, 0), 12)
		_shape.lathe(_static, "TeaPot", PackedVector2Array([Vector2(0, 0), Vector2(0, 0.1), Vector2(0.06, 0.13), Vector2(0.16, 0.12), Vector2(0.22, 0.06), Vector2(0.24, 0)]), clay, top + Vector3(0.8, 0.0, 0)).rotation.x = -PI * 0.5
		var fruit: StandardMaterial3D = _material(Color("d8a23c"))
		for index: int in range(4):
			_shape.block(_static, "Fruit", Vector3(0.08, 0.08, 0.08), fruit, top + Vector3(1.4 + float(index) * 0.1, 0.05, 0.05 * float(index % 2)))
	else:
		# The morning after: whatever was carried, a pot, a few cups, a loaf.
		_shape.lathe(_static, "SoupPot", PackedVector2Array([Vector2(0, 0), Vector2(0, 0.24), Vector2(0.24, 0.24), Vector2(0.24, 0)]), _material(Color("4a4e4a")), top + Vector3(0.2, 0.0, 0)).rotation.x = -PI * 0.5
		for index: int in range(5):
			_bowl(top + Vector3(-2.4 + float(index) * 0.9, 0.0, -0.36 if index % 2 == 0 else 0.36), 0.15, bone if index % 2 else clay)
		_shape.hull(_static, "Loaf", PackedVector3Array([Vector3(0, 0.25, 0.1), Vector3(0.05, 0.27, 0.11), Vector3(0.11, 0.2, 0.09), Vector3(0.14, 0.07, 0.05)]), bread, top + Vector3(-1.2, 0.0, 0.1), 12)

func _bowl(at: Vector3, radius: float, finish: StandardMaterial3D) -> void:
	var vessel: MeshInstance3D = _shape.lathe(_static, "Bowl", PackedVector2Array([Vector2(0, radius * 0.4), Vector2(0.02, radius * 0.64), Vector2(radius * 0.46, radius), Vector2(radius * 0.49, radius), Vector2(radius * 0.49, radius * 0.92), Vector2(0.035, radius * 0.56), Vector2(0.025, 0)]), finish, at, 14)
	vessel.rotation.x = -PI * 0.5

func _mug(at: Vector3, finish: StandardMaterial3D) -> void:
	var vessel: MeshInstance3D = _shape.lathe(_static, "Mug", PackedVector2Array([Vector2(0, 0), Vector2(0, 0.06), Vector2(0.12, 0.07), Vector2(0.13, 0.07), Vector2(0.13, 0.054), Vector2(0.016, 0.05), Vector2(0.016, 0)]), finish, at, 12)
	vessel.rotation.x = -PI * 0.5

# ---------------------------------------------------------------- first light

func _build_aftermath() -> void:
	var stone: StandardMaterial3D = _material(Color("807b70"))
	var plaster: StandardMaterial3D = _material(Color("8e7658"))
	var dark: StandardMaterial3D = _material(Color("4a4740"))
	var rebar: StandardMaterial3D = _material(Color("5a3a2a"))
	# Rubble where a corner and a balcony came down.
	var concrete: StandardMaterial3D = _shape.material("refuge_rubble_concrete", Color("8a867c"))
	var broken_plaster: StandardMaterial3D = _shape.material("refuge_rubble_plaster", Color("94806c"))
	var brick: StandardMaterial3D = _shape.material("refuge_rubble_brick", Color("7a4a38"))
	var dust: StandardMaterial3D = _material(Color("6e6a62"))
	for key: String in ["rubble_a", "rubble_b"]:
		if not _has(key):
			continue
		var at: Vector3 = _center(key)
		var size: Vector3 = _size(key)
		var base: Vector3 = at - Vector3(0, size.y * 0.5, 0)
		# A low spread of dust and grit first, then the broken pieces on it.
		_plane("RubbleDust", base + Vector3(0, 0.006, 0), Vector2(size.x + 1.4, size.z + 1.0), dust).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for index: int in range(22):
			var u: float = float((index * 37) % 100) / 100.0 - 0.5
			var v: float = float((index * 61) % 100) / 100.0 - 0.5
			var height: float = 0.14 + float((index * 13) % 7) * 0.08 * (1.0 - absf(u) * 1.2)
			var lump: Vector3 = Vector3(0.28 + float(index % 4) * 0.16, height, 0.22 + float((index * 3) % 5) * 0.12)
			var finish: StandardMaterial3D = [concrete, broken_plaster, brick, concrete][index % 4]
			var block: MeshInstance3D = _shape.block(_static, "Rubble", lump, finish, base + Vector3(u * size.x, lump.y * 0.5 + float(index % 3) * 0.12 * (1.0 - absf(u) * 1.5), v * size.z))
			block.rotation = Vector3(float(index % 5 - 2) * 0.12, float(index) * 0.73, float(index % 3 - 1) * 0.22)
		# A slab that came down whole, tilted across the pile.
		var slab: MeshInstance3D = _shape.block(_static, "FallenSlab", Vector3(size.x * 0.7, 0.16, 1.1), concrete, base + Vector3(0.2, 0.42, 0.0))
		slab.rotation = Vector3(0.0, 0.18, 0.32)
		for index: int in range(4):
			var rod: MeshInstance3D = _box("Rebar", base + Vector3(-0.8 + float(index) * 0.55, 0.55, 0.1 * float(index % 2)), Vector3(0.035, 0.035, 1.4), rebar)
			rod.rotation = Vector3(0.7 + 0.1 * float(index), float(index) * 0.5, 0.2)
	# The people's barricade across the pier landing: crates, a handcart and
	# a sheet of corrugated iron.
	if _has("pier_barricade"):
		var at: Vector3 = _center("pier_barricade")
		var crate: StandardMaterial3D = _shape.material("refuge_crate_wood", Color("7a5f42"))
		for index: int in range(5):
			var z: float = -2.6 + float(index) * 1.3
			_shape.block(_static, "BarricadeCrate", Vector3(1.0, 0.8 + float(index % 2) * 0.4, 1.1), crate, at + Vector3(0, -0.35 + float(index % 2) * 0.2, z))
		# A sheet of corrugated iron propped against the crates.
		var sheet: Node3D = Node3D.new()
		sheet.name = "Corrugated"
		sheet.position = at + Vector3(0.62, -0.05, 0.0)
		sheet.rotation.z = 0.28
		_static.add_child(sheet)
		var rust: StandardMaterial3D = _material(Color("6a4a38"))
		var zinc: StandardMaterial3D = _material(Color("55605c"))
		for rib: int in range(16):
			var strip: MeshInstance3D = MeshInstance3D.new()
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3(0.05 if rib % 2 == 0 else 0.03, 1.4, 0.18)
			strip.mesh = mesh
			strip.material_override = rust if rib % 5 == 2 else zinc
			strip.position = Vector3(0.0 if rib % 2 == 0 else 0.03, 0.0, -1.35 + float(rib) * 0.18)
			sheet.add_child(strip)
		# A handcart, tipped up on its wheels at the end of the line.
		_box("CartBed", at + Vector3(-0.2, 0.0, 2.6), Vector3(1.2, 0.08, 0.8), _shape.material("refuge_crate_wood", Color("7a5f42")))
		for z: float in [2.2, 3.0]:
			var wheel: MeshInstance3D = _shape.cylinder(_static, "CartWheel", 0.3, 0.06, _material(Color("2a2420")), at + Vector3(0.2, -0.45, z))
			wheel.rotation.y = 0.0
	# Cots outside the clinic, under a tarp off the wall, and Edda's lamp.
	for key: String in ["cot_a", "cot_b"]:
		if not _has(key):
			continue
		var at: Vector3 = _center(key)
		_box("CotFrame", at + Vector3(0, 0.1, 0), Vector3(2.0, 0.06, 0.8), _material(Color("3a4240")))
		_box("CotCanvas", at + Vector3(0, 0.2, 0), Vector3(1.9, 0.05, 0.72), _material(Color("6e7a5a")))
		_box("Blanket", at + Vector3(0.3, 0.26, 0), Vector3(1.2, 0.06, 0.76), _material(Color("7a5a4a")))
		for leg: Vector2 in [Vector2(-0.9, -0.34), Vector2(0.9, -0.34), Vector2(-0.9, 0.34), Vector2(0.9, 0.34)]:
			_box("CotLeg", at + Vector3(leg.x, 0.0, leg.y), Vector3(0.05, 0.22, 0.05), _material(Color("3a4240")))
	var tarp: MeshInstance3D = _box("ClinicTarp", Vector3(-16.8, 2.4, 11.2), Vector3(3.4, 0.04, 4.2), _material(Color("5f6b4e")))
	tarp.rotation.x = 0.22
	for x: float in [-18.4, -15.2]:
		_box("TarpPole", Vector3(x, 1.0, 9.2), Vector3(0.06, 2.0, 0.06), _material(Color("3a3530")))
	_hurricane_lamp(Vector3(-15.6, 0.0, 11.4))
	# The standpipe the pumps still feed, and what people brought to it.
	if _has("standpipe"):
		var at: Vector3 = _center("standpipe")
		_box("Standpipe", at + Vector3(0, 0.1, 0), Vector3(0.16, 1.4, 0.16), _material(Color("3b4240")))
		_box("Tap", at + Vector3(0.0, 0.62, 0.18), Vector3(0.1, 0.1, 0.3), _material(Color("7d3b2c")))
		_box("Drip", at + Vector3(0.0, -0.58, 0.32), Vector3(0.5, 0.01, 0.5), _wet())
		for index: int in range(6):
			var can: Vector3 = at + Vector3(-1.2 + float(index % 3) * 0.6, -0.4, 0.9 + float(index / 3) * 0.6)
			_box("WaterCan", can, Vector3(0.32, 0.4, 0.26), _material([Color("5a7898"), Color("c8a048"), Color("6a6a6a")][index % 3]))
	# Crates people carried, with their lanterns.
	for key: String in ["crate_a", "crate_b", "crate_c"]:
		if not _has(key):
			continue
		var at: Vector3 = _center(key)
		var size: Vector3 = _size(key)
		_shape.block(_static, "Crate", size - Vector3(0.04, 0.0, 0.04), _shape.material("refuge_crate_wood", Color("7a5f42")), at)
		_box("CrateStrap", at, Vector3(size.x + 0.02, 0.06, 0.08), _material(Color("2f2a24")))
	for spot: Vector3 in [Vector3(-7.0, 0.0, 9.6), Vector3(-1.0, 0.0, 8.0), Vector3(-15.0, 0.0, -10.0), Vector3(-25.4, 0.0, 10.6), Vector3(-25.0, 0.0, -10.4), Vector3(5.0, 0.0, 9.0)]:
		_lantern(spot)
	# Tern's work lamp on the quay kerb, set down to keep watch down the pier.
	_lantern(Vector3(-21.8, 0.0, 4.0))
	# The workshop: the cursed tram motor on its stand, with its tag.
	if _has("motor_stand"):
		var at: Vector3 = _center("motor_stand")
		_box("MotorStand", at + Vector3(0, -0.1, 0), Vector3(1.3, 0.8, 1.3), _material(Color("3a4240")))
		var motor: MeshInstance3D = _shape.cylinder(_static, "TramMotor", 0.42, 0.9, _shape.material("refuge_motor", Color("5a6058"), 0.6, 0.4), at + Vector3(0, 0.62, 0))
		motor.rotation.y = PI * 0.5
		_box("MotorTag", at + Vector3(0.0, 0.9, 0.62), Vector3(0.3, 0.18, 0.02), _material(Color("d8cfb4")))
		var tag: WorldSign = WorldSign.new()
		tag.name = "CursedTag"
		tag.configure("STILL_HERE_TAG_CURSED", Vector2(0.28, 0.16), Color("2a2420"), true)
		tag.position = at + Vector3(0.0, 0.9, 0.632)
		_static.add_child(tag)
	_ledger(true)
	# The board of the missing on the court wall: notes, photographs, string.
	_missing_board(false)
	# Smoke still standing behind the court, and a lamp across the street,
	# down.
	var fallen: MeshInstance3D = _box("FallenLamp", Vector3(20.6, 0.15, 6.0), Vector3(0.14, 0.14, 6.2), _material(Color("262b2b")))
	fallen.rotation.y = 0.3
	_box("FallenLampHead", Vector3(21.5, 0.2, 9.0), Vector3(0.5, 0.2, 0.5), _material(Color("3b3730")))
	_box("DownWire", Vector3(17.0, 2.4, -16.0), Vector3(0.03, 0.03, 9.0), _material(Color("262b2b"))).rotation.x = 0.5

## The open ledger on the repair table, or closed beside Latch years on.
func _ledger(open: bool) -> void:
	var paper: StandardMaterial3D = _material(Color("e2d8b9"))
	var ink: StandardMaterial3D = _material(Color("3a3530"))
	var cover: StandardMaterial3D = _material(Color("5a3a2a"))
	if open:
		if not _has("repair_table"):
			return
		var detail: Dictionary = _info["presentation"]["decorations"][int(geometry["latch"]["decoration"])]
		var solid: Dictionary = _info["solids"][int(detail["solid"])]
		var root: Node3D = Node3D.new()
		root.name = "Ledger"
		root.transform = MapDecoration.placement(solid, detail)
		_static.add_child(root)
		root.add_child(_quad("LedgerCover", Vector3(0, 0, 0.002), Vector2(0.62, 0.44), cover))
		for side: float in [-0.15, 0.15]:
			root.add_child(_quad("LedgerPage", Vector3(side, 0, 0.006), Vector2(0.28, 0.4), paper))
			for line: int in range(9):
				var stroke: MeshInstance3D = _quad("LedgerLine", Vector3(side - 0.02 + float(line % 3) * 0.01, 0.15 - float(line) * 0.035, 0.008), Vector2(0.2 - float(line % 4) * 0.03, 0.008), ink)
				root.add_child(stroke)
		# The pencil, and a mug gone cold.
		var pencil: MeshInstance3D = _quad("Pencil", Vector3(0.36, -0.1, 0.008), Vector2(0.16, 0.012), _material(Color("c8a048")))
		pencil.rotation.z = 0.5
		root.add_child(pencil)
		_mug(_center("repair_table") + Vector3(0.6, 0.45, 0.5), _material(Color("6e8980")))
	else:
		if not _has("bench_quay"):
			return
		var at: Vector3 = _center("bench_quay") + Vector3(-0.1, 0.25, -0.2)
		_box("ClosedLedger", at, Vector3(0.3, 0.05, 0.42), cover)
		_box("ClosedLedgerPages", at + Vector3(0.0, 0.0, 0.0), Vector3(0.28, 0.04, 0.4), paper)

## The board of the missing: notes and photographs pinned to the store wall,
## string between some. The first light: HAVE YOU SEEN. Years on: STILL
## LOOKING, fewer notes, flowers in jars underneath. A rescue this run did not
## carry is a name on it, never a grave.
func _missing_board(still_looking: bool) -> void:
	var index: int = -1
	var decorations: Array = _info["presentation"]["decorations"]
	for candidate: int in range(decorations.size()):
		if decorations[candidate]["kind"] == "epilogue_missing_board":
			index = candidate
	if index < 0:
		return
	var detail: Dictionary = decorations[index]
	var solid: Dictionary = _info["solids"][int(detail["solid"])]
	var root: Node3D = Node3D.new()
	root.name = "MissingBoard"
	root.transform = MapDecoration.placement(solid, detail)
	_static.add_child(root)
	var size: Vector2 = Vector2(float(detail["size"][0]), float(detail["size"][1]))
	root.add_child(_quad("Cork", Vector3(0, 0, 0.0), size, _material(Color("7a5f42") if not still_looking else Color("6a5a48"))))
	var header: WorldSign = WorldSign.new()
	header.name = "BoardHeader"
	header.configure("STILL_HERE_BOARD_STILL_LOOKING" if still_looking else "STILL_HERE_BOARD_HAVE_YOU_SEEN", Vector2(size.x * 0.7, 0.36), Color("e8e2d6"))
	header.position = Vector3(0, size.y * 0.5 - 0.22, 0.01)
	root.add_child(header)
	var papers: Array[Color] = [Color("e2d8b9"), Color("d6d0c2"), Color("c9c2a8"), Color("e8dcc0"), Color("b8b0a0")]
	var count: int = 30 if not still_looking else 18
	for note: int in range(count):
		var column: int = note % 10
		var row: int = note / 10
		var x: float = -size.x * 0.45 + float(column) * size.x * 0.1 + float((note * 7) % 5 - 2) * 0.04
		var y: float = size.y * 0.16 - float(row) * size.y * 0.27 + float((note * 11) % 5 - 2) * 0.03
		var tall: bool = note % 3 == 0
		var paper: Color = papers[note % papers.size()]
		if still_looking:
			paper = paper.darkened(0.12).lerp(Color("c9c2a8"), 0.3)
		var card: MeshInstance3D = _quad("Note", Vector3(x, y, 0.004 + float(note % 4) * 0.001), Vector2(0.3, 0.38) if tall else Vector2(0.36, 0.26), _material(paper))
		card.rotation.z = float((note * 13) % 9 - 4) * 0.04
		root.add_child(card)
		if tall:
			# A photograph: a dark face-shaped square on the card.
			root.add_child(_quad("Photo", Vector3(x, y + 0.05, 0.009), Vector2(0.22, 0.2), _material([Color("4a4a48"), Color("5a5048"), Color("3e4448")][note % 3])))
		else:
			for line: int in range(3):
				root.add_child(_quad("Handwriting", Vector3(x - 0.02, y + 0.06 - float(line) * 0.06, 0.009), Vector2(0.24 - float(line % 2) * 0.06, 0.018), _material(Color("3a3530"))))
		root.add_child(_quad("Pin", Vector3(x, y + 0.15, 0.012), Vector2(0.03, 0.03), _material(Color("b84c3a"))))
	if still_looking:
		# Jars of flowers on the ground under it.
		var base: Vector3 = root.transform.origin
		for jar: int in range(5):
			var at: Vector3 = Vector3(base.x - 2.4 + float(jar) * 1.2, 0.0, base.z + 0.4)
			_box("Jar", at + Vector3(0, 0.12, 0), Vector3(0.14, 0.24, 0.14), _material(Color("6a8a88")))
			_box("Stems", at + Vector3(0, 0.32, 0), Vector3(0.06, 0.2, 0.06), _material(Color("4f7a3e")))
			_box("Blooms", at + Vector3(0, 0.46, 0), Vector3(0.2, 0.1, 0.2), _material([Color("d8a23c"), Color("c4644a"), Color("e8dcc0")][jar % 3]))

# ---------------------------------------------------------------- years later

func _build_later() -> void:
	# The fountain the pumps feed now: a basin, clean water and a spout.
	if _has("fountain"):
		var at: Vector3 = _center("fountain")
		var size: Vector3 = _size("fountain")
		var rim: StandardMaterial3D = _material(Color("8a877c"))
		for side: Array in [[Vector3(0, 0, -size.z * 0.5 + 0.12), Vector3(size.x, 0.6, 0.24)], [Vector3(0, 0, size.z * 0.5 - 0.12), Vector3(size.x, 0.6, 0.24)],
				[Vector3(-size.x * 0.5 + 0.12, 0, 0), Vector3(0.24, 0.6, size.z)], [Vector3(size.x * 0.5 - 0.12, 0, 0), Vector3(0.24, 0.6, size.z)]]:
			_box("FountainRim", at + side[0], side[1], rim)
		_fountain_material = ShaderMaterial.new()
		_fountain_material.shader = ArenaWater.SHADER
		_fountain_material.set_shader_parameter("patch_size", Vector2(size.x - 0.48, size.z - 0.48))
		_fountain_material.set_shader_parameter("deep_color", Color("2d6a6a"))
		_fountain_material.set_shader_parameter("water_color", Color("4a8a84"))
		_fountain_material.set_shader_parameter("crest_color", Color("b8d8c8"))
		var detail: Texture2D = EnvironmentTextures.texture_at("res://assets/environment/production/water_ripples.png")
		if detail != null:
			_fountain_material.set_shader_parameter("ripple_detail", detail)
			_fountain_material.set_shader_parameter("detail_enabled", true)
		_plane("FountainWater", at + Vector3(0, 0.2, 0), Vector2(size.x - 0.48, size.z - 0.48), _fountain_material)
		_box("Spout", at + Vector3(0, 0.6, 0), Vector3(0.24, 1.2, 0.24), _material(Color("6f6c62")))
		_box("SpoutWater", at + Vector3(0, 0.62, 0.0), Vector3(0.06, 0.9, 0.06), _material(Color("cfe6e0"), true, 0.3))
	# The ferry gate across the pier, where Tern takes the fares nobody pays.
	if _has("ferry_gate"):
		var at: Vector3 = _center("ferry_gate")
		for z: float in [-3.0, 3.0]:
			_box("GatePost", at + Vector3(0, 0.1, z), Vector3(0.14, 1.3, 0.14), _material(Color("3f6f62")))
		_box("GateChain", at + Vector3(0, 0.3, 0), Vector3(0.04, 0.04, 6.0), _material(Color("8a8478")))
		_box("FareBox", at + Vector3(0.4, 0.0, -2.4), Vector3(0.5, 1.0, 0.5), _material(Color("e4d8b4")))
	# Moss and grass where the court's paving is never walked, and a tree
	# where the corner came down.
	var moss: StandardMaterial3D = _material(Color("5a7444"))
	for spot: Vector4 in [Vector4(-18.4, 13.4, 1.0, 0.8), Vector4(-11.0, 13.6, 3.0, 0.6), Vector4(11.4, 13.6, 1.2, 0.8), Vector4(-18.6, -13.6, 1.6, 0.6),
			Vector4(0.0, -13.6, 4.0, 0.6), Vector4(11.4, -13.6, 1.2, 0.8), Vector4(21.6, 12.0, 0.6, 3.0), Vector4(21.6, -20.0, 0.6, 4.0), Vector4(-29.4, 12.0, 0.8, 6.0), Vector4(-29.4, -12.0, 0.8, 6.0)]:
		_plane("Moss", Vector3(spot.x, 0.004, spot.y), Vector2(spot.z, spot.w), moss).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_young_tree(Vector3(1.4, 0.0, -12.6))
	_young_tree(Vector3(4.6, 0.0, 12.8))
	# Years of growth in the planters people built out of the rubble, and
	# grass tufting along the wall bases where nobody walks.
	for key: String in ["planter_a", "planter_b"]:
		if _has(key):
			_young_tree(_center(key) + Vector3(0.0, 0.3, 0.0))
	var tuft: StandardMaterial3D = _material(Color("6b8448"))
	var dark_tuft: StandardMaterial3D = _material(Color("4f6a3a"))
	for run: Vector4 in [Vector4(-18.6, 13.75, -16.4, 13.75), Vector4(-13.6, 13.75, -11.4, 13.75), Vector4(-4.6, 13.75, 0.6, 13.75), Vector4(7.4, 13.75, 11.6, 13.75),
			Vector4(-18.6, -13.75, -12.0, -13.75), Vector4(6.4, -13.75, 11.6, -13.75), Vector4(-19.6, -12.0, -19.6, -4.0), Vector4(-19.6, 4.0, -19.6, 13.0)]:
		var from: Vector2 = Vector2(run.x, run.y)
		var to: Vector2 = Vector2(run.z, run.w)
		var count: int = int(from.distance_to(to) / 0.45)
		for index: int in range(count):
			var t: float = (float(index) + 0.5) / float(count)
			var at: Vector2 = from.lerp(to, t) + Vector2(float((index * 7) % 5 - 2) * 0.05, float((index * 3) % 5 - 2) * 0.05)
			var height: float = 0.06 + float((index * 5) % 4) * 0.03
			var blade: MeshInstance3D = _box("GrassTuft", Vector3(at.x, height * 0.5, at.y), Vector3(0.22, height, 0.18), dark_tuft if index % 3 == 0 else tuft)
			blade.rotation.y = float(index) * 0.9
			blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The plates of the ones who were taken, cleaned and hung on the wall
	# by the gate. Nobody can say what they were by then. They are kept.
	var plate: StandardMaterial3D = _material(Color("2e3234"))
	var stamp: StandardMaterial3D = _material(Color("8a8478"))
	_box("PlateWire", Vector3(-20.06, 1.18, 9.5), Vector3(0.02, 0.02, 8.0), _material(Color("8a8478")))
	for index: int in range(11):
		var z: float = 5.9 + float(index) * 0.72
		_box("TakenPlate", Vector3(-20.07, 0.98, z), Vector3(0.02, 0.3, 0.5), plate)
		_box("PlateStamp", Vector3(-20.085, 1.0, z), Vector3(0.01, 0.06, 0.34), stamp)
	for index: int in range(4):
		_box("WallFlowers", Vector3(-20.3, 0.1, 6.4 + float(index) * 2.2), Vector3(0.3, 0.2, 0.4), _material([Color("d8a23c"), Color("c4644a"), Color("e8dcc0"), Color("8a5aa0")][index]))
	# A repaired corner in fresh plaster where the store's corner came down.
	_box("RepairPatch", Vector3(1.4, 3.0, -13.99), Vector3(4.0, 6.0, 0.02), _material(Color("c9b89a")))
	# A washing line between the homes.
	_box("WashLine", Vector3(-3.0, 5.6, 13.8), Vector3(10.0, 0.02, 0.02), _material(Color("8a8478")))
	for index: int in range(6):
		var cloth: MeshInstance3D = _box("Washing", Vector3(-7.0 + float(index) * 1.5, 5.25, 13.82), Vector3(0.7, 0.6, 0.02), _material([Color("e8dcc0"), Color("5a7898"), Color("c4644a"), Color("e2d8b9"), Color("6e8980"), Color("d8a23c")][index]))
		_sway.append(cloth)
	_ledger(false)
	_missing_board(true)
	# The tram's blind reads home.
	if _has("tram_running"):
		var front: Vector3 = Vector3(17.0, 2.7, 14.02)
		_box("Blind", front, Vector3(1.6, 0.36, 0.02), _material(Color("141414")))
		var blind: WorldSign = WorldSign.new()
		blind.name = "TramBlind"
		blind.configure("STILL_HERE_TRAM_BLIND", Vector2(1.5, 0.3), Color("ffd27a"), true)
		blind.position = front + Vector3(0, 0, 0.012)
		_static.add_child(blind)
	for at: Vector3 in [Vector3(-14.0, 0.0, -1.0), Vector3(8.0, 0.0, -2.0)]:
		_bicycle(at)

func _young_tree(at: Vector3) -> void:
	var bark: StandardMaterial3D = _material(Color("5a4630"))
	var leaves: StandardMaterial3D = _material(Color("5a7a42"))
	_box("Trunk", at + Vector3(0, 1.2, 0), Vector3(0.18, 2.4, 0.18), bark)
	for index: int in range(4):
		var crown: MeshInstance3D = _box("Leaves", at + Vector3(float(index % 2) * 0.5 - 0.25, 2.6 + float(index / 2) * 0.5, float(index / 2) * 0.4 - 0.2), Vector3(1.4, 1.0, 1.3), leaves)
		crown.rotation.y = float(index) * 0.6
		_sway.append(crown)

func _bicycle(at: Vector3) -> void:
	var frame: StandardMaterial3D = _material(Color("8e4a34"))
	var tyre: StandardMaterial3D = _material(Color("1e1e1e"))
	# Standing on its stand along +X: open wheels upright in the X-Y plane,
	# a tyre ring, four spokes and the hub.
	var spoke: StandardMaterial3D = _material(Color("8a8478"))
	for x: float in [-0.52, 0.52]:
		var wheel: MeshInstance3D = MeshInstance3D.new()
		wheel.name = "Tyre"
		var ring: TorusMesh = TorusMesh.new()
		ring.inner_radius = 0.28
		ring.outer_radius = 0.34
		ring.rings = 20
		ring.ring_segments = 6
		wheel.mesh = ring
		wheel.material_override = tyre
		wheel.position = at + Vector3(x, 0.34, 0)
		# The torus lies in XZ; stand it up into XY.
		wheel.rotation.x = PI * 0.5
		_static.add_child(wheel)
		for turn: int in range(2):
			var rod: MeshInstance3D = _box("Spoke", at + Vector3(x, 0.34, 0), Vector3(0.56, 0.012, 0.012), spoke)
			rod.rotation.z = PI * 0.25 + float(turn) * PI * 0.5
		_box("Hub", at + Vector3(x, 0.34, 0), Vector3(0.08, 0.08, 0.06), frame)
	_box("TopTube", at + Vector3(0.02, 0.72, 0), Vector3(0.62, 0.04, 0.04), frame)
	var down: MeshInstance3D = _box("DownTube", at + Vector3(0.12, 0.52, 0), Vector3(0.66, 0.04, 0.04), frame)
	down.rotation.z = 0.62
	var seat_tube: MeshInstance3D = _box("SeatTube", at + Vector3(-0.22, 0.56, 0), Vector3(0.04, 0.5, 0.04), frame)
	seat_tube.rotation.z = -0.25
	_box("Chainstay", at + Vector3(-0.36, 0.34, 0), Vector3(0.36, 0.03, 0.06), frame)
	_box("Seat", at + Vector3(-0.28, 0.84, 0), Vector3(0.24, 0.05, 0.1), tyre)
	_box("Fork", at + Vector3(0.44, 0.55, 0), Vector3(0.04, 0.46, 0.04), frame)
	_box("Bars", at + Vector3(0.4, 0.86, 0), Vector3(0.05, 0.04, 0.5), frame)
	_box("Basket", at + Vector3(0.6, 0.76, 0), Vector3(0.26, 0.2, 0.32), _material(Color("8a6a40")))

# ---------------------------------------------------------------- people

func apply_state(state: Dictionary) -> void:
	if geometry.is_empty() or state.get("id") != MissionState.STILL_HERE_ID or not state.get("epilogue") is Dictionary:
		return
	state_applied += 1
	var facts: Dictionary = state["epilogue"]
	if facts["refuge"] != refuge or people.is_empty():
		refuge = facts["refuge"].duplicate()
		_build_people()
	var was: bool = departed
	departed = state.get("phase") == "departed"
	# Latch, asked the score.
	if departed and not was and caption != null:
		caption.clear()
		caption.say([tr("STILL_HERE_LINE_LATCH_SCORE")])

func _build_people() -> void:
	# Freed now, in the tree: the old people never share a frame with the new.
	if _people_root != null:
		_people_root.free()
	if _absence_root != null:
		_absence_root.free()
	people.clear()
	_calm.clear()
	_people_root = Node3D.new()
	_people_root.name = "People"
	add_child(_people_root)
	_absence_root = Node3D.new()
	_absence_root.name = "Absences"
	add_child(_absence_root)
	for person: Dictionary in EpilogueMissionState.people(geometry, refuge):
		var node: Node3D = _person(person)
		if node != null:
			people[str(person["id"])] = node
	_build_absences()

## Absences are as specific as presences: a name still on the board, a cab
## kept for someone. Never a grave for a person the run did not see die. The
## same pass leaves the small traces of who did come, like a tag on a door.
func _build_absences() -> void:
	var names: Array[String] = []
	for who: String in ["cars", "edda", "splice", "sorrel"]:
		if refuge.get(who) != true:
			names.append(who)
	var board: Node3D = _static.get_node_or_null("MissingBoard") as Node3D if _static != null else null
	if board != null:
		for index: int in range(names.size()):
			var at: Vector3 = Vector3(0.6 + float(index) * 0.66, -0.52, 0.016)
			var card: MeshInstance3D = _quad("NamedNote" + names[index].to_pascal_case(), at, Vector2(0.6, 0.44), _material(Color("e8e2d6")))
			card.transform = board.transform * Transform3D(Basis.IDENTITY, at)
			_absence_root.add_child(card)
			var label: WorldSign = WorldSign.new()
			label.name = "NamedNoteCopy" + names[index].to_pascal_case()
			label.configure("STILL_HERE_MISSING_" + names[index].to_upper(), Vector2(0.52, 0.36), Color("2a2420"), true)
			label.transform = board.transform * Transform3D(Basis.IDENTITY, at + Vector3(0, 0, 0.004))
			_absence_root.add_child(label)
	# Years on, the family from the recall car keeps a tag on their door.
	if later and refuge.get("cars") == true and _has("store_a"):
		var tag: MeshInstance3D = _quad("CarTagOnDoor", Vector3(-11.9, 1.6, -13.985), Vector2(0.16, 0.24), _material(Color("d8cfb4")))
		_absence_root.add_child(tag)
		_absence_root.add_child(_quad("CarTagString", Vector3(-11.9, 1.75, -13.982), Vector2(0.01, 0.1), _material(Color("6a5038"))))
	# Years on, Sorrel's cab is kept: a card in the window, nobody in the seat.
	if later and refuge.get("sorrel") != true and _has("tram_running"):
		var window: Vector3 = Vector3(17.0, 1.9, 14.03)
		var card: MeshInstance3D = _box("CabCard", window, Vector3(0.6, 0.3, 0.01), _material(Color("e8e2d6")))
		card.reparent(_absence_root)
		var label: WorldSign = WorldSign.new()
		label.name = "CabCardCopy"
		label.configure("STILL_HERE_CAB_CARD", Vector2(0.56, 0.26), Color("2a2420"), true)
		label.position = window + Vector3(0, 0, 0.008)
		_absence_root.add_child(label)

func _person(person: Dictionary) -> Node3D:
	var id: String = person["id"]
	var pose: String = person["pose"]
	var feet: Vector3 = Vector3(float(person["feet"][0]), float(person["feet"][1]), float(person["feet"][2]))
	var facing: float = PI * 0.5 - float(person["yaw"])
	if id == "latch":
		return _latch(feet, facing, pose == "perch")
	if id == "splice":
		# Splice in their own body: the compact chassis with the offset tool
		# rack. A stand-in synthetic only if that source is missing.
		var own: SpliceCharacter = SpliceCharacter.new()
		if own.configure():
			own.name = "Splice"
			_people_root.add_child(own)
			own.position = feet
			own.rotation.y = facing
			_calm.append(own)
			return own
		own.free()
	var kind: String = "human"
	var accent: Color = Color(0, 0, 0, 0)
	var look: String = SAME_PERSON.get(id, id)
	match id:
		"edda", "tern":
			kind = id
		"orrin":
			kind = "synthetic"
			accent = ORRIN
		"sorrel":
			kind = "synthetic"
			accent = SORREL
		"splice", "mechanic":
			kind = "synthetic"
			accent = Color("9a4e5a") if id == "splice" else Color("7a8a4a")
		_:
			# Free agents are grown people; a child is always a human child.
			kind = "synthetic" if _hash(look) % 5 == 2 and pose != "child" else "human"
	var body: SkinnedCharacter = SkinnedCharacter.new()
	if not body.configure(kind):
		body.free()
		return null
	body.name = id.to_pascal_case()
	var index: int = _hash(look)
	if kind in ["human", "synthetic"] and accent.a == 0.0:
		var synthetic: bool = kind == "synthetic"
		var palette: Array[Color] = M20Waterworks.SYNTHETIC_PANELS if synthetic else M20Waterworks.COATS
		var coat: Color = palette[index % palette.size()]
		if id == "mara":
			coat = MARA_COAT
		elif id == "ascender":
			coat = Color("c8a048")
		elif id == "kneeler":
			coat = Color("5a5a6a")
		var tone: Color = M20Waterworks.PLATE_WARMTH if synthetic else M20Waterworks.SKIN_TONES[(index * 7 + 2) % M20Waterworks.SKIN_TONES.size()]
		# The morning after, everyone is a little greyer for the night.
		var lift: float = 1.05 if not later else 1.25
		CrowdLook.outfit(body, coat, M20Waterworks.TROUSERS[(index * 3 + 1) % M20Waterworks.TROUSERS.size()], tone, lift)
		if synthetic:
			CrowdLook.face_lamp(body, M20Waterworks.FACE_LAMPS[index % M20Waterworks.FACE_LAMPS.size()])
	elif accent.a > 0.0:
		# Named free agents in their own warm paint, never a dark chassis.
		CrowdLook.outfit(body, accent, M20Waterworks.TROUSERS[index % M20Waterworks.TROUSERS.size()], M20Waterworks.PLATE_WARMTH, 1.15)
		CrowdLook.face_lamp(body, Color("ffb060"))
	_people_root.add_child(body)
	body.position = feet
	body.rotation.y = facing
	match pose:
		"child":
			body.scale = Vector3.ONE * (0.64 + float(index % 3) * 0.04)
			body.pose(0.0, false, false, false)
		"sit":
			body.pose(0.0, false, false, false)
			_seat(body, 0.06, false)
		"perch":
			# On a bench, a crate or a cab seat: hips on it, feet down.
			body.pose(0.0, false, false, false)
			_seat(body, _seat_height(feet), _at_table(feet))
		"lie":
			body.pose(0.0, false, false, false, 1.0)
			body.position.y = 0.48
		"work":
			body.pose(0.0, false, false, false, 0.0, true)
		_:
			body.scale = Vector3.ONE * (0.94 + float(index % 7) * 0.015)
			body.pose(0.0, false, false, false)
	if pose != "lie":
		_sway.append(body)
	if id == "ascender":
		# A candle in a jar at the door, with the person, not the court.
		_box("Candle", feet + Vector3(0.5, 0.12, 0.4), Vector3(0.1, 0.24, 0.1), _material(Color("e8dcc0")), _people_root)
		_lamps.append(_light("CandleLight", feet + Vector3(0.5, 0.4, 0.4), Color("ffc27a"), 0.8, 3.0, _people_root))
	if id.begins_with("entrant"):
		# The games' numbered placard: worn on the chest the morning after,
		# nailed over a door years on.
		var placard: MeshInstance3D = MeshInstance3D.new()
		placard.name = "EntrantPlacard"
		var card: BoxMesh = BoxMesh.new()
		card.size = Vector3(0.34, 0.26, 0.02)
		placard.mesh = card
		placard.material_override = _material(Color("e8e2d6"))
		# The number the games painted on them; digits, not copy.
		var number: Label3D = Label3D.new()
		number.name = "EntrantNumber"
		number.text = str(17 + _hash(look) % 60)
		number.font = WorldSign.FONT
		number.font_size = 32
		number.pixel_size = 0.0045
		number.modulate = Color("2a2420")
		number.outline_size = 0
		number.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		number.double_sided = false
		number.position = Vector3(0, 0, 0.012)
		placard.add_child(number)
		if id == "entrant":
			# Flat on the home's wall over the door, its number to the court.
			placard.position = feet + Vector3(0, 2.7, 1.17)
			placard.rotation.y = PI
			_people_root.add_child(placard)
		else:
			placard.position = Vector3(0, 1.28, 0.18)
			body.add_child(placard)
	if id.begins_with("car_family_"):
		# The recall car's luggage tag, still tied to a coat button.
		var tag: MeshInstance3D = MeshInstance3D.new()
		tag.name = "CarTag"
		var slip: BoxMesh = BoxMesh.new()
		slip.size = Vector3(0.09, 0.13, 0.01)
		tag.mesh = slip
		tag.material_override = _material(Color("d8cfb4"))
		tag.position = Vector3(0.08, 1.22, 0.17)
		body.add_child(tag)
	if id == "mara":
		# The folded route case Mara carries everywhere.
		_hand_case(body)
	return body

## Mara's folded route case in the right hand, in skeleton centimetres.
func _hand_case(body: SkinnedCharacter) -> void:
	if body.skeleton == null or body.skeleton.find_bone("RightHand") < 0:
		return
	var grip: BoneAttachment3D = BoneAttachment3D.new()
	grip.name = "RouteCase"
	grip.bone_name = "RightHand"
	body.skeleton.add_child(grip)
	var case: MeshInstance3D = MeshInstance3D.new()
	case.name = "Case"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(30.0, 22.0, 6.0)
	case.mesh = box
	case.layers = ArenaSky.ACTOR_LAYERS
	case.material_override = _material(Color("4a3a2a"))
	case.position = Vector3(0.0, -14.0, 0.0)
	grip.add_child(case)

func _latch(feet: Vector3, facing: float, seated: bool) -> Node3D:
	var latch: LatchView = LatchView.new()
	latch.name = "Latch"
	_people_root.add_child(latch)
	latch.set_render_layers(ArenaSky.ACTOR_LAYERS)
	latch.set_weapon_visible(false)
	latch.set_face_phosphor(Color("ffb860"), Color("6a3a16"), 0.7)
	latch.position = feet
	latch.rotation.y = facing
	if seated:
		# On the bench's front edge, legs over it, looking at the water.
		latch.position = feet + Vector3(0.0, 0.46, 0.0)
		LatchSeat.apply(latch)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.name = "LatchScreenLight"
	lamp.light_color = Color("ffb860")
	lamp.light_energy = 0.7
	lamp.omni_range = 2.2
	lamp.position = Vector3(0.0, 1.6 if not seated else 1.1, 0.2)
	latch.add_child(lamp)
	return latch

## Sit a free person on a seat `height` metres up: pelvis on it a little
## back from the body's origin, knees bent, feet on the ground ahead, hands on
## the knees or on the table in front. Applied after the standing pose, so the
## shared sources stay unchanged. The skeleton works in centimetres.
static func _seat(body: SkinnedCharacter, height: float, table: bool) -> void:
	var skeleton: Skeleton3D = body.skeleton
	var source: LatchSource = body._source
	if skeleton == null or source == null:
		return
	var hips: int = skeleton.find_bone("Hips")
	var rest: float = skeleton.get_bone_global_rest(hips).origin.y
	var at: Vector3 = skeleton.get_bone_pose_position(hips)
	var seat: float = height * 100.0
	at.y -= rest - (seat + 9.0)
	at.z -= 14.0
	skeleton.set_bone_pose_position(hips, at)
	var reach: float = 46.0 if seat > 20.0 else 58.0
	for side: String in ["Left", "Right"]:
		var across: float = 11.0 if side == "Left" else -11.0
		var foot: Vector3 = Vector3(across, maxf(4.0, seat - 52.0), reach)
		source._two_bone(skeleton, side + "UpLeg", side + "Leg", side + "Foot", foot, Vector3(across * 1.5, seat + 60.0, reach + 70.0))
	for side: String in ["Left", "Right"]:
		var across: float = 17.0 if side == "Left" else -17.0
		var hand: Vector3 = Vector3(across, seat + 36.0, 46.0) if table else Vector3(across * 0.9, seat + 14.0, 30.0)
		source._two_bone(skeleton, side + "Arm", side + "ForeArm", side + "Hand", hand, Vector3(across * 2.8, seat + 50.0, -10.0))

## The seat under a perched person: the low solid they sit on.
func _seat_height(feet: Vector3) -> float:
	var best: float = 0.45
	for raw: Variant in _info.get("solids", []):
		var solid: Dictionary = raw
		var top: float = float(solid.get("top", 0.0))
		if float(solid.get("bottom", 0.0)) <= 0.01 and top <= 1.2 and top >= 0.3 \
				and feet.x >= float(solid["min_x"]) - 0.6 and feet.x <= float(solid["max_x"]) + 0.6 \
				and feet.z >= float(solid["min_z"]) - 0.6 and feet.z <= float(solid["max_z"]) + 0.6:
			best = top
	return best

func _at_table(feet: Vector3) -> bool:
	return _has("meal_table") and absf(feet.x - _center("meal_table").x) <= 3.2 and absf(feet.z - _center("meal_table").z) <= 1.8

static func _hash(id: String) -> int:
	var value: int = 7
	for character: String in id:
		value = (value * 31 + character.unicode_at(0)) % 100003
	return value

# ---------------------------------------------------------------- lines

func _process(delta: float) -> void:
	if not is_finite(delta) or geometry.is_empty():
		return
	_clock = fmod(_clock + maxf(delta, 0.0), 600.0)
	if _fountain_material != null:
		_fountain_material.set_shader_parameter("ripple_time", fmod(_clock * 1.4, 32.0))
	for lamp: OmniLight3D in _lamps:
		if is_instance_valid(lamp):
			var base: float = float(lamp.get_meta("base", lamp.light_energy))
			lamp.light_energy = maxf(0.0, base + 0.12 * sin(_clock * 7.3 + lamp.position.x) + 0.06 * sin(_clock * 17.1 + lamp.position.z))
	for index: int in range(_sway.size()):
		var node: Node3D = _sway[index]
		if is_instance_valid(node):
			node.rotation.z = sin(_clock * 0.6 + float(index) * 1.3) * (0.02 if node is MeshInstance3D else 0.0)
	for figure: SpliceCharacter in _calm:
		if is_instance_valid(figure):
			figure.pose(0.0, false, _clock / 4.0)
	_hear()

## Walk past someone and they say their one line, once in each world.
func _hear() -> void:
	if caption == null or departed or people.is_empty() or not hearing:
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var eye: Vector3 = camera.global_position
	var stage: String = "later" if later else "aftermath"
	for id: String in people:
		var key: String = stage + "/" + id
		if not LINES.has(key) or _spoken.get(key, false):
			continue
		var node: Node3D = people[id]
		if not is_instance_valid(node) or Vector2(node.global_position.x - eye.x, node.global_position.z - eye.z).length() > float(HEARING.get(key, HEAR_DISTANCE)):
			continue
		_spoken[key] = true
		var lines: Array[String] = [tr(LINES[key])]
		var reply: String = str(REPLIES.get(key, ""))
		if key == "later/mara":
			lines.append(tr("STILL_HERE_LINE_MARA_VOTE_RESULT"))
		elif not reply.is_empty() and LINES.has(reply) and not _spoken.get(reply, false) and people.has(reply.get_slice("/", 1)):
			_spoken[reply] = true
			lines.append(tr(LINES[reply]))
		caption.say(lines)
		return

# ---------------------------------------------------------------- helpers

func _hurricane_lamp(at: Vector3) -> void:
	_box("LampStool", at + Vector3(0, 0.25, 0), Vector3(0.4, 0.5, 0.4), _material(Color("5a4630")))
	_box("LampBase", at + Vector3(0, 0.55, 0), Vector3(0.26, 0.1, 0.26), _material(Color("4a3a2a")))
	_box("LampGlass", at + Vector3(0, 0.78, 0), Vector3(0.2, 0.32, 0.2), _material(Color("ffd08a"), true, 2.6))
	_box("LampCap", at + Vector3(0, 0.98, 0), Vector3(0.28, 0.08, 0.28), _material(Color("4a3a2a")))
	_lamps.append(_light("EddaLamp", at + Vector3(0, 0.85, 0), Color("ffc27a"), 2.2, 7.0))

## A paper notice flat on a west-facing face, readable from the pier side:
## paper, then each [key, height offset, text bounds] as keyed world copy.
func _notice(at: Vector3, size: Vector2, paper: Color, copy: Array) -> void:
	var root: Node3D = Node3D.new()
	root.name = "Notice"
	root.position = at
	# Quads and labels face +Z; turn them to face west.
	root.rotation.y = -PI * 0.5
	_static.add_child(root)
	root.add_child(_quad("NoticePaper", Vector3.ZERO, size, _material(paper)))
	for line: Array in copy:
		var sign: WorldSign = WorldSign.new()
		sign.name = "NoticeCopy"
		sign.configure(str(line[0]), line[2], Color("2a2420"), true)
		sign.position = Vector3(0.0, float(line[1]), 0.004)
		root.add_child(sign)

func _lantern(at: Vector3) -> void:
	_box("Lantern", at + Vector3(0, 0.16, 0), Vector3(0.16, 0.24, 0.16), _material(Color("ffc27a"), true, 2.4))
	_box("LanternCap", at + Vector3(0, 0.31, 0), Vector3(0.2, 0.05, 0.2), _material(Color("2f2a24")))
	_lamps.append(_light("Lantern", at + Vector3(0, 0.45, 0), Color("ffbf73"), 1.3, 5.0))

func _wet() -> StandardMaterial3D:
	var wet: StandardMaterial3D = StandardMaterial3D.new()
	wet.albedo_color = Color(0.07, 0.08, 0.09, 0.55)
	wet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wet.roughness = 0.08
	wet.metallic_specular = 0.9
	return wet

## A box under the court's static dressing, or under `parent` when it
## belongs to something rebuilt with the people.
func _box(label: String, at: Vector3, size: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	(parent if parent != null else _static).add_child(node)
	return node

func _plane(label: String, at: Vector3, size: Vector2, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	_static.add_child(node)
	return node

func _quad(label: String, at: Vector3, size: Vector2, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	return node

func _light(label: String, at: Vector3, color: Color, energy: float, reach: float, parent: Node3D = null) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = label
	light.position = at
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.light_specular = 0.25
	light.distance_fade_enabled = true
	light.distance_fade_begin = 60.0
	light.distance_fade_length = 20.0
	light.add_to_group(ArenaSky.PRACTICAL_GROUP)
	light.set_meta("base", energy)
	(parent if parent != null else _static).add_child(light)
	return light

static func _material(color: Color, glow: bool = false, energy: float = 1.0) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
	return material
