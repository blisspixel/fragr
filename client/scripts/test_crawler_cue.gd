extends SceneTree

class CaptionHud extends Node:
	var shown: int = 0
	var crawler_caption: CrawlerCaption = null
	func show_crawler_scrabble_caption() -> void:
		shown += 1

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("test_crawler_cue: " + message)

func _run() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/crawler_scrabble-manifest.json"))
	var path: String = "res://assets/audio/" + str(record.get("file", ""))
	var stream: AudioStreamWAV = load(path) as AudioStreamWAV
	_expect(stream != null and stream.mix_rate == 24000 and not stream.stereo, "offline Crawler WAV imports as mono 24 kHz")
	_expect(FileAccess.get_sha256(path) == record.get("sha256"), "Crawler WAV matches its deterministic manifest")
	var caption := CrawlerCaption.new()
	root.add_child(caption)
	var effects: int = AudioServer.get_bus_index(&"Effects")
	_expect(effects >= 0, "Effects bus exists")
	var prior_mute: bool = AudioServer.is_bus_mute(effects)
	AudioServer.set_bus_mute(effects, true)
	_expect(caption.push_scrabble(1000), "first scrabble is captioned")
	_expect(caption.caption_label.visible and caption.caption_label.text == tr(CrawlerCaption.CAPTION_KEY), "caption remains visible with Effects muted")
	_expect(not caption.push_scrabble(1100) and caption.entries.size() == 1, "near duplicate is suppressed")
	_expect(caption.push_scrabble(2000) and caption.entries.size() == 2, "later cue joins bounded caption queue")
	_expect(caption.push_scrabble(3000) and caption.entries.size() == 2, "caption queue never exceeds two entries")
	caption.prune(6000)
	_expect(caption.entries.is_empty() and not caption.caption_label.visible, "expired captions leave the screen")
	caption.clear()
	_expect(caption.push_scrabble(6000), "new mission resets caption dedup")
	AudioServer.set_bus_mute(effects, prior_mute)
	caption.free()

	var manager: Variant = Node.new()
	root.add_child(manager)
	manager.set_script(load("res://scripts/game_manager.gd"))
	var arena: Node3D = Node3D.new()
	arena.name = "Arena"
	manager.add_child(arena)
	var spectator_camera: Node3D = Node3D.new()
	spectator_camera.name = "SpectatorCamera"
	manager.add_child(spectator_camera)
	var lens: Camera3D = Camera3D.new()
	lens.name = "Camera3D"
	spectator_camera.add_child(lens)
	var hud := CaptionHud.new()
	manager.add_child(hud)
	manager.hud = hud
	manager.crawler_sound_stream = stream
	_expect(manager._crawler_position([1.0, 2.0, 3.0]) == Vector3(1.0, 2.0, 3.0), "finite world position accepted")
	for bad: Variant in [null, [], [1, 2], [1, "2", 3], [NAN, 1, 2], [10001, 1, 2]]:
		_expect(not manager._crawler_position(bad).is_finite(), "malformed Crawler position rejected")
	lens.global_position = Vector3(100.0, 0.0, 100.0)
	manager._on_event_received({"event": "crawler_scrabble", "position": [1.0, 0.0, 2.0]})
	_expect(manager.crawler_scrabble_count == 0 and hud.shown == 0 and manager.crawler_sound_players.is_empty(), "remote listener gets no false nearby caption or sound")
	lens.global_position = Vector3(0.0, 1.5, 0.0)
	manager._on_event_received({"event": "crawler_scrabble", "position": [1.0, 0.0, 2.0]})
	_expect(manager.crawler_scrabble_count == 1 and hud.shown == 1, "valid event drives caption and cue counter")
	_expect(manager.crawler_sound_players.size() == 1 and manager.crawler_sound_players[0].global_position == Vector3(1.0, 0.0, 2.0), "sound plays at server world position")
	manager._on_event_received({"event": "crawler_scrabble", "position": [1.0, 0.0, 2.0]})
	_expect(manager.crawler_scrabble_count == 1 and hud.shown == 1, "duplicate event cannot stack sound or caption")
	manager._on_event_received({"event": "crawler_scrabble", "position": [NAN, 0.0, 2.0]})
	_expect(manager.crawler_scrabble_count == 1 and hud.shown == 1, "malformed event never reaches sound or caption")
	var old_voice: AudioStreamPlayer3D = manager.crawler_sound_players[0]
	arena.free()
	var replacement: Node3D = Node3D.new()
	replacement.name = "Arena"
	manager.add_child(replacement)
	manager._play_crawler_scrabble(Vector3(4.0, 0.0, 5.0))
	_expect(not is_instance_valid(old_voice) and manager.crawler_sound_players.size() == 1, "freed arena voice is replaced")
	_expect(manager.crawler_sound_players[0].get_parent() == replacement, "replacement voice belongs to live arena")
	manager._reset_crawler_cues()
	_expect(manager.crawler_scrabble_count == 0 and manager._accept_crawler_scrabble(Vector3(1.0, 0.0, 2.0), Time.get_ticks_msec()), "mission reset re-arms first cue")
	manager.free()
	if failures == 0:
		print("test_crawler_cue: PASS")
	quit(1 if failures else 0)
