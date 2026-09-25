extends SceneTree

## Gamepad look math: radial deadzone, response curve, separate yaw and pitch
## rates, turn boost, eight-way movement, frame-rate independence, and the
## camera actually using them.

const CamScript := preload("res://scripts/spectator_cam.gd")

class OpenOwner extends Node:
	func controls_blocked() -> bool:
		return false

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_gamepad_look: " + message)

func _run() -> void:
	InputDevice.reset()
	_test_radial_deadzone()
	_test_curve()
	_test_rates_and_boost()
	_test_movement()
	_test_camera()
	_test_settings()
	InputDevice.reset()
	if _failures == 0:
		print("test_gamepad_look: PASS radial deadzone, curve, rates, boost, movement, camera")
	quit(0 if _failures == 0 else 1)

func _test_radial_deadzone() -> void:
	var dz: float = 0.12
	_check(LookInput.radial(Vector2(0.1, 0.05), dz) == Vector2.ZERO, "drift inside the deadzone is ignored")
	_check(LookInput.radial(Vector2(0.084, 0.084), dz) == Vector2.ZERO, "the deadzone is round, not per axis")
	var just_out: Vector2 = LookInput.radial(Vector2(0.121, 0.0), dz)
	_check(just_out.length() < 0.01, "output starts from zero at the deadzone edge, got %f" % just_out.length())
	var diagonal: Vector2 = LookInput.radial(Vector2(0.5, 0.5), dz)
	_check(absf(diagonal.angle() - Vector2(1, 1).angle()) < 1e-5, "direction survives the deadzone exactly")
	_check(is_equal_approx(LookInput.radial(Vector2(0.0, -0.97), dz).length(), 1.0), "past the outer edge the stick is fully deflected")
	var half: float = LookInput.radial(Vector2(0.535, 0.0), dz).length()
	_check(absf(half - 0.5) < 0.001, "the range rescales linearly between the edges, got %f" % half)
	_check(LookInput.radial(Vector2(NAN, 0.3), dz) == Vector2.ZERO, "non-finite input is ignored")

func _test_curve() -> void:
	# Five magnitudes, as the buttery-controls plan asks.
	var expected: Dictionary = {0.1: pow(0.1, 1.8), 0.25: pow(0.25, 1.8), 0.5: pow(0.5, 1.8), 0.75: pow(0.75, 1.8), 1.0: 1.0}
	for magnitude: float in expected:
		var shaped: Vector2 = LookInput.curve(Vector2(magnitude, 0.0), 1.8)
		_check(absf(shaped.x - float(expected[magnitude])) < 1e-5, "curve at %.2f should be %.4f, got %.4f" % [magnitude, expected[magnitude], shaped.x])
	_check(LookInput.curve(Vector2(0.4, 0.0), 1.0) == Vector2(0.4, 0.0), "exponent one is linear")
	var angled: Vector2 = LookInput.curve(Vector2(0.3, -0.4), 2.0)
	_check(absf(angled.angle() - Vector2(0.3, -0.4).angle()) < 1e-6, "the curve bends magnitude only, never direction")
	var precise: float = LookInput.shape(Vector2(0.3, 0.0), 0.12, 2.6).x
	var linear: float = LookInput.shape(Vector2(0.3, 0.0), 0.12, 1.0).x
	_check(precise < linear, "a steeper curve is finer near the centre")

func _test_rates_and_boost() -> void:
	var yaw_rate: float = deg_to_rad(240.0)
	var pitch_rate: float = deg_to_rad(150.0)
	var change: Vector2 = LookInput.stick_look(Vector2(1.0, 0.0), yaw_rate, pitch_rate, false, 1.0, 0.5)
	_check(is_equal_approx(change.x, deg_to_rad(120.0)) and is_zero_approx(change.y), "full right stick turns at the yaw rate")
	change = LookInput.stick_look(Vector2(0.0, -1.0), yaw_rate, pitch_rate, false, 1.0, 0.5)
	_check(is_equal_approx(change.y, deg_to_rad(75.0)), "stick up looks up at the separate pitch rate")
	change = LookInput.stick_look(Vector2(0.0, -1.0), yaw_rate, pitch_rate, true, 1.0, 0.5)
	_check(is_equal_approx(change.y, -deg_to_rad(75.0)), "invert flips stick pitch")
	_check(LookInput.accel_multiplier(0.0, true) == 1.0, "no boost before the stick sits at its edge")
	_check(is_equal_approx(LookInput.accel_multiplier(LookInput.ACCEL_SECONDS, true), 1.0 + LookInput.ACCEL_BOOST), "full boost after the ramp")
	_check(LookInput.accel_multiplier(5.0, false) == 1.0, "boost can be turned off")
	# Frame-rate independence: the same stick for one second at any frame rate.
	for fps: float in [30.0, 144.0, 360.0]:
		var total: float = 0.0
		for _frame: int in range(int(fps)):
			total += LookInput.stick_look(Vector2(0.6, 0.0), yaw_rate, pitch_rate, false, 1.0, 1.0 / fps).x
		_check(absf(total - 0.6 * yaw_rate) < 1e-4, "stick turn is frame-rate independent at %d fps" % int(fps))

func _test_movement() -> void:
	var cases: Dictionary = {
		Vector2(0.0, -1.0): ["forward"], Vector2(0.0, 1.0): ["back"],
		Vector2(-1.0, 0.0): ["left"], Vector2(1.0, 0.0): ["right"],
		Vector2(0.7, -0.7): ["forward", "right"], Vector2(-0.7, 0.7): ["back", "left"],
		Vector2(0.2, -0.95): ["forward"], Vector2(0.15, 0.05): [],
	}
	for stick: Vector2 in cases:
		var bits: Dictionary = LookInput.move_bits(stick, 0.12)
		var on: Array = []
		for key: String in ["forward", "back", "left", "right"]:
			if bits[key]:
				on.append(key)
		on.sort()
		var want: Array = (cases[stick] as Array).duplicate()
		want.sort()
		_check(on == want, "stick %s should move %s, got %s" % [stick, want, on])

func _test_camera() -> void:
	var owner_node: OpenOwner = OpenOwner.new()
	var cam: Node3D = CamScript.new()
	owner_node.add_child(cam)
	root.add_child(owner_node)
	cam.set_process(false)
	cam.fp_mode = true
	cam.stick_accel = false
	var stick: Array[Vector2] = [Vector2(0.05, 0.08)]
	cam.stick_source = func(right: bool) -> Vector2: return stick[0] if right else Vector2.ZERO
	cam._process_fp(0.5)
	_check(is_zero_approx(cam.fp_yaw) and is_zero_approx(cam.fp_pitch), "a resting, drifting stick does not move the view")
	stick[0] = Vector2(1.0, 0.0)
	cam._process_fp(0.25)
	_check(is_equal_approx(cam.fp_yaw, deg_to_rad(60.0)), "full right stick for a quarter second turns sixty degrees, got %f" % rad_to_deg(cam.fp_yaw))
	cam.fp_yaw = 0.0
	cam.stick_accel = true
	cam._stick_edge_seconds = 0.0
	for _frame: int in range(30):
		cam._process_fp(1.0 / 60.0)
	# Half a second: 120 degrees without the boost, about 182 with it.
	_check(rad_to_deg(cam.fp_yaw) > 170.0 and rad_to_deg(cam.fp_yaw) < 195.0, "turn boost speeds up a held full turn, got %.1f degrees" % rad_to_deg(cam.fp_yaw))
	stick[0] = Vector2.ZERO
	cam.stick_source = func(right: bool) -> Vector2: return Vector2.ZERO if right else Vector2(0.0, -0.9)
	var bits: Dictionary = cam.pad_move_bits()
	_check(bits["forward"] and not bits["back"], "left stick up walks forward")
	_check(cam._gamepad_move_active() and not cam._gamepad_look_active(), "the camera tells move from look")
	owner_node.free()

func _test_settings() -> void:
	var preferences: FragrSettings = FragrSettings.new("user://gamepad-look-unused.cfg")
	preferences.set_value("controls", "stick_yaw_speed", 300.0)
	preferences.set_value("controls", "stick_pitch_speed", 90.0)
	preferences.set_value("controls", "stick_deadzone", 0.9)
	preferences.set_value("controls", "stick_curve", 2.2)
	var cam: Node3D = CamScript.new()
	var lens: Camera3D = Camera3D.new()
	lens.name = "Camera3D"
	cam.add_child(lens)
	cam.apply_preferences(preferences)
	_check(is_equal_approx(cam.stick_yaw_rate, deg_to_rad(300.0)) and is_equal_approx(cam.stick_pitch_rate, deg_to_rad(90.0)), "separate horizontal and vertical speeds reach the camera")
	_check(is_equal_approx(cam.stick_deadzone, 0.4) and is_equal_approx(cam.stick_curve, 2.2), "deadzone is clamped and the curve reaches the camera")
	cam.free()
