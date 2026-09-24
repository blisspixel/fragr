extends SceneTree

## Recall Notice by keyboard alone, against the real local server. Menus are
## driven with arrows and Enter, the story is skipped with Escape, and play uses
## only the arrow keys, the comma and period strafe keys, Ctrl and Enter: no
## mouse, no gamepad, and no direct writes to the camera's aim. Aim assist
## (standard, the default) is allowed to help, exactly as it would a player.
##
## It walks to the confiscated Tack, turns to the intake guard and shoots it
## down, then presses Enter to use. That covers turn, fire and use through the
## same Action wire every device shares. It is not a full clear of M01.

var failures: int = 0
var settings_path: String
var run_directory: String
var _held: Dictionary = {}
var _shots_hit: int = 0
var _assist_engaged: bool = false

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://keyboard-m01-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	run_directory = ProjectSettings.globalize_path("user://keyboard-m01-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	call_deferred("_run")

func _finalize() -> void:
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	var saved: DirAccess = DirAccess.open(run_directory)
	if saved != null:
		saved.list_dir_begin()
		var name: String = saved.get_next()
		while not name.is_empty():
			if not saved.current_is_dir():
				DirAccess.remove_absolute(run_directory.path_join(name))
			name = saved.get_next()
		saved.list_dir_end()
		DirAccess.remove_absolute(run_directory)
	OS.unset_environment("FRAGR_RUN_DIR")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_keyboard_m01: " + message)

func _until(condition: Callable, description: String, seconds: float = 20.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	_expect(passed, description)
	return passed

## A physical key, as a keyboard would send it.
func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	_held[code] = pressed

func _tap(code: Key) -> void:
	_key(code, true)
	await process_frame
	await process_frame
	_key(code, false)
	await process_frame

func _hold(code: Key, down: bool) -> void:
	if bool(_held.get(code, false)) != down:
		_key(code, down)

func _release_all() -> void:
	for code: Variant in _held.keys():
		if _held[code]:
			_key(code as Key, false)

func _local() -> Dictionary:
	for player: Dictionary in current_scene.latest_snapshot.get("players", []):
		if player.get("id") == current_scene.net_client.player_id:
			return player
	return {}

func _guard() -> Dictionary:
	for player: Dictionary in current_scene.latest_snapshot.get("players", []):
		var campaign: Variant = player.get("campaign")
		if campaign is Dictionary and campaign.get("side") == "union" and campaign.get("kind") == "clerk":
			return player
	return {}

func _playing() -> bool:
	return current_scene != null and current_scene.has_method("change_role") \
		and current_scene.current_map_id == 1001 and not current_scene.latest_snapshot.is_empty() \
		and not current_scene.mission_hud.state.is_empty()

## Turn with the arrow keys toward a server yaw. Returns the remaining error.
func _steer(goal: float) -> float:
	var camera: Node = current_scene.camera
	var error: float = AimAssist.angle_to(float(camera.fp_yaw), goal)
	_hold(KEY_RIGHT, error > deg_to_rad(2.0))
	_hold(KEY_LEFT, error < -deg_to_rad(2.0))
	return error

func _walk_to(goal: Vector2, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var me: Dictionary = _local()
		var here: Vector2 = Vector2(float(me.get("x", 0.0)), float(me.get("z", 0.0)))
		if here.distance_to(goal) < 0.6:
			_release_all()
			return true
		var error: float = _steer(atan2(goal.y - here.y, goal.x - here.x))
		_hold(KEY_UP, absf(error) < deg_to_rad(25.0))
		await create_timer(0.03).timeout
	_release_all()
	return false

func _run() -> void:
	var prefs: FragrSettings = FragrSettings.new(settings_path)
	prefs.set_value("video", "display_mode", 0)
	_expect(prefs.save_to_disk() == OK, "isolated preferences saved")
	_expect(prefs.get_value("controls", "aim_assist") == AimAssist.Level.STANDARD, "standard aim assist is the default")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 960)
	_expect(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "boot menu loads")
	# Menus by keyboard: Single Player takes focus first; Enter opens it.
	await _until(func() -> bool: return root.gui_get_focus_owner() is Button and (root.gui_get_focus_owner() as Button).text == "SINGLE PLAYER", "the menu opens with keyboard focus on Single Player")
	await _tap(KEY_ENTER)
	if not await _until(func() -> bool: return LocalMatch.for_tree(self).run_preview.get("status") == "missing" and current_scene._page == "single", "Enter opens Single Player with no saved run"):
		quit(1)
		return
	await process_frame
	_expect(root.gui_get_focus_owner() != null and root.gui_get_focus_owner().name == "RecallNotice", "Recall Notice holds keyboard focus")
	await _tap(KEY_ENTER)
	if not await _until(func() -> bool: return current_scene._page == "difficulty" and root.gui_get_focus_owner() != null and root.gui_get_focus_owner().name == "Difficulty_standard", "Enter opens the difficulty choice"):
		quit(1)
		return
	await _tap(KEY_DOWN)
	_expect(root.gui_get_focus_owner().name == "Difficulty_assisted", "Down moves focus to the next difficulty")
	await _tap(KEY_ENTER)
	if not await _until(_playing, "keyboard launch enters authoritative M01", 30.0):
		quit(1)
		return
	if not await _until(func() -> bool: return is_instance_valid(current_scene.opening), "the story opens"):
		quit(1)
		return
	await _tap(KEY_ESCAPE)
	if not await _until(func() -> bool: return not current_scene.controls_blocked() and current_scene._has_local_input_target(), "Escape skips the story into first-person play", 30.0):
		quit(1)
		return
	_expect(current_scene.mission_hud.state["rules"]["difficulty"] == "assisted", "the keyboard choice reached the server")
	# Centre on the bay with the Doom strafe keys, then walk and claim the Tack.
	var side: Key = KEY_COMMA if float(_local().get("x", 0.0)) < 0.0 else KEY_PERIOD
	_hold(side, true)
	await _until(func() -> bool: return absf(float(_local().get("x", 99.0))) < 0.6, "comma or period strafes onto the route")
	_release_all()
	_expect(await _walk_to(Vector2(0.0, -26.0), 15.0), "arrows walk to the confiscated Tack")
	_expect(await _until(func() -> bool: return current_scene.net_client.equipment.get("selected") == "tack", "walking claims the Tack"), "Tack claimed")
	# The guard: turn toward it with the arrows and fire with Ctrl.
	var shooter: String = str(current_scene.net_client.player_id)
	current_scene.net_client.snapshot_received.connect(func(data: Dictionary) -> void:
		for shot: Variant in data.get("shot_results", []):
			if shot is Dictionary and str(shot.get("shooter_id", "")) == shooter and shot.get("hit") == true:
				_shots_hit += 1
	)
	var deadline: int = Time.get_ticks_msec() + 45000
	var fired: int = 0
	var turned_by_key: bool = false
	while Time.get_ticks_msec() < deadline:
		var guard: Dictionary = _guard()
		if guard.is_empty() or float(guard.get("hp", 0.0)) <= 0.0 or float(_local().get("hp", 0.0)) <= 0.0:
			break
		var me: Dictionary = _local()
		var eye: Vector3 = Vector3(float(me["x"]), float(me["y"]) + 0.1, float(me["z"]))
		var goal: Vector2 = AimAssist.aim_at(eye, AimAssist.body_centre(Vector3(float(guard["x"]), float(guard["y"]), float(guard["z"]))))
		var error: float = _steer(goal.x)
		turned_by_key = turned_by_key or absf(error) > deg_to_rad(2.0)
		if not current_scene.camera.assist_pick.is_empty():
			_assist_engaged = true
		var aligned: bool = absf(error) < deg_to_rad(4.0)
		_hold(KEY_CTRL, aligned)
		if aligned:
			fired += 1
		# Close in if the guard is far and nothing stands in the way.
		_hold(KEY_UP, aligned and eye.distance_to(Vector3(float(guard["x"]), eye.y, float(guard["z"]))) > 9.0)
		await create_timer(0.03).timeout
	_release_all()
	var guard_state: Dictionary = _guard()
	_expect(float(_local().get("hp", 0.0)) > 0.0, "the keyboard player survives the guard")
	_expect(not guard_state.is_empty() and float(guard_state.get("hp", 1.0)) <= 0.0, "keys alone defeat the intake guard: " + str(guard_state.get("hp")))
	_expect(fired > 0 and turned_by_key and _shots_hit > 0, "Ctrl fired, the arrows turned toward the guard, and the server confirmed hits")
	_expect(_assist_engaged, "aim assist engaged for keyboard look")
	# Use: Enter reaches the wire as the same interact the server reads.
	var before: int = int(current_scene.input_seq)
	_key(KEY_ENTER, true)
	await process_frame
	_expect(current_scene.pending_interact or current_scene.interact_held, "Enter queues a use")
	await _until(func() -> bool: return int(current_scene.input_seq) > before + 2, "use is carried by the next paced send")
	_key(KEY_ENTER, false)
	print("test_keyboard_m01: guard down, %d aligned frames firing, %d confirmed hits" % [fired, _shots_hit])
	current_scene.pause_menu.leave_requested.emit()
	await _until(func() -> bool: return current_scene != null and current_scene.has_method("_start_campaign") and LocalMatch.for_tree(self).state == LocalMatch.State.IDLE, "leaving stops the owned server")
	# Let the retired match free its audio players before quitting.
	current_scene.queue_free()
	for _frame: int in range(4):
		await process_frame
	if failures == 0:
		print("test_keyboard_m01: PASS menus, walk, turn, fire and use by keyboard alone")
	quit(0 if failures == 0 else 1)
