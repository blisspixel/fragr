extends SceneTree

## Bakes the Ranged Sweeper atlas in the shared standing layout: 55 poses at
## eight directions in 160-pixel cells, fixed feet, nearest sampling. The
## Sweeper, Clerk, Heavy Sweeper and Turret atlases are not touched.

const Rig = preload("res://art/characters/ranged_sweeper_rig.gd")
const OUTPUT: String = "res://assets/characters/union/ranged_sweeper.png"
const MANIFEST: String = "res://assets/characters/union/ranged_sweeper-manifest.json"
const SOURCES: Array[String] = ["res://art/characters/ranged_sweeper_rig.gd",
	"res://art/characters/ranged_sweeper_bake.gd", "res://art/characters/rig.gd",
	"res://art/characters/geometry.gd", "res://scripts/enemy_animation.gd"]

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
	var rig: RefCounted = Rig.new()
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
				var action: String = str(clip["action"])
				# The bot has no seated pose; its seated cell repeats idle, as the Sweeper's does.
				if action == "seated":
					action = "idle"
				var model: Node3D = rig.build_ranged(action, progress, bool(clip["unarmed"]))
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
					push_error("ranged_sweeper_bake: empty or clipped %s %d/%d rect %s" % [action, direction, index, rect])
					quit(1)
					return
				var frame: int = direction * EnemyAnimation.poses() + pose
				var cell: Vector2i = Vector2i(frame % EnemyAnimation.COLUMNS,
					floori(float(frame) / EnemyAnimation.COLUMNS)) * EnemyAnimation.TILE
				atlas.blit_rect(capture, Rect2i(Vector2i.ZERO, viewport.size), cell)
				pose += 1
				model.queue_free()
				await process_frame
	if atlas.save_png(ProjectSettings.globalize_path(OUTPUT)) != OK:
		push_error("ranged_sweeper_bake: could not write atlas")
		quit(1)
		return
	var sources: Dictionary[String, String] = {}
	for path: String in SOURCES:
		sources[path] = FileAccess.get_sha256(path)
	var receipt: FileAccess = FileAccess.open(MANIFEST, FileAccess.WRITE)
	if receipt == null or not receipt.store_string(JSON.stringify({
		"schema":1, "engine":Engine.get_version_info()["string"],
		"model":"Original procedural Sweeper body with mast antenna and scoped precision rifle",
		"format":"RGBA8 PNG, nearest sampling, no mipmaps",
		"sources":sources, "file":"ranged_sweeper.png", "sha256":FileAccess.get_sha256(OUTPUT),
		"tile_pixels":EnemyAnimation.TILE, "poses":EnemyAnimation.poses(),
		"directions":EnemyAnimation.DIRECTIONS, "columns":EnemyAnimation.COLUMNS,
		"rows":EnemyAnimation.rows(), "clips":EnemyAnimation.CLIPS
	}, "\t") + "\n"):
		push_error("ranged_sweeper_bake: could not write receipt")
		quit(1)
		return
	receipt.close()
	viewport.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	print("ranged_sweeper_bake: PASS")
	quit()
