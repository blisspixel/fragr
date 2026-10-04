extends SceneTree

const UNION: Shader = preload("res://assets/shaders/union_sprite.gdshader")
var _failures: int = 0
var _out: String

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("test_union_billboard_shadow: " + message)

func _frame(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _save(image: Image, label: String) -> void:
	_check(image.save_png(_out.path_join(label + ".png")) == OK, "save " + label)

func _darkened(before: Image, after: Image) -> int:
	var count: int = 0
	for y: int in range(before.get_height()):
		for x: int in range(before.get_width()):
			if before.get_pixel(x, y).get_luminance() - after.get_pixel(x, y).get_luminance() > 0.04:
				count += 1
	return count

func _plate_range(image: Image, camera: Camera3D) -> float:
	var minimum: float = INF
	var maximum: float = -INF
	# Interior gray plate, away from silhouette/nearest edge and floor.
	for row: int in range(25):
		for column: int in range(21):
			var world: Vector3 = Vector3(0.0, 0.6 + row * 0.024, -0.20 + column * 0.02)
			var screen: Vector2i = Vector2i(camera.unproject_position(world))
			var value: float = image.get_pixel(screen.x, screen.y).get_luminance()
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
	return maximum - minimum

func _plate_darkened(before: Image, after: Image, camera: Camera3D) -> int:
	var count: int = 0
	for row: int in range(25):
		for column: int in range(21):
			var world: Vector3 = Vector3(0.0, 0.6 + row * 0.024, -0.20 + column * 0.02)
			var screen: Vector2i = Vector2i(camera.unproject_position(world))
			if before.get_pixelv(screen).get_luminance() - after.get_pixelv(screen).get_luminance() > 0.04:
				count += 1
	return count

func _run() -> void:
	_check(UNION.code.contains("MAIN_CAM_INV_VIEW_MATRIX[0]") and
		UNION.code.contains("MAIN_CAM_INV_VIEW_MATRIX[2]"), "both fixed-Y axes retain the scene camera")
	_check(not UNION.code.contains("shadows_disabled") and not UNION.code.contains("unshaded"),
		"Union bodies retain lighting and shadow reception")
	_check(UNION.code.contains("discard;") and UNION.code.contains("filter_nearest"),
		"opaque pixel silhouette and nearest sampling remain")
	if DisplayServer.get_name() == "headless":
		if _failures == 0:
			print("test_union_billboard_shadow: PASS headless boundary; rendered pixel gates require a framebuffer")
		quit(0 if _failures == 0 else 1)
		return
	_out = OS.get_environment("FRAGR_UNION_SHADOW_CAPTURE_DIR")
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("res://../.agents/union-shadow-fixture")
	DirAccess.make_dir_recursive_absolute(_out)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("17191b")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.3
	viewport.add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	light.light_energy = 1.4
	light.shadow_enabled = true
	viewport.add_child(light)
	var floor: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor.mesh = plane
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color("b3ad9c")
	floor_material.roughness = 1.0
	floor.material_override = floor_material
	viewport.add_child(floor)
	var body: Sprite3D = Sprite3D.new()
	var paint: Image = Image.create(64, 96, false, Image.FORMAT_RGBA8)
	paint.fill(Color("807c7c"))
	var texture: ImageTexture = ImageTexture.create_from_image(paint)
	body.texture = texture
	body.pixel_size = 0.018
	body.position.y = 0.864
	body.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	body.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	body.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = UNION
	material.set_shader_parameter("sprite_texture", texture)
	body.material_override = material
	viewport.add_child(body)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(2.4, 1.6, 0.0)
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.85, 0.0))
	var old_shader: Shader = Shader.new()
	old_shader.code = UNION.code.replace("MAIN_CAM_INV_VIEW_MATRIX", "INV_VIEW_MATRIX")
	material.shader = old_shader
	var original: Image = await _frame(viewport)
	_save(original, "original-fixed-camera")
	var old_range: float = _plate_range(original, camera)
	material.shader = UNION
	var corrected: Image = await _frame(viewport)
	_save(corrected, "corrected-fixed-camera")
	var corrected_range: float = _plate_range(corrected, camera)
	_check(old_range > 0.06, "original light-camera billboard reproduces diagonal plate bands")
	_check(corrected_range < 0.035, "corrected broad plate is free of diagonal self-shadow bands")
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var no_cast: Image = await _frame(viewport)
	_save(no_cast, "casting-off-control")
	var casting_pixels: int = _darkened(no_cast, corrected)
	_check(casting_pixels > 200, "corrected body still casts a real world shadow")
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var blocker: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	blocker.mesh = box
	blocker.position = Vector3(0.0, 0.9, 0.0) + light.global_basis.z * 0.8
	blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	viewport.add_child(blocker)
	var received: Image = await _frame(viewport)
	_save(received, "receiver-blocker-present")
	var receiving_pixels: int = _plate_darkened(corrected, received, camera)
	_check(receiving_pixels > 100, "corrected sprite itself receives a real blocker shadow")
	var receipt: FileAccess = FileAccess.open(_out.path_join("fixture.json"), FileAccess.WRITE)
	_check(receipt != null, "fixture receipt opens")
	if receipt != null:
		receipt.store_string(JSON.stringify({"shader_sha256": FileAccess.get_sha256("res://assets/shaders/union_sprite.gdshader"),
			"old_plate_luminance_range": old_range, "corrected_plate_luminance_range": corrected_range,
			"casting_darkened_pixels": casting_pixels, "receiving_darkened_pixels": receiving_pixels,
			"camera": [2.4, 1.6, 0.0], "camera_target": [0.0, 0.85, 0.0],
			"failures": _failures}, "\t"))
		receipt.close()
	viewport.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	if _failures == 0:
		print("test_union_billboard_shadow: rendered PASS fixed camera, original failure, retained casting and reception")
	quit(0 if _failures == 0 else 1)
