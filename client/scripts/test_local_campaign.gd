extends SceneTree

var failures: int = 0
var settings_path: String
var captures: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://local-campaign-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	captures = OS.get_environment("FRAGR_LOCAL_QA_DIR")
	call_deferred("_run")

func _finalize() -> void:
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))

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
	await process_frame
	await _capture("single-player")
	var mission: Button = current_scene._root.get_node("RecallNotice") as Button
	_expect(not mission.disabled, "Recall Notice is selectable")
	mission.pressed.emit()
	if not await _until(_playing, "menu enters authoritative M01"):
		return
	var owned: LocalMatch = LocalMatch.for_tree(self)
	var pid: int = owned.process._pid
	var address: String = owned.url
	_expect(owned.state == LocalMatch.State.RUNNING and pid > 0, "live child is owned")
	_expect(current_scene.is_human_player and current_scene.net_client.server_url == address, "campaign joins as human at its selected endpoint")
	if not await _until(func() -> bool: return current_scene.get_node_or_null("LoadingCard") == null, "controls card dismisses into gameplay"):
		return
	await _capture("recall-notice-entry")
	current_scene.change_role(false)
	if not await _until(func() -> bool: return _playing() and not current_scene.role_transition and current_scene.net_client.role == "spectator", "role change reaches spectator"):
		return
	_expect(owned.process._pid == pid and owned.process.running(), "spectating retains the same child")
	current_scene.change_role(true)
	if not await _until(func() -> bool: return _playing() and not current_scene.role_transition and current_scene.net_client.role == "human", "player rejoins local mission"):
		return
	current_scene.pause_menu.leave_requested.emit()
	if not await _until(func() -> bool: return _menu() and owned.state == LocalMatch.State.IDLE, "Leave match returns to menu and stops owned server"):
		return
	_expect(not OS.is_process_running(pid), "owned child exits on leave")
	_expect(unrelated.is_listening(), "leaving preserves unrelated listeners")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "menu releases desktop pointer")
	await _capture("returned-menu")
	current_scene._start_campaign()
	if not await _until(_playing, "second launch reaches M01"):
		return
	pid = owned.process._pid
	_expect(OS.kill(pid) == OK, "simulate unexpected owned child exit")
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
	unrelated.stop()
	current_scene.queue_free()
	await process_frame
	await process_frame
	if failures == 0:
		print("test_local_campaign: PASS")
	quit(0 if failures == 0 else 1)
