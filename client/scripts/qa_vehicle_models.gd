extends SceneTree

var viewport: SubViewport
var camera: Camera3D

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("_run")

func _run() -> void:
	var directory: String = ProjectSettings.globalize_path("res://../.agents/vehicle-assets-20261006/prepared-review")
	DirAccess.make_dir_recursive_absolute(directory)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("8babae")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c1c8cd")
	environment.ambient_light_energy = 0.6
	world.environment = environment
	viewport.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	sun.light_energy = 1.3
	viewport.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	for kind: String in ["jeep", "boat", "light_aircraft"]:
		var model: JeepView = JeepView.new()
		model.kind = kind
		viewport.add_child(model)
		model.set_process(false)
		if not model.uses_prepared_model:
			push_error("vehicle model QA requires prepared " + kind)
			quit(1)
			return
		var size: float = 11.0 if kind == "light_aircraft" else 6.2
		camera.size = size
		for view: int in range(3):
			var angle: float = float(view) * PI * 0.5 + 0.35
			camera.position = Vector3(sin(angle) * 20.0, 6.5, cos(angle) * 20.0)
			camera.look_at(Vector3(0, 0.9, 0))
			await _capture(directory.path_join(kind + "-%d.png" % view))
		if model.propeller != null:
			model.propeller.rotation.x = PI / 2
			camera.size = 4.0
			camera.position = Vector3(8, 2.5, 4.0)
			camera.look_at(Vector3(3.5, 1.3, 0))
			await _capture(directory.path_join(kind + "-prop-quarter.png"))
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 85
		var driver: Vector3 = VehicleStep.seat_feet(Vector3.ZERO, 0.0, "driver", kind)
		camera.position = driver + Vector3(0, 1.15, 0)
		camera.look_at(camera.position + Vector3(5, -0.3, 0))
		await _capture(directory.path_join(kind + "-driver.png"))
		if model.gun != null:
			camera.position = VehicleStep.seat_feet(Vector3.ZERO, 0.0, "gunner", kind) + Vector3(0, 1.6, 0)
			camera.look_at(camera.position + Vector3(5, 0, 0))
			await _capture(directory.path_join(kind + "-gunner.png"))
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		model.free()
	print("qa_vehicle_models: PASS (prepared rig viewport captures; visual review required)")
	quit(0)

func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if viewport.get_texture().get_image().save_png(path) != OK:
		push_error("vehicle model QA cannot save " + path)
