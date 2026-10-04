extends "res://art/models/clerk_source.gd"

## Skinned custody officer with a registered shield, cable and repair emitter.
const AUDITOR_SOURCE: String = "res://art/models/candidates/auditor.glb"
const HAND_HEIGHT: float = 1.35
const BONE: Color = Color8(232, 226, 214)

func source_path() -> String:
	return AUDITOR_SOURCE

func pose_name() -> String:
	return "AuditorPose"

func _apply_pose(model: Node3D, body: Node3D, action: String, progress: float, unarmed: bool) -> void:
	var channel: bool = action == "channel"
	super._apply_pose(model, body, "idle" if channel else action, progress, unarmed)
	var skeleton: Skeleton3D = body.get_node("Armature/Skeleton3D") as Skeleton3D
	# Cross the protected forearm before the chest and preserve lamp sockets.
	var target: Vector3 = Vector3(-14, 112, 23)
	if channel:
		target = Vector3(-14, HAND_HEIGHT * 100.0, 43)
	_two_bone(skeleton, "LeftArm", "LeftForeArm", "LeftHand", target, Vector3(35, 111, 18))
	var chain: Transform3D = _local_chain(skeleton, body)
	var hand: Vector3 = chain * skeleton.get_bone_global_pose(skeleton.find_bone("LeftHand")).origin
	var elbow: Vector3 = chain * skeleton.get_bone_global_pose(skeleton.find_bone("LeftForeArm")).origin
	var wrist: Marker3D = Marker3D.new()
	wrist.name = "RepairWrist"
	wrist.position = hand
	body.add_child(wrist)
	_plate(body, hand, channel)
	_cable(body, elbow, hand, chain * skeleton.get_bone_global_pose(skeleton.find_bone("Spine")).origin)
	_emitter(body, hand, channel)

func _plate(root: Node3D, hand: Vector3, channel: bool) -> void:
	var plate: Node3D = Node3D.new()
	plate.name = "ShieldPlate"
	plate.position = hand + (Vector3(-0.04, -0.07, 0.07) if channel else Vector3(-0.035, -0.06, 0.09))
	root.add_child(plate)
	part(plate, Vector3.ZERO, Vector3(0.44, 0.68, 0.05), PLATE)
	part(plate, Vector3(0, 0, 0.03), Vector3(0.37, 0.60, 0.01), STEEL.lightened(0.08)).name = "FrontFace"
	part(plate, Vector3(0, -0.02, 0.041), Vector3(0.05, 0.51, 0.012), RED)
	part(plate, Vector3(0, 0.31, 0.035), Vector3(0.45, 0.04, 0.04), STEEL)
	part(plate, Vector3(0, -0.32, 0.035), Vector3(0.40, 0.04, 0.04), STEEL)
	for x: float in [-0.10, 0.10]:
		var socket: MeshInstance3D = part(plate, Vector3(x, 0.20, 0.05), Vector3(0.06, 0.06, 0.022), RED.darkened(0.45))
		socket.name = "SocketLeft" if x < 0.0 else "SocketRight"
	for corner: Vector2 in [Vector2(-0.17, 0.27), Vector2(0.17, 0.27), Vector2(-0.17, -0.29), Vector2(0.17, -0.29)]:
		part(plate, Vector3(corner.x, corner.y, 0.05), Vector3(0.025, 0.025, 0.01), PLATE.lightened(0.25))
	limb(root, hand + Vector3(0, 0, -0.025), plate.position, 0.06, 0.04, INK).name = "PlateGrip"

func _cable(root: Node3D, elbow: Vector3, hand: Vector3, spine: Vector3) -> void:
	var cable: Node3D = Node3D.new()
	cable.name = "RepairCable"
	root.add_child(cable)
	var spool: Vector3 = spine + Vector3(0.07, 0.05, -0.16)
	var socket: Marker3D = Marker3D.new()
	socket.name = "SpoolOutlet"
	socket.position = spool
	cable.add_child(socket)
	var sag: Vector3 = elbow + Vector3(0.08, -0.12, -0.08)
	limb(cable, spool, sag, 0.024, 0.024, INK)
	limb(cable, sag, elbow + Vector3(0.03, -0.04, 0), 0.024, 0.024, INK)
	limb(cable, elbow + Vector3(0.03, -0.04, 0), hand + Vector3(0, -0.05, 0.08), 0.024, 0.024, INK)
	part(cable, hand + Vector3(0, -0.05, 0.08), Vector3(0.045, 0.045, 0.05), STEEL).name = "Coupling"

func _emitter(root: Node3D, hand: Vector3, active: bool) -> void:
	var emitter: Node3D = Node3D.new()
	emitter.name = "RepairEmitter"
	emitter.position = hand + Vector3(0, 0, 0.10)
	root.add_child(emitter)
	part(emitter, Vector3.ZERO, Vector3(0.13, 0.13, 0.05), STEEL)
	part(emitter, Vector3(0, 0, 0.035), Vector3(0.10, 0.10, 0.03), GLOW if active else INK).name = "Lens"
	if active:
		part(emitter, Vector3(0, 0, 0.055), Vector3(0.05, 0.05, 0.02), BONE)
		for spoke: Vector3 in [Vector3(0.10, 0, 0), Vector3(-0.10, 0, 0), Vector3(0, 0.10, 0), Vector3(0, -0.10, 0)]:
			part(emitter, spoke + Vector3(0, 0, 0.055), Vector3(0.035, 0.035, 0.02), GLOW)
