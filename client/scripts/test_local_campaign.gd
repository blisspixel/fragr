extends SceneTree

var failures: int = 0
var settings_path: String
var captures: String
var run_directory: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://local-campaign-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	run_directory = ProjectSettings.globalize_path("user://local-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	captures = OS.get_environment("FRAGR_LOCAL_QA_DIR")
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
		push_error("test_local_campaign: " + message)

func _until(condition: Callable, description: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 20000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	_expect(passed, description)
	if not passed:
		quit(1)
	return passed

func _playing() -> bool:
	return current_scene != null and current_scene.has_method("change_role") \
		and current_scene.current_map_id == 1001 and not current_scene.latest_snapshot.is_empty() \
		and not current_scene.mission_hud.state.is_empty()

func _menu() -> bool:
	return current_scene != null and current_scene.has_method("_start_campaign")

func _local_pawn() -> Dictionary:
	for player: Dictionary in current_scene.latest_snapshot.get("players", []):
		if player.get("id") == current_scene.net_client.player_id:
			return player
	return {}

func _crash(pid: int) -> bool:
	if OS.get_name() == "Windows":
		return OS.kill(pid) == OK
	# Godot's Unix kill also waits for the child. An external signal leaves the
	# exit to the actual owner, as a crash would, instead of stealing its wait.
	return OS.execute("/bin/kill", PackedStringArray(["-KILL", str(pid)])) == 0

func _capture(filename: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_expect(DirAccess.make_dir_recursive_absolute(captures) == OK, "capture directory created")
	_expect(root.get_texture().get_image().save_png(captures.path_join(filename + ".png")) == OK, "capture saved")

func _run() -> void:
	var prefs: FragrSettings = FragrSettings.new(settings_path)
	prefs.set_value("video", "display_mode", 0)
	_expect(prefs.save_to_disk() == OK, "isolated preferences saved")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 960)
	var unrelated: TCPServer = TCPServer.new()
	_expect(unrelated.listen(0, "127.0.0.1") == OK, "unrelated listener starts")
	_expect(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "boot menu loads")
	await process_frame
	await process_frame
	current_scene._show("single")
	if not await _until(func() -> bool: return LocalMatch.for_tree(self).run_preview.get("status") == "missing", "isolated campaign run starts without a save"):
		return
	await process_frame
	await _capture("single-player")
	var mission: Button = current_scene._root.get_node("RecallNotice") as Button
	_expect(not mission.disabled, "Recall Notice is selectable")
	mission.pressed.emit()
	await process_frame
	await process_frame
	_expect(current_scene._page == "difficulty" and LocalMatch.for_tree(self).state == LocalMatch.State.IDLE, "mission choice opens difficulty without launching")
	_expect(root.gui_get_focus_owner().name == "Difficulty_standard", "original pressure is the initial keyboard choice")
	await _capture("difficulty")
	var severe: Button = current_scene._root.get_node("Difficulty_severe") as Button
	severe.pressed.emit()
	if not await _until(_playing, "menu enters authoritative M01"):
		return
	var owned: LocalMatch = LocalMatch.for_tree(self)
	var pid: int = owned.process._pid
	var address: String = owned.url
	_expect(owned.state == LocalMatch.State.RUNNING and pid > 0, "live child is owned")
	_expect(current_scene.is_human_player and current_scene.net_client.server_url == address, "campaign joins as human at its selected endpoint")
	if not await _until(func() -> bool: return is_instance_valid(current_scene.opening), "campaign opening appears before combat"):
		return
	_expect(current_scene.get_node_or_null("LoadingCard") == null and current_scene.controls_blocked(), "campaign replaces timed controls card and blocks play")
	_expect(current_scene.mission_hud.state["phase"] == "briefing", "server waits for the reader")
	var rules: Dictionary = current_scene.mission_hud.state["rules"]
	_expect(rules["difficulty"] == "severe" and rules["revision"] == 1, "menu selection reaches authoritative mission rules: " + str(rules))
	var partner: Node = load("res://scripts/net_client.gd").new()
	root.add_child(partner)
	partner.set_server_host(address)
	partner.connect_to_server("spectator", "Observer")
	if not await _until(func() -> bool: return partner.mission.get("state", {}).get("party", []).size() == 1, "spectator observes the solo briefing without taking a seat"):
		return
	_expect(partner.player_id == null and current_scene.mission_hud.state["run"]["continues"] == 3, "local campaign is a solo run with three continues")
	for page: int in range(CampaignOpening.BEATS.size()):
		_expect(partner.mission["state"]["rules"] == current_scene.mission_hud.state["rules"], "agent and human share host difficulty")
		await _capture("opening-%d" % (page + 1))
		if page < CampaignOpening.BEATS.size() - 1:
			current_scene.opening.advance()
	var dismiss: InputEventKey = InputEventKey.new()
	dismiss.keycode = KEY_ESCAPE
	dismiss.physical_keycode = KEY_ESCAPE
	dismiss.pressed = true
	Input.parse_input_event(dismiss)
	await process_frame
	_expect(not is_instance_valid(current_scene.opening) and current_scene.controls_blocked(), "dismissal stays blocked until release")
	_expect(not current_scene.pause_menu.is_open(), "intro Escape cannot also open the match menu")
	dismiss = dismiss.duplicate()
	dismiss.pressed = false
	Input.parse_input_event(dismiss)
	if not await _until(func() -> bool:
		for member: Dictionary in current_scene.mission_hud.state["party"]:
			if member["id"] == current_scene.net_client.player_id:
				return member["ready"]
		return false, "server confirms first reader independently"):
		return
	_expect(not partner.send_mission_ready(), "spectator cannot hold or acknowledge a solo briefing")
	if not await _until(func() -> bool: return not current_scene.controls_blocked() and current_scene._has_local_input_target(), "readiness enters first-person play"):
		return
	_expect(current_scene.mission_hud.state["phase"] == "find_transfer", "server confirms active mission")
	_expect(not current_scene.pending_jump and not current_scene.pending_interact and not current_scene.pending_reload, "intro leaves no queued gameplay press")
	var first_map: Dictionary = current_scene.current_map_info.duplicate(true)
	current_scene._on_map_info(first_map)
	_expect(not is_instance_valid(current_scene.opening) and current_scene._opening_finished, "a repeated mission map does not replay the story")
	var side: String = "move_left" if float(_local_pawn().get("x", 0.0)) < 0.0 else "move_right"
	Input.action_press(side)
	var centered: bool = await _until(func() -> bool: return absf(float(_local_pawn().get("x", 99.0))) < 0.6, "player centers on the pistol route")
	Input.action_release(side)
	if not centered:
		return
	Input.action_press("move_forward")
	var found_pistol: bool = await _until(func() -> bool: return current_scene.net_client.equipment.get("selected") == "tack", "walking from entry claims the pistol on the live server")
	Input.action_release("move_forward")
	if not found_pistol:
		return
	var fists_key: InputEventKey = InputEventKey.new()
	fists_key.keycode = KEY_1
	fists_key.physical_keycode = KEY_1
	fists_key.pressed = true
	Input.parse_input_event(fists_key)
	await process_frame
	fists_key = fists_key.duplicate()
	fists_key.pressed = false
	Input.parse_input_event(fists_key)
	if not await _until(func() -> bool: return current_scene.net_client.equipment.get("selected") == "fists", "key 1 selects fists in the authoritative M01 loadout"):
		return
	if not await _until(func() -> bool: return _local_pawn().get("weapon") == "Fists", "public snapshot agrees with private fists selection"):
		return
	partner.disconnect_from_server()
	partner.free()
	await _capture("recall-notice-entry")
	var original_run_id: String = str(current_scene.mission_hud.state["run"]["id"])
	current_scene.change_role(false)
	await process_frame
	_expect(current_scene.is_human_player and current_scene.net_client.role == "human", "solo owner cannot switch role inside the same run")
	var rejected: Node = load("res://scripts/net_client.gd").new()
	root.add_child(rejected)
	var errors: Array[String] = []
	rejected.server_error.connect(func(message: String) -> void: errors.append(message))
	rejected.set_server_host(address)
	rejected.connect_to_server("agent", "Replacement")
	if not await _until(func() -> bool: return not errors.is_empty(), "a new connection cannot reclaim the lifetime run seat"):
		return
	_expect(rejected.player_id == null and errors[0] == tr("RUN_SEAT_CLOSED"), "run rejection is localized and leaves no player")
	rejected.free()
	current_scene.pause_menu.leave_requested.emit()
	if not await _until(func() -> bool: return _menu() and owned.state == LocalMatch.State.IDLE, "Exit to menu stops the owned server"):
		return
	_expect(not OS.is_process_running(pid), "owned child exits on menu return")
	_expect(unrelated.is_listening(), "leaving preserves unrelated listeners")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "menu releases desktop pointer")
	await _capture("returned-menu")
	current_scene._show("single")
	if not await _until(func() -> bool: return owned.run_preview.get("status") == "ready", "menu previews the saved run"):
		return
	_expect(owned.run_preview["difficulty"] == "severe" and int(owned.run_preview["continues"]) == 3, "menu retains difficulty and allowance")
	current_scene._start_campaign_resume()
	if not await _until(_playing, "Continue Run reopens M01"):
		return
	_expect(str(current_scene.mission_hud.state["run"]["id"]) == original_run_id, "resume preserves the run ID")
	_expect(not is_instance_valid(current_scene.opening), "resume does not replay the opening")
	if not await _until(func() -> bool: return current_scene.mission_hud.state.get("phase") == "find_transfer", "resumed briefing acknowledges once"):
		return
	current_scene.pause_menu.leave_requested.emit()
	if not await _until(func() -> bool: return _menu() and owned.state == LocalMatch.State.IDLE, "resumed run returns to menu"):
		return
	current_scene._start_campaign("assisted")
	if not await _until(_playing, "second launch reaches M01"):
		return
	_expect(current_scene.mission_hud.state["rules"]["difficulty"] == "assisted", "a new server can select another tier")
	pid = owned.process._pid
	_expect(_crash(pid), "simulate unexpected owned child exit")
	if not await _until(func() -> bool: return _menu() and owned.state in [LocalMatch.State.IDLE, LocalMatch.State.FAILED], "unexpected exit returns to menu"):
		return
	_expect(owned.error_key == "LOCAL_SERVER_STOPPED", "failure remains visible after scene change")
	await _capture("stopped-server")
	current_scene._start_campaign()
	pid = owned.process._pid
	current_scene._cancel_campaign()
	if not await _until(func() -> bool: return owned.state == LocalMatch.State.IDLE, "cancelled startup finishes cleanup"):
		return
	_expect(_menu() and not OS.is_process_running(pid), "cancel does not enter a late-ready match or leave a child")
	_expect(unrelated.is_listening(), "failure and cancellation preserve unrelated listener")
	var leased: LocalProcess = LocalProcess.new()
	_expect(leased.start(owned.executable_path(), PackedStringArray(["--local-mission", "recall_notice"])), "native pipe lease starts")
	var output: PackedByteArray = PackedByteArray()
	if not await _until(func() -> bool:
		leased.drain_errors()
		output.append_array(leased.read_output())
		return output.find(10) >= 0, "native pipe lease reaches readiness"):
		leased.dispose()
		return
	leased._stdio.close()
	if not await _until(func() -> bool: return not leased.running(), "closing Godot's pipe ends the child without a shutdown command"):
		leased.dispose()
		return
	leased.dispose()
	_expect(not leased.running(), "an observed exit remains retired during repeated cleanup")
	unrelated.stop()
	current_scene.queue_free()
	await process_frame
	await process_frame
	if failures == 0:
		print("test_local_campaign: PASS")
	quit(0 if failures == 0 else 1)
