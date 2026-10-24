extends SceneTree

## Offline procedural cue for a weapon, health or armour pad coming back on
## its clock: a heavy latch clack, then a short two-step servo rise and a
## ring-down, heard where the pad is. No external request, no charge.

const RATE: int = 24000
const SAMPLES: int = 16800
const SEED: int = 23017
const OUTPUT: String = "res://assets/audio/pickup/pad_return.wav"
const MANIFEST: String = "res://assets/audio/pickup/pad_return-manifest.json"

func _initialize() -> void:
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Could not open pad return WAV for writing")
		quit(1)
		return
	file.big_endian = false
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + SAMPLES * 2)
	file.store_buffer("WAVEfmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(RATE)
	file.store_32(RATE * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(SAMPLES * 2)
	var seed: int = SEED
	var phase: float = 0.0
	for index: int in range(SAMPLES):
		seed = (seed * 1664525 + 1013904223) & 0x7fffffff
		var noise: float = float(seed) / 1073741824.0 - 1.0
		var t: float = float(index) / RATE
		var sample: float = 0.0
		# Latch: a short noise burst through a low body resonance.
		if index < 1900:
			var latch_env: float = exp(-float(index) / 260.0)
			sample += noise * 0.42 * latch_env
			sample += sin(float(index) * TAU * 96.0 / RATE) * 0.5 * exp(-float(index) / 900.0)
		# Servo: two rising steps, square-ish so it reads through gunfire.
		if t > 0.07 and t < 0.52:
			var step: float = 330.0 if t < 0.24 else 495.0
			var glide: float = step * (1.0 + 0.18 * fmod(t - 0.07, 0.17) / 0.17)
			phase += TAU * glide / RATE
			var tone: float = clampf(sin(phase) * 2.4, -1.0, 1.0)
			var servo_env: float = minf((t - 0.07) / 0.02, 1.0) * clampf((0.52 - t) / 0.08, 0.0, 1.0)
			sample += tone * 0.16 * servo_env
		# Ring-down: the pad plate settling.
		if t > 0.46:
			var age: float = t - 0.46
			sample += sin(age * TAU * 1240.0) * 0.12 * exp(-age / 0.09)
			sample += sin(age * TAU * 1870.0) * 0.06 * exp(-age / 0.05)
		var pcm: int = roundi(clampf(sample, -0.95, 0.95) * 32767.0)
		file.store_16(pcm & 0xffff)
	file.close()
	var manifest: Dictionary = {
		"file": "pickup/pad_return.wav",
		"kind": "offline_procedural",
		"generator": "bake_pad_return.gd",
		"engine": "Godot 4.7.2-stable",
		"seed": SEED,
		"format": "pcm_s16le_mono_24000",
		"samples": SAMPLES,
		"bytes": 44 + SAMPLES * 2,
		"sha256": FileAccess.get_sha256(OUTPUT),
	}
	var record: FileAccess = FileAccess.open(MANIFEST, FileAccess.WRITE)
	if record == null:
		push_error("Could not write pad return WAV manifest")
		quit(1)
		return
	record.store_string(JSON.stringify(manifest, "  ") + "\n")
	record.close()
	quit()
