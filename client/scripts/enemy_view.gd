class_name EnemyView
extends RefCounted

const CAMERA = preload("res://scripts/spectator_cam.gd")
const UNION_SPRITE: Shader = preload("res://assets/shaders/union_sprite.gdshader")
## Linear plate scale that brings the Heavy Sweeper's sheet to the Clerk's
## issued-black value in daylight, red points excluded.
const HEAVY_BODY_VALUE: float = 0.4
## Sheets whose lamps are painted about three times the issued optic's linear
## red (0.76 against 0.26). Their light is held to the issued optic's value
## and the tell swells in a deeper red, so the top of a windup stays red.
const BRIGHT_LAMP_KINDS: Array[String] = ["heavy_sweeper", "turret"]
const ISSUED_OPTIC_LEVEL: float = 0.3
const UNCAPPED_OPTIC_LEVEL: float = 1000.0
const ISSUED_TELL_HUE: Vector3 = Vector3(1.0, 0.07, 0.05)
const BRIGHT_TELL_HUE: Vector3 = Vector3(1.0, 0.03, 0.025)
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
## Absorbed bots: the Inheritance's muted cyan working light in place of the
## dead red optics. Never neon: the art bible swatch at a low energy.
const WORK_GLOW: Color = Color("4a8a92")
const WORK_ENERGY: float = 1.1
## Every absorbed bot breathes and steps on one shared beat, taken from the
## server tick, so a group moves with one timing no Union squad has.
const SHARED_BEAT_SECONDS: float = 0.64
const SHARED_BREATH_SECONDS: float = 2.56
## Union optic light (the shader's `red_glow`): at rest, the flash that opens
## a tell, the swell from just after it to the shot, and through a burst.
const OPTIC_REST: float = 1.6
const OPTIC_FLASH: float = 4.6
const OPTIC_FLASH_SECONDS: float = 0.1
const OPTIC_SWELL: float = 2.2
const OPTIC_PEAK: float = 3.6
const OPTIC_FIRING: float = 2.8

## Level 18's turn, in server ticks [from, to): while a snapshot tick is
## inside it every absorbed bot's working light carries the custody depot's
## rhythm (M08Archive.noise_lit, three short and one long) on the same
## clock. Set by the M18 presenter from a server fact; (-1, -1) is none.
static var signal_window: Vector2i = Vector2i(-1, -1)

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
## Under Inheritance control: Union chassis with dead red optics.
var absorbed: bool = false
var assessor_rig: AssessorRig
var paver_rig: PaverRig
var surveyor_rig: SurveyorRig

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
	absorbed = ActorState.control(actor) == "absorbed"
	if kind == "surveyor":
		if surveyor_rig == null:
			surveyor_rig = SurveyorRig.new()
			surveyor_rig.position.y = -CAMERA.FP_SERVER_REFERENCE_Y
			body.get_parent().add_child(surveyor_rig)
		body.visible = false
		_kind = kind
		surveyor_rig.present(actor, tick, elapsed)
		return
	if kind == "assessor":
		if assessor_rig == null:
			assessor_rig = AssessorRig.new()
			assessor_rig.position.y = -CAMERA.FP_SERVER_REFERENCE_Y
			body.get_parent().add_child(assessor_rig)
		body.visible = false
		_kind = kind
		assessor_rig.present(actor, tick, elapsed)
		return
	if kind == "paver":
		if paver_rig == null:
			paver_rig = PaverRig.new()
			paver_rig.position.y = -CAMERA.FP_SERVER_REFERENCE_Y
			body.get_parent().add_child(paver_rig)
		body.visible = false
		_kind = kind
		paver_rig.present(actor, tick, elapsed)
		return
	if kind == "notary":
		var feet: Vector3 = Vector3(float(state["x"]), float(state["y"]) - CAMERA.FP_SERVER_REFERENCE_Y, float(state["z"]))
		_landed = actor["phase"] == "dead" and absf(feet.y - NotaryAnimation.support(feet)) <= 0.04
	if kind == _kind:
		_apply_absorbed(body)
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
	# Issued black at distance: the Heavy's plates are baked lighter than any
	# other Union sheet and carry no normal map (see union_sprite body_value).
	material.set_shader_parameter("body_value", HEAVY_BODY_VALUE if kind == "heavy_sweeper" else 1.0)
	# Lamps painted far above the issued optic would clip to salmon when the
	# tell drives them; only these sheets cap and deepen their light.
	var bright: bool = kind in BRIGHT_LAMP_KINDS
	material.set_shader_parameter("optic_level", ISSUED_OPTIC_LEVEL if bright else UNCAPPED_OPTIC_LEVEL)
	material.set_shader_parameter("tell_hue", BRIGHT_TELL_HUE if bright else ISSUED_TELL_HUE)
	if kind == "auditor":
		material.set_shader_parameter("rim_color", AUDITOR_RIM)
		_attach_plate(body)
		_place_lamps(body, phase == "channeling")
	_apply_absorbed(body)

## Absorption keeps the chassis, paint and plates; only the light changes.
func _apply_absorbed(body: Sprite3D) -> void:
	var material: ShaderMaterial = body.material_override as ShaderMaterial
	if material == null or material.shader != UNION_SPRITE:
		return
	material.set_shader_parameter("absorbed", 1.0 if absorbed else 0.0)
	material.set_shader_parameter("work_glow", WORK_GLOW)
	material.set_shader_parameter("work_rest", WORK_ENERGY)

## Seconds on the shared server clock, smoothed by at most one tick.
func shared_seconds() -> float:
	return float(tick) * EnemyAnimation.TICK_SECONDS + clampf(elapsed, 0.0, EnemyAnimation.MAX_EXTRAPOLATION)

## The working light's energy for this frame. The attack tell keeps its
## shape and timing: it swells through the authoritative windup exactly where
## a Union bot's red optics would.
static func work_energy(state: Dictionary, seconds: float, snapshot_tick: int, since: float) -> float:
	var phase: String = str(state.get("phase", ""))
	if phase == "dead":
		return 0.0
	var breath: float = 0.82 + 0.18 * sin(seconds * TAU / SHARED_BREATH_SECONDS)
	if phase == "windup":
		var started: int = int(state.get("phase_started", snapshot_tick))
		var duration: float = maxf(EnemyAnimation.TICK_SECONDS,
			float(int(state.get("phase_ends", snapshot_tick)) - started) * EnemyAnimation.TICK_SECONDS)
		var age: float = maxf(0.0, float(snapshot_tick - started) * EnemyAnimation.TICK_SECONDS) \
			+ clampf(since, 0.0, EnemyAnimation.MAX_EXTRAPOLATION)
		return WORK_ENERGY * (1.0 + 1.6 * clampf(age / duration, 0.0, 1.0))
	if phase == "firing":
		return WORK_ENERGY * 2.6
	return WORK_ENERGY * breath

## The Union optics' light for this frame. Red optics are the Union attack
## tell (art bible): steady at rest, a hard flash on the tick a tell starts,
## a swell to the shot and hot through the burst. The server starts a tell
## only with a free attack token, so a guard holding its lane while two others
## shoot keeps resting optics: on screen, lit optics are the attacks coming.
static func tell_glow(state: Dictionary, snapshot_tick: int, since: float) -> float:
	var phase: String = str(state.get("phase", ""))
	if phase == "windup":
		var started: int = int(state.get("phase_started", snapshot_tick))
		var duration: float = maxf(EnemyAnimation.TICK_SECONDS,
			float(int(state.get("phase_ends", snapshot_tick)) - started) * EnemyAnimation.TICK_SECONDS)
		var age: float = maxf(0.0, float(snapshot_tick - started) * EnemyAnimation.TICK_SECONDS) \
			+ clampf(since, 0.0, EnemyAnimation.MAX_EXTRAPOLATION)
		if age < OPTIC_FLASH_SECONDS:
			return OPTIC_FLASH
		return lerpf(OPTIC_SWELL, OPTIC_PEAK, clampf(age / duration, 0.0, 1.0))
	if phase == "firing":
		return OPTIC_FIRING
	return OPTIC_REST

## Absorbed gait progress in metres of stride, on the shared beat rather than
## the body's own travel. A Heavy steps on every other beat.
func shared_travel() -> float:
	var beats: float = 2.0 if _kind == "heavy_sweeper" else 1.0
	var stride: float = CrawlerAnimation.STRIDE_METRES if _kind == "crawler" else EnemyAnimation.STRIDE_METRES
	return fposmod(shared_seconds() / (SHARED_BEAT_SECONDS * beats), 1.0) * stride

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
	if paver_rig != null:
		paver_rig.advance(delta, distance >= 0.002 and distance < 2.0)
	if surveyor_rig != null:
		surveyor_rig.advance(delta)
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
	if _kind == "paver" and paver_rig != null:
		paver_rig.present(actor, tick, elapsed)
		return
	if _kind == "surveyor" and surveyor_rig != null:
		surveyor_rig.present(actor, tick, elapsed)
		return
	if _kind == "redactor":
		var material: ShaderMaterial = body.material_override as ShaderMaterial
		if material != null:
			var hidden_approach: bool = actor.get("phase") in ["idle", "moving"]
			material.set_shader_parameter("shimmer", 1.0 if hidden_approach else 0.0)
			material.set_shader_parameter("shimmer_tick", float(tick))
	var glow: ShaderMaterial = body.material_override as ShaderMaterial
	if glow != null and glow.shader == UNION_SPRITE:
		if absorbed:
			var energy: float = work_energy(actor, shared_seconds(), tick, elapsed)
			if tick >= signal_window.x and tick < signal_window.y and actor.get("phase") != "dead":
				var since: float = float(tick - signal_window.x) * EnemyAnimation.TICK_SECONDS + clampf(elapsed, 0.0, EnemyAnimation.MAX_EXTRAPOLATION)
				energy = WORK_ENERGY * (2.4 if M08Archive.noise_lit(since) else 0.1)
			glow.set_shader_parameter("work_energy", energy)
		else:
			glow.set_shader_parameter("red_glow", tell_glow(actor, tick, elapsed))
	var gait_travel: float = shared_travel() if absorbed else travel
	var facing: int = EnemyAnimation.direction(yaw, to_camera)
	if _kind == "notary":
		body.frame = NotaryAnimation.frame(actor, tick, elapsed, facing, _landed)
	elif _kind == "jammer":
		body.frame = JammerAnimation.frame(actor, tick, elapsed, facing)
	elif _kind == "crawler":
		body.frame = CrawlerAnimation.frame(actor, tick, elapsed, gait_travel, facing)
	elif _kind == "enforcer" and actor.get("phase") == "charging":
		body.frame = enforcer_charge_frame(travel, facing)
	else:
		var custody: int = custody_frame(actor, weapon, tick, elapsed, facing, _standing)
		body.frame = custody if custody >= 0 else EnemyAnimation.frame(actor, weapon, tick, elapsed,
			gait_travel, shot_age, facing, stepping)

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
