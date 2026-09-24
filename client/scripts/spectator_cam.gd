extends Node3D

@export var move_speed = 10.0
## Mouse look in the units every other shooter uses: degrees of turn per mouse
## count at sensitivity 1.0. 0.022 is the Source convention, so a player can
## paste a sensitivity number from another game and get the same hand movement.
## At 800 counts per inch, sensitivity 1.5 is 34.7 cm per 360 degrees, inside
## the band competitive players actually use. The old 0.003 radians per count
## was 6.6 cm per 360, about six times faster than a Counter-Strike default.
const DEGREES_PER_COUNT := 0.022
@export var mouse_sensitivity := 1.5
var invert_y: bool = false
## Radians per second of keyboard turn once the short ramp in look_input.gd
## is done. 2.8 is about a hundred and sixty degrees a second, a little faster
## than Doom's walking turn.
@export var stick_look_sensitivity = 2.8
## Gamepad look, radians per second at full deflection, after a radial
## deadzone and a response curve (look_input.gd).
var stick_yaw_rate: float = deg_to_rad(240.0)
var stick_pitch_rate: float = deg_to_rad(150.0)
@export var stick_deadzone = 0.12
var stick_curve: float = 1.8
var stick_accel: bool = true
var auto_centre: bool = false
var aim_assist: AimAssist.Level = AimAssist.Level.STANDARD
## Hostile body centres and map solids, refreshed by the match each frame.
var assist_targets: Array = []
var assist_solids: Array = []
## What the assist chose last frame, for the harnesses.
var assist_pick: Dictionary = {}
## Reads a stick: `true` for the right (look) stick. Harnesses replace it.
var stick_source: Callable = LookInput.read_stick
var _key_yaw_held: float = 0.0
var _key_yaw_dir: int = 0
var _key_pitch_held: float = 0.0
var _key_pitch_dir: int = 0
var _since_pitch_key: float = 0.0
var _centring: bool = false
var _centre_was_down: bool = false
var _stick_edge_seconds: float = 0.0
@export var auto_cycle_interval = 0.0

var follow_mode = true
var spectator_first_person: bool = true
var _observed_pawn: Node3D = null
var follow_target_index = 0
var available_targets = []
var _all_targets: Array = []
var auto_cycle_timer = 0.0
var frag_follow_timer = 0.0
var frag_follow_target_id = ""
## Developer watch mode follows one admitted participant through roster changes.
var pinned_player_id: String = ""
# tip_capture: freeze follow / frag yank while posing at dish origin.
# Held transform is re-applied every frame so set_fp_mode / other yanks cannot stick.
var tip_pose_lock = false
var tip_locked_transform: Transform3D = Transform3D.IDENTITY
var tip_has_locked_transform = false
var camera_shake_intensity = 0.0
var camera_zoom_offset = 0.0

var mouse_motion = Vector2.ZERO

# First-person join: local aim is sent through the shared action channel.
var fp_mode = false
var fp_target: Node3D = null
var fp_pitch = 0.0
## First-person facing the client owns. Mouse and stick move it on the frame
## the input arrives; the server is told the absolute value and agrees. Turn
## bits stay for agents and for anything that does not send a yaw.
var fp_yaw = 0.0
var turn_accum = 0.0
## Eye height above the fighter's feet.
const FP_EYE_ABOVE_FEET = MoveStep.EYE_HEIGHT
## The server's y for a standing fighter. Its position is a reference point,
## not the floor, so the eye offset from it is the difference of the two. When
## the fighters were put back on the floor this was missed, and the camera sat
## at three metres looking down on a world built for one and a half.
const FP_SERVER_REFERENCE_Y = 1.5
const FP_EYE_HEIGHT = FP_EYE_ABOVE_FEET - FP_SERVER_REFERENCE_Y
const TURN_ACCUM_THRESHOLD = 2.5

func apply_preferences(preferences: FragrSettings) -> void:
	mouse_sensitivity = float(preferences.get_value("controls", "mouse_sensitivity"))
	stick_look_sensitivity = float(preferences.get_value("controls", "turn_speed"))
	invert_y = bool(preferences.get_value("controls", "invert_y"))
	stick_yaw_rate = deg_to_rad(float(preferences.get_value("controls", "stick_yaw_speed")))
	stick_pitch_rate = deg_to_rad(float(preferences.get_value("controls", "stick_pitch_speed")))
	stick_deadzone = float(preferences.get_value("controls", "stick_deadzone"))
	stick_curve = float(preferences.get_value("controls", "stick_curve"))
	stick_accel = bool(preferences.get_value("controls", "stick_accel"))
	auto_centre = bool(preferences.get_value("controls", "auto_centre"))
	aim_assist = AimAssist.level_from(preferences.get_value("controls", "aim_assist"))
	var lens: Camera3D = get_node("Camera3D")
	lens.keep_aspect = Camera3D.KEEP_HEIGHT
	lens.fov = preferences.fov()

func _controls_blocked() -> bool:
	var owner_node: Node = get_parent()
	return owner_node != null and owner_node.has_method("controls_blocked") and bool(owner_node.controls_blocked())

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		accept_mouse_motion(event as InputEventMouseMotion, Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)

## Keep the display-server state at the input boundary; headless has no capture.
func accept_mouse_motion(event: InputEventMouseMotion, captured: bool) -> void:
	if captured and not _controls_blocked():
		mouse_motion += event.screen_relative

	# Escape belongs to the pause menu now. The mouse is released and recaptured
	# by whatever opens over the match, so two things no longer fight for it.

func _process(delta):
	camera_shake_intensity = lerp(camera_shake_intensity, 0.0, delta * 10.0)
	camera_zoom_offset = lerp(camera_zoom_offset, 0.0, delta * 5.0)
	if _controls_blocked():
		mouse_motion = Vector2.ZERO
		# A chat draft blocks input, but the watched fight keeps moving.
		if not fp_mode and follow_mode and not tip_pose_lock:
			_follow_target()
		return

	if tip_pose_lock:
		mouse_motion = Vector2.ZERO
		if tip_has_locked_transform:
			global_transform = tip_locked_transform
		return

	var mouse_captured = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	var pad_active = _gamepad_look_active() or _gamepad_move_active()

	if not mouse_captured:
		mouse_motion = Vector2.ZERO

	if fp_mode:
		_process_fp(delta)
		return

	var can_control: bool = pinned_player_id.is_empty() and (mouse_captured or pad_active)
	if can_control and Input.is_action_just_pressed("cycle_cam"):
		cycle_next_target()
		if not follow_mode:
			follow_mode = true
			print("Follow cam ON (F / pad cycles targets)")

	if can_control and Input.is_action_just_pressed("toggle_follow"):
		toggle_follow_mode()

	if frag_follow_timer > 0:
		frag_follow_timer -= delta
		if frag_follow_timer <= 0:
			frag_follow_target_id = ""
		else:
			_follow_frag_target()
			return

	if follow_mode and len(available_targets) > 0:
		auto_cycle_timer += delta
		if auto_cycle_interval > 0.0 and auto_cycle_timer >= auto_cycle_interval:
			cycle_next_target()
			auto_cycle_timer = 0.0
		_follow_target()
	else:
		_set_observed_pawn(null)
		if can_control:
			_free_fly(delta)

func _gamepad_move_active() -> bool:
	return LookInput.radial(_stick(false), maxf(stick_deadzone, LookInput.MOVE_MIN_DEADZONE)) != Vector2.ZERO

func _gamepad_look_active() -> bool:
	return LookInput.radial(_stick(true), stick_deadzone) != Vector2.ZERO

## Left stick as the four direction bits the wire carries.
func pad_move_bits() -> Dictionary:
	return LookInput.move_bits(_stick(false), stick_deadzone)

func _stick(right: bool) -> Vector2:
	var value: Variant = stick_source.call(right)
	return value if value is Vector2 and (value as Vector2).is_finite() else Vector2.ZERO

## Keyboard and gamepad look for one frame, as a (yaw, pitch) change in the
## server's convention: positive yaw turns right, positive pitch looks up.
## Keys ramp from a slow start so taps are fine adjustments; the stick goes
## through a radial deadzone, a response curve and optional acceleration.
## `friction` slows the stick near a hostile when aim assist allows it.
func _look_delta(delta: float, friction: float = 1.0) -> Vector2:
	var change: Vector2 = Vector2.ZERO
	var strafing: bool = InputMap.has_action("strafe") and Input.is_action_pressed("strafe")
	var yaw_dir: int = 0
	if not strafing:
		yaw_dir = int(Input.is_action_pressed("turn_right")) - int(Input.is_action_pressed("turn_left"))
	if yaw_dir != _key_yaw_dir:
		_key_yaw_held = 0.0
		_key_yaw_dir = yaw_dir
	if yaw_dir != 0:
		change.x += yaw_dir * LookInput.key_turn_angle(_key_yaw_held, _key_yaw_held + delta, stick_look_sensitivity)
		_key_yaw_held += delta
	var pitch_dir: int = int(Input.is_action_pressed("look_up")) - int(Input.is_action_pressed("look_down"))
	if pitch_dir != _key_pitch_dir:
		_key_pitch_held = 0.0
		_key_pitch_dir = pitch_dir
	if pitch_dir != 0:
		change.y += pitch_dir * LookInput.key_turn_angle(_key_pitch_held, _key_pitch_held + delta, stick_look_sensitivity * LookInput.KEY_PITCH_SCALE)
		_key_pitch_held += delta
		_since_pitch_key = 0.0
		_centring = false
	else:
		_since_pitch_key += delta
	var shaped: Vector2 = LookInput.shape(_stick(true), stick_deadzone, stick_curve)
	if absf(shaped.x) >= LookInput.ACCEL_EDGE:
		_stick_edge_seconds += delta
	else:
		_stick_edge_seconds = 0.0
	var boost: float = LookInput.accel_multiplier(_stick_edge_seconds, stick_accel)
	change += LookInput.stick_look(shaped, stick_yaw_rate, stick_pitch_rate, invert_y, boost, delta) * friction
	if shaped != Vector2.ZERO:
		_since_pitch_key = 0.0
	return change

func _apply_stick_look(delta: float, apply_yaw_to_node: bool) -> void:
	var change: Vector2 = _look_delta(delta)
	if apply_yaw_to_node:
		rotation.y -= change.x
		rotation.x = clampf(rotation.x + change.y, -PI / 2, PI / 2)
	else:
		fp_yaw = wrapf(fp_yaw + change.x, 0.0, TAU)
		fp_pitch = clampf(fp_pitch + change.y, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT)

func _free_fly(delta):
	if mouse_motion.length() > 0:
		var radians_per_count := _radians_per_count()
		rotation.y -= mouse_motion.x * radians_per_count
		rotation.x -= mouse_motion.y * radians_per_count * (-1.0 if invert_y else 1.0)
		rotation.x = clamp(rotation.x, -PI / 2, PI / 2)
		mouse_motion = Vector2.ZERO

	_apply_stick_look(delta, true)

	var input_dir = Vector3.ZERO
	input_dir.z -= Input.get_action_strength("move_forward")
	input_dir.z += Input.get_action_strength("move_back")
	input_dir.x -= Input.get_action_strength("move_left")
	input_dir.x += Input.get_action_strength("move_right")
	var pad_move: Vector2 = LookInput.radial(_stick(false), maxf(stick_deadzone, LookInput.MOVE_MIN_DEADZONE))
	input_dir.x += pad_move.x
	input_dir.z += pad_move.y

	var speed_mult = 1.0
	if Input.is_key_pressed(KEY_SHIFT):
		speed_mult = 3.0

	if input_dir.length() > 0.01:
		input_dir = input_dir.normalized()
		var move_vec = transform.basis * input_dir
		position += move_vec * move_speed * speed_mult * delta

func _follow_target():
	if len(available_targets) == 0:
		_set_observed_pawn(null)
		return

	follow_target_index = follow_target_index % len(available_targets)
	var target = available_targets[follow_target_index]

	if is_instance_valid(target):
		if spectator_first_person:
			_set_observed_pawn(target)
			var yaw: float = _target_server_yaw(target)
			global_position = target.global_position + Vector3(0, FP_EYE_HEIGHT, 0)
			rotation = Vector3(_target_server_pitch(target), ServerYaw.camera_rotation_y(yaw), 0.0)
			mouse_motion = Vector2.ZERO
			return
		_set_observed_pawn(null)
		var target_pos = target.global_position
		var offset = Vector3(0, 5.5, 10.5 + camera_zoom_offset)

		if camera_shake_intensity > 0:
			offset += Vector3(
				randf_range(-camera_shake_intensity, camera_shake_intensity),
				randf_range(-camera_shake_intensity, camera_shake_intensity),
				0
			)

		var cam_pos = target_pos + offset.rotated(Vector3.UP, target.rotation.y)
		position = position.lerp(cam_pos, 0.1)

		var look_target = target_pos + Vector3(0, 1.5, 0)
		var desired_transform = global_transform.looking_at(look_target, Vector3.UP)
		global_transform = global_transform.interpolate_with(desired_transform, 0.15)
	else:
		cycle_next_target()

func toggle_follow_mode():
	if not pinned_player_id.is_empty():
		return
	# V cycles eye, chase, free. F changes the fighter without changing the view.
	if follow_mode and spectator_first_person:
		spectator_first_person = false
	elif follow_mode:
		follow_mode = false
	else:
		follow_mode = true
		spectator_first_person = true
	_set_observed_pawn(null)
	frag_follow_timer = 0.0
	auto_cycle_timer = 0.0

func cycle_next_target():
	if not pinned_player_id.is_empty():
		return
	if len(available_targets) > 0:
		follow_target_index = (follow_target_index + 1) % len(available_targets)
		auto_cycle_timer = 0.0
		camera_shake_intensity = 0.12
		camera_zoom_offset = -0.6

func pin_player(player_id: String) -> void:
	pinned_player_id = player_id.strip_edges()
	if not pinned_player_id.is_empty():
		set_fp_mode(false)
		follow_mode = true
		spectator_first_person = true
		frag_follow_timer = 0.0
		frag_follow_target_id = ""
	set_available_targets(_all_targets)

func set_available_targets(targets: Array):
	var previous: Node3D = get_followed_target()
	# Drop freed pawns so follow cam / highlight never soft-prison on a dead instance.
	_all_targets = []
	available_targets = []
	for t in targets:
		if not is_instance_valid(t):
			continue
		_all_targets.append(t)
		if pinned_player_id.is_empty() or str(t.get("player_id")) == pinned_player_id:
			available_targets.append(t)
	if follow_mode and len(available_targets) > 0:
		var previous_index: int = available_targets.find(previous)
		follow_target_index = previous_index if previous_index >= 0 else follow_target_index % len(available_targets)
	else:
		follow_target_index = 0
		_set_observed_pawn(null)

func camera_punch():
	camera_shake_intensity = 0.3
	camera_zoom_offset = -1.5

func get_followed_target():
	if fp_mode and is_instance_valid(fp_target):
		return fp_target
	if follow_mode and len(available_targets) > 0:
		var idx = follow_target_index % len(available_targets)
		var target = available_targets[idx]
		if is_instance_valid(target):
			return target
	return null

func lock_on_frag(killer_id: String, duration: float = 1.5):
	if tip_pose_lock or not pinned_player_id.is_empty():
		return
	if fp_mode or spectator_first_person:
		return
	frag_follow_target_id = killer_id
	frag_follow_timer = duration
	auto_cycle_timer = 0.0

func _follow_frag_target():
	if frag_follow_target_id == "":
		return

	for target in available_targets:
		if is_instance_valid(target) and target.player_id == frag_follow_target_id:
			var target_pos = target.global_position
			var offset = Vector3(0, 5.5, 10.5)
			var cam_pos = target_pos + offset.rotated(Vector3.UP, target.rotation.y)
			position = position.lerp(cam_pos, 0.15)

			var look_target = target_pos + Vector3(0, 1.5, 0)
			var desired_transform = global_transform.looking_at(look_target, Vector3.UP)
			global_transform = global_transform.interpolate_with(desired_transform, 0.2)
			return

func _process_fp(delta):
	# Local angles are sent as absolute authoritative aim in the next action.
	if mouse_motion.length() > 0:
		var radians_per_count := _radians_per_count()
		fp_yaw = wrapf(fp_yaw + mouse_motion.x * radians_per_count, 0.0, TAU)
		fp_pitch -= mouse_motion.y * radians_per_count * (-1.0 if invert_y else 1.0)
		fp_pitch = clampf(fp_pitch, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT)
		mouse_motion = Vector2.ZERO

	# Keys and the right stick change the same local aim sent through Action.
	# Aim assist reads the look source: the mouse is never assisted.
	var assisted: bool = AimAssist.enabled_for(aim_assist, InputDevice.look_source)
	assist_pick = AimAssist.pick(_assist_eye(), fp_yaw, fp_pitch, assist_targets, assist_solids, aim_assist) if assisted else {}
	var pad_look: bool = InputDevice.look_source == "gamepad"
	var change: Vector2 = _look_delta(delta, AimAssist.friction(assist_pick, aim_assist) if pad_look else 1.0)
	fp_yaw = wrapf(fp_yaw + change.x, 0.0, TAU)
	fp_pitch = clampf(fp_pitch + change.y, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT)
	var centre_down: bool = InputMap.has_action("center_view") and Input.is_action_pressed("center_view")
	if centre_down and not _centre_was_down:
		_centring = true
	_centre_was_down = centre_down
	if _centring:
		fp_pitch = fp_pitch * exp(-12.0 * delta)
		if absf(fp_pitch) < 0.002:
			fp_pitch = 0.0
			_centring = false
	if assisted and not assist_pick.is_empty():
		var aim: Vector2
		if pad_look:
			var steering: bool = change != Vector2.ZERO or _gamepad_move_active()
			aim = AimAssist.pad_step(fp_yaw, fp_pitch, assist_pick, aim_assist, steering, delta)
		else:
			aim = AimAssist.keyboard_step(fp_yaw, fp_pitch, assist_pick, aim_assist, delta)
		fp_yaw = aim.x
		fp_pitch = aim.y
	elif auto_centre and InputDevice.look_source == "keyboard" and _since_pitch_key >= LookInput.AUTO_CENTRE_DELAY \
		and (Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_back")):
		fp_pitch = LookInput.auto_centre(fp_pitch, delta)

	if not is_instance_valid(fp_target):
		return

	var eye = fp_target.global_position + Vector3(0, FP_EYE_HEIGHT, 0)
	# The eye looks where the client aims, not where the last snapshot said.
	var yaw = fp_yaw

	if camera_shake_intensity > 0:
		eye += Vector3(
			randf_range(-camera_shake_intensity, camera_shake_intensity) * 0.35,
			randf_range(-camera_shake_intensity, camera_shake_intensity) * 0.25,
			0
		)

	position = position.lerp(eye, min(1.0, 18.0 * delta))
	# The server's yaw is not a Godot rotation. Assigning it straight to
	# rotation.y pointed the camera ninety degrees away from where the server
	# was moving the fighter, which is why holding forward read as strafing.
	rotation.y = ServerYaw.camera_rotation_y(yaw)
	rotation.x = fp_pitch

## Where the assist measures from: the fighter's authoritative eye.
func _assist_eye() -> Vector3:
	if not is_instance_valid(fp_target):
		return global_position
	var base: Vector3 = fp_target.global_position
	if "target_position" in fp_target:
		base = fp_target.get("target_position")
	return base + Vector3(0, FP_EYE_HEIGHT, 0)

## Radians of turn per mouse count at the current sensitivity.
func _radians_per_count() -> float:
	return deg_to_rad(DEGREES_PER_COUNT * mouse_sensitivity)


## Centimetres of mouse travel for a full turn, the number players compare.
## Pure arithmetic, so the harness can assert it without a mouse.
static func cm_per_360(sensitivity: float, counts_per_inch: float) -> float:
	var degrees_per_count := DEGREES_PER_COUNT * sensitivity
	if degrees_per_count <= 0.0 or counts_per_inch <= 0.0:
		return 0.0
	return (360.0 / (degrees_per_count * counts_per_inch)) * 2.54


## The absolute facing to send with this input, in the server's convention.
func consume_yaw() -> float:
	return wrapf(fp_yaw, 0.0, TAU)

func consume_pitch() -> float:
	return clampf(fp_pitch, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT)


func consume_turn_bits() -> Dictionary:
	# Discrete turn for Action. Called each tick while human; clears accum.
	var left = false
	var right = false
	if turn_accum <= -TURN_ACCUM_THRESHOLD:
		left = true
		turn_accum = 0.0
	elif turn_accum >= TURN_ACCUM_THRESHOLD:
		right = true
		turn_accum = 0.0
	return {"turn_left": left, "turn_right": right}

func set_fp_mode(enabled: bool, target: Node3D = null) -> void:
	if enabled and not pinned_player_id.is_empty():
		return
	# tip_capture pose lock: never teleport onto a soldier mid-jammer still.
	if tip_pose_lock:
		return
	# Snapshot refresh must not overwrite the local aim on every network tick.
	if fp_mode == enabled and fp_target == target:
		return
	_set_observed_pawn(null)
	fp_mode = enabled
	fp_target = target
	if not enabled:
		fp_pitch = 0.0
		turn_accum = 0.0
		fp_yaw = 0.0
		fp_target = null
	elif is_instance_valid(target):
		# Snap once so join does not tween from spectator orbit, and adopt the
		# fighter's facing so the first mouse move continues from it.
		var yaw: float = _target_server_yaw(target)
		fp_yaw = wrapf(yaw, 0.0, TAU)
		fp_pitch = _target_server_pitch(target)
		position = target.global_position + Vector3(0, FP_EYE_HEIGHT, 0)
		rotation.y = ServerYaw.camera_rotation_y(yaw)
		rotation.x = fp_pitch

static func _target_server_yaw(target: Node3D) -> float:
	return float(target.get("target_yaw")) if "target_yaw" in target else -target.rotation.y

static func _target_server_pitch(target: Node3D) -> float:
	return clampf(float(target.get("target_pitch")), -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT) if "target_pitch" in target else 0.0

func is_observing_first_person() -> bool:
	return not fp_mode and follow_mode and spectator_first_person and is_instance_valid(get_followed_target())

func _set_observed_pawn(target: Node3D) -> void:
	if _observed_pawn == target:
		return
	if is_instance_valid(_observed_pawn) and _observed_pawn.has_method("set_local_fp"):
		_observed_pawn.set_local_fp(false)
	_observed_pawn = target
	if is_instance_valid(_observed_pawn) and _observed_pawn.has_method("set_local_fp"):
		_observed_pawn.set_local_fp(true)


## tip_capture: latch free-fly pose at dish and re-assert every frame.
func latch_tip_pose(xform: Transform3D) -> void:
	_set_observed_pawn(null)
	tip_pose_lock = true
	tip_locked_transform = xform
	tip_has_locked_transform = true
	follow_mode = false
	frag_follow_timer = 0.0
	frag_follow_target_id = ""
	fp_mode = false
	fp_target = null
	global_transform = xform


func capture_tip_pose_from_current() -> void:
	latch_tip_pose(global_transform)


func clear_tip_pose_lock() -> void:
	tip_pose_lock = false
	tip_has_locked_transform = false
