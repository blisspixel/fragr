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

const RECORD: String = '{"version":2,"mission":"recall_notice","difficulty":"standard","url":"ws://127.0.0.1:12345","gameplay_version":26}\n'
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_local_match: " + message)

func _run() -> void:
	var lunar_ready: Dictionary = {"version": 2, "mission": MissionState.M06_ID, "difficulty": "severe", "url": "ws://127.0.0.1:12345", "gameplay_version": 27}
	_expect(LocalMatch.readiness_url(JSON.stringify(lunar_ready).to_utf8_buffer(), "severe", MissionState.M06_ID, "") == "ws://127.0.0.1:12345", "lunar child readiness requires capability27")
	lunar_ready["gameplay_version"] = 26
	_expect(LocalMatch.readiness_url(JSON.stringify(lunar_ready).to_utf8_buffer(), "severe", MissionState.M06_ID, "").is_empty(), "old-capability executable cannot launch the lunar client")
	_expect(LocalMatch.parse_run_preview(JSON.stringify({"status": "awaiting_mission", "mission": MissionState.M06_ID, "difficulty": "severe", "continues": 0, "body": "synthetic"}).to_utf8_buffer()).get("continues") == 0, "pending episode preview reports its spent old allowance")
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
	_m03(fixture, child)
	_m04(fixture, child)
	var ready_preview: Dictionary = {"status": "ready", "mission": "recall_notice", "difficulty": "severe", "attempt": 3, "continues": 1, "pending_continue": true, "body": "synthetic"}
	var parsed_preview: Dictionary = LocalMatch.parse_run_preview(JSON.stringify(ready_preview).to_ascii_buffer())
	_expect(parsed_preview.size() == 7 and parsed_preview.get("status") == "ready" and int(parsed_preview.get("attempt", 0)) == 3 and parsed_preview.get("pending_continue") == true, "bounded preview accepts a valid pending run")
	for patch: Dictionary in [{"attempt": 2}, {"continues": 0}, {"difficulty": "other"}, {"extra": 1}, {"pending_continue": 1}, {"body": "robot"}, {"mission": "other"}]:
		var bad_preview: Dictionary = ready_preview.duplicate()
		bad_preview.merge(patch, true)
		_expect(LocalMatch.parse_run_preview(JSON.stringify(bad_preview).to_ascii_buffer()).is_empty(), "preview rejects inconsistent state: " + str(patch))
	var m02_preview: Dictionary = ready_preview.duplicate()
	m02_preview["mission"] = MissionState.M02_ID
	m02_preview["attempt"] = 1
	m02_preview["body"] = null
	_expect(LocalMatch.parse_run_preview(JSON.stringify(m02_preview).to_ascii_buffer()).get("mission") == MissionState.M02_ID, "M02 attempt resets while remaining continues carry")
	var awaiting: Dictionary = {"status": "awaiting_mission", "mission": MissionState.M02_ID, "difficulty": "severe", "continues": 1, "body": null}
	_expect(LocalMatch.parse_run_preview(JSON.stringify(awaiting).to_ascii_buffer()).get("mission") == MissionState.M02_ID, "M01 completion previews the pending M02 destination and unbound legacy body")
	awaiting["mission"] = MissionState.M03_ID
	_expect(LocalMatch.parse_run_preview(JSON.stringify(awaiting).to_ascii_buffer()).get("mission") == MissionState.M03_ID, "M02 completion previews the pending M03 destination")
	awaiting["mission"] = MissionState.M04_ID
	_expect(LocalMatch.parse_run_preview(JSON.stringify(awaiting).to_ascii_buffer()).get("mission") == MissionState.M04_ID, "M03 completion previews the available M04 destination")
	awaiting["mission"] = LocalMatch.NEXT_MISSION
	_expect(LocalMatch.parse_run_preview(JSON.stringify(awaiting).to_ascii_buffer()).get("mission") == LocalMatch.NEXT_MISSION, "M09 completion previews the unbuilt M10 destination")
	awaiting["mission"] = MissionState.M09_ID
	_expect(LocalMatch.parse_run_preview(JSON.stringify(awaiting).to_ascii_buffer()).get("mission") == MissionState.M09_ID, "M08 completion previews the playable berth")
	awaiting["mission"] = MissionState.M08_ID
	_expect(LocalMatch.parse_run_preview(JSON.stringify(awaiting).to_ascii_buffer()).get("mission") == MissionState.M08_ID, "M07 completion previews the playable M08 destination")
	m02_preview["mission"] = MissionState.M08_ID
	_expect(LocalMatch.parse_run_preview(JSON.stringify(m02_preview).to_ascii_buffer()).get("mission") == MissionState.M08_ID, "M08 entry is a valid saved resume")
	m02_preview["mission"] = LocalMatch.NEXT_MISSION
	_expect(LocalMatch.parse_run_preview(JSON.stringify(m02_preview).to_ascii_buffer()).is_empty(), "M10 cannot claim a playable saved entry")
	m02_preview["mission"] = MissionState.M09_ID
	_expect(LocalMatch.parse_run_preview(JSON.stringify(m02_preview).to_ascii_buffer()).get("mission") == MissionState.M09_ID, "M09 accepts its supported saved entry")
	m02_preview["mission"] = MissionState.M03_ID
	_expect(LocalMatch.parse_run_preview(JSON.stringify(m02_preview).to_ascii_buffer()).get("mission") == MissionState.M03_ID, "ready M03 resets its attempt without refilling the allowance")
	m02_preview["mission"] = MissionState.M04_ID
	_expect(LocalMatch.parse_run_preview(JSON.stringify(m02_preview).to_ascii_buffer()).get("mission") == MissionState.M04_ID, "ready M04 retains the same level allowance")
	awaiting["mission"] = "other"
	_expect(LocalMatch.parse_run_preview(JSON.stringify(awaiting).to_ascii_buffer()).is_empty(), "unknown pending destination is rejected")
	_expect(LocalMatch.parse_run_preview('{"status":"corrupt"}'.to_ascii_buffer()).get("status") == "corrupt", "preview distinguishes corrupt save")
	for patch: Dictionary in [{"version":true}, {"version":1.5}, {"mission":"calibration"}, {"extra":1},
		{"gameplay_version":4}, {"gameplay_version":5.5}, {"gameplay_version":10}, {"gameplay_version":11}, {"url":"ws://localhost:12345"}, {"url":"ws://127.0.0.1:0"},
		{"url":"ws://127.0.0.1:65536"}, {"url":"ws://127.0.0.1:0123"}, {"url":"ws://127.0.0.1:123/x"}, {"url":42}]:
		var bad: Dictionary = record.duplicate()
		bad.merge(patch, true)
		_expect(LocalMatch.readiness_url(JSON.stringify(bad).to_ascii_buffer()).is_empty(), "strict bootstrap contract: " + str(patch))
	fixture.free()
	if failures == 0:
		print("test_local_match: PASS")
	quit(0 if failures == 0 else 1)

## M02 development and durable resume use distinct bootstrap capabilities.
func _development(fixture: Fixture, child: FakeProcess) -> void:
	var record: Dictionary = JSON.parse_string(RECORD)
	var m02: Dictionary = record.duplicate()
	m02["mission"] = "persons_unknown"
	m02["gameplay_version"] = 26
	var bytes: PackedByteArray = JSON.stringify(m02).to_ascii_buffer()
	_expect(not LocalMatch.readiness_url(bytes, "standard", "persons_unknown", "").is_empty(), "development M02 readiness names its own contract")
	_expect(LocalMatch.readiness_url(bytes).is_empty(), "an M02 child cannot satisfy an M01 launch")
	_expect(LocalMatch.readiness_url(JSON.stringify(record).to_ascii_buffer(), "standard", "persons_unknown", "").is_empty(), "an M01 child cannot satisfy an M02 launch")
	var old: Dictionary = m02.duplicate()
	old["gameplay_version"] = 20
	_expect(LocalMatch.readiness_url(JSON.stringify(old).to_ascii_buffer(), "standard", "persons_unknown", "").is_empty(), "development M02 requires the capability 26 contract")
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
	var durable: Dictionary = m02.duplicate()
	durable["gameplay_version"] = 26
	child.expected = PackedStringArray(["--local-mission", "persons_unknown", "--run-mode", "resume", "--difficulty", "standard"])
	_expect(fixture.start_mission("standard", "resume", "persons_unknown"), "saved M02 resumes as a durable child")
	child.output = JSON.stringify(durable).to_ascii_buffer() + PackedByteArray([10])
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.RUNNING and fixture.has_durable_run(), "durable M02 requires capability 26")
	_expect(not LocalMatch.readiness_url(bytes, "standard", "persons_unknown", "resume").is_empty(),
		"both M02 launch modes use the same capability 26 readiness envelope")
	child.alive = false
	fixture._process(0)
	fixture.stop()
	child.expected = PackedStringArray(["--local-mission", "recall_notice", "--run-mode", "new", "--difficulty", "standard"])

func _m03(fixture: Fixture, child: FakeProcess) -> void:
	var ready: Dictionary = {"version": 2, "mission": MissionState.M03_ID, "difficulty": "standard", "url": "ws://127.0.0.1:12345", "gameplay_version": 26}
	for version: int in [18, 22, 23, 24, 25, 27]:
		var bad: Dictionary = ready.duplicate()
		bad["gameplay_version"] = version
		_expect(LocalMatch.readiness_url(JSON.stringify(bad).to_ascii_buffer(), "standard", MissionState.M03_ID, "").is_empty(), "M03 requires exact capability 26")
	var starts: int = child.starts
	_expect(not fixture.start_mission("standard", "new", MissionState.M03_ID) and child.starts == starts,
		"standalone M03 cannot create or overwrite a personal campaign run")
	child.expected = PackedStringArray(["--local-mission", MissionState.M03_ID, "--difficulty", "standard"])
	_expect(fixture.start_mission("standard", "", MissionState.M03_ID), "development M03 starts through the owned local child")
	child.output = JSON.stringify(ready).to_ascii_buffer() + PackedByteArray([10])
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.RUNNING and not fixture.has_durable_run(), "development M03 readiness creates no durable run")
	fixture.stop()
	child.alive = false
	fixture._process(0)
	child.expected = PackedStringArray(["--local-mission", MissionState.M03_ID, "--run-mode", "resume", "--difficulty", "standard"])
	_expect(fixture.start_mission("standard", "resume", MissionState.M03_ID), "saved M03 uses the existing resume mode")
	child.output = JSON.stringify(ready).to_ascii_buffer() + PackedByteArray([10])
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.RUNNING and fixture.has_durable_run(), "durable M03 also binds exact capability 26")
	fixture.stop()
	child.alive = false
	fixture._process(0)
	child.expected = PackedStringArray(["--local-mission", "recall_notice", "--run-mode", "new", "--difficulty", "standard"])

func _m04(fixture: Fixture, child: FakeProcess) -> void:
	var ready: Dictionary = {"version": 2, "mission": MissionState.M04_ID, "difficulty": "standard", "url": "ws://127.0.0.1:12345", "gameplay_version": 26}
	for version: int in [18, 22, 23, 24, 25, 27]:
		var bad: Dictionary = ready.duplicate()
		bad["gameplay_version"] = version
		_expect(LocalMatch.readiness_url(JSON.stringify(bad).to_ascii_buffer(), "standard", MissionState.M04_ID, "").is_empty(), "M04 requires exact capability 26")
	var starts: int = child.starts
	_expect(not fixture.start_mission("standard", "new", MissionState.M04_ID) and child.starts == starts,
		"standalone M04 cannot create or overwrite a personal campaign run")
	child.expected = PackedStringArray(["--local-mission", MissionState.M04_ID, "--difficulty", "standard"])
	_expect(fixture.start_mission("standard", "", MissionState.M04_ID), "development M04 starts through the owned local child")
	child.output = JSON.stringify(ready).to_ascii_buffer() + PackedByteArray([10])
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.RUNNING and not fixture.has_durable_run(), "development M04 readiness creates no durable run")
	fixture.stop()
	child.alive = false
	fixture._process(0)
	child.expected = PackedStringArray(["--local-mission", MissionState.M04_ID, "--run-mode", "resume", "--difficulty", "standard"])
	_expect(fixture.start_mission("standard", "resume", MissionState.M04_ID), "saved M04 uses the existing resume mode")
	child.output = JSON.stringify(ready).to_ascii_buffer() + PackedByteArray([10])
	fixture._process(0)
	_expect(fixture.state == LocalMatch.State.RUNNING and fixture.has_durable_run(), "durable M04 also binds exact capability 26")
	fixture.stop()
	child.alive = false
	fixture._process(0)
	child.expected = PackedStringArray(["--local-mission", "recall_notice", "--run-mode", "new", "--difficulty", "standard"])
