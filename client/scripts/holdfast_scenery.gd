class_name HoldfastScenery
extends Node3D

## Surface dressing follows registered geometry. The island water presenter
## owns the sea; these meshes add no collision or cover.
const FONT: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")

static func material_for(solid: Dictionary, _index: int) -> Material:
	var material: ShaderMaterial = ArenaMaterials.make(7, 2)
	var x: float = (float(solid["min_x"]) + float(solid["max_x"])) * 0.5
	var z: float = (float(solid["min_z"]) + float(solid["max_z"])) * 0.5
	var color: Color = Color("aaa98b")
	if float(solid.get("bottom", 0.0)) == 0.0:
		color = Color("b4b18c") if float(solid["top"]) < 3.0 else Color("869574")
		material.set_shader_parameter("markings_enabled", false)
		material.set_shader_parameter("tile_enabled", false)
		material.set_shader_parameter("base_shade", 0.0)
		material.set_shader_parameter("panel_contrast", 0.0)
	elif x < -112:
		color = Color("b6a47f") if z > 0 else Color("91aa97")
	elif x > 112:
		color = Color("e0d6b4") if z > 0 else Color("94adb0")
	elif absf(x) < 65 and z < -60:
		color = Color("798b85")
	material.set_shader_parameter("surface_color", color)
	material.set_shader_parameter("panel_size", 6.0)
	material.set_shader_parameter("sector_variation", 0.03)
	return material

func build(info: Dictionary) -> void:
	if int(info.get("map_id", 0)) != 7:
		return
	name = "HoldfastCoast"
	position.y = 3.0
	var asphalt: Material = _paint("666e60")
	_plane(Vector3(0, 0.012, -110), Vector2(250, 18), asphalt)
	var cream: Material = _paint("d6d4ad")
	for x: float in [-112, -96, -80, -64, -48, -32, -16, 0, 16, 32, 48, 64, 80, 96, 112]:
		_plane(Vector3(x, 0.025, -110), Vector2(6, 0.7), cream)
	# Flat repaired road surfaces explain the routes between the five sites.
	for x: float in [-101, 101]:
		_plane(Vector3(x, 0.009, -10), Vector2(8, 234), _paint("8d9274"))
	_plane(Vector3(0, 0.01, -17), Vector2(210, 8), _paint("8d9274"))
	var repairs: Material = _paint("84968b")
	for x: float in [-128, -124, 124, 128]:
		var z: float = (64 if x < 0 else 65) if absf(x) == 128 else -32
		# The front wall has a central door. These shallow paint patches and
		# signs remain on its solid shoulders, never across that opening.
		_box(Vector3(x - 8, 1.4, z + 13.715), Vector3(3.2, 1.8, 0.025), repairs)
		_box(Vector3(x + 7, 3.5, z + 13.715), Vector3(4, 0.08, 0.025), cream)
	_sign("HOLDFAST_HARBOUR", Vector3(-135.5, 4.2, 77.74), 0, 0.018)
	_sign("HOLDFAST_VILLAGE", Vector3(-131.5, 4.2, -18.26), 0, 0.016)
	_sign("HOLDFAST_SERVER_HALLS", Vector3(116.5, 4.2, -18.26), 0, 0.017)
	_sign("HOLDFAST_LIGHTHOUSE", Vector3(120.5, 4.2, 78.74), 0, 0.020)
	_sign("HOLDFAST_REPAIR_NOTE", Vector3(-136, 2.45, 77.745), 0, 0.018)
	_sign("HOLDFAST_LAUNDRY_NOTE", Vector3(-132, 2.5, -18.255), 0, 0.017)
	# Lighthouse lantern sits on the actual registered tower top.
	var glass: StandardMaterial3D = _paint("ecd49c")
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_box(Vector3(127, 18.03, 112), Vector3(7.5, 0.06, 7.5), glass)
	# Low distant islets remain far beyond the server boundary.
	for offset: Vector3 in [Vector3(-330, -1, 230), Vector3(290, -1, 290), Vector3(80, -1, 470)]:
		var island: MeshInstance3D = MeshInstance3D.new()
		var hill: SphereMesh = SphereMesh.new()
		hill.radial_segments = 12
		hill.rings = 6
		island.mesh = hill
		island.scale = Vector3(110, 20, 50)
		island.position = offset
		island.material_override = _paint("667c66")
		add_child(island)
	ArenaSky.mark_world(self)

func _paint(hex: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material

func _plane(at: Vector3, dimensions: Vector2, material: Material) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.position = at
	node.material_override = material
	add_child(node)

func _box(at: Vector3, dimensions: Vector3, material: Material) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.position = at
	node.material_override = material
	add_child(node)

func _sign(key: String, at: Vector3, yaw: float, pixel: float = 0.025) -> void:
	var label: Label3D = Label3D.new()
	label.text = tr(key)
	label.font = FONT
	label.font_size = 32
	label.pixel_size = pixel
	label.position = at
	label.rotation.y = yaw
	label.modulate = Color("eee2b9")
	label.outline_size = 3
	add_child(label)

