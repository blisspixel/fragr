class_name WeaponHandlingAudio
extends Node3D

## Spatial presentation of accepted server actions. No loadout, animation or
## local trigger can invent a reload or dry click for another fighter.
const RELOAD_START_SOUND_PATH: String = "res://assets/audio/sniper/scope_out.wav"
const DRY_FIRE_SOUND_PATH: String = "res://assets/audio/dry_fire.wav"
const DISTANCE: float = 24.0
const HANDLING_HEIGHT: float = 1.2
const VOICES: int = 8
const MAX_REMEMBERED: int = 512
const RELOAD_DB: float = -9.0
const DRY_DB: float = -12.0

var voices: Array[AudioStreamPlayer3D] = []
var reload_count: int = 0
var dry_count: int = 0
var _next_voice: int = 0
var _streams: Dictionary[String, AudioStream] = {}
var _latest: Dictionary[String, int] = {}
## Evicted identities cannot replay old facts after the bounded cache fills.
var _retired_tick: int = -1


func _ready() -> void:
	for kind: String in ["reload_start", "dry_fire"]:
		var path: String = RELOAD_START_SOUND_PATH if kind == "reload_start" else DRY_FIRE_SOUND_PATH
		if ResourceLoader.exists(path):
			_streams[kind] = load(path) as AudioStream


## Called on map replacement and disconnect, before accepting a new stream.
func clear() -> void:
	for voice: AudioStreamPlayer3D in voices:
		voice.stop()
	_next_voice = 0
	_latest.clear()
	_retired_tick = -1
	reload_count = 0
	dry_count = 0


## True only when a new audible fact starts a voice. Consume valid facts even
## without a listener or outside range; walking closer never replays them.
func present(event: Dictionary, listener: Vector3) -> bool:
	if event.size() != 6 or event.get("type") != "event" or event.get("event") != "weapon_handling" \
			or not MissionState._uuid(event.get("player_id")) \
			or not EquipmentState.integer(event.get("tick"), EquipmentState.MAX_EXACT_INTEGER) \
			or event.get("kind") not in ["reload_start", "dry_fire"]:
		return false
	var coordinates: Variant = event.get("position")
	if not coordinates is Array or coordinates.size() != 3:
		return false
	for coordinate: Variant in coordinates:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) \
				or absf(float(coordinate)) > JammerAudio.MAX_COORDINATE:
			return false
	var kind: String = event["kind"]
	var key: String = (event["player_id"] as String).to_lower() + "/" + kind
	var tick: int = int(event["tick"])
	if tick <= _retired_tick or tick <= _latest.get(key, -1):
		return false
	if not _latest.has(key) and _latest.size() >= MAX_REMEMBERED:
		var oldest: String = _latest.keys()[0]
		for remembered: String in _latest:
			if _latest[remembered] < _latest[oldest]:
				oldest = remembered
		_retired_tick = maxi(_retired_tick, _latest[oldest])
		_latest.erase(oldest)
		if tick <= _retired_tick:
			return false
	_latest[key] = tick
	var feet: Vector3 = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
	if not is_inside_tree() or not listener.is_finite() or not _streams.has(kind) \
			or feet.distance_squared_to(listener) > DISTANCE * DISTANCE:
		return false
	var voice: AudioStreamPlayer3D = _voice()
	voice.stop()
	voice.stream = _streams[kind]
	voice.volume_db = RELOAD_DB if kind == "reload_start" else DRY_DB
	voice.global_position = feet + Vector3.UP * HANDLING_HEIGHT
	voice.play()
	if kind == "reload_start":
		reload_count += 1
	else:
		dry_count += 1
	return true


func _voice() -> AudioStreamPlayer3D:
	if voices.size() < VOICES:
		var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice.name = "WeaponHandling%d" % voices.size()
		Footsteps.configure_player(voice)
		voice.bus = &"Effects"
		voice.max_distance = DISTANCE
		voice.max_polyphony = 1
		add_child(voice)
		voices.append(voice)
		return voice
	var voice: AudioStreamPlayer3D = voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	return voice
