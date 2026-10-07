extends SceneTree

## Bounded live input proof. Run against an isolated map7 Conquest server with
## zero bots. This records the actual viewport and never owns the desktop mouse.
var game: Node
var failures: Array[String] = []
var mounted_shots: int = 0
var directory: String
var report: Dictionary = {}

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("_run")

func _finalize() -> void:
	QaCombat.release_inputs()
	Input.action_release("jump")
	Input.action_release("duck")
	MouseCapture.release()

func _check(ok: bool, reason: String) -> bool:
	if not ok:
		failures.append(reason)
		push_error(reason)
	return ok

func _until(predicate: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func _run() -> void:
	var chosen_kind: String = OS.get_environment("FRAGR_VEHICLE_KIND")
	if chosen_kind not in ["boat", "light_aircraft"]:
		chosen_kind = "jeep"
	directory = ProjectSettings.globalize_path("res://../.agents/vehicle-live/" + chosen_kind).simplify_path()
	report["kind"] = chosen_kind
	report["display"] = DisplayServer.get_name()
	DirAccess.make_dir_recursive_absolute(directory)
	set_meta("fragr_settings_path", directory.path_join("settings.cfg"))
	set_meta("fragr_records_path", directory.path_join("records"))
	var preferences: FragrSettings = FragrSettings.new(directory.path_join("settings.cfg"))
	preferences.set_value("video", "display_mode", 0)
	preferences.save_to_disk()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/main.tscn")
	await _until(func() -> bool: return root.get_node_or_null("GameManager") != null, 10)
	game = root.find_child("GameManager", true, false)
	if not _check(game != null, "live vehicle: main scene has manager"):
		_finish()
		return
	if not _check(await _until(func() -> bool: return not game.latest_snapshot.is_empty(), 15), "live vehicle: server sends world"):
		_finish()
		return
	if not _check(int(game.current_map_info.get("map_id", 0)) == 7, "live vehicle: requires map7"):
		_finish()
		return
	if not _check(await _until(func() -> bool: return game.get_node_or_null("LoadingCard") == null and not game.controls_blocked(), 10), "live vehicle: spectator world revealed before Join"):
		_finish()
		return
	await game.change_role(true)
	if not _check(await _until(func() -> bool: return game.net_client.player_id != null and game.players.has(game.net_client.player_id) and game.latest_snapshot.get("round_state") == "Active", 45), "live vehicle: human admitted in active round"):
		_finish()
		return
	game.net_client.snapshot_received.connect(_shots)
	if not _check(await _until(func() -> bool: return game.get_node_or_null("LoadingCard") == null and not game.controls_blocked(), 10), "live vehicle: world reveal completes"):
		var loading: LoadingCard = game.get_node_or_null("LoadingCard") as LoadingCard
		report["blocked"] = {"loading": loading != null, "waiting_world": loading.waiting_for_world if loading != null else false, "loading_visible": loading.visible if loading != null else false, "loading_elapsed": loading._elapsed if loading != null else -1, "transition": game.role_transition, "awaiting_map": game._awaiting_map, "mission_blocked": game._mission_controls_blocked(), "pause": game.pause_menu.is_open(), "console": game.console.is_open(), "mouse_allowed": game.mouse_capture.gameplay_input_allowed()}
		_finish()
		return
	root.size = Vector2i(1280, 720)
	await create_timer(0.3).timeout
	await _capture("01-spawn.png")
	if chosen_kind in ["boat", "light_aircraft"]:
		await _transport(chosen_kind)
		_finish()
		return
	# The north service road passes behind both registered hangars.
	if not await _walk(Vector3(_feet().x, 3, -119)) or not await _walk(Vector3(0, 3, -119)) or not await _walk(Vector3(0, 3, -117.5)):
		_finish()
		return
	await _capture("02-entry.png")
	_tap("interact")
	if not _check(await _until(func() -> bool: return not game._vehicle_seat().is_empty(), 3), "live vehicle: normal Use enters registered jeep"):
		_finish()
		return
	_check(game._vehicle_seat() == "driver", "live vehicle: empty jeep chooses driver")
	game.camera.fp_yaw = 0.0
	game.camera.fp_pitch = -0.08
	await _capture("03-driver.png")
	var start: Vector3 = GrenadeFacts.vector(_occupied().vehicle.position)
	Input.action_press("move_forward")
	await create_timer(3.0).timeout
	Input.action_release("move_forward")
	Input.action_press("jump")
	await create_timer(1.2).timeout
	Input.action_release("jump")
	var occupied: Dictionary = _occupied()
	if not _check(not occupied.is_empty(), "live vehicle: driver remains seated"):
		_finish()
		return
	var travelled: float = start.distance_to(GrenadeFacts.vector(occupied.vehicle.position))
	_check(travelled > 10, "live vehicle: real throttle moves chassis more than10m")
	_check(absf(float(occupied.vehicle.speed)) < 0.1, "live vehicle: held jump brakes to rest")
	_check(not game.hud.fp_weapon.visible and not game.hud.crosshair.visible, "live vehicle: driver has no handheld weapon or reticle")
	report["travel_metres"] = travelled
	report["prediction_corrections"] = game.vehicle_prediction.correction_count
	report["prediction_max_metres"] = game.vehicle_prediction.correction_max
	report["prediction_fallbacks"] = game.vehicle_prediction.fallback_reasons.duplicate(true)
	await _capture("04-driven.png")
	_tap("weapon_next")
	if not _check(await _until(func() -> bool: return game._vehicle_seat() == "gunner", 3), "live vehicle: normal weapon cycle switches seat"):
		_finish()
		return
	await create_timer(0.6).timeout
	Input.action_press("fire")
	await create_timer(1.0).timeout
	Input.action_release("fire")
	_check(mounted_shots > 0, "live vehicle: gunner receives resolved mounted trace")
	_check(not game.hud.fp_weapon.visible and game.hud.crosshair.visible, "live vehicle: gunner shows mounted reticle with no handheld")
	report["mounted_shots"] = mounted_shots
	await _capture("05-gunner.png")
	_tap("interact")
	_check(await _until(func() -> bool: return game._vehicle_seat().is_empty(), 3), "live vehicle: safe Use exit returns on foot")
	await create_timer(0.3).timeout
	_check(game.vehicle_prediction.vehicle_id == 0, "live vehicle: exit clears driver replay")
	await _capture("06-exit.png")
	# Retained capture progress is exercised through ordinary walking.
	if await _walk(Vector3(0, 0, -70)):
		await create_timer(8.5).timeout
		var captured: bool = false
		for point: Dictionary in game.latest_snapshot.get("conquest", {}).get("points", []):
			if point.id == "airfield" and point.owner != null:
				captured = true
		_check(captured, "live conquest: standing at airfield captures through server ticks")
		await _capture("07-airfield.png")
	_finish()

func _transport(kind: String) -> void:
	var side: float = -1.0 if _feet().x < 0 else 1.0
	if kind == "boat":
		if not await _walk(Vector3(side * 70, 3, _feet().z)) or not await _walk(Vector3(side * 70, 3, 75)) or not await _walk(Vector3(side * 59.7, 2.2, 75)):
			return
	else:
		if not await _walk(Vector3(_feet().x, 3, -119)) or not await _walk(Vector3(7, 3, -119)) or not await _walk(Vector3(7, 3, -99.5)) or not await _walk(Vector3(0, 3, -99.5)):
			return
	await _capture(kind + "-02-entry.png")
	_tap("interact")
	if not _check(await _until(func() -> bool: return game._vehicle_kind() == kind and game._vehicle_seat() == "driver", 3), "live transport: normal Use boards " + kind):
		return
	game.camera.fp_yaw = float(_occupied().vehicle.yaw)
	game.camera.fp_pitch = -0.16
	await _capture(kind + "-03-driver.png")
	var before: Vector3 = GrenadeFacts.vector(_occupied().vehicle.position)
	Input.action_press("move_forward")
	if kind == "light_aircraft":
		Input.action_press("jump")
		await create_timer(3.4).timeout
		Input.action_release("jump")
	else:
		await create_timer(1.4).timeout
		Input.action_press("move_left" if side < 0 else "move_right")
		await create_timer(0.5).timeout
		Input.action_release("move_left")
		Input.action_release("move_right")
		await create_timer(1.1).timeout
	if not _check(not _occupied().is_empty(), "live transport: occupant retained through motion"):
		return
	var after: Vector3 = GrenadeFacts.vector(_occupied().vehicle.position)
	report["kind"] = kind
	report["travel_metres"] = before.distance_to(after)
	report["altitude_gain"] = after.y - before.y
	report["prediction_corrections"] = game.vehicle_prediction.correction_count
	report["prediction_max_metres"] = game.vehicle_prediction.correction_max
	report["prediction_fallbacks"] = game.vehicle_prediction.fallback_reasons.duplicate(true)
	_check(before.distance_to(after) > 10, "live transport: native motion travels more than10m")
	if kind == "light_aircraft":
		_check(after.y - before.y > 2, "live aircraft: held climb takes off above runway")
		await _capture(kind + "-04-flight.png")
		Input.action_press("duck")
		await create_timer(1.55).timeout
		Input.action_release("duck")
		_check(float(_occupied().vehicle.vy) < -1, "live aircraft: normal crouch input commands descent")
		await _capture(kind + "-05-descend.png")
		Input.action_release("move_forward")
		return
	Input.action_release("move_forward")
	Input.action_press("jump")
	await create_timer(1.4).timeout
	Input.action_release("jump")
	_check(absf(float(_occupied().vehicle.speed)) < 0.1, "live boat: held brake stops surface craft")
	await _capture(kind + "-04-water.png")
	_tap("weapon_next")
	if not _check(await _until(func() -> bool: return game._vehicle_seat() == "gunner", 3), "live boat: normal weapon cycle changes seat"):
		return
	await create_timer(0.6).timeout
	Input.action_press("fire")
	await create_timer(0.6).timeout
	Input.action_release("fire")
	_check(mounted_shots > 0, "live boat: mounted traces remain authoritative")
	await _capture(kind + "-05-gunner.png")
	_tap("interact")
	_check(await _until(func() -> bool: return game._vehicle_seat().is_empty(), 3), "live boat: safe exit enters registered swimming medium")
	await _capture(kind + "-06-swim.png")

func _feet() -> Vector3:
	for actor: Dictionary in game.latest_snapshot.get("players", []):
		if actor.id == game.net_client.player_id:
			return Vector3(actor.x, float(actor.y) - 1.5, actor.z)
	return Vector3.INF

func _occupied() -> Dictionary:
	return VehicleState.occupied(game.latest_snapshot, str(game.net_client.player_id))

func _walk(goal: Vector3) -> bool:
	var deadline: int = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		var at: Vector3 = _feet()
		if Vector2(at.x - goal.x, at.z - goal.z).length() < 0.28:
			Input.action_release("move_forward")
			await create_timer(0.12).timeout
			return true
		game.camera.fp_yaw = atan2(goal.z - at.z, goal.x - at.x)
		game.camera.fp_pitch = 0.0
		Input.action_press("move_forward")
		await create_timer(0.05).timeout
	Input.action_release("move_forward")
	return _check(false, "live vehicle: ordinary walk failed to reach " + str(goal) + " from " + str(_feet()))

func _tap(action: String) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func _shots(snapshot: Dictionary) -> void:
	for shot: Dictionary in snapshot.get("shot_results", []):
		if shot.get("shooter_id") == game.net_client.player_id and VehicleState.shot_vehicle(shot) > 0:
			mounted_shots += 1

func _capture(file: String) -> void:
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "live vehicle: desktop pointer stays visible")
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(directory.path_join(file)) == OK, "write viewport " + file)

func _finish() -> void:
	QaCombat.release_inputs()
	Input.action_release("jump")
	Input.action_release("duck")
	report["failures"] = failures
	report["passed"] = failures.is_empty()
	var file: FileAccess = FileAccess.open(directory.path_join("report-headless.json" if DisplayServer.get_name() == "headless" else "report-rendered.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("live vehicle: ", JSON.stringify(report))
	_shutdown.call_deferred()

func _shutdown() -> void:
	if game != null:
		game.net_client.leave_match()
		game.queue_free()
	await process_frame
	VehicleAudio._loops.clear()
	await process_frame
	quit(0 if failures.is_empty() else 1)
