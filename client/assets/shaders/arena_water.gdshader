shader_type spatial;
render_mode diffuse_lambert, specular_disabled, depth_draw_opaque, cull_back;

uniform vec4 deep_color : source_color = vec4(0.157, 0.290, 0.286, 1.0);
uniform vec4 water_color : source_color = vec4(0.259, 0.420, 0.408, 1.0);
uniform vec4 crest_color : source_color = vec4(0.525, 0.663, 0.596, 1.0);
uniform vec4 shore_color : source_color = vec4(0.255, 0.310, 0.271, 1.0);
uniform vec2 patch_size = vec2(4.0, 2.4);
uniform float ripple_time = 0.0;
uniform float phase = 0.0;
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
	float radius = length(oval);
	float edge = 0.955 + (grain(floor(cells / 3.0)) - 0.5) * 0.065;
	if (radius > edge) {
		discard;
	}
	float clock = floor(ripple_time * 8.0) / 8.0;
	float flow = sin(p.x * 4.8 + p.y * 2.7 - clock * 0.7853981634 + phase);
	float cross_wave = sin(p.x * 1.5 - p.y * 6.2 + clock * 0.3926990817 + phase);
	float level = floor((flow * 0.32 + cross_wave * 0.18 + 0.5) * 4.0);
	vec3 color = level < 1.0 ? deep_color.rgb : water_color.rgb;
	float crest = step(0.93, flow) * step(0.15, cross_wave);
	color = mix(color, crest_color.rgb, crest);
	// A restrained wet rim reads as water lying on concrete, not a deep pool.
	float rim = step(edge - 0.09, radius);
	color = mix(color, shore_color.rgb, rim);
	float broken_edge = step(edge - 0.15, radius) * step(0.78, grain(cells));
	color = mix(color, crest_color.rgb * 0.7, broken_edge * (1.0 - rim));
	ALBEDO = color;
	ROUGHNESS = 0.68;
	SPECULAR = 0.0;
}
