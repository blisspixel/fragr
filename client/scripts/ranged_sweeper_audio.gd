class_name RangedSweeperAudio
extends Node3D

## One glint cue per server-confirmed marksman windup, played where the Ranged
## Sweeper stands. Presentation only; the windup itself is the server's fact.
const VOICES: int = 4
const MAX_ACTORS: int = 512
## Audible across a crater cut, inside the marksman's own sight range.
const DISTANCE: float = 95.0
const MAX_REMEMBERED: int = 64
var voices: Array[AudioStreamPlayer3D] = []
var cue_count: int = 0
var last_snapshot_tick: int = -1
var _next_voice: int = 0
var _stream: AudioStream = null
## Windup start tick already cued, per marksman id.
var _cued: Dictionary[String, int] = {}


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


## Returns the number of new glint cues started by this snapshot.
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
				or actor["campaign"].get("kind") != "ranged_sweeper" \
				or actor["campaign"].get("phase") != "windup":
			continue
		var id: Variant = actor.get("id")
		var started: Variant = actor["campaign"].get("phase_started")
		if not id is String or id.is_empty() or id.length() > 64 \
				or not EquipmentState.integer(started, EquipmentState.MAX_EXACT_INTEGER) \
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
		voice.global_position = position
		voice.play()
		cue_count += 1
		played += 1
	return played


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
