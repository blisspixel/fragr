extends Node3D
class_name ArenaBackdrop

## Scenery is strictly outside the server's playable square. Wall signs are flat
## markings; none of this supplies cover, a platform, or an interaction target.
const FONT: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")

func build(map_id: int, half: float) -> void:
	name = "Backdrop"
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
	return material
