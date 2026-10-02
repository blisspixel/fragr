extends SceneTree

const DIRECTORY: String = "res://assets/story/"
const SCENES: Array[String] = ["l03_l04", "m04_arrival", "l04_l05", "m05_arrival", "l05_l06", "m06_arrival", "l06_l07"]
var failures: int = 0
var settings_path: String = ""

func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://campaign-audio-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	_run.call_deferred()

func _finalize() -> void:
	MouseCapture.release()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_campaign_audio: " + message)

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "audiogen-manifest.json"))
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../tools/audiogen/specs/campaign-transitions-20260930.json"))
	_check(manifest["entries"].size() == 16 and spec["items"].size() == 7, "exact bounded twelve narrations, two ambiences and two grenade effects are committed")
	var requests: Dictionary[String, Dictionary] = {}
	var m05_spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../tools/audiogen/specs/m05-transitions-20260930.json"))
	spec["items"].append_array(m05_spec["items"])
	var m06_spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../tools/audiogen/specs/m06-port-20261001.json"))
	spec["items"].append_array(m06_spec["items"])
	for item: Dictionary in spec["items"]:
		requests[item["name"]] = item
	_check_key_images()
	for scene_id: String in SCENES:
		var scene: Dictionary = StoryScene.load_scene(scene_id)
		_check(scene["shots"].size() == (1 if scene_id in ["m05_arrival", "l06_l07"] else 2), "bounded scene structure retained: " + scene_id)
		for shot: Dictionary in scene["shots"]:
			var name: String = "voice/en/%s/%s" % [scene_id, str(shot["id"]).to_lower()]
			var receipt: Dictionary = manifest["entries"][name]
			var request: Dictionary = requests[name]
			var caption: String = TranslationServer.translate(shot["caption_key"])
			_check(caption == request["text"] and receipt["prompt"] == caption, "actual translated caption exactly matches submitted and recorded narration: " + name)
			_check(not shot.has("speaker_key") and receipt["voice"] == "SAz9YHcvj6GT2YYXdXww", "neutral narrator never acquires a named character label")
			_check(shot["timing"] == "narration" and float(shot["hold"]) == 1.0 and str(shot["narration"]).contains("{locale}"), "existing locale-aware narration and one-second hold used")
			var path: String = StoryScene.narration_path(shot, "en_US")
			_check(path == DIRECTORY + receipt["file"] and StoryScene.narration_path(shot, "fr_CA") == path, "missing localized voice falls back to actual English asset")
			var stream: AudioStreamMP3 = load(path) as AudioStreamMP3
			_check(stream != null and not stream.loop and stream.get_length() > 1.0 and stream.get_length() < 30.0, "narration decodes with finite positive bounded duration")
			_check(FileAccess.get_file_as_bytes(path).size() == int(receipt["bytes"]), "committed narration bytes match generation receipt")
			_measure(stream, name)
	var ambience_path: String = DIRECTORY + "ambience/low_water_runoff.wav"
	var ambience: AudioStreamWAV = load(ambience_path) as AudioStreamWAV
	var bed: Dictionary = manifest["entries"]["ambience/low_water_runoff"]
	_check(ambience != null and ambience.format == AudioStreamWAV.FORMAT_16_BITS and ambience.mix_rate == 24000 and ambience.stereo,
		"runoff retains original stereo 24 kHz 16-bit PCM")
	_check(ambience.loop_mode == AudioStreamWAV.LOOP_FORWARD and absf(ambience.get_length() - 6.0) < 0.01,
		"arrival runoff loops the complete bounded six-second asset")
	_check(bed["looping"] and bed["prompt"] == requests["ambience/low_water_runoff"]["prompt"] \
		and FileAccess.get_file_as_bytes(ambience_path).size() == int(bed["bytes"]), "ambience source and byte receipt match committed asset")
	_measure(ambience, "ambience/low_water_runoff")
	var lunar_path: String = DIRECTORY + "ambience/lunar_port_utility.wav"
	var lunar_bed: AudioStreamWAV = load(lunar_path) as AudioStreamWAV
	_check(lunar_bed != null and lunar_bed.format == AudioStreamWAV.FORMAT_16_BITS and lunar_bed.stereo \
		and lunar_bed.mix_rate == 24000 and lunar_bed.loop_mode == AudioStreamWAV.LOOP_FORWARD \
		and absf(lunar_bed.get_length() - 6.0) < 0.01, "lunar utility ambience is a bounded stereo six-second loop")
	var lunar_receipt: Dictionary = manifest["entries"]["ambience/lunar_port_utility"]
	_check(lunar_receipt["looping"] and lunar_receipt["prompt"] == requests["ambience/lunar_port_utility"]["prompt"] \
		and FileAccess.get_file_as_bytes(lunar_path).size() == int(lunar_receipt["bytes"]), "lunar utility source matches exact committed batch")
	_measure(lunar_bed, "ambience/lunar_port_utility")
	for name: String in ["effects/grenade_bounce", "effects/grenade_blast"]:
		var receipt: Dictionary = manifest["entries"][name]
		var effect: AudioStreamWAV = load(DIRECTORY + receipt["file"]) as AudioStreamWAV
		_check(effect != null and effect.loop_mode == AudioStreamWAV.LOOP_DISABLED and absf(effect.get_length() - float(requests[name]["seconds"])) <= 0.05,
			"bounded grenade effects decode without looping")
		_check(FileAccess.get_file_as_bytes(DIRECTORY + receipt["file"]).size() == int(receipt["bytes"]) and receipt["prompt"] == requests[name]["prompt"], "effect source matches exact committed receipt")
		_measure(effect, name)
	await _playback()
	await _fallback()
	await process_frame
	if failures == 0:
		print("test_campaign_audio: PASS exact captions/spec, decoded energy/duration, Voice/Effects routing, locale, timing, skip and text fallback")
	quit(0 if failures == 0 else 1)

func _check_key_images() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/story/m06-key-images-20261001/manifest.json"))
	_check(source["assets"].size() == 2 and float(source["estimated_batch_usd"]) <= 1.5, "two bounded selected lunar story illustrations have source receipts")
	for entry: Dictionary in source["assets"]:
		var path: String = entry["runtime_path"]
		var texture: Texture2D = load(path) as Texture2D
		_check(texture != null and texture.get_size() == Vector2(672, 378)
			and FileAccess.get_sha256(path) == entry["processed_sha256"], "lunar story keeper loads and matches inspected prepared source")
		_check(FileAccess.get_sha256("res://art/story/m06-key-images-20261001/" + str(entry["raw"])) == entry["raw_sha256"], "metadata-free original story source remains exact")
	var arrival: Dictionary = StoryScene.load_scene("m06_arrival")
	var departure: Dictionary = StoryScene.load_scene("l06_l07")
	_check(arrival["shots"][0]["image"] == arrival["shots"][1]["image"], "arrival framing pages keep the same establishing ship image")
	_check(arrival["shots"][0]["image"] == source["assets"][0]["runtime_path"]
		and departure["shots"][0]["image"] == source["assets"][1]["runtime_path"], "lunar images bind only to their frozen framing scenes")

func _measure(stream: AudioStream, label: String) -> void:
	if stream == null:
		return
	var playback: AudioStreamPlayback = stream.instantiate_playback()
	var energy: float = 0.0
	var peak: float = 0.0
	var count: int = 0
	for fraction: float in [0.2, 0.5, 0.75]:
		playback.start(stream.get_length() * fraction)
		var frames: PackedVector2Array = playback.mix_audio(1.0, 4096)
		for sample: Vector2 in frames:
			_check(sample.is_finite(), "decoded samples are finite")
			energy += sample.length_squared()
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		count += frames.size() * 2
		playback.stop()
	var rms: float = sqrt(energy / float(maxi(count, 1)))
	_check(count > 0 and peak > 0.005 and rms > 0.0005, "actual decoded sample windows contain positive audio energy: " + label)
	print("test_campaign_audio: decoded ", label, " seconds=", snappedf(stream.get_length(), 0.001), " rms=", snappedf(rms, 0.00001), " peak=", snappedf(peak, 0.00001))

func _start(scene: Dictionary) -> ScenePlayer:
	var player: ScenePlayer = ScenePlayer.new(scene)
	root.add_child(player)
	await process_frame
	await process_frame
	return player

func _playback() -> void:
	var preferences: FragrSettings = FragrSettings.for_tree(self)
	preferences.set_value("gameplay", "story_captions", true)
	_check(preferences.save_to_disk() == OK, "isolated caption preferences saved")
	for scene_id: String in SCENES:
		var scene: Dictionary = StoryScene.load_scene(scene_id)
		var player: ScenePlayer = await _start(scene)
		var completions: Array[int] = [0]
		player.completed.connect(func() -> void: completions[0] += 1)
		_check(player._voiced and player._narration.playing and player._narration.bus == &"Voice", "actual scene starts its committed clip on Voice: " + scene_id)
		_check(player._body.text == tr(scene["shots"][0]["caption_key"]) and player._scroll.visible and player._captions.visible, "actual scene exposes exact caption and caption controls")
		if scene_id in ["m06_arrival", "l06_l07"]:
			_check(player._still_frame.visible and player._still.texture != null
				and player._still.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "actual lunar scene displays its selected pixel image")
		_check(player._speaker.text.is_empty(), "framing narration has no character speaker")
		if scene_id in ["m04_arrival", "m06_arrival"]:
			_check(player._ambience != null and player._ambience.playing and player._ambience.bus == &"Effects" and player._ambience.volume_db == -22.0,
				"arrival bed plays quietly on Effects through existing scene seam")
		# Audio-thread startup can lag the first scene under a concurrent import.
		var deadline: int = Time.get_ticks_msec() + 2000
		while player._narration.get_playback_position() <= 0.02 and Time.get_ticks_msec() < deadline:
			await create_timer(0.05).timeout
		_check(player._narration.get_playback_position() > 0.02, "actual committed narration playback advances")
		if DisplayServer.get_name() != "headless" and scene_id == "m04_arrival":
			await RenderingServer.frame_post_draw
			var directory: String = ProjectSettings.globalize_path("res://../.agents/campaign-transition-audio-20260930")
			DirAccess.make_dir_recursive_absolute(directory)
			root.get_texture().get_image().save_png(directory.path_join("arrival-voice-captions.png"))
			print("test_campaign_audio: rendered actual arrival caption/control receipt, Voiceplaying=", player._narration.playing, " Effectsplaying=", player._ambience.playing)
		player.toggle_captions()
		_check(not player._scroll.visible, "caption toggle acts on real voiced scene")
		player.toggle_captions()
		if scene["shots"].size() > 1:
			player._on_narration_finished()
			player.set_process(false)
			player._process(0.5)
			_check(player.page == 0, "narration hold retains current page before expiry")
			player._process(0.6)
			_check(player.page == 1 and player._narration.playing, "narration hold advances to the real second clip")
		player.toggle_captions()
		_check(not player._scroll.visible, "captions disabled during actual final-page speech")
		var narration_completions: Array[int] = [0]
		player._narration.finished.connect(func() -> void: narration_completions[0] += 1)
		player._narration.seek(maxf(0.0, player._narration.stream.get_length() - 0.03))
		deadline = Time.get_ticks_msec() + 2000
		# The mixer can report inactive before the main thread emits finished.
		# Wait for the same real event that refreshes the reader's captions.
		while narration_completions[0] == 0 and Time.get_ticks_msec() < deadline:
			await create_timer(0.05).timeout
		_check(narration_completions[0] == 1,
			"actual final narration emits exactly one completion: %s (page=%d playing=%s voiced=%s caption_visible=%s)" % [
				scene_id, player.page, player._narration.playing, player._voiced, player._scroll.visible])
		_check(not player._narration.playing and player._scroll.visible and not player._voiced,
			"actual final narration completion reveals captions for the waiting reader even with captions disabled: " + scene_id)
		player._process(2.0)
		_check(player.page == scene["shots"].size() - 1 and not player.finished and completions[0] == 0, "last voiced page still waits for deliberate reader completion")
		player._skip.pressed.emit()
		player.finish()
		_check(completions[0] == 1 and not player._narration.playing and (player._ambience == null or not player._ambience.playing), "skip stops all real scene players and completes once")
		player.free()

func _fallback() -> void:
	for id: String in ["m04_arrival", "m06_arrival", "l06_l07"]:
		await _fallback_scene(id)

func _fallback_scene(id: String) -> void:
	var scene: Dictionary = StoryScene.load_scene(id).duplicate(true)
	for shot: Dictionary in scene["shots"]:
		shot["narration"] = "res://assets/story/voice/{locale}/unavailable.mp3"
		if id in ["m06_arrival", "l06_l07"]:
			shot["image"] = "res://assets/story/images/unavailable.png"
	if scene.has("ambience"):
		scene["ambience"]["path"] = "res://assets/story/ambience/unavailable.wav"
	var preferences: FragrSettings = FragrSettings.for_tree(self)
	preferences.set_value("gameplay", "story_captions", false)
	_check(preferences.save_to_disk() == OK, "isolated captions-off preference saved")
	var player: ScenePlayer = await _start(scene)
	_check(not player._voiced and player._narration.stream == null and player._ambience == null \
		and player._scroll.visible and not player._captions.visible, "missing clips and bed retain readable text even with captions disabled")
	if id in ["m06_arrival", "l06_l07"]:
		_check(not player._still_frame.visible and player._still.texture == null, "missing lunar image keeps the real text-only layout")
	player._process(60.0)
	_check(player.page == 0 and not player.finished, "missing narration never invents an automatic completion")
	if scene["shots"].size() > 1:
		player.advance()
		_check(player.page == 1 and player._scroll.visible, "reader can proceed normally without any asset: " + id)
	player.finish()
	player.free()
