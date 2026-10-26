class_name LocalProcess
extends RefCounted

## Only owns the process returned by execute_with_pipe, never a discovered PID.
var _pid: int = -1
var _stdio: FileAccess
var _stderr: FileAccess
var _error_pending: PackedByteArray = PackedByteArray()
var _error_lines: Array[String] = []
var _discard_error_line: bool = false
## An observed exit or successful owned termination, not a later PID lookup.
var retirement_confirmed: bool = true
var retirement_error: Error = OK

func start(executable: String, arguments: PackedStringArray) -> bool:
	# Failed retirement keeps custody. A replacement must not hide that child.
	if _pid > 0 or _stdio != null or _stderr != null:
		return false
	var child: Dictionary = OS.execute_with_pipe(executable, arguments, false)
	if child.is_empty():
		return false
	_pid = int(child["pid"])
	_stdio = child["stdio"] as FileAccess
	_stderr = child["stderr"] as FileAccess
	retirement_confirmed = false
	retirement_error = OK
	return true

func read_output() -> PackedByteArray:
	return _stdio.get_buffer(4096) if _stdio != null and _stdio.is_open() else PackedByteArray()

func drain_errors() -> void:
	if _stderr == null or not _stderr.is_open():
		return
	for byte: int in _stderr.get_buffer(4096):
		if byte == 10:
			_error_lines.append("[oversized diagnostic omitted]" if _discard_error_line else _error_pending.get_string_from_utf8())
			if _error_lines.size() > 8:
				_error_lines.pop_front()
			_error_pending.clear()
			_discard_error_line = false
		elif _error_pending.size() < 2048 and not _discard_error_line:
			_error_pending.append(byte)
		else:
			_discard_error_line = true

func diagnostics() -> String:
	return "\n".join(_error_lines)

func running() -> bool:
	if _pid <= 0:
		return false
	# Godot may discard its native handle even when termination fails. That
	# lost observation must not become a false exit or a kill of a reused PID.
	if retirement_error != OK:
		return true
	if _owned_process_running():
		return true
	# Retire observed exits. Cleanup must never query or kill a reused PID.
	_pid = -1
	retirement_confirmed = true
	return false

func _owned_process_running() -> bool:
	return OS.is_process_running(_pid)

func _terminate_owned_process() -> Error:
	return OS.kill(_pid)

func request_stop() -> void:
	if _stdio != null and _stdio.is_open():
		if running():
			_stdio.store_string("{\"type\":\"shutdown\"}\n")
			_stdio.flush()
		# Closing the lease also handles a short or failed control write.
		_stdio.close()

func dispose() -> void:
	if retirement_error != OK:
		return
	if running():
		retirement_error = _terminate_owned_process()
		if retirement_error != OK:
			retirement_confirmed = false
			return
	_pid = -1
	retirement_confirmed = true
	if _stdio != null and _stdio.is_open():
		_stdio.close()
	if _stderr != null and _stderr.is_open():
		_stderr.close()
	_stdio = null
	_stderr = null
	_error_pending.clear()
	_error_lines.clear()
	_discard_error_line = false
