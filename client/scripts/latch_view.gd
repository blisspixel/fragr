class_name LatchView
extends Node3D

## One provisional chassis for the ward tableau and the server-owned ally.
## The ward poses the right arm; the moving pawn supplies travelled distance.
const BONE: Color = Color("c2b9a4")
const STEEL: Color = Color("343d3d")
const CYAN: Color = Color("71b8ad")
const DARK: Color = Color("232b2c")

var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _gun: Node3D
var _flash: MeshInstance3D
var _stride: float = 0.0
var _flash_left: float = 0.0

func _init() -> void:
	var bone: StandardMaterial3D = _material(BONE)
	var steel: StandardMaterial3D = _material(STEEL)
	var cyan: StandardMaterial3D = _material(CYAN)
	var dark: StandardMaterial3D = _material(DARK)
	_box(self, "Torso", Vector3(0.0, 1.2, 0.0), Vector3(0.62, 0.78, 0.29), bone)
	_box(self, "ChestPlate", Vector3(0.0, 1.38, 0.16), Vector3(0.44, 0.38, 0.05), steel)
	_box(self, "Patch", Vector3(-0.17, 1.48, 0.195), Vector3(0.13, 0.12, 0.025), cyan)
	_box(self, "Neck", Vector3(0.0, 1.69, 0.0), Vector3(0.2, 0.16, 0.19), steel)
	_box(self, "Head", Vector3(0.0, 1.9, 0.0), Vector3(0.36, 0.32, 0.32), bone)
	_box(self, "FacePlate", Vector3(0.0, 1.91, 0.17), Vector3(0.26, 0.13, 0.025), dark)
	for side: float in [-1.0, 1.0]:
		var leg: Node3D = Node3D.new()
		leg.name = "RightLeg" if side > 0.0 else "LeftLeg"
		leg.position = Vector3(side * 0.18, 0.62, 0.0)
		add_child(leg)
		_box(leg, "Leg", Vector3(0.0, -0.24, 0.0), Vector3(0.21, 0.68, 0.22), steel)
		_box(leg, "Foot", Vector3(0.0, -0.53, 0.1), Vector3(0.23, 0.13, 0.38), bone)
		var arm: Node3D = Node3D.new()
		arm.name = "RightArm" if side > 0.0 else "LeftArm"
		arm.position = Vector3(side * 0.42, 1.42, 0.0)
		add_child(arm)
		_box(arm, "UpperArm", Vector3(0.0, -0.15, 0.0), Vector3(0.18, 0.32, 0.19), steel)
		_box(arm, "Forearm", Vector3(0.0, -0.43, 0.0),
			Vector3(0.24, 0.38, 0.25) if side > 0.0 else Vector3(0.17, 0.37, 0.20),
			bone if side > 0.0 else steel)
		_box(arm, "Hand", Vector3(0.0, -0.65, 0.01), Vector3(0.13, 0.13, 0.15), steel)
		if side > 0.0:
			_right_leg = leg
			_right_arm = arm
		else:
			_left_leg = leg
			_left_arm = arm
	_gun = Node3D.new()
	_gun.name = "Tack"
	_gun.position = Vector3(0.0, -0.62, 0.15)
	_right_arm.add_child(_gun)
	_box(_gun, "Grip", Vector3(0.0, -0.04, 0.12), Vector3(0.15, 0.19, 0.27), dark)
	_box(_gun, "Barrel", Vector3(0.0, 0.04, 0.36), Vector3(0.15, 0.11, 0.45), steel)
	_flash = _box(_gun, "Flash", Vector3(0.0, 0.04, 0.62), Vector3(0.19, 0.19, 0.16),
		_material(Color("cb894d"), true))
	_flash.visible = false
	_gun.visible = false

func set_weapon_visible(enabled: bool) -> void:
	_gun.visible = enabled
	if not enabled:
		_flash_left = 0.0
		_flash.visible = false

func set_render_layers(layers: int) -> void:
	for node: Node in find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = layers

func advance(delta: float, travel: float, phase: String) -> void:
	if travel > 0.0 and travel < 2.0:
		_stride += travel * 8.0
	var movement: float = clampf(travel / maxf(delta, 0.001) / 3.0, 0.0, 1.0)
	var swing: float = sin(_stride) * 0.43 * movement
	_left_leg.rotation.x = lerpf(_left_leg.rotation.x, swing, minf(delta * 12.0, 1.0))
	_right_leg.rotation.x = lerpf(_right_leg.rotation.x, -swing, minf(delta * 12.0, 1.0))
	_left_arm.rotation.x = lerpf(_left_arm.rotation.x, -swing * 0.35, minf(delta * 12.0, 1.0))
	var aim: float = -0.55 if phase == "firing" else -0.22
	_right_arm.rotation.x = lerpf(_right_arm.rotation.x, aim, minf(delta * 12.0, 1.0))
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		_flash.visible = _flash_left > 0.0

func shot() -> void:
	if not _gun.visible:
		return
	_flash_left = 0.1
	_flash.visible = true

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

func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.3
	material.roughness = 0.85
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.3
	return material
