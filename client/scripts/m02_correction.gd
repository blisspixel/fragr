class_name M02Correction
extends Node3D

## Persons Unknown's golden-slice dressing (docs/campaign/m02-persons-unknown.md,
## docs/design/earth.md "M02 correction"). The server owns every solid; this
## presenter only furnishes them: wall fittings, flush paint, small possessions
## on existing tops, overhead runs above head height and practical light. A
## body that could stop a pawn or a shot is never added here.
##
## The story is told without words. Watchers left their coffee on the gallery
## sill; two guards were playing cards. The antechamber issues the plates and
## smocks that replace a person's own paint, and keeps what it cut off in a
## tagged tray. A painted lane leads every captive to the frame, where one hard
## pool of light holds Latch. On the processing floor personal panels go in at
## one end of the line and issued black plate comes out the other. The dock's
## daylight under the yard door is the way out.

const Geometry = preload("res://scripts/model_geometry.gd")
const MAP_ID: int = 1002
const DAYLIGHT: Color = Color(0.86, 0.9, 0.9)
const OCHRE: Color = Color("8a7442")
## Issued cold fluorescent, the same white as the ceiling strips: neutral
## enough that it never reads as Inheritance cyan.
const BATTEN_COLOR: Color = Color(0.86, 0.92, 0.9)
## Personal paint the Union strips off: warm, varied, never black-and-red.
const PERSONAL: Array[Color] = [Color("b5652e"), Color("6f8a4e"), Color("c49a3c"), Color("8a3a58"), Color("4f6f8a"), Color("a8552c"), Color("7c5a8c")]

var _shape: RefCounted = Geometry.new()
var _unattached: Array[Node3D] = []
## Rooms built for the current map, and the presenter lamps they carry.
var rooms: Array[String] = []
var lamps: int = 0

func clear_map() -> void:
	rooms.clear()
	lamps = 0
	for room: Node3D in _unattached:
		room.free()
	_unattached.clear()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

func active() -> bool:
	return not rooms.is_empty()

## Persons Unknown's own authored layout only. A custom map reusing the id with
## different furniture gets no dressing rather than floating props.
static func authored(info: Dictionary) -> bool:
	if int(info.get("map_id", -1)) != MAP_ID or not info.get("solids") is Array:
		return false
	var wanted: Array = [
		[Vector3(-5.5, 3.68, -32), Vector3(-4.7, 3.78, -29.5)],
		[Vector3(-4, 0, -15), Vector3(0, 3.2, -13)],
		[Vector3(8, 0, -13), Vector3(9, 2.6, -9)],
		[Vector3(-4, 0, 3), Vector3(-1, 2.2, 6)],
		[Vector3(-5, 0, 19), Vector3(-3, 1.4, 21)],
		[Vector3(-7, 0, 24), Vector3(7, 7, 25)],
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

func configure_map(info: Dictionary) -> void:
	if active() and authored(info):
		return
	clear_map()
	if not authored(info):
		return
	_build_gallery()
	_build_stair()
	_build_service()
	_build_antechamber()
	_build_ward()
	_build_floor()
	_build_side_ward()
	_build_dock()
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
	return _shape.material("m02_" + key, tint, metallic, roughness)

func _glow(key: String, tint: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = _mat(key, tint)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	return material

func _block(props: Node3D, label: String, size: Vector3, finish: StandardMaterial3D, at: Vector3) -> MeshInstance3D:
	return _shape.block(props, label, size, finish, at)

## A picture on a face, named as MapDecoration names faces: west faces -X,
## east +X, north -Z, south +Z, up +Y.
func _picture(parent: Node3D, label: String, image: Texture2D, size: Vector2, at: Vector3, face: String, glow: float = 0.0) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	node.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = image
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	if glow > 0.0:
		material.emission_enabled = true
		material.emission_texture = image
		material.emission_energy_multiplier = glow
	node.material_override = material
	node.transform = Transform3D(MapDecoration.face_basis(face), at)
	parent.add_child(node)
	return node

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
	light.distance_fade_begin = 30.0
	light.distance_fade_length = 8.0
	room.add_child(light)
	lamps += 1
	return light

## A warm caged service lamp where staff work: bulb, cage, cable and a short light.
func _lamp(room: Node3D, at: Vector3, energy: float = 1.8, reach: float = 6.0, cable_to: float = 7.0) -> OmniLight3D:
	var props: Node3D = _props(room)
	var bulb: StandardMaterial3D = _glow("lamp_bulb", ArenaSky.SERVICE_LAMP_COLOR.lightened(0.25), 2.6)
	var cage: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	_shape.cylinder(props, "LampBulb", 0.075, 0.16, bulb, at, 10).rotation.x = PI * 0.5
	_shape.cylinder(props, "LampShade", 0.17, 0.05, cage, at + Vector3(0, 0.1, 0), 12).rotation.x = PI * 0.5
	for side: int in range(4):
		var angle: float = TAU * float(side) / 4.0
		var offset: Vector3 = Vector3(cos(angle), 0, sin(angle)) * 0.11
		_shape.rod(props, "LampCage", at + offset + Vector3(0, 0.09, 0), at + offset * 0.6 + Vector3(0, -0.12, 0), 0.008, cage, 4)
	if cable_to > at.y:
		_shape.rod(props, "LampCable", at + Vector3(0, 0.12, 0), Vector3(at.x, cable_to, at.z), 0.012, cage, 4)
	return _omni(room, "ServiceLamp", at + Vector3(0, -0.12, 0), ArenaSky.SERVICE_LAMP_COLOR, energy, reach)

## A small desk lamp standing on a top, angled toward the work.
func _desk_lamp(room: Node3D, base: Vector3, toward: Vector3) -> void:
	var props: Node3D = _props(room)
	var arm: StandardMaterial3D = _mat("desk_lamp", Color("3d4441"), 0.35, 0.6)
	var shade: StandardMaterial3D = _mat("desk_lamp_shade", Color("4e5844"), 0.2, 0.7)
	_shape.cylinder(props, "DeskLampBase", 0.1, 0.03, arm, base + Vector3(0, 0.015, 0), 10).rotation.x = PI * 0.5
	var elbow: Vector3 = base + Vector3(0, 0.38, 0) + (toward - base).normalized() * -0.05
	var head: Vector3 = elbow + (Vector3(toward.x, elbow.y, toward.z) - elbow).normalized() * 0.28 + Vector3(0, 0.04, 0)
	_shape.rod(props, "DeskLampArm", base, elbow, 0.012, arm, 6)
	_shape.rod(props, "DeskLampArm", elbow, head, 0.012, arm, 6)
	_shape.cylinder(props, "DeskLampShade", 0.09, 0.14, shade, head, 10).rotation.x = PI * 0.5
	_shape.cylinder(props, "DeskLampBulb", 0.05, 0.03, _glow("desk_bulb", Color("ffd9a0"), 2.4), head + Vector3(0, -0.08, 0), 8).rotation.x = PI * 0.5
	var light: OmniLight3D = _omni(room, "DeskLamp", head + Vector3(0, -0.15, 0), ArenaSky.SERVICE_LAMP_COLOR, 1.3, 3.6)
	light.omni_attenuation = 1.8

## A cold issued fixture pool: a hooded lamp on two drop rods and a downward
## spot with a hard edge. This is the room's focus, not general light.
func _pool(room: Node3D, at: Vector3, size: Vector2, energy: float, reach: float, angle: float) -> SpotLight3D:
	var props: Node3D = _props(room)
	var hood: StandardMaterial3D = _mat("fixture_hood", Color("2c2d32"), 0.5, 0.5)
	var rod: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	_block(props, "FixtureHood", Vector3(size.x, 0.16, size.y), hood, at + Vector3(0, 0.08, 0))
	_block(props, "FixtureLens", Vector3(size.x - 0.12, 0.02, size.y - 0.12), _glow("fixture_lens", Color("e6eeee"), 2.2), at + Vector3(0, -0.005, 0))
	for side: float in [-1.0, 1.0]:
		_shape.rod(props, "FixtureDrop", at + Vector3(side * size.x * 0.35, 0.16, 0), Vector3(at.x + side * size.x * 0.35, 7.0, at.z), 0.014, rod, 4)
	var light: SpotLight3D = SpotLight3D.new()
	light.name = "FixturePool%d" % lamps
	light.position = at + Vector3(0, -0.05, 0)
	light.rotation.x = -PI * 0.5
	light.light_color = Color(0.9, 0.96, 0.96)
	light.light_energy = energy
	light.light_specular = 0.15
	light.spot_range = reach
	light.spot_angle = angle
	light.spot_angle_attenuation = 0.6
	light.spot_attenuation = 0.8
	light.shadow_enabled = false
	room.add_child(light)
	lamps += 1
	return light

## A cold issued batten: a long fluorescent tube in a hood on two drop rods,
## giving a big room the readable base its few ceiling strips cannot reach.
## Soft and wide, never a focus; the hard pools and warm lamps still lead.
func _batten(room: Node3D, at: Vector3, length: float, energy: float = 3.0, reach: float = 9.5) -> OmniLight3D:
	var props: Node3D = _props(room)
	var hood: StandardMaterial3D = _mat("fixture_hood", Color("2c2d32"), 0.5, 0.5)
	var rod: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	_block(props, "BattenHood", Vector3(length, 0.1, 0.3), hood, at + Vector3(0, 0.05, 0))
	_block(props, "BattenTube", Vector3(length - 0.1, 0.04, 0.12), _glow("batten_tube", Color("e6eeee"), 2.0), at + Vector3(0, -0.02, 0))
	for side: float in [-1.0, 1.0]:
		_shape.rod(props, "BattenDrop", at + Vector3(side * length * 0.4, 0.1, 0), Vector3(at.x + side * length * 0.4, 7.0, at.z), 0.012, rod, 4)
	var light: OmniLight3D = _omni(room, "Batten", at + Vector3(0, -0.2, 0), BATTEN_COLOR, energy, reach)
	light.omni_attenuation = 1.1
	return light

func _papers(props: Node3D, at: Vector3, count: int, seed_value: int) -> void:
	var paper: StandardMaterial3D = _mat("paper", Color("e3dccb"), 0.0, 0.95)
	var form: StandardMaterial3D = _mat("form_green", Color("b8c4a6"), 0.0, 0.95)
	for index: int in range(count):
		var height: float = 0.02 + float((seed_value + index * 7) % 5) * 0.01
		var piece: MeshInstance3D = _block(props, "FormStack", Vector3(0.24, height, 0.32), form if (index + seed_value) % 3 == 0 else paper, at + Vector3(float(index) * 0.29, height * 0.5, float((index * 3 + seed_value) % 4) * 0.03))
		piece.rotation.y = float((index * 5 + seed_value) % 7 - 3) * 0.06

func _mug(props: Node3D, at: Vector3, tint: Color) -> void:
	_shape.cylinder(props, "Mug", 0.045, 0.1, _mat("mug_%s" % tint.to_html(false), tint, 0.0, 0.6), at + Vector3(0, 0.05, 0), 10).rotation.x = PI * 0.5

## Thin ochre floor paint, flush on an existing top. Never a body.
func _paint_line(props: Node3D, from: Vector3, to: Vector3, width: float, finish: StandardMaterial3D) -> void:
	var span: Vector3 = to - from
	var line: MeshInstance3D = _block(props, "FloorPaint", Vector3(width, 0.006, span.length()), finish, (from + to) * 0.5 + Vector3(0, 0.004, 0))
	line.rotation.y = atan2(span.x, span.z)

## A square floor drain: dark grate with bars, flush with the floor.
func _drain(props: Node3D, at: Vector3) -> void:
	var grate: StandardMaterial3D = _mat("drain_grate", Color("1c1d1f"), 0.5, 0.6)
	var bar: StandardMaterial3D = _mat("drain_bar", Color("4a4c4c"), 0.6, 0.5)
	_block(props, "Drain", Vector3(0.5, 0.008, 0.5), grate, at + Vector3(0, 0.004, 0))
	for index: int in range(5):
		_block(props, "DrainBar", Vector3(0.04, 0.01, 0.46), bar, at + Vector3(-0.2 + float(index) * 0.1, 0.006, 0))

## A PA horn on a wall bracket: the ward's soft voice comes from these.
func _speaker(props: Node3D, at: Vector3, out: Vector3) -> void:
	var horn: StandardMaterial3D = _mat("pa_horn", Color("c9c4ae"), 0.3, 0.6)
	var bracket: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	_shape.rod(props, "SpeakerArm", at, at + out * 0.3, 0.02, bracket, 6)
	var bell: MeshInstance3D = _shape.lathe(props, "SpeakerHorn", PackedVector2Array([Vector2(-0.18, 0.0), Vector2(-0.18, 0.06), Vector2(0.0, 0.08), Vector2(0.18, 0.2), Vector2(0.18, 0.0)]), horn, at + out * 0.38 + Vector3(0, -0.08, 0), 12)
	bell.basis = Basis(Quaternion(Vector3.BACK, (out + Vector3(0, -0.6, 0)).normalized()))

## An empty restraint back flush on a wall: open cuffs, a dead status lamp
## and a bone number plate with no words. The ward was built for many.
func _empty_bay(props: Node3D, at: Vector3, face: String, number: int) -> void:
	var basis: Basis = MapDecoration.face_basis(face)
	var out: Vector3 = basis.z
	var side: Vector3 = basis.x
	var steel: StandardMaterial3D = _mat("restraint_back", Color("56605f"), 0.4, 0.6)
	var rail: StandardMaterial3D = _mat("restraint_rail", Color("c2b9a4"), 0.2, 0.7)
	var cuff: StandardMaterial3D = _mat("restraint_cuff", Color("46504e"), 0.5, 0.5)
	var back: MeshInstance3D = _block(props, "EmptyBayBack", Vector3(1.3, 2.3, 0.08), steel, at + Vector3(0, 1.25, 0) + out * 0.04)
	back.basis = basis
	for edge: float in [-0.68, 0.68]:
		var post: MeshInstance3D = _block(props, "EmptyBayRail", Vector3(0.09, 2.5, 0.12), rail, at + side * edge + Vector3(0, 1.25, 0) + out * 0.06)
		post.basis = basis
	for height: float in [0.55, 1.35, 1.75]:
		for edge: float in [-0.48, 0.48]:
			var open: MeshInstance3D = _block(props, "OpenCuff", Vector3(0.2, 0.08, 0.14), cuff, at + side * edge + Vector3(0, height, 0) + out * 0.15)
			open.basis = basis
	var lamp: MeshInstance3D = _block(props, "DeadStatusLamp", Vector3(0.5, 0.1, 0.05), _mat("status_dead", Color("4a4f4d"), 0.2, 0.6), at + Vector3(0, 2.62, 0) + out * 0.05)
	lamp.basis = basis
	# The bay number in bone dots on a black plate: issued, not named.
	var plate: MeshInstance3D = _block(props, "BayPlate", Vector3(0.36, 0.16, 0.02), _mat("plate_black", Color("1e1e22"), 0.2, 0.7), at + Vector3(0, 2.38, 0) + out * 0.09)
	plate.basis = basis
	for dot: int in range(number):
		var mark: MeshInstance3D = _block(props, "BayDot", Vector3(0.035, 0.035, 0.01), rail, at + side * (-0.12 + float(dot) * 0.06) + Vector3(0, 2.38, 0) + out * 0.1)
		mark.basis = basis

## A Union seal plate in the intake's issued emblem, small and on a wall.
func _seal(room: Node3D, at: Vector3, face: String, size: float) -> void:
	_picture(room, "UnionSeal", M01IntakeArt.texture("emblem"), Vector2(size, size), at, face, 0.0)

# --- observation gallery and guard room --------------------------------------

func _build_gallery() -> void:
	var room: Node3D = _room("Gallery")
	var props: Node3D = _props(room)
	var sill: float = 3.8
	# The watchers' sill: coffee, clipboards and a documentation camera aimed
	# down at the frame. Ordinary people do their shift here. Everything sits
	# west of x 0 or east of x 6, clear of the sightlines from the gallery
	# spawns to Latch on the frame.
	_papers(props, Vector3(-3.4, sill, -25.6), 3, 2)
	_mug(props, Vector3(-1.2, sill, -25.75), Color("c4a46a"))
	_mug(props, Vector3(-4.9, sill, -25.8), Color("d8cfae"))
	var flask: StandardMaterial3D = _mat("thermos", Color("4e5844"), 0.3, 0.5)
	_shape.cylinder(props, "Thermos", 0.06, 0.32, flask, Vector3(-5.3, sill + 0.16, -25.6), 10).rotation.x = PI * 0.5
	var clip: StandardMaterial3D = _mat("clipboard", Color("6b4a35"), 0.0, 0.8)
	var paper: StandardMaterial3D = _mat("paper", Color("e3dccb"), 0.0, 0.95)
	for x: float in [-6.6, 6.5]:
		_block(props, "Clipboard", Vector3(0.26, 0.012, 0.34), clip, Vector3(x, sill + 0.006, -25.55)).rotation.y = 0.2
		_block(props, "ClipboardSheet", Vector3(0.22, 0.004, 0.28), paper, Vector3(x, sill + 0.014, -25.55)).rotation.y = 0.2
	# The camera on a short tripod: the Office photographs what it does.
	var body: StandardMaterial3D = _mat("camera_body", Color("1e1e22"), 0.3, 0.5)
	var lens: StandardMaterial3D = _mat("camera_lens", Color("3a3d40"), 0.6, 0.3)
	var camera: Vector3 = Vector3(7.3, sill, -25.5)
	for angle: float in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		_shape.rod(props, "TripodLeg", camera + Vector3(cos(angle) * 0.18, 0.0, sin(angle) * 0.18), camera + Vector3(0, 0.42, 0), 0.012, body, 4)
	_block(props, "CameraBody", Vector3(0.22, 0.16, 0.14), body, camera + Vector3(0, 0.5, 0))
	_shape.cylinder(props, "CameraLens", 0.05, 0.16, lens, camera + Vector3(0.0, 0.48, 0.12), 10).rotation.x = -0.35
	_desk_lamp(room, Vector3(-2.5, sill, -25.4), Vector3(-3.2, sill, -25.7))
	# Fold-down observer seats on the back wall, all folded: the shift is short.
	var seat: StandardMaterial3D = _mat("seat_shell", Color("4e5844"), 0.2, 0.7)
	var bracket: StandardMaterial3D = _mat("seat_bracket", Color("2c2d32"), 0.5, 0.5)
	for index: int in range(6):
		var x: float = 0.6 + float(index) * 1.15
		_block(props, "SeatBracket", Vector3(0.06, 0.5, 0.1), bracket, Vector3(x - 0.24, 3.55, -33.95))
		_block(props, "SeatBracket", Vector3(0.06, 0.5, 0.1), bracket, Vector3(x + 0.24, 3.55, -33.95))
		_block(props, "FoldedSeat", Vector3(0.44, 0.52, 0.06), seat, Vector3(x, 3.62, -33.9))
	# A coat hook rail with a guard's cap and a long coat: off duty, nearby.
	var hook: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	var cloth: StandardMaterial3D = _mat("coat_black", Color("1e1e22"), 0.0, 0.9)
	var band: StandardMaterial3D = _mat("cap_band", Color("8c1a1e"), 0.0, 0.8)
	_block(props, "HookRail", Vector3(1.6, 0.06, 0.05), hook, Vector3(-2.6, 4.9, -33.95))
	_block(props, "HangingCoat", Vector3(0.5, 1.1, 0.1), cloth, Vector3(-3.0, 4.3, -33.88))
	_shape.cylinder(props, "HangingCap", 0.14, 0.1, cloth, Vector3(-2.2, 4.72, -33.85), 12).rotation.x = PI * 0.5
	_shape.cylinder(props, "CapBand", 0.145, 0.03, band, Vector3(-2.2, 4.69, -33.85), 12).rotation.x = PI * 0.5
	_block(props, "CapPeak", Vector3(0.2, 0.015, 0.1), cloth, Vector3(-2.2, 4.66, -33.75))
	# Guard room table: a hand of cards, two mugs, a lunch tin and an ashtray.
	var table: float = 3.78
	var card: StandardMaterial3D = _mat("playing_card", Color("e8e2d6"), 0.0, 0.9)
	var back: StandardMaterial3D = _mat("card_back", Color("4f6f8a"), 0.0, 0.9)
	for index: int in range(7):
		var piece: MeshInstance3D = _block(props, "PlayingCard", Vector3(0.06, 0.003, 0.09), card if index % 3 != 0 else back, Vector3(-5.2 + float(index % 3) * 0.12, table + 0.002 + float(index) * 0.001, -31.2 + float(index) * 0.18))
		piece.rotation.y = float(index * 3 % 5 - 2) * 0.35
	_block(props, "CardDeck", Vector3(0.07, 0.03, 0.1), back, Vector3(-4.95, table + 0.015, -30.5))
	_mug(props, Vector3(-5.3, table, -29.85), Color("d8cfae"))
	_mug(props, Vector3(-5.25, table, -31.75), Color("4e5844"))
	_block(props, "LunchTin", Vector3(0.3, 0.1, 0.2), _mat("lunch_tin", Color("7a3a22"), 0.4, 0.5), Vector3(-4.95, table + 0.05, -31.4))
	_shape.cylinder(props, "Ashtray", 0.07, 0.025, _mat("ashtray", Color("3a3836"), 0.4, 0.5), Vector3(-5.0, table + 0.012, -30.0), 10).rotation.x = PI * 0.5
	# The duty roster pinned behind the table: rows of shifts, no words.
	var board: StandardMaterial3D = _mat("roster_board", Color("4e5844"), 0.0, 0.9)
	var mark: StandardMaterial3D = _mat("roster_mark", Color("2b2a33"), 0.0, 0.9)
	_block(props, "RosterBoard", Vector3(1.3, 0.9, 0.03), board, Vector3(-5.1, 4.75, -33.97))
	for row: int in range(5):
		_block(props, "RosterSheet", Vector3(1.1, 0.12, 0.006), paper, Vector3(-5.1, 5.07 - float(row) * 0.16, -33.95))
		for tick: int in range(row % 3 + 2):
			_block(props, "RosterTick", Vector3(0.05, 0.05, 0.004), mark, Vector3(-5.5 + float(tick) * 0.18 + float(row) * 0.04, 5.07 - float(row) * 0.16, -33.946))
	_lamp(room, Vector3(-5.1, 5.3, -30.75), 2.2, 6.0)
	_lamp(room, Vector3(3.5, 5.6, -29.0), 1.4, 6.5)
	_finish(room)

# --- service stair -------------------------------------------------------------

func _build_stair() -> void:
	var room: Node3D = _room("Stair")
	var props: Node3D = _props(room)
	# Worn ochre nosing on every tread edge so the descent reads at a glance.
	var nosing: StandardMaterial3D = _mat("stair_nosing", OCHRE, 0.2, 0.8)
	for step: Array in [[-9.0, 2.5, -32.6, 2.8], [-10.0, 2.0, -32.6, 2.8], [-11.0, 1.5, -32.6, 2.8], [-10.0, 1.0, -30.0, 2.0], [-9.0, 0.5, -30.0, 2.0]]:
		var edge: float = step[0]
		_block(props, "TreadNosing", Vector3(0.08, 0.008, float(step[3]) - 0.1), nosing, Vector3(edge + 0.05 if float(step[2]) < -31.0 else edge - 0.05, float(step[1]) + 0.004, step[2]))
	# Pipes along the enclosed well and a caged lamp on each landing.
	var pipe: StandardMaterial3D = _mat("service_pipe", Color("5b6458"), 0.4, 0.6)
	var rust: StandardMaterial3D = _mat("service_pipe_rust", Color("6f3f28"), 0.3, 0.75)
	_shape.rod(props, "WellPipe", Vector3(-8.2, 5.8, -33.85), Vector3(-13.2, 5.8, -33.85), 0.08, pipe, 10)
	_shape.rod(props, "WellPipe", Vector3(-8.2, 6.15, -33.85), Vector3(-13.2, 6.15, -33.85), 0.05, rust, 8)
	_shape.rod(props, "WellRiser", Vector3(-13.2, 0.6, -33.85), Vector3(-13.2, 6.15, -33.85), 0.05, rust, 8)
	_lamp(room, Vector3(-12.2, 4.4, -32.6), 2.4, 6.5)
	_lamp(room, Vector3(-9.6, 3.4, -29.9), 2.2, 6.5)
	_lamp(room, Vector3(-11.6, 3.0, -27.4), 2.0, 6.0)
	# One cold batten high in the well so the treads read grey, not tungsten.
	_batten(room, Vector3(-10.5, 6.3, -32.0), 2.0, 3.2, 9.0)
	_finish(room)

# --- pack landing and the maintenance cut -------------------------------------

func _build_service() -> void:
	var room: Node3D = _room("Service")
	var props: Node3D = _props(room)
	var pipe: StandardMaterial3D = _mat("service_pipe", Color("5b6458"), 0.4, 0.6)
	var rust: StandardMaterial3D = _mat("service_pipe_rust", Color("6f3f28"), 0.3, 0.75)
	var bracket: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	# Two pipe runs along the service wall down to the antechamber.
	for run: Array in [[4.6, 0.1, pipe], [5.0, 0.065, rust]]:
		_shape.rod(props, "ServicePipe", Vector3(-18.8, run[0], -33.8), Vector3(-18.8, run[0], -12.2), run[1], run[2], 10)
	for z: float in [-32.0, -26.0, -20.0, -14.0]:
		_block(props, "PipeBracket", Vector3(0.36, 0.06, 0.06), bracket, Vector3(-18.82, 4.8, z))
	# Cable tray under the ceiling along the cut.
	var tray: StandardMaterial3D = _mat("cable_tray", Color("2c2d32"), 0.5, 0.5)
	var cable: StandardMaterial3D = _mat("cable_black", Color("1b1b1d"), 0.0, 0.7)
	_block(props, "CableTray", Vector3(0.5, 0.06, 20.0), tray, Vector3(-16.8, 6.3, -22.5))
	for offset: float in [-0.14, 0.0, 0.14]:
		_block(props, "TrayCable", Vector3(0.07, 0.06, 20.0), cable, Vector3(-16.8 + offset, 6.36, -22.5))
	# A breaker panel above the pack landing, levers thrown at odd angles.
	var panel: StandardMaterial3D = _mat("breaker_panel", Color("4e5844"), 0.3, 0.6)
	var lever: StandardMaterial3D = _mat("breaker_lever", Color("d8c9a4"), 0.0, 0.6)
	_block(props, "BreakerPanel", Vector3(0.12, 0.9, 0.7), panel, Vector3(-18.94, 2.1, -31.6))
	for index: int in range(4):
		_block(props, "BreakerLever", Vector3(0.06, 0.12, 0.05), lever, Vector3(-18.86, 2.3 - float(index % 2) * 0.3, -31.8 + floorf(float(index) / 2.0) * 0.4))
	# Mop bucket and a squeegee in the corner: the floor is kept clean.
	var bucket: StandardMaterial3D = _mat("mop_bucket", Color("6f7a5a"), 0.2, 0.7)
	_shape.cylinder(props, "MopBucket", 0.18, 0.3, bucket, Vector3(-18.6, 0.65, -27.95), 12).rotation.x = PI * 0.5
	_shape.rod(props, "MopHandle", Vector3(-18.6, 0.7, -27.95), Vector3(-18.85, 2.0, -27.75), 0.015, _mat("mop_handle", Color("8d6c43"), 0.0, 0.8), 5)
	_drain(props, Vector3(-16.5, 0.5, -30.2))
	_lamp(room, Vector3(-18.3, 3.2, -29.6), 2.6, 7.0)
	_lamp(room, Vector3(-16.0, 3.0, -24.6), 2.2, 6.5)
	_finish(room)

# --- antechamber -------------------------------------------------------------

func _build_antechamber() -> void:
	var room: Node3D = _room("Antechamber")
	var props: Node3D = _props(room)
	var top: float = 1.1
	var tag: StandardMaterial3D = _mat("stock_tag", Color("e6dfcf"), 0.0, 0.95)
	# Issued handle plates laid out to be stamped: black plate, red band.
	var plate: StandardMaterial3D = _mat("issued_plate", Color("1e1e22"), 0.5, 0.45)
	var red: StandardMaterial3D = _mat("issued_band", Color("8c1a1e"), 0.2, 0.7)
	var tray: StandardMaterial3D = _mat("sorting_tray", Color("4e5844"), 0.3, 0.6)
	_block(props, "PlateTray", Vector3(1.0, 0.04, 0.6), tray, Vector3(-15.2, top + 0.02, -18.4))
	for index: int in range(8):
		var at: Vector3 = Vector3(-15.55 + float(index % 4) * 0.23, top + 0.05, -18.55 + floorf(float(index) / 4.0) * 0.3)
		_block(props, "HandlePlate", Vector3(0.18, 0.012, 0.11), plate, at)
		_block(props, "HandleBand", Vector3(0.18, 0.014, 0.025), red, at + Vector3(0, 0.0, -0.035))
	# The hand press that stamps them.
	var press: StandardMaterial3D = _mat("hand_press", Color("343a3c"), 0.5, 0.5)
	_block(props, "PressBase", Vector3(0.36, 0.08, 0.3), press, Vector3(-14.25, top + 0.04, -18.5))
	_block(props, "PressColumn", Vector3(0.08, 0.5, 0.08), press, Vector3(-14.4, top + 0.33, -18.5))
	_block(props, "PressHead", Vector3(0.3, 0.1, 0.14), press, Vector3(-14.3, top + 0.55, -18.5))
	_shape.rod(props, "PressLever", Vector3(-14.2, top + 0.58, -18.5), Vector3(-13.95, top + 0.85, -18.3), 0.015, press, 5)
	# What the Union cut off: hand-painted panels, stickers and an antenna,
	# tagged in a tray as surplus. No words needed; the colour says whose.
	var bin: StandardMaterial3D = _mat("bin_steel", Color("56575e"), 0.4, 0.6)
	var bin_at: Vector3 = Vector3(-15.3, top, -17.45)
	_block(props, "SurplusTray", Vector3(0.8, 0.03, 0.5), bin, bin_at + Vector3(0, 0.015, 0))
	for side: float in [-1.0, 1.0]:
		_block(props, "SurplusWall", Vector3(0.8, 0.14, 0.025), bin, bin_at + Vector3(0, 0.07, side * 0.24))
		_block(props, "SurplusWall", Vector3(0.025, 0.14, 0.5), bin, bin_at + Vector3(side * 0.39, 0.07, 0))
	for index: int in range(6):
		var colour: Color = PERSONAL[index % PERSONAL.size()]
		var piece: MeshInstance3D = _block(props, "RemovedPanel", Vector3(0.26, 0.02, 0.18), _mat("personal_%s" % colour.to_html(false), colour, 0.2, 0.6), bin_at + Vector3(-0.22 + float(index % 3) * 0.22, 0.04 + floorf(float(index) / 3.0) * 0.025, -0.08 + floorf(float(index) / 3.0) * 0.14))
		piece.rotation = Vector3(0.0, float(index) * 0.5 - 1.0, float(index % 2) * 0.15)
		_block(props, "Sticker", Vector3(0.06, 0.004, 0.06), _mat("sticker_bone", Color("e8e2d6"), 0.0, 0.8), piece.position + Vector3(0.04, 0.012, 0.02))
	_shape.rod(props, "CutAntenna", bin_at + Vector3(-0.2, 0.08, 0.12), bin_at + Vector3(0.25, 0.1, 0.05), 0.01, _mat("antenna", Color("9a978c"), 0.6, 0.4), 4)
	_block(props, "SurplusTag", Vector3(0.2, 0.12, 0.006), tag, bin_at + Vector3(0.1, 0.12, -0.255))
	_papers(props, Vector3(-13.8, top, -17.6), 2, 4)
	_desk_lamp(room, Vector3(-13.35, top, -18.7), Vector3(-14.6, top, -18.2))
	# Issued smocks on a hook rail, all one grey: what a captive leaves in.
	var smock: StandardMaterial3D = _mat("issue_smock", Color("6b6e6b"), 0.0, 0.95)
	var hook: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	_block(props, "SmockRail", Vector3(0.05, 0.05, 5.2), hook, Vector3(-18.95, 2.25, -15.2))
	for index: int in range(7):
		var z: float = -17.4 + float(index) * 0.72
		_block(props, "Smock", Vector3(0.07, 1.0, 0.5), smock, Vector3(-18.9, 1.7, z))
		_block(props, "SmockTag", Vector3(0.008, 0.08, 0.12), tag, Vector3(-18.855, 1.95, z + 0.12))
	# A hose reel and drain: the room is washed down.
	var reel: StandardMaterial3D = _mat("hose_reel", Color("4e5844"), 0.3, 0.6)
	var hose: StandardMaterial3D = _mat("hose", Color("2d2b29"), 0.0, 0.7)
	_shape.cylinder(props, "HoseReel", 0.3, 0.12, reel, Vector3(-11.5, 1.4, -12.08), 14)
	_shape.cylinder(props, "HoseCoil", 0.24, 0.16, hose, Vector3(-11.5, 1.4, -12.12), 14)
	_drain(props, Vector3(-12.0, 0.0, -15.0))
	_seal(room, Vector3(-14.5, 4.6, -12.02), "north", 1.1)
	_lamp(room, Vector3(-14.6, 3.4, -18.2), 2.2, 6.0)
	_lamp(room, Vector3(-17.8, 3.6, -14.0), 1.5, 5.5)
	_finish(room)

# --- correction ward ---------------------------------------------------------

func _build_ward() -> void:
	var room: Node3D = _room("Ward")
	var props: Node3D = _props(room)
	# The processing lane: a bone-painted route from the ward door to the
	# frame, with a stand box in front of it. Every captive walked this.
	var lane: StandardMaterial3D = _mat("lane_paint", Color("cfc7ac"), 0.0, 0.9)
	var hatch: StandardMaterial3D = _mat("hazard_ochre", OCHRE, 0.0, 0.85)
	for offset: float in [-0.55, 0.55]:
		_paint_line(props, Vector3(-8.8, 0.0, -18.5 + offset), Vector3(1.6, 0.0, -18.5 + offset), 0.09, lane)
		_paint_line(props, Vector3(1.6 + offset, 0.0, -18.5 + offset * -1.0), Vector3(6.4 + offset, 0.0, -11.0 + offset * -0.4), 0.09, lane)
	for index: int in range(5):
		var x: float = -7.5 + float(index) * 2.0
		_paint_line(props, Vector3(x, 0.0, -18.9), Vector3(x + 0.35, 0.0, -18.5), 0.09, lane)
		_paint_line(props, Vector3(x + 0.35, 0.0, -18.5), Vector3(x, 0.0, -18.1), 0.09, lane)
	# The stand box before the frame and a hatched border round the machine.
	for edge: Array in [[Vector3(6.2, 0, -12.6), Vector3(7.9, 0, -12.6)], [Vector3(6.2, 0, -8.4), Vector3(7.9, 0, -8.4)], [Vector3(6.2, 0, -12.6), Vector3(6.2, 0, -8.4)]]:
		_paint_line(props, edge[0], edge[1], 0.12, lane)
	for edge: Array in [[Vector3(-4.3, 0, -15.3), Vector3(0.3, 0, -15.3)], [Vector3(-4.3, 0, -12.7), Vector3(0.3, 0, -12.7)], [Vector3(-4.3, 0, -15.3), Vector3(-4.3, 0, -12.7)], [Vector3(0.3, 0, -15.3), Vector3(0.3, 0, -12.7)]]:
		_paint_line(props, edge[0], edge[1], 0.22, hatch)
	_drain(props, Vector3(5.6, 0.0, -10.6))
	_drain(props, Vector3(-2.0, 0.0, -11.9))
	# Power runs from the machine to the frame: floor cables flat in a trough
	# and an overhead tray, so the two read as one apparatus.
	var cable: StandardMaterial3D = _mat("cable_black", Color("1b1b1d"), 0.0, 0.7)
	var tray: StandardMaterial3D = _mat("cable_tray", Color("2c2d32"), 0.5, 0.5)
	for offset: float in [-0.08, 0.08]:
		_shape.pipe(props, "FloorCable", PackedVector3Array([Vector3(0.05, 0.05, -14.0 + offset), Vector3(3.5, 0.05, -13.6 + offset), Vector3(7.9, 0.05, -12.9 + offset)]), 0.045, cable)
	_shape.pipe(props, "RiserCable", PackedVector3Array([Vector3(-2.0, 3.2, -14.0), Vector3(-2.0, 5.4, -14.0), Vector3(8.5, 5.4, -11.0), Vector3(8.5, 2.6, -11.0)]), 0.07, cable)
	_block(props, "OverheadTray", Vector3(0.4, 0.06, 0.4), tray, Vector3(-2.0, 5.5, -14.0))
	_build_frame_facade(props)
	# Empty restraint backs along the north wall: built for many more.
	for index: int in range(4):
		_empty_bay(props, Vector3(-7.4 + float(index) * 2.3, 0.0, -8.0), "north", index + 3)
	# The ward's soft voice: PA horns high on the long walls.
	_speaker(props, Vector3(-9.0, 5.6, -21.5), Vector3(1, 0, 0))
	_speaker(props, Vector3(9.0, 5.6, -14.0), Vector3(-1, 0, 0))
	# A monitoring panel flush on the west wall: one amber trace, no words.
	var housing: StandardMaterial3D = _mat("monitor_frame", Color("2c2d32"), 0.4, 0.55)
	_block(props, "MonitorHousing", Vector3(0.12, 1.0, 1.5), housing, Vector3(-8.94, 1.7, -10.5))
	_picture(room, "VitalsTrace", _trace_texture(), Vector2(1.3, 0.8), Vector3(-8.87, 1.72, -10.5), "east", 1.2)
	var dial: StandardMaterial3D = _mat("dial_bone", Color("d8c9a4"), 0.0, 0.6)
	for index: int in range(3):
		_shape.cylinder(props, "PanelDial", 0.06, 0.03, dial, Vector3(-8.87, 1.08, -11.0 + float(index) * 0.5), 12).rotation.y = PI * 0.5
	# Frame trim on the gallery opening above: the watchers' window.
	var trim: StandardMaterial3D = _mat("window_trim", Color("2c2d32"), 0.5, 0.5)
	_block(props, "GallerySillLip", Vector3(18.0, 0.1, 0.14), trim, Vector3(0.0, 3.75, -24.95))
	_block(props, "GalleryHeaderLip", Vector3(18.0, 0.1, 0.14), trim, Vector3(0.0, 5.45, -24.95))
	_seal(room, Vector3(-4.5, 2.2, -24.98), "south", 1.0)
	# One hard pool over the frame, cold, so Latch is the brightest thing in
	# the room from the gallery; a second, dimmer pool over the machine.
	_pool(room, Vector3(7.2, 4.6, -10.8), Vector2(1.6, 1.2), 9.0, 6.5, 32.0)
	_pool(room, Vector3(-2.0, 5.2, -11.6), Vector2(1.4, 1.0), 4.5, 6.5, 30.0)
	# Guards' station by the door: one warm lamp where staff stand.
	_lamp(room, Vector3(-7.6, 3.6, -22.8), 1.8, 6.0)
	_finish(room)

## The restraint frame's own face behind Latch: issued plate with bone rails,
## a head brace, wrist and ankle cuffs and cable ports. It covers the plain
## locker panel the graybox gave the frame; the server's frame body is unchanged.
func _build_frame_facade(props: Node3D) -> void:
	var plate: StandardMaterial3D = _mat("frame_plate", Color("3f4446"), 0.5, 0.5)
	var rail: StandardMaterial3D = _mat("restraint_rail", Color("c2b9a4"), 0.2, 0.7)
	var cuff: StandardMaterial3D = _mat("restraint_cuff", Color("46504e"), 0.5, 0.5)
	var port: StandardMaterial3D = _mat("cable_black", Color("1b1b1d"), 0.0, 0.7)
	var face: float = 7.96
	_block(props, "FramePlate", Vector3(0.05, 2.56, 3.96), plate, Vector3(face, 1.28, -11.0))
	for z: float in [-12.94, -9.06]:
		_block(props, "FrameRail", Vector3(0.1, 2.6, 0.12), rail, Vector3(face - 0.04, 1.3, z))
	_block(props, "FrameHead", Vector3(0.1, 0.12, 3.96), rail, Vector3(face - 0.04, 2.54, -11.0))
	# Latch's position: head brace, wrist and ankle cuffs either side.
	_block(props, "HeadBrace", Vector3(0.16, 0.1, 0.62), rail, Vector3(face - 0.08, 2.08, -10.0))
	for z: float in [-10.62, -9.38]:
		_block(props, "WristCuff", Vector3(0.18, 0.12, 0.16), cuff, Vector3(face - 0.1, 1.45, z))
		_block(props, "AnkleCuff", Vector3(0.18, 0.1, 0.16), cuff, Vector3(face - 0.1, 0.25, z))
	_block(props, "SpineChannel", Vector3(0.03, 1.9, 0.12), port, Vector3(face - 0.03, 1.05, -10.0))
	# The second position on the same frame, empty, its cuffs open.
	_block(props, "HeadBrace", Vector3(0.16, 0.1, 0.62), rail, Vector3(face - 0.08, 2.08, -12.0))
	for z: float in [-12.62, -11.38]:
		_block(props, "OpenCuff", Vector3(0.2, 0.08, 0.14), cuff, Vector3(face - 0.1, 1.45, z))
	_block(props, "SpineChannel", Vector3(0.03, 1.9, 0.12), port, Vector3(face - 0.03, 1.05, -12.0))
	for index: int in range(4):
		_shape.cylinder(props, "CablePort", 0.05, 0.06, port, Vector3(face - 0.03, 2.35, -12.4 + float(index) * 0.35), 8).rotation.y = PI * 0.5

## An amber vitals trace on a black monitor face.
func _trace_texture() -> Texture2D:
	var image: Image = Image.create(64, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color("141210"))
	var amber: Color = M01IntakeArt.PHOSPHOR
	var dim: Color = amber.darkened(0.6)
	for x: int in range(2, 62, 6):
		for y: int in range(3, 37):
			image.set_pixel(x, y, Color("1f1c18"))
	var baseline: int = 24
	for x: int in range(2, 62):
		var phase: int = x % 20
		var y: int = baseline
		if phase == 8:
			y = baseline - 4
		elif phase == 9:
			y = baseline - 14
		elif phase == 10:
			y = baseline + 5
		elif phase == 11:
			y = baseline - 2
		image.set_pixel(x, y, amber)
		if phase in [9, 10]:
			for fill: int in range(mini(y, baseline), maxi(y, baseline)):
				image.set_pixel(x, fill, amber)
	for x: int in range(4, 24):
		image.set_pixel(x, 6, dim)
		image.set_pixel(x, 8, dim)
	return ImageTexture.create_from_image(image)

# --- processing floor ------------------------------------------------------------

func _build_floor() -> void:
	var room: Node3D = _room("Floor")
	var props: Node3D = _props(room)
	var steel: StandardMaterial3D = _mat("press_steel", Color("343a3c"), 0.5, 0.5)
	var rod: StandardMaterial3D = _mat("press_rod", Color("8a8c86"), 0.7, 0.35)
	var hatch: StandardMaterial3D = _mat("hazard_ochre", OCHRE, 0.0, 0.85)
	var amber: StandardMaterial3D = _glow("button_amber", Color("e0a040"), 1.4)
	# Two presses: a die plate on top, piston rods up to a crossbeam, an
	# ochre band round the base and a control box flush on one face.
	for press: Array in [[Vector3(-4, 0, 3), Vector3(-1, 2.2, 6), "west"], [Vector3(8, 0, -2), Vector3(11, 2.8, 2), "west"]]:
		var low: Vector3 = press[0]
		var high: Vector3 = press[1]
		var centre: Vector3 = (low + high) * 0.5
		var size: Vector3 = high - low
		_block(props, "DiePlate", Vector3(size.x - 0.5, 0.06, size.z - 0.5), steel, Vector3(centre.x, high.y + 0.03, centre.z))
		for side: float in [-1.0, 1.0]:
			_shape.rod(props, "PressRod", Vector3(centre.x + side * (size.x * 0.3), high.y + 0.06, centre.z), Vector3(centre.x + side * (size.x * 0.3), 6.3, centre.z), 0.09, rod, 10)
		_block(props, "PressCrossbeam", Vector3(size.x + 0.4, 0.4, 0.5), steel, Vector3(centre.x, 6.5, centre.z))
		_block(props, "PressCylinder", Vector3(0.7, 0.5, 0.7), steel, Vector3(centre.x, 6.05, centre.z))
		for edge: Array in [[Vector3(low.x - 0.15, 0, low.z - 0.15), Vector3(high.x + 0.15, 0, low.z - 0.15)], [Vector3(low.x - 0.15, 0, high.z + 0.15), Vector3(high.x + 0.15, 0, high.z + 0.15)], [Vector3(low.x - 0.15, 0, low.z - 0.15), Vector3(low.x - 0.15, 0, high.z + 0.15)], [Vector3(high.x + 0.15, 0, low.z - 0.15), Vector3(high.x + 0.15, 0, high.z + 0.15)]]:
			_paint_line(props, edge[0], edge[1], 0.22, hatch)
		var box: Vector3 = Vector3(low.x - 0.04, 1.3, centre.z)
		_block(props, "ControlBox", Vector3(0.08, 0.6, 0.5), _mat("control_box", Color("4e5844"), 0.3, 0.6), box)
		for index: int in range(3):
			_block(props, "ControlButton", Vector3(0.03, 0.07, 0.07), amber, box + Vector3(-0.05, 0.12 - float(index) * 0.12, 0.1))
	# The line: personal panels ride in from the east end; issued black
	# plate with a red band stacks at the west end. Rollers flush on top.
	var roller: StandardMaterial3D = _mat("roller", Color("6b6e6b"), 0.6, 0.4)
	var rail: StandardMaterial3D = _mat("conveyor_rail", Color("2c2d32"), 0.5, 0.5)
	for index: int in range(17):
		_shape.rod(props, "Roller", Vector3(5.2 + float(index) * 0.4, 1.0, 8.1), Vector3(5.2 + float(index) * 0.4, 1.0, 9.4), 0.05, roller, 8)
	for z: float in [8.03, 9.47]:
		_block(props, "ConveyorRail", Vector3(7.0, 0.12, 0.06), rail, Vector3(8.5, 1.05, z))
	for index: int in range(5):
		var colour: Color = PERSONAL[(index + 2) % PERSONAL.size()]
		var panel: MeshInstance3D = _block(props, "PersonalPanel", Vector3(0.5, 0.03, 0.4), _mat("personal_%s" % colour.to_html(false), colour, 0.2, 0.6), Vector3(11.4 - float(index) * 0.75, 1.07, 8.75 + float(index % 2) * 0.1 - 0.05))
		panel.rotation.y = float(index % 3 - 1) * 0.25
		_block(props, "PanelSticker", Vector3(0.08, 0.004, 0.08), _mat("sticker_bone", Color("e8e2d6"), 0.0, 0.8), panel.position + Vector3(0.1, 0.018, 0.05))
	var issued: StandardMaterial3D = _mat("issued_plate", Color("1e1e22"), 0.5, 0.45)
	var red: StandardMaterial3D = _mat("issued_band", Color("8c1a1e"), 0.2, 0.7)
	for index: int in range(6):
		var at: Vector3 = Vector3(5.7, 1.07 + float(index) * 0.035, 8.75)
		_block(props, "IssuedPlate", Vector3(0.5, 0.03, 0.4), issued, at)
		_block(props, "IssuedBand", Vector3(0.08, 0.032, 0.4), red, at + Vector3(0.12, 0, 0))
	# The service rack: shelves of boxed handle plates.
	var box_grey: StandardMaterial3D = _mat("archive_box_grey", Color("9a978c"), 0.0, 0.9)
	var label: StandardMaterial3D = _mat("stock_tag", Color("e6dfcf"), 0.0, 0.95)
	for y: float in [0.6, 1.2]:
		_block(props, "RackShelf", Vector3(2.0, 0.04, 0.05), rail, Vector3(4.0, y, 11.96))
		for index: int in range(4):
			_block(props, "PlateBox", Vector3(0.4, 0.3, 0.04), box_grey, Vector3(3.3 + float(index) * 0.47, y + 0.17, 11.97))
			_block(props, "PlateBoxLabel", Vector3(0.16, 0.07, 0.01), label, Vector3(3.3 + float(index) * 0.47, y + 0.2, 11.945))
	# Overhead: two I-beams with hoist chains above head height.
	var beam: StandardMaterial3D = _mat("i_beam", Color("2c2d32"), 0.5, 0.5)
	var chain: StandardMaterial3D = _mat("chain", Color("4a4c4c"), 0.6, 0.5)
	for z: float in [0.0, 10.5]:
		_block(props, "IBeam", Vector3(27.8, 0.36, 0.22), beam, Vector3(0.0, 6.8, z))
	for at: Vector3 in [Vector3(3.0, 0, 0.0), Vector3(-3.5, 0, 10.5), Vector3(9.5, 0, 10.5)]:
		_block(props, "HoistTrolley", Vector3(0.5, 0.3, 0.4), steel, Vector3(at.x, 6.45, at.z))
		_shape.rod(props, "HoistChain", Vector3(at.x, 6.3, at.z), Vector3(at.x, 4.3, at.z), 0.03, chain, 4)
		_block(props, "HoistHook", Vector3(0.12, 0.25, 0.06), _mat("hook_ochre", OCHRE, 0.4, 0.6), Vector3(at.x, 4.15, at.z))
	# Wall pipes and the officer's post on the mezzanine wall.
	var pipe: StandardMaterial3D = _mat("service_pipe", Color("5b6458"), 0.4, 0.6)
	_shape.rod(props, "FloorPipe", Vector3(13.85, 5.2, -6.8), Vector3(13.85, 5.2, 1.8), 0.1, pipe, 10)
	_shape.rod(props, "FloorPipe", Vector3(-13.85, 5.6, -6.8), Vector3(-13.85, 5.6, 13.8), 0.1, pipe, 10)
	# The mezzanine edge paint: the drop reads before a step goes over it.
	_paint_line(props, Vector3(-6.12, 2.5, 1.0), Vector3(-6.12, 2.5, 14.0), 0.2, hatch)
	var desk: StandardMaterial3D = _mat("wall_desk", Color("4e5844"), 0.3, 0.6)
	_block(props, "WallDesk", Vector3(0.45, 0.05, 1.4), desk, Vector3(-13.78, 3.55, 6.0))
	_block(props, "DeskBracket", Vector3(0.05, 0.4, 0.05), desk, Vector3(-13.95, 3.35, 5.5))
	_block(props, "DeskBracket", Vector3(0.05, 0.4, 0.05), desk, Vector3(-13.95, 3.35, 6.5))
	_papers(props, Vector3(-13.85, 3.58, 5.6), 2, 6)
	_block(props, "Telephone", Vector3(0.18, 0.08, 0.22), _mat("telephone", Color("1e1e22"), 0.3, 0.5), Vector3(-13.75, 3.62, 6.5))
	_seal(room, Vector3(-13.98, 5.3, 6.0), "east", 1.2)
	_lamp(room, Vector3(-2.5, 4.9, 4.5), 3.0, 8.0)
	_lamp(room, Vector3(8.5, 4.2, 8.75), 2.8, 7.5)
	_lamp(room, Vector3(-12.6, 5.6, 6.0), 2.4, 7.0)
	_lamp(room, Vector3(12.6, 4.4, 4.2), 2.4, 7.0)
	_lamp(room, Vector3(5.5, 4.6, -4.5), 2.6, 7.5)
	_lamp(room, Vector3(0.0, 4.6, 11.8), 2.6, 7.5)
	_lamp(room, Vector3(-8.0, 4.6, -4.6), 2.4, 7.5)
	# Cold battens between the ceiling strips: the floor reads end to end
	# like the intake's halls, with the warm lamps still marking the work.
	for at: Vector3 in [Vector3(-5.5, 5.0, -3.5), Vector3(4.0, 5.0, -3.5), Vector3(-3.0, 5.0, 8.0), Vector3(10.0, 5.0, 5.0), Vector3(4.0, 5.0, 13.5)]:
		_batten(room, at, 2.4)
	_finish(room)

# --- side ward ------------------------------------------------------------------

func _build_side_ward() -> void:
	var room: Node3D = _room("SideWard")
	var props: Node3D = _props(room)
	# Two more empty bays down the wall: the side ward was never full by chance.
	_empty_bay(props, Vector3(19.6, 0.0, 10.0), "north", 1)
	_empty_bay(props, Vector3(21.1, 0.0, 10.0), "north", 2)
	# Each captive's own belongings in a clear bag on a hook beside them.
	var bag: StandardMaterial3D = _mat("evidence_bag", Color("c8c3b0"), 0.0, 0.6)
	var hook: StandardMaterial3D = _mat("lamp_cage", Color("2f3030"), 0.4, 0.6)
	for index: int in range(2):
		var x: float = 22.6 + float(index) * 1.9 + 0.85
		_block(props, "BagHook", Vector3(0.04, 0.12, 0.08), hook, Vector3(x, 2.1, 9.93))
		_block(props, "BelongingsBag", Vector3(0.36, 0.5, 0.12), bag, Vector3(x, 1.75, 9.9))
		var colour: Color = PERSONAL[index * 3]
		_block(props, "BaggedThing", Vector3(0.2, 0.18, 0.06), _mat("personal_%s" % colour.to_html(false), colour, 0.2, 0.6), Vector3(x, 1.68, 9.86))
	_drain(props, Vector3(23.5, 0.0, 6.5))
	_speaker(props, Vector3(26.0, 5.0, 4.0), Vector3(-1, 0, 0))
	_pool(room, Vector3(23.55, 4.2, 8.6), Vector2(2.6, 0.9), 7.0, 6.0, 42.0)
	_lamp(room, Vector3(16.6, 3.4, 2.2), 2.4, 6.5)
	_lamp(room, Vector3(21.5, 4.2, 5.2), 3.0, 8.0)
	# The side ward has no ceiling strip of its own; two battens give it one.
	_batten(room, Vector3(18.5, 4.8, 3.0), 2.4, 3.4)
	_batten(room, Vector3(24.0, 4.8, 4.0), 2.4, 3.4)
	_finish(room)

# --- loading dock ------------------------------------------------------------

func _build_dock() -> void:
	var room: Node3D = _room("Dock")
	var props: Node3D = _props(room)
	var frame: StandardMaterial3D = _mat("door_frame", Color("2c2d32"), 0.5, 0.5)
	var slat: StandardMaterial3D = _mat("shutter_slat", Color("5d6266"), 0.5, 0.55)
	var rib: StandardMaterial3D = _mat("shutter_rib", Color("3f4446"), 0.5, 0.55)
	var day: StandardMaterial3D = _glow("daylight", DAYLIGHT, 2.2)
	var face: float = 23.98
	# The yard door: a roller shutter stopped short of the floor, daylight
	# showing under it, and high panes over it lit by the overcast yard.
	_block(props, "DaylightGap", Vector3(7.6, 0.42, 0.01), day, Vector3(0.0, 0.21, face))
	for x: float in [-4.0, 4.0]:
		_block(props, "DoorPost", Vector3(0.3, 5.0, 0.24), frame, Vector3(x, 2.5, face - 0.1))
	_block(props, "DoorHead", Vector3(8.3, 0.5, 0.36), frame, Vector3(0.0, 5.0, face - 0.16))
	_block(props, "ShutterDrum", Vector3(7.8, 0.6, 0.6), frame, Vector3(0.0, 4.55, face - 0.3))
	for index: int in range(18):
		var y: float = 0.62 + float(index) * 0.22
		if y > 4.25:
			break
		_block(props, "ShutterSlat", Vector3(7.7, 0.2, 0.05), slat, Vector3(0.0, y, face - 0.04))
		_block(props, "ShutterRib", Vector3(7.7, 0.03, 0.07), rib, Vector3(0.0, y - 0.1, face - 0.05))
	_block(props, "ShutterBottomBar", Vector3(7.7, 0.12, 0.09), frame, Vector3(0.0, 0.5, face - 0.06))
	for index: int in range(4):
		var x: float = -4.5 + float(index) * 3.0
		_block(props, "Clerestory", Vector3(2.4, 0.9, 0.01), day, Vector3(x, 6.2, face))
		_block(props, "ClerestoryFrame", Vector3(2.6, 0.08, 0.08), frame, Vector3(x, 5.71, face - 0.04))
		for bar: int in range(4):
			_block(props, "ClerestoryBar", Vector3(0.05, 0.9, 0.06), frame, Vector3(x - 0.9 + float(bar) * 0.6, 6.2, face - 0.04))
	var daylight: OmniLight3D = _omni(room, "YardDaylight", Vector3(0.0, 0.6, 23.2), DAYLIGHT, 2.4, 8.0)
	daylight.light_specular = 0.2
	_omni(room, "ClerestoryDaylight", Vector3(0.0, 6.0, 23.0), DAYLIGHT, 1.6, 9.0)
	# Chevrons at the threshold: the way out is painted on the floor.
	var hatch: StandardMaterial3D = _mat("hazard_ochre", OCHRE, 0.0, 0.85)
	for index: int in range(7):
		var x: float = -3.0 + float(index) * 1.0
		_paint_line(props, Vector3(x - 0.3, 0.0, 22.6), Vector3(x, 0.0, 23.2), 0.14, hatch)
		_paint_line(props, Vector3(x, 0.0, 23.2), Vector3(x + 0.3, 0.0, 22.6), 0.14, hatch)
	# The registered freight crate gets slats, banding and a stock tag.
	var crate: StandardMaterial3D = _mat("crate_slat", Color("5d6650"), 0.0, 0.85)
	var band: StandardMaterial3D = _mat("crate_band", Color("2c2d32"), 0.5, 0.5)
	for side: Array in [[Vector3(-4.0, 0.7, 18.98), Vector3(2.0, 1.4, 0.04)], [Vector3(-4.0, 0.7, 21.02), Vector3(2.0, 1.4, 0.04)]]:
		var at: Vector3 = side[0]
		for row: int in range(4):
			_block(props, "CrateSlat", Vector3(1.96, 0.3, 0.04), crate, Vector3(at.x, 0.2 + float(row) * 0.34, at.z))
		for x: float in [-0.9, 0.9]:
			_block(props, "CrateBand", Vector3(0.08, 1.42, 0.05), band, Vector3(at.x + x, 0.7, at.z))
	for side: Array in [[Vector3(-5.02, 0.7, 20.0)], [Vector3(-2.98, 0.7, 20.0)]]:
		var at: Vector3 = side[0]
		for row: int in range(4):
			_block(props, "CrateSlat", Vector3(0.04, 0.3, 1.96), crate, Vector3(at.x, 0.2 + float(row) * 0.34, at.z))
	_block(props, "CrateTag", Vector3(0.3, 0.2, 0.01), _mat("stock_tag", Color("e6dfcf"), 0.0, 0.95), Vector3(-3.6, 1.1, 18.955))
	# Flat pallets and strapping against the walls; nothing a pawn trips on.
	var pallet: StandardMaterial3D = _mat("pallet_wood", Color("8d6c43"), 0.0, 0.85)
	for at: Vector3 in [Vector3(5.35, 0.0, 17.2), Vector3(5.35, 0.0, 18.5)]:
		_block(props, "PalletDeck", Vector3(1.1, 0.03, 1.2), pallet, at + Vector3(0, 0.1, 0))
		for z: float in [-0.5, 0.0, 0.5]:
			_block(props, "PalletRunner", Vector3(1.1, 0.085, 0.12), pallet, at + Vector3(0, 0.0425, z))
	# The dispatch board: a wall clipboard of tick marks, and the yard clock.
	var paper: StandardMaterial3D = _mat("paper", Color("e3dccb"), 0.0, 0.95)
	_block(props, "DispatchBoard", Vector3(0.04, 0.9, 1.2), _mat("roster_board", Color("4e5844"), 0.0, 0.9), Vector3(-5.97, 1.7, 17.2))
	for row: int in range(4):
		_block(props, "DispatchSheet", Vector3(0.006, 0.16, 1.0), paper, Vector3(-5.94, 2.0 - float(row) * 0.2, 17.2))
	_lamp(room, Vector3(-4.6, 4.6, 22.9), 2.2, 6.5)
	_lamp(room, Vector3(0.0, 4.2, 15.6), 2.4, 7.0)
	_finish(room)
