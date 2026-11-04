extends SceneTree

const ACTOR: String = "00000000-0000-0000-0000-000000000001"
var _failures: PackedStringArray = []


func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()


func _event(kind: String = "reload_start", tick: int = 20, actor: String = ACTOR) -> Dictionary:
	# net_client forwards the complete JSON envelope, including type.
	return JSON.parse_string(JSON.stringify({"type": "event", "event": "weapon_handling",
		"player_id": actor, "tick": tick, "kind": kind, "position": [3.0, 0.0, 0.0]})) as Dictionary


func _run() -> void:
	var first: WeaponHandlingAudio = WeaponHandlingAudio.new()
	var second: WeaponHandlingAudio = WeaponHandlingAudio.new()
	root.add_child(first)
	root.add_child(second)
	var event: Dictionary = _event()
	var unchanged: Dictionary = event.duplicate(true)
	for observer: WeaponHandlingAudio in [first, second]:
		_check(observer.present(event, Vector3.ZERO), "each observer hears another fighter's accepted reload")
		_check(observer.present(_event("dry_fire"), Vector3.ZERO), "dry fire is a separate cue even on the same tick")
		_check(observer.reload_count == 1 and observer.dry_count == 1, "each observer starts one of each cue")
		_check(not observer.present(event, Vector3.ZERO), "duplicate reload is silent")
		_check(not observer.present(_event("dry_fire", 19), Vector3.ZERO), "older dry trigger is silent")
		_check(not observer.present(_event("reload_start", 19), Vector3.ZERO), "late reload does not replay")
		_check(observer.reload_count == 1 and observer.dry_count == 1, "replays never increment counts")
	_check(event == unchanged, "presentation leaves server facts untouched")
	for voice: AudioStreamPlayer3D in first.voices:
		_check(voice.playing and voice.stream != null and voice.stream.get_length() > 0.0, "real shipped clips start playback")
		_check(voice.global_position == Vector3(3.0, WeaponHandlingAudio.HANDLING_HEIGHT, 0.0), "source follows supplied feet, independent of actor visibility")
		_check(voice.bus == &"Effects" and voice.max_distance == 24.0 and voice.unit_size == Footsteps.UNIT_SIZE
			and voice.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			and voice.max_polyphony == 1 and voice.volume_db <= -9.0,
			"bounded spatial Effects cue uses a quiet footstep-style rolloff")
	_check(first.voices[0].stream.resource_path == WeaponHandlingAudio.RELOAD_START_SOUND_PATH
		and first.voices[1].stream.resource_path == WeaponHandlingAudio.DRY_FIRE_SOUND_PATH,
		"reload and dry trigger retain distinct clips")
	_check(first.present(_event("reload_start", 21), Vector3.ZERO), "new reload from same actor plays")
	_malformed(first)
	_range(first)
	_bounded(first)
	first.clear()
	_check(first.reload_count == 0 and first.dry_count == 0 and first._latest.is_empty(), "clear resets map/connection history")
	for voice: AudioStreamPlayer3D in first.voices:
		_check(not voice.playing, "clear stops active voices")
	_check(first.present(_event("reload_start", 1), Vector3.ZERO), "new map accepts a fresh clock")
	first.free()
	second.free()
	for failure: String in _failures:
		push_error("test_weapon_handling_audio: " + failure)
	if _failures.is_empty():
		print("test_weapon_handling_audio: PASS observers, validation, late events, range, bounded voices and reset")
	quit(0 if _failures.is_empty() else 1)


func _malformed(cues: WeaponHandlingAudio) -> void:
	var before: int = cues.reload_count + cues.dry_count
	for field: String in ["type", "event", "player_id", "tick", "kind", "position"]:
		var missing: Dictionary = _event("reload_start", 100)
		missing.erase(field)
		_check(not cues.present(missing, Vector3.ZERO), "missing " + field + " refused")
	var bad_fields: Dictionary[String, Array] = {
		"type": ["snapshot", null], "event": ["snapshot", null], "player_id": ["actor", "", 3],
		"tick": [-1, 1.5, NAN, INF, "100", null, true],
		"kind": ["reload_complete", "fire", null, 0],
		"position": [null, Vector3.ZERO, [], [1, 2], [1, 2, 3, 4], [NAN, 0, 0],
			[0, INF, 0], [0, 0, "3"], [0, true, 0], [8193, 0, 0]],
	}
	for field: String in bad_fields:
		for value: Variant in bad_fields[field]:
			var bad: Dictionary = _event("reload_start", 100)
			bad[field] = value
			_check(not cues.present(bad, Vector3.ZERO), "malformed " + field + " refused")
	var private_data: Dictionary = _event("reload_start", 100)
	private_data["magazine"] = 5
	_check(not cues.present(private_data, Vector3.ZERO), "unexpected inventory fields refused")
	_check(cues.reload_count + cues.dry_count == before, "invalid messages do not change playback")
	_check(cues.present(_event("reload_start", 100), Vector3.ZERO), "malformed messages cannot poison the dedup clock")


func _range(cues: WeaponHandlingAudio) -> void:
	var far: Dictionary = _event("dry_fire", 101)
	far["position"] = [24.1, 0.0, 0.0]
	_check(not cues.present(far, Vector3.ZERO), "outside 24 metres is silent")
	_check(not cues.present(far, Vector3(24, 0, 0)), "approach cannot replay consumed out-of-range cue")
	var absent: Dictionary = _event("reload_start", 102)
	_check(not cues.present(absent, Vector3.INF), "absent listener is silent")
	_check(not cues.present(absent, Vector3.ZERO), "returning listener cannot replay consumed cue")
	var near: Dictionary = _event("dry_fire", 103)
	near["position"] = [23.0, 0.0, 0.0]
	_check(cues.present(near, Vector3.ZERO), "nearby cue starts before the spatial cutoff")


func _bounded(cues: WeaponHandlingAudio) -> void:
	cues.clear()
	for index: int in range(WeaponHandlingAudio.MAX_REMEMBERED + 8):
		var actor: String = "00000000-0000-0000-0000-%012x" % (index + 1)
		_check(cues.present(_event("reload_start", index + 1, actor), Vector3.ZERO), "new actor gets its current cue")
	_check(cues._latest.size() <= WeaponHandlingAudio.MAX_REMEMBERED, "history stays bounded")
	_check(cues.voices.size() == WeaponHandlingAudio.VOICES and cues.get_child_count() == WeaponHandlingAudio.VOICES,
		"bursts reuse a fixed voice pool")
	_check(not cues.present(_event("reload_start", 1), Vector3.ZERO), "evicted identity cannot replay an old event")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
