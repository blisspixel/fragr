extends SceneTree

## Offline stills of Larak Lot for visual review: every quarter, both
## landmarks, first-person views from the spawn slots and spectator overviews.
## Geometry comes from the server's own MapInfo, written by
##   FRAGR_LARAK_MAP_INFO=/abs/map.json cargo test -p fragr-server --lib \
##     larak_write_map_info -- --ignored
## and the scene is lit exactly as a match lights it (arena scene lights, the
## venue sky, quality settings, practicals). There are no fighters or pickups;
## a live match through tools/qa_tour.sh shows those.
##
##   FRAGR_LARAK_MAP_INFO=/abs/map.json FRAGR_QA_DIR=/abs/out \
##     "$GODOT_BIN" --path client --audio-driver Dummy --windowed \
##     --resolution 1280x720 --script ../tools/preview_larak_lot.gd
const ARENA_SCENE: PackedScene = preload("res://scenes/arena.tscn")
const EYE: float = 1.6

## name, camera position, look target. Spawn views use the slot's own yaw.
const VIEWS: Array = [
	["overview_se", Vector3(31.0, 24.0, 33.0), Vector3(-6.0, 1.0, -6.0)],
	["overview_nw", Vector3(-33.0, 22.0, -27.0), Vector3(6.0, 1.0, 8.0)],
	["overview_top", Vector3(0.5, 58.0, 30.0), Vector3(0.0, 0.0, 0.0)],
	["pit_from_stands", Vector3(2.0, 1.5 + EYE, 13.0), Vector3(0.0, 4.0, -8.0)],
	["pit_floor", Vector3(-6.0, EYE, 6.0), Vector3(4.0, 6.0, -6.0)],
	["repossession_from_toll", Vector3(-22.0, 3.0 + EYE, -8.0), Vector3(0.0, 12.0, 0.0)],
	["repossession_from_lane", Vector3(-30.0, 1.5 + EYE, 4.0), Vector3(0.0, 12.0, 0.0)],
	["repossession_from_impound", Vector3(22.0, 1.5 + EYE, 8.0), Vector3(0.0, 12.0, 0.0)],
	["sign_from_gallery", Vector3(-4.0, 4.5 + EYE, -14.0), Vector3(37.0, 11.0, -20.0)],
	["sign_from_stands", Vector3(-6.0, 1.5 + EYE, 18.0), Vector3(37.0, 11.0, -20.0)],
	["roof_valet", Vector3(13.0, 6.0 + EYE, -13.0), Vector3(31.0, 6.5, -22.0)],
	["low_ramp_tunnel", Vector3(-11.0, EYE, 6.0), Vector3(-22.0, 1.0, 6.0)],
	["toll_booths", Vector3(-34.0, 3.0 + EYE, -6.0), Vector3(-20.0, 4.0, -17.0)],
	["lane_bay", Vector3(-29.0, 1.5 + EYE, 0.0), Vector3(-32.0, 2.5, 22.0)],
	["impound_bay", Vector3(15.0, 1.5 + EYE, 10.0), Vector3(30.0, 2.5, 24.0)],
	["stair_b", Vector3(34.0, 1.5 + EYE, 10.0), Vector3(34.0, 5.0, -6.0)],
	["crane_fire_stair", Vector3(12.0, 3.0 + EYE, -2.0), Vector3(28.0, 5.5, -9.0)],
	["spiral_gallery", Vector3(-8.0, 3.5 + EYE, -24.0), Vector3(6.0, 5.0, -14.0)],
]
## Server spawn slots: x, floor, z, yaw (mirrors larak_lot.rs SPAWNS).
const SPAWNS: Array = [
	[-33.0, 3.0, -27.0, PI * 0.25], [-33.5, 3.0, -15.5, PI * 0.5], [-27.0, 3.0, -15.0, PI * 0.5],
	[-17.0, 3.0, -23.0, 0.0], [-3.0, 4.5, -26.0, PI * 0.5], [-27.5, 1.5, 27.0, PI * 1.5],
	[-35.0, 1.5, 21.0, 0.0], [-5.0, 1.5, 25.0, PI * 1.5], [7.0, 1.5, 23.0, PI * 1.5],
	[13.0, 1.5, 26.0, PI * 1.5], [2.5, 1.5, 24.5, PI * 1.5], [25.0, 1.5, 26.0, PI * 1.5],
]

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("preview_larak_lot: " + message)
	quit(1)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("the preview needs a real renderer")
		return
	var source: FileAccess = FileAccess.open(OS.get_environment("FRAGR_LARAK_MAP_INFO"), FileAccess.READ)
	if source == null:
		_fail("set FRAGR_LARAK_MAP_INFO to the written MapInfo")
		return
	var parsed: Variant = JSON.parse_string(source.get_as_text())
	if not parsed is Dictionary:
		_fail("MapInfo is not an object")
		return
	var info: Dictionary = parsed
	var out: String = OS.get_environment("FRAGR_QA_DIR")
	if out.is_empty() or DirAccess.make_dir_recursive_absolute(out) != OK:
		_fail("set FRAGR_QA_DIR to a writable directory")
		return
	# Equal size limits keep a tiling window manager from reshaping the
	# window, so every round's stills share one frame.
	root.min_size = Vector2i(1280, 720)
	root.max_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var settings: FragrSettings = FragrSettings.new("user://preview_larak_settings.cfg")
	var arena: Node3D = Node3D.new()
	arena.name = "Arena"
	root.add_child(arena)
	var layout: Node = ARENA_SCENE.instantiate()
	layout.name = "Layout"
	arena.add_child(layout)
	var cover: ArenaCover = ArenaCover.new()
	arena.add_child(cover)
	cover.apply_map_info(info)
	var map_name: String = str(info.get("map_name", ""))
	var world: WorldEnvironment = _world_environment(layout)
	if world == null:
		_fail("arena scene has no WorldEnvironment")
		return
	world.environment = ArenaSky.build_environment(map_name)
	RenderQuality.apply(root, settings, world.environment)
	ArenaSky.apply_scene_lights(layout, map_name)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 90.0
	camera.near = 0.05
	camera.far = 400.0
	arena.add_child(camera)
	camera.make_current()
	ArenaSky.apply_view_fill(camera, map_name)
	RenderQuality.apply_practicals(arena, settings)
	for i: int in range(8):
		await process_frame
	for view: Array in VIEWS:
		camera.position = view[1]
		camera.look_at(view[2], Vector3.UP)
		if not await _shoot(out, str(view[0])):
			return
	for index: int in range(SPAWNS.size()):
		var slot: Array = SPAWNS[index]
		camera.position = Vector3(float(slot[0]), float(slot[1]) + EYE, float(slot[2]))
		camera.rotation = Vector3(-0.05, ServerYaw.camera_rotation_y(float(slot[3])), 0.0)
		if not await _shoot(out, "spawn_s%02d" % (index + 1)):
			return
	print("preview_larak_lot: wrote %d stills to %s" % [VIEWS.size() + SPAWNS.size(), out])
	quit(0)

func _shoot(out: String, name: String) -> bool:
	for i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.save_png(out.path_join(name + ".png")) != OK:
		_fail("could not save " + name)
		return false
	return true

static func _world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child: Node in node.get_children():
		var found: WorldEnvironment = _world_environment(child)
		if found != null:
			return found
	return null
