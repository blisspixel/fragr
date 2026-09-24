class_name InstallCheck
extends Node
## `fragr --headless -- --check-install` asks the bundled fragr-server for a run
## preview through the boot menu's LocalMatch, prints one verdict line and quits.
## In an exported build the server must sit beside the game executable.

signal finished(passed: bool)

const FLAG: String = "--check-install"
const TIMEOUT_MS: int = 15000

var quit_when_done: bool = true
var _local: LocalMatch
var _deadline: int = 0

static func requested() -> bool:
	return FLAG in OS.get_cmdline_user_args()

func _init(local: LocalMatch) -> void:
	_local = local

func _ready() -> void:
	var path: String = _local.executable_path()
	if path.is_empty():
		_finish(false, "no fragr-server beside %s" % OS.get_executable_path())
		return
	if not OS.has_feature("editor") and path.get_base_dir() != OS.get_executable_path().get_base_dir():
		_finish(false, "an exported build resolved %s outside its own directory" % path)
		return
	_local.run_preview_changed.connect(_on_preview)
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	_local.refresh_run_preview()

func _process(_delta: float) -> void:
	if _deadline > 0 and Time.get_ticks_msec() > _deadline:
		_finish(false, "run preview timed out")

func _on_preview() -> void:
	var status: String = str(_local.run_preview.get("status", ""))
	if status == "loading":
		return
	if status.is_empty() or status == "unavailable":
		_finish(false, "the server did not answer a run preview")
		return
	_finish(true, "server %s answered %s" % [_local.executable_path(), status])

func _finish(passed: bool, detail: String) -> void:
	if _deadline < 0:
		return
	_deadline = -1
	if _local.run_preview_changed.is_connected(_on_preview):
		_local.run_preview_changed.disconnect(_on_preview)
	if passed:
		print("fragr install check: PASS, ", detail)
	else:
		printerr("fragr install check: FAIL, " + detail)
	finished.emit(passed)
	if quit_when_done:
		get_tree().quit(0 if passed else 1)
