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

var _right_arm: Node3D
var _gun: Node3D
var _flash: MeshInstance3D
var _stride: float = 0.0
var _flash_left: float = 0.0
var _workshop: RefCounted = Workshop.new()

const Source = preload("res://scripts/latch_source.gd")
var _source: RefCounted = Source.new()
var _source_body: Node3D
var _release: float = 0.0
var _ward_pose: bool = false
var _moving: bool = false
var _firing: bool = false
var _ward_position: Vector3 = Vector3.INF
var _screen: MeshInstance3D
var _eyes: MeshInstance3D

func _init() -> void:
	_source_body = load(Source.LATCH_SOURCE).instantiate() as Node3D
	_source_body.name = "LatchSource"
	add_child(_source_body)
	for node: Node in _source_body.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		part.material_override = part.get_active_material(0).duplicate() as StandardMaterial3D
	_right_arm = Node3D.new()
	_right_arm.name = "RightArm"
	add_child(_right_arm)
	_gun = Node3D.new()
	_gun.name = "Tack"
	_right_arm.add_child(_gun)
	var dark: StandardMaterial3D = _material(DARK)
	var steel: StandardMaterial3D = _material(STEEL)
	_box(_gun, "Grip", Vector3(0, -0.04, 0.06), Vector3(0.12, 0.16, 0.13), dark)
	_box(_gun, "Barrel", Vector3(0, 0.035, 0.22), Vector3(0.11, 0.09, 0.32), steel)
	_flash = _box(_gun, "Flash", Vector3(0, 0.035, 0.40), Vector3(0.16, 0.16, 0.13), _material(Color("cb894d"), true))
	_flash.visible = false
	_gun.visible = false
	# Independent optics cover the painted display, following the actual head skin.
	_screen = _box(self, "FaceRecess", Vector3.ZERO, Vector3(0.139, 0.155, 0.004), _material(DARK))
	var optics: SurfaceTool = SurfaceTool.new()
	optics.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: float in [-0.035, 0.035]:
		_workshop.quad(optics, Vector3(x - 0.009, 0.018, 0), Vector3(x + 0.009, 0.018, 0),
			Vector3(x + 0.009, 0.044, 0), Vector3(x - 0.009, 0.044, 0), Vector3.BACK)
	_workshop.quad(optics, Vector3(-0.018, -0.032, 0), Vector3(0.018, -0.032, 0),
		Vector3(0.018, -0.026, 0), Vector3(-0.018, -0.026, 0), Vector3.BACK)
	for x: float in [-0.021, 0.021]:
		_workshop.quad(optics, Vector3(x - 0.003, -0.027, 0), Vector3(x + 0.003, -0.027, 0),
			Vector3(x + 0.003, -0.018, 0), Vector3(x - 0.003, -0.018, 0), Vector3.BACK)
	_eyes = _workshop.instance(self, "PixelEyes", optics.commit(), _material(CYAN, true))
	_pose_source()
	set_process(false)

func _pose_source() -> void:
	_source.pose_live(_source_body, _stride, _moving, _gun.visible, _release, _firing, not _ward_pose)
	var hand: Transform3D = _source.bone_transform(_source_body, "RightHand")
	var arm: Transform3D = _source.bone_transform(_source_body, "RightArm")
	_right_arm.transform = Transform3D(arm.basis.orthonormalized(), arm.origin)
	# Keep the actual weapon in the skinned palm, pointing along the actor's facing.
	_gun.transform = _right_arm.transform.affine_inverse() * Transform3D(Basis.IDENTITY, hand.origin + Vector3(0, 0.025, 0.03))
	var head_delta: Transform3D = _source.bone_delta(_source_body, "Head")
	_screen.transform = head_delta * Transform3D(Basis.IDENTITY, Vector3(0, 1.55, 0.148))
	_eyes.transform = _screen.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.004))

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
	_pose_source()
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
		clipped.set_shader_parameter("normal_enabled", original.normal_enabled and original.normal_texture != null)
		clipped.set_shader_parameter("normal_strength", original.normal_scale)
		if original.normal_texture != null:
			clipped.set_shader_parameter("chassis_normal", original.normal_texture)
		clipped.set_shader_parameter("metallic_enabled", original.metallic_texture != null)
		if original.metallic_texture != null:
			clipped.set_shader_parameter("chassis_metallic_map", original.metallic_texture)
		clipped.set_shader_parameter("metallic_channel", _texture_channel(original.metallic_texture_channel))
		clipped.set_shader_parameter("roughness_enabled", original.roughness_texture != null)
		if original.roughness_texture != null:
			clipped.set_shader_parameter("chassis_roughness_map", original.roughness_texture)
		clipped.set_shader_parameter("roughness_channel", _texture_channel(original.roughness_texture_channel))
		clipped.set_shader_parameter("chassis_emission", original.emission * original.emission_energy_multiplier if original.emission_enabled else Color.BLACK)
		clipped.set_shader_parameter("chassis_center_height", NEAR_CENTER_HEIGHT)
		clipped.set_shader_parameter("near_hide_distance", NEAR_HIDE_DISTANCE)
		clipped.set_shader_parameter("near_full_distance", NEAR_FULL_DISTANCE)
		part.material_override = clipped
	_update_near_origin()

func set_render_layers(layers: int) -> void:
	for node: Node in find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = layers

func _texture_channel(channel: int) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN: return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE: return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: return Vector4(0, 0, 0, 1)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: return Vector4(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 0)
		_: return Vector4(1, 0, 0, 0)

## Optics remain independently expressive instead of relying on painted pixels.
func set_screen_expression(openness: float) -> void:
	_eyes.scale.y = clampf(openness, 0.1, 1.0)

## The open right hand and balancing left arm are a voluntary second-bay action.
## Call with a server-derived release timeline; it never advances mission state.
func pose_release(progress: float) -> void:
	_ward_pose = true
	var travel: float = position.distance_to(_ward_position) if _ward_position != Vector3.INF else 0.0
	_ward_position = position
	_moving = travel > 0.001 and travel < 2.0
	if _moving:
		_stride += travel * 8.0
	elif travel >= 2.0:
		_stride = 0.0
	_release = clampf(progress, 0.0, 1.0)
	_pose_source()

func advance(delta: float, travel: float, phase: String) -> void:
	# During M02 release the visible server pawn replaces the hidden tableau.
	# Retain its previous zero-release pose until ordinary following begins.
	_ward_pose = phase == "releasing"
	_moving = travel > 0.0 and travel < 2.0
	_firing = phase == "firing"
	if _moving:
		_stride += travel * 8.0
	_release = 0.0
	_pose_source()
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
