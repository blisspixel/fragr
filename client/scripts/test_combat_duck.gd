extends SceneTree

## Headless ducking gate: combat near the listener always lowers the radio
## and the campaign score (CombatDuck), on every station, under the Host's
## own duck, and lets them back up once the fight cools. The radio part is
## measured through the mixer: a steady tone on the radio's own player,
## recorded on Master before, during and after a burst of nearby fire.
## Prints the measured levels. Run:
## godot --headless --path client --script res://scripts/test_combat_duck.gd

const RadioScript := preload("res://scripts/radio.gd")
## Full combat must take music down at least this far through the mixer.
const MIN_MEASURED_DUCK_DB: float = 8.0

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_combat_duck: " + message)


func _run() -> void:
	_check_heat()
	_check_nearness()
	_check_tables()
	await _check_radio_through_the_mixer()
	if _failures == 0:
		print("test_combat_duck: PASS")
	quit(0 if _failures == 0 else 1)


func _check_heat() -> void:
	var duck: CombatDuck = CombatDuck.new()
	_check(duck.duck_db() == 0.0, "no fight, no duck")
	duck.add(3, 0)
	_check(duck.duck_db() < -2.0 and duck.duck_db() > CombatDuck.FULL_DB, "a few shots duck part way: %.1f" % duck.duck_db())
	duck.add(0, 4)
	_check(is_equal_approx(duck.duck_db(), CombatDuck.FULL_DB), "a sustained fight ducks fully")
	duck.add(100, 100)
	_check(duck.heat <= CombatDuck.MAX_HEAT, "heat is bounded, so a long fight recovers in bounded time")
	duck.cool(1.0)
	_check(is_equal_approx(duck.duck_db(), CombatDuck.FULL_DB), "the duck holds a moment after the last shot")
	duck.cool(CombatDuck.MAX_HEAT / CombatDuck.COOL_PER_SECOND)
	_check(duck.duck_db() == 0.0, "the duck lifts once the fight cools")
	duck.add(-5, -5)
	duck.cool(-1.0)
	_check(duck.heat == 0.0, "negative input is ignored")


func _check_nearness() -> void:
	var me: String = "me"
	var positions: Dictionary = {"near": Vector3(0.0, 0.0, -20.0), "far": Vector3(0.0, 0.0, -90.0), "me": Vector3.ZERO}
	var results: Array = [
		{"shooter_id": "me", "target_id": "far"},
		{"shooter_id": "far", "target_id": "me"},
		{"shooter_id": "near", "target_id": "someone"},
		{"shooter_id": "far", "target_id": "someone"},
		{"shooter_id": "unknown"},
		"junk",
	]
	_check(CombatDuck.shots_near(results, me, Vector3.ZERO, positions) == 3, "own shots, shots at me and nearby fire count; a far duel does not")
	_check(CombatDuck.shots_near(results, "", Vector3.ZERO, positions) == 2, "a spectator hears the fights near its camera")
	_check(CombatDuck.shots_near(results, "", Vector3.INF, positions) == 0, "no listener, no nearby fire")
	_check(CombatDuck.shots_near("junk", me, Vector3.ZERO, positions) == 0, "malformed results are ignored")
	var blasts: Array = [{"position": [0.0, 0.0, 30.0]}, {"position": [0, 0, 300]}, {"position": [1, 2]}, {"position": ["a", 0, 0]}, 7]
	_check(CombatDuck.blasts_near(blasts, Vector3.ZERO) == 1, "a blast 30 m away counts; far and malformed ones do not")
	_check(CombatDuck.blasts_near(blasts, Vector3.INF) == 0 and CombatDuck.blasts_near(null, Vector3.ZERO) == 0, "no listener or no list is nothing")


func _check_tables() -> void:
	# Combat lowers every station, LOCK IN included, playing or watching.
	for human: bool in [true, false]:
		for station_ducks: bool in [true, false]:
			var calm: float = RadioScript.target_db(human, false, station_ducks)
			var fight: float = RadioScript.target_db(human, false, station_ducks, 1.0)
			_check(is_equal_approx(fight, calm + CombatDuck.FULL_DB), "combat ducks the radio (human %s, station ducks %s): %.1f to %.1f" % [human, station_ducks, calm, fight])
	# The Host's duck and the fight's stack: a call over a firefight is clear.
	_check(is_equal_approx(RadioScript.target_db(false, true, true, 1.0), RadioScript.SPECTATE_DB + RadioScript.DUCK_DB + CombatDuck.FULL_DB), "Host plus combat stack")
	# The campaign score reads the same rule.
	var bed: float = CampaignScore.target_db(true, true, false, false, false, false, 0.0)
	var fight: float = CampaignScore.target_db(true, true, false, false, false, false, 1.0)
	_check(is_equal_approx(fight, bed + CombatDuck.FULL_DB), "combat ducks the campaign score by the same amount")
	_check(CampaignScore.COMBAT_DUCK_DB == CombatDuck.FULL_DB, "one combat duck depth")
	var score: CampaignScore = CampaignScore.new()
	score.combat(20, 1)
	_check(is_equal_approx(CombatDuck.db_for(score.combat_duck.heat), CombatDuck.FULL_DB), "score combat() feeds its CombatDuck")
	score.free()


static func _tone() -> AudioStreamWAV:
	var rate: int = 44100
	var data: PackedByteArray = PackedByteArray()
	data.resize(rate * 2)
	for frame: int in range(rate):
		data.encode_s16(frame * 2, int(round(0.25 * 32767.0 * sin(TAU * 440.0 * float(frame) / float(rate)))))
	var clip: AudioStreamWAV = AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = rate
	clip.data = data
	clip.loop_mode = AudioStreamWAV.LOOP_FORWARD
	clip.loop_end = rate
	return clip


func _level(recorder: AudioEffectRecord, seconds: float) -> float:
	recorder.set_recording_active(true)
	await create_timer(seconds).timeout
	var take: AudioStreamWAV = recorder.get_recording()
	recorder.set_recording_active(false)
	if take == null or take.data.size() < 8:
		return -INF
	var sum: float = 0.0
	var count: int = 0
	for index: int in range(take.data.size() / 2, take.data.size() - 1, 2):
		var value: float = float(take.data.decode_s16(index)) / 32768.0
		sum += value * value
		count += 1
	return 20.0 * log(sqrt(sum / float(count))) / log(10.0) if sum > 0.0 else -INF


func _check_radio_through_the_mixer() -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	var recorder: AudioEffectRecord = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(master, recorder)
	var radio: Node = RadioScript.new()
	root.add_child(radio)
	await process_frame
	radio.enabled = true
	radio.set_human_mode(true)
	radio.player.stream = _tone()
	radio.player.play()
	await create_timer(0.5).timeout
	var calm: float = await _level(recorder, 0.4)
	# A burst of nearby fire, the way game_manager feeds it each tick.
	for tick: int in range(10):
		radio.combat(2, 0)
		await create_timer(0.05).timeout
	var fight: float = await _level(recorder, 0.4)
	# Keep firing for a second, then stop and let it cool.
	for tick: int in range(20):
		radio.combat(1, 0)
		await create_timer(0.05).timeout
	var held: float = await _level(recorder, 0.3)
	await create_timer(CombatDuck.MAX_HEAT / CombatDuck.COOL_PER_SECOND + RadioScript.DUCK_RECOVER_SECONDS + 0.5).timeout
	var after: float = await _level(recorder, 0.4)
	print("test_combat_duck: radio through Master: calm %.1f dB, in the fight %.1f dB (%.1f), held %.1f dB, recovered %.1f dB" % [calm, fight, fight - calm, held, after])
	_check(calm > -60.0, "the radio is audible before the fight: %.1f" % calm)
	_check(calm - fight >= MIN_MEASURED_DUCK_DB, "nearby fire ducks the radio %d dB or more: %.1f" % [int(MIN_MEASURED_DUCK_DB), calm - fight])
	_check(calm - held >= MIN_MEASURED_DUCK_DB, "a continuing fight keeps it down: %.1f" % (calm - held))
	_check(absf(after - calm) < 1.0, "the radio returns once the fight cools: %.1f vs %.1f" % [after, calm])
	radio.player.stop()
	radio.player.stream = null
	await create_timer(0.1).timeout
	root.remove_child(radio)
	radio.free()
	for index: int in range(AudioServer.get_bus_effect_count(master) - 1, -1, -1):
		if AudioServer.get_bus_effect(master, index) == recorder:
			AudioServer.remove_bus_effect(master, index)
	await process_frame
