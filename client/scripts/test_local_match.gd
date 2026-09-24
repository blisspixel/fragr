extends SceneTree

class FakeProcess extends LocalProcess:
	var alive: bool = false
	var starts: int = 0
	var stops: int = 0
	var killed: int = 0
	var output: PackedByteArray = PackedByteArray()
	var allowed: bool = true
	var expected: PackedStringArray = PackedStringArray(["--local-mission", "recall_notice", "--run-mode", "new", "--difficulty", "standard"])
	func start(_executable: String, arguments: PackedStringArray) -> bool:
		assert(arguments == expected)
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

const RECORD: String = '{"version":2,"mission":"recall_notice","difficulty":"standard","url":"ws://127.0.0.1:12345","gameplay_version":10}\n'
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
	_expect(not fixture.start_mission("standard", "invalid") and child.starts == starts, "invalid run mode cannot start a child")
	_development(fixture, child)
	var ready_preview: Dictionary = {"status": "ready", "difficulty": "severe", "attempt": 3, "continues": 1, "pending_continue": true}
	var parsed_preview: Dictionary = LocalMatch.parse_run_preview(JSON.stringify(ready_preview).to_ascii_buffer())
	_expect(parsed_preview.size() == 5 and parsed_preview.get("status") == "ready" and int(parsed_preview.get("attempt", 0)) == 3 and parsed_preview.get("pending_continue") == true, "bounded preview accepts a valid pending run")
	for patch: Dictionary in [{"attempt": 2}, {"continues": 0}, {"difficulty": "other"}, {"extra": 1}, {"pending_continue": 1}]:
		var bad_preview: Dictionary = ready_preview.duplicate()
		bad_preview.merge(patch, true)
		_expect(LocalMatch.parse_run_preview(JSON.stringify(bad_preview).to_ascii_buffer()).is_empty(), "preview rejects inconsistent state: " + str(patch))
	_expect(LocalMatch.parse_run_preview('{"status":"corrupt"}'.to_ascii_buffer()).get("status") == "corrupt", "preview distinguishes corrupt save")
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

## M02 is a development child: its own mission and capability, never a run mode.
func _development(fixture: Fixture, child: FakeProcess) -> void:
	var record: Dictionary = JSON.parse_string(RECORD)
	var m02: Dictionary = record.duplicate()
	m02["mission"] = "persons_unknown"
	m02["gameplay_version"] = 10
	var bytes: PackedByteArray = JSON.stringify(m02).to_ascii_buffer()
	_expect(not LocalMatch.readiness_url(bytes, "standard", "persons_unknown").is_empty(), "M02 readiness names its own contract")
	_expect(LocalMatch.readiness_url(bytes).is_empty(), "an M02 child cannot satisfy an M01 launch")
	_expect(LocalMatch.readiness_url(JSON.stringify(record).to_ascii_buffer(), "standard", "persons_unknown").is_empty(), "an M01 child cannot satisfy an M02 launch")
	var old: Dictionary = m02.duplicate()
	old["gameplay_version"] = 9
	_expect(LocalMatch.readiness_url(JSON.stringify(old).to_ascii_buffer(), "standard", "persons_unknown").is_empty(), "M02 requires the capability 10 ammunition contract")
	_expect(LocalMatch.readiness_url(bytes, "standard", "m03").is_empty(), "an unregistered mission fails closed")
	var starts: int = child.starts
	_expect(not fixture.start_mission("standard", "new", "persons_unknown") and child.starts == starts, "M02 refuses a run mode")
	_expect(not fixture.start_mission("standard", "", "recall_notice") and child.starts == starts, "M01 still requires a run mode")
	child.expected = PackedStringArray(["--local-mission", "persons_unknown", "--difficulty", "standard"])
	_expect(fixture.start_mission("standard", "", "persons_unknown") and child.starts == starts + 1 and fixture.mission == "persons_unknown", "M02 starts without a run mode")
	child.output = bytes + PackedByteArray([10])
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.RUNNING and fixture.url == "ws://127.0.0.1:12345", "M02 readiness completes the launch")
	child.alive = false
	fixture._process(0)
	_expect(fixture.error_key == "LOCAL_SERVER_STOPPED", "a stopped M02 child is reported")
	fixture.stop()
	child.expected = PackedStringArray(["--local-mission", "recall_notice", "--run-mode", "new", "--difficulty", "standard"])
