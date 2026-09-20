class_name LocalProcess
extends RefCounted

## Only owns the process returned by execute_with_pipe, never a discovered PID.
var _pid: int = -1
var _stdio: FileAccess
var _stderr: FileAccess
var _error_pending: PackedByteArray = PackedByteArray()
var _error_lines: Array[String] = []
var _discard_error_line: bool = false

func start(executable: String, arguments: PackedStringArray) -> bool:
	var child: Dictionary = OS.execute_with_pipe(executable, arguments, false)
	if child.is_empty():
		return false
	_pid = int(child["pid"])
	_stdio = child["stdio"] as FileAccess
	_stderr = child["stderr"] as FileAccess
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
	return _pid > 0 and OS.is_process_running(_pid)

func request_stop() -> void:
	if _stdio != null and _stdio.is_open():
		if running():
			_stdio.store_string("{\"type\":\"shutdown\"}\n")
			_stdio.flush()
		# Closing the lease also handles a short or failed control write.
		_stdio.close()

func dispose() -> void:
	if running():
		OS.kill(_pid)
	_pid = -1
	if _stdio != null and _stdio.is_open():
		_stdio.close()
	if _stderr != null and _stderr.is_open():
		_stderr.close()
	_stdio = null
	_stderr = null
	_error_pending.clear()
	_error_lines.clear()
	_discard_error_line = false
