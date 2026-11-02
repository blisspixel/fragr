extends SceneTree

const Support = preload("res://art/characters/pose_support.gd")
const Machines = preload("res://art/characters/machines.gd")
const Jammer = preload("res://art/characters/jammer_rig.gd")
const Crawler = preload("res://art/characters/crawler_rig.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_enemy_pose_support: " + message)

func _run() -> void:
	var machines: RefCounted = Machines.new()
	var jammer: RefCounted = Jammer.new()
	var crawler: RefCounted = Crawler.new()
	for index: int in range(21):
		var progress: float = index / 20.0
		for kind: String in ["heavy_sweeper", "jammer", "crawler"]:
			var pose: Node3D = machines.build_machine(kind, "death", progress, false) if kind == "heavy_sweeper" else (jammer.build_pose("death", progress) if kind == "jammer" else crawler.build_pose("death", progress))
			var low: float = Support.minimum_y(pose)
			_check(is_finite(low) and low >= -0.005, "%s death %.2f actual source bottom %.5f" % [kind, progress, low])
			pose.free()
	# A nested rotated mesh supplies an independent physical penetration control.
	var control: Node3D = Node3D.new()
	var joint: Node3D = Node3D.new()
	control.add_child(joint)
	joint.position.y = 0.2
	joint.rotation_degrees.z = 30
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(0.4, 1.0, 0.3)
	joint.add_child(mesh)
	var before: float = Support.minimum_y(control)
	_check(before < -0.25, "nested tilted source actually penetrates before correction")
	var lift: float = Support.lift_to_floor(control)
	_check(lift > 0.25 and absf(Support.minimum_y(control)) < 0.00001, "actual transformed source rests on floor after correction")
	_check(Support.lift_to_floor(control) < 0.00001, "settled source does not drift on repeated correction")
	control.free()
	if _failures == 0:
		print("test_enemy_pose_support: PASS")
	quit(0 if _failures == 0 else 1)
