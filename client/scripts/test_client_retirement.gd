extends SceneTree

var _failures: int = 0
var _settings_path: String
var _playbacks: Array[WeakRef] = []
var _streams: Array[WeakRef] = []
var _quit_observed: bool = false
var _owned_pids: Array[int] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_records_path", "")
	_settings_path = "user://exit-retirement-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", _settings_path)
	OS.set_environment("FRAGR_SERVER", "127.0.0.1:1")
	OS.set_environment("FRAGR_RUN_DIR", ProjectSettings.globalize_path("user://exit-run-%d" % OS.get_process_id()))
	_run.call_deferred()

func _finalize() -> void:
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings_path))
	OS.unset_environment("FRAGR_RUN_DIR")
	if not _quit_observed:
		push_error("test_client_retirement: exit bypassed observed retirement")

func _expect(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error("test_client_retirement: " + message)

func _voice(parent: Node, kind: int) -> Node:
	var player: Node = AudioStreamPlayer.new() if kind == 0 else AudioStreamPlayer2D.new() if kind == 1 else AudioStreamPlayer3D.new()
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 22050
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 22050
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(22050)
	samples.fill(128)
	stream.data = samples
	parent.add_child(player)
	player.stream = stream
	_streams.append(weakref(stream))
	player.play()
	return player

func _remember_playback(player: Node) -> void:
	_expect(player.has_stream_playback(), "ordinary voice has active decoder")
	if player.has_stream_playback():
		_playbacks.append(weakref(player.get_stream_playback()))

func _all_released(references: Array[WeakRef]) -> bool:
	for reference: WeakRef in references:
		if reference.get_ref() != null:
			return false
	return true

func _run() -> void:
	var prefs: FragrSettings = FragrSettings.new(_settings_path)
	prefs.set_value("video", "display_mode", 0)
	_expect(prefs.save_to_disk() == OK, "isolated window settings saved")
	var owner: ClientRetirement = ClientRetirement.for_tree(self)
	_expect(ClientRetirement.for_tree(self) == owner, "ready-time calls share one pending owner")
	_expect(not auto_accept_quit, "window close follows resource retirement")
	var fixture: Node = Node.new()
	root.add_child(fixture)
	var voices: Array[Node] = []
	for kind: int in range(3):
		voices.append(_voice(fixture, kind))
	await physics_frame
	await process_frame
	for voice: Node in voices:
		_remember_playback(voice)
	# Only tree removal reports these decoders. The caller does not track them.
	fixture.queue_free()
	await process_frame
	_expect(await owner.drain(), "removed scene retires mixer decoders")
	_expect(_all_released(_playbacks) and _all_released(_streams), "all three voice kinds release both decoder and stream")
	_playbacks.clear()
	_streams.clear()
	# Replace skies and leave the real main scene before its first completed draw.
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game._apply_arena_sky("Launch Authority (development)")
	game._apply_arena_sky("Terms of Cooperation (development)")
	game._on_leave_requested()
	await process_frame
	_expect(await owner.drain(), "rapid main-scene return retires its pending skies")
	_expect(current_scene != null and current_scene.has_method("_start_campaign"), "ordinary leave reaches the menu")
	var mode: String = OS.get_environment("FRAGR_EXIT_CASE")
	if mode.is_empty():
		mode = "menu"
	if mode == "owned":
		current_scene._start_campaign("standard")
		var local: LocalMatch = LocalMatch.for_tree(self)
		var host: LocalHost = LocalHost.for_tree(self)
		_expect(host.start_host({"mode": "tdm", "map_id": 1, "bots": 0, "bot_policy": "none", "fill_target": 0, "lan": false, "port": 0}), "independent owned arena starts")
		var deadline: int = Time.get_ticks_msec() + 20000
		while (local.state != LocalMatch.State.RUNNING or host.state != LocalHost.State.RUNNING or not current_scene.has_method("change_role")) and Time.get_ticks_msec() < deadline:
			await process_frame
		_expect(local.state == LocalMatch.State.RUNNING and host.state == LocalHost.State.RUNNING, "both native children reach readiness")
		_owned_pids.append(local.process._pid)
		_owned_pids.append(host.process._pid)
		_expect(_owned_pids[0] > 0 and _owned_pids[1] > 0 and _owned_pids[0] != _owned_pids[1], "quit owns two distinct native processes")
	elif mode == "minimized":
		root.mode = Window.MODE_MINIMIZED
		await process_frame
		current_scene.queue_free()
		var pending_game: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(pending_game)
		current_scene = pending_game
		pending_game._apply_arena_sky("Launch Authority (development)")
		root.mode = Window.MODE_MINIMIZED
		await process_frame
		_expect(root.mode == Window.MODE_MINIMIZED, "close begins with an actually minimized window")
	var final_voice: Node = _voice(current_scene, 0)
	_remember_playback(final_voice)
	owner.quit_ready.connect(func(code: int) -> void:
		_quit_observed = true
		_expect(code == 0 and owner.drained(), "Quit waits for actual release")
		_expect(_all_released(_playbacks) and _all_released(_streams), "Quit releases current scene audio")
		_expect(current_scene == null, "Quit frees the current scene before engine shutdown")
		for pid: int in _owned_pids:
			_expect(not OS.is_process_running(pid), "Quit releases only its owned native child")
		if _failures == 0:
			print("test_client_retirement: PASS, removed voices, rapid sky changes and ", mode, " exit")
	)
	match mode:
		"menu":
			_press(current_scene, "Quit")
		"pause":
			var pause: PauseMenu = PauseMenu.new()
			pause.preferences = prefs
			current_scene.add_child(pause)
			_press(pause, "Quit to desktop")
		"console":
			var console: FragrConsole = FragrConsole.new()
			current_scene.add_child(console)
			console.run("quit")
		"window", "owned", "minimized":
			root.close_requested.emit()
		_:
			push_error("test_client_retirement: unknown exit case")
			owner.request_quit(1)
	# Repeated close notifications cannot start a second teardown.
	owner.request_quit()

func _press(parent: Node, label: String) -> void:
	for button: Node in parent.find_children("*", "Button", true, false):
		if str(button.text).to_lower() == label.to_lower():
			button.pressed.emit()
			return
	_expect(false, "ordinary exit button exists: " + label)
	ClientRetirement.for_tree(self).request_quit(1)
