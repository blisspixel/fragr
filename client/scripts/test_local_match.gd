extends SceneTree

class FakeProcess extends LocalProcess:
	var alive: bool = false
	var starts: int = 0
	var stops: int = 0
	var killed: int = 0
	var output: PackedByteArray = PackedByteArray()
	var allowed: bool = true
	func start(_executable: String, arguments: PackedStringArray) -> bool:
		assert(arguments == PackedStringArray(["--local-mission", "recall_notice", "--difficulty", "standard"]))
		starts += 1
		alive = allowed
		return allowed
	func running() -> bool:
		return alive
	func read_output() -> PackedByteArray:
		var bytes: PackedByteArray = output
		output = PackedByteArray()
		return bytes
	func drain_errors() -> void:
		pass
	func request_stop() -> void:
		stops += 1
	func dispose() -> void:
		if alive:
			killed += 1
		alive = false

class Fixture extends LocalMatch:
	var path: String = "fixture-server"
	func executable_path() -> String:
		return path

const RECORD: String = '{"version":2,"mission":"recall_notice","difficulty":"standard","url":"ws://127.0.0.1:12345","gameplay_version":8}\n'
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_local_match: " + message)

func _run() -> void:
	var fixture: Fixture = Fixture.new()
	var child: FakeProcess = FakeProcess.new()
	fixture.process = child
	var addresses: Array[String] = []
	fixture.mission_ready.connect(func(address: String) -> void: addresses.append(address))
	_expect(fixture.start_mission(), "first activation starts a child")
	_expect(not fixture.start_mission() and child.starts == 1, "repeated activation cannot start another child")
	child.output = RECORD.left(19).to_ascii_buffer()
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.STARTING and addresses.is_empty(), "partial record cannot launch gameplay")
	child.output = RECORD.substr(19).to_ascii_buffer()
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.RUNNING and addresses == ["ws://127.0.0.1:12345"], "complete validated record launches once")
	fixture.stop()
	_expect(fixture.state == LocalMatch.State.STOPPING and child.stops == 1, "stop requests graceful shutdown")
	fixture._deadline = 0
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.IDLE and child.killed == 1, "unresponsive owned child is disposed after deadline")
	fixture.start_mission()
	fixture.stop()
	child.output = RECORD.to_ascii_buffer()
	fixture._process(0)
	_expect(addresses.size() == 1, "late readiness after cancellation cannot enter gameplay")
	child.alive = false
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.IDLE, "normal cancellation settles idle")
	child.output.clear()
	fixture.start_mission()
	fixture._deadline = 0
	fixture._process(0)
	_expect(fixture.error_key == "LOCAL_SERVER_TIMEOUT" and child.stops == 3, "timeout stops only the owned process")
	child.alive = false
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.FAILED, "failure remains visible after cleanup")
	fixture.start_mission()
	child.output = RECORD.to_ascii_buffer()
	fixture._process(0)
	child.alive = false
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.FAILED and fixture.error_key == "LOCAL_SERVER_STOPPED", "unexpected live exit is visible")
	fixture.path = ""
	_expect(not fixture.start_mission() and fixture.error_key == "LOCAL_SERVER_MISSING", "missing binary never opens an external listener")
	fixture.path = "fixture-server"
	child.allowed = false
	_expect(not fixture.start_mission() and fixture.error_key == "LOCAL_SERVER_START_FAILED", "process creation failure is visible")
	child.allowed = true
	var oversized: PackedByteArray = PackedByteArray()
	oversized.resize(LocalMatch.MAX_READY_BYTES + 1)
	for payload: PackedByteArray in [oversized, (RECORD + "extra").to_ascii_buffer(), "garbage\n".to_ascii_buffer()]:
		fixture.start_mission()
		child.output = payload
		fixture._process(0)
		_expect(fixture.error_key == "LOCAL_SERVER_INVALID_READY", "invalid readiness fails closed")
		child.alive = false
		fixture._process(0)
	var record: Dictionary = JSON.parse_string(RECORD)
	for difficulty: String in MissionState.DIFFICULTIES:
		var chosen: Dictionary = record.duplicate()
		chosen["difficulty"] = difficulty
		_expect(not LocalMatch.readiness_url(JSON.stringify(chosen).to_ascii_buffer(), difficulty).is_empty(), "chosen difficulty is acknowledged")
		_expect(LocalMatch.readiness_url(JSON.stringify(chosen).to_ascii_buffer(), "invalid").is_empty(), "invalid selection fails closed")
	var wrong_tier: Dictionary = record.duplicate()
	wrong_tier["difficulty"] = "severe"
	_expect(LocalMatch.readiness_url(JSON.stringify(wrong_tier).to_ascii_buffer()).is_empty(), "child cannot silently select another tier")
	var starts: int = child.starts
	_expect(not fixture.start_mission("invalid") and child.starts == starts, "invalid tier cannot start a child")
	for patch: Dictionary in [{"version":true}, {"version":1.5}, {"mission":"calibration"}, {"extra":1},
		{"gameplay_version":4}, {"gameplay_version":5.5}, {"url":"ws://localhost:12345"}, {"url":"ws://127.0.0.1:0"},
		{"url":"ws://127.0.0.1:65536"}, {"url":"ws://127.0.0.1:0123"}, {"url":"ws://127.0.0.1:123/x"}, {"url":42}]:
		var bad: Dictionary = record.duplicate()
		bad.merge(patch, true)
		_expect(LocalMatch.readiness_url(JSON.stringify(bad).to_ascii_buffer()).is_empty(), "strict bootstrap contract: " + str(patch))
	fixture.free()
	if failures == 0:
		print("test_local_match: PASS")
	quit(0 if failures == 0 else 1)
