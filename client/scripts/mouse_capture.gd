extends Node
class_name MouseCapture

## Match-owned pointer lifecycle. Camera and menus request state through the
## game manager; they never capture a desktop pointer independently.
var _gameplay: bool = false
var _focused: bool = false
var _closing: bool = false
var _automated: bool = false

func _ready() -> void:
	var window: Window = get_window()
	_focused = window.has_focus()
	_automated = DisplayServer.get_name() == "headless" or get_tree().has_meta("fragr_automated")
	window.focus_entered.connect(_focus_entered)
	window.focus_exited.connect(_focus_exited)
	window.close_requested.connect(_close_requested)
	_sync()

func set_gameplay(enabled: bool) -> void:
	_gameplay = enabled
	_sync()

func desired_mode() -> Input.MouseMode:
	return Input.MOUSE_MODE_CAPTURED if _gameplay and _focused and not _closing and not _automated else Input.MOUSE_MODE_VISIBLE

func gameplay_input_allowed() -> bool:
	return not _closing and (_focused or _automated)

func _sync() -> void:
	var mode: Input.MouseMode = desired_mode()
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode

func _focus_entered() -> void:
	_focused = true
	_sync()

func _focus_exited() -> void:
	_focused = false
	release()

func _close_requested() -> void:
	_closing = true
	release()

func _exit_tree() -> void:
	_closing = true
	release()

static func release() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
