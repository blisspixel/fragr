extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("test_notary_audio: " + message)

func _actor(id: String = "drone", phase: String = "moving", y: float = 5.5, started: int = 10) -> Dictionary:
	return {"id": id, "x": 2.0, "y": y, "z": 0.0, "hp": 0 if phase == "dead" else 50, "just_fired": false,
		"campaign": {"side": "union", "kind": "notary", "phase": phase, "phase_started": started, "phase_ends": started + 16}}

func _shot(id: String = "drone") -> Dictionary:
	return {"shooter_id": id, "hit": false, "damage": 0, "trace": {"weapon": "flechette", "origin": [2, 5.5, 0], "end": [2, 5.5, 10], "impact": {"kind": "range"}}}

func _snapshot(tick: int, actor: Dictionary, shots: Array = []) -> Dictionary:
	return {"tick": tick, "players": [actor], "shot_results": shots}

func _run() -> void:
	_assets()
	var audio: NotaryAudio = NotaryAudio.new()
	root.add_child(audio)
	var notices: Array[String] = []
	audio.notice_requested.connect(func(text: String) -> void: notices.append(text))
	audio.configure_map({"map_id": 1004, "geometry_version": 2, "half_extent": 40, "solids": []})
	var listener: Vector3 = Vector3(0, 1.6, 0)
	var moving: Dictionary = _actor()
	_check(audio.apply(_snapshot(10, moving), listener) == 0 and audio.fans.size() == 1 and audio.fans["drone"].playing,
		"nearby live Notary starts one bounded spatial fan without inventing a shot")
	var fan: AudioStreamPlayer3D = audio.fans["drone"]
	_check(fan.bus == &"Effects" and fan.max_distance == NotaryAudio.DISTANCE and fan.volume_db == -20.0
		and (fan.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"fan stays quieter than cues, attenuates spatially and loops its offline sample")
	_check(notices.size() == 1 and notices[0] == "DUCTED FANS ABOVE THE AWNINGS", "fan onset has a localized mute-safe caption")
	var windup: Dictionary = _actor("drone", "windup", 5.5, 11)
	windup["just_fired"] = true
	_check(audio.apply(_snapshot(11, windup), listener) == 0 and audio.shutter_count == 0,
		"phase and just_fired alone cannot invent a photograph launch")
	_check(audio.apply(_snapshot(30, windup), listener) == 0 and audio.shutter_count == 0,
		"expired held windup never fires from a client timer")
	var real: Dictionary = _snapshot(31, _actor("drone", "firing", 5.5, 31), [_shot(), _shot()])
	var preserved: Dictionary = real.duplicate(true)
	_check(audio.apply(real, listener) == 1 and audio.shutter_count == 1 and real == preserved,
		"resolved shot provenance creates one cue per actor/tick despite duplicate evidence")
	_check(audio.apply(real, listener) == 0 and audio.apply(_snapshot(30, moving, [_shot()]), listener) == 0
		and audio.shutter_count == 1, "duplicate and out-of-order snapshots never replay cues")
	audio.configure_map({"map_id": 1004, "geometry_version": 2, "half_extent": 40, "solids": []})
	_check(audio.apply(real, listener) == 0 and audio.fans["drone"] == fan, "same-map clinic handoff retains phase/shot history and fan voice")
	var dead: Dictionary = _actor("drone", "dead", 4.0, 32)
	_check(audio.apply(_snapshot(32, dead), listener) == 0 and audio.fans.is_empty() and audio.crash_count == 0,
		"airborne death silences fans without predicting ground impact")
	dead["y"] = 1.5
	_check(audio.apply(_snapshot(33, dead), listener) == 1 and audio.crash_count == 1,
		"authoritative underside arriving at support produces one grounded crash")
	_check(audio.apply(_snapshot(34, dead), listener) == 0 and audio.crash_count == 1, "settled corpse does not replay crash")
	var unknown: Dictionary = _snapshot(35, _actor("late", "dead", 1.5, 32))
	_check(audio.apply(unknown, listener) == 0 and audio.crash_count == 1, "late join to a settled wreck invents no landing event")
	var no_identity: Dictionary = _actor("participant")
	no_identity["campaign"] = {"side": "participant"}
	_check(audio.apply(_snapshot(36, no_identity, [_shot("participant")]), listener) == 0, "callsign or participant shot never acquires Notary sound")
	var far: Dictionary = _actor("far")
	far["x"] = 40.0
	_check(audio.apply(_snapshot(37, far, [_shot("far")]), Vector3.INF) == 0 and audio.fans.is_empty(), "missing listener never allocates a fan or cue")
	var malformed: Dictionary = _actor("broken")
	malformed["x"] = INF
	_check(audio.apply(_snapshot(38, malformed, [_shot("broken")]), listener) == 0, "invalid actor coordinates cannot reach playback")
	var many: Array[Dictionary] = []
	var shots: Array[Dictionary] = []
	for index: int in range(20):
		many.append(_actor("drone_%s" % index))
		shots.append(_shot("drone_%s" % index))
	var notice_count: int = notices.size()
	_check(audio.apply({"tick": 39, "players": many, "shot_results": shots}, listener) == 20,
		"confirmed simultaneous cues retain resolved launches through a bounded pool")
	_check(notices.size() <= notice_count + 2, "overlapping fans and burst rounds never flood the bounded corner feed")
	_check(audio.fans.size() == NotaryAudio.FAN_VOICES and audio.fan_pool.size() == NotaryAudio.FAN_VOICES
		and audio.cues.size() == NotaryAudio.CUE_VOICES and audio.get_child_count() == 8,
		"fan and cue allocation stay within fixed four-voice pools")
	audio.reset()
	_check(audio.fans.is_empty() and audio._seen.is_empty() and audio.last_tick == -1 and audio.get_child_count() == 8,
		"disconnect resets facts without leaking or growing voice pools")
	audio.configure_map({"map_id": 1004, "geometry_version": 2, "half_extent": 40,
		"solids": [{"min_x": 1, "max_x": 3, "min_z": -1, "max_z": 1, "bottom": 0, "top": 2}]})
	audio.apply(_snapshot(40, _actor("raised", "dead", 6.0, 40)), listener)
	_check(audio.apply(_snapshot(41, _actor("raised", "dead", 3.5, 40)), listener) == 1,
		"crash registers at raised authoritative support rather than only ground zero")
	# An emitter removed after trading shots still has provenance from the prior snapshot.
	audio.apply(_snapshot(42, _actor("trade")), listener)
	_check(audio.apply({"tick": 43, "players": [], "shot_results": [_shot("trade")]}, listener) == 1,
		"previous known Notary identity preserves resolved shot after actor removal")
	audio.reset()
	var muted_fallback: NotaryAudio = NotaryAudio.new()
	root.add_child(muted_fallback)
	muted_fallback._streams.clear()
	muted_fallback.configure_map({"map_id": 1004, "geometry_version": 2, "half_extent": 40, "solids": []})
	var fallback_notices: Array[String] = []
	muted_fallback.notice_requested.connect(func(text: String) -> void: fallback_notices.append(text))
	muted_fallback.apply(_snapshot(50, _actor()), listener)
	muted_fallback.apply(_snapshot(51, _actor("drone", "firing", 5.5, 51), [_shot()]), listener)
	_check(fallback_notices.size() == 2 and muted_fallback.fans.is_empty() and muted_fallback.cues.is_empty(),
		"missing samples retain captions without allocating unusable audio nodes")
	muted_fallback.free()
	audio.free()
	if failures == 0:
		print("test_notary_audio: PASS original assets, quiet loop, resolved launch, supported crash, late join, lifecycle and bounded pools")
	quit(0 if failures == 0 else 1)

func _assets() -> void:
	var path: String = NotaryAudio.DIRECTORY + "soundscape-manifest.json"
	_check(FileAccess.file_exists(path), "offline manifest exists")
	if not FileAccess.file_exists(path):
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(manifest is Dictionary and manifest.get("source_sha256") == FileAccess.get_sha256(str(manifest.get("source", ""))),
		"committed source hash proves cue freshness")
	if not manifest is Dictionary or not manifest.get("sounds") is Array:
		return
	_check(manifest["sounds"].size() == 3 and manifest["format"] == "pcm_s16le_mono_24000", "three original mono PCM cues declared")
	for receipt: Dictionary in manifest["sounds"]:
		var file: String = NotaryAudio.DIRECTORY + str(receipt["file"])
		var stream: AudioStreamWAV = load(file) as AudioStreamWAV
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(file)
		_check(stream != null and stream.mix_rate == 24000 and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo,
			"committed cue loads in pinned Godot: " + str(receipt["file"]))
		_check(FileAccess.get_sha256(file) == receipt["sha256"] and bytes.size() == int(receipt["bytes"])
			and bytes.size() == 44 + int(receipt["samples"]) * 2, "sample and byte bounds match receipt")
		_check(float(receipt["peak_linear"]) > 0.05 and float(receipt["peak_linear"]) < 0.9
			and float(receipt["rms_linear"]) > 0.01 and float(receipt["seconds"]) <= 2.0, "cue is nonsilent, unclipped and bounded")
		var energy: int = 0
		for index: int in range(44, bytes.size(), 2):
			var sample: int = bytes[index] | (bytes[index + 1] << 8)
			if sample >= 32768:
				sample -= 65536
			energy += absi(sample)
		_check(energy > int(receipt["samples"]) * 100, "actual committed PCM contains audible samples")
