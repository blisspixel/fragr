extends SceneTree

## Original offline ducted fan, mechanical shutter and grounded casing impact.
const RATE: int = 24000
const SEED: int = 261004
const SOURCE: String = "res://assets/audio/notary/bake_soundscape.gd"
const DIRECTORY: String = "res://assets/audio/notary/"
const SOUNDS: Array[Dictionary] = [
	{"file": "fan.wav", "seconds": 2.0, "loop": true, "purpose": "live Notary ducted fan near the listener"},
	{"file": "shutter.wav", "seconds": 0.18, "loop": false, "purpose": "resolved Notary photograph round, mechanical shutter"},
	{"file": "crash.wav", "seconds": 0.65, "loop": false, "purpose": "server-positioned Notary wreck contacting registered support"},
]

func _initialize() -> void:
	var receipts: Array[Dictionary] = []
	for index: int in range(SOUNDS.size()):
		var spec: Dictionary = SOUNDS[index]
		var count: int = roundi(float(spec["seconds"]) * RATE)
		var file: FileAccess = FileAccess.open(DIRECTORY + str(spec["file"]), FileAccess.WRITE)
		if file == null:
			push_error("notary_soundscape_bake: cannot write cue")
			quit(1)
			return
		_header(file, count)
		var seed: int = SEED + index
		var peak: float = 0.0
		var sum: float = 0.0
		for sample_index: int in range(count):
			seed = (seed * 1664525 + 1013904223) & 0x7fffffff
			var noise: float = float(seed) / 1073741824.0 - 1.0
			var t: float = float(sample_index) / RATE
			var duration: float = float(spec["seconds"])
			var value: float = _sample(index, t, duration, noise)
			var pcm: int = roundi(clampf(value, -0.9, 0.9) * 32767.0)
			peak = maxf(peak, absf(float(pcm) / 32767.0))
			sum += pow(float(pcm) / 32767.0, 2.0)
			file.store_16(pcm & 0xffff)
		file.close()
		var entry: Dictionary = spec.duplicate(true)
		entry.merge({"samples": count, "bytes": 44 + count * 2, "peak_linear": snappedf(peak, 0.0001),
			"rms_linear": snappedf(sqrt(sum / count), 0.0001), "sha256": FileAccess.get_sha256(DIRECTORY + str(spec["file"]))})
		receipts.append(entry)
	var manifest: FileAccess = FileAccess.open(DIRECTORY + "soundscape-manifest.json", FileAccess.WRITE)
	if manifest == null:
		push_error("notary_soundscape_bake: cannot write receipt")
		quit(1)
		return
	manifest.store_string(JSON.stringify({"kind": "original_offline_procedural", "source": SOURCE,
		"source_sha256": FileAccess.get_sha256(SOURCE), "engine": "Godot 4.7.2-stable", "seed": SEED,
		"format": "pcm_s16le_mono_24000", "sounds": receipts}, "  ") + "\n")
	manifest.close()
	print("notary_soundscape_bake: PASS")
	quit()

func _header(file: FileAccess, count: int) -> void:
	file.big_endian = false
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + count * 2)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(RATE)
	file.store_32(RATE * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(count * 2)

func _sample(kind: int, t: float, duration: float, noise: float) -> float:
	if kind == 0:
		# Integer-cycle harmonics make the loop continuous without a tail click.
		var rotation: float = TAU * 138.0 * t
		return (0.23 * sin(rotation) + 0.09 * sin(rotation * 2.0) + 0.025 * sin(rotation * 3.0)) \
			* (0.86 + 0.14 * cos(TAU * 6.0 * t))
	var attack: float = minf(t / 0.002, 1.0)
	var tail: float = maxf(0.0, 1.0 - t / duration)
	if kind == 1:
		var first: float = exp(-t * 85.0) * (0.42 * noise + 0.24 * sin(TAU * 2100.0 * t))
		var latch: float = exp(-maxf(0.0, t - 0.055) * 90.0) * (0.2 * noise + 0.12 * sin(TAU * 1150.0 * t)) if t >= 0.055 else 0.0
		return attack * tail * (first + latch)
	var metal: float = 0.26 * sin(TAU * 173.0 * t) + 0.16 * sin(TAU * 281.0 * t) + 0.11 * sin(TAU * 457.0 * t)
	return attack * tail * (metal * exp(-t * 7.0) + 0.35 * noise * exp(-t * 28.0))
