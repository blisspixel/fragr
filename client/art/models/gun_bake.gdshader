shader_type spatial;
// Offline only (tools/bake_viewmodels.gd). Mode 0 writes light, specular and
// view depth; mode 1 writes each part's palette ramp, outline group and depth.
// Values are pre-linearised so the viewport's sRGB output stores them exactly.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform int mode = 0;
uniform vec3 key_dir = vec3(-0.35, 0.90, 0.30);
uniform vec3 fill_dir = vec3(0.70, -0.10, 0.60);
uniform float depth_range = 1.6;
instance uniform float ramp_id = 0.0;
instance uniform float part_id = 0.0;
instance uniform float glow = 0.0;

vec3 linear_from_srgb(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float depth = clamp(-VERTEX.z / depth_range, 0.0, 1.0);
	if (mode == 0) {
		vec3 l = normalize(key_dir);
		float key = max(dot(n, l), 0.0);
		float fill = max(dot(n, normalize(fill_dir)), 0.0);
		float rim = pow(1.0 - max(dot(n, v), 0.0), 2.0);
		float spec = pow(max(dot(reflect(-l, n), v), 0.0), 18.0);
		float lum = 0.08 + 0.74 * key + 0.16 * fill + 0.08 * rim;
		lum = max(lum, glow);
		ALBEDO = linear_from_srgb(vec3(clamp(lum, 0.0, 1.0), spec, depth));
	} else {
		ALBEDO = linear_from_srgb(vec3(ramp_id * 16.0 / 255.0, part_id * 2.0 / 255.0, depth));
	}
}
