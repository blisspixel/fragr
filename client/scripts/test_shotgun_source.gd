extends SceneTree

const Source = preload("res://art/models/shotgun_imported_source.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var source: RefCounted = Source.new()
	var gun: Node3D = source.build(true)
	root.add_child(gun)
	var body: MeshInstance3D = gun.get_node("Body") as MeshInstance3D
	var pump: Node3D = gun.get_node("Pump") as Node3D
	var fore_end: MeshInstance3D = pump.get_node("ForeEnd") as MeshInstance3D
	_check(body.mesh.get_faces().size() / 3 == 11357 and fore_end.mesh.get_faces().size() / 3 == 1496,
		"source split retains every reviewed triangle")
	var material: StandardMaterial3D = fore_end.get_active_material(0) as StandardMaterial3D
	_check(material.albedo_texture.get_width() == 1024 and material.normal_texture.get_width() == 1024,
		"prepared maps stay within their embedded 1K budget")
	var rest: Vector3 = pump.position
	var fixed: Transform3D = body.transform
	var muzzle: Vector3 = gun.get_node("Muzzle").position
	var glove: Node3D = pump.get_node("SupportHand") as Node3D
	var contact: Transform3D = glove.transform
	var initial_hand: Vector3 = glove.global_position
	source.pose(gun, 0.31)
	_check(pump.position.z > rest.z + 0.10, "the actual independent fore-end cycles back")
	_check(body.transform == fixed and gun.get_node("Muzzle").position == muzzle,
		"receiver and barrel stay fixed while the fore-end cycles")
	_check(glove.transform == contact and glove.global_position.z > initial_hand.z + 0.10,
		"support glove travels with the pump without changing grip")
	source.pose(gun, 0.5)
	_check(pump.position.is_equal_approx(rest) and body.transform == fixed,
		"source returns to the same geometry")
	gun.free()
	await process_frame
	if _failures == 0:
		print("test_shotgun_source: PASS preserved geometry, map budget and independent pump with attached hand")
	quit(0 if _failures == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_shotgun_source: " + message)
