extends "res://art/models/clerk_source.gd"

## Actual covert human skin, shared joint math, separate close-strike poses.
const REDACTOR_SOURCE: String = "res://art/models/candidates/redactor.glb"

func source_path() -> String:
	return REDACTOR_SOURCE

func pose_name() -> String:
	return "RedactorPose"

func _sample_walk(body: Node3D, skeleton: Skeleton3D, progress: float) -> void:
	var player: AnimationPlayer = body.get_node("AnimationPlayer") as AnimationPlayer
	if not player.has_animation(&"walk"):
		var library: AnimationLibrary = player.get_animation_library(&"")
		for clip: StringName in player.get_animation_list():
			if str(clip).contains("walking_man"):
				library.add_animation(&"walk", player.get_animation(clip))
				break
	super._sample_walk(body, skeleton, progress)

func _apply_pose(model: Node3D, body: Node3D, action: String, progress: float, _unarmed: bool) -> void:
	super._apply_pose(model, body, "idle" if action == "seated" else action, progress, true)
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	if action != "death":
		var raised: float = smoothstep(0.0, 1.0, progress) if action == "raise" else 0.0
		if action == "recover":
			raised = 1.0 - smoothstep(0.0, 1.0, progress)
		var target: Vector3 = Vector3(-24, 104, 15).lerp(Vector3(-35, 142, 6), raised)
		if action == "fire":
			target = Vector3(-18, 130, 56).lerp(Vector3(-25, 123, 31), progress)
		_two_bone(skeleton, "RightArm", "RightForeArm", "RightHand", target, Vector3(-60, 121, 0))
		_two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", Vector3(24, 112, 22), Vector3(48, 114, 1))
	var hand: Vector3 = _local_chain(skeleton, body) * skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
	var blade: Node3D = Node3D.new()
	blade.name = "HeldShiv"
	body.add_child(blade)
	part(blade, hand + Vector3(0, 0.01, 0.015), Vector3(0.038, 0.035, 0.11), Color("39363a"))
	part(blade, hand + Vector3(0, 0.014, 0.095), Vector3(0.075, 0.022, 0.026), Color("74757b"))
	part(blade, hand + Vector3(0, 0.014, 0.21), Vector3(0.035, 0.014, 0.21), Color("c1c4cb"))
