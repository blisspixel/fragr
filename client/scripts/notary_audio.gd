class_name NotaryAudio
extends Node3D

## Local feedback from actor and resolved-shot facts, never a timer-owned attack.
signal notice_requested(text: String)
const DIRECTORY: String = "res://assets/audio/notary/"
const FAN_VOICES: int = 4
const CUE_VOICES: int = 4
const MAX_ACTORS: int = 512
const MAX_TRACKED: int = 32
const DISTANCE: float = 28.0
const CAPTION_TICKS: int = 20
var fans: Dictionary[String, AudioStreamPlayer3D] = {}
var fan_pool: Array[AudioStreamPlayer3D] = []
var cues: Array[AudioStreamPlayer3D] = []
var shutter_count: int = 0
var crash_count: int = 0
var last_tick: int = -1
var _next_cue: int = 0
var _seen: Dictionary[String, Dictionary] = {}
var _streams: Dictionary[String, AudioStream] = {}
var _map_id: int = -1
var _caption_ticks: Dictionary[String, int] = {}
var _last_canister: int = 0

func _ready() -> void:
	for kind: String in ["fan", "shutter", "crash"]:
		if ResourceLoader.exists(DIRECTORY + kind + ".wav"):
			_streams[kind] = load(DIRECTORY + kind + ".wav")
			if kind == "fan" and _streams[kind] is AudioStreamWAV:
				var loop: AudioStreamWAV = (_streams[kind] as AudioStreamWAV).duplicate() as AudioStreamWAV
				loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
				loop.loop_begin = 0
				loop.loop_end = loop.data.size() / 2
				_streams[kind] = loop
		else:
			push_warning("Notary audio is unavailable: " + kind)
	if ResourceLoader.exists("res://assets/audio/assessor/launch.wav"):
		_streams["canister"] = load("res://assets/audio/assessor/launch.wav")

func reset() -> void:
	for voice: AudioStreamPlayer3D in fan_pool:
		voice.stop()
	fans.clear()
	for voice: AudioStreamPlayer3D in cues:
		voice.stop()
	_seen.clear()
	last_tick = -1
	_next_cue = 0
	shutter_count = 0
	crash_count = 0
	_map_id = -1
	_caption_ticks.clear()
	_last_canister = 0

func configure_map(info: Dictionary) -> void:
	if not MapGeometry.validation_error(info).is_empty():
		reset()
		return
	var id: int = int(info["map_id"])
	if id != _map_id:
		reset()
	_map_id = id
	NotaryAnimation.configure_map(info)

func apply(snapshot: Dictionary, listener: Vector3) -> int:
	var tick: Variant = snapshot.get("tick")
	var actors: Variant = snapshot.get("players")
	if not EquipmentState.integer(tick, EquipmentState.MAX_EXACT_INTEGER) or int(tick) <= last_tick or not actors is Array:
		return 0
	var initial: bool = last_tick < 0
	last_tick = int(tick)
	var active: Dictionary[String, bool] = {}
	var nearby: bool = listener.is_finite() and _map_id >= 0 and is_inside_tree()
	var played: int = 0
	for index: int in range(mini(actors.size(), MAX_ACTORS)):
		var actor: Variant = actors[index]
		if not actor is Dictionary or not ActorState.is_union(actor) or actor["campaign"].get("kind") not in ["notary", "assessor"]:
			continue
		var id: Variant = actor.get("id")
		var position: Vector3 = JammerAudio._position(actor)
		var identity: Dictionary = actor["campaign"]
		var heavy: bool = identity["kind"] == "assessor"
		if not id is String or id.is_empty() or id.length() > 64 or active.has(id) or not position.is_finite() \
			or not EquipmentState.integer(identity.get("phase_started"), int(tick)) \
			or identity.get("phase") not in ["idle", "moving", "windup", "firing", "recovery", "hit", "dead"]:
			continue
		if not _seen.has(id) and _seen.size() >= MAX_TRACKED:
			continue
		active[id] = true
		var previous: Dictionary = _seen.get(id, {})
		if identity["phase"] != "dead" and previous.get("death_epoch", -1) >= 0:
			previous = {}
		var dead: bool = identity["phase"] == "dead"
		var epoch: int = int(identity["phase_started"])
		var crashed: bool = previous.get("crashed", false) if previous.get("death_epoch") == epoch and dead else false
		var in_range: bool = nearby and position.distance_squared_to(listener) <= DISTANCE * DISTANCE
		if dead:
			_stop_fan(id)
			var feet: Vector3 = position - Vector3(0, 1.5, 0)
			var support: float = NotaryAnimation.support(feet)
			if not crashed and not previous.is_empty() and float(previous["y"]) - 1.5 > support + 0.05 \
				and absf(feet.y - support) <= 0.04:
				crashed = true
				if in_range:
					if _cue("crash", position):
						crash_count += 1
						played += 1
					_caption("assessor_crash" if heavy else "crash")
		else:
			if in_range:
				_start_fan(id, position, identity["phase"] == "windup", heavy)
				if not previous.get("captioned", false):
					_caption("assessor_fan" if heavy else "fan")
				if heavy and identity["phase"] == "windup" and previous.get("phase") != "windup":
					_caption("assessor_countdown")
			else:
				_stop_fan(id)
		_seen[id] = {"y": position.y, "death_epoch": epoch if dead else -1, "crashed": crashed,
			"captioned": previous.get("captioned", false) or (in_range and not dead), "tick": tick, "kind": identity["kind"], "phase": identity["phase"]}
	if AssessorFacts.validation_error(snapshot).is_empty():
		for canister: Dictionary in snapshot.get("assessor_canisters", []):
			var serial: int = int(canister["id"])
			if serial <= _last_canister:
				continue
			_last_canister = serial
			var position: Vector3 = GrenadeFacts.vector(canister["position"])
			if not initial and nearby and position.distance_squared_to(listener) <= DISTANCE * DISTANCE:
				if _cue("canister", position):
					played += 1
				_caption("assessor_launch")
	# Resolved trace proves a launch even if the shooter died in this snapshot.
	var fired: Dictionary[String, bool] = {}
	var results: Variant = snapshot.get("shot_results", [])
	if results is Array and results.size() <= ShotEffects.MAX_RESULTS:
		for result: Variant in results:
			var effect: ShotEffects.Effect = ShotEffects._parse(result)
			if effect == null or not (active.has(effect.shooter) or _seen.has(effect.shooter)) or fired.has(effect.shooter):
				continue
			fired[effect.shooter] = true
			if nearby and effect.origin.distance_squared_to(listener) <= DISTANCE * DISTANCE:
				if _cue("shutter", effect.origin):
					shutter_count += 1
					played += 1
				_caption("shutter")
	for id: String in fans.keys():
		if not active.has(id):
			_stop_fan(id)
	for id: String in _seen.keys():
		if not active.has(id):
			_seen.erase(id)
	return played

func _caption(kind: String) -> void:
	if _caption_ticks.has(kind) and last_tick - _caption_ticks[kind] < CAPTION_TICKS:
		return
	_caption_ticks[kind] = last_tick
	var key: String = "WORLD_ASSESSOR_" + kind.trim_prefix("assessor_").to_upper() if kind.begins_with("assessor_") else "WORLD_M04_NOTARY_" + kind.to_upper()
	notice_requested.emit(WorldSign.localized(key))

func _start_fan(id: String, position: Vector3, windup: bool, heavy: bool = false) -> bool:
	if not _streams.has("fan"):
		return false
	if not fans.has(id):
		if fans.size() >= FAN_VOICES:
			return false
		var voice: AudioStreamPlayer3D = null
		for candidate: AudioStreamPlayer3D in fan_pool:
			if candidate not in fans.values():
				voice = candidate
				break
		if voice == null:
			voice = _voice("NotaryFan", -20.0)
			voice.stream = _streams["fan"]
			add_child(voice)
			fan_pool.append(voice)
		fans[id] = voice
		voice.play()
	var fan: AudioStreamPlayer3D = fans[id]
	fan.global_position = position
	fan.pitch_scale = (0.81 if windup else 0.72) if heavy else (1.06 if windup else 1.0)
	return true

func _stop_fan(id: String) -> void:
	if fans.has(id):
		var voice: AudioStreamPlayer3D = fans[id]
		voice.stop()
		fans.erase(id)

func _cue(kind: String, position: Vector3) -> bool:
	if not _streams.has(kind):
		return false
	var voice: AudioStreamPlayer3D
	if cues.size() < CUE_VOICES:
		voice = _voice("NotaryCue", -5.0)
		add_child(voice)
		cues.append(voice)
	else:
		voice = cues[_next_cue]
		_next_cue = (_next_cue + 1) % CUE_VOICES
	voice.stop()
	voice.stream = _streams[kind]
	voice.global_position = position
	voice.play()
	return true

func _voice(label: String, volume: float) -> AudioStreamPlayer3D:
	var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	voice.name = label
	voice.bus = &"Effects"
	voice.volume_db = volume
	voice.unit_size = 7.0
	voice.max_distance = DISTANCE
	voice.max_polyphony = 1
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	return voice
