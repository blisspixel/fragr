extends SceneTree

## Offline stills of the prepared campaign props (tools/campaign_props_20261025.json)
## for visual review. Needs a real renderer: launch windowed with
## --audio-driver Dummy.
##
## Turnarounds of every prepared prop beside a 1.8 m figure, under neutral light:
##   "$GODOT_BIN" --path client --audio-driver Dummy --windowed --resolution 1280x720 \
##     --script ../tools/preview_campaign_props.gd -- turn /abs/out
## Props in place, each level built from the server's own MapInfo (written by
## server/src/tests/map_info_writer.rs) with ArenaCover, the level's mission
## presenter and its sky, scene lights and practicals, as a match lights it:
##   "$GODOT_BIN" ... --script ../tools/preview_campaign_props.gd -- place /abs/views.json /abs/out [view prefix]
## views.json: {"levels": [{"map_info": "/abs/m19.json", "presenter": "M19Works",
##   "views": [{"name": "...", "eye": [x, y, z], "look": [x, y, z], "gray": false,
##   "union": [[x, floor, z, "sweeper"]], "free": [[x, floor, z]]}]}]}
## A view with "gray" is also shot in grayscale; "union" stands campaign Union
## pawns and "free" free fighters there for the faction readability check.
const ARENA_SCENE: PackedScene = preload("res://scenes/arena.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
## Server body centre above the floor (sim.rs PLAYER_FLOOR_Y).
const BODY_Y: float = 1.5
const TILE: int = 320
const WEAPONS: Dictionary[String, String] = {"clerk": "Tack", "sweeper": "Flechette", "heavy_sweeper": "Flechette",
	"auditor": "Tack", "redactor": "Shiv", "enforcer": "Flechette"}

var _shots: int = 0

func _initialize() -> void:
	set_meta("fragr_automated", true)
	set_meta("fragr_settings_path", "")
	set_meta("fragr_records_path", "")
	MouseCapture.release()
	call_deferred("_run")

func _fail(message: String) -> void:
	push_error("preview_campaign_props: " + message)
	quit(1)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("the preview needs a real renderer")
		return
	AudioServer.set_bus_mute(0, true)
	root.min_size = Vector2i(1280, 720)
	root.max_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "turn":
		await _turnarounds(args[1])
	elif args.size() in [3, 4] and args[0] == "place":
		await _place(args[1], args[2], args[3] if args.size() == 4 else "")
	else:
		_fail("usage: turn <out> | place <views.json> <out> [prefix]")
		return
	print("preview_campaign_props: wrote %d stills" % _shots)
	quit(0)

func _turnarounds(out: String) -> void:
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		_fail("cannot create " + out)
		return
	for prop: String in CampaignProps.NAMES:
		var strip: Image = Image.create(TILE * 4, TILE, false, Image.FORMAT_RGBA8)
		for index: int in range(4):
			var viewport: SubViewport = SubViewport.new()
			viewport.size = Vector2i(TILE, TILE)
			viewport.own_world_3d = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			root.add_child(viewport)
			var world: WorldEnvironment = WorldEnvironment.new()
			var environment: Environment = Environment.new()
			environment.background_mode = Environment.BG_COLOR
			environment.background_color = Color("6b6f73")
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.ambient_light_color = Color("c8c8c8")
			environment.ambient_light_energy = 0.55
			world.environment = environment
			viewport.add_child(world)
			for spec: Vector3 in [Vector3(-40, -35, 1.4), Vector3(-15, 150, 0.6)]:
				var light: DirectionalLight3D = DirectionalLight3D.new()
				light.rotation_degrees = Vector3(spec.x, spec.y, 0)
				light.light_energy = spec.z
				viewport.add_child(light)
			var model: Node3D = CampaignProps.instance(prop)
			if model == null:
				_fail("missing " + prop)
				return
			viewport.add_child(model)
			var box: AABB = CampaignProps.model_bounds(model)
			var figure: MeshInstance3D = MeshInstance3D.new()
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = 0.22
			capsule.height = 1.8
			figure.mesh = capsule
			var paint: StandardMaterial3D = StandardMaterial3D.new()
			paint.albedo_color = Color("3a2a48")
			figure.material_override = paint
			figure.position = Vector3(box.end.x + 0.5, 0.9, box.get_center().z)
			viewport.add_child(figure)
			box = box.merge(AABB(figure.position - Vector3(0.22, 0.9, 0.22), Vector3(0.44, 1.8, 0.44)))
			var centre: Vector3 = box.get_center()
			var radius: float = box.size.length() * 0.5
			var camera: Camera3D = Camera3D.new()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = radius * 2.1
			camera.near = 0.01
			camera.far = radius * 10.0
			var yaw: float = [35.0, 0.0, 90.0, 180.0][index]
			var pitch: float = [-22.0, -6.0, -6.0, -6.0][index]
			viewport.add_child(camera)
			camera.look_at_from_position(centre + Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0)) * Vector3(0, 0, 1) * radius * 4.0, centre, Vector3.UP)
			camera.make_current()
			for frame: int in range(3):
				await RenderingServer.frame_post_draw
			var image: Image = viewport.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			strip.blit_rect(image, Rect2i(0, 0, TILE, TILE), Vector2i(index * TILE, 0))
			viewport.queue_free()
		await process_frame
		if strip.save_png(out.path_join(prop + "-turn.png")) != OK:
			_fail("cannot save " + prop)
			return
		_shots += 1

func _place(views_path: String, out: String, only: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(views_path))
	if not parsed is Dictionary or not parsed.get("levels") is Array or DirAccess.make_dir_recursive_absolute(out) != OK:
		_fail("cannot read views or create " + out)
		return
	for level: Dictionary in parsed["levels"]:
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(level["map_info"])))
		if not info is Dictionary:
			_fail("cannot read MapInfo " + str(level["map_info"]))
			return
		var views: Array = []
		for view: Dictionary in level["views"]:
			if only.is_empty() or str(view["name"]).begins_with(only):
				views.append(view)
		if views.is_empty():
			continue
		await _level(info, str(level.get("presenter", "")), views, out)

func _level(info: Dictionary, presenter_name: String, views: Array, out: String) -> void:
	var settings: FragrSettings = FragrSettings.new("user://preview_campaign_settings.cfg")
	var arena: Node3D = Node3D.new()
	arena.name = "Arena"
	root.add_child(arena)
	var layout: Node = ARENA_SCENE.instantiate()
	layout.name = "Layout"
	arena.add_child(layout)
	var cover: ArenaCover = ArenaCover.new()
	arena.add_child(cover)
	cover.apply_map_info(info)
	var presenter: Node3D = _presenter(presenter_name)
	if presenter != null:
		root.add_child(presenter)
		presenter.call("configure_map", info)
	var map_name: String = str(info.get("map_name", ""))
	var world: WorldEnvironment = _world_environment(layout)
	world.environment = ArenaSky.build_environment(map_name)
	RenderQuality.apply(root, settings, world.environment)
	ArenaSky.apply_scene_lights(layout, map_name)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 400.0
	arena.add_child(camera)
	camera.make_current()
	ArenaSky.apply_view_fill(camera, map_name)
	RenderQuality.apply_practicals(arena, settings)
	for i: int in range(8):
		await process_frame
	for view: Dictionary in views:
		var pawns: Array[Node3D] = []
		var tick: int = 100
		var index: int = 0
		for spot: Array in view.get("union", []):
			pawns.append(_union(arena, spot, view["eye"], tick, index))
			index += 1
		for spot: Array in view.get("free", []):
			pawns.append(_free(arena, spot, view["eye"], index))
			index += 1
		for step: int in range(30):
			for pawn: Node3D in pawns:
				pawn._process(0.05)
			await process_frame
		camera.position = _vector(view["eye"])
		camera.look_at(_vector(view["look"]), Vector3.UP)
		await _shoot(out, str(view["name"]))
		if bool(view.get("gray", false)):
			world.environment.adjustment_enabled = true
			world.environment.adjustment_saturation = 0.0
			await _shoot(out, str(view["name"]) + "_gray")
			world.environment.adjustment_enabled = false
			world.environment.adjustment_saturation = 1.0
		for pawn: Node3D in pawns:
			pawn.queue_free()
		await process_frame
	if presenter != null:
		presenter.queue_free()
	arena.queue_free()
	for i: int in range(3):
		await process_frame

func _presenter(name: String) -> Node3D:
	match name:
		"M02Ward": return M02Ward.new()
		"M06Port": return M06Port.new()
		"M10Ship": return M10Ship.new()
		"M13Foundry": return M13Foundry.new()
		"M19Works": return M19Works.new()
		"M20Waterworks": return M20Waterworks.new()
	return null

## A campaign Union pawn standing on `spot` [x, floor, z, kind], facing the eye.
func _union(arena: Node3D, spot: Array, eye: Array, tick: int, index: int) -> Node3D:
	var kind: String = str(spot[3]) if spot.size() > 3 else "sweeper"
	var feet: Vector3 = Vector3(float(spot[0]), float(spot[1]), float(spot[2]))
	var pawn: Node3D = PLAYER_SCENE.instantiate() as Node3D
	arena.add_child(pawn)
	pawn.set_process(false)
	pawn.set("nameplate_enabled", false)
	pawn.call("set_player_data", "union-%s-%d" % [kind, index], kind)
	var yaw: float = atan2(float(eye[2]) - feet.z, float(eye[0]) - feet.x)
	pawn.call("update_state", {"id": "union-%s-%d" % [kind, index], "name": kind, "x": feet.x, "y": feet.y + BODY_Y, "z": feet.z,
		"yaw": yaw, "hp": 100, "weapon": WEAPONS.get(kind, "Flechette"), "ducking": false,
		"campaign": {"side": "union", "kind": kind, "phase": "moving", "phase_started": 1, "phase_ends": 1}}, tick)
	pawn.call("snap_authoritative_position")
	pawn.call("set_nameplate_enabled", false)
	return pawn

## A free human fighter standing on `spot` [x, floor, z], facing the eye.
func _free(arena: Node3D, spot: Array, eye: Array, index: int) -> Node3D:
	var feet: Vector3 = Vector3(float(spot[0]), float(spot[1]), float(spot[2]))
	var pawn: Node3D = PLAYER_SCENE.instantiate() as Node3D
	arena.add_child(pawn)
	pawn.set_process(false)
	pawn.call("set_player_data", "free-%d" % index, "FREE %d" % index)
	var yaw: float = atan2(float(eye[2]) - feet.z, float(eye[0]) - feet.x)
	pawn.call("update_state", {"x": feet.x, "y": feet.y + BODY_Y, "z": feet.z, "yaw": yaw, "pitch": 0.0,
		"hp": 100, "armor": 0, "weapon": "flechette", "score": 0, "body": "human"}, 0)
	pawn.call("snap_authoritative_position")
	pawn.call("set_nameplate_enabled", false)
	return pawn

func _shoot(out: String, name: String) -> void:
	for i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.save_png(out.path_join(name + ".png")) != OK:
		_fail("could not save " + name)
		return
	_shots += 1

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child: Node in node.get_children():
		var found: WorldEnvironment = _world_environment(child)
		if found != null:
			return found
	return null
