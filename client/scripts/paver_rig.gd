class_name PaverRig
extends Node3D

## A broad matte restoration machine inside the server's 1.8 m fighter volume.
## Local +X is the server's forward; feet registration never bobs or scales.
## The phase poses read the authoritative windup (preparation) and firing
## (work) windows only; the strip itself is drawn by PaverStrips.
##
## Swap seam: when the generated Paver model is delivered, set MODEL_PATH to
## its scene. The rig then instances that scene in place of the placeholder
## parts and drives an optional AnimationPlayer with clips named after the
## server phases (idle, moving, windup, firing, recovery, hit, dead).
const MODEL_PATH: String = ""

## Matte off-white continuous body over ink joints, with no markings. The
## working indicators are the Inheritance's muted cyan, never a neon or a
## warm lamp: warm light belongs to free people. Only the projected strip
## (PaverStrips) is white work light.
const MATTE: Color = Color("bdb9ab")
const MATTE_SHADE: Color = Color("98958a")
const DARK: Color = Color("1f2326")
## Ink joints: a hard value break so the pale body never melts into pale
## concrete or plaster behind it.
const JOINT: Color = Color("2a2e31")
const WORK_CYAN: Color = Color("4a8a92")
const LENS: Color = WORK_CYAN
const LAMP: Color = WORK_CYAN
var phase: String = "idle"
var progress: float = 0.0
var model: Node3D
var _animation: AnimationPlayer
var _hull: Node3D
var _head: Node3D
var _pauldrons: Array[Node3D] = []
var _lens: MeshInstance3D
var _lamps: Array[MeshInstance3D] = []
var _treads: Array[MeshInstance3D] = []
var _vents: Array[MeshInstance3D] = []
var _parts: Array[MeshInstance3D] = []
var _hit_material: StandardMaterial3D
var _clock: float = 0.0
var _travel: float = 0.0
var _pulse: float = 0.0

func _init() -> void:
	name = "PaverRig"
	if not MODEL_PATH.is_empty() and ResourceLoader.exists(MODEL_PATH):
		var scene: Resource = load(MODEL_PATH)
		if scene is PackedScene:
			model = (scene as PackedScene).instantiate() as Node3D
			if model != null:
				model.name = "PaverModel"
				add_child(model)
				for node: Node in model.find_children("*", "AnimationPlayer", true, false):
					_animation = node as AnimationPlayer
					break
	if model == null:
		_build_placeholder()
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		_parts.append(node as MeshInstance3D)
		(node as MeshInstance3D).layers = ArenaSky.ACTOR_LAYERS
	_hit_material = StandardMaterial3D.new()
	_hit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hit_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hit_material.albedo_color = Color(1.0, 0.92, 0.8, 0.45)

func _build_placeholder() -> void:
	# Low tracked sledge, carrying a broad hull, two shoulder plates and a
	# projector head that leans toward the strip it is preparing.
	for side: float in [-1.0, 1.0]:
		var tread: MeshInstance3D = part("Tread", Vector3(1.04, 0.3, 0.24), Vector3(0.0, 0.15, side * 0.38), DARK)
		_treads.append(tread)
		add_child(tread)
		for index: int in range(5):
			add_child(part("TreadGuard", Vector3(0.16, 0.04, 0.27), Vector3(-0.4 + index * 0.2, 0.31, side * 0.38), JOINT))
	_hull = Node3D.new()
	_hull.name = "Hull"
	add_child(_hull)
	_hull.add_child(part("Chassis", Vector3(0.92, 0.18, 0.86), Vector3(0.0, 0.42, 0.0), JOINT))
	_hull.add_child(part("Body", Vector3(0.86, 0.78, 0.94), Vector3(-0.04, 0.9, 0.0), MATTE))
	_hull.add_child(part("BodyBand", Vector3(0.87, 0.08, 0.95), Vector3(-0.04, 0.66, 0.0), MATTE_SHADE))
	_hull.add_child(part("Brow", Vector3(0.62, 0.1, 0.9), Vector3(0.05, 1.32, 0.0), MATTE_SHADE))
	# Continuous surfaces with few breaks: one ink waist joint between the
	# body and its chassis, and an ink collar under the brow. No plates,
	# serials or markings; the dark joints carry the silhouette instead.
	_hull.add_child(part("WaistJoint", Vector3(0.9, 0.07, 0.98), Vector3(-0.04, 0.53, 0.0), JOINT))
	_hull.add_child(part("BrowJoint", Vector3(0.66, 0.05, 0.92), Vector3(0.05, 1.27, 0.0), JOINT))
	# The front work apron: a scraper blade that meets the floor it marks.
	var apron: MeshInstance3D = part("WorkApron", Vector3(0.08, 0.36, 0.98), Vector3(0.52, 0.32, 0.0), MATTE)
	apron.rotation.z = -0.32
	_hull.add_child(apron)
	for index: int in range(4):
		_hull.add_child(part("ApronRib", Vector3(0.085, 0.3, 0.05), Vector3(0.53, 0.33, -0.36 + index * 0.24), DARK))
	# Rear cooling grille: glows dull during recovery.
	for index: int in range(3):
		var vent: MeshInstance3D = part("RecoveryVent", Vector3(0.04, 0.42, 0.16), Vector3(-0.48, 0.92, -0.26 + index * 0.26), DARK, true)
		_vents.append(vent)
		_hull.add_child(vent)
	for side: float in [-1.0, 1.0]:
		var lamp: MeshInstance3D = part("WorkLamp", Vector3(0.12, 0.08, 0.04), Vector3(0.22, 1.08, side * 0.48), LAMP, true)
		_lamps.append(lamp)
		_hull.add_child(lamp)
		var pauldron: Node3D = Node3D.new()
		pauldron.name = "Pauldron"
		pauldron.position = Vector3(-0.02, 1.3, side * 0.46)
		pauldron.add_child(part("Plate", Vector3(0.62, 0.12, 0.34), Vector3(0.0, 0.04, side * 0.13), MATTE))
		pauldron.add_child(part("PlateEdge", Vector3(0.64, 0.05, 0.05), Vector3(0.0, 0.01, side * 0.3), DARK))
		pauldron.set_meta("side", side)
		_pauldrons.append(pauldron)
		_hull.add_child(pauldron)
	_head = Node3D.new()
	_head.name = "ProjectorHead"
	_head.position = Vector3(0.02, 1.42, 0.0)
	_hull.add_child(_head)
	_head.add_child(part("Neck", Vector3(0.18, 0.16, 0.2), Vector3(0.0, 0.06, 0.0), JOINT))
	_head.add_child(part("Housing", Vector3(0.42, 0.26, 0.5), Vector3(0.05, 0.24, 0.0), MATTE))
	_head.add_child(part("Hood", Vector3(0.46, 0.05, 0.54), Vector3(0.07, 0.38, 0.0), MATTE_SHADE))
	_lens = part("ProjectorLens", Vector3(0.05, 0.14, 0.38), Vector3(0.28, 0.22, 0.0), LENS, true)
	_head.add_child(_lens)
	for side: float in [-1.0, 1.0]:
		_head.add_child(part("LensCheek", Vector3(0.06, 0.2, 0.05), Vector3(0.27, 0.22, side * 0.22), DARK))

static func part(part_name: String, size: Vector3, offset: Vector3, colour: Color, glow: bool = false) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = part_name
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	node.mesh = box
	node.position = offset
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.94
	material.metallic = 0.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.emission_enabled = glow
	material.emission = colour if glow else Color.BLACK
	material.emission_energy_multiplier = 0.4
	node.material_override = material
	return node

func set_hit(active: bool) -> void:
	for node: MeshInstance3D in _parts:
		node.material_overlay = _hit_material if active else null

## Phase and progress through its authoritative window. A repeated snapshot
## never restarts the pose: progress follows the server tick, smoothed by
## at most one tick of presentation time.
func present(actor: Dictionary, tick: int, elapsed: float) -> void:
	phase = str(actor.get("phase", "idle"))
	var started: int = int(actor.get("phase_started", tick))
	var duration: float = maxf(1.0, float(int(actor.get("phase_ends", tick)) - started))
	var age: float = float(tick - started) + minf(elapsed, 0.05) * 20.0
	progress = clampf(age / duration, 0.0, 1.0)
	# Work pulses land every four ticks from the start of the work cycle.
	_pulse = 1.0 - fposmod(age, 4.0) / 4.0 if phase == "firing" else 0.0
	if _animation != null and _animation.has_animation(phase) and _animation.current_animation != phase:
		_animation.play(phase)
	_pose()

func advance(delta: float, moving: bool) -> void:
	var step: float = clampf(delta, 0.0, 0.1)
	_clock += step
	if moving:
		_travel = fposmod(_travel + step * 1.2, 1.0)
	_pose()

func _pose() -> void:
	if model != null or _hull == null:
		return
	var raised: float = 0.0
	match phase:
		"windup": raised = ease(progress, 0.6)
		"firing": raised = 1.0
		"recovery": raised = 1.0 - progress
	var dead: bool = phase == "dead"
	for pauldron: Node3D in _pauldrons:
		var side: float = float(pauldron.get_meta("side"))
		# The shoulder plates lift and open: the readable preparation tell.
		pauldron.rotation.x = side * (-0.62 * raised + (0.35 if dead else 0.0))
		pauldron.position.y = 1.3 + 0.08 * raised - (0.12 if dead else 0.0)
	_head.rotation.z = -0.42 * raised + (-0.5 if dead else 0.0)
	var judder: float = 0.0
	if phase == "firing":
		judder = _pulse * 0.025
	elif phase == "windup":
		judder = sin(_clock * 55.0) * 0.004 * raised
	_hull.position = Vector3(-judder, 0.0, 0.0)
	_hull.rotation.z = 0.12 if phase == "hit" else (0.38 if dead else 0.0)
	_hull.position.y = -0.18 if dead else 0.0
	var lens: StandardMaterial3D = _lens.material_override as StandardMaterial3D
	var energy: float = 0.25
	match phase:
		"windup": energy = 0.4 + 2.2 * raised + 0.4 * sin(_clock * 18.0) * raised
		"firing": energy = 1.6 + 2.4 * _pulse
		"hit": energy = 0.1 if fmod(_clock, 0.18) < 0.09 else 0.8
		"dead": energy = 0.0
	lens.emission_energy_multiplier = energy
	for lamp: MeshInstance3D in _lamps:
		(lamp.material_override as StandardMaterial3D).emission_energy_multiplier = 0.0 if dead else 0.6
	for vent: MeshInstance3D in _vents:
		var vent_material: StandardMaterial3D = vent.material_override as StandardMaterial3D
		vent_material.emission = WORK_CYAN if phase == "recovery" else Color.BLACK
		vent_material.emission_energy_multiplier = 0.5 * (1.0 - progress) if phase == "recovery" else 0.0
	for tread: MeshInstance3D in _treads:
		tread.position.x = sin(_travel * TAU) * 0.01
