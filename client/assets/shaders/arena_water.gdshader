shader_type spatial;
render_mode diffuse_lambert, depth_draw_opaque, cull_back;

uniform vec4 deep_color : source_color = vec4(0.157, 0.290, 0.286, 1.0);
uniform vec4 water_color : source_color = vec4(0.259, 0.420, 0.408, 1.0);
uniform vec4 crest_color : source_color = vec4(0.525, 0.663, 0.596, 1.0);
uniform vec4 shore_color : source_color = vec4(0.255, 0.310, 0.271, 1.0);
uniform vec2 patch_size = vec2(4.0, 2.4);
uniform float ripple_time = 0.0;
uniform float phase = 0.0;
uniform sampler2D ripple_detail : filter_nearest, repeat_enable;
uniform bool detail_enabled = false;
uniform bool river_mode = false;
varying vec2 world_xz;

float grain(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	// Register every cell to the floor's sixteen texels per metre grid.
	vec2 cells = floor(world_xz * 16.0);
	vec2 p = cells / 16.0;
	vec2 shore_uv = floor(UV * patch_size * 16.0) / (patch_size * 16.0);
	vec2 oval = (shore_uv - 0.5) * 2.0;
	float radius = river_mode ? abs(oval.x) : length(oval);
	float edge = 0.955 + (grain(floor(cells / 3.0)) - 0.5) * 0.065;
	if (radius > edge) {
		discard;
	}
	float clock = floor(ripple_time * 8.0) / 8.0;
	float flow = sin(p.x * 4.8 + p.y * 2.7 - clock * 0.7853981634 + phase);
	float cross_wave = sin(p.x * 1.5 - p.y * 6.2 + clock * 0.3926990817 + phase);
	float level = floor((flow * 0.24 + cross_wave * 0.14 + 0.5) * 6.0) / 6.0;
	vec3 color = mix(deep_color.rgb, water_color.rgb, level);
	float crest = step(0.93, flow) * step(0.15, cross_wave);
	color = mix(color, crest_color.rgb, crest);
	// A restrained wet rim reads as water lying on concrete, not a deep pool.
	float rim = step(edge - 0.09, radius);
	color = mix(color, shore_color.rgb, rim);
	float broken_edge = step(edge - 0.15, radius) * step(0.78, grain(cells));
	color = mix(color, crest_color.rgb * 0.7, broken_edge * (1.0 - rim));
	// Wave slopes produce moving highlights under the venue's actual lights.
	vec2 slope = vec2(4.8, 2.7) * cos(p.x * 4.8 + p.y * 2.7 - clock * 0.7853981634 + phase) * 0.009;
	slope += vec2(1.5, -6.2) * cos(p.x * 1.5 - p.y * 6.2 + clock * 0.3926990817 + phase) * 0.005;
	if (detail_enabled) {
		vec2 detail_uv = p * 0.28 + vec2(clock * 0.013, -clock * 0.009);
		vec2 detail_step = 1.0 / vec2(textureSize(ripple_detail, 0));
		float h = texture(ripple_detail, detail_uv).r;
		float dx = texture(ripple_detail, detail_uv + vec2(detail_step.x, 0.0)).r - h;
		float dy = texture(ripple_detail, detail_uv + vec2(0.0, detail_step.y)).r - h;
		slope += vec2(dx, dy) * 0.20;
		color *= 0.94 + h * 0.09;
	}
	// Sparse drips expand and fade. The floor patch never displaces geometry.
	vec2 drop_cell = floor(p / 1.4);
	vec2 drop_center = (drop_cell + vec2(grain(drop_cell), grain(drop_cell + 17.0))) * 1.4;
	float age = fract(clock * 0.31 + grain(drop_cell + phase));
	float ring_radius = age * 0.56;
	float distance_to_drop = length(p - drop_center);
	float ring = (1.0 - smoothstep(0.025, 0.08, abs(distance_to_drop - ring_radius))) * (1.0 - age);
	vec2 outward = normalize(p - drop_center + vec2(0.0001));
	slope += outward * ring * 0.042 * (1.0 - rim);
	color = mix(color, crest_color.rgb, ring * 0.12 * (1.0 - rim));
	NORMAL_MAP = normalize(vec3(-slope.x, -slope.y, 1.0)) * 0.5 + 0.5;
	ALBEDO = color;
	ROUGHNESS = mix(0.18, 0.62, rim);
	SPECULAR = mix(0.65, 0.12, rim);
}
