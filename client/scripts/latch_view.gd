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
const Workshop = preload("res://scripts/model_geometry.gd")
const NEAR_CENTER_HEIGHT: float = 1.2
const NEAR_HIDE_DISTANCE: float = 1.1
const NEAR_FULL_DISTANCE: float = 1.35
var near_camera_clip: bool = false
var _ward_materials: Dictionary[MeshInstance3D, StandardMaterial3D] = {}
var _near_origin: Vector3 = Vector3.INF

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
var _workshop: RefCounted = Workshop.new()

func _init() -> void:
	var bone: StandardMaterial3D = _material(BONE)
	var steel: StandardMaterial3D = _material(STEEL)
	var cyan: StandardMaterial3D = _material(CYAN)
	var dark: StandardMaterial3D = _material(DARK)
	var rust: StandardMaterial3D = _material(RUST)
	_box(self, "Waist", Vector3(0.0, 0.79, 0.0), Vector3(0.29, 0.16, 0.22), steel)
	_workshop.hull(self, "Torso", PackedVector3Array([
		Vector3(-0.22, 0.135, 0.1), Vector3(-0.17, 0.16, 0.125),
		Vector3(0.15, 0.195, 0.13), Vector3(0.22, 0.16, 0.1)]), bone, Vector3(0, 1.12, 0))
	_box(self, "ChestPlate", Vector3(0.0, 1.19, 0.13), Vector3(0.25, 0.22, 0.027), steel)
	_box(self, "Patch", Vector3(-0.07, 1.22, 0.15), Vector3(0.06, 0.075, 0.012), cyan)
	_box(self, "Collar", Vector3(0.0, 1.38, 0.0), Vector3(0.23, 0.06, 0.2), steel)
	_box(self, "Neck", Vector3(0.0, 1.44, 0.0), Vector3(0.12, 0.12, 0.13), steel)
	_box(self, "FacetedHead", Vector3(0.0, 1.63, -0.015), Vector3(0.26, 0.32, 0.23), bone)
	_box(self, "Brow", Vector3(0.0, 1.635, 0.108), Vector3(0.238, 0.29, 0.027), steel)
	_box(self, "FaceRecess", Vector3(0.0, 1.635, 0.125), Vector3(0.204, 0.252, 0.012), dark)
	# Two small pixel eyes share one mesh. The screen stays taller than wide.
	var eyes: SurfaceTool = SurfaceTool.new()
	eyes.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: float in [-0.047, 0.047]:
		_workshop.quad(eyes, Vector3(x - 0.016, 1.651, 0.133), Vector3(x + 0.016, 1.651, 0.133),
			Vector3(x + 0.016, 1.681, 0.133), Vector3(x - 0.016, 1.681, 0.133), Vector3.BACK)
	_workshop.instance(self, "PixelEyes", eyes.commit(), _material(CYAN, true))
	# Facing +Z puts anatomical left at +X, the viewer's right in a front view.
	_workshop.rod(self, "LeftAntenna", Vector3(0.105, 1.77, -0.04), Vector3(0.117, 1.91, -0.04), 0.007, steel, 8)
	for side: float in [-1.0, 1.0]:
		var leg: Node3D = Node3D.new()
		leg.name = "RightLeg" if side > 0.0 else "LeftLeg"
		leg.position = Vector3(side * 0.115, 0.62, 0.0)
		add_child(leg)
		_box(leg, "Leg", Vector3(0.0, -0.24, 0.0), Vector3(0.105, 0.68, 0.13), steel)
		_box(leg, "ShinShell", Vector3(0.0, -0.3, 0.078), Vector3(0.115, 0.34, 0.035), bone)
		_box(leg, "Foot", Vector3(0.0, -0.53, 0.07), Vector3(0.16, 0.13, 0.28), bone)
		var arm: Node3D = Node3D.new()
		arm.name = "RightArm" if side > 0.0 else "LeftArm"
		arm.position = Vector3(side * 0.26, 1.29, 0.0)
		add_child(arm)
		_box(arm, "Shoulder", Vector3(0.0, -0.04, 0.0), Vector3(0.15, 0.16, 0.16), bone)
		_box(arm, "UpperArm", Vector3(0.0, -0.19, 0.0), Vector3(0.095, 0.29, 0.115), steel)
		_box(arm, "Elbow", Vector3(0.0, -0.34, 0.0), Vector3(0.12, 0.1, 0.13), dark)
		_box(arm, "Forearm", Vector3(0.0, -0.43, 0.0),
			Vector3(0.16, 0.34, 0.16) if side > 0.0 else Vector3(0.105, 0.34, 0.13),
			bone if side > 0.0 else steel)
		if side > 0.0:
			# This repair belongs to Latch's right arm, not issued Union armor.
			_box(arm, "RustRepair", Vector3(0.0, -0.43, 0.09), Vector3(0.13, 0.27, 0.024), rust)
			_box(arm, "RustRepairEdge", Vector3(0.086, -0.43, 0.02), Vector3(0.025, 0.23, 0.11), rust)
			_box(arm, "RepairPinUpper", Vector3(-0.04, -0.34, 0.107), Vector3(0.017, 0.017, 0.01), dark)
			_box(arm, "RepairPinLower", Vector3(0.04, -0.52, 0.107), Vector3(0.017, 0.017, 0.01), dark)
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
	set_process(false)

func _process(_delta: float) -> void:
	_update_near_origin()

func _update_near_origin() -> void:
	if not near_camera_clip or not is_inside_tree():
		return
	var origin: Vector3 = global_position
	if origin == _near_origin:
		return
	_near_origin = origin
	for part: MeshInstance3D in _ward_materials:
		var material: ShaderMaterial = part.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("chassis_origin", origin)

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
	set_process(enabled)
	_near_origin = Vector3.INF
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
		clipped.set_shader_parameter("finish_enabled", original.albedo_texture != null)
		if original.albedo_texture != null:
			clipped.set_shader_parameter("chassis_finish", original.albedo_texture)
		clipped.set_shader_parameter("chassis_metallic", original.metallic)
		clipped.set_shader_parameter("chassis_roughness", original.roughness)
		clipped.set_shader_parameter("chassis_emission", original.emission * original.emission_energy_multiplier if original.emission_enabled else Color.BLACK)
		clipped.set_shader_parameter("chassis_center_height", NEAR_CENTER_HEIGHT)
		clipped.set_shader_parameter("near_hide_distance", NEAR_HIDE_DISTANCE)
		clipped.set_shader_parameter("near_full_distance", NEAR_FULL_DISTANCE)
		part.material_override = clipped
	_update_near_origin()

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
	return _workshop.block(parent, label, size, material, offset)

func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.3
	material.roughness = 0.85
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if not glow:
		material.albedo_texture = _workshop.material("bone_latch" if color == BONE else "metal_latch", color).albedo_texture
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.3
	return material
