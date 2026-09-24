extends SceneTree

## Aim assist for keyboard-only and gamepad look: the cone, line of sight
## through MapInfo solids, device gating, gentle frame-rate independent pull,
## gamepad friction, and proof that mouse look is never altered.

const CamScript := preload("res://scripts/spectator_cam.gd")
const STANDARD: AimAssist.Level = AimAssist.Level.STANDARD

class OpenOwner extends Node:
	func controls_blocked() -> bool:
		return false

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_aim_assist: " + message)

## A point `distance` metres away at `degrees` of yaw right of +X and `rise`
## metres above the eye.
static func _at(eye: Vector3, degrees: float, distance: float, rise: float = 0.0) -> Vector3:
	var yaw: float = deg_to_rad(degrees)
	return eye + Vector3(cos(yaw) * distance, rise, sin(yaw) * distance)

func _run() -> void:
	InputDevice.reset()
	_test_cone_and_range()
	_test_visibility()
	_test_gating()
	_test_keyboard_pull()
	_test_pad()
	_test_camera_mouse_untouched()
	_test_camera_keyboard_and_levels()
	InputDevice.reset()
	if _failures == 0:
		print("test_aim_assist: PASS cone, line of sight, device gating, gentle pull, pad friction, mouse untouched")
	quit(0 if _failures == 0 else 1)

func _test_cone_and_range() -> void:
	var eye: Vector3 = Vector3(0, 1.6, 0)
	var near_edge: Vector3 = _at(eye, 6.0, 20.0, -1.0)
	var picked: Dictionary = AimAssist.pick(eye, 0.0, 0.0, [near_edge], [], STANDARD)
	_check(not picked.is_empty(), "a hostile six degrees off at twenty metres is inside the standard cone")
	_check(AimAssist.pick(eye, 0.0, 0.0, [near_edge], [], AimAssist.Level.LIGHT).is_empty(), "light has a narrower cone")
	_check(AimAssist.pick(eye, 0.0, 0.0, [_at(eye, 12.0, 20.0)], [], STANDARD).is_empty(), "twelve degrees off is ignored")
	_check(not AimAssist.pick(eye, 0.0, 0.0, [_at(eye, 12.0, 2.0)], [], STANDARD).is_empty(), "a close body widens the cone by its own width")
	_check(AimAssist.pick(eye, 0.0, 0.0, [_at(eye, 1.0, 45.0)], [], STANDARD).is_empty(), "beyond forty metres there is no help")
	_check(AimAssist.pick(eye, 0.0, 0.0, [_at(eye, 181.0, 10.0)], [], STANDARD).is_empty(), "nothing behind the player")
	_check(AimAssist.pick(eye, 0.0, 0.0, [near_edge], [], AimAssist.Level.OFF).is_empty(), "off is off")
	var nearest: Dictionary = AimAssist.pick(eye, 0.0, 0.0, [_at(eye, 4.0, 10.0), _at(eye, -1.0, 30.0)], [], STANDARD)
	_check(absf(rad_to_deg(float(nearest["yaw_error"])) + 1.0) < 0.01, "the hostile nearest the crosshair wins")
	# Wrap-around: facing just under a full turn still sees a target at zero.
	_check(not AimAssist.pick(eye, TAU - 0.01, 0.0, [_at(eye, 0.5, 10.0)], [], STANDARD).is_empty(), "yaw wraps across zero")
	var server: Vector3 = Vector3(3, 1.5, 4)
	_check(AimAssist.body_centre(server).is_equal_approx(Vector3(3, 0.9, 4)), "the body centre sits mid-height above the server reference")

func _test_visibility() -> void:
	var eye: Vector3 = Vector3(0, 1.6, 0)
	var target: Vector3 = Vector3(10, 1.6, 0)
	var wall: Dictionary = {"min_x": 4.0, "max_x": 5.0, "min_z": -2.0, "max_z": 2.0, "bottom": 0.0, "top": 4.5}
	_check(not AimAssist.line_of_sight(eye, target, [wall]), "a wall between blocks sight")
	_check(AimAssist.pick(eye, 0.0, 0.0, [target], [wall], STANDARD).is_empty(), "no help through cover")
	var low: Dictionary = {"min_x": 4.0, "max_x": 5.0, "min_z": -2.0, "max_z": 2.0, "bottom": 0.0, "top": 1.0}
	_check(AimAssist.line_of_sight(eye, target, [low]), "a waist-high crate does not block eye to chest")
	var aside: Dictionary = {"min_x": 4.0, "max_x": 5.0, "min_z": 3.0, "max_z": 4.0}
	_check(AimAssist.line_of_sight(eye, target, [aside]), "cover to one side does not block")
	var beyond: Dictionary = {"min_x": 12.0, "max_x": 13.0, "min_z": -2.0, "max_z": 2.0}
	_check(AimAssist.line_of_sight(eye, target, [beyond]), "a wall behind the target does not block")
	var slab: Dictionary = {"min_x": 4.0, "max_x": 6.0, "min_z": -2.0, "max_z": 2.0, "bottom": 2.4, "top": 3.0}
	_check(not AimAssist.line_of_sight(Vector3(0, 4.0, 0), Vector3(10, 0.9, 0), [slab]), "a raised deck blocks a shot down through it")
	_check(AimAssist.line_of_sight(eye, target, ["junk", 3]), "malformed solids are skipped, not trusted")

func _test_gating() -> void:
	_check(not AimAssist.enabled_for(STANDARD, "mouse"), "mouse look is never assisted")
	_check(not AimAssist.enabled_for(STANDARD, ""), "no assist before any look input")
	_check(AimAssist.enabled_for(STANDARD, "keyboard") and AimAssist.enabled_for(AimAssist.Level.LIGHT, "gamepad"), "keyboard and gamepad look are assisted")
	_check(not AimAssist.enabled_for(AimAssist.Level.OFF, "keyboard"), "the setting turns it off")
	_check(AimAssist.level_from(7) == AimAssist.Level.OFF and AimAssist.level_from("2") == AimAssist.Level.OFF, "unknown levels are off")
	var prefs: FragrSettings = FragrSettings.new("user://aim-assist-unused.cfg")
	_check(prefs.get_value("controls", "aim_assist") == 2, "standard is the default")
	prefs.set_value("controls", "aim_assist", 5)
	_check(prefs.get_value("controls", "aim_assist") == 2, "invalid stored levels fall back")
	# Look source follows look input only.
	InputDevice.reset()
	var w: InputEventKey = InputEventKey.new()
	w.physical_keycode = KEY_W
	w.pressed = true
	InputDevice.note(w)
	_check(InputDevice.look_source == "", "walking keys do not claim the look")
	var arrow: InputEventKey = InputEventKey.new()
	arrow.physical_keycode = KEY_LEFT
	arrow.pressed = true
	InputDevice.note(arrow)
	_check(InputDevice.look_source == "keyboard", "an arrow claims keyboard look")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.screen_relative = Vector2(1, 1)
	InputDevice.note(motion)
	_check(InputDevice.look_source == "keyboard", "a one count bump of the desk is not mouse look")
	motion.screen_relative = Vector2(12, 3)
	InputDevice.note(motion)
	_check(InputDevice.look_source == "mouse", "real mouse motion turns assist off")
	InputDevice.note(w)
	_check(InputDevice.look_source == "mouse", "WASD with the mouse stays unassisted")

func _test_keyboard_pull() -> void:
	var eye: Vector3 = Vector3(0, 1.6, 0)
	var target: Vector3 = _at(eye, 3.0, 15.0, 2.0)
	var picked: Dictionary = AimAssist.pick(eye, 0.0, 0.0, [target], [], STANDARD)
	var first: Vector2 = AimAssist.keyboard_step(0.0, 0.0, picked, STANDARD, 1.0 / 60.0)
	var yaw_share: float = first.x / float(picked["yaw_error"])
	var pitch_share: float = first.y / float(picked["pitch"])
	_check(yaw_share > 0.0 and yaw_share < 0.1, "yaw pull is gentle, not a snap: %.3f of the error in one frame" % yaw_share)
	_check(pitch_share > 0.05 and pitch_share < 0.2, "vertical autoaim eases pitch, %.3f of the error in one frame" % pitch_share)
	# Frame-rate independence: half a second at 30 and at 240 fps agree.
	var results: Array[Vector2] = []
	for fps: float in [30.0, 240.0]:
		var aim: Vector2 = Vector2.ZERO
		for _frame: int in range(int(fps * 0.5)):
			var now: Dictionary = AimAssist.pick(eye, aim.x, aim.y, [target], [], STANDARD)
			aim = AimAssist.keyboard_step(aim.x, aim.y, now, STANDARD, 1.0 / fps)
		results.append(aim)
	_check(results[0].distance_to(results[1]) < 0.005, "pull is frame-rate independent: %s vs %s" % [results[0], results[1]])
	# Vertical autoaim works outside the smaller yaw cone; yaw pull does not.
	var wide: Vector3 = _at(eye, 5.5, 30.0, 3.0)
	var outer: Dictionary = AimAssist.pick(eye, 0.0, 0.0, [wide], [], STANDARD)
	var step: Vector2 = AimAssist.keyboard_step(0.0, 0.0, outer, STANDARD, 0.1)
	_check(step.x == 0.0 and step.y > 0.0, "Doom-style: pitch follows a hostile near the horizontal line, yaw is left to the player")

func _test_pad() -> void:
	var eye: Vector3 = Vector3(0, 1.6, 0)
	var picked: Dictionary = AimAssist.pick(eye, 0.0, 0.0, [_at(eye, 2.0, 15.0, -0.7)], [], STANDARD)
	_check(is_equal_approx(AimAssist.friction(picked, STANDARD), 0.5), "stick slows to half near a hostile")
	_check(is_equal_approx(AimAssist.friction(picked, AimAssist.Level.LIGHT), 0.7), "light slows less")
	_check(AimAssist.friction({}, STANDARD) == 1.0, "no hostile, no slowdown")
	var idle: Vector2 = AimAssist.pad_step(0.0, 0.0, picked, STANDARD, false, 0.1)
	_check(idle == Vector2.ZERO, "no pull while the player is not steering")
	var pulled: Vector2 = AimAssist.pad_step(0.0, 0.0, picked, STANDARD, true, 1.0 / 60.0)
	_check(pulled.x > 0.0 and pulled.x < float(picked["yaw_error"]) * 0.05, "pad pull is mild")

func _camera() -> Node3D:
	var owner_node: OpenOwner = OpenOwner.new()
	var cam: Node3D = CamScript.new()
	owner_node.add_child(cam)
	root.add_child(owner_node)
	cam.set_process(false)
	cam.fp_mode = true
	return cam

func _test_camera_mouse_untouched() -> void:
	var cam: Node3D = _camera()
	var eye: Vector3 = cam.global_position
	cam.assist_targets = [_at(eye, 3.0, 12.0, 1.5)]
	InputDevice.force(InputDevice.Kind.MOUSE, "mouse")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.screen_relative = Vector2(7, -4)
	cam.accept_mouse_motion(motion, true)
	cam._process_fp(1.0 / 60.0)
	var turn: float = deg_to_rad(0.022 * 1.5)
	_check(is_equal_approx(cam.fp_yaw, 7 * turn) and is_equal_approx(cam.fp_pitch, 4 * turn), "mouse counts land exactly with a hostile in the cone")
	for _frame: int in range(120):
		cam._process_fp(1.0 / 60.0)
	_check(is_equal_approx(cam.fp_yaw, 7 * turn) and is_equal_approx(cam.fp_pitch, 4 * turn), "two seconds later a mouse player's aim has not moved")
	_check(cam.assist_pick.is_empty(), "the assist never picks for mouse look")
	cam.get_parent().free()

func _test_camera_keyboard_and_levels() -> void:
	var cam: Node3D = _camera()
	var eye: Vector3 = cam.global_position
	var target: Vector3 = _at(eye, 2.5, 12.0, 1.5)
	cam.assist_targets = [target]
	InputDevice.force(InputDevice.Kind.KEYBOARD, "keyboard")
	for _frame: int in range(60):
		cam._process_fp(1.0 / 60.0)
	var wanted: Vector2 = AimAssist.aim_at(eye, target)
	_check(absf(cam.fp_pitch - wanted.y) < 0.02, "keyboard pitch settles on the hostile within a second")
	_check(absf(AimAssist.angle_to(cam.fp_yaw, wanted.x)) < deg_to_rad(1.0), "keyboard yaw drifts onto a hostile in the small cone")
	cam.fp_yaw = 0.0
	cam.fp_pitch = 0.0
	cam.aim_assist = AimAssist.Level.OFF
	for _frame: int in range(60):
		cam._process_fp(1.0 / 60.0)
	_check(cam.fp_yaw == 0.0 and cam.fp_pitch == 0.0, "off leaves keyboard aim alone")
	cam.aim_assist = STANDARD
	cam.assist_solids = [{"min_x": 5.0, "max_x": 6.0, "min_z": -3.0, "max_z": 3.0, "bottom": 0.0, "top": 4.5}]
	for _frame: int in range(60):
		cam._process_fp(1.0 / 60.0)
	_check(cam.fp_yaw == 0.0 and cam.fp_pitch == 0.0, "a hostile behind a wall gets no help")
	cam.get_parent().free()
