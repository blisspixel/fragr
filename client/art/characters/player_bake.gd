extends SceneTree

## Bakes the two free participant bodies into runtime strips under
## `client/assets/characters/free/`. Each strip is one row of 160 pixel cells:
## four idle breaths, then a four-frame walk. The camera, field and feet
## registration are the Union bake's, so a participant is exactly as tall as
## the shared 1.8 metre hit volume and never enlarged for readability.
## A comparison sheet beside the Union Clerk and Sweeper goes to .agents/.

const Rig = preload("res://art/characters/player_rig.gd")
const OUTPUT: String = "res://assets/characters/free/"
const IDLE_FRAMES: int = 4
const WALK_FRAMES: int = 4
## Breathing lift of the upper body per idle frame, in metres.
const BREATH: Array[float] = [0.0, 0.012, 0.02, 0.01]
const OUTLINE: Color = Color8(58, 42, 72)
const BODIES: Dictionary[String, String] = {
	"human": "Free human: bone shirt, open warm-leather jacket, rust scarf, cyan patch and armband, visible face and hair.",
	"synthetic": "Free embodied agent: bone shell over a gunmetal frame, leather harness, ember scarf, rust repair plates, round cyan lenses, magenta-tipped antenna.",
}

var viewport: SubViewport
var failures: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("_bake")

## A one-texel outline in the free outline purple around every opaque edge.
static func outlined(image: Image) -> Image:
	var out: Image = image.duplicate()
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.5:
				continue
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + offset
				if n.x >= 0 and n.y >= 0 and n.x < image.get_width() and n.y < image.get_height() \
					and image.get_pixel(n.x, n.y).a > 0.5:
					out.set_pixel(x, y, OUTLINE)
					break
	return out

func _capture(model: Node3D) -> Image:
	viewport.add_child(model)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	model.queue_free()
	await process_frame
	return image

func _bake() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("player_bake: a real renderer is required")
		quit(1)
		return
	root.size = Vector2i(640, 480)
	viewport = SubViewport.new()
	viewport.size = Vector2i.ONE * EnemyAnimation.TILE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	viewport.add_child(environment)
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
	var tile: int = EnemyAnimation.TILE
	var frames: int = IDLE_FRAMES + WALK_FRAMES
	var entries: Array[Dictionary] = []
	var strips: Array[Image] = []
	for kind: String in BODIES:
		var strip: Image = Image.create(frames * tile, tile, false, Image.FORMAT_RGBA8)
		for frame: int in range(frames):
			var walking: bool = frame >= IDLE_FRAMES
			var progress: float = float(frame - IDLE_FRAMES) / WALK_FRAMES if walking else 0.0
			var model: Node3D = rig.build_pose(kind == "synthetic", "walk" if walking else "idle", progress, true)
			if not walking:
				(model.get_child(0) as Node3D).position.y += BREATH[frame]
			var image: Image = await _capture(model)
			var rect: Rect2i = image.get_used_rect()
			if rect.size == Vector2i.ZERO or rect.position.x <= 1 or rect.position.y <= 1 \
				or rect.end.x >= tile - 1 or rect.end.y >= tile - 1:
				push_error("player_bake: empty or clipped %s frame %d rect %s" % [kind, frame, rect])
				failures += 1
			strip.blit_rect(outlined(image), Rect2i(Vector2i.ZERO, viewport.size), Vector2i(frame * tile, 0))
		var destination: String = OUTPUT + kind + ".png"
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) != OK \
			or strip.save_png(destination) != OK:
			push_error("player_bake: could not write " + destination)
			quit(1)
			return
		strips.append(strip)
		entries.append({"body": kind, "file": kind + ".png", "sha256": FileAccess.get_sha256(destination),
			"brief": BODIES[kind]})
		print("player_bake: wrote ", kind)
	_write_comparison(strips, tile)
	var sources: Dictionary[String, String] = {}
	for source: String in ["res://art/characters/geometry.gd", "res://art/characters/rig.gd",
		"res://art/characters/player_rig.gd", "res://art/characters/player_bake.gd",
		"res://scripts/enemy_animation.gd"]:
		sources[source] = FileAccess.get_sha256(source)
	var manifest: FileAccess = FileAccess.open(OUTPUT + "manifest.json", FileAccess.WRITE)
	if manifest == null or not manifest.store_string(JSON.stringify({
		"schema":1, "engine":Engine.get_version_info()["string"],
		"format":"RGBA8 PNG, nearest sampling, no mipmaps", "sources":sources,
		"tile_pixels":tile, "idle_frames":IDLE_FRAMES, "walk_frames":WALK_FRAMES,
		"view_metres":EnemyAnimation.VIEW_SIZE, "centre_metres":EnemyAnimation.CENTRE_HEIGHT,
		"entries":entries
	}, "\t") + "\n"):
		push_error("player_bake: could not write manifest")
		quit(1)
		return
	manifest.close()
	viewport.queue_free()
	display.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	print("player_bake: " + ("PASS" if failures == 0 else "FAIL") + " (%d bodies)" % entries.size())
	quit(0 if failures == 0 else 1)

## Review sheet only: both free bodies, then the Union Clerk and Sweeper at the
## same scale, on a mid-grey, enlarged twice. Written outside the game assets.
func _write_comparison(strips: Array[Image], tile: int) -> void:
	var columns: Array[Image] = []
	for strip: Image in strips:
		columns.append(strip.get_region(Rect2i(0, 0, tile, tile)))
		columns.append(strip.get_region(Rect2i(IDLE_FRAMES * tile + tile, 0, tile, tile)))
	for kind: String in ["clerk", "sweeper"]:
		var atlas: Texture2D = load("res://assets/characters/union/%s.png" % kind)
		if atlas != null:
			var image: Image = atlas.get_image()
			image.convert(Image.FORMAT_RGBA8)
			columns.append(image.get_region(Rect2i(0, 0, tile, tile)))
	var sheet: Image = Image.create(columns.size() * tile, tile, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.34, 0.33, 0.32))
	for index: int in range(columns.size()):
		sheet.blend_rect(columns[index], Rect2i(0, 0, tile, tile), Vector2i(index * tile, 0))
	sheet.resize(sheet.get_width() * 2, tile * 2, Image.INTERPOLATE_NEAREST)
	var folder: String = ProjectSettings.globalize_path("res://../.agents/characters/free-bodies")
	if DirAccess.make_dir_recursive_absolute(folder) == OK:
		sheet.save_png(folder.path_join("comparison.png"))
