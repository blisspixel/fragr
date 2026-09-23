extends SceneTree

class Fighter extends Node3D:
	var player_id: String = ""
	var target_yaw: float = 0.0
	var target_pitch: float = 0.0
	var local_fp: bool = false
	func set_local_fp(enabled: bool) -> void:
		local_fp = enabled

class InputBlocker extends Node3D:
	func controls_blocked() -> bool:
		return true

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
	first.player_id = "first"
	second.player_id = "second"
	root.add_child(first)
	root.add_child(second)
	root.add_child(camera)
	camera.set_process(false)
	_check(camera.follow_mode and camera.spectator_first_person, "new spectators default to followed eyes")
	first.position = Vector3(4, 1.5, 7)
	second.position = Vector3(-3, 1.5, -9)
	for i in range(16):
		first.target_yaw = TAU * float(i) / 16.0
		first.target_pitch = -0.7 + float(i) / 15.0 * 1.4
		camera.set_fp_mode(false)
		camera.set_fp_mode(true, first)
		_check((-camera.transform.basis.z).distance_to(ServerYaw.aim_direction(first.target_yaw, first.target_pitch)) < 0.00001, "join facing must match server yaw and pitch")
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
	_check((-camera.transform.basis.z).distance_to(ServerYaw.aim_direction(first.target_yaw, first.target_pitch)) < 0.00001, "spectator facing uses server yaw and pitch")
	_check(camera.position.distance_to(first.position + Vector3(0.0, 0.1, 0.0)) < 0.00001, "camera origin matches the server eye without a forward offset")
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
	camera.set_available_targets([first, second])
	camera.auto_cycle_interval = 3.0
	camera.pin_player("second")
	_check(camera.get_followed_target() == second and camera.available_targets.size() == 1, "watch pin selects exact identity")
	camera.cycle_next_target()
	camera.toggle_follow_mode()
	_check(camera.get_followed_target() == second and camera.spectator_first_person, "watch pin ignores camera controls")
	camera._follow_target()
	camera.set_available_targets([first])
	_check(camera.get_followed_target() == null and not second.local_fp, "missing pin never switches fighter")
	var replacement: Fighter = Fighter.new()
	replacement.player_id = "second"
	root.add_child(replacement)
	camera.set_available_targets([first, replacement])
	_check(camera.get_followed_target() == replacement, "watch pin reacquires same identity")
	camera.pin_player("")
	_check(camera.available_targets.size() == 2, "clearing pin restores roster")
	_check(camera.auto_cycle_interval == 3.0, "clearing pin retains normal camera cycle setting")
	var blocker: InputBlocker = InputBlocker.new()
	root.add_child(blocker)
	camera.reparent(blocker)
	camera.pin_player("second")
	replacement.position = Vector3(8, 1.5, 12)
	camera._process(0.05)
	_check(camera.global_position.distance_to(replacement.global_position + Vector3(0.0, 0.1, 0.0)) < 0.00001, "blocked chat input keeps first-person follow live")
	replacement.queue_free()
	camera.queue_free()
	blocker.queue_free()
	first.queue_free()
	second.queue_free()
	await process_frame
	if _failures == 0:
		print("test_spectator_camera: PASS aim, facing, eye height, view cycle, roster changes")
	quit(0 if _failures == 0 else 1)
