shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

void fragment() {
	float radius = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.025, 0.027, 0.03);
	ALPHA = (1.0 - smoothstep(0.35, 1.0, radius)) * 0.34;
}
