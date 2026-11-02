extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("test_render_quality: " + message)

## The five tiers as data: Low, Medium and High stay exactly the earlier
## Performance, Balanced and High; Potato and Ultra add their own; the
## renderer gates what it lacks; the governor's steps and render scale.
func _tiers(viewport: SubViewport, loaded: LocalExceptionSettings, environment: Environment, practical: OmniLight3D, renderer: String) -> void:
	var earlier: Array[Dictionary] = [{"msaa": 0, "atlas": 1024, "fixtures": false, "ao": 0, "glow": false, "water": 0},
		{"msaa": 2, "atlas": 2048, "fixtures": true, "ao": 1, "glow": true, "water": 1},
		{"msaa": 4, "atlas": 4096, "fixtures": true, "ao": 2, "glow": true, "water": 2}]
	for index: int in range(3):
		var spec: Dictionary = RenderQuality.TIERS[RenderQuality.LOW + index]
		var old: Dictionary = earlier[index]
		_check(int(spec["msaa"]) == old["msaa"] and int(spec["directional_atlas"]) == old["atlas"] and int(spec["positional_atlas"]) == old["atlas"]
			and bool(spec["fixture_shadows"]) == old["fixtures"] and int(spec["ssao"]) == old["ao"] and bool(spec["glow"]) == old["glow"]
			and int(spec["water"]) == old["water"] and int(spec["shadow_filter"]) == -1 and not bool(spec["ssil"]) and float(spec["practical_fade"]) == 0.0,
			"%s is exactly the earlier preset" % RenderQuality.TIER_NAMES[RenderQuality.LOW + index])
	var potato: Dictionary = RenderQuality.TIERS[RenderQuality.POTATO]
	_check(int(potato["msaa"]) == 0 and int(potato["positional_atlas"]) == 512 and int(potato["shadow_filter"]) == RenderingServer.SHADOW_QUALITY_HARD
		and is_equal_approx(float(potato["effects"]), 0.25) and is_equal_approx(float(potato["practical_fade"]), 24.0), "Potato trims shadows, lamp reach and effects")
	_check(RenderQuality.effective_tier(RenderQuality.ULTRA, "gl_compatibility") == RenderQuality.HIGH and RenderQuality.effective_tier(RenderQuality.ULTRA, "forward_plus") == RenderQuality.ULTRA
		and not RenderQuality.tier_available(RenderQuality.ULTRA, "gl_compatibility"), "Ultra is Forward+ only and draws as High elsewhere")
	_check(bool(RenderQuality.tier_spec(RenderQuality.ULTRA, "forward_plus")["volumetric_fog"]) and not bool(RenderQuality.tier_spec(RenderQuality.ULTRA, "gl_compatibility")["ssil"]), "Ultra asks for volumetric fog on Forward+ (a venue opt-in still gates it); Compatibility has no bounce light")
	_check(int(RenderQuality.tier_spec(RenderQuality.HIGH, "gl_compatibility")["ssao"]) == 2 and not bool(RenderQuality.tier_spec(RenderQuality.HIGH, "gl_compatibility")["fixture_shadows"]),
		"Compatibility keeps SSAO and drops fixture shadows")
	# Potato on the real viewport and a practical with an authored fade.
	practical.distance_fade_enabled = true
	practical.distance_fade_begin = 40.0
	practical.distance_fade_length = 10.0
	practical.distance_fade_shadow = 30.0
	if practical.has_meta(&"localexception_authored_fade"):
		practical.remove_meta(&"localexception_authored_fade")
	loaded.set_value("video", "quality", RenderQuality.POTATO)
	loaded.set_value("video", "pixel_scale", 0)
	RenderQuality.apply(viewport, loaded, environment)
	RenderQuality.apply_practicals(root, loaded)
	_check(viewport.msaa_3d == Viewport.MSAA_DISABLED and viewport.positional_shadow_atlas_size == 512 and is_equal_approx(viewport.mesh_lod_threshold, 2.0)
		and not environment.ssao_enabled and is_equal_approx(RenderQuality.effects_budget, 0.25), "Potato applies to the real viewport")
	_check(practical.distance_fade_enabled and is_equal_approx(practical.distance_fade_begin, 24.0) and practical.distance_fade_shadow <= 24.0, "Potato fades lamps at 24 m")
	_check(VfxDecals.mark_limit() == 12 and VfxDecals.scorch_limit() == 3 and GrenadeEffects.rocket_lights() == 0, "Potato's quarter budget reaches marks, scorches and exhaust lights")
	loaded.set_value("video", "quality", RenderQuality.HIGH)
	RenderQuality.apply(viewport, loaded, environment)
	RenderQuality.apply_practicals(root, loaded)
	_check(is_equal_approx(practical.distance_fade_begin, 40.0) and is_equal_approx(practical.distance_fade_shadow, 30.0) and is_equal_approx(viewport.mesh_lod_threshold, 1.0)
		and VfxDecals.mark_limit() == VfxDecals.MAX_MARKS and GrenadeEffects.rocket_lights() == GrenadeEffects.ROCKET_LIGHTS, "High restores the authored fade and the full budget")
	loaded.set_value("video", "quality", RenderQuality.ULTRA)
	RenderQuality.apply(viewport, loaded, environment)
	RenderQuality.apply_practicals(root, loaded)
	if renderer == "forward_plus":
		_check(environment.ssil_enabled and is_equal_approx(practical.distance_fade_shadow, 45.0) and is_equal_approx(RenderQuality.decal_life, 1.5), "Ultra adds bounce light, longer lamp shadows and decal life")
		_check(not environment.volumetric_fog_enabled and not environment.ssr_enabled, "no venue opts into volumetric fog or reflections yet")
		environment.set_meta(RenderQuality.VOLUMETRIC_META, 0.01)
		environment.set_meta(RenderQuality.SSR_META, true)
		RenderQuality.apply_environment(environment, loaded)
		_check(environment.volumetric_fog_enabled and environment.ssr_enabled, "a venue opt-in turns them on at Ultra")
		environment.remove_meta(RenderQuality.VOLUMETRIC_META)
		environment.remove_meta(RenderQuality.SSR_META)
	else:
		_check(not environment.ssil_enabled and viewport.msaa_3d == Viewport.MSAA_4X, "Ultra draws as High on this renderer")
	# Governor steps lower one thing each, never the grid.
	RenderQuality.reductions = PackedStringArray(["ssao", "msaa"])
	var reduced: Dictionary = RenderQuality.tier_spec(RenderQuality.HIGH, "forward_plus")
	_check(int(reduced["ssao"]) == 1 and int(reduced["msaa"]) == 2, "governor steps lower SSAO and MSAA one level")
	_check(int(RenderQuality.tier_spec(RenderQuality.HIGH, "forward_plus", false)["msaa"]) == 4, "the tier itself is unchanged")
	RenderQuality.reductions = PackedStringArray()
	# Render scale with the pixel look off; ignored under it.
	loaded.set_value("video", "render_scale", 67)
	RenderQuality.apply(viewport, loaded, environment)
	_check(is_equal_approx(viewport.scaling_3d_scale, 0.67), "render scale lowers the 3D buffer")
	loaded.set_value("video", "render_scale", 150)
	loaded.set_value("video", "upscaling", 1)
	RenderQuality.apply(viewport, loaded, environment)
	_check(is_equal_approx(viewport.scaling_3d_scale, 1.5) and viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR, "supersampling is Bilinear only")
	loaded.set_value("video", "pixel_scale", 1)
	RenderQuality.apply(viewport, loaded, environment)
	_check(viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_NEAREST and is_equal_approx(viewport.scaling_3d_scale, 0.5), "the pixel look owns the 3D buffer; render scale never splits its grid")
	loaded.set_value("video", "render_scale", 100)
	loaded.set_value("video", "upscaling", 0)
	loaded.set_value("video", "pixel_scale", 0)
	_check(RenderQuality.preset_features(RenderQuality.POTATO, "forward_plus", {}, Vector2i(1920, 1080)).contains("hard shadow edges")
		and RenderQuality.preset_features(RenderQuality.ULTRA, "forward_plus", {}, Vector2i(1920, 1080)).contains("bounce light on")
		and not RenderQuality.preset_features(RenderQuality.ULTRA, "gl_compatibility", {}, Vector2i(1920, 1080)).contains("bounce light"), "feature text reads the same spec")
	_check(RenderQuality.RENDER_COST_REVISION >= 1 and RenderQuality.TIERS.size() == RenderQuality.TIER_NAMES.size(), "one table, one name per tier")

func _run() -> void:
	var path: String = "user://test-render-quality-%d.cfg" % OS.get_process_id()
	var preferences: LocalExceptionSettings = LocalExceptionSettings.new(path)
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
	_check(RenderQuality.pixel_factor(0, Vector2i(1920, 1080)) == 1, "native world pixels do not scale")
	_check(RenderQuality.pixel_factor(1, Vector2i(1920, 1080)) == 2 and RenderQuality.pixel_factor(2, Vector2i(1920, 1080)) == 3 and RenderQuality.pixel_factor(3, Vector2i(1920, 1080)) == 4, "1080p pixel looks are 540, 360 and 270 world lines")
	_check(RenderQuality.pixel_factor(3, Vector2i(3840, 2160)) == 8 and RenderQuality.pixel_factor(1, Vector2i(1280, 720)) == 1, "pixel looks stay whole numbers on other outputs")
	_check(RenderQuality.pixel_factor(9, Vector2i(1920, 1080)) == 1 and RenderQuality.pixel_factor(2, Vector2i.ZERO) == 1, "invalid pixel look or minimized output never divides")
	for key: String in ["quality", "upscaling", "resolution_height", "pixel_scale"]:
		for invalid: Variant in [true, "2", [], 99, -1, 1.5]:
			preferences.set_value("video", key, invalid)
			_check(preferences.get_value("video", key) == LocalExceptionSettings.DEFAULTS["video"][key], "invalid choice rejected: " + key)
	for invalid: Variant in [5, -1, "3", 1.0]:
		preferences.set_value("video", "quality", invalid)
		_check(preferences.get_value("video", "quality") == RenderQuality.MEDIUM, "an out-of-range tier falls back to Medium: %s" % str(invalid))
	for invalid: Variant in [99, 0, 100.0, "100", 200]:
		preferences.set_value("video", "render_scale", invalid)
		_check(preferences.get_value("video", "render_scale") == 100, "an unknown render scale falls back to 100: %s" % str(invalid))
	preferences.set_value("video", "resolution_height", 720)
	preferences.set_value("video", "quality", RenderQuality.HIGH)
	preferences.set_value("video", "upscaling", 2)
	_check(preferences.save_to_disk() == OK, "graphics preferences save")
	var loaded: LocalExceptionSettings = LocalExceptionSettings.new(path)
	loaded.load_from_disk()
	_check(loaded.get_value("video", "quality") == RenderQuality.HIGH and loaded.get_value("video", "upscaling") == 2 and loaded.get_value("video", "resolution_height") == 720, "graphics choices survive restart")
	_check(LocalExceptionSettings.new("user://unused").get_value("video", "pixel_scale") == 1 and not LocalExceptionSettings.new("user://unused").get_value("video", "dither"),
		"a fresh settings file starts on Fine world pixels with the dither off")
	_check(RenderQuality.pixel_factor(1, Vector2i(1280, 720)) == 1, "the Fine default stays native at 720p")
	# Reconstruction and resolution below are checked with the pixel look off.
	loaded.set_value("video", "pixel_scale", 0)
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
	environment.glow_intensity = 0.5
	RenderQuality.apply_environment(environment, loaded)
	_check(environment.glow_enabled, "High keeps fixture glow when the venue authors it")
	_check(not environment.ssil_enabled and not environment.volumetric_fog_enabled and not environment.ssr_enabled, "High adds no bounce light, volumetric fog or reflections")
	loaded.set_value("video", "pixel_scale", 2)
	RenderQuality.apply(viewport, loaded, environment)
	_check(viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_NEAREST and is_equal_approx(viewport.scaling_3d_scale, 1.0 / 3.0), "world pixels use an exact nearest upscale")
	_check(viewport.msaa_3d == Viewport.MSAA_4X, "world pixels replace FSR2, so multisampling returns")
	var practical: OmniLight3D = OmniLight3D.new()
	practical.add_to_group(ArenaSky.PRACTICAL_GROUP)
	root.add_child(practical)
	RenderQuality.apply_practicals(root, loaded)
	_check(practical.shadow_enabled == RenderQuality.supports_fixture_shadows(renderer) and practical.omni_shadow_mode == OmniLight3D.SHADOW_CUBE, "High practical fixtures cast cube shadows where the renderer keeps them stable")
	_check(not RenderQuality.supports_fixture_shadows("gl_compatibility") and RenderQuality.supports_fixture_shadows("forward_plus"), "Compatibility drops fixture shadow maps (#521), Forward+ keeps them")
	loaded.set_value("video", "quality", RenderQuality.MEDIUM)
	RenderQuality.apply_practicals(root, loaded)
	_check(practical.shadow_enabled == RenderQuality.supports_fixture_shadows(renderer) and (practical.omni_shadow_mode == OmniLight3D.SHADOW_DUAL_PARABOLOID) == RenderQuality.supports_dual_paraboloid(renderer), "Medium uses paraboloid shadows only where the renderer has them")
	_check(not RenderQuality.supports_dual_paraboloid("gl_compatibility"), "Compatibility never receives paraboloid omni shadows")
	loaded.set_value("video", "quality", RenderQuality.HIGH)
	var owner: Node = Node.new()
	root.add_child(owner)
	loaded.set_value("video", "dither", true)
	RenderQuality.apply_dither(owner, viewport, loaded)
	var layer: CanvasLayer = owner.get_node_or_null(RenderQuality.DITHER_LAYER) as CanvasLayer
	_check(layer != null and layer.layer < 1, "dither sits under the HUD layer")
	var material: ShaderMaterial = (layer.get_node("Dither") as ColorRect).material as ShaderMaterial if layer != null else null
	_check(material != null and is_equal_approx(float(material.get_shader_parameter("pixel_size")), 3.0), "dither grid follows the world pixel size")
	_check(material != null and is_equal_approx(float(material.get_shader_parameter("steps")), RenderQuality.DITHER_STEPS)
		and not str(material.shader.code).contains("palette["), "the dither steps value and never snaps to a swatch list")
	RenderQuality.apply_dither(owner, viewport, loaded)
	_check(owner.get_child_count() == 1, "reapplying never stacks a second dither layer")
	loaded.set_value("video", "dither", false)
	RenderQuality.apply_dither(owner, viewport, loaded)
	_check(owner.get_node_or_null(RenderQuality.DITHER_LAYER) == null, "turning dither off removes the layer")
	owner.free()
	loaded.set_value("video", "quality", RenderQuality.LOW)
	loaded.set_value("video", "upscaling", 0)
	loaded.set_value("video", "resolution_height", 0)
	loaded.set_value("video", "pixel_scale", 0)
	RenderQuality.apply(viewport, loaded, environment)
	RenderQuality.apply_practicals(root, loaded)
	_check(viewport.msaa_3d == Viewport.MSAA_DISABLED and viewport.positional_shadow_atlas_size == 1024 and not environment.ssao_enabled and not environment.glow_enabled and viewport.scaling_3d_scale == 1.0, "changing back to Low removes costly features")
	_check(not practical.shadow_enabled and viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_NEAREST, "Low drops practical shadow maps and the pixel upscale")
	loaded.set_value("video", "quality", RenderQuality.MEDIUM)
	RenderQuality.apply_environment(environment, loaded)
	_check(environment.ssao_enabled == RenderQuality.supports_ao(renderer), "Medium adds supported contact shading")
	_tiers(viewport, loaded, environment, practical, renderer)
	practical.free()
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
