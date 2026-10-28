class_name M03Dressing
extends Node3D

## Scheduled Service's golden-slice dressing (docs/campaign/l03-scheduled-service.md,
## docs/design/earth.md "M03 freight yard"). The server owns every solid; this
## presenter only furnishes them: flush ballast, sleepers and paint, faces on
## existing bodies, small possessions on existing tops, overhead runs and
## practical light, plus the yard wall and the country beyond the play square.
## A body that could stop a pawn or a shot is never added inside the yard.
##
## The story is told without words. People were walked from the correction
## complex's dock straight along a painted lane into the first car; what they
## carried was taken off them at a baggage cart. The cars are issued recall
## stock, numbered and sealed. The brakemen left a kettle on a warm stove. The
## dispatcher's desk still has a mug on the timetable. The mast is a red-banded
## lattice over everything, and through the closed yard gate the line runs on
## past open country to a smudge on the horizon that is Low Water.

const Geometry = preload("res://scripts/model_geometry.gd")
const MAP_ID: int = 1003
const OCHRE: Color = Color("9a7c3e")
const BONE: Color = Color("c8c1aa")
const MAST_RED: Color = Color("7a1e1e")
const COLD: Color = Color(0.86, 0.92, 0.92)
## Personal colours on what people carried: warm, varied, never black-and-red.
const PERSONAL: Array[Color] = [Color("b5652e"), Color("6f8a4e"), Color("c49a3c"), Color("8a3a58"), Color("4f6f8a"), Color("a8552c"), Color("7c5a8c")]
## Coupled cars: [low corner, high corner, open west bay].
const CARS: Array = [
	[Vector3(-15, 0, -33), Vector3(-5, 3, -21), true],
	[Vector3(-15, 0, -15), Vector3(-5, 3, -3), true],
	[Vector3(-15, 0, 3), Vector3(-5, 3, 15), true],
	[Vector3(5, 0, -27), Vector3(11, 3, -15), false],
	[Vector3(5, 0, -9), Vector3(11, 3, 3), false],
	[Vector3(5, 0, 9), Vector3(11, 3, 21), false],
]
const TRACKS: Array[float] = [-8.0, 8.0]
const WALL: float = 44.75

var _shape: RefCounted = Geometry.new()
var _unattached: Array[Node3D] = []
var _mast_down: bool = false
## Rooms built for the current map, and the presenter lamps they carry.
var rooms: Array[String] = []
var lamps: int = 0

func clear_map() -> void:
	rooms.clear()
	lamps = 0
	_mast_down = false
	for room: Node3D in _unattached:
		room.free()
	_unattached.clear()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func active() -> bool:
	return not rooms.is_empty()

func mast_down() -> bool:
	return _mast_down

## Scheduled Service's own authored layout only, checked on bodies that never
## move when the mast falls. A custom map reusing the id gets no dressing.
static func authored(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != MAP_ID or not info.get("solids") is Array:
		return false
	var wanted: Array = [
		[Vector3(18, 0, 11), Vector3(27, 2.5, 23)],
		[Vector3(19, 2.5, 19), Vector3(26, 3.5, 23)],
		[Vector3(-11, 0, 29), Vector3(-5, 2.2, 38)],
		[Vector3(-27, 0, -36), Vector3(-25, 4, -35.5)],
		[Vector3(-25, 0, 3), Vector3(-22, 0.8, 5)],
		[Vector3(24, 0, -30), Vector3(26, 0.8, -27)],
		[Vector3(5, 0, -27), Vector3(11, 3, -15)],
	]
	var found: int = 0
	for raw: Variant in info["solids"]:
		if not raw is Dictionary:
			continue
		var solid: Dictionary = raw
		var low: Vector3 = Vector3(float(solid.get("min_x", 0.0)), float(solid.get("bottom", 0.0)), float(solid.get("min_z", 0.0)))
		var high: Vector3 = Vector3(float(solid.get("max_x", 0.0)), float(solid.get("top", 0.0)), float(solid.get("max_z", 0.0)))
		for pair: Array in wanted:
			if low.is_equal_approx(pair[0]) and high.is_equal_approx(pair[1]):
				found += 1
	return found == wanted.size()

static func _shutdown(info: Dictionary) -> bool:
	return info.get("m03") is Dictionary and info["m03"].get("mast_shutdown", false) == true

func configure_map(info: Dictionary) -> void:
	if active() and authored(info):
		# The fallen mast arrives as a new MapInfo with moved solids; only the
		# mast's own dressing changes with it.
		if _shutdown(info) != _mast_down:
			var old: Node = get_node_or_null("Mast")
			if old != null:
				remove_child(old)
				old.queue_free()
			rooms.erase("Mast")
			_mast_down = _shutdown(info)
			_build_mast()
			_attach()
		return
	clear_map()
	if not authored(info):
		return
	_mast_down = _shutdown(info)
	_build_perimeter()
	_build_country()
	_build_tracks()
	_build_platform()
	_build_cars()
	_build_board()
	_build_office()
	_build_hut()
	_build_mast()
	_build_signal_box()
	_build_gantry()
	_build_locomotive()
	_attach()

func _attach() -> void:
	# Final layers before attachment; see M01Intake for the Forward+ reason.
	for room: Node3D in _unattached:
		ArenaSky.mark_world(room)
		add_child(room)
	_unattached.clear()

# --- shared builders -------------------------------------------------------

func _room(label: String) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = label
	_unattached.append(node)
	rooms.append(label)
	return node

## One merged mesh per room keeps draw calls low and each room's light list
## local, which the Compatibility renderer's per-object limit needs.
func _finish(room: Node3D) -> void:
	var props: Node3D = room.get_node_or_null("Props") as Node3D
	if props != null and props.get_child_count() > 0:
		_shape.merge(props)

func _props(room: Node3D) -> Node3D:
	var props: Node3D = room.get_node_or_null("Props") as Node3D
	if props == null:
		props = Node3D.new()
		props.name = "Props"
		room.add_child(props)
	return props

func _mat(key: String, tint: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	return _shape.material("m03_" + key, tint, metallic, roughness)

func _glow(key: String, tint: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = _mat(key, tint)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	return material

func _block(props: Node3D, label: String, size: Vector3, finish: StandardMaterial3D, at: Vector3) -> MeshInstance3D:
	return _shape.block(props, label, size, finish, at)

## A flat world-tiled ground patch, outside the merged props.
func _floor(parent: Node3D, label: String, low: Vector2, high: Vector2, y: float, material: Material) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = high - low
	node.mesh = mesh
	node.position = Vector3((low.x + high.x) * 0.5, y, (low.y + high.y) * 0.5)
	node.material_override = material
	parent.add_child(node)

## A mark painted by the facility panel shader (the circled six, a chalk 67),
## named as MapDecoration names faces.
func _mark(parent: Node3D, label: String, style: int, paint: Color, size: Vector2, at: Vector3, face: String) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = ArenaDecoration.PANEL_SHADER
	material.set_shader_parameter("panel_size", size)
	material.set_shader_parameter("style", style)
	material.set_shader_parameter("paint_color", paint)
	node.material_override = material
	node.transform = Transform3D(MapDecoration.face_basis(face), at)
	parent.add_child(node)

func _omni(room: Node3D, label: String, at: Vector3, colour: Color, energy: float, reach: float) -> OmniLight3D:
	var light: OmniLight3D = OmniLight3D.new()
	light.name = label
	light.position = at
	light.light_color = colour
	light.light_energy = energy
	light.light_specular = 0.1
	light.omni_range = reach
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 34.0
	light.distance_fade_length = 8.0
	room.add_child(light)
	lamps += 1
	return light

## A caged service lamp: bulb, cage, an optional cable and a short light.
func _lamp(room: Node3D, at: Vector3, colour: Color, energy: float = 1.6, reach: float = 6.0, cable_to: float = -1.0) -> OmniLight3D:
	var props: Node3D = _props(room)
	var bulb: StandardMaterial3D = _glow("lamp_bulb_%s" % colour.to_html(false), colour.lightened(0.2), 2.4)
	var cage: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	_shape.cylinder(props, "LampBulb", 0.075, 0.16, bulb, at, 10).rotation.x = PI * 0.5
	_shape.cylinder(props, "LampShade", 0.18, 0.05, cage, at + Vector3(0, 0.1, 0), 12).rotation.x = PI * 0.5
	if cable_to > at.y:
		_shape.rod(props, "LampCable", at + Vector3(0, 0.12, 0), Vector3(at.x, cable_to, at.z), 0.012, cage, 4)
	return _omni(room, "ServiceLamp", at + Vector3(0, -0.12, 0), colour, energy, reach)

func _mug(props: Node3D, at: Vector3, tint: Color) -> void:
	_shape.cylinder(props, "Mug", 0.045, 0.1, _mat("mug_%s" % tint.to_html(false), tint, 0.0, 0.6), at + Vector3(0, 0.05, 0), 10).rotation.x = PI * 0.5

func _papers(props: Node3D, at: Vector3, count: int, seed_value: int) -> void:
	var paper: StandardMaterial3D = _mat("paper", Color("e3dccb"), 0.0, 0.95)
	var form: StandardMaterial3D = _mat("form_green", Color("b8c4a6"), 0.0, 0.95)
	for index: int in range(count):
		var height: float = 0.012 + float((seed_value + index * 7) % 4) * 0.008
		var piece: MeshInstance3D = _block(props, "Forms", Vector3(0.22, height, 0.3), form if (index + seed_value) % 3 == 0 else paper, at + Vector3(float(index) * 0.27, height * 0.5, float((index * 3 + seed_value) % 4) * 0.03))
		piece.rotation.y = float((index * 5 + seed_value) % 7 - 3) * 0.07

## Thin paint, flush on the ground or an existing top. Never a body.
func _paint_line(props: Node3D, from: Vector3, to: Vector3, width: float, finish: StandardMaterial3D) -> void:
	var span: Vector3 = to - from
	var line: MeshInstance3D = _block(props, "Paint", Vector3(width, 0.006, span.length()), finish, (from + to) * 0.5 + Vector3(0, 0.004, 0))
	line.rotation.y = atan2(span.x, span.z)

## A wheel whose axle runs across X, standing proud of a car face.
func _wheel(props: Node3D, at: Vector3, radius: float, tread: StandardMaterial3D, hub: StandardMaterial3D) -> void:
	_shape.cylinder(props, "Wheel", radius, 0.12, tread, at, 14).rotation.y = PI * 0.5
	_shape.cylinder(props, "WheelHub", radius * 0.38, 0.16, hub, at, 10).rotation.y = PI * 0.5

## A brake wheel: rim, hub and four spokes on a face (out is the face normal).
func _brake_wheel(props: Node3D, at: Vector3, out: Vector3, finish: StandardMaterial3D) -> void:
	var rim: MeshInstance3D = _shape.lathe(props, "BrakeRim", PackedVector2Array([Vector2(-0.02, 0.3), Vector2(-0.02, 0.36), Vector2(0.02, 0.36), Vector2(0.02, 0.3)]), finish, at, 16)
	rim.basis = Basis(Quaternion(Vector3.BACK, out))
	var side: Vector3 = out.cross(Vector3.UP).normalized()
	for axis: Vector3 in [side, Vector3.UP]:
		_shape.rod(props, "BrakeSpoke", at - axis * 0.32, at + axis * 0.32, 0.018, finish, 5)
	_shape.rod(props, "BrakeShaft", at, at - out * 0.14, 0.03, finish, 6)

# --- yard wall, correction complex and the dock door -------------------------

func _build_perimeter() -> void:
	var room: Node3D = _room("Perimeter")
	var props: Node3D = _props(room)
	var dirt: ShaderMaterial = ArenaMaterials.scenery_tile(EnvironmentTextures.EARTH + "earth_yard_cast_concrete.png", Color("6b6556"))
	# Ground beyond the play square, a step under the yard slab.
	_floor(room, "OuterGround", Vector2(-320, -320), Vector2(320, 320), -0.03, dirt)
	var panel: StandardMaterial3D = _mat("wall_panel", Color("85806f"), 0.0, 0.95)
	var stained: StandardMaterial3D = _mat("wall_panel_stained", Color("6e6a5c"), 0.0, 0.95)
	var post: StandardMaterial3D = _mat("wall_post", Color("5c5a52"), 0.0, 0.9)
	var wire: StandardMaterial3D = _mat("wire", Color("2a2a2a"), 0.5, 0.5)
	var rust: StandardMaterial3D = _mat("rust_streak", Color("54402f"), 0.0, 0.9)
	# Precast panels on posts with three strands of wire above: west, east and
	# the north wall either side of the gate. The south is the complex itself.
	var runs: Array = [
		[Vector3(-WALL, 0, -WALL), Vector3(-WALL, 0, WALL)],
		[Vector3(WALL, 0, -WALL), Vector3(WALL, 0, WALL)],
		[Vector3(-WALL, 0, WALL), Vector3(-13.0, 0, WALL)],
		[Vector3(13.0, 0, WALL), Vector3(WALL, 0, WALL)],
	]
	var count: int = 0
	for run: Array in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var along: Vector3 = (b - a).normalized()
		var length: float = a.distance_to(b)
		var steps: int = int(round(length / 4.0))
		for index: int in range(steps):
			var centre: Vector3 = a + along * (float(index) + 0.5) * (length / float(steps))
			var size: Vector3 = Vector3(0.4, 3.0, length / float(steps) - 0.08) if absf(along.z) > 0.5 else Vector3(length / float(steps) - 0.08, 3.0, 0.4)
			_block(props, "WallPanel", size, stained if (count * 7) % 5 == 0 else panel, centre + Vector3(0, 1.5, 0))
			var corner: Vector3 = a + along * float(index) * (length / float(steps))
			_block(props, "WallPost", Vector3(0.5, 3.7, 0.5), post, corner + Vector3(0, 1.85, 0))
			if count % 3 == 1:
				var inward: Vector3 = -Vector3(signf(centre.x), 0, 0) if absf(along.z) > 0.5 else -Vector3(0, 0, signf(centre.z))
				var streak: Vector3 = centre + inward * 0.21 + along * (float(count % 4) - 1.5) * 0.6
				_block(props, "RustStreak", Vector3(0.05, 1.4, 0.18) if absf(along.z) > 0.5 else Vector3(0.18, 1.4, 0.05), rust, streak + Vector3(0, 2.1, 0))
			count += 1
		for strand: int in range(3):
			_shape.rod(props, "Wire", a + Vector3(0, 3.25 + float(strand) * 0.17, 0), b + Vector3(0, 3.25 + float(strand) * 0.17, 0), 0.01, wire, 4)
	# Floodlight masts on the wall line: unlit in the afternoon, they give the
	# yard its rhythm of verticals and mark where the night shift works.
	var mast: StandardMaterial3D = _mat("flood_mast", Color("4a4c4a"), 0.4, 0.6)
	var head: StandardMaterial3D = _mat("flood_head", Color("2c2d2e"), 0.4, 0.6)
	var lens: StandardMaterial3D = _mat("flood_lens", Color("b9b7a8"), 0.2, 0.4)
	for at: Vector3 in [Vector3(-WALL - 0.6, 0, -24), Vector3(-WALL - 0.6, 0, 8), Vector3(WALL + 0.6, 0, -8), Vector3(WALL + 0.6, 0, 24), Vector3(-30, 0, WALL + 0.6), Vector3(30, 0, WALL + 0.6)]:
		_shape.cylinder(props, "FloodMast", 0.22, 17.0, mast, at + Vector3(0, 8.5, 0), 8).rotation.x = PI * 0.5
		var inward: Vector3 = Vector3(-signf(at.x), 0, 0) if absf(at.x) > 40.0 else Vector3(0, 0, -signf(at.z))
		var side: Vector3 = inward.cross(Vector3.UP)
		_block(props, "FloodBar", Vector3(2.6, 0.12, 0.12) if absf(side.x) > 0.5 else Vector3(0.12, 0.12, 2.6), head, at + Vector3(0, 16.6, 0))
		for offset: float in [-0.9, 0.0, 0.9]:
			var lamp_at: Vector3 = at + Vector3(0, 16.9, 0) + side * offset + inward * 0.2
			_block(props, "FloodHead", Vector3(0.55, 0.45, 0.35), head, lamp_at)
			_block(props, "FloodLens", Vector3(0.42, 0.32, 0.02) if absf(inward.z) > 0.5 else Vector3(0.02, 0.32, 0.42), lens, lamp_at + inward * 0.18)
	_finish(room)
	_build_complex()

## The correction complex closes the south side: the same bone enamel and
## green band as the intake and the ward, and the dock's roller shutter
## stopped short of the floor behind the arrival, as Level 2 left it.
func _build_complex() -> void:
	var room: Node3D = _room("Complex")
	var props: Node3D = _props(room)
	var enamel: StandardMaterial3D = _mat("complex_bone", Color("cfc8b4"), 0.0, 0.9)
	enamel.uv1_triplanar = true
	enamel.uv1_world_triplanar = true
	enamel.uv1_scale = Vector3(0.3, 0.3, 0.3)
	var face: float = -WALL
	var door_x: float = -19.0
	var door_half: float = 3.6
	var door_top: float = 5.0
	# The building mass, leaving the dock opening.
	var masses: Array = [
		[Vector3(-WALL - 6.0, 0, face - 14.0), Vector3(door_x - door_half, 16.0, face)],
		[Vector3(door_x + door_half, 0, face - 14.0), Vector3(WALL + 6.0, 11.0, face)],
		[Vector3(door_x - door_half, door_top, face - 14.0), Vector3(door_x + door_half, 16.0, face)],
		[Vector3(-8.0, 11.0, face - 14.0), Vector3(14.0, 19.0, face - 3.0)],
	]
	for entry: Array in masses:
		var low: Vector3 = entry[0]
		var high: Vector3 = entry[1]
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = "ComplexMass"
		var box: BoxMesh = BoxMesh.new()
		box.size = high - low
		node.mesh = box
		node.position = (low + high) * 0.5
		node.material_override = enamel
		room.add_child(node)
	var band: StandardMaterial3D = _mat("institutional_green", Color("4e5844"), 0.0, 0.85)
	var parapet: StandardMaterial3D = _mat("complex_parapet", Color("57595a"), 0.3, 0.7)
	var glass: StandardMaterial3D = _mat("complex_glass", Color("1d2426"), 0.1, 0.4)
	var bar: StandardMaterial3D = _mat("complex_bar", Color("2c2d32"), 0.5, 0.5)
	# The institutional band along the foot of the wall, storey joints and
	# downpipes on a long plain facade.
	var joint: StandardMaterial3D = _mat("complex_joint", Color("a39c88"), 0.0, 0.9)
	for span: Vector2 in [Vector2(-WALL - 6.0, door_x - door_half), Vector2(door_x + door_half, WALL + 6.0)]:
		_block(props, "GreenBand", Vector3(span.y - span.x, 1.2, 0.06), band, Vector3((span.x + span.y) * 0.5, 0.6, face + 0.02))
		for y: float in [3.6, 7.2, 10.8, 14.4]:
			if y < (11.0 if span.x > door_x else 16.0):
				_block(props, "StoreyJoint", Vector3(span.y - span.x, 0.12, 0.04), joint, Vector3((span.x + span.y) * 0.5, y, face + 0.02))
		_block(props, "Parapet", Vector3(span.y - span.x, 0.4, 0.5), parapet, Vector3((span.x + span.y) * 0.5, 11.2 if span.x > door_x else 16.2, face - 0.1))
	for x: float in [-36.0, -27.0, -8.0, 6.0, 20.0, 34.0]:
		_block(props, "Downpipe", Vector3(0.18, 11.0 if x > door_x else 16.0, 0.16), parapet, Vector3(x, (11.0 if x > door_x else 16.0) * 0.5, face + 0.1))
	# Barred clerestory windows high on the facade: nobody looks out of these.
	for index: int in range(15):
		var x: float = -40.0 + float(index) * 6.0
		if absf(x - door_x) < 5.0:
			continue
		var y: float = 8.2 if x > door_x else 12.0
		_block(props, "ComplexWindow", Vector3(2.4, 1.0, 0.06), glass, Vector3(x, y, face + 0.03))
		for bar_index: int in range(5):
			_block(props, "WindowBar", Vector3(0.05, 1.0, 0.08), bar, Vector3(x - 1.0 + float(bar_index) * 0.5, y, face + 0.06))
	# The dock door: frame, a roller shutter stopped short of the floor and the
	# drum above it. Dark under the shutter; the ward is behind it.
	var frame: StandardMaterial3D = _mat("door_frame", Color("2c2d32"), 0.5, 0.5)
	var slat: StandardMaterial3D = _mat("shutter_slat", Color("6d6f6a"), 0.4, 0.6)
	var dark: StandardMaterial3D = _mat("dock_dark", Color("0d0e0f"), 0.0, 1.0)
	_block(props, "DockDark", Vector3(door_half * 2.0, door_top, 0.1), dark, Vector3(door_x, door_top * 0.5, face - 3.0))
	for side: float in [-1.0, 1.0]:
		_block(props, "DoorPost", Vector3(0.35, door_top + 0.4, 0.3), frame, Vector3(door_x + side * (door_half + 0.1), (door_top + 0.4) * 0.5, face + 0.05))
		_block(props, "DockBumper", Vector3(0.45, 0.6, 0.25), _mat("bumper", Color("1b1b1c"), 0.0, 0.95), Vector3(door_x + side * (door_half + 0.9), 0.9, face + 0.12))
	_block(props, "DoorHead", Vector3(door_half * 2.0 + 0.9, 0.5, 0.36), frame, Vector3(door_x, door_top + 0.25, face + 0.06))
	_shape.cylinder(props, "ShutterDrum", 0.42, door_half * 2.0, frame, Vector3(door_x, door_top - 0.4, face - 0.4), 12).rotation.y = PI * 0.5
	var bottom: float = 0.38
	var slats: int = int((door_top - 0.8 - bottom) / 0.24)
	for index: int in range(slats):
		_block(props, "ShutterSlat", Vector3(door_half * 2.0 - 0.1, 0.22, 0.06), slat, Vector3(door_x, bottom + 0.12 + float(index) * 0.24, face - 0.5))
	_block(props, "ShutterBar", Vector3(door_half * 2.0 - 0.1, 0.08, 0.1), frame, Vector3(door_x, bottom + 0.04, face - 0.5))
	# Ochre chevrons on the threshold, the dock's working side.
	var hatch: StandardMaterial3D = _mat("hazard_ochre", OCHRE, 0.0, 0.85)
	for index: int in range(8):
		var x: float = door_x - door_half + 0.45 + float(index) * 0.9
		var stripe: MeshInstance3D = _block(props, "DockChevron", Vector3(0.22, 0.006, 1.1), hatch, Vector3(x, 0.004, face + 1.0))
		stripe.rotation.y = 0.5
	# A cold strip over the door, the ward's light on the yard side.
	_omni(room, "DockStrip", Vector3(door_x, door_top + 0.9, face + 0.6), COLD, 1.2, 6.0)
	_block(props, "DockStripLens", Vector3(2.4, 0.08, 0.16), _glow("strip_lens", Color("e6eeee"), 1.6), Vector3(door_x, door_top + 0.75, face + 0.25))
	_finish(room)

# --- beyond the gate: the line home ----------------------------------------

func _build_country() -> void:
	var room: Node3D = _room("Country")
	var props: Node3D = _props(room)
	var post: StandardMaterial3D = _mat("gate_post", Color("4b4a45"), 0.3, 0.7)
	var gate: StandardMaterial3D = _mat("gate_bar", Color("3d3f3c"), 0.5, 0.55)
	# The yard gate, closed across both lines; the train opens it on the way out.
	for x: float in [-13.0, 0.0, 13.0]:
		_block(props, "GatePost", Vector3(0.6, 4.2, 0.6), post, Vector3(x, 2.1, WALL))
		_block(props, "GateCap", Vector3(0.8, 0.2, 0.8), post, Vector3(x, 4.3, WALL))
	for leaf: Vector2 in [Vector2(-12.7, -0.3), Vector2(0.3, 12.7)]:
		var mid: float = (leaf.x + leaf.y) * 0.5
		var width: float = leaf.y - leaf.x
		for y: float in [0.25, 1.6, 3.1]:
			_block(props, "GateRail", Vector3(width, 0.12, 0.1), gate, Vector3(mid, y, WALL))
		var bars: int = int(width / 0.32)
		for index: int in range(bars + 1):
			_block(props, "GateBar", Vector3(0.05, 2.95, 0.05), gate, Vector3(leaf.x + float(index) * (width / float(bars)), 1.68, WALL))
		_shape.rod(props, "GateBrace", Vector3(leaf.x + 0.2, 0.3, WALL - 0.05), Vector3(leaf.y - 0.2, 3.05, WALL - 0.05), 0.04, gate, 5)
	# The line runs on: ballast, sleepers and polished rail heads past the gate.
	var ballast: ShaderMaterial = ArenaMaterials.scenery_tile(EnvironmentTextures.EARTH + "earth_service_dark_tread.png", Color("4d463d"))
	var sleeper: StandardMaterial3D = _mat("sleeper_wood", Color("3b322a"), 0.0, 0.95)
	var rail: StandardMaterial3D = _mat("rail_outside", Color("5a5853"), 0.6, 0.45)
	var head: StandardMaterial3D = _mat("rail_head", Color("a9a79e"), 0.8, 0.3)
	for x: float in TRACKS:
		_floor(room, "BallastBeyond", Vector2(x - 2.2, WALL - 0.2), Vector2(x + 2.2, 300.0), 0.004, ballast)
		for z_index: int in range(150):
			var z: float = WALL + 0.6 + float(z_index) * 1.6
			_block(props, "Sleeper", Vector3(2.6, 0.06, 0.26), sleeper, Vector3(x, 0.03, z))
		for side: float in [-1.0, 1.0]:
			_block(props, "RailBeyond", Vector3(0.2, 0.08, 300.0 - WALL), rail, Vector3(x + side * 1.05, 0.04, (WALL + 300.0) * 0.5))
			_block(props, "RailHeadBeyond", Vector3(0.07, 0.01, 300.0 - WALL), head, Vector3(x + side * 1.05, 0.085, (WALL + 300.0) * 0.5))
	# Open country: low sage rises either side of the line, then the horizon.
	var leaf: StandardMaterial3D = _mat("field_sage", Color("74884e"), 0.0, 1.0)
	var shade: StandardMaterial3D = _mat("field_shadow", Color("4f6138"), 0.0, 1.0)
	var hills: Array = [
		[Vector3(-70, 0, 120), Vector3(70, 7, 40), leaf],
		[Vector3(60, 0, 150), Vector3(60, 9, 45), shade],
		[Vector3(-130, 0, 190), Vector3(90, 14, 60), shade],
		[Vector3(140, 0, 210), Vector3(100, 12, 55), leaf],
		[Vector3(-30, 0, 260), Vector3(120, 10, 50), leaf],
		[Vector3(-90, 0, 70), Vector3(40, 4, 25), leaf],
		[Vector3(95, 0, 80), Vector3(45, 5, 28), leaf],
	]
	for entry: Array in hills:
		var at: Vector3 = entry[0]
		var size: Vector3 = entry[1]
		_shape.hull(props, "Rise", PackedVector3Array([Vector3(0, size.x * 0.5, size.z * 0.5), Vector3(size.y * 0.55, size.x * 0.4, size.z * 0.38), Vector3(size.y, size.x * 0.18, size.z * 0.16)]), entry[2], at, 14)
	# Hedge lines and a few trees break the fields.
	var tree: StandardMaterial3D = _mat("tree_leaf", Color("3a4c2e"), 0.0, 1.0)
	var trunk: StandardMaterial3D = _mat("tree_trunk", Color("3b3128"), 0.0, 1.0)
	for index: int in range(16):
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var at: Vector3 = Vector3(side * (22.0 + float((index * 37) % 50)), 0, 62.0 + float(index) * 9.0)
		var tall: float = 4.0 + float((index * 13) % 5)
		_shape.cylinder(props, "TreeTrunk", 0.22, tall * 0.4, trunk, at + Vector3(0, tall * 0.2, 0), 6).rotation.x = PI * 0.5
		_shape.hull(props, "TreeCrown", PackedVector3Array([Vector3(0, 0.4, 0.4), Vector3(tall * 0.3, tall * 0.32, tall * 0.3), Vector3(tall * 0.7, tall * 0.22, tall * 0.2), Vector3(tall * 0.75, 0.1, 0.1)]), tree, at + Vector3(0, tall * 0.35, 0), 8)
	# Low Water on the horizon: homes, a tram mast and rooftop tanks, a smudge
	# in the afternoon haze where the line ends.
	var plaster: StandardMaterial3D = _mat("low_water_plaster", Color("b48a6a"), 0.0, 0.95)
	var sage: StandardMaterial3D = _mat("low_water_sage", Color("8f9a7c"), 0.0, 0.95)
	var roof: StandardMaterial3D = _mat("low_water_roof", Color("5a4a40"), 0.0, 0.95)
	var tank: StandardMaterial3D = _mat("low_water_tank", Color("6d6a60"), 0.2, 0.8)
	var town: Vector3 = Vector3(36, 0, 236)
	for index: int in range(11):
		var x: float = town.x - 30.0 + float(index) * 6.2
		var z: float = town.z + float((index * 17) % 5) * 3.0
		var tall: float = 5.0 + float((index * 7) % 4) * 2.2
		_block(props, "TownHouse", Vector3(5.4, tall, 7.0), plaster if index % 3 != 1 else sage, Vector3(x, tall * 0.5, z))
		_block(props, "TownRoof", Vector3(5.8, 0.5, 7.4), roof, Vector3(x, tall + 0.25, z))
		if index % 3 == 0:
			_shape.cylinder(props, "TownTank", 1.0, 1.8, tank, Vector3(x + 1.0, tall + 1.4, z), 10).rotation.x = PI * 0.5
	_shape.rod(props, "TownMast", town + Vector3(6, 0, 4), town + Vector3(6, 20, 4), 0.25, tank, 6)
	_finish(room)

# --- track, ballast, sleepers and crossings ----------------------------------

func _build_tracks() -> void:
	var room: Node3D = _room("Tracks")
	var props: Node3D = _props(room)
	var ballast: ShaderMaterial = ArenaMaterials.scenery_tile(EnvironmentTextures.EARTH + "earth_service_dark_tread.png", Color("4d463d"))
	var sleeper: StandardMaterial3D = _mat("sleeper_wood", Color("3b322a"), 0.0, 0.95)
	var head: StandardMaterial3D = _mat("rail_head", Color("a9a79e"), 0.8, 0.3)
	var plate: StandardMaterial3D = _mat("tie_plate", Color("2d2b29"), 0.5, 0.6)
	var coping: StandardMaterial3D = _mat("platform_coping", Color("9b968a"), 0.0, 0.9)
	var safety: StandardMaterial3D = _mat("hazard_ochre", OCHRE, 0.0, 0.85)
	var plank: StandardMaterial3D = _mat("crossing_wood", Color("5e4c3a"), 0.0, 0.95)
	# The yard slab: weathered cast concrete over the whole square, with
	# expansion joints every six metres and oil where the shunters stand.
	var slab: ShaderMaterial = ArenaMaterials.scenery_tile(EnvironmentTextures.EARTH + "earth_yard_cast_concrete.png", Color("615d55"))
	slab.set_shader_parameter("tile_floor_strength", 0.5)
	_floor(room, "YardSlab", Vector2(-44.0, -44.0), Vector2(44.0, 44.0), 0.002, slab)
	# Steel stairs: ochre nosing on every tread and dark stringers.
	var stringer: StandardMaterial3D = _mat("stair_stringer", Color("2f322d"), 0.4, 0.6)
	var stairs: Array = [
		# [first step low corner, step run along x or z, rise per step, count, riser faces]
		[Vector3(-23, 0, -25), Vector3(2, 0, 0), 0.5, 6, Vector3(-1, 0, 0), 3.0],
		[Vector3(21, 0, -23), Vector3(-2, 0, 0), 0.5, 6, Vector3(1, 0, 0), 3.0],
		[Vector3(20, 0, 1), Vector3(0, 0, 2), 0.5, 5, Vector3(0, 0, -1), 3.0],
	]
	for flight: Array in stairs:
		var start: Vector3 = flight[0]
		var run: Vector3 = flight[1]
		var rise: float = flight[2]
		var riser: Vector3 = flight[4]
		var width: float = flight[5]
		for step: int in range(int(flight[3])):
			var low: Vector3 = start + run * float(step)
			var top: float = rise * float(step + 1)
			var span: Vector3 = Vector3(absf(run.x), 0, absf(run.z))
			var across: Vector3 = Vector3(0, 0, width) if span.x > 0.0 else Vector3(width, 0, 0)
			var centre: Vector3 = low + (span + across) * 0.5
			var edge: Vector3 = centre + riser * (span.length() * 0.5 - 0.06)
			_block(props, "Nosing", Vector3(0.1, 0.008, width) if span.x > 0.0 else Vector3(width, 0.008, 0.1), safety, Vector3(edge.x, top + 0.004, edge.z))
			for side: float in [-0.5, 0.5]:
				var at: Vector3 = centre + across * side + (Vector3(0, 0, 0.012 * signf(side)) if span.x > 0.0 else Vector3(0.012 * signf(side), 0, 0))
				_block(props, "Stringer", Vector3(span.x, top, 0.025) if span.x > 0.0 else Vector3(0.025, top, span.z), stringer, Vector3(at.x, top * 0.5, at.z))
	var joint: StandardMaterial3D = _mat("slab_joint", Color("4a4740"), 0.0, 0.95)
	for index: int in range(1, 15):
		var at: float = -44.0 + float(index) * 6.0
		_block(props, "SlabJoint", Vector3(88.0, 0.004, 0.05), joint, Vector3(0, 0.0035, at))
		_block(props, "SlabJoint", Vector3(0.05, 0.004, 88.0), joint, Vector3(at, 0.0035, 0))
	var oil: StandardMaterial3D = _mat("oil_stain", Color("4d4943"), 0.0, 0.8)
	for at: Vector3 in [Vector3(-2, 0, -20), Vector3(15, 0, -30), Vector3(-20, 0, 20), Vector3(14, 0, 14), Vector3(0, 0, 33), Vector3(-24, 0, -10), Vector3(24, 0, 2)]:
		for drop: int in range(5):
			var spread: Vector3 = Vector3(float((drop * 7) % 5) - 2.0, 0, float((drop * 3) % 5) - 2.0) * 0.28
			var size: float = 0.25 + float((drop * 5 + int(at.z)) % 4) * 0.12
			var stain: MeshInstance3D = _block(props, "OilStain", Vector3(size, 0.003, size * 0.8), oil, at + spread + Vector3(0, 0.0045, 0))
			stain.rotation.y = float(drop) * 1.1 + at.x
	for x: float in TRACKS:
		_floor(room, "Ballast", Vector2(x - 2.2, -44.0), Vector2(x + 2.2, 44.0), 0.006, ballast)
		for side: float in [-1.0, 1.0]:
			# Rail heads polished by use catch the sun along both lines.
			_block(props, "RailHead", Vector3(0.07, 0.01, 80.0), head, Vector3(x + side * 1.05, 0.085, 1.0))
			# Platform coping and a painted safety line along each bed.
			_block(props, "Coping", Vector3(0.35, 0.012, 88.0), coping, Vector3(x + side * 2.38, 0.006, 0.0))
			_block(props, "SafetyLine", Vector3(0.12, 0.008, 88.0), safety, Vector3(x + side * 2.75, 0.006, 0.0))
		var z: float = -43.5
		while z < 43.6:
			if not _under_car(x, z):
				_block(props, "Sleeper", Vector3(2.6, 0.05, 0.24), sleeper, Vector3(x, 0.03, z))
				for side: float in [-1.0, 1.0]:
					_block(props, "TiePlate", Vector3(0.34, 0.02, 0.2), plate, Vector3(x + side * 1.05, 0.065, z))
			z += 0.9
	# Plank foot crossings in the gaps between coupled cars: the walk under the
	# couplings Latch uses to reach each car.
	for crossing: Vector2 in [Vector2(-8.0, -18.0), Vector2(-8.0, 0.0), Vector2(-8.0, 18.5), Vector2(8.0, -12.0), Vector2(8.0, 6.0), Vector2(8.0, 23.0), Vector2(-8.0, -38.0), Vector2(8.0, -38.0)]:
		for index: int in range(6):
			_block(props, "CrossingPlank", Vector3(3.9, 0.04, 0.26), plank, Vector3(crossing.x, 0.035, crossing.y - 0.85 + float(index) * 0.34))
	# Drain grates along the platforms, flush with the slab.
	var grate: StandardMaterial3D = _mat("drain_grate", Color("1c1d1f"), 0.5, 0.6)
	for at: Vector3 in [Vector3(-20, 0, -14), Vector3(-20, 0, 18), Vector3(0, 0, -32), Vector3(0, 0, 12), Vector3(16, 0, -6), Vector3(16, 0, 28), Vector3(-26, 0, -24)]:
		_block(props, "Drain", Vector3(0.6, 0.008, 0.6), grate, at + Vector3(0, 0.004, 0))
	_finish(room)

func _under_car(x: float, z: float) -> bool:
	for car: Array in CARS:
		var low: Vector3 = car[0]
		var high: Vector3 = car[1]
		if x >= low.x and x <= high.x and z > low.z + 0.2 and z < high.z - 0.2:
			return true
	return false

# --- platform one: the painted lane, the baggage carts and what was taken ----

func _build_platform() -> void:
	var room: Node3D = _room("Platform")
	var props: Node3D = _props(room)
	var bone: StandardMaterial3D = _mat("lane_bone", Color("bdb59e"), 0.0, 0.9)
	# A bone processing lane from the dock door to the first car's bay, with
	# standing boxes where people waited in twos.
	_paint_line(props, Vector3(-20.0, 0, -43.6), Vector3(-20.0, 0, -31.5), 0.12, bone)
	_paint_line(props, Vector3(-17.4, 0, -43.6), Vector3(-17.4, 0, -31.5), 0.12, bone)
	_paint_line(props, Vector3(-20.0, 0, -31.5), Vector3(-15.2, 0, -29.6), 0.12, bone)
	_paint_line(props, Vector3(-17.4, 0, -31.5), Vector3(-15.2, 0, -30.6), 0.12, bone)
	for index: int in range(4):
		var z: float = -41.0 + float(index) * 2.4
		_paint_line(props, Vector3(-20.0, 0, z), Vector3(-17.4, 0, z), 0.08, bone)
	# Scattered transfer forms on the platform, ground flat.
	var paper: StandardMaterial3D = _mat("paper", Color("e3dccb"), 0.0, 0.95)
	for index: int in range(9):
		var at: Vector3 = Vector3(-23.0 + float((index * 7) % 9) * 0.9, 0.006, -33.0 + float((index * 5) % 7) * 1.1)
		var sheet: MeshInstance3D = _block(props, "LooseForm", Vector3(0.22, 0.004, 0.3), paper, at)
		sheet.rotation.y = float(index) * 0.7
	# The three cover crates are baggage carts: wheels, a frame and what was
	# taken off people, tagged and stacked on the tops.
	var frame: StandardMaterial3D = _mat("cart_frame", Color("3b3d3a"), 0.4, 0.6)
	var tread: StandardMaterial3D = _mat("cart_wheel", Color("1d1d1e"), 0.1, 0.9)
	var hub: StandardMaterial3D = _mat("wheel_hub", Color("6a6458"), 0.5, 0.5)
	var tag: StandardMaterial3D = _mat("bag_tag", Color("d8d0b8"), 0.0, 0.9)
	var carts: Array = [[Vector3(-2, 0, -28), Vector3(1, 1.2, -26)], [Vector3(-2, 0, 4), Vector3(1, 1.2, 6)], [Vector3(-1, 0, 26), Vector3(2, 1.2, 28)]]
	for cart_index: int in range(carts.size()):
		var low: Vector3 = carts[cart_index][0]
		var high: Vector3 = carts[cart_index][1]
		var centre: Vector3 = (low + high) * 0.5
		var size: Vector3 = high - low
		_block(props, "CartDeck", Vector3(size.x + 0.08, 0.1, size.z + 0.08), frame, Vector3(centre.x, high.y - 0.05, centre.z))
		_block(props, "CartSkirt", Vector3(size.x + 0.04, 0.18, size.z + 0.04), frame, Vector3(centre.x, 0.42, centre.z))
		for wx: float in [low.x + 0.4, high.x - 0.4]:
			for wz: float in [low.z - 0.03, high.z + 0.03]:
				var wheel: MeshInstance3D = _shape.cylinder(props, "CartWheel", 0.2, 0.1, tread, Vector3(wx, 0.2, wz), 10)
				_shape.cylinder(props, "CartHub", 0.07, 0.12, hub, Vector3(wx, 0.2, wz), 6)
				wheel.rotation.y = 0.0
		# Bags and bundles on the top, each with a pale tag.
		for bag: int in range(5):
			var tint: Color = PERSONAL[(bag + cart_index * 3) % PERSONAL.size()]
			var bag_size: Vector3 = Vector3(0.7 - float(bag % 2) * 0.2, 0.32 + float(bag % 3) * 0.08, 0.45)
			var at: Vector3 = Vector3(low.x + 0.5 + float(bag % 3) * 0.95, high.y + bag_size.y * 0.5 + (0.36 if bag >= 3 else 0.0), low.z + 0.6 + float(bag % 2) * 0.8)
			var piece: MeshInstance3D = _block(props, "Bag", bag_size, _mat("bag_%s" % tint.to_html(false), tint.darkened(0.15), 0.0, 0.9), at)
			piece.rotation.y = float(bag - 2) * 0.18
			_block(props, "BagTag", Vector3(0.1, 0.14, 0.02), tag, at + Vector3(bag_size.x * 0.3, 0.0, bag_size.z * 0.5 + 0.02))
	_finish(room)

# --- the coupled recall cars ---------------------------------------------------

func _build_cars() -> void:
	var room: Node3D = _room("Cars")
	var props: Node3D = _props(room)
	var side_paint: StandardMaterial3D = _mat("car_side", Color("5a6450"), 0.2, 0.75)
	var rib: StandardMaterial3D = _mat("car_rib", Color("454e3f"), 0.3, 0.7)
	var door: StandardMaterial3D = _mat("car_door", Color("4f5947"), 0.2, 0.75)
	var under: StandardMaterial3D = _mat("underframe", Color("232322"), 0.4, 0.7)
	var tread: StandardMaterial3D = _mat("wheel_tread", Color("2d2b29"), 0.6, 0.5)
	var hub: StandardMaterial3D = _mat("wheel_hub_rust", Color("2f2925"), 0.3, 0.8)
	var rust: StandardMaterial3D = _mat("rust_streak", Color("54402f"), 0.0, 0.9)
	var plate: StandardMaterial3D = _mat("number_plate", Color("c8c1aa"), 0.0, 0.85)
	var ink: StandardMaterial3D = _mat("plate_ink", Color("2a2a28"), 0.0, 0.9)
	var seal: StandardMaterial3D = _mat("union_seal", Color("8c1a1e"), 0.1, 0.7)
	var walkway: StandardMaterial3D = _mat("walkway_wood", Color("3f362d"), 0.0, 0.95)
	var deck: StandardMaterial3D = _mat("car_deck_wood", Color("4a3e32"), 0.0, 0.95)
	var cage: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	for car_index: int in range(CARS.size()):
		var low: Vector3 = CARS[car_index][0]
		var high: Vector3 = CARS[car_index][1]
		var open_bay: bool = CARS[car_index][2]
		var length: float = high.z - low.z
		var mid_z: float = (low.z + high.z) * 0.5
		# Faces that carry the car's outside skin: an open bay has only its
		# east wall; a closed car has both.
		var faces: Array[float] = [high.x]
		if not open_bay:
			faces.append(low.x)
		for face_x: float in faces:
			var out: float = 1.0 if face_x > (low.x + high.x) * 0.5 else -1.0
			_block(props, "Underframe", Vector3(0.06, 0.7, length - 0.2), under, Vector3(face_x + out * 0.01, 0.35, mid_z))
			_block(props, "CarSide", Vector3(0.04, 2.08, length - 0.12), side_paint, Vector3(face_x + out * 0.02, 1.95, mid_z))
			var ribs: int = int(length / 0.8)
			for index: int in range(1, ribs):
				var z: float = low.z + float(index) * (length / float(ribs))
				if absf(z - mid_z) < 1.5:
					continue
				_block(props, "CarRib", Vector3(0.05, 2.0, 0.08), rib, Vector3(face_x + out * 0.045, 1.95, z))
			_block(props, "CarDoor", Vector3(0.06, 2.0, 2.6), door, Vector3(face_x + out * 0.05, 1.9, mid_z))
			_block(props, "DoorTrack", Vector3(0.08, 0.08, 5.6), under, Vector3(face_x + out * 0.07, 2.95, mid_z))
			_block(props, "DoorTrack", Vector3(0.08, 0.06, 5.6), under, Vector3(face_x + out * 0.07, 0.88, mid_z))
			_block(props, "DoorHasp", Vector3(0.06, 0.24, 0.1), under, Vector3(face_x + out * 0.09, 1.6, mid_z + 1.25))
			_block(props, "DoorSeal", Vector3(0.05, 0.1, 0.1), seal, Vector3(face_x + out * 0.12, 1.45, mid_z + 1.25))
			# A numbered plate in plain bars, never readable words.
			var plate_z: float = low.z + 1.6
			_block(props, "NumberPlate", Vector3(0.03, 0.34, 0.9), plate, Vector3(face_x + out * 0.05, 2.45, plate_z))
			for digit: int in range(4):
				_block(props, "PlateDigit", Vector3(0.02, 0.2, 0.08), ink, Vector3(face_x + out * 0.07, 2.45, plate_z - 0.3 + float(digit) * 0.2))
			for streak: int in range(3):
				var z: float = low.z + 2.3 + float((car_index * 5 + streak * 7) % 9) * 0.9
				_block(props, "RustStreak", Vector3(0.03, 0.9 + float(streak) * 0.3, 0.07), rust, Vector3(face_x + out * 0.05, 2.4 - float(streak) * 0.15, z))
			# Two bogies: four wheels and a side frame each.
			for bogie_z: float in [low.z + 2.1, high.z - 2.1]:
				_block(props, "BogieFrame", Vector3(0.1, 0.3, 2.4), under, Vector3(face_x + out * 0.1, 0.5, bogie_z))
				for offset: float in [-0.8, 0.8]:
					_wheel(props, Vector3(face_x + out * 0.08, 0.42, bogie_z + offset), 0.42, tread, hub)
		# Couplers and a brake wheel on the ends, over corrugated end sheets.
		for end: float in [-1.0, 1.0]:
			var end_z: float = (high.z if end > 0.0 else low.z)
			var width: float = high.x - low.x
			var mid_x: float = (low.x + high.x) * 0.5
			_block(props, "EndSheet", Vector3(width - 0.1, 2.1, 0.04), side_paint, Vector3(mid_x, 1.95, end_z + end * 0.02))
			for y: float in [1.3, 1.95, 2.6]:
				_block(props, "EndCorrugation", Vector3(width - 0.3, 0.12, 0.05), rib, Vector3(mid_x, y, end_z + end * 0.05))
			for x: float in [low.x + 0.08, high.x - 0.08]:
				_block(props, "CornerPost", Vector3(0.14, 2.95, 0.08), under, Vector3(x, 1.48, end_z + end * 0.04))
			_block(props, "EndSill", Vector3(width, 0.25, 0.08), under, Vector3(mid_x, 0.75, end_z + end * 0.04))
			_block(props, "Coupler", Vector3(0.32, 0.3, 0.5), under, Vector3(-8.0 if open_bay else 8.0, 0.8, end_z + end * 0.2))
			_block(props, "Buffer", Vector3(0.24, 0.24, 0.3), under, Vector3((-8.0 if open_bay else 8.0) - 1.4, 0.85, end_z + end * 0.1))
			_block(props, "Buffer", Vector3(0.24, 0.24, 0.3), under, Vector3((-8.0 if open_bay else 8.0) + 1.4, 0.85, end_z + end * 0.1))
		_brake_wheel(props, Vector3(high.x - 1.0, 2.1, high.z + 0.12), Vector3.BACK, under)
		# The roof walkway: boards along the centre, ribs across.
		_block(props, "RoofWalk", Vector3(0.7, 0.012, length - 0.4), walkway, Vector3((low.x + high.x) * 0.5 + (2.0 if open_bay else 0.0), 3.006, mid_z))
		if open_bay:
			# Inside the bay: a plank floor, a restraint rail along the back
			# wall and one cold caged lamp under the roof.
			_block(props, "BayDeck", Vector3(high.x - low.x - 1.0, 0.014, length - 1.0), deck, Vector3(low.x + (high.x - low.x - 1.0) * 0.5, 0.007, mid_z))
			var seams: int = int((high.x - low.x - 1.0) / 0.36)
			for seam: int in range(1, seams):
				_block(props, "DeckSeam", Vector3(0.025, 0.004, length - 1.0), under, Vector3(low.x + float(seam) * 0.36, 0.0155, mid_z))
			_block(props, "RestraintRail", Vector3(0.06, 0.06, length - 1.4), under, Vector3(high.x - 1.04, 1.3, mid_z))
			for ring: int in range(int(length) - 2):
				_shape.cylinder(props, "RestraintRing", 0.08, 0.02, cage, Vector3(high.x - 1.08, 1.2, low.z + 1.5 + float(ring)), 8).rotation.y = PI * 0.5
			_block(props, "BayFascia", Vector3(0.12, 0.3, length), side_paint, Vector3(low.x - 0.04, 2.6, mid_z))
			_block(props, "BayDoorTrack", Vector3(0.08, 0.08, length - 0.4), under, Vector3(low.x + 0.06, 2.42, mid_z))
			_lamp(room, Vector3(-9.5, 2.3, mid_z), COLD, 1.2, 6.0, 2.5)
	# The last car of the consist is chalked 67, with a tally beside it: one
	# more than the schedule board lists.
	_mark(room, "Chalk67", 11, ArenaDecoration.CHALK, Vector2(0.9, 0.6), Vector3(-11.5, 1.5, 14.49), "north")
	var chalk: StandardMaterial3D = _mat("chalk", Color("dcd8cc"), 0.0, 0.95)
	for index: int in range(5):
		var x: float = -9.8 + float(index) * 0.12
		if index == 4:
			var slash: MeshInstance3D = _block(props, "Tally", Vector3(0.6, 0.03, 0.01), chalk, Vector3(-9.6, 1.5, 14.485))
			slash.rotation.z = 0.5
		else:
			_block(props, "Tally", Vector3(0.03, 0.4, 0.01), chalk, Vector3(x, 1.5, 14.485))
	_finish(room)

# --- the departures board ----------------------------------------------------

func _build_board() -> void:
	var room: Node3D = _room("Board")
	var props: Node3D = _props(room)
	var frame: StandardMaterial3D = _mat("board_frame", Color("26272a"), 0.5, 0.5)
	var flap: StandardMaterial3D = _mat("board_flap", Color("1c1d1f"), 0.2, 0.6)
	var bar: StandardMaterial3D = _mat("flap_bar", Color("d9d1b8"), 0.0, 0.8)
	var canopy: StandardMaterial3D = _mat("board_canopy", Color("4a4c48"), 0.4, 0.6)
	# Host: (-27, 0, -36) to (-25, 4, -35.5); the copy faces south.
	var face: float = -35.5
	for side: float in [-1.0, 1.0]:
		_block(props, "BoardFrame", Vector3(0.12, 4.0, 0.08), frame, Vector3(-26.0 + side * 0.98, 2.0, face + 0.03))
	_block(props, "BoardFrame", Vector3(2.08, 0.12, 0.08), frame, Vector3(-26.0, 3.94, face + 0.03))
	_block(props, "BoardFrame", Vector3(2.08, 0.16, 0.08), frame, Vector3(-26.0, 0.08, face + 0.03))
	_block(props, "BoardCanopy", Vector3(2.8, 0.12, 1.4), canopy, Vector3(-26.0, 4.2, -35.6))
	# A station clock on the canopy.
	var clock: MeshInstance3D = _shape.cylinder(props, "ClockFace", 0.32, 0.08, _mat("clock_face", Color("e3dccb"), 0.0, 0.8), Vector3(-26.0, 4.7, -35.4), 16)
	clock.rotation.x = 0.0
	_shape.cylinder(props, "ClockRim", 0.36, 0.06, frame, Vector3(-26.0, 4.7, -35.44), 16)
	_block(props, "ClockHand", Vector3(0.03, 0.24, 0.01), frame, Vector3(-26.0, 4.79, -35.35))
	var minute: MeshInstance3D = _block(props, "ClockHand", Vector3(0.025, 0.3, 0.01), frame, Vector3(-25.92, 4.68, -35.35))
	minute.rotation.z = -2.1
	# The back carries rows of blank flaps, the same clacking machine.
	for row: int in range(9):
		var y: float = 0.5 + float(row) * 0.38
		_block(props, "Flap", Vector3(1.8, 0.3, 0.03), flap, Vector3(-26.0, y, -36.02))
		for cell: int in range(6):
			if (row * 5 + cell * 3) % 7 == 0:
				continue
			_block(props, "FlapBar", Vector3(0.18, 0.05, 0.01), bar, Vector3(-26.75 + float(cell) * 0.3, y, -36.04))
	_finish(room)

# --- the dispatcher's office ----------------------------------------------------

func _build_office() -> void:
	var room: Node3D = _room("Office")
	var props: Node3D = _props(room)
	var roof: StandardMaterial3D = _mat("office_roof", Color("4a4b47"), 0.3, 0.8)
	var glass: StandardMaterial3D = _mat("window_glass", Color("2a3335"), 0.1, 0.7)
	var sill: StandardMaterial3D = _mat("window_sill", Color("3d3f3c"), 0.3, 0.7)
	# Office walls: x 19 to 28, z -34 to -23, three metres, door gap on the
	# south. A flat roof with a short overhang shades the door.
	_block(props, "OfficeRoof", Vector3(9.6, 0.18, 11.8), roof, Vector3(23.5, 3.09, -28.3))
	_block(props, "RoofEdge", Vector3(9.8, 0.24, 0.12), sill, Vector3(23.5, 3.08, -22.4))
	# Windows on the west and east walls, both faces.
	for z: float in [-31.0, -26.0]:
		for x: float in [18.97, 19.53, 27.47, 28.03]:
			_block(props, "OfficeWindow", Vector3(0.02, 1.0, 1.6), glass, Vector3(x, 1.7, z))
		for x: float in [18.94, 28.06]:
			_block(props, "WindowSill", Vector3(0.1, 0.06, 1.8), sill, Vector3(x, 1.17, z))
	# The desk: timetable, papers, a telephone, a mug and a lamp.
	_papers(props, Vector3(24.25, 0.8, -29.6), 4, 3)
	_mug(props, Vector3(25.6, 0.8, -27.6), Color("c49a3c"))
	var phone: StandardMaterial3D = _mat("phone", Color("1e1f20"), 0.2, 0.5)
	_block(props, "Telephone", Vector3(0.24, 0.1, 0.2), phone, Vector3(25.5, 0.85, -29.3))
	_block(props, "Handset", Vector3(0.26, 0.05, 0.07), phone, Vector3(25.5, 0.93, -29.3))
	var stamp: StandardMaterial3D = _mat("stamp", Color("2c2d32"), 0.3, 0.6)
	_shape.cylinder(props, "Stamp", 0.04, 0.12, stamp, Vector3(24.6, 0.86, -27.6), 8).rotation.x = PI * 0.5
	_block(props, "StampPad", Vector3(0.14, 0.02, 0.1), _mat("stamp_pad", Color("8c1a1e"), 0.0, 0.9), Vector3(24.85, 0.81, -27.5))
	var arm: StandardMaterial3D = _mat("desk_lamp", Color("3d4441"), 0.35, 0.6)
	_shape.rod(props, "DeskLampArm", Vector3(24.3, 0.8, -27.3), Vector3(24.4, 1.2, -27.5), 0.012, arm, 6)
	_shape.cylinder(props, "DeskLampShade", 0.09, 0.14, _mat("desk_lamp_shade", Color("4e5844"), 0.2, 0.7), Vector3(24.55, 1.22, -27.75), 10).rotation.x = PI * 0.5
	var desk_light: OmniLight3D = _omni(room, "DeskLamp", Vector3(24.6, 1.05, -27.9), ArenaSky.SERVICE_LAMP_COLOR, 1.2, 3.6)
	desk_light.omni_attenuation = 1.8
	# Clipboards of manifests on the north wall, a key board and a wall clock.
	var board: StandardMaterial3D = _mat("clipboard", Color("6b5843"), 0.0, 0.9)
	var paper: StandardMaterial3D = _mat("paper", Color("e3dccb"), 0.0, 0.95)
	for index: int in range(5):
		var x: float = 20.4 + float(index) * 0.55
		_block(props, "Clipboard", Vector3(0.36, 0.48, 0.02), board, Vector3(x, 1.75, -33.48))
		_block(props, "Manifest", Vector3(0.3, 0.4, 0.01), paper, Vector3(x, 1.72, -33.465))
	_block(props, "KeyBoard", Vector3(0.02, 0.6, 0.9), board, Vector3(27.48, 1.6, -31.5))
	for hook: int in range(6):
		_block(props, "Key", Vector3(0.02, 0.1, 0.03), _mat("brass", Color("a8873e"), 0.6, 0.4), Vector3(27.46, 1.55 + float(hook % 2) * 0.2, -31.8 + float(hook / 2) * 0.3))
	_lamp(room, Vector3(23.5, 2.75, -28.5), ArenaSky.SERVICE_LAMP_COLOR, 1.4, 6.5, 3.0)
	_finish(room)

# --- the brakemen's hut ------------------------------------------------------

func _build_hut() -> void:
	var room: Node3D = _room("Hut")
	var props: Node3D = _props(room)
	var roof: StandardMaterial3D = _mat("hut_roof", Color("4f4237"), 0.0, 0.95)
	var trim: StandardMaterial3D = _mat("hut_trim_wood", Color("6b5843"), 0.0, 0.9)
	var iron: StandardMaterial3D = _mat("stove_iron", Color("242322"), 0.5, 0.6)
	var glass: StandardMaterial3D = _mat("window_glass", Color("2a3335"), 0.1, 0.7)
	# Hut walls: x -28 to -18, z 0 to 12, door gap on the east (z 4 to 7).
	# A tarred roof with an overhang over the door.
	_block(props, "HutRoof", Vector3(10.8, 0.2, 12.8), roof, Vector3(-23.0, 3.1, 6.0))
	_block(props, "PorchRoof", Vector3(1.6, 0.12, 4.2), roof, Vector3(-17.1, 2.85, 5.5))
	for z: float in [3.6, 7.4]:
		_block(props, "PorchBracket", Vector3(0.9, 0.08, 0.08), trim, Vector3(-17.6, 2.7, z))
	# The brakemen clad their hut themselves: faded blue weatherboards
	# outside, bare timber inside. Never the issued enamel of the office.
	var board_out: StandardMaterial3D = _mat("hut_board_wood", Color("5d6c72"), 0.0, 0.9)
	var board_alt: StandardMaterial3D = _mat("hut_board_alt_wood", Color("53626a"), 0.0, 0.9)
	var board_in: StandardMaterial3D = _mat("hut_lining_wood", Color("6b5843"), 0.0, 0.9)
	# [fixed axis value, along-axis low, along-axis high, normal]; x faces run along z.
	var faces: Array = [
		[-28.0, 0.0, 12.0, Vector3.LEFT, false], [-18.0, 0.0, 4.0, Vector3.RIGHT, false], [-18.0, 7.0, 12.0, Vector3.RIGHT, false],
		[0.0, -28.0, -18.0, Vector3.FORWARD, false], [12.0, -28.0, -18.0, Vector3.BACK, false],
		[-27.5, 0.5, 11.5, Vector3.RIGHT, true], [11.5, -27.5, -18.5, Vector3.FORWARD, true],
		[-18.5, 0.5, 4.0, Vector3.LEFT, true], [-18.5, 7.0, 11.5, Vector3.LEFT, true],
	]
	for entry: Array in faces:
		var fixed: float = entry[0]
		var low: float = entry[1]
		var high: float = entry[2]
		var normal: Vector3 = entry[3]
		var inside: bool = entry[4]
		var length: float = high - low
		for row: int in range(10):
			var y: float = 0.16 + float(row) * 0.29
			var finish: StandardMaterial3D = board_in if inside else (board_alt if row % 3 == 1 else board_out)
			if absf(normal.x) > 0.5:
				_block(props, "Weatherboard", Vector3(0.03, 0.27, length), finish, Vector3(fixed + normal.x * 0.016, y, (low + high) * 0.5))
			else:
				_block(props, "Weatherboard", Vector3(length, 0.27, 0.03), finish, Vector3((low + high) * 0.5, y, fixed + normal.z * 0.016))
	# Windows in the west and south walls, both faces, in timber frames.
	for pair: Vector2 in [Vector2(-28.04, -28.07), Vector2(-27.46, -27.43)]:
		_block(props, "WindowFrame", Vector3(0.04, 1.16, 1.76), trim, Vector3(pair.x, 1.7, 6.0))
		_block(props, "HutWindow", Vector3(0.02, 1.0, 1.6), glass, Vector3(pair.y, 1.7, 6.0))
	for pair: Vector2 in [Vector2(-0.04, -0.07), Vector2(0.54, 0.57)]:
		_block(props, "WindowFrame", Vector3(1.76, 1.16, 0.04), trim, Vector3(-23.0, 1.7, pair.x))
		_block(props, "HutWindow", Vector3(1.6, 1.0, 0.02), glass, Vector3(-23.0, 1.7, pair.y))
	# The stove (-26..-24, 8.5..10.5, 1.4 high): a kettle still on it, a pipe
	# through the roof and a warm glow at the door.
	_shape.cylinder(props, "StovePipe", 0.12, 3.6, iron, Vector3(-25.5, 3.2, 10.0), 8).rotation.x = PI * 0.5
	_block(props, "PipeCap", Vector3(0.4, 0.06, 0.4), iron, Vector3(-25.5, 5.05, 10.0))
	var kettle: MeshInstance3D = _shape.lathe(props, "Kettle", PackedVector2Array([Vector2(-0.12, 0.0), Vector2(-0.12, 0.12), Vector2(0.0, 0.14), Vector2(0.1, 0.11), Vector2(0.14, 0.04), Vector2(0.14, 0.0)]), _mat("kettle", Color("7b6a4f"), 0.6, 0.4), Vector3(-24.6, 1.4 + 0.12, 9.2), 12)
	kettle.rotation.x = -PI * 0.5
	_shape.rod(props, "KettleSpout", Vector3(-24.5, 1.47, 9.2), Vector3(-24.3, 1.57, 9.2), 0.02, _mat("kettle", Color("7b6a4f"), 0.6, 0.4), 6)
	# Black iron over the stove's body: side sheets, a hob plate and feet.
	_block(props, "StoveHob", Vector3(2.04, 0.05, 2.04), iron, Vector3(-25.0, 1.405, 9.5))
	_block(props, "StoveSheet", Vector3(0.03, 1.2, 1.96), iron, Vector3(-23.985, 0.75, 9.5))
	_block(props, "StoveSheet", Vector3(1.96, 1.2, 0.03), iron, Vector3(-25.0, 0.75, 8.485))
	_block(props, "StoveSheet", Vector3(1.96, 1.2, 0.03), iron, Vector3(-25.0, 0.75, 10.515))
	_block(props, "StoveRail", Vector3(0.04, 0.04, 2.0), _mat("brass", Color("a8873e"), 0.6, 0.4), Vector3(-23.94, 1.25, 9.5))
	_block(props, "StoveDoor", Vector3(0.03, 0.42, 0.5), _mat("stove_door", Color("3a3631"), 0.5, 0.5), Vector3(-23.96, 0.55, 9.5))
	_block(props, "StoveEmbers", Vector3(0.02, 0.1, 0.4), _glow("embers", Color("c45a20"), 2.2), Vector3(-23.96, 0.38, 9.5))
	_mark(room, "StoveSix", 10, ArenaDecoration.SPRAY, Vector2(0.3, 0.3), Vector3(-23.955, 0.6, 9.5), "east")
	var glow: OmniLight3D = _omni(room, "StoveGlow", Vector3(-23.5, 0.5, 9.5), Color(1.0, 0.62, 0.32), 1.2, 3.2)
	glow.omni_attenuation = 1.9
	# The table: three mismatched mugs, a hand of cards and a lunch tin.
	_mug(props, Vector3(-24.4, 0.8, 3.5), Color("b5652e"))
	_mug(props, Vector3(-23.2, 0.8, 4.4), Color("4f6f8a"))
	_mug(props, Vector3(-22.6, 0.8, 3.4), Color("6f8a4e"))
	var card: StandardMaterial3D = _mat("card", Color("e8e2d6"), 0.0, 0.9)
	for index: int in range(5):
		var piece: MeshInstance3D = _block(props, "Card", Vector3(0.07, 0.004, 0.1), card, Vector3(-23.9 + float(index) * 0.09, 0.803, 4.2))
		piece.rotation.y = float(index - 2) * 0.25
	_block(props, "LunchTin", Vector3(0.3, 0.12, 0.2), _mat("tin", Color("6a6458"), 0.5, 0.5), Vector3(-22.6, 0.86, 4.5))
	# Coats on hooks by the door, each one somebody's own colour.
	for index: int in range(3):
		var tint: Color = PERSONAL[(index * 2 + 1) % PERSONAL.size()].darkened(0.2)
		_block(props, "Coat", Vector3(0.5, 0.9, 0.16), _mat("coat_%s" % tint.to_html(false), tint, 0.0, 0.95), Vector3(-19.2 - float(index) * 0.6, 1.55, 11.38))
		_block(props, "CoatHook", Vector3(0.04, 0.04, 0.12), iron, Vector3(-19.2 - float(index) * 0.6, 2.05, 11.44))
	# The brakemen's mark over the window: a brake wheel on the wall.
	_brake_wheel(props, Vector3(-27.38, 2.55, 6.0), Vector3.RIGHT, trim)
	_lamp(room, Vector3(-23.5, 2.7, 4.5), ArenaSky.SERVICE_LAMP_COLOR, 1.6, 6.5, 3.0)
	_lamp(room, Vector3(-17.5, 2.6, 5.5), ArenaSky.SERVICE_LAMP_COLOR, 0.9, 4.0)
	_finish(room)

# --- the jamming mast ----------------------------------------------------------

func _build_mast() -> void:
	var room: Node3D = _room("Mast")
	var props: Node3D = _props(room)
	var red: StandardMaterial3D = _mat("mast_red", MAST_RED, 0.3, 0.6)
	var white: StandardMaterial3D = _mat("mast_bone", BONE, 0.2, 0.7)
	var steel: StandardMaterial3D = _mat("mast_steel", Color("3a3836"), 0.5, 0.5)
	var beacon: StandardMaterial3D = _glow("mast_beacon", Color("e23430"), 2.4)
	var cable: StandardMaterial3D = _mat("cable", Color("1b1b1d"), 0.0, 0.7)
	if _mast_down:
		_build_fallen_mast(props, red, white, steel, cable)
		_finish(room)
		return
	# The column (21.5..22.5, 2.5..7, 16.5..17.5) carries lattice faces; above
	# the pod (7..8) the tower tapers to a whip and a beacon, red and bone
	# banded so it reads from every point in the yard.
	var centre: Vector3 = Vector3(22.0, 0, 17.0)
	for level: int in range(3):
		var y0: float = 2.5 + float(level) * 1.5
		for side: int in range(4):
			var angle: float = TAU * float(side) / 4.0
			var normal: Vector3 = Vector3(cos(angle), 0, sin(angle))
			var across: Vector3 = normal.cross(Vector3.UP)
			var face: Vector3 = centre + normal * 0.52
			_shape.rod(props, "ColumnBrace", face + across * 0.48 + Vector3(0, y0, 0), face - across * 0.48 + Vector3(0, y0 + 1.5, 0), 0.03, red if level % 2 == 0 else white, 4)
			_shape.rod(props, "ColumnBrace", face - across * 0.48 + Vector3(0, y0, 0), face + across * 0.48 + Vector3(0, y0 + 1.5, 0), 0.03, red if level % 2 == 0 else white, 4)
	var top: float = 15.5
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var sections: int = 5
	for section: int in range(sections):
		var y0: float = 8.0 + float(section) * (top - 8.0) / float(sections)
		var y1: float = 8.0 + float(section + 1) * (top - 8.0) / float(sections)
		var w0: float = lerpf(0.7, 0.32, float(section) / float(sections))
		var w1: float = lerpf(0.7, 0.32, float(section + 1) / float(sections))
		var paint: StandardMaterial3D = red if section % 2 == 0 else white
		for index: int in range(4):
			var c: Vector2 = corners[index]
			var n: Vector2 = corners[(index + 1) % 4]
			var a0: Vector3 = centre + Vector3(c.x * w0, y0, c.y * w0)
			var a1: Vector3 = centre + Vector3(c.x * w1, y1, c.y * w1)
			var b0: Vector3 = centre + Vector3(n.x * w0, y0, n.y * w0)
			var b1: Vector3 = centre + Vector3(n.x * w1, y1, n.y * w1)
			_shape.rod(props, "MastLeg", a0, a1, 0.06, paint, 5)
			_shape.rod(props, "MastBrace", a0, b1, 0.025, paint, 4)
			_shape.rod(props, "MastBrace", b0, a1, 0.025, paint, 4)
			_shape.rod(props, "MastRing", a1, b1, 0.03, paint, 4)
	# Two jamming dishes aimed down over the yard, and the whip and beacon.
	for dish: Array in [[Vector3(22.0, 11.2, 16.0), Vector3(-0.6, -0.35, -1.0)], [Vector3(21.2, 12.8, 17.4), Vector3(-1.0, -0.25, 0.2)]]:
		var at: Vector3 = dish[0]
		var aim: Vector3 = (dish[1] as Vector3).normalized()
		var bowl: MeshInstance3D = _shape.lathe(props, "JamDish", PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.08, 0.35), Vector2(0.2, 0.7), Vector2(0.24, 0.72), Vector2(0.12, 0.35), Vector2(0.04, 0.0)]), white, at + aim * 0.3, 14)
		bowl.basis = Basis(Quaternion(Vector3.BACK, -aim))
		_shape.rod(props, "DishArm", at - aim * 0.2, at + aim * 0.3, 0.05, steel, 6)
		_shape.rod(props, "DishFeed", at + aim * 0.3, at + aim * 0.95, 0.025, steel, 4)
	_shape.rod(props, "Whip", centre + Vector3(0, top, 0), centre + Vector3(0, top + 3.5, 0), 0.04, steel, 5)
	_shape.cylinder(props, "Beacon", 0.14, 0.24, beacon, centre + Vector3(0, top + 3.6, 0), 10).rotation.x = PI * 0.5
	# A feeder cable down the column face from the pod.
	_shape.pipe(props, "PodFeeder", PackedVector3Array([Vector3(22.55, 7.0, 17.3), Vector3(22.58, 5.0, 17.3), Vector3(22.58, 2.62, 17.3), Vector3(23.4, 2.53, 17.6)]), 0.04, cable)
	_finish(room)

## Fallen across the signal box: the column (19..25, 3.5..4.5, 19.25..20.25)
## and the pod (24.2..25.8, 3.5..5.1, 21.2..22.8). Every piece stays on
## those fallen bodies.
func _build_fallen_mast(props: Node3D, red: StandardMaterial3D, white: StandardMaterial3D, steel: StandardMaterial3D, cable: StandardMaterial3D) -> void:
	for index: int in range(4):
		var x0: float = 19.1 + float(index) * 1.45
		var paint: StandardMaterial3D = red if index % 2 == 0 else white
		for side: float in [-1.0, 1.0]:
			_shape.rod(props, "FallenBrace", Vector3(x0, 3.5, 19.75 + side * 0.52), Vector3(x0 + 1.45, 4.5, 19.75 + side * 0.52), 0.03, paint, 4)
			_shape.rod(props, "FallenBrace", Vector3(x0, 4.5, 19.75 + side * 0.52), Vector3(x0 + 1.45, 3.5, 19.75 + side * 0.52), 0.03, paint, 4)
	# The snapped upper lattice bent back over the pod, and a torn dish.
	_shape.rod(props, "SnappedLeg", Vector3(24.4, 5.1, 21.4), Vector3(25.2, 6.0, 21.8), 0.06, red, 5)
	_shape.rod(props, "SnappedLeg", Vector3(25.6, 5.1, 22.6), Vector3(25.4, 5.9, 22.1), 0.06, white, 5)
	_shape.rod(props, "SnappedBrace", Vector3(25.2, 6.0, 21.8), Vector3(25.4, 5.9, 22.1), 0.03, red, 4)
	var bowl: MeshInstance3D = _shape.lathe(props, "TornDish", PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.08, 0.35), Vector2(0.2, 0.62), Vector2(0.12, 0.35), Vector2(0.04, 0.0)]), white, Vector3(25.0, 5.2, 22.0), 12)
	bowl.basis = Basis(Quaternion(Vector3.BACK, Vector3(0.4, 0.8, -0.3).normalized()))
	_shape.pipe(props, "DeadFeeder", PackedVector3Array([Vector3(24.3, 4.0, 21.3), Vector3(23.6, 3.7, 21.0), Vector3(23.2, 3.52, 20.4)]), 0.04, cable)
	_shape.rod(props, "BentWhip", Vector3(19.1, 4.0, 19.75), Vector3(19.05, 3.56, 20.6), 0.04, steel, 5)

# --- the signal box under the mast ------------------------------------------

func _build_signal_box() -> void:
	var room: Node3D = _room("SignalBox")
	var props: Node3D = _props(room)
	var glass: StandardMaterial3D = _mat("signal_glass", Color("232b2d"), 0.1, 0.7)
	var lit: StandardMaterial3D = _glow("signal_glass_lit", Color("4a3f2c"), 0.5)
	var frame: StandardMaterial3D = _mat("signal_frame", Color("3b3128"), 0.0, 0.85)
	var lever: StandardMaterial3D = _mat("signal_lever", Color("1e1f20"), 0.3, 0.6)
	var lever_top: StandardMaterial3D = _mat("signal_lever_top", Color("a8873e"), 0.6, 0.4)
	var fascia: StandardMaterial3D = _mat("signal_fascia", Color("3f4b41"), 0.1, 0.8)
	var safety: StandardMaterial3D = _mat("hazard_ochre", OCHRE, 0.0, 0.85)
	# The platform's north end (z 19..23, under the box slab) is the signal
	# box itself: framed windows on its north and east faces with the dark
	# lever frame and its polished handles behind the glass.
	for index: int in range(4):
		var x: float = 19.4 + float(index) * 2.0
		_block(props, "BoxWindowFrame", Vector3(1.76, 1.16, 0.04), frame, Vector3(x, 1.65, 23.02))
		_block(props, "BoxWindow", Vector3(1.6, 1.0, 0.02), lit if index == 1 else glass, Vector3(x, 1.65, 23.05))
		_block(props, "BoxMullion", Vector3(0.06, 1.0, 0.03), frame, Vector3(x, 1.65, 23.07))
		for bar: int in range(3):
			_block(props, "Lever", Vector3(0.05, 0.55, 0.01), lever, Vector3(x - 0.5 + float(bar) * 0.5, 1.42, 23.065))
			_block(props, "LeverHandle", Vector3(0.09, 0.06, 0.012), lever_top, Vector3(x - 0.5 + float(bar) * 0.5, 1.72, 23.066))
	for index: int in range(2):
		var z: float = 20.0 + float(index) * 2.0
		_block(props, "BoxWindowFrame", Vector3(0.04, 1.16, 1.76), frame, Vector3(27.02, 1.65, z))
		_block(props, "BoxWindow", Vector3(0.02, 1.0, 1.6), glass, Vector3(27.05, 1.65, z))
	# The box roof slab (2.5..3.5) is a fascia band with a gutter.
	for z: float in [18.98, 23.02]:
		_block(props, "Fascia", Vector3(7.0, 0.5, 0.04), fascia, Vector3(22.5, 3.15, z))
	_block(props, "Gutter", Vector3(7.2, 0.1, 0.14), lever, Vector3(22.5, 3.42, 23.1))
	# Ochre edge paint on the platform top, a door and a short pipe run.
	for edge: Array in [[Vector3(18.1, 2.5, 11.2), Vector3(26.9, 2.5, 11.2)], [Vector3(26.85, 2.5, 11.2), Vector3(26.85, 2.5, 18.9)], [Vector3(18.15, 2.5, 11.2), Vector3(18.15, 2.5, 14.9)]]:
		_paint_line(props, edge[0], edge[1], 0.14, safety)
	_block(props, "BoxDoor", Vector3(0.04, 2.0, 1.0), frame, Vector3(27.02, 1.0, 13.0))
	_block(props, "DoorStep", Vector3(0.3, 0.04, 1.2), lever, Vector3(27.15, 0.02, 13.0))
	_omni(room, "BoxLamp", Vector3(23.5, 1.7, 23.6), ArenaSky.SERVICE_LAMP_COLOR, 0.8, 3.5)
	# The six on the back steps: the signal roof's secret.
	_mark(room, "BackSix", 10, ArenaDecoration.SPRAY, Vector2(0.5, 0.5), Vector3(16.99, 1.8, 19.5), "west")
	_finish(room)

# --- the loading gantry over the east line ----------------------------------

func _build_gantry() -> void:
	var room: Node3D = _room("Gantry")
	var props: Node3D = _props(room)
	var steel: StandardMaterial3D = _mat("gantry_steel", Color("58584f"), 0.4, 0.6)
	var safety: StandardMaterial3D = _mat("hazard_ochre", OCHRE, 0.0, 0.85)
	var chain: StandardMaterial3D = _mat("chain", Color("2b2a28"), 0.6, 0.5)
	# Platform 5..11, 2.5..3, 25..31 on two legs. A hoist beam rides above it
	# on four posts at the platform corners, clear of the walking deck.
	for x: float in [5.15, 10.85]:
		for z: float in [25.15, 30.85]:
			_block(props, "HoistPost", Vector3(0.2, 3.3, 0.2), steel, Vector3(x, 4.65, z))
	for z: float in [25.15, 30.85]:
		_block(props, "HoistBeam", Vector3(6.2, 0.3, 0.24), steel, Vector3(8.0, 6.35, z))
	_block(props, "HoistRail", Vector3(0.3, 0.26, 6.0), steel, Vector3(8.0, 6.35, 28.0))
	_block(props, "Trolley", Vector3(0.6, 0.4, 0.8), _mat("trolley", Color("8a7442"), 0.3, 0.6), Vector3(8.0, 6.0, 27.0))
	_shape.rod(props, "HoistChain", Vector3(8.0, 5.8, 27.0), Vector3(8.0, 5.0, 27.0), 0.025, chain, 4)
	_block(props, "Hook", Vector3(0.12, 0.25, 0.06), chain, Vector3(8.0, 4.9, 27.0))
	for edge: Array in [[Vector3(5.1, 3.0, 31.0), Vector3(10.9, 3.0, 31.0)], [Vector3(5.1, 3.0, 25.0), Vector3(5.1, 3.0, 31.0)], [Vector3(10.9, 3.0, 25.0), Vector3(10.9, 3.0, 31.0)]]:
		_paint_line(props, edge[0], edge[1], 0.14, safety)
	_lamp(room, Vector3(8.0, 5.9, 29.5), COLD, 1.0, 6.0, 6.2)
	_finish(room)

# --- the locomotive ------------------------------------------------------------

func _build_locomotive() -> void:
	var room: Node3D = _room("Locomotive")
	var props: Node3D = _props(room)
	var hood: StandardMaterial3D = _mat("loco_hood", Color("4f5947"), 0.3, 0.7)
	var louvre: StandardMaterial3D = _mat("loco_louvre", Color("2a2d29"), 0.4, 0.6)
	var under: StandardMaterial3D = _mat("underframe", Color("232322"), 0.4, 0.7)
	var tread: StandardMaterial3D = _mat("wheel_tread", Color("2d2b29"), 0.6, 0.5)
	var hub: StandardMaterial3D = _mat("wheel_hub_rust", Color("2f2925"), 0.3, 0.8)
	var rail: StandardMaterial3D = _mat("handrail", Color("c8c1aa"), 0.3, 0.6)
	var glass: StandardMaterial3D = _mat("cab_glass", Color("232b2d"), 0.1, 0.7)
	var safety: StandardMaterial3D = _mat("hazard_ochre", OCHRE, 0.0, 0.85)
	var lens: StandardMaterial3D = _glow("headlamp", Color("ffe6b8"), 2.0)
	# Body -11..-5, 0..2.2, 29..38; cab 2.2..4.2 over 34..38; nose 38..40.
	for face_x: float in [-11.0, -5.0]:
		var out: float = -1.0 if face_x < -8.0 else 1.0
		_block(props, "LocoSkirt", Vector3(0.06, 0.75, 8.8), under, Vector3(face_x + out * 0.02, 0.375, 33.5))
		_block(props, "LocoSill", Vector3(0.12, 0.1, 9.0), under, Vector3(face_x + out * 0.05, 0.8, 33.5))
		# Two three-axle bogies, the wheels mostly behind their side frames.
		for bogie_z: float in [31.0, 36.2]:
			_block(props, "BogieFrame", Vector3(0.12, 0.36, 2.6), under, Vector3(face_x + out * 0.12, 0.42, bogie_z))
			for offset: float in [-0.85, 0.0, 0.85]:
				_wheel(props, Vector3(face_x + out * 0.07, 0.34, bogie_z + offset), 0.34, tread, hub)
			_block(props, "AxleBox", Vector3(0.1, 0.18, 0.22), louvre, Vector3(face_x + out * 0.19, 0.42, bogie_z - 0.85))
			_block(props, "AxleBox", Vector3(0.1, 0.18, 0.22), louvre, Vector3(face_x + out * 0.19, 0.42, bogie_z + 0.85))
		# Engine-room grilles: framed banks of thin horizontal slats.
		for bank: int in range(2):
			var z0: float = 29.6 + float(bank) * 2.3
			_block(props, "GrilleFrame", Vector3(0.04, 0.9, 1.9), louvre, Vector3(face_x + out * 0.02, 1.45, z0 + 0.95))
			for slat: int in range(7):
				_block(props, "GrilleSlat", Vector3(0.05, 0.05, 1.76), hood, Vector3(face_x + out * 0.045, 1.07 + float(slat) * 0.125, z0 + 0.95))
		_shape.rod(props, "Handrail", Vector3(face_x + out * 0.15, 1.9, 29.4), Vector3(face_x + out * 0.15, 1.9, 33.8), 0.025, rail, 5)
		for index: int in range(2):
			_block(props, "CabWindow", Vector3(0.03, 0.8, 1.4), glass, Vector3(face_x + out * 0.02, 3.3, 35.0 + float(index) * 1.9))
	# Cab front windows, warm inside: the driver's place you will take.
	for x: float in [-9.6, -6.4]:
		_block(props, "CabFront", Vector3(1.8, 0.8, 0.03), _glow("cab_lit", Color("b9a77e"), 0.45), Vector3(x, 3.3, 38.02))
	_omni(room, "CabLamp", Vector3(-8.0, 3.5, 36.0), ArenaSky.SERVICE_LAMP_COLOR, 1.0, 4.0)
	# Nose: headlamp pair, buffer beam with chevrons, and the horn on the cab.
	for x: float in [-9.2, -6.8]:
		_shape.cylinder(props, "Headlamp", 0.16, 0.12, lens, Vector3(x, 1.6, 40.06), 12)
		_shape.cylinder(props, "HeadlampRim", 0.2, 0.08, under, Vector3(x, 1.6, 40.02), 12)
	_block(props, "BufferBeam", Vector3(4.4, 0.45, 0.1), under, Vector3(-8.0, 0.55, 40.05))
	for index: int in range(7):
		var stripe: MeshInstance3D = _block(props, "BeamChevron", Vector3(0.22, 0.4, 0.02), safety, Vector3(-9.8 + float(index) * 0.6, 0.55, 40.11))
		stripe.rotation.z = 0.6
	_shape.cylinder(props, "Exhaust", 0.18, 0.5, louvre, Vector3(-8.0, 2.45, 31.0), 8).rotation.x = PI * 0.5
	_shape.cylinder(props, "Horn", 0.08, 0.4, rail, Vector3(-8.0, 4.32, 36.5), 8)
	_block(props, "HoodTop", Vector3(5.6, 0.04, 4.6), hood, Vector3(-8.0, 2.22, 31.4))
	_finish(room)
