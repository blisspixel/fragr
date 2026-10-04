class_name LatchSource
extends RefCounted

const LATCH_SOURCE: String = "res://assets/models/latch_stylized.glb"

## Sample the retained skin, without root motion or a client-owned action clock.
func pose_live(body: Node3D, stride: float, moving: bool, armed: bool, release: float, firing: bool = false) -> void:
	release = clampf(release, 0.0, 1.0)
	stride = fposmod(stride, TAU)
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	skeleton.reset_bone_poses()
	if moving:
		_sample_walk(body, skeleton, stride / TAU)
	var sway: float = sin(stride) * 3.0 if moving else 0.0
	var right: Vector3 = Vector3(-27, 96 + sway, 12)
	var left: Vector3 = Vector3(27, 96 - sway, 12)
	if armed:
		right = Vector3(-28, 130, 44) if firing else Vector3(-28, 122, 35)
	right = right.lerp(Vector3(-26, 132, 43), release)
	left = left.lerp(Vector3(30, 111, 18), release)
	_two_bone(skeleton, "RightArm", "RightForeArm", "RightHand", right, Vector3(-58, 109, 3))
	_two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", left, Vector3(56, 109, 3))
	_turn(skeleton, "RightHand", Vector3.RIGHT, -0.35 * release)
	_turn(skeleton, "RightHand", Vector3.FORWARD, -0.18 * release)

func bone_transform(body: Node3D, name: String) -> Transform3D:
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	return _local_chain(skeleton, body) * skeleton.get_bone_global_pose(skeleton.find_bone(name))

func bone_delta(body: Node3D, name: String) -> Transform3D:
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	var bone: int = skeleton.find_bone(name)
	var chain: Transform3D = _local_chain(skeleton, body)
	return chain * skeleton.get_bone_global_pose(bone) * (chain * skeleton.get_bone_global_rest(bone)).affine_inverse()

func _sample_walk(body: Node3D, skeleton: Skeleton3D, progress: float) -> void:
	var player: AnimationPlayer = body.get_node("AnimationPlayer") as AnimationPlayer
	var animation: Animation = player.get_animation(&"walk")
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

func _two_bone(skeleton: Skeleton3D, upper_name: String, lower_name: String, hand_name: String, target: Vector3, pole: Vector3) -> void:
	var upper: int = skeleton.find_bone(upper_name)
	var lower: int = skeleton.find_bone(lower_name)
	var hand: int = skeleton.find_bone(hand_name)
	var shoulder: Vector3 = skeleton.get_bone_global_pose(upper).origin
	var length_a: float = (skeleton.get_bone_global_pose(lower).origin - shoulder).length()
	var length_b: float = (skeleton.get_bone_global_pose(hand).origin - skeleton.get_bone_global_pose(lower).origin).length()
	var direction: Vector3 = (target - shoulder).normalized()
	var distance: float = clampf((target - shoulder).length(), absf(length_a - length_b) + 0.01, length_a + length_b - 0.05)
	var bend: Vector3 = pole - shoulder
	bend = (bend - direction * bend.dot(direction)).normalized()
	var along: float = (length_a * length_a + distance * distance - length_b * length_b) / (2.0 * distance)
	var elbow: Vector3 = shoulder + direction * along + bend * sqrt(maxf(0.0, length_a * length_a - along * along))
	_aim(skeleton, upper, lower, elbow - shoulder)
	_aim(skeleton, lower, hand, target - skeleton.get_bone_global_pose(lower).origin)

func _aim(skeleton: Skeleton3D, bone: int, child: int, direction: Vector3) -> void:
	var pose: Transform3D = skeleton.get_bone_global_pose(bone)
	var from: Vector3 = skeleton.get_bone_global_pose(child).origin - pose.origin
	pose.basis = Basis(Quaternion(from.normalized(), direction.normalized())) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)

func _turn(skeleton: Skeleton3D, name: String, axis: Vector3, angle: float) -> void:
	var bone: int = skeleton.find_bone(name)
	var pose: Transform3D = skeleton.get_bone_global_pose(bone)
	pose.basis = Basis(axis, angle) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)

func _local_chain(node: Node3D, stop: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != stop and current is Node3D:
		result = current.transform * result
		current = current.get_parent()
	return result
