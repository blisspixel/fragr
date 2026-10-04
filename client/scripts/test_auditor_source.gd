extends SceneTree

const Source = preload("res://art/models/auditor_source.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var source: RefCounted = Source.new()
	var models: Array[Node3D] = []
	for spec: Array in [["idle", 0.0, false], ["raise", 1.0, false], ["fire", 0.0, false],
		["recover", 1.0, false], ["walk", 0.0, false], ["walk", 0.5, false],
		["channel", 0.0, false], ["fire", 0.0, true], ["raise", 1.0, true],
		["hit", 0.0, false], ["death", 1.0, false]]:
		var model: Node3D = source.build_pose(spec[0], spec[1], spec[2])
		root.add_child(model)
		models.append(model)
	var idle: Node3D = models[0]
	var skeleton: Skeleton3D = idle.get_node("Auditor/Armature/Skeleton3D") as Skeleton3D
	_check(skeleton.get_bone_count() == 24, "reviewed source skin retained")
	_check(_bone(models[1], "RightHand").y > _bone(idle, "RightHand").y + 0.25, "draw raises physical pistol hand")
	_check(_bone(models[2], "RightHand").z < _bone(models[1], "RightHand").z - 0.035, "resolved fire pose recoils")
	_check(_bone(models[3], "RightHand").distance_to(_bone(idle, "RightHand")) < 0.001, "recovery returns grip")
	_check(_bone(models[4], "LeftFoot").distance_to(_bone(models[5], "LeftFoot")) > 0.10, "sampled gait moves feet")
	_check(_bone(models[4], "Hips").distance_to(_bone(models[5], "Hips")) < 0.04, "gait root remains registered")
	var channel: Node3D = models[6]
	_check(absf(_bone(channel, "LeftHand").y - AuditorChannels.HAND_ABOVE_FEET) < 0.01, "physical channel wrist matches beam height")
	_check(_bone(channel, "RightHand").y < 1.02, "channel pistol lowered")
	for model: Node3D in [idle, channel]:
		var body: Node3D = model.get_node("Auditor") as Node3D
		var hand: Vector3 = _bone(model, "LeftHand")
		_check((body.get_node("RepairWrist") as Node3D).position.distance_to(hand) < 0.001, "hardware uses actual posed wrist")
		var emitter: Node3D = body.get_node("RepairEmitter") as Node3D
		_check(emitter.position.distance_to(hand + Vector3(0, 0, 0.10)) < 0.001, "emitter remains attached to glove")
		var plate: Node3D = body.get_node("ShieldPlate") as Node3D
		_check(plate.position.distance_to(hand) < 0.16 and plate.basis.z.dot(Vector3.BACK) > 0.99, "shield held on forearm with frontal face")
		var sockets: Array[Vector3] = []
		for name: String in ["SocketLeft", "SocketRight"]:
			var at: Vector3 = plate.position + (plate.get_node(name) as Node3D).position
			sockets.append(Vector3(at.z, at.y - 1.5, -at.x))
		var expected: Array[Vector3] = EnemyView.CHANNEL_LAMPS if model == channel else EnemyView.PLATE_LAMPS
		_check(sockets[0].distance_to(expected[1]) < 0.035 and sockets[1].distance_to(expected[0]) < 0.035, "shield sockets agree with live repair budget lamps")
		var cable: Node3D = body.get_node("RepairCable") as Node3D
		_check(cable.get_child_count() == 5, "continuous three-link cable, spool outlet and glove coupling retained")
		_check((cable.get_node("SpoolOutlet") as Node3D).position.distance_to(
			_bone(model, "Spine") + Vector3(0.07, 0.05, -0.16)) < 0.001, "cable starts at upper-back spool fitting")
		_check((cable.get_node("Coupling") as Node3D).position.distance_to(hand + Vector3(0, -0.05, 0.08)) < 0.001, "cable reaches glove fitting")
	_check(models[7].find_children("Pistol", "Node3D", true, false).is_empty(), "empty weapon melee has no pistol")
	_check(_bone(models[7], "RightHand").z > _bone(models[8], "RightHand").z + 0.15, "melee follows through physically")
	var hit_skeleton: Skeleton3D = models[9].get_node("Auditor/Armature/Skeleton3D") as Skeleton3D
	_check(not hit_skeleton.get_bone_pose_rotation(hit_skeleton.find_bone("Spine")).is_equal_approx(
		skeleton.get_bone_pose_rotation(skeleton.find_bone("Spine"))), "first hit cell contains physical torso reaction")
	_check(_bone(models[10], "Head").y < 0.60, "corpse falls to supported floor height")
	_check(absf((models[10].get_node("Auditor") as Node3D).rotation.x + PI / 2.0) < 0.001, "corpse includes physical torso fall")
	var idle_material: StandardMaterial3D = (idle.get_node("Auditor/RepairEmitter/Lens") as MeshInstance3D).material_override as StandardMaterial3D
	var channel_material: StandardMaterial3D = (channel.get_node("Auditor/RepairEmitter/Lens") as MeshInstance3D).material_override as StandardMaterial3D
	_check(idle_material.albedo_color.r < 0.2 and channel_material.albedo_color.r > 0.8, "only channel lights the lens")
	for model: Node3D in models:
		model.free()
	await process_frame
	if _failures == 0:
		print("test_auditor_source: PASS skin, gait, grip, recoil, melee, sockets, cable, channel and corpse")
	quit(0 if _failures == 0 else 1)

func _bone(model: Node3D, name: String) -> Vector3:
	var skeleton: Skeleton3D = model.get_node("Auditor/Armature/Skeleton3D") as Skeleton3D
	return model.to_local(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_auditor_source: " + message)
