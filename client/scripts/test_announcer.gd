extends SceneTree

## The announcer setting (#431): On, Big moments only or Off, plus its volume,
## on the Audio page and in the match menu. It decides which Host calls reach
## the voice row; frags, objectives and results never pass through it.

var _failures: int = 0
var _settings_path: String = ""
var hud: CanvasLayer

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_settings_path = "user://announcer-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", _settings_path)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_announcer: " + message)

func _run() -> void:
	_test_settings()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	hud = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	await process_frame
	hud.set_process(false)
	_test_hud_gate()
	hud.queue_free()
	await process_frame
	await _test_match_menu()
	await _test_audio_page()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_settings_path))
	FragrSettings.new(_settings_path + ".defaults").apply_audio()
	if _failures == 0:
		print("test_announcer: PASS modes and volume, Host call gate, match menu row, audio page")
	quit(0 if _failures == 0 else 1)

func _test_settings() -> void:
	var prefs: FragrSettings = FragrSettings.new(_settings_path)
	_check(prefs.announcer() == FragrSettings.ANNOUNCER_ON, "the announcer defaults to On")
	for bad: Variant in [3, -1, "off", 1.5, null]:
		prefs.set_value("audio", "announcer", bad)
		_check(prefs.announcer() == FragrSettings.ANNOUNCER_ON, "an invalid announcer mode falls back to On: " + str(bad))
	prefs.set_value("audio", "announcer", FragrSettings.ANNOUNCER_OFF)
	prefs.set_value("audio", "announcer_volume", 4.0)
	_check(float(prefs.get_value("audio", "announcer_volume")) == 1.0, "announcer volume is bounded")
	_check(prefs.save_to_disk() == OK, "announcer settings save")
	var loaded: FragrSettings = FragrSettings.new(_settings_path)
	loaded.load_from_disk()
	_check(loaded.announcer() == FragrSettings.ANNOUNCER_OFF, "the announcer mode survives a reload")
	_check(FragrSettings.announcer_labels() == (["ON", "BIG MOMENTS ONLY", "OFF"] as Array[String]), "three named choices: " + str(FragrSettings.announcer_labels()))
	loaded.set_value("audio", "announcer_volume", 0.0)
	loaded.apply_audio()
	var bus: int = AudioServer.get_bus_index(&"Announcer")
	_check(bus >= 0 and AudioServer.get_bus_send(bus) == &"Master", "the Announcer bus feeds Master")
	_check(bus >= 0 and AudioServer.is_bus_mute(bus), "zero announcer volume mutes its bus")
	loaded.set_value("audio", "announcer_volume", 0.5)
	loaded.apply_audio()
	_check(bus >= 0 and not AudioServer.is_bus_mute(bus) and is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5)), "announcer volume drives its bus")

## Whether one call puts a line in the voice row.
func _reaches(call: Callable) -> bool:
	hud.combat_feed.clear()
	hud.combat_feed.set_limit(CombatFeed.LIMIT)
	call.call()
	var reached: bool = hud.combat_feed.get_child_count() == 1
	hud.combat_feed.clear()
	return reached

## Which of five Host calls reach the voice row, in order.
func _host_calls() -> Array[bool]:
	return [
		_reaches(func() -> void: hud.show_host_reaction({"kind": "first_blood", "variant": 0, "player": "Grandma Rizz", "other": "Nightfall", "team": "union", "big": true})),
		_reaches(func() -> void: hud.show_host_reaction({"kind": "golden_rail", "variant": 0, "player": "Grandma Rizz", "team": "union"})),
		_reaches(func() -> void: hud.show_host_reaction({"kind": "double_frag", "variant": 0, "player": "Nightfall"})),
		_reaches(func() -> void: hud.show_host_reaction({"kind": "triple_frag", "variant": 0, "player": "Nightfall", "big": true})),
		_reaches(func() -> void: hud.show_host_join("HOST: A NEW CHALLENGER")),
	]

func _test_hud_gate() -> void:
	var prefs: FragrSettings = FragrSettings.new(_settings_path)
	prefs.reset_all()
	hud.apply_preferences(prefs)
	var calls: Array[bool] = _host_calls()
	_check(calls == ([true, true, true, true, true] as Array[bool]), "On shows every Host call: " + str(calls))
	_check(_ducks() == ([true, true] as Array[bool]), "On lowers the radio for the bumper and the result")
	prefs.set_value("audio", "announcer", FragrSettings.ANNOUNCER_BIG_MOMENTS)
	hud.apply_preferences(prefs)
	calls = _host_calls()
	_check(calls == ([true, false, false, true, false] as Array[bool]), "Big moments only keeps the calls the server marks big (first blood, the triple frag): " + str(calls))
	# The server's `big` flag is the one list of big moments; the client keeps
	# no second list.
	_check(MatchRules.reaction_big({"kind": "golden_rail", "big": true}) and not MatchRules.reaction_big({"kind": "first_blood"}) and not MatchRules.reaction_big({"kind": "first_blood", "big": "true"}), "a call is big only when the server says so")
	_check(_ducks() == ([false, true] as Array[bool]), "Big moments only lowers the radio for a result, not the warmup bumper")
	prefs.set_value("audio", "announcer", FragrSettings.ANNOUNCER_OFF)
	hud.apply_preferences(prefs)
	calls = _host_calls()
	_check(calls == ([false, false, false, false, false] as Array[bool]), "Off silences every Host call: " + str(calls))
	_check(_ducks() == ([false, false] as Array[bool]), "Off never lowers the radio for the Host")
	# The real bumper path, not only the helper.
	var heard: Array[float] = []
	var listener: Callable = func(seconds: float) -> void: heard.append(seconds)
	hud.host_spoke.connect(listener)
	hud.show_warmup_bumper("HOST: WARMUP", 3, [])
	hud.host_spoke.disconnect(listener)
	hud.hide_warmup_tv()
	_check(heard.is_empty(), "with the announcer off the warmup bumper does not lower the radio")
	_check(_reaches(func() -> void: hud.show_speak("Nightfall", "nice shot")), "player speech is not the announcer")

## Whether the warmup bumper and a round result ask the radio to duck.
func _ducks() -> Array[bool]:
	var asked: Array[bool] = []
	for seconds_and_big: Array in [[3.0, false], [4.0, true]]:
		var heard: Array[float] = []
		var listener: Callable = func(seconds: float) -> void: heard.append(seconds)
		hud.host_spoke.connect(listener)
		hud.host_duck(float(seconds_and_big[0]), bool(seconds_and_big[1]))
		hud.host_spoke.disconnect(listener)
		asked.append(not heard.is_empty())
	return asked

func _test_match_menu() -> void:
	var prefs: FragrSettings = FragrSettings.new(_settings_path)
	prefs.reset_all()
	_check(prefs.save_to_disk() == OK, "defaults save")
	var menu: PauseMenu = PauseMenu.new()
	menu.preferences = prefs
	root.add_child(menu)
	await process_frame
	menu.open()
	await process_frame
	var mode: OptionButton = menu.find_child("AnnouncerMode", true, false) as OptionButton
	var volume: HSlider = menu.find_child("AnnouncerVolume", true, false) as HSlider
	_check(mode != null and volume != null, "the match menu has the announcer row")
	if mode == null or volume == null:
		menu.queue_free()
		return
	_check(mode.selected == 0 and mode.item_count == 3 and not mode.disabled, "it shows the saved mode")
	mode.select(1)
	mode.item_selected.emit(1)
	_check(prefs.announcer() == FragrSettings.ANNOUNCER_BIG_MOMENTS, "choosing a mode saves it at once")
	var saved: FragrSettings = FragrSettings.new(_settings_path)
	saved.load_from_disk()
	_check(saved.announcer() == FragrSettings.ANNOUNCER_BIG_MOMENTS, "the mode reached the settings file")
	volume.value = 0.0
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Announcer")), "the volume is heard at once")
	_check(is_equal_approx(float(prefs.get_value("audio", "announcer_volume")), 0.9), "the volume is a draft until the menu closes")
	menu.close()
	_check(is_equal_approx(float(prefs.get_value("audio", "announcer_volume")), 0.0) and prefs.announcer() == FragrSettings.ANNOUNCER_BIG_MOMENTS, "closing saves the volume and keeps the mode")
	menu.open()
	await process_frame
	await process_frame
	_check(mode.selected == 1 and is_equal_approx(volume.value, 0.0), "reopening shows the saved row")
	var panel: Rect2 = menu._panel.get_global_rect()
	_check(panel.encloses(mode.get_global_rect()) and panel.encloses(volume.get_global_rect()), "the row fits the match menu")
	_check(volume.size.x >= 160.0, "the announcer slider is wide enough to use: %d" % int(volume.size.x))
	menu.close()
	menu.queue_free()
	await process_frame

func _test_audio_page() -> void:
	var prefs: FragrSettings = FragrSettings.new(_settings_path)
	prefs.reset_all()
	var panel: SettingsPanel = SettingsPanel.new()
	panel.preferences = prefs
	panel.size = Vector2(1200, 680)
	root.add_child(panel)
	await process_frame
	panel.show_page("AUDIO")
	await process_frame
	var mode: OptionButton = panel.find_child("announcer", true, false) as OptionButton
	_check(mode != null and mode.item_count == 3, "the Audio page has the announcer choice")
	_check(panel.find_child("announcer_volume", true, false) != null, "and its volume")
	if mode != null:
		mode.select(2)
		mode.item_selected.emit(2)
		panel.save()
		_check(prefs.announcer() == FragrSettings.ANNOUNCER_OFF, "the Audio page saves the announcer mode")
	panel.queue_free()
	await process_frame
