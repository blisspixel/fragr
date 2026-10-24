class_name StutterTrace
extends RefCounted

## The client half of a stutter diagnosis. Off by default; the console's
## `stutter start` or a harness turns it on for one bounded session.
##
## While recording it keeps every drawn frame interval with the script span,
## renderer CPU and GPU time and new pipeline compilations behind it; every
## network poll that delivered messages; every Snapshot with its server tick,
## arrival time and handler cost; every movement Ack; prediction corrections,
## resets and state changes; and camera mode changes. Phase marks split one
## session into steady walking, first fire, reload, death and menu windows.
##
## The server half is `--tick-trace` (or FRAGR_TICK_TRACE). Both name the same
## Snapshot tick, so `StutterReport` joins them without agreeing on a clock.
## While off, each hook costs one boolean test and nothing is measured.

const VERSION: int = 1
## About twenty-three minutes at 144 frames per second.
const MAX_FRAMES: int = 200000
## Over half an hour of Snapshots or Acks at 20 Hz.
const MAX_TICKS: int = 40000
const MAX_EVENTS: int = 20000
const MAX_LABEL: int = 48
## A frame interval past this is a stall, a load or a debugger stop. It is
## kept, clamped, so one absurd value cannot overflow the packed arrays.
const MAX_INTERVAL_US: int = 10000000

var recording: bool = false
var started_usec: int = 0
var started_unix_us: int = 0
var stopped_usec: int = 0
var context: Dictionary = {}
## Stream name to the number of samples refused past its cap.
var dropped: Dictionary = {}

var frame_usec: PackedInt64Array = PackedInt64Array()
var frame_interval_us: PackedInt32Array = PackedInt32Array()
## Time from the first to the last _process callback of the frame that began
## this interval. -1 when the end marker did not run (the first frame).
var frame_script_us: PackedInt32Array = PackedInt32Array()
var frame_render_cpu_us: PackedInt32Array = PackedInt32Array()
var frame_render_gpu_us: PackedInt32Array = PackedInt32Array()
var frame_compiles: PackedInt32Array = PackedInt32Array()
## Remote pawns whose interpolation clock ran past their newest Snapshot.
var frame_remote_starved: PackedInt32Array = PackedInt32Array()
## Camera x, y, z and facing in radians, four floats per frame.
var frame_camera: PackedFloat32Array = PackedFloat32Array()

var poll_usec: PackedInt64Array = PackedInt64Array()
var poll_us: PackedInt32Array = PackedInt32Array()
var poll_packets: PackedInt32Array = PackedInt32Array()
var poll_bytes: PackedInt32Array = PackedInt32Array()

var snapshot_usec: PackedInt64Array = PackedInt64Array()
var snapshot_tick: PackedInt64Array = PackedInt64Array()
var snapshot_handler_us: PackedInt32Array = PackedInt32Array()

var ack_usec: PackedInt64Array = PackedInt64Array()
var ack_seq: PackedInt64Array = PackedInt64Array()
var ack_tick: PackedInt64Array = PackedInt64Array()

var correction_usec: PackedInt64Array = PackedInt64Array()
var correction_tick: PackedInt64Array = PackedInt64Array()
## Same-tick distance between the predicted and authoritative body.
var correction_m: PackedFloat32Array = PackedFloat32Array()
## The visual offset left to ease out after that reconciliation.
var correction_offset_m: PackedFloat32Array = PackedFloat32Array()

## {usec, kind, ...}: mark, camera, prediction_state, prediction_reset.
var events: Array[Dictionary] = []

var _last_frame_usec: int = -1
var _compiles_seen: int = -1
var _view_camera: Vector4 = Vector4(NAN, NAN, NAN, NAN)
var _view_starved: int = 0
var _camera_key: String = ""
var _prediction_reason: String = ""
var _prediction_resets: int = -1
var _corrections_seen: int = -1
var _prediction_seen: bool = false


## Clears every stream and starts a window. `info` describes the session:
## build, renderer, settings, map and role; it is saved as given.
func begin(now_usec: int, unix_us: int, info: Dictionary = {}) -> void:
	_reset_streams()
	events.clear()
	dropped.clear()
	context = info.duplicate(true)
	started_usec = now_usec
	started_unix_us = unix_us
	stopped_usec = 0
	_last_frame_usec = -1
	_compiles_seen = -1
	_view_camera = Vector4(NAN, NAN, NAN, NAN)
	_view_starved = 0
	_camera_key = ""
	_prediction_reason = ""
	_prediction_resets = -1
	_corrections_seen = -1
	_prediction_seen = false
	recording = true


func stop(now_usec: int) -> Dictionary:
	if recording:
		recording = false
		stopped_usec = now_usec
	return to_dictionary()


## One drawn frame, recorded at the start of its _process phase. `script_us`
## is the previous frame's whole _process span; render times are the engine's
## newest measurement in milliseconds. The first call only starts the clock.
func record_frame(now_usec: int, script_us: int, render_cpu_ms: float, render_gpu_ms: float, compiles_total: int) -> void:
	if not recording:
		return
	var previous: int = _last_frame_usec
	_last_frame_usec = now_usec
	var compiled: int = 0 if _compiles_seen < 0 else maxi(0, compiles_total - _compiles_seen)
	_compiles_seen = compiles_total
	if previous < 0 or now_usec <= previous:
		return
	if frame_usec.size() >= MAX_FRAMES:
		_drop("frames")
		return
	frame_usec.append(now_usec)
	frame_interval_us.append(mini(now_usec - previous, MAX_INTERVAL_US))
	frame_script_us.append(clampi(script_us, -1, MAX_INTERVAL_US))
	frame_render_cpu_us.append(_ms_to_us(render_cpu_ms))
	frame_render_gpu_us.append(_ms_to_us(render_gpu_ms))
	frame_compiles.append(compiled)
	frame_remote_starved.append(_view_starved)
	frame_camera.append_array(PackedFloat32Array([_view_camera.x, _view_camera.y, _view_camera.z, _view_camera.w]))


## What the view showed this frame. The next frame record carries it.
func note_view(now_usec: int, camera_key: String, camera: Vector4, remote_starved: int) -> void:
	if not recording:
		return
	_view_camera = camera
	_view_starved = maxi(0, remote_starved)
	if camera_key != _camera_key:
		_event(now_usec, "camera", {"from": _camera_key, "to": camera_key})
		_camera_key = camera_key


## One network poll that delivered at least one message.
func record_poll(now_usec: int, elapsed_us: int, packets: int, bytes: int) -> void:
	if not recording or packets <= 0:
		return
	if poll_usec.size() >= MAX_FRAMES:
		_drop("polls")
		return
	poll_usec.append(now_usec)
	poll_us.append(clampi(elapsed_us, 0, MAX_INTERVAL_US))
	poll_packets.append(packets)
	poll_bytes.append(maxi(0, bytes))


## A validated Snapshot. Only an integral, non-negative tick is kept; the
## network client has already refused malformed messages.
func record_snapshot(tick: Variant, now_usec: int, handler_us: int) -> void:
	if not recording:
		return
	if not _wire_tick(tick):
		_drop("snapshot_ticks")
		return
	if snapshot_usec.size() >= MAX_TICKS:
		_drop("snapshots")
		return
	snapshot_usec.append(now_usec)
	snapshot_tick.append(int(tick))
	snapshot_handler_us.append(clampi(handler_us, 0, MAX_INTERVAL_US))


func record_ack(data: Dictionary, now_usec: int) -> void:
	if not recording:
		return
	if not _wire_tick(data.get("tick")) or not _wire_tick(data.get("seq")):
		_drop("ack_fields")
		return
	if ack_usec.size() >= MAX_TICKS:
		_drop("acks")
		return
	ack_usec.append(now_usec)
	ack_seq.append(int(data["seq"]))
	ack_tick.append(int(data["tick"]))


## Reads the predictor's own counters, so the predictor needs no hook. Call
## after each Ack and once a frame; a reset from the frame clock (ack_lag,
## ack_timeout) is seen on that frame.
func observe_prediction(predictor: LocalPrediction, now_usec: int) -> void:
	if not recording or predictor == null:
		return
	if not _prediction_seen:
		_prediction_seen = true
		_prediction_resets = predictor.fallback_count
		_corrections_seen = predictor.correction_count
		_prediction_reason = _state_name(predictor)
		_event(now_usec, "prediction_state", {"state": _prediction_reason})
		return
	if predictor.fallback_count < _prediction_resets or predictor.correction_count < _corrections_seen:
		# Someone opened a new measurement window on the predictor.
		_prediction_resets = predictor.fallback_count
		_corrections_seen = predictor.correction_count
	if predictor.fallback_count > _prediction_resets:
		_event(now_usec, "prediction_reset", {"reason": predictor.last_fallback_reason,
			"count": predictor.fallback_count - _prediction_resets})
		_prediction_resets = predictor.fallback_count
	var fresh: int = predictor.correction_count - _corrections_seen
	if fresh > 0:
		var samples: Array[float] = predictor.correction_samples
		var first: int = maxi(0, samples.size() - fresh)
		for index: int in range(first, samples.size()):
			_correction(now_usec, predictor.tick, samples[index], predictor.visual_offset.length())
		_corrections_seen = predictor.correction_count
	var state: String = _state_name(predictor)
	if state != _prediction_reason:
		_event(now_usec, "prediction_state", {"state": state})
		_prediction_reason = state


func mark(label: String, now_usec: int) -> void:
	if not recording:
		return
	var clean: String = label.strip_edges().left(MAX_LABEL)
	_event(now_usec, "mark", {"label": clean if not clean.is_empty() else "mark"})


func to_dictionary() -> Dictionary:
	return {
		"version": VERSION,
		"kind": "fragr_client_stutter_trace",
		"context": context.duplicate(true),
		"started_usec": started_usec,
		"started_unix_us": started_unix_us,
		"stopped_usec": stopped_usec,
		"recording": recording,
		"dropped": dropped.duplicate(),
		"frames": {
			"usec": Array(frame_usec), "interval_us": Array(frame_interval_us),
			"script_us": Array(frame_script_us), "render_cpu_us": Array(frame_render_cpu_us),
			"render_gpu_us": Array(frame_render_gpu_us), "compiles": Array(frame_compiles),
			"remote_starved": Array(frame_remote_starved), "camera": _json_numbers(frame_camera),
		},
		"polls": {"usec": Array(poll_usec), "elapsed_us": Array(poll_us),
			"packets": Array(poll_packets), "bytes": Array(poll_bytes)},
		"snapshots": {"usec": Array(snapshot_usec), "tick": Array(snapshot_tick),
			"handler_us": Array(snapshot_handler_us)},
		"acks": {"usec": Array(ack_usec), "seq": Array(ack_seq), "tick": Array(ack_tick)},
		"corrections": {"usec": Array(correction_usec), "tick": Array(correction_tick),
			"metres": Array(correction_m), "offset_m": Array(correction_offset_m)},
		"events": events.duplicate(true),
	}


## Writes the trace as one JSON document. The directory is created.
static func save(trace: Dictionary, path: String) -> Error:
	var directory: String = path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var made: Error = DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return made
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(trace))
	var error: Error = file.get_error()
	file.close()
	return error


## Cumulative pipeline compilations across every renderer stage. Godot's
## monitors count since start, so a frame's share is the difference.
static func pipeline_compilations() -> int:
	var total: int = 0
	for monitor: Performance.Monitor in [Performance.PIPELINE_COMPILATIONS_CANVAS,
			Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE,
			Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		total += int(Performance.get_monitor(monitor))
	return total


static func _state_name(predictor: LocalPrediction) -> String:
	return "active" if predictor.active() else predictor.fallback_reason


func _correction(now_usec: int, tick: int, metres: float, offset_m: float) -> void:
	if correction_usec.size() >= MAX_TICKS:
		_drop("corrections")
		return
	correction_usec.append(now_usec)
	correction_tick.append(tick)
	correction_m.append(metres if is_finite(metres) else -1.0)
	correction_offset_m.append(offset_m if is_finite(offset_m) else -1.0)


func _event(now_usec: int, kind: String, fields: Dictionary) -> void:
	if events.size() >= MAX_EVENTS:
		_drop("events")
		return
	var event: Dictionary = {"usec": now_usec, "kind": kind}
	event.merge(fields)
	events.append(event)


func _drop(stream: String) -> void:
	dropped[stream] = int(dropped.get(stream, 0)) + 1


func _reset_streams() -> void:
	frame_usec = PackedInt64Array()
	frame_interval_us = PackedInt32Array()
	frame_script_us = PackedInt32Array()
	frame_render_cpu_us = PackedInt32Array()
	frame_render_gpu_us = PackedInt32Array()
	frame_compiles = PackedInt32Array()
	frame_remote_starved = PackedInt32Array()
	frame_camera = PackedFloat32Array()
	poll_usec = PackedInt64Array()
	poll_us = PackedInt32Array()
	poll_packets = PackedInt32Array()
	poll_bytes = PackedInt32Array()
	snapshot_usec = PackedInt64Array()
	snapshot_tick = PackedInt64Array()
	snapshot_handler_us = PackedInt32Array()
	ack_usec = PackedInt64Array()
	ack_seq = PackedInt64Array()
	ack_tick = PackedInt64Array()
	correction_usec = PackedInt64Array()
	correction_tick = PackedInt64Array()
	correction_m = PackedFloat32Array()
	correction_offset_m = PackedFloat32Array()


## JSON has no NaN, and the engine logs an error when asked to write one.
## An unknown camera sample is written as null instead.
static func _json_numbers(values: PackedFloat32Array) -> Array:
	var out: Array = []
	out.resize(values.size())
	for index: int in range(values.size()):
		out[index] = values[index] if is_finite(values[index]) else null
	return out


static func _ms_to_us(ms: float) -> int:
	if not is_finite(ms) or ms < 0.0:
		return -1
	return mini(roundi(ms * 1000.0), MAX_INTERVAL_US)


static func _wire_tick(value: Variant) -> bool:
	if value is int:
		return value >= 0
	if value is float:
		var number: float = value
		return is_finite(number) and number >= 0.0 and number <= 9007199254740991.0 and number == floorf(number)
	return false
