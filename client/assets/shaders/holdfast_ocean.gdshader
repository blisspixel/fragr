shader_type spatial;
render_mode cull_disabled;

uniform sampler2D coast_depth : filter_linear, repeat_disable;
uniform float map_half = 220.0;
uniform int water_quality = 1;
uniform int wake_count = 0;
uniform vec4 wake_poses[8];
uniform float wake_powers[8];
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (water_quality > 0) {
		float broad = sin(dot(world_position.xz, vec2(0.11, 0.16)) + TIME * 0.65);
		VERTEX.y += broad * 0.045;
	}
}

void fragment() {
	float distance_to_eye = length(VERTEX);
	float near_detail = 1.0 - smoothstep(35.0, 150.0, distance_to_eye);
	vec2 cell = floor(world_position.xz * 4.0) * 0.25;
	vec2 uv = world_position.xz / (map_half * 2.0) + vec2(0.5);
	float inside_map = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float depth = mix(2.2, texture(coast_depth, uv).r * 4.0, inside_map);
	float phase = dot(cell, vec2(0.38, 0.27)) + TIME * 0.8;
	float cross_phase = dot(cell, vec2(-0.19, 0.44)) - TIME * 0.55;
	float broad = sin(phase);
	float crossing = sin(cross_phase);
	float ripple = 0.0;
	if (water_quality > 0) {
		ripple = sin(dot(cell, vec2(1.7, -0.9)) + TIME * 1.1) * near_detail * 0.18;
	}
	vec2 slope = vec2(0.38, 0.27) * cos(phase) * 0.16 + vec2(-0.19, 0.44) * cos(cross_phase) * 0.11;
	slope *= mix(0.3, 1.0, near_detail);
	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	float band = floor((broad * 0.6 + crossing * 0.4 + ripple + 1.2) * 3.0) / 7.0;
	vec3 shallows = vec3(0.19, 0.49, 0.43);
	vec3 deep = vec3(0.055, 0.23, 0.27);
	vec3 water = mix(shallows, deep, smoothstep(0.15, 3.5, depth));
	water += (band - 0.5) * 0.055 * mix(0.25, 1.0, near_detail);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	water = mix(water, vec3(0.45, 0.62, 0.61), fresnel * 0.55);
	// Foam follows registered submerged steps. Stable world pixels and distant
	// fading avoid sparkling horizons while keeping the surface readable.
	float wash = 0.32 + (sin(TIME * 0.65 + cell.x * 0.08 + cell.y * 0.06) + 1.0) * 0.19;
	float foam = (1.0 - smoothstep(0.12, 0.38, abs(depth - wash))) * (1.0 - smoothstep(1.0, 1.4, depth));
	foam *= mix(0.28, 0.75, step(0.1, broad + crossing * 0.5));
	for (int i = 0; i < 8; i++) {
		if (i >= wake_count) { break; }
		vec2 relative = cell - wake_poses[i].xy;
		vec2 heading = wake_poses[i].zw;
		float aft = -dot(relative, heading);
		float across = abs(dot(relative, vec2(-heading.y, heading.x)));
		float length_limit = 6.0 + 18.0 * wake_powers[i];
		float gate = smoothstep(0.5, 2.0, aft) * (1.0 - smoothstep(length_limit * 0.4, length_limit, aft));
		float arms = 1.0 - smoothstep(0.20, 0.65, abs(across - (0.8 + aft * 0.27)));
		float churn = (1.0 - smoothstep(0.2, 1.1 + aft * 0.06, across)) * (0.5 + 0.5 * sin(aft * 2.0 - TIME * 5.0));
		foam = max(foam, max(arms, churn * 0.7) * gate * wake_powers[i]);
	}
	float glint = step(0.95, broad * 0.65 + crossing * 0.35 + ripple) * near_detail;
	if (water_quality == 0) { glint = 0.0; }
	ALBEDO = mix(water, vec3(0.72, 0.82, 0.71), clamp(foam * 0.75 + glint * 0.14, 0.0, 0.85));
	ROUGHNESS = 0.65;
	SPECULAR = 0.18;
}
