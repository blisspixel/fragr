class_name LatchView
extends Node3D

## One workshop-repaired chassis for the ward tableau and server-owned ally.
## Ward gestures and moving-pawn travel only pose this render-only figure.
const BONE: Color = Color("c2b9a4")
const STEEL: Color = Color("343d3d")
const CYAN: Color = Color("4a8a92")
const DARK: Color = Color("232b2c")
const RUST: Color = Color("7a3a22")
const NEAR_CLIP: Shader = preload("res://assets/shaders/latch_near_clip.gdshader")
const CAMERA_CLEARANCE: float = 0.7
var near_camera_clip: bool = false
var _ward_materials: Dictionary[MeshInstance3D, StandardMaterial3D] = {}

var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _gun: Node3D
var _right_hand: Node3D
var _right_fingers: Array[Node3D] = []
var _flash: MeshInstance3D
var _stride: float = 0.0
var _flash_left: float = 0.0

func _init() -> void:
	var bone: StandardMaterial3D = _material(BONE)
	var steel: StandardMaterial3D = _material(STEEL)
	var cyan: StandardMaterial3D = _material(CYAN)
	var dark: StandardMaterial3D = _material(DARK)
	var rust: StandardMaterial3D = _material(RUST)
	_box(self, "Waist", Vector3(0.0, 0.76, 0.0), Vector3(0.37, 0.22, 0.25), steel)
	_box(self, "Torso", Vector3(0.0, 1.22, 0.0), Vector3(0.57, 0.72, 0.31), bone)
	_box(self, "ChestPlate", Vector3(0.0, 1.4, 0.17), Vector3(0.38, 0.27, 0.045), steel)
	_box(self, "Patch", Vector3(-0.115, 1.46, 0.204), Vector3(0.14, 0.14, 0.027), cyan)
	_box(self, "Collar", Vector3(0.0, 1.61, 0.0), Vector3(0.4, 0.1, 0.32), steel)
	_box(self, "Neck", Vector3(0.0, 1.69, 0.0), Vector3(0.2, 0.16, 0.19), steel)
	var head: MeshInstance3D = MeshInstance3D.new()
	head.name = "FacetedHead"
	var shell: CylinderMesh = CylinderMesh.new()
	shell.top_radius = 0.23
	shell.bottom_radius = 0.18
	shell.height = 0.35
	shell.radial_segments = 6
	head.mesh = shell
	head.position = Vector3(0.0, 1.91, 0.0)
	head.material_override = bone
	add_child(head)
	# The recessed lower face and pale brow echo the workshop still without an optic.
	_box(self, "FaceRecess", Vector3(0.0, 1.85, 0.192), Vector3(0.21, 0.1, 0.018), dark)
	_box(self, "Brow", Vector3(0.0, 1.93, 0.193), Vector3(0.25, 0.045, 0.032), bone)
	for side: float in [-1.0, 1.0]:
		var leg: Node3D = Node3D.new()
		leg.name = "RightLeg" if side > 0.0 else "LeftLeg"
		leg.position = Vector3(side * 0.18, 0.62, 0.0)
		add_child(leg)
		_box(leg, "Leg", Vector3(0.0, -0.24, 0.0), Vector3(0.19, 0.68, 0.2), steel)
		_box(leg, "ShinShell", Vector3(0.0, -0.3, 0.12), Vector3(0.2, 0.34, 0.05), bone)
		_box(leg, "Foot", Vector3(0.0, -0.53, 0.1), Vector3(0.22, 0.13, 0.35), bone)
		var arm: Node3D = Node3D.new()
		arm.name = "RightArm" if side > 0.0 else "LeftArm"
		arm.position = Vector3(side * 0.38, 1.45, 0.0)
		add_child(arm)
		_box(arm, "Shoulder", Vector3(0.0, -0.04, 0.0), Vector3(0.27, 0.18, 0.27), bone)
		_box(arm, "UpperArm", Vector3(0.0, -0.19, 0.0), Vector3(0.16, 0.29, 0.17), steel)
		_box(arm, "Elbow", Vector3(0.0, -0.34, 0.0), Vector3(0.17, 0.12, 0.18), dark)
		_box(arm, "Forearm", Vector3(0.0, -0.43, 0.0),
			Vector3(0.26, 0.37, 0.26) if side > 0.0 else Vector3(0.16, 0.34, 0.19),
			bone if side > 0.0 else steel)
		if side > 0.0:
			# This repair belongs to Latch's right arm, not issued Union armor.
			_box(arm, "RustRepair", Vector3(0.0, -0.43, 0.145), Vector3(0.19, 0.29, 0.035), rust)
			_box(arm, "RustRepairEdge", Vector3(0.145, -0.43, 0.045), Vector3(0.035, 0.23, 0.13), rust)
			_box(arm, "RepairPinUpper", Vector3(-0.065, -0.34, 0.169), Vector3(0.024, 0.024, 0.01), dark)
			_box(arm, "RepairPinLower", Vector3(0.065, -0.52, 0.169), Vector3(0.024, 0.024, 0.01), dark)
		var hand: Node3D = Node3D.new()
		hand.name = "Hand"
		hand.position = Vector3(0.0, -0.64, 0.015)
		arm.add_child(hand)
		_box(hand, "Palm", Vector3.ZERO, Vector3(0.135, 0.12, 0.15), steel)
		for finger_side: float in [-1.0, 1.0]:
			var finger: Node3D = Node3D.new()
			finger.name = "Index" if finger_side < 0.0 else "Opposed"
			finger.position = Vector3(finger_side * 0.047, -0.1, 0.045)
			hand.add_child(finger)
			_box(finger, "Segment", Vector3(0.0, -0.05, 0.0), Vector3(0.042, 0.12, 0.055), bone)
			if side > 0.0:
				_right_fingers.append(finger)
		_box(hand, "Thumb", Vector3(side * 0.083, -0.015, 0.09), Vector3(0.055, 0.095, 0.07), bone)
		if side > 0.0:
			_right_leg = leg
			_right_arm = arm
			_right_hand = hand
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

## Live pawn only. The ward tableau retains its original lit materials.
func set_near_camera_clip(enabled: bool) -> void:
	if enabled == near_camera_clip:
		return
	near_camera_clip = enabled
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		if not enabled:
			if _ward_materials.has(part):
				part.material_override = _ward_materials[part]
			continue
		var original: StandardMaterial3D = part.material_override as StandardMaterial3D
		if original == null:
			continue
		_ward_materials[part] = original
		var clipped: ShaderMaterial = ShaderMaterial.new()
		clipped.shader = NEAR_CLIP
		clipped.set_shader_parameter("chassis_color", original.albedo_color)
		clipped.set_shader_parameter("chassis_metallic", original.metallic)
		clipped.set_shader_parameter("chassis_roughness", original.roughness)
		clipped.set_shader_parameter("chassis_emission", original.emission * original.emission_energy_multiplier if original.emission_enabled else Color.BLACK)
		clipped.set_shader_parameter("camera_clearance", CAMERA_CLEARANCE)
		part.material_override = clipped

func set_render_layers(layers: int) -> void:
	for node: Node in find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = layers

## The open right hand and balancing left arm are a voluntary second-bay action.
## Call with a server-derived release timeline; it never advances mission state.
func pose_release(progress: float) -> void:
	var reach: float = clampf(progress, 0.0, 1.0)
	_left_arm.rotation.x = -0.28 * reach
	_right_hand.rotation.x = -0.35 * reach
	_right_hand.rotation.z = -0.18 * reach
	for index: int in range(_right_fingers.size()):
		_right_fingers[index].rotation.z = (-0.35 if index == 0 else 0.35) * reach

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
