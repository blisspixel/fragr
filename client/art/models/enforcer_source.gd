extends "res://art/models/clerk_source.gd"

## Offline combat poses. The packaged atlas presents authoritative body facts.
const ENFORCER_SOURCE: String = "res://art/models/candidates/enforcer.glb"

func source_path() -> String:
	return ENFORCER_SOURCE

func pose_name() -> String:
	return "EnforcerPose"

func _apply_pose(model: Node3D, body: Node3D, action: String, progress: float,
		_unarmed: bool) -> void:
	var charge: bool = action == "charge"
	var pose: String = "walk" if charge else action
	super._apply_pose(model, body, pose, progress, true)
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	var lean: float = 0.0
	if charge:
		lean = 1.0
	elif action == "raise":
		lean = smoothstep(0.0, 1.0, progress)
	elif action == "recover":
		lean = 1.0 - smoothstep(0.0, 1.0, progress)
	if lean > 0.0:
		_turn(skeleton, "Spine", Vector3.RIGHT, 0.35 * lean)
		_turn(skeleton, "Spine02", Vector3.RIGHT, 0.12 * lean)
		_two_bone(skeleton, "RightArm", "RightForeArm", "RightHand",
			Vector3(-22, 119, 29), Vector3(-55, 119, 2))
		_two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand",
			Vector3(23, 112, 20), Vector3(53, 113, 1))
	var chain: Transform3D = _local_chain(skeleton, body)
	var chest: Vector3 = chain * skeleton.get_bone_global_pose(skeleton.find_bone("Spine02")).origin
	var vents: Node3D = Node3D.new()
	vents.name = "IssuedChargeVents"
	body.add_child(vents)
	var glow: Color = Color("47171a").lerp(Color("ff3925"), lean)
	for side: float in [-1.0, 1.0]:
		for row: int in range(3):
			part(vents, chest + Vector3(side * 0.19, 0.05 - row * 0.035, 0.16),
				Vector3(0.095, 0.02, 0.024), glow)
