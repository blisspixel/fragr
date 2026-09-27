extends SceneTree

const Rig = preload("res://art/characters/crawler_rig.gd")
const OUTPUT: String = "res://assets/characters/union/crawler.png"
const MANIFEST: String = "res://assets/characters/union/crawler-manifest.json"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("bake")

func bake() -> void:
	root.size = Vector2i(640, 480)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i.ONE * CrawlerAnimation.TILE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d1ccc1")
	environment.environment.ambient_light_energy = 0.45
	viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -30, 0)
	light.light_energy = 1.3
	viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CrawlerAnimation.VIEW_SIZE
	viewport.add_child(camera)
	camera.position = Vector3(0, CrawlerAnimation.CENTRE_HEIGHT, 5)
	camera.look_at(Vector3(0, CrawlerAnimation.CENTRE_HEIGHT, 0))
	var rig: RefCounted = Rig.new()
	var atlas: Image = Image.create(CrawlerAnimation.COLUMNS * CrawlerAnimation.TILE,
		CrawlerAnimation.rows() * CrawlerAnimation.TILE, false, Image.FORMAT_RGBA8)
	for direction: int in range(CrawlerAnimation.DIRECTIONS):
		var pose: int = 0
		for clip: Dictionary in CrawlerAnimation.CLIPS:
			var count: int = int(clip["count"])
			for index: int in range(count):
				var progress: float = float(index) / maxf(1.0, float(count - 1))
				if clip["action"] == "scuttle":
					progress = float(index) / count
				var model: Node3D = rig.build_pose(str(clip["action"]), progress)
				viewport.add_child(model)
				model.rotation_degrees.y = direction * 45.0
				await process_frame
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var capture: Image = viewport.get_texture().get_image()
				capture.convert(Image.FORMAT_RGBA8)
				var rect: Rect2i = capture.get_used_rect()
				if rect.size == Vector2i.ZERO or rect.position.x == 0 or rect.position.y == 0 \
					or rect.end.x >= CrawlerAnimation.TILE or rect.end.y >= CrawlerAnimation.TILE:
					push_error("crawler_bake: empty or clipped %s %d/%d rect %s" % [clip["action"], direction, index, rect])
					quit(1)
					return
				var frame: int = direction * CrawlerAnimation.poses() + pose
				var cell: Vector2i = Vector2i(frame % CrawlerAnimation.COLUMNS,
					floori(float(frame) / CrawlerAnimation.COLUMNS)) * CrawlerAnimation.TILE
				atlas.blit_rect(capture, Rect2i(Vector2i.ZERO, viewport.size), cell)
				pose += 1
				model.queue_free()
				await process_frame
	if atlas.save_png(ProjectSettings.globalize_path(OUTPUT)) != OK:
		push_error("crawler_bake: could not write atlas")
		quit(1)
		return
	var sources: Dictionary[String, String] = {}
	for path: String in ["res://art/characters/crawler_rig.gd",
			"res://art/characters/crawler_bake.gd", "res://art/characters/geometry.gd",
			"res://scripts/crawler_animation.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	var receipt: FileAccess = FileAccess.open(MANIFEST, FileAccess.WRITE)
	if receipt == null or not receipt.store_string(JSON.stringify({
		"schema":1, "engine":Engine.get_version_info()["string"],
		"model":"Original procedural low Union chassis", "format":"RGBA8 PNG, nearest sampling, no mipmaps",
		"sources":sources, "file":"crawler.png", "sha256":FileAccess.get_sha256(OUTPUT),
		"tile_pixels":CrawlerAnimation.TILE, "poses":CrawlerAnimation.poses(),
		"directions":CrawlerAnimation.DIRECTIONS, "columns":CrawlerAnimation.COLUMNS,
		"rows":CrawlerAnimation.rows(), "clips":CrawlerAnimation.CLIPS
	}, "\t") + "\n"):
		push_error("crawler_bake: could not write receipt")
		quit(1)
		return
	receipt.close()
	viewport.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	print("crawler_bake: PASS")
	quit()
