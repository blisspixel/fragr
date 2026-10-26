class_name VfxSprites
extends MeshInstance3D

## A bounded pool of camera-facing atlas sprites drawn as one mesh: blast
## fire, smoke puffs, rocket trails and thrown debris. Cosmetic motion only,
## integrated locally from a resolved server position; nothing here is
## sent anywhere or decides anything.
##
## The atlas is one horizontal strip. A sprite either plays every frame over
## its lifetime or holds one cell. A sprite with negative age waits that long
## before it appears, so one blast can stagger its parts.

const SHADER: Shader = preload("res://assets/shaders/vfx_sprite.gdshader")
## Fire is its own light: drawn unlit at its palette colours.
const FIRE_SHADER: Shader = preload("res://assets/shaders/vfx_fire.gdshader")
const CAMERA_CLEARANCE: float = 0.6
## Each sprite is drawn this share of its size nearer the eye, so a fireball
## against a wall or floor is not cut in half by the surface behind it, the
## way a flat sprite in a retro shooter never is.
const TOWARD_EYE: float = 0.5

class Sprite:
	var position: Vector3
	var velocity: Vector3
	var gravity: float = 0.0
	var drag: float = 0.0
	var size: float
	var grow: float = 0.0
	var age: float = 0.0
	var lifetime: float
	## -1 plays the strip over the lifetime; otherwise the held cell.
	var cell: int = -1
	## 1 is fire that lights itself; 0 is lit by the room.
	var emit: float = 0.0
	## Share of the lifetime, at its end, spent dithering out.
	var fade_share: float = 0.0

var _sprites: Array[Sprite] = []
var _cells: int = 1
var _capacity: int = 64
var _immediate: ImmediateMesh = ImmediateMesh.new()
var _material: ShaderMaterial = ShaderMaterial.new()
var _drawn: int = 0
## Share of a sprite's size it is drawn nearer the eye; TOWARD_EYE by default.
var toward_eye: float = TOWARD_EYE

func setup(texture: Texture2D, cells: int, capacity: int, emission_energy: float = 1.0, unlit: bool = false) -> void:
	_cells = maxi(cells, 1)
	_capacity = maxi(capacity, 1)
	_material.shader = FIRE_SHADER if unlit else SHADER
	_material.set_shader_parameter("sprite_texture", texture)
	_material.set_shader_parameter("camera_clearance", CAMERA_CLEARANCE)
	_material.set_shader_parameter("emission_energy", emission_energy)
	mesh = _immediate
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	set_process(false)

## Adds a sprite; the oldest gives way at capacity. Returns it so a caller
## can set the optional fields.
func spawn(at: Vector3, velocity: Vector3, size: float, lifetime: float) -> Sprite:
	if _sprites.size() >= _capacity:
		_sprites.pop_front()
	var sprite: Sprite = Sprite.new()
	sprite.position = at
	sprite.velocity = velocity
	sprite.size = size
	sprite.lifetime = maxf(lifetime, 0.01)
	_sprites.append(sprite)
	visible = true
	set_process(true)
	return sprite

func clear() -> void:
	_sprites.clear()
	_immediate.clear_surfaces()
	_drawn = 0
	visible = false
	set_process(false)

func active_count() -> int:
	return _sprites.size()

## Sprites the last rebuild actually drew.
func drawn_count() -> int:
	return _drawn

func _process(delta: float) -> void:
	advance(delta)

## Steps every sprite by `delta` seconds and redraws; harnesses call it
## directly to play a blast frame by frame.
func advance(delta: float) -> void:
	var step: float = maxf(delta, 0.0)
	for index: int in range(_sprites.size() - 1, -1, -1):
		var sprite: Sprite = _sprites[index]
		sprite.age += step
		if sprite.age >= sprite.lifetime:
			_sprites.remove_at(index)
			continue
		if sprite.age <= 0.0:
			continue
		sprite.velocity += Vector3.DOWN * sprite.gravity * step
		sprite.velocity *= maxf(1.0 - sprite.drag * step, 0.0)
		sprite.position += sprite.velocity * step
		sprite.size += sprite.grow * step
	_rebuild()

func _rebuild() -> void:
	_immediate.clear_surfaces()
	_drawn = 0
	if _sprites.is_empty():
		visible = false
		set_process(false)
		return
	var right: Vector3 = Vector3.RIGHT
	var up: Vector3 = Vector3.UP
	var toward: Vector3 = Vector3.BACK
	var eye: Vector3 = Vector3.INF
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if is_instance_valid(camera):
		var view: Basis = global_transform.basis.inverse() * camera.get_camera_transform().basis
		right = view.x.normalized()
		up = view.y.normalized()
		toward = view.z.normalized()
		eye = to_local(camera.get_camera_transform().origin)
	var begun: bool = false
	for sprite: Sprite in _sprites:
		if sprite.age < 0.0:
			continue
		var progress: float = sprite.age / sprite.lifetime
		var cell: int = sprite.cell if sprite.cell >= 0 else int(progress * _cells)
		var uv: Rect2 = ShotVfx.strip_uv(cell, _cells)
		var fade: float = 1.0
		if sprite.fade_share > 0.0:
			fade = clampf((1.0 - progress) / sprite.fade_share, 0.0, 1.0)
		var half: float = sprite.size * 0.5
		var centre: Vector3 = sprite.position
		if eye.is_finite():
			var to_eye: Vector3 = eye - centre
			var reach: float = to_eye.length()
			if reach > 0.001:
				# Shrink by the same ratio so it keeps its apparent size.
				var pull: float = minf(sprite.size * toward_eye, maxf(reach - CAMERA_CLEARANCE - half, 0.0))
				centre += to_eye / reach * pull
				half *= (reach - pull) / reach
		var across: Vector3 = right * half
		var rise: Vector3 = up * half
		if not begun:
			_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
			begun = true
		_drawn += 1
		# Colour and normal carry to every following vertex; two triangles,
		# no per-sprite arrays: smoke trails put hundreds of these up a frame.
		_immediate.surface_set_color(Color(sprite.emit, 0.0, 0.0, fade))
		_immediate.surface_set_normal(toward)
		_vertex(Vector2(uv.position.x, uv.end.y), centre - across - rise)
		_vertex(uv.end, centre + across - rise)
		_vertex(Vector2(uv.end.x, uv.position.y), centre + across + rise)
		_vertex(Vector2(uv.position.x, uv.end.y), centre - across - rise)
		_vertex(Vector2(uv.end.x, uv.position.y), centre + across + rise)
		_vertex(uv.position, centre - across + rise)
	if begun:
		_immediate.surface_end()
	visible = begun or not _sprites.is_empty()

func _vertex(uv: Vector2, at: Vector3) -> void:
	_immediate.surface_set_uv(uv)
	_immediate.surface_add_vertex(at)
