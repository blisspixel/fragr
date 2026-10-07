class_name IslandWater
extends Node3D

## One opaque material, one static depth texture, bounded nearby boat wakes.
## The authoritative water level stays flat. Waves never change collision.
const SHADER: Shader = preload("res://assets/shaders/holdfast_ocean.gdshader")
const DEPTH_SIZE: int = 512
const WAKE_LIMITS: Array[int] = [2, 4, 8]
var material: ShaderMaterial
var quality: int = 1
var _wake_clock: float = 0.0
var _patches: Array[MeshInstance3D] = []

func build(info: Dictionary) -> void:
	if not WaterRegions.validation_error(info).is_empty() or info.get("water_regions", []).is_empty():
		return
	name = "IslandWater"
	add_to_group("island_water")
	var half: float = float(info["half_extent"])
	var level: float = float(info["water_regions"][0]["level"])
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("map_half", half)
	material.set_shader_parameter("coast_depth", _depth_texture(info, level))
	for region: Dictionary in info["water_regions"]:
		_patch(Vector2(region["min"][0], region["min"][1]), Vector2(region["max"][0], region["max"][1]), float(region["level"]))
	# Decorative ocean outside the playable boundary shares the same level and
	# shader. Bounds still come from the server, never these distant surfaces.
	var far: float = half + 4000.0
	_patch(Vector2(-far, -far), Vector2(-half, far), level)
	_patch(Vector2(half, -far), Vector2(far, far), level)
	_patch(Vector2(-half, -far), Vector2(half, -half), level)
	_patch(Vector2(-half, half), Vector2(half, far), level)
	apply_quality(quality)

func _patch(low: Vector2, high: Vector2, level: float) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = high - low
	mesh.subdivide_width = clampi(ceili(mesh.size.x / 12.0), 1, 48)
	mesh.subdivide_depth = clampi(ceili(mesh.size.y / 12.0), 1, 48)
	node.mesh = mesh
	node.material_override = material
	node.position = Vector3((low.x + high.x) * 0.5, level, (low.y + high.y) * 0.5)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 0.15
	add_child(node)
	_patches.append(node)

static func _depth_texture(info: Dictionary, level: float) -> ImageTexture:
	var half: float = float(info["half_extent"])
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(DEPTH_SIZE * DEPTH_SIZE)
	# Rasterize each solid once at map load. Registered land and submerged
	# beach steps supply the same shore shape that collision uses.
	for solid: Dictionary in info["solids"]:
		var x0: int = clampi(floori((float(solid["min_x"]) + half) / (half * 2.0) * DEPTH_SIZE), 0, DEPTH_SIZE - 1)
		var x1: int = clampi(ceili((float(solid["max_x"]) + half) / (half * 2.0) * DEPTH_SIZE), 0, DEPTH_SIZE)
		var z0: int = clampi(floori((float(solid["min_z"]) + half) / (half * 2.0) * DEPTH_SIZE), 0, DEPTH_SIZE - 1)
		var z1: int = clampi(ceili((float(solid["max_z"]) + half) / (half * 2.0) * DEPTH_SIZE), 0, DEPTH_SIZE)
		var top: float = minf(level, float(solid["top"]))
		for z: int in range(z0, z1):
			for x: int in range(x0, x1):
				var index: int = z * DEPTH_SIZE + x
				heights[index] = maxf(heights[index], top)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(DEPTH_SIZE * DEPTH_SIZE)
	for index: int in range(bytes.size()):
		bytes[index] = clampi(roundi((level - heights[index]) / 4.0 * 255.0), 0, 255)
	return ImageTexture.create_from_image(Image.create_from_data(DEPTH_SIZE, DEPTH_SIZE, false, Image.FORMAT_R8, bytes))

func apply_quality(value: int) -> void:
	quality = clampi(value, 0, 2)
	if material != null:
		material.set_shader_parameter("water_quality", quality)

func _process(delta: float) -> void:
	_wake_clock += delta
	if material == null or _wake_clock < 0.1:
		return
	_wake_clock = fmod(_wake_clock, 0.1)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var nearby: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("island_water_wakes"):
		if node is JeepView and not node.wreck and absf(node.speed) > 0.5 and node.global_position.distance_squared_to(camera.global_position) < 180.0 * 180.0:
			nearby.append(node)
	nearby.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(camera.global_position) < b.global_position.distance_squared_to(camera.global_position))
	var poses: PackedVector4Array = PackedVector4Array()
	var powers: PackedFloat32Array = PackedFloat32Array()
	poses.resize(8)
	powers.resize(8)
	var count: int = mini(nearby.size(), WAKE_LIMITS[quality])
	for index: int in range(count):
		var boat: JeepView = nearby[index] as JeepView
		var heading: Vector3 = boat.global_basis.x * signf(boat.speed)
		poses[index] = Vector4(boat.global_position.x, boat.global_position.z, heading.x, heading.z)
		powers[index] = clampf(absf(boat.speed) / 14.0, 0.0, 1.0)
	material.set_shader_parameter("wake_count", count)
	material.set_shader_parameter("wake_poses", poses)
	material.set_shader_parameter("wake_powers", powers)
