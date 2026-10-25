extends SceneTree

## Offline stills of Larak Lot for visual review: every quarter, both
## landmarks, first-person views from the spawn slots and spectator overviews.
## Geometry comes from the server's own MapInfo, written by
##   FRAGR_LARAK_MAP_INFO=/abs/map.json cargo test -p fragr-server --lib \
##     larak_write_map_info -- --ignored
## and the scene is lit exactly as a match lights it (arena scene lights, the
## venue sky, quality settings, practicals). Every pad has its item seated on
## the kit the presenter stages, and `pad_return_*` is the Rail coming back on
## its clock, frame by frame (`walk_stands_*` a run across the Stands); a live
## match through tools/qa_tour.sh shows the fights. The committed
## client/golden/larak_lot_map_info.json is a current MapInfo to point
## FRAGR_LARAK_MAP_INFO at. The readability stagings stand a NODS
## rule bot beside a free fighter in the Pit, a booth lane and on the Roof, in
## colour and grayscale, for the faction readability check.
##
##   FRAGR_LARAK_MAP_INFO=/abs/map.json FRAGR_QA_DIR=/abs/out \
##     "$GODOT_BIN" --path client --audio-driver Dummy --windowed \
##     --resolution 1280x720 --script ../tools/preview_larak_lot.gd
## Set FRAGR_LARAK_VIEWS=prop_ (view-name prefixes, comma separated) for just those views.
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
	["revival", Vector3(-3.0, 4.5 + EYE, -20.5), Vector3(-3.0, 6.4, -28.0)],
	["revival_from_pit", Vector3(2.0, EYE, 4.0), Vector3(-3.0, 7.0, -28.0)],
	["lane_entry", Vector3(-27.0, 1.5 + EYE, 2.0), Vector3(-36.0, 3.2, 9.0)],
	["ramp_directory", Vector3(-20.0, 1.5 + EYE, -3.0), Vector3(-20.0, 2.8, 1.5)],
	["tunnel_halfway", Vector3(-17.0, 0.5 + EYE, 6.0), Vector3(-23.5, 1.8, 10.0)],
	["stands_back", Vector3(0.0, 1.5 + EYE, 11.0), Vector3(-2.0, 5.0, 28.0)],
	["impound_office", Vector3(24.0, 1.5 + EYE, 18.0), Vector3(31.0, 2.4, 23.0)],
	["toll_north_wall", Vector3(-24.0, 3.0 + EYE, -18.5), Vector3(-24.0, 5.0, -28.0)],
	["gulf_breeze_corner", Vector3(24.0, 3.0 + EYE, -2.0), Vector3(30.0, 4.0, -2.0)],
	# The prepared props, each in place at play distance.
	["prop_pit_wreck", Vector3(-1.0, EYE, 2.0), Vector3(4.2, 0.7, -3.0)],
	["prop_stack", Vector3(0.3, EYE, 0.6), Vector3(6.2, 1.4, 5.5)],
	["prop_booths", Vector3(-20.2, 3.0 + EYE, -9.5), Vector3(-24.0, 4.3, -15.0)],
	["prop_pay_machines", Vector3(-29.0, 3.0 + EYE, -23.8), Vector3(-31.5, 3.8, -27.8)],
	["prop_pay_close", Vector3(-31.0, 3.0 + EYE, -25.6), Vector3(-31.5, 4.0, -28.0)],
	["prop_kiosk", Vector3(1.2, 1.5 + EYE, 11.6), Vector3(0.0, 2.7, 17.5)],
	["prop_kiosk_end", Vector3(-6.0, 1.5 + EYE, 15.0), Vector3(-2.0, 2.8, 17.9)],
	["prop_impound_cars", Vector3(17.0, 1.5 + EYE, 14.5), Vector3(20.0, 2.2, 20.0)],
	["prop_coffee", Vector3(28.0, 1.5 + EYE, 19.2), Vector3(30.2, 2.3, 22.8)],
	["prop_bell", Vector3(-6.0, 1.5 + EYE, 23.0), Vector3(-9.3, 3.9, 27.5)],
	["prop_hook", Vector3(2.0, 4.5 + EYE, -12.0), Vector3(0.0, 15.3, 0.0)],
	["prop_hook_spectator", Vector3(4.0, 14.5, -5.0), Vector3(0.0, 14.6, 0.0)],
	["prop_roof_wrecks", Vector3(24.0, 6.0 + EYE, -18.0), Vector3(16.2, 6.6, -24.0)],
	["prop_pulpit", Vector3(-3.0, 4.5 + EYE, -24.5), Vector3(-3.0, 5.5, -28.0)],
	# The pad kit with its items seated, at the distance a fighter runs in.
	["pad_rail", Vector3(-15.5, 0.5 + EYE, 5.0), Vector3(-20.0, 0.7, 6.0)],
	["pad_plate", Vector3(26.5, 6.0 + EYE, -19.5), Vector3(31.0, 6.4, -22.0)],
	["pad_rocket", Vector3(3.5, EYE, -1.5), Vector3(7.5, 0.4, 2.0)],
	["pad_booths", Vector3(-17.5, 3.0 + EYE, -11.0), Vector3(-21.0, 3.3, -15.0)],
	["pad_health", Vector3(-29.5, 3.0 + EYE, -9.0), Vector3(-33.0, 3.3, -7.0)],
	["pad_pit_overview", Vector3(0.0, 9.0, 12.0), Vector3(0.0, 0.0, 0.0)],
]
## The server's pads (larak_lot.rs): id, kind, weapon, floor position. The
## preview lays a pickup on each, as a match does with every pad up.
const PADS: Array = [
	["larak_custody_plate", "plate", "", Vector3(31.0, 6.0, -22.0)],
	["larak_rail", "weapon", "Rail", Vector3(-20.0, 0.5, 6.0)],
	["larak_scatter_booths", "weapon", "Scatter", Vector3(-21.0, 3.0, -15.0)],
	["larak_scatter_stairb", "weapon", "Scatter", Vector3(26.0, 1.5, 10.0)],
	["larak_flechette_pit", "weapon", "Flechette", Vector3(-4.0, 0.0, 4.0)],
	["larak_flechette_lane", "weapon", "Flechette", Vector3(-31.0, 1.5, 16.0)],
	["larak_armor_bridge", "armor", "", Vector3(0.0, 3.0, -6.5)],
	["larak_health_toll", "health", "", Vector3(-33.0, 3.0, -7.0)],
	["larak_health_stands", "health", "", Vector3(6.0, 1.5, 22.0)],
	["larak_health_crane", "health", "", Vector3(14.0, 3.0, -3.0)],
	["larak_rocket_pit", "weapon", "Rocket", Vector3(7.5, 0.0, 2.0)],
]
const PICKUP_SCENE: PackedScene = preload("res://scenes/weapon_pickup.tscn")
## Readability stagings: name, camera, look target, then a NODS bot and a free
## fighter side by side near (about 15 m) and far (about 22 to 30 m), each as
## floor positions. Every staging is shot in colour and in grayscale.
const READABILITY: Array = [
	["read_pit", Vector3(0.0, 1.5 + EYE, 16.0), Vector3(0.0, 2.5, -6.0),
		[Vector3(-1.2, 0.0, 1.0), Vector3(1.2, 0.0, 1.0)], [Vector3(-1.2, 4.5, -15.0), Vector3(1.2, 4.5, -15.0)]],
	["read_booth_lane", Vector3(-27.0, 3.0 + EYE, -26.0), Vector3(-27.0, 4.0, -10.0),
		[Vector3(-27.7, 3.0, -11.0), Vector3(-26.3, 3.0, -11.0)], [Vector3(-27.7, 3.0, -5.0), Vector3(-26.3, 3.0, -5.0)]],
	["read_roof", Vector3(10.0, 6.0 + EYE, -21.0), Vector3(31.0, 7.0, -23.0),
		[Vector3(24.5, 6.0, -22.5), Vector3(24.5, 6.0, -24.0)], [Vector3(34.5, 6.0, -23.0), Vector3(34.5, 6.0, -24.5)]],
]
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
## Server body centre above the floor (sim.rs PLAYER_FLOOR_Y).
const BODY_Y: float = 1.5

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
	# Every pad up, its item seated on the kit the presenter stages.
	var pickups: Dictionary[String, Node3D] = {}
	for pad: Array in PADS:
		var pickup: Node3D = PICKUP_SCENE.instantiate() as Node3D
		arena.add_child(pickup)
		pickup.call("setup", str(pad[0]), str(pad[2]), (pad[3] as Vector3) + Vector3(0.0, 0.4, 0.0), str(pad[1]), 0, "")
		pickups[str(pad[0])] = pickup
	for i: int in range(8):
		await process_frame
	# FRAGR_LARAK_VIEWS narrows the run to the views whose names start with
	# that prefix, without the spawn and readability sets.
	var only: String = OS.get_environment("FRAGR_LARAK_VIEWS")
	var prefixes: PackedStringArray = only.split(",", false)
	var shot_count: int = 0
	for view: Array in VIEWS:
		if not only.is_empty() and not Array(prefixes).any(func(prefix: String) -> bool: return str(view[0]).begins_with(prefix)):
			continue
		camera.position = view[1]
		camera.look_at(view[2], Vector3.UP)
		if not await _shoot(out, str(view[0])):
			return
		shot_count += 1
	# The Rail's clock runs out while the camera watches: the return pop and
	# shimmer as a strip of frames, in real time.
	if only.is_empty() or Array(prefixes).has("pad_return"):
		var rail: Node3D = pickups["larak_rail"]
		camera.position = Vector3(-16.5, 0.5 + EYE, 5.2)
		camera.look_at(Vector3(-20.0, 1.0, 6.0), Vector3.UP)
		rail.call("note_server_available", true, false)
		rail.call("note_server_available", false, false)
		rail.call("note_server_available", true, false)
		for frame: int in range(10):
			if not await _shoot(out, "pad_return_%02d" % frame):
				return
			shot_count += 1
	# A run across the Stands toward the Pit at 6 m/s, one frame per 1/24 s,
	# to judge the decks and walls in motion (texel crawl, sparkle).
	if only.is_empty() or Array(prefixes).has("walk_stands"):
		for frame: int in range(12):
			camera.position = Vector3(-6.5, 1.5 + EYE, 22.0 - float(frame) * 0.25)
			camera.look_at(camera.position + Vector3(0.1, -0.3, -1.0), Vector3.UP)
			if not await _shoot(out, "walk_stands_%02d" % frame):
				return
			shot_count += 1
	if not only.is_empty():
		print("preview_larak_lot: wrote %d stills to %s" % [shot_count, out])
		quit(0)
		return
	for index: int in range(SPAWNS.size()):
		var slot: Array = SPAWNS[index]
		camera.position = Vector3(float(slot[0]), float(slot[1]) + EYE, float(slot[2]))
		camera.rotation = Vector3(-0.05, ServerYaw.camera_rotation_y(float(slot[3])), 0.0)
		if not await _shoot(out, "spawn_s%02d" % (index + 1)):
			return
	var shots: int = VIEWS.size() + SPAWNS.size()
	for staging: Array in READABILITY:
		var pawns: Array[Node3D] = []
		var index: int = 0
		for pair: Array in [staging[3], staging[4]]:
			pawns.append(_fighter(arena, "NODS-0%d" % (index + 1), "", pair[0], staging[1]))
			pawns.append(_fighter(arena, "STTC KD %d" % (index + 1), "human", pair[1], staging[1]))
			index += 1
		for i: int in range(20):
			await process_frame
		camera.position = staging[1]
		camera.look_at(staging[2], Vector3.UP)
		if not await _shoot(out, str(staging[0])):
			return
		world.environment.adjustment_enabled = true
		world.environment.adjustment_saturation = 0.0
		if not await _shoot(out, str(staging[0]) + "_gray"):
			return
		world.environment.adjustment_enabled = false
		world.environment.adjustment_saturation = 1.0
		shots += 2
		for pawn: Node3D in pawns:
			pawn.queue_free()
		await process_frame
	print("preview_larak_lot: wrote %d stills to %s" % [shots, out])
	quit(0)

## A fighter as a match presents it to a spectator, standing on `feet` and
## facing the camera: a NODS rule bot on the legacy strip, or a free body.
func _fighter(arena: Node3D, callsign: String, body: String, feet: Vector3, toward: Vector3) -> Node3D:
	var pawn: Node3D = PLAYER_SCENE.instantiate() as Node3D
	arena.add_child(pawn)
	pawn.call("set_player_data", callsign, callsign)
	var yaw: float = atan2(toward.z - feet.z, toward.x - feet.x)
	var state: Dictionary = {"x": feet.x, "y": feet.y + BODY_Y, "z": feet.z, "yaw": yaw, "pitch": 0.0,
		"hp": 100, "armor": 0, "weapon": "flechette", "score": 0}
	if not body.is_empty():
		state["body"] = body
	pawn.call("update_state", state, 0)
	pawn.position = Vector3(feet.x, feet.y + BODY_Y, feet.z)
	return pawn

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
