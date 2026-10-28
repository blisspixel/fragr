extends SceneTree

## Headless gate for the shooter's hit confirm: the tier each reported hit
## earns (stopped, body, headshot, kill), body pitch rising with damage, the
## gap that keeps automatic fire from machine-gunning it, the Effects bus, the
## shipped clips, and the HUD seam that game_manager calls once per shot.
## Run: godot --path client --headless --script res://scripts/test_hit_chime.gd

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_hit_chime: " + message)


func _run() -> void:
	_check_tiers()
	await _check_gap()
	_check_clips()
	await _check_hud()
	if _failures == 0:
		print("test_hit_chime: PASS")
	quit(0 if _failures == 0 else 1)


func _check_tiers() -> void:
	_check(HitChime.tier_for(0, false, false) == HitChime.Tier.BLOCKED, "zero damage is a stopped shot")
	_check(HitChime.tier_for(0, true, false) == HitChime.Tier.BLOCKED, "a shield that took nothing is no headshot")
	_check(HitChime.tier_for(24, false, false) == HitChime.Tier.BODY, "damage is a body hit")
	_check(HitChime.tier_for(48, true, false) == HitChime.Tier.HEAD, "the server's head fact is the head tier")
	_check(HitChime.tier_for(48, true, true) == HitChime.Tier.KILL, "a kill outranks a headshot")
	_check(HitChime.tier_for(12, false, true) == HitChime.Tier.KILL, "the frag shot is the kill tier")
	# Body pitch climbs with damage and stops at the top.
	var pitches: Array[float] = []
	for damage: int in [1, 12, 25, 50, 80, 100, 160]:
		pitches.append(HitChime.pitch_for(HitChime.Tier.BODY, damage))
	for i: int in range(1, pitches.size() - 1):
		_check(pitches[i] > pitches[i - 1], "body pitch rises with damage: " + str(pitches))
	_check(is_equal_approx(pitches[pitches.size() - 1], pitches[pitches.size() - 2]), "body pitch tops out at 100 damage")
	_check(pitches[0] >= 0.9 and pitches.back() <= 1.3, "body pitch stays in its range: " + str(pitches))
	_check(HitChime.pitch_for(HitChime.Tier.HEAD, 160) > HitChime.pitch_for(HitChime.Tier.HEAD, 20), "a harder headshot rings higher")
	_check(HitChime.pitch_for(HitChime.Tier.BLOCKED, 0) < pitches[0], "a stopped shot sits under every hit")
	# Each tier above a body hit has its own clip, not a repitched tick.
	var paths: Dictionary = {}
	for tier: int in [HitChime.Tier.BODY, HitChime.Tier.HEAD, HitChime.Tier.KILL]:
		paths[HitChime.path_for(tier)] = tier
	_check(paths.size() == 3, "body, head and kill are three clips: " + str(paths.keys()))
	_check(HitChime.path_for(HitChime.Tier.BLOCKED) == HitChime.BODY_PATH, "a stopped shot reuses the body tick")


func _tone() -> AudioStreamWAV:
	var clip: AudioStreamWAV = AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_8_BITS
	clip.mix_rate = 8000
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(800)
	clip.data = bytes
	return clip


func _check_gap() -> void:
	var chime: HitChime = HitChime.new()
	var asked: Array[String] = []
	var tone: AudioStreamWAV = _tone()
	chime.clip_source = func(path: String) -> AudioStream:
		asked.append(path)
		return tone
	root.add_child(chime)
	await process_frame
	var hit_player: AudioStreamPlayer = chime.get_node("HitChimePlayer") as AudioStreamPlayer
	var kill_player: AudioStreamPlayer = chime.get_node("KillChimePlayer") as AudioStreamPlayer
	_check(hit_player.bus == &"Effects" and kill_player.bus == &"Effects", "the confirm plays on the Effects bus")
	# A Repeater stream: a hit every 100 ms.
	var sounded: Array[int] = []
	for shot: int in range(10):
		sounded.append(chime.confirm(9, false, false, 1000 + shot * 100))
	var played: int = sounded.count(HitChime.Tier.BODY)
	_check(played == 5 and sounded.count(-1) == 5, "a 10 per second stream chimes every other hit: " + str(sounded))
	# Slower guns chime on every hit.
	var arc: Array[int] = []
	for shot: int in range(4):
		arc.append(chime.confirm(18, false, false, 5000 + shot * 150))
	_check(arc.count(-1) == 0, "the Arc's 150 ms chimes every hit: " + str(arc))
	# Inside the gap a higher tier still sounds; the same or lower does not.
	_check(chime.confirm(20, false, false, 8000) == HitChime.Tier.BODY, "a body hit sounds")
	_check(chime.confirm(40, true, false, 8040) == HitChime.Tier.HEAD, "a headshot inside the gap outranks the body tick")
	_check(chime.confirm(40, true, false, 8080) == -1, "a second headshot inside the gap waits")
	_check(chime.confirm(20, false, false, 8100) == -1, "a lower tier inside the gap waits")
	_check(chime.confirm(60, false, true, 8110) == HitChime.Tier.KILL, "a kill always sounds")
	_check(kill_player.playing and kill_player.volume_db > hit_player.volume_db - 6.0, "the kill has its own player")
	_check(chime.confirm(60, false, true, 8120) == HitChime.Tier.KILL, "two frags in one blast both sound")
	_check(chime.confirm(10, false, false, 9000) == HitChime.Tier.BODY and is_equal_approx(chime.last_pitch, HitChime.pitch_for(HitChime.Tier.BODY, 10)),
		"after the gap the pitch is the damage's: " + str(chime.last_pitch))
	_check(chime.confirm(95, false, false, 9200) == HitChime.Tier.BODY and chime.last_pitch > HitChime.pitch_for(HitChime.Tier.BODY, 10),
		"a bigger hit rings higher")
	_check(chime.confirm(0, false, false, 9400) == HitChime.Tier.BLOCKED and hit_player.volume_db < -8.0, "a stopped shot is low and quiet")
	_check(asked.size() == 3, "each clip loads once: " + str(asked))
	var retirement: ClientRetirement = ClientRetirement.for_tree(self)
	retirement.track_audio(chime)
	chime.silence()
	chime.clip_source = Callable()
	chime.queue_free()
	_check(await retirement.drain(), "the chime's playbacks retire")


## The shipped clips: short one-shots the importer keeps as samples.
func _check_clips() -> void:
	for path: String in [HitChime.BODY_PATH, HitChime.HEAD_PATH, HitChime.KILL_PATH]:
		_check(ResourceLoader.exists(path), "the clip ships: " + path)
		if not ResourceLoader.exists(path):
			continue
		var clip: AudioStream = load(path) as AudioStream
		_check(clip is AudioStreamWAV, "a confirm is a WAV sample: " + path)
		if clip != null:
			_check(clip.get_length() > 0.05 and clip.get_length() < 0.8, "a confirm is short: %s %.3f s" % [path, clip.get_length()])
	var body: AudioStream = load(HitChime.BODY_PATH) as AudioStream
	var kill: AudioStream = load(HitChime.KILL_PATH) as AudioStream
	if body != null and kill != null:
		_check(kill.get_length() >= body.get_length(), "the kill rings at least as long as a hit")


func _check_hud() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	var hud: CanvasLayer = scene.get_node("HUD")
	scene.remove_child(hud)
	scene.free()
	root.add_child(hud)
	await process_frame
	var chime: HitChime = hud.get("hit_chime") as HitChime
	_check(chime != null, "the HUD owns one hit chime")
	if chime != null:
		var before: int = chime.played
		hud.show_hit_marker(40, "Tack")
		_check(chime.played == before, "the marker alone does not chime; game_manager confirms once per shot")
		_check(hud.confirm_hit(40, true, false) == HitChime.Tier.HEAD, "the HUD seam plays the server's tier")
		_check(chime.played == before + 1, "one confirm per call")
	# Retire the HUD's playbacks the way the match scene does on exit.
	var retirement: ClientRetirement = ClientRetirement.for_tree(self)
	retirement.track_audio(hud)
	if chime != null:
		chime.silence()
	hud.queue_free()
	_check(await retirement.drain(), "the HUD's confirm playbacks retire before exit")
