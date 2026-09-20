class_name MeleeView
extends Control

## Alternating arms from the full-canvas pose. Wrist cutoffs stay below screen.
const TEXTURE: Texture2D = preload("res://assets/weapons/viewmodels/wpn_fists_0.png")
const DURATION: float = 0.32
var arms: Array[TextureRect] = []
var active_arm: int = 0
var remaining: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(2):
		var arm: TextureRect = TextureRect.new()
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = TEXTURE
		var split: int = TEXTURE.get_width() / 2
		atlas.region = Rect2(0 if index == 0 else split, 0, split if index == 0 else TEXTURE.get_width() - split, TEXTURE.get_height())
		arm.texture = atlas
		arm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		arm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(arm)
		arms.append(arm)
	visible = false

func punch() -> void:
	active_arm = 1 - active_arm
	remaining = DURATION

func reset() -> void:
	remaining = 0.0
	visible = false

func _process(delta: float) -> void:
	remaining = maxf(0.0, remaining - delta)

func pose(base: Vector2, canvas_size: Vector2) -> void:
	position = base
	var elapsed: float = DURATION - remaining
	var extension: float = minf(elapsed / 0.075, remaining / 0.245) if remaining > 0.0 else 0.0
	for index in range(arms.size()):
		var weight: float = extension if index == active_arm else 0.0
		var arm: TextureRect = arms[index]
		var width: float = arm.texture.get_width() / float(TEXTURE.get_width()) * canvas_size.x
		arm.size = Vector2(width, canvas_size.y) * (1.0 + weight * 1.1)
		var rest_x: float = 0.0 if index == 0 else canvas_size.x - width
		var extended_x: float = canvas_size.x * 0.5 - arm.size.x * (0.72 if index == 0 else 0.28)
		arm.position = Vector2(lerpf(rest_x, extended_x, weight), canvas_size.y - arm.size.y).round()
