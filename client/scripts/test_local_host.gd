extends SceneTree

class FakeProcess extends LocalProcess:
	var alive: bool = false
	var allowed: bool = true
	var starts: int = 0
	var stops: int = 0
	var killed: int = 0
	var arguments: PackedStringArray = PackedStringArray()
	var output: PackedByteArray = PackedByteArray()
	func start(_executable: String, args: PackedStringArray) -> bool:
		arguments = args
		output.clear()
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

class Fixture extends LocalHost:
	var path: String = "fixture-native"
	func executable_path() -> String:
		return path

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_local_host: " + message)

func _config(lan: bool = false, sabotage: bool = false, policy: String = "fixed") -> Dictionary:
	return {"mode": "sabotage" if sabotage else "tdm", "map_id": 4, "bots": 4 if policy == "fixed" else 0,
		"bot_policy": policy, "fill_target": 4 if policy == "auto" else 0,
		"lan": lan, "port": 6767 if lan else 0}

func _ready_record(config: Dictionary) -> Dictionary:
	var port: int = 6767 if config["lan"] else 32123
	return {"version": 1, "kind": "arena", "url": "ws://127.0.0.1:" + str(port),
		"listen": ("0.0.0.0" if config["lan"] else "127.0.0.1") + ":" + str(port),
		"map_id": config["map_id"], "mode": config["mode"], "five_vs_five": config["mode"] == "sabotage",
		"bots": config["bots"], "bot_policy": config["bot_policy"], "fill_target": config["fill_target"], "gameplay_version": 37}

func _run() -> void:
	for policy: String in ["fixed", "none", "auto"]:
		for lan: bool in [false, true]:
			for sabotage: bool in [false, true]:
				_test_profile(_config(lan, sabotage, policy))
	var zero: Dictionary = _config()
	zero["bots"] = 0
	_check(LocalHost.valid_settings(zero), "fixed zero remains compatible")
	_test_profile(zero)
	for policy: String in ["none", "auto"]:
		var contradictory: Dictionary = _config(false, false, policy)
		contradictory["bots"] = 1
		_check(not LocalHost.valid_settings(contradictory), "non-fixed policy refuses a fixed bot count")
	var automatic: Dictionary = _config(false, false, "auto")
	for invalid_target: Variant in [0, 11, -1, 1.5, true, "4"]:
		var invalid: Dictionary = automatic.duplicate()
		invalid["fill_target"] = invalid_target
		_check(not LocalHost.valid_settings(invalid), "automatic target must be a bounded positive integer")
	for target: int in [1, 10]:
		automatic["fill_target"] = target
		_test_profile(automatic)
	for policy: String in ["fixed", "none"]:
		var contradictory: Dictionary = _config(false, false, policy)
		contradictory["fill_target"] = 1
		_check(not LocalHost.valid_settings(contradictory), "inactive automatic target must be zero")
	var config: Dictionary = _config()
	for item: Dictionary in [{"key": "mode", "value": "ffa"}, {"key": "bots", "value": 11},
		{"key": "bots", "value": -1}, {"key": "map_id", "value": 7}, {"key": "port", "value": 6767},
		{"key": "lan", "value": "true"}, {"key": "bots", "value": 2.5}, {"key": "extra", "value": true},
		{"key": "bot_policy", "value": "adaptive"}, {"key": "bot_policy", "value": true},
		{"key": "fill_target", "value": true}]:
		var invalid: Dictionary = config.duplicate()
		invalid[item["key"]] = item["value"]
		_check(not LocalHost.valid_settings(invalid) and LocalHost.arguments_for(invalid).is_empty(),
			"refuse malformed settings before process creation")
	for field: String in config:
		var missing: Dictionary = config.duplicate()
		missing.erase(field)
		_check(not LocalHost.valid_settings(missing), "all seven settings fields are required")
	var wrong_sabotage: Dictionary = _config(false, true)
	wrong_sabotage["map_id"] = 1
	_check(not LocalHost.valid_settings(wrong_sabotage), "Sabotage requires existing site map")
	var record: Dictionary = _ready_record(config)
	for item: Dictionary in [{"key": "version", "value": 2}, {"key": "kind", "value": "campaign"},
		{"key": "url", "value": "ws://0.0.0.0:32123"}, {"key": "url", "value": "wss://127.0.0.1:32123"},
		{"key": "listen", "value": "0.0.0.0:32123"}, {"key": "map_id", "value": 1},
		{"key": "mode", "value": "sabotage"}, {"key": "five_vs_five", "value": 1},
		{"key": "five_vs_five", "value": true}, {"key": "bots", "value": 5},
		{"key": "bot_policy", "value": "auto"}, {"key": "bot_policy", "value": true},
		{"key": "fill_target", "value": 1}, {"key": "fill_target", "value": true}, {"key": "fill_target", "value": 1.5},
		{"key": "gameplay_version", "value": 35}, {"key": "extra", "value": true}]:
		var forged: Dictionary = record.duplicate()
		forged[item["key"]] = item["value"]
		_check(LocalHost.parse_ready(JSON.stringify(forged).to_ascii_buffer(), config).is_empty(),
			"readiness cannot silently change host's accepted settings")
	for field: String in record:
		var missing: Dictionary = record.duplicate()
		missing.erase(field)
		_check(LocalHost.parse_ready(JSON.stringify(missing).to_ascii_buffer(), config).is_empty(),
			"every readiness field is required")
	await _test_lifetime(config, record)

func _test_profile(config: Dictionary) -> void:
	var ready: Dictionary = _ready_record(config)
	_check(LocalHost.valid_settings(config), "both presets validate explicit binding")
	_check(LocalHost.parse_ready(JSON.stringify(ready).to_ascii_buffer(), config) == JSON.parse_string(JSON.stringify(ready)),
		"real binding and preset metadata accepted")
	var args: PackedStringArray = LocalHost.arguments_for(config)
	_check(args[0] == "--desktop-host" and args[1] == "--bind" \
		and args[2] == (ready["listen"] if config["lan"] else "127.0.0.1:0"), "binding choice is always explicit")
	_check(args.has("--sabotage-five-v-five") == (config["mode"] == "sabotage"), "only Sabotage opts into 5v5")
	_check(args[args.find("--bots") + 1] == str(config["bots"])
		and args[args.find("--bot-policy") + 1] == config["bot_policy"]
		and args[args.find("--fill-target") + 1] == str(config["fill_target"]), "native flags carry the complete explicit bot policy")

func _test_lifetime(config: Dictionary, record: Dictionary) -> void:
	var fixture: Fixture = Fixture.new()
	var child: FakeProcess = FakeProcess.new()
	fixture.process = child
	var addresses: Array[String] = []
	fixture.server_ready.connect(func(address: String) -> void: addresses.append(address))
	_check(fixture.start_host(config), "first activation starts owned child")
	_check(not fixture.start_host(config) and child.starts == 1, "repeat activation cannot spawn twice")
	var line: String = JSON.stringify(record) + "\n"
	child.output = line.left(20).to_ascii_buffer()
	fixture._process(0)
	_check(fixture.state == LocalHost.State.STARTING and addresses.is_empty(), "partial readiness cannot launch")
	child.output = line.substr(20).to_ascii_buffer()
	fixture._process(0)
	_check(fixture.state == LocalHost.State.RUNNING and addresses == [record["url"]], "complete ready launches exactly once")
	fixture.stop()
	_check(child.stops == 1 and fixture.state == LocalHost.State.STOPPING, "explicit Stop closes owned lease")
	fixture._deadline = 0
	fixture._process(0)
	_check(child.killed == 1 and fixture.state == LocalHost.State.IDLE and fixture.url.is_empty(), "bounded cleanup retires only owned child")
	fixture.start_host(config)
	fixture.stop()
	child.output = line.to_ascii_buffer()
	fixture._process(0)
	_check(addresses.size() == 1, "late ready after cancellation never launches")
	child.alive = false
	fixture._process(0)
	fixture.start_host(config)
	fixture._deadline = 0
	fixture._process(0)
	_check(fixture.error_key == "LOCAL_SERVER_TIMEOUT" and fixture.state == LocalHost.State.STOPPING, "bounded startup timeout is observable")
	child.alive = false
	fixture._process(0)
	fixture.start_host(config)
	child.output = (line + line).to_ascii_buffer()
	fixture._process(0)
	_check(fixture.error_key == "LOCAL_SERVER_INVALID_READY", "extra stdout refuses activation")
	fixture.free()
	var owner: LocalHost = LocalHost.for_tree(self)
	_check(LocalHost.for_tree(self) == owner, "deferred root ownership is unique")
	await process_frame
	var temporary_scene: Node = Node.new()
	root.add_child(temporary_scene)
	temporary_scene.queue_free()
	await process_frame
	_check(is_instance_valid(owner) and LocalHost.for_tree(self) == owner, "gameplay scene retirement does not retire root host")
	owner.queue_free()
	await process_frame
	if failures == 0:
		print("test_local_host: PASS")
	quit(0 if failures == 0 else 1)
