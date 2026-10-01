class_name JammerAudio
extends Node3D

## Presentation of confirmed launches, never a prediction of the attack.
const SOUND_PATH: String = "res://assets/audio/jammer/launch.wav"
const VOICES: int = 4
const MAX_ACTORS: int = 512
const DISTANCE: float = 24.0
const MAX_COORDINATE: float = 8192.0
var voices: Array[AudioStreamPlayer3D] = []
var launch_count: int = 0
var last_snapshot_tick: int = -1
var _next_voice: int = 0
var _stream: AudioStream = null


func _ready() -> void:
	if ResourceLoader.exists(SOUND_PATH):
		_stream = load(SOUND_PATH)
	else:
		push_warning("Jammer launch sound is unavailable")


func reset() -> void:
	for voice: AudioStreamPlayer3D in voices:
		voice.stop()
	_next_voice = 0
	last_snapshot_tick = -1
	launch_count = 0


func apply(snapshot: Dictionary, listener_position: Vector3) -> int:
	var tick: Variant = snapshot.get("tick")
	var actors: Variant = snapshot.get("players")
	if not EquipmentState.integer(tick, EquipmentState.MAX_EXACT_INTEGER) \
			or int(tick) <= last_snapshot_tick or not actors is Array:
		return 0
	last_snapshot_tick = int(tick)
	if not listener_position.is_finite() or _stream == null or not is_inside_tree():
		return 0
	var seen: Dictionary[String, bool] = {}
	var played: int = 0
	for index: int in range(mini(actors.size(), MAX_ACTORS)):
		var actor: Variant = actors[index]
		if not actor is Dictionary or not ActorState.is_union(actor) \
				or actor["campaign"].get("kind") != "jammer" \
				or typeof(actor.get("just_fired")) != TYPE_BOOL or not actor["just_fired"]:
			continue
		var id: Variant = actor.get("id")
		if not id is String or id.is_empty() or id.length() > 64 or seen.has(id):
			continue
		seen[id] = true
		var position: Vector3 = _position(actor)
		if not position.is_finite() or position.distance_squared_to(listener_position) > DISTANCE * DISTANCE:
			continue
		var voice: AudioStreamPlayer3D = _voice()
		voice.stop()
		voice.global_position = position
		voice.play()
		launch_count += 1
		played += 1
	return played


func _voice() -> AudioStreamPlayer3D:
	if voices.size() < VOICES:
		var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice.name = "JammerLaunch%s" % voices.size()
		voice.stream = _stream
		voice.bus = &"Effects"
		voice.volume_db = -3.0
		voice.unit_size = 6.0
		voice.max_distance = DISTANCE
		voice.max_polyphony = 1
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(voice)
		voices.append(voice)
		return voice
	var voice: AudioStreamPlayer3D = voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	return voice


static func _position(actor: Dictionary) -> Vector3:
	var coordinates: Array[float] = []
	for axis: String in ["x", "y", "z"]:
		var value: Variant = actor.get(axis)
		if not (value is int or value is float) or not is_finite(float(value)) \
				or absf(float(value)) > MAX_COORDINATE:
			return Vector3.INF
		coordinates.append(float(value))
	return Vector3(coordinates[0], coordinates[1], coordinates[2])
