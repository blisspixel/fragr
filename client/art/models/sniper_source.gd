extends RefCounted

const SOURCE: String = "res://art/models/candidates/sniper.glb"
const Workshop = preload("res://scripts/model_geometry.gd")
const BOLT_TRAVEL_METRES: float = 0.065
const BOLT_LIFT_RADIANS: float = PI / 3.0
const MECHANISM_SECONDS: float = 1.10
const INDEX_ROOT: Vector3 = Vector3(0.020, 0.015, -0.011)
const INDEX_JOINT: Vector3 = Vector3(0.012, 0.044, -0.045)
const INDEX_IDLE: Vector3 = Vector3(-0.032, 0.052, -0.058)
const INDEX_FIRE: Vector3 = Vector3(-0.031, 0.025, -0.077)
static var _packed: PackedScene

func build(hands: bool = false) -> Node3D:
	if _packed == null:
		_packed = load(SOURCE) as PackedScene
	var gun: Node3D = _packed.instantiate() as Node3D
	var bolt: Node3D = gun.get_node("Bolt") as Node3D
	gun.set_meta("bolt_rest", bolt.transform)
	for label: String in ["Body", "MuzzleCap"]:
		var mesh: MeshInstance3D = gun.get_node(label + "/" + label + "Mesh") as MeshInstance3D
		var finish: StandardMaterial3D = mesh.get_active_material(0).duplicate() as StandardMaterial3D
		finish.vertex_color_use_as_albedo = true
		mesh.material_override = finish
	if hands:
		var geometry: RefCounted = Workshop.new()
		_hand(geometry, geometry.group(gun, "TriggerHand", Vector3(0.040, -0.117, 0.136)), false)
		_hand(geometry, geometry.group(gun, "SupportHand", Vector3(-0.023, -0.065, -0.350)), true)
	return gun

func _hand(geometry: RefCounted, hand: Node3D, support: bool) -> void:
	var glove: StandardMaterial3D = geometry.material("sniper_work_glove", Color("78543d"), 0.0, 0.94)
	var cuff: StandardMaterial3D = geometry.material("sniper_cloth_cuff", Color("51483b"), 0.0, 0.96)
	var seam: StandardMaterial3D = geometry.material("sniper_glove_stitch", Color("a58059"), 0.0, 0.94)
	var side: float = -1.0 if support else 1.0
	var palm: MeshInstance3D = geometry.hull(hand, "Palm", PackedVector3Array([
		Vector3(-0.038, 0.016, 0.024), Vector3(-0.028, 0.024, 0.030),
		Vector3(0.025, 0.024, 0.030), Vector3(0.038, 0.017, 0.024)]), glove, Vector3.ZERO, 10)
	if support:
		palm.rotation.x = PI * 0.5
		palm.scale.z = 0.65
		palm.position.y = 0.016
	for digit: int in range(3):
		var y: float = 0.020 if support else 0.025 - digit * 0.018
		var z: float = -0.014 + digit * 0.016 if support else -0.004
		var a: Vector3 = Vector3(side * 0.022, y, z)
		var b: Vector3 = Vector3(side * 0.013, y + (0.020 if support else 0.0), z if support else -0.029)
		var c: Vector3 = Vector3(side * -0.030, b.y, z if support else -0.030)
		geometry.rod(hand, "Finger%dBase" % digit, a, b, 0.008, glove, 10)
		geometry.rod(hand, "Finger%dTip" % digit, b, c, 0.008, glove, 10)
		geometry.rod(hand, "Finger%dStitch" % digit, b + Vector3(0, 0.003, -0.008), b + Vector3(side * -0.016, 0.003, -0.008), 0.0012, seam, 6)
	if not support:
		for segment: MeshInstance3D in [geometry.rod(hand, "IndexBase", INDEX_ROOT, INDEX_JOINT, 0.007, glove, 10),
			geometry.rod(hand, "IndexTip", INDEX_JOINT, INDEX_IDLE, 0.006, glove, 10)]:
			segment.set_meta("index_rest", segment.transform)
	geometry.rod(hand, "ThumbBase", Vector3(side * 0.020, 0.0, 0.020), Vector3(side * 0.009, 0.028, 0.013), 0.009, glove, 10)
	geometry.rod(hand, "ThumbTip", Vector3(side * 0.009, 0.028, 0.013), Vector3(side * -0.009, 0.035, -0.017), 0.007, glove, 10)
	geometry.rod(hand, "Wrist", Vector3(side * 0.010, 0.005 if support else -0.027, 0.028), Vector3(side * 0.026, -0.074, 0.094), 0.024, glove, 12)
	geometry.rod(hand, "Sleeve", Vector3(side * 0.024, -0.069, 0.088), Vector3(side * 0.145, -0.200, 0.180), 0.035, cuff, 12)

func pose(gun: Node3D, time: float) -> void:
	var elapsed: float = time if is_finite(time) and time >= 0.0 else MECHANISM_SECONDS
	var bolt: Node3D = gun.get_node("Bolt") as Node3D
	bolt.transform = gun.get_meta("bolt_rest") as Transform3D
	var lift: float = 0.0
	var travel: float = 0.0
	if elapsed >= 0.05 and elapsed < 0.20:
		lift = smoothstep(0.05, 0.20, elapsed)
	elif elapsed >= 0.20 and elapsed < 0.85:
		lift = 1.0
	elif elapsed >= 0.85 and elapsed < 1.10:
		lift = 1.0 - smoothstep(0.85, 1.10, elapsed)
	if elapsed >= 0.20 and elapsed < 0.48:
		travel = smoothstep(0.20, 0.48, elapsed)
	elif elapsed >= 0.48 and elapsed < 0.60:
		travel = 1.0
	elif elapsed >= 0.60 and elapsed < 0.85:
		travel = 1.0 - smoothstep(0.60, 0.85, elapsed)
	bolt.rotation.z += lift * BOLT_LIFT_RADIANS
	bolt.position.z += travel * BOLT_TRAVEL_METRES
	var recoil: float = exp(-elapsed * 28.0) if elapsed < 0.22 else 0.0
	gun.rotation.x = -recoil * 0.025
	gun.position.z = recoil * 0.014
	_pose_index(gun, elapsed)

func _pose_index(gun: Node3D, elapsed: float) -> void:
	var hand: Node3D = gun.get_node_or_null("TriggerHand") as Node3D
	if hand == null:
		return
	var base: MeshInstance3D = hand.get_node("IndexBase") as MeshInstance3D
	var tip: MeshInstance3D = hand.get_node("IndexTip") as MeshInstance3D
	base.transform = base.get_meta("index_rest") as Transform3D
	tip.transform = tip.get_meta("index_rest") as Transform3D
	var held: float = 1.0 if elapsed < 0.08 else 1.0 - smoothstep(0.08, 0.18, elapsed)
	if held <= 0.0:
		return
	var end: Vector3 = INDEX_IDLE.lerp(INDEX_FIRE, held)
	var axis: Vector3 = (end - INDEX_ROOT).normalized()
	var reach: float = end.distance_to(INDEX_ROOT)
	var first_length: float = INDEX_JOINT.distance_to(INDEX_ROOT)
	var second_length: float = INDEX_IDLE.distance_to(INDEX_JOINT)
	var along: float = (first_length * first_length - second_length * second_length + reach * reach) / (2.0 * reach)
	var original_axis: Vector3 = (INDEX_IDLE - INDEX_ROOT).normalized()
	var bend: Vector3 = INDEX_JOINT - INDEX_ROOT
	bend -= original_axis * bend.dot(original_axis)
	bend = (bend - axis * bend.dot(axis)).normalized()
	var joint: Vector3 = INDEX_ROOT + axis * along + bend * sqrt(maxf(first_length * first_length - along * along, 0.0))
	for segment: Array in [[base, INDEX_ROOT, joint], [tip, joint, end]]:
		var mesh: MeshInstance3D = segment[0]
		var a: Vector3 = segment[1]
		var b: Vector3 = segment[2]
		mesh.position = (a + b) * 0.5
		mesh.quaternion = Quaternion(Vector3.BACK, (b - a).normalized())
