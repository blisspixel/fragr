extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_render_quality: " + message)

func _run() -> void:
	var path: String = "user://test-render-quality-%d.cfg" % OS.get_process_id()
	var preferences: FragrSettings = FragrSettings.new(path)
	_check(preferences.get_value("video", "display_mode") == 2, "fresh settings default to fullscreen")
	_check(RenderQuality.render_size(0, Vector2i(3440, 1440)) == Vector2i(3440, 1440), "native keeps ultrawide dimensions")
	_check(RenderQuality.render_size(720, Vector2i(3440, 1440)) == Vector2i(1720, 720), "lower world resolution preserves ultrawide aspect")
	_check(RenderQuality.render_size(2160, Vector2i(1920, 1080)) == Vector2i(1920, 1080), "oversize selection cannot accidentally supersample")
	_check(RenderQuality.render_scale(720, Vector2i.ZERO) == 1.0, "minimized output never divides by zero")
	var size: Vector2i = RenderQuality.window_size(2160, Vector2i(1366, 768))
	_check(size.x <= 1334 and size.y <= 688 and absf(float(size.x) / size.y - 16.0 / 9.0) < 0.01, "large window request fits usable screen without distortion")
	for renderer: String in ["gl_compatibility", "mobile", "unknown"]:
		_check(not RenderQuality.supports_fsr(renderer), "unsupported renderer cannot enable FSR: " + renderer)
	_check(RenderQuality.supports_fsr("forward_plus"), "Forward+ supports FSR")
	for key: String in ["quality", "upscaling", "resolution_height"]:
		for invalid: Variant in [true, "2", [], 99, -1, 1.5]:
			preferences.set_value("video", key, invalid)
			_check(preferences.get_value("video", key) == FragrSettings.DEFAULTS["video"][key], "invalid choice rejected: " + key)
	preferences.set_value("video", "resolution_height", 720)
	preferences.set_value("video", "quality", 2)
	preferences.set_value("video", "upscaling", 2)
	_check(preferences.save_to_disk() == OK, "graphics preferences save")
	var loaded: FragrSettings = FragrSettings.new(path)
	loaded.load_from_disk()
	_check(loaded.get_value("video", "quality") == 2 and loaded.get_value("video", "upscaling") == 2 and loaded.get_value("video", "resolution_height") == 720, "graphics choices survive restart")
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var environment: Environment = Environment.new()
	environment.ambient_light_color = Color("889988")
	environment.ambient_light_energy = 0.8
	var authored_color: Color = environment.ambient_light_color
	var authored_energy: float = environment.ambient_light_energy
	var renderer: String = RenderingServer.get_current_rendering_method()
	RenderQuality.apply(viewport, loaded, environment)
	_check(is_equal_approx(viewport.scaling_3d_scale, 2.0 / 3.0), "actual viewport gets selected world resolution")
	_check(viewport.scaling_3d_mode == (Viewport.SCALING_3D_MODE_FSR2 if RenderQuality.supports_fsr(renderer) else Viewport.SCALING_3D_MODE_BILINEAR), "actual renderer gets supported reconstruction")
	_check(viewport.msaa_3d == (Viewport.MSAA_DISABLED if RenderQuality.supports_fsr(renderer) else Viewport.MSAA_4X), "FSR2 does not stack multisampling")
	_check(environment.ssao_enabled == RenderQuality.supports_ao(renderer), "High uses supported contact shading")
	_check(environment.ambient_light_color == authored_color and environment.ambient_light_energy == authored_energy, "quality never rewrites authored ambient visibility")
	loaded.set_value("video", "quality", 0)
	loaded.set_value("video", "upscaling", 0)
	loaded.set_value("video", "resolution_height", 0)
	RenderQuality.apply(viewport, loaded, environment)
	_check(viewport.msaa_3d == Viewport.MSAA_DISABLED and viewport.positional_shadow_atlas_size == 1024 and not environment.ssao_enabled and viewport.scaling_3d_scale == 1.0, "changing back to Performance removes costly features")
	viewport.free()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		loaded.set_value("video", "display_mode", 0)
		loaded.set_value("video", "resolution_height", 720)
		loaded.apply_video()
		await process_frame
		await process_frame
		_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "real windowed transition")
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		_check(root.size.x <= usable.size.x and root.size.y <= usable.size.y, "actual window fits current display")
		loaded.set_value("video", "display_mode", 2)
		loaded.apply_video()
		await process_frame
		await process_frame
		RenderQuality.apply(root, loaded, environment)
		_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "real fullscreen transition")
		_check(is_equal_approx(root.scaling_3d_scale, RenderQuality.render_scale(720, root.size)), "root viewport updates the actual fullscreen 3D scale")
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "display changes never capture desktop input")
	DirAccess.remove_absolute(path)
	await process_frame
	if _failures == 0:
		print("test_render_quality: PASS defaults, validation, persistence, aspect, bounds and actual renderer settings")
	quit(0 if _failures == 0 else 1)
