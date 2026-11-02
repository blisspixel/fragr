class_name JetpackRig
extends Node3D

## The coalition jetpack worn on a fighter's back, with its visible flame.
## Local +X is the wearer's forward (the pawn applies server yaw); the rig's
## origin is the wearer's feet. Presentation only: fuel and thrust come from
## the snapshot's `jetpacks` facts.
##
## Swap seam: MODEL_PATH names the prepared pack scene
## (`tools/prepare_jetpack_source.gd`, receipt beside it). It replaces the
## placeholder pack; its "NozzleLeft" and "NozzleRight" nodes anchor the
## flames, and the fuel gauge stays a local overlay on its frame. An empty or
## missing path falls back to the placeholder.
const MODEL_PATH: String = "res://assets/models/jetpack.glb"
## Where the gauge window sits on the prepared pack's rear panel, facing
## whoever follows the wearer.
const MODEL_GAUGE: Vector3 = Vector3(-0.19, 0.08, 0.0)

const SHELL: Color = Color("7b8a7a")
const FRAME: Color = Color("33393a")
const STRAP: Color = Color("4e463b")
const BRASS: Color = Color("a8864f")
const FLAME_CORE: Color = Color("fff1c8")
const FLAME_EDGE: Color = Color("f08a3a")
## The pack sits between the shoulder blades of a 1.8 m fighter.
const BACK_OFFSET: Vector3 = Vector3(-0.27, 1.12, 0.0)
const FLAME_LENGTH: float = 0.85
## The plume lingers this long after a burn so a short tap still reads.
const FLAME_TAIL: float = 0.18

var thrusting: bool = false
var fuel_fraction: float = 1.0
var model: Node3D
var _flames: Array[MeshInstance3D] = []
var _flame_light: OmniLight3D
var _hiss: AudioStreamPlayer3D
var _gauge: MeshInstance3D
var _clock: float = 0.0
var _heat: float = 0.0
var _tail: float = 0.0

func _init() -> void:
	name = "JetpackRig"
	var anchors: Array[Vector3] = [Vector3(-0.1, -0.32, -0.12), Vector3(-0.1, -0.32, 0.12)]
	model = pack_model()
	var pack: Node3D = Node3D.new()
	pack.name = "Pack"
	pack.position = BACK_OFFSET
	add_child(pack)
	if model != null:
		pack.add_child(model)
		for index: int in range(2):
			var nozzle: Node3D = model.find_child(["NozzleLeft", "NozzleRight"][index], true, false) as Node3D
			if nozzle != null:
				anchors[index] = pack.to_local(nozzle.global_position) if nozzle.is_inside_tree() else nozzle.position
		_gauge = PaverRig.part("Gauge", Vector3(0.02, 0.12, 0.04), MODEL_GAUGE, BRASS, true)
		pack.add_child(_gauge)
	else:
		_gauge = build_placeholder(pack)
	for anchor: Vector3 in anchors:
		var flame: MeshInstance3D = MeshInstance3D.new()
		flame.name = "Flame"
		var cone: CylinderMesh = CylinderMesh.new()
		cone.top_radius = 0.09
		cone.bottom_radius = 0.0
		cone.height = FLAME_LENGTH
		cone.radial_segments = 8
		cone.rings = 1
		flame.mesh = cone
		flame.position = anchor + Vector3(0.0, -0.28, 0.0)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(FLAME_EDGE, 0.85)
		material.emission_enabled = true
		material.emission = FLAME_CORE
		material.emission_energy_multiplier = 3.0
		flame.material_override = material
		# A white-hot inner core, shorter than the plume.
		var core: MeshInstance3D = MeshInstance3D.new()
		core.name = "FlameCore"
		var inner: CylinderMesh = CylinderMesh.new()
		inner.top_radius = 0.045
		inner.bottom_radius = 0.0
		inner.height = FLAME_LENGTH * 0.5
		inner.radial_segments = 6
		inner.rings = 1
		core.mesh = inner
		core.position.y = FLAME_LENGTH * 0.25
		var hot: StandardMaterial3D = material.duplicate() as StandardMaterial3D
		hot.albedo_color = Color(FLAME_CORE, 1.0)
		hot.emission_energy_multiplier = 6.0
		core.material_override = hot
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.add_child(core)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.visible = false
		pack.add_child(flame)
		_flames.append(flame)
	_flame_light = OmniLight3D.new()
	_flame_light.name = "FlameLight"
	_flame_light.light_color = Color("ffb36b")
	_flame_light.omni_range = 4.5
	_flame_light.light_energy = 0.0
	_flame_light.shadow_enabled = false
	_flame_light.position = BACK_OFFSET + Vector3(-0.1, -0.7, 0.0)
	add_child(_flame_light)
	_hiss = AudioStreamPlayer3D.new()
	_hiss.name = "ThrustHiss"
	_hiss.stream = WorksAudio.jet_thrust()
	_hiss.bus = &"Effects"
	_hiss.unit_size = 5.0
	_hiss.max_distance = 30.0
	_hiss.position = BACK_OFFSET
	add_child(_hiss)
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).layers = ArenaSky.ACTOR_LAYERS

## The prepared pack scene, or null when MODEL_PATH is empty or missing.
static func pack_model() -> Node3D:
	if MODEL_PATH.is_empty() or not ResourceLoader.exists(MODEL_PATH):
		return null
	var scene: Resource = load(MODEL_PATH)
	if not scene is PackedScene:
		return null
	var node: Node3D = (scene as PackedScene).instantiate() as Node3D
	if node == null:
		return null
	node.name = "JetpackModel"
	# Painted pixel clusters stay crisp at any distance.
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var surface: MeshInstance3D = child as MeshInstance3D
		for index: int in range(surface.get_surface_override_material_count()):
			var finish: BaseMaterial3D = surface.get_active_material(index) as BaseMaterial3D
			if finish != null:
				finish.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return node

## An unworn pack for the stores racks: the same model, no flame or gauge
## light. Its origin is the pack's centre, harness toward local +X.
static func spare() -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "SparePack"
	var pack_scene: Node3D = pack_model()
	if pack_scene != null:
		node.add_child(pack_scene)
	else:
		build_placeholder(node)
	return node

## The placeholder pack; returns its fuel gauge window.
static func build_placeholder(pack: Node3D) -> MeshInstance3D:
	pack.add_child(PaverRig.part("Frame", Vector3(0.08, 0.62, 0.42), Vector3(0.05, 0.0, 0.0), FRAME))
	for side: float in [-1.0, 1.0]:
		var tank: MeshInstance3D = MeshInstance3D.new()
		tank.name = "Canister"
		var body: CylinderMesh = CylinderMesh.new()
		body.top_radius = 0.1
		body.bottom_radius = 0.1
		body.height = 0.56
		body.radial_segments = 10
		tank.mesh = body
		tank.position = Vector3(-0.1, 0.0, side * 0.12)
		var finish: StandardMaterial3D = StandardMaterial3D.new()
		finish.albedo_color = SHELL
		finish.roughness = 0.8
		tank.material_override = finish
		pack.add_child(tank)
		pack.add_child(PaverRig.part("CanisterCap", Vector3(0.14, 0.05, 0.14), Vector3(-0.1, 0.3, side * 0.12), BRASS))
		pack.add_child(PaverRig.part("Nozzle", Vector3(0.12, 0.08, 0.12), Vector3(-0.1, -0.32, side * 0.12), FRAME))
		pack.add_child(PaverRig.part("Strap", Vector3(0.38, 0.06, 0.05), Vector3(0.18, 0.18, side * 0.17), STRAP))
	# A single amber gauge window on the frame reads fuel to teammates.
	var gauge: MeshInstance3D = PaverRig.part("Gauge", Vector3(0.03, 0.2, 0.05), Vector3(-0.21, 0.02, 0.0), BRASS, true)
	pack.add_child(gauge)
	return gauge

func apply(fact: Dictionary, fuel_max: float) -> void:
	thrusting = bool(fact.get("thrusting", false))
	fuel_fraction = clampf(float(fact.get("fuel", 0)) / maxf(1.0, fuel_max), 0.0, 1.0)
	if _gauge != null:
		var finish: StandardMaterial3D = _gauge.material_override as StandardMaterial3D
		finish.emission_energy_multiplier = 0.2 + 1.4 * fuel_fraction
		_gauge.scale.y = maxf(0.1, fuel_fraction)
	if thrusting and not _hiss.playing and is_inside_tree() and not get_tree().has_meta("fragr_automated"):
		_hiss.play()
	elif not thrusting and _hiss.playing:
		_hiss.stop()

func _process(delta: float) -> void:
	_clock += clampf(delta, 0.0, 0.1)
	_tail = FLAME_TAIL if thrusting else maxf(0.0, _tail - delta)
	var burning: bool = thrusting or _tail > 0.0
	_heat = move_toward(_heat, 1.0 if burning else 0.0, delta * (12.0 if burning else 5.0))
	var flicker: float = 0.82 + 0.18 * sin(_clock * 47.0) * sin(_clock * 23.0 + 1.3)
	for index: int in range(_flames.size()):
		var flame: MeshInstance3D = _flames[index]
		flame.visible = _heat > 0.02
		var length: float = _heat * flicker * (1.0 + 0.08 * float(index))
		flame.scale = Vector3(0.7 + 0.3 * _heat, maxf(0.05, length), 0.7 + 0.3 * _heat)
		flame.position.y = -0.32 - FLAME_LENGTH * 0.5 * length
	_flame_light.light_energy = 2.4 * _heat * flicker
