extends RefCounted

## Latch sitting on the Planned Works tank rim: the pelvis on the ledge at the
## figure's origin, legs over the edge in front (+Z), hands flat beside the
## hips. Applied after LatchView has posed its frame, so the exported Latch
## sources stay unchanged; the screen and optics follow the seated head.
## The imported chain uses centimetres.

static func apply(view: LatchView) -> void:
	var body: Node3D = view._source_body
	var source: LatchSource = view._source as LatchSource
	if body == null or source == null:
		return
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	skeleton.reset_bone_poses()
	var hips: int = skeleton.find_bone("Hips")
	var rest: Vector3 = skeleton.get_bone_global_rest(hips).origin
	var at: Vector3 = skeleton.get_bone_pose_position(hips)
	# The pelvis rests just above the ledge, a little back from its edge.
	at.y -= rest.y - 12.0
	at.z -= 14.0
	skeleton.set_bone_pose_position(hips, at)
	for side: String in ["Left", "Right"]:
		var across: float = 11.0 if side == "Left" else -11.0
		source._two_bone(skeleton, side + "UpLeg", side + "Leg", side + "Foot", Vector3(across, -34.0, 30.0), Vector3(across, 14.0, 90.0))
	source._two_bone(skeleton, "RightArm", "RightForeArm", "RightHand", Vector3(-26, 14, -10), Vector3(-60, 60, -20))
	source._two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", Vector3(26, 14, -10), Vector3(60, 60, -20))
	# The same head-following placement LatchView gives its screen and optics.
	var head_delta: Transform3D = source.bone_delta(body, "Head")
	view._screen.transform = head_delta * Transform3D(Basis.IDENTITY, LatchView.SCREEN_OFFSET)
	view._eyes.transform = view._screen.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.004))
