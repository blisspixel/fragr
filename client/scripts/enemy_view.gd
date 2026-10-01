class_name EnemyView
extends RefCounted

const CAMERA = preload("res://scripts/spectator_cam.gd")
const UNION_SPRITE: Shader = preload("res://assets/shaders/union_sprite.gdshader")
static var _textures: Dictionary[String, Texture2D] = {}

var actor: Dictionary = {}
var weapon: String = ""
var tick: int = 0
var elapsed: float = 0.0
var travel: float = 0.0
var shot_age: float = INF
var _kind: String = ""
var _landed: bool = false

func update(state: Dictionary, snapshot_tick: int, body: Sprite3D) -> void:
	actor = state["campaign"]
	weapon = str(state["weapon"])
	# A repeated snapshot must not restart a windup, gait or corpse animation.
	if snapshot_tick > tick or _kind == "":
		tick = snapshot_tick
		elapsed = 0.0
	var kind: String = actor["kind"]
	if kind == "notary":
		var feet: Vector3 = Vector3(float(state["x"]), float(state["y"]) - CAMERA.FP_SERVER_REFERENCE_Y, float(state["z"]))
		_landed = actor["phase"] == "dead" and absf(feet.y - NotaryAnimation.support(feet)) <= 0.04
	if kind == _kind:
		return
	_kind = kind
	if not _textures.has(kind):
		_textures[kind] = load("res://assets/characters/union/%s.png" % kind)
	body.frame = 0
	body.texture = _textures[kind]
	if kind == "notary":
		body.hframes = NotaryAnimation.COLUMNS
		body.vframes = NotaryAnimation.rows()
		body.pixel_size = NotaryAnimation.VIEW_SIZE / NotaryAnimation.TILE
		body.position.y = NotaryAnimation.CENTRE_HEIGHT - CAMERA.FP_SERVER_REFERENCE_Y
	elif kind == "jammer":
		body.hframes = JammerAnimation.COLUMNS
		body.vframes = JammerAnimation.rows()
		body.pixel_size = JammerAnimation.VIEW_SIZE / JammerAnimation.TILE
		body.position.y = JammerAnimation.CENTRE_HEIGHT - CAMERA.FP_SERVER_REFERENCE_Y
	elif kind == "crawler":
		body.hframes = CrawlerAnimation.COLUMNS
		body.vframes = CrawlerAnimation.rows()
		body.pixel_size = CrawlerAnimation.VIEW_SIZE / CrawlerAnimation.TILE
		body.position.y = CrawlerAnimation.CENTRE_HEIGHT - CAMERA.FP_SERVER_REFERENCE_Y
	else:
		body.hframes = EnemyAnimation.COLUMNS
		body.vframes = EnemyAnimation.rows()
		body.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
		body.position.y = EnemyAnimation.CENTRE_HEIGHT - CAMERA.FP_SERVER_REFERENCE_Y
	body.shaded = true
	# Black and red in fixture-lit rooms: red optics and tells burn full-bright,
	# the darkest cloth lifts toward charcoal, and a one-texel line separates
	# the silhouette from any wall. The override keeps billboard, nearest
	# sampling, alpha cut and the hit-flash modulate of the Sprite3D.
	var material: ShaderMaterial = body.material_override as ShaderMaterial
	if material == null or material.shader != UNION_SPRITE:
		material = ShaderMaterial.new()
		material.shader = UNION_SPRITE
		body.material_override = material
	material.set_shader_parameter("sprite_texture", body.texture)

func advance(delta: float, distance: float) -> void:
	elapsed += delta
	shot_age += delta
	if actor.get("phase") == "moving" and distance >= 0.0 and distance < 2.0:
		var stride: float = CrawlerAnimation.STRIDE_METRES if _kind == "crawler" else EnemyAnimation.STRIDE_METRES
		travel = fposmod(travel + distance, stride)

func shot() -> void:
	shot_age = 0.0

func render(body: Sprite3D, yaw: float, to_camera: Vector3) -> void:
	if actor.is_empty():
		return
	var facing: int = EnemyAnimation.direction(yaw, to_camera)
	if _kind == "notary":
		body.frame = NotaryAnimation.frame(actor, tick, elapsed, facing, _landed)
	elif _kind == "jammer":
		body.frame = JammerAnimation.frame(actor, tick, elapsed, facing)
	elif _kind == "crawler":
		body.frame = CrawlerAnimation.frame(actor, tick, elapsed, travel, facing)
	else:
		body.frame = EnemyAnimation.frame(actor, weapon, tick, elapsed, travel,
			shot_age, facing)
