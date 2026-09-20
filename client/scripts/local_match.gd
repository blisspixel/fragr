class_name LocalMatch
extends Node

signal mission_ready(address: String)
signal failed(message_key: String)
signal state_changed

enum State { IDLE, STARTING, RUNNING, STOPPING, FAILED }
const START_TIMEOUT_MS: int = 15000
const STOP_TIMEOUT_MS: int = 3000
const MAX_READY_BYTES: int = 4096
const GAMEPLAY_VERSION: int = preload("res://scripts/net_client.gd").GAMEPLAY_VERSION

var state: State = State.IDLE
var url: String = ""
var error_key: String = ""
var process: LocalProcess = LocalProcess.new()
var _pending: PackedByteArray = PackedByteArray()
var _deadline: int = 0
var _failure_pending: bool = false
var _difficulty: String = "standard"

static func for_tree(tree: SceneTree) -> LocalMatch:
	var existing: LocalMatch = tree.root.get_node_or_null("LocalMatch") as LocalMatch
	if existing != null:
		return existing
	var owner: LocalMatch = LocalMatch.new()
	owner.name = "LocalMatch"
	tree.root.add_child(owner)
	return owner

func executable_path() -> String:
	var filename: String = "fragr-server.exe" if OS.get_name() == "Windows" else "fragr-server"
	var candidates: Array[String] = [OS.get_executable_path().get_base_dir().path_join(filename)]
	if OS.has_feature("editor"):
		for profile: String in ["release", "debug"]:
			candidates.append(ProjectSettings.globalize_path("res://../target/%s/%s" % [profile, filename]).simplify_path())
	for path: String in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""

func start_mission(difficulty: String = "standard") -> bool:
	if state not in [State.IDLE, State.FAILED]:
		return false
	if difficulty not in MissionState.DIFFICULTIES:
		_fail("LOCAL_SERVER_INVALID_DIFFICULTY")
		return false
	_difficulty = difficulty
	process.dispose()
	url = ""
	error_key = ""
	_pending.clear()
	_failure_pending = false
	var executable: String = executable_path()
	if executable.is_empty():
		_fail("LOCAL_SERVER_MISSING")
		return false
	if not process.start(executable, PackedStringArray(["--local-mission", MissionState.ID, "--difficulty", difficulty])):
		_fail("LOCAL_SERVER_START_FAILED")
		return false
	_deadline = Time.get_ticks_msec() + START_TIMEOUT_MS
	state = State.STARTING
	state_changed.emit()
	return true

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
			state_changed.emit()
		return
	if not process.running():
		_fail("LOCAL_SERVER_STOPPED")
		return
	if state == State.STARTING:
		_pending.append_array(process.read_output())
		if _pending.size() > MAX_READY_BYTES:
			_fail("LOCAL_SERVER_INVALID_READY")
			return
		var newline: int = _pending.find(10)
		if newline >= 0:
			var address: String = readiness_url(_pending.slice(0, newline), _difficulty)
			if address.is_empty() or newline != _pending.size() - 1:
				_fail("LOCAL_SERVER_INVALID_READY")
				return
			url = address
			_pending.clear()
			state = State.RUNNING
			state_changed.emit()
			mission_ready.emit(url)
		elif Time.get_ticks_msec() >= _deadline:
			_fail("LOCAL_SERVER_TIMEOUT")
	elif not process.read_output().is_empty():
		_fail("LOCAL_SERVER_INVALID_READY")

static func readiness_url(bytes: PackedByteArray, difficulty: String = "standard") -> String:
	# This bootstrap contract contains only fixed ASCII identifiers and IPv4.
	for byte: int in bytes:
		if byte < 32 or byte > 126:
			return ""
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_ascii()) != OK:
		return ""
	var data: Variant = parser.data
	if difficulty not in MissionState.DIFFICULTIES or not data is Dictionary or data.size() != 5 \
		or not EquipmentState.integer(data.get("version"), 2) or data["version"] != 2 \
		or not data.get("difficulty") is String or data["difficulty"] != difficulty \
		or not data.get("mission") is String or data["mission"] != MissionState.ID \
		or not EquipmentState.integer(data.get("gameplay_version"), GAMEPLAY_VERSION) or data["gameplay_version"] != GAMEPLAY_VERSION \
		or not data.get("url") is String:
		return ""
	var address: String = data["url"]
	const PREFIX: String = "ws://127.0.0.1:"
	if not address.begins_with(PREFIX):
		return ""
	var port: String = address.trim_prefix(PREFIX)
	if port.length() < 1 or port.length() > 5 or not port.is_valid_int() \
		or str(port.to_int()) != port or port.to_int() < 1 or port.to_int() > 65535:
		return ""
	return address

func _fail(key: String) -> void:
	error_key = key
	url = ""
	_failure_pending = true
	var diagnostic: String = process.diagnostics()
	if not diagnostic.is_empty():
		print("Local server: ", diagnostic)
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
