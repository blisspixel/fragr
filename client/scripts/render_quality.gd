extends RefCounted
class_name RenderQuality
## One portable presentation path. Preferences never change simulation geometry.

const RESOLUTION_HEIGHTS: Array[int] = [0, 720, 900, 1080, 1440, 2160]

static func supports_fsr(renderer: String) -> bool:
	return renderer == "forward_plus"

static func supports_ao(renderer: String) -> bool:
	return renderer in ["forward_plus", "gl_compatibility"]

static func render_scale(height: int, output: Vector2i) -> float:
	if height == 0 or output.y <= 0:
		return 1.0
	return clampf(float(height) / float(output.y), 0.1, 1.0)

static func render_size(height: int, output: Vector2i) -> Vector2i:
	var scale: float = render_scale(height, output)
	return Vector2i(maxi(1, roundi(output.x * scale)), maxi(1, roundi(output.y * scale)))

static func window_size(height: int, available: Vector2i) -> Vector2i:
	var requested: Vector2i = Vector2i(roundi(float(height) * 16.0 / 9.0), height) if height > 0 else Vector2i(1280, 720)
	var space: Vector2i = Vector2i(maxi(1, available.x - 32), maxi(1, available.y - 80))
	var fit: float = minf(1.0, minf(float(space.x) / requested.x, float(space.y) / requested.y))
	return Vector2i(maxi(1, floori(requested.x * fit)), maxi(1, floori(requested.y * fit)))

static func apply(viewport: Viewport, preferences: FragrSettings, environment: Environment = null) -> void:
	var renderer: String = RenderingServer.get_current_rendering_method()
	var quality: int = int(preferences.get_value("video", "quality"))
	var upscale: int = int(preferences.get_value("video", "upscaling"))
	var output: Vector2i = (viewport as Window).size if viewport is Window else Vector2i(viewport.get_visible_rect().size)
	viewport.scaling_3d_scale = render_scale(int(preferences.get_value("video", "resolution_height")), output)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	if supports_fsr(renderer):
		if upscale == 1:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		elif upscale == 2:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	if not (supports_fsr(renderer) and upscale == 2):
		if quality == 1:
			viewport.msaa_3d = Viewport.MSAA_2X
		elif quality == 2:
			viewport.msaa_3d = Viewport.MSAA_4X
	viewport.positional_shadow_atlas_size = 1024 if quality == 0 else (4096 if quality == 2 else 2048)
	RenderingServer.directional_shadow_atlas_set_size(viewport.positional_shadow_atlas_size, true)
	if environment != null:
		apply_environment(environment, preferences)

static func apply_environment(environment: Environment, preferences: FragrSettings) -> void:
	# Preserve authored ambient visibility; High only adds contact shading.
	environment.ssao_enabled = int(preferences.get_value("video", "quality")) == 2 and supports_ao(RenderingServer.get_current_rendering_method())
	environment.ssao_radius = 1.0
	environment.ssao_intensity = 0.6
