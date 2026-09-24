extends SceneTree

## Keyboard-only play, classic Doom style: turn on the arrows with a short
## ramp so taps are fine adjustments, look on Page Up and Page Down, strafe
## with Alt, fire on Ctrl and use on Enter with one hand on the arrows. The
## keys reach the same discrete actions and the same wire as every device.

const CamScript := preload("res://scripts/spectator_cam.gd")

class CaptureNetwork extends Node:
	var connection_state: int = WebSocketPeer.STATE_OPEN
	var player_id: String = "self"
	var mission: Dictionary = {}
	var sent: Array[Dictionary] = []
	func send_action(action: Dictionary) -> void:
		sent.append(action.duplicate())

class OpenOwner extends Node:
	func controls_blocked() -> bool:
		return false

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_keyboard_only: " + message)

func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event

func _press(code: Key) -> void:
	Input.parse_input_event(_key(code, true))
	Input.flush_buffered_events()

func _release(code: Key) -> void:
	Input.parse_input_event(_key(code, false))
	Input.flush_buffered_events()

func _run() -> void:
	FragrSettings.new("user://keyboard-only-unused.cfg").apply_controls()
	InputDevice.reset()
	_test_default_bindings()
	_test_turn_ramp_and_frame_independence()
	_test_camera_keys()
	_test_wire_actions()
	InputDevice.reset()
	if _failures == 0:
		print("test_keyboard_only: PASS turning, look, strafe, fire, use and weapon keys")
	quit(0 if _failures == 0 else 1)

## One hand on the arrows reaches Ctrl, Enter, Alt, Page Up and Down and End;
## the other can stay on WASD. None of these defaults collide in play.
func _test_default_bindings() -> void:
	var expected: Dictionary = {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_COMMA], "move_right": [KEY_D, KEY_PERIOD],
		"turn_left": [KEY_LEFT, KEY_Q], "turn_right": [KEY_RIGHT, KEY_E],
		"look_up": [KEY_PAGEUP], "look_down": [KEY_PAGEDOWN], "center_view": [KEY_END],
		"strafe": [KEY_ALT], "fire": [KEY_CTRL], "interact": [KEY_F, KEY_ENTER],
		"jump": [KEY_SPACE], "weapon_1": [KEY_1], "weapon_5": [KEY_5],
		"weapon_next": [KEY_BRACKETRIGHT], "weapon_prev": [KEY_BRACKETLEFT], "pause": [KEY_ESCAPE],
	}
	for action: String in expected:
		for code: Key in expected[action]:
			_check(_key(code).is_action_pressed(action), "%s should be bound to %s" % [OS.get_keycode_string(code), action])
	var right_ctrl: InputEventKey = _key(KEY_CTRL)
	right_ctrl.location = KEY_LOCATION_RIGHT
	_check(right_ctrl.is_action_pressed("fire"), "right Ctrl fires beside the arrows")
	_check(InputBindings.conflicts(FragrSettings.new("user://keyboard-only-unused.cfg")).is_empty(), "default bindings have no conflicts")

func _test_turn_ramp_and_frame_independence() -> void:
	var rate: float = 2.8
	var tap: float = LookInput.key_turn_angle(0.0, 1.0 / 144.0, rate)
	_check(rad_to_deg(tap) < 0.25, "a one frame tap at 144 Hz is a fine nudge, got %.3f degrees" % rad_to_deg(tap))
	# A deliberate human tap is about 80 ms whatever the frame rate. Doom's slow
	# first tics made that about five degrees; this is a little finer.
	var short: float = LookInput.key_turn_angle(0.0, 0.08, rate)
	_check(rad_to_deg(short) > 2.0 and rad_to_deg(short) < 5.0, "an 80 ms tap turns a few degrees, got %.2f" % rad_to_deg(short))
	var late: float = LookInput.key_turn_angle(1.0, 1.5, rate)
	_check(is_equal_approx(late, rate * 0.5), "after the ramp a held key turns at the full rate")
	for fps: float in [30.0, 60.0, 144.0, 240.0, 500.0]:
		var total: float = 0.0
		var held: float = 0.0
		var frames: int = int(round(fps))
		for _frame: int in range(frames):
			total += LookInput.key_turn_angle(held, held + 1.0 / fps, rate)
			held += 1.0 / fps
		_check(absf(total - LookInput.key_turn_angle(0.0, 1.0, rate)) < 1e-4, "one second of turning is the same at %d fps" % int(fps))

func _test_camera_keys() -> void:
	var owner_node: OpenOwner = OpenOwner.new()
	var cam: Node3D = CamScript.new()
	owner_node.add_child(cam)
	root.add_child(owner_node)
	cam.set_process(false)
	cam.fp_mode = true
	var start: float = cam.fp_yaw
	_press(KEY_RIGHT)
	cam._process_fp(1.0 / 144.0)
	_release(KEY_RIGHT)
	cam._process_fp(1.0 / 144.0)
	var nudge: float = wrapf(cam.fp_yaw - start, -PI, PI)
	_check(nudge > 0.0 and rad_to_deg(nudge) < 0.25, "a right arrow tap turns right by a fraction of a degree, got %.3f" % rad_to_deg(nudge))
	start = cam.fp_yaw
	_press(KEY_LEFT)
	for _frame: int in range(60):
		cam._process_fp(1.0 / 60.0)
	_release(KEY_LEFT)
	var turned: float = wrapf(start - cam.fp_yaw, -PI, PI)
	_check(absf(turned - LookInput.key_turn_angle(0.0, 1.0, 2.8)) < 0.01, "a one second left hold turns the ramped amount, got %.3f" % turned)
	_press(KEY_PAGEUP)
	for _frame: int in range(30):
		cam._process_fp(1.0 / 60.0)
	_release(KEY_PAGEUP)
	_check(cam.fp_pitch > 0.2, "Page Up looks up")
	_press(KEY_END)
	for _frame: int in range(90):
		cam._process_fp(1.0 / 60.0)
	_release(KEY_END)
	_check(is_zero_approx(cam.fp_pitch), "End centres the view, pitch %.4f" % cam.fp_pitch)
	# Strafe modifier: Alt with an arrow moves sideways and does not turn.
	start = cam.fp_yaw
	_press(KEY_ALT)
	_press(KEY_LEFT)
	for _frame: int in range(20):
		cam._process_fp(1.0 / 60.0)
	_release(KEY_LEFT)
	_release(KEY_ALT)
	_check(is_equal_approx(cam.fp_yaw, start), "Alt plus an arrow strafes instead of turning")
	# Optional auto-centre while walking with the keyboard.
	cam.auto_centre = true
	cam.fp_pitch = 0.4
	InputDevice.force(InputDevice.Kind.KEYBOARD, "keyboard")
	_press(KEY_UP)
	for _frame: int in range(120):
		cam._process_fp(1.0 / 60.0)
	_release(KEY_UP)
	_check(absf(cam.fp_pitch) < 0.05, "auto-centre levels pitch while walking, pitch %.3f" % cam.fp_pitch)
	cam.auto_centre = false
	cam.fp_pitch = 0.4
	_press(KEY_UP)
	for _frame: int in range(120):
		cam._process_fp(1.0 / 60.0)
	_release(KEY_UP)
	_check(is_equal_approx(cam.fp_pitch, 0.4), "auto-centre is off by default and leaves pitch alone")
	owner_node.free()

## The keys become the same Action the server has always read.
func _test_wire_actions() -> void:
	var manager: Node = load("res://scripts/game_manager.gd").new()
	var network: CaptureNetwork = CaptureNetwork.new()
	manager.set("net_client", network)
	manager.set("is_human_player", true)
	var clock: Array[int] = [1000000]
	var send: Callable = func() -> Dictionary:
		clock[0] += 20000
		manager.call("_send_local_action", clock[0])
		return network.sent.back() if not network.sent.is_empty() else {}
	_press(KEY_UP)
	_press(KEY_CTRL)
	var action: Dictionary = send.call()
	_check(action.get("forward") == true and action.get("fire") == true, "Up arrow walks and Ctrl fires: " + str(action))
	_release(KEY_CTRL)
	_release(KEY_UP)
	_press(KEY_ALT)
	_press(KEY_RIGHT)
	action = send.call()
	_check(action.get("right") == true and action.get("left") == false and action.get("turn_right") == false, "Alt plus Right strafes right on the wire: " + str(action))
	_release(KEY_RIGHT)
	_release(KEY_ALT)
	_press(KEY_PERIOD)
	action = send.call()
	_check(action.get("right") == true, "Period strafes right")
	_release(KEY_PERIOD)
	var enter: InputEventKey = _key(KEY_ENTER)
	manager.call("_input", enter)
	manager.call("_input", _key(KEY_ENTER, false))
	action = send.call()
	_check(action.get("interact") == true, "Enter uses")
	action = send.call()
	_check(action.get("interact") == false, "a use tap is delivered once")
	manager.free()
	network.free()
