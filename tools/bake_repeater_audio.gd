extends SceneTree

## Original, deterministic single-shot mechanism and report for the Repeater.
## At ten shots a second the short dry reports form a rattle; every playback
## is a shot cue, never a claim that a trigger hold has completed warmup.
const RATE: int = 48000
const PATH: String = "res://assets/audio/fire_repeater.wav"

func _initialize() -> void:
	var noise: RandomNumberGenerator = RandomNumberGenerator.new()
	noise.seed = 101017
	var frames: int = int(0.095 * RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	var low: float = 0.0
	var previous: float = 0.0
	for frame: int in range(frames):
		var t: float = float(frame) / RATE
		var raw: float = noise.randf_range(-1.0, 1.0)
		low += (raw - low) * 0.28
		var attack: float = minf(t / 0.0005, 1.0)
		var report: float = low * exp(-t * 65.0) * 1.7
		var body: float = sin(TAU * (145.0 * t - 300.0 * t * t)) * exp(-t * 90.0) * 0.38
		var bolt: float = (raw - previous) * exp(-absf(t - 0.028) * 850.0) * 0.18
		previous = raw
		var tail: float = clampf((0.095 - t) / 0.008, 0.0, 1.0)
		var sample: float = tanh((report + body + bolt) * attack) * 0.74 * tail
		data.encode_s16(frame * 2, int(sample * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if stream.save_to_wav(PATH) != OK:
		push_error("bake_repeater_audio: could not write " + PATH)
		quit(1)
		return
	var manifest: FileAccess = FileAccess.open("res://assets/audio/fire_repeater-manifest.json", FileAccess.WRITE)
	if manifest == null:
		quit(1)
		return
	manifest.store_string(JSON.stringify({"source": "tools/bake_repeater_audio.gd", "source_sha256": FileAccess.get_sha256("res://../tools/bake_repeater_audio.gd"),
		"file": "fire_repeater.wav", "sha256": FileAccess.get_sha256(PATH), "seed": 101017, "sample_rate": RATE,
		"channels": 1, "format": "signed 16-bit PCM WAV", "seconds": 0.095, "purpose": "single Repeater shot report"}, "  ") + "\n")
	print("bake_repeater_audio: PASS")
	quit()
