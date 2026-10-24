shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_back;

// Dusk harbour water outside the playable square. Pixel-stepped swell bands
// and real-light glints; it never claims collision or depth authority.
uniform vec4 deep_color : source_color = vec4(0.055, 0.105, 0.125, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.2, 0.21, 1.0);
uniform vec4 crest_color : source_color = vec4(0.36, 0.44, 0.43, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.42, 0.33, 0.32, 1.0);
uniform float cell_size = 0.25;
varying vec3 world_position;

float grain(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = floor(world_position.xz / cell_size) * cell_size;
	float clock = floor(TIME * 6.0) / 6.0;
	float swell = sin(cell.x * 0.21 + cell.y * 0.13 + clock * 0.9);
	float chop = sin(cell.x * 0.93 - cell.y * 0.71 - clock * 1.7) * 0.5;
	float band = floor((swell * 0.55 + chop * 0.45 + 1.0) * 2.5) / 5.0;
	vec3 color = mix(deep_color.rgb, shallow_color.rgb, band);
	float crest = step(0.86, swell * 0.6 + chop * 0.4 + grain(floor(cell / 2.0)) * 0.25);
	color = mix(color, crest_color.rgb, crest * 0.55);
	float distance_fade = smoothstep(30.0, 160.0, length(VERTEX));
	color = mix(color, sky_tint.rgb * 0.45, distance_fade * 0.35);
	vec2 slope = vec2(0.21, 0.13) * cos(cell.x * 0.21 + cell.y * 0.13 + clock * 0.9) * 0.35
		+ vec2(0.93, -0.71) * cos(cell.x * 0.93 - cell.y * 0.71 - clock * 1.7) * 0.12;
	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ALBEDO = color;
	ROUGHNESS = 0.14;
	SPECULAR = 0.75;
	METALLIC = 0.0;
}
