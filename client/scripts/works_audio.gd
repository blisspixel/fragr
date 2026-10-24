class_name WorksAudio
extends RefCounted
## Small synthesized cues for restoration work and the coalition jetpack,
## built once in memory. Placeholder sound until reviewed recordings exist;
## every cue also has a visual path and a caption.

const RATE: int = 22050
static var _cache: Dictionary[String, AudioStreamWAV] = {}

## Rising projector charge for a Paver preparation, about 1.6 s.
static func projector_charge() -> AudioStreamWAV:
	return _cached("projector_charge", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = PackedFloat32Array()
		var count: int = int(RATE * 1.6)
		samples.resize(count)
		var phase_low: float = 0.0
		var phase_high: float = 0.0
		for index: int in range(count):
			var t: float = float(index) / float(count)
			phase_low += TAU * 58.0 / RATE
			phase_high += TAU * lerpf(320.0, 980.0, t * t) / RATE
			var saw: float = fposmod(phase_low / TAU, 1.0) * 2.0 - 1.0
			var tone: float = sin(phase_high) * (0.25 + 0.45 * t)
			var envelope: float = minf(1.0, t * 12.0) * (1.0 - smoothstep(0.92, 1.0, t))
			samples[index] = (saw * 0.22 + tone) * envelope * 0.7
		return samples)

## One worked pulse: a dull ground thud with a short grind.
static func work_thud() -> AudioStreamWAV:
	return _cached("work_thud", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = PackedFloat32Array()
		var count: int = int(RATE * 0.32)
		samples.resize(count)
		var noise: RandomNumberGenerator = RandomNumberGenerator.new()
		noise.seed = 19019
		var smooth: float = 0.0
		var phase: float = 0.0
		for index: int in range(count):
			var t: float = float(index) / float(count)
			phase += TAU * lerpf(70.0, 38.0, t) / RATE
			smooth = lerpf(smooth, noise.randf_range(-1.0, 1.0), 0.18)
			var envelope: float = exp(-t * 7.0)
			samples[index] = (sin(phase) * 0.8 + smooth * 0.5) * envelope * 0.85
		return samples)

## A seamless thrust loop: rumble under a soft hiss.
static func jet_thrust() -> AudioStreamWAV:
	var stream: AudioStreamWAV = _cached("jet_thrust", func() -> PackedFloat32Array:
		var samples: PackedFloat32Array = PackedFloat32Array()
		var count: int = int(RATE * 0.6)
		samples.resize(count)
		var noise: RandomNumberGenerator = RandomNumberGenerator.new()
		noise.seed = 55019
		var low: float = 0.0
		var high: float = 0.0
		for index: int in range(count):
			var white: float = noise.randf_range(-1.0, 1.0)
			low = lerpf(low, white, 0.04)
			high = lerpf(high, white, 0.35)
			samples[index] = (low * 2.2 + (high - low) * 0.35) * 0.6
		# Cross-fade the loop seam.
		var fade: int = int(RATE * 0.05)
		for index: int in range(fade):
			var w: float = float(index) / float(fade)
			samples[index] = samples[index] * w + samples[count - fade + index] * (1.0 - w)
		return samples)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(RATE * 0.6) - int(RATE * 0.05)
	return stream

static func _cached(key: String, build: Callable) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var samples: PackedFloat32Array = build.call()
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index: int in range(samples.size()):
		bytes.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32000.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	_cache[key] = stream
	return stream
