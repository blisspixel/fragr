class_name WaterworksBackdrop
extends Node3D

## Local Exception scenery strictly outside the server's playable square, and
## the harbour water inside the two fenced basins. Nothing here is cover, a
## platform or an interaction: the quay edges, the pier beyond the lane and
## the refuge across the water are drawn only. The square's floor is split so
## the basins read as water at their real depth below the quay.
const SHADER: Shader = preload("res://assets/shaders/harbour_water.gdshader")
const WATER_LEVEL: float = -1.15
## Land inside the square: everything west of the fence, plus the crowd strip
## and lane behind the gate. The two basins are water.
const LAND: Array[Rect2] = [Rect2(-64, -64, 121, 128), Rect2(57, -22, 7, 44)]
const BASINS: Array[Rect2] = [Rect2(57, 22, 7, 42), Rect2(57, -64, 7, 42)]
const QUAY: Color = Color("6f6c62")
const QUAY_DARK: Color = Color("3d3e39")
const WARM: Color = Color("ffc98a")
const WINDOW: Color = Color("f2b56b")
const CYAN: Color = Color("6fa8a4")

var water_material: ShaderMaterial
var _lamp_lights: Array[OmniLight3D] = []

func build(half: float) -> void:
	name = "WaterworksBackdrop"
	water_material = ShaderMaterial.new()
	water_material.shader = SHADER
	_water(Rect2(half, -half - 400.0, 600.0, half * 2.0 + 800.0))
	_water(Rect2(-half - 400.0, half + 30.0, half * 2.0 + 400.0, 400.0))
	for basin: Rect2 in BASINS:
		_water(basin)
	_quay_edges(half)
	_pier(half)
	_refuge(half)
	_districts(half)

## Replace the square's single floor plane with the land rectangles so the
## basins open onto real water. The floor material is the ground surface.
static func split_floor(cover: Node3D, floor_node: MeshInstance3D) -> void:
	if floor_node == null:
		return
	floor_node.visible = false
	for index: int in range(LAND.size()):
		var rect: Rect2 = LAND[index]
		var land: MeshInstance3D = MeshInstance3D.new()
		land.name = "WaterworksLand%d" % index
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

## Concrete quay faces from the waterline up to the quay, with a dark
## weathered band where the tide has been and iron mooring rings.
func _quay_edges(half: float) -> void:
	var face: StandardMaterial3D = _material(QUAY)
	var stain: StandardMaterial3D = _material(QUAY_DARK)
	var iron: StandardMaterial3D = _material(Color("2f3633"))
	var depth: float = -WATER_LEVEL + 0.6
	for span: Array in [
		[Vector3(57.0, 0, 43.0), Vector3(0.6, depth, 42.0)],
		[Vector3(57.0, 0, -43.0), Vector3(0.6, depth, 42.0)],
		[Vector3(60.5, 0, 22.0), Vector3(7.0, depth, 0.6)],
		[Vector3(60.5, 0, -22.0), Vector3(7.0, depth, 0.6)],
		[Vector3(64.0, 0, 12.5), Vector3(0.6, depth, 19.0)],
		[Vector3(64.0, 0, -12.5), Vector3(0.6, depth, 19.0)],
	]:
		var at: Vector3 = span[0]
		var size: Vector3 = span[1]
		_box(Vector3(at.x, -depth * 0.5 + 0.0, at.z), size, face)
		_box(Vector3(at.x, WATER_LEVEL + 0.35, at.z), size + Vector3(0.04, -depth + 0.7, 0.04), stain)
	for z: float in [30.0, 40.0, 50.0, -30.0, -40.0, -50.0]:
		_box(Vector3(57.35, -0.35, z), Vector3(0.12, 0.35, 0.35), iron)

## The pier runs on past the gate toward the refuge. Its deck, rails, lamps
## and the people already crossing are scenery beyond the square's edge.
func _pier(half: float) -> void:
	var deck: StandardMaterial3D = _material(Color("7d7768"))
	var timber: StandardMaterial3D = _material(Color("5a4a3b"))
	var rail: StandardMaterial3D = _material(Color("3a4240"))
	var length: float = 120.0
	_box(Vector3(half + length * 0.5, -0.4, 0.0), Vector3(length, 0.8, 6.0), deck)
	for index: int in range(int(length / 6.0)):
		var x: float = half + 3.0 + float(index) * 6.0
		for side: float in [-3.4, 3.4]:
			_box(Vector3(x, WATER_LEVEL * 0.5 - 0.6, side), Vector3(0.5, 2.6, 0.5), timber)
		_box(Vector3(x, 0.55, -3.1), Vector3(0.12, 1.1, 0.12), rail)
		_box(Vector3(x, 0.55, 3.1), Vector3(0.12, 1.1, 0.12), rail)
		if index % 3 == 1:
			_lamp(Vector3(x, 0.0, 3.0), 4.2, 2.2)
	_box(Vector3(half + length * 0.5, 1.05, -3.1), Vector3(length, 0.08, 0.08), rail)
	_box(Vector3(half + length * 0.5, 1.05, 3.1), Vector3(length, 0.08, 0.08), rail)

## The refuge across the water: a low headland of homes and stores, every
## window lit, the end of the pier at its gate. Inside the exception.
func _refuge(half: float) -> void:
	var walls: Array[StandardMaterial3D] = [_material(Color("8f8473")), _material(Color("6f776c")), _material(Color("9a7f66"))]
	var roof: StandardMaterial3D = _material(Color("4a4e4a"))
	var glow: StandardMaterial3D = _material(WINDOW, true)
	var land: StandardMaterial3D = _material(Color("4f5148"))
	var x0: float = half + 120.0
	_box(Vector3(x0 + 40.0, -0.6, 0.0), Vector3(90.0, 1.2, 160.0), land)
	for index: int in range(14):
		var z: float = -60.0 + float(index) * 9.0 + float(index % 3) * 1.5
		var x: float = x0 + 12.0 + float((index * 7) % 5) * 6.0
		var height: float = 5.0 + float((index * 5) % 4) * 2.0
		_box(Vector3(x, height * 0.5, z), Vector3(7.0, height, 6.0), walls[index % walls.size()])
		_box(Vector3(x, height + 0.25, z), Vector3(7.6, 0.5, 6.6), roof)
		for level: int in range(int(height / 2.6)):
			for window: int in range(2):
				if (index + level + window) % 4 != 0:
					_box(Vector3(x - 3.53, 1.6 + float(level) * 2.4, z - 1.4 + float(window) * 2.8), Vector3(0.08, 0.9, 0.8), glow)
	# A few warm pools on the refuge shore read at range through the fog.
	for z: float in [-28.0, 0.0, 26.0]:
		_lamp(Vector3(x0 + 6.0, 0.0, z), 4.8, 3.0)

## The districts around the waterworks: filter beds and stores to the west,
## warehouses beyond the yard and the trench, the city further off with
## most windows dark. A few muted cyan working lights move on, elsewhere.
func _districts(half: float) -> void:
	var concrete: StandardMaterial3D = _material(Color("5f625b"))
	var brick: StandardMaterial3D = _material(Color("6b5246"))
	var steel: StandardMaterial3D = _material(Color("454d4e"))
	var lit: StandardMaterial3D = _material(WINDOW, true)
	var work: StandardMaterial3D = _material(CYAN, true)
	for side: int in range(3):
		for index: int in range(9):
			var along: float = (float(index) - 4.0) * half * 0.26
			var height: float = 9.0 + float((index * 7 + side * 3) % 5) * 4.0
			var depth: float = 14.0 + float(index % 3) * 6.0
			var centre: Vector3
			var size: Vector3
			match side:
				0:
					centre = Vector3(-half - 10.0 - depth * 0.5, height * 0.5, along)
					size = Vector3(depth, height, half * 0.22)
				1:
					centre = Vector3(along * 0.8, height * 0.5, half + 12.0 + depth * 0.5)
					size = Vector3(half * 0.22, height, depth)
				_:
					centre = Vector3(along * 0.8, height * 0.5, -half - 12.0 - depth * 0.5)
					size = Vector3(half * 0.22, height, depth)
			var material: StandardMaterial3D = [concrete, brick, steel][(index + side) % 3]
			_box(centre, size, material)
			# Mostly dark windows: a district after the switch, a few holdouts.
			if (index * 3 + side) % 4 == 0:
				var face: Vector3 = Vector3(size.x * 0.5 + 0.06, 0, 0) if side == 0 else Vector3(0, 0, -size.z * 0.5 - 0.06 if side == 1 else size.z * 0.5 + 0.06)
				_box(centre + face + Vector3(0, height * 0.2, 0), Vector3(0.1, 0.9, 1.2) if side == 0 else Vector3(1.2, 0.9, 0.1), lit)
	# Far skyline: the city along the river, mostly unlit.
	for index: int in range(18):
		var angle: float = -1.2 + float(index) * 0.14
		var radius: float = 260.0 + float((index * 37) % 60)
		var height: float = 18.0 + float((index * 13) % 5) * 9.0
		var centre: Vector3 = Vector3(-cos(angle) * radius, height * 0.5, sin(angle) * radius)
		_box(centre, Vector3(16.0, height, 16.0), steel)
	for index: int in range(7):
		var light: MeshInstance3D = _box(Vector3(-140.0 - float(index) * 22.0, 2.5, -90.0 + float(index) * 31.0), Vector3(0.6, 0.6, 0.6), work)
		light.set_meta("drift", float(index))

func _lamp(at: Vector3, height: float, energy: float) -> void:
	var pole: StandardMaterial3D = _material(Color("2b3130"))
	_box(at + Vector3(0, height * 0.5, 0), Vector3(0.14, height, 0.14), pole)
	_box(at + Vector3(0, height + 0.12, 0), Vector3(0.45, 0.24, 0.45), _material(WARM, true))
	var light: OmniLight3D = OmniLight3D.new()
	light.position = at + Vector3(0, height - 0.2, 0)
	light.light_color = WARM
	light.light_energy = energy
	light.omni_range = 10.0
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 90.0
	light.distance_fade_length = 30.0
	add_child(light)
	_lamp_lights.append(light)

func _box(at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	add_child(node)
	return node

static func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.4
	return material

func _process(delta: float) -> void:
	if not is_finite(delta):
		return
	for child: Node in get_children():
		if child.has_meta("drift"):
			var node: Node3D = child as Node3D
			node.position.z += sin(Time.get_ticks_msec() * 0.0002 + float(child.get_meta("drift"))) * delta * 0.6
