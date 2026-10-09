class_name CivilianFigure
extends Node3D

## A current mission person follows accepted feet; this owns only appearance.
var skin: SkinnedCharacter = null
var rigid: SpliceCharacter = null
var strip: Sprite3D = null
var _placed: bool = false
var _walked: float = 0.0
var _clock: float = 0.0
var _moving_age: float = 1.0

func configure(person: String, color: Color) -> void:
	if person == "splice":
		var candidate: SpliceCharacter = SpliceCharacter.new()
		if candidate.configure():
			rigid = candidate
			rigid.name = "SpliceFigure"
			add_child(rigid)
			return
		candidate.free()
	if person in ["tern", "edda"]:
		var candidate: SkinnedCharacter = SkinnedCharacter.new()
		if candidate.configure(person):
			skin = candidate
			skin.name = person.capitalize() + "Skin"
			add_child(skin)
		else:
			candidate.free()
	if skin != null:
		return
	strip = Sprite3D.new()
	strip.name = "CivilianStrip"
	strip.texture = load(PlayerBody.strip_path(PlayerBody.SYNTHETIC if person in ["tern", "splice"] else PlayerBody.HUMAN)) as Texture2D
	strip.hframes = PlayerBody.IDLE_FRAMES + PlayerBody.WALK_FRAMES
	strip.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
	strip.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	strip.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	strip.layers = ArenaSky.ACTOR_LAYERS
	strip.modulate = color
	strip.position.y = EnemyAnimation.CENTRE_HEIGHT
	add_child(strip)

func place_feet(feet: Vector3) -> void:
	if _placed:
		var delta: Vector3 = feet - position
		var distance: float = Vector2(delta.x, delta.z).length()
		if distance > 0.001 and distance < 2.0:
			_walked += distance
			_moving_age = 0.0
			# Meshes face local +Z; current route travel supplies presentation facing.
			rotation.y = atan2(delta.x, delta.z)
		elif distance >= 2.0:
			_walked = 0.0
			_moving_age = 1.0
	position = feet
	_placed = true

func _process(delta: float) -> void:
	_clock += delta
	_moving_age += delta
	var moving: bool = _moving_age < 0.15
	if skin != null:
		skin.pose(fposmod(_walked / EnemyAnimation.STRIDE_METRES, 1.0), moving, false, false)
	elif rigid != null:
		rigid.pose(fposmod(_walked / EnemyAnimation.STRIDE_METRES, 1.0), moving, _clock / 4.0)
	elif strip != null:
		strip.frame = PlayerBody.frame(_clock * 4.0, _walked, 2.0 if moving else 0.0)
