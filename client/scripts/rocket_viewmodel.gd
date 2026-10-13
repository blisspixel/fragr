class_name RocketViewmodel
extends SubViewport

## Original development tube, rendered once with the same chunky geometry as
## world equipment. No ray, inventory, or projectile outcome is decided here.
const SIZE := Vector2i(224, 160)
var camera: Camera3D
var muzzle := Vector3(0.0, 0.04, -0.88)

func _init() -> void:
	size = SIZE
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ONCE

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8b29d")
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_energy = 1.15
	add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.18
	camera.position = Vector3(1.3,0.7,1.8)
	add_child(camera)
	camera.look_at(Vector3(0.0,-0.10,-0.25))
	camera.current = true
	_tube("LaunchTube", Vector3(0,0.04,-0.22),0.16,1.28,Color("666c4d"))
	_tube("ForwardCollar", Vector3(0,0.04,-0.80),0.185,0.12,Color("92917b"))
	_tube("RearCollar", Vector3(0,0.04,0.38),0.195,0.16,Color("454e44"))
	_tube("RearOpening", Vector3(0,0.04,0.468),0.145,0.016,Color("161d1b"))
	_box("HeatShield",Vector3(0,-0.11,-0.20),Vector3(0.32,0.09,0.68),Color("303a34"))
	_box("SightRail",Vector3(0,0.22,-0.33),Vector3(0.075,0.045,0.65),Color("252d2a"))
	_box("FrontSight",Vector3(0,0.29,-0.63),Vector3(0.035,0.15,0.04),Color("9a9780"))
	_box("RearSight",Vector3(0,0.27,-0.03),Vector3(0.11,0.085,0.045),Color("555e50"))
	_box("Grip",Vector3(0,-0.28,0.12),Vector3(0.11,0.34,0.14),Color("282e29"))
	_box("SupportGlove",Vector3(0.12,-0.19,-0.40),Vector3(0.21,0.21,0.25),Color("6c5540"))
	_box("SupportCuff",Vector3(0.24,-0.57,-0.30),Vector3(0.22,0.71,0.26),Color("49483b"))
	_box("TriggerGlove",Vector3(0.09,-0.30,0.14),Vector3(0.18,0.22,0.23),Color("796147"))
	_box("TriggerCuff",Vector3(0.20,-0.54,0.25),Vector3(0.25,0.38,0.26),Color("505143"))

func muzzle_pixel() -> Vector2:
	return camera.unproject_position(muzzle) if camera != null else Vector2(112,28)

func _part(label: String, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	part.material_override = material
	add_child(part)
	return part

func _tube(label: String, at: Vector3, radius: float, length: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 8
	mesh.rings = 1
	_part(label,mesh,at,color).rotation.x = PI*0.5

func _box(label: String, at: Vector3, size_at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size_at
	_part(label,mesh,at,color)
