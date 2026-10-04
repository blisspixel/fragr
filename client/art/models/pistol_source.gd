extends RefCounted

const SOURCE: String = "res://art/models/candidates/pistol.glb"
const Workshop = preload("res://scripts/model_geometry.gd")
const SLIDE_TRAVEL_METRES: float = 0.012
const MECHANISM_SECONDS: float = 0.12
static var _packed: PackedScene

func build(hands: bool = false) -> Node3D:
	if _packed == null:
		_packed = load(SOURCE) as PackedScene
	var gun: Node3D = _packed.instantiate() as Node3D
	for name: String in ["Slide", "Trigger", "Hammer"]:
		var part: Node3D = gun.get_node(name) as Node3D
		gun.set_meta(name.to_lower() + "_rest", part.transform)
	if hands:
		var geometry: RefCounted = Workshop.new()
		_hand(geometry, geometry.group(gun, "TriggerHand"), false)
		_hand(geometry, geometry.group(gun, "SupportHand"), true)
	return gun

func _hand(geometry: RefCounted, hand: Node3D, support: bool) -> void:
	var glove: StandardMaterial3D = geometry.material("pistol_work_glove", Color("555b45"), 0.0, 0.92)
	var cuff: StandardMaterial3D = geometry.material("pistol_cuff", Color("353c32"), 0.0, 0.96)
	var seam: StandardMaterial3D = geometry.material("pistol_glove_seam", Color("7e8269"), 0.0, 0.9)
	var side: float = -1.0 if support else 1.0
	var palm: MeshInstance3D = geometry.hull(hand, "Palm", PackedVector3Array([
		Vector3(-0.028, 0.014, 0.020), Vector3(-0.018, 0.019, 0.027),
		Vector3(0.018, 0.019, 0.027), Vector3(0.030, 0.013, 0.021)]), glove,
		Vector3(side * 0.034, -0.100, 0.025), 10)
	palm.rotation.z = side * -0.12
	for digit: int in range(3):
		var y: float = -0.081 - digit * 0.016 - (0.008 if support else 0.0)
		var z: float = -0.010 - (0.009 if support else 0.0)
		var a: Vector3 = Vector3(side * 0.040, y, 0.010)
		var b: Vector3 = Vector3(side * 0.026, y, z)
		var c: Vector3 = Vector3(side * -0.008, y, z - 0.003)
		geometry.rod(hand, "Finger%dBase" % digit, a, b, 0.008, glove, 10)
		geometry.rod(hand, "Finger%dTip" % digit, b, c, 0.008, glove, 10)
		geometry.rod(hand, "Finger%dSeam" % digit, b + Vector3(0, 0.002, -0.007),
			b + Vector3(side * -0.011, 0.002, -0.007), 0.001, seam, 6)
	if not support:
		geometry.rod(hand, "IndexBase", Vector3(0.041, -0.080, 0.008),
			Vector3(0.029, -0.047, -0.039), 0.006, glove, 10)
		geometry.rod(hand, "IndexTip", Vector3(0.029, -0.047, -0.039),
			Vector3(0.005, -0.044, -0.058), 0.006, glove, 10)
	var thumb_y: float = -0.065 if not support else -0.078
	geometry.rod(hand, "ThumbBase", Vector3(side * 0.040, -0.093, 0.041),
		Vector3(side * 0.029, thumb_y, 0.030), 0.010, glove, 10)
	geometry.rod(hand, "ThumbTip", Vector3(side * 0.029, thumb_y, 0.030),
		Vector3(side * 0.018, thumb_y + 0.005, -0.012), 0.008, glove, 10)
	geometry.rod(hand, "Wrist", Vector3(side * 0.035, -0.128, 0.040),
		Vector3(side * 0.062, -0.173, 0.112), 0.026, glove, 12)
	geometry.rod(hand, "Sleeve", Vector3(side * 0.057, -0.162, 0.102),
		Vector3(side * 0.135, -0.280, 0.245), 0.034, cuff, 12)

func pose(gun: Node3D, time: float) -> void:
	var elapsed: float = time if is_finite(time) and time >= 0.0 else MECHANISM_SECONDS
	var cycle: float = sin(elapsed / MECHANISM_SECONDS * PI) if elapsed > 0.0 and elapsed < MECHANISM_SECONDS else 0.0
	var recoil: float = exp(-elapsed * 32.0) if elapsed < MECHANISM_SECONDS else 0.0
	gun.rotation.x = -0.035 * recoil
	gun.position.z = 0.008 * recoil
	for name: String in ["Slide", "Trigger", "Hammer"]:
		var part: Node3D = gun.get_node(name) as Node3D
		part.transform = gun.get_meta(name.to_lower() + "_rest") as Transform3D
	var slide: Node3D = gun.get_node("Slide") as Node3D
	var trigger: Node3D = gun.get_node("Trigger") as Node3D
	var hammer: Node3D = gun.get_node("Hammer") as Node3D
	slide.position.z += cycle * SLIDE_TRAVEL_METRES
	trigger.rotation.x -= cycle * 0.14
	hammer.rotation.x += cycle * 0.4
