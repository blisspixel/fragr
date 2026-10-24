shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Art style trial, Treatments A and C: a live skinned model drawn like a
// directional pixel sprite under real venue light.
// - albedo is a low-resolution, palette-reduced copy of the model's own map,
//   sampled nearest so texels read as deliberate clusters;
// - every light lands in a few hard steps (no smooth gradient), so form reads
//   as painted value blocks the way a pre-rendered sprite's shading does;
// - a stepped highlight band on the lit silhouette edge and a faint cool
//   fresnel band keep the body off the wall in shade;
// - Union red issue marks burn full-bright, matching the shipped sprite rule.
// Not used by any shipped material.

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform bool use_texture = true;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D normal_texture : hint_normal, filter_nearest, repeat_enable;
uniform bool use_normal = false;
uniform float normal_depth = 1.0;
// Flat faces instead of interpolated normals: sculpted planes read as planes.
uniform bool facets = false;
uniform float bands = 3.0;
uniform float light_gain = 1.0;
uniform float edge_light = 0.55;
uniform float edge_width = 0.58;
uniform vec3 fresnel_color : source_color = vec3(0.36, 0.30, 0.44);
uniform float fresnel_strength = 0.22;
uniform float red_glow = 0.0;
uniform float glint = 0.18;
uniform bool unshaded_flash = false;

float red_mask(vec3 c) {
	return step(0.12, c.r) * step(c.g * 3.0, c.r) * step(c.b * 3.0, c.r);
}

void fragment() {
	vec3 base = albedo.rgb;
	if (use_texture) {
		base *= texture(albedo_texture, UV).rgb;
	}
	if (facets) {
		NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	}
	if (use_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = fresnel_color * fresnel_strength * step(edge_width + 0.12, edge)
		+ base * red_mask(base) * red_glow;
	if (unshaded_flash) {
		ALBEDO = vec3(0.0);
		EMISSION = base * 2.0;
	}
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float lit = ndl * ATTENUATION;
	float stepped = floor(lit * bands + 0.5) / bands;
	DIFFUSE_LIGHT += LIGHT_COLOR * stepped * light_gain / PI;
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * edge_light * step(edge_width, edge) * step(0.25, lit) / PI;
	vec3 half_vector = normalize(LIGHT + VIEW);
	float shine = pow(clamp(dot(NORMAL, half_vector), 0.0, 1.0), 28.0) * ATTENUATION;
	SPECULAR_LIGHT += LIGHT_COLOR * step(0.55, shine) * glint / PI;
}
