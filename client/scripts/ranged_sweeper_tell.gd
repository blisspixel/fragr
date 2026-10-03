class_name RangedSweeperTell
extends Node3D

## The marksman's scope glint, drawn from the server's windup phase alone: a
## bright star on the first ticks, then a steady lens shine while it holds its
## aim. Nothing shows outside a windup, and nothing predicts the shot.
const CAMERA = preload("res://scripts/spectator_cam.gd")
const TICK_SECONDS: float = 0.05
const MAX_EXTRAPOLATION: float = 0.1
## The opening flash. The hold that follows is quieter but never dark.
const FLASH_SECONDS: float = 0.3
## Scope lens above the feet and forward of the chest, in the pawn's frame.
const LENS_FEET: Vector3 = Vector3(0.42, 1.58, -0.04)
## Screen-space size, so the glint still reads as a few pixels across the cut.
const FLASH_SIZE: float = 0.0016
const HOLD_SIZE: float = 0.0009
const TEXTURE_PIXELS: int = 15
const GLINT: Color = Color("fff6e8")
const HOLD: Color = Color("ffd2b8")

var sprite: Sprite3D
var phase_age: float = -1.0
var holding: bool = false

func _ready() -> void:
	sprite = Sprite3D.new()
	sprite.name = "Glint"
	sprite.texture = star_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.fixed_size = true
	sprite.shaded = false
	sprite.double_sided = true
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.position = LENS_FEET - Vector3(0.0, CAMERA.FP_SERVER_REFERENCE_Y, 0.0)
	sprite.visible = false
	add_child(sprite)

## A four-point star with a bright core, made in code so no file is needed.
static func star_texture() -> ImageTexture:
	var image: Image = Image.create(TEXTURE_PIXELS, TEXTURE_PIXELS, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var centre: int = TEXTURE_PIXELS / 2
	for offset: int in range(-centre, centre + 1):
		var fade: float = 1.0 - float(absi(offset)) / float(centre + 1)
		var arm: Color = Color(1, 1, 1, clampf(fade * 1.4, 0.0, 1.0))
		image.set_pixel(centre + offset, centre, arm)
		image.set_pixel(centre, centre + offset, arm)
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			image.set_pixel(centre + dx, centre + dy, Color.WHITE)
	return ImageTexture.create_from_image(image)

## Age of the current windup in seconds, or negative outside one.
static func windup_age(actor: Dictionary, tick: int, elapsed: float) -> float:
	if actor.get("phase") != "windup" or not EquipmentState.integer(actor.get("phase_started"), EquipmentState.MAX_EXACT_INTEGER):
		return -1.0
	var started: int = int(actor["phase_started"])
	if tick < started:
		return -1.0
	return float(tick - started) * TICK_SECONDS + clampf(elapsed, 0.0, MAX_EXTRAPOLATION)

func present(actor: Dictionary, tick: int, elapsed: float) -> void:
	if sprite == null:
		return
	phase_age = windup_age(actor, tick, elapsed)
	sprite.visible = phase_age >= 0.0
	if not sprite.visible:
		holding = false
		return
	holding = phase_age >= FLASH_SECONDS
	if holding:
		# A slow shimmer through the hold so the lens never reads as a lamp.
		var shimmer: float = 0.85 + 0.15 * sin(phase_age * TAU * 3.0)
		sprite.pixel_size = HOLD_SIZE * shimmer
		sprite.modulate = HOLD
	else:
		var flash: float = 1.0 - phase_age / FLASH_SECONDS
		sprite.pixel_size = lerpf(HOLD_SIZE, FLASH_SIZE, flash)
		sprite.modulate = GLINT
