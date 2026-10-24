shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// The Surveyor's projected mark: a pale disc of light with a hard working rim
// and survey ticks. Presentation only; the server owns centre and lifetime.
// The rim is the restoration swatch #4A8A92, never brighter; the disc reads by
// shape (a wide double border, twelve ticks and a sweep) rather than by hue,
// so it survives grayscale and colour-vision review.
uniform vec4 rim_color : source_color = vec4(0.290, 0.541, 0.573, 1.0);
uniform vec4 fill_color : source_color = vec4(0.86, 0.84, 0.76, 1.0);
uniform float strength = 1.0;
uniform float pulse = 0.0;
uniform float tracking = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// Pixel-stepped radius keeps the disc in the game's chunky register.
	vec2 cell = floor(p * 48.0) / 48.0;
	float r = length(cell);
	if (r > 1.0) {
		discard;
	}
	float rim = step(0.84, r);
	float rim_edge = step(0.95, r);
	float inner = step(0.40, r) * step(r, 0.45);
	float angle = atan(cell.y, cell.x);
	float ticks = step(0.92, fract(angle / 6.2831853 * 12.0)) * step(0.62, r) * step(r, 0.82);
	float sweep = step(0.93, fract(angle / 6.2831853 + pulse * 0.25)) * step(0.2, r) * step(r, 0.88);
	float fill = 0.10 + 0.05 * sin(pulse * 6.2831853);
	// The outermost ring is the pale work light itself, so the border holds
	// its value against wet concrete even with the cyan rim inside it muted.
	vec3 color = fill_color.rgb * (fill + rim_edge * 0.55) + rim_color.rgb * (rim * 1.1 + inner * 0.6 + ticks * 0.7 + sweep * 0.45 * tracking);
	float flicker = mix(0.45 + 0.35 * step(0.5, fract(pulse * 4.0)), 1.0, tracking);
	ALBEDO = color * strength * flicker;
}
