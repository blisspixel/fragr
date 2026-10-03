extends SceneTree

const Shotgun = preload("res://art/models/shotgun_source.gd")
const Sweeper = preload("res://art/models/sweeper_source.gd")
const Clips = preload("res://art/models/model_clips.gd")
const Facility = preload("res://scripts/facility_geometry.gd")
const OUTPUT: String = "res://assets/models/"
var _viewport: SubViewport
var _camera: Camera3D
var _environment: Environment

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) != OK:
		_fail("cannot create model directory")
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1200, 900)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world: WorldEnvironment = WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CLEAR_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("d3d9d7")
	_environment.ambient_light_energy = 0.8
	world.environment = _environment
	_viewport.add_child(world)
	for spec: Vector3 in [Vector3(-32, -40, 1.6), Vector3(-15, 130, 0.8)]:
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(spec.x, spec.y, 0)
		light.light_energy = spec.z
		_viewport.add_child(light)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1.8
	_viewport.add_child(_camera)
	var source: RefCounted = Shotgun.new()
	var gun: Node3D = source.build()
	_viewport.add_child(gun)
	if not _export(gun, "shotgun.glb"):
		return
	_camera.position = Vector3(1.6, 0.9, 0.4)
	_camera.look_at(Vector3(0, 0, -0.25))
	await _capture("shotgun_studio.png")
	gun.free()
	gun = source.build(true)
	_viewport.add_child(gun)
	if not _export(gun, "shotgun_hands.glb"):
		return
	_viewport.size = Vector2i(964, 720)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 58.0
	_camera.position = Vector3(0.15, 0.16, 0.16)
	_camera.look_at(Vector3(0.0, 0.04, -0.8))
	var times: Array[float] = [-1.0, 0.0, 0.08, 0.14, 0.18, 0.23, 0.28, 0.31, 0.35, 0.40, 0.44, 0.5]
	var strip: Image = Image.create(241 * times.size(), 180, false, Image.FORMAT_RGBA8)
	for index: int in range(times.size()):
		source.pose(gun, times[index] if times[index] >= 0.0 else 1.0)
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var picture: Image = _viewport.get_texture().get_image()
		picture.convert(Image.FORMAT_RGBA8)
		picture.resize(241, 180, Image.INTERPOLATE_LANCZOS)
		for y: int in range(180):
			for x: int in range(241):
				var pixel: Color = picture.get_pixel(x, y)
				if pixel.a < 0.5:
					picture.set_pixel(x, y, Color.TRANSPARENT)
				else:
					pixel.a = 1.0
					picture.set_pixel(x, y, pixel)
		if picture.save_png(OUTPUT + "shotgun_pose_%02d.png" % index) != OK:
			_fail("could not save weapon pose")
			return
		strip.blit_rect(picture, Rect2i(0, 0, 241, 180), Vector2i(index * 241, 0))
	strip.save_png(OUTPUT + "shotgun_motion.png")
	gun.free()
	var bot_source: RefCounted = Sweeper.new()
	var bot: Node3D = bot_source.build_pose()
	_viewport.add_child(bot)
	Clips.attach(bot, bot_source)
	if not _export(bot, "sweeper.glb"):
		return
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.25
	_camera.position = Vector3(2.0, 1.2, 4.0)
	_camera.look_at(Vector3(0, 0.9, 0))
	await _capture("sweeper_studio.png")
	bot.free()
	var latch: LatchView = LatchView.new()
	latch.name = "Latch"
	_viewport.add_child(latch)
	if not _export(latch, "latch.glb"):
		return
	_camera.size = 2.2
	_camera.position = Vector3(1.2, 1.2, 4.0)
	_camera.look_at(Vector3(0, 0.95, 0))
	await _capture("latch_studio.png")
	latch.free()
	for kind: String in ["vent", "terminal", "lockers", "strip_light", "property_sign"]:
		var fixture: Node3D = Facility.new().build(kind, Vector2(1.0, 0.7))
		_viewport.add_child(fixture)
		if not _export(fixture, "fixture_" + kind + ".glb"):
			return
		fixture.free()
	var sources: Dictionary[String, String] = {}
	for path: String in ["res://scripts/model_geometry.gd", "res://art/models/shotgun_source.gd", "res://art/models/sweeper_source.gd", "res://art/models/model_clips.gd", "res://scripts/facility_geometry.gd", "res://art/models/bake.gd", "res://scripts/latch_view.gd", "res://assets/models/finishes/wood.png", "res://assets/models/finishes/metal.png", "res://assets/models/finishes/enamel.png"]:
		sources[path] = FileAccess.get_sha256(path)
	var file: FileAccess = FileAccess.open(OUTPUT + "manifest.json", FileAccess.WRITE)
	if file == null:
		_fail("could not write model manifest")
		return
	var models: Array[Dictionary] = []
	for name: String in DirAccess.get_files_at(OUTPUT):
		if name.ends_with(".glb"):
			models.append({"file": name, "sha256": FileAccess.get_sha256(OUTPUT + name)})
	file.store_string(JSON.stringify({"schema": 1, "sources": sources, "engine": Engine.get_version_info()["string"],
		"models": models,
		"pose_seconds": times, "canvas": [241, 180]}, "\t") + "\n")
	file.close()
	_viewport.queue_free()
	await process_frame
	print("model_bake: PASS")
	quit()

func _export(model: Node3D, name: String) -> bool:
	var document: GLTFDocument = GLTFDocument.new()
	document.image_format = "PNG"
	var state: GLTFState = GLTFState.new()
	if document.append_from_scene(model, state) != OK or document.write_to_filesystem(state, OUTPUT + name) != OK:
		_fail("could not export " + name)
		return false
	return _metadata(OUTPUT + name)

func _metadata(path: String) -> bool:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 20 or bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != bytes.size():
		_fail("invalid exported GLB header")
		return false
	var length: int = bytes.decode_u32(12)
	if length > bytes.size() - 20 or bytes.decode_u32(16) != 0x4e4f534a:
		_fail("invalid exported GLB JSON chunk")
		return false
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("asset") is Dictionary:
		_fail("invalid exported GLB document")
		return false
	# Optional software credit is not product authorship. Preserve copyright.
	parsed["asset"].erase("generator")
	var json: PackedByteArray = JSON.stringify(parsed).to_utf8_buffer()
	while json.size() % 4 != 0:
		json.append(32)
	var remainder: PackedByteArray = bytes.slice(20 + length)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write export metadata")
		return false
	file.store_32(0x46546c67)
	file.store_32(2)
	file.store_32(20 + json.size() + remainder.size())
	file.store_32(json.size())
	file.store_32(0x4e4f534a)
	file.store_buffer(json)
	file.store_buffer(remainder)
	file.close()
	return true

func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var picture: Image = _viewport.get_texture().get_image()
	if picture.save_png(OUTPUT + name) != OK:
		_fail("could not save " + name)

func _fail(message: String) -> void:
	push_error("model_bake: " + message)
	quit(1)
