extends RefCounted
class_name RenderQuality
## One portable presentation path. Preferences never change simulation geometry.

const RESOLUTION_HEIGHTS: Array[int] = [0, 720, 900, 1080, 1440, 2160]
## Pixel look targets in world lines: off, fine, medium, chunky. The factor is
## the nearest whole number that reaches the target on the actual output, so
## every choice is an exact integer upscale and the HUD stays native.
const PIXEL_TARGETS: Array[int] = [0, 540, 360, 270]
const DITHER_SHADER: Shader = preload("res://assets/shaders/palette_dither.gdshader")
const DITHER_LAYER: String = "PaletteDither"
## Sits over the 3D frame and under the HUD (layer 1) and menus.
const DITHER_CANVAS_LAYER: int = -1
## docs/palette.json world swatches, in file order. The cyan and magenta
## pairs are fighter and team accents; left in, every pale green wall dithered
## toward cyan. The dither never invents a colour.
const PALETTE: Array[Color] = [
	Color8(10, 10, 12), Color8(232, 226, 214), Color8(58, 42, 72), Color8(58, 56, 54),
	Color8(90, 85, 79), Color8(140, 132, 122), Color8(122, 58, 34), Color8(110, 18, 24),
	Color8(196, 90, 32), Color8(220, 140, 60), Color8(139, 30, 30), Color8(78, 88, 68),
	Color8(58, 76, 46), Color8(116, 136, 78),
]

static func supports_fsr(renderer: String) -> bool:
	return renderer == "forward_plus"

static func supports_ao(renderer: String) -> bool:
	return renderer in ["forward_plus", "gl_compatibility"]

static func supports_dual_paraboloid(renderer: String) -> bool:
	return renderer in ["forward_plus", "mobile"]

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
	var quality: int = int(preferences.get_value("video", "quality"))
	var upscale: int = int(preferences.get_value("video", "upscaling"))
	var output: Vector2i = _output(viewport)
	var pixels: int = pixel_factor(int(preferences.get_value("video", "pixel_scale")), output)
	viewport.scaling_3d_scale = render_scale(int(preferences.get_value("video", "resolution_height")), output)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var fsr2: bool = false
	if pixels > 1:
		# The pixel look is a nearest integer upscale. Reconstruction would
		# smear the very grid it asks for, so it replaces FSR while selected.
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_NEAREST
		viewport.scaling_3d_scale = minf(viewport.scaling_3d_scale, 1.0 / float(pixels))
	elif supports_fsr(renderer):
		if upscale == 1:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		elif upscale == 2:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			fsr2 = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	if not fsr2:
		if quality == 1:
			viewport.msaa_3d = Viewport.MSAA_2X
		elif quality == 2:
			viewport.msaa_3d = Viewport.MSAA_4X
	viewport.positional_shadow_atlas_size = 1024 if quality == 0 else (4096 if quality == 2 else 2048)
	RenderingServer.directional_shadow_atlas_set_size(viewport.positional_shadow_atlas_size, true)
	if environment != null:
		apply_environment(environment, preferences)

static func apply_environment(environment: Environment, preferences: FragrSettings) -> void:
	# Preserve authored ambient visibility. Balanced adds contact shading and
	# fixture glow; High deepens the contact shading. Performance adds neither.
	var quality: int = int(preferences.get_value("video", "quality"))
	environment.ssao_enabled = quality >= 1 and supports_ao(RenderingServer.get_current_rendering_method())
	environment.ssao_radius = 1.2 if quality == 2 else 1.0
	environment.ssao_intensity = 1.4 if quality == 2 else 1.0
	environment.ssao_power = 1.5
	environment.ssao_detail = 0.5
	environment.glow_enabled = quality >= 1 and environment.glow_intensity > 0.0
	# Balanced takes the cheaper sampler; High the engine's medium default.
	if quality >= 1:
		RenderingServer.environment_set_ssao_quality(
			RenderingServer.ENV_SSAO_QUALITY_LOW if quality == 1 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
			true, 0.5, 2, 50.0, 300.0)

## Practical fixtures cast shadows from Balanced up. Performance keeps the
## pools of light and drops the shadow maps, which are the largest cost the
## look pass adds (see docs/plans/look-pass-boomer.md).
## Scoped to a subtree so a detached match scene (harness fixtures) works too.
static func apply_practicals(scope: Node, preferences: FragrSettings) -> void:
	var quality: int = int(preferences.get_value("video", "quality"))
	for node: Node in scope.find_children("*", "Light3D", true, false):
		if not node.is_in_group(ArenaSky.PRACTICAL_GROUP):
			continue
		if node is Light3D:
			(node as Light3D).shadow_enabled = quality >= 1
		# Two paraboloid passes instead of six cube faces on Balanced, where the
		# renderer has them. Compatibility renders omni shadows as cubes only.
		if node is OmniLight3D:
			var paraboloid: bool = quality == 1 and supports_dual_paraboloid(RenderingServer.get_current_rendering_method())
			(node as OmniLight3D).omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID if paraboloid else OmniLight3D.SHADOW_CUBE

## The optional ordered palette dither, owned by the match scene so it never
## sits over a menu. Grid-aligned to the world pixel size.
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
		var swatches: PackedVector3Array = PackedVector3Array()
		for colour: Color in PALETTE:
			swatches.append(Vector3(colour.r, colour.g, colour.b))
		material.set_shader_parameter("palette", swatches)
		material.set_shader_parameter("palette_size", PALETTE.size())
		rect.material = material
		layer.add_child(rect)
		owner.add_child(layer)
	var dither: ColorRect = layer.get_node("Dither") as ColorRect
	var pixels: int = pixel_factor(int(preferences.get_value("video", "pixel_scale")), _output(viewport))
	(dither.material as ShaderMaterial).set_shader_parameter("pixel_size", float(pixels))
