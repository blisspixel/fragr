extends SceneTree

# Headless checks on the settings store. No window, no engine state touched.
# Run: godot --path client --headless --script res://scripts/test_settings.gd

func _initialize() -> void:
	var ok: bool = true
	var script: GDScript = load("res://scripts/settings.gd") as GDScript
	if script == null:
		push_error("test_settings: failed to load settings.gd")
		quit(1)
		return

	var test_path: String = "user://test-settings-%d.cfg" % OS.get_process_id()
	var s: RefCounted = script.new(test_path)

	# A fresh store answers with the documented defaults.
	if not is_equal_approx(float(s.get_value("controls", "mouse_sensitivity")), 1.5):
		push_error("test_settings: default sensitivity must preserve the live camera")
		ok = false
	if not is_equal_approx(float(s.get_value("video", "vertical_fov")), 75.0):
		push_error("test_settings: default vertical FOV must preserve the live camera")
		ok = false

	# An unknown key falls back rather than returning null, so a config file
	# written by an older build cannot produce a missing value.
	if s.get_value("video", "no_such_key") != null:
		push_error("test_settings: an unknown key should be null, not invented")
		ok = false
	s.set_value("video", "vertical_fov", 90.0)
	if absf(float(s.get_value("video", "vertical_fov")) - 90.0) > 0.001:
		push_error("test_settings: a set value must read back")
		ok = false

	# The clamp exists so a hand-edited file cannot produce an unusable camera.
	s.set_value("video", "vertical_fov", 400.0)
	if absf(float(s.fov()) - 110.0) > 0.001:
		push_error("test_settings: fov must clamp to the top of the range")
		ok = false
	s.set_value("video", "vertical_fov", 5.0)
	if absf(float(s.fov()) - 60.0) > 0.001:
		push_error("test_settings: fov must clamp to the bottom of the range")
		ok = false

	# Reset restores a section without disturbing the others.
	s.set_value("audio", "effects", 1.0)
	s.reset_section("audio")
	if s.get_value("audio", "effects") != 0.5 or s.get_value("audio", "music") != 0.7:
		push_error("test_settings: audio reset must restore the balanced defaults")
		ok = false
	s.set_value("audio", "master", 0.1)
	s.reset_section("video")
	if absf(float(s.get_value("audio", "master")) - 0.1) > 0.001:
		push_error("test_settings: resetting one section must not touch another")
		ok = false
	if absf(float(s.get_value("video", "vertical_fov")) - 75.0) > 0.001:
		push_error("test_settings: resetting a section must restore its defaults")
		ok = false

	# A round trip through disk keeps every value.
	s.set_value("controls", "mouse_sensitivity", 2.25)
	s.set_value("gameplay", "head_bob", false)
	s.set_value("audio", "effects", 1.0)
	s.save_to_disk()
	var loaded: RefCounted = script.new(test_path)
	loaded.load_from_disk()
	if loaded.get_value("audio", "effects") != 1.0:
		push_error("test_settings: new defaults must preserve an existing full-volume preference")
		ok = false
	if absf(float(loaded.get_value("controls", "mouse_sensitivity")) - 2.25) > 1e-6:
		push_error("test_settings: sensitivity did not survive a save and load")
		ok = false
	if bool(loaded.get_value("gameplay", "head_bob")):
		push_error("test_settings: weapon bob did not survive a save and load")
		ok = false

	# Every default is reachable through get_value, which is what the menu
	# builds itself from, so a typo in DEFAULTS fails here rather than silently.
	for section in script.DEFAULTS:
		for key in (script.DEFAULTS[section] as Dictionary):
			if loaded.get_value(section, key) == null:
				push_error("test_settings: %s/%s read back as null" % [section, key])
				ok = false

	# The tips are player-facing text with a pure accessor, so they get checked
	# here rather than needing a harness of their own.
	var tips: GDScript = load("res://scripts/tips.gd") as GDScript
	if tips == null:
		push_error("test_settings: failed to load tips.gd")
		ok = false
	else:
		var total: int = int(tips.count())
		if total < 40:
			push_error("test_settings: only %d tips, the card will repeat itself" % total)
			ok = false
		# The draw is deterministic for a seed and covers the whole list.
		var seen: Dictionary = {}
		for i in range(total * 3):
			var t: String = str(tips.pick(i))
			if t.is_empty():
				push_error("test_settings: tip %d is empty" % i)
				ok = false
				break
			seen[t] = true
		if seen.size() != total:
			push_error("test_settings: the draw reached %d of %d tips" % [seen.size(), total])
			ok = false
		if tips.pick(7) != tips.pick(7 + total):
			push_error("test_settings: the draw is not deterministic for a seed")
			ok = false

	# Profile input stays bounded and cannot introduce line breaks into the HUD.
	s.set_value("profile", "name", "  Patch\n\t  ")
	if s.player_name() != "Patch":
		push_error("test_settings: callsign control characters must be removed")
		ok = false
	s.set_value("profile", "name", "x".repeat(80))
	if s.player_name().length() != 24:
		push_error("test_settings: callsign must fit its display contract")
		ok = false
	s.set_value("profile", "name", 42)
	if s.player_name() != "Meat Proxy":
		push_error("test_settings: invalid saved callsign needs a safe default")
		ok = false
	s.set_value("profile", "reticle_colour", ["invalid"])
	if s.get_value("profile", "reticle_colour") != "bone":
		push_error("test_settings: invalid reticle option must use the default")
		ok = false
	if s.player_body() != "human":
		push_error("test_settings: a new profile is human")
		ok = false
	for bad: Variant in ["robot", "res://assets/characters/free/synthetic.png", 3, null]:
		s.set_value("profile", "body", bad)
		if s.get_value("profile", "body") != "human":
			push_error("test_settings: an unknown body must narrow to human: " + str(bad))
			ok = false
	s.set_value("profile", "name", "Signal 67")
	s.set_value("profile", "reticle_colour", "cyan")
	s.set_value("profile", "body", "synthetic")
	if s.save_to_disk() != OK:
		push_error("test_settings: save must report success")
		ok = false
	loaded.load_from_disk()
	if loaded.player_name() != "Signal 67" or loaded.reticle_colour() != Color("8ee9df") 		or loaded.player_body() != "synthetic":
		push_error("test_settings: profile must survive a fresh instance")
		ok = false
	# Malformed config values never reach engine APIs through permissive casts.
	var invalid: ConfigFile = ConfigFile.new()
	invalid.set_value("video", "vertical_fov", "wide")
	invalid.set_value("video", "fps_cap", INF)
	invalid.set_value("video", "display_mode", true)
	invalid.set_value("video", "vsync", "false")
	invalid.set_value("controls", "mouse_sensitivity", [])
	invalid.set_value("audio", "master", -10)
	invalid.set_value("audio", "music", NAN)
	invalid.set_value("controls", "sensitivity", 0.0041)
	invalid.save(test_path)
	loaded.load_from_disk()
	if loaded.fov() != 75.0 or loaded.get_value("video", "fps_cap") != 0 or loaded.get_value("video", "display_mode") != 2:
		push_error("test_settings: invalid display values must use safe defaults")
		ok = false
	if loaded.get_value("video", "vsync") != false or loaded.get_value("controls", "mouse_sensitivity") != 1.5:
		push_error("test_settings: wrong types and legacy units must not be coerced")
		ok = false
	if loaded.get_value("audio", "master") != 0.0 or loaded.get_value("audio", "music") != 0.7:
		push_error("test_settings: volume must be finite and bounded")
		ok = false
	loaded.set_value("unknown", "anything", 1)
	if loaded.get_value("unknown", "anything") != null:
		push_error("test_settings: unknown settings must not be persisted")
		ok = false
	loaded.set_value("video", "display_mode", 1)
	if loaded.get_value("video", "display_mode") != 2:
		push_error("test_settings: legacy exclusive mode must map to portable fullscreen")
		ok = false
	for path in script.RANGES:
		var parts: PackedStringArray = str(path).split("/")
		var limits: Vector2 = script.RANGES[path]
		loaded.set_value(parts[0], parts[1], -10000.0)
		if float(loaded.get_value(parts[0], parts[1])) != limits.x:
			push_error("test_settings: missing lower bound for " + path)
			ok = false
		loaded.set_value(parts[0], parts[1], 10000.0)
		if float(loaded.get_value(parts[0], parts[1])) != limits.y:
			push_error("test_settings: missing upper bound for " + path)
			ok = false
	DirAccess.remove_absolute(test_path)
	if ok:
		print("test_settings: PASS defaults, fallback, clamp, reset, a disk round trip, and %d tips" % int(tips.count()))
		quit(0)
	else:
		push_error("test_settings: FAIL")
		quit(1)
