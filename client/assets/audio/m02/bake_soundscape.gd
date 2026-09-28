extends SceneTree

## Original, deterministic M02 machinery cues. Run with Godot 4.7.2-stable.
## The two beds use whole-cycle components and periodic mechanical pulses so
## their PCM endpoints can wrap without a crossfade or an imported loop region.

const RATE: int = 24000
const SEED: int = 240927
const OUTPUT_DIR: String = "res://assets/audio/m02/"
const MANIFEST: String = OUTPUT_DIR + "soundscape-manifest.json"
const CUES: Array[Dictionary] = [
	{"file": "ward_machine_loop.wav", "seconds": 2.0, "loop": true, "purpose": "correction ward machine bed"},
	{"file": "ward_machine_stop.wav", "seconds": 1.0, "loop": false, "purpose": "server-confirmed ward machine stop"},
	{"file": "restraint_release.wav", "seconds": 1.4, "loop": false, "purpose": "mechanical restraint release"},
	{"file": "floor_machinery_loop.wav", "seconds": 2.6, "loop": true, "purpose": "processing-floor machinery bed"},
]

func _initialize() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)) != OK:
		push_error("Could not create M02 audio directory")
		quit(1)
		return
	var records: Array[Dictionary] = []
	for cue: Dictionary in CUES:
		var record: Dictionary = _bake(cue)
		if record.is_empty():
			quit(1)
			return
		records.append(record)
	var manifest: Dictionary = {
		"kind": "original_offline_procedural",
		"generator": "bake_soundscape.gd",
		"engine": "Godot 4.7.2-stable",
		"seed": SEED,
		"format": "pcm_s16le_mono_24000",
		"cues": records,
	}
	var file: FileAccess = FileAccess.open(MANIFEST, FileAccess.WRITE)
	if file == null:
		push_error("Could not write M02 soundscape manifest")
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	quit()

func _bake(cue: Dictionary) -> Dictionary:
	var name: String = cue["file"]
	var path: String = OUTPUT_DIR + name
	var samples: int = roundi(float(cue["seconds"]) * RATE)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write M02 audio: " + name)
		return {}
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
		var sample: float = clampf(_sample(name, float(index) / RATE, noise), -0.95, 0.95)
		peak = maxf(peak, absf(sample))
		sum_squares += sample * sample
		file.store_16(roundi(sample * 32767.0) & 0xffff)
	file.close()
	return {
		"file": name,
		"purpose": cue["purpose"],
		"loop": cue["loop"],
		"seconds": cue["seconds"],
		"samples": samples,
		"bytes": 44 + samples * 2,
		"peak_linear": snappedf(peak, 0.0001),
		"rms_linear": snappedf(sqrt(sum_squares / samples), 0.0001),
		"sha256": FileAccess.get_sha256(path),
	}

func _sample(name: String, t: float, noise: float) -> float:
	match name:
		"ward_machine_loop.wav":
			return _ward(t, noise)
		"ward_machine_stop.wav":
			return _stop(t, noise)
		"restraint_release.wav":
			return _restraint(t, noise)
		"floor_machinery_loop.wav":
			return _floor(t, noise)
	return 0.0

func _pulse_age(t: float, offset: float, period: float) -> float:
	return fposmod(t - offset, period)

func _ward(t: float, noise: float) -> float:
	# Every tone completes an integer number of cycles in the two-second bed.
	var drive: float = 0.053 * sin(TAU * 60.0 * t)
	drive += 0.020 * sin(TAU * 120.0 * t)
	drive += 0.011 * sin(TAU * 62.0 * t)
	var age: float = _pulse_age(t, 0.22, 0.5)
	var relay: float = exp(-age * 42.0) * (0.021 * noise + 0.019 * sin(TAU * 710.0 * age))
	return drive + relay

func _stop(t: float, noise: float) -> float:
	var wind_down: float = sin(TAU * (105.0 * t - 35.0 * t * t))
	wind_down *= 0.105 * exp(-t * 3.2) * _falloff(t, 0.68, 0.96)
	var trip: float = _transient(t, 0.035, 0.070, noise, 1200.0) * 0.20
	var settle: float = _transient(t, 0.35, 0.14, noise, 560.0) * 0.095
	return wind_down + trip + settle

func _restraint(t: float, noise: float) -> float:
	var first_latch: float = _transient(t, 0.08, 0.11, noise, 840.0) * 0.24
	var second_latch: float = _transient(t, 0.53, 0.15, noise, 620.0) * 0.19
	var slide_age: float = t - 0.19
	var slide: float = 0.0
	if slide_age > 0.0 and slide_age < 0.82:
		var envelope: float = minf(slide_age / 0.06, 1.0) * _falloff(slide_age, 0.55, 0.82)
		slide = envelope * (0.061 * noise + 0.029 * sin(TAU * 172.0 * slide_age))
	return first_latch + second_latch + slide

func _floor(t: float, noise: float) -> float:
	# 2.6 seconds contains whole cycles of each motor component and five rollers.
	var motors: float = 0.032 * sin(TAU * 50.0 * t)
	motors += 0.016 * sin(TAU * 100.0 * t)
	motors += 0.010 * sin(TAU * 125.0 * t)
	var age: float = _pulse_age(t, 0.24, 0.52)
	var roller: float = exp(-age * 34.0) * (0.018 * noise + 0.015 * sin(TAU * 460.0 * age))
	return motors + roller

func _transient(t: float, onset: float, length: float, noise: float, ring_hz: float) -> float:
	var age: float = t - onset
	if age < 0.0 or age >= length:
		return 0.0
	var envelope: float = minf(age / 0.003, 1.0) * exp(-age * 24.0) * _falloff(age, length * 0.7, length)
	return envelope * (0.66 * noise + 0.34 * sin(TAU * ring_hz * age))

func _falloff(t: float, begin: float, end: float) -> float:
	if t <= begin:
		return 1.0
	if t >= end:
		return 0.0
	var x: float = (t - begin) / (end - begin)
	return 1.0 - x * x * (3.0 - 2.0 * x)
