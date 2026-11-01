extends SceneTree

## Headless gate for fighters' feet (footsteps.gd, footstep_gait.gd,
## footstep_surface.gd) and the master limiter, measured through the real
## mixer with AudioEffectRecord (the Dummy driver mixes in real time):
## - the gait: running steps at about three a second, silence when walking or
##   crouched, a jump only on a rising take-off, landings after real airtime;
## - the attenuation curve of the footstep player, sampled at 1 to 40 m: a
##   running step at 20 to 30 m is still inside the mix window and nothing is
##   heard past MAX_DISTANCE;
## - direction: the left-right level difference at 45 degree bearings;
## - surfaces from MapInfo kits, both shipped takes, own-feet level;
## - the Master limiter holding an overdriven tone under its ceiling.
## Prints the measured table. Run:
## godot --headless --path client --script res://scripts/test_footsteps.gd

## The mix window: a step this far under the same step at 2 m is still above
## a game mix's floor (fun-craft-targets row 18, audible to 20 to 30 m).
const AUDIBLE_WINDOW_DB: float = 24.0
const DISTANCES: Array[float] = [1.0, 2.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 50.0, 60.0]
const BEARINGS: Array[float] = [-90.0, -45.0, 0.0, 45.0, 90.0]
## Two bearings 45 degrees apart must differ by at least this much between ears.
const MIN_BEARING_STEP_DB: float = 2.0

var _failures: int = 0
var _world: Node3D = null
var _camera: Camera3D = null
var _recorder: AudioEffectRecord = null
var _mixer_warm: bool = false
var _master: int = -1


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_footsteps: " + message)


func _run() -> void:
	_check_gait()
	_check_surfaces()
	_check_clips()
	_setup_world()
	await _check_curve()
	await _check_direction()
	await _check_playback()
	await _check_limiter()
	await _teardown()
	if _failures == 0:
		print("test_footsteps: PASS")
	quit(0 if _failures == 0 else 1)


## Seconds of running at `speed` on flat ground, 60 frames a second.
func _events(gait: FootstepGait, seconds: float, speed: float, ducking: bool = false, airborne: bool = false, rise: float = 0.0) -> Array[String]:
	var out: Array[String] = []
	var delta: float = 1.0 / 60.0
	for frame: int in range(int(round(seconds * 60.0))):
		var event: String = gait.advance(delta, speed * delta, rise, airborne, ducking, true, false)
		if not event.is_empty():
			out.append(event)
	return out


func _check_gait() -> void:
	var gait: FootstepGait = FootstepGait.new()
	var run: Array[String] = _events(gait, 3.0, 6.0)
	_check(run.size() >= 8 and run.size() <= 10 and run.all(func(e: String) -> bool: return e == FootstepGait.STEP),
		"a 6 m/s run is about three steps a second: %s" % [run])
	gait.reset()
	_check(_events(gait, 3.0, 3.0).is_empty(), "a 3 m/s walk is silent")
	gait.reset()
	_check(_events(gait, 3.0, 2.04).is_empty(), "the crouch walk speed is silent")
	gait.reset()
	_check(_events(gait, 3.0, 6.0, true).is_empty(), "a crouched run is silent")
	# The server's bots hear runs from the same speed.
	_check(FootstepGait.RUN_SPEED == 3.5, "the run line matches the bots' ears (FOOTSTEP_SPEED 3.5)")
	# A first step comes half a stride into a run, not a full one.
	gait.reset()
	var first: int = -1
	for frame: int in range(60):
		if gait.advance(1.0 / 60.0, 0.1, 0.0, false, false, true, false) == FootstepGait.STEP:
			first = frame
			break
	_check(first >= 8 and first <= 10, "the first footfall lands about a metre in: frame %d" % first)
	# Jump: rising take-off, airtime, landing.
	gait.reset()
	_events(gait, 0.2, 6.0)
	var take_off: Array[String] = _events(gait, 0.1, 6.0, false, true, 0.1)
	_check(take_off == [FootstepGait.JUMP], "a rising take-off is one jump: %s" % [take_off])
	_events(gait, 0.5, 6.0, false, true, -0.1)
	var landing: Array[String] = _events(gait, 1.0 / 60.0, 6.0)
	_check(landing == [FootstepGait.LAND] and gait.landing_db == 0.0, "a full jump lands at full weight: %s %.1f" % [landing, gait.landing_db])
	# A hop lands lighter.
	gait.reset()
	_events(gait, 0.2, 0.0, false, true, 0.05)
	_check(_events(gait, 1.0 / 60.0, 0.0) == [FootstepGait.LAND] and gait.landing_db == FootstepGait.HOP_LANDING_DB, "a short hop lands lighter")
	# Leaving a ledge falls: no push-off, then a landing.
	gait.reset()
	var ledge: Array[String] = _events(gait, 0.6, 6.0, false, true, -0.08)
	_check(ledge.is_empty(), "walking off a ledge pushes off nothing: %s" % [ledge])
	_check(_events(gait, 1.0 / 60.0, 6.0) == [FootstepGait.LAND], "the fall still lands")
	# A crouched landing is heard: landings are as audible as steps.
	gait.reset()
	_events(gait, 0.5, 0.0, true, true, 0.0)
	_check(_events(gait, 1.0 / 60.0, 0.0, true) == [FootstepGait.LAND], "a crouched landing is heard")
	# A one-tick flicker (a head on a ceiling, a step down) is not a landing.
	gait.reset()
	_events(gait, 0.05, 6.0, false, true, 0.0)
	_check(not FootstepGait.LAND in _events(gait, 1.0 / 60.0, 6.0), "a 50 ms flicker is no landing")
	# Dead, seated, teleported and hitched frames make nothing.
	gait.reset()
	_check(gait.advance(1.0 / 60.0, 0.1, 0.0, false, false, false, false).is_empty(), "the dead make no steps")
	_check(gait.advance(1.0 / 60.0, 0.1, 0.0, false, false, true, true).is_empty(), "a seated rider makes no steps")
	var spawned: FootstepGait = FootstepGait.new()
	_check(spawned.advance(1.0 / 60.0, 30.0, 0.0, false, false, true, false).is_empty(), "a teleport is no stride")
	_check(spawned.advance(0.5, 3.0, 0.0, false, false, true, false).is_empty(), "a hitch frame says nothing about speed")
	_check(spawned.advance(INF, 0.1, 0.0, false, false, true, false).is_empty(), "a non-finite frame is refused")
	# A body that spawns in the air does not land on its first grounded frame.
	var dropped: FootstepGait = FootstepGait.new()
	dropped.advance(1.0 / 60.0, 0.0, 0.0, true, false, false, false)
	_check(dropped.advance(1.0 / 60.0, 0.0, 0.0, false, false, true, false).is_empty(), "respawn is no landing")


func _check_surfaces() -> void:
	var info: Dictionary = {
		"map_id": 1, "half_extent": 40.0, "geometry_version": 1,
		"solids": [
			{"min_x": 0.0, "max_x": 4.0, "min_z": 0.0, "max_z": 4.0, "top": 1.0},
			{"min_x": 10.0, "max_x": 14.0, "min_z": 0.0, "max_z": 4.0, "top": 0.5},
			{"min_x": 0.0, "max_x": 4.0, "min_z": 0.0, "max_z": 4.0, "top": 3.0},
		],
		"presentation": {"ground": "concrete", "solids": ["service_steel", "records_tile", "enamel"]},
	}
	_check(MapGeometry.validation_error(info).is_empty(), "the surface fixture is a valid map: " + MapGeometry.validation_error(info))
	FootstepSurface.configure(info)
	_check(FootstepSurface.at(Vector3(2.0, 1.0, 2.0)) == FootstepSurface.METAL, "a steel deck rings metal")
	_check(FootstepSurface.at(Vector3(12.0, 0.5, 2.0)) == FootstepSurface.TILE, "records tile clicks")
	_check(FootstepSurface.at(Vector3(2.0, 3.0, 2.0)) == FootstepSurface.TILE, "the highest top under the feet wins")
	_check(FootstepSurface.at(Vector3(20.0, 0.0, 20.0)) == FootstepSurface.CONCRETE, "open ground is the ground kit")
	_check(FootstepSurface.at(Vector3(2.0, 0.0, 2.0)) == FootstepSurface.CONCRETE, "a deck far overhead is not underfoot")
	_check(FootstepSurface.at(Vector3(2.0, 1.4, 2.0)) == FootstepSurface.METAL, "a step down is still mid-stride on the deck")
	info["presentation"]["ground"] = "service_steel"
	FootstepSurface.configure(info)
	_check(FootstepSurface.at(Vector3(20.0, 0.0, 20.0)) == FootstepSurface.METAL, "a steel venue floor rings metal")
	info.erase("presentation")
	FootstepSurface.configure(info)
	_check(FootstepSurface.at(Vector3(2.0, 1.0, 2.0)) == FootstepSurface.CONCRETE, "a map without kits is concrete")
	FootstepSurface.configure({"solids": "bad"})
	_check(FootstepSurface.at(Vector3.ZERO) == FootstepSurface.CONCRETE, "malformed MapInfo falls back to concrete")
	FootstepSurface.clear()


func _check_clips() -> void:
	for take: String in Footsteps.TAKES:
		for surface: String in FootstepSurface.SETS:
			for event: String in [FootstepGait.STEP, FootstepGait.LAND]:
				for clip: String in Footsteps.clip_names(take, event, surface):
					var stream: AudioStream = Footsteps.stream_for(clip)
					_check(stream is AudioStreamWAV, "shipped clip loads: " + clip)
					if stream is AudioStreamWAV:
						_check(not (stream as AudioStreamWAV).stereo, "placed clips are mono: " + clip)
						_check(stream.get_length() > 0.2 and stream.get_length() < 1.0, "a footfall is short: " + clip)
		_check(Footsteps.stream_for(Footsteps.clip_names(take, FootstepGait.JUMP, "")[0]) != null, "take %s has a jump" % take)
	_check(Footsteps.clip_names("a", FootstepGait.STEP, "glass")[0].begins_with("a/concrete"), "an unknown set falls back to concrete")
	_check(Footsteps.valid_take("b") == "b" and Footsteps.valid_take("c") == "a" and Footsteps.valid_take(2) == "a", "takes validate")
	# Which bodies have feet.
	_check(Footsteps.walks_for({}, "human"), "a free fighter walks")
	_check(Footsteps.walks_for({"side": "hostile", "kind": "sweeper"}, "sweeper"), "a Sweeper walks")
	_check(not Footsteps.walks_for({"side": "hostile", "kind": "notary"}, "notary"), "a Notary flies")
	_check(not Footsteps.walks_for({"side": "hostile", "kind": "crawler"}, "crawler"), "a Crawler keeps its scrabble")
	_check(not Footsteps.walks_for({"side": "companion"}, ""), "Latch keeps her own sounds")
	_check(not Footsteps.walks_for({"side": "figure"}, ""), "a staged figure is silent")
	_check(Footsteps.pitch_for("heavy_sweeper") < Footsteps.pitch_for("sweeper") and Footsteps.pitch_for("human") == 1.0, "heavier bodies land lower")
	# The airborne timeline: landings follow the drawn tick, not the newest.
	var feet: Footsteps = Footsteps.new()
	feet.observe(10, false)
	feet.observe(12, true)
	feet.observe(20, false)
	feet.observe(19, true)
	_check(not feet.airborne_at(11.5) and feet.airborne_at(12.0) and feet.airborne_at(19.9) and not feet.airborne_at(20.0), "the flag reads as of the drawn tick")
	_check(not feet.airborne_at(-1.0), "without a drawn tick the newest fact holds")
	feet.observe(-1, true)
	_check(feet.airborne_at(-1.0), "an untimed fact is the newest")
	feet.free()


func _setup_world() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_camera = Camera3D.new()
	_world.add_child(_camera)
	_camera.current = true
	# The listener looks down -Z; +X is its right ear.
	_camera.global_transform = Transform3D.IDENTITY
	_master = AudioServer.get_bus_index(&"Master")
	_recorder = AudioEffectRecord.new()
	_recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(_master, _recorder)


func _teardown() -> void:
	# Retire every playback before the mixer can hold one past exit.
	for node: Node in _world.find_children("*", "", true, false):
		if node is AudioStreamPlayer3D or node is AudioStreamPlayer:
			node.stop()
			node.set("stream", null)
	await create_timer(0.1).timeout
	for index: int in range(AudioServer.get_bus_effect_count(_master) - 1, -1, -1):
		if AudioServer.get_bus_effect(_master, index) == _recorder:
			AudioServer.remove_bus_effect(_master, index)
	if _world != null:
		_world.queue_free()
	await create_timer(0.1).timeout


## A looping 1 kHz test tone at `dbfs` peak.
static func _tone(dbfs: float) -> AudioStreamWAV:
	var rate: int = 44100
	var frames: int = rate
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	var amplitude: float = pow(10.0, dbfs / 20.0) * 32767.0
	for frame: int in range(frames):
		data.encode_s16(frame * 2, int(round(amplitude * sin(TAU * 1000.0 * float(frame) / float(rate)))))
	var clip: AudioStreamWAV = AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = rate
	clip.stereo = false
	clip.data = data
	clip.loop_mode = AudioStreamWAV.LOOP_FORWARD
	clip.loop_end = frames
	return clip


## Left and right RMS in dBFS of `seconds` of the Master mix, skipping the
## first quarter while the player starts.
func _record(seconds: float) -> Vector2:
	if not _mixer_warm:
		# Some drivers (Windows CI) start mixing only after the first frames; a
		# recording taken before then is empty. Wait until the bus carries sound.
		var deadline: int = Time.get_ticks_msec() + 5000
		while AudioServer.get_bus_peak_volume_left_db(0, 0) < -80.0 and Time.get_ticks_msec() < deadline:
			await process_frame
		_mixer_warm = true
	_recorder.set_recording_active(true)
	await create_timer(seconds).timeout
	var take: AudioStreamWAV = _recorder.get_recording()
	_recorder.set_recording_active(false)
	if take == null or take.data.size() < 8:
		return Vector2(-INF, -INF)
	var pcm: PackedByteArray = take.data
	var channels: int = 2 if take.stereo else 1
	var frames: int = pcm.size() / (2 * channels)
	var sums: Vector2 = Vector2.ZERO
	var counted: int = 0
	for frame: int in range(frames / 4, frames):
		var left: float = float(pcm.decode_s16(frame * 2 * channels)) / 32768.0
		var right: float = float(pcm.decode_s16(frame * 2 * channels + 2 * (channels - 1))) / 32768.0
		sums += Vector2(left * left, right * right)
		counted += 1
	if counted == 0:
		return Vector2(-INF, -INF)
	return Vector2(_db(sqrt(sums.x / counted)), _db(sqrt(sums.y / counted)))


static func _db(linear: float) -> float:
	return 20.0 * log(linear) / log(10.0) if linear > 0.0000001 else -INF


static func _sum_db(level: Vector2) -> float:
	if level.x == -INF and level.y == -INF:
		return -INF
	return _db(sqrt((pow(10.0, level.x / 10.0) + pow(10.0, level.y / 10.0)) / 2.0))


## A footstep player in front of the listener at each distance, playing the
## tone at the step's own source volume.
func _check_curve() -> void:
	var source: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	Footsteps.configure_player(source)
	source.bus = &"Master"
	source.stream = _tone(-12.0)
	_world.add_child(source)
	var levels: Dictionary = {}
	var rows: Array[String] = []
	for distance: float in DISTANCES:
		source.global_position = Vector3(0.0, 0.0, -distance)
		source.play()
		levels[distance] = _sum_db(await _record(0.3))
		source.stop()
		await create_timer(0.05).timeout
	var near: float = float(levels[2.0])
	for distance: float in DISTANCES:
		var level: float = float(levels[distance])
		rows.append("%5.1f m  %7.1f dB  %+6.1f dB vs 2 m" % [distance, level, level - near])
	print("test_footsteps: attenuation curve (running step source volume %.1f dB)\n  %s" % [Footsteps.STEP_DB, "\n  ".join(rows)])
	_check(near > -60.0, "a step 2 m away is heard: %.1f" % near)
	for distance: float in [20.0, 25.0, 30.0]:
		var drop: float = float(levels[distance]) - near
		_check(drop > -AUDIBLE_WINDOW_DB and float(levels[distance]) > -INF, "a run %d m away stays inside the %d dB window: %.1f" % [int(distance), int(AUDIBLE_WINDOW_DB), drop])
	for index: int in range(1, DISTANCES.size()):
		var nearer: float = float(levels[DISTANCES[index - 1]])
		var farther: float = float(levels[DISTANCES[index]])
		if DISTANCES[index] <= Footsteps.MAX_DISTANCE:
			_check(farther <= nearer + 0.5, "farther is never louder: %s" % [levels])
	for distance: float in DISTANCES:
		if distance > Footsteps.MAX_DISTANCE:
			_check(float(levels[distance]) == -INF or float(levels[distance]) < -80.0, "nothing is heard at %d m, past %d m: %.1f" % [int(distance), int(Footsteps.MAX_DISTANCE), float(levels[distance])])
	_check(Footsteps.MAX_DISTANCE <= 50.0, "steps do not carry across a whole arena")
	source.queue_free()


## The same source at 10 m on bearings round the front.
func _check_direction() -> void:
	var source: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	Footsteps.configure_player(source)
	source.bus = &"Master"
	source.stream = _tone(-12.0)
	_world.add_child(source)
	var differences: Array[float] = []
	var rows: Array[String] = []
	for bearing: float in BEARINGS:
		var angle: float = deg_to_rad(bearing)
		source.global_position = Vector3(sin(angle) * 10.0, 0.0, -cos(angle) * 10.0)
		source.play()
		var level: Vector2 = await _record(0.3)
		source.stop()
		await create_timer(0.05).timeout
		var difference: float = level.y - level.x
		differences.append(difference)
		rows.append("%+5.0f deg  L %6.1f  R %6.1f  R-L %+5.1f dB" % [bearing, level.x, level.y, difference])
	print("test_footsteps: direction at 10 m\n  %s" % "\n  ".join(rows))
	_check(absf(differences[2]) < 1.0, "straight ahead is centred: %.1f" % differences[2])
	for index: int in range(1, differences.size()):
		_check(differences[index] - differences[index - 1] >= MIN_BEARING_STEP_DB,
			"45 degrees apart sound %d dB apart or more: %s" % [int(MIN_BEARING_STEP_DB), differences])
	source.queue_free()


## The node the pawn uses: a run plays steps, a walk does not, own feet sit
## lower, and the take switch changes the clips.
func _check_playback() -> void:
	var feet: Footsteps = Footsteps.new()
	_world.add_child(feet)
	feet.global_position = Vector3(0.0, 0.0, -6.0)
	_check(feet.player.bus == &"Effects", "steps play on the Effects bus")
	var events: Array[String] = []
	for frame: int in range(60):
		var event: String = feet.present(1.0 / 60.0, 0.1, 0.0, false, false, true, false)
		if not event.is_empty():
			events.append(event)
	_check(events.size() >= 2 and feet.last_event == FootstepGait.STEP and feet.last_surface == FootstepSurface.CONCRETE, "a run plays steps: %s" % [events])
	var enemy_db: float = feet.player.volume_db
	_check(is_equal_approx(enemy_db, Footsteps.STEP_DB), "another fighter's step plays at STEP_DB")
	_check(str(feet.player.stream.resource_path).contains("/a/"), "take A plays by default")
	feet.own = true
	Footsteps.take = "b"
	for frame: int in range(60):
		feet.present(1.0 / 60.0, 0.1, 0.0, false, false, true, false)
	_check(feet.player.volume_db < enemy_db - 6.0, "own feet sit under another fighter's")
	_check(str(feet.player.stream.resource_path).contains("/b/"), "the take switch plays take B")
	Footsteps.take = Footsteps.DEFAULT_TAKE
	feet.last_event = ""
	feet.walks = false
	feet.gait.reset()
	for frame: int in range(60):
		feet.present(1.0 / 60.0, 0.1, 0.0, false, false, true, false)
	_check(feet.last_event.is_empty(), "a body without feet stays silent")
	feet.queue_free()
	await process_frame


## An overdriven tone through Master comes out under the limiter's ceiling.
func _check_limiter() -> void:
	var limiter: AudioEffect = AudioServer.get_bus_effect(_master, 0) if AudioServer.get_bus_effect_count(_master) > 0 else null
	_check(limiter is AudioEffectHardLimiter, "Master opens with the limiter")
	if not limiter is AudioEffectHardLimiter:
		return
	var ceiling: float = (limiter as AudioEffectHardLimiter).ceiling_db
	_check(ceiling <= -1.0, "the ceiling leaves true peak headroom: %.1f dB" % ceiling)
	var hot: AudioStreamPlayer = AudioStreamPlayer.new()
	hot.bus = &"Master"
	hot.stream = _tone(0.0)
	hot.volume_db = 9.0
	_world.add_child(hot)
	hot.play()
	_recorder.set_recording_active(true)
	await create_timer(0.4).timeout
	var take: AudioStreamWAV = _recorder.get_recording()
	_recorder.set_recording_active(false)
	hot.stop()
	var peak: int = 0
	if take != null:
		# Skip the limiter's first attack.
		for index: int in range(take.data.size() / 4, take.data.size() - 1, 2):
			peak = maxi(peak, absi(take.data.decode_s16(index)))
	var peak_db: float = _db(float(peak) / 32768.0)
	print("test_footsteps: +9 dB over full scale through Master peaks at %.2f dBFS (ceiling %.1f)" % [peak_db, ceiling])
	_check(peak > 0 and peak_db <= ceiling + 0.2, "the limiter holds +9 dB over full scale under its ceiling: %.2f" % peak_db)
	hot.queue_free()
	await process_frame
