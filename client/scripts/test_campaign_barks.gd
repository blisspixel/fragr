extends SceneTree

class BarkHud extends Node:
	var shown: Array[String] = []
	var bark_caption: BarkCaption = null
	var crawler_caption: CrawlerCaption = null
	func show_bark_caption(speaker_key: String, caption_key: String, _union: bool = true) -> void:
		shown.append(speaker_key + "|" + caption_key)

var failures: int = 0
var requested: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_campaign_barks: " + message)

func _enemy(kind: String, register: Variant, variant: Variant) -> Dictionary:
	return {"event": "enemy_bark", "kind": kind, "register": register, "variant": variant,
		"speaker_id": "00000000-0000-0000-0000-000000000001", "position": [1.0, 0.0, 2.0]}

func _latch(kind: String, subject: Variant, variant: Variant) -> Dictionary:
	var data: Dictionary = {"event": "companion_bark", "kind": kind, "variant": variant,
		"speaker_id": "00000000-0000-0000-0000-000000000002", "position": [3.0, 0.0, 4.0]}
	if subject != null:
		data["subject"] = subject
	return data

func _tone() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(22050 * 2)
	wav.data = bytes
	return wav

func _run() -> void:
	var valid: Array[Dictionary] = []
	for register: String in CampaignBarks.REGISTERS:
		for kind: String in CampaignBarks.ENEMY_KINDS:
			for variant: int in range(CampaignBarks.VARIANTS):
				valid.append(_enemy(kind, register, variant))
	for variant: int in range(CampaignBarks.VARIANTS):
		valid.append(_latch("flank_warning", null, variant))
		valid.append(_latch("low_health", null, variant))
		for subject: String in CampaignBarks.SUBJECTS:
			valid.append(_latch("priority_target", subject, variant))
	_expect(valid.size() == 30, "thirty voiced slots")
	for data: Dictionary in valid:
		var key: String = CampaignBarks.caption_key(data)
		var speaker: String = CampaignBarks.speaker_key(data)
		_expect(not key.is_empty() and tr(key) != key, "caption translates: " + key)
		_expect(not speaker.is_empty() and tr(speaker) != speaker, "speaker translates: " + speaker)
		_expect(CampaignBarks.slot_path(data).begins_with("res://assets/audio/barks/"), "slot path for " + key)
		_expect(not tr(key).contains(String.chr(0x2014)) and not tr(key).contains(String.chr(0x2013)), "no long dashes: " + key)
	_expect(CampaignBarks.caption_key(_enemy("officer_down", "unit", 2)) == "BARK_ENEMY_UNIT_OFFICER_DOWN_2", "enemy key shape")
	_expect(CampaignBarks.caption_key(_latch("priority_target", "turret", 1)) == "BARK_LATCH_PRIORITY_TARGET_TURRET_1", "priority key shape")
	_expect(CampaignBarks.slot_path(_enemy("sighting", "personnel", 0)) == "res://assets/audio/barks/union_personnel/sighting_0.mp3", "personnel slot")
	_expect(CampaignBarks.slot_path(_enemy("flanking", "unit", 1)) == "res://assets/audio/barks/union_unit/flanking_1.mp3", "unit slot")
	_expect(CampaignBarks.slot_path(_latch("priority_target", "auditor", 2)) == "res://assets/audio/barks/latch/priority_target_auditor_2.mp3", "latch subject slot")
	_expect(CampaignBarks.slot_path(_latch("low_health", null, 0)) == "res://assets/audio/barks/latch/low_health_0.mp3", "latch slot")
	_expect(CampaignBarks.speaker_key(_enemy("sighting", "personnel", 0)) == "BARK_SPEAKER_UNION", "personnel speaker")
	_expect(CampaignBarks.speaker_key(_enemy("sighting", "unit", 0)) == "BARK_SPEAKER_UNIT", "unit speaker")
	_expect(CampaignBarks.speaker_key(_latch("low_health", null, 0)) == "BARK_SPEAKER_LATCH", "latch speaker")
	_expect(CampaignBarks.is_union(_enemy("sighting", "unit", 0)) and not CampaignBarks.is_union(_latch("low_health", null, 0)), "union side")
	_expect(CampaignBarks.caption_key(_enemy("sighting", "unit", 1.0)) == "BARK_ENEMY_UNIT_SIGHTING_1", "whole float variant accepted")

	var invalid: Array[Dictionary] = [
		_enemy("taunt", "unit", 0), _enemy("sighting", "officer", 0), _enemy("sighting", "unit", 3),
		_enemy("sighting", "unit", -1), _enemy("sighting", "unit", 1.5), _enemy("sighting", "unit", "1"),
		_enemy("sighting", null, 0), _latch("priority_target", null, 0), _latch("priority_target", "clerk", 0),
		_latch("low_health", "turret", 0), _latch("sing", null, 0), {"event": "frag"}, {},
	]
	for bad_position: Variant in [null, [], [1, 2], [1, "2", 3], [NAN, 1, 2], [INF, 0, 0], [10001, 1, 2], "1,2,3"]:
		var data: Dictionary = _enemy("sighting", "unit", 0)
		data["position"] = bad_position
		invalid.append(data)
	for data: Dictionary in invalid:
		_expect(CampaignBarks.caption_key(data).is_empty(), "malformed bark ignored: " + str(data))
		_expect(CampaignBarks.slot_path(data).is_empty() and CampaignBarks.speaker_key(data).is_empty(), "malformed bark has no slot or speaker")

	# Voice: the Union radio bus and dry Latch.
	var voice := BarkVoice.new()
	voice.clip_source = func(path: String) -> AudioStream:
		requested.append(path)
		return null if path.contains("missing") or path.contains("low_health") else _tone()
	root.add_child(voice)
	var radio: int = AudioServer.get_bus_index(BarkVoice.RADIO_BUS)
	_expect(radio >= 0, "UnionRadio bus created")
	_expect(AudioServer.get_bus_send(radio) == &"Voice", "UnionRadio sends to Voice")
	_expect(AudioServer.get_bus_effect_count(radio) == 2 and AudioServer.get_bus_effect(radio, 0) is AudioEffectBandPassFilter, "radio colour is a band-pass then drive")
	_expect(BarkVoice.ensure_radio_bus() == radio, "radio bus is created once")
	_expect(voice.union_player.bus == BarkVoice.RADIO_BUS and voice.latch_player.bus == &"Voice", "buses per side")
	_expect(voice.speak(_enemy("sighting", "personnel", 0)), "Union line plays")
	_expect(voice.union_player.playing and voice.union_player.global_position == Vector3(1.0, 0.0, 2.0), "Union line at the speaker")
	_expect(voice.speak(_latch("flank_warning", null, 0)), "Latch line plays")
	_expect(voice.latch_player.playing and not voice.union_player.playing, "a new line stops the one speaking")
	_expect(not voice.speak(_latch("low_health", null, 0)), "missing slot is silence")
	_expect(not voice.speak(_enemy("sighting", "unit", 9)), "malformed bark never plays")
	_expect(requested.size() == 3, "malformed bark asks for no clip")
	voice.free()

	# Caption shows without audio and expires.
	var caption := BarkCaption.new()
	root.add_child(caption)
	var voice_bus: int = AudioServer.get_bus_index(&"Voice")
	var prior_mute: bool = AudioServer.is_bus_mute(voice_bus)
	AudioServer.set_bus_mute(voice_bus, true)
	_expect(caption.push("BARK_SPEAKER_UNION", "BARK_ENEMY_PERSONNEL_SIGHTING_0", true, 1000), "caption shows with Voice muted")
	_expect(caption.caption_label.visible and caption.text() == "UNION RADIO: Contact. Unscheduled person on the floor. Opening a file.", "speaker and line")
	_expect(not caption.push("", "BARK_LATCH_LOW_HEALTH_0", false, 1100), "empty speaker refused")
	caption.push("BARK_SPEAKER_LATCH", "BARK_LATCH_LOW_HEALTH_0", false, 2000)
	caption.push("BARK_SPEAKER_LATCH", "BARK_LATCH_LOW_HEALTH_1", false, 3000)
	_expect(caption.entries.size() == BarkCaption.MAX_ENTRIES, "at most two captions")
	caption.prune(3000 + BarkCaption.LIFETIME_MS)
	_expect(caption.entries.is_empty() and not caption.caption_label.visible, "captions expire")
	_expect(caption.rotation == 0.0 and caption.caption_label.rotation == 0.0, "level baseline")
	AudioServer.set_bus_mute(voice_bus, prior_mute)
	caption.free()

	# Game manager routes both events, ignores malformed ones and resets.
	var manager: Variant = Node.new()
	root.add_child(manager)
	manager.set_script(load("res://scripts/game_manager.gd"))
	var hud := BarkHud.new()
	manager.add_child(hud)
	manager.hud = hud
	manager._on_event_received(_enemy("flanking", "unit", 1))
	manager._on_event_received(_latch("priority_target", "auditor", 2))
	manager._on_event_received(_latch("priority_target", "clerk", 2))
	_expect(hud.shown == ["BARK_SPEAKER_UNIT|BARK_ENEMY_UNIT_FLANKING_1", "BARK_SPEAKER_LATCH|BARK_LATCH_PRIORITY_TARGET_AUDITOR_2"], "events caption: " + str(hud.shown))
	_expect(manager.bark_voice is BarkVoice, "manager owns one bark voice")
	manager._reset_crawler_cues()
	manager.free()
	if failures == 0:
		print("test_campaign_barks: PASS")
	quit(1 if failures else 0)
