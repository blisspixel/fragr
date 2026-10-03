class_name EnemyView
extends RefCounted

const CAMERA = preload("res://scripts/spectator_cam.gd")
const UNION_SPRITE: Shader = preload("res://assets/shaders/union_sprite.gdshader")
static var _textures: Dictionary[String, Texture2D] = {}
## Kinds still drawn with another kind's atlas. The Auditor uses the Clerk
## officer atlas until `res://assets/characters/union/auditor.png` is baked;
## removing its entry is the whole swap. Its plate and rim keep it distinct.
const PLACEHOLDER_ATLAS: Dictionary = {"auditor": "clerk"}
const AUDITOR_SCALE: float = 1.12
const AUDITOR_RIM: Color = Color("c9a15a")
const PLATE_STEEL: Color = Color("3c4248")
const PLATE_EDGE: Color = Color("8d8f86")
const PLATE_SHADER: Shader = preload("res://assets/shaders/grenade_surface.gdshader")

var actor: Dictionary = {}
var weapon: String = ""
var tick: int = 0
var elapsed: float = 0.0
var travel: float = 0.0
var shot_age: float = INF
var _kind: String = ""
var _landed: bool = false
## A repaired bot stands back up through its death clip in reverse.
var _standing: bool = false
var _last_phase: String = ""

func update(state: Dictionary, snapshot_tick: int, body: Sprite3D) -> void:
	actor = state["campaign"]
	weapon = str(state["weapon"])
	var phase: String = str(actor["phase"])
	if phase != _last_phase:
		_standing = _last_phase == "dead" and phase == "recovery"
		_last_phase = phase
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
		_textures[kind] = load(atlas_path(kind))
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
	if kind == "auditor":
		body.pixel_size *= AUDITOR_SCALE
		material.set_shader_parameter("rim_color", AUDITOR_RIM)
		_attach_plate(body)

## The shield plate faces the server facing, not the camera, so its side and
## back read as a flank. Two lamps count the repairs left.
func _attach_plate(body: Sprite3D) -> void:
	var pawn: Node = body.get_parent()
	if pawn == null or pawn.get_node_or_null("AuditorPlate") != null:
		return
	var plate: Node3D = Node3D.new()
	plate.name = "AuditorPlate"
	# Pawn origin sits 1.5 m above the feet; local +X is the facing.
	plate.position = Vector3(0.42, 1.0 - CAMERA.FP_SERVER_REFERENCE_Y, 0.0)
	plate.add_child(_plate_part("Face", Vector3(0.06, 1.0, 0.72), Vector3.ZERO, PLATE_STEEL))
	plate.add_child(_plate_part("Edge", Vector3(0.08, 0.06, 0.78), Vector3(0, 0.5, 0), PLATE_EDGE))
	for index: int in range(2):
		plate.add_child(_plate_part("Lamp%d" % index, Vector3(0.08, 0.09, 0.09),
			Vector3(0.02, 0.32, -0.14 + index * 0.28), Color("ff3020")))
	pawn.add_child(plate)

func _plate_part(part_name: String, size: Vector3, offset: Vector3, colour: Color) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = part_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = offset
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = PLATE_SHADER
	material.set_shader_parameter("effect_color", colour)
	material.set_shader_parameter("camera_clearance", 0.0)
	part.material_override = material
	return part

## Per-kind atlas source. Delivered art replaces a placeholder in one table.
static func atlas_path(kind: String) -> String:
	if kind == "ranged_sweeper":
		return L07Assets.RANGED_SWEEPER_ATLAS
	return "res://assets/characters/union/%s.png" % str(PLACEHOLDER_ATLAS.get(kind, kind))

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
		var custody: int = custody_frame(actor, weapon, tick, elapsed, facing, _standing)
		body.frame = custody if custody >= 0 else EnemyAnimation.frame(actor, weapon, tick, elapsed,
			travel, shot_age, facing)

## Custody poses over the shared baked layout: the Auditor's channel holds its
## raised hand, and a repaired bot rises through its death clip in reverse.
## Returns -1 when the ordinary phase table applies.
static func custody_frame(state: Dictionary, held: String, snapshot_tick: int, since: float,
		facing: int, standing: bool) -> int:
	var phase: String = str(state.get("phase", ""))
	var base: int = posmod(facing, EnemyAnimation.DIRECTIONS) * EnemyAnimation.poses()
	var unarmed: bool = held == "Fists"
	if phase == "channeling":
		return base + EnemyAnimation.pose_frame("raise", unarmed, 1.0)
	if phase != "recovery" or not standing:
		return -1
	var started: int = int(state["phase_started"])
	var age: float = maxf(0.0, float(snapshot_tick - started) * EnemyAnimation.TICK_SECONDS) \
		+ clampf(since, 0.0, EnemyAnimation.MAX_EXTRAPOLATION)
	var duration: float = maxf(EnemyAnimation.TICK_SECONDS,
		float(int(state["phase_ends"]) - started) * EnemyAnimation.TICK_SECONDS)
	return base + EnemyAnimation.pose_frame("death", unarmed, 1.0 - age / duration)
