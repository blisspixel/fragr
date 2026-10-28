class_name M05Dressing
extends M04Dressing

## No Forwarding Address's golden-slice dressing (docs/campaign/l05-no-forwarding-address.md,
## docs/design/earth.md "M05 Low Water roofs"). It extends Level 4's presenter
## so the two levels share one district vocabulary: the same plaster colours,
## shutters, windows, washing, belongings, lamps and the tram's old terracotta
## and cream. The server owns every solid; this presenter only furnishes them:
## flush paint and relief on registered faces, possessions on existing tops,
## things in a wall's own clearance, overhead runs above head height and
## practical light. A body that could stop a pawn or a shot is never added.
##
## The story is told without words. Ten minutes after Level 4 the shutters are
## down on every street, the notice is pasted on each door and a chalk cross
## says who has already gone. The roofs are how people are leaving: duckboards
## lead from the stair past the water tanks to the plank bridge, and what was
## dropped on the way is still lying there. The workshop is Splice's, with the
## half-green tram the neighbours voted on and the Union's black pen on its
## floor. The tram trench is a working rail cut under the backs of the homes,
## with recesses, span wires and sleepers, and at its end the freight
## platform's floodlights over Tern's battered carrier.

const L5_MAP_ID: int = 1005
const L5_HALF: float = 40.0
const ROOF: float = 4.0
## The registered tram's start, so its livery can follow the moving solid.
const TRAM_LOW: Vector3 = Vector3(-1.5, 0, 4)
const TRAM_HIGH: Vector3 = Vector3(1.5, 1, 8)
## Only geometry that never moves: the roofs, the bridge, the workshop wall,
## the stripped chassis, a freight wall and the carrier's hull. Never the
## tram, which rides the trench, or the freight gate, which lifts: either can
## move in a re-sent MapInfo, and the district must stay dressed through it.
const L5_KEY_SOLIDS: Array = [
	[Vector3(-30, 0, -36), Vector3(-7, 4, -20)],
	[Vector3(7, 0, -36), Vector3(30, 4, -20)],
	[Vector3(-7, 3.75, -29), Vector3(7, 4, -26)],
	[Vector3(-23, 0, -16), Vector3(18, 4, -15.5)],
	[Vector3(3, 0, -13), Vector3(7, 2.5, -7)],
	[Vector3(-40, 0, 33.5), Vector3(-15, 3, 34)],
	[Vector3(-12, 0.5, 36), Vector3(2, 3, 39.5)],
]
const FLOOD_LAMP: Color = Color(1.0, 0.9, 0.74)
const GATE_LOW: Vector3 = Vector3(-15, 0, 33.5)
const GATE_HIGH: Vector3 = Vector3(15, 3, 34)

## The tram's livery, moved with the server's tram as its state arrives.
var tram_room: Node3D
## The freight gate's cladding, raised with the gate solid MapInfo carries.
var gate_room: Node3D
var _tram_start_z: float = 6.0

func clear_map() -> void:
	super.clear_map()
	tram_room = null
	gate_room = null

## No Forwarding Address's own authored layout only. A custom map reusing the
## id with different furniture gets no dressing rather than floating props.
static func layout(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != L5_MAP_ID or not info.get("solids") is Array:
		return false
	if not is_equal_approx(float(info.get("half_extent", 0.0)), L5_HALF):
		return false
	var found: int = 0
	for raw: Variant in info["solids"]:
		if not raw is Dictionary:
			continue
		var solid: Dictionary = raw
		var low: Vector3 = Vector3(float(solid.get("min_x", 0.0)), float(solid.get("bottom", 0.0)), float(solid.get("min_z", 0.0)))
		var high: Vector3 = Vector3(float(solid.get("max_x", 0.0)), float(solid.get("top", 0.0)), float(solid.get("max_z", 0.0)))
		for pair: Array in L5_KEY_SOLIDS:
			if low.is_equal_approx(pair[0]) and high.is_equal_approx(pair[1]):
				found += 1
	return found == L5_KEY_SOLIDS.size()

func configure_map(info: Dictionary) -> void:
	if active() and layout(info):
		# The same district re-sent (the freight gate lifting): keep it, and
		# hide the tram until the next state places it, as ArenaCover does.
		if tram_room != null:
			tram_room.visible = false
		_place_gate(info)
		return
	clear_map()
	if not layout(info):
		return
	_tram_start_z = _tram_start(info)
	_build_boundary()
	_build_ground()
	_build_roofs()
	_build_tanks()
	_build_bridge()
	_build_crane()
	_build_workshop_shell()
	_build_paint_bay()
	_build_pen()
	_build_service_bay()
	_build_market_strip()
	_build_trench()
	_build_freight()
	_build_carrier()
	_build_tram()
	_build_gate()
	_place_gate(info)
	for room: Node3D in _unattached:
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

## Raise the gate's cladding to wherever the server's gate solid now sits.
## The gate is found by its fixed footprint; its height is the server's fact.
func _place_gate(info: Dictionary) -> void:
	if gate_room == null or not info.get("solids") is Array:
		return
	for raw: Variant in info["solids"]:
		if not raw is Dictionary:
			continue
		var solid: Dictionary = raw
		if is_equal_approx(float(solid.get("min_x", 0.0)), GATE_LOW.x) and is_equal_approx(float(solid.get("max_x", 0.0)), GATE_HIGH.x) \
			and is_equal_approx(float(solid.get("min_z", 0.0)), GATE_LOW.z) and is_equal_approx(float(solid.get("max_z", 0.0)), GATE_HIGH.z):
			var bottom: float = float(solid.get("bottom", 0.0))
			if is_finite(bottom) and absf(bottom) <= 20.0:
				gate_room.visible = true
				gate_room.position = Vector3(0.0, bottom, 0.0)
				return
	gate_room.visible = false

## Follow the server's tram along the trench. Presentation only: the state
## says where the tram is; nothing here moves or decides it.
func apply_state(state: Dictionary) -> void:
	if tram_room == null:
		return
	var valid: bool = state.get("id") == MissionState.M05_ID and state.get("m05") is Dictionary \
		and state["m05"].get("tram") is Dictionary and state["m05"]["tram"].get("feet") is Array \
		and (state["m05"]["tram"]["feet"] as Array).size() == 3
	var delta: float = 0.0
	if valid:
		delta = float(state["m05"]["tram"]["feet"][2]) - _tram_start_z
		valid = is_finite(delta) and absf(delta) <= L5_HALF * 2.0
	tram_room.visible = valid
	tram_room.position = Vector3(0.0, 0.0, delta if valid else 0.0)

static func _tram_start(info: Dictionary) -> float:
	var m05: Variant = info.get("m05")
	if m05 is Dictionary and (m05 as Dictionary).get("tram") is Dictionary:
		var start: Variant = m05["tram"].get("start")
		if start is Array and (start as Array).size() == 3 and is_finite(float(start[2])):
			return float(start[2])
	return (TRAM_LOW.z + TRAM_HIGH.z) * 0.5

# --- shared Level 5 builders --------------------------------------------------

## Cover every vertical face of a box with one finish, and optionally its top.
func _wrap(props: Node3D, label: String, low: Vector3, high: Vector3, finish: Material, top: Material = null, skip: Array = []) -> void:
	var size: Vector3 = high - low
	var centre: Vector3 = (low + high) * 0.5
	for face: Array in [[Vector3.FORWARD, size.x, Vector3(centre.x, centre.y, low.z)], [Vector3.BACK, size.x, Vector3(centre.x, centre.y, high.z)],
			[Vector3.LEFT, size.z, Vector3(low.x, centre.y, centre.z)], [Vector3.RIGHT, size.z, Vector3(high.x, centre.y, centre.z)]]:
		var out: Vector3 = face[0]
		if out in skip:
			continue
		_sheet(props, label, Vector2(float(face[1]) - 0.01, size.y - 0.01), finish, (face[2] as Vector3) + out * 0.005, out)
	if top != null:
		_floor(props, label + "Top", Vector2(low.x + 0.005, low.z + 0.005), Vector2(high.x - 0.005, high.z - 0.005), top, high.y + 0.004)

## Warm weathered timber: plain planks laid over a dark gap, so a walk,
## a deck or a bench reads as boards at play distance. `across_x` lays the
## planks across x (a walk running along z).
const TIMBER: Array[Color] = [Color("9c7a56"), Color("8a6a4a"), Color("a88660"), Color("7f6246")]

func _planks(props: Node3D, label: String, low: Vector2, high: Vector2, height: float, across_x: bool, pitch: float = 0.24) -> void:
	_floor(props, label + "Gap", low, high, _mat("pallet_gap", Color("2b2420"), 0.0, 1.0), height)
	var span: float = (high.y - low.y) if across_x else (high.x - low.x)
	var count: int = maxi(1, int(span / pitch))
	var step: float = span / float(count)
	for index: int in range(count):
		var tint: Color = TIMBER[(index * 3 + int(absf(low.x + low.y))) % TIMBER.size()]
		var finish: StandardMaterial3D = _mat("timber_%s" % tint.to_html(false), tint, 0.0, 0.9)
		var a: float = (low.y if across_x else low.x) + step * float(index) + 0.02
		var b: float = a + step - 0.04
		if across_x:
			_floor(props, label, Vector2(low.x, a), Vector2(high.x, b), finish, height + 0.003)
		else:
			_floor(props, label, Vector2(a, low.y), Vector2(b, high.y), finish, height + 0.003)

## Plank cladding on every vertical face of a box: timber with dark seams.
func _plank_faces(props: Node3D, label: String, low: Vector3, high: Vector3, tint: Color, skip: Array = []) -> void:
	var finish: StandardMaterial3D = _mat("timber_%s" % tint.to_html(false), tint, 0.0, 0.9)
	_wrap(props, label, low, high, finish, null, skip)
	var seam: StandardMaterial3D = _mat("pallet_gap", Color("2b2420"), 0.0, 1.0)
	var size: Vector3 = high - low
	var centre: Vector3 = (low + high) * 0.5
	var rows: int = maxi(1, int(size.y / 0.2))
	for face: Array in [[Vector3.FORWARD, size.x, Vector3(centre.x, 0, low.z)], [Vector3.BACK, size.x, Vector3(centre.x, 0, high.z)],
			[Vector3.LEFT, size.z, Vector3(low.x, 0, centre.z)], [Vector3.RIGHT, size.z, Vector3(high.x, 0, centre.z)]]:
		var out: Vector3 = face[0]
		if out in skip:
			continue
		for row: int in range(1, rows):
			_sheet(props, label + "Seam", Vector2(float(face[1]) - 0.02, 0.025), seam, (face[2] as Vector3) + Vector3(0, low.y + size.y * float(row) / float(rows), 0) + out * 0.007, out)

## A chalk cross a neighbour leaves on a door when the home is empty.
func _chalk_cross(props: Node3D, at: Vector3, out: Vector3) -> void:
	var chalk: StandardMaterial3D = _mat("chalk", Color("e6dfcc"), 0.0, 0.95)
	for lean: float in [-0.75, 0.75]:
		var stroke: MeshInstance3D = _sheet(props, "ChalkCross", Vector2(0.34, 0.04), chalk, at, out)
		stroke.rotate_object_local(Vector3.BACK, lean)

## The notice to vacate, pasted on a shutter or a door: paper and a small seal.
func _pasted_notice(props: Node3D, at: Vector3, out: Vector3, index: int) -> void:
	var paper: StandardMaterial3D = _mat("pasted_notice", Color("e2dccb"), 0.0, 0.95)
	var sheet: MeshInstance3D = _sheet(props, "PastedNotice", Vector2(0.42, 0.58), paper, at, out)
	sheet.rotate_object_local(Vector3.BACK, float(index % 3 - 1) * 0.03)
	_sheet(props, "NoticeSeal", Vector2(0.12, 0.12), _seal_material(), at + Vector3(0, 0.19, 0) + out * 0.002, out)
	var rule: StandardMaterial3D = _mat("notice_rule", Color("8a8574"), 0.0, 0.95)
	for line: int in range(4):
		_sheet(props, "NoticeRule", Vector2(0.3, 0.018), rule, at + Vector3(0, 0.02 - float(line) * 0.07, 0) + out * 0.002, out)

## A caged wall lamp over a maintenance recess or a door, with its own pool.
func _service_lamp(room: Node3D, props: Node3D, at: Vector3, out: Vector3, energy: float = 1.2, reach: float = 6.5) -> void:
	_wall_lamp(props, at, out)
	_omni(room, "ServiceLamp", at + out * 0.6 - Vector3(0, 0.25, 0), WARM_LAMP, energy, reach)

# --- the district: homes over the streets and the backs over the trench ------

func _build_boundary() -> void:
	var south: Node3D = _room("StreetSouth")
	var props: Node3D = _props(south)
	# The street behind the roofs: the same homes over shops as Level 4, every
	# shutter down, the notice pasted on and a chalk cross where they have gone.
	_facade(props, Vector3(WALL, 0, -WALL), Vector3.LEFT, Vector3.BACK, WALL * 2.0, WALL_TOP, 4, true)
	for index: int in range(9):
		var x: float = -34.0 + float(index) * 8.6
		var spot: Vector3 = Vector3(x, 1.45, -WALL) + Vector3.BACK * 0.05
		_pasted_notice(props, spot, Vector3.BACK, index)
		if index % 3 != 1:
			_chalk_cross(props, spot + Vector3(0.0, -0.55, 0.003), Vector3.BACK)
	_finish(south)
	var west: Node3D = _room("StreetWest")
	props = _props(west)
	_facade(props, Vector3(-WALL, 0, -WALL), Vector3.BACK, Vector3.RIGHT, 29.5, WALL_TOP, 7, true)
	for z: float in [-35.0, -27.0, -18.5]:
		_pasted_notice(props, Vector3(-WALL, 1.45, z) + Vector3.RIGHT * 0.05, Vector3.RIGHT, int(z))
		_chalk_cross(props, Vector3(-WALL, 0.9, z) + Vector3.RIGHT * 0.053, Vector3.RIGHT)
	_clinic_front(props)
	_retaining(west, props, Vector3(-WALL, 0, 3.5), Vector3.BACK, Vector3.RIGHT, 30.0, 3)
	_yard_wall(props, Vector3(-WALL, 0, 34.0), Vector3.BACK, Vector3.RIGHT, 5.5)
	_finish(west)
	var east: Node3D = _room("StreetEast")
	props = _props(east)
	_yard_wall(props, Vector3(WALL, 0, WALL), Vector3.FORWARD, Vector3.LEFT, 5.5)
	_retaining(east, props, Vector3(WALL, 0, 33.5), Vector3.FORWARD, Vector3.LEFT, 29.5, 8)
	_facade(props, Vector3(WALL, 0, 4), Vector3.FORWARD, Vector3.LEFT, 43.5, WALL_TOP, 9, true)
	for z: float in [-2.0, -12.5, -26.0, -34.0]:
		_pasted_notice(props, Vector3(WALL, 1.45, z) + Vector3.LEFT * 0.05, Vector3.LEFT, int(z))
		if int(z) % 2 == 0:
			_chalk_cross(props, Vector3(WALL, 0.9, z) + Vector3.LEFT * 0.053, Vector3.LEFT)
	_finish(east)
	var north: Node3D = _room("FreightYard")
	props = _props(north)
	_yard_wall(props, Vector3(WALL, 0, WALL), Vector3.LEFT, Vector3.FORWARD, WALL * 2.0)
	_finish(north)

## Edda's clinic from Level 4, closed: the same sage render and painted hand
## with a sprout, its windows dark and its shutter down. She got out.
func _clinic_front(props: Node3D) -> void:
	var out: Vector3 = Vector3.RIGHT
	var sage: ShaderMaterial = _surface("enamel", Color("9fae96"))
	var frame: StandardMaterial3D = _mat("window_frame", Color("e0d3b8").darkened(0.15), 0.0, 0.8)
	var dark: StandardMaterial3D = _mat("glass_dark", Color("2b3634"), 0.2, 0.35)
	var from: float = -10.0
	var to: float = 3.5
	var mid: float = (from + to) * 0.5
	_sheet(props, "ClinicRender", Vector2(to - from - 0.02, WALL_TOP - 0.3), sage, Vector3(-WALL, (WALL_TOP - 0.3) * 0.5, mid) + out * 0.014, out)
	_sheet(props, "ClinicPlinth", Vector2(to - from - 0.02, 0.45), _surface("concrete", Color("6f7a68")), Vector3(-WALL, 0.225, mid) + out * 0.018, out)
	_relief(props, "ClinicCornice", Vector3(to - from, 0.16, 0.14), _mat("clinic_cornice", Color("b7c0aa")), Vector3(-WALL, WALL_TOP - 0.38, mid), out)
	_relief(props, "ClinicBand", Vector3(to - from, 0.12, 0.1), _mat("clinic_cornice", Color("b7c0aa")), Vector3(-WALL, 3.3, mid), out)
	# The shutter down over the covered entrance, the lamp over it out.
	var steel: Color = SHUTTERS[0]
	_sheet(props, "ClinicShutter", Vector2(3.2, 2.6), _surface("service_steel", steel, 0.25, 0.6), Vector3(-WALL, 1.3, -1.5) + out * 0.022, out)
	for row: int in range(7):
		_relief(props, "ShutterSlat", Vector3(3.2, 0.035, 0.012), _mat("shutter_slat_%s" % steel.to_html(false), steel.darkened(0.3), 0.3, 0.6), Vector3(-WALL, 0.3 + float(row) * 0.36, -1.5) + out * 0.022, out)
	_relief(props, "ClinicCanopy", Vector3(4.0, 0.12, 0.9), _mat("clinic_canopy", Color("6f8a6a"), 0.0, 0.85), Vector3(-WALL, 2.95, -1.5), out)
	_wall_lamp(props, Vector3(-WALL, 3.45, -1.5) + out * 0.02, out)
	_pasted_notice(props, Vector3(-WALL, 1.5, -2.3) + out * 0.04, out, 2)
	for z: float in [-8.2, -5.6, 1.6]:
		_sheet(props, "ClinicWindow", Vector2(1.4, 1.2), dark, Vector3(-WALL, 1.9, z) + out * 0.02, out)
		_relief(props, "ClinicSill", Vector3(1.6, 0.07, 0.15), frame, Vector3(-WALL, 1.27, z), out)
		_relief(props, "ClinicHead", Vector3(1.6, 0.07, 0.06), frame, Vector3(-WALL, 2.53, z), out)
		var curtain: StandardMaterial3D = _mat("clinic_curtain", Color("d8cfb6"), 0.0, 0.95)
		_sheet(props, "ClinicCurtain", Vector2(1.3, 1.1), curtain, Vector3(-WALL, 1.9, z) + out * 0.024, out)
	for z: float in [-8.0, -4.5, -1.0, 2.5]:
		_window(props, Vector3(-WALL, 4.6, z) + out * 0.0, out, Vector2(1.0, 1.3), 3 if z < 0.0 else 8, Color("9fae96"))
	# The painted hand holding a sprout, the clinic's mark in both levels.
	var hand: StandardMaterial3D = _mat("mural_hand", Color("c49a6a"), 0.0, 0.9)
	var sprout: StandardMaterial3D = _mat("mural_sprout", Color("6f8a4e"), 0.0, 0.9)
	var ground: StandardMaterial3D = _mat("mural_ground", Color("8fa595"), 0.0, 0.9)
	var at: Vector3 = Vector3(-WALL, 4.2, -5.0) + out * 0.02
	_sheet(props, "MuralGround", Vector2(3.4, 2.4), ground, at + Vector3(0, 1.4, 0), out)
	_sheet(props, "MuralPalm", Vector2(1.4, 0.55), hand, at + Vector3(0, 0.95, 0) + out * 0.003, out)
	for index: int in range(4):
		_sheet(props, "MuralFinger", Vector2(0.22, 0.48), hand, at + Vector3(0, 1.4, -0.5 + float(index) * 0.28) + out * 0.003, out)
	_sheet(props, "MuralThumb", Vector2(0.44, 0.2), hand, at + Vector3(0, 1.1, 0.82) + out * 0.003, out)
	_sheet(props, "MuralStem", Vector2(0.08, 0.8), sprout, at + Vector3(0, 1.75, 0) + out * 0.004, out)
	for side: float in [-1.0, 1.0]:
		var leaf: MeshInstance3D = _sheet(props, "MuralLeaf", Vector2(0.44, 0.2), sprout, at + Vector3(0, 2.02 + side * 0.06, side * 0.22) + out * 0.004, out)
		leaf.rotate_object_local(Vector3.BACK, side * 0.4)
	for z: float in [-9.3, 2.9]:
		_pot_plant(props, Vector3(-WALL + 0.32, 0.0, z), 0.95, int(z + 10.0))

## The trench side: a cast retaining wall to street level, with buttresses,
## weep holes, a cable tray and maintenance recesses, and the backs of the
## homes standing on it with their washing out over the cut.
func _retaining(room: Node3D, props: Node3D, origin: Vector3, along: Vector3, out: Vector3, length: float, seed_value: int) -> void:
	var cut: float = 4.2
	var concrete: StandardMaterial3D = _tiled("trench_concrete", EnvironmentTextures.EARTH + "earth_yard_cast_concrete.png", Color("a39a8b"), 2.0)
	var buttress: StandardMaterial3D = _tiled("trench_buttress", EnvironmentTextures.EARTH + "earth_yard_cast_concrete.png", Color("8e8576"), 2.0)
	var coping: StandardMaterial3D = _mat("coping", Color("8e8576"), 0.0, 0.9)
	var iron: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	var stain: StandardMaterial3D = _mat("weep_stain", Color("5f6152"), 0.0, 0.95)
	var hole: StandardMaterial3D = _mat("weep_hole", Color("1d1e1c"), 0.0, 1.0)
	var centre: Vector3 = origin + along * length * 0.5
	_sheet(props, "RetainingWall", Vector2(length - 0.02, cut), concrete, centre + Vector3(0, cut * 0.5, 0) + out * 0.012, out)
	_relief(props, "Coping", Vector3(length, 0.2, 0.3), coping, centre + Vector3(0, cut + 0.1, 0), out)
	var steps: int = int(length / 1.5)
	for index: int in range(steps):
		var s: float = 0.75 + float(index) * 1.5
		var spot: Vector3 = origin + along * s
		_sheet(props, "WeepHole", Vector2(0.12, 0.12), hole, spot + Vector3(0, 0.55, 0) + out * 0.016, out)
		_sheet(props, "WeepStain", Vector2(0.14, 0.38), stain, spot + Vector3(0, 0.3, 0) + out * 0.014, out)
	for index: int in range(int(length / 6.0) + 1):
		var spot: Vector3 = origin + along * minf(float(index) * 6.0, length - 0.3) + along * (0.3 if index == 0 else 0.0)
		_relief(props, "Buttress", Vector3(0.6, cut, 0.22), buttress, spot + Vector3(0, cut * 0.5, 0), out)
	# A cable tray and its cables along the wall above head height.
	_relief(props, "CableTray", Vector3(length, 0.06, 0.24), iron, centre + Vector3(0, 3.4, 0), out)
	_relief(props, "TrayCables", Vector3(length, 0.08, 0.16), _mat("cable", Color("232526"), 0.0, 0.7), centre + Vector3(0, 3.46, 0), out)
	# Maintenance recesses: a dark iron door in a painted frame, a caged lamp.
	var door: StandardMaterial3D = _mat("recess_door", Color("2c302e"), 0.4, 0.6)
	var ochre: StandardMaterial3D = _mat("recess_ochre", Color("b0843e"), 0.0, 0.8)
	for s: float in [length * 0.22, length * 0.62]:
		var spot: Vector3 = origin + along * s
		_sheet(props, "RecessFrame", Vector2(1.7, 2.45), ochre, spot + Vector3(0, 1.22, 0) + out * 0.018, out)
		_sheet(props, "RecessDoor", Vector2(1.4, 2.25), door, spot + Vector3(0, 1.13, 0) + out * 0.022, out)
		_relief(props, "RecessHinge", Vector3(0.06, 2.1, 0.04), iron, spot + Vector3(0, 1.13, 0) + Vector3.UP.cross(out).normalized() * 0.62 + out * 0.02, out)
		_relief(props, "RecessStep", Vector3(1.8, 0.08, 0.3), coping, spot + Vector3(0, 0.04, 0), out)
		_service_lamp(room, props, spot + Vector3(0, 2.6, 0) + out * 0.02, out, 1.1, 6.5)
	# The backs of the homes on the street above the cut, washing out.
	var start: float = 0.0
	var building: int = 0
	var widths: Array[float] = [6.4, 9.6, 6.4, 3.2 * 2.0, 9.6]
	var pipe: StandardMaterial3D = _mat("drainpipe", Color("4f5a55"), 0.3, 0.6)
	while start < length - 0.5:
		var width: float = minf(widths[(building + seed_value) % widths.size()], length - start)
		var tint: Color = PAINTS[(building * 5 + seed_value) % PAINTS.size()].darkened(0.05)
		var height: float = WALL_TOP - cut - float((building + seed_value) % 2) * 0.3
		var middle: Vector3 = origin + along * (start + width * 0.5)
		_sheet(props, "BackPlaster", Vector2(width - 0.02, height), _surface("enamel", tint), middle + Vector3(0, cut + 0.2 + height * 0.5, 0) + out * 0.012, out)
		_relief(props, "BackParapet", Vector3(width, 0.14, 0.12), _mat("parapet_%s" % tint.to_html(false), tint.darkened(0.15)), middle + Vector3(0, cut + 0.2 + height - 0.07, 0), out)
		var bays: int = maxi(1, int(round(width / BAY)))
		for bay: int in range(bays):
			var s: float = start + width / float(bays) * (float(bay) + 0.5)
			var hash_value: int = (seed_value * 5 + building * 11 + bay * 3) % 12
			_window(props, origin + along * s + Vector3(0, 6.1, 0), out, Vector2(0.9, 1.1), hash_value, tint)
		if building % 2 == 0 and width > 6.0:
			var a: Vector3 = origin + along * (start + 0.8) + Vector3(0, 5.35, 0) + out * 0.45
			var b: Vector3 = origin + along * (start + width - 0.8) + Vector3(0, 5.35, 0) + out * 0.45
			_washing(props, a, b, 0.2, building + seed_value)
		var edge: Vector3 = origin + along * (start + width) + out * 0.09
		if start + width < length - 0.5:
			_shape.rod(props, "Downpipe", edge + Vector3(0, WALL_TOP - 0.4, 0), edge + Vector3(0, 0.2, 0), 0.05, pipe, 6)
		start += width
		building += 1

## A freight yard wall: cast concrete with an ochre and black band, and
## ribbed steel sheeting above it.
func _yard_wall(props: Node3D, origin: Vector3, along: Vector3, out: Vector3, length: float) -> void:
	var concrete: StandardMaterial3D = _tiled("yard_concrete", EnvironmentTextures.EARTH + "earth_yard_cast_concrete.png", Color("948b7d"), 2.0)
	var sheeting: StandardMaterial3D = _tiled("yard_sheeting", EnvironmentTextures.PRODUCTION + "low_water_steel.png", Color("8f9a90"), 1.5)
	var centre: Vector3 = origin + along * length * 0.5
	_sheet(props, "YardWall", Vector2(length - 0.02, 3.2), concrete, centre + Vector3(0, 1.6, 0) + out * 0.012, out)
	_sheet(props, "YardSheeting", Vector2(length - 0.02, WALL_TOP - 3.4), sheeting, centre + Vector3(0, 3.4 + (WALL_TOP - 3.4) * 0.5, 0) + out * 0.012, out)
	_hazard_band(props, centre + Vector3(0, 3.3, 0) + out * 0.016, out, length - 0.04, 0.2)
	var rib: StandardMaterial3D = _mat("cladding_rib", Color("6c7468"), 0.3, 0.6)
	for index: int in range(int(length / 0.8)):
		_relief(props, "SheetRib", Vector3(0.05, WALL_TOP - 3.5, 0.025), rib, origin + along * (0.4 + float(index) * 0.8) + Vector3(0, 3.4 + (WALL_TOP - 3.4) * 0.5, 0), out)

## Alternate ochre and black, the freight lines' own hazard paint. Never red.
func _hazard_band(props: Node3D, at: Vector3, out: Vector3, length: float, tall: float) -> void:
	var ochre: StandardMaterial3D = _mat("hazard_ochre", Color("c49a3c"), 0.0, 0.8)
	var black: StandardMaterial3D = _mat("hazard_black", Color("26262a"), 0.0, 0.8)
	var side: Vector3 = Vector3.UP.cross(out).normalized()
	_sheet(props, "HazardBand", Vector2(length, tall), ochre, at, out)
	var count: int = int(length / 0.8)
	for index: int in range(count):
		_sheet(props, "HazardStripe", Vector2(0.4, tall), black, at + side * (-length * 0.5 + 0.6 + float(index) * 0.8) + out * 0.001, out)

# --- the ground: streets, the workshop slab, the trench and the platform ------

func _build_ground() -> void:
	var room: Node3D = _room("Ground")
	var props: Node3D = _props(room)
	var setts: ShaderMaterial = _surface("concrete", Color("847a6d"), 0.5, 0.85)
	var asphalt: ShaderMaterial = _surface("concrete", Color("5c5a55"), 4.0, 0.25)
	# The street behind the roofs and the lanes either side of them: setts.
	_floor(props, "BackStreet", Vector2(-WALL + 0.02, -WALL + 0.02), Vector2(WALL - 0.02, -36.0), setts)
	_floor(props, "WestLane", Vector2(-WALL + 0.02, -36.0), Vector2(-30.0, -16.0), setts)
	_floor(props, "EastLane", Vector2(30.0, -36.0), Vector2(WALL - 0.02, -16.0), setts)
	# The street the sweep holds, between the roofs: dark asphalt.
	_floor(props, "SweepStreet", Vector2(-7.0, -36.0), Vector2(7.0, -20.0), asphalt, 0.009)
	_floor(props, "WorkshopLane", Vector2(-30.0, -20.0), Vector2(30.0, -16.0), _surface("concrete", Color("6f6a62"), 2.0, 0.4), 0.009)
	# The market strip and the tram yard east of the workshop.
	_floor(props, "MarketSetts", Vector2(-WALL + 0.02, -16.0), Vector2(-23.0, 3.5), setts, 0.009)
	_floor(props, "TramYard", Vector2(18.0, -16.0), Vector2(WALL - 0.02, 3.5), asphalt, 0.009)
	# The workshop slab: worn poured concrete, oil, painted bay lines.
	_floor(props, "WorkshopSlab", Vector2(-22.5, -15.5), Vector2(17.5, 3.98), _surface("concrete", Color("6a6760"), 4.0, 0.3), 0.009)
	var oil: StandardMaterial3D = _mat("oil_stain", Color("3a3836"), 0.0, 0.7)
	for at: Vector2 in [Vector2(5.0, -4.5), Vector2(-3.5, -11.0), Vector2(14.5, -7.5), Vector2(-15.5, -9.0), Vector2(0.5, -1.5)]:
		_floor(props, "OilStain", at - Vector2(0.8, 0.5), at + Vector2(0.8, 0.5), oil, 0.012)
	var bay_line: StandardMaterial3D = _mat("road_paint", Color("c9a23c"), 0.0, 0.9)
	for line: Array in [[Vector2(2.2, -15.4), Vector2(2.32, 3.9)], [Vector2(7.8, -15.4), Vector2(7.92, 3.9)], [Vector2(-11.0, -15.4), Vector2(-10.88, -0.0)], [Vector2(-22.4, -1.6), Vector2(-12.4, -1.48)]]:
		_floor(props, "BayLine", line[0], line[1], bay_line, 0.011)
	# The inspection pit under the service bay: dark, edged in ochre.
	_floor(props, "InspectionPit", Vector2(-9.6, -13.3), Vector2(-6.4, -10.2), _mat("pit_dark", Color("1f2020"), 0.0, 1.0), 0.012)
	for z: float in [-13.3, -10.3]:
		_floor(props, "PitEdge", Vector2(-9.7, z), Vector2(-6.3, z + 0.1), bay_line, 0.013)
	# The trench: ballast under the line, concrete cess either side and the
	# old cinder beyond, toward the retaining walls.
	_floor(props, "TrenchCinder", Vector2(-WALL + 0.02, 3.98), Vector2(WALL - 0.02, 33.5), _surface("concrete", Color("6b655b"), 1.0, 0.5))
	_floor(props, "TrenchCess", Vector2(-14.0, 3.98), Vector2(14.0, 28.0), _tiled("cess", EnvironmentTextures.EARTH + "earth_yard_cast_concrete.png", Color("a0978a"), 2.0), 0.009)
	_floor(props, "Ballast", Vector2(-2.2, 3.98), Vector2(2.2, 33.5), _surface("concrete", Color("6f6a61"), 0.25, 0.9), 0.01)
	for x: float in [-14.0, -2.35, 2.25, 13.9]:
		_floor(props, "CessEdge", Vector2(x, 3.98), Vector2(x + 0.1, 28.0), bay_line, 0.012)
	var drain: StandardMaterial3D = _mat("gutter", Color("4b4a46"), 0.0, 0.9)
	for x: float in [-38.9, 38.5]:
		_floor(props, "WallDrain", Vector2(x, 3.98), Vector2(x + 0.4, 33.5), drain, 0.011)
	# Sleepers and rails: the main line from the workshop to the platform, and
	# the paint-bay siding under the stripped chassis.
	var sleeper: StandardMaterial3D = _mat("sleeper", Color("4a3a2c"), 0.0, 0.9)
	var z_sleeper: float = 4.2
	while z_sleeper < 33.3:
		_floor(props, "Sleeper", Vector2(-1.3, z_sleeper), Vector2(1.3, z_sleeper + 0.24), sleeper, 0.014)
		z_sleeper += 0.7
	var rail: StandardMaterial3D = _mat("rail_steel", Color("8e8f8a"), 0.7, 0.35)
	var groove: StandardMaterial3D = _mat("rail_groove", Color("2a2928"), 0.0, 1.0)
	for x: float in [-0.72, 0.72]:
		_floor(props, "Rail", Vector2(x - 0.04, -15.4), Vector2(x + 0.04, 33.45), rail, 0.018)
		_floor(props, "RailGroove", Vector2(x + 0.04, -15.4), Vector2(x + 0.1, 3.98), groove, 0.011)
	for x: float in [4.28, 5.72]:
		_floor(props, "SidingRail", Vector2(x - 0.04, -15.4), Vector2(x + 0.04, 3.9), rail, 0.018)
		_floor(props, "RailGroove", Vector2(x + 0.04, -15.4), Vector2(x + 0.1, 3.9), groove, 0.011)
	# Board foot crossings over the line, where people cross the cut.
	for z: float in [12.5, 24.8]:
		_planks(props, "FootCrossing", Vector2(-2.3, z), Vector2(2.3, z + 1.6), 0.02, false, 0.3)
	# The platform apron and its ramp edge, and the pad past the gate.
	_floor(props, "PlatformApron", Vector2(-14.0, 28.0), Vector2(14.0, 33.5), _surface("concrete", Color("8a847a"), 2.0, 0.35), 0.009)
	for index: int in range(28):
		var x: float = -13.5 + float(index)
		_floor(props, "RampChevron", Vector2(x - 0.5, 27.75), Vector2(x + 0.5, 28.25), bay_line if index % 2 == 0 else _mat("hazard_black", Color("26262a"), 0.0, 0.8), 0.013)
	_floor(props, "CarrierPad", Vector2(-WALL + 0.02, 34.0), Vector2(WALL - 0.02, WALL - 0.02), _surface("concrete", Color("777168"), 4.0, 0.3), 0.009)
	for index: int in range(12):
		var angle: float = TAU * float(index) / 12.0
		var ring: MeshInstance3D = _floor(props, "PadRing", Vector2(-0.9, -0.08), Vector2(0.9, 0.08), bay_line, 0.012)
		ring.position = Vector3(-5.0 + cos(angle) * 9.0, 0.012, 37.8 + sin(angle) * 3.0)
		ring.rotation.y = -angle + PI * 0.5
	# The notice, dropped and trodden in where the neighbours ran, and what
	# was dropped with it: a shoe, a tote, a child's ball.
	var leaflet: StandardMaterial3D = _mat("leaflet", Color("e2dccb"), 0.0, 0.95)
	for index: int in range(24):
		var x: float = -6.5 + fmod(float(index) * 5.37, 13.0)
		var z: float = -39.0 + fmod(float(index) * 3.91, 18.0)
		var sheet: MeshInstance3D = _floor(props, "Leaflet", Vector2(x - 0.11, z - 0.15), Vector2(x + 0.11, z + 0.15), leaflet, 0.013)
		sheet.rotation.y = float(index) * 1.31
	for index: int in range(14):
		var x: float = -30.0 + fmod(float(index) * 4.37, 6.0)
		var z: float = -15.0 + fmod(float(index) * 2.91, 17.0)
		var sheet: MeshInstance3D = _floor(props, "Leaflet", Vector2(x - 0.11, z - 0.15), Vector2(x + 0.11, z + 0.15), leaflet, 0.013)
		sheet.rotation.y = float(index) * 0.87
	_block(props, "DroppedShoe", Vector3(0.12, 0.09, 0.28), _mat("shoe", Color("5a3a26"), 0.0, 0.8), Vector3(-2.6, 0.045, -31.2)).rotation.y = 0.7
	_block(props, "DroppedTote", Vector3(0.42, 0.06, 0.34), _mat("tote", PERSONAL[4], 0.0, 0.95), Vector3(3.1, 0.03, -24.6)).rotation.y = -0.4
	_shape.cylinder(props, "ChildBall", 0.11, 0.2, _mat("ball", Color("c49a3c"), 0.0, 0.6), Vector3(1.4, 0.11, -37.8), 10)
	_finish(room)

# --- the roofs: tar, duckboards, skylights and the stair head -------------------

const ROOFS: Array = [
	[Vector3(-30, 0, -36), Vector3(-7, 4, -20), 2],
	[Vector3(7, 0, -36), Vector3(30, 4, -20), 6],
]

func _build_roofs() -> void:
	var room: Node3D = _room("Roofs")
	var props: Node3D = _props(room)
	var tar: StandardMaterial3D = _tiled("roof_tar", EnvironmentTextures.EARTH + "earth_roof_tar_patches.png", Color("d8cfbf"), 3.0)
	var patch: StandardMaterial3D = _mat("roof_patch", Color("4a4844"), 0.0, 0.95)
	var coping: StandardMaterial3D = _mat("roof_coping", Color("a89c88"), 0.0, 0.85)
	for roof: Array in ROOFS:
		var low: Vector3 = roof[0]
		var high: Vector3 = roof[1]
		var seed_value: int = roof[2]
		_floor(props, "RoofTar", Vector2(low.x + 0.02, low.z + 0.02), Vector2(high.x - 0.02, high.z - 0.02), tar, ROOF + 0.006)
		for index: int in range(7):
			var x: float = low.x + 2.0 + fmod(float(index * 7 + seed_value) * 2.9, high.x - low.x - 4.0)
			var z: float = low.z + 1.5 + fmod(float(index * 3 + seed_value) * 3.7, high.z - low.z - 3.0)
			_floor(props, "TarPatch", Vector2(x - 0.9, z - 0.6), Vector2(x + 0.9, z + 0.6), patch, ROOF + 0.009)
		# The shops under the roofs: one storey of Low Water frontage on every
		# face, over a plaster backing that fills the parapet line.
		var faces: Array = [
			[Vector3(high.x, 0, low.z), Vector3.LEFT, Vector3.FORWARD, high.x - low.x],
			[Vector3(low.x, 0, high.z), Vector3.RIGHT, Vector3.BACK, high.x - low.x],
			[Vector3(low.x, 0, low.z), Vector3.BACK, Vector3.LEFT, high.z - low.z],
			[Vector3(high.x, 0, high.z), Vector3.FORWARD, Vector3.RIGHT, high.z - low.z],
		]
		for index: int in range(faces.size()):
			var face: Array = faces[index]
			var origin: Vector3 = face[0]
			var along: Vector3 = face[1]
			var out: Vector3 = face[2]
			var length: float = face[3]
			var backing: Color = PAINTS[(seed_value + index * 3) % PAINTS.size()].darkened(0.12)
			_sheet(props, "ShopBacking", Vector2(length - 0.02, ROOF - 0.02), _surface("enamel", backing), origin + along * length * 0.5 + Vector3(0, ROOF * 0.5, 0) + out * 0.008, out)
			_facade(props, origin, along, out, length, ROOF, seed_value + index * 4, false)
			_relief(props, "RoofCoping", Vector3(length + 0.1, 0.18, 0.1), coping, origin + along * length * 0.5 + Vector3(0, ROOF - 0.09, 0), out)
		# Skylights over the homes below: flush frames, a few still lit.
		var frame: StandardMaterial3D = _mat("skylight_frame", Color("3b3f3c"), 0.4, 0.6)
		for index: int in range(3):
			var x: float = low.x + 3.5 + float(index) * 7.5
			var z: float = high.z - 3.0 if index % 2 == 0 else low.z + 2.5
			_floor(props, "SkylightFrame", Vector2(x - 0.9, z - 0.6), Vector2(x + 0.9, z + 0.6), frame, ROOF + 0.012)
			var glass: Material = _glow("skylight_lit", Color("d9a466"), 0.45) if (index + seed_value) % 3 == 0 else _mat("glass_dark", Color("2b3634"), 0.2, 0.35)
			_floor(props, "SkylightGlass", Vector2(x - 0.78, z - 0.48), Vector2(x + 0.78, z + 0.48), glass, ROOF + 0.016)
	# Duckboards: the way the neighbours cross, from the stair past the tanks
	# to the plank bridge, and from the bridge along the far roof to the crane.
	for path: Array in [[Vector2(-28.4, -28.4), Vector2(-7.02, -26.6), false], [Vector2(-27.9, -26.6), Vector2(-26.4, -21.2), true], [Vector2(7.02, -28.4), Vector2(27.0, -26.6), false], [Vector2(25.2, -26.6), Vector2(27.0, -20.02), true]]:
		_planks(props, "Duckboards", path[0], path[1], ROOF + 0.014, path[2], 0.3)
	# The stair head from Level 4's roof stair: a small door house with its
	# door open, a lamp over it and belongings set down beside it.
	var head_low: Vector3 = Vector3(-30, 4, -24)
	var head_high: Vector3 = Vector3(-29, 6, -21)
	_wrap(props, "StairHead", head_low, head_high, _surface("enamel", Color("bf9a60")), _mat("stair_head_cap", Color("58625c"), 0.0, 0.9), [Vector3.RIGHT])
	_sheet(props, "StairHeadFace", Vector2(2.99, 1.99), _surface("enamel", Color("bf9a60")), Vector3(-29.0, 5.0, -22.5) + Vector3.RIGHT * 0.005, Vector3.RIGHT)
	_sheet(props, "StairDoorFrame", Vector2(1.1, 1.9), _mat("frame_dark", Color("3b3430"), 0.0, 0.8), Vector3(-29.0, 4.95, -22.5) + Vector3.RIGHT * 0.01, Vector3.RIGHT)
	_sheet(props, "StairDoorway", Vector2(0.9, 1.8), _mat("doorway_dark", Color("171716"), 0.0, 1.0), Vector3(-29.0, 4.9, -22.5) + Vector3.RIGHT * 0.014, Vector3.RIGHT)
	_relief(props, "StairCanopy", Vector3(1.6, 0.08, 0.45), _mat("stair_head_cap", Color("58625c"), 0.0, 0.9), Vector3(-29.0, 5.98, -22.5), Vector3.RIGHT)
	_wall_lamp(props, Vector3(-29.0, 5.75, -21.6), Vector3.RIGHT)
	_omni(room, "StairLamp", Vector3(-28.5, 5.5, -21.6), WARM_LAMP, 1.2, 6.0)
	_suitcase(props, Vector3(-28.75, ROOF, -23.6), Vector3(0.5, 0.62, 0.2), Color("7a3a22"), PI * 0.5)
	_bundle(props, Vector3(-28.78, ROOF, -21.4), Vector3(0.45, 0.4, 0.4), PERSONAL[6], 0.1)
	_pot_plant(props, Vector3(-28.72, ROOF, -24.4), 0.8, 3)
	# A birdcage set down by the duckboards, its door open.
	var wire: StandardMaterial3D = _mat("cage_wire", Color("b39a5e"), 0.6, 0.4)
	var cage: Vector3 = Vector3(-21.0, ROOF + 0.02, -28.75)
	for index: int in range(8):
		var angle: float = TAU * float(index) / 8.0
		if index == 2:
			continue
		_shape.rod(props, "CageWire", cage + Vector3(cos(angle) * 0.14, 0.02, sin(angle) * 0.14), cage + Vector3(cos(angle) * 0.08, 0.42, sin(angle) * 0.08), 0.006, wire, 3)
	_shape.cylinder(props, "CageBase", 0.16, 0.04, _mat("cage_base", Color("6e4e34")), cage + Vector3(0, 0.02, 0), 10).rotation.x = PI * 0.5
	# Dropped on the far roof in the hurry: a scarf and a single glove.
	_block(props, "DroppedScarf", Vector3(0.9, 0.02, 0.22), _mat("scarf", PERSONAL[3], 0.0, 0.95), Vector3(12.0, ROOF + 0.03, -25.6)).rotation.y = 0.35
	_block(props, "DroppedGlove", Vector3(0.12, 0.03, 0.2), _mat("glove", Color("6e4e34"), 0.0, 0.9), Vector3(18.5, ROOF + 0.035, -29.0)).rotation.y = -0.6
	# Washing still out between the stair head and the first tank.
	_washing(props, Vector3(-29.1, 6.3, -21.3), Vector3(-27.6, 6.5, -26.0), 0.18, 5, Vector2(-23.0, -21.0))
	_finish(room)

# --- the water tanks: Level 4's sage tanks on the roof loop ---------------------

func _build_tanks() -> void:
	var room: Node3D = _room("Tanks")
	var props: Node3D = _props(room)
	var sage: StandardMaterial3D = _mat("tank_sage", Color("6e8980"), 0.2, 0.7)
	var band: StandardMaterial3D = _mat("tank_band", Color("a6a18d"), 0.2, 0.6)
	var rib: StandardMaterial3D = _mat("tank_rib", Color("5d746c"), 0.2, 0.7)
	var stand: StandardMaterial3D = _mat("tank_stand", Color("2a2b29"), 0.4, 0.7)
	var iron: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	# The far tank's south face carries its registered six; nothing crosses it.
	for tank: Array in [[Vector3(-28, 4, -29), Vector3(-25, 6.5, -26), Vector3.RIGHT], [Vector3(-16, 4, -34), Vector3(-13, 6.5, -31), Vector3.BACK]]:
		var low: Vector3 = tank[0]
		var high: Vector3 = tank[1]
		var ladder_face: Vector3 = tank[2]
		var centre: Vector3 = (low + high) * 0.5
		var lift: float = 0.55
		# The steel stand, dark under the tank, its legs at the corners.
		_wrap(props, "TankStand", low, Vector3(high.x, low.y + lift, high.z), stand)
		for corner: Vector2 in [Vector2(low.x, low.z), Vector2(high.x, low.z), Vector2(low.x, high.z), Vector2(high.x, high.z)]:
			_block(props, "TankLeg", Vector3(0.2, lift, 0.2), iron, Vector3(corner.x + signf(centre.x - corner.x) * 0.1, low.y + lift * 0.5, corner.y + signf(centre.z - corner.y) * 0.1))
		# The pressed-steel tank in Level 4's sage with its pale bands.
		var body_low: Vector3 = Vector3(low.x, low.y + lift, low.z)
		_wrap(props, "TankBody", body_low, high, sage, _mat("tank_lid", Color("63786f"), 0.2, 0.7))
		for face: Array in [[Vector3.FORWARD, Vector3(centre.x, 0, low.z)], [Vector3.BACK, Vector3(centre.x, 0, high.z)], [Vector3.LEFT, Vector3(low.x, 0, centre.z)], [Vector3.RIGHT, Vector3(high.x, 0, centre.z)]]:
			var out: Vector3 = face[0]
			var base: Vector3 = face[1]
			var side: Vector3 = Vector3.UP.cross(out).normalized()
			if out == ladder_face and out == Vector3.BACK:
				continue
			for fraction: float in [0.15, 0.85]:
				_relief(props, "TankBand", Vector3(3.0, 0.09, 0.03), band, base + Vector3(0, lerpf(body_low.y, high.y, fraction), 0), out)
			for offset: float in [-0.5, 0.5]:
				_relief(props, "TankRib", Vector3(0.05, high.y - body_low.y - 0.1, 0.025), rib, base + side * offset + Vector3(0, (body_low.y + high.y) * 0.5, 0), out)
		# A ladder up the access face, a vent, a hatch and the overflow.
		var ladder_base: Vector3 = Vector3(centre.x, low.y, centre.z) + ladder_face * 1.5 + Vector3.UP.cross(ladder_face).normalized() * 1.1
		for edge: float in [-0.2, 0.2]:
			var rail_at: Vector3 = ladder_base + Vector3.UP.cross(ladder_face).normalized() * edge + ladder_face * 0.12
			_shape.rod(props, "TankLadderRail", rail_at + Vector3(0, 0.1, 0), rail_at + Vector3(0, high.y - low.y + 0.4, 0), 0.02, iron, 4)
		for rung: int in range(8):
			var y: float = 0.35 + float(rung) * 0.3
			var mid: Vector3 = ladder_base + ladder_face * 0.12 + Vector3(0, y, 0)
			_shape.rod(props, "TankLadderRung", mid - Vector3.UP.cross(ladder_face).normalized() * 0.2, mid + Vector3.UP.cross(ladder_face).normalized() * 0.2, 0.014, iron, 4)
		_floor(props, "TankHatch", Vector2(centre.x - 0.4, centre.z - 0.4), Vector2(centre.x + 0.4, centre.z + 0.4), iron, high.y + 0.01)
		_shape.rod(props, "TankVent", Vector3(centre.x + 0.9, high.y, centre.z - 0.8), Vector3(centre.x + 0.9, high.y + 0.5, centre.z - 0.8), 0.06, iron, 6)
		_shape.lathe(props, "VentCap", PackedVector2Array([Vector2(0.0, 0.08), Vector2(0.14, 0.0)]), iron, Vector3(centre.x + 0.9, high.y + 0.56, centre.z - 0.8), 8).rotation.x = -PI * 0.5
		var overflow: Vector3 = Vector3(centre.x, 0, centre.z) - ladder_face * 1.5 - Vector3.UP.cross(ladder_face).normalized() * 0.9
		_shape.rod(props, "TankOverflow", overflow - ladder_face * 0.08 + Vector3(0, high.y - 0.3, 0), overflow - ladder_face * 0.08 + Vector3(0, low.y + 0.1, 0), 0.04, _mat("drainpipe", Color("4f5a55"), 0.3, 0.6), 6)
	# A television aerial on the far tank: the skyline that comes back later.
	var mast: Vector3 = Vector3(-14.0, 6.5, -33.2)
	_shape.rod(props, "AerialMast", mast, mast + Vector3(0, 1.8, 0), 0.025, iron, 4)
	for index: int in range(4):
		var y: float = 1.1 + float(index) * 0.22
		var span: float = 0.9 - float(index) * 0.14
		_shape.rod(props, "AerialArm", mast + Vector3(-span * 0.5, y, 0), mast + Vector3(span * 0.5, y, 0), 0.012, iron, 3)
	_finish(room)

# --- the plank bridge over the sweep's street ----------------------------------

func _build_bridge() -> void:
	var room: Node3D = _room("Bridge")
	var props: Node3D = _props(room)
	var planks: StandardMaterial3D = _mat("timber_8a6a4a", Color("8a6a4a"), 0.0, 0.9)
	var iron: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	_planks(props, "BridgePlanks", Vector2(-7.0, -28.98), Vector2(7.0, -26.02), ROOF + 0.004, false, 0.32)
	for out: Vector3 in [Vector3.FORWARD, Vector3.BACK]:
		var z: float = -29.0 if out == Vector3.FORWARD else -26.0
		_sheet(props, "BridgeEdge", Vector2(13.98, 0.24), planks, Vector3(0, 3.875, z) + out * 0.005, out)
		# A steel channel under each edge, bolted to the roofs' copings.
		_block(props, "BridgeChannel", Vector3(14.6, 0.18, 0.14), iron, Vector3(0, 3.66, z - out.z * 0.12))
	var underside: MeshInstance3D = _floor(props, "BridgeUnderside", Vector2(-7.0, -28.98), Vector2(7.0, -26.02), planks, 3.745)
	underside.rotation.x = PI
	for x: float in [-4.5, -1.5, 1.5, 4.5]:
		_block(props, "BridgeCrossTie", Vector3(0.12, 0.14, 2.9), iron, Vector3(x, 3.68, -27.5))
	# Rope lashings where the planks were tied on in a hurry this morning.
	var rope: StandardMaterial3D = _mat("rope", Color("b39a6a"), 0.0, 0.9)
	for x: float in [-6.6, 6.6]:
		for z: float in [-28.9, -26.1]:
			_shape.cylinder(props, "Lashing", 0.07, 0.3, rope, Vector3(x, 3.86, z), 6)
	_finish(room)

# --- Level 4's gantry crane, now underfoot -----------------------------------

func _build_crane() -> void:
	var room: Node3D = _room("Crane")
	var props: Node3D = _props(room)
	var ochre: StandardMaterial3D = _mat("gantry_ochre", Color("b0843e"), 0.4, 0.6)
	var dark: StandardMaterial3D = _mat("gantry_dark", Color("5a4426"), 0.4, 0.6)
	var iron: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	_wrap(props, "GantryPost", Vector3(19, 0, -16), Vector3(20, 7, -15), ochre, ochre)
	_wrap(props, "GantryPost", Vector3(29, 0, -16), Vector3(30, 7, -15), ochre, ochre)
	_wrap(props, "GantryBeam", Vector3(19, 6.5, -16), Vector3(30, 7, -15), ochre, ochre)
	var under: MeshInstance3D = _floor(props, "GantryBeamUnder", Vector2(19.0, -16.0), Vector2(30.0, -15.0), ochre, 6.495)
	under.rotation.x = PI
	for x: float in [19.5, 29.5]:
		for y: float in [0.6, 3.5, 6.0]:
			for out: Vector3 in [Vector3.FORWARD, Vector3.BACK]:
				_relief(props, "PostBand", Vector3(1.0, 0.1, 0.02), dark, Vector3(x, y, -15.5 + out.z * 0.5), out)
	# The trolley and its hook over the crane walk, hung clear above the treads.
	_block(props, "Trolley", Vector3(0.9, 0.4, 1.3), iron, Vector3(26.0, 6.3, -15.5))
	_shape.rod(props, "HoistChain", Vector3(26.0, 6.1, -15.5), Vector3(26.0, 5.75, -15.5), 0.03, iron, 4)
	_shape.lathe(props, "Hook", PackedVector2Array([Vector2(0.0, 0.1), Vector2(0.18, 0.06), Vector2(0.18, 0.0)]), iron, Vector3(26.0, 5.68, -15.5), 8).rotation.x = PI * 0.5
	# The walk's treads: checker plate with worn ochre nosings.
	var tread: StandardMaterial3D = _tiled("tread", EnvironmentTextures.EARTH + "earth_service_dark_tread.png", Color("9a9a90"), 1.0)
	var nosing: StandardMaterial3D = _mat("tread_nosing", Color("b0843e"), 0.0, 0.8)
	for step: int in range(7):
		var z0: float = -20.0 + float(step) * 2.0
		var top: float = 3.5 - float(step) * 0.5
		_floor(props, "CraneTread", Vector2(24.02, z0 + 0.02), Vector2(27.98, z0 + 1.98), tread, top + 0.006)
		_floor(props, "CraneNosing", Vector2(24.02, z0 + 1.88), Vector2(27.98, z0 + 1.98), nosing, top + 0.01)
		for out: Vector3 in [Vector3.LEFT, Vector3.RIGHT]:
			var x: float = 24.0 if out == Vector3.LEFT else 28.0
			_sheet(props, "CraneStepSide", Vector2(1.99, top - 0.01), _mat("crane_side", Color("5f5c55"), 0.3, 0.6), Vector3(x, top * 0.5, z0 + 1.0) + out * 0.005, out)
		_sheet(props, "CraneRiser", Vector2(3.98, 0.49), _mat("crane_side", Color("5f5c55"), 0.3, 0.6), Vector3(26.0, top + 0.25, z0 + 2.0) + Vector3.BACK * 0.005, Vector3.BACK)
	_finish(room)

# --- the tram workshop ----------------------------------------------------------

func _build_workshop_shell() -> void:
	var room: Node3D = _room("Workshop")
	var props: Node3D = _props(room)
	var cladding: StandardMaterial3D = _tiled("shed_cladding", EnvironmentTextures.PRODUCTION + "low_water_steel.png", Color("c4ccbc"), 1.5)
	var inside: StandardMaterial3D = _tiled("shed_inside", EnvironmentTextures.PRODUCTION + "low_water_steel.png", Color("e0d6c0"), 1.5)
	var rib: StandardMaterial3D = _mat("cladding_rib", Color("6c7468"), 0.3, 0.6)
	var cap: StandardMaterial3D = _mat("wall_cap", Color("4a5a5e"), 0.3, 0.6)
	# [face centre at ground, out, length, finish]
	var walls: Array = [
		[Vector3(-23.0, 0, -6.0), Vector3.LEFT, 20.0, cladding], [Vector3(-22.5, 0, -5.75), Vector3.RIGHT, 19.5, inside],
		[Vector3(-2.5, 0, -16.0), Vector3.FORWARD, 41.0, cladding], [Vector3(-2.5, 0, -15.5), Vector3.BACK, 40.0, inside],
		[Vector3(18.0, 0, -12.0), Vector3.RIGHT, 8.0, cladding], [Vector3(17.5, 0, -11.75), Vector3.LEFT, 7.5, inside],
		[Vector3(18.0, 0, 1.0), Vector3.RIGHT, 6.0, cladding], [Vector3(17.5, 0, 1.0), Vector3.LEFT, 6.0, inside],
	]
	for wall: Array in walls:
		var at: Vector3 = wall[0]
		var out: Vector3 = wall[1]
		var length: float = wall[2]
		var side: Vector3 = Vector3.UP.cross(out).normalized()
		_sheet(props, "Cladding", Vector2(length - 0.02, 3.98), wall[3], at + Vector3(0, 2.0, 0) + out * 0.004, out)
		if wall[3] == cladding:
			for index: int in range(int(length / 0.5)):
				_relief(props, "CladdingRib", Vector3(0.05, 3.6, 0.025), rib, at + side * (-length * 0.5 + 0.25 + float(index) * 0.5) + Vector3(0, 1.9, 0), out)
		else:
			# A tidemark of grime at the foot and patched sheets above it.
			_sheet(props, "Grime", Vector2(length - 0.02, 0.5), _mat("shed_grime", Color("8a8270"), 0.0, 0.95), at + Vector3(0, 0.25, 0) + out * 0.006, out)
	# Wall caps along every top and the end posts of each run.
	for cap_run: Array in [[Vector3(-22.75, 4.04, -6.0), Vector3(0.6, 0.08, 20.0)], [Vector3(-2.5, 4.04, -15.75), Vector3(41.0, 0.08, 0.6)], [Vector3(17.75, 4.04, -12.0), Vector3(0.6, 0.08, 8.0)], [Vector3(17.75, 4.04, 1.0), Vector3(0.6, 0.08, 6.0)]]:
		_block(props, "WallCap", cap_run[1], cap, cap_run[0])
	for end: Array in [[Vector3(-22.75, 2.0, 4.0), Vector3.BACK], [Vector3(17.75, 2.0, 4.0), Vector3.BACK], [Vector3(17.75, 2.0, -8.0), Vector3.BACK], [Vector3(17.75, 2.0, -2.0), Vector3.FORWARD]]:
		_sheet(props, "WallEnd", Vector2(0.49, 3.99), cap, (end[0] as Vector3) + (end[1] as Vector3) * 0.005, end[1])
	# Inside the south wall: shelves of tins and parts, the colour tins from
	# the vote, wheels leaning, a hose and tool boards.
	var shelf: StandardMaterial3D = _mat("work_shelf", Color("6e4e34"), 0.0, 0.85)
	for run: Vector2 in [Vector2(-20.0, -13.0), Vector2(-4.0, 1.0)]:
		var mid: float = (run.x + run.y) * 0.5
		for y: float in [1.1, 1.8]:
			_relief(props, "WorkShelf", Vector3(run.y - run.x, 0.05, 0.38), shelf, Vector3(mid, y, -15.5), Vector3.BACK)
			for index: int in range(int((run.y - run.x) / 0.6)):
				var x: float = run.x + 0.3 + float(index) * 0.6
				var tint: Color = [Color("6f8a4e"), Color("4f6f8a"), Color("a64a3a"), Color("8e8f8a"), Color("c49a3c")][(index + int(y * 10.0)) % 5]
				if (index + int(y)) % 4 == 3:
					continue
				_shape.cylinder(props, "ShelfTin", 0.1, 0.2 + float(index % 2) * 0.06, _mat("swatch_tin_%s" % tint.to_html(false), tint, 0.3, 0.5), Vector3(x, y + 0.13, -15.3), 8).rotation.x = PI * 0.5
	var tool: StandardMaterial3D = _mat("tool_steel", Color("5a5f5c"), 0.6, 0.45)
	for board: Vector3 in [Vector3(6.0, 2.0, -15.5), Vector3(15.0, 2.0, -15.5)]:
		_sheet(props, "ToolBoard", Vector2(3.0, 1.3), _boards(Color("8f7a62")), board + Vector3.BACK * 0.012, Vector3.BACK)
		for index: int in range(8):
			_relief(props, "BoardTool", Vector3(0.05, 0.3 + float(index % 3) * 0.12, 0.03), tool, board + Vector3(-1.2 + float(index) * 0.34, 0.05, 0), Vector3.BACK)
	var wheel: StandardMaterial3D = _mat("tram_wheel", Color("3d3b37"), 0.7, 0.4)
	for x: float in [-11.6, -10.6, 9.0]:
		_shape.cylinder(props, "LeaningWheel", 0.45, 0.14, wheel, Vector3(x, 0.45, -15.3), 16)
	_shape.cylinder(props, "HoseCoil", 0.32, 0.1, _mat("hose", Color("3a4a3a"), 0.0, 0.7), Vector3(-22.35, 0.9, -4.0), 14).rotation.y = PI * 0.5
	# Splice's corner on the west wall: their patched coat on a hook, a radio
	# and a mug on the sill, the muted magenta of their wrist band.
	_relief(props, "SpliceCoat", Vector3(0.55, 0.95, 0.06), _mat("splice_coat", Color("6e5a4a"), 0.0, 0.95), Vector3(-22.5, 1.65, -9.0), Vector3.RIGHT)
	_relief(props, "SplicePatch", Vector3(0.2, 0.2, 0.065), _mat("splice_magenta", Color("8a3a58"), 0.0, 0.9), Vector3(-22.5, 1.8, -8.9), Vector3.RIGHT)
	_relief(props, "SpliceSill", Vector3(1.4, 0.05, 0.3), shelf, Vector3(-22.5, 1.3, -11.0), Vector3.RIGHT)
	_block(props, "SpliceRadio", Vector3(0.22, 0.2, 0.38), _mat("radio_0", Color("6e4e34"), 0.2, 0.6), Vector3(-22.32, 1.43, -11.3))
	_shape.cylinder(props, "SpliceMug", 0.05, 0.1, _mat("splice_magenta", Color("8a3a58"), 0.0, 0.9), Vector3(-22.32, 1.38, -10.6), 8).rotation.x = PI * 0.5
	# Span wires for the tram's overhead line, crossing the open shed.
	var wire: StandardMaterial3D = _mat("cable", Color("232526"), 0.0, 0.7)
	for z: float in [-12.0, -4.0, 2.0]:
		_shape.rod(props, "SpanWire", Vector3(-22.5, 3.95, z), Vector3(17.5, 3.95, z), 0.012, wire, 3)
	_shape.rod(props, "ContactWire", Vector3(0.0, 3.85, -15.5), Vector3(0.0, 3.85, 3.98), 0.015, wire, 3)
	# Work lamps on the inside walls.
	for lamp: Array in [[Vector3(-14.0, 3.3, -15.5), Vector3.BACK], [Vector3(2.0, 3.3, -15.5), Vector3.BACK], [Vector3(-22.5, 3.3, 1.0), Vector3.RIGHT], [Vector3(17.5, 3.3, -11.0), Vector3.LEFT]]:
		_service_lamp(room, props, lamp[0], lamp[1], 1.5, 8.0)
	_finish(room)

func _build_paint_bay() -> void:
	var room: Node3D = _room("PaintBay")
	var props: Node3D = _props(room)
	# The bench: boards, drips of the three vote colours and the tins at its
	# ends, its middle left clear where the Grenades lie.
	var bench_low: Vector3 = Vector3(10, 0, -14)
	var bench_high: Vector3 = Vector3(14, 0.9, -11)
	_plank_faces(props, "PaintBench", bench_low, bench_high, Color("a88660"))
	_planks(props, "PaintBenchTop", Vector2(10.0, -14.0), Vector2(14.0, -11.0), 0.9, true, 0.3)
	var swatches: Array[Color] = [Color("6f8a4e"), Color("4f6f8a"), Color("a64a3a")]
	for index: int in range(7):
		var drip: Color = swatches[index % 3]
		_sheet(props, "BenchDrip", Vector2(0.06, 0.2 + float(index % 3) * 0.12), _mat("tram_green" if index % 3 == 0 else "swatch_%d" % (index % 3), drip, 0.0, 0.6), Vector3(10.4 + float(index) * 0.5, 0.75 - float(index % 3) * 0.06, -11.0) + Vector3.BACK * 0.008, Vector3.BACK)
	for spot: Vector3 in [Vector3(10.35, 0.9, -13.6), Vector3(10.75, 0.9, -13.65), Vector3(13.6, 0.9, -13.55), Vector3(13.65, 0.9, -11.4)]:
		var tint: Color = swatches[int(spot.x + spot.z) % 3]
		_shape.cylinder(props, "PaintTin", 0.11, 0.2, _mat("swatch_tin_%s" % tint.to_html(false), tint, 0.3, 0.5), spot + Vector3(0, 0.1, 0), 10).rotation.x = PI * 0.5
	_shape.cylinder(props, "BrushJar", 0.07, 0.16, _mat("jar", Color("8e8f8a"), 0.5, 0.3), Vector3(10.4, 0.98, -11.4), 8).rotation.x = PI * 0.5
	for index: int in range(3):
		_shape.rod(props, "Brush", Vector3(10.4, 1.0, -11.4), Vector3(10.4 + float(index - 1) * 0.05, 1.28, -11.4 + float(index % 2) * 0.04), 0.012, _mat("brush_handle", Color("6e4e34")), 4)
	_floor(props, "Rag", Vector2(13.2, -12.9), Vector2(13.8, -12.4), _mat("rag", Color("b39a6a"), 0.0, 0.95), 0.905).rotation.y = 0.3
	# The step up: a pallet, slats and dark gaps.
	_plank_faces(props, "PaintStep", Vector3(10, 0, -11), Vector3(14, 0.5, -9), Color("9c7a56"))
	_planks(props, "PaintStepTop", Vector2(10.0, -11.0), Vector2(14.0, -9.0), 0.5, true, 0.36)
	# The stripped tram over the siding: the same old terracotta and cream as
	# Level 4's tram, and the green the neighbours voted for, half on.
	var cream: StandardMaterial3D = _mat("tram_cream", Color("d2c19a"), 0.1, 0.6)
	var terracotta: StandardMaterial3D = _mat("tram_terracotta", Color("9a5038"), 0.1, 0.6)
	var skirt: StandardMaterial3D = _mat("tram_skirt", Color("33302c"), 0.3, 0.6)
	var green: StandardMaterial3D = _mat("tram_green", Color("6f8a4e"), 0.0, 0.6)
	var dark: StandardMaterial3D = _mat("doorway_dark", Color("171716"), 0.0, 1.0)
	var masking: StandardMaterial3D = _mat("masking_paper", Color("cdbf9c"), 0.0, 0.95)
	var low: Vector3 = Vector3(3, 0, -13)
	var high: Vector3 = Vector3(7, 2.5, -7)
	for face: Array in [[Vector3.LEFT, 6.0, Vector3(3, 0, -10)], [Vector3.RIGHT, 6.0, Vector3(7, 0, -10)], [Vector3.FORWARD, 4.0, Vector3(5, 0, -13)], [Vector3.BACK, 4.0, Vector3(5, 0, -7)]]:
		var out: Vector3 = face[0]
		var span: float = face[1]
		var base: Vector3 = face[2]
		var side: Vector3 = Vector3.UP.cross(out).normalized()
		_sheet(props, "ChassisCream", Vector2(span - 0.02, 1.25), cream, base + Vector3(0, 1.87, 0) + out * 0.004, out)
		_sheet(props, "ChassisLower", Vector2(span - 0.02, 0.95), terracotta, base + Vector3(0, 0.77, 0) + out * 0.004, out)
		_sheet(props, "ChassisSkirt", Vector2(span - 0.02, 0.3), skirt, base + Vector3(0, 0.15, 0) + out * 0.005, out)
		if span > 5.0:
			for index: int in range(4):
				_sheet(props, "ChassisWindow", Vector2(0.95, 0.75), dark, base + side * (-2.1 + float(index) * 1.4) + Vector3(0, 1.85, 0) + out * 0.006, out)
			for edge: float in [-2.2, 2.2]:
				_shape.cylinder(props, "Bogie", 0.32, 0.08, _mat("tram_wheel", Color("3d3b37"), 0.7, 0.4), base + side * edge + Vector3(0, 0.32, 0) + out * 0.05, 14).basis = Basis(Quaternion(Vector3.BACK, out))
		else:
			_sheet(props, "ChassisWindscreen", Vector2(3.2, 0.8), dark, base + Vector3(0, 1.85, 0) + out * 0.006, out)
			for edge: float in [-1.5, 1.5]:
				_sheet(props, "ChassisLamp", Vector2(0.28, 0.2), _mat("lamp_out", Color("8a826a"), 0.2, 0.5), base + side * edge + Vector3(0, 0.75, 0) + out * 0.007, out)
	# The voted green is on the east flank already; masking paper above it.
	_sheet(props, "FreshGreen", Vector2(3.6, 0.93), green, Vector3(7, 0.77, -11.0) + Vector3.RIGHT * 0.007, Vector3.RIGHT)
	_sheet(props, "Masking", Vector2(3.6, 0.12), masking, Vector3(7, 1.3, -11.0) + Vector3.RIGHT * 0.008, Vector3.RIGHT)
	_sheet(props, "FreshGreen", Vector2(1.6, 0.93), green, Vector3(5.8, 0.77, -7) + Vector3.BACK * 0.007, Vector3.BACK)
	_floor(props, "ChassisRoof", Vector2(low.x + 0.01, low.z + 0.01), Vector2(high.x - 0.01, high.z - 0.01), _mat("tram_roof", Color("6a6a62"), 0.3, 0.6), high.y + 0.004)
	_bundle(props, Vector3(4.2, high.y, -11.5), Vector3(1.1, 0.25, 0.7), Color("6f7d76"), 0.1)
	_wall_lamp(props, Vector3(12.0, 3.3, -15.5), Vector3.BACK)
	_omni(room, "PaintBayLamp", Vector3(12.0, 3.0, -14.9), WARM_LAMP, 1.6, 7.5)
	_finish(room)

## The Union's loading pen: issued black steel, a restrained red seal band
## and mesh, the one Union object on the workshop floor.
func _build_pen() -> void:
	var room: Node3D = _room("LoadingPen")
	var props: Node3D = _props(room)
	var black: StandardMaterial3D = _mat("union_black", Color("1e1e22"), 0.3, 0.55)
	var shell_mat: StandardMaterial3D = _mat("union_case", Color("2c2d32"), 0.4, 0.5)
	var red: StandardMaterial3D = _mat("union_red", Color("8c1a1e"), 0.2, 0.7)
	var mesh_bar: StandardMaterial3D = _mat("pen_mesh", Color("3a3b40"), 0.5, 0.5)
	for cap: Array in [[Vector3(-21.5, 0, -1), Vector3(-13, 2.8, -0.5)], [Vector3(-21.5, 0, 3.5), Vector3(-13, 2.8, 4)]]:
		var low: Vector3 = cap[0]
		var high: Vector3 = cap[1]
		_wrap(props, "PenPanel", low, high, shell_mat)
		for out: Vector3 in [Vector3.FORWARD, Vector3.BACK]:
			var z: float = low.z if out == Vector3.FORWARD else high.z
			for index: int in range(17):
				_relief(props, "PenBar", Vector3(0.05, 2.7, 0.03), mesh_bar, Vector3(-21.25 + float(index) * 0.5, 1.4, z), out)
			_relief(props, "PenRail", Vector3(8.5, 0.12, 0.05), black, Vector3(-17.25, 2.6, z), out)
			_relief(props, "PenRail", Vector3(8.5, 0.12, 0.05), black, Vector3(-17.25, 0.15, z), out)
			_relief(props, "PenSealBand", Vector3(8.5, 0.08, 0.055), red, Vector3(-17.25, 2.3, z), out)
			_sheet(props, "PenSeal", Vector2(0.4, 0.4), _seal_material(), Vector3(-14.0, 1.6, z) + out * 0.06, out)
		_sheet(props, "PenEnd", Vector2(0.49, 2.79), black, Vector3(-13.0, 1.4, (low.z + high.z) * 0.5) + Vector3.RIGHT * 0.006, Vector3.RIGHT)
	_wrap(props, "PenBack", Vector3(-21.5, 0, -1), Vector3(-21, 2.8, 4), shell_mat, null, [Vector3.RIGHT])
	_wrap(props, "PenRoof", Vector3(-21.5, 2.8, -1), Vector3(-13, 3.05, 4), black, shell_mat)
	var under: MeshInstance3D = _floor(props, "PenCeiling", Vector2(-21.5, -1.0), Vector2(-13.0, 4.0), black, 2.795)
	under.rotation.x = PI
	_relief(props, "PenRoofBand", Vector3(5.0, 0.08, 0.02), red, Vector3(-13.0, 2.92, 1.5), Vector3.RIGHT)
	_floor(props, "PenMat", Vector2(-21.0, -0.5), Vector2(-13.0, 3.5), _mat("pen_mat", Color("2a2a2c"), 0.0, 0.95), 0.012)
	for index: int in range(4):
		_floor(props, "PenFootprint", Vector2(-19.5 + float(index) * 1.6, 0.4), Vector2(-19.2 + float(index) * 1.6, 2.6), _mat("pen_line", Color("4a4a4c"), 0.0, 0.95), 0.014)
	_finish(room)

func _build_service_bay() -> void:
	var room: Node3D = _room("ServiceBay")
	var props: Node3D = _props(room)
	# The bay host: steel lockers and a parts board facing the pit.
	var locker: StandardMaterial3D = _mat("locker_steel", Color("5f7277"), 0.4, 0.5)
	# Its pit face keeps the registered six clear: vents above, kick plate below.
	_wrap(props, "BayLockers", Vector3(-10, 0, -14.5), Vector3(-6, 2.5, -13.5), locker, _mat("locker_top", Color("4a5a5e"), 0.4, 0.5), [Vector3.BACK])
	for index: int in range(5):
		var x: float = -9.6 + float(index) * 0.8
		_relief(props, "LockerVent", Vector3(0.4, 0.2, 0.015), _mat("locker_seam", Color("3d4a4e"), 0.4, 0.5), Vector3(x, 2.15, -13.5), Vector3.BACK)
		_relief(props, "LockerHandle", Vector3(0.16, 0.04, 0.04), _mat("brass", Color("9a7d3e"), 0.6, 0.4), Vector3(x + 0.2, 1.95, -13.5), Vector3.BACK)
	_relief(props, "KickPlate", Vector3(4.0, 0.3, 0.015), _mat("locker_seam", Color("3d4a4e"), 0.4, 0.5), Vector3(-8.0, 0.15, -13.5), Vector3.BACK)
	# The service cover: Splice's rolling tool chest in their own colours.
	var chest: StandardMaterial3D = _mat("tool_chest", Color("4f6f8a"), 0.4, 0.5)
	_wrap(props, "ToolChest", Vector3(-9, 0, -10), Vector3(-6, 1.2, -8), chest, _mat("chest_top", Color("3a3d3c"), 0.3, 0.7))
	for out: Vector3 in [Vector3.FORWARD, Vector3.BACK]:
		var z: float = -10.0 if out == Vector3.FORWARD else -8.0
		for row: int in range(4):
			_relief(props, "ChestDrawer", Vector3(2.8, 0.02, 0.02), _mat("chest_seam", Color("2c3d4c"), 0.4, 0.5), Vector3(-7.5, 0.3 + float(row) * 0.25, z), out)
			_relief(props, "ChestHandle", Vector3(0.5, 0.03, 0.04), _mat("tool_steel", Color("5a5f5c"), 0.6, 0.45), Vector3(-7.5, 0.4 + float(row) * 0.25, z), out)
		_relief(props, "ChestSticker", Vector3(0.22, 0.22, 0.01), _mat("splice_magenta", Color("8a3a58"), 0.0, 0.9), Vector3(-6.6, 1.0, z), out)
	_shape.cylinder(props, "Spanner", 0.02, 0.4, _mat("tool_steel", Color("5a5f5c"), 0.6, 0.45), Vector3(-8.2, 1.22, -9.0), 4).rotation.y = 0.6
	_block(props, "PartsTray", Vector3(0.5, 0.06, 0.35), _mat("tray", Color("6a6a62"), 0.4, 0.5), Vector3(-6.7, 1.23, -8.6))
	_finish(room)

# --- the market strip below the roofs -------------------------------------------

func _build_market_strip() -> void:
	var room: Node3D = _room("MarketStrip")
	var props: Node3D = _props(room)
	# The awning: Level 4's striped canvas over a timber post wall.
	var stripes: Array[Color] = [Color("c49a3c"), Color("8fa595"), Color("d8c8a0")]
	for index: int in range(7):
		var x0: float = -32.0 + float(index)
		_floor(props, "AwningStripe", Vector2(x0 + 0.005, -17.995), Vector2(x0 + 0.995, -12.005), _mat("awning_%d" % (index % 3), stripes[index % 3], 0.0, 0.95), 2.754)
		var under: MeshInstance3D = _floor(props, "AwningUnder", Vector2(x0 + 0.005, -17.995), Vector2(x0 + 0.995, -12.005), _mat("awning_%d" % (index % 3), stripes[index % 3].darkened(0.25), 0.0, 0.95), 2.496)
		under.rotation.x = PI
	for out: Vector3 in [Vector3.FORWARD, Vector3.BACK]:
		var z: float = -18.0 if out == Vector3.FORWARD else -12.0
		_sheet(props, "AwningEdge", Vector2(6.98, 0.24), _mat("awning_0", stripes[0], 0.0, 0.95), Vector3(-28.5, 2.625, z) + out * 0.005, out)
	for index: int in range(12):
		var z: float = -17.75 + float(index) * 0.5
		_block(props, "Valance", Vector3(0.02, 0.26, 0.48), _mat("awning_%d" % (index % 3), stripes[index % 3], 0.0, 0.95), Vector3(-24.98, 2.37, z))
	_plank_faces(props, "AwningPost", Vector3(-32, 0, -18), Vector3(-31, 3, -12), Color("8a6a4a"), [Vector3.RIGHT])
	# The three stalls half packed into their own crates.
	var trades: Array[String] = ["greens", "radios", "cloth"]
	for index: int in range(3):
		var z0: float = [-10.0, -5.0, 0.0][index]
		var low: Vector3 = Vector3(-31, 0, z0)
		var high: Vector3 = Vector3(-28, 0.9, z0 + 2.0)
		_plank_faces(props, "StallBench", low, high, Color("a88660"))
		var cloth: Color = [Color("6f8a4e"), Color("4f6f8a"), Color("8a3a58")][index]
		_floor(props, "StallCloth", Vector2(low.x + 0.05, low.z + 0.05), Vector2(high.x - 0.05, high.z - 0.05), _mat("bench_cloth_%s" % trades[index], cloth, 0.0, 0.95), high.y + 0.004)
		_sheet(props, "StallDrop", Vector2(1.9, 0.3), _mat("bench_cloth_%s" % trades[index], cloth, 0.0, 0.95), Vector3(-28.0, high.y - 0.15, z0 + 1.0) + Vector3.RIGHT * 0.01, Vector3.RIGHT)
		_crate(props, Vector3(-30.3, high.y, z0 + 0.6), Vector3(0.6, 0.35, 0.45), Color("9a7a52"), 0.1 * float(index))
		_crate(props, Vector3(-29.4, high.y, z0 + 1.4), Vector3(0.55, 0.3, 0.45), Color("8d6c43"), -0.1)
		match trades[index]:
			"greens":
				_block(props, "Greens", Vector3(0.48, 0.1, 0.36), _mat("greens_0", Color("5e7a44"), 0.0, 0.9), Vector3(-30.3, high.y + 0.4, z0 + 0.6))
			"radios":
				_block(props, "Radio", Vector3(0.42, 0.26, 0.2), _mat("radio_1", Color("7d6c5a"), 0.2, 0.6), Vector3(-28.6, high.y + 0.13, z0 + 0.5))
			"cloth":
				_bundle(props, Vector3(-28.7, high.y, z0 + 0.5), Vector3(0.6, 0.35, 0.4), Color("bcae8e"), 0.2)
	# Festoon lights from the workshop wall top out over the strip.
	for z: float in [-7.0, -2.0]:
		_festoon(props, Vector3(-23.0, 3.95, z), Vector3(-39.3, 4.4, z + 1.0), 0.45, 9)
	_hanging_lamp(room, Vector3(-28.5, 2.35, -15.0), 2.5, 1.4, 6.5)
	# Belongings left against the workshop's outer wall, in its clearance.
	_suitcase(props, Vector3(-23.25, 0.0, -13.5), Vector3(0.6, 0.7, 0.24), Color("6f8a4e"), PI * 0.5)
	_crate(props, Vector3(-23.3, 0.0, -11.6), Vector3(0.7, 0.55, 0.4), Color("8d6c43"), PI * 0.5)
	_bundle(props, Vector3(-23.3, 0.55, -11.6), Vector3(0.45, 0.35, 0.35), PERSONAL[0], PI * 0.5)
	_bicycle(props, Vector3(-23.22, 0.0, -6.5), Vector3.BACK, PERSONAL[2])
	_finish(room)

# --- the trench: covers, the dock, the footbridge, wires and recesses -----------

func _build_trench() -> void:
	var room: Node3D = _room("Trench")
	var props: Node3D = _props(room)
	# The four trench covers are stacks of old sleepers waiting to be laid.
	for cover: Array in [[Vector3(-10, 0, 9), Vector3(-7, 1.2, 12)], [Vector3(7, 0, 12), Vector3(10, 1.2, 15)], [Vector3(-10, 0, 21), Vector3(-7, 1.2, 24)], [Vector3(7, 0, 24), Vector3(10, 1.2, 27)]]:
		_sleeper_stack(props, cover[0], cover[1])
	# The tram dock: a checker-plate boarding step with an ochre edge.
	var tread: StandardMaterial3D = _tiled("tread", EnvironmentTextures.EARTH + "earth_service_dark_tread.png", Color("9a9a90"), 1.0)
	_wrap(props, "DockStep", Vector3(2.6, 0, 4.5), Vector3(4.6, 0.5, 7.5), _mat("dock_side", Color("4a4f4d"), 0.4, 0.6), tread)
	_floor(props, "DockEdge", Vector2(2.62, 4.52), Vector2(2.78, 7.48), _mat("road_paint", Color("c9a23c"), 0.0, 0.9), 0.51)
	# The footbridge over the cut: checker plate, a lattice girder under each
	# edge and lamps at its middle.
	var steel: StandardMaterial3D = _mat("bridge_steel", Color("4a5a5e"), 0.4, 0.55)
	var iron: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	_wrap(props, "FootBridge", Vector3(-13, 4.5, 18), Vector3(13, 4.75, 20), steel, tread)
	var deck_under: MeshInstance3D = _floor(props, "FootBridgeUnder", Vector2(-13.0, 18.0), Vector2(13.0, 20.0), steel, 4.495)
	deck_under.rotation.x = PI
	# Plate girders in the crane's ochre under each edge, stiffened, with end
	# plates where the bridge meets the old abutment line.
	var ochre: StandardMaterial3D = _mat("gantry_ochre", Color("b0843e"), 0.4, 0.6)
	var dark: StandardMaterial3D = _mat("gantry_dark", Color("5a4426"), 0.4, 0.6)
	for z: float in [17.94, 20.06]:
		_block(props, "PlateGirder", Vector3(26.0, 0.75, 0.12), ochre, Vector3(0, 4.375, z))
		_block(props, "GirderFlange", Vector3(26.0, 0.06, 0.3), dark, Vector3(0, 4.0, z))
		for index: int in range(14):
			var x: float = -12.5 + float(index) * 1.923
			_block(props, "Stiffener", Vector3(0.06, 0.7, 0.2), dark, Vector3(x, 4.36, z + (0.1 if z > 19.0 else -0.1)))
	for x: float in [-13.02, 13.02]:
		_block(props, "GirderEnd", Vector3(0.04, 0.8, 2.3), dark, Vector3(x, 4.4, 19.0))
	for x: float in [-9.0, -3.0, 3.0, 9.0]:
		_block(props, "CrossBeam", Vector3(0.12, 0.12, 2.0), iron, Vector3(x, 4.42, 19.0))
	# The overhead line down the cut, held by span wires from the homes.
	var wire: StandardMaterial3D = _mat("cable", Color("232526"), 0.0, 0.7)
	_shape.rod(props, "ContactWire", Vector3(0.0, 3.85, 3.98), Vector3(0.0, 3.5, 33.4), 0.015, wire, 3)
	for z: float in [8.0, 15.0, 24.0, 31.0]:
		var drop: float = 3.85 - (z - 4.0) / 29.4 * 0.35
		_shape.rod(props, "SpanWire", Vector3(-39.3, 6.2, z), Vector3(0.0, drop + 0.05, z), 0.012, wire, 3)
		_shape.rod(props, "SpanWire", Vector3(0.0, drop + 0.05, z), Vector3(39.3, 6.2, z), 0.012, wire, 3)
		_shape.cylinder(props, "Insulator", 0.05, 0.12, _mat("insulator", Color("8a5a3a"), 0.0, 0.4), Vector3(-12.0, drop + 0.05 + (6.2 - drop) * 12.0 / 39.3, z), 6)
	# A lamp under the footbridge's middle, over the crossing below.
	_omni(room, "BridgeLamp", Vector3(0.0, 4.2, 19.0), WARM_LAMP, 1.3, 7.0)
	_shape.cylinder(props, "BridgeLampGlobe", 0.09, 0.14, _glow("wall_bulb", Color("ffd394"), 2.2), Vector3(0.0, 4.38, 19.0), 8).rotation.x = PI * 0.5
	_finish(room)

## A stack of old sleepers on a cover's footprint: dark timber faces with the
## ends showing in alternate courses, and a few spikes on top.
func _sleeper_stack(props: Node3D, low: Vector3, high: Vector3) -> void:
	var timber: StandardMaterial3D = _mat("sleeper_side", Color("4f3e2e"), 0.0, 0.9)
	var end_grain: StandardMaterial3D = _mat("sleeper_end", Color("7a6248"), 0.0, 0.9)
	var gap: StandardMaterial3D = _mat("pallet_gap", Color("2b2420"), 0.0, 1.0)
	_wrap(props, "SleeperStack", low, high, timber, timber)
	var courses: int = 5
	var course: float = (high.y - low.y) / float(courses)
	for index: int in range(courses):
		var y: float = low.y + course * (float(index) + 1.0)
		for face: Array in [[Vector3.FORWARD, low.z, high.x - low.x], [Vector3.BACK, high.z, high.x - low.x], [Vector3.LEFT, low.x, high.z - low.z], [Vector3.RIGHT, high.x, high.z - low.z]]:
			var out: Vector3 = face[0]
			var at: Vector3 = Vector3((low.x + high.x) * 0.5, y - 0.01, (low.z + high.z) * 0.5)
			if absf(out.x) > 0.5:
				at.x = float(face[1])
			else:
				at.z = float(face[1])
			_sheet(props, "SleeperGap", Vector2(float(face[2]) - 0.02, 0.025), gap, at + out * 0.007, out)
			# Every other course shows its sleepers' ends on the long faces.
			if index % 2 == 0 and absf(out.z) > 0.5:
				for end: int in range(5):
					var side: Vector3 = Vector3.UP.cross(out).normalized()
					_sheet(props, "SleeperEnd", Vector2(0.24, course - 0.05), end_grain, at + side * (-1.2 + float(end) * 0.6) + Vector3(0, -course * 0.5, 0) + out * 0.008, out)
	var spike: StandardMaterial3D = _mat("rail_steel", Color("8e8f8a"), 0.7, 0.35)
	for index: int in range(4):
		_block(props, "Spike", Vector3(0.03, 0.03, 0.18), spike, Vector3(low.x + 0.6 + float(index) * 0.5, high.y + 0.015, low.z + 0.7 + float(index % 2) * 0.4))

# --- the freight platform and its floodlights -----------------------------------

func _build_freight() -> void:
	var room: Node3D = _room("Freight")
	var props: Node3D = _props(room)
	var concrete: StandardMaterial3D = _tiled("yard_concrete", EnvironmentTextures.EARTH + "earth_yard_cast_concrete.png", Color("948b7d"), 2.0)
	for wall: Array in [[Vector3(-40, 0, 33.5), Vector3(-15, 3, 34)], [Vector3(15, 0, 33.5), Vector3(40, 3, 34)]]:
		var low: Vector3 = wall[0]
		var high: Vector3 = wall[1]
		_wrap(props, "FreightWall", low, high, concrete, _mat("coping", Color("8e8576"), 0.0, 0.9))
		var mid: float = (low.x + high.x) * 0.5
		for out: Vector3 in [Vector3.FORWARD, Vector3.BACK]:
			var z: float = low.z if out == Vector3.FORWARD else high.z
			_hazard_band(props, Vector3(mid, 2.75, z) + out * 0.009, out, high.x - low.x - 0.1, 0.18)
			for index: int in range(int((high.x - low.x) / 4.0)):
				_relief(props, "WallPier", Vector3(0.4, 3.0, 0.12), concrete, Vector3(low.x + 2.0 + float(index) * 4.0, 1.5, z), out)
	# The Union's freight sign pylon: issued black with its red band.
	_wrap(props, "SignPylon", Vector3(-14, 0, 30), Vector3(-12, 3, 31), _mat("union_case", Color("2c2d32"), 0.4, 0.5), _mat("union_black", Color("1e1e22"), 0.3, 0.55), [Vector3.FORWARD])
	for out: Vector3 in [Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var at: Vector3 = Vector3(-13.0, 2.75, 30.5)
		var length: float = 2.0
		if out == Vector3.BACK:
			at.z = 31.0
		else:
			at.x = -14.0 if out == Vector3.LEFT else -12.0
			length = 1.0
		_relief(props, "PylonRedBand", Vector3(length, 0.1, 0.02), _mat("union_red", Color("8c1a1e"), 0.2, 0.7), at, out)
	# Floodlight masts at the platform's end, in the yard wall's clearance:
	# the light the whole trench walks toward.
	var mast: StandardMaterial3D = _mat("mast_grey", Color("5d6366"), 0.5, 0.5)
	for x: float in [-22.0, 22.0]:
		var foot: Vector3 = Vector3(x, 0.0, WALL - 0.22)
		_shape.rod(props, "FloodMast", foot, foot + Vector3(0, 11.0, 0), 0.16, mast, 8)
		_block(props, "FloodFrame", Vector3(3.0, 1.2, 0.3), mast, foot + Vector3(0, 11.4, -0.3))
		_shape.rod(props, "FloodStay", foot + Vector3(0, 9.0, 0), foot + Vector3(0, 10.8, -0.35), 0.06, mast, 6)
		for row: int in range(2):
			for index: int in range(4):
				var lens: Vector3 = foot + Vector3(-1.05 + float(index) * 0.7, 11.1 + float(row) * 0.55, -0.46)
				_sheet(props, "FloodLens", Vector2(0.55, 0.42), _glow("flood_lens", Color("fff0d0"), 3.0), lens, Vector3.FORWARD)
		var flood: SpotLight3D = SpotLight3D.new()
		flood.name = "Floodlight%d" % lamps
		var aim: Vector3 = foot + Vector3(0, 11.0, -0.8)
		flood.transform = Transform3D(Basis.looking_at(Vector3(x * 0.25, 0.0, 26.0) - aim, Vector3.UP), aim)
		flood.light_color = FLOOD_LAMP
		flood.light_energy = 2.2
		flood.light_specular = 0.1
		flood.spot_range = 30.0
		flood.spot_angle = 34.0
		flood.spot_attenuation = 0.8
		flood.shadow_enabled = false
		flood.distance_fade_enabled = true
		flood.distance_fade_begin = 50.0
		flood.distance_fade_length = 10.0
		room.add_child(flood)
		lamps += 1
	_finish(room)

# --- Tern's carrier on the pad ------------------------------------------------------

func _build_carrier() -> void:
	var room: Node3D = _room("Carrier")
	var props: Node3D = _props(room)
	# Gunmetal plating with Tern's ember panel and patched repairs; never a
	# Union livery and never an Inheritance off-white.
	var gunmetal: StandardMaterial3D = _mat("carrier_gunmetal", Color("626b6e"), 0.5, 0.5)
	var seam: StandardMaterial3D = _mat("carrier_seam", Color("2e3335"), 0.5, 0.5)
	var ember: StandardMaterial3D = _mat("carrier_ember", Color("b5652e"), 0.2, 0.6)
	var low: Vector3 = Vector3(-12, 0.5, 36)
	var high: Vector3 = Vector3(2, 3, 39.5)
	_wrap(props, "CarrierHull", low, high, gunmetal, gunmetal)
	var under: MeshInstance3D = _floor(props, "CarrierBelly", Vector2(low.x, low.z), Vector2(high.x, high.z), seam, low.y - 0.005)
	under.rotation.x = PI
	_relief(props, "EmberStripe", Vector3(14.0, 0.22, 0.02), ember, Vector3(-5.0, 1.45, 36.0), Vector3.FORWARD)
	_relief(props, "EmberPanel", Vector3(1.6, 0.9, 0.025), ember, Vector3(-9.6, 2.1, 36.0), Vector3.FORWARD)
	for index: int in range(6):
		_relief(props, "HullSeam", Vector3(0.04, 2.4, 0.015), seam, Vector3(-11.0 + float(index) * 2.4, 1.75, 36.0), Vector3.FORWARD)
		_relief(props, "HullSeam", Vector3(0.04, 2.4, 0.015), seam, Vector3(-11.0 + float(index) * 2.4, 1.75, 39.5), Vector3.BACK)
	_relief(props, "HullSeam", Vector3(14.0, 0.04, 0.015), seam, Vector3(-5.0, 2.55, 36.0), Vector3.FORWARD)
	for patch: Array in [[Vector3(-3.4, 1.0, 36.0), Color("6f8a4e")], [Vector3(0.6, 2.6, 36.0), Color("c49a3c")], [Vector3(-7.4, 0.9, 36.0), Color("7d6c5a")]]:
		_relief(props, "HullPatch", Vector3(0.7, 0.5, 0.02), _mat("hull_patch_%s" % (patch[1] as Color).to_html(false), patch[1], 0.3, 0.6), patch[0], Vector3.FORWARD)
	# The cockpit at the west end, lit warm: someone is aboard and waiting.
	_sheet(props, "Cockpit", Vector2(2.6, 0.9), _glow("cockpit_glass", Color("e0b070"), 0.6), Vector3(-12.0, 2.3, 37.75) + Vector3.LEFT * 0.01, Vector3.LEFT)
	_relief(props, "CockpitFrame", Vector3(2.8, 0.1, 0.05), seam, Vector3(-12.0, 2.8, 37.75), Vector3.LEFT)
	_relief(props, "CockpitFrame", Vector3(2.8, 0.1, 0.05), seam, Vector3(-12.0, 1.8, 37.75), Vector3.LEFT)
	_omni(room, "CockpitGlow", Vector3(-12.8, 2.2, 37.75), WARM_LAMP, 0.9, 5.0)
	# Engine pods on the hull's back, landing struts under its belly.
	for z: float in [36.8, 38.7]:
		_shape.cylinder(props, "EnginePod", 0.42, 5.0, _mat("pod_steel", Color("5a6264"), 0.5, 0.45), Vector3(-1.0, 3.42, z), 12).rotation.y = PI * 0.5
		_shape.cylinder(props, "EngineGlow", 0.3, 0.05, _glow("engine_warm", Color("e09050"), 0.8), Vector3(1.53, 3.42, z), 12).rotation.y = PI * 0.5
	for x: float in [-10.5, -5.0, 0.5]:
		for z: float in [36.6, 38.9]:
			_shape.rod(props, "LandingStrut", Vector3(x, 0.5, z), Vector3(x, 0.03, z), 0.08, seam, 6)
			_block(props, "LandingPad", Vector3(0.4, 0.05, 0.4), seam, Vector3(x, 0.025, z))
	# The boarding hatch in the east end, open and lit: Tern is waiting.
	_sheet(props, "HatchFrame", Vector2(1.5, 2.0), seam, Vector3(2.0, 1.5, 37.75) + Vector3.RIGHT * 0.008, Vector3.RIGHT)
	_sheet(props, "HatchOpen", Vector2(1.2, 1.8), _glow("hatch_warm", Color("d8a868"), 0.7), Vector3(2.0, 1.45, 37.75) + Vector3.RIGHT * 0.012, Vector3.RIGHT)
	_relief(props, "HatchStep", Vector3(1.4, 0.08, 0.35), seam, Vector3(2.0, 0.5, 37.75), Vector3.RIGHT)
	for z: float in [36.5, 39.0]:
		_relief(props, "EndEmber", Vector3(0.6, 2.2, 0.02), ember, Vector3(2.0, 1.75, z), Vector3.RIGHT)
	# The cockpit house, the spine and the tail fin over the hull's back: the
	# ship reads over the freight wall from the whole trench.
	_wrap(props, "CockpitHouse", Vector3(-12, 3, 36.7), Vector3(-8.5, 4.7, 38.8), gunmetal, seam)
	_sheet(props, "CockpitGlass", Vector2(1.9, 0.7), _glow("cockpit_glass", Color("e0b070"), 0.6), Vector3(-12.0, 4.1, 37.75) + Vector3.LEFT * 0.01, Vector3.LEFT)
	for out: Vector3 in [Vector3.FORWARD, Vector3.BACK]:
		var z: float = 36.7 if out == Vector3.FORWARD else 38.8
		_sheet(props, "CockpitSide", Vector2(2.4, 0.6), _glow("cockpit_glass", Color("e0b070"), 0.6), Vector3(-10.4, 4.1, z) + out * 0.01, out)
		_relief(props, "HouseEmber", Vector3(3.5, 0.18, 0.02), ember, Vector3(-10.25, 3.35, z), out)
	_wrap(props, "Spine", Vector3(-9, 3, 37.3), Vector3(0, 3.3, 38.2), gunmetal, seam)
	# The tail fin sweeps aft, an ember band near its tip and a running light.
	var lean: float = 0.45
	var up: Vector3 = Vector3(sin(lean), cos(lean), 0.0)
	var fin_at: Vector3 = Vector3(0.4, 4.55, 37.75)
	_block(props, "TailFin", Vector3(2.0, 3.6, 0.4), gunmetal, fin_at).rotation.z = -lean
	_block(props, "FinEmber", Vector3(2.04, 0.45, 0.44), ember, fin_at + up * 1.2).rotation.z = -lean
	_block(props, "FinPatch", Vector3(0.6, 0.5, 0.43), _mat("hull_patch_6f8a4e", Color("6f8a4e"), 0.3, 0.6), fin_at + up * -0.4 + Vector3(-0.3, 0, 0)).rotation.z = -lean
	_shape.cylinder(props, "RunningLight", 0.1, 0.12, _glow("running_amber", Color("ffb050"), 2.5), fin_at + up * 1.9 + Vector3(0.5, 0, 0), 8).rotation.x = PI * 0.5
	_shape.cylinder(props, "RunningLight", 0.1, 0.12, _glow("running_amber", Color("ffb050"), 2.5), Vector3(-10.2, 4.78, 37.75), 8).rotation.x = PI * 0.5
	# The boarding console: gunmetal post with an ember edge, a lamp over it.
	_wrap(props, "BoardingConsole", Vector3(8, 0, 37), Vector3(9, 2, 38), gunmetal, seam, [Vector3.LEFT])
	_relief(props, "ConsoleEmber", Vector3(1.0, 0.08, 0.02), ember, Vector3(8.5, 1.9, 37.0), Vector3.FORWARD)
	_planks(props, "BoardingWalk", Vector2(2.2, 36.6), Vector2(7.8, 38.4), 0.016, false, 0.3)
	_omni(room, "BoardingLamp", Vector3(6.0, 2.6, 37.5), WARM_LAMP, 1.2, 6.5)
	_finish(room)

# --- Splice's patched tram, which rides the trench ---------------------------

func _build_tram() -> void:
	var room: Node3D = _room("Tram")
	var props: Node3D = _props(room)
	tram_room = room
	room.visible = false
	var terracotta: StandardMaterial3D = _mat("tram_terracotta", Color("9a5038"), 0.1, 0.6)
	var cream: StandardMaterial3D = _mat("tram_cream", Color("d2c19a"), 0.1, 0.6)
	var skirt: StandardMaterial3D = _mat("tram_skirt", Color("33302c"), 0.3, 0.6)
	var green: StandardMaterial3D = _mat("tram_green", Color("6f8a4e"), 0.0, 0.6)
	var plate: StandardMaterial3D = _tiled("tram_patch", EnvironmentTextures.EARTH + "earth_workshop_patched_steel.png", Color("9a9a90"), 1.0)
	var rivet: StandardMaterial3D = _mat("iron", Color("2f3231"), 0.4, 0.6)
	var low: Vector3 = TRAM_LOW
	var high: Vector3 = TRAM_HIGH
	for face: Array in [[Vector3.LEFT, 4.0, Vector3(low.x, 0, 6.0)], [Vector3.RIGHT, 4.0, Vector3(high.x, 0, 6.0)], [Vector3.FORWARD, 3.0, Vector3(0, 0, low.z)], [Vector3.BACK, 3.0, Vector3(0, 0, high.z)]]:
		var out: Vector3 = face[0]
		var span: float = face[1]
		var base: Vector3 = face[2]
		var side: Vector3 = Vector3.UP.cross(out).normalized()
		_sheet(props, "TramCream", Vector2(span - 0.02, 0.24), cream, base + Vector3(0, 0.86, 0) + out * 0.004, out)
		_sheet(props, "TramLower", Vector2(span - 0.02, 0.5), terracotta, base + Vector3(0, 0.49, 0) + out * 0.004, out)
		_sheet(props, "TramSkirt", Vector2(span - 0.02, 0.24), skirt, base + Vector3(0, 0.12, 0) + out * 0.005, out)
		if span > 3.5:
			# Wheels in the skirt and Splice's riveted patches on the flanks.
			for edge: float in [-1.3, 1.3]:
				_shape.cylinder(props, "TramWheel", 0.26, 0.06, _mat("tram_wheel", Color("3d3b37"), 0.7, 0.4), base + side * edge + Vector3(0, 0.26, 0) + out * 0.035, 12).basis = Basis(Quaternion(Vector3.BACK, out))
			_sheet(props, "TramPatch", Vector2(0.9, 0.42), plate, base + side * -0.6 + Vector3(0, 0.5, 0) + out * 0.008, out)
			_sheet(props, "TramPatch", Vector2(0.5, 0.3), _mat("splice_magenta", Color("8a3a58"), 0.0, 0.9), base + side * 1.1 + Vector3(0, 0.62, 0) + out * 0.008, out)
			for index: int in range(6):
				_relief(props, "Rivet", Vector3(0.04, 0.04, 0.012), rivet, base + side * (-1.0 + float(index % 3) * 0.4) + Vector3(0, 0.33 + floorf(float(index) / 3.0) * 0.34, 0) + out * 0.008, out)
			if out == Vector3.RIGHT:
				_sheet(props, "FreshGreen", Vector2(1.2, 0.5), green, base + side * 0.4 + Vector3(0, 0.49, 0) + out * 0.006, out)
		else:
			for edge: float in [-1.0, 1.0]:
				_sheet(props, "TramHeadlamp", Vector2(0.26, 0.18), _glow("tram_lamp", Color("e8d6a8"), 0.6), base + side * edge + Vector3(0, 0.62, 0) + out * 0.007, out)
			_relief(props, "TramBumper", Vector3(span - 0.3, 0.12, 0.1), skirt, base + Vector3(0, 0.28, 0), out)
	# The deck: boards over the old roof frame, an ochre edge to stand back
	# from, and a rolled tarp along one side.
	_planks(props, "TramDeck", Vector2(low.x + 0.01, low.z + 0.01), Vector2(high.x - 0.01, high.z - 0.01), high.y + 0.002, true, 0.3)
	for x: float in [low.x + 0.02, high.x - 0.14]:
		_floor(props, "DeckEdge", Vector2(x, low.z + 0.02), Vector2(x + 0.12, high.z - 0.02), _mat("road_paint", Color("c9a23c"), 0.0, 0.9), high.y + 0.008)
	_shape.cylinder(props, "RolledTarp", 0.08, 3.6, _mat("tarp", Color("6f7d76"), 0.0, 0.9), Vector3(high.x - 0.3, high.y + 0.08, 6.0), 8)
	_finish(room)

# --- the freight gate, the level's one door ----------------------------------

## A ribbed roller gate in dark issued steel, ochre and black along its foot.
## It rises with the server's gate solid; nothing here opens it.
func _build_gate() -> void:
	var room: Node3D = _room("FreightGate")
	var props: Node3D = _props(room)
	gate_room = room
	var steel: StandardMaterial3D = _mat("gate_steel", Color("4a4f52"), 0.4, 0.55)
	var slat: StandardMaterial3D = _mat("gate_slat", Color("33383a"), 0.4, 0.55)
	_wrap(props, "GateSteel", GATE_LOW, GATE_HIGH, steel, _mat("gate_top", Color("2e3335"), 0.4, 0.6))
	for out: Vector3 in [Vector3.FORWARD, Vector3.BACK]:
		var z: float = GATE_LOW.z if out == Vector3.FORWARD else GATE_HIGH.z
		for row: int in range(1, 12):
			_sheet(props, "GateSlat", Vector2(29.96, 0.05), slat, Vector3(0.0, float(row) * 0.25, z) + out * 0.008, out)
		_hazard_band(props, Vector3(0.0, 0.18, z) + out * 0.01, out, 29.9, 0.3)
		for x: float in [-10.0, 0.0, 10.0]:
			_relief(props, "GateRib", Vector3(0.18, 2.96, 0.04), slat, Vector3(x, 1.5, z), out)
	_finish(room)
