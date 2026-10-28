extends Node
class_name HitChime

## The shooter's hit confirm: a sharp metallic tick whose pitch climbs with the
## damage the server reported, a brighter ping for a headshot and a heavier
## clang for the shot that put a fighter down. Presentation only: the tier
## comes from `shot_results` facts (`damage`, `head`, `killed`), never from a
## client judgement. Plays on the Effects bus, so the Effects volume and mute
## apply. Automatic fire does not machine-gun it: a confirm inside the gap
## after the last one is dropped unless it outranks it, and a kill always
## sounds on its own player so it never cuts a hit off.

enum Tier { BLOCKED, BODY, HEAD, KILL }

const BODY_PATH: String = "res://assets/audio/hit_chime/body.wav"
const HEAD_PATH: String = "res://assets/audio/hit_chime/head.wav"
const KILL_PATH: String = "res://assets/audio/hit_chime/kill.wav"
const BUS_NAME: StringName = &"Effects"
## Shortest spacing between two confirms of the same or a lower tier. The
## Repeater fires every 0.10 s, so it chimes about every other shot; the Arc
## (0.15 s) and slower guns chime on every hit.
const MIN_GAP_MS: int = 130
## Body pitch runs from a graze to a 100 point hit; more stays at the top.
const BODY_PITCH_LOW: float = 0.9
const BODY_PITCH_HIGH: float = 1.3
const BODY_DAMAGE_TOP: float = 100.0
## A headshot rises a little with its damage, from its own base.
const HEAD_PITCH_LOW: float = 1.0
const HEAD_PITCH_HIGH: float = 1.12
const HEAD_DAMAGE_TOP: float = 200.0
## A shield or a teammate stopped the shot: low and quiet.
const BLOCKED_PITCH: float = 0.8
const VOLUME_DB: Dictionary = {
	Tier.BLOCKED: -12.0,
	Tier.BODY: -6.0,
	Tier.HEAD: -4.0,
	Tier.KILL: -3.0,
}

## Tests inject a source: Callable(path: String) -> AudioStream or null.
var clip_source: Callable = Callable()
var _hit_player: AudioStreamPlayer = null
var _kill_player: AudioStreamPlayer = null
var _streams: Dictionary = {}
var _last_ms: int = -1000000
var _last_tier: int = -1
## What the last accepted confirm played, for tests and the QA tour.
var last_tier: int = -1
var last_pitch: float = 1.0
var played: int = 0
var dropped: int = 0


func _ready() -> void:
	var bus: StringName = BUS_NAME if AudioServer.get_bus_index(BUS_NAME) >= 0 else &"Master"
	_hit_player = AudioStreamPlayer.new()
	_hit_player.name = "HitChimePlayer"
	_hit_player.bus = bus
	add_child(_hit_player)
	_kill_player = AudioStreamPlayer.new()
	_kill_player.name = "KillChimePlayer"
	_kill_player.bus = bus
	add_child(_kill_player)


## The tier a reported hit earns. Zero damage is a stopped shot whatever else
## the result says; a kill outranks a headshot.
static func tier_for(damage: int, head: bool, killed: bool) -> int:
	if killed:
		return Tier.KILL
	if damage <= 0:
		return Tier.BLOCKED
	return Tier.HEAD if head else Tier.BODY


## Pitch for a tier and the damage that earned it. Body hits climb with damage;
## the head and kill tiers have their own clip and a narrow range of their own.
static func pitch_for(tier: int, damage: int) -> float:
	match tier:
		Tier.BLOCKED:
			return BLOCKED_PITCH
		Tier.BODY:
			return lerpf(BODY_PITCH_LOW, BODY_PITCH_HIGH, clampf(float(damage) / BODY_DAMAGE_TOP, 0.0, 1.0))
		Tier.HEAD:
			return lerpf(HEAD_PITCH_LOW, HEAD_PITCH_HIGH, clampf(float(damage) / HEAD_DAMAGE_TOP, 0.0, 1.0))
	return 1.0


static func path_for(tier: int) -> String:
	match tier:
		Tier.HEAD:
			return HEAD_PATH
		Tier.KILL:
			return KILL_PATH
	return BODY_PATH


## Play the confirm for one reported hit. Returns the tier that sounded, or -1
## when the gap dropped it or no clip exists.
func confirm(damage: int, head: bool = false, killed: bool = false, now_ms: int = -1) -> int:
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	var tier: int = tier_for(damage, head, killed)
	if tier != Tier.KILL and now - _last_ms < MIN_GAP_MS and tier <= _last_tier:
		dropped += 1
		return -1
	var clip: AudioStream = _stream(path_for(tier))
	if clip == null:
		return -1
	var player: AudioStreamPlayer = _kill_player if tier == Tier.KILL else _hit_player
	if player == null:
		return -1
	player.stream = clip
	player.pitch_scale = pitch_for(tier, damage)
	player.volume_db = float(VOLUME_DB[tier])
	player.play()
	_last_ms = now
	_last_tier = tier
	last_tier = tier
	last_pitch = player.pitch_scale
	played += 1
	return tier


func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var clip: AudioStream = null
	if clip_source.is_valid():
		var injected: Variant = clip_source.call(path)
		clip = injected as AudioStream if injected is AudioStream else null
	elif ResourceLoader.exists(path):
		clip = load(path) as AudioStream
	_streams[path] = clip
	return clip


## Stop both players; the match scene retires them on exit.
func silence() -> void:
	if _hit_player != null:
		_hit_player.stop()
	if _kill_player != null:
		_kill_player.stop()
