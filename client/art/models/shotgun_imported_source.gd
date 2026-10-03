extends "res://art/models/shotgun_source.gd"

const SOURCE: String = "res://art/models/candidates/shotgun.glb"
static var _packed: PackedScene

func build(hands: bool = false) -> Node3D:
	if _packed == null:
		_packed = load(SOURCE) as PackedScene
	var gun: Node3D = _packed.instantiate() as Node3D
	gun.set_meta("pump_rest_z", (gun.get_node("Pump") as Node3D).position.z)
	if hands:
		var g: RefCounted = Workshop.new()
		_hand(g, g.group(gun.get_node("Pump"), "SupportHand", Vector3(-0.02, -0.063, 0.012)), true)
		_hand(g, g.group(gun, "TriggerHand", Vector3(0.04, -0.081, 0.047)), false)
		gun.get_node("TriggerHand").rotation_degrees = Vector3(0, 0, 90)
	return gun

func pose(gun: Node3D, time: float) -> void:
	# Reuse the existing presentation cadence and stroke. Only the source's
	# actual fore-end origin differs; the support glove shares its parent.
	super.pose(gun, time)
	gun.get_node("Pump").position.z += float(gun.get_meta("pump_rest_z")) + 0.55
