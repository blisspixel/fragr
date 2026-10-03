class_name RangedSweeperAudio
extends Node3D

## One tell per server-confirmed marksman windup, played where the Ranged
## Sweeper stands. Presentation only; the windup itself is the server's fact.
## The cue is paced to the actual windup and stops when the windup ends, so a
## broken sightline silences it and the held tone never runs over the shot.
const VOICES: int = 4
const MAX_ACTORS: int = 512
## Audible across a crater cut, inside the marksman's own sight range.
const DISTANCE: float = 95.0
const MAX_REMEMBERED: int = 64
## The cue may be sped up or slowed this far to end with the windup.
const PITCH_MIN: float = 0.8
const PITCH_MAX: float = 1.25
var voices: Array[AudioStreamPlayer3D] = []
var cue_count: int = 0
var last_snapshot_tick: int = -1
var _next_voice: int = 0
var _stream: AudioStream = null
## Windup start tick already cued, per marksman id.
var _cued: Dictionary[String, int] = {}
## The voice currently sounding each marksman's tell.
var _sounding: Dictionary[String, AudioStreamPlayer3D] = {}


func _ready() -> void:
	if ResourceLoader.exists(L07Assets.RANGED_SWEEPER_TELL_SOUND):
		_stream = load(L07Assets.RANGED_SWEEPER_TELL_SOUND)
	else:
		push_warning("Ranged Sweeper tell sound is unavailable")


func reset() -> void:
	for voice: AudioStreamPlayer3D in voices:
		voice.stop()
	_next_voice = 0
	last_snapshot_tick = -1
	cue_count = 0
	_cued.clear()
	_sounding.clear()


## Returns the number of new tell cues started by this snapshot.
func apply(snapshot: Dictionary, listener_position: Vector3) -> int:
	var tick: Variant = snapshot.get("tick")
	var actors: Variant = snapshot.get("players")
	if not EquipmentState.integer(tick, EquipmentState.MAX_EXACT_INTEGER) \
			or int(tick) <= last_snapshot_tick or not actors is Array:
		return 0
	last_snapshot_tick = int(tick)
	var played: int = 0
	for index: int in range(mini(actors.size(), MAX_ACTORS)):
		var actor: Variant = actors[index]
		if not actor is Dictionary or not ActorState.is_union(actor) \
				or actor["campaign"].get("kind") != "ranged_sweeper":
			continue
		var id: Variant = actor.get("id")
		if not id is String or id.is_empty() or id.length() > 64:
			continue
		if actor["campaign"].get("phase") != "windup":
			_silence(id)
			continue
		var started: Variant = actor["campaign"].get("phase_started")
		var ends: Variant = actor["campaign"].get("phase_ends")
		if not EquipmentState.integer(started, EquipmentState.MAX_EXACT_INTEGER) \
				or not EquipmentState.integer(ends, EquipmentState.MAX_EXACT_INTEGER) \
				or _cued.get(id, -1) == int(started):
			continue
		if _cued.size() >= MAX_REMEMBERED and not _cued.has(id):
			_cued.clear()
		_cued[id] = int(started)
		var position: Vector3 = JammerAudio._position(actor)
		if _stream == null or not is_inside_tree() or not listener_position.is_finite() \
				or not position.is_finite() \
				or position.distance_squared_to(listener_position) > DISTANCE * DISTANCE:
			continue
		var voice: AudioStreamPlayer3D = _voice()
		voice.stop()
		for other: String in _sounding.keys():
			if _sounding[other] == voice:
				_sounding.erase(other)
		voice.global_position = position
		voice.pitch_scale = windup_pitch(_stream.get_length(),
			float(int(ends) - int(started)) * MoveStep.DT_LIVE)
		voice.play()
		_sounding[id] = voice
		cue_count += 1
		played += 1
	return played


## Ends a marksman's tell when its windup is over, fired or cancelled.
func _silence(id: String) -> void:
	var voice: AudioStreamPlayer3D = _sounding.get(id)
	if voice != null and voice.playing:
		voice.stop()
	_sounding.erase(id)


## Pace the tell to the actual windup within a recognisable range.
static func windup_pitch(cue_seconds: float, windup_seconds: float) -> float:
	if cue_seconds <= 0.0 or windup_seconds <= 0.0:
		return 1.0
	return clampf(cue_seconds / windup_seconds, PITCH_MIN, PITCH_MAX)


func _voice() -> AudioStreamPlayer3D:
	if voices.size() < VOICES:
		var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice.name = "MarksmanGlint%s" % voices.size()
		voice.stream = _stream
		voice.bus = &"Effects"
		voice.volume_db = 0.0
		voice.unit_size = 18.0
		voice.max_distance = DISTANCE
		voice.max_polyphony = 1
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(voice)
		voices.append(voice)
		return voice
	var voice: AudioStreamPlayer3D = voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	return voice
