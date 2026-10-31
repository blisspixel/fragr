extends SceneTree

## Union billboards against a wall: real enemy pawns stand at the body radius
## (0.5 m) from a wall face and are seen from a fighter walking along that
## wall, at a grazing and at a quarter angle. A camera-facing quad wider than
## the body cuts into the wall unless its depth keeps the body's clearance.
## Controlled fixture, not ordinary play. Run through tools/qa_tour.sh with
## FRAGR_QA_SCRIPT=res://qa/sprite_wall_review.gd (it writes FRAGR_QA_DIR).
const KINDS: Array[String] = ["clerk", "sweeper", "heavy_sweeper", "auditor"]
const VIEWS: Dictionary[String, Vector3] = {
	"grazing": Vector3(1.0, 1.6, 7.0),
	"quarter": Vector3(4.5, 1.6, 5.0),
}

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _frame(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

static func _differing(a: Image, b: Image) -> int:
	var count: int = 0
	for y: int in range(0, a.get_height()):
		for x: int in range(0, a.get_width()):
			var p: Color = a.get_pixel(x, y)
			var q: Color = b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.02:
				count += 1
	return count

func _run() -> void:
	var output: String = OS.get_environment("FRAGR_QA_DIR")
	if output.is_empty():
		push_error("sprite_wall_review: FRAGR_QA_DIR is required")
		quit(1)
		return
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("242b33")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c3c6b9")
	world.environment.ambient_light_energy = 0.7
	viewport.add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	viewport.add_child(light)
	# The wall's face is the plane x = 0; bodies stand on the x > 0 side.
	var wall: MeshInstance3D = AssessorRig.part("Wall", Vector3(0.4, 3.2, 14.0), Vector3(-0.2, 1.6, 0.0), Color("8c847a"))
	viewport.add_child(wall)
	viewport.add_child(AssessorRig.part("Floor", Vector3(10.0, 0.2, 14.0), Vector3(4.0, -0.1, 0.0), Color("464c4c")))
	var camera: Camera3D = Camera3D.new()
	camera.fov = 75.0
	viewport.add_child(camera)
	var scene: PackedScene = load("res://scenes/player.tscn")
	var rows: Array[Dictionary] = []
	var stills: Array[Image] = []
	for kind: String in KINDS:
		var pawn: Node3D = scene.instantiate()
		viewport.add_child(pawn)
		pawn.set_process(false)
		pawn.set_player_data(kind, kind)
		pawn.position = Vector3(0.5, 1.5, 0.0)
		pawn.update_state({"id": kind, "x": 0.5, "y": 1.5, "z": 0.0, "yaw": 0.0, "hp": 60, "weapon": "Tack",
			"campaign": {"side": "union", "kind": kind, "phase": "idle", "phase_started": 100, "phase_ends": 140}}, 105)
		for view: String in VIEWS:
			camera.position = VIEWS[view]
			camera.look_at(Vector3(0.5, 1.2, 0.0))
			for frame: int in range(3):
				pawn._process(0.02)
			(pawn.get_node("Label3D") as Node3D).visible = false
			# The body's visible pixels with and without the wall: what the wall
			# hides of a body that stands clear of it is clipping.
			var shown: Array[int] = []
			for with_wall: bool in [false, true]:
				wall.visible = with_wall
				pawn.visible = false
				var empty: Image = await _frame(viewport)
				pawn.visible = true
				var full: Image = await _frame(viewport)
				shown.append(_differing(empty, full))
			var hidden: float = 1.0 - float(shown[1]) / maxf(float(shown[0]), 1.0)
			var name: String = "%02d_%s_%s" % [rows.size() + 1, kind, view]
			var image: Image = viewport.get_texture().get_image()
			if image.save_png(output.path_join(name + ".png")) != OK:
				push_error("sprite_wall_review: could not save " + name)
				quit(1)
				return
			stills.append(image)
			rows.append({"name": name, "file": name + ".png", "kind": kind, "view": view,
				"camera": [camera.position.x, camera.position.y, camera.position.z], "body_x": 0.5,
				"body_pixels_open": shown[0], "body_pixels_walled": shown[1], "hidden_fraction": snappedf(hidden, 0.001)})
			print("sprite_wall_review: %s %s hidden %.1f%% (%d of %d body pixels)" % [kind, view, hidden * 100.0, shown[0] - shown[1], shown[0]])
		pawn.free()
	var contact: Image = Image.create_empty(1280, 720, false, Image.FORMAT_RGBA8)
	var columns: int = 4
	var tile: Vector2i = Vector2i(1280 / columns, 720 / 2)
	for index: int in range(stills.size()):
		var small: Image = stills[index].duplicate() as Image
		small.convert(Image.FORMAT_RGBA8)
		small.resize(tile.x, tile.y, Image.INTERPOLATE_BILINEAR)
		contact.blit_rect(small, Rect2i(Vector2i.ZERO, tile), Vector2i((index % columns) * tile.x, (index / columns) * tile.y))
	contact.save_png(output.path_join("contact.png"))
	var receipt: FileAccess = FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"controlled_fixture": true, "states": rows}, "\t") + "\n")
	receipt.close()
	viewport.free()
	await process_frame
	print("sprite_wall_review: PASS %d stills" % rows.size())
	quit(0)
