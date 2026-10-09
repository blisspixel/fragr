extends SceneTree

## Original bounded mechanical cues, authored locally as mono PCM.
const OUT: String = "res://assets/audio/assessor"
const RATE: int = 22050

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if not _write("tell", 1.2) or not _write("launch", 0.24):
		push_error("bake_assessor: sound write failed")
		quit(1)
		return
	print("bake_assessor: PASS two original mechanical PCM cues")
	quit(0)

func _write(kind: String, duration: float) -> bool:
	var samples: int = int(float(RATE) * duration)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples * 2)
	for index: int in range(samples):
		var t: float = float(index) / float(RATE)
		var sample: float
		if kind == "tell":
			var local: float = fposmod(t, 0.4)
			var burst: float = clampf(1.0 - local / 0.14, 0.0, 1.0)
			var frequency: float = 330.0 + floorf(t / 0.4) * 110.0
			sample = (sin(TAU * frequency * t) * 0.28 + sin(TAU * 82.5 * t) * 0.1) * burst
		else:
			var decay: float = exp(-t * 20.0) * minf(t * 450.0, 1.0)
			sample = (sin(TAU * (82.0 * t - 70.0 * t * t)) * 0.55 + sin(TAU * 710.0 * t) * 0.18 + sin(TAU * 1117.0 * t) * 0.09) * decay
		var fade: float = minf(1.0, float(samples - index - 1) / 64.0)
		bytes.encode_s16(index * 2, int(clampf(sample * fade, -0.95, 0.95) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream.save_to_wav(ProjectSettings.globalize_path(OUT.path_join(kind + ".wav"))) == OK
