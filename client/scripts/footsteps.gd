class_name Footsteps
extends Node3D

## A fighter's feet: running steps, jump push-offs and landings, placed in the
## world at the fighter's feet so a listener can tell where they are. Rides on
## the pawn and reads only what the pawn already has from the server: its
## rendered travel, its stance and the `airborne` flag (docs/protocol.md).
## The pawn decides nothing here; FootstepGait says when, FootstepSurface
## says what the floor is, and this node plays it.
##
## Range (docs/plans/fun-craft-targets.md row 18): a running enemy is heard
## out to 20 to 30 m and not past MAX_DISTANCE; a walk or a crouch is silent.
## test_footsteps.gd measures the curve through the mixer.

const ROOT: String = "res://assets/audio/footsteps/"
const TAKES: Array[String] = ["a", "b"]
const DEFAULT_TAKE: String = "a"
const STEP_VARIANTS: int = 3
const BUS: StringName = &"Effects"

## Inverse-distance rolloff: full level inside UNIT_SIZE, -6 dB per doubling
## after it, and Godot's linear fade to nothing at MAX_DISTANCE on top. Measured
## by test_footsteps.gd against the same step at 2 m: -15 dB at 20 m, -19 at
## 25, -22 at 30, -31 at 40 and nothing from 50 m.
const UNIT_SIZE: float = 10.0
const MAX_DISTANCE: float = 50.0
const MAX_DB: float = 0.0
## Another fighter's step, at the source.
const STEP_DB: float = -6.0
## Landings as audible as steps, a little heavier.
const LAND_DB: float = -4.0
const JUMP_DB: float = -10.0
## Your own feet sit under everybody else's (the priority stack: enemy
## footsteps above own footsteps).
const OWN_DB: float = -9.0
## Distance muffling: the far step is duller as well as quieter.
const FAR_CUTOFF_HZ: float = 3200.0
const FAR_FILTER_DB: float = -12.0
## Each footfall varies a little so a run is not one sample on repeat.
const PITCH_SPREAD: float = 0.05

## Body weight in pitch. Union bots and powered armour land heavier.
const PITCH_BY_KIND: Dictionary[String, float] = {
	"heavy_sweeper": 0.8,
	"enforcer": 0.86,
	"sweeper": 0.92,
	"synthetic": 0.95,
}
## Hostile kinds that walk on feet. Fliers, crawlers, turrets and broad
## machines keep their own sounds.
const WALKING_ENEMIES: Array[String] = ["clerk", "sweeper", "heavy_sweeper", "auditor", "enforcer", "redactor"]

## The take everyone hears ("a" or "b"), from settings (`[footsteps] take`).
static var take: String = DEFAULT_TAKE
static var _streams: Dictionary = {}

var gait: FootstepGait = FootstepGait.new()
var player: AudioStreamPlayer3D = null
## Pitch for this body, from its kind.
var base_pitch: float = 1.0
## The listener's own body: quieter, still positional.
var own: bool = false
## False for bodies whose feet make no footsteps (fliers, turrets).
var walks: bool = true
## The last thing played, for the harnesses: "", "step", "land", "jump".
var last_event: String = ""
var last_surface: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_variant: int = -1
## Server airborne edges by tick, so a remote body lands when it is drawn
## landing, not when the newest snapshot says so.
var _airborne_ticks: Array[Vector2i] = []
var _latest_airborne: bool = false


func _ready() -> void:
	_rng.randomize()
	player = AudioStreamPlayer3D.new()
	player.name = "FeetPlayer"
	configure_player(player)
	add_child(player)


## The rolloff every footstep player uses. Static so the harness builds the
## same player the game does.
static func configure_player(target: AudioStreamPlayer3D) -> void:
	target.bus = BUS if AudioServer.get_bus_index(BUS) >= 0 else &"Master"
	target.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	target.unit_size = UNIT_SIZE
	target.max_distance = MAX_DISTANCE
	target.max_db = MAX_DB
	target.volume_db = STEP_DB
	target.panning_strength = 1.0
	target.attenuation_filter_cutoff_hz = FAR_CUTOFF_HZ
	target.attenuation_filter_db = FAR_FILTER_DB
	target.max_polyphony = 3
	target.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED


## Which bodies have feet, from the snapshot row's campaign identity.
static func walks_for(campaign_actor: Dictionary, hostile_kind: String) -> bool:
	if campaign_actor.is_empty():
		return true
	var side: String = str(campaign_actor.get("side", ""))
	if side == "hostile":
		return hostile_kind in WALKING_ENEMIES
	# Latch keeps her own machine sounds, and a staged story figure is dressed
	# by its level, not walked by the pawn.
	return side in ["participant", "entrant"]


static func pitch_for(kind: String) -> float:
	return PITCH_BY_KIND.get(kind, 1.0)


static func valid_take(value: Variant) -> String:
	return str(value) if value is String and value in TAKES else DEFAULT_TAKE



## The clip names for one sound of one take: three steps, or one landing, or
## the jump.
static func clip_names(of_take: String, event: String, surface: String) -> Array[String]:
	var names: Array[String] = []
	var set_name: String = surface if surface in FootstepSurface.SETS else FootstepSurface.CONCRETE
	match event:
		FootstepGait.STEP:
			for index: int in range(1, STEP_VARIANTS + 1):
				names.append("%s/%s_step_%d" % [of_take, set_name, index])
		FootstepGait.LAND:
			names.append("%s/%s_land" % [of_take, set_name])
		FootstepGait.JUMP:
			names.append("%s/jump" % of_take)
	return names


static func stream_for(clip: String) -> AudioStream:
	if _streams.has(clip):
		return _streams[clip]
	var path: String = ROOT + clip + ".wav"
	var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	_streams[clip] = stream
	return stream


## A server airborne fact for `tick`. Ticks arrive in order; older edges are
## dropped once a newer one is drawn.
func observe(tick: int, airborne: bool) -> void:
	if tick < 0:
		_latest_airborne = airborne
		return
	if not _airborne_ticks.is_empty() and _airborne_ticks.back().x >= tick:
		return
	_latest_airborne = airborne
	if _airborne_ticks.is_empty() or bool(_airborne_ticks.back().y) != airborne:
		_airborne_ticks.append(Vector2i(tick, 1 if airborne else 0))
	if _airborne_ticks.size() > 16:
		_airborne_ticks.pop_front()


## The flag as of the drawn tick, or the newest one without a timeline.
func airborne_at(view_tick: float) -> bool:
	if view_tick < 0.0 or _airborne_ticks.is_empty():
		return _latest_airborne
	var value: bool = bool(_airborne_ticks[0].y) if float(_airborne_ticks[0].x) <= view_tick else not bool(_airborne_ticks[0].y)
	for edge: Vector2i in _airborne_ticks:
		if float(edge.x) > view_tick:
			break
		value = bool(edge.y)
	return value


func clear() -> void:
	gait.reset()
	_airborne_ticks.clear()
	_latest_airborne = false


## One frame from the pawn. Plays at most one sound. Returns the event.
func present(delta: float, travel: float, rise: float, airborne: bool, ducking: bool, alive: bool, seated: bool) -> String:
	var event: String = gait.advance(delta, travel, rise, airborne, ducking, alive, seated)
	if event.is_empty() or not walks:
		return FootstepGait.NONE
	play(event, FootstepSurface.at(global_position))
	return event


func play(event: String, surface: String) -> void:
	var names: Array[String] = clip_names(take, event, surface)
	if names.is_empty() or player == null:
		return
	var index: int = 0
	if names.size() > 1:
		index = _rng.randi_range(0, names.size() - 2)
		if index >= _last_variant and _last_variant >= 0:
			index += 1
		index = clampi(index, 0, names.size() - 1)
	_last_variant = index
	var stream: AudioStream = stream_for(names[index])
	if stream == null:
		return
	var event_db: float = STEP_DB
	if event == FootstepGait.LAND:
		event_db = LAND_DB + gait.landing_db
	elif event == FootstepGait.JUMP:
		event_db = JUMP_DB
	player.stream = stream
	player.volume_db = event_db + (OWN_DB if own else 0.0)
	player.pitch_scale = base_pitch * (1.0 + _rng.randf_range(-PITCH_SPREAD, PITCH_SPREAD))
	player.play()
	last_event = event
	last_surface = surface
