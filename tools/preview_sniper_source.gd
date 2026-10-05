extends SceneTree

const Source = preload("res://art/models/sniper_source.gd")
const Geometry = preload("res://scripts/model_geometry.gd")
var _failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("preview_sniper_source: require output directory")
		quit(1)
		return
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(964, 720)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_CLEAR_COLOR
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("d3d9d7")
	world.environment.ambient_light_energy = 0.65
	viewport.add_child(world)
	for spec: Vector3 in [Vector3(-32, -40, 1.6), Vector3(-15, 130, 0.8)]:
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(spec.x, spec.y, 0)
		light.light_energy = spec.z
		viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 58.0
	camera.position = Vector3(0.090, 0.070, 0.340)
	viewport.add_child(camera)
	camera.look_at(Vector3(-0.020, -0.270, -0.600))
	var source: RefCounted = Source.new()
	var gun: Node3D = source.build(true)
	viewport.add_child(gun)
	var flash: Node3D = _flash(gun.get_node("MuzzleAxis") as Node3D)
	var times: Array[float] = [1.60, 0.0, 0.070, 0.20, 0.48, 0.60, 0.85, 1.10]
	var strip: Image = Image.create(241 * times.size(), 180, false, Image.FORMAT_RGBA8)
	for index: int in range(times.size()):
		source.pose(gun, times[index])
		flash.visible = index in [1, 2]
		var picture: Image = await _capture(viewport)
		_save(picture, args[0].path_join("full_%02d.png" % index))
		picture.resize(241, 180, Image.INTERPOLATE_LANCZOS)
		_harden_alpha(picture)
		_save(picture, args[0].path_join("pose_%02d.png" % index))
		strip.blit_rect(picture, Rect2i(0, 0, 241, 180), Vector2i(index * 241, 0))
		if index in [0, 2]:
			_save(picture, args[0].path_join("sniper_idle.png" if index == 0 else "sniper_fire.png"))
	_save(strip, args[0].path_join("motion.png"))
	source.pose(gun, 1.60)
	flash.visible = false
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.46
	camera.position = Vector3(1.6, -0.035, 0.050)
	camera.look_at(Vector3(0, -0.035, 0.050))
	_save(await _capture(viewport), args[0].path_join("grip_side.png"))
	source.pose(gun, 0.070)
	_save(await _capture(viewport), args[0].path_join("grip_fire.png"))
	gun.free()
	gun = source.build(false)
	viewport.add_child(gun)
	viewport.size = Vector2i(1700, 440)
	for side: int in [-1, 1]:
		camera.size = 0.34
		camera.position = Vector3(side * 1.6, -0.040, -0.190)
		camera.look_at(Vector3(0, -0.040, -0.190))
		_save(await _capture(viewport), args[0].path_join("source_side_%d.png" % side))
	viewport.size = Vector2i(964, 720)
	for side: int in [-1, 1]:
		camera.size = 0.36
		camera.position = Vector3(side * 1.6, 0.030, 0.10)
		camera.look_at(Vector3(0, 0.030, 0.10))
		for frame: int in range(2):
			source.pose(gun, 1.60 if frame == 0 else 0.48)
			_save(await _capture(viewport), args[0].path_join("mechanism_%d_%d.png" % [side, frame]))
	source.pose(gun, 1.60)
	for label: String in ["MuzzleAxis", "OpticFrontAxis", "OpticBackAxis"]:
		var axis: Node3D = gun.get_node(label) as Node3D
		camera.size = 0.043
		camera.position = axis.to_global(Vector3(0, 0, -0.30))
		camera.look_at(axis.global_position)
		_save(await _capture(viewport), args[0].path_join(label.to_snake_case() + ".png"))
	viewport.size = Vector2i(2000, 400)
	camera.size = 0.30
	camera.position = Vector3(-1.6, -0.053, -0.185)
	camera.look_at(Vector3(0, -0.053, -0.185))
	var profile: Image = await _capture(viewport)
	_save(profile, args[0].path_join("pickup_full.png"))
	profile.resize(100, 20, Image.INTERPOLATE_LANCZOS)
	_harden_alpha(profile)
	_save(profile, args[0].path_join("sniper.png"))
	var receipt: Dictionary = {"schema":1, "runtime_selected":false,
		"source_sha256":FileAccess.get_sha256(Source.SOURCE),
		"presenter_sha256":FileAccess.get_sha256("res://art/models/sniper_source.gd"),
		"bake_sha256":FileAccess.get_sha256("res://../tools/preview_sniper_source.gd"),
		"renderer":RenderingServer.get_current_rendering_method(), "times":times, "frames":{}}
	for label: String in ["sniper_idle.png", "sniper_fire.png", "sniper.png"]:
		receipt["frames"][label] = FileAccess.get_sha256(args[0].path_join(label))
	var file: FileAccess = FileAccess.open(args[0].path_join("bake.json"), FileAccess.WRITE)
	if file == null:
		push_error("preview_sniper_source: cannot write receipt")
		_failures += 1
		viewport.free()
		await process_frame
		quit(1)
		return
	file.store_string(JSON.stringify(receipt, "\t") + "\n")
	file.close()
	viewport.free()
	await process_frame
	if _failures == 0:
		print("preview_sniper_source: PASS eight diagnostic poses and physical mechanism/bore/optics; all art candidates remain unselected")
	quit(0 if _failures == 0 else 1)

func _save(picture: Image, path: String) -> void:
	if picture.get_used_rect().size == Vector2i.ZERO or picture.save_png(path) != OK:
		push_error("preview_sniper_source: empty or unwritable frame " + path.get_file())
		_failures += 1

func _capture(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = viewport.get_texture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	return picture

func _harden_alpha(picture: Image) -> void:
	for y: int in range(picture.get_height()):
		for x: int in range(picture.get_width()):
			var pixel: Color = picture.get_pixel(x, y)
			if pixel.a < 0.5:
				picture.set_pixel(x, y, Color.TRANSPARENT)
			else:
				pixel.a = 1.0
				picture.set_pixel(x, y, pixel)

func _flash(muzzle: Node3D) -> Node3D:
	var geometry: RefCounted = Geometry.new()
	var flash: Node3D = geometry.group(muzzle, "BakedFlash")
	for layer: int in range(2):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_color = Color("ffe8a0") if layer == 1 else Color("ed9c40")
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var points: PackedVector3Array = []
		for point: int in range(10):
			var radius: float = (0.075 if point % 2 == 0 else 0.036) * (0.72 if layer == 1 else 1.0)
			var angle: float = TAU * point / 10.0
			points.append(Vector3(cos(angle) * radius, sin(angle) * radius, -0.008 + layer * 0.001))
		for point: int in range(10):
			geometry.triangle(surface, Vector3(0, 0, -0.008 + layer * 0.001), points[point], points[(point + 1) % 10], Vector3.BACK)
		geometry.instance(flash, "Flash%d" % layer, surface.commit(), material)
	return flash
