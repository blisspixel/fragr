class_name BenchmarkCapture
extends RefCounted

## One bounded, already validated authoritative stream reused by every preset.
## Playback reaches the ordinary presenter, never simulation or network ingress.
const MAX_FRAMES: int = 640
const MAX_BYTES: int = 16 * 1024 * 1024
const DURATION_TICKS: int = 560
var map_info: Dictionary = {}
var frames: Array[Dictionary] = []
var bytes: int = 0
var first_tick: int = -1
var last_tick: int = -1
var cursor: int = 0
var error: String = ""
var _digest: HashingContext = HashingContext.new()
var digest: String = ""

func _init() -> void:
	_digest.start(HashingContext.HASH_SHA256)

func accept(snapshot: Dictionary) -> bool:
	if not error.is_empty() or complete():
		return false
	var tick: int = int(snapshot.get("tick", -1))
	if tick <= last_tick:
		return false
	if last_tick >= 0 and tick - last_tick > 10:
		error = "The local match paused during capture. Please run the benchmark again."
		return false
	var encoded: PackedByteArray = JSON.stringify(snapshot).to_utf8_buffer()
	if frames.size() >= MAX_FRAMES or bytes + encoded.size() > MAX_BYTES:
		error = "The benchmark recording exceeded its limit."
		return false
	if first_tick < 0:
		first_tick = tick
	last_tick = tick
	bytes += encoded.size()
	_digest.update(encoded)
	frames.append(snapshot.duplicate(true))
	if complete():
		digest = _digest.finish().hex_encode()
	return true

func complete() -> bool:
	return first_tick >= 0 and last_tick - first_tick >= DURATION_TICKS

func elapsed() -> float:
	return float(maxi(0, last_tick - first_tick)) / 20.0

func rewind() -> void:
	cursor = 0

func due(seconds: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	while cursor < frames.size() and float(int(frames[cursor]["tick"]) - first_tick) / 20.0 <= seconds:
		result.append(frames[cursor].duplicate(true))
		cursor += 1
	return result
