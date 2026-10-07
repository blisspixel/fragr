extends SceneTree

## Offline renderer measurement with production geometry and pawn presenters.
## This does not measure server simulation or network capacity.
const PAWN: PackedScene = preload("res://scenes/player.tscn")
var view: SubViewport
var camera: Camera3D
var world: Node3D
var water: IslandWater
var actors: Array[Node3D] = []
var boats: Array[JeepView] = []
var output: String
var rows: Array[Dictionary] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("require exported MapInfo path and output directory")
		quit(1)
		return
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not MapGeometry.validation_error(info).is_empty() or int(info.get("map_id", 0)) != 7:
		push_error("invalid Holdfast MapInfo")
		quit(1)
		return
	output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	view = SubViewport.new()
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	world = Node3D.new()
	view.add_child(world)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = ArenaSky.build_environment("Holdfast Atoll")
	world.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -28, 0)
	sun.light_energy = 1.0
	world.add_child(sun)
	var cover: ArenaCover = ArenaCover.new()
	world.add_child(cover)
	cover.apply_map_info(info)
	water = cover.get_node("IslandWater") as IslandWater
	camera = Camera3D.new()
	camera.far = 1600
	world.add_child(camera)
	camera.current = true
	for index: int in range(64):
		var pawn: Node3D = PAWN.instantiate() as Node3D
		world.add_child(pawn)
		pawn.set_player_data(str(index), "Harbour %02d" % index)
		pawn._wear_body("human" if index % 2 == 0 else "synthetic")
		pawn.set_nameplate_enabled(false)
		actors.append(pawn)
	for index: int in range(2):
		var boat: JeepView = JeepView.new()
		boat.kind = "boat"
		world.add_child(boat)
		boat.speed = 10.0
		boats.append(boat)
	var preferences: FragrSettings = FragrSettings.new(output.path_join("unused-settings.cfg"))
	preferences.set_value("video", "resolution_height", 0)
	preferences.set_value("video", "pixel_scale", 0)
	for actor_count: int in [0, 64]:
		for actor: Node3D in actors:
			actor.visible = actor_count > 0
			actor.process_mode = Node.PROCESS_MODE_INHERIT if actor_count > 0 else Node.PROCESS_MODE_DISABLED
		for quality: int in range(3):
			preferences.set_value("video", "quality", quality)
			RenderQuality.apply(view, preferences, environment.environment)
			water.apply_quality(quality)
			for enabled: bool in [false, true]:
				water.visible = enabled
				var frame_ms: Array[float] = []
				var gpu_ms: Array[float] = []
				var cpu_ms: Array[float] = []
				var calls: int = 0
				for frame: int in range(240):
					_pose(float(frame) / 60.0)
					var start: int = Time.get_ticks_usec()
					await process_frame
					await RenderingServer.frame_post_draw
					if frame >= 60:
						frame_ms.append(float(Time.get_ticks_usec() - start) / 1000.0)
						gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
						cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
						calls = maxi(calls, RenderingServer.viewport_get_render_info(view.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
				rows.append({"actors": actor_count, "quality": quality, "water": enabled, "frames": frame_ms.size(), "frame_ms": _stats(frame_ms), "gpu_ms": _stats(gpu_ms), "render_cpu_ms": _stats(cpu_ms), "max_draw_calls": calls})
				if enabled:
					view.get_texture().get_image().save_png(output.path_join("shore-%d-actors-quality-%d.png" % [actor_count, quality]))
				print("water_measure: actors=%d quality=%d water=%s frame=%s gpu=%s" % [actor_count, quality, enabled, str(_stats(frame_ms)), str(_stats(gpu_ms))])
	camera.position = Vector3(0, 130, 215)
	camera.look_at(Vector3(0, 0, -20))
	await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(output.path_join("island-overview.png"))
	var receipt: Dictionary = {"schema": 1, "kind": "offline_presenter_workload", "renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(), "resolution": [1280, 720], "map_sha256": FileAccess.get_sha256(args[0]), "rows": rows}
	var file: FileAccess = FileAccess.open(output.path_join("measurement.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt, "\t") + "\n")
	file.close()
	quit(0)

func _pose(time: float) -> void:
	camera.position = Vector3(-100 + time * 1.5, 12, 110)
	camera.look_at(Vector3(-25, 2.2, 63))
	for index: int in range(actors.size()):
		var actor: Node3D = actors[index]
		var at: Vector3 = Vector3(-87 + (index % 8) * 2.3, 4.5, 45 + (index / 8) * 4.0 + sin(time + index) * 0.7)
		actor.set_predicted_position(at, 1.7)
	for index: int in range(boats.size()):
		boats[index].position = Vector3(-45 + time * 3.0, 2.2, 65 + index * 17)
		boats[index].rotation.y = 0

func _stats(values: Array[float]) -> Dictionary:
	values.sort()
	return {"p50": values[values.size() / 2], "p95": values[mini(values.size() - 1, ceili(values.size() * 0.95))], "p99": values[mini(values.size() - 1, ceili(values.size() * 0.99))]}
