class_name JeepView
extends Node3D

## Development rig for the vehicle seam. A prepared, inspected model replaces
## the chassis at MODEL_PATH; this rig keeps registered wheels and gun motion.
const MODEL_PATH: String = "res://assets/vehicles/jeep.tscn"
const MODELS: Dictionary = {"jeep": MODEL_PATH, "boat": "res://assets/vehicles/boat.tscn", "light_aircraft": "res://assets/vehicles/light_aircraft.tscn"}
var kind: String = "jeep"
var wheels: Array[Node3D] = []
var gun: Node3D
var barrel: MeshInstance3D
var lamp: OmniLight3D
var smoke: Array[MeshInstance3D] = []
var speed: float = 0.0
var heat: float = 0.0
var burning: bool = false
var wreck: bool = false
var _age: float = 0.0
var _flash_left: float = 0.0
var uses_prepared_model: bool = false
var occupied: bool = false
var engine: VehicleAudio
var propeller: Node3D

func _ready() -> void:
	if kind == "boat":
		add_to_group("island_water_wakes")
	engine = VehicleAudio.new()
	engine.name = "Engine"
	add_child(engine)
	var model_path: String = str(MODELS.get(kind, ""))
	if ResourceLoader.exists(model_path):
		var scene: PackedScene = load(model_path) as PackedScene
		if scene != null:
			var model: Node = scene.instantiate()
			add_child(model)
			_apply_model_materials(model)
			uses_prepared_model = true
			propeller = model.find_child("Propeller", true, false) as Node3D
			for index: int in range(4):
				var wheel: Node3D = model.find_child("Wheel%d" % index, true, false) as Node3D
				if wheel != null:
					wheels.append(wheel)
	if not uses_prepared_model:
		if kind == "jeep":
			_build_development_chassis()
		else:
			_build_development_transport()
	if kind != "light_aircraft":
		_build_gun()
	for index: int in range(6):
		var puff: MeshInstance3D = _box(self, "Smoke%d" % index, Vector3.ZERO,
			Vector3.ONE * 0.25, _material(Color("342b25")))
		puff.visible = false
		smoke.append(puff)

static func _apply_model_materials(model: Node) -> void:
	# glTF does not retain every renderer-specific sampler/material property.
	# Apply the same matte nearest-filter treatment to every registered part.
	for item: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = item as MeshInstance3D
		for surface: int in range(mesh.mesh.get_surface_count()):
			var source: Material = mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D = source.duplicate() as StandardMaterial3D
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				material.roughness = 1.0
				material.metallic = 0.0
				material.metallic_specular = 0.0
				mesh.set_surface_override_material(surface, material)

static func _material(colour: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material

static func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

func _build_development_chassis() -> void:
	var paint: Material = _material(Color("b5a98a"))
	var steel: Material = _material(Color("424a45"))
	var rubber: Material = _material(Color("242625"))
	var leather: Material = _material(Color("6b4935"))
	var light: Material = _material(Color("e9d9a8"))
	_box(self, "Frame", Vector3(0, 0.47, 0), Vector3(3.65, 0.25, 1.46), steel)
	_box(self, "RearBed", Vector3(-1.0, 0.79, 0), Vector3(1.55, 0.25, 1.45), paint)
	_box(self, "Hood", Vector3(1.18, 1.0, 0), Vector3(1.22, 0.43, 1.4), paint)
	_box(self, "Grille", Vector3(1.81, 0.96, 0), Vector3(0.10, 0.36, 1.38), steel)
	_box(self, "Bumper", Vector3(1.86, 0.53, 0), Vector3(0.08, 0.12, 1.85), steel)
	_box(self, "Tailgate", Vector3(-1.82, 1.0, 0), Vector3(0.12, 0.6, 1.46), paint)
	for side: float in [-1.0, 1.0]:
		_box(self, "SideRail", Vector3(-0.92, 1.03, side * 0.7), Vector3(1.8, 0.35, 0.10), paint)
		_box(self, "CabStep", Vector3(0.14, 0.48, side * 0.81), Vector3(0.92, 0.1, 0.2), steel)
		_box(self, "Headlight", Vector3(1.872, 1.04, side * 0.51), Vector3(0.035, 0.20, 0.22), light)
		_box(self, "WindshieldPost", Vector3(0.67, 1.63, side * 0.65), Vector3(0.07, 0.8, 0.07), steel)
		_box(self, "SeatBase", Vector3(0.13, 0.77, side * 0.37), Vector3(0.60, 0.19, 0.49), leather)
		_box(self, "SeatBack", Vector3(-0.15, 1.06, side * 0.37), Vector3(0.12, 0.66, 0.49), leather)
		for axle: float in [-1.15, 1.18]:
			var wheel: Node3D = Node3D.new()
			wheel.position = Vector3(axle, 0.45, side * 0.8)
			add_child(wheel)
			var tire: MeshInstance3D = MeshInstance3D.new()
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = 0.45
			cylinder.bottom_radius = 0.45
			cylinder.height = 0.27
			cylinder.radial_segments = 12
			tire.mesh = cylinder
			tire.material_override = rubber
			tire.rotation.x = PI * 0.5
			wheel.add_child(tire)
			_box(wheel, "Hub", Vector3(0, 0, side * 0.15), Vector3(0.23, 0.23, 0.035), steel)
			wheels.append(wheel)
	_box(self, "WindshieldTop", Vector3(0.67, 2.01, 0), Vector3(0.07, 0.07, 1.37), steel)
	_box(self, "Dashboard", Vector3(0.49, 1.24, 0), Vector3(0.17, 0.19, 1.28), steel)
	_box(self, "GaugePlate", Vector3(0.395, 1.26, -0.39), Vector3(0.015, 0.09, 0.21), light)
	_box(self, "Rollbar", Vector3(-0.46, 1.97, 0), Vector3(0.09, 0.09, 1.46), steel)
	for side: float in [-0.7, 0.7]:
		_box(self, "RollbarFoot", Vector3(-0.46, 1.47, side), Vector3(0.09, 1.0, 0.09), steel)

func _build_gun() -> void:
	var steel: Material = _material(Color("414744"))
	var mount_x: float = -1.0 if kind == "boat" else -0.65
	if find_child("GunPedestal", true, false) == null:
		_box(self, "GunPedestal", Vector3(mount_x, 1.43, 0), Vector3(0.16, 1.72, 0.16), steel)
		_box(self, "MountFoot", Vector3(mount_x, 0.58, 0), Vector3(0.43, 0.08, 0.43), steel)
	else:
		_box(self, "MountBridge", Vector3(mount_x, 2.26, 0), Vector3(0.12, 0.16, 0.12), steel)
	gun = Node3D.new()
	gun.name = "MountedGun"
	# Keep the receiver below the authoritative eye ray so the gunner camera
	# cannot sit inside it. The trace remains the server's resolved geometry.
	gun.position = Vector3(mount_x, 2.33, 0)
	add_child(gun)
	_box(gun, "Receiver", Vector3(0.14, 0, 0), Vector3(0.56, 0.19, 0.2), steel)
	barrel = _box(gun, "Barrel", Vector3(0.65, 0, 0), Vector3(0.68, 0.085, 0.085), _material(Color("282d2b")))
	_box(gun, "Handle", Vector3(-0.23, -0.1, 0), Vector3(0.1, 0.19, 0.29), steel)
	_box(gun, "FeedBox", Vector3(0.03, -0.05, 0.2), Vector3(0.27, 0.29, 0.18), _material(Color("74765a")))
	_box(gun, "FeedLid", Vector3(0.03, 0.12, 0.2), Vector3(0.3, 0.035, 0.2), steel)
	for index: int in range(3):
		_box(gun, "BarrelCollar%d" % index, Vector3(0.40 + index * 0.17, 0, 0), Vector3(0.045, 0.12, 0.12), steel)
	_box(gun, "MuzzleCap", Vector3(0.997, 0, 0), Vector3(0.055, 0.115, 0.115), steel)
	_box(gun, "MuzzleBore", Vector3(1.027, 0, 0), Vector3(0.005, 0.065, 0.065), _material(Color("151a18")))
	lamp = OmniLight3D.new()
	lamp.position = Vector3(1.0, 0, 0)
	lamp.omni_range = 4.0
	lamp.light_color = Color("ffba6b")
	lamp.light_energy = 0.0
	gun.add_child(lamp)

func _build_development_transport() -> void:
	var paint: Material = _material(Color("a1ac98"))
	var steel: Material = _material(Color("3f5350"))
	if kind == "boat":
		_box(self, "DevelopmentHull", Vector3(0, 0.35, 0), Vector3(4.8, 0.7, 2.2), paint)
		for side: float in [-1, 1]:
			_box(self, "Gunwale", Vector3(0, 0.9, side), Vector3(4.4, 0.4, 0.16), steel)
		_box(self, "Wheelhouse", Vector3(1.0, 1.05, 0), Vector3(0.25, 0.7, 1.3), steel)
	else:
		_box(self, "DevelopmentFuselage", Vector3(0, 0.7, 0), Vector3(8, 1.3, 1.1), paint)
		_box(self, "Wing", Vector3(0.4, 0.7, 0), Vector3(1.8, 0.12, 9.2), steel)
		_box(self, "Tailplane", Vector3(-3.4, 1, 0), Vector3(1.0, 0.12, 3.5), steel)

func apply(row: Dictionary, aim_yaw: float, aim_pitch: float) -> void:
	speed = float(row["speed"])
	heat = float(row["gun_heat"])
	burning = int(row["burning_ticks"]) > 0
	wreck = int(row["hp"]) == 0
	occupied = row["driver"] != null or row["gunner"] != null
	if gun != null:
		gun.rotation = Vector3(0.0, ServerYaw.pawn_rotation_y(aim_yaw - float(row["yaw"])), aim_pitch)
	if barrel != null:
		var material: StandardMaterial3D = barrel.material_override as StandardMaterial3D
		material.albedo_color = Color("282d2b").lerp(Color("db6031"), heat)
		material.emission_enabled = heat > 0.6
		material.emission = Color("cc4121") * maxf(0.0, heat - 0.6)

func shot() -> void:
	_flash_left = 0.06

func _process(delta: float) -> void:
	_age += delta
	var listener: Camera3D = get_viewport().get_camera_3d()
	engine.apply(kind, speed, occupied, wreck, listener != null and global_position.distance_squared_to(listener.global_position) < 4900)
	_flash_left = maxf(0.0, _flash_left - delta)
	for wheel: Node3D in wheels:
		wheel.rotation.z -= speed * delta / 0.45
	if propeller != null and occupied and not wreck:
		propeller.rotation.x = fmod(propeller.rotation.x + delta * (18.0 + absf(speed) * 1.8), TAU)
	if lamp != null:
		lamp.light_energy = 2.5 if _flash_left > 0.0 else 0.0
	for index: int in range(smoke.size()):
		var puff: MeshInstance3D = smoke[index]
		puff.visible = burning
		if burning:
			var phase: float = fmod(_age * 0.7 + float(index) / smoke.size(), 1.0)
			puff.position = Vector3(1.1 + sin(index * 2.3 + _age) * phase * 0.3, 1.1 + phase * 2.6, cos(index * 1.7) * phase * 0.4)
			puff.scale = Vector3.ONE * (0.4 + phase * 2.0)
