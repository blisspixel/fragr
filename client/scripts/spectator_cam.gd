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
var reduced_motion: bool = false

## Joined-player death view (#441). While set, the camera holds the dead
## eye or chases the killer and reads no movement, look or view keys, so held
## gameplay input cannot become free flight or a jump into another fighter.
var death_view: bool = false
var death_chase_id: String = ""

## The director. While a watcher lets the camera follow, it cuts to the
## fight that matters: an open multikill chain, a Rocket frag, a power pad
## about to return with somebody close to it, a spree at its mode's step.
## It reads the booth's facts and public frag events, never input, and only
## changes which fighter the follow camera rides. A bigger moment can cut
## into a smaller one's hold; nothing cuts into a bigger one. Changing the
## fighter or the view by hand rests it, so the watcher drives.
enum Cue { NONE, SPREE, POWER, ROCKET, MULTIKILL }
const DIRECTOR_REST_SECONDS: float = 15.0
const DIRECTOR_HOLD: Dictionary = {Cue.SPREE: 6.0, Cue.ROCKET: 4.0, Cue.MULTIKILL: 5.0}
## A power pad this close to returning is a fight about to happen over it.
const DIRECTOR_POWER_SECONDS: float = 3.0
## Only a fighter this near a returning pad is in that fight.
const DIRECTOR_POWER_RANGE: float = 28.0
var director_enabled: bool = true
## Why the last cut happened and who it went to, for the harnesses.
var director_reason: String = ""
var director_target_id: String = ""
var _director_hold: float = 0.0
var _director_cue: Cue = Cue.NONE
var _director_rest: float = 0.0
var _director_sprees: Dictionary = {}
var _director_chains: Dictionary = {}
var _director_pads: Dictionary = {}
## A director's cut is a cut: the chase camera's next frame stands at its
## new fighter instead of sweeping across the map to it.
var _director_snap: bool = false

var mouse_motion = Vector2.ZERO
## Sniper scope magnification from the HUD: 1.0 is the player's own view. Look
## turns slow by the same factor, so one mouse count covers the same picture.
var zoom_factor: float = 1.0
## The player's field of view, kept so the scope can return to it exactly.
var base_fov: float = 75.0
var _applied_zoom: float = 1.0

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

## Standing lift, or the crouch drop when the pawn is short. The viewmodel
## is a child of this camera, so it drops with the eye.
static func eye_lift(target: Object) -> float:
	if target != null and target.get("ducking") == true:
		return FP_EYE_HEIGHT - (MoveStep.EYE_HEIGHT - MoveStep.DUCK_EYE_HEIGHT)
	return FP_EYE_HEIGHT
const TURN_ACCUM_THRESHOLD = 2.5

## Camera punch: presentation only. A shot kicks the drawn view up (and rolls
## it a little) on a critically damped spring and the view settles back; aim,
## the yaw and pitch sent to the server, never moves, so the first shot and
## every later one go where the player aimed. Degrees of pitch at the peak and
## the roll as a share of it. Fast attack, ~25 ms to the peak, settled in about
## 0.2 s: Quake's damage kick and Doom Eternal's gun punch are this shape.
const PUNCH_OMEGA: float = 40.0
const PUNCH_DEGREES: Dictionary = {
	"Tack": 0.55, "Flechette": 0.4, "Repeater": 0.22, "Arc": 0.12,
	"Rail": 1.5, "Sniper": 2.0, "Scatter": 1.7, "Rocket": 1.3,
	"Article Blade": 0.6, "ArticleBlade": 0.6,
}
const PUNCH_ROLL_SHARE: float = 0.35
## Landing dip: the eye drops with the impact and comes back, Quake's
## 150 ms down and 300 ms up. Metres per metre-per-second of fall speed beyond
## a hop's own landing, capped.
const DIP_OMEGA: float = 9.0
const DIP_PER_SPEED: float = 0.012
const DIP_MAX: float = 0.12
const DIP_FREE_SPEED: float = 6.0
var _punch: Vector2 = Vector2.ZERO
var _punch_rate: Vector2 = Vector2.ZERO
var _punch_side: float = 1.0
var _dip: float = 0.0
var _dip_rate: float = 0.0
var _eye_y: float = NAN
var _eye_vy: float = 0.0

func apply_preferences(preferences: FragrSettings) -> void:
	reduced_motion = bool(preferences.get_value("accessibility", "reduced_motion"))
	if reduced_motion:
		camera_shake_intensity = 0.0
		camera_zoom_offset = 0.0
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
	base_fov = preferences.fov()
	lens.fov = base_fov * _applied_zoom

func _controls_blocked() -> bool:
	var owner_node: Node = get_parent()
	return owner_node != null and owner_node.has_method("controls_blocked") and bool(owner_node.controls_blocked())

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		accept_mouse_motion(event as InputEventMouseMotion, Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)

## Keep the display-server state at the input boundary; headless has no capture.
func accept_mouse_motion(event: InputEventMouseMotion, captured: bool) -> void:
	if not captured or _controls_blocked():
		return
	# First-person aim turns the moment the motion arrives. Input events are
	# handled before any node's process, so the Action this frame sends and the
	# frame this frame draws both carry it; waiting for the camera's own
	# process sent every flick one frame late. Raw counts, no smoothing and no
	# acceleration.
	if fp_mode:
		_turn_by_counts(event.screen_relative)
	else:
		mouse_motion += event.screen_relative


func _turn_by_counts(counts: Vector2) -> void:
	var radians_per_count := _radians_per_count()
	fp_yaw = wrapf(fp_yaw + counts.x * radians_per_count, 0.0, TAU)
	fp_pitch -= counts.y * radians_per_count * (-1.0 if invert_y else 1.0)
	fp_pitch = clampf(fp_pitch, -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT)

	# Escape belongs to the pause menu now. The mouse is released and recaptured
	# by whatever opens over the match, so two things no longer fight for it.

func _process(delta: float) -> void:
	camera_shake_intensity *= exp(-10.0 * maxf(delta, 0.0))
	camera_zoom_offset *= exp(-5.0 * maxf(delta, 0.0))
	_director_hold = maxf(0.0, _director_hold - delta)
	_director_rest = maxf(0.0, _director_rest - delta)
	if _director_hold <= 0.0:
		_director_cue = Cue.NONE
	if death_view and not tip_pose_lock:
		mouse_motion = Vector2.ZERO
		_process_death_view(delta)
		return
	if _controls_blocked():
		mouse_motion = Vector2.ZERO
		# A chat draft blocks input, but the watched fight keeps moving.
		if not fp_mode and follow_mode and not tip_pose_lock:
			_follow_target(delta)
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
	# Board browsing reuses play bindings, which may overlap spectator bindings.
	# Event consumption does not clear the global actions polled here.
	var browsing_board: bool = Input.is_action_pressed("scoreboard") and (
		Input.is_action_just_pressed("weapon_next") or Input.is_action_just_pressed("weapon_prev"))
	var can_switch_view: bool = can_control and not browsing_board
	if can_switch_view and Input.is_action_just_pressed("cycle_cam"):
		cycle_next_target()
		director_rest()
		if not follow_mode:
			follow_mode = true
			print("Follow cam ON (F / pad cycles targets)")

	if can_switch_view and Input.is_action_just_pressed("toggle_follow"):
		toggle_follow_mode()
		director_rest()

	if frag_follow_timer > 0:
		frag_follow_timer -= delta
		if frag_follow_timer <= 0:
			frag_follow_target_id = ""
		else:
			_follow_frag_target(delta)
			return

	if follow_mode and len(available_targets) > 0:
		auto_cycle_timer += delta
		if auto_cycle_interval > 0.0 and auto_cycle_timer >= auto_cycle_interval:
			cycle_next_target()
			auto_cycle_timer = 0.0
		_follow_target(delta)
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

func _follow_target(delta: float = 1.0 / 60.0) -> void:
	if len(available_targets) == 0:
		_set_observed_pawn(null)
		return

	follow_target_index = follow_target_index % len(available_targets)
	var target = available_targets[follow_target_index]

	if is_instance_valid(target):
		if spectator_first_person:
			_set_observed_pawn(target)
			var yaw: float = _target_presentation_yaw(target)
			global_position = target.global_position + Vector3(0, eye_lift(target), 0)
			rotation = Vector3(_target_presentation_pitch(target), ServerYaw.camera_rotation_y(yaw), 0.0)
			mouse_motion = Vector2.ZERO
			_director_snap = false
			return
		_set_observed_pawn(null)
		var target_pos = target.global_position
		var offset = Vector3(0, 5.5, 10.5 + camera_zoom_offset)

		if not reduced_motion and camera_shake_intensity > 0:
			offset += Vector3(
				randf_range(-camera_shake_intensity, camera_shake_intensity),
				randf_range(-camera_shake_intensity, camera_shake_intensity),
				0
			)

		var look_target = target_pos + Vector3(0, CHASE_LOOK_RISE, 0)
		# Cover between the fighter's body and the boom pulls the camera in,
		# so the view never shows a crate top with the followed fighter hidden
		# behind it. The pawn's origin is the server reference, 1.5 m above
		# its feet, so the body probe sits below it.
		var body: Vector3 = target_pos + Vector3(0, CHASE_BODY_PROBE, 0)
		var cam_pos: Vector3 = chase_clear_position(body, target_pos + offset.rotated(Vector3.UP, target.rotation.y), assist_solids)
		position = position.lerp(cam_pos, follow_weight(0.1, delta))
		if _director_snap or not AimAssist.line_of_sight(body, global_position, assist_solids):
			global_position = cam_pos
			if _director_snap and not global_position.is_equal_approx(look_target):
				look_at(look_target, Vector3.UP)
			_director_snap = false

		var desired_transform = global_transform.looking_at(look_target, Vector3.UP)
		global_transform = global_transform.interpolate_with(desired_transform, follow_weight(0.15, delta))
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
		if not reduced_motion:
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
	if reduced_motion:
		return
	camera_shake_intensity = 0.3
	camera_zoom_offset = -1.5

func get_followed_target():
	if death_view:
		return death_view_target()
	if fp_mode and is_instance_valid(fp_target):
		return fp_target
	if follow_mode and len(available_targets) > 0:
		var idx = follow_target_index % len(available_targets)
		var target = available_targets[idx]
		if is_instance_valid(target):
			return target
	return null

## The watcher took the camera: the director waits before cutting again.
func director_rest(seconds: float = DIRECTOR_REST_SECONDS) -> void:
	_director_rest = maxf(_director_rest, seconds)
	_director_hold = 0.0
	_director_cue = Cue.NONE

func director_can_cut() -> bool:
	return director_enabled and not fp_mode and not death_view and not tip_pose_lock \
		and pinned_player_id.is_empty() and follow_mode and _director_rest <= 0.0

## Cut the follow camera to a fighter for at least `hold` seconds. Refused
## while the watcher drives, while a cut of the same or a bigger cue holds,
## or when that fighter is not on the field.
func director_cut(player_id: String, cue: Cue, hold: float, reason: String) -> bool:
	if not director_can_cut() or player_id.is_empty():
		return false
	if _director_hold > 0.0 and cue <= _director_cue:
		return false
	var index: int = -1
	for i: int in range(available_targets.size()):
		var target: Variant = available_targets[i]
		if is_instance_valid(target) and str(target.get("player_id")) == player_id:
			index = i
			break
	if index < 0:
		return false
	follow_target_index = index
	auto_cycle_timer = 0.0
	frag_follow_timer = 0.0
	frag_follow_target_id = ""
	_director_hold = hold
	_director_cue = cue
	_director_snap = true
	director_reason = reason
	director_target_id = player_id
	return true

## Read the booth's facts: open multikill chains first, then a power pad
## about to return with a fighter near it, then a spree reaching a new frag
## at or past its mode's step. Each moment is cut to once.
func director_observe_facts(facts: Dictionary, pickups: Array) -> void:
	var chains: Dictionary = {}
	for chain: Dictionary in facts.get("chains", []):
		chains[chain["id"]] = int(chain["frags"])
	for id: Variant in _director_chains.keys():
		if not chains.has(id):
			_director_chains.erase(id)
	for chain: Dictionary in facts.get("chains", []):
		var frags: int = int(chain["frags"])
		if frags >= 2 and frags > int(_director_chains.get(chain["id"], 0)):
			_director_chains[chain["id"]] = frags
			director_cut(str(chain["id"]), Cue.MULTIKILL, DIRECTOR_HOLD[Cue.MULTIKILL], "multikill")
			break
	var returning: Array[Dictionary] = []
	for pad: Dictionary in facts.get("pads", []):
		if pad.get("power") == true:
			returning.append({"id": pad["id"], "back_in": int(pad["back_in"])})
	var plate: Dictionary = facts.get("plate", {})
	if not plate.is_empty() and plate.get("up") == false and int(plate.get("back_in", -1)) >= 0:
		returning.append({"id": plate["id"], "back_in": int(plate["back_in"])})
	var down: Dictionary = {}
	for pad: Dictionary in returning:
		down[pad["id"]] = true
	for id: Variant in _director_pads.keys():
		if not down.has(id):
			_director_pads.erase(id)
	for pad: Dictionary in returning:
		var seconds: float = float(pad["back_in"]) / 20.0
		if seconds > DIRECTOR_POWER_SECONDS or _director_pads.has(pad["id"]):
			continue
		var spot: Vector3 = pad_position(pickups, str(pad["id"]))
		if not spot.is_finite():
			continue
		var nearest: String = nearest_fighter(spot, DIRECTOR_POWER_RANGE)
		if nearest.is_empty():
			continue
		_director_pads[pad["id"]] = true
		director_cut(nearest, Cue.POWER, seconds + 4.0, "power")
		break
	var step: int = maxi(1, int(facts.get("spree_step", 5)))
	var sprees: Dictionary = {}
	for spree: Dictionary in facts.get("sprees", []):
		sprees[spree["id"]] = int(spree["frags"])
	for id: Variant in _director_sprees.keys():
		if not sprees.has(id):
			_director_sprees.erase(id)
	for spree: Dictionary in facts.get("sprees", []):
		var frags: int = int(spree["frags"])
		if frags >= step and frags > int(_director_sprees.get(spree["id"], 0)):
			_director_sprees[spree["id"]] = frags
			director_cut(str(spree["id"]), Cue.SPREE, DIRECTOR_HOLD[Cue.SPREE], "spree")
			break

## A public frag: a Rocket frag is worth the cut to its shooter.
func director_observe_frag(data: Dictionary, killer_id: String) -> void:
	if str(data.get("weapon", "")) == "rocket":
		director_cut(killer_id, Cue.ROCKET, DIRECTOR_HOLD[Cue.ROCKET], "rocket")

## A pad's place in the world from the snapshot, or a non-finite vector.
static func pad_position(pickups: Array, pad_id: String) -> Vector3:
	for pad: Variant in pickups:
		if pad is Dictionary and str(pad.get("id", "")) == pad_id:
			var at := Vector3(float(pad.get("x", NAN)), float(pad.get("y", NAN)), float(pad.get("z", NAN)))
			return at
	return Vector3(NAN, NAN, NAN)

## The followable fighter nearest a point inside `reach`, or empty.
func nearest_fighter(spot: Vector3, reach: float) -> String:
	var best: String = ""
	var best_distance: float = reach
	for target: Variant in available_targets:
		if not is_instance_valid(target) or int(target.get("hp")) <= 0:
			continue
		var distance: float = (target as Node3D).global_position.distance_to(spot)
		if distance <= best_distance:
			best_distance = distance
			best = str(target.get("player_id"))
	return best

func lock_on_frag(killer_id: String, duration: float = 1.5):
	# A director's cut holds its fighter; an ordinary frag elsewhere waits.
	if tip_pose_lock or not pinned_player_id.is_empty() or _director_hold > 0.0:
		return
	if fp_mode or spectator_first_person:
		return
	frag_follow_target_id = killer_id
	frag_follow_timer = duration
	auto_cycle_timer = 0.0

func _follow_frag_target(delta: float = 1.0 / 60.0) -> void:
	if frag_follow_target_id == "":
		return

	for target in available_targets:
		if is_instance_valid(target) and target.player_id == frag_follow_target_id:
			var target_pos = target.global_position
			var offset = Vector3(0, 5.5, 10.5)
			var cam_pos = target_pos + offset.rotated(Vector3.UP, target.rotation.y)
			position = position.lerp(cam_pos, follow_weight(0.15, delta))

			var look_target = target_pos + Vector3(0, 1.5, 0)
			var desired_transform = global_transform.looking_at(look_target, Vector3.UP)
			global_transform = global_transform.interpolate_with(desired_transform, follow_weight(0.2, delta))
			return


## Begin the death view from wherever the camera is now: the dead eye. No
## other camera mode runs until `end_death_view`.
func begin_death_view(chase_id: String = "") -> void:
	if not pinned_player_id.is_empty():
		return
	if fp_mode:
		set_fp_mode(false)
	_set_observed_pawn(null)
	frag_follow_timer = 0.0
	frag_follow_target_id = ""
	mouse_motion = Vector2.ZERO
	death_view = true
	death_chase_id = chase_id

func end_death_view() -> void:
	death_view = false
	death_chase_id = ""

## The fighter the death view is actually following, or null while holding.
func death_view_target() -> Node3D:
	if not death_view or death_chase_id.is_empty():
		return null
	for target: Variant in _all_targets:
		if is_instance_valid(target) and str(target.get("player_id")) == death_chase_id:
			return target as Node3D
	return null

func _process_death_view(delta: float) -> void:
	var target: Node3D = death_view_target()
	if target == null:
		# Killer gone, suicide or no killer: hold the last view exactly.
		return
	var target_pos: Vector3 = target.global_position
	var cam_pos: Vector3 = target_pos + Vector3(0, 5.5, 10.5).rotated(Vector3.UP, target.rotation.y)
	var look_target: Vector3 = target_pos + Vector3(0, 1.5, 0)
	if reduced_motion:
		global_position = cam_pos
		if not global_position.is_equal_approx(look_target):
			look_at(look_target, Vector3.UP)
		return
	position = position.lerp(cam_pos, follow_weight(0.15, delta))
	if not global_position.is_equal_approx(look_target):
		var desired: Transform3D = global_transform.looking_at(look_target, Vector3.UP)
		global_transform = global_transform.interpolate_with(desired, follow_weight(0.2, delta))

## Preserve the existing 60 Hz chase speed at every rendering cadence.
## The room the camera keeps off a cover face, and its closest approach.
const CHASE_COVER_PAD: float = 0.5
const CHASE_NEAREST: float = 0.8
## Mid-body, from the pawn's server reference point (1.5 m above its feet).
const CHASE_BODY_PROBE: float = -0.6
## Boom elevations tried, lowest first, when cover blocks the usual one.
const CHASE_LIFT_DEGREES: Array[float] = [40.0, 55.0, 70.0, 85.0]
## Under a deck every raised boom meets the ceiling: then lower ones, which
## see the fighter along the floor instead of staring up at the slab.
const CHASE_DROP_DEGREES: Array[float] = [15.0, 5.0]
## The chase view looks at the fighter's head, this far above its server
## reference point (1.5 m above its feet).
const CHASE_LOOK_RISE: float = 0.3

## The chase camera's spot on its boom from `look` to `desired`. Cover on the
## boom first raises the boom at full length, lowest clear angle first, so the
## view stays a chase view; only cover tall enough to block every angle pulls
## the camera in.
static func chase_clear_position(look: Vector3, desired: Vector3, solids: Array) -> Vector3:
	var hit: float = AimAssist.first_hit(look, desired, solids)
	if hit < 0.0:
		return desired
	var boom: Vector3 = desired - look
	var length: float = boom.length()
	var flat: Vector3 = Vector3(boom.x, 0.0, boom.z)
	var behind: Vector3 = flat.normalized() if flat.length() > 0.001 else Vector3.BACK
	# The longest clear stretch seen so far, for when no boom is clear.
	var best: Vector3 = desired
	var best_free: float = hit
	for degrees: float in CHASE_LIFT_DEGREES + CHASE_DROP_DEGREES:
		var angle: float = deg_to_rad(degrees)
		var spot: Vector3 = look + (behind * cos(angle) + Vector3.UP * sin(angle)) * length
		var blocked: float = AimAssist.first_hit(look, spot, solids)
		if blocked < 0.0:
			return spot
		if blocked > best_free:
			best_free = blocked
			best = spot
	return look + (best - look).normalized() * maxf(CHASE_NEAREST, best_free - CHASE_COVER_PAD)

static func follow_weight(weight_at_60_hz: float, delta: float) -> float:
	return 1.0 - pow(1.0 - clampf(weight_at_60_hz, 0.0, 1.0), maxf(delta, 0.0) * 60.0)

func _process_fp(delta):
	# Local angles are sent as absolute authoritative aim in the next action.
	if mouse_motion.length() > 0:
		_turn_by_counts(mouse_motion)
		mouse_motion = Vector2.ZERO

	# Keys and the right stick change the same local aim sent through Action.
	# Aim assist reads the look source: the mouse is never assisted.
	var assisted: bool = AimAssist.enabled_for(aim_assist, InputDevice.look_source)
	assist_pick = AimAssist.pick(_assist_eye(), fp_yaw, fp_pitch, assist_targets, assist_solids, aim_assist) if assisted else {}
	var pad_look: bool = InputDevice.look_source == "gamepad"
	var change: Vector2 = _look_delta(delta, AimAssist.friction(assist_pick, aim_assist) if pad_look else 1.0) * look_scale()
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

	# Predicted play follows the rendered body, which moves between server
	# ticks. Snapshot fallback keeps the authoritative position so the eye
	# cannot smooth through a stair wall into the next room.
	var predicted: bool = fp_target.get("prediction_active") == true
	var lift: float = eye_lift(fp_target)
	var eye: Vector3 = fp_target.global_position + Vector3(0, lift, 0)
	if not predicted and "target_position" in fp_target:
		eye = fp_target.get("target_position") + Vector3(0, lift, 0)
	# The eye looks where the client aims, not where the last snapshot said.
	var yaw = fp_yaw

	if not reduced_motion and camera_shake_intensity > 0:
		eye += Vector3(
			randf_range(-camera_shake_intensity, camera_shake_intensity) * 0.35,
			randf_range(-camera_shake_intensity, camera_shake_intensity) * 0.25,
			0
		)

	var camera_eye: Vector3 = fp_camera_position(global_position, eye, delta, predicted)
	# Keep the usual motion smoothing while both eyes share a clear space.
	# Crossing an authoritative solid would put the view inside cover, so use
	# the server eye immediately at that boundary.
	global_position = camera_eye if AimAssist.line_of_sight(camera_eye, eye, assist_solids) else eye
	_watch_landing(global_position.y, delta)
	_settle_punch(delta)
	global_position.y += _dip
	# The server's yaw is not a Godot rotation. Assigning it straight to
	# rotation.y pointed the camera ninety degrees away from where the server
	# was moving the fighter, which is why holding forward read as strafing.
	rotation.y = ServerYaw.camera_rotation_y(yaw)
	# The punch moves the drawn view only; fp_pitch is the aim.
	rotation.x = clampf(fp_pitch + _punch.x, -PI / 2.0, PI / 2.0)
	rotation.z = _punch.y


## The prediction seam has its own bounded correction offset. Running the old
## snapshot lerp on top adds a second camera delay to every local move.
static func fp_camera_position(current: Vector3, eye: Vector3, delta: float, predicted: bool) -> Vector3:
	return eye if predicted else current.lerp(eye, minf(1.0, 18.0 * delta))

## Where the assist measures from: the fighter's authoritative eye.
func _assist_eye() -> Vector3:
	if not is_instance_valid(fp_target):
		return global_position
	var base: Vector3 = fp_target.global_position
	if "target_position" in fp_target and fp_target.get("prediction_active") != true:
		base = fp_target.get("target_position")
	return base + Vector3(0, eye_lift(fp_target), 0)

## Radians of turn per mouse count at the current sensitivity.
func _radians_per_count() -> float:
	return deg_to_rad(DEGREES_PER_COUNT * mouse_sensitivity) * look_scale()

## Scoped look is finer by the magnification; the open view is unchanged.
func look_scale() -> float:
	return clampf(zoom_factor, 0.05, 1.0) if fp_mode else 1.0

## Touch the lens only while the scope is in use or returning, so other owners
## of the field of view (settings, captures) are never overwritten.
func apply_zoom() -> void:
	var wanted: float = clampf(zoom_factor, 0.05, 1.0) if fp_mode else 1.0
	if is_equal_approx(wanted, _applied_zoom):
		return
	_applied_zoom = wanted
	var lens: Camera3D = get_node_or_null("Camera3D")
	if lens != null:
		lens.fov = magnified_fov(base_fov, wanted)

## Magnification scales the projected image, not the angle in degrees.
static func magnified_fov(open_fov: float, inverse_zoom: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(open_fov) * 0.5) * inverse_zoom))


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

## Kick the drawn first-person view for one of this player's own shots.
func punch_for_weapon(weapon_name: String) -> void:
	if not fp_mode:
		return
	punch_view(float(PUNCH_DEGREES.get(weapon_name, 0.0)))


func punch_view(pitch_degrees: float) -> void:
	if reduced_motion or pitch_degrees <= 0.0:
		return
	# An impulse whose spring peak is exactly the requested angle.
	var gain: float = PUNCH_OMEGA * exp(1.0)
	_punch_side = -_punch_side
	_punch_rate += Vector2(deg_to_rad(pitch_degrees), deg_to_rad(pitch_degrees) * PUNCH_ROLL_SHARE * _punch_side) * gain


## The drawn view's punch now, for harnesses: (pitch, roll) radians.
func view_punch() -> Vector2:
	return _punch


func landing_dip() -> float:
	return _dip


## One exact step of a critically damped spring toward zero, so the shape is
## the same at every frame rate: (value, rate) after `dt`.
static func spring_step(value: float, rate: float, omega: float, dt: float) -> Vector2:
	var decay: float = exp(-omega * dt)
	var drive: float = rate + omega * value
	return Vector2((value + drive * dt) * decay, (rate - drive * omega * dt) * decay)


func _settle_punch(delta: float) -> void:
	var pitch: Vector2 = spring_step(_punch.x, _punch_rate.x, PUNCH_OMEGA, delta)
	var roll: Vector2 = spring_step(_punch.y, _punch_rate.y, PUNCH_OMEGA, delta)
	_punch = Vector2(pitch.x, roll.x)
	_punch_rate = Vector2(pitch.y, roll.y)
	if _punch.length() < 0.00001 and _punch_rate.length() < 0.0001:
		_punch = Vector2.ZERO
		_punch_rate = Vector2.ZERO
	var dip: Vector2 = spring_step(_dip, _dip_rate, DIP_OMEGA, delta)
	_dip = dip.x
	_dip_rate = dip.y
	if absf(_dip) < 0.00001 and absf(_dip_rate) < 0.0001:
		_dip = 0.0
		_dip_rate = 0.0


## Watches the drawn eye fall and land: a landing faster than a plain hop's
## dips the eye by how much faster it came down.
func _watch_landing(eye_y: float, delta: float) -> void:
	if delta <= 0.0:
		return
	if is_nan(_eye_y):
		_eye_y = eye_y
		return
	var vy: float = (eye_y - _eye_y) / delta
	if _eye_vy < -2.0 and vy > -0.5 and not reduced_motion:
		var depth: float = clampf((-_eye_vy - DIP_FREE_SPEED) * DIP_PER_SPEED, 0.0, DIP_MAX) + 0.015
		_dip_rate -= depth * DIP_OMEGA * exp(1.0)
	_eye_vy = vy
	_eye_y = eye_y


func _clear_punch() -> void:
	_punch = Vector2.ZERO
	_punch_rate = Vector2.ZERO
	_dip = 0.0
	_dip_rate = 0.0
	_eye_y = NAN
	_eye_vy = 0.0


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
	if enabled:
		end_death_view()
	fp_mode = enabled
	fp_target = target
	_clear_punch()
	rotation.z = 0.0
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
		position = target.global_position + Vector3(0, eye_lift(target), 0)
		rotation.y = ServerYaw.camera_rotation_y(yaw)
		rotation.x = fp_pitch

static func _target_server_yaw(target: Node3D) -> float:
	return float(target.get("target_yaw")) if "target_yaw" in target else -target.rotation.y

static func _target_server_pitch(target: Node3D) -> float:
	return clampf(float(target.get("target_pitch")), -ServerYaw.PITCH_LIMIT, ServerYaw.PITCH_LIMIT) if "target_pitch" in target else 0.0


static func _target_presentation_yaw(target: Node3D) -> float:
	return float(target.get("presentation_yaw")) if "presentation_yaw" in target else _target_server_yaw(target)


static func _target_presentation_pitch(target: Node3D) -> float:
	return float(target.get("presentation_pitch")) if "presentation_pitch" in target else _target_server_pitch(target)

func is_observing_first_person() -> bool:
	return not death_view and not fp_mode and follow_mode and spectator_first_person and is_instance_valid(get_followed_target())

func _set_observed_pawn(target: Node3D) -> void:
	if _observed_pawn == target:
		return
	if is_instance_valid(_observed_pawn) and _observed_pawn.has_method("set_local_fp"):
		_observed_pawn.set_local_fp(false)
	_observed_pawn = target
	if is_instance_valid(_observed_pawn) and _observed_pawn.has_method("set_local_fp"):
		_observed_pawn.set_local_fp(true)


## A scripted camera path (the benchmark orbit) owns the pose from here. The
## camera stops following anyone, so no fighter is hidden for an eye view, no
## viewmodel or vitals are presented for a fighter the camera is not inside,
## and no highlight ring marks a followed pawn.
func hand_over_pose() -> void:
	set_fp_mode(false)
	_set_observed_pawn(null)
	follow_mode = false
	spectator_first_person = false
	frag_follow_timer = 0.0
	frag_follow_target_id = ""
	auto_cycle_timer = 0.0
	mouse_motion = Vector2.ZERO

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
