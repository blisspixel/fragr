class_name IncomingCombatFeedback
extends Node3D

## Presentation from committed rays only. No damage or shooter tracking here.
const RADIUS: float = 2.0
const MIN_TRAVEL: float = 2.0
const CADENCE_TICKS: int = 3
const MAX_CUES: int = 2
const MAX_VISIBILITY_CHECKS: int = 32
const VOICES: int = 4
const STREAMS: Dictionary[String, AudioStreamWAV] = {
	"pellet": preload("res://assets/audio/near_miss/pellet.wav"),
	"rifle": preload("res://assets/audio/near_miss/rifle.wav"),
	"rail": preload("res://assets/audio/near_miss/rail.wav"),
}
var indicator: DamageBearing = null
var voices: Array[AudioStreamPlayer3D] = []
var last_tick: int = -1
var cue_count: int = 0
var damage_count: int = 0
var last_cue_positions: Array[Vector3] = []
var _next_voice: int = 0
var _next_cue_tick: int = 0
var _owner: String = ""
var _solids: Array = []
var _map_valid: bool = false
var _listener: Transform3D = Transform3D.IDENTITY


func setup(hud: CanvasLayer) -> void:
	if is_instance_valid(indicator):
		return
	indicator = DamageBearing.new()
	indicator.name = "DamageBearing"
	hud.add_child(indicator)


func configure_map(info: Dictionary) -> bool:
	reset()
	_map_valid = MapGeometry.validation_error(info).is_empty()
	_solids = info["solids"].duplicate(true) if _map_valid else []
	return _map_valid


func reset() -> void:
	for voice: AudioStreamPlayer3D in voices:
		voice.stop()
	if is_instance_valid(indicator):
		indicator.reset()
	_owner = ""
	last_tick = -1
	_next_cue_tick = 0
	_next_voice = 0
	cue_count = 0
	damage_count = 0
	last_cue_positions.clear()


func _exit_tree() -> void:
	reset()
	if is_instance_valid(indicator):
		indicator.queue_free()
	indicator = null


## The manager supplies its actual local-human first-person view, including
## the final committed hit before death. Dead views never start pass-by cues.
func ingest(tick: int, results: Variant, owner_id: String, listener: Transform3D,
		first_person: bool, alive: bool = true) -> void:
	if not first_person or owner_id.is_empty() or owner_id.length() > 64 \
			or not listener.is_finite():
		reset()
		return
	if _owner != owner_id:
		reset()
		_owner = owner_id
	_listener = listener
	if not _map_valid or tick < 0 or tick > EquipmentState.MAX_EXACT_INTEGER \
			or tick <= last_tick or not results is Array or results.size() > ShotEffects.MAX_RESULTS:
		return
	last_tick = tick
	last_cue_positions.clear()
	var sounded: Dictionary[String, bool] = {}
	var hurt: Dictionary[String, bool] = {}
	var visibility_checks: int = 0
	var may_cue: bool = alive and tick >= _next_cue_tick
	for result: Variant in results:
		if not result is Dictionary or not _identity(result.get("shooter_id")) \
				or result["shooter_id"] == owner_id:
			continue
		var effects: Array[ShotEffects.Effect] = ShotEffects._parse_all(result)
		if effects.is_empty():
			continue
		var shooter: String = result["shooter_id"]
		if _damaged(result, owner_id, effects):
			if not hurt.has(shooter):
				hurt[shooter] = true
				if is_instance_valid(indicator):
					indicator.hit(effects[0].origin - listener.origin)
					damage_count += 1
			continue
		if not may_cue or sounded.has(shooter) or sounded.size() >= MAX_CUES:
			continue
		for effect: ShotEffects.Effect in effects:
			if effect.weapon in EquipmentState.MELEE:
				continue
			var point: Vector3 = closest_pass(effect.origin, effect.end, listener.origin)
			if not point.is_finite():
				continue
			if visibility_checks >= MAX_VISIBILITY_CHECKS:
				break
			visibility_checks += 1
			if not AimAssist.line_of_sight(listener.origin, point, _solids):
				continue
			if _play(effect.weapon, point):
				sounded[shooter] = true
				_next_cue_tick = tick + CADENCE_TICKS
			break


static func _identity(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 64


static func _damaged(result: Dictionary, owner_id: String, effects: Array[ShotEffects.Effect]) -> bool:
	if result.get("hit") != true or not result.get("hit") is bool \
			or result.get("target_id") != owner_id \
			or not EquipmentState.integer(result.get("damage"), EquipmentState.MAX_EXACT_INTEGER) \
			or int(result["damage"]) <= 0:
		return false
	for effect: ShotEffects.Effect in effects:
		if effect.kind == "fighter":
			return true
	return false


## Reject muzzle chatter, rays travelling away, and a stopped shot's extension.
static func closest_pass(origin: Vector3, end: Vector3, listener: Vector3) -> Vector3:
	if not origin.is_finite() or not end.is_finite() or not listener.is_finite():
		return Vector3.INF
	var segment: Vector3 = end - origin
	var squared: float = segment.length_squared()
	if squared < MIN_TRAVEL * MIN_TRAVEL:
		return Vector3.INF
	var fraction: float = (listener - origin).dot(segment) / squared
	if fraction <= 0.0 or fraction >= 1.0 or fraction * sqrt(squared) < MIN_TRAVEL:
		return Vector3.INF
	var point: Vector3 = origin + segment * fraction
	return point if point.distance_squared_to(listener) <= RADIUS * RADIUS else Vector3.INF


func _play(weapon: String, point: Vector3) -> bool:
	if not is_inside_tree():
		return false
	if voices.size() < VOICES:
		var created: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		created.bus = "Effects"
		created.unit_size = 1.0
		created.max_distance = 4.0
		created.max_db = -8.0
		created.volume_db = -8.0
		created.attenuation_filter_cutoff_hz = 20500.0
		created.max_polyphony = 1
		add_child(created)
		voices.append(created)
	var voice: AudioStreamPlayer3D = voices[_next_voice % voices.size()]
	_next_voice += 1
	voice.stop()
	var family: String = "rail" if weapon == "rail" else ("pellet" if weapon == "scatter" else "rifle")
	voice.stream = STREAMS[family]
	voice.global_position = point
	voice.play()
	cue_count += 1
	last_cue_positions.append(point)
	return true


func _process(delta: float) -> void:
	if not is_instance_valid(indicator):
		return
	var active_camera: Camera3D = get_viewport().get_camera_3d()
	var basis: Basis = active_camera.global_basis if is_instance_valid(active_camera) else _listener.basis
	indicator.advance(delta, basis)
