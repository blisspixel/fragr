extends SceneTree

const Source = preload("res://art/models/rifle_source.gd")
const Geometry = preload("res://scripts/model_geometry.gd")

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("preview_rifle_source: require output directory")
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
	viewport.add_child(camera)
	camera.position = Vector3(0.180, 0.100, 0.550)
	camera.look_at(Vector3(-0.050, -0.420, -0.470))
	var source: RefCounted = Source.new()
	var gun: Node3D = source.build(true)
	viewport.add_child(gun)
	var flash: Node3D = _flash(gun.get_node("Muzzle") as Node3D)
	var times: Array[float] = [1.0, 0.0, 0.035, 0.070, 0.100, 0.140, 0.200]
	var strip: Image = Image.create(241 * times.size(), 180, false, Image.FORMAT_RGBA8)
	for index: int in range(times.size()):
		source.pose(gun, times[index])
		flash.visible = index in [1, 2, 3]
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var picture: Image = viewport.get_texture().get_image()
		picture.convert(Image.FORMAT_RGBA8)
		if picture.get_used_rect().size == Vector2i.ZERO or picture.save_png(args[0].path_join("full_%02d.png" % index)) != OK:
			push_error("preview_rifle_source: empty or unwritable weapon frame")
			quit(1)
			return
		picture.resize(241, 180, Image.INTERPOLATE_LANCZOS)
		_harden_alpha(picture)
		if picture.save_png(args[0].path_join("pose_%02d.png" % index)) != OK:
			push_error("preview_rifle_source: cannot write pixel frame")
			quit(1)
			return
		strip.blit_rect(picture, Rect2i(0, 0, 241, 180), Vector2i(index * 241, 0))
		if index in [0, 3]:
			var label: String = "rifle_idle.png" if index == 0 else "rifle_fire.png"
			if picture.save_png(args[0].path_join(label)) != OK:
				push_error("preview_rifle_source: cannot write registered candidate")
				quit(1)
				return
	if strip.save_png(args[0].path_join("motion.png")) != OK:
		push_error("preview_rifle_source: cannot write motion strip")
		quit(1)
		return
	source.pose(gun, 1.0)
	flash.visible = false
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.60
	camera.position = Vector3(1.6, -0.04, 0.0)
	camera.look_at(Vector3(0, -0.04, 0.0))
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if viewport.get_texture().get_image().save_png(args[0].path_join("grip_side.png")) != OK:
		push_error("preview_rifle_source: cannot write glove contact view")
		quit(1)
		return
	gun.free()
	gun = source.build(false)
	viewport.add_child(gun)
	camera.size = 0.85
	for index: int in range(2):
		source.pose(gun, 1.0 if index == 0 else 0.070)
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if viewport.get_texture().get_image().save_png(args[0].path_join("mechanism_side_%d.png" % index)) != OK:
			push_error("preview_rifle_source: cannot write mechanism view")
			quit(1)
			return
	camera.size = 0.055
	var muzzle: Node3D = gun.get_node("Muzzle") as Node3D
	camera.position = muzzle.position + Vector3(0, 0, -0.30)
	camera.look_at(muzzle.position)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if viewport.get_texture().get_image().save_png(args[0].path_join("muzzle_front.png")) != OK:
		push_error("preview_rifle_source: cannot write source muzzle inspection")
		quit(1)
		return
	source.pose(gun, 1.0)
	viewport.size = Vector2i(1600, 380)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.34
	camera.position = Vector3(-1.6, -0.04, 0.0)
	camera.look_at(Vector3(0, -0.04, 0.0))
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var profile: Image = viewport.get_texture().get_image()
	profile.convert(Image.FORMAT_RGBA8)
	profile.save_png(args[0].path_join("pickup_full.png"))
	profile.resize(80, 19, Image.INTERPOLATE_LANCZOS)
	_harden_alpha(profile)
	if profile.get_used_rect().size == Vector2i.ZERO or profile.save_png(args[0].path_join("rifle.png")) != OK:
		push_error("preview_rifle_source: cannot write bounded pickup candidate")
		quit(1)
		return
	var receipt: Dictionary = {"schema": 1, "runtime_selected": false,
		"source_sha256": FileAccess.get_sha256(Source.SOURCE),
		"presenter_sha256": FileAccess.get_sha256("res://art/models/rifle_source.gd"),
		"bake_sha256": FileAccess.get_sha256("res://../tools/preview_rifle_source.gd"),
		"renderer": RenderingServer.get_current_rendering_method(), "frames": {}}
	for label: String in ["rifle_idle.png", "rifle_fire.png", "rifle.png"]:
		receipt["frames"][label] = FileAccess.get_sha256(args[0].path_join(label))
	var file: FileAccess = FileAccess.open(args[0].path_join("bake.json"), FileAccess.WRITE)
	if file == null:
		push_error("preview_rifle_source: cannot write candidate receipt")
		quit(1)
		return
	file.store_string(JSON.stringify(receipt, "\t") + "\n")
	file.close()
	viewport.free()
	await process_frame
	print("preview_rifle_source: PASS (7 coherent frames, 241x180 held and 80x19 pickup; candidates only)")
	quit()

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
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var points: PackedVector3Array = []
		for point: int in range(10):
			var radius: float = (0.045 if point % 2 == 0 else 0.016) * (0.62 if layer == 1 else 1.0)
			var angle: float = TAU * point / 10.0
			points.append(Vector3(cos(angle) * radius, sin(angle) * radius, -0.008 - layer * 0.001))
		for point: int in range(10):
			geometry.triangle(tool, Vector3(0, 0, -0.008 - layer * 0.001), points[point], points[(point + 1) % 10], Vector3.BACK)
		geometry.instance(flash, "Flash%d" % layer, tool.commit(), material)
	return flash
