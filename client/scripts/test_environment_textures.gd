extends SceneTree

var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("test_environment_textures: " + message)

func _run() -> void:
	var paths: Dictionary[String, bool] = {}
	for venue: String in ["earth_union", "earth_yard", "earth_scrap", "low_water", "moon_port"]:
		for surface: String in MapGeometry.SURFACES:
			for horizontal: bool in [false, true]:
				var path: String = EnvironmentTextures.path_for(surface, venue, horizontal)
				if not path.is_empty():
					paths[path] = true
	_check(paths.size() >= 12, "distinct reviewed venue materials are registered")
	for path: String in paths:
		var texture: Texture2D = EnvironmentTextures.texture_at(path)
		_check(texture != null, "registered local tile loads: " + path)
		if texture == null:
			continue
		_check(texture == EnvironmentTextures.texture_at(path), "repeated solids reuse one cached texture")
		var image: Image = texture.get_image()
		_check(image.get_size() == Vector2i(128, 128) and not image.has_mipmaps(), "tiles have bounded 128-square nearest pixel storage")
		for index: int in range(128):
			_check(image.get_pixel(0, index) == image.get_pixel(127, index), "horizontal wrap edge matches")
			_check(image.get_pixel(index, 0) == image.get_pixel(index, 127), "vertical wrap edge matches")
	var wall: ShaderMaterial = ArenaMaterials.authored("service_steel", "moon_port") as ShaderMaterial
	_check(wall.get_shader_parameter("tile_enabled") == true, "existing lunar surfaces enable reviewed tiles")
	_check(wall.get_shader_parameter("tile_wall") != wall.get_shader_parameter("tile_floor"), "lunar issued walls and worn walking decks retain different materials")
	_check(wall.get_shader_parameter("detail_enabled") != true, "opaque lunar fallback cannot cover the selected issued steel tile")
	var repair: ShaderMaterial = ArenaMaterials.authored("enamel", "low_water") as ShaderMaterial
	_check(repair.get_shader_parameter("detail_enabled") == true and repair.get_shader_parameter("tile_enabled") == true, "existing grounded repair layer and new repeating albedo coexist")
	var plain: ShaderMaterial = ArenaMaterials.authored("enamel", "unknown") as ShaderMaterial
	_check(plain.get_shader_parameter("tile_enabled") != true, "unknown venue keeps established fallback")
	_check(ArenaMaterials.authored("inspection_glass", "moon_port") is StandardMaterial3D, "registered glass retains transparent material")
	_check(EnvironmentTextures.path_for("inspection_glass", "moon_port").is_empty(), "opaque tiles never substitute pressure glass")
	_check(EnvironmentTextures.path_for("concrete", "mars").is_empty(), "future Mars library does not imply an implemented venue")
	_check(EnvironmentTextures.texture_at("res://assets/environment/missing.png") == null, "missing local asset retains procedural fallback")
	if failures == 0 and DisplayServer.get_name() != "headless":
		for venue: String in ["earth_union", "low_water", "moon_port"]:
			await _rendered(venue)
	await process_frame
	if failures == 0:
		print("test_environment_textures: PASS local venue tiles, cache, wrap edges, grounded repairs and glass isolation")
	quit(0 if failures == 0 else 1)

func _rendered(venue: String) -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("252a2c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.12
	viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -20, 0)
	light.light_energy = 0.9
	viewport.add_child(light)
	var material: ShaderMaterial = ArenaMaterials.authored("service_steel", venue) as ShaderMaterial
	var wall: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(12, 5, 0.4)
	wall.mesh = box
	wall.position = Vector3(0, 2.5, 0)
	wall.material_override = material
	viewport.add_child(wall)
	var floor: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor.mesh = plane
	floor.material_override = material
	viewport.add_child(floor)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0, 1.65, 7)
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 1.3, 0))
	camera.current = true
	material.set_shader_parameter("tile_enabled", false)
	var original: Image = await _frame(viewport)
	material.set_shader_parameter("tile_enabled", true)
	var detailed: Image = await _frame(viewport)
	light.light_energy = 0.1
	var dim: Image = await _frame(viewport)
	var changed: int = 0
	var wall_changes: int = 0
	var floor_changes: int = 0
	var lit: int = 0
	for y: int in range(360):
		for x: int in range(640):
			var pixel: Color = detailed.get_pixel(x, y)
			if absf(pixel.get_luminance() - original.get_pixel(x, y).get_luminance()) > 0.02:
				changed += 1
				if y >= 55 and y < 180:
					wall_changes += 1
				if y >= 260:
					floor_changes += 1
			if pixel.get_luminance() > dim.get_pixel(x, y).get_luminance() + 0.02:
				lit += 1
	_check(changed > 3000, "reviewed tiles change visible world surfaces at player height")
	_check(wall_changes > 3000 and floor_changes > 3000, "both walls and walking floors show selected albedos")
	_check(lit > 10000, "new albedos respond to actual lighting")
	var directory: String = ProjectSettings.globalize_path("res://../.agents/world-textures-20261001/rendered")
	DirAccess.make_dir_recursive_absolute(directory)
	_check(detailed.save_png(directory.path_join(venue + "_lit.png")) == OK, "lit surface evidence saves")
	_check(dim.save_png(directory.path_join(venue + "_dim.png")) == OK, "dim surface evidence saves")
	print("test_environment_textures: rendered ", venue, " changed=", changed, " wall=", wall_changes, " floor=", floor_changes, " lit=", lit)
	viewport.queue_free()
	await process_frame
	await process_frame

func _frame(viewport: SubViewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
