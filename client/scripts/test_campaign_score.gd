extends SceneTree
## Headless check for the optional campaign score: the setting's default and
## validation, Off silencing beds and cues, a bed for every campaign map, the
## radio rule, take selection and fallback, missing-file tolerance and the
## pause menu's score row. Run with:
## godot --headless --path client --script res://scripts/test_campaign_score.gd

const RadioScript := preload("res://scripts/radio.gd")

var failures: Array[String] = []
var settings_path: String = ""


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	set_meta("fragr_automated", true)
	settings_path = "user://campaign-score-%d.cfg" % OS.get_process_id()
	set_meta("fragr_settings_path", settings_path)
	_run.call_deferred()


func _finalize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))


func _run() -> void:
	# Stopped decoders are released after a mixer turn; retire them before quit.
	var retirement: ClientRetirement = ClientRetirement.for_tree(self)
	_test_settings()
	_test_mapping()
	_test_rules()
	_test_resolution()
	await _test_live_node()
	await _test_radio_starts_off()
	await _test_pause_menu()
	_check(await retirement.drain(), "every score decoder retires before the harness exits")
	await process_frame
	if failures.is_empty():
		print("test_campaign_score: PASS default on, off silences, every campaign map has a bed, radio rule, takes, missing files, menu row")
		quit(0)
	else:
		for failure: String in failures:
			printerr("test_campaign_score: FAIL " + failure)
		quit(1)


func _test_settings() -> void:
	var settings: FragrSettings = FragrSettings.new(settings_path)
	_check(bool(settings.get_value("score", "enabled")), "the campaign score defaults to On")
	_check((settings.get_value("score", "takes") as Dictionary).is_empty(), "no take is chosen by default")
	_check(CampaignScore.chosen_take(settings, "l04") == "a", "an unchosen slot plays take A")
	settings.set_value("score", "takes", {"l04": "b", "Bad Slot": "a", "l05": "c", 3: "a", "cue-l19": "a"})
	var takes: Dictionary = settings.get_value("score", "takes")
	_check(takes == {"l04": "b", "cue-l19": "a"}, "takes keep only slot ids with A or B: %s" % [takes])
	settings.set_value("score", "takes", "l04=b")
	_check((settings.get_value("score", "takes") as Dictionary).is_empty(), "a non-dictionary takes value is refused")
	settings.set_value("score", "enabled", "yes")
	_check(bool(settings.get_value("score", "enabled")), "a non-bool switch falls back to On")
	settings.set_value("score", "enabled", false)
	settings.set_value("score", "takes", {"l04": "b", "cue-l02": "b"})
	_check(settings.save_to_disk() == OK, "settings save")
	var loaded: FragrSettings = FragrSettings.new(settings_path)
	loaded.load_from_disk()
	_check(not bool(loaded.get_value("score", "enabled")), "Off persists")
	_check(CampaignScore.chosen_take(loaded, "l04") == "b" and CampaignScore.chosen_take(loaded, "cue-l02") == "b", "per-slot takes persist")
	# A hand-edited file is validated at load, not trusted.
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value("score", "takes", {"l04": "z", "l06": "b"})
	cfg.save(settings_path)
	loaded.load_from_disk()
	_check(loaded.get_value("score", "takes") == {"l06": "b"}, "an invalid take in the file is dropped at load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))


func _test_mapping() -> void:
	var slots: Array[Dictionary] = CampaignScore.parse_slots(FileAccess.get_file_as_string(CampaignScore.SLOTS_PATH))
	var missions: Array[String] = [MissionState.ID, MissionState.M02_ID]
	missions.append_array(MissionState.ORDERED_IDS)
	missions.append_array([MissionState.M20_ID, MissionState.STILL_HERE_ID])
	_check(missions.size() == 21, "twenty levels and the epilogue")
	var beds: Dictionary[String, bool] = {}
	for mission: String in missions:
		var slot: String = CampaignScore.bed_slot_for(mission, slots)
		_check(not slot.is_empty(), "campaign map has a bed: " + mission)
		_check(not beds.has(slot), "each level has its own bed: " + slot)
		beds[slot] = true
	_check(CampaignScore.bed_slot_for("", slots).is_empty() and CampaignScore.bed_slot_for("arena", slots).is_empty(), "no bed outside the campaign")
	var cues: int = 0
	for slot: Dictionary in slots:
		if slot["kind"] != "cue":
			continue
		cues += 1
		if slot.has("scene"):
			var scene: Dictionary = StoryScene.load_scene(str(slot["scene"]))
			var music: Dictionary = scene.get("music", {})
			_check(CampaignScore.slot_from_path(str(music.get("path", ""))) == slot["id"], "the scene's music slot plays its cue: " + str(slot["id"]))
		else:
			_check(slot.get("mission") == MissionState.M19_ID and slot.get("moment") == "latch_choice", "the in-level cue belongs to Latch's choice")
	_check(cues >= 5, "the designed story cues are listed")
	_check(CampaignScore.parse_slots("").is_empty() and CampaignScore.parse_slots("{\"slots\": [{\"id\": \"../x\", \"kind\": \"bed\"}, {\"id\": \"ok\", \"kind\": \"loud\"}]}").is_empty(),
		"bad slot rows are dropped")


func _test_rules() -> void:
	var silent: float = CampaignScore.SILENT_DB
	_check(CampaignScore.target_db(true, true, false, false, false, false, 0.0) == CampaignScore.BED_DB, "on, a bed, nothing else: the bed level")
	_check(CampaignScore.target_db(false, true, false, false, false, false, 0.0) == silent, "Off silences the bed")
	_check(CampaignScore.target_db(true, false, false, false, false, false, 0.0) == silent, "no bed file, no sound")
	_check(CampaignScore.target_db(true, true, true, false, false, false, 0.0) == silent, "a radio station replaces the score")
	_check(CampaignScore.target_db(true, true, false, true, false, false, 0.0) == silent, "a story page owns the music")
	_check(CampaignScore.target_db(true, true, false, false, true, false, 0.0) == silent, "a cue rests the bed")
	_check(CampaignScore.target_db(true, true, false, false, false, true, 0.0) == CampaignScore.BED_DB + CampaignScore.DUCK_DB, "Host and barks duck the bed")
	_check(CampaignScore.target_db(true, true, false, false, false, false, 3.0) == CampaignScore.BED_DB + CampaignScore.COMBAT_DUCK_DB, "heavy combat ducks it, bounded")
	_check(CampaignScore.BED_DB < RadioScript.PLAYING_DB, "the bed sits under a station")


func _test_resolution() -> void:
	var none: Callable = func(_path: String) -> bool: return false
	var only_b: Callable = func(path: String) -> bool: return path.ends_with("/b.mp3")
	var both: Callable = func(_path: String) -> bool: return true
	_check(CampaignScore.resolve_path("l04", "a", none).is_empty(), "a slot with no takes is silent")
	_check(CampaignScore.resolve_path("l04", "a", only_b) == "res://assets/audio/score/l04/b.mp3", "a missing take falls back to the other one")
	_check(CampaignScore.resolve_path("l04", "b", both).ends_with("l04/b.mp3") and CampaignScore.resolve_path("l04", "x", both).ends_with("l04/a.mp3"), "the chosen take plays; nonsense means A")
	_check(CampaignScore.resolve_path("", "a", both).is_empty(), "no slot, no path")
	_check(CampaignScore.slot_from_path("res://assets/audio/score/cue-l05/a.mp3") == "cue-l05" and CampaignScore.slot_from_path("res://assets/story/ambience/x.wav").is_empty(), "score paths name their slot")
	var gained: Array[Dictionary] = CampaignScore.parse_slots(JSON.stringify({"slots": [{"id": "l04", "kind": "bed", "gain_db": {"a": -2.5, "b": 40, "c": 1}}]}))
	_check(CampaignScore.gain_for_path("res://assets/audio/score/l04/a.mp3", gained) == -2.5, "a take's level match applies")
	_check(CampaignScore.gain_for_path("res://assets/audio/score/l04/b.mp3", gained) == CampaignScore.MAX_GAIN_DB, "a level match is bounded")
	_check(CampaignScore.gain_for_path("res://assets/audio/score/l05/a.mp3", gained) == 0.0, "no match, no change")
	for slot: Dictionary in CampaignScore.shipped_slots():
		_check((slot["gain_db"] as Dictionary).size() == 2, "every shipped slot level-matches both takes: " + str(slot["id"]))
	var settings: FragrSettings = FragrSettings.new(settings_path)
	settings.set_value("score", "takes", {"cue-l05": "b"})
	_check(CampaignScore.scene_music_path("res://assets/audio/score/cue-l05/a.mp3", settings, both).ends_with("cue-l05/b.mp3"), "a scene cue plays the chosen take")
	_check(CampaignScore.scene_music_path("res://assets/story/ambience/low_water_runoff.wav", settings, both) == "res://assets/story/ambience/low_water_runoff.wav", "other scene beds are untouched")
	settings.set_value("score", "enabled", false)
	_check(CampaignScore.scene_music_path("res://assets/audio/score/cue-l05/a.mp3", settings, both).is_empty(), "Off silences story cues")


func _test_live_node() -> void:
	var settings: FragrSettings = FragrSettings.new(settings_path)
	var score: CampaignScore = CampaignScore.new()
	score.preferences = settings
	# Injected slots: one real level and one whose files do not exist.
	score.slots = CampaignScore.parse_slots(JSON.stringify({"slots": [
		{"id": "l04", "kind": "bed", "mission": MissionState.M04_ID},
		{"id": "missing-bed", "kind": "bed", "mission": "nowhere"},
	]}))
	root.add_child(score)
	await process_frame
	score.set_mission("nowhere")
	_check(score.bed_slot() == "missing-bed" and score.bed_path().is_empty(), "a level without files keeps its slot and stays silent")
	_check(not score.play_cue("cue-none"), "a missing cue is silence, not an error")
	score.set_mission("arena")
	_check(score.bed_slot().is_empty() and score.bed_path().is_empty(), "no bed outside the campaign")
	score.set_mission(MissionState.M04_ID)
	var has_a: bool = ResourceLoader.exists(CampaignScore.take_path("l04", "a"))
	var has_b: bool = ResourceLoader.exists(CampaignScore.take_path("l04", "b"))
	if has_a:
		_check(score.bed_path().ends_with("l04/a.mp3"), "take A plays by default")
	if has_b:
		score.set_take("l04", "b")
		_check(score.bed_path().ends_with("l04/b.mp3"), "switching the take changes the bed live")
		_check(CampaignScore.chosen_take(settings, "l04") == "b", "the switch is kept in the settings")
		var saved: FragrSettings = FragrSettings.new(settings_path)
		saved.load_from_disk()
		_check(CampaignScore.chosen_take(saved, "l04") == "b", "the switch is written to the settings file")
		score.toggle_take("l04")
		_check(CampaignScore.chosen_take(settings, "l04") == "a", "toggling returns to A")
	score.set_enabled(false)
	_check(not score.enabled and score.bed_path().is_empty() and score.bed_slot() == "l04", "Off drops the bed but keeps the level's slot")
	score.radio_playing = false
	for frame: int in 3:
		await process_frame
	_check(not score.audible(), "Off is silent")
	score.set_enabled(true)
	_check(score.enabled and (score.bed_path().is_empty() == not (has_a or has_b)), "On brings the bed back")
	score.radio_playing = true
	for frame: int in 3:
		await process_frame
	_check(not score.audible(), "a station silences the bed")
	score.note_scene({"music": {"path": "res://assets/audio/score/cue-l02/a.mp3"}})
	_check(score.last_cue == "cue-l02", "a story page's cue is remembered for its take control")
	score.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))


func _test_radio_starts_off() -> void:
	var radio: Node = RadioScript.new()
	radio.enabled = false
	var announced: Array[Dictionary] = []
	radio.now_playing_changed.connect(func(info: Dictionary) -> void: announced.append(info))
	root.add_child(radio)
	await process_frame
	await process_frame
	var state: String = str((radio.now_playing() as Dictionary).get("state", ""))
	_check(state in ["off", "none"], "a radio started off stays off: " + state)
	_check(announced.is_empty(), "a radio started off announces nothing")
	_check(radio.player == null or not radio.player.playing, "a radio started off plays nothing")
	if not radio.stations.is_empty():
		radio.toggle()
		_check(str((radio.now_playing() as Dictionary).get("state", "")) in ["playing", "unavailable", "off_air"], "the dial still turns it on")
		radio.toggle()
		_check(str((radio.now_playing() as Dictionary).get("state", "")) == "off", "and off again")
	radio.queue_free()
	await process_frame


func _test_pause_menu() -> void:
	var settings: FragrSettings = FragrSettings.new(settings_path)
	var menu: PauseMenu = PauseMenu.new()
	menu.preferences = settings
	root.add_child(menu)
	await process_frame
	var row: Control = menu.find_child("Score", true, false) as Control
	_check(row != null and not row.visible, "no score row without a campaign score")
	var score: CampaignScore = CampaignScore.new()
	score.preferences = settings
	root.add_child(score)
	await process_frame
	score.set_mission(MissionState.M04_ID)
	menu.bind_score(score)
	menu.open()
	await process_frame
	_check(row != null and row.visible, "a campaign shows the score row")
	var take: Button = menu.find_child("ScoreTake", true, false) as Button
	var toggle: Button = menu.find_child("ScoreToggle", true, false) as Button
	var cue: Button = menu.find_child("CueTake", true, false) as Button
	_check(take != null and take.text == tr("MENU_SCORE_TAKE") % "A", "the level take reads A")
	_check(cue != null and not cue.visible, "no cue take before a cue was heard")
	take.pressed.emit()
	_check(CampaignScore.chosen_take(settings, "l04") == "b" and take.text == tr("MENU_SCORE_TAKE") % "B", "the menu switches the level take")
	toggle.pressed.emit()
	_check(not score.enabled and toggle.text == tr("MENU_SCORE_OFF"), "the menu switches the score off")
	toggle.pressed.emit()
	_check(score.enabled and toggle.text == tr("MENU_SCORE_ON"), "and on")
	score.play_cue("cue-l19")
	_check(cue.visible and cue.text == tr("MENU_SCORE_CUE_TAKE") % "A", "a heard cue gets its take control")
	cue.pressed.emit()
	_check(CampaignScore.chosen_take(settings, "cue-l19") == "b", "the menu switches the cue take")
	menu.close()
	menu.queue_free()
	score.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
