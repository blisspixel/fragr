extends "res://art/models/clerk_source.gd"

## Civilian pose source for the selectable human strip, not campaign authority.
func source_path() -> String:
	return "res://art/models/candidates/free_human.glb"

func pose_name() -> String:
	return "FreeHumanPose"

func _apply_pose(_model: Node3D, body: Node3D, action: String, progress: float, _unarmed: bool) -> void:
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	skeleton.reset_bone_poses()
	if action == "walk":
		_sample_walk(body, skeleton, progress)
	else:
		_two_bone(skeleton, "RightArm", "RightForeArm", "RightHand", Vector3(-24, 96, 8), Vector3(-44, 108, 2))
		_two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", Vector3(24, 96, 8), Vector3(44, 108, 2))
