extends "res://art/models/clerk_source.gd"

## Offline named source only. No runtime mission or bake selects this candidate.
func source_path() -> String:
	return "res://art/models/candidates/tern.glb"

func pose_name() -> String:
	return "TernPose"

func _apply_pose(model: Node3D, body: Node3D, action: String, progress: float, _unarmed: bool) -> void:
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	skeleton.reset_bone_poses()
	if action == "walk":
		_sample_walk(body, skeleton, progress)
	elif action == "calm":
		_two_bone(skeleton, "RightArm", "RightForeArm", "RightHand", Vector3(-24, 96, 8), Vector3(-44, 108, 2))
		_two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", Vector3(24, 96, 8), Vector3(44, 108, 2))
	# Register the actual weighted feet, not the undeformed mesh AABB. Original
	# clip keys remain intact; this is the offline figure's floor placement.
	var points: PackedVector3Array = weighted_points(body)
	if not points.is_empty():
		var minimum: float = points[0].y
		for point: Vector3 in points:
			minimum = minf(minimum, point.y)
		model.position.y -= minimum

func _sample_walk(body: Node3D, skeleton: Skeleton3D, progress: float) -> void:
	var player: AnimationPlayer = body.get_node("AnimationPlayer") as AnimationPlayer
	# Keep the original walking clip name and key data in the retained source.
	var animation: Animation = player.get_animation(player.get_animation_list()[0])
	var seconds: float = fposmod(progress, 1.0) * animation.length
	for track: int in range(animation.get_track_count()):
		var path: NodePath = animation.track_get_path(track)
		if path.get_subname_count() != 1:
			continue
		var bone: int = skeleton.find_bone(String(path.get_subname(0)))
		if bone < 0:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				var position: Vector3 = animation.position_track_interpolate(track, seconds)
				if skeleton.get_bone_name(bone) == "Hips":
					var rest: Vector3 = skeleton.get_bone_rest(bone).origin
					position.x = rest.x
					position.z = rest.z
				skeleton.set_bone_pose_position(bone, position)
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(track, seconds))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone, animation.scale_track_interpolate(track, seconds))

static func weighted_points(model: Node3D) -> PackedVector3Array:
	var result: PackedVector3Array = []
	for candidate: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = candidate as MeshInstance3D
		var skeleton: Skeleton3D = instance.get_node_or_null(instance.skeleton) as Skeleton3D
		if skeleton == null or instance.skin == null:
			return []
		var transforms: Array[Transform3D] = []
		for bind: int in range(instance.skin.get_bind_count()):
			var bone: int = instance.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skeleton.find_bone(instance.skin.get_bind_name(bind))
			if bone < 0 or bone >= skeleton.get_bone_count():
				return []
			transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(bind))
		for surface: int in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences: int = int(bones.size() / vertices.size())
			if influences not in [4, 8] or weights.size() != bones.size():
				return []
			for vertex: int in range(vertices.size()):
				var point: Vector3 = Vector3.ZERO
				var total: float = 0.0
				for influence: int in range(influences):
					var index: int = vertex * influences + influence
					if bones[index] < 0 or bones[index] >= transforms.size() or not is_finite(weights[index]) or weights[index] < 0.0:
						return []
					point += (transforms[bones[index]] * vertices[vertex]) * weights[index]
					total += weights[index]
				if absf(total - 1.0) > 0.0001 or not point.is_finite():
					return []
				result.append(point)
	return result
