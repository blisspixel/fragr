extends SceneTree

class ResetSink extends Node:
	func set_campaign(_enabled: bool) -> void:
		pass
	func apply(_state: Dictionary) -> void:
		pass

class AudioHud extends Node:
	var crawler_caption: CrawlerCaption = null
	var combat_feed: ResetSink = ResetSink.new()
	var equipment_hud: ResetSink = ResetSink.new()
	func _init() -> void:
		add_child(combat_feed)
		add_child(equipment_hud)

class AudioManager extends "res://scripts/game_manager.gd":
	func _apply_arena_sky(_map_name: String = "") -> void:
		pass

var _failures: int = 0


func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_jammer_audio: " + reason)


func _actor(id: String = "emitter", fired: bool = true, x: float = 2.0) -> Dictionary:
	return {"id": id, "name": "Any callsign", "x": x, "y": 1.5, "z": 0.0,
		"hp": 90, "weapon": "Fists", "just_fired": fired,
		"campaign": {"side": "union", "kind": "jammer", "phase": "firing",
			"phase_started": 10, "phase_ends": 11}}


func _run() -> void:
	_check_asset()
	var cues: JammerAudio = JammerAudio.new()
	root.add_child(cues)
	var listener: Vector3 = Vector3(0, 1.6, 0)
	var emitter: Dictionary = _actor()
	var snapshot: Dictionary = {"tick": 10, "players": [emitter, emitter.duplicate(true)]}
	var before: Dictionary = snapshot.duplicate(true)
	_check(cues.apply(snapshot, listener) == 1 and cues.launch_count == 1
		and cues.voices.size() == 1 and cues.voices[0].playing,
		"one confirmed Union launch starts one spatial cue despite duplicate actor rows")
	_check(snapshot == before, "presentation never mutates attack or outcome facts")
	var voice: AudioStreamPlayer3D = cues.voices[0]
	_check(voice.global_position == Vector3(2, 1.5, 0) and voice.bus == &"Effects"
		and voice.max_distance == JammerAudio.DISTANCE and voice.max_polyphony == 1
		and voice.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE,
		"confirmed origin uses the bounded spatial Effects mix")
	_check(cues.apply(snapshot, listener) == 0 and cues.launch_count == 1,
		"repeated snapshot cannot replay a launch")
	snapshot["tick"] = 9
	_check(cues.apply(snapshot, listener) == 0 and cues.launch_count == 1,
		"older snapshot cannot replay a launch")
	var quiet: Dictionary = _actor("quiet", false)
	quiet["campaign"]["phase"] = "windup"
	var wrong_kind: Dictionary = _actor("clerk")
	wrong_kind["campaign"]["kind"] = "clerk"
	var participant: Dictionary = _actor("participant")
	participant["name"] = "Jammer"
	participant["campaign"] = {"side": "participant"}
	var no_identity: Dictionary = _actor("legacy")
	no_identity.erase("campaign")
	var wrong_boolean: Dictionary = _actor("badbool")
	wrong_boolean["just_fired"] = 1
	_check(cues.apply({"tick": 11, "players": [quiet, wrong_kind, participant, no_identity, wrong_boolean]}, listener) == 0,
		"a tell, callsign, ordinary gun or nonboolean fire never invents a pulse launch")
	_check(cues.apply({"tick": 12, "players": [_actor("far", true, 25.0)]}, listener) == 0,
		"out-of-range launches do not allocate a voice")
	var malformed: Array = []
	for coordinate: Variant in [NAN, INF, 8193.0, "2", null]:
		var bad: Dictionary = _actor("bad%s" % malformed.size())
		bad["x"] = coordinate
		malformed.append(bad)
	_check(cues.apply({"tick": 13, "players": malformed}, listener) == 0,
		"invalid source coordinates cannot reach audio playback")
	_check(cues.apply({"tick": 14, "players": [_actor()]}, Vector3.INF) == 0,
		"a missing or invalid listener cannot receive a nearby cue")
	_check(cues.apply({"tick": 14, "players": [_actor()]}, listener) == 0,
		"returning listener cannot replay a fact already consumed while absent")
	var dead_launch: Dictionary = _actor("trade")
	dead_launch["hp"] = 0
	dead_launch["campaign"]["phase"] = "dead"
	_check(cues.apply({"tick": 15, "players": [dead_launch]}, listener) == 1,
		"a launch remains audible when its emitter dies on the same server tick")
	var crowded: Array[Dictionary] = []
	for index: int in range(12):
		crowded.append(_actor("emitter%s" % index))
	_check(cues.apply({"tick": 16, "players": crowded}, listener) == 12
		and cues.voices.size() == JammerAudio.VOICES and cues.get_child_count() == JammerAudio.VOICES,
		"simultaneous launches reuse a fixed voice pool")
	var count: int = cues.launch_count
	for tick: Variant in [-1, 0.5, NAN, "17", null]:
		_check(cues.apply({"tick": tick, "players": [_actor()]}, listener) == 0,
			"invalid tick never reaches deduplication")
	_check(cues.launch_count == count, "rejected snapshots preserve cue accounting")
	cues.reset()
	_check(cues.launch_count == 0 and cues.last_snapshot_tick == -1, "reset clears event accounting")
	for pooled: AudioStreamPlayer3D in cues.voices:
		_check(not pooled.playing, "reset stops every active voice")
	_check(cues.apply({"tick": 1, "players": [_actor()]}, listener) == 1,
		"a new map or connection accepts a fresh tick baseline")
	_check_manager(cues)
	cues.free()
	if _failures == 0:
		print("test_jammer_audio: PASS confirmed cue, validation, deduplication, bounded pool, lifecycle and fresh PCM")
	quit(0 if _failures == 0 else 1)


func _check_asset() -> void:
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/audio/jammer/launch-manifest.json"))
	_check(receipt is Dictionary, "original audio has an offline receipt")
	if not receipt is Dictionary:
		return
	_check(receipt.get("source") == "res://assets/audio/jammer/bake_launch.gd"
		and FileAccess.get_sha256(receipt["source"]) == receipt.get("source_sha256"),
		"committed source matches the baked cue")
	_check(FileAccess.get_sha256(JammerAudio.SOUND_PATH) == receipt.get("sha256"),
		"committed PCM matches its manifest")
	var stream: AudioStreamWAV = load(JammerAudio.SOUND_PATH) as AudioStreamWAV
	_check(stream != null, "launch cue loads through Godot import")
	if stream == null:
		return
	_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 24000
		and not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,
		"cue stays uncompressed mono 16-bit 24 kHz without looping")
	_check(stream.get_length() > 0.1 and stream.get_length() < 0.6
		and is_equal_approx(stream.get_length(), float(receipt["seconds"])),
		"launch cue is short and its measured duration matches the receipt")
	var peak: float = 0.0
	var sum_squares: float = 0.0
	var samples: int = stream.data.size() / 2
	var data: PackedByteArray = stream.data
	for index: int in range(samples):
		var pcm: int = int(data[index * 2]) | (int(data[index * 2 + 1]) << 8)
		if pcm >= 32768:
			pcm -= 65536
		var value: float = float(pcm) / 32767.0
		peak = maxf(peak, absf(value))
		sum_squares += value * value
	var rms: float = sqrt(sum_squares / maxi(samples, 1))
	_check(samples == int(receipt["samples"]) and peak > 0.2 and peak < 0.9 and rms > 0.02,
		"actual PCM is non-silent, bounded and unclipped")
	_check(absf(peak - float(receipt["peak_linear"])) < 0.0001
		and absf(rms - float(receipt["rms_linear"])) < 0.0001,
		"actual PCM level matches the bake receipt")


func _check_manager(cues: JammerAudio) -> void:
	# Attach after entering the tree to exercise the seam without opening a socket.
	var manager: Node = Node.new()
	root.add_child(manager)
	manager.set_script(AudioManager)
	manager.set("jammer_audio", cues)
	var hud: AudioHud = AudioHud.new()
	manager.add_child(hud)
	manager.set("hud", hud)
	var lens: Camera3D = Camera3D.new()
	root.add_child(lens)
	lens.global_position = Vector3(0, 1.6, 0)
	lens.make_current()
	var before: int = cues.launch_count
	manager.call("_present_jammer_launches", {"tick": 2, "players": [_actor("integrated")]})
	_check(cues.launch_count == before + 1, "GameManager routes confirmed snapshots through the camera listener")
	lens.global_position = Vector3(100, 1.6, 0)
	manager.call("_present_jammer_launches", {"tick": 3, "players": [_actor("distant")]})
	_check(cues.launch_count == before + 1, "GameManager uses the actual distant spectator camera")
	manager.call("_on_map_info", {"map_id": 1012, "geometry_version": 2, "half_extent": 24.0, "solids": []})
	_check(cues.launch_count == 0 and cues.last_snapshot_tick == -1,
		"real MapInfo handler clears launch deduplication")
	for voice: AudioStreamPlayer3D in cues.voices:
		_check(not voice.playing, "real MapInfo handler stops active launch voices")
	lens.global_position = Vector3(0, 1.6, 0)
	manager.call("_present_jammer_launches", {"tick": 1, "players": [_actor("reconnected")]})
	_check(cues.launch_count == 1, "map reset admits a new launch baseline")
	manager.call("_clear_world")
	_check(cues.launch_count == 0 and cues.last_snapshot_tick == -1,
		"disconnect world cleanup resets launch state")
	for voice: AudioStreamPlayer3D in cues.voices:
		_check(not voice.playing, "disconnect world cleanup stops active launch voices")
	manager.free()
	lens.free()
