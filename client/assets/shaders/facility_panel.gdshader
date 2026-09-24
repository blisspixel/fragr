shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec2 panel_size = vec2(1.0);
uniform int style = 0;
// Palette colors require the same sRGB conversion as other world materials.
uniform vec4 steel_color : source_color = vec4(0.353, 0.333, 0.310, 1.0);
uniform vec4 bone_color : source_color = vec4(0.910, 0.886, 0.839, 1.0);
uniform vec4 ink_color : source_color = vec4(0.039, 0.039, 0.047, 1.0);
uniform vec4 green_color : source_color = vec4(0.306, 0.345, 0.267, 1.0);
uniform vec4 red_color : source_color = vec4(0.545, 0.118, 0.118, 1.0);
uniform vec4 gate_locked_color : source_color = vec4(0.902, 0.180, 0.141, 1.0);
uniform vec4 gate_open_color : source_color = vec4(0.349, 0.839, 0.380, 1.0);

float box(vec2 p, vec2 lo, vec2 hi) {
	return step(lo.x, p.x) * step(lo.y, p.y) * step(p.x, hi.x) * step(p.y, hi.y);
}

void fragment() {
	// Fixed physical texel density keeps small panels and long banks coherent.
	vec2 p = floor(UV * panel_size * 48.0) / 48.0;
	vec2 uv = p / panel_size;
	vec2 edge = min(p, panel_size - p);
	float frame = 1.0 - step(0.06, min(edge.x, edge.y));
	vec3 steel = steel_color.rgb;
	vec3 bone = bone_color.rgb;
	vec3 dark = ink_color.rgb;
	vec3 ink = mix(green_color.rgb, steel, frame);
	vec3 glow = vec3(0.0);
	if (style == 1) {
		float doors = max(1.0, floor(panel_size.x / 0.75));
		vec2 cell = vec2(fract(uv.x * doors), uv.y);
		ink = mix(steel, dark, step(0.965, cell.x));
		ink += vec3(0.055) * (1.0 - step(0.035, cell.x));
		float slit = box(cell, vec2(0.15, 0.12), vec2(0.82, 0.30));
		ink = mix(ink, dark, slit * step(0.5, fract(p.y * 9.0)));
		ink = mix(ink, bone, box(cell, vec2(0.80, 0.49), vec2(0.87, 0.59)));
		ink = mix(ink, bone * 0.65, box(cell, vec2(0.35, 0.38), vec2(0.65, 0.41)));
	} else if (style == 2) {
		ink = mix(dark, steel, step(0.55, fract(p.y * 8.0)));
		ink = mix(ink, bone * 0.55, frame);
	} else if (style == 3) {
		ink = mix(green_color.rgb * 0.45, steel, frame);
		float line = step(0.93, fract(p.y * 12.0));
		ink *= 1.0 - line * 0.15;
		glow = ink * (1.0 - frame) * 0.25;
	} else if (style == 4) {
		float cage = max(frame, 1.0 - step(0.055, fract(p.x * 2.0)));
		ink = mix(bone, dark, cage);
		glow = bone * (1.0 - cage) * 1.5;
	} else if (style == 5) {
		vec2 emblem = (uv - 0.5) * vec2(1.0, panel_size.y / panel_size.x);
		float diamond = step(abs(emblem.x) + abs(emblem.y), 0.35);
		float bars = step(0.48, fract((emblem.x + emblem.y) * 10.0));
		ink = mix(bone * 0.8, red_color.rgb, diamond);
		ink = mix(ink, bone, diamond * bars * box(uv, vec2(0.32), vec2(0.68)));
	} else if (style == 6) {
		ink = mix(bone, steel, frame);
	} else if (style == 7 || style == 8) {
		// Gate signal: a lamp over a shutter pictogram. Locked is a red lamp over
		// a closed slatted door; open is a green lamp over a raised shutter and an
		// up arrow. Colour and shape both carry the state.
		bool open = style == 8;
		vec3 lamp_color = open ? gate_open_color.rgb : gate_locked_color.rgb;
		vec2 s = vec2(uv.x, 1.0 - uv.y);
		ink = mix(dark, steel, frame);
		vec2 lamp_offset = (s - vec2(0.5, 0.79)) * vec2(panel_size.x / panel_size.y, 1.0);
		float lamp = 1.0 - step(0.15, length(lamp_offset));
		ink = mix(ink, lamp_color, lamp);
		glow = lamp_color * lamp * 1.8;
		float outer = box(s, vec2(0.2, 0.08), vec2(0.8, 0.6));
		float inner = box(s, vec2(0.27, 0.08), vec2(0.73, 0.53));
		ink = mix(ink, bone * 0.85, outer * (1.0 - inner));
		float slats = inner * step(0.5, fract(s.y * 15.0));
		if (open) {
			slats *= step(0.44, s.y);
			float head = step(0.25, s.y) * step(s.y, 0.41) * step(abs(s.x - 0.5), (0.41 - s.y) * 0.9);
			float shaft = step(0.12, s.y) * step(s.y, 0.26) * step(abs(s.x - 0.5), 0.035);
			float arrow = max(head, shaft);
			ink = mix(ink, lamp_color, arrow);
			glow += lamp_color * arrow * 0.8;
		}
		ink = mix(ink, mix(steel, bone, 0.35), slats);
	} else {
		ink = mix(ink, bone * 0.75, box(uv, vec2(0.06, 0.90), vec2(0.94, 0.93)));
	}
	// Small screws and deterministic wear, without animated noise or neon.
	float screw = (1.0 - step(0.04, abs(edge.x - 0.10)))
		* (1.0 - step(0.04, abs(edge.y - 0.10)));
	ink = mix(ink, bone * 0.65, screw);
	float wear = fract(sin(dot(floor(p * 48.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = ink * (0.94 + wear * 0.08);
	ROUGHNESS = 0.88;
	EMISSION = glow;
}
