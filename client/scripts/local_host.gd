class_name LocalHost
extends Node

## An owned arena outlives gameplay scenes. Campaign ownership stays LocalMatch.
signal server_ready(address: String)
signal failed(message_key: String)
signal state_changed

enum State { IDLE, STARTING, RUNNING, STOPPING, FAILED }
const START_TIMEOUT_MS: int = 15000
const STOP_TIMEOUT_MS: int = 3000
const MAX_READY_BYTES: int = 4096
const PENDING_META: StringName = &"fragr_local_host_pending"
const GAMEPLAY_VERSION: int = 38

var state: State = State.IDLE
var url: String = ""
var listen: String = ""
var error_key: String = ""
var process: LocalProcess = LocalProcess.new()
var settings: Dictionary = {}
var _pending: PackedByteArray = PackedByteArray()
var _deadline: int = 0
var _failure_pending: bool = false

static func for_tree(tree: SceneTree) -> LocalHost:
	var existing: LocalHost = tree.root.get_node_or_null("LocalHost") as LocalHost
	if existing != null:
		return existing
	var pending: Variant = tree.get_meta(PENDING_META) if tree.has_meta(PENDING_META) else null
	if is_instance_valid(pending) and pending is LocalHost and not (pending as LocalHost).is_inside_tree():
		return pending as LocalHost
	var owner: LocalHost = LocalHost.new()
	owner.name = "LocalHost"
	tree.root.add_child.call_deferred(owner)
	tree.set_meta(PENDING_META, owner)
	return owner

func executable_path() -> String:
	return LocalMatch.find_executable_path()

static func valid_settings(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	if data.size() != 7 or not data.get("mode") is String \
		or data["mode"] not in ["tdm", "sabotage"] or not data.get("lan") is bool \
		or not data.get("bot_policy") is String or data["bot_policy"] not in ["none", "fixed", "auto"] \
		or not EquipmentState.integer(data.get("map_id"), 6) or data["map_id"] < 1 \
		or not EquipmentState.integer(data.get("bots"), 10) \
		or not EquipmentState.integer(data.get("fill_target"), 10) \
		or not EquipmentState.integer(data.get("port"), 65535):
		return false
	if data["bot_policy"] == "fixed":
		if data["fill_target"] != 0:
			return false
	elif data["bots"] != 0 or (data["fill_target"] < 1 if data["bot_policy"] == "auto" else data["fill_target"] != 0):
		return false
	if data["mode"] == "sabotage" and data["map_id"] != 4:
		return false
	return data["port"] > 0 if data["lan"] else data["port"] == 0

static func arguments_for(value: Dictionary) -> PackedStringArray:
	if not valid_settings(value):
		return PackedStringArray()
	var bind: String = ("0.0.0.0" if value["lan"] else "127.0.0.1") + ":" + str(int(value["port"]))
	var args: PackedStringArray = PackedStringArray(["--desktop-host", "--bind", bind,
		"--mode", value["mode"], "--map", str(int(value["map_id"])), "--bots", str(int(value["bots"])),
		"--bot-policy", value["bot_policy"], "--fill-target", str(int(value["fill_target"]))])
	if value["mode"] == "sabotage":
		args.append("--sabotage-five-v-five")
	return args

func start_host(value: Dictionary) -> bool:
	if state not in [State.IDLE, State.FAILED]:
		return false
	if not valid_settings(value):
		_fail("HOST_INVALID_SETTINGS")
		return false
	var executable: String = executable_path()
	if executable.is_empty():
		_fail("LOCAL_SERVER_MISSING")
		return false
	process.dispose()
	settings = value.duplicate(true)
	url = ""
	listen = ""
	error_key = ""
	_pending.clear()
	_failure_pending = false
	if not process.start(executable, arguments_for(settings)):
		_fail("LOCAL_SERVER_START_FAILED")
		return false
	_deadline = Time.get_ticks_msec() + START_TIMEOUT_MS
	state = State.STARTING
	state_changed.emit()
	return true

static func parse_ready(bytes: PackedByteArray, requested: Dictionary) -> Dictionary:
	if not valid_settings(requested):
		return {}
	for byte: int in bytes:
		if byte < 32 or byte > 126:
			return {}
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_ascii()) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	if data.size() != 11 or not EquipmentState.integer(data.get("version"), 1) or data["version"] != 1 \
		or data.get("kind") != "arena" or data.get("mode") != requested["mode"] \
		or not data.get("five_vs_five") is bool or data["five_vs_five"] != (requested["mode"] == "sabotage") \
		or not EquipmentState.integer(data.get("map_id"), 6) or data["map_id"] != requested["map_id"] \
		or not EquipmentState.integer(data.get("bots"), 10) or data["bots"] != requested["bots"] \
		or not data.get("bot_policy") is String or data["bot_policy"] != requested["bot_policy"] \
		or not EquipmentState.integer(data.get("fill_target"), 10) or data["fill_target"] != requested["fill_target"] \
		or not EquipmentState.integer(data.get("gameplay_version"), GAMEPLAY_VERSION) \
		or data["gameplay_version"] != GAMEPLAY_VERSION or not data.get("listen") is String:
		return {}
	var endpoint: Dictionary = ServerEndpoint.parse(data.get("url"))
	if endpoint.is_empty() or endpoint["host"] != "127.0.0.1" or endpoint["secure"] \
		or endpoint["game_url"] != data["url"]:
		return {}
	var actual_port: int = endpoint["port"]
	var address: String = ("0.0.0.0" if requested["lan"] else "127.0.0.1") + ":" + str(actual_port)
	if data["listen"] != address or requested["lan"] and actual_port != requested["port"]:
		return {}
	return data

func stop() -> void:
	if state in [State.IDLE, State.FAILED]:
		process.dispose()
		state = State.IDLE
		state_changed.emit()
		return
	if state == State.STOPPING:
		return
	process.request_stop()
	state = State.STOPPING
	_deadline = Time.get_ticks_msec() + STOP_TIMEOUT_MS
	state_changed.emit()

func _process(_delta: float) -> void:
	if state in [State.IDLE, State.FAILED]:
		return
	process.drain_errors()
	if state == State.STOPPING:
		if not process.running() or Time.get_ticks_msec() >= _deadline:
			process.dispose()
			state = State.FAILED if _failure_pending else State.IDLE
			url = ""
			listen = ""
			state_changed.emit()
		return
	if not process.running():
		_fail("LOCAL_SERVER_START_FAILED" if state == State.STARTING else "LOCAL_SERVER_STOPPED")
		return
	if state == State.STARTING:
		_pending.append_array(process.read_output())
		if _pending.size() > MAX_READY_BYTES:
			_fail("LOCAL_SERVER_INVALID_READY")
			return
		var newline: int = _pending.find(10)
		if newline >= 0:
			var ready: Dictionary = parse_ready(_pending.slice(0, newline), settings)
			if ready.is_empty() or newline != _pending.size() - 1:
				_fail("LOCAL_SERVER_INVALID_READY")
				return
			url = ready["url"]
			listen = ready["listen"]
			_pending.clear()
			state = State.RUNNING
			state_changed.emit()
			server_ready.emit(url)
		elif Time.get_ticks_msec() >= _deadline:
			_fail("LOCAL_SERVER_TIMEOUT")
	elif not process.read_output().is_empty():
		_fail("LOCAL_SERVER_INVALID_READY")

func _fail(key: String) -> void:
	error_key = key
	url = ""
	listen = ""
	_failure_pending = true
	if process.running():
		stop()
	else:
		process.dispose()
		state = State.FAILED
		state_changed.emit()
	failed.emit(key)

func _exit_tree() -> void:
	process.request_stop()
	process.dispose()
