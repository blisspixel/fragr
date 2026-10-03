class_name SabotageAudio
extends RefCounted

## Placeholder Sabotage sounds synthesized once in code, so the mode is
## readable by ear at $0: the charge's timer beep, the hum a carried or loose
## charge makes up close, the plant and defuse cues and the detonation. A later
## audio batch replaces these by name.

const RATE: int = 22050

static var _cache: Dictionary = {}


static func _stream(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


static func _tone(frequency: float, seconds: float, volume: float, attack: float = 0.004) -> PackedFloat32Array:
	var count: int = int(seconds * RATE)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for i: int in range(count):
		var t: float = float(i) / RATE
		var envelope: float = minf(t / attack, 1.0) * exp(-4.0 * t / seconds)
		# A square edge keeps it audible over gunfire, like a real timer.
		var wave: float = sin(TAU * frequency * t) * 0.7 + signf(sin(TAU * frequency * t)) * 0.3
		samples[i] = wave * envelope * volume
	return samples


## The charge's timer beep. Pitch rises from the player as time runs out.
static func beep() -> AudioStreamWAV:
	if not _cache.has("beep"):
		_cache["beep"] = _stream(_tone(1480.0, 0.09, 0.55))
	return _cache["beep"]


## A low electrical hum, looped: the charge heard within ten metres.
static func hum() -> AudioStreamWAV:
	if not _cache.has("hum"):
		var count: int = int(0.5 * RATE)
		var samples: PackedFloat32Array = PackedFloat32Array()
		samples.resize(count)
		for i: int in range(count):
			var t: float = float(i) / RATE
			samples[i] = (sin(TAU * 60.0 * t) * 0.6 + sin(TAU * 120.0 * t) * 0.3 + sin(TAU * 180.0 * t) * 0.1) * 0.35
		_cache["hum"] = _stream(samples, true)
	return _cache["hum"]


## Two quick clicks: a plant or defuse has started.
static func arm() -> AudioStreamWAV:
	if not _cache.has("arm"):
		var samples: PackedFloat32Array = _tone(900.0, 0.05, 0.5)
		var gap: PackedFloat32Array = PackedFloat32Array()
		gap.resize(int(0.05 * RATE))
		samples.append_array(gap)
		samples.append_array(_tone(900.0, 0.05, 0.5))
		_cache["arm"] = _stream(samples)
	return _cache["arm"]


## A falling two-tone: the charge is planted and running.
static func planted() -> AudioStreamWAV:
	if not _cache.has("planted"):
		var samples: PackedFloat32Array = _tone(1200.0, 0.12, 0.6)
		samples.append_array(_tone(800.0, 0.22, 0.6))
		_cache["planted"] = _stream(samples)
	return _cache["planted"]


## A rising two-tone: defused.
static func defused() -> AudioStreamWAV:
	if not _cache.has("defused"):
		var samples: PackedFloat32Array = _tone(700.0, 0.12, 0.55)
		samples.append_array(_tone(1050.0, 0.2, 0.55))
		_cache["defused"] = _stream(samples)
	return _cache["defused"]


## The detonation: a filtered noise crack with a long low tail. The noise is
## a fixed sequence, so the sound is the same every time.
static func detonation() -> AudioStreamWAV:
	if not _cache.has("detonation"):
		var count: int = int(1.6 * RATE)
		var samples: PackedFloat32Array = PackedFloat32Array()
		samples.resize(count)
		var state: int = 0x2545F491
		var low: float = 0.0
		for i: int in range(count):
			state = (state * 1103515245 + 12345) & 0x7fffffff
			var noise: float = float(state) / float(0x7fffffff) * 2.0 - 1.0
			low = low * 0.92 + noise * 0.08
			var t: float = float(i) / RATE
			var crack: float = noise * exp(-30.0 * t)
			var rumble: float = (low * 6.0 + sin(TAU * 42.0 * t) * 0.4) * exp(-2.2 * t)
			samples[i] = clampf(crack * 0.8 + rumble, -1.0, 1.0) * 0.9
		_cache["detonation"] = _stream(samples)
	return _cache["detonation"]


## Remaining charge ticks at which the next timer beep falls due: every five
## seconds, then every second for the last ten, twice a second in the last five.
static func next_beep(remaining: int) -> int:
	if remaining > 200:
		return int(ceil(float(remaining) / 100.0) - 1.0) * 100
	if remaining > 100:
		return remaining - 20
	return remaining - 10


## The beep's pitch for the remaining share of the charge's clock.
static func beep_pitch(remaining_share: float) -> float:
	return 1.0 + (1.0 - clampf(remaining_share, 0.0, 1.0)) * 0.6
