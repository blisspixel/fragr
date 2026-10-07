class_name LanScan
extends Node

## One pass over addresses this computer can reach. A row is a host that
## answered GET /status. A closed port is not a row. This is not a join.

signal found(address: String, summary: String)
signal finished
const IN_FLIGHT: int = 16
const TIMEOUT_SEC: float = 0.5

var _generation: int = 0
var _running: bool = false
var _pending: Array[String] = []
var _requests: Array[HTTPRequest] = []
var _in_flight: int = 0

func start(addresses: Array) -> void:
	stop()
	_generation += 1
	for entry: Variant in addresses:
		var text: String = str(entry).strip_edges()
		if not text.is_empty() and text not in _pending:
			_pending.append(text)
	if _pending.is_empty():
		finished.emit()
		return
	_running = true
	set_process(true)
	_pump()

func stop() -> void:
	_generation += 1
	_running = false
	_pending.clear()
	_in_flight = 0
	for request: HTTPRequest in _requests:
		if is_instance_valid(request):
			request.cancel_request()
			request.queue_free()
	_requests.clear()
	set_process(false)

func _process(_delta: float) -> void:
	_pump()

func _pump() -> void:
	if not _running:
		return
	var generation: int = _generation
	while _in_flight < IN_FLIGHT and not _pending.is_empty():
		var address: String = _pending.pop_front()
		var endpoint: Dictionary = ServerEndpoint.parse(address)
		if endpoint.is_empty():
			continue
		var request: HTTPRequest = HTTPRequest.new()
		request.timeout = TIMEOUT_SEC
		request.body_size_limit = 4096
		add_child(request)
		_requests.append(request)
		_in_flight += 1
		var started: int = Time.get_ticks_msec()
		var callback: Callable = _on_completed.bind(generation, address, started, request)
		request.request_completed.connect(callback, CONNECT_ONE_SHOT)
		if request.request(str(endpoint["status_url"])) != OK:
			if request.request_completed.is_connected(callback):
				request.request_completed.disconnect(callback)
				_requests.erase(request)
				request.queue_free()
				_in_flight = maxi(0, _in_flight - 1)
			continue
	_maybe_finish()

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int, address: String, started: int, request: HTTPRequest) -> void:
	if is_instance_valid(request):
		_requests.erase(request)
		request.queue_free()
	if generation != _generation:
		return
	_in_flight = maxi(0, _in_flight - 1)
	var parsed: Variant = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		parsed = JSON.parse_string(body.get_string_from_utf8())
	var summary: String = ServerBook.probe_row(result, code, parsed, maxi(0, Time.get_ticks_msec() - started))
	if not summary.is_empty():
		found.emit(address, summary)
	_pump()

func _maybe_finish() -> void:
	if _running and _pending.is_empty() and _in_flight == 0:
		_running = false
		set_process(false)
		finished.emit()
