extends SceneTree

var _failures: int = 0
var _feedback: IncomingCombatFeedback
var _hud: CanvasLayer
const EYE: Vector3 = Vector3(0.0, 1.5, 0.0)


func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_incoming_combat_feedback: " + message)


static func _map(solids: Array = []) -> Dictionary:
	return {"map_id": 1, "geometry_version": 2, "half_extent": 24.0, "solids": solids}


static func _ray(origin: Vector3, end: Vector3, shooter: String = "enemy", kind: String = "range", weapon: String = "flechette") -> Dictionary:
	var impact: Dictionary = {"kind": kind}
	if kind != "range":
		impact["normal"] = [0.0, 0.0, 1.0]
	return {"shooter_id": shooter, "hit": kind == "fighter", "target_id": "me" if kind == "fighter" else null,
		"damage": 10 if kind == "fighter" else 0, "trace": {"weapon": weapon,
		"origin": [origin.x, origin.y, origin.z], "end": [end.x, end.y, end.z], "impact": impact}}


func _ingest(tick: int, results: Variant, owner: String = "me", fp: bool = true, alive: bool = true) -> void:
	_feedback.ingest(tick, results, owner, Transform3D(Basis.IDENTITY, EYE), fp, alive)


func _run() -> void:
	_hud = CanvasLayer.new()
	root.add_child(_hud)
	_feedback = IncomingCombatFeedback.new()
	root.add_child(_feedback)
	_feedback.setup(_hud)
	_feedback.setup(_hud)
	_check(_hud.get_child_count() == 1, "setup owns one pointer-free overlay")
	_check(_feedback.indicator.mouse_filter == Control.MOUSE_FILTER_IGNORE, "overlay cannot intercept controls")
	_geometry()
	_bearings()
	_audio_sources()
	_boundaries_and_damage()
	_cadence_and_pool()
	_cover()
	_feedback.free()
	await process_frame
	_check(_hud.get_child_count() == 0, "teardown releases sibling overlay")
	_hud.free()
	if _failures == 0:
		print("test_incoming_combat_feedback: PASS geometry, bearings, committed damage, ownership, cover, cadence, pool, mono waveform, fade and teardown")
	quit(0 if _failures == 0 else 1)


func _geometry() -> void:
	var start: Vector3 = Vector3(-10.0, 1.5, 1.0)
	var end: Vector3 = Vector3(10.0, 1.5, 1.0)
	_check(IncomingCombatFeedback.closest_pass(start, end, EYE).is_equal_approx(Vector3(0.0, 1.5, 1.0)), "finite closest approach")
	_check(IncomingCombatFeedback.closest_pass(start + Vector3.BACK, end + Vector3.BACK, EYE).is_finite(), "2 m radius includes boundary")
	_check(not IncomingCombatFeedback.closest_pass(start + Vector3.BACK * 1.001, end + Vector3.BACK * 1.001, EYE).is_finite(), "outside radius rejected")
	_check(not IncomingCombatFeedback.closest_pass(start, Vector3(-0.1, 1.5, 1.0), EYE).is_finite(), "never extends past impact")
	_check(not IncomingCombatFeedback.closest_pass(Vector3(0.1, 1.5, 1.0), end, EYE).is_finite(), "ray travels away")
	_check(not IncomingCombatFeedback.closest_pass(Vector3(-1.0, 1.5, 1.0), end, EYE).is_finite(), "muzzle chatter rejected")
	_check(not IncomingCombatFeedback.closest_pass(EYE, EYE, EYE).is_finite(), "zero-length ray rejected")
	_check(not IncomingCombatFeedback.closest_pass(Vector3.INF, end, EYE).is_finite(), "nonfinite ray rejected")
	_check(IncomingCombatFeedback.closest_pass(start + Vector3.UP, end + Vector3.UP, EYE).is_finite(), "radius is three dimensional")
	_check(not IncomingCombatFeedback.closest_pass(start + Vector3.UP * 2.0, end + Vector3.UP * 2.0, EYE).is_finite(), "above-radius ray rejected")


func _bearings() -> void:
	for turn: float in [0.0, 0.7, PI, -1.5]:
		for pitch: float in [0.0, -0.9, 1.2]:
			var basis: Basis = Basis(Vector3.UP, turn) * Basis(Vector3.RIGHT, pitch)
			for bearing: float in [0.0, PI * 0.25, PI * 0.5, PI * 0.75, PI, -PI * 0.25, -PI * 0.5]:
				var incoming: Vector3 = Basis(Vector3.UP, turn) * Vector3(sin(bearing), 0.4, -cos(bearing))
				var measured: float = DamageBearing.angle(incoming, basis)
				_check(absf(wrapf(measured - bearing, -PI, PI)) < 0.0001, "cardinal/diagonal bearing under yaw and pitch")
	_check(is_nan(DamageBearing.angle(Vector3.UP, Basis.IDENTITY)), "vertical source cannot invent azimuth")
	var indicator: DamageBearing = _feedback.indicator
	indicator.hit(Vector3.LEFT)
	indicator.advance(0.2, Basis(Vector3.UP, PI * 0.5))
	_check(absf(DamageBearing.angle(indicator.directions[0], indicator.view_basis)) < 0.0001, "old resolved bearing follows current view turn")
	indicator.advance(DamageBearing.LIFETIME, Basis.IDENTITY)
	_check(not indicator.visible and indicator.directions.is_empty(), "indicator expires")
	for index: int in range(10):
		indicator.hit(Vector3.RIGHT)
	_check(indicator.directions.size() == DamageBearing.MAX_HITS, "overlay bounded during crossfire")
	indicator.reset()


func _audio_sources() -> void:
	var hashes: Dictionary[String, bool] = {}
	for family: String in IncomingCombatFeedback.STREAMS:
		var stream: AudioStreamWAV = IncomingCombatFeedback.STREAMS[family]
		_check(stream.mix_rate == 48000 and not stream.stereo and stream.format == AudioStreamWAV.FORMAT_16_BITS \
			and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "48 kHz mono PCM one-shot " + family)
		_check(stream.get_length() >= 0.1 and stream.get_length() <= 0.2, "short candidate " + family)
		var data: PackedByteArray = stream.data
		var frames: int = data.size() / 2
		var energy: float = 0.0
		var mean: float = 0.0
		var peak: float = 0.0
		var tail_energy: float = 0.0
		for frame: int in range(frames):
			var sample: float = float(data.decode_s16(frame * 2)) / 32767.0
			energy += sample * sample
			mean += sample
			peak = maxf(peak, absf(sample))
			if frame >= frames * 9 / 10:
				tail_energy += sample * sample
		var rms: float = sqrt(energy / frames)
		_check(rms > 0.015 and rms < 0.2 and peak < 0.8 and absf(mean / frames) < 0.01, "audible bounded waveform without clipping or DC " + family)
		_check(data.decode_s16(0) == 0 and data.decode_s16(data.size() - 2) == 0 \
			and tail_energy < energy * 0.01, "tapered silence endpoints " + family)
		var hash_context: HashingContext = HashingContext.new()
		hash_context.start(HashingContext.HASH_SHA256)
		hash_context.update(data)
		var hash: String = hash_context.finish().hex_encode()
		_check(not hashes.has(hash), "families have distinct source data")
		hashes[hash] = true


func _boundaries_and_damage() -> void:
	_check(_feedback.configure_map(_map()), "valid MapInfo accepted")
	var hit: Dictionary = _ray(EYE + Vector3.LEFT * 8.0, EYE, "dead-shooter", "fighter")
	_ingest(1, [hit])
	_check(_feedback.damage_count == 1 and _feedback.cue_count == 0, "resolved dead-shooter hit gets bearing, not duplicate pass-by")
	_check(_feedback.indicator.directions[0].is_equal_approx(Vector3.LEFT), "resolved source retained without pawn lookup")
	_ingest(1, [hit])
	_check(_feedback.damage_count == 1, "repeated snapshot cannot repeat damage")
	var no_damage: Dictionary = hit.duplicate(true)
	no_damage["damage"] = 0
	_ingest(2, [no_damage])
	_check(_feedback.damage_count == 1, "friendly or nonlanding zero damage has no bearing")
	var other: Dictionary = hit.duplicate(true)
	other["target_id"] = "other"
	_ingest(3, [other])
	_check(_feedback.damage_count == 1, "other target has no damage cue")
	var untraced: Dictionary = hit.duplicate(true)
	untraced.erase("trace")
	_ingest(4, [untraced])
	_check(_feedback.damage_count == 1, "no inferred explosion or HP direction")
	var malformed: Dictionary = hit.duplicate(true)
	malformed["trace"]["origin"] = [NAN, 0.0, 0.0]
	_ingest(5, [malformed])
	_check(_feedback.damage_count == 1, "malformed trace rejected")
	malformed = hit.duplicate(true)
	malformed["damage"] = true
	_ingest(6, [malformed])
	_check(_feedback.damage_count == 1, "boolean damage rejected")
	_ingest(7, [hit, hit, hit])
	_check(_feedback.damage_count == 2, "scatter result aggregation one bearing per shooter per tick")
	_ingest(8, [hit], "me", true, false)
	_check(_feedback.damage_count == 3, "last committed damage before death is retained")
	_ingest(9, [hit], "me", false)
	_check(_feedback.damage_count == 0 and not _feedback.indicator.visible, "spectator/invalid FP view clears local cue")
	_ingest(10, [hit], "new-owner")
	_check(_feedback.damage_count == 0, "new owner cannot inherit old damage")
	_ingest(-1, [hit])
	_ingest(1, {})
	var flood: Array = []
	flood.resize(ShotEffects.MAX_RESULTS + 1)
	_ingest(1, flood)
	_check(_feedback.last_tick == -1, "bad ticks, collections and oversized snapshots rejected")
	_feedback.ingest(2, [hit], "me", Transform3D(Basis.IDENTITY, Vector3.INF), true)
	_check(_feedback.last_tick == -1, "nonfinite listener invalidates local view")
	malformed = hit.duplicate(true)
	malformed["shooter_id"] = ""
	_ingest(3, [malformed])
	_check(_feedback.damage_count == 0, "missing source identity rejected")
	_check(not _feedback.configure_map({"map_id": 1}), "invalid MapInfo fails closed")
	_ingest(20, [hit])
	_check(_feedback.damage_count == 0, "invalid map cannot supply cover or bearings")


func _cadence_and_pool() -> void:
	_feedback.configure_map(_map())
	var near: Dictionary = _ray(Vector3(-10.0, 1.5, 1.0), Vector3(10.0, 1.5, 1.0))
	_ingest(1, [near, near, near])
	_check(_feedback.cue_count == 1 and _feedback.voices.size() == 1, "one cue per shooter/pellets")
	_check(_feedback.last_cue_positions[0].is_equal_approx(Vector3(0.0, 1.5, 1.0)), "cue positioned at actual closest point")
	_ingest(2, [near])
	_ingest(3, [near])
	_check(_feedback.cue_count == 1, "global cadence blocks noisy repeated fire")
	_ingest(4, [near])
	_check(_feedback.cue_count == 2, "cadence reopens at exact tick")
	var scatter: Dictionary = near.duplicate(true)
	scatter["trace"]["weapon"] = "scatter"
	scatter["trace"]["pellets"] = [
		{"end": [10.0, 1.5, 1.0], "impact": {"kind": "range"}},
		{"end": [10.0, 1.5, 1.5], "impact": {"kind": "range"}}]
	_ingest(7, [scatter])
	_check(_feedback.cue_count == 3, "real pellet array shares one cue")
	_check(_feedback.voices.back().stream == IncomingCombatFeedback.STREAMS["pellet"], "pellet family source selected")
	for tick: int in range(10, 46, 3):
		var shots: Array[Dictionary] = []
		for shooter: int in range(8):
			var item: Dictionary = near.duplicate(true)
			item["shooter_id"] = "enemy-" + str(shooter)
			shots.append(item)
		var before: int = _feedback.cue_count
		_ingest(tick, shots)
		_check(_feedback.cue_count - before == IncomingCombatFeedback.MAX_CUES, "crossfire per-tick budget")
	_check(_feedback.voices.size() == IncomingCombatFeedback.VOICES, "voice pool never grows past bound")
	for voice: AudioStreamPlayer3D in _feedback.voices:
		_check(voice.bus == "Effects" and voice.max_polyphony == 1 and voice.max_distance <= 4.0, "spatial local Effects voice config")
	_ingest(49, [near], "new-owner")
	_check(_feedback.cue_count == 1, "ownership replacement clears old cue accounting")
	_check(_feedback.indicator.directions.is_empty(), "new owner has no inherited bearing")
	_feedback.reset()
	_ingest(50, [near], "me", true, false)
	_check(_feedback.cue_count == 0, "dead local view cannot start near misses")
	_ingest(51, [_ray(Vector3(-10.0, 1.5, 1.0), Vector3(10.0, 1.5, 1.0), "me")])
	_check(_feedback.cue_count == 0, "own shots never incoming")
	_feedback.reset()
	for voice: AudioStreamPlayer3D in _feedback.voices:
		_check(not voice.playing, "reset stops every sounding voice")
	_check(_feedback.last_tick == -1 and _feedback.last_cue_positions.is_empty(), "reset clears snapshot/source memory")


func _cover() -> void:
	var wall: Dictionary = {"min_x": -2.0, "max_x": 2.0, "min_z": 0.3, "max_z": 0.6, "bottom": 0.0, "top": 3.0}
	var near: Dictionary = _ray(Vector3(-10.0, 1.5, 1.0), Vector3(10.0, 1.5, 1.0))
	_feedback.configure_map(_map([wall]))
	_ingest(1, [near])
	_check(_feedback.cue_count == 0, "close trace behind wall cannot disclose pass-by")
	wall["bottom"] = 2.0
	_feedback.configure_map(_map([wall]))
	_ingest(1, [near])
	_check(_feedback.cue_count == 1, "raised slab keeps actual open gap")
	wall["bottom"] = 1.0
	_feedback.configure_map(_map([wall]))
	_ingest(1, [near])
	_check(_feedback.cue_count == 0, "raised slab blocks connector at listener height")
	var blocked: Array[Dictionary] = []
	for index: int in range(IncomingCombatFeedback.MAX_VISIBILITY_CHECKS):
		var item: Dictionary = near.duplicate(true)
		item["shooter_id"] = "blocked-" + str(index)
		blocked.append(item)
	blocked.append(_ray(Vector3(-10.0, 1.5, -1.0), Vector3(10.0, 1.5, -1.0), "clear"))
	blocked.append(_ray(EYE + Vector3.LEFT * 8.0, EYE, "actual-hit", "fighter"))
	_ingest(2, blocked)
	_check(_feedback.cue_count == 0 and _feedback.damage_count == 1, "bounded cover work cannot suppress actual damage handling")
	wall["top"] = "bad"
	_check(not _feedback.configure_map(_map([wall])), "malformed wall invalidates cached map")
	_ingest(1, [near])
	_check(_feedback.cue_count == 0, "invalid replacement clears previous clear-gap state")
