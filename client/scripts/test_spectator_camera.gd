extends SceneTree

const TOUR = preload("res://scripts/qa_tour.gd")

class Fighter extends Node3D:
	var player_id: String = ""
	var target_yaw: float = 0.0
	var target_pitch: float = 0.0
	var local_fp: bool = false
	func set_local_fp(enabled: bool) -> void:
		local_fp = enabled

class AuthoritativeFighter extends Fighter:
	var target_position: Vector3 = Vector3.ZERO
	var prediction_active: bool = false
	var ducking: bool = false

class BufferedFighter extends Fighter:
	var presentation_yaw: float = 0.0
	var presentation_pitch: float = 0.0

class InputBlocker extends Node3D:
	func controls_blocked() -> bool:
		return true

var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
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
	var buffered: BufferedFighter = BufferedFighter.new()
	root.add_child(buffered)
	buffered.player_id = "buffered"
	buffered.position = Vector3(5.0, 1.5, 6.0)
	buffered.target_yaw = 2.4
	buffered.target_pitch = 0.6
	buffered.presentation_yaw = 1.2
	buffered.presentation_pitch = -0.2
	camera.set_available_targets([buffered])
	camera._follow_target()
	_check((-camera.transform.basis.z).distance_to(ServerYaw.aim_direction(1.2, -0.2)) < 0.00001,
		"spectator eyes use buffered aim at the same time as rendered position")
	camera.set_fp_mode(true, buffered)
	_check(is_equal_approx(camera.fp_yaw, 2.4) and is_equal_approx(camera.fp_pitch, 0.6),
		"local joining still adopts latest authoritative aim instead of buffered spectator aim")
	camera.set_fp_mode(false)
	camera.set_available_targets([first, second])
	camera._follow_target()
	_check(camera.is_observing_first_person(), "spectator starts at eye level")
	_check(first.local_fp and not second.local_fp, "hide only the watched body")
	_check(is_equal_approx(camera.position.y, 1.6), "spectator eye height is 1.6 metres")
	_check((-camera.transform.basis.z).distance_to(ServerYaw.aim_direction(first.target_yaw, first.target_pitch)) < 0.00001, "spectator facing uses server yaw and pitch")
	_check(camera.position.distance_to(first.position + Vector3(0.0, 0.1, 0.0)) < 0.00001, "camera origin matches the server eye without a forward offset")
	var local: AuthoritativeFighter = AuthoritativeFighter.new()
	root.add_child(local)
	local.position = Vector3(-2.0, 1.5, 0.0)
	local.target_position = Vector3(4.0, 1.5, 0.0)
	camera.set_fp_mode(false)
	camera.set_fp_mode(true, local)
	camera.assist_solids = [{"min_x":-0.5, "max_x":0.5, "min_z":-1.0, "max_z":1.0, "bottom":0.0, "top":3.0}]
	camera._process(0.016)
	_check(camera.global_position.distance_to(local.target_position + Vector3(0.0, 0.1, 0.0)) < 0.00001,
		"local first-person eye snaps to the server body instead of smoothing through stair cover")
	camera.assist_solids = []
	camera.global_position = local.position + Vector3(0.0, 0.1, 0.0)
	camera._process(0.016)
	_check(camera.global_position.x > local.position.x and camera.global_position.x < local.target_position.x,
		"local first-person motion remains smoothed in open space")
	local.prediction_active = true
	local.position = Vector3(1.0, 1.5, 2.0)
	local.target_position = Vector3(4.0, 1.5, 0.0)
	camera.assist_solids = []
	camera.global_position = Vector3.ZERO
	camera._process(0.016)
	_check(camera.global_position.distance_to(local.position + Vector3(0.0, 0.1, 0.0)) < 0.00001,
		"predicted first person follows the rendered body between snapshots")
	local.ducking = true
	camera._process(0.016)
	_check(camera.global_position.distance_to(local.position + Vector3(0.0, 0.1 - 0.45, 0.0)) < 0.00001,
		"a duck lowers the eye by 0.45 metres")
	local.ducking = false
	local.prediction_active = false
	camera.set_fp_mode(false)
	camera.set("tip_pose_lock", true)
	camera.set("tip_has_locked_transform", true)
	camera.set_fp_mode(true, local)
	_check(not bool(camera.get("fp_mode")), "a detached spectator pose blocks human first-person mode")
	TOUR.release_camera_pose_lock(camera)
	camera.set_fp_mode(true, local)
	_check(bool(camera.get("fp_mode")) and camera.get("fp_target") == local,
		"tour clears the detached pose before restoring human first-person control")
	camera.set_fp_mode(false)
	local.queue_free()
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
	_check_chase_cadence(first)
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
	buffered.queue_free()
	await process_frame
	if _failures == 0:
		print("test_spectator_camera: PASS aim, facing, eye height, view cycle, roster changes")
	quit(0 if _failures == 0 else 1)


func _check_chase_cadence(target: Fighter) -> void:
	var reference: Vector3 = Vector3.ZERO
	var reference_basis: Basis = Basis.IDENTITY
	var frag_reference: Vector3 = Vector3.ZERO
	for hz: int in [30, 60, 144]:
		var chase: Node3D = load("res://scripts/spectator_cam.gd").new()
		root.add_child(chase)
		chase.set_process(false)
		chase.spectator_first_person = false
		chase.set_available_targets([target])
		for frame: int in range(hz / 2):
			chase._follow_target(1.0 / float(hz))
		if hz == 30:
			reference = chase.position
		else:
			_check(chase.position.distance_to(reference) < 0.0001,
				"chase displacement agrees after equal time at %d Hz" % hz)
		# Isolate orientation from the changing chase origin.
		chase.position = target.position + Vector3(0, 5.5, 10.5).rotated(Vector3.UP, target.rotation.y)
		chase.rotation = Vector3.ZERO
		for frame: int in range(hz / 2):
			chase._follow_target(1.0 / float(hz))
		if hz == 30:
			reference_basis = chase.basis
		else:
			_check(chase.basis.x.distance_to(reference_basis.x) < 0.0001
				and chase.basis.z.distance_to(reference_basis.z) < 0.0001,
				"chase orientation agrees after equal time at %d Hz" % hz)
		chase.position = Vector3.ZERO
		chase.frag_follow_target_id = target.player_id
		for frame: int in range(hz / 2):
			chase._follow_frag_target(1.0 / float(hz))
		if hz == 30:
			frag_reference = chase.position
		else:
			_check(chase.position.distance_to(frag_reference) < 0.0001,
				"frag chase displacement agrees after equal time at %d Hz" % hz)
		chase.camera_shake_intensity = 0.3
		chase.camera_zoom_offset = -1.5
		chase._process(10.0)
		_check(chase.camera_shake_intensity >= 0.0 and chase.camera_zoom_offset <= 0.0,
			"a long frame does not invert camera decay")
		chase.queue_free()
