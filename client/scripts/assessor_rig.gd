class_name AssessorRig
extends Node3D

## Authored mechanical parts in the actual 2.6 m by 1.2 m target volume.
## Local +X is the server's forward. Feet registration never bobs or scales.
const METAL: Color = Color("3b4146")
const PLATE: Color = Color("6f746a")
const RED: Color = Color("d74932")
const LIGHT: Color = Color("f1cda0")
var fans: Array[Node3D] = []
var optics: Array[MeshInstance3D] = []
var vents: Array[MeshInstance3D] = []
var launcher: Node3D
var phase: String = "idle"
var progress: float = 0.0
var spin: float = 0.0
var _parts: Array[MeshInstance3D] = []
var _hit_material: StandardMaterial3D

func _init() -> void:
	name = "AssessorRig"
	add_child(part("Hull", Vector3(1.7, 0.58, 1.48), Vector3(0, 0.56, 0), METAL))
	add_child(part("UndersidePlate", Vector3(1.65, 0.14, 1.45), Vector3(0, 0.07, 0), PLATE))
	add_child(part("FrontPlate", Vector3(0.16, 0.61, 1.2), Vector3(0.88, 0.52, 0), PLATE))
	for x: float in [-0.78, 0.78]:
		for z: float in [-0.78, 0.78]:
			var fan: Node3D = Node3D.new()
			fan.position = Vector3(x, 0.44, z)
			var shroud: MeshInstance3D = part("Shroud", Vector3.ONE, Vector3.ZERO, PLATE)
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = 0.43
			cylinder.bottom_radius = 0.43
			cylinder.height = 0.24
			cylinder.radial_segments = 12
			cylinder.rings = 1
			shroud.mesh = cylinder
			fan.add_child(shroud)
			for side: float in [-1.0,1.0]:
				var inset: MeshInstance3D = part("FanIntake",Vector3.ONE,Vector3(0,side*0.125,0),Color("14191e"))
				var disc: CylinderMesh = CylinderMesh.new()
				disc.top_radius = 0.34
				disc.bottom_radius = 0.34
				disc.height = 0.012
				disc.radial_segments = 12
				disc.rings = 1
				inset.mesh = disc
				fan.add_child(inset)
			var rotor: Node3D = Node3D.new()
			rotor.name = "Rotor"
			rotor.position.y = 0.14
			for index: int in range(3):
				var blade: MeshInstance3D = part("Blade%d" % index, Vector3(0.68, 0.035, 0.09), Vector3.ZERO, Color("a4a493"))
				blade.rotation.y = float(index) * TAU / 3.0
				rotor.add_child(blade)
			fan.add_child(rotor)
			fans.append(rotor)
			add_child(fan)
	for z: float in [-0.28, 0.28]:
		var optic: MeshInstance3D = part("CountdownOptic", Vector3(0.1, 0.2, 0.2), Vector3(1.02, 0.76, z), RED, true)
		optics.append(optic)
		add_child(optic)
	for z: float in [-0.42, 0.0, 0.42]:
		var vent: MeshInstance3D = part("RecoveryVent", Vector3(0.045, 0.32, 0.16), Vector3(-0.87, 0.59, z), METAL, true)
		vents.append(vent)
		add_child(vent)
	launcher = Node3D.new()
	launcher.name = "FoldingLauncher"
	launcher.position = Vector3(0.5, 0.3, 0)
	launcher.add_child(part("Launcher", Vector3(0.62, 0.18, 0.52), Vector3(0.31, 0.0, 0), PLATE))
	for z: float in [-0.13, 0.0, 0.13]:
		launcher.add_child(part("Tube", Vector3(0.12, 0.11, 0.095), Vector3(0.62, 0.0, z), Color("14191e")))
	add_child(launcher)
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		_parts.append(node as MeshInstance3D)
	_hit_material = StandardMaterial3D.new()
	_hit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hit_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hit_material.albedo_color = Color(1.0, 0.3, 0.18, 0.55)

func set_hit(active: bool) -> void:
	for part: MeshInstance3D in _parts:
		part.material_overlay = _hit_material if active else null

static func part(part_name: String, size: Vector3, offset: Vector3, colour: Color, glow: bool = false) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = part_name
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	node.mesh = box
	node.position = offset
	node.layers = ArenaSky.ACTOR_LAYERS
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	material.metallic = 0.05
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.emission_enabled = glow
	material.emission = colour if glow else Color.BLACK
	material.emission_energy_multiplier = 0.65
	node.material_override = material
	return node

func present(actor: Dictionary, tick: int, elapsed: float) -> void:
	phase = str(actor.get("phase", "idle"))
	var duration: float = maxf(1.0, float(int(actor.get("phase_ends", tick)) - int(actor.get("phase_started", tick))))
	progress = clampf((float(tick - int(actor.get("phase_started", tick))) + minf(elapsed, 0.15) * 20.0) / duration, 0.0, 1.0)
	var raised: float = progress if phase == "windup" else (1.0 if phase == "firing" else (1.0 - progress if phase == "recovery" else 0.0))
	launcher.rotation.z = lerpf(0.9, -0.22, raised)
	for index: int in range(optics.size()):
		# Visible optic area grows through the locked countdown and closes at death.
		optics[index].scale.y = 0.25 if phase == "dead" else (1.0 + raised * (1.0 if index == 0 else 0.6))
		(optics[index].material_override as StandardMaterial3D).emission_energy_multiplier = 0.0 if phase == "dead" else (1.5 if phase == "windup" else 0.65)
	for vent: MeshInstance3D in vents:
		vent.scale.y = 1.0 if phase == "recovery" else 0.18
		var material: StandardMaterial3D = vent.material_override as StandardMaterial3D
		material.albedo_color = LIGHT if phase == "recovery" else METAL
		material.emission = LIGHT if phase == "recovery" else Color.BLACK
		material.emission_energy_multiplier = 0.8 if phase == "recovery" else 0.0

func advance(delta: float) -> void:
	spin = fposmod(spin + clampf(delta, 0.0, 0.1) * (2.0 if phase == "dead" else (26.0 if phase == "windup" else 18.0)), TAU)
	for index: int in range(fans.size()):
		fans[index].rotation.y = spin * (-1.0 if index % 2 == 0 else 1.0)
