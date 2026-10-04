extends "res://art/characters/geometry.gd"

const SOURCE: String = "res://art/models/candidates/clerk.glb"
static var _scenes: Dictionary[String, PackedScene] = {}

func source_path() -> String:
	return SOURCE

func pose_name() -> String:
	return "ClerkPose"

func build_pose(action: String, progress: float, unarmed: bool = false) -> Node3D:
	var path: String = source_path()
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	var packed: PackedScene = _scenes[path]
	var model: Node3D = Node3D.new()
	model.name = pose_name()
	if packed == null:
		push_error("clerk_source: source is unavailable")
		return model
	var body: Node3D = packed.instantiate() as Node3D
	model.add_child(body)
	model.ready.connect(_apply_pose.bind(model, body, action, progress, unarmed), CONNECT_ONE_SHOT)
	return model

func _apply_pose(_model: Node3D, body: Node3D, action: String, progress: float, unarmed: bool) -> void:
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	skeleton.reset_bone_poses()
	if action == "walk":
		_sample_walk(body, skeleton, progress)
	var raised: float = 0.0
	if action == "raise":
		raised = smoothstep(0.0, 1.0, progress)
	elif action == "fire":
		raised = 1.0
	elif action == "recover":
		raised = 1.0 - smoothstep(0.0, 1.0, progress)
	var sway: float = sin(progress * TAU) * 2.0 if action == "walk" else 0.0
	var right_target: Vector3 = Vector3(-23, 97 + sway, 12).lerp(Vector3(-42, 131, 28), raised)
	var left_target: Vector3 = Vector3(26, 97 - sway, 8)
	if unarmed and raised > 0.0:
		right_target = Vector3(-23, 104, 12).lerp(Vector3(-16, 137, 36), raised)
		left_target = Vector3(25, 104, 10).lerp(Vector3(17, 130, 29), raised)
	if action == "fire":
		if unarmed:
			_turn(skeleton, "Spine02", Vector3.RIGHT, 0.30 * (1.0 - progress))
			right_target.z += 20.0 * (1.0 - progress)
		else:
			right_target.z -= 5.0 * (1.0 - progress)
	if action == "seated":
		body.position.y = -0.38
		_seat_leg(skeleton, "Left")
		_seat_leg(skeleton, "Right")
		right_target = Vector3(-20, 102, 31)
		left_target = Vector3(23, 101, 30)
	_two_bone(skeleton, "RightArm", "RightForeArm", "RightHand", right_target, Vector3(-60, lerpf(105, 130, raised), 3))
	_two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", left_target, Vector3(44, 105, 3))
	if action == "hit":
		_turn(skeleton, "Spine", Vector3.FORWARD, sin(lerpf(0.2, 1.0, progress) * PI) * 0.16)
	if action == "death":
		var fall: float = smoothstep(0.0, 1.0, progress)
		body.rotation.x = -PI * 0.5 * fall
		body.position.y = 0.20 * fall
		body.position.z = 0.85 * fall
	if not unarmed:
		var hand: Vector3 = _local_chain(skeleton, body) * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
		gun(body, hand + Vector3(0, 0.045, 0.02), false, raised)
		var weapon: Node3D = body.get_child(body.get_child_count() - 1) as Node3D
		weapon.name = "Pistol"
		weapon.rotation.y = 0.0
		if action == "fire":
			part(weapon, Vector3(0, 0.02, 0.235), Vector3(0.13, 0.13, 0.14), Color("ffe2a2"))
			part(weapon, Vector3(0, 0.02, 0.28), Vector3(0.06, 0.19, 0.08), Color("e47e3b"), Vector3(0, 0, 30))

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

func _seat_leg(skeleton: Skeleton3D, side: String) -> void:
	var thigh: int = skeleton.find_bone(side + "UpLeg")
	var knee: int = skeleton.find_bone(side + "Leg")
	var foot: int = skeleton.find_bone(side + "Foot")
	_aim(skeleton, thigh, knee, Vector3(0, -0.01, 1))
	_aim(skeleton, knee, foot, Vector3.DOWN)

func _local_chain(node: Node3D, stop: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != stop and current is Node3D:
		result = current.transform * result
		current = current.get_parent()
	return result
