class_name NotaryView
extends Node3D

## Source-owned, noncombat Notary silhouette. M02 poses it behind glass;
## a later enemy renderer can reuse the body without inheriting mission rules.
const STEEL: Color = Color("252a2c")
const CASING: Color = Color("555f60")
const FAN_WELL: Color = Color("151a1c")
const OPTIC: Color = Color("81312d")
const SEAL: Color = Color("a0483c")

var _body: Node3D
var _elapsed: float = 0.0

func _init() -> void:
	_body = Node3D.new()
	_body.name = "NotaryBody"
	add_child(_body)
	var steel: StandardMaterial3D = _material(STEEL)
	var casing: StandardMaterial3D = _material(CASING)
	var well: StandardMaterial3D = _material(FAN_WELL)
	var red: StandardMaterial3D = _material(OPTIC)
	var seal: StandardMaterial3D = _material(SEAL)
	_box(_body, "BlackBox", Vector3.ZERO, Vector3(0.76, 0.43, 0.52), steel)
	_box(_body, "LowerHousing", Vector3(0.0, -0.23, 0.01), Vector3(0.63, 0.16, 0.46), casing)
	_box(_body, "FrontShutter", Vector3(0.0, -0.03, 0.28), Vector3(0.37, 0.25, 0.055), well)
	_box(_body, "DimOptic", Vector3(0.0, -0.03, 0.313), Vector3(0.17, 0.085, 0.018), red)
	_box(_body, "OfficeSeal", Vector3(0.25, 0.11, 0.272), Vector3(0.13, 0.10, 0.017), seal)
	for side: float in [-1.0, 1.0]:
		var duct: Node3D = Node3D.new()
		duct.name = "LeftDuct" if side < 0.0 else "RightDuct"
		duct.position = Vector3(side * 0.53, 0.28, 0.0)
		_body.add_child(duct)
		_cylinder(duct, "DuctRim", Vector3.ZERO, 0.31, 0.12, casing)
		_cylinder(duct, "DuctWell", Vector3(0.0, 0.069, 0.0), 0.24, 0.016, well)
		_cylinder(duct, "Hub", Vector3(0.0, 0.083, 0.0), 0.08, 0.02, steel)
		for blade: int in range(3):
			var arm: Node3D = Node3D.new()
			arm.name = "FanArm%d" % blade
			arm.rotation.y = float(blade) * TAU / 3.0
			duct.add_child(arm)
			_box(arm, "Blade", Vector3(0.0, 0.081, 0.14), Vector3(0.065, 0.012, 0.22), casing)

func set_render_layers(layers: int) -> void:
	for part: Node in find_children("*", "VisualInstance3D", true, false):
		(part as VisualInstance3D).layers = layers

func advance(delta: float) -> void:
	_elapsed += delta
	# A small surveillance sweep and pause. This is never a windup or aim state.
	_body.position.x = sin(_elapsed * 0.65) * 0.25
	_body.position.y = sin(_elapsed * 1.1) * 0.055
	_body.rotation.y = sin(_elapsed * 0.37) * 0.22

func _box(parent: Node3D, label: String, offset: Vector3, size: Vector3,
		material: StandardMaterial3D) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = offset
	part.material_override = material
	parent.add_child(part)
	return part

func _cylinder(parent: Node3D, label: String, offset: Vector3, radius: float,
		height: float, material: StandardMaterial3D) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = label
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	part.mesh = mesh
	part.position = offset
	part.material_override = material
	parent.add_child(part)
	return part

func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.18
	material.roughness = 0.82
	return material
