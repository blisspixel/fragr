extends SceneTree

const Rig = preload("res://art/characters/rig.gd")
const OUTPUT: String = "res://assets/characters/union/"

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("bake")

func bake() -> void:
	root.size = Vector2i(640, 480)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i.ONE * EnemyAnimation.TILE
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
	camera.size = EnemyAnimation.VIEW_SIZE
	viewport.add_child(camera)
	camera.position = Vector3(0, EnemyAnimation.CENTRE_HEIGHT, 5)
	camera.look_at(Vector3(0, EnemyAnimation.CENTRE_HEIGHT, 0))
	var display: TextureRect = TextureRect.new()
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.size = Vector2(480, 480)
	root.add_child(display)
	var rig: RefCounted = Rig.new()
	var entries: Array[Dictionary] = []
	for kind: String in ["clerk", "sweeper"]:
		var atlas: Image = Image.create(EnemyAnimation.COLUMNS * EnemyAnimation.TILE,
			EnemyAnimation.rows() * EnemyAnimation.TILE, false, Image.FORMAT_RGBA8)
		for direction: int in range(EnemyAnimation.DIRECTIONS):
			var pose: int = 0
			for clip: Dictionary in EnemyAnimation.CLIPS:
				var count: int = int(clip["count"])
				for index: int in range(count):
					var progress: float = float(index) / maxf(1.0, float(count - 1))
					if clip["action"] == "walk":
						progress = float(index) / count
					var model: Node3D = rig.build_pose(kind == "sweeper",
						str(clip["action"]), progress, bool(clip["unarmed"]))
					viewport.add_child(model)
					model.rotation_degrees.y = direction * 45.0
					await process_frame
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					var capture: Image = viewport.get_texture().get_image()
					capture.convert(Image.FORMAT_RGBA8)
					var rect: Rect2i = capture.get_used_rect()
					if rect.size == Vector2i.ZERO or rect.position.x == 0 or rect.position.y == 0 \
						or rect.end.x >= EnemyAnimation.TILE or rect.end.y >= EnemyAnimation.TILE:
						push_error("character_bake: empty or clipped %s %s %d/%d rect %s" % [kind, clip["action"], direction, index, rect])
						quit(1)
						return
					var frame: int = direction * EnemyAnimation.poses() + pose
					var cell: Vector2i = Vector2i(frame % EnemyAnimation.COLUMNS,
						floori(float(frame) / EnemyAnimation.COLUMNS)) * EnemyAnimation.TILE
					atlas.blit_rect(capture, Rect2i(Vector2i.ZERO, viewport.size), cell)
					pose += 1
					model.queue_free()
					await process_frame
		var destination: String = OUTPUT + kind + ".png"
		if atlas.save_png(destination) != OK:
			push_error("character_bake: could not write " + destination)
			quit(1)
			return
		entries.append({"file": kind + ".png", "sha256": FileAccess.get_sha256(destination),
			"model": "articulated human security rig" if kind == "clerk" else "articulated issued bot rig",
			"brief": "Visible human face, open helmet, institutional green cloth, issued bone armor and restrained red seal."
				if kind == "clerk" else "Covered mechanical chassis, dark status slit, battery pack, issued bone armor and restrained red seal."})
		print("character_bake: wrote ", kind)
	var sources: Dictionary[String, String] = {}
	for source: String in ["res://art/characters/geometry.gd", "res://art/characters/rig.gd",
		"res://art/characters/bake.gd", "res://scripts/enemy_animation.gd"]:
		sources[source] = FileAccess.get_sha256(source)
	var manifest: FileAccess = FileAccess.open(OUTPUT + "manifest.json", FileAccess.WRITE)
	if manifest == null or not manifest.store_string(JSON.stringify({
		"schema":1, "engine":Engine.get_version_info()["string"],
		"format":"RGBA8 PNG, nearest sampling, no mipmaps", "sources":sources,
		"tile_pixels":EnemyAnimation.TILE, "poses":EnemyAnimation.poses(),
		"directions":EnemyAnimation.DIRECTIONS, "columns":EnemyAnimation.COLUMNS,
		"rows":EnemyAnimation.rows(), "clips":EnemyAnimation.CLIPS, "entries":entries
	}, "\t") + "\n"):
		push_error("character_bake: could not write manifest")
		quit(1)
		return
	manifest.close()
	viewport.queue_free()
	display.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	print("character_bake: PASS (", entries.size(), " atlases)")
	quit()
