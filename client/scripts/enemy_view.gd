class_name EnemyView
extends RefCounted

const CAMERA = preload("res://scripts/spectator_cam.gd")
const UNION_SPRITE: Shader = preload("res://assets/shaders/union_sprite.gdshader")
static var _textures: Dictionary[String, Texture2D] = {}
## The Auditor's atlas draws its shield plate; a gold rim keeps the officer
## distinct at range, and two lamps on the drawn plate count repairs left.
const AUDITOR_RIM: Color = Color("c9a15a")
const LAMP_SHADER: Shader = preload("res://assets/shaders/grenade_surface.gdshader")
## Where the atlas draws the plate's two lamp sockets, in pawn space (facing
## +X, origin 1.5 m above the feet): at rest, and raised with the plate while
## the Auditor channels. Measured from `auditor_rig.gd`.
const PLATE_LAMPS: Array[Vector3] = [Vector3(0.37, -0.24, 0.08), Vector3(0.40, -0.24, 0.27)]
const CHANNEL_LAMPS: Array[Vector3] = [Vector3(0.55, -0.02, 0.08), Vector3(0.55, -0.02, 0.28)]

var actor: Dictionary = {}
var weapon: String = ""
var tick: int = 0
var elapsed: float = 0.0
var travel: float = 0.0
## True when this presentation step actually moved. Recovery uses it for the walk.
var stepping: bool = false
var shot_age: float = INF
var _kind: String = ""
var _landed: bool = false
## A repaired bot stands back up through its death clip in reverse.
var _standing: bool = false
var _last_phase: String = ""
var assessor_rig: AssessorRig

func update(state: Dictionary, snapshot_tick: int, body: Sprite3D) -> void:
	actor = state["campaign"]
	weapon = str(state["weapon"])
	var phase: String = str(actor["phase"])
	if phase != _last_phase:
		_standing = _last_phase == "dead" and phase == "recovery"
		_last_phase = phase
		if _kind == "auditor":
			_place_lamps(body, phase == "channeling")
	# A repeated snapshot must not restart a windup, gait or corpse animation.
	if snapshot_tick > tick or _kind == "":
		tick = snapshot_tick
		elapsed = 0.0
	var kind: String = actor["kind"]
	if kind == "assessor":
		if assessor_rig == null:
			assessor_rig = AssessorRig.new()
			assessor_rig.position.y = -CAMERA.FP_SERVER_REFERENCE_Y
			body.get_parent().add_child(assessor_rig)
		body.visible = false
		_kind = kind
		assessor_rig.present(actor, tick, elapsed)
		return
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
	material.set_shader_parameter("normals_enabled", kind in ["sweeper", "clerk", "auditor", "enforcer", "redactor"])
	if kind in ["sweeper", "clerk", "auditor", "enforcer", "redactor"]:
		var normal_key: String = kind + "_normals"
		if not _textures.has(normal_key):
			_textures[normal_key] = load("res://assets/characters/union/" + normal_key + ".png") as Texture2D
		material.set_shader_parameter("sprite_normals", _textures[normal_key])
	if kind == "auditor":
		material.set_shader_parameter("rim_color", AUDITOR_RIM)
		_attach_plate(body)
		_place_lamps(body, phase == "channeling")

## Two repair lamps for the plate the atlas draws. They live in pawn space, so
## they turn with the server facing and the body hides them from behind;
## `AuditorChannels` lights one per repair left.
func _attach_plate(body: Sprite3D) -> void:
	var pawn: Node = body.get_parent()
	if pawn == null or pawn.get_node_or_null("AuditorPlate") != null:
		return
	var plate: Node3D = Node3D.new()
	plate.name = "AuditorPlate"
	for index: int in range(PLATE_LAMPS.size()):
		plate.add_child(_plate_part("Lamp%d" % index, Vector3(0.06, 0.06, 0.06), PLATE_LAMPS[index], Color("ff3020")))
	pawn.add_child(plate)

## The lamps follow the drawn plate up when the Auditor raises it to channel.
func _place_lamps(body: Sprite3D, channeling: bool) -> void:
	var pawn: Node = body.get_parent()
	var plate: Node = pawn.get_node_or_null("AuditorPlate") if pawn != null else null
	if plate == null:
		return
	# Standing plate sockets cannot remain suspended above a fallen or rising body.
	plate.visible = actor.get("kind") == "auditor" and actor.get("phase") != "dead" \
		and not (_standing and actor.get("phase") == "recovery")
	var places: Array[Vector3] = CHANNEL_LAMPS if channeling else PLATE_LAMPS
	for index: int in range(places.size()):
		var lamp: Node3D = plate.get_node_or_null("Lamp%d" % index)
		if lamp != null:
			lamp.position = places[index]

func _plate_part(part_name: String, size: Vector3, offset: Vector3, colour: Color) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = part_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = offset
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = LAMP_SHADER
	material.set_shader_parameter("effect_color", colour)
	material.set_shader_parameter("camera_clearance", 0.0)
	part.material_override = material
	return part

## Per-kind atlas source. Delivered art replaces a placeholder in one table.
static func atlas_path(kind: String) -> String:
	if kind == "ranged_sweeper":
		return L07Assets.RANGED_SWEEPER_ATLAS
	return "res://assets/characters/union/%s.png" % kind

func advance(delta: float, distance: float) -> void:
	elapsed += delta
	if assessor_rig != null:
		assessor_rig.advance(delta)
	shot_age += delta
	var phase: String = str(actor.get("phase", ""))
	stepping = distance >= 0.002 and distance < 2.0
	var gait: bool = phase in ["moving", "charging"] or (phase == "recovery" and stepping)
	if gait and distance >= 0.0 and distance < 2.0:
		var stride: float = CrawlerAnimation.STRIDE_METRES if _kind == "crawler" else EnemyAnimation.STRIDE_METRES
		travel = fposmod(travel + distance, stride)

func shot() -> void:
	shot_age = 0.0

func render(body: Sprite3D, yaw: float, to_camera: Vector3) -> void:
	if actor.is_empty():
		return
	if _kind == "assessor" and assessor_rig != null:
		assessor_rig.present(actor, tick, elapsed)
		return
	if _kind == "redactor":
		var material: ShaderMaterial = body.material_override as ShaderMaterial
		if material != null:
			var hidden_approach: bool = actor.get("phase") in ["idle", "moving"]
			material.set_shader_parameter("shimmer", 1.0 if hidden_approach else 0.0)
			material.set_shader_parameter("shimmer_tick", float(tick))
			material.set_shader_parameter("red_glow", 2.4 if actor.get("phase") == "windup" else 1.6)
	var facing: int = EnemyAnimation.direction(yaw, to_camera)
	if _kind == "notary":
		body.frame = NotaryAnimation.frame(actor, tick, elapsed, facing, _landed)
	elif _kind == "jammer":
		body.frame = JammerAnimation.frame(actor, tick, elapsed, facing)
	elif _kind == "crawler":
		body.frame = CrawlerAnimation.frame(actor, tick, elapsed, travel, facing)
	elif _kind == "enforcer" and actor.get("phase") == "charging":
		body.frame = enforcer_charge_frame(travel, facing)
	else:
		var custody: int = custody_frame(actor, weapon, tick, elapsed, facing, _standing)
		body.frame = custody if custody >= 0 else EnemyAnimation.frame(actor, weapon, tick, elapsed,
			travel, shot_age, facing, stepping)

## The Enforcer's unused armed gait row holds its committed charge posture.
## Playback cannot advance the authoritative charge phase or cause a hit.
static func enforcer_charge_frame(distance: float, facing: int) -> int:
	return posmod(facing, EnemyAnimation.DIRECTIONS) * EnemyAnimation.poses() \
		+ EnemyAnimation.pose_frame("walk", false,
			fposmod(distance / EnemyAnimation.STRIDE_METRES, 1.0))

## Custody poses over the shared baked layout: the Auditor's channel is the
## seated cell of its own atlas, which an Auditor never otherwise uses, and a
## repaired bot rises through its death clip in reverse.
## Returns -1 when the ordinary phase table applies.
static func custody_frame(state: Dictionary, held: String, snapshot_tick: int, since: float,
		facing: int, standing: bool) -> int:
	var phase: String = str(state.get("phase", ""))
	var base: int = posmod(facing, EnemyAnimation.DIRECTIONS) * EnemyAnimation.poses()
	var unarmed: bool = held == "Fists"
	if phase == "channeling":
		return base + EnemyAnimation.pose_frame("seated", false, 0.0)
	if phase != "recovery" or not standing:
		return -1
	var started: int = int(state["phase_started"])
	var age: float = maxf(0.0, float(snapshot_tick - started) * EnemyAnimation.TICK_SECONDS) \
		+ clampf(since, 0.0, EnemyAnimation.MAX_EXTRAPOLATION)
	var duration: float = maxf(EnemyAnimation.TICK_SECONDS,
		float(int(state["phase_ends"]) - started) * EnemyAnimation.TICK_SECONDS)
	return base + EnemyAnimation.pose_frame("death", unarmed, 1.0 - age / duration)
