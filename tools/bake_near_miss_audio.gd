extends SceneTree

## Offline candidate pass-by accents. Fixed seeds, mono signed PCM, no services.
const RATE: int = 48000
const OUTPUT: String = "res://assets/audio/near_miss/"
const RECIPES: Dictionary[String, Dictionary] = {
	"pellet": {"seconds": 0.105, "seed": 71, "low": 2000.0, "high": 7400.0, "tone": 0.0},
	"rifle": {"seconds": 0.145, "seed": 139, "low": 1100.0, "high": 6100.0, "tone": 0.0},
	"rail": {"seconds": 0.19, "seed": 271, "low": 850.0, "high": 5000.0, "tone": 0.1},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for family: String in RECIPES:
		var recipe: Dictionary = RECIPES[family]
		var noise: RandomNumberGenerator = RandomNumberGenerator.new()
		noise.seed = recipe["seed"]
		var frames: int = int(float(recipe["seconds"]) * RATE)
		var data: PackedByteArray = PackedByteArray()
		data.resize(frames * 2)
		var slow: float = 0.0
		var fast: float = 0.0
		var phase: float = 0.0
		for frame: int in range(frames):
			var time: float = float(frame) / RATE
			var progress: float = float(frame) / (frames - 1)
			var raw: float = noise.randf_range(-1.0, 1.0)
			slow += (raw - slow) * (1.0 - exp(-TAU * float(recipe["low"]) / RATE))
			fast += (raw - fast) * (1.0 - exp(-TAU * float(recipe["high"]) / RATE))
			var envelope: float = minf(1.0, time / 0.004) * pow(1.0 - progress, 1.6)
			phase += TAU * lerpf(1900.0, 900.0, progress) / RATE
			var sample: float = ((fast - slow) * 0.8 + sin(phase) * float(recipe["tone"])) * envelope
			data.encode_s16(frame * 2, int(clampf(sample, -0.8, 0.8) * 32767.0))
		var stream: AudioStreamWAV = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = RATE
		stream.stereo = false
		stream.data = data
		if stream.save_to_wav(OUTPUT + family + ".wav") != OK:
			push_error("Unable to save near-miss " + family)
			quit(1)
			return
	print("bake_near_miss_audio: PASS three candidate mono cues")
	quit()
