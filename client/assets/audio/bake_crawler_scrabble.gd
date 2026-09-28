extends SceneTree

const RATE: int = 24000
const SAMPLES: int = 24000
const SEED: int = 17041
const OUTPUT: String = "res://assets/audio/crawler_scrabble.wav"
const MANIFEST: String = "res://assets/audio/crawler_scrabble-manifest.json"

func _initialize() -> void:
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Could not open Crawler WAV for writing")
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
	for index: int in range(SAMPLES):
		seed = (seed * 1664525 + 1013904223) & 0x7fffffff
		var noise: float = float(seed) / 1073741824.0 - 1.0
		var sample: float = 0.0
		for start: int in [1400, 6400, 11800, 17200]:
			var age: int = index - start
			if age < 0 or age >= 4100:
				continue
			var attack: float = minf(float(age) / 130.0, 1.0)
			var fade: float = 1.0 - float(age) / 4100.0
			var envelope: float = attack * fade * fade
			var scrape: float = noise * 0.26 + sin(float(age) * TAU * 157.0 / RATE) * 0.13
			var ring: float = sin(float(age) * TAU * 730.0 / RATE) * exp(-float(age) / 1250.0) * 0.12
			sample += scrape * envelope + ring
		var pcm: int = roundi(clampf(sample, -0.95, 0.95) * 32767.0)
		file.store_16(pcm & 0xffff)
	file.close()
	var manifest: Dictionary = {
		"file": "crawler_scrabble.wav",
		"kind": "offline_procedural",
		"generator": "bake_crawler_scrabble.gd",
		"engine": "Godot 4.7.2-stable",
		"seed": SEED,
		"format": "pcm_s16le_mono_24000",
		"samples": SAMPLES,
		"bytes": 44 + SAMPLES * 2,
		"sha256": FileAccess.get_sha256(OUTPUT),
	}
	var record: FileAccess = FileAccess.open(MANIFEST, FileAccess.WRITE)
	if record == null:
		push_error("Could not write Crawler WAV manifest")
		quit(1)
		return
	record.store_string(JSON.stringify(manifest, "  ") + "\n")
	record.close()
	quit()
