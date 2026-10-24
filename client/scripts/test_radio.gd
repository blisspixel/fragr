extends SceneTree
## Headless check for the radio: station grouping, shuffle without repeats,
## station cycling, and the volume state table. Run with:
## godot --headless --path client --script res://scripts/test_radio.gd

const RadioScript := preload("res://scripts/radio.gd")
const TourScript := preload("res://scripts/qa_tour.gd")

var failures: Array = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _initialize() -> void:
	_test_build_stations()
	_test_start_variation()
	_test_pick_next_no_repeat()
	_test_station_cycle_and_toggle()
	_test_volume_table()
	await _test_missing_track_stops_previous()
	await _test_scene_hold()
	await _test_playback_retirement()
	if failures.is_empty():
		print("test_radio: PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("test_radio: FAIL " + failure)
		quit(1)


func _fake_entries(station_id: String, count: int) -> Dictionary:
	var entries := {}
	for i in range(count):
		var name := "radio/%s/%02d-track" % [station_id, i + 1]
		entries[name] = {
			"kind": "music",
			"file": name + ".mp3",
			"title": "Track %d" % (i + 1),
			"length_ms": 120000,
		}
	return entries


func _test_build_stations() -> void:
	var station_list := [
		{"id": "rock", "name": "Larak Lot Rock", "tagline": "loud", "ducks_in_combat": true, "badge": "LR", "color": "#7A3A22"},
		{"id": "lockin", "name": "LOCK IN", "ducks_in_combat": false},
		{"name": "no id, must be skipped"},
	]
	var entries := _fake_entries("rock", 3)
	entries["fire_rail"] = {"kind": "sfx", "file": "fire_rail.wav"}
	entries["radio/rock/untitled"] = {"kind": "music", "file": "radio/rock/untitled.mp3"}
	var stations: Array = RadioScript.build_stations(station_list, entries)
	_check(stations.size() == 2, "build_stations keeps only stations with an id, got %d" % stations.size())
	if stations.size() < 2:
		return
	_check(stations[0]["tracks"].size() == 4, "rock should have 4 tracks, got %d" % stations[0]["tracks"].size())
	_check(stations[0]["tracks"][0]["path"] == "res://assets/audio/radio/rock/01-track.mp3", "track path uses the audio root")
	_check(stations[0]["tracks"][0]["title"] == "Track 1", "title comes from the manifest")
	_check(stations[0]["tracks"][3]["title"] == "untitled", "missing title falls back to the file stem")
	_check(stations[1]["tracks"].is_empty(), "lockin has no tracks in this manifest")
	_check(stations[1]["ducks_in_combat"] == false, "ducks_in_combat is read from stations.json")
	_check(stations[0]["ducks_in_combat"] == true, "default ducks_in_combat is true")
	_check(stations[0]["badge"] == "LR", "badge comes from stations.json")
	_check(stations[0]["color"] == "#7A3A22", "color comes from stations.json")
	_check(stations[1]["badge"] == "LO", "badge defaults to the first two letters of the id")
	_check(stations[1]["color"] == "#5A554F", "color defaults to gunmetal")


func _test_start_variation() -> void:
	var radio: Node = RadioScript.new()
	var entries: Dictionary = _fake_entries("a", 4)
	entries.merge(_fake_entries("b", 4))
	radio.stations = RadioScript.build_stations(
		[{"id": "empty"}, {"id": "a"}, {"id": "b"}], entries)
	var starts: Dictionary = {}
	for seed_value: int in range(64):
		radio.rng.seed = seed_value
		radio.history.clear()
		radio.choose_start_station()
		_check(radio.station_index == 1 or radio.station_index == 2,
			"normal startup chooses a populated station rather than an off-air station")
		var track: Dictionary = radio.pick_next(radio.current_station())
		starts[track["name"]] = true
	_check(starts.size() == 8, "startup varies both stations and their tracks across controlled seeds")
	radio.stations = [radio.stations[0], radio.stations[2]]
	radio.choose_start_station()
	_check(radio.station_index == 1, "a lone populated station is the safe startup choice")
	radio.stations = [radio.stations[0]]
	radio.choose_start_station()
	_check(radio.station_index == 0 and radio.current_station()["tracks"].is_empty(),
		"an entirely off-air catalog stays silent without an invalid random range")
	radio.stations.clear()
	radio.choose_start_station()
	_check(radio.station_index == 0 and radio.current_station().is_empty(),
		"an empty catalog remains safe")
	radio.free()


func _test_pick_next_no_repeat() -> void:
	var radio = RadioScript.new()
	radio.rng.seed = 7
	var station := {"id": "edm", "tracks": []}
	for i in range(20):
		station["tracks"].append({"name": "radio/edm/%02d" % i, "path": "", "title": "t%d" % i, "length_ms": 0})
	var seen: Array = []
	for i in range(radio.NO_REPEAT_WINDOW):
		var track = radio.pick_next(station)
		_check(not seen.has(track["name"]), "repeat inside the no-repeat window at pick %d" % i)
		seen.append(track["name"])
	_check(radio.history["edm"].size() == radio.NO_REPEAT_WINDOW, "history is capped at the window")
	var tiny := {"id": "one", "tracks": [{"name": "radio/one/01", "path": "", "title": "solo", "length_ms": 0}]}
	_check(radio.pick_next(tiny)["name"] == "radio/one/01", "single-track station still plays")
	_check(radio.pick_next(tiny)["name"] == "radio/one/01", "single-track station repeats when it must")
	_check(radio.pick_next({"id": "empty", "tracks": []}).is_empty(), "empty station returns nothing")
	radio.free()


func _test_station_cycle_and_toggle() -> void:
	var radio = RadioScript.new()
	radio.stations = RadioScript.build_stations(
		[{"id": "a", "name": "A"}, {"id": "b", "name": "B"}, {"id": "c", "name": "C"}],
		{}
	)
	var seen: Array = []
	radio.now_playing_changed.connect(func(info: Dictionary) -> void:
		seen.append(str(info["station"]) if info["state"] != "off" else "OFF"))
	radio.next_station()
	radio.next_station()
	_check(radio.station_index == 2 and radio.enabled, "next_station walks the dial")
	radio.next_station()
	_check(not radio.enabled and radio.now_playing()["state"] == "off", "past the last station the dial reaches RADIO OFF")
	radio.next_station()
	_check(radio.enabled and radio.station_index == 0, "next from RADIO OFF wraps to the first station, got %d" % radio.station_index)
	radio.prev_station()
	_check(not radio.enabled, "previous from the first station wraps back to RADIO OFF")
	radio.prev_station()
	_check(radio.enabled and radio.station_index == 2, "previous from RADIO OFF lands on the last station, got %d" % radio.station_index)
	_check(seen == ["B", "C", "OFF", "A", "OFF", "C"], "one now-playing change per dial step, in order, got %s" % str(seen))
	_check(radio.now_playing()["state"] == "off_air" and radio.now_playing()["title"] == "", "an empty station says off the air and names no song")
	seen.clear()
	radio.toggle()
	_check(radio.enabled == false and radio.now_playing()["state"] == "off", "toggle turns the radio off")
	radio.next_track()
	_check(not radio.enabled, "skip while off does not switch the radio on")
	radio.toggle()
	_check(radio.enabled == true and radio.station_index == 2, "toggle turns the radio back on at the same station")
	_check(seen == ["OFF", "OFF", "C"], "toggle and skip each announce the state, got %s" % str(seen))
	radio.free()
	_test_hold_gestures()
	var empty: Node = RadioScript.new()
	empty.next_station()
	empty.prev_station()
	empty.toggle()
	empty.next_track()
	_check(empty.now_playing()["state"] == "none" and empty.enabled, "an empty catalog ignores every control")
	empty.free()


func _pad_button(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


## D-pad left and right turn the dial on release; holding right skips the
## track and holding left is power. Keys act at once.
func _test_hold_gestures() -> void:
	var radio: Node = RadioScript.new()
	radio.stations = RadioScript.build_stations([{"id": "a", "name": "A"}, {"id": "b", "name": "B"}], {})
	var right_down: InputEventJoypadButton = _pad_button(JOY_BUTTON_DPAD_RIGHT, true)
	_check(right_down.is_action_pressed("radio_next_station"), "D-pad right is the next station")
	_check(_pad_button(JOY_BUTTON_DPAD_LEFT, true).is_action_pressed("radio_prev_station"), "D-pad left is the previous station")
	_check(radio.handle_input(right_down), "the D-pad arm is a radio control")
	Input.action_press("radio_next_station")
	_check(radio.station_index == 0, "a pad arm waits for release before turning the dial")
	radio.advance_holds(0.1)
	Input.action_release("radio_next_station")
	radio.handle_input(_pad_button(JOY_BUTTON_DPAD_RIGHT, false))
	_check(radio.station_index == 1 and radio.enabled, "a short press of D-pad right turns to the next station")
	var skips: Array = []
	radio.now_playing_changed.connect(func(info: Dictionary) -> void: skips.append(info["state"]))
	radio.handle_input(right_down)
	Input.action_press("radio_next_station")
	radio.advance_holds(RadioScript.HOLD_SECONDS * 0.5)
	_check(skips.is_empty(), "a hold does nothing before the threshold")
	radio.advance_holds(RadioScript.HOLD_SECONDS)
	_check(skips.size() == 1 and radio.station_index == 1, "holding D-pad right skips the track without changing station")
	radio.advance_holds(1.0)
	_check(skips.size() == 1, "a long hold skips only once")
	Input.action_release("radio_next_station")
	radio.handle_input(_pad_button(JOY_BUTTON_DPAD_RIGHT, false))
	_check(radio.station_index == 1 and skips.size() == 1, "releasing after a hold does not also turn the dial")
	radio.handle_input(_pad_button(JOY_BUTTON_DPAD_LEFT, true))
	Input.action_press("radio_prev_station")
	radio.advance_holds(RadioScript.HOLD_SECONDS + 0.01)
	_check(not radio.enabled, "holding D-pad left switches the radio off")
	Input.action_release("radio_prev_station")
	radio.handle_input(_pad_button(JOY_BUTTON_DPAD_LEFT, false))
	_check(not radio.enabled and radio.station_index == 1, "release after the power hold leaves the dial alone")
	radio.handle_input(_pad_button(JOY_BUTTON_DPAD_LEFT, true))
	Input.action_press("radio_prev_station")
	radio.advance_holds(RadioScript.HOLD_SECONDS + 0.01)
	Input.action_release("radio_prev_station")
	radio.handle_input(_pad_button(JOY_BUTTON_DPAD_LEFT, false))
	_check(radio.enabled and radio.station_index == 1, "holding D-pad left again switches it back on at the same station")
	# A hold whose release never arrives is dropped, not fired.
	radio.handle_input(right_down)
	radio.advance_holds(RadioScript.HOLD_SECONDS + 0.01)
	_check(radio._holds.is_empty() and radio.station_index == 1, "a lost release drops the hold without acting")
	_check(radio.handle_input(_key(KEY_C)) and not radio.enabled, "C turns at once, past the last station to RADIO OFF")
	_check(radio.handle_input(_key(KEY_C)) and radio.station_index == 0 and radio.enabled, "C again wraps to the first station")
	_check(radio.handle_input(_key(KEY_X)) and not radio.enabled, "X turns back through RADIO OFF")
	_check(radio.handle_input(_key(KEY_X)) and radio.station_index == 1 and radio.enabled, "X again lands on the last station")
	_check(radio.handle_input(_key(KEY_M)) and not radio.enabled, "M is power")
	_check(radio.handle_input(_key(KEY_M)) and radio.enabled, "M again is power on")
	var skipped: Array = []
	radio.now_playing_changed.connect(func(_info: Dictionary) -> void: skipped.append(true))
	_check(radio.handle_input(_key(KEY_N)) and skipped.size() == 1, "N skips the track")
	_check(not radio.handle_input(_key(KEY_W)), "movement is not a radio control")
	var echo: InputEventKey = _key(KEY_C)
	echo.echo = true
	_check(not radio.handle_input(echo) and radio.station_index == 1, "key repeat does not spin the dial")
	radio.free()


## A track that fails to load must stop the song before it, never leave it
## playing under the new station's name.
func _test_missing_track_stops_previous() -> void:
	var radio: Node = RadioScript.new()
	root.add_child(radio)
	await process_frame
	radio.stations = RadioScript.build_stations([{"id": "lockin", "name": "LOCK IN"}, {"id": "ghost", "name": "Ghost"}], {
		"radio/lockin/01-push": {"file": "radio/lockin/01-push.mp3", "title": "Push Push Push Push"},
		"radio/ghost/01-missing": {"file": "radio/ghost/01-missing.mp3", "title": "Never Shipped"},
	})
	radio.station_index = 0
	radio.enabled = true
	radio.play_random()
	_check(radio.player.stream != null and radio.now_playing()["state"] == "playing" and radio.now_playing()["title"] == "Push Push Push Push",
		"a committed track loads and is named")
	radio.next_station()
	var info: Dictionary = radio.now_playing()
	_check(radio.player.stream == null and not radio.player.playing, "a missing file stops the previous song")
	_check(info["state"] == "unavailable" and info["title"] == "" and info["station"] == "Ghost", "the state names the station and no song")
	radio.prev_station()
	_check(radio.now_playing()["state"] == "playing" and radio.player.stream != null, "changing station recovers")
	root.remove_child(radio)
	radio.free()


func _test_scene_hold() -> void:
	var radio: Node = RadioScript.new()
	root.add_child(radio)
	await process_frame
	radio.stations = RadioScript.build_stations([{"id": "lockin", "name": "LOCK IN"}], {
		"radio/lockin/01-push": {"file": "radio/lockin/01-push.mp3", "title": "Push Push Push Push"},
	})
	radio.station_index = 0
	radio.enabled = true
	radio.play_random()
	var announced: Array = []
	radio.now_playing_changed.connect(func(info: Dictionary) -> void: announced.append(info["state"]))
	radio.set_scene_hold(true)
	_check(radio.player.stream_paused and radio.now_playing()["state"] == "held", "a story scene pauses the station")
	radio.set_scene_hold(true)
	_check(announced == ["held"], "a repeated hold announces once")
	radio.next_track()
	_check(radio.player.stream_paused, "a track chosen during a scene stays paused")
	radio.set_scene_hold(false)
	_check(not radio.player.stream_paused and radio.now_playing()["state"] == "playing", "the station resumes after the scene")
	root.remove_child(radio)
	radio.free()


func _test_volume_table() -> void:
	_check(is_equal_approx(RadioScript.target_db(false, false, true), -6.0), "spectating sits at -6 dB")
	_check(is_equal_approx(RadioScript.target_db(true, false, true), -8.0), "playing keeps music present at -8 dB")
	_check(is_equal_approx(RadioScript.target_db(false, true, true), -15.0), "spectating plus duck is -15 dB")
	_check(is_equal_approx(RadioScript.target_db(true, true, true), -17.0), "playing plus duck is -17 dB")
	_check(is_equal_approx(RadioScript.target_db(true, true, false), -8.0), "LOCK IN does not duck while playing")
	_check(is_equal_approx(RadioScript.target_db(false, true, false), -15.0), "LOCK IN still ducks under the Host while spectating")


func _test_playback_retirement() -> void:
	for iteration: int in 3:
		var radio: Node = RadioScript.new()
		root.add_child(radio)
		await process_frame
		var player: AudioStreamPlayer = radio.player
		_check(player != null and player.stream is AudioStreamMP3, "radio %d starts an MP3" % iteration)
		_check(player != null and player.has_stream_playback(), "radio %d starts playback" % iteration)
		if player == null or not player.has_stream_playback():
			root.remove_child(radio)
			radio.free()
			return
		if iteration == 0:
			_check(TourScript.fixed_radio_track(radio, "radio/lockin/missing").is_empty(),
				"QA comparison rejects a track outside the committed station catalog")
			var selected: Dictionary = TourScript.fixed_radio_track(radio, "radio/lockin/01-push")
			_check(selected.get("title") == "Push Push Push Push"
				and selected.get("path") == "res://assets/audio/radio/lockin/01-push.mp3"
				and TourScript.radio_comparison_matches(radio, selected),
				"QA comparison plays the fixed committed track on the ordinary radio")
			radio.play_random()
			_check(TourScript.radio_comparison_matches(radio, selected),
				"QA comparison repeats the same track if playback rolls over")
			radio.load_catalog()
			for step: int in range(radio.stations.size() + 1):
				radio.next_station()
				var players: int = 0
				for child: Node in radio.get_children():
					if child is AudioStreamPlayer:
						players += 1
				_check(players == 1, "station change %d keeps a single radio player" % step)
				var state: String = str(radio.now_playing()["state"])
				_check((state == "playing") == player.playing, "station change %d: playing label matches the player (%s)" % [step, state])
			_check(radio.enabled, "a full turn of the dial returns to a station")
		var playback: WeakRef = weakref(player.get_stream_playback())
		root.remove_child(radio)
		_check(not player.playing, "scene exit stops radio %d" % iteration)
		_check(player.stream == null, "scene exit drops radio %d stream" % iteration)
		radio.free()
		var deadline: int = Time.get_ticks_msec() + 2000
		while playback.get_ref() != null and Time.get_ticks_msec() < deadline:
			await create_timer(0.01).timeout
		_check(playback.get_ref() == null, "radio %d decoder retires" % iteration)
