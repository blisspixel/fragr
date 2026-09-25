extends SceneTree
## Headless check that mouse look uses portable units and lands in the band
## competitive players actually use. Run with:
## godot --headless --path client --script res://scripts/test_aim_sensitivity.gd

const CamScript := preload("res://scripts/spectator_cam.gd")

var failures: Array = []

class OverlayOwner extends Node:
	var blocked: bool = false
	func controls_blocked() -> bool:
		return blocked


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_convention()
	_test_default_is_in_the_band()
	_test_edges()
	_test_input_path()
	if failures.is_empty():
		print("test_aim_sensitivity: PASS")
		quit(0)
	else:
		for failure: String in failures:
			printerr("test_aim_sensitivity: FAIL " + failure)
		quit(1)


func _test_convention() -> void:
	# The Source convention: 0.022 degrees per count at sensitivity 1.0.
	_check(
		absf(CamScript.DEGREES_PER_COUNT - 0.022) < 1e-9,
		"degrees per count should be the Source 0.022, got %f" % CamScript.DEGREES_PER_COUNT
	)
	# A known pairing: Counter-Strike's default 1.25 at 800 counts per inch is
	# about 41.6 cm per 360. Same arithmetic, so it must reproduce.
	var cs := CamScript.cm_per_360(1.25, 800.0)
	_check(absf(cs - 41.6) < 0.2, "sensitivity 1.25 at 800 cpi should be about 41.6 cm/360, got %.2f" % cs)
	# Doubling sensitivity halves the travel.
	var a := CamScript.cm_per_360(1.0, 800.0)
	var b := CamScript.cm_per_360(2.0, 800.0)
	_check(absf(a / b - 2.0) < 1e-6, "twice the sensitivity should be half the travel")
	# Doubling the mouse resolution halves the travel too.
	var c := CamScript.cm_per_360(1.0, 1600.0)
	_check(absf(a / c - 2.0) < 1e-6, "twice the counts per inch should be half the travel")


func _test_default_is_in_the_band() -> void:
	var cam = CamScript.new()
	var cm := CamScript.cm_per_360(cam.mouse_sensitivity, 800.0)
	_check(
		cm >= 30.0 and cm <= 50.0,
		"the default should sit in the 30 to 50 cm/360 band at 800 cpi, got %.1f" % cm
	)
	# The old default was 0.003 radians per count, which is far outside it.
	var old_cm := (360.0 / (rad_to_deg(0.003) * 800.0)) * 2.54
	_check(old_cm < 10.0, "sanity: the old default really was under 10 cm/360, got %.1f" % old_cm)
	cam.free()


func _test_edges() -> void:
	_check(CamScript.cm_per_360(0.0, 800.0) == 0.0, "zero sensitivity has no meaningful travel")
	_check(CamScript.cm_per_360(1.0, 0.0) == 0.0, "zero counts per inch has no meaningful travel")
	_check(CamScript.cm_per_360(-1.0, 800.0) == 0.0, "negative sensitivity has no meaningful travel")

func _test_input_path() -> void:
	var owner_node: OverlayOwner = OverlayOwner.new()
	var cam: Node3D = CamScript.new()
	owner_node.add_child(cam)
	root.add_child(owner_node)
	cam.set_process(false)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(900, 900)
	motion.screen_relative = Vector2(10, 5)
	cam.accept_mouse_motion(motion, true)
	motion.relative = Vector2(1800, 1800)
	cam.accept_mouse_motion(motion, true)
	_check(cam.mouse_motion == Vector2(20, 10), "mouse events accumulate unscaled counts independent of content scaling")
	cam._process_fp(0.0)
	var turn: float = deg_to_rad(0.022 * 1.5)
	_check(is_equal_approx(cam.fp_yaw, 20 * turn) and is_equal_approx(cam.fp_pitch, -10 * turn), "counts drive actual yaw and pitch exactly once")
	_check(cam.mouse_motion == Vector2.ZERO, "consumed counts must clear")
	cam.invert_y = true
	cam.accept_mouse_motion(motion, true)
	cam._process_fp(0.0)
	_check(is_equal_approx(cam.fp_pitch, -5 * turn), "invert look reverses mouse pitch without changing yaw")
	owner_node.blocked = true
	cam.mouse_motion = Vector2(80, 30)
	var previous: float = cam.fp_yaw
	Input.action_press("turn_right")
	cam._process(1.0)
	Input.action_release("turn_right")
	_check(cam.mouse_motion == Vector2.ZERO and cam.fp_yaw == previous, "overlay blocks held keyboard/gamepad look and clears queued motion")
	cam.accept_mouse_motion(motion, true)
	_check(cam.mouse_motion == Vector2.ZERO, "overlay rejects new mouse motion")
	owner_node.blocked = false
	cam.accept_mouse_motion(motion, false)
	_check(cam.mouse_motion == Vector2.ZERO, "released mouse cannot queue aim input")
	cam.fp_pitch = 0.0
	cam.stick_source = func(right: bool) -> Vector2: return Vector2(0.0, 1.0) if right else Vector2.ZERO
	cam._apply_stick_look(0.25, false)
	var stick_pitch: float = deg_to_rad(150.0) * 0.25
	_check(is_equal_approx(cam.fp_pitch, stick_pitch), "invert look applies to gamepad pitch, got %f" % cam.fp_pitch)
	cam.invert_y = false
	cam._apply_stick_look(0.25, false)
	_check(is_zero_approx(cam.fp_pitch), "normal gamepad pitch reverses the same deflection")
	Input.action_press("look_down")
	cam.invert_y = true
	cam.stick_source = func(_right: bool) -> Vector2: return Vector2.ZERO
	cam._apply_stick_look(0.25, false)
	Input.action_release("look_down")
	_check(cam.fp_pitch < 0.0, "look keys are literal: invert changes mouse and stick, never the look down key")
	owner_node.free()
