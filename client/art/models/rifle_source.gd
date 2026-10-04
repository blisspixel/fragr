extends RefCounted

const SOURCE: String = "res://art/models/candidates/rifle.glb"
const Workshop = preload("res://scripts/model_geometry.gd")
const BOLT_TRAVEL_METRES: float = 0.030
const MECHANISM_SECONDS: float = 0.14
static var _packed: PackedScene

func build(hands: bool = false) -> Node3D:
	if _packed == null:
		_packed = load(SOURCE) as PackedScene
	var gun: Node3D = _packed.instantiate() as Node3D
	for name: String in ["Body", "Bolt", "Trigger"]:
		var part: Node3D = gun.get_node(name) as Node3D
		gun.set_meta(name.to_lower() + "_rest", part.transform)
		var mesh: MeshInstance3D = part.get_node(name + "Mesh") as MeshInstance3D
		var finish: StandardMaterial3D = mesh.get_active_material(0).duplicate() as StandardMaterial3D
		finish.vertex_color_use_as_albedo = true
		mesh.material_override = finish
	if hands:
		var geometry: RefCounted = Workshop.new()
		_hand(geometry, geometry.group(gun, "TriggerHand", Vector3(0.025, -0.137, 0.185)), false)
		_hand(geometry, geometry.group(gun, "SupportHand", Vector3(-0.024, -0.058, -0.215)), true)
	return gun

func _hand(geometry: RefCounted, hand: Node3D, support: bool) -> void:
	var glove: StandardMaterial3D = geometry.material("rifle_work_glove", Color("78543d"), 0.0, 0.94)
	var cuff: StandardMaterial3D = geometry.material("rifle_cuff", Color("514137"), 0.0, 0.96)
	var seam: StandardMaterial3D = geometry.material("rifle_glove_seam", Color("a58059"), 0.0, 0.94)
	var side: float = -1.0 if support else 1.0
	var palm: MeshInstance3D = geometry.hull(hand, "Palm", PackedVector3Array([
		Vector3(-0.038, 0.016, 0.024), Vector3(-0.028, 0.024, 0.030),
		Vector3(0.025, 0.024, 0.030), Vector3(0.038, 0.017, 0.024)]), glove, Vector3.ZERO, 10)
	if support:
		palm.rotation.x = PI * 0.5
		palm.scale.z = 0.65
		palm.position.y = 0.016
	for digit: int in range(3):
		var y: float = 0.020 if support else 0.020 - digit * 0.018
		var z: float = -0.014 + digit * 0.016 if support else -0.004
		var a: Vector3 = Vector3(side * 0.022, y, z)
		var b: Vector3 = Vector3(side * 0.013, y + (0.020 if support else 0.0), z if support else -0.029)
		var c: Vector3 = Vector3(side * -0.030, b.y, z if support else -0.030)
		geometry.rod(hand, "Finger%dBase" % digit, a, b, 0.008, glove, 10)
		geometry.rod(hand, "Finger%dTip" % digit, b, c, 0.008, glove, 10)
		geometry.rod(hand, "Finger%dSeam" % digit, b + Vector3(0, 0.003, -0.008),
			b + Vector3(side * -0.016, 0.003, -0.008), 0.0012, seam, 6)
	if not support:
		geometry.rod(hand, "IndexBase", Vector3(0.020, 0.015, -0.011), Vector3(0.012, 0.060, -0.045), 0.007, glove, 10)
		geometry.rod(hand, "IndexTip", Vector3(0.012, 0.060, -0.045), Vector3(-0.018, 0.065, -0.066), 0.006, glove, 10)
	geometry.rod(hand, "ThumbBase", Vector3(side * 0.020, 0.0, 0.020), Vector3(side * 0.009, 0.028, 0.013), 0.009, glove, 10)
	geometry.rod(hand, "ThumbTip", Vector3(side * 0.009, 0.028, 0.013), Vector3(side * -0.009, 0.035, -0.017), 0.007, glove, 10)
	geometry.rod(hand, "Wrist", Vector3(side * 0.010, 0.005 if support else -0.027, 0.028), Vector3(side * 0.026, -0.074, 0.094), 0.024, glove, 12)
	geometry.rod(hand, "Sleeve", Vector3(side * 0.024, -0.069, 0.088), Vector3(side * 0.145, -0.200, 0.310), 0.035, cuff, 12)

func pose(gun: Node3D, time: float) -> void:
	var elapsed: float = time if is_finite(time) and time >= 0.0 else MECHANISM_SECONDS
	var cycle: float = sin(elapsed / MECHANISM_SECONDS * PI) if elapsed > 0.0 and elapsed < MECHANISM_SECONDS else 0.0
	var recoil: float = exp(-elapsed * 36.0) if elapsed < MECHANISM_SECONDS else 0.0
	gun.rotation.x = -0.025 * recoil
	gun.position.z = 0.010 * recoil
	for name: String in ["Bolt", "Trigger"]:
		var part: Node3D = gun.get_node(name) as Node3D
		part.transform = gun.get_meta(name.to_lower() + "_rest") as Transform3D
	var bolt: Node3D = gun.get_node("Bolt") as Node3D
	var trigger: Node3D = gun.get_node("Trigger") as Node3D
	bolt.position.z += cycle * BOLT_TRAVEL_METRES
	trigger.rotation.x -= cycle * 0.12
