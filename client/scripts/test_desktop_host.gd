extends SceneTree

const TOUR = preload("res://scripts/qa_tour.gd")

## Actual menu/native/socket ownership, separate from renderer or human fun.
var failures: int = 0
var peers: Array[Node] = []
var retiring_radio: Array[WeakRef] = []
var settings_path: String
var run_directory: String
var unrelated: TCPServer = TCPServer.new()

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://desktop-host-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	set_meta("fragr_records_path", "")
	run_directory = ProjectSettings.globalize_path("user://desktop-host-run-%d" % OS.get_process_id())
	OS.set_environment("FRAGR_RUN_DIR", run_directory)
	call_deferred("_run")

func _finalize() -> void:
	for peer: Node in peers:
		if is_instance_valid(peer):
			peer.leave_match()
			peer.free()
	var owner: LocalHost = root.get_node_or_null("LocalHost") as LocalHost if root != null else null
	if owner != null:
		owner.process.request_stop()
		owner.process.dispose()
	unrelated.stop()
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	OS.unset_environment("FRAGR_RUN_DIR")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_desktop_host: " + message)

func _until(condition: Callable, description: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 20000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = condition.call()
	_expect(passed, description)
	if not passed:
		quit(1)
	return passed

func _menu() -> bool:
	return current_scene != null and current_scene.has_method("_start_host")

func _remember_radio() -> bool:
	var radio: Node = current_scene.radio
	var player: AudioStreamPlayer = radio.player if radio != null else null
	var live: bool = player != null and player.stream is AudioStreamMP3 and player.has_stream_playback()
	_expect(live, "ordinary hosted gameplay has actual MP3 radio playback")
	if not live:
		quit(1)
		return false
	retiring_radio.append(weakref(player.get_stream_playback()))
	return true

func _radio_retired() -> bool:
	for playback: WeakRef in retiring_radio:
		if not TOUR.audio_reference_retired(playback):
			return false
	return true

func _await_radio_retirement() -> bool:
	var deadline: int = Time.get_ticks_msec() + 2000
	while not _radio_retired() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	var retired: bool = _radio_retired()
	_expect(retired, "ordinary gameplay exit retires every captured radio decoder within two seconds")
	if not retired:
		quit(1)
	return retired

func _playing(map_id: int) -> bool:
	return current_scene != null and current_scene.has_method("change_role") \
		and current_scene.current_map_id == map_id and not current_scene.latest_snapshot.is_empty()

func _peer(address: String, role: String, callsign: String) -> Node:
	var peer: Node = load("res://scripts/net_client.gd").new()
	root.add_child(peer)
	peers.append(peer)
	peer.set_server_host(address)
	peer.server_error.connect(func(message: String) -> void: _expect(false, "unexpected peer error: " + message))
	_expect(peer.connect_to_server(role, callsign), "second real socket starts")
	return peer

func _start(mode: String, bots: int, policy: String = "fixed", target: int = 0) -> LocalHost:
	await current_scene._show("host")
	current_scene._host_mode.select(1 if mode == "sabotage" else 0)
	current_scene._host_mode.item_selected.emit(current_scene._host_mode.selected)
	current_scene._host_bot_policy.select(["fixed", "none", "auto"].find(policy))
	current_scene._host_bot_policy.item_selected.emit(current_scene._host_bot_policy.selected)
	current_scene._host_bots.value = target if policy == "auto" else bots
	(current_scene._root.get_node("StartServer") as Button).pressed.emit()
	var owner: LocalHost = LocalHost.for_tree(self)
	if not await _until(func() -> bool: return owner.state == LocalHost.State.RUNNING, "actual native arena reaches validated readiness"):
		return null
	_expect(owner.process._pid > 0 and OS.is_process_running(owner.process._pid), "ready child has its owned live PID")
	_expect(current_scene._root.get_node_or_null("JoinHosted") != null, "real readiness enables host Join")
	return owner

func _preset(mode: String) -> bool:
	var owner: LocalHost = await _start(mode, 0, "none")
	if owner == null:
		return false
	var pid: int = owner.process._pid
	var address: String = owner.url
	var map_id: int = 4 if mode == "sabotage" else 1
	(current_scene._root.get_node("WatchHosted") as Button).pressed.emit()
	if not await _until(func() -> bool: return _playing(map_id), "Watch enters the real hosted map"):
		return false
	_expect(not current_scene.is_human_player and current_scene.local_match == null, "arena Watch has no campaign owner")
	var partner: Node = _peer(address, "human", "Peer")
	var snapshots: Array[Dictionary] = []
	partner.snapshot_received.connect(func(data: Dictionary) -> void:
		snapshots.clear()
		snapshots.append(data))
	if not await _until(func() -> bool: return partner.player_id != null and not snapshots.is_empty(), "second actual human receives welcome and snapshots"):
		return false
	current_scene.change_role(true)
	if not await _until(func() -> bool: return current_scene.net_client.player_id != null and current_scene.is_human_player, "watcher joins through normal human path"):
		return false
	var own_id: String = current_scene.net_client.player_id
	var partner_id: String = partner.player_id
	if not await _until(func() -> bool:
		var ids: Array[String] = []
		for pawn: Dictionary in snapshots.back().get("players", []):
			ids.append(pawn["id"])
		return own_id in ids and partner_id in ids, "both actual human pawns share one server snapshot"):
		return false
	_expect(partner.mission.is_empty() and current_scene.net_client.mission.is_empty(), "arena participants never receive campaign state")
	_expect(current_scene.current_map_info.get("rules", {}).get("mode") == mode, "authoritative map confirms selected mode")
	_expect(current_scene.pause_menu.hosting_server, "gameplay recognizes its persistent root owner")
	if mode == "sabotage":
		_expect(partner.equipment.get("selected") == "tack", "5v5 human starts with actual pistol loadout")
	# Close only this client's socket. The existing resume path must retain its pawn.
	var resumed: Array[bool] = []
	partner.session_resumed.connect(func() -> void: resumed.append(true))
	partner.socket.close()
	if not await _until(func() -> bool: return not resumed.is_empty() and partner.connection_state == WebSocketPeer.STATE_OPEN and partner.player_id == partner_id and not partner._resume_used, "ordinary dropped socket resumes the same pawn"):
		return false
	current_scene.change_role(false)
	if not await _until(func() -> bool: return not current_scene.is_human_player and current_scene.net_client.role == "spectator", "Leave returns the host to watching"):
		return false
	_expect(owner.state == LocalHost.State.RUNNING and OS.is_process_running(pid), "watch/leave preserves owned server")
	if not _remember_radio():
		return false
	current_scene.pause_menu.leave_requested.emit()
	if not await _until(_menu, "Exit to menu retires gameplay only"):
		return false
	if not await _await_radio_retirement():
		return false
	_expect(owner.state == LocalHost.State.RUNNING and OS.is_process_running(pid), "server survives menu return")
	_expect(partner.connection_state == WebSocketPeer.STATE_OPEN and partner.player_id == partner_id, "other human remains connected across host menu return")
	partner.leave_match()
	await current_scene._show("host")
	(current_scene._root.get_node("JoinHosted") as Button).pressed.emit()
	if not await _until(func() -> bool: return _playing(map_id) and current_scene.net_client.player_id != null, "host can rejoin its surviving server from menu"):
		return false
	if not _remember_radio():
		return false
	current_scene.pause_menu.stop_server_requested.emit()
	if not await _until(func() -> bool: return _menu() and owner.state == LocalHost.State.IDLE, "explicit match Stop returns to menu and ends owned lease"):
		return false
	if not await _await_radio_retirement():
		return false
	_expect(not OS.is_process_running(pid) and unrelated.is_listening(), "Stop retires only owned PID")
	print("test_desktop_host: owned_stop ", mode, " pid=", pid, " retired=", not OS.is_process_running(pid))
	_expect(not DirAccess.dir_exists_absolute(run_directory), "hosting creates no campaign directory or save")
	print("test_desktop_host: " + mode + " real two-client lifetime PASS")
	return true

func _automatic(mode: String) -> bool:
	var target: int = 10 if mode == "sabotage" else 4
	var owner: LocalHost = await _start(mode, 0, "auto", target)
	if owner == null:
		return false
	var pid: int = owner.process._pid
	_expect(owner.settings["bot_policy"] == "auto" and owner.settings["bots"] == 0
		and owner.settings["fill_target"] == target, "real automatic readiness retains the requested total target")
	var watcher: Node = _peer(owner.url, "spectator", "AutoWatch")
	var snapshots: Array[Dictionary] = []
	watcher.snapshot_received.connect(func(data: Dictionary) -> void:
		snapshots.clear()
		snapshots.append(data))
	if not await _until(func() -> bool:
		return not snapshots.is_empty() and snapshots.back().get("players", []).size() == target, "automatic server fills its actual initial roster"):
		return false
	var human: Node = _peer(owner.url, "human", "AutoHuman")
	var agent: Node = _peer(owner.url, "agent", "AutoAgent")
	var human_maps: Array[Dictionary] = []
	var agent_maps: Array[Dictionary] = []
	human.map_info_received.connect(func(data: Dictionary) -> void: human_maps.append(data))
	agent.map_info_received.connect(func(data: Dictionary) -> void: agent_maps.append(data))
	if not await _until(func() -> bool:
		return human.player_id != null and agent.player_id != null and not human_maps.is_empty() and not agent_maps.is_empty(), "automatic hosted room admits both actual human and external agent"):
		return false
	var human_id: String = human.player_id
	var agent_id: String = agent.player_id
	if not await _until(func() -> bool:
		var ids: Array[String] = []
		for pawn: Dictionary in snapshots.back().get("players", []):
			ids.append(pawn["id"])
		return ids.size() == target and human_id in ids and agent_id in ids, "both external participants replace filler bots in the same authoritative roster"):
		return false
	_expect(human_maps.back().get("rules", {}).get("mode") == mode
		and agent_maps.back().get("rules", {}).get("mode") == mode, "automatic participants receive the selected authoritative mode")
	human.leave_match()
	agent.leave_match()
	if not await _until(func() -> bool:
		var ids: Array[String] = []
		for pawn: Dictionary in snapshots.back().get("players", []):
			ids.append(pawn["id"])
		return ids.size() == target and human_id not in ids and agent_id not in ids, "automatic roster refills after explicit human and agent Leave"):
		return false
	watcher.leave_match()
	(current_scene._root.get_node("StopServer") as Button).pressed.emit()
	if not await _until(func() -> bool: return owner.state == LocalHost.State.IDLE, "automatic Host menu Stop retires its canonical lease"):
		return false
	_expect(not OS.is_process_running(pid) and unrelated.is_listening(), "automatic Stop retires only its owned PID")
	print("test_desktop_host: owned_stop auto_", mode, " pid=", pid, " retired=", not OS.is_process_running(pid))
	print("test_desktop_host: auto " + mode + " actual human and agent fill PASS")
	return true

func _run() -> void:
	_expect(unrelated.listen(0, "127.0.0.1") == OK, "unrelated listener starts")
	_expect(change_scene_to_file("res://scenes/boot_menu.tscn") == OK, "ordinary boot scene loads")
	await process_frame
	await process_frame
	for mode: String in ["tdm", "sabotage"]:
		if not await _preset(mode):
			return
		if not await _automatic(mode):
			return
	# A filled preset is watchable, while the server refuses an eleventh fighter.
	var owner: LocalHost = await _start("sabotage", 10)
	if owner == null:
		return
	var pid: int = owner.process._pid
	var rejected: Node = load("res://scripts/net_client.gd").new()
	root.add_child(rejected)
	peers.append(rejected)
	var errors: Array[String] = []
	rejected.server_error.connect(func(message: String) -> void: errors.append(message))
	rejected.set_server_host(owner.url)
	rejected.connect_to_server("human", "FullSeat")
	if not await _until(func() -> bool: return not errors.is_empty(), "filled 5v5 room refuses human through existing admission boundary"):
		return
	_expect(errors == [tr("SABOTAGE_MATCH_FULL")] and rejected.player_id == null, "full-room error is useful and takes no seat")
	(current_scene._root.get_node("WatchHosted") as Button).pressed.emit()
	if not await _until(func() -> bool: return _playing(4), "full 5v5 server still accepts spectator"):
		return
	if not _remember_radio():
		return
	current_scene.pause_menu.leave_requested.emit()
	if not await _until(_menu, "filled match leaves to menu"):
		return
	if not await _await_radio_retirement():
		return
	# Root-node retirement exercises the app-shutdown owner boundary with a real child.
	owner.queue_free()
	await process_frame
	await process_frame
	_expect(not OS.is_process_running(pid), "retiring app host owner closes and retires its native child")
	print("test_desktop_host: app_owner pid=", pid, " retired=", not OS.is_process_running(pid))
	_expect(unrelated.is_listening() and not DirAccess.dir_exists_absolute(run_directory), "app owner cleanup preserves unrelated listener and campaign storage")
	var campaign: LocalMatch = root.get_node_or_null("LocalMatch") as LocalMatch
	if campaign != null:
		campaign.queue_free()
	await process_frame
	for peer: Node in peers:
		if is_instance_valid(peer):
			peer.leave_match()
			peer.queue_free()
	peers.clear()
	await process_frame
	_expect(retiring_radio.size() == 5 and _radio_retired(), "all five actual hosted scene radio decoders are retired before quit")
	if failures == 0:
		print("test_desktop_host: five actual radio decoders retired PASS")
	if failures == 0:
		print("test_desktop_host: PASS")
	quit(0 if failures == 0 else 1)
