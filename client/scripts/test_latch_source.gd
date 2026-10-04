extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_latch_source: " + message)

func _run() -> void:
	var view: LatchView = LatchView.new()
	root.add_child(view)
	var skeleton: Skeleton3D = view._source_body.get_node("Armature/Skeleton3D") as Skeleton3D
	var mesh: MeshInstance3D = view._source_body.get_node("Armature/Skeleton3D/char1") as MeshInstance3D
	_check(mesh.skin != null and skeleton.get_bone_count() == 24, "the live source has weighted skin")
	var player: AnimationPlayer = view._source_body.get_node("AnimationPlayer") as AnimationPlayer
	_check(player.get_animation_list() == PackedStringArray(["walk"]), "only the bounded walking clip remains")
	var idle: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("LeftLeg"))
	view.advance(0.05, 0.1, "following")
	var walking: Transform3D = skeleton.get_bone_global_pose(skeleton.find_bone("LeftLeg"))
	_check(not idle.is_equal_approx(walking), "actual travel deforms the weighted leg")
	view.advance(0.05, 0.0, "following")
	_check(idle.is_equal_approx(skeleton.get_bone_global_pose(skeleton.find_bone("LeftLeg"))), "idle returns the real leg to rest")
	view.set_weapon_visible(true)
	var palm: Transform3D = view._source.bone_transform(view._source_body, "RightHand")
	var weapon: Transform3D = view._right_arm.transform * view._gun.transform
	_check(weapon.origin.distance_to(palm.origin + Vector3(0, 0.025, 0.03)) < 0.001, "Tack is registered in the actual skinned palm")
	view.shot()
	_check(view._flash.visible, "only the resolved-shot callback enables flash")
	view.advance(0.11, 0.0, "following")
	_check(not view._flash.visible, "resolved flash expires without another shot")
	view.set_weapon_visible(false)
	view.shot()
	_check(not view._flash.visible, "unarmed release cannot display a shot")
	view.set_screen_expression(0.0)
	_check(is_equal_approx(view._eyes.scale.y, 0.1), "independent optics bound closed expression")
	view.set_screen_expression(2.0)
	_check(is_equal_approx(view._eyes.scale.y, 1.0), "independent optics bound open expression")
	view.set_render_layers(ArenaSky.ACTOR_LAYERS)
	for node: Node in view.find_children("*", "VisualInstance3D", true, false):
		_check((node as VisualInstance3D).layers == ArenaSky.ACTOR_LAYERS, "skin and attachments preserve actor-only lighting")
	var original: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	view.set_near_camera_clip(true)
	var clipped: ShaderMaterial = mesh.material_override as ShaderMaterial
	_check(clipped.get_shader_parameter("chassis_normal") == original.normal_texture
		and clipped.get_shader_parameter("chassis_roughness_map") == original.roughness_texture
		and clipped.get_shader_parameter("chassis_metallic_map") == original.metallic_texture,
		"near fade preserves the actual PBR maps")
	view.set_near_camera_clip(false)
	_check(mesh.material_override == original, "near fade restores the exact source material")
	view.free()
	await process_frame
	if failures == 0:
		print("test_latch_source: PASS weighted travel, palm, expression, weapon, actor layers and PBR preservation")
	quit(0 if failures == 0 else 1)
