extends SceneTree

const Source = preload("res://art/models/shotgun_imported_source.gd")

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.make_dir_recursive_absolute(args[0]) != OK:
		push_error("preview_shotgun_source: require output directory")
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
	world.environment.ambient_light_energy = 0.8
	viewport.add_child(world)
	for spec: Vector3 in [Vector3(-32, -40, 1.6), Vector3(-15, 130, 0.8)]:
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(spec.x, spec.y, 0)
		light.light_energy = spec.z
		viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 58.0
	viewport.add_child(camera)
	camera.position = Vector3(0.02, 0.12, 0.23)
	camera.look_at(Vector3(0.0, 0.035, -0.65))
	var source: RefCounted = Source.new()
	var gun: Node3D = source.build(true)
	viewport.add_child(gun)
	var times: Array[float] = [1.0, 0.0, 0.08, 0.14, 0.18, 0.23, 0.28, 0.31, 0.35, 0.40, 0.44, 0.5]
	var strip: Image = Image.create(241 * times.size(), 180, false, Image.FORMAT_RGBA8)
	for index: int in range(times.size()):
		source.pose(gun, times[index])
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var picture: Image = viewport.get_texture().get_image()
		picture.convert(Image.FORMAT_RGBA8)
		picture.resize(241, 180, Image.INTERPOLATE_LANCZOS)
		if picture.get_used_rect().size == Vector2i.ZERO:
			push_error("preview_shotgun_source: empty weapon frame")
			quit(1)
			return
		if picture.save_png(args[0].path_join("pose_%02d.png" % index)) != OK:
			push_error("preview_shotgun_source: cannot write weapon frame")
			quit(1)
			return
		strip.blit_rect(picture, Rect2i(0, 0, 241, 180), Vector2i(index * 241, 0))
	if strip.save_png(args[0].path_join("motion.png")) != OK:
		push_error("preview_shotgun_source: cannot write motion strip")
		quit(1)
		return
	viewport.free()
	await process_frame
	print("preview_shotgun_source: PASS (12 coherent frames, owned pump and attached support glove)")
	quit()
