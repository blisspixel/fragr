extends SceneTree

var _failures: int = 0
var _closes: int = 0

## Exercise real player setup without randomly starting a long catalog track.
class QuietRadio extends "res://scripts/radio.gd":
	func load_catalog(_stations_text: String = "", _manifest_text: String = "") -> void:
		super.load_catalog("{\"stations\":[]}", "{\"entries\":{}}")

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_settings_panel: " + message)

func _panel(preferences: FragrSettings) -> SettingsPanel:
	var panel: SettingsPanel = SettingsPanel.new()
	panel.preferences = preferences
	panel.closed.connect(func() -> void: _closes += 1)
	root.add_child(panel)
	return panel

func _run() -> void:
	var path: String = "user://test-panel-%d.cfg" % OS.get_process_id()
	var preferences: FragrSettings = FragrSettings.new(path)
	preferences.apply_audio()
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects"))), 0.5), "fresh effects mix reaches its bus")
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Radio"))), 0.7), "fresh music mix reaches its bus")
	preferences.set_value("profile", "name", "Keep this callsign")
	preferences.save_to_disk()
	var panel: SettingsPanel = _panel(preferences)
	(panel.find_child("mouse_sensitivity", true, false) as HSlider).value = 2.25
	(panel.find_child("invert_y", true, false) as Button).button_pressed = true
	panel.show_page("DISPLAY")
	(panel.find_child("vertical_fov", true, false) as HSlider).value = 85
	var cap: OptionButton = panel.find_child("fps_cap", true, false) as OptionButton
	cap.select(4)
	cap.item_selected.emit(4)
	(panel.find_child("vsync", true, false) as Button).button_pressed = true
	panel.show_page("AUDIO")
	(panel.find_child("music", true, false) as HSlider).value = 0.0
	(panel.find_child("effects", true, false) as HSlider).value = 0.35
	_check(preferences.fov() == 75, "draft must not change active preferences")
	panel.save()
	_check(_closes == 1, "successful save closes the panel")
	var loaded: FragrSettings = FragrSettings.new(path)
	loaded.load_from_disk()
	_check(loaded.fov() == 85 and loaded.get_value("video", "fps_cap") == 120, "display settings survive a fresh store")
	_check(loaded.get_value("video", "vsync") == true, "VSync survives a fresh store")
	_check(loaded.get_value("controls", "mouse_sensitivity") == 2.25 and loaded.get_value("controls", "invert_y") == true, "control settings survive a fresh store")
	_check(loaded.player_name() == "Keep this callsign", "settings save preserves the profile")
	panel.free()
	panel = _panel(preferences)
	(panel.find_child("mouse_sensitivity", true, false) as HSlider).value = 7.0
	panel.cancel()
	loaded.load_from_disk()
	_check(preferences.get_value("controls", "mouse_sensitivity") == 2.25 and loaded.get_value("controls", "mouse_sensitivity") == 2.25, "Cancel preserves both active and saved preferences")
	panel.free()

	var bad: FragrSettings = FragrSettings.new("user://missing-directory-%d/settings.cfg" % OS.get_process_id())
	panel = _panel(bad)
	(panel.find_child("mouse_sensitivity", true, false) as HSlider).value = 4.0
	panel.save()
	_check(_closes == 2 and bad.get_value("controls", "mouse_sensitivity") == 1.5, "failed save must not close or apply")
	var note: Label = panel.get("_note")
	_check(note.text.begins_with("SAVE FAILED"), "write failure stays visible")
	panel.free()

	# The saved values drive the actual camera and audio buses, not only the store.
	var camera: Node3D = load("res://scripts/spectator_cam.gd").new()
	var lens: Camera3D = Camera3D.new()
	lens.name = "Camera3D"
	camera.add_child(lens)
	camera.apply_preferences(loaded)
	_check(lens.fov == 85 and lens.keep_aspect == Camera3D.KEEP_HEIGHT, "saved FOV reaches the camera in vertical units")
	_check(camera.mouse_sensitivity == 2.25 and camera.invert_y, "saved aim values reach the camera")
	camera.free()
	loaded.apply()
	var radio: int = AudioServer.get_bus_index("Radio")
	var effects: int = AudioServer.get_bus_index("Effects")
	_check(radio > 0 and effects > 0, "mix buses must exist")
	_check(AudioServer.is_bus_mute(radio), "zero radio volume must mute the radio bus")
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(effects)), 0.35), "custom effects volume survives defaults and reaches its bus")
	_check(Engine.max_fps == 120, "saved frame cap reaches the engine")
	var pawn: Node = load("res://scenes/player.tscn").instantiate()
	_check(pawn.get_node("FireSound").bus == &"Effects" and pawn.get_node("HitSound").bus == &"Effects", "weapon and hit players route to effects")
	pawn.free()
	var radio_node: Node = QuietRadio.new()
	root.add_child(radio_node)
	_check(radio_node.player.bus == &"Radio", "radio playback routes to its bus")
	radio_node.free()

	var console: FragrConsole = FragrConsole.new()
	console.preferences = preferences
	console.run("sens 3.25")
	loaded.load_from_disk()
	_check(loaded.get_value("controls", "mouse_sensitivity") == 3.25, "console uses the persistent settings store")
	console.run("sens 2oops")
	console.run("sens nan")
	_check(preferences.get_value("controls", "mouse_sensitivity") == 3.25, "console rejects malformed numbers")
	console.free()
	var match_menu: PauseMenu = PauseMenu.new()
	match_menu.preferences = preferences
	root.add_child(match_menu)
	match_menu.open()
	await process_frame
	match_menu.show_settings()
	_check(match_menu.get("_settings_panel") is SettingsPanel, "match menu uses the same settings panel")
	match_menu.toggle()
	_check(match_menu.is_open() and match_menu.get("_settings_panel") == null, "Escape returns to the match menu before resuming")
	match_menu.close()
	match_menu.free()
	Engine.max_fps = 0
	FragrSettings.new().apply_audio()
	DirAccess.remove_absolute(path)
	await process_frame
	if _failures == 0:
		print("test_settings_panel: PASS save/cancel, failed write, runtime readers, console, match menu")
	quit(0 if _failures == 0 else 1)
