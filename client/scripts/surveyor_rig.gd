class_name SurveyorRig
extends Node3D

## The Surveyor's local mechanical mast rig: matte bone over ink joints with
## one muted cyan working indicator, per the art bible's restoration machines.
## Local +X is the server's forward; feet registration never bobs or scales.
##
## Swap seam: the generated production model drops in at SOURCE_SCENE. When it
## exists it replaces the placeholder body below; the lens, iris and
## indicator nodes are looked up by name in either form, so presentation of
## the authoritative phases does not change with the art.
const SOURCE_SCENE: String = "res://assets/models/surveyor.glb"
const BONE: Color = Color("d6d0c2")
const BONE_SHADE: Color = Color("a9a395")
const INK: Color = Color("202528")
## The art bible swatch, never brighter: restoration light is muted.
const CYAN: Color = Color("4a8a92")
const LENS_GLASS: Color = Color("cfe6e1")
## Lens centre above the feet, also the origin of the projected mark.
const LENS_HEIGHT: float = 2.05
const PETALS: int = 6

var phase: String = "idle"
var progress: float = 0.0
var aperture: float = 0.0
var _iris: Array[Node3D] = []
var _glass: MeshInstance3D
var _indicator: MeshInstance3D
var _head: Node3D
var _parts: Array[MeshInstance3D] = []
var _hit_material: StandardMaterial3D
var _scan: float = 0.0
var placeholder: bool = true

func _init() -> void:
	name = "SurveyorRig"
	if ResourceLoader.exists(SOURCE_SCENE):
		var packed: PackedScene = load(SOURCE_SCENE) as PackedScene
		if packed != null:
			var source: Node3D = packed.instantiate() as Node3D
			if source != null:
				source.name = "Source"
				add_child(source)
				placeholder = false
	if placeholder:
		_build_placeholder()
	_head = find_child("Head", true, false) as Node3D
	_glass = find_child("LensGlass", true, false) as MeshInstance3D
	_indicator = find_child("Indicator", true, false) as MeshInstance3D
	for index: int in range(PETALS):
		var petal: Node3D = find_child("IrisPetal%d" % index, true, false) as Node3D
		if petal != null:
			_iris.append(petal)
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		mesh.layers = ArenaSky.ACTOR_LAYERS
		_parts.append(mesh)
	_hit_material = StandardMaterial3D.new()
	_hit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hit_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hit_material.albedo_color = Color(1.0, 0.95, 0.85, 0.5)

## A tripod clamp, a slim mast, a yoke and a long head whose front is the
## lens: one continuous bone form with few seams, no face and no serials.
func _build_placeholder() -> void:
	for index: int in range(3):
		var leg: MeshInstance3D = part("Leg%d" % index, Vector3(1.15, 0.12, 0.16), Vector3.ZERO, INK)
		var angle: float = float(index) * TAU / 3.0 + 0.4
		leg.position = Vector3(cos(angle) * 0.46, 0.16, sin(angle) * 0.46)
		leg.rotation = Vector3(0.0, -angle, 0.3)
		add_child(leg)
		var foot: MeshInstance3D = part("Foot%d" % index, Vector3(0.22, 0.06, 0.22), Vector3(cos(angle) * 0.98, 0.03, sin(angle) * 0.98), INK)
		add_child(foot)
	add_child(cylinder("Clamp", 0.32, 0.38, 0.36, Vector3(0, 0.24, 0), BONE_SHADE))
	add_child(cylinder("Mast", 0.11, 0.13, 1.2, Vector3(0, 0.98, 0), BONE))
	add_child(cylinder("MastCollar", 0.17, 0.17, 0.1, Vector3(0, 1.58, 0), INK))
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0, LENS_HEIGHT, 0)
	add_child(_head)
	_head.add_child(part("Yoke", Vector3(0.24, 0.5, 0.86), Vector3(-0.12, -0.26, 0), INK))
	_head.add_child(part("Housing", Vector3(1.05, 0.62, 0.66), Vector3(0.05, 0.0, 0), BONE))
	_head.add_child(part("Brow", Vector3(0.92, 0.1, 0.72), Vector3(0.08, 0.35, 0), BONE_SHADE))
	_head.add_child(part("Tail", Vector3(0.32, 0.44, 0.52), Vector3(-0.56, -0.02, 0), BONE_SHADE))
	var rim: MeshInstance3D = cylinder("LensRim", 0.36, 0.36, 0.14, Vector3(0.62, 0.0, 0), INK)
	rim.rotation.z = PI * 0.5
	_head.add_child(rim)
	_glass = cylinder("LensGlass", 0.27, 0.27, 0.04, Vector3(0.7, 0.0, 0), LENS_GLASS, true)
	_glass.rotation.z = PI * 0.5
	_head.add_child(_glass)
	var iris: Node3D = Node3D.new()
	iris.name = "Iris"
	iris.position = Vector3(0.725, 0.0, 0)
	_head.add_child(iris)
	for index: int in range(PETALS):
		var hinge: Node3D = Node3D.new()
		hinge.name = "IrisPetal%d" % index
		hinge.rotation.x = float(index) * TAU / float(PETALS)
		var blade: MeshInstance3D = part("Blade", Vector3(0.02, 0.28, 0.16), Vector3(0, 0.14, 0), INK)
		hinge.add_child(blade)
		iris.add_child(hinge)
	# A muted cyan band around the housing: the one colour that reads from a
	# tower at range, steady while idle, brighter while observing.
	_indicator = part("Indicator", Vector3(0.06, 0.07, 0.68), Vector3(-0.38, 0.2, 0), CYAN, true)
	_head.add_child(_indicator)

func set_hit(active: bool) -> void:
	for mesh: MeshInstance3D in _parts:
		mesh.material_overlay = _hit_material if active else null

static func part(part_name: String, size: Vector3, offset: Vector3, colour: Color, glow: bool = false) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = part_name
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	node.mesh = box
	node.position = offset
	node.material_override = material(colour, glow)
	return node

static func cylinder(part_name: String, top: float, bottom: float, height: float, offset: Vector3, colour: Color, glow: bool = false) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = part_name
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	node.mesh = mesh
	node.position = offset
	node.material_override = material(colour, glow)
	return node

static func material(colour: Color, glow: bool) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = colour
	result.roughness = 0.92
	result.metallic = 0.0
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	result.emission_enabled = glow
	result.emission = colour if glow else Color.BLACK
	result.emission_energy_multiplier = 0.4
	return result

## Phase presentation only. Opening, projecting and recovery follow the
## authoritative phase window; nothing here can start or end a mark.
func present(actor: Dictionary, tick: int, elapsed: float) -> void:
	phase = str(actor.get("phase", "idle"))
	var started: int = int(actor.get("phase_started", tick))
	var duration: float = maxf(1.0, float(int(actor.get("phase_ends", tick)) - started))
	progress = clampf((float(tick - started) + minf(elapsed, 0.15) * 20.0) / duration, 0.0, 1.0)
	match phase:
		"windup": aperture = progress
		"firing": aperture = 1.0
		"recovery": aperture = 1.0 - progress
		_: aperture = 0.0
	for index: int in range(_iris.size()):
		# Petals fold outward from a closed shutter to a wide open lens.
		_iris[index].rotation.z = lerpf(0.0, 1.25, aperture)
		_iris[index].scale = Vector3.ONE * lerpf(1.0, 0.82, aperture)
	if _glass != null:
		var glass: StandardMaterial3D = _glass.material_override as StandardMaterial3D
		if glass != null:
			glass.emission_energy_multiplier = 0.0 if phase == "dead" else lerpf(0.15, 2.6, aperture)
	if _indicator != null:
		_indicator.visible = phase != "dead"
	if _head != null:
		# Dead: the head drops on its yoke. Hit: a short recoil.
		_head.rotation.z = -0.55 if phase == "dead" else (0.18 * (1.0 - progress) if phase == "hit" else 0.0)

func advance(delta: float) -> void:
	_scan = fposmod(_scan + clampf(delta, 0.0, 0.1) * 3.0, TAU)
	if _indicator != null:
		var lit: StandardMaterial3D = _indicator.material_override as StandardMaterial3D
		if lit != null:
			lit.emission_energy_multiplier = 0.25 + 0.2 * (0.5 + 0.5 * sin(_scan)) if phase in ["idle", "moving"] else 0.9
