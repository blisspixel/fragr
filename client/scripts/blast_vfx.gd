class_name BlastVfx
extends Node3D

## What a resolved blast looks like: a pixel fireball that burns through ten
## frames, smoke that climbs and thins, debris and embers thrown clear, one
## warm amber light that flares and dies, and a scorch on the face it struck.
## Also the smoke a rocket leaves behind it. Every part is presentation of a
## server-resolved position; the client decides no damage or reach.
##
## Bounded: fixed sprite pools and at most MAX_LIGHTS blast lights at once,
## the oldest light reused first. Light is amber, never red: red is the Union
## attack tell.

const MAX_LIGHTS: int = 3
const LIGHT_SECONDS: float = 0.42
const LIGHT_PEAK: float = 7.5
const FIRE_SECONDS: float = 0.66
const SMOKE_CAPACITY: int = 240
const FIRE_CAPACITY: int = 48
const DEBRIS_CAPACITY: int = 96
## Smoke lights itself this much, so it reads grey in a dark room.
const SMOKE_SELF_LIGHT: float = 0.35

var fire: VfxSprites
var smoke: VfxSprites
var debris: VfxSprites
var decals: VfxDecals
var _lights: Array[OmniLight3D] = []
var _light_age: Array[float] = []
var _next_light: int = 0
var blasts_shown: int = 0

func _init() -> void:
	name = "BlastVfx"
	smoke = _pool("Smoke", ShotVfx.SMOKE, ShotVfx.SMOKE_FRAMES, SMOKE_CAPACITY, 1.0)
	fire = _pool("Fire", ShotVfx.FIREBALL, ShotVfx.FIREBALL_FRAMES, FIRE_CAPACITY, 1.0, true)
	smoke.toward_eye = 0.25
	debris = _pool("Debris", ShotVfx.DEBRIS, ShotVfx.DEBRIS_CELLS, DEBRIS_CAPACITY, 1.2)
	for index: int in range(MAX_LIGHTS):
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "BlastLight%d" % index
		light.light_color = ShotVfx.BLAST_LIGHT
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.omni_attenuation = 1.4
		light.visible = false
		add_child(light)
		_lights.append(light)
		_light_age.append(LIGHT_SECONDS)
	set_process(false)

func _pool(label: String, texture: Texture2D, cells: int, capacity: int, energy: float, unlit: bool = false) -> VfxSprites:
	var pool: VfxSprites = VfxSprites.new()
	pool.name = label
	pool.setup(texture, cells, capacity, energy, unlit)
	add_child(pool)
	return pool

func clear() -> void:
	fire.clear()
	smoke.clear()
	debris.clear()
	for index: int in range(_lights.size()):
		_light_age[index] = LIGHT_SECONDS
		_lights[index].light_energy = 0.0
		_lights[index].visible = false
	set_process(false)

## Lights currently up.
func lights_lit() -> int:
	var lit: int = 0
	for light: OmniLight3D in _lights:
		lit += int(light.visible)
	return lit

## One resolved blast at `at` with server radius `radius`. `serial` seeds the
## scatter so every viewer of the same blast sees the same shape.
func blast(at: Vector3, radius: float, serial: int) -> void:
	if not at.is_finite():
		return
	blasts_shown += 1
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(serial)
	var size_scale: float = clampf(radius / 4.0, 0.5, 1.5)
	# The main ball and two smaller lobes a beat behind it.
	var ball: VfxSprites.Sprite = fire.spawn(at + Vector3.UP * 0.5 * size_scale, Vector3.UP * 0.7, 3.4 * size_scale, FIRE_SECONDS)
	ball.emit = 1.0
	ball.grow = 0.5 * size_scale
	for lobe: int in range(2):
		var side: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.1, 0.7), rng.randf_range(-1.0, 1.0)).normalized()
		var part: VfxSprites.Sprite = fire.spawn(at + side * 0.7 * size_scale, side * 1.4 + Vector3.UP * 0.6,
			2.0 * size_scale, FIRE_SECONDS * 0.85)
		part.emit = 1.0
		part.age = -0.04 - 0.05 * lobe
	# Smoke climbs out of the ball after it peaks and outlasts it.
	for puff: int in range(8):
		var out: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).limit_length(1.0)
		var cloud: VfxSprites.Sprite = smoke.spawn(at + out * 0.9 * size_scale + Vector3.UP * rng.randf_range(0.4, 1.2) * size_scale,
			out * 0.5 + Vector3.UP * rng.randf_range(0.7, 1.4), rng.randf_range(1.5, 2.1) * size_scale, rng.randf_range(1.7, 2.5))
		cloud.grow = 1.1 * size_scale
		cloud.drag = 0.6
		cloud.fade_share = 0.55
		cloud.age = -rng.randf_range(0.36, 0.5)
		cloud.emit = SMOKE_SELF_LIGHT
	# Debris and embers thrown clear, falling under gravity.
	for chunk: int in range(14):
		var direction: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.35, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var cell: int = chunk % ShotVfx.DEBRIS_CELLS
		var piece: VfxSprites.Sprite = debris.spawn(at + direction * 0.3, direction * rng.randf_range(4.5, 8.5) * size_scale,
			rng.randf_range(0.14, 0.24), rng.randf_range(0.7, 1.2))
		piece.cell = cell
		piece.gravity = 9.8
		piece.drag = 0.4
		piece.emit = 1.0 if cell == 2 else 0.0
		piece.fade_share = 0.25
	_light(at + Vector3.UP * 0.6, 8.0 * size_scale)
	if decals != null:
		decals.add_scorch(at)
	set_process(true)

## Smoke behind a rocket in flight at `at`, moving along `forward`.
func trail(at: Vector3, forward: Vector3, serial: int) -> void:
	if not at.is_finite():
		return
	var drift: Vector3 = Vector3(sin(serial * 1.7), 0.6 + 0.3 * sin(serial * 2.3), cos(serial * 1.3)) * 0.25
	var puff: VfxSprites.Sprite = smoke.spawn(at, drift - forward * 0.5, 0.46, 1.1 + 0.4 * absf(sin(serial * 0.9)))
	puff.grow = 1.0
	puff.drag = 1.2
	puff.fade_share = 0.55
	puff.emit = SMOKE_SELF_LIGHT

func _light(at: Vector3, reach: float) -> void:
	# Reuse the oldest light: a new blast always gets one.
	var index: int = _next_light % _lights.size()
	_next_light += 1
	var light: OmniLight3D = _lights[index]
	light.position = at
	light.omni_range = reach
	light.visible = true
	_light_age[index] = 0.0
	light.light_energy = LIGHT_PEAK

## The flare: up in a frame, then a fast fall with a short warm tail.
static func light_energy(age: float) -> float:
	if age < 0.0 or age >= LIGHT_SECONDS:
		return 0.0
	var fall: float = 1.0 - age / LIGHT_SECONDS
	return LIGHT_PEAK * fall * fall

func _process(delta: float) -> void:
	advance(delta)

## Steps lights by `delta`; the sprite pools step themselves each frame.
func advance(delta: float) -> void:
	var any: bool = false
	for index: int in range(_lights.size()):
		if not _lights[index].visible:
			continue
		_light_age[index] += maxf(delta, 0.0)
		var energy: float = light_energy(_light_age[index])
		_lights[index].light_energy = energy
		_lights[index].visible = energy > 0.0
		any = any or _lights[index].visible
	if not any:
		set_process(false)
