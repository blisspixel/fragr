extends SceneTree

const TOWN_FIXTURE = preload("res://scripts/test_m07_mission.gd")
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
	for venue: String in ["earth_union", "earth_yard", "earth_scrap", "low_water", "moon_port", "moon_town", "right_of_search", "holdfast_atoll"]:
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
	_civilian_boundaries()
	for surface: String in ["enamel", "service_steel", "lift_panel", "records_tile"]:
		var ship: ShaderMaterial = ArenaMaterials.authored(surface, "common_carrier") as ShaderMaterial
		_check(ship.get_shader_parameter("tile_enabled") == true and ship.get_shader_parameter("trim_glow") == 0.0, "ship selects reviewed local tiles and quiet nonemissive markings: " + surface)
		_check(ship.get_shader_parameter("warning_color") == ship.get_shader_parameter("accent_color"), "ship warning paint matches its civilian material: " + surface)
	_check(EnvironmentTextures.path_for("service_steel", "common_carrier") == EnvironmentTextures.MOON + "moon_repair_plate.png", "ship working steel has no borrowed issued archive texture")
	_check(EnvironmentTextures.path_for("enamel", "common_carrier") == EnvironmentTextures.MOON + "moon_pressure_bone.png", "ship shells retain reviewed pressure paint")
	_check(EnvironmentTextures.path_for("enamel", "right_of_search") != EnvironmentTextures.path_for("enamel", "common_carrier"), "custody tender and civilian Carrier retain distinct pressure walls")
	_check(EnvironmentTextures.path_for("enamel", "holdfast_atoll") != EnvironmentTextures.path_for("enamel", "holdfast_atoll", true), "coastal walking ledges and salt-worn plaster use distinct tiles")
	await _town_ground_assignment()
	var plain: ShaderMaterial = ArenaMaterials.authored("enamel", "unknown") as ShaderMaterial
	_check(plain.get_shader_parameter("tile_enabled") != true, "unknown venue keeps established fallback")
	_check(ArenaMaterials.authored("inspection_glass", "moon_port") is StandardMaterial3D, "registered glass retains transparent material")
	_check(EnvironmentTextures.path_for("inspection_glass", "moon_port").is_empty(), "opaque tiles never substitute pressure glass")
	_check(EnvironmentTextures.path_for("concrete", "mars").is_empty(), "future Mars library does not imply an implemented venue")
	_check(EnvironmentTextures.texture_at("res://assets/environment/missing.png") == null, "missing local asset retains procedural fallback")
	if failures == 0 and DisplayServer.get_name() != "headless":
		for venue: String in ["earth_union", "low_water", "moon_port", "moon_town", "right_of_search", "holdfast_atoll"]:
			await _rendered(venue)
	await process_frame
	if failures == 0:
		print("test_environment_textures: PASS local venue tiles, cache, wrap edges, civilian markings, issued boundaries, grounded repairs and glass isolation")
	quit(0 if failures == 0 else 1)

func _civilian_boundaries() -> void:
	for surface: String in ["concrete", "enamel", "service_steel"]:
		var civilian: ShaderMaterial = ArenaMaterials.authored(surface, "low_water") as ShaderMaterial
		_check(civilian.get_shader_parameter("trim_glow") == 0.0, "Low Water surfaces have no emissive warning marks: " + surface)
		var expected: Color = {"concrete": Color("5a655f"), "enamel": Color("6f6554"), "service_steel": Color("aa7451")}[surface]
		_check(civilian.get_shader_parameter("warning_color") == expected, "Low Water markings use the actual venue paint: " + surface)
	var dwelling: ShaderMaterial = ArenaMaterials.authored("enamel", "moon_town") as ShaderMaterial
	_check(dwelling.get_shader_parameter("trim_glow") == 0.0 and dwelling.get_shader_parameter("warning_color") == Color("7f8278"), "lunar dwelling enamel has quiet nonemissive seam paint")
	_check((dwelling.get_shader_parameter("tile_wall") as Texture2D).resource_path == EnvironmentTextures.MOON + "moon_pressure_bone.png", "actual dwelling wall selects pressure-bone")
	_check((dwelling.get_shader_parameter("tile_floor") as Texture2D).resource_path == EnvironmentTextures.MOON + "moon_worn_deck.png", "actual dwelling ledges select worn deck")
	_check(dwelling.get_shader_parameter("tile_strength") == 0.3, "large town dwelling faces keep restrained pressure-shell history")
	var issued: ShaderMaterial = ArenaMaterials.authored("service_steel", "moon_town") as ShaderMaterial
	_check(issued.get_shader_parameter("accent_color") == Color("9a302a") and issued.get_shader_parameter("surface_color") == Color("394144"), "town issued steel retains dark body and red marking")
	_check((issued.get_shader_parameter("tile_wall") as Texture2D).resource_path == EnvironmentTextures.PRODUCTION + "archive_steel.png", "issued town walls retain their selected steel texture")
	_check((issued.get_shader_parameter("tile_floor") as Texture2D).resource_path == EnvironmentTextures.MOON + "moon_worn_deck.png", "town walking steel selects worn deck")
	var ground: ShaderMaterial = ArenaMaterials.ground(issued, "service_steel", "moon_town") as ShaderMaterial
	_check(ground != issued and ground.get_shader_parameter("surface_style") == issued.get_shader_parameter("surface_style") and ground.shader == issued.shader, "town ground is independent without replacing shared shader or pixel rib geometry")
	_check(ground.get_shader_parameter("surface_color") == Color("505954") and ground.get_shader_parameter("accent_color") == Color("7f8278") and ground.get_shader_parameter("trim_glow") == 0.0, "town common ground has quiet nonemissive worn-deck paint")
	_check(ground.get_shader_parameter("tile_floor") == issued.get_shader_parameter("tile_floor"), "ground duplicate reuses nearest cached worn-deck texture")
	ground.set_shader_parameter("accent_color", Color("e8e2d6"))
	_check(issued.get_shader_parameter("accent_color") == Color("9a302a"), "editing town ground cannot recolor the issued wall instance")
	_check(ArenaMaterials.ground(dwelling, "enamel", "moon_town") == dwelling, "ground override is limited to the authored town steel deck")
	for venue: String in ["moon_port", "earth_union", "earth_yard", "earth_scrap", "unknown"]:
		# Duplication materializes shader defaults on a real renderer. Compare
		# both after that same operation, rather than an unset null to a default.
		var institution: ShaderMaterial = ArenaMaterials.authored("enamel", venue).duplicate() as ShaderMaterial
		_check(institution.get_shader_parameter("warning_color") == issued.get_shader_parameter("warning_color") and institution.get_shader_parameter("trim_glow") == issued.get_shader_parameter("trim_glow"), "other venues retain shader warning defaults: " + venue)
		var original_ground: Material = ArenaMaterials.authored("service_steel", venue)
		_check(ArenaMaterials.ground(original_ground, "service_steel", venue) == original_ground, "other venues retain their exact ground material instance: " + venue)
	var low_water_ground: Material = ArenaMaterials.authored("enamel", "low_water")
	_check(ArenaMaterials.ground(low_water_ground, "enamel", "low_water") == low_water_ground, "Low Water ground assignment retains existing material identity")
	_check(EnvironmentTextures.path_for("enamel", "moon_port") == EnvironmentTextures.PRODUCTION + "archive_enamel.png", "port/archive enamel remains unchanged")
	_check(EnvironmentTextures.path_for("service_steel", "moon_port", true) == EnvironmentTextures.PRODUCTION + "archive_floor.png", "port/archive deck remains unchanged")
	_check(EnvironmentTextures.path_for("lift_panel", "moon_town") == EnvironmentTextures.MOON + "moon_repair_plate.png", "town repairs retain reviewed plates")
	_check(EnvironmentTextures.path_for("inspection_glass", "moon_town").is_empty(), "civilian glass receives no opaque pressure tile")

func _town_ground_assignment() -> void:
	var info: Dictionary = TOWN_FIXTURE.fixture_map()
	info["presentation"]["solids"][0] = "service_steel"
	_check(MapGeometry.validation_error(info).is_empty(), "town ground integration uses a validated registered world")
	var cover: ArenaCover = ArenaCover.new()
	root.add_child(cover)
	cover.apply_map_info(info)
	var deck: ShaderMaterial = (cover.get_node("MapFloor") as MeshInstance3D).material_override as ShaderMaterial
	var wall: ShaderMaterial = cover._solid_views[0].material_override as ShaderMaterial
	_check(deck != wall and deck.get_shader_parameter("accent_color") == Color("7f8278") and wall.get_shader_parameter("accent_color") == Color("9a302a"), "actual MapFloor receives quiet paint while the issued solid retains red")
	_check(deck.get_shader_parameter("tile_floor") == wall.get_shader_parameter("tile_floor") and deck.shader == wall.shader, "actual floor and walls reuse shader and nearest cached tile")
	var legacy: Dictionary = info.duplicate(true)
	legacy.erase("m07")
	legacy["map_id"] = 1002
	legacy["map_name"] = "Persons Unknown"
	legacy["presentation"]["decorations"] = []
	cover.apply_map_info(legacy)
	_check((cover.get_node("MapFloor") as MeshInstance3D).material_override == cover._solid_views[0].material_override, "replacing town with another venue restores original shared material assignment")
	cover.queue_free()
	await process_frame
	await process_frame

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
	var material: ShaderMaterial = ArenaMaterials.authored("enamel" if venue == "right_of_search" else "service_steel", venue) as ShaderMaterial
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
