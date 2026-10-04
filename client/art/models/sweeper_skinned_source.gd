extends "res://art/models/clerk_source.gd"

## Runtime directional source. The separate mechanical Sweeper source retains
## its earlier rigid GLB library contract and supplies the issued rifle mesh.
const RifleSource = preload("res://art/models/sweeper_source.gd")
const SKIN_SOURCE: String = "res://art/models/candidates/sweeper.glb"
const RIGHT_GRIP: Vector3 = Vector3(0, -0.078, -0.04)
const LEFT_GRIP: Vector3 = Vector3(0, -0.03, 0.12)
const ISSUED_WIDTH: float = 1.38
var _rifle_source: RefCounted = RifleSource.new()

func source_path() -> String:
	return SKIN_SOURCE

func pose_name() -> String:
	return "SweeperSkinPose"

func _apply_pose(_model: Node3D, body: Node3D, action: String, progress: float, unarmed: bool) -> void:
	# Broad issued machinery remains distinct from the lean human and free-agent
	# silhouettes. Height, registered feet and runtime sprite scale stay fixed.
	body.scale.x = ISSUED_WIDTH
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	skeleton.reset_bone_poses()
	if action == "walk":
		_sample_walk(body, skeleton, progress)
	var raised: float = smoothstep(0.0, 1.0, progress) if action == "raise" else 0.0
	if action == "fire":
		raised = 1.0
	elif action == "recover":
		raised = 1.0 - smoothstep(0.0, 1.0, progress)
	var recoil: float = 1.0 - progress if action == "fire" and not unarmed else 0.0
	if action == "hit":
		_turn(skeleton, "Spine01", Vector3.FORWARD, sin(lerpf(0.2, 1.0, progress) * PI) * 0.16)
	elif recoil > 0.0:
		_turn(skeleton, "Spine01", Vector3.RIGHT, recoil * -0.035)
	var fall: float = smoothstep(0.0, 1.0, progress) if action == "death" else 0.0
	var carry: Vector3 = Vector3(-0.20, 1.26, 0.10).lerp(Vector3(-0.20, 1.43, 0.16), raised)
	carry.z -= recoil * 0.045
	carry = carry.lerp(Vector3(-0.20, 1.28, 0.12), fall)
	var weapon_basis: Basis = Basis(Vector3.RIGHT, fall * PI * 0.5)
	var right: Vector3 = carry + weapon_basis * RIGHT_GRIP
	var left: Vector3 = carry + weapon_basis * LEFT_GRIP
	if unarmed:
		right = Vector3(-0.20, 1.08, 0.10).lerp(Vector3(-0.20, 1.28, 0.22), raised)
		left = Vector3(0.20, 1.08, 0.10).lerp(Vector3(0.20, 1.30, 0.22), raised)
		var strike: float = 1.0 - progress * 0.3 if action == "fire" else (1.0 - progress if action == "recover" else 0.0)
		if action in ["fire", "recover"]:
			right = right.lerp(Vector3(-0.12, 1.34, 0.49), strike)
		right = right.lerp(Vector3(-0.22, 1.10, 0.07), fall)
		left = left.lerp(Vector3(0.22, 1.10, 0.07), fall)
	# Imported armature units are centimetres. Derive their targets from the
	# same metre-space weapon anchors, not independently approximated hands.
	var to_skin: Transform3D = _local_chain(skeleton, body).affine_inverse()
	_two_bone(skeleton, "RightArm", "RightForeArm", "RightHand", to_skin * right,
		to_skin * Vector3(-0.60, lerpf(1.10, 1.26, raised), 0.08))
	_two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", to_skin * left,
		to_skin * Vector3(0.50, 1.12, 0.14))
	if not unarmed:
		# The imported palms have no separate finger bones. Keep their grip
		# orientation deliberate instead of inheriting the elbow's IK twist.
		var hand: int = skeleton.find_bone("LeftHand")
		var hand_pose: Transform3D = skeleton.get_bone_global_pose(hand)
		hand_pose.basis = weapon_basis * Basis(Vector3.RIGHT, -PI * 0.5) * skeleton.get_bone_global_rest(hand).basis
		skeleton.set_bone_global_pose(hand, hand_pose)
	if not unarmed:
		var rifle: Node3D = Node3D.new()
		rifle.name = "IssuedRifle"
		rifle.position = carry
		rifle.basis = weapon_basis
		body.add_child(rifle)
		_rifle_source._rifle(rifle, 1.0)
		# _rifle keeps a horizontal axis at raised=1. Death lays that same
		# firearm across the body through the registered weapon transform.
		rifle.basis = weapon_basis
		for spec: Dictionary in [{"name": "RightGrip", "point": RIGHT_GRIP}, {"name": "LeftGrip", "point": LEFT_GRIP}]:
			var marker: Node3D = Node3D.new()
			marker.name = spec["name"]
			marker.position = spec["point"]
			rifle.add_child(marker)
		if action == "fire" and progress < 0.5:
			part(rifle, Vector3(0, 0.021, 0.62), Vector3(0.13, 0.13, 0.16), Color("ffe2a2"))
			part(rifle, Vector3(0, 0.021, 0.69), Vector3(0.06, 0.17, 0.08), Color("e47e3b"))
	if action == "death":
		body.rotation.x = -PI * 0.5 * fall
		body.position.y = 0.20 * fall
		body.position.z = 0.85 * fall
