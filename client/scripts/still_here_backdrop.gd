class_name StillHereBackdrop
extends Node3D

## The view from the refuge, strictly outside the walkable quay and court:
## the harbour, the long pier back to the waterworks, the tower the free
## agents talked from, Low Water's roofs and tanks across the water, and the
## city further off. The first light keeps the wipe's palette and landmarks
## (dark windows, smoke, the work front's cyan lights moving on to the next
## district). Years later the same skyline has opened up: clean water,
## trees where streets were, a few towers left standing and green on the
## ones that fell. Nothing here is collision, cover or an interaction.
const SHADER: Shader = preload("res://assets/shaders/harbour_water.gdshader")
const WATER_LEVEL: float = -1.2
## Land inside the square: the court and the town behind it, and the quay
## apron in front of the wall. The basins either side of the apron and
## everything west of the quay rail are harbour.
const LAND: Array[Rect2] = [Rect2(-20.0, -40.0, 60.0, 80.0), Rect2(-30.0, -16.4, 10.0, 32.8)]
const WARM: Color = Color("ffc98a")
const WINDOW: Color = Color("f2b56b")
const CYAN: Color = Color("4a8a92")
const WATERWORKS: Vector3 = Vector3(-168.0, 0.0, 28.0)

var later: bool = false
var water_material: ShaderMaterial
var _clock: float = 0.0
var _smoke: Array[MeshInstance3D] = []
var _birds: Array[Node3D] = []
var _work_lights: Array[MeshInstance3D] = []

func build(half: float, is_later: bool) -> void:
	name = "StillHereBackdrop"
	later = is_later
	water_material = ShaderMaterial.new()
	water_material.shader = SHADER
	if later:
		# Clear water: lighter, greener, the bottom close under the surface.
		water_material.set_shader_parameter("deep_color", Color(0.10, 0.24, 0.26))
		water_material.set_shader_parameter("shallow_color", Color(0.20, 0.38, 0.36))
		water_material.set_shader_parameter("crest_color", Color(0.62, 0.74, 0.70))
		water_material.set_shader_parameter("sky_tint", Color(0.56, 0.66, 0.74))
	else:
		# The morning after: slate water under a low grey sky.
		water_material.set_shader_parameter("deep_color", Color(0.05, 0.08, 0.09))
		water_material.set_shader_parameter("shallow_color", Color(0.11, 0.15, 0.16))
		water_material.set_shader_parameter("crest_color", Color(0.30, 0.33, 0.33))
		water_material.set_shader_parameter("sky_tint", Color(0.34, 0.33, 0.36))
	# The harbour west of the quay, and the two basins beside the apron.
	_water(Rect2(-half - 600.0, -700.0, 600.0 + 10.0, 1400.0))
	_water(Rect2(-30.0, 16.4, 10.0, half - 16.4 + 300.0))
	_water(Rect2(-30.0, -half - 300.0, 10.0, half - 16.4 + 300.0))
	_land(half)
	_quay_edges(half)
	_pier()
	_waterworks()
	_low_water()
	_city()
	_headland(half)
	if later:
		_ferry()
		_flock()
	else:
		_smoke_columns()
		_work_front()

## Replace the square's single floor with the land rectangles, so the basins
## either side of the apron open onto water at its real depth.
static func split_floor(cover: Node3D, floor_node: MeshInstance3D) -> void:
	if floor_node == null:
		return
	floor_node.visible = false
	for index: int in range(LAND.size()):
		var rect: Rect2 = LAND[index]
		var land: MeshInstance3D = MeshInstance3D.new()
		land.name = "RefugeLand%d" % index
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = rect.size
		land.mesh = plane
		land.position = Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5)
		land.material_override = floor_node.material_override
		cover.add_child(land)

func _water(rect: Rect2) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = "Harbour"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = rect.size
	plane.subdivide_width = clampi(int(rect.size.x / 16.0), 1, 32)
	plane.subdivide_depth = clampi(int(rect.size.y / 16.0), 1, 32)
	node.mesh = plane
	node.position = Vector3(rect.position.x + rect.size.x * 0.5, WATER_LEVEL, rect.position.y + rect.size.y * 0.5)
	node.material_override = water_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

## The headland the refuge stands on runs on past the square: ground, a
## shore road and the town's other streets.
func _land(half: float) -> void:
	var ground: StandardMaterial3D = _material(Color("4f5148") if not later else Color("586048"))
	var land: MeshInstance3D = _box(Vector3(half + 200.0, -0.02, 0.0), Vector3(400.0, 0.02, 800.0), ground)
	land.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(Vector3(-10.0 + 5.0, -0.02, half + 150.0), Vector3(30.0, 0.02, 300.0), ground)
	_box(Vector3(-10.0 + 5.0, -0.02, -half - 150.0), Vector3(30.0, 0.02, 300.0), ground)
	if later:
		# Meadow on the far shore where the old yards were.
		var grass: StandardMaterial3D = _material(Color("5f7446"))
		_box(Vector3(half + 150.0, 0.01, 0.0), Vector3(200.0, 0.02, 500.0), grass)

func _quay_edges(half: float) -> void:
	var face: StandardMaterial3D = _material(Color("6f6c62"))
	var stain: StandardMaterial3D = _material(Color("3d3e39") if not later else Color("42513f"))
	var depth: float = -WATER_LEVEL + 0.6
	for span: Array in [
		[Vector3(-30.2, 0, 9.8), Vector3(0.4, depth, 13.2)],
		[Vector3(-30.2, 0, -9.8), Vector3(0.4, depth, 13.2)],
		[Vector3(-25.0, 0, 16.6), Vector3(10.4, depth, 0.4)],
		[Vector3(-25.0, 0, -16.6), Vector3(10.4, depth, 0.4)],
		[Vector3(-20.2, 0, 16.4 + (half - 16.4 + 100.0) * 0.5), Vector3(0.4, depth, half - 16.4 + 100.0)],
		[Vector3(-20.2, 0, -16.4 - (half - 16.4 + 100.0) * 0.5), Vector3(0.4, depth, half - 16.4 + 100.0)],
	]:
		var at: Vector3 = span[0]
		var size: Vector3 = span[1]
		_box(Vector3(at.x, -depth * 0.5, at.z), size, face)
		# The tide line: dark weed the morning after, green years on.
		_box(Vector3(at.x, WATER_LEVEL + 0.35, at.z), size + Vector3(0.04, -depth + 0.7, 0.04), stain)

## The long pier back to the waterworks, on its timber piles. Inside the
## square its deck is the map's own floor; past the barricade it is drawn.
func _pier() -> void:
	var deck: StandardMaterial3D = _material(Color("7d7768"))
	var timber: StandardMaterial3D = _material(Color("5a4a3b"))
	var rail: StandardMaterial3D = _material(Color("3a4240"))
	var start: float = -40.0
	var length: float = 108.0
	_box(Vector3(start - length * 0.5, -0.4, 0.0), Vector3(length, 0.8, 6.4), deck)
	# The deck inside the square, laid over the floor between the rails.
	var planks: StandardMaterial3D = _material(Color("6e675a"))
	_box(Vector3(-35.0, 0.004, 0.0), Vector3(10.0, 0.008, 6.4), planks)
	for index: int in range(24):
		_box(Vector3(-39.6 + float(index) * 0.42, 0.01, 0.0), Vector3(0.04, 0.004, 6.4), timber)
	for index: int in range(int(length / 6.0)):
		var x: float = start - 3.0 - float(index) * 6.0
		for side: float in [-3.4, 3.4]:
			_box(Vector3(x, WATER_LEVEL * 0.5 - 0.6, side), Vector3(0.5, 2.6, 0.5), timber)
		_box(Vector3(x, 0.55, -3.3), Vector3(0.12, 1.1, 0.12), rail)
		_box(Vector3(x, 0.55, 3.3), Vector3(0.12, 1.1, 0.12), rail)
		if index % 4 == 1:
			_lamp(Vector3(x, 0.0, 3.3), 4.2, later or index % 8 == 1)
	_box(Vector3(start - length * 0.5, 1.05, -3.3), Vector3(length, 0.08, 0.08), rail)
	_box(Vector3(start - length * 0.5, 1.05, 3.3), Vector3(length, 0.08, 0.08), rail)
	# Piles under the walkable deck inside the square.
	for x: float in [-31.0, -34.0, -37.0]:
		for side: float in [-3.4, 3.4]:
			_box(Vector3(x, WATER_LEVEL * 0.5 - 0.6, side), Vector3(0.5, 2.6, 0.5), timber)

## The waterworks across the water: the tower the free agents talked from,
## its filter beds and pump houses on the far quay.
func _waterworks() -> void:
	var concrete: StandardMaterial3D = _material(Color("8a877c") if later else Color("6c6a62"))
	var dark: StandardMaterial3D = _material(Color("2a2f30"))
	var at: Vector3 = WATERWORKS
	# The far quay the pier lands on, and the sluice houses along it.
	_box(Vector3(-182.0, -0.4, -6.0), Vector3(60.0, 0.8, 70.0), _material(Color("6f6c62")))
	_box(at + Vector3(0.0, 12.0, 0.0), Vector3(16.0, 24.0, 14.0), concrete)
	_box(at + Vector3(0.0, 24.3, 0.0), Vector3(16.4, 0.6, 14.4), _material(Color("8f8d82")))
	_box(at + Vector3(4.0, 28.0, 0.0), Vector3(0.25, 8.0, 0.25), _material(Color("3a403f")))
	for x: float in [-26.0, -14.0, 16.0]:
		_box(at + Vector3(x, 4.0, -10.0 + (x * 0.2)), Vector3(10.0, 8.0, 14.0), concrete)
	# The control room's windows facing the refuge.
	for level: int in range(6):
		for column: int in range(4):
			var lit: bool = later and (level + column) % 3 == 0
			var y: float = 4.0 + float(level) * 3.2
			var pane: MeshInstance3D = _box(at + Vector3(8.06, y, -5.0 + float(column) * 3.3), Vector3(0.08, 1.6, 1.5),
				_material(WINDOW, true) if lit else dark)
			pane.name = "TowerWindow"
	if not later:
		# One lamp stays on in the control room after the talking is done.
		_box(at + Vector3(8.08, 21.6, 0.0), Vector3(0.08, 1.2, 1.4), _material(WINDOW, true, 2.2))
	else:
		# Years on the tower wears a green coat on its weather side, and a
		# garden on its roof.
		var ivy: StandardMaterial3D = _material(Color("4a6b3a"))
		for index: int in range(7):
			var z: float = -6.0 + float(index) * 2.0
			var tall: float = 6.0 + float((index * 7) % 5) * 3.0
			_box(at + Vector3(8.1, tall * 0.5, z), Vector3(0.12, tall, 1.6), ivy)
		for index: int in range(5):
			_tree(at + Vector3(-4.0 + float(index) * 2.0, 24.6, -3.0 + float(index % 2) * 4.0), 1.4)
		for index: int in range(18):
			_tree(at + Vector3(-50.0 + float(index) * 6.0, 0.0, -34.0 + float((index * 7) % 5) * 3.0), 3.0 + float(index % 3))

## Low Water across the water to the south-west: homes, the roof tanks the
## party ran over, the tram workshop's crane.
func _low_water() -> void:
	var walls: Array[StandardMaterial3D] = [_material(Color("8e7658")), _material(Color("5e7a70")), _material(Color("94806c")), _material(Color("8a5e48"))]
	if not later:
		for index: int in range(walls.size()):
			walls[index] = _material(walls[index].albedo_color.darkened(0.35))
	var roof: StandardMaterial3D = _material(Color("4a4e4a"))
	var tank: StandardMaterial3D = _material(Color("5f7f7a"))
	var lit: StandardMaterial3D = _material(WINDOW, true)
	for index: int in range(26):
		var x: float = -118.0 - float(index % 7) * 13.0 - float(index / 7) * 7.0
		var z: float = -46.0 - float(index / 7) * 16.0 + float((index * 5) % 3) * 4.0
		var height: float = 7.0 + float((index * 3) % 4) * 1.8
		_box(Vector3(x, height * 0.5, z), Vector3(12.0, height, 10.0), walls[index % walls.size()])
		_box(Vector3(x, height + 0.15, z), Vector3(12.4, 0.3, 10.4), roof)
		if index % 3 == 0:
			_box(Vector3(x + 2.0, height + 1.9, z), Vector3(3.2, 3.6, 3.2), tank)
		if not later and index % 5 == 2:
			_box(Vector3(x + 6.06, height * 0.5, z), Vector3(0.1, 1.0, 1.1), lit)
		if later and index % 2 == 0:
			_tree(Vector3(x + 7.5, 0.0, z + 5.5), 3.0 + float(index % 3))
	# The workshop crane over the trench.
	var steel: StandardMaterial3D = _material(Color("3e4648"))
	_box(Vector3(-150.0, 8.0, -92.0), Vector3(0.8, 16.0, 0.8), steel)
	_box(Vector3(-144.0, 15.6, -92.0), Vector3(14.0, 0.8, 0.8), steel)
	# Low Water's own shore under the homes.
	_box(Vector3(-160.0, -0.3, -80.0), Vector3(110.0, 0.6, 90.0), _material(Color("5d5f57") if not later else Color("5f6e4c")))

## The city further off. The first light: towers dark but for a handful of
## holdouts. Years on: fewer towers, broken crowns gone green, forest where
## the streets between them were.
func _city() -> void:
	var steel: StandardMaterial3D = _material(Color("3c4446") if not later else Color("6a7270"))
	var lit: StandardMaterial3D = _material(WINDOW, true)
	for index: int in range(16):
		var angle: float = 2.25 + float(index) * 0.12
		var radius: float = 360.0 + float((index * 37) % 90)
		var height: float = 14.0 + float((index * 13) % 5) * 6.0
		var centre: Vector3 = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if later:
			if index % 3 == 1:
				continue
			# A broken crown, and something growing on what is left.
			height *= 0.55 + 0.1 * float(index % 3)
			_box(centre + Vector3(0.0, height + 1.0, 0.0), Vector3(14.0, 2.0, 14.0), _material(Color("4a6a3a")))
		_box(centre + Vector3(0.0, height * 0.5, 0.0), Vector3(18.0 + float(index % 3) * 10.0, height, 16.0), steel)
		if not later and index % 6 == 0:
			_box(centre + Vector3(8.1, height * 0.6, 0.0), Vector3(0.1, 1.2, 1.5), lit)
	if later:
		var canopy: StandardMaterial3D = _material(Color("3f5a34"))
		for index: int in range(30):
			var angle: float = 2.0 + float(index) * 0.08
			var radius: float = 230.0 + float((index * 29) % 120)
			_box(Vector3(cos(angle) * radius, 4.0, sin(angle) * radius), Vector3(28.0, 8.0 + float(index % 3) * 3.0, 24.0), canopy)

## The rest of the refuge behind the court, and the hills inland.
func _headland(half: float) -> void:
	var walls: Array[Color] = [Color("8f8473"), Color("6f776c"), Color("9a7f66"), Color("7c6a58")]
	for index: int in range(20):
		var side: float = 1.0 if index % 2 == 0 else -1.0
		var x: float = -15.0 + float(index / 2) * 7.0
		var z: float = side * (half + 6.0 + float((index * 3) % 3) * 4.0)
		var height: float = 6.0 + float((index * 5) % 4) * 2.0
		var colour: Color = walls[index % walls.size()]
		colour = colour.darkened(0.25) if not later else colour.lightened(0.08)
		_box(Vector3(x, height * 0.5, z), Vector3(6.4, height, 9.0), _material(colour))
		_box(Vector3(x, height + 0.2, z), Vector3(6.8, 0.4, 9.4), _material(Color("4a4e4a")))
	for index: int in range(8):
		var z: float = -60.0 + float(index) * 17.0
		var height: float = 8.0 + float((index * 7) % 4) * 3.0
		_box(Vector3(half + 12.0 + float(index % 3) * 6.0, height * 0.5, z), Vector3(10.0, height, 14.0), _material(walls[index % walls.size()].darkened(0.3 if not later else 0.0)))
	var hill: StandardMaterial3D = _material(Color("4c5446") if not later else Color("55703f"))
	for index: int in range(6):
		var z: float = -180.0 + float(index) * 72.0
		var hump: MeshInstance3D = _box(Vector3(half + 140.0 + float(index % 2) * 30.0, 6.0, z), Vector3(120.0, 24.0 + float(index % 3) * 8.0, 90.0), hill)
		hump.rotation.y = 0.3 * float(index % 3)
	if later:
		for index: int in range(16):
			_tree(Vector3(half + 30.0 + float(index % 4) * 9.0, 0.0, -50.0 + float(index) * 7.0), 3.5 + float(index % 3))

## Years on: the ferry moored against the pier, its awning up.
func _ferry() -> void:
	var hull: StandardMaterial3D = _material(Color("3f6f62"))
	var cream: StandardMaterial3D = _material(Color("e4d8b4"))
	var dark: StandardMaterial3D = _material(Color("2a2f30"))
	_box(Vector3(-47.0, WATER_LEVEL + 0.5, -6.2), Vector3(9.0, 1.4, 3.2), hull)
	_box(Vector3(-47.0, WATER_LEVEL + 1.3, -6.2), Vector3(9.2, 0.2, 3.4), cream)
	_box(Vector3(-48.0, WATER_LEVEL + 2.3, -6.2), Vector3(4.0, 1.8, 2.6), cream)
	for x: float in [-49.4, -48.0, -46.6]:
		_box(Vector3(x, WATER_LEVEL + 2.5, -4.89), Vector3(1.0, 0.7, 0.04), dark)
	var awning: StandardMaterial3D = _material(Color("c4644a"))
	_box(Vector3(-44.6, WATER_LEVEL + 2.6, -6.2), Vector3(3.0, 0.08, 3.0), awning)

## Years on: birds over the water, circling the way birds do.
func _flock() -> void:
	var feather: StandardMaterial3D = _material(Color("2a2a2a"))
	for index: int in range(9):
		var bird: Node3D = Node3D.new()
		bird.name = "Bird"
		bird.set_meta("orbit", Vector4(-70.0 - float(index % 3) * 18.0, 14.0 + float(index % 4) * 3.0, float(index) * 0.7, 12.0 + float(index % 3) * 6.0))
		add_child(bird)
		for side: float in [-1.0, 1.0]:
			var wing: MeshInstance3D = MeshInstance3D.new()
			var mesh: BoxMesh = BoxMesh.new()
			mesh.size = Vector3(0.7, 0.05, 0.22)
			wing.mesh = mesh
			wing.material_override = feather
			wing.position = Vector3(side * 0.34, 0.0, 0.0)
			wing.name = "Wing"
			bird.add_child(wing)
		_birds.append(bird)

## The morning after: smoke still standing over Low Water and the city.
func _smoke_columns() -> void:
	for index: int in range(5):
		var base: Vector3 = Vector3(-140.0 - float(index) * 30.0, 6.0, -60.0 - float((index * 31) % 70))
		for puff: int in range(7):
			var material: StandardMaterial3D = StandardMaterial3D.new()
			material.albedo_color = Color(0.22, 0.22, 0.23, 0.32 - float(puff) * 0.03)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var node: MeshInstance3D = MeshInstance3D.new()
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = 5.0 + float(puff) * 2.2
			sphere.height = sphere.radius * 2.0
			sphere.radial_segments = 8
			sphere.rings = 4
			node.mesh = sphere
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.position = base + Vector3(float(puff) * 4.0, float(puff) * 9.0, float(puff) * -1.5)
			node.set_meta("rise", float(puff))
			add_child(node)
			_smoke.append(node)

## The morning after: the work front's muted cyan working lights, moving on
## to the next district, far up the coast. Never toward the refuge.
func _work_front() -> void:
	var work: StandardMaterial3D = _material(CYAN, true, 1.6)
	for index: int in range(9):
		var light: MeshInstance3D = _box(Vector3(-150.0 - float(index % 3) * 20.0, 2.0 + float(index % 2), 140.0 + float(index) * 9.0), Vector3(0.7, 0.7, 0.7), work)
		light.set_meta("start", light.position)
		_work_lights.append(light)

func _tree(at: Vector3, size: float) -> void:
	var bark: StandardMaterial3D = _material(Color("4a3a2a"))
	var leaves: StandardMaterial3D = _material(Color("4f6d3c") if int(at.x) % 2 == 0 else Color("5a7a42"))
	_box(at + Vector3(0.0, size * 0.6, 0.0), Vector3(size * 0.16, size * 1.2, size * 0.16), bark)
	_box(at + Vector3(0.0, size * 1.45, 0.0), Vector3(size, size * 0.9, size), leaves)
	_box(at + Vector3(size * 0.2, size * 1.9, -size * 0.1), Vector3(size * 0.7, size * 0.6, size * 0.7), leaves)

func _lamp(at: Vector3, height: float, lit: bool) -> void:
	var pole: StandardMaterial3D = _material(Color("2b3130"))
	_box(at + Vector3(0, height * 0.5, 0), Vector3(0.14, height, 0.14), pole)
	_box(at + Vector3(0, height + 0.12, 0), Vector3(0.45, 0.24, 0.45), _material(WARM, true) if lit and not later else _material(Color("3b3730")))

func _box(at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	add_child(node)
	return node

static func _material(color: Color, glow: bool = false, energy: float = 1.4) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = energy
	return material

func _process(delta: float) -> void:
	if not is_finite(delta):
		return
	_clock = fmod(_clock + maxf(delta, 0.0), 3600.0)
	for puff: MeshInstance3D in _smoke:
		var rise: float = float(puff.get_meta("rise"))
		puff.scale = Vector3.ONE * (1.0 + 0.04 * sin(_clock * 0.3 + rise))
	for light: MeshInstance3D in _work_lights:
		var start: Vector3 = light.get_meta("start")
		light.position = start + Vector3(-fmod(_clock * 0.8, 60.0), 0.0, fmod(_clock * 1.1, 80.0))
	for bird: Node3D in _birds:
		var orbit: Vector4 = bird.get_meta("orbit")
		var angle: float = _clock * 0.25 + orbit.z
		bird.position = Vector3(orbit.x + cos(angle) * orbit.w, orbit.y + sin(_clock * 0.7 + orbit.z) * 0.6, sin(angle) * orbit.w * 0.6)
		bird.rotation.y = -angle
		var flap: float = sin(_clock * 9.0 + orbit.z * 3.0) * 0.5
		for child: Node in bird.get_children():
			var wing: Node3D = child as Node3D
			wing.rotation.z = flap * signf(wing.position.x)
