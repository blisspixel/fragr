extends SceneTree

## Original offline interference discharge. No runtime synthesis or service call.
const RATE: int = 24000
const SECONDS: float = 0.48
const SEED: int = 260930
const SOURCE: String = "res://assets/audio/jammer/bake_launch.gd"
const OUTPUT: String = "res://assets/audio/jammer/launch.wav"
const MANIFEST: String = "res://assets/audio/jammer/launch-manifest.json"


func _initialize() -> void:
	var samples: int = roundi(SECONDS * RATE)
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("jammer_launch_bake: cannot write cue")
		quit(1)
		return
	file.big_endian = false
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + samples * 2)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(RATE)
	file.store_32(RATE * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(samples * 2)
	var seed: int = SEED
	var peak: float = 0.0
	var sum_squares: float = 0.0
	for index: int in range(samples):
		seed = (seed * 1664525 + 1013904223) & 0x7fffffff
		var noise: float = float(seed) / 1073741824.0 - 1.0
		var t: float = float(index) / RATE
		var envelope: float = minf(t / 0.006, 1.0) * pow(maxf(0.0, 1.0 - t / SECONDS), 1.6)
		var phase: float = TAU * (580.0 * t - 400.0 * t * t)
		var tremolo: float = 0.65 + 0.35 * sin(TAU * 37.0 * t)
		var tone: float = 0.36 * sin(phase) + 0.16 * sin(phase * 1.97)
		var static_edge: float = 0.14 * noise * exp(-t * 16.0)
		var sample: float = clampf(envelope * (tone * tremolo + static_edge), -0.9, 0.9)
		var pcm: int = roundi(sample * 32767.0)
		peak = maxf(peak, absf(float(pcm) / 32767.0))
		sum_squares += pow(float(pcm) / 32767.0, 2.0)
		file.store_16(pcm & 0xffff)
	file.close()
	var receipt: Dictionary = {
		"kind": "original_offline_procedural", "source": SOURCE,
		"source_sha256": FileAccess.get_sha256(SOURCE), "engine": "Godot 4.7.2-stable",
		"seed": SEED, "format": "pcm_s16le_mono_24000", "file": "launch.wav",
		"purpose": "server-confirmed Jammer interference pulse launch",
		"seconds": SECONDS, "samples": samples, "bytes": 44 + samples * 2,
		"peak_linear": snappedf(peak, 0.0001), "rms_linear": snappedf(sqrt(sum_squares / samples), 0.0001),
		"sha256": FileAccess.get_sha256(OUTPUT)
	}
	var manifest: FileAccess = FileAccess.open(MANIFEST, FileAccess.WRITE)
	if manifest == null:
		push_error("jammer_launch_bake: cannot write receipt")
		quit(1)
		return
	manifest.store_string(JSON.stringify(receipt, "  ") + "\n")
	manifest.close()
	print("jammer_launch_bake: PASS")
	quit()
