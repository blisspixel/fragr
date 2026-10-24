shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

// Art style trial: inverted-hull silhouette line in palette outline_purple.
// The hull grows in clip space by a whole number of screen pixels so the line
// stays crisp: about one sprite texel (1.9 cm) near the camera, never thinner
// than `min_pixels` at range. `grid` is the world pixel size when the frame
// is rendered at a reduced integer scale.

uniform vec4 outline_color : source_color = vec4(0.227, 0.165, 0.282, 1.0);
uniform float texel_metres = 0.019;
uniform float min_pixels = 1.0;
uniform float max_pixels = 4.0;
uniform float grid = 1.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 view_normal = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec2 direction = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	float length_xy = length(direction);
	direction = length_xy > 1e-5 ? direction / length_xy : vec2(0.0);
	float metres_to_pixels = PROJECTION_MATRIX[1][1] * 0.5 * VIEWPORT_SIZE.y / max(clip.w, 0.01);
	float pixels = clamp(round(texel_metres * metres_to_pixels), min_pixels, max_pixels) * grid;
	clip.xy += direction * pixels * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
