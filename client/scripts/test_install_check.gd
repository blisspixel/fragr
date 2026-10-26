extends SceneTree
## The install check must reach the real fragr-server through LocalMatch, and
## LocalMatch must attach even when requested while the root is adding children.

class MissingServer extends LocalMatch:
	func executable_path() -> String:
		return ""

class DiagnosticProcess extends LocalProcess:
	var calls: Array[String] = []
	var alive: bool = true
	func running() -> bool:
		return alive
	func drain_errors() -> void:
		calls.append("drain")
		_error_lines = ["synthetic hello_timeout diagnostic"]
	func diagnostics() -> String:
		calls.append("diagnostics")
		return super.diagnostics()
	func request_stop() -> void:
		calls.append("stop")
	func dispose() -> void:
		calls.append("dispose")
		alive = false
		super.dispose()

class WirePeer extends Node:
	signal map_info_received(info: Dictionary)
	signal snapshot_received(info: Dictionary)
	signal server_error(message: String)
	signal disconnected_from_server
	var leaves: int = 0
	func set_server_host(_address: String) -> void:
		pass
	func connect_to_server(_role: String, _callsign: String) -> bool:
		return true
	func leave_match() -> void:
		leaves += 1
		disconnected_from_server.emit()

class WireCheck extends InstallCheck:
	func _ready() -> void:
		set_process(false)
	func _create_arena_peer() -> Node:
		return WirePeer.new()

class RetirementProcess extends LocalProcess:
	var alive: bool = true
	var terminate_result: Error = OK
	var inspections: int = 0
	var terminations: int = 0
	func _init() -> void:
		_pid = 123
		retirement_confirmed = false
	func _owned_process_running() -> bool:
		inspections += 1
		return alive
	func _terminate_owned_process() -> Error:
		terminations += 1
		return terminate_result

class DropBeforeWelcome extends InstallCheck:
	var dropped: bool = false
	func _process(delta: float) -> void:
		if not dropped and _phase == "wire" and _preset == 1:
			dropped = true
			_peer.disconnect_from_server()
			return
		super._process(delta)

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_install_check: " + message)

func _run() -> void:
	_test_wire_loss()
	_test_retirement()
	_test_intentional_stop()
	_expect(InstallCheck._current_composition_error().is_empty(), "current named mesh, M12 copy, Arc surfaces/cues and actual Assessor construct from packaged resources")
	var saved: PackedScene = SpliceCharacter._packed[SpliceCharacter.SOURCE]
	SpliceCharacter._packed[SpliceCharacter.SOURCE] = null
	_expect(InstallCheck._current_composition_error().contains("Splice"), "rigid source availability is required outside the humanoid registry")
	SpliceCharacter._packed[SpliceCharacter.SOURCE] = saved
	var first: LocalMatch = LocalMatch.for_tree(self)
	_expect(LocalMatch.for_tree(self) == first, "a second request before attachment reuses the pending owner")
	await process_frame
	_expect(first.is_inside_tree() and root.get_node_or_null("LocalMatch") == first, "the owner attaches on the next frame")

	var results: Array[bool] = []
	var absent: MissingServer = MissingServer.new()
	var missing: InstallCheck = InstallCheck.new(absent)
	missing.quit_when_done = false
	missing.finished.connect(func(passed: bool) -> void: results.append(passed))
	root.add_child(missing)
	_expect(results == [false], "a missing server fails the check at once")
	missing.queue_free()
	absent.free()

	var run_dir: String = ProjectSettings.globalize_path("user://install-check-runs")
	DirAccess.make_dir_recursive_absolute(run_dir)
	OS.set_environment("FRAGR_RUN_DIR", run_dir)
	var check: InstallCheck = InstallCheck.new(first)
	check.quit_when_done = false
	check.finished.connect(func(passed: bool) -> void: results.append(passed))
	root.add_child(check)
	var deadline: int = Time.get_ticks_msec() + InstallCheck.TIMEOUT_MS + 2000
	while results.size() < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(results == [false, true], "the built server answers a run preview")
	check.queue_free()
	await process_frame
	# Force only the socket loss, while the second real child is still owned.
	# Cleanup must not query a PID Godot has already reaped during termination.
	var dropped: DropBeforeWelcome = DropBeforeWelcome.new(first)
	dropped.quit_when_done = false
	dropped.finished.connect(func(passed: bool) -> void: results.append(passed))
	root.add_child(dropped)
	deadline = Time.get_ticks_msec() + InstallCheck.TIMEOUT_MS + 2000
	while results.size() < 3 and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(dropped.dropped and results == [false, true, false], "real Sabotage socket loss fails before Welcome")
	_expect(dropped._host.process.retirement_confirmed and not dropped._owns_host,
		"failure confirms the actual owned child's retirement without a stale PID lookup")
	OS.unset_environment("FRAGR_RUN_DIR")
	DirAccess.remove_absolute(run_dir)
	first.stop()
	dropped.queue_free()
	await process_frame
	if failures == 0:
		print("test_install_check: PASS")
	quit(0 if failures == 0 else 1)

func _wire_fixture(local: LocalMatch, host: LocalHost) -> WireCheck:
	var check: WireCheck = WireCheck.new(local)
	check.quit_when_done = false
	check._host = host
	check._owns_host = true
	root.add_child(check)
	check._connect_arena()
	return check

func _test_wire_loss() -> void:
	# Synthetic transport failures use the production signal wiring and finish
	# path, without a real listener or an artificial wait for the timeout.
	for with_map: bool in [false, true]:
		var local: MissingServer = MissingServer.new()
		var host: LocalHost = LocalHost.new()
		var child: DiagnosticProcess = DiagnosticProcess.new()
		host.process = child
		host.state = LocalHost.State.RUNNING
		var check: WireCheck = _wire_fixture(local, host)
		check._preset = 1
		var results: Array[bool] = []
		check.finished.connect(func(passed: bool) -> void: results.append(passed))
		var peer: WirePeer = check._peer as WirePeer
		if with_map:
			peer.map_info_received.emit({"map_id": 4, "rules": {"mode": "sabotage"}})
		_expect(check._deadline > Time.get_ticks_msec(), "wire failure fixture precedes the unchanged timeout")
		peer.disconnected_from_server.emit()
		_expect(results == [false] and check._deadline == -1,
			"disconnect before Welcome or before Snapshot fails immediately")
		_expect(child.calls == ["drain", "diagnostics", "stop", "dispose"] and child._error_lines.is_empty(),
			"owned child diagnostics are drained and read before cleanup clears them")
		_expect(peer.leaves == 1 and not check._owns_host, "failure retires only the owned child and peer once")
		peer.disconnected_from_server.emit()
		_expect(results == [false], "late disconnect cannot emit a second result")
		check.free()
		host.free()
		local.free()

func _test_retirement() -> void:
	for alive: bool in [false, true]:
		var child: RetirementProcess = RetirementProcess.new()
		child.alive = alive
		child.dispose()
		_expect(child.retirement_confirmed and child._pid == -1 and child.retirement_error == OK,
			"observed exit or successful termination confirms owned retirement")
		_expect(child.inspections == 1 and child.terminations == (1 if alive else 0),
			"only a still-running owned child is terminated")
		child.dispose()
		_expect(not child.running() and child.inspections == 1 and child.terminations == (1 if alive else 0),
			"a retired PID is neither queried nor killed again")
	var child: RetirementProcess = RetirementProcess.new()
	child.terminate_result = ERR_UNAUTHORIZED
	child._error_lines = ["retained child diagnostic"]
	child.dispose()
	_expect(not child.retirement_confirmed and child.retirement_error == ERR_UNAUTHORIZED and child._pid == 123,
		"failed termination retains its owned PID and reports uncertainty")
	child.alive = false
	child.dispose()
	_expect(child.running() and child.inspections == 1 and child.terminations == 1
		and child._error_lines == ["retained child diagnostic"],
		"failed termination cannot become success through a lost native handle or a reused PID")
	_expect(not child.start("unused replacement", PackedStringArray()) and child._pid == 123,
		"an unconfirmed child prevents replacement without launching another process")
	var local: MissingServer = MissingServer.new()
	var host: LocalHost = LocalHost.new()
	host.process = child
	host.state = LocalHost.State.RUNNING
	var check: WireCheck = _wire_fixture(local, host)
	var results: Array[bool] = []
	check.finished.connect(func(passed: bool) -> void: results.append(passed))
	check._finish(true, "synthetic completed facts with failed retirement")
	_expect(results == [false] and check._owns_host and not child.retirement_confirmed,
		"unconfirmed retirement refuses an otherwise successful check and retains custody")
	check.free()
	host.free()
	local.free()

func _test_intentional_stop() -> void:
	# The same leave signal during successful Stop or explicit disposal is
	# intentional. Full wire facts still have to match before Stop begins.
	for complete: bool in [false, true]:
		var local: MissingServer = MissingServer.new()
		var host: LocalHost = LocalHost.new()
		var child: DiagnosticProcess = DiagnosticProcess.new()
		host.process = child
		host.state = LocalHost.State.RUNNING
		var check: WireCheck = _wire_fixture(local, host)
		var results: Array[bool] = []
		check.finished.connect(func(passed: bool) -> void: results.append(passed))
		var peer: WirePeer = check._peer as WirePeer
		if complete:
			peer.map_info_received.emit({"map_id": 1, "rules": {"mode": "tdm"}})
			peer.snapshot_received.emit({"map_id": 1})
			check._process(0)
			_expect(check._phase == "stopping" and child.calls == ["stop"], "matched wire facts reach the unchanged owned Stop path")
		else:
			check._close_peer()
		_expect(results.is_empty() and peer.leaves == 1, "intentional peer retirement is not a wire failure")
		check.free()
		host.free()
		local.free()
