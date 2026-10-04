extends SceneTree

## Isolated diagnostic of the runtime pixel material under a moving light.
## This fixture proves lighting response, not an authoritative encounter.
var _viewport: SubViewport

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("_run")

func _run() -> void:
	var output: String = OS.get_environment("FRAGR_QA_DIR")
	if output.is_empty():
		push_error("qa_auditor_lighting: requires owned output directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(320, 320)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("24282d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d1ccc1")
	environment.environment.ambient_light_energy = 0.16
	_viewport.add_child(environment)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0, 0.9, 6)
	camera.fov = 45.0
	_viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	var sprite: Sprite3D = Sprite3D.new()
	sprite.position.y = EnemyAnimation.CENTRE_HEIGHT
	sprite.texture = load("res://assets/characters/union/auditor.png") as Texture2D
	sprite.hframes = EnemyAnimation.COLUMNS
	sprite.vframes = EnemyAnimation.rows()
	sprite.frame = EnemyAnimation.pose_frame("idle", false, 0.0)
	sprite.pixel_size = EnemyAnimation.VIEW_SIZE / EnemyAnimation.TILE
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = EnemyView.UNION_SPRITE
	material.set_shader_parameter("sprite_texture", sprite.texture)
	material.set_shader_parameter("sprite_normals", load("res://assets/characters/union/auditor_normals.png"))
	material.set_shader_parameter("normals_enabled", true)
	material.set_shader_parameter("rim_color", EnemyView.AUDITOR_RIM)
	sprite.material_override = material
	_viewport.add_child(sprite)
	var light: OmniLight3D = OmniLight3D.new()
	light.omni_range = 8.0
	light.light_energy = 5.0
	_viewport.add_child(light)
	var images: Array[Image] = []
	for side: float in [-1.0, 1.0]:
		light.position = Vector3(side * 2.4, 1.4, 2.2)
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		images.append(_viewport.get_texture().get_image())
	var changed: int = 0
	var delta_sum: float = 0.0
	for y: int in range(320):
		for x: int in range(320):
			var a: Color = images[0].get_pixel(x, y)
			var b: Color = images[1].get_pixel(x, y)
			var delta: float = absf(a.get_luminance() - b.get_luminance())
			if delta > 0.035:
				changed += 1
				delta_sum += delta
	var sheet: Image = Image.create(640, 320, false, Image.FORMAT_RGBA8)
	for index: int in range(2):
		sheet.blit_rect(images[index], Rect2i(Vector2i.ZERO, Vector2i(320, 320)), Vector2i(index * 320, 0))
	var saved: bool = sheet.save_png(output.path_join("lighting.png")) == OK
	var file: FileAccess = FileAccess.open(output.path_join("lighting.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"diagnostic": true, "camera_distance_m": 6,
			"changed_pixels": changed, "luminance_delta_sum": delta_sum,
			"albedo_sha256": FileAccess.get_sha256("res://assets/characters/union/auditor.png"),
			"normals_sha256": FileAccess.get_sha256("res://assets/characters/union/auditor_normals.png")}, "\t") + "\n")
	_viewport.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	if not saved or changed < 200:
		push_error("qa_auditor_lighting: expected shaped surface response under the moved point light")
		quit(1)
		return
	print("qa_auditor_lighting: PASS six-metre runtime material, moving-light pixels ", changed)
	quit()
