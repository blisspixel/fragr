extends "res://art/models/tern_source.gd"

## Offline source adapter. Runtime selection requires its separate integration gate.
func source_path() -> String:
	return "res://art/models/candidates/edda.glb"

func pose_name() -> String:
	return "EddaPose"

func _apply_pose(model: Node3D, body: Node3D, action: String, progress: float, _unarmed: bool) -> void:
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	skeleton.reset_bone_poses()
	if action == "walk":
		_sample_walk(body, skeleton, progress)
	elif action in ["calm", "crouch", "fallen"]:
		# Keep the anatomical-left hand outside the retained satchel. These are
		# resting wrists, not a hand-to-bag or individual-finger contact claim.
		_two_bone(skeleton, "RightArm", "RightForeArm", "RightHand", Vector3(-27, 97, 8), Vector3(-46, 108, 2))
		_two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", Vector3(35, 97, 8), Vector3(49, 108, 2))
	if action == "crouch":
		for side: String in ["Left", "Right"]:
			_turn(skeleton, side + "UpLeg", Vector3.RIGHT, -0.50)
			_turn(skeleton, side + "Leg", Vector3.RIGHT, 0.95)
			_turn(skeleton, side + "Foot", Vector3.RIGHT, -0.45)
		body.position.y = -0.22
	elif action == "fallen":
		body.rotation.x = -PI * 0.5 * clampf(progress, 0.0, 1.0)
	var points: PackedVector3Array = weighted_points(body)
	if not points.is_empty():
		var minimum: float = points[0].y
		for point: Vector3 in points:
			minimum = minf(minimum, point.y)
		model.position.y -= minimum
