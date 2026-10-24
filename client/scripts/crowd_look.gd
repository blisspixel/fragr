class_name CrowdLook
extends RefCounted

## Render-only looks for crowds of distinct free people wearing one shared
## source body: their own clothes over the atlas and, for synthetics, their
## own warm screen light. Kept apart from SkinnedCharacter so the pose
## implementation its support curves bind stays unchanged.
const OUTFIT_SHADER: Shader = preload("res://assets/shaders/crowd_outfit.gdshader")

## A person's own clothes over the shared atlas: coat, trousers and a skin
## or plate warmth, recoloured by painted value (`crowd_outfit.gdshader`).
static func outfit(body: SkinnedCharacter, coat: Color, trousers: Color, skin_tone: Color, lift: float = 1.0) -> void:
	if body == null or body.source_body == null:
		return
	for node: Node in body.source_body.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		for surface: int in range(part.mesh.get_surface_count()):
			var original: StandardMaterial3D = part.get_active_material(surface) as StandardMaterial3D
			if original == null or original.albedo_texture == null:
				continue
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = OUTFIT_SHADER
			material.set_shader_parameter("albedo_texture", original.albedo_texture)
			material.set_shader_parameter("coat", coat)
			material.set_shader_parameter("trousers", trousers)
			material.set_shader_parameter("skin", skin_tone)
			material.set_shader_parameter("lift", lift)
			material.set_shader_parameter("synthetic", body.kind == "synthetic")
			part.set_surface_override_material(surface, material)

## A small warm screen face on the head's front: synthetic free people carry
## their own warm light, never a cyan glow or a red optic.
static func face_lamp(body: SkinnedCharacter, colour: Color) -> void:
	if body == null or body.skeleton == null or body.skeleton.get_node_or_null("FaceLamp") != null:
		return
	var mount: BoneAttachment3D = BoneAttachment3D.new()
	mount.name = "FaceLamp"
	mount.bone_name = "headfront"
	body.skeleton.add_child(mount)
	var glow: MeshInstance3D = MeshInstance3D.new()
	glow.name = "Screen"
	var box: BoxMesh = BoxMesh.new()
	# Skeleton space is centimetres under the source's 0.01 scale.
	box.size = Vector3(9.0, 6.0, 1.5)
	glow.mesh = box
	glow.layers = ArenaSky.ACTOR_LAYERS
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 1.6
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	glow.material_override = material
	mount.add_child(glow)
