extends SceneTree

## Render a Rust active-frame fixture. This is geometry inspection, not a live
## campaign or network playtest. Generate the recording with export_enclosed_capture.
const PHASES: Array[String] = ["underpass", "stairs_up", "upper_exit", "head_contact", "underside_shot"]
var _out: String
var _stills: Array[Image] = []
var _receipts: Array[Dictionary] = []

func _initialize() -> void:
	set_meta("fragr_automated", true)
	MouseCapture.release()
	call_deferred("_run")

func _finalize() -> void:
	MouseCapture.release()

func _fail(message: String) -> void:
	push_error("qa_enclosed: " + message)
	quit(1)

func _vector(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3:
		return Vector3.INF
	for component: Variant in value:
		if not (component is float or component is int) or not is_finite(float(component)):
			return Vector3.INF
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _run() -> void:
	var path: String = ProjectSettings.globalize_path("res://../.agents/qa/enclosed-session.json")
	var source: FileAccess = FileAccess.open(path, FileAccess.READ)
	if source == null or source.get_length() > 5_000_000:
		_fail("missing or oversized fixture recording")
		return
	var value: Variant = JSON.parse_string(source.get_as_text())
	if not value is Dictionary or value.get("schema_version") != 1 or value.get("kind") != "active_frame_fixture":
		_fail("invalid recording contract")
		return
	var recording: Dictionary = value
	if not recording.get("map") is Dictionary or not recording.get("frames") is Array:
		_fail("missing map or frames")
		return
	var map: Dictionary = recording["map"]
	var frames: Array = recording["frames"]
	if MapGeometry.validation_error(map) != "" or frames.is_empty() or frames.size() > 10_000:
		_fail("invalid geometry or frame count")
		return
	for entry: Variant in frames:
		if not entry is Dictionary or not _vector(entry.get("feet")).is_finite() or entry.get("phase") not in PHASES or not entry.get("shots") is Array:
			_fail("invalid recorded frame")
			return
		for key: String in ["yaw", "pitch"]:
			if not (entry.get(key) is float or entry.get(key) is int) or not is_finite(float(entry[key])):
				_fail("invalid recorded facing")
				return
	_out = OS.get_environment("FRAGR_QA_DIR")
	if _out.is_empty():
		_fail("set FRAGR_QA_DIR to an inspection output directory")
		return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_fail("cannot create output directory")
		return
	root.size = Vector2i(1280, 720)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var cover: ArenaCover = ArenaCover.new()
	world.add_child(cover)
	cover.apply_map_info(map)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("171b1c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d5c8ac")
	environment.ambient_light_energy = 0.6
	environment_node.environment = environment
	world.add_child(environment_node)
	var light: OmniLight3D = OmniLight3D.new()
	light.position = Vector3(-2, 4.5, -5)
	light.omni_range = 30.0
	light.light_energy = 2.0
	world.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 85.0
	camera.near = 0.05
	world.add_child(camera)
	camera.make_current()
	var effects: ShotEffects = ShotEffects.new()
	world.add_child(effects)
	var label: Label = Label.new()
	label.position = Vector2(16, 16)
	label.add_theme_font_size_override("font_size", 18)
	root.add_child(label)
	var phase_index: int = 0
	var previous_phase: String = ""
	for index: int in range(frames.size()):
		var frame: Dictionary = frames[index]
		var phase: String = frame["phase"]
		if phase != previous_phase:
			phase_index = 0
			previous_phase = phase
		var feet: Vector3 = _vector(frame["feet"])
		camera.position = feet + Vector3(0, MoveStep.EYE_HEIGHT, 0)
		camera.rotation = Vector3(float(frame["pitch"]), ServerYaw.camera_rotation_y(float(frame["yaw"])), 0)
		label.text = "GEOMETRY FIXTURE: %s | frame %d | feet %.2f, %.2f, %.2f" % [phase, index, feet.x, feet.y, feet.z]
		effects.clear()
		effects.ingest(index, frame["shots"])
		effects.set_process(false)
		await RenderingServer.frame_post_draw
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			_fail("desktop pointer was captured")
			return
		var last_in_phase: bool = index + 1 == frames.size() or frames[index + 1]["phase"] != phase
		var stride: int = 2 if phase == "head_contact" else 30
		var head_strike: bool = phase == "head_contact" and phase_index < 3
		if head_strike or phase_index % stride == 0 or last_in_phase or not frame["shots"].is_empty():
			var picture: Image = root.get_texture().get_image()
			var name: String = "%04d_%s.png" % [index, phase]
			if picture == null or picture.save_png(_out.path_join(name)) != OK:
				_fail("cannot save rendered frame")
				return
			_receipts.append({"file": name, "frame": index, "phase": phase, "feet": frame["feet"], "shots": frame["shots"]})
			picture.convert(Image.FORMAT_RGBA8)
			picture.resize(320, 180, Image.INTERPOLATE_NEAREST)
			_stills.append(picture)
		phase_index += 1
	var sheet: Image = Image.create(1280, ceili(float(_stills.size()) / 4.0) * 180, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	for index: int in range(_stills.size()):
		sheet.blit_rect(_stills[index], Rect2i(0, 0, 320, 180), Vector2i((index % 4) * 320, floori(float(index) / 4.0) * 180))
	var manifest: FileAccess = FileAccess.open(_out.path_join("manifest.json"), FileAccess.WRITE)
	if sheet.save_png(_out.path_join("contact.png")) != OK or manifest == null:
		_fail("cannot save capture evidence")
		return
	manifest.store_string(JSON.stringify({"kind": "active_frame_fixture", "renderer": RenderingServer.get_current_rendering_driver_name(), "frames": frames.size(), "captures": _receipts}, "\t"))
	print("qa_enclosed: PASS %d active frames, %d inspected samples required" % [frames.size(), _stills.size()])
	quit(0)
