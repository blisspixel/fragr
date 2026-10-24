extends SceneTree

## Headless gate for the Host spine on the client: the announcer setting
## (On, Big moments only, Off, and its volume on the Announcer bus), which
## Host calls reach the corner in each mode, the name-free voiced slots that
## recorded lines drop into, and the sudden death chip.
## Run: godot --path client --headless --script res://scripts/test_host_voice.gd

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_host_voice: " + message)


func _run() -> void:
	var path: String = "user://test-host-voice-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", path)
	_check_setting(path)
	await _check_menus(path)
	await _check_hud_gate()
	await _check_voice()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _failures == 0:
		print("test_host_voice: PASS")
	quit(0 if _failures == 0 else 1)


func _check_setting(path: String) -> void:
	var preferences: FragrSettings = FragrSettings.new(path)
	_check(preferences.announcer() == FragrSettings.ANNOUNCER_ON, "the announcer starts On")
	preferences.set_value("audio", "announcer", 7)
	_check(preferences.announcer() == FragrSettings.ANNOUNCER_ON, "an unknown announcer mode falls back to On")
	preferences.set_value("audio", "announcer", "2")
	_check(preferences.announcer() == FragrSettings.ANNOUNCER_ON, "a string is not a mode")
	preferences.set_value("audio", "announcer", FragrSettings.ANNOUNCER_BIG_MOMENTS)
	preferences.set_value("audio", "announcer_volume", 4.0)
	_check(is_equal_approx(float(preferences.get_value("audio", "announcer_volume")), 1.0), "announcer volume clamps to the bus range")
	preferences.set_value("audio", "announcer_volume", 0.4)
	_check(preferences.save_to_disk() == OK, "the announcer setting saves")
	var reloaded: FragrSettings = FragrSettings.new(path)
	reloaded.load_from_disk()
	_check(reloaded.announcer() == FragrSettings.ANNOUNCER_BIG_MOMENTS, "Big moments only survives a restart")
	var bus: int = AudioServer.get_bus_index("Announcer")
	_check(bus >= 0, "the Announcer bus exists")
	reloaded.apply_audio()
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(bus)), 0.4) and not AudioServer.is_bus_mute(bus), "announcer volume drives its own bus")
	reloaded.set_value("audio", "announcer_volume", 0.0)
	reloaded.apply_audio()
	_check(AudioServer.is_bus_mute(bus), "zero announcer volume mutes the bus")
	_check(FragrSettings.announcer_labels() == (["ON", "BIG MOMENTS ONLY", "OFF"] as Array[String]), "three labelled choices: " + str(FragrSettings.announcer_labels()))


## Settings > Audio, and the same page from the match menu.
func _check_menus(path: String) -> void:
	var preferences: FragrSettings = FragrSettings.new(path)
	var panel: SettingsPanel = SettingsPanel.new()
	panel.preferences = preferences
	root.add_child(panel)
	panel.show_page("AUDIO")
	var mode: OptionButton = panel.find_child("announcer", true, false) as OptionButton
	var volume: HSlider = panel.find_child("announcer_volume", true, false) as HSlider
	_check(mode != null and mode.item_count == 3, "the Audio page offers the announcer modes")
	_check(volume != null, "the Audio page has an announcer volume")
	if mode != null:
		mode.select(2)
		mode.item_selected.emit(2)
	panel.queue_free()
	await process_frame
	var pause: PauseMenu = PauseMenu.new()
	pause.preferences = preferences
	root.add_child(pause)
	pause.show_settings()
	var embedded: SettingsPanel = pause.find_child("SettingsPanel", true, false) as SettingsPanel
	_check(embedded != null, "the match menu opens settings")
	if embedded != null:
		embedded.show_page("AUDIO")
		_check(embedded.find_child("announcer", true, false) is OptionButton, "the announcer is reachable from the match menu")
	pause.queue_free()
	await process_frame


func _hud() -> CanvasLayer:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	return hud


func _feed_lines(hud: CanvasLayer) -> PackedStringArray:
	var lines: PackedStringArray = []
	for entry: Variant in hud.combat_feed._entries:
		lines.append(entry.label.text)
	return lines


func _check_hud_gate() -> void:
	var hud: CanvasLayer = _hud()
	await process_frame
	var big: Dictionary = {"kind": "triple_frag", "variant": 0, "player": "Nightfall", "big": true}
	var small: Dictionary = {"kind": "double_frag", "variant": 0, "player": "Nightfall"}
	var expected: Dictionary = {
		FragrSettings.ANNOUNCER_ON: ["HOST: TRIPLE FRAG! NIGHTFALL!", "HOST: DOUBLE FRAG. NIGHTFALL."],
		FragrSettings.ANNOUNCER_BIG_MOMENTS: ["HOST: TRIPLE FRAG! NIGHTFALL!"],
		FragrSettings.ANNOUNCER_OFF: [],
	}
	for mode: int in FragrSettings.ANNOUNCER_MODES:
		hud.combat_feed.clear()
		hud.announcer = mode
		hud.show_host_reaction(big)
		hud.show_host_reaction(small)
		hud.show_host_join("HOST: ARENA DUEL IS LIVE.")
		var lines: PackedStringArray = _feed_lines(hud)
		var want: Array = (expected[mode] as Array).duplicate()
		if mode == FragrSettings.ANNOUNCER_ON:
			want.append("HOST: ARENA DUEL IS LIVE.")
		_check(Array(lines) == want, "announcer mode %d shows %s, got %s" % [mode, str(want), str(lines)])
		_check(hud.announcer_allows(true) == (mode != FragrSettings.ANNOUNCER_OFF), "big moments pass unless Off")
		_check(hud.announcer_allows(false) == (mode == FragrSettings.ANNOUNCER_ON), "captions pass only when On")
	# Sudden death is a rule fact: it shows whatever the announcer says.
	hud.announcer = FragrSettings.ANNOUNCER_OFF
	hud.call("set_match_rules", {"mode": "ffa", "name": "Free-for-all"})
	hud.set_round_info("Active", null, 10, true)
	var chip: Label = hud.get("mode_chip_label")
	_check(chip != null and chip.text.contains("SUDDEN DEATH: NEXT SCORE WINS"), "the chip says sudden death: " + (chip.text if chip else ""))
	hud.set_round_info("Active", 30, 10, false)
	_check(not chip.text.contains("SUDDEN DEATH"), "a running clock is not sudden death: " + chip.text)
	hud.set_round_info("Ended", null, 10, true)
	_check(not chip.text.contains("SUDDEN DEATH"), "the result card is not sudden death: " + chip.text)
	hud.queue_free()
	await process_frame


func _tone() -> AudioStreamWAV:
	var clip: AudioStreamWAV = AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_8_BITS
	clip.mix_rate = 8000
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(800)
	clip.data = bytes
	return clip


func _check_voice() -> void:
	# Every slot is a kind and a variant only: no names reach a recording.
	var slot: RegEx = RegEx.create_from_string("^res://assets/audio/host/[a-z_]+_[0-2]\\.mp3$")
	for kind: String in MatchRules.REACTIONS:
		for variant: int in range(MatchRules.REACTION_VARIANTS):
			_check(slot.search(HostVoice.slot_path(kind, variant)) != null, "name-free slot: " + HostVoice.slot_path(kind, variant))
	_check(HostVoice.slot_path("triple_frag", 1) == "res://assets/audio/host/triple_frag_1.mp3", "the documented slot layout")
	var voice: HostVoice = HostVoice.new()
	root.add_child(voice)
	await process_frame
	_check(voice.bus == &"Announcer", "the Host speaks on the Announcer bus: " + str(voice.bus))
	var big: Dictionary = {"kind": "triple_frag", "variant": 1, "player": "Nightfall", "big": true}
	# No recording yet: silence, never an error.
	_check(not voice.speak(big, FragrSettings.ANNOUNCER_ON), "a missing clip is silence")
	var asked: Array[String] = []
	var clip: AudioStreamWAV = _tone()
	voice.clip_source = func(path: String) -> AudioStream:
		asked.append(path)
		return clip if path.ends_with("_1.mp3") else null
	var ducked: Array[float] = []
	voice.spoke.connect(func(seconds: float) -> void: ducked.append(seconds))
	_check(voice.speak(big, FragrSettings.ANNOUNCER_ON), "a recorded big moment plays")
	_check(voice.playing and voice.stream == clip, "the slot's clip is what plays")
	_check(asked == (["res://assets/audio/host/triple_frag_1.mp3"] as Array[String]), "the slot asked for is the kind and variant: " + str(asked))
	_check(ducked.size() == 1 and ducked[0] > clip.get_length(), "the radio ducks for the clip and its tail")
	_check(voice.speak(big, FragrSettings.ANNOUNCER_BIG_MOMENTS), "Big moments only still voices a big moment")
	_check(not voice.speak(big, FragrSettings.ANNOUNCER_OFF), "Off never speaks")
	var caption: Dictionary = big.duplicate()
	caption.erase("big")
	_check(not voice.speak(caption, FragrSettings.ANNOUNCER_ON), "a text-only caption is never voiced")
	for bad: Dictionary in [{"kind": "ace", "variant": 1, "big": true}, {"kind": "triple_frag", "variant": 3, "big": true}, {"kind": "triple_frag", "variant": 1.5, "big": true}]:
		_check(not voice.speak(bad, FragrSettings.ANNOUNCER_ON), "malformed calls stay silent: " + str(bad))
	_check(not voice.speak({"kind": "triple_frag", "variant": 0, "big": true}, FragrSettings.ANNOUNCER_ON), "an empty slot does not interrupt")
	_check(voice.playing, "the current call keeps speaking")
	# Leaving the match retires the voice the way the match scene does.
	var retirement: ClientRetirement = ClientRetirement.for_tree(self)
	retirement.track_audio(voice)
	voice.stop()
	voice.stream = null
	voice.clip_source = Callable()
	voice.queue_free()
	await process_frame
	_check(await retirement.drain(), "the Host's playbacks retire before exit")
