extends SceneTree

class Fighter extends Node3D:
	var target_yaw: float = 0.0
	var local_fp: bool = false
	func set_local_fp(enabled: bool) -> void:
		local_fp = enabled

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_spectator_camera: " + message)

func _run() -> void:
	var camera: Node3D = load("res://scripts/spectator_cam.gd").new()
	var first: Fighter = Fighter.new()
	var second: Fighter = Fighter.new()
	root.add_child(first)
	root.add_child(second)
	root.add_child(camera)
	camera.set_process(false)
	first.position = Vector3(4, 1.5, 7)
	second.position = Vector3(-3, 1.5, -9)
	for i in range(16):
		first.target_yaw = TAU * float(i) / 16.0
		camera.set_fp_mode(false)
		camera.set_fp_mode(true, first)
		_check((-camera.transform.basis.z).distance_to(ServerYaw.forward(first.target_yaw)) < 0.00001, "join facing must match server yaw")
		camera.fp_yaw = 2.1
		camera.fp_pitch = 0.3
		camera.set_fp_mode(true, first)
		_check(is_equal_approx(camera.fp_yaw, 2.1) and is_equal_approx(camera.fp_pitch, 0.3), "snapshot refresh must preserve local aim")
	camera.set_fp_mode(false)
	camera.set_available_targets([first, second])
	camera._follow_target()
	_check(camera.is_observing_first_person(), "spectator starts at eye level")
	_check(first.local_fp and not second.local_fp, "hide only the watched body")
	_check(is_equal_approx(camera.position.y, 1.6), "spectator eye height is 1.6 metres")
	_check((-camera.transform.basis.z).distance_to(ServerYaw.forward(first.target_yaw)) < 0.00001, "spectator facing uses server convention")
	camera.set_available_targets([second, first])
	_check(camera.get_followed_target() == first, "roster order must not change the watched fighter")
	camera.cycle_next_target()
	camera._follow_target()
	_check(not first.local_fp and second.local_fp, "cycling restores the previous fighter")
	camera.toggle_follow_mode()
	camera._follow_target()
	_check(camera.follow_mode and not camera.is_observing_first_person() and not second.local_fp, "chase view restores the body")
	camera.toggle_follow_mode()
	_check(not camera.follow_mode and camera.get_followed_target() == null, "free camera has no watched fighter")
	camera.toggle_follow_mode()
	camera._follow_target()
	_check(camera.is_observing_first_person(), "view cycle returns to eyes")
	camera.set_available_targets([])
	_check(not second.local_fp and not camera.is_observing_first_person(), "empty roster clears hidden bodies")
	camera.queue_free()
	first.queue_free()
	second.queue_free()
	await process_frame
	if _failures == 0:
		print("test_spectator_camera: PASS aim, facing, eye height, view cycle, roster changes")
	quit(0 if _failures == 0 else 1)
