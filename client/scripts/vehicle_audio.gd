class_name VehicleAudio
extends AudioStreamPlayer3D

## A cached mechanical loop, mixed on the ordinary Effects bus. Engine intensity
## reads authoritative motion and never implies throttle acceptance or damage.
static var _loops: Dictionary[String, AudioStreamWAV] = {}
const RATE: int = 22050

func _ready() -> void:
	bus = "Effects"
	unit_size = 4.0
	max_distance = 70.0
	attenuation_filter_cutoff_hz = 2200.0
	volume_db = -28.0

func apply(kind: String, speed: float, occupied: bool, destroyed: bool, audible: bool) -> void:
	if not occupied or destroyed or not audible:
		if playing:
			stop()
		return
	if stream == null:
		stream = _loop(kind)
	var top: float = 32.0 if kind == "light_aircraft" else 14.0 if kind == "boat" else 16.0
	var effort: float = clampf(absf(speed) / top, 0.0, 1.0)
	pitch_scale = 0.85 + effort * (0.65 if kind == "light_aircraft" else 0.95)
	volume_db = -28.0 + effort * 6.0
	if not playing:
		play()

static func _loop(kind: String) -> AudioStreamWAV:
	if _loops.has(kind):
		return _loops[kind]
	var fundamental: float = 95.0 if kind == "light_aircraft" else 42.0 if kind == "boat" else 55.0
	var bytes: PackedByteArray = []
	bytes.resize(RATE * 2)
	for index: int in range(RATE):
		var t: float = float(index) / RATE
		var cycle: float = t * TAU * fundamental
		var pulse: float = sin(cycle) * 0.40 + sin(cycle * 2.0) * 0.19 + sin(cycle * 3.0) * 0.10
		var rattle: float = sin(cycle * 7.0 + sin(cycle * 2.0)) * 0.055
		var envelope: float = 0.85 + 0.15 * sin(t * TAU * 7.0)
		bytes.encode_s16(index * 2, int(clampf((pulse + rattle) * envelope, -1, 1) * 32767))
	var loop: AudioStreamWAV = AudioStreamWAV.new()
	loop.format = AudioStreamWAV.FORMAT_16_BITS
	loop.mix_rate = RATE
	loop.stereo = false
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = RATE
	loop.data = bytes
	_loops[kind] = loop
	return loop
