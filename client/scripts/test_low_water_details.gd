extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_low_water_details: " + message)

func _run() -> void:
	var ordinary: ShaderMaterial = ArenaMaterials.authored("enamel", "annex") as ShaderMaterial
	var plaster: ShaderMaterial = ArenaMaterials.authored("enamel", "low_water") as ShaderMaterial
	var repeated: ShaderMaterial = ArenaMaterials.authored("concrete", "low_water") as ShaderMaterial
	var steel: ShaderMaterial = ArenaMaterials.authored("service_steel", "low_water") as ShaderMaterial
	var lift: ShaderMaterial = ArenaMaterials.authored("lift_panel", "low_water") as ShaderMaterial
	_check(ordinary.get_shader_parameter("detail_enabled") != true and lift.get_shader_parameter("detail_enabled") != true, "other venues and unrelated surface styles keep detail disabled")
	_check(ArenaMaterials.make(1004, 0).get_shader_parameter("detail_enabled") != true, "arcade material paths retain original defaults")
	_check(plaster.get_shader_parameter("detail_enabled") == true and steel.get_shader_parameter("detail_enabled") == true, "explicit Low Water plaster and service faces receive repairs")
	_check(plaster.get_shader_parameter("detail_texture") == repeated.get_shader_parameter("detail_texture"), "same overlay is cached across authored solid materials")
	_check(plaster.get_shader_parameter("detail_texture") != steel.get_shader_parameter("detail_texture"), "plaster and steel retain distinct repair histories")
	var bytes: int = 0
	for material: ShaderMaterial in [plaster, steel]:
		var texture: Texture2D = material.get_shader_parameter("detail_texture") as Texture2D
		_check(texture != null and texture.get_width() == 128 and texture.get_height() == 128, "fixed texture dimensions prevent hidden allocation growth")
		if texture == null:
			continue
		var image: Image = texture.get_image()
		bytes += image.get_data().size()
		_check(not image.has_mipmaps(), "original palette clusters have no interpolated mip levels")
		var occupied: int = 0
		for y: int in range(128):
			for x: int in range(128):
				if image.get_pixel(x, y).a > 0.01:
					occupied += 1
		_check(occupied > 500 and occupied < 5000, "repairs use bounded coherent fields and leave most wall pixels quiet")
	_check(bytes == 131072, "two RGBA overlays stay within the declared 128 KiB budget")
	var shader: String = ArenaMaterials.SURFACE.code
	_check(shader.contains("filter_nearest, repeat_enable") and shader.contains("detail_enabled && n.y < 0.5"), "shared shader samples nearest pixels and keeps floors untouched")
	if DisplayServer.get_name() != "headless" and failures == 0:
		await _rendered(plaster, "plaster")
		await _rendered(steel, "steel")
	await process_frame
	if failures == 0:
		print("test_low_water_details: PASS venue isolation, cached palette texture budget, nearest pixels and lit surface detail")
	quit(0 if failures == 0 else 1)

func _rendered(material: ShaderMaterial, subject: String) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("353b3a")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.15
	viewport.add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -25, 0)
	light.light_energy = 0.8
	viewport.add_child(light)
	var wall: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(6, 4, 0.4)
	wall.mesh = box
	wall.position = Vector3(0, 2, 0)
	wall.material_override = material
	viewport.add_child(wall)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0, 2, 7)
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 2, 0))
	camera.current = true
	material.set_shader_parameter("detail_enabled", false)
	var plain: Image = await _frame(viewport)
	material.set_shader_parameter("detail_enabled", true)
	var detailed: Image = await _frame(viewport)
	light.light_energy = 0.1
	var dim: Image = await _frame(viewport)
	var changed: int = 0
	var lit_changes: int = 0
	for y: int in range(360):
		for x: int in range(640):
			if _difference(plain.get_pixel(x, y), detailed.get_pixel(x, y)) > 0.025:
				changed += 1
				if detailed.get_pixel(x, y).get_luminance() > dim.get_pixel(x, y).get_luminance() + 0.05:
					lit_changes += 1
	_check(changed > 250 and changed < 50000, "lit wall displays restrained repairs instead of blank or full-face replacement")
	_check(lit_changes > changed * 0.8, "detail responds to directional light rather than acting as unlit paint")
	var directory: String = ProjectSettings.globalize_path("res://../.agents/environment")
	DirAccess.make_dir_recursive_absolute(directory)
	_check(detailed.save_png(directory.path_join("low_water_%s_lit.png" % subject)) == OK and dim.save_png(directory.path_join("low_water_%s_dim.png" % subject)) == OK, "inspected rendered evidence writes successfully")
	# The same opt-in material must leave horizontal floor presentation unchanged.
	wall.mesh = PlaneMesh.new()
	(wall.mesh as PlaneMesh).size = Vector2(6, 4)
	wall.position = Vector3.ZERO
	camera.position = Vector3(0, 6, 5)
	camera.look_at(Vector3.ZERO)
	light.light_energy = 0.8
	material.set_shader_parameter("detail_enabled", false)
	var floor_plain: Image = await _frame(viewport)
	material.set_shader_parameter("detail_enabled", true)
	var floor_detail: Image = await _frame(viewport)
	_check(floor_plain.get_data() == floor_detail.get_data(), "horizontal surface is pixel-identical with optional wall detail enabled")
	print("test_low_water_details: rendered ", subject, " changed=", changed, " lit_changes=", lit_changes)
	viewport.queue_free()

func _frame(viewport: SubViewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _difference(first: Color, second: Color) -> float:
	return maxf(absf(first.r - second.r), maxf(absf(first.g - second.g), absf(first.b - second.b)))
