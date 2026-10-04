class_name LocalMatch
extends Node

signal mission_ready(address: String)
signal failed(message_key: String)
signal state_changed
signal run_preview_changed

enum State { IDLE, STARTING, RUNNING, STOPPING, FAILED }
const START_TIMEOUT_MS: int = 15000
const STOP_TIMEOUT_MS: int = 3000
const MAX_READY_BYTES: int = 4096
const PENDING_META: StringName = &"fragr_local_match_pending"
## Set by a finished mission that asked to continue the saved run directly.
const ONWARD_META: StringName = &"fragr_run_onward"
## Rules revision 3 retires older live mission readers on every authored map.
const DURABLE_GAMEPLAY: int = 26
const M02_GAMEPLAY: int = 26
const M03_GAMEPLAY: int = 26
const M04_GAMEPLAY: int = 26
const MISSION_GAMEPLAY: Dictionary[String, int] = {"recall_notice": DURABLE_GAMEPLAY, "persons_unknown": M02_GAMEPLAY, "scheduled_service": M03_GAMEPLAY, "notice_to_vacate": M04_GAMEPLAY, "no_forwarding_address": M05_GAMEPLAY, "port_of_entry": M06_GAMEPLAY, "declared_goods": M07_GAMEPLAY, "custodian_of_record": M08_GAMEPLAY}
const M05_GAMEPLAY: int = 26
const M06_GAMEPLAY: int = 27
const M07_GAMEPLAY: int = 32
const M08_GAMEPLAY: int = 31
const NEXT_MISSION: String = "custodian_of_record"

var state: State = State.IDLE
var url: String = ""
var error_key: String = ""
var process: LocalProcess = LocalProcess.new()
var run_preview: Dictionary = {}
var _preview_process: LocalProcess = LocalProcess.new()
var _preview_pending: PackedByteArray = PackedByteArray()
var _preview_active: bool = false
var _preview_deadline: int = 0
var _pending: PackedByteArray = PackedByteArray()
var _deadline: int = 0
var _failure_pending: bool = false
var _difficulty: String = "standard"
var _run_mode: String = "new"
## The bundled mission of the running or starting child.
var mission: String = MissionState.ID

func has_durable_run() -> bool:
	return not _run_mode.is_empty()

static func for_tree(tree: SceneTree) -> LocalMatch:
	var existing: LocalMatch = tree.root.get_node_or_null("LocalMatch") as LocalMatch
	if existing != null:
		return existing
	var pending: Variant = tree.get_meta(PENDING_META) if tree.has_meta(PENDING_META) else null
	if is_instance_valid(pending) and pending is LocalMatch and not (pending as LocalMatch).is_inside_tree():
		return pending as LocalMatch
	var owner: LocalMatch = LocalMatch.new()
	owner.name = "LocalMatch"
	# The main scene's _ready runs while the root is still adding children, and a
	# direct add_child fails there, so the owner would never poll its child.
	tree.root.add_child.call_deferred(owner)
	tree.set_meta(PENDING_META, owner)
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

func refresh_run_preview() -> void:
	if _preview_active:
		return
	var executable: String = executable_path()
	if executable.is_empty():
		run_preview = {"status": "unavailable"}
		run_preview_changed.emit()
		return
	_preview_process.dispose()
	_preview_pending.clear()
	run_preview = {"status": "loading"}
	if not _preview_process.start(executable, PackedStringArray(["--local-run-preview"])):
		run_preview = {"status": "unavailable"}
		run_preview_changed.emit()
		return
	_preview_active = true
	_preview_deadline = Time.get_ticks_msec() + START_TIMEOUT_MS
	run_preview_changed.emit()

func start_mission(difficulty: String = "standard", run_mode: String = "new", mission_id: String = MissionState.ID) -> bool:
	if state not in [State.IDLE, State.FAILED]:
		return false
	# Later missions keep independent development children beside durable resume.
	var development: bool = mission_id != MissionState.ID and run_mode.is_empty()
	if difficulty not in MissionState.DIFFICULTIES or not MISSION_GAMEPLAY.has(mission_id) \
		or (mission_id == MissionState.ID and run_mode not in ["new", "resume"]) \
		or (mission_id != MissionState.ID and run_mode not in ["", "resume"]):
		_fail("LOCAL_SERVER_INVALID_DIFFICULTY")
		return false
	_preview_process.dispose()
	_preview_active = false
	_difficulty = difficulty
	_run_mode = run_mode
	mission = mission_id
	process.dispose()
	url = ""
	error_key = ""
	_pending.clear()
	_failure_pending = false
	var executable: String = executable_path()
	if executable.is_empty():
		_fail("LOCAL_SERVER_MISSING")
		return false
	var arguments: PackedStringArray = PackedStringArray(["--local-mission", mission_id])
	if not development:
		arguments.append_array(PackedStringArray(["--run-mode", run_mode]))
	arguments.append_array(PackedStringArray(["--difficulty", difficulty]))
	if not process.start(executable, arguments):
		_fail("LOCAL_SERVER_START_FAILED")
		return false
	_deadline = Time.get_ticks_msec() + START_TIMEOUT_MS
	state = State.STARTING
	state_changed.emit()
	return true

func stop() -> void:
	_preview_process.dispose()
	_preview_active = false
	run_preview.clear()
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
	_poll_run_preview()
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
		if state == State.STARTING:
			if _run_mode.is_empty():
				_fail("LOCAL_SERVER_START_FAILED")
			else:
				_fail("LOCAL_RUN_OPEN_FAILED" if _run_mode == "resume" else "LOCAL_RUN_CREATE_FAILED")
		else:
			_fail("LOCAL_SERVER_STOPPED")
		return
	if state == State.STARTING:
		_pending.append_array(process.read_output())
		if _pending.size() > MAX_READY_BYTES:
			_fail("LOCAL_SERVER_INVALID_READY")
			return
		var newline: int = _pending.find(10)
		if newline >= 0:
			var address: String = readiness_url(_pending.slice(0, newline), _difficulty, mission, _run_mode)
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

func _poll_run_preview() -> void:
	if not _preview_active:
		return
	_preview_process.drain_errors()
	_preview_pending.append_array(_preview_process.read_output())
	if _preview_pending.size() > MAX_READY_BYTES:
		_finish_run_preview({"status": "unavailable"})
		return
	var newline: int = _preview_pending.find(10)
	if newline >= 0:
		var parsed: Dictionary = parse_run_preview(_preview_pending.slice(0, newline))
		if newline != _preview_pending.size() - 1 or parsed.is_empty():
			parsed = {"status": "unavailable"}
		_finish_run_preview(parsed)
	elif not _preview_process.running() or Time.get_ticks_msec() >= _preview_deadline:
		_finish_run_preview({"status": "unavailable"})

func _finish_run_preview(value: Dictionary) -> void:
	_preview_active = false
	_preview_process.dispose()
	_preview_pending.clear()
	run_preview = value
	run_preview_changed.emit()

static func parse_run_preview(bytes: PackedByteArray) -> Dictionary:
	for byte: int in bytes:
		if byte < 32 or byte > 126:
			return {}
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_ascii()) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	if not data.get("status") is String:
		return {}
	var status: String = data["status"]
	if status in ["missing", "failed", "abandoned", "incompatible", "corrupt"]:
		return data if data.size() == 1 else {}
	if status == "awaiting_mission":
		return data if data.size() == 5 and data.has("body") and data.get("mission") in [MissionState.M02_ID, MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID, NEXT_MISSION] \
			and data.get("difficulty") in MissionState.DIFFICULTIES \
			and EquipmentState.integer(data.get("continues"), 3) \
			and (data.get("body") == null or PlayerBody.valid(data["body"])) else {}
	if status != "ready" or data.size() != 7 or not data.has("body") \
		or data.get("mission") not in [MissionState.ID, MissionState.M02_ID, MissionState.M03_ID, MissionState.M04_ID, MissionState.M05_ID, MissionState.M06_ID, MissionState.M07_ID] \
		or not data.get("difficulty") is String or data["difficulty"] not in MissionState.DIFFICULTIES \
		or not EquipmentState.integer(data.get("continues"), 3) \
		or not EquipmentState.integer(data.get("attempt"), 4) or int(data["attempt"]) < 1 \
		or int(data["attempt"]) + int(data["continues"]) > 4 \
		or (data["mission"] == MissionState.ID and int(data["attempt"]) != 4 - int(data["continues"])) \
		or not data.get("pending_continue") is bool or (data["pending_continue"] and int(data["continues"]) == 0) \
		or (data.get("body") != null and not PlayerBody.valid(data["body"])):
		return {}
	return data

static func readiness_url(bytes: PackedByteArray, difficulty: String = "standard", mission_id: String = MissionState.ID, run_mode: String = "new") -> String:
	# This bootstrap contract contains only fixed ASCII identifiers and IPv4.
	for byte: int in bytes:
		if byte < 32 or byte > 126:
			return ""
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_ascii()) != OK:
		return ""
	var data: Variant = parser.data
	var gameplay: int = MISSION_GAMEPLAY.get(mission_id, -1)
	if difficulty not in MissionState.DIFFICULTIES or not MISSION_GAMEPLAY.has(mission_id) \
		or (mission_id != MissionState.ID and run_mode not in ["", "resume"]) \
		or (mission_id == MissionState.ID and run_mode not in ["new", "resume"]) \
		or not data is Dictionary or data.size() != 5 \
		or not EquipmentState.integer(data.get("version"), 2) or data["version"] != 2 \
		or not data.get("difficulty") is String or data["difficulty"] != difficulty \
		or not data.get("mission") is String or data["mission"] != mission_id \
		or not EquipmentState.integer(data.get("gameplay_version"), 4294967295) \
		or int(data["gameplay_version"]) != gameplay \
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
	_preview_process.dispose()
	process.request_stop()
	process.dispose()
