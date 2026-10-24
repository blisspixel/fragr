extends SceneTree

## Rendered movement and weapon feel probe on a real joined match. A scripted
## human strafes, stops, reverses, jumps, flicks the mouse and fires through
## the ordinary Action path while every drawn frame records the camera that
## was actually drawn. The same script runs on any build, so a before and after
## pair measures one change rather than two sessions.
##
## Measurements (written to FRAGR_QA_DIR as feel.json and feel.md):
## key to first moved frame, key to 90 percent of top speed, release to rest
## and the slide distance, a strafe reversal, steady strafe speed variation and
## backward frames, frame time percentiles, same-tick prediction corrections,
## mouse event to drawn and to sent aim, jump rise, and fire to local kick and
## to the resolved shot. A second pass grabs consecutive frames into motion
## strips (strafe_stop, reversal, jump, fire) for a person to inspect.
##
## FRAGR_SERVER names a separately started server, for example
## `fragr-server --bind 127.0.0.1:6791 --bots 0 --map 1 --no-round-events`.
## FRAGR_FEEL_STRIPS=0 skips the strip pass. The probe is evidence, not a
## gate: it fails only when the session itself could not run.

const BOUND_MS: int = 180000
const STRAFE_SECONDS: float = 1.2
const REST_SECONDS: float = 0.9
const FLICK_COUNTS: float = 240.0
const STRIP_FRAMES: int = 24
const STRIP_TILE: Vector2i = Vector2i(320, 180)
## A frame that moves less than this is at rest for the stop measurement.
const REST_EPSILON: float = 0.0005

var _directory: String = ""
var _manager: Node = null
var _started: int = 0
var _failed: bool = false
var _finishing: bool = false
var _recording: bool = false
var _frames: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _phase: String = ""
var _yaw: float = 0.0
var _shots_seen: Array[Dictionary] = []
var _last_shot_tick: int = -1
## The flick pass needs a captured mouse on builds that only turn a captured
## view; everything else keeps the cursor free.
var _hold_capture: bool = false


func _initialize() -> void:
	set_meta("fragr_automated", true)
	_started = Time.get_ticks_msec()
	MouseCapture.release()
	call_deferred("_run")


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started > BOUND_MS:
		_require(false, "session exceeded its bound")
		_finish()
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE and not _hold_capture:
		MouseCapture.release()
	return false


func _finalize() -> void:
	MouseCapture.release()


func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error("qa_feel: " + message)
		_failed = true
	return condition


func _until(condition: Callable, timeout_ms: int = 30000) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	return condition.call()


func _run() -> void:
	_directory = OS.get_environment("FRAGR_QA_DIR")
	if not _require(not _directory.is_empty() and _directory.is_absolute_path(), "FRAGR_QA_DIR must name an absolute owned directory"):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_directory)
	set_meta("fragr_settings_path", _directory.path_join("settings.cfg"))
	set_meta("fragr_records_path", _directory.path_join("records.json"))
	var settings: FragrSettings = FragrSettings.new(_directory.path_join("settings.cfg"))
	settings.set_value("video", "display_mode", 0)
	settings.set_value("audio", "music", 0.0)
	settings.set_value("audio", "voice", 0.0)
	if not _require(settings.save_to_disk() == OK, "isolated settings save"):
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var url: String = OS.get_environment("FRAGR_SERVER")
	if not _require(not url.is_empty(), "FRAGR_SERVER must name the server"):
		quit(1)
		return
	set_meta("fragr_boot", {"mode": "join", "host": url})
	change_scene_to_file("res://scenes/main.tscn")
	if not _require(await _until(func() -> bool: return current_scene != null and current_scene.get("local_prediction") != null), "match scene loaded"):
		_finish()
		return
	_manager = current_scene
	if not _require(await _until(func() -> bool: return _manager.get_node_or_null("LoadingCard") == null \
			and bool(_manager.camera.fp_mode) and _alive(), 60000), "a live first-person fighter"):
		_finish()
		return
	await create_timer(1.5).timeout
	_manager.set("pending_weapon_swap", "flechette")
	await create_timer(0.6).timeout
	_yaw = _clear_yaw()
	_face()
	RenderingServer.frame_pre_draw.connect(_sample)
	await _settle()
	_manager.local_prediction.clear_measurements()
	_recording = true
	_mark("idle")
	await create_timer(1.0).timeout
	await _strafe("strafe_left", "move_left")
	await _strafe("strafe_right", "move_right")
	await _reversal()
	await _jump()
	await _dodge()
	await _flicks()
	await _fire()
	_recording = false
	QaCombat.release_inputs()
	var report: Dictionary = _analyze()
	report["corrections"] = _corrections()
	if OS.get_environment("FRAGR_FEEL_STRIPS") != "0":
		report["strips"] = await _strips()
	_write(report)
	_finish()


## The facing whose left and right both have the longest clear strafe line.
func _clear_yaw() -> float:
	var arena: Dictionary = _manager.local_prediction.arena
	var feet: Vector3 = _feet()
	var best: float = 0.0
	var best_room: float = -1.0
	if arena.is_empty():
		return best
	for step: int in range(24):
		var yaw: float = TAU * float(step) / 24.0
		var right: Vector2 = Vector2(-sin(yaw), cos(yaw))
		var room: float = INF
		for side: float in [-1.0, 1.0]:
			var clear: float = 0.0
			for metre: int in range(1, 13):
				var point: Vector2 = Vector2(feet.x, feet.z) + right * side * float(metre)
				if MoveStep.arena_blocked_body_at(arena, point.x, point.y, feet.y, feet.y + MoveStep.STEP_UP):
					break
				var limit: float = float(arena["half"]) - MoveStep.RADIUS
				if absf(point.x) > limit or absf(point.y) > limit:
					break
				clear = float(metre)
			room = minf(room, clear)
		if room > best_room:
			best_room = room
			best = yaw
	_events.append({"kind": "clearance", "metres": best_room, "yaw": best})
	return best


func _face() -> void:
	_manager.camera.fp_yaw = _yaw
	_manager.camera.fp_pitch = 0.0


func _settle() -> void:
	QaCombat.release_inputs()
	Input.action_release("jump")
	await create_timer(REST_SECONDS).timeout


func _mark(label: String) -> void:
	_phase = label
	_events.append({"kind": "phase", "label": label, "usec": Time.get_ticks_usec()})


func _event(kind: String, extra: Dictionary = {}) -> void:
	var entry: Dictionary = {"kind": kind, "phase": _phase, "usec": Time.get_ticks_usec()}
	entry.merge(extra)
	_events.append(entry)


func _strafe(label: String, action: String) -> void:
	_mark(label)
	_face()
	Input.action_press(action)
	_event("press", {"action": action})
	await create_timer(STRAFE_SECONDS).timeout
	Input.action_release(action)
	_event("release", {"action": action})
	await create_timer(REST_SECONDS).timeout


func _reversal() -> void:
	_mark("reversal")
	_face()
	Input.action_press("move_left")
	_event("press", {"action": "move_left"})
	await create_timer(0.8).timeout
	Input.action_release("move_left")
	Input.action_press("move_right")
	_event("reverse", {"action": "move_right"})
	await create_timer(0.8).timeout
	Input.action_release("move_right")
	_event("release", {"action": "move_right"})
	await create_timer(REST_SECONDS).timeout


func _jump() -> void:
	_mark("jump")
	_face()
	Input.action_press("jump")
	_event("press", {"action": "jump"})
	await create_timer(0.08).timeout
	Input.action_release("jump")
	await create_timer(1.1).timeout


## A dodge to the right from a standstill, where the build has one.
func _dodge() -> void:
	_mark("dodge")
	_face()
	if not InputMap.has_action("dodge"):
		_event("absent")
		await create_timer(0.1).timeout
		return
	Input.action_press("move_right")
	Input.action_press("dodge")
	_event("press", {"action": "dodge"})
	await create_timer(0.05).timeout
	Input.action_release("dodge")
	await create_timer(0.45).timeout
	Input.action_release("move_right")
	_event("release", {"action": "move_right"})
	await create_timer(REST_SECONDS).timeout


func _flicks() -> void:
	_mark("flick")
	_face()
	_hold_capture = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await create_timer(0.2).timeout
	for index: int in range(3):
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.screen_relative = Vector2(FLICK_COUNTS * (1.0 if index % 2 == 0 else -1.0), 0.0)
		motion.relative = motion.screen_relative
		_event("flick", {"counts": motion.screen_relative.x})
		_manager.camera.accept_mouse_motion(motion, true)
		await create_timer(0.4).timeout
	_hold_capture = false
	MouseCapture.release()
	_face()
	await create_timer(0.3).timeout


func _fire() -> void:
	_mark("fire")
	_face()
	await create_timer(0.2).timeout
	for index: int in range(3):
		Input.action_press("fire")
		_event("press", {"action": "fire"})
		await create_timer(0.05).timeout
		Input.action_release("fire")
		await create_timer(0.6).timeout


## Called on the rendering thread's pre-draw signal, after every node's
## process: the camera recorded here is the one this frame draws.
func _sample() -> void:
	if not _recording or not is_instance_valid(_manager):
		return
	var camera: Node3D = _manager.camera
	var hud: Node = _manager.hud
	var prediction: LocalPrediction = _manager.local_prediction
	var position: Vector3 = camera.global_position
	var now: int = Time.get_ticks_usec()
	var presented: Variant = _manager.get("presented_usec")
	_frames.append({
		"usec": now,
		# The clock the body was drawn for, where the build exposes it. Drawn
		# speed against it is the motion itself, without the engine's varying
		# gap between process and draw.
		"pusec": int(presented) if presented is int and int(presented) > 0 else now,
		"phase": _phase,
		"x": position.x, "y": position.y, "z": position.z,
		"rot_y": camera.rotation.y,
		"rot_x": camera.rotation.x,
		"aim_pitch": float(camera.get("fp_pitch")),
		"sent_yaw": float(_manager.action_state.get("yaw", 0.0)),
		"kick": float(hud.get("fp_kick_timer")) if hud != null else 0.0,
		"active": prediction.active(),
		"corrections": prediction.correction_count,
		"offset": prediction.visual_offset.length(),
		"fallbacks": prediction.fallback_count,
	})
	var snapshot: Dictionary = _manager.latest_snapshot
	var tick: int = int(snapshot.get("tick", -1))
	if tick != _last_shot_tick:
		_last_shot_tick = tick
		var me: String = str(_manager.net_client.player_id)
		for shot: Variant in snapshot.get("shot_results", []):
			if shot is Dictionary and str(shot.get("shooter_id", "")) == me:
				_shots_seen.append({"usec": Time.get_ticks_usec(), "tick": tick})
				break


func _top_speed() -> float:
	return MoveStep.TOP_SPEED


func _analyze() -> Dictionary:
	var report: Dictionary = {"frames": _frames.size(), "top_speed": _top_speed(),
		"build": str(ProjectSettings.get_setting("application/config/version", "")),
		"load": _proc_line("/proc/loadavg")}
	var right: Vector2 = Vector2(-sin(_yaw), cos(_yaw))
	var deltas: Array[float] = []
	var backward: int = 0
	for index: int in range(1, _frames.size()):
		deltas.append(float(int(_frames[index]["usec"]) - int(_frames[index - 1]["usec"])) / 1000.0)
	report["frame_ms"] = _percentiles(deltas)
	for label: String in ["strafe_left", "strafe_right"]:
		report[label] = _strafe_metrics(label, right * (-1.0 if label == "strafe_left" else 1.0))
		backward += int(report[label].get("backward_frames", 0))
	report["reversal"] = _reversal_metrics(right)
	report["backward_frames_total"] = backward + int(report["reversal"].get("backward_frames", 0))
	report["jump"] = _jump_metrics()
	report["dodge"] = _dodge_metrics(right)
	report["flick"] = _flick_metrics()
	report["fire"] = _fire_metrics()
	return report


func _phase_frames(label: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for frame: Dictionary in _frames:
		if frame["phase"] == label:
			result.append(frame)
	return result


func _phase_event(label: String, kind: String) -> Dictionary:
	for entry: Dictionary in _events:
		if entry.get("phase", "") == label and entry["kind"] == kind:
			return entry
	return {}


static func _along(a: Dictionary, b: Dictionary, axis: Vector2) -> float:
	return Vector2(float(b["x"]) - float(a["x"]), float(b["z"]) - float(a["z"])).dot(axis)


static func _seconds(a: Dictionary, b: Dictionary) -> float:
	return maxf(float(int(b["usec"]) - int(a["usec"])) / 1000000.0, 0.000001)


func _strafe_metrics(label: String, axis: Vector2) -> Dictionary:
	var frames: Array[Dictionary] = _phase_frames(label)
	var press: Dictionary = _phase_event(label, "press")
	var release: Dictionary = _phase_event(label, "release")
	if frames.size() < 4 or press.is_empty() or release.is_empty():
		return {"error": "not recorded"}
	return _motion_from(frames, axis, int(press["usec"]), int(release["usec"]))


## Start response, steady speed and the stop, from rendered camera motion.
func _motion_from(frames: Array[Dictionary], axis: Vector2, press_usec: int, release_usec: int) -> Dictionary:
	var result: Dictionary = {}
	var top: float = _top_speed()
	var first_move: int = -1
	var reach: int = -1
	var steady: Array[float] = []
	var steady_presented: Array[float] = []
	var backward: int = 0
	var run: int = 0
	var frames_after_press: int = 0
	for index: int in range(1, frames.size()):
		var frame: Dictionary = frames[index]
		var usec: int = int(frame["usec"])
		if usec < press_usec or usec > release_usec:
			continue
		frames_after_press += 1
		var step: float = _along(frames[index - 1], frame, axis)
		var speed: float = step / _seconds(frames[index - 1], frame)
		if step < -REST_EPSILON:
			backward += 1
		if first_move < 0 and step > 0.001:
			first_move = usec
			result["key_to_first_motion_frames"] = frames_after_press
		run = run + 1 if speed >= 0.9 * top else 0
		if reach < 0 and run >= 3:
			reach = usec
		if usec >= press_usec + 500000 and usec <= release_usec - 50000:
			steady.append(speed)
			var span: float = float(int(frame["pusec"]) - int(frames[index - 1]["pusec"])) / 1000000.0
			if span > 0.0:
				steady_presented.append(step / span)
	result["key_to_first_motion_ms"] = _ms(first_move - press_usec) if first_move >= 0 else -1.0
	result["key_to_90pct_ms"] = _ms(reach - press_usec) if reach >= 0 else -1.0
	var mean: float = 0.0
	for value: float in steady:
		mean += value
	mean = mean / float(maxi(steady.size(), 1))
	var variance: float = 0.0
	for value: float in steady:
		variance += (value - mean) * (value - mean)
	var deviation: float = sqrt(variance / float(maxi(steady.size(), 1)))
	result["steady_speed_mean"] = snappedf(mean, 0.001)
	result["steady_speed_cv"] = snappedf(deviation / maxf(mean, 0.001), 0.0001)
	result["steady_frames"] = steady.size()
	result["steady_speed_cv_presented"] = _cv(steady_presented)
	# The stop: from release until the drawn eye no longer moves.
	var release_frame: Dictionary = {}
	var rest: int = -1
	for index: int in range(1, frames.size()):
		var frame: Dictionary = frames[index]
		if int(frame["usec"]) < release_usec:
			continue
		if release_frame.is_empty():
			release_frame = frames[index - 1]
		var step: float = _along(frames[index - 1], frame, axis)
		if step < -REST_EPSILON:
			backward += 1
		if absf(step) <= REST_EPSILON * 0.2:
			if rest < 0:
				rest = index
		else:
			rest = -1
	if not release_frame.is_empty() and rest > 0:
		result["release_to_rest_ms"] = _ms(int(frames[rest]["usec"]) - release_usec)
		result["slide_m"] = snappedf(_along(release_frame, frames[rest], axis), 0.001)
	result["backward_frames"] = backward
	return result


func _reversal_metrics(right: Vector2) -> Dictionary:
	var frames: Array[Dictionary] = _phase_frames("reversal")
	var reverse: Dictionary = _phase_event("reversal", "reverse")
	var release: Dictionary = _phase_event("reversal", "release")
	if frames.size() < 4 or reverse.is_empty() or release.is_empty():
		return {"error": "not recorded"}
	var result: Dictionary = _motion_from(frames, right, int(reverse["usec"]), int(release["usec"]))
	var crossing: int = -1
	for index: int in range(1, frames.size()):
		var frame: Dictionary = frames[index]
		if int(frame["usec"]) < int(reverse["usec"]):
			continue
		if _along(frames[index - 1], frame, right) > 0.0:
			crossing = int(frame["usec"])
			break
	result["reverse_to_direction_change_ms"] = _ms(crossing - int(reverse["usec"])) if crossing >= 0 else -1.0
	return result


func _jump_metrics() -> Dictionary:
	var frames: Array[Dictionary] = _phase_frames("jump")
	var press: Dictionary = _phase_event("jump", "press")
	if frames.size() < 4 or press.is_empty():
		return {"error": "not recorded"}
	var base: float = float(frames[0]["y"])
	var rise: int = -1
	var peak: float = base
	var landed: int = -1
	for frame: Dictionary in frames:
		var usec: int = int(frame["usec"])
		if usec < int(press["usec"]):
			base = float(frame["y"])
			continue
		var height: float = float(frame["y"]) - base
		peak = maxf(peak, float(frame["y"]))
		if rise < 0 and height > 0.001:
			rise = usec
		if rise >= 0 and landed < 0 and usec > rise + 100000 and absf(height) <= 0.001:
			landed = usec
	return {"key_to_rise_ms": _ms(rise - int(press["usec"])) if rise >= 0 else -1.0,
		"peak_m": snappedf(peak - base, 0.001),
		"air_ms": _ms(landed - rise) if rise >= 0 and landed >= 0 else -1.0}


func _dodge_metrics(right: Vector2) -> Dictionary:
	var frames: Array[Dictionary] = _phase_frames("dodge")
	var press: Dictionary = _phase_event("dodge", "press")
	if frames.size() < 4 or press.is_empty():
		return {"error": "no dodge on this build"}
	var start: Dictionary = {}
	var peak_speed: float = 0.0
	var peak_height: float = 0.0
	var travelled: float = 0.0
	for index: int in range(1, frames.size()):
		var frame: Dictionary = frames[index]
		if int(frame["usec"]) < int(press["usec"]):
			continue
		if start.is_empty():
			start = frames[index - 1]
		if int(frame["usec"]) > int(press["usec"]) + 400000:
			break
		var step: float = _along(frames[index - 1], frame, right)
		peak_speed = maxf(peak_speed, step / _seconds(frames[index - 1], frame))
		peak_height = maxf(peak_height, float(frame["y"]) - float(start["y"]))
		travelled = _along(start, frame, right)
	return {"peak_drawn_speed": snappedf(peak_speed, 0.01), "hop_m": snappedf(peak_height, 0.001),
		"distance_400ms_m": snappedf(travelled, 0.001)}


func _flick_metrics() -> Dictionary:
	var frames: Array[Dictionary] = _phase_frames("flick")
	var drawn: Array[float] = []
	var sent: Array[float] = []
	for entry: Dictionary in _events:
		if entry["kind"] != "flick":
			continue
		var at: int = int(entry["usec"])
		var before: Dictionary = {}
		var drawn_at: int = -1
		var sent_at: int = -1
		for frame: Dictionary in frames:
			if int(frame["usec"]) < at:
				before = frame
				continue
			if before.is_empty():
				break
			if drawn_at < 0 and absf(angle_difference(float(frame["rot_y"]), float(before["rot_y"]))) > 0.001:
				drawn_at = int(frame["usec"])
			if sent_at < 0 and absf(angle_difference(float(frame["sent_yaw"]), float(before["sent_yaw"]))) > 0.001:
				sent_at = int(frame["usec"])
		drawn.append(_ms(drawn_at - at) if drawn_at >= 0 else -1.0)
		sent.append(_ms(sent_at - at) if sent_at >= 0 else -1.0)
	return {"event_to_drawn_ms": drawn, "event_to_sent_yaw_ms": sent}


func _fire_metrics() -> Dictionary:
	var frames: Array[Dictionary] = _phase_frames("fire")
	var kick: Array[float] = []
	var resolved: Array[float] = []
	var punch_peak: Array[float] = []
	var punch_peak_ms: Array[float] = []
	var punch_settle_ms: Array[float] = []
	var aim_moved: float = 0.0
	for entry: Dictionary in _events:
		if entry.get("phase", "") != "fire" or entry["kind"] != "press":
			continue
		var at: int = int(entry["usec"])
		var kicked: int = -1
		var previous: float = 0.0
		for frame: Dictionary in frames:
			if int(frame["usec"]) < at:
				previous = float(frame["kick"])
				continue
			if float(frame["kick"]) > previous + 0.0001:
				kicked = int(frame["usec"])
				break
			previous = float(frame["kick"])
		kick.append(_ms(kicked - at) if kicked >= 0 else -1.0)
		var shot_at: int = -1
		for shot: Dictionary in _shots_seen:
			if int(shot["usec"]) >= at:
				shot_at = int(shot["usec"])
				break
		resolved.append(_ms(shot_at - at) if shot_at >= 0 else -1.0)
		# The drawn view's punch: drawn pitch minus aim pitch, peak and settle.
		var peak: float = 0.0
		var peak_at: int = -1
		var settled: int = -1
		var base_aim: float = NAN
		for frame: Dictionary in frames:
			var usec: int = int(frame["usec"])
			if usec < at or usec > at + 550000:
				continue
			if is_nan(base_aim):
				base_aim = float(frame["aim_pitch"])
			aim_moved = maxf(aim_moved, absf(float(frame["aim_pitch"]) - base_aim))
			var punch: float = float(frame["rot_x"]) - float(frame["aim_pitch"])
			if punch > peak:
				peak = punch
				peak_at = usec
			if peak_at >= 0 and settled < 0 and punch < peak * 0.05:
				settled = usec
		punch_peak.append(snappedf(rad_to_deg(peak), 0.01))
		punch_peak_ms.append(_ms(peak_at - at) if peak_at >= 0 else -1.0)
		punch_settle_ms.append(_ms(settled - at) if settled >= 0 else -1.0)
	return {"press_to_local_kick_ms": kick, "press_to_resolved_shot_ms": resolved,
		"camera_punch_deg": punch_peak, "press_to_punch_peak_ms": punch_peak_ms,
		"press_to_punch_settled_ms": punch_settle_ms, "aim_pitch_moved_deg": snappedf(rad_to_deg(aim_moved), 0.001)}


func _corrections() -> Dictionary:
	var prediction: LocalPrediction = _manager.local_prediction
	var visible: int = 0
	for value: float in prediction.correction_samples:
		if value > 0.05:
			visible += 1
	var drawn: Dictionary = {}
	if prediction.has_method("presented_correction_percentile"):
		drawn = {"p50_m": snappedf(prediction.presented_correction_percentile(0.5), 0.0001),
			"p99_m": snappedf(prediction.presented_correction_percentile(0.99), 0.0001),
			"max_m": snappedf(prediction.presented_correction_percentile(1.0), 0.0001)}
	return {"count": prediction.correction_count,
		"drawn_eye_step_absorbed": drawn,
		"p50_m": snappedf(prediction.correction_percentile(0.5), 0.0001),
		"p99_m": snappedf(prediction.correction_percentile(0.99), 0.0001),
		"max_m": snappedf(prediction.correction_max, 0.0001),
		"over_5cm": visible,
		"fallbacks": prediction.fallback_count,
		"fallback_reasons": prediction.fallback_reasons.duplicate()}


static func _cv(values: Array[float]) -> float:
	if values.is_empty():
		return -1.0
	var mean: float = 0.0
	for value: float in values:
		mean += value
	mean /= float(values.size())
	var variance: float = 0.0
	for value: float in values:
		variance += (value - mean) * (value - mean)
	return snappedf(sqrt(variance / float(values.size())) / maxf(mean, 0.001), 0.0001)


static func _ms(usec: int) -> float:
	return snappedf(float(usec) / 1000.0, 0.01)


static func _percentiles(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	var pick: Callable = func(p: float) -> float:
		return ordered[clampi(int(ceilf(p * ordered.size())) - 1, 0, ordered.size() - 1)]
	return {"n": ordered.size(), "p50": snappedf(pick.call(0.5), 0.01), "p99": snappedf(pick.call(0.99), 0.01),
		"max": snappedf(ordered.back(), 0.01)}


## Drawn frames at a fixed interval from a press, tiled into one image per
## strip. Each step lists [seconds after the press, action, pressed]. The
## sheet reads left to right, top to bottom; frame_ms gives each tile's time.
func _strips() -> Dictionary:
	var saved: Dictionary = {}
	for strip: Dictionary in [
		{"name": "strafe_stop", "from": 0.0, "every": 0.035,
			"steps": [[0.0, "move_right", true], [0.42, "move_right", false]]},
		{"name": "reversal", "from": 0.25, "every": 0.03,
			"steps": [[0.0, "move_left", true], [0.45, "move_left", false], [0.45, "move_right", true], [0.9, "move_right", false]]},
		{"name": "jump", "from": 0.0, "every": 0.035,
			"steps": [[0.0, "jump", true], [0.08, "jump", false]]},
		{"name": "fire", "from": 0.0, "every": 0.02,
			"steps": [[0.0, "fire", true], [0.05, "fire", false]]},
		{"name": "dodge", "from": 0.0, "every": 0.03,
			"steps": [[0.0, "move_right", true], [0.0, "dodge", true], [0.05, "dodge", false], [0.5, "move_right", false]]},
	]:
		if strip["name"] == "dodge" and not InputMap.has_action("dodge"):
			continue
		await _settle()
		_face()
		# The strip's own frames are recorded too: a readback every capture
		# stalls the renderer, so the strip shows the build under hitches, and
		# these numbers say whether the eye stepped or reset while it did.
		var fallbacks_before: int = _manager.local_prediction.fallback_count
		var first_frame: int = _frames.size()
		_phase = "strip_" + str(strip["name"])
		_recording = true
		var images: Array[Image] = []
		var times: Array[float] = []
		var steps: Array = strip["steps"].duplicate(true)
		var began: int = Time.get_ticks_usec()
		var next_capture: int = began + int(float(strip["from"]) * 1000000.0)
		var every: int = int(float(strip["every"]) * 1000000.0)
		while images.size() < STRIP_FRAMES and Time.get_ticks_usec() - began < 4000000:
			var now: int = Time.get_ticks_usec()
			while not steps.is_empty() and now - began >= int(float(steps[0][0]) * 1000000.0):
				var step: Array = steps.pop_front()
				if bool(step[2]):
					Input.action_press(str(step[1]))
				else:
					Input.action_release(str(step[1]))
			await RenderingServer.frame_post_draw
			now = Time.get_ticks_usec()
			if now < next_capture:
				continue
			next_capture += every
			var image: Image = root.get_texture().get_image()
			image.resize(STRIP_TILE.x, STRIP_TILE.y, Image.INTERPOLATE_BILINEAR)
			images.append(image)
			times.append(_ms(now - began))
		_recording = false
		QaCombat.release_inputs()
		Input.action_release("jump")
		if InputMap.has_action("dodge"):
			Input.action_release("dodge")
		var largest_step: float = 0.0
		var longest_frame: float = 0.0
		for index: int in range(first_frame + 1, _frames.size()):
			var a: Dictionary = _frames[index - 1]
			var b: Dictionary = _frames[index]
			largest_step = maxf(largest_step, Vector3(float(b["x"]) - float(a["x"]), float(b["y"]) - float(a["y"]), float(b["z"]) - float(a["z"])).length())
			longest_frame = maxf(longest_frame, _ms(int(b["usec"]) - int(a["usec"])))
		var sheet: Image = Image.create(STRIP_TILE.x * 6, STRIP_TILE.y * ceili(float(images.size()) / 6.0), false, Image.FORMAT_RGB8)
		for index: int in range(images.size()):
			var tile: Image = images[index]
			tile.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(tile, Rect2i(Vector2i.ZERO, STRIP_TILE), Vector2i((index % 6) * STRIP_TILE.x, (index / 6) * STRIP_TILE.y))
		var path: String = _directory.path_join("strip_%s.png" % strip["name"])
		_require(sheet.save_png(path) == OK, "strip saves")
		saved[strip["name"]] = {"file": path.get_file(), "frame_ms": times,
			"largest_eye_step_m": snappedf(largest_step, 0.001), "longest_frame_ms": longest_frame,
			"prediction_resets": _manager.local_prediction.fallback_count - fallbacks_before}
	return saved


func _write(report: Dictionary) -> void:
	report["events"] = _events
	var raw: FileAccess = FileAccess.open(_directory.path_join("feel-frames.json"), FileAccess.WRITE)
	if _require(raw != null, "feel-frames.json opens"):
		raw.store_string(JSON.stringify({"yaw": _yaw, "frames": _frames}))
		raw.close()
	var out: FileAccess = FileAccess.open(_directory.path_join("feel.json"), FileAccess.WRITE)
	if _require(out != null, "feel.json opens"):
		out.store_string(JSON.stringify(report, "  "))
		out.close()
	var lines: PackedStringArray = ["| Measure | Value |", "|---|---|"]
	for key: String in ["frame_ms", "strafe_left", "strafe_right", "reversal", "backward_frames_total", "jump", "dodge", "flick", "fire", "corrections"]:
		lines.append("| %s | %s |" % [key, JSON.stringify(report.get(key, {}))])
	var table: FileAccess = FileAccess.open(_directory.path_join("feel.md"), FileAccess.WRITE)
	if _require(table != null, "feel.md opens"):
		table.store_string("\n".join(lines) + "\n")
		table.close()
	for line: String in lines:
		print(line)


func _alive() -> bool:
	if not is_instance_valid(_manager) or _manager.net_client.player_id == null:
		return false
	var me: Dictionary = QaCombat.actor_by_id(_manager.latest_snapshot, str(_manager.net_client.player_id))
	return not me.is_empty() and int(me.get("hp", 0)) > 0


func _feet() -> Vector3:
	var me: Dictionary = QaCombat.actor_by_id(_manager.latest_snapshot, str(_manager.net_client.player_id))
	if me.is_empty():
		return Vector3.ZERO
	return Vector3(float(me["x"]), float(me.get("y", 1.5)) - LocalPrediction.FLOOR_OFFSET, float(me["z"]))


static func _proc_line(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "unknown"
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unknown"
	var line: String = file.get_line().strip_edges()
	file.close()
	return line


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	_recording = false
	QaCombat.release_inputs()
	if is_instance_valid(_manager):
		_manager.net_client.leave_match()
	await create_timer(0.5).timeout
	# Retire the match the way the menu does, so quitting leaks nothing.
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	if not await ClientRetirement.for_tree(self).drain():
		_failed = true
	if _failed:
		push_error("qa_feel: FAIL")
		quit(1)
	else:
		print("qa_feel: PASS evidence written to ", _directory)
		quit(0)
