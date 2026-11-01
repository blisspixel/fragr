extends RefCounted
class_name RenderQuality
## One portable presentation path. Preferences never change simulation geometry.

const RESOLUTION_HEIGHTS: Array[int] = [0, 720, 900, 1080, 1440, 2160]
## Pixel look targets in world lines: off, fine, medium, chunky. The factor is
## the nearest whole number that reaches the target on the actual output, so
## every choice is an exact integer upscale and the HUD stays native.
const PIXEL_TARGETS: Array[int] = [0, 540, 360, 270]
const DITHER_SHADER: Shader = preload("res://assets/shaders/value_dither.gdshader")
const DITHER_LAYER: String = "WorldDither"
## Sits over the 3D frame and under the HUD (layer 1) and menus.
const DITHER_CANVAS_LAYER: int = -1
## Value steps the ordered dither shades in. Each pixel keeps its hue, so a
## Union red tell or a cyan working light is never dithered into another
## colour (see value_dither.gdshader).
const DITHER_STEPS: float = 10.0

## Five tiers, `video/quality` 0 to 4. Low, Medium and High are exactly the
## three presets earlier builds called Performance, Balanced and High, so the
## measurements taken of those still describe them.
const POTATO: int = 0
const LOW: int = 1
const MEDIUM: int = 2
const HIGH: int = 3
const ULTRA: int = 4
const DEFAULT_TIER: int = MEDIUM
const TIER_NAMES: Array[String] = ["Potato", "Low", "Medium", "High", "Ultra"]
## Bump in any change to a tier's contents, a shader's cost, the benchmark
## scene or a venue's lighting cost (the same discipline as WORKLOAD_ID). A
## saved auto-tune from another revision is stale and a re-tune is offered.
const RENDER_COST_REVISION: int = 1
## 3D render scale steps, percent of the output (pixel look off only). Above
## 100 is Bilinear supersampling, which is the only mode that goes past 1.0.
const RENDER_SCALES: Array[int] = [50, 67, 83, 100, 125, 150]

## One table, read by every owner of a tier's cost. Never change the ambient
## floor, palette, fog, faction colours or sign budget here: tiers add or take
## away depth (shadows, contact shading, bounce light), never the room.
## msaa: samples. *_atlas: shadow atlas sizes. shadow_filter: a
## RenderingServer.ShadowQuality, or -1 for the project default.
## fixture_shadows: practical lamps cast shadow maps. omni: paraboloid or cube
## for those lamps. practical_fade: metres where lamps fade out, 0 keeps the
## authored fade. practical_shadow_scale: multiplies authored shadow fade.
## ssao: 0 off, 1 low, 2 medium, 3 high. ssil: bounce light. glow: authored
## glow. volumetric_fog, ssr: only where a venue opts in (none yet, pending a
## look pass). water: IslandWater quality 0 to 2. effects: decal and effect
## budget share. lod: mesh LOD threshold in pixels. decal_life: multiplier.
const TIERS: Array[Dictionary] = [
	{"msaa": 0, "directional_atlas": 1024, "positional_atlas": 512, "shadow_filter": RenderingServer.SHADOW_QUALITY_HARD,
		"fixture_shadows": false, "omni": "cube", "practical_fade": 24.0, "practical_shadow_scale": 1.0, "ssao": 0, "ssil": false,
		"glow": false, "volumetric_fog": false, "ssr": false, "water": 0, "effects": 0.25, "lod": 2.0, "decal_life": 1.0, "forward_plus_only": false},
	{"msaa": 0, "directional_atlas": 1024, "positional_atlas": 1024, "shadow_filter": -1,
		"fixture_shadows": false, "omni": "cube", "practical_fade": 0.0, "practical_shadow_scale": 1.0, "ssao": 0, "ssil": false,
		"glow": false, "volumetric_fog": false, "ssr": false, "water": 0, "effects": 0.5, "lod": 1.0, "decal_life": 1.0, "forward_plus_only": false},
	{"msaa": 2, "directional_atlas": 2048, "positional_atlas": 2048, "shadow_filter": -1,
		"fixture_shadows": true, "omni": "paraboloid", "practical_fade": 0.0, "practical_shadow_scale": 1.0, "ssao": 1, "ssil": false,
		"glow": true, "volumetric_fog": false, "ssr": false, "water": 1, "effects": 1.0, "lod": 1.0, "decal_life": 1.0, "forward_plus_only": false},
	{"msaa": 4, "directional_atlas": 4096, "positional_atlas": 4096, "shadow_filter": -1,
		"fixture_shadows": true, "omni": "cube", "practical_fade": 0.0, "practical_shadow_scale": 1.0, "ssao": 2, "ssil": false,
		"glow": true, "volumetric_fog": false, "ssr": false, "water": 2, "effects": 1.0, "lod": 1.0, "decal_life": 1.0, "forward_plus_only": false},
	{"msaa": 4, "directional_atlas": 4096, "positional_atlas": 4096, "shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"fixture_shadows": true, "omni": "cube", "practical_fade": 0.0, "practical_shadow_scale": 1.5, "ssao": 3, "ssil": true,
		"glow": true, "volumetric_fog": true, "ssr": true, "water": 2, "effects": 1.0, "lod": 1.0, "decal_life": 1.5, "forward_plus_only": true},
]
## In-match governor steps, cheapest to lose first (FrameGovernor). They last
## until the session ends or the player tunes again; never saved.
const GOVERNOR_ORDER: Array[String] = ["volumetric_fog", "ssil", "ssr", "ssao", "practical_shadows", "effects", "msaa"]
static var reductions: PackedStringArray = PackedStringArray()
## Share of the decal and effect budget the drawn tier allows; read by
## VfxDecals and GrenadeEffects. Set by `apply`.
static var effects_budget: float = 1.0
static var decal_life: float = 1.0

static func supports_fsr(renderer: String) -> bool:
	return renderer == "forward_plus"

static func supports_ao(renderer: String) -> bool:
	return renderer in ["forward_plus", "gl_compatibility"]

static func supports_dual_paraboloid(renderer: String) -> bool:
	return renderer in ["forward_plus", "mobile"]

## Light fixtures cast shadow maps only where the renderer keeps them stable
## beside the transient lights of a fight (#521). Under Compatibility a shot's
## muzzle or blast light joining shadowed omni fixtures can leave the frame
## lit as if every fixture reached every surface: whole decks wash to white.
## The pools of light stay; only their shadow maps go.
static func supports_fixture_shadows(renderer: String) -> bool:
	return renderer != "gl_compatibility"

## The renderer's name as the engine's project settings print it.
static func renderer_name(renderer: String) -> String:
	match renderer:
		"forward_plus":
			return "Forward+"
		"mobile":
			return "Mobile"
		"gl_compatibility":
			return "Compatibility"
		_:
			return renderer

## What a tier changes in the drawn frame, in player words. It reads the same
## spec `apply`, `apply_environment` and `apply_practicals` use, so a result can
## say how its tiers differ instead of only naming them.
static func preset_features(quality: int, renderer: String, video: Dictionary, output: Vector2i) -> String:
	var spec: Dictionary = tier_spec(quality, renderer)
	var pixels: int = pixel_factor(int(video.get("pixel_scale", 0)), output)
	var fsr2: bool = pixels <= 1 and supports_fsr(renderer) and int(video.get("upscaling", 0)) == 2
	var parts: PackedStringArray = PackedStringArray()
	var msaa: int = 0 if fsr2 else int(spec["msaa"])
	parts.append("no MSAA" if msaa == 0 else "MSAA %dx" % msaa)
	if int(spec["directional_atlas"]) == int(spec["positional_atlas"]):
		parts.append("shadow atlas %d" % int(spec["directional_atlas"]))
	else:
		parts.append("shadow atlas %d, lamps %d" % [int(spec["directional_atlas"]), int(spec["positional_atlas"])])
	var filter: int = int(spec["shadow_filter"])
	if filter == RenderingServer.SHADOW_QUALITY_HARD:
		parts.append("hard shadow edges")
	elif filter == RenderingServer.SHADOW_QUALITY_SOFT_HIGH:
		parts.append("soft shadow edges")
	parts.append("light fixture shadows %s" % ("on" if bool(spec["fixture_shadows"]) else "off"))
	parts.append("ambient occlusion %s" % ["off", "low", "medium", "high"][int(spec["ssao"])])
	if bool(spec["ssil"]):
		parts.append("bounce light on")
	parts.append("glow %s" % ("on" if bool(spec["glow"]) else "off"))
	if float(spec["practical_fade"]) > 0.0:
		parts.append("lamps fade at %d m" % int(spec["practical_fade"]))
	if float(spec["effects"]) < 1.0:
		parts.append("effects %d%%" % roundi(float(spec["effects"]) * 100.0))
	return ", ".join(parts)

## The tier's contents for this renderer, with any in-match governor steps
## already taken (`reductions`). Ultra asks for Forward+; elsewhere it draws
## as High. Features the renderer lacks are off, so every reader of the spec
## (apply, practicals, the feature text, the governor) agrees on what is drawn.
static func tier_spec(quality: int, renderer: String, governor: bool = true) -> Dictionary:
	var steps: PackedStringArray = reductions if governor else PackedStringArray()
	var tier: int = effective_tier(quality, renderer)
	var spec: Dictionary = (TIERS[tier] as Dictionary).duplicate()
	spec["tier"] = tier
	if not supports_ao(renderer):
		spec["ssao"] = 0
	if not supports_fixture_shadows(renderer):
		spec["fixture_shadows"] = false
	if renderer != "forward_plus":
		spec["ssil"] = false
		spec["volumetric_fog"] = false
		spec["ssr"] = false
	for step: String in steps:
		match step:
			"volumetric_fog":
				spec["volumetric_fog"] = false
			"ssil":
				spec["ssil"] = false
			"ssr":
				spec["ssr"] = false
			"ssao":
				spec["ssao"] = maxi(0, int(spec["ssao"]) - 1)
			"practical_shadows":
				if bool(spec["fixture_shadows"]):
					spec["practical_shadow_scale"] = float(spec["practical_shadow_scale"]) * 0.5
			"effects":
				spec["effects"] = float(spec["effects"]) * 0.5
			"msaa":
				spec["msaa"] = 2 if int(spec["msaa"]) == 4 else 0
	return spec

static func tier_available(quality: int, renderer: String) -> bool:
	return quality >= POTATO and quality <= ULTRA and (not bool((TIERS[quality] as Dictionary)["forward_plus_only"]) or renderer == "forward_plus")

## The tier that actually draws: a Forward+ only tier falls to the one below.
static func effective_tier(quality: int, renderer: String) -> int:
	var tier: int = clampi(quality, POTATO, ULTRA)
	while tier > POTATO and not tier_available(tier, renderer):
		tier -= 1
	return tier

static func tier_name(quality: int) -> String:
	return TIER_NAMES[quality] if quality >= 0 and quality < TIER_NAMES.size() else "Tier %d" % quality

## Render scale percent and the 3D resolution it gives on this output.
static func scale_valid(percent: Variant) -> bool:
	return percent is int and int(percent) in RENDER_SCALES

static func render_scale(height: int, output: Vector2i) -> float:
	if height == 0 or output.y <= 0:
		return 1.0
	return clampf(float(height) / float(output.y), 0.1, 1.0)

static func render_size(height: int, output: Vector2i) -> Vector2i:
	var scale: float = render_scale(height, output)
	return Vector2i(maxi(1, roundi(output.x * scale)), maxi(1, roundi(output.y * scale)))

## Whole-number world pixel size for a pixel look choice on this output.
static func pixel_factor(choice: int, output: Vector2i) -> int:
	if choice <= 0 or choice >= PIXEL_TARGETS.size() or output.y <= 0:
		return 1
	return maxi(1, roundi(float(output.y) / float(PIXEL_TARGETS[choice])))

static func window_size(height: int, available: Vector2i) -> Vector2i:
	var requested: Vector2i = Vector2i(roundi(float(height) * 16.0 / 9.0), height) if height > 0 else Vector2i(1280, 720)
	var space: Vector2i = Vector2i(maxi(1, available.x - 32), maxi(1, available.y - 80))
	var fit: float = minf(1.0, minf(float(space.x) / requested.x, float(space.y) / requested.y))
	return Vector2i(maxi(1, floori(requested.x * fit)), maxi(1, floori(requested.y * fit)))

static func _output(viewport: Viewport) -> Vector2i:
	return (viewport as Window).size if viewport is Window else Vector2i(viewport.get_visible_rect().size)

static func apply(viewport: Viewport, preferences: FragrSettings, environment: Environment = null) -> void:
	var renderer: String = RenderingServer.get_current_rendering_method()
	var spec: Dictionary = tier_spec(int(preferences.get_value("video", "quality")), renderer)
	var upscale: int = int(preferences.get_value("video", "upscaling"))
	var output: Vector2i = _output(viewport)
	var pixels: int = pixel_factor(int(preferences.get_value("video", "pixel_scale")), output)
	var scale: float = world_scale(int(preferences.get_value("video", "resolution_height")), int(preferences.get_value("video", "render_scale")), output)
	viewport.scaling_3d_scale = scale
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var fsr2: bool = false
	if pixels > 1:
		# The pixel look is a nearest integer upscale. Reconstruction would
		# smear the very grid it asks for, so it replaces FSR while selected,
		# and it owns the 3D resolution: render scale never splits its grid.
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_NEAREST
		viewport.scaling_3d_scale = minf(render_scale(int(preferences.get_value("video", "resolution_height")), output), 1.0 / float(pixels))
	elif supports_fsr(renderer) and scale <= 1.0:
		# Only Bilinear supersamples above 1.0.
		if upscale == 1:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		elif upscale == 2:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			fsr2 = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	if not fsr2:
		if int(spec["msaa"]) == 2:
			viewport.msaa_3d = Viewport.MSAA_2X
		elif int(spec["msaa"]) == 4:
			viewport.msaa_3d = Viewport.MSAA_4X
	viewport.positional_shadow_atlas_size = int(spec["positional_atlas"])
	viewport.mesh_lod_threshold = float(spec["lod"])
	RenderingServer.directional_shadow_atlas_set_size(int(spec["directional_atlas"]), true)
	var filter: int = int(spec["shadow_filter"])
	var directional: int = filter if filter >= 0 else _project_filter("directional")
	var positional: int = filter if filter >= 0 else _project_filter("positional")
	RenderingServer.directional_soft_shadow_filter_set_quality(directional as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(positional as RenderingServer.ShadowQuality)
	effects_budget = float(spec["effects"])
	decal_life = float(spec["decal_life"])
	if environment != null:
		apply_environment(environment, preferences)

## The project's own soft shadow filter, which Low, Medium and High keep.
static func _project_filter(kind: String) -> int:
	return int(ProjectSettings.get_setting("rendering/lights_and_shadows/%s_shadow/soft_shadow_filter_quality" % kind, RenderingServer.SHADOW_QUALITY_SOFT_LOW))

## 3D render scale from the render height and the render scale percent.
## Above 1.0 only when the player or the tuner picks supersampling.
static func world_scale(height: int, percent: int, output: Vector2i) -> float:
	var share: float = float(percent if percent in RENDER_SCALES else 100) / 100.0
	return clampf(render_scale(height, output) * share, 0.1, 2.0)

static func apply_environment(environment: Environment, preferences: FragrSettings) -> void:
	# Preserve authored ambient visibility. Medium adds contact shading and
	# fixture glow; High deepens the contact shading; Ultra adds bounce light.
	# Low and Potato add neither.
	var spec: Dictionary = tier_spec(int(preferences.get_value("video", "quality")), RenderingServer.get_current_rendering_method())
	var ao: int = int(spec["ssao"])
	environment.ssao_enabled = ao >= 1
	environment.ssao_radius = 1.2 if ao >= 2 else 1.0
	environment.ssao_intensity = 1.4 if ao >= 2 else 1.0
	environment.ssao_power = 1.5
	environment.ssao_detail = 0.5
	environment.glow_enabled = bool(spec["glow"]) and environment.glow_intensity > 0.0
	# Medium takes the cheaper sampler; High the engine's medium default;
	# Ultra the high sampler.
	if ao >= 1:
		var sampler: int = AO_SAMPLERS[ao]
		RenderingServer.environment_set_ssao_quality(sampler as RenderingServer.EnvironmentSSAOQuality, true, 0.5, 2, 50.0, 300.0)
	# Bounce light at a modest strength so a lamp tints the floor around it
	# without lifting the authored ambient floor.
	environment.ssil_enabled = bool(spec["ssil"])
	if environment.ssil_enabled:
		environment.ssil_intensity = 0.7
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	# Volumetric fog and screen-space reflections only where a venue opts in
	# (ArenaSky metas); no venue does until its look pass. The fog keeps the
	# venue's colour and density so a lower tier never shows another room.
	environment.volumetric_fog_enabled = bool(spec["volumetric_fog"]) and float(environment.get_meta(VOLUMETRIC_META, 0.0)) > 0.0
	if environment.volumetric_fog_enabled:
		environment.volumetric_fog_density = float(environment.get_meta(VOLUMETRIC_META, 0.0))
		environment.volumetric_fog_albedo = environment.fog_light_color
	environment.ssr_enabled = bool(spec["ssr"]) and bool(environment.get_meta(SSR_META, false))

const AO_SAMPLERS: Array[int] = [RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW,
	RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH]

## Venue opt-ins for Ultra's per-venue features, set by the venue's sky.
const VOLUMETRIC_META: StringName = &"fragr_ultra_volumetric_density"
const SSR_META: StringName = &"fragr_ultra_ssr"

## Practical fixtures cast shadows from Medium up. Low keeps the pools of
## light and drops the shadow maps, which are the largest cost the look pass
## adds (see docs/plans/look-pass-boomer.md). Potato also fades lamps sooner;
## Ultra carries their shadows further. Authored fades are kept on the node
## and restored, so every tier starts from the venue's own numbers.
## Scoped to a subtree so a detached match scene (harness fixtures) works too.
static func apply_practicals(scope: Node, preferences: FragrSettings) -> void:
	var renderer: String = RenderingServer.get_current_rendering_method()
	var spec: Dictionary = tier_spec(int(preferences.get_value("video", "quality")), renderer)
	for water: Node in scope.find_children("IslandWater", "Node3D", true, false):
		if water is IslandWater:
			water.apply_quality(int(spec["water"]))
	for node: Node in scope.find_children("*", "Light3D", true, false):
		if not node.is_in_group(ArenaSky.PRACTICAL_GROUP) or not node is Light3D:
			continue
		var light: Light3D = node as Light3D
		light.shadow_enabled = bool(spec["fixture_shadows"])
		_apply_fade(light, float(spec["practical_fade"]), float(spec["practical_shadow_scale"]))
		# Two paraboloid passes instead of six cube faces on Medium, where the
		# renderer has them. Compatibility renders omni shadows as cubes only.
		if light is OmniLight3D:
			var paraboloid: bool = str(spec["omni"]) == "paraboloid" and supports_dual_paraboloid(renderer)
			(light as OmniLight3D).omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID if paraboloid else OmniLight3D.SHADOW_CUBE

static func _apply_fade(light: Light3D, fade: float, shadow_scale: float) -> void:
	if not light.has_meta(&"fragr_authored_fade"):
		light.set_meta(&"fragr_authored_fade", [light.distance_fade_enabled, light.distance_fade_begin, light.distance_fade_length, light.distance_fade_shadow])
	var authored: Array = light.get_meta(&"fragr_authored_fade")
	light.distance_fade_enabled = bool(authored[0])
	light.distance_fade_begin = float(authored[1])
	light.distance_fade_length = float(authored[2])
	light.distance_fade_shadow = float(authored[3]) * shadow_scale
	if fade > 0.0:
		light.distance_fade_enabled = true
		light.distance_fade_begin = minf(fade, light.distance_fade_begin) if bool(authored[0]) else fade
		light.distance_fade_length = minf(light.distance_fade_length, 8.0)
		light.distance_fade_shadow = minf(light.distance_fade_shadow, fade)

## The optional ordered dither, owned by the match scene so it never sits over
## a menu. Grid-aligned to the world pixel size.
static func apply_dither(owner: Node, viewport: Viewport, preferences: FragrSettings) -> void:
	var layer: CanvasLayer = owner.get_node_or_null(DITHER_LAYER) as CanvasLayer
	if not bool(preferences.get_value("video", "dither")):
		if layer != null:
			owner.remove_child(layer)
			layer.queue_free()
		return
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = DITHER_LAYER
		layer.layer = DITHER_CANVAS_LAYER
		var rect: ColorRect = ColorRect.new()
		rect.name = "Dither"
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = DITHER_SHADER
		material.set_shader_parameter("steps", DITHER_STEPS)
		rect.material = material
		layer.add_child(rect)
		owner.add_child(layer)
	var dither: ColorRect = layer.get_node("Dither") as ColorRect
	var pixels: int = pixel_factor(int(preferences.get_value("video", "pixel_scale")), _output(viewport))
	(dither.material as ShaderMaterial).set_shader_parameter("pixel_size", float(pixels))
