class_name EnemyView
extends RefCounted

const CAMERA = preload("res://scripts/spectator_cam.gd")
static var _textures: Dictionary[String, Texture2D] = {}

var actor: Dictionary = {}
var weapon: String = ""
var tick: int = 0
var elapsed: float = 0.0
var travel: float = 0.0
var shot_age: float = INF
var _kind: String = ""

func update(state: Dictionary, snapshot_tick: int, body: Sprite3D) -> void:
	actor = state["campaign"]
	weapon = str(state["weapon"])
	# A repeated snapshot must not restart a windup, gait or corpse animation.
	if snapshot_tick > tick or _kind == "":
		tick = snapshot_tick
		elapsed = 0.0
	var kind: String = actor["kind"]
	if kind == _kind:
		return
	_kind = kind
	if not _textures.has(kind):
		_textures[kind] = load("res://assets/characters/union/%s.png" % kind)
	body.frame = 0
	body.texture = _textures[kind]
	body.hframes = EnemyAnimation.COLUMNS
	body.vframes = EnemyAnimation.rows()
	body.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
	body.position.y = EnemyAnimation.CENTRE_HEIGHT - CAMERA.FP_SERVER_REFERENCE_Y
	body.shaded = true

func advance(delta: float, distance: float) -> void:
	elapsed += delta
	shot_age += delta
	if actor.get("phase") == "moving" and distance >= 0.0 and distance < 2.0:
		travel = fposmod(travel + distance, EnemyAnimation.STRIDE_METRES)

func shot() -> void:
	shot_age = 0.0

func render(body: Sprite3D, yaw: float, to_camera: Vector3) -> void:
	if actor.is_empty():
		return
	body.frame = EnemyAnimation.frame(actor, weapon, tick, elapsed, travel,
		shot_age, EnemyAnimation.direction(yaw, to_camera))
