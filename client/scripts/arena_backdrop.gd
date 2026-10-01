extends Node3D
class_name ArenaBackdrop

## Scenery is strictly outside the server's playable square. Wall signs are flat
## markings; none of this supplies cover, a platform, or an interaction target.
const FONT: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")

func build(map_id: int, half: float, venue: String = "") -> void:
	name = "Backdrop"
	if venue == "moon_port":
		var lunar: MoonBackdrop = MoonBackdrop.new()
		lunar.build(half)
		add_child(lunar)
		return
	if venue == "low_water":
		_build_town(half)
		return
	var steel: StandardMaterial3D = _metal(Color("41494b"))
	var edge: StandardMaterial3D = _metal(Color("6b716d"))
	var accent_material: StandardMaterial3D = _metal(ArenaMaterials.accent(map_id))
	var lamp: StandardMaterial3D = _metal(Color("c49559"))
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index: int in range(3):
		var x: float = (float(index) - 1.0) * half * 0.72
		var height: float = 12.0 + float(index % 2) * 7.0
		var z: float = -half - 10.0 - float(index % 2) * 4.0
		_box(Vector3(x, height * 0.5, z), Vector3(15.0, height, 12.0), steel)
		_box(Vector3(x, height - 0.3, z), Vector3(16.0, 0.6, 13.0), edge)
		_box(Vector3(x, 7.5, z + 6.05), Vector3(14.0, 0.8, 0.12), accent_material)
		for window: int in range(5):
			_box(Vector3(x - 5.5 + float(window) * 2.7, height - 2.8, z + 6.08), Vector3(1.2, 0.35, 0.14), lamp)
		var stack: MeshInstance3D = MeshInstance3D.new()
		var pipe: CylinderMesh = CylinderMesh.new()
		pipe.top_radius = 1.15
		pipe.bottom_radius = 1.35
		pipe.height = 10.0 + float(index) * 2.0
		pipe.radial_segments = 8
		stack.mesh = pipe
		stack.material_override = steel
		stack.position = Vector3(x - 3.0, height + pipe.height * 0.5, z)
		add_child(stack)
		_box(Vector3(x - 3.0, height + pipe.height - 1.2, z), Vector3(2.7, 0.55, 2.7), accent_material)
	# A service gantry outside the east boundary breaks the enclosing-box skyline.
	for z: float in [-half * 0.58, half * 0.58]:
		_box(Vector3(half + 4.0, 7.0, z), Vector3(1.4, 14.0, 1.4), edge)
	_box(Vector3(half + 4.0, 13.4, 0.0), Vector3(2.0, 1.4, half * 1.24), steel)
	var wall_material: ShaderMaterial = ArenaMaterials.make(map_id, 1)
	_box(Vector3(half * 0.25, 6.0, half + 10.0), Vector3(28.0, 12.0, 16.0), wall_material)
	_box(Vector3(half * 0.25, 12.1, half + 10.0), Vector3(30.0, 0.8, 18.0), edge)
	_box(Vector3(-half - 9.0, 6.5, half * 0.3), Vector3(14.0, 13.0, 26.0), wall_material)
	_box(Vector3(-half - 9.0, 13.2, half * 0.3), Vector3(16.0, 0.8, 28.0), edge)
	_sign("CONTINUANCE // 67" if map_id in [2, 3, 4] else "SCRAP FREQUENCY // 67", Vector3(0.0, 5.7, -half + 0.54), 0.0, 0.036)
	_sign("AUTHORIZED PERSONNEL ONLY" if map_id in [2, 3, 4] else "MEAT PROXIES WELCOME", Vector3(0.0, 4.0, -half + 0.55), 0.0, 0.015)
	_sign("BAY 02", Vector3(-half + 0.54, 5.4, 0.0), PI * 0.5, 0.04)
	_sign("BAY 03", Vector3(half - 0.54, 5.4, 0.0), -PI * 0.5, 0.04)

func _build_town(half: float) -> void:
	var plaster: Array[StandardMaterial3D] = [
		_metal(Color("b6977a")), _metal(Color("879587")),
		_metal(Color("a97f67")), _metal(Color("c3b38e")),
	]
	var roof: StandardMaterial3D = _metal(Color("58625c"))
	var frame: StandardMaterial3D = _metal(Color("d1c4a5"))
	var dark: StandardMaterial3D = _metal(Color("394a48"))
	var curtains: StandardMaterial3D = _metal(Color("b78d65"))
	# Four rows of homes sit entirely beyond the boundary. Their upper windows,
	# clothes rails and water barrels establish a lived-in district skyline.
	for side: int in range(4):
		for index: int in range(5):
			var home: Node3D = Node3D.new()
			home.name = "Home%d_%d" % [side, index]
			home.rotation.y = float(side) * PI * 0.5
			var centre: Vector3 = Vector3((float(index) - 2.0) * half * 0.33, 0.0, -half - 6.0)
			home.position = centre.rotated(Vector3.UP, home.rotation.y)
			add_child(home)
			var height: float = 10.0 + float((index + side) % 3) * 1.5
			_town_piece(home, Vector3(0.0, height * 0.5, 0.0), Vector3(9.0, height, 8.0), plaster[(index + side) % plaster.size()])
			_town_piece(home, Vector3(0.0, height + 0.2, 0.0), Vector3(9.6, 0.4, 8.8), roof)
			for level: int in range(2):
				var y: float = height - 1.7 - float(level) * 2.2
				for window: int in range(3):
					var x: float = (float(window) - 1.0) * 2.5
					_town_piece(home, Vector3(x, y, 4.03), Vector3(1.5, 1.5, 0.1), frame)
					_town_piece(home, Vector3(x, y, 4.10), Vector3(1.25, 1.25, 0.08), dark)
					if (window + index + level) % 3 == 0:
						_town_piece(home, Vector3(x + 0.31, y, 4.16), Vector3(0.58, 1.15, 0.04), curtains)
			_town_piece(home, Vector3(-2.1, height + 0.85, 0.4), Vector3(1.25, 1.3, 1.25), dark)
			_town_piece(home, Vector3(1.6, height + 0.8, 0.4), Vector3(2.7, 0.08, 0.08), frame)
			_town_piece(home, Vector3(1.0, height + 0.4, 0.4), Vector3(0.55, 0.75, 0.04), curtains)
			_town_piece(home, Vector3(2.0, height + 0.4, 0.4), Vector3(0.65, 0.75, 0.04), plaster[(index + 1) % plaster.size()])

func _town_piece(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)

func _box(at: Vector3, size: Vector3, material: Material) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	add_child(node)

func _sign(text: String, at: Vector3, yaw: float, pixel_size: float) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = 32
	label.pixel_size = pixel_size
	label.position = at
	label.rotation.y = yaw
	label.modulate = Color("c8c1aa")
	label.outline_size = 0
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.double_sided = false
	add_child(label)

static func _metal(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material
