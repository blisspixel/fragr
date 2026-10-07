class_name ReleaseFetch
extends Node

## Downloads one published desktop archive after the player asks.
## A checksum mismatch is not unpacked and not started.

signal reported(text: String)
signal failed(text: String)
signal started(quit_after: bool)

var _http: HTTPRequest
var _serial: int = 0
var _busy: bool = false
var _accepting: bool = false
var _phase: String = ""
var _host: String = ""
var _staging: String = ""
var _blocked: String = ""
var _release: Dictionary = {}
var _sums: String = ""
var _zip_path: String = ""
var _offer_dir: String = ""

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "ReleaseHttp"
	_http.use_threads = true
	_http.accept_gzip = true
	add_child(_http)
	_http.request_completed.connect(_on_http)

func is_busy() -> bool:
	return _busy

func cancel() -> void:
	_serial += 1
	_busy = false
	_accepting = false
	_phase = ""
	if _http != null and is_instance_valid(_http):
		_http.download_file = ""
		_http.cancel_request()

func start(host: String, staging: String, blocked: String) -> void:
	cancel()
	_busy = true
	var serial: int = _serial
	_host = host
	_staging = staging.replace("\\", "/").simplify_path()
	_blocked = blocked.replace("\\", "/").simplify_path()
	_release = {}
	_sums = ""
	_zip_path = ""
	_offer_dir = ""
	await get_tree().process_frame
	if serial != _serial or not is_inside_tree():
		return
	if _staging.is_empty() or (not _blocked.is_empty() and ReleaseInstall.path_is_inside(_staging, _blocked)):
		_fail(ReleaseInstall.OUTSIDE)
		return
	var platform: String = ReleaseInstall.platform_id()
	if platform.is_empty():
		_fail(ReleaseInstall.NO_BUILD)
		return
	if DirAccess.make_dir_recursive_absolute(_staging) != OK and not DirAccess.dir_exists_absolute(_staging):
		_fail(ReleaseInstall.PREPARE_FAILED)
		return
	_accepting = true
	_phase = "manifest"
	reported.emit(ReleaseInstall.CHECKING)
	_configure(ReleaseInstall.MANIFEST_LIMIT, 20.0, "")
	if _http.request(ReleaseInstall.API_URL, ReleaseInstall.api_headers()) != OK:
		_fail(ReleaseInstall.UNREACHABLE)

func _configure(limit: int, timeout: float, download: String) -> void:
	_http.body_size_limit = limit
	_http.timeout = timeout
	_http.download_file = download

func _on_http(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _accepting:
		return
	var phase: String = _phase
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail(_failure_result(result))
		return
	if code != 200:
		_fail(ReleaseInstall.UNREADABLE if phase == "manifest" else ReleaseInstall.UNREACHABLE)
		return
	match phase:
		"manifest":
			_got_manifest(body)
		"sums":
			_got_sums(body)
		"archive":
			_got_archive()
		_:
			_fail(ReleaseInstall.UNREADABLE)

func _got_manifest(body: PackedByteArray) -> void:
	var parsed: Dictionary = ReleaseInstall.parse_release(body.get_string_from_utf8(), ReleaseInstall.platform_id())
	if parsed.has("error"):
		_fail(str(parsed["error"]))
		return
	_release = parsed
	_phase = "sums"
	reported.emit(ReleaseInstall.DOWNLOADING_SUMS)
	_configure(ReleaseInstall.SUMS_LIMIT, 20.0, "")
	if _http.request(str(parsed["sums_url"]), ReleaseInstall.file_headers()) != OK:
		_fail(ReleaseInstall.UNREACHABLE)

func _got_sums(body: PackedByteArray) -> void:
	_sums = body.get_string_from_utf8()
	if ReleaseInstall.checksum_for(_sums, str(_release["archive"])).is_empty():
		_fail(ReleaseInstall.UNREADABLE)
		return
	_offer_dir = _staging.path_join("offer-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()])
	if DirAccess.make_dir_recursive_absolute(_offer_dir) != OK and not DirAccess.dir_exists_absolute(_offer_dir):
		_fail(ReleaseInstall.PREPARE_FAILED)
		return
	_zip_path = _offer_dir.path_join(str(_release["archive"]))
	_phase = "archive"
	reported.emit(ReleaseInstall.DOWNLOADING)
	_configure(ReleaseInstall.ARCHIVE_LIMIT, 0.0, _zip_path)
	_http.download_chunk_size = 262144
	if _http.request(str(_release["archive_url"]), ReleaseInstall.file_headers()) != OK:
		_fail(ReleaseInstall.UNREACHABLE)

func _got_archive() -> void:
	_accepting = false
	_phase = ""
	_http.download_file = ""
	if not FileAccess.file_exists(_zip_path):
		_fail(ReleaseInstall.UNREACHABLE)
		return
	var extracted: String = ReleaseInstall.checked_extract(
		_zip_path, _sums, str(_release["archive"]), _offer_dir, str(_release["package"]), str(_release["platform"]))
	if not extracted.is_empty():
		_fail(extracted)
		return
	_launch_checked()

func _launch_checked() -> void:
	var package_dir: String = _offer_dir.path_join(str(_release["package"]))
	var executable: String = OS.get_executable_path()
	var editor: bool = Engine.is_editor_hint() or OS.has_feature("editor")
	var blocked: PackedStringArray = PackedStringArray()
	if not _blocked.is_empty():
		blocked.append(_blocked)
	var replace: String = ReleaseInstall.replace_directory(executable, editor, blocked)
	var install_files: PackedStringArray = PackedStringArray()
	if not replace.is_empty():
		var listing: DirAccess = DirAccess.open(replace)
		if listing != null:
			install_files = listing.get_files()
	var plan: Dictionary = ReleaseInstall.handoff(
		executable, editor, blocked, install_files, OS.get_process_id(), package_dir, _host, str(_release["platform"]))
	if plan.has("error"):
		_fail(str(plan["error"]))
		return
	var game: String = str(plan.get("game", ""))
	if not FileAccess.file_exists(game):
		_fail(ReleaseInstall.NO_GAME)
		return
	var arguments: PackedStringArray = PackedStringArray()
	var raw_arguments: Variant = plan.get("arguments", PackedStringArray())
	if raw_arguments is PackedStringArray:
		arguments = raw_arguments
	if str(plan.get("mode", "")) == "replace":
		if not _start_replacement(str(plan.get("script", ""))):
			_fail(ReleaseInstall.START_FAILED)
			return
		started.emit(true)
		return
	_mark_executable(game, str(_release["platform"]))
	if OS.create_process(game, arguments) <= 0:
		_fail(ReleaseInstall.START_FAILED)
		return
	_busy = false
	started.emit(bool(plan.get("quit_after", false)))

func _start_replacement(script: String) -> bool:
	if script.is_empty():
		return false
	var script_path: String = _staging.path_join("handoff.cmd" if OS.has_feature("windows") else "handoff.sh")
	var file: FileAccess = FileAccess.open(script_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(script)
	file.close()
	if OS.has_feature("windows"):
		return OS.create_process("cmd.exe", PackedStringArray(["/D", "/C", script_path])) > 0
	return OS.create_process("/bin/sh", PackedStringArray([script_path])) > 0

func _mark_executable(game: String, platform: String) -> void:
	if platform == "macos-universal":
		var app: String = game.get_base_dir().get_base_dir().get_base_dir()
		OS.execute("xattr", PackedStringArray(["-dr", "com.apple.quarantine", app]))
	if OS.has_feature("windows"):
		return
	OS.execute("chmod", PackedStringArray(["+x", game]))
	var server: String = game.get_base_dir().path_join("fragr-server")
	if FileAccess.file_exists(server):
		OS.execute("chmod", PackedStringArray(["+x", server]))

func _failure_result(result: int) -> String:
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return ReleaseInstall.TOO_LARGE
	if result == HTTPRequest.RESULT_CANT_RESOLVE or result == HTTPRequest.RESULT_CANT_CONNECT \
		or result == HTTPRequest.RESULT_CONNECTION_ERROR or result == HTTPRequest.RESULT_TIMEOUT \
		or result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
		return ReleaseInstall.UNREACHABLE
	return ReleaseInstall.UNREADABLE

func _fail(text: String) -> void:
	_busy = false
	_accepting = false
	_phase = ""
	if _http != null and is_instance_valid(_http):
		_http.download_file = ""
		_http.cancel_request()
	failed.emit(text)
