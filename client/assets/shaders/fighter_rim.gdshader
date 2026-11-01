shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

// A fighter's rim of light (#528), drawn as a second pass over a live body.
// Where the surface turns away from the eye it gains a stepped band of light,
// so a figure separates from the lot behind it at fighting range without an
// outline round the whole body: the TF2 rule, rim highlights, not outlines.
// Steps keep the band in the pixel look instead of a smooth glow. The colour
// follows the faction contract: free bodies take a warm rim, the Union's
// issued black a cool plate value, never red or cyan.

uniform vec3 rim_color : source_color = vec3(0.96, 0.78, 0.56);
uniform float rim_strength = 0.6;
uniform float rim_power = 1.4;
uniform float rim_steps = 3.0;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, rim_power);
	rim = floor(rim * rim_steps + 0.5) / rim_steps;
	ALBEDO = rim_color * rim * rim_strength;
}
