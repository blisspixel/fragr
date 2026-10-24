shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// A marked Paver strip, drawn on the floor the server marked. UV.x runs from
// the near edge to the far edge, UV.y across. Presentation only: the server
// decides what the strip works.
uniform float strip_length = 10.0;
uniform float half_width = 1.6;
// Preparation progress, 0 at the tell's start, 1 when the work begins.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// 1 during the work cycle.
uniform float working : hint_range(0.0, 1.0) = 0.0;
// 1 on a work pulse, decaying to 0 before the next.
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float clock = 0.0;
uniform vec3 paint_color : source_color = vec3(0.96, 0.95, 0.9);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 metres = vec2(UV.x * strip_length, (UV.y - 0.5) * 2.0 * half_width);
	float edge_x = min(metres.x, strip_length - metres.x);
	float edge_z = half_width - abs(metres.y);
	float edge = min(edge_x, edge_z);
	// Pixel-snapped 8 cm cells keep the strip in the retro surface language.
	vec2 cell = floor(metres / 0.08);
	// A hard border of projected light, brighter than any painted mark, with
	// dashes marching away from the Paver.
	float border = step(edge, 0.22);
	float dash = step(0.45, fract((metres.x - clock * 3.0) / 0.8));
	float border_light = border * mix(0.7, 1.0, dash) * (1.4 + 0.8 * progress + 1.2 * working);
	// Chevrons pointing down the strip march faster as the work approaches.
	float speed = mix(1.2, 4.5, progress) * (1.0 - working);
	float chevron = step(0.7, fract((metres.x - abs(metres.y) * 0.9 - clock * speed) / 1.2));
	float bed = chevron * (0.25 + 0.55 * progress) + 0.06 + 0.12 * progress;
	// The scan line sweeps from the projector to the far edge before the work.
	float sweep_at = fract(clock * mix(0.8, 2.8, progress)) * strip_length;
	float sweep = (1.0 - smoothstep(0.0, 0.4, abs(metres.x - sweep_at))) * (1.0 - working);
	// Worked ground: a hot flash per pulse broken by coarse grit.
	float grit = hash(cell + floor(clock * 12.0));
	float worked = working * (0.5 + 1.6 * pulse) * mix(0.55, 1.0, grit);
	float light = border_light + bed * (1.0 - border) + sweep * 1.2 + worked;
	ALBEDO = paint_color * light;
	ALPHA = clamp(light, 0.0, 1.0);
}
