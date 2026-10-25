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
// Hand paint for marks a person put there: the free side's circled six, chalk.
uniform vec4 paint_color : source_color = vec4(0.769, 0.353, 0.125, 1.0);
uniform vec4 wood_color : source_color = vec4(0.427, 0.322, 0.220, 1.0);
uniform vec4 amber_color : source_color = vec4(0.941, 0.722, 0.376, 1.0);

float box(vec2 p, vec2 lo, vec2 hi) {
	return step(lo.x, p.x) * step(lo.y, p.y) * step(p.x, hi.x) * step(p.y, hi.y);
}

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

// A hand-drawn numeral on a 4x6 grid, row 0 on top: the six and the seven of
// the free side's marks. `q` is the position inside the glyph box, 0..1.
float numeral(int digit, vec2 q) {
	if (q.x < 0.0 || q.y < 0.0 || q.x >= 1.0 || q.y >= 1.0) {
		return 0.0;
	}
	int column = int(floor(q.x * 4.0));
	int row = int(floor((1.0 - q.y) * 6.0));
	int bits = 0;
	if (digit == 6) {
		bits = row == 0 ? 6 : row == 1 ? 8 : row == 2 ? 14 : row == 5 ? 6 : 9;
	} else {
		bits = row == 0 ? 15 : row == 1 ? 1 : row == 2 ? 2 : 4;
	}
	return float((bits >> (3 - column)) & 1);
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
	} else if (style == 9) {
		// Stencil: the paint is the copy itself, straight on the host surface.
		discard;
	} else if (style == 10 || style == 11) {
		// Hand marks on the wall, no plate: the circled six (10) or a child's
		// chalk 67 (11). Bare paint, a little overspray, nothing else drawn.
		vec2 m = vec2(p.x, panel_size.y - p.y);
		vec2 c = panel_size * 0.5;
		float paint = 0.0;
		float grain = hash(floor(m * 48.0) + vec2(3.0, 7.0));
		if (style == 10) {
			float r = min(0.24, 0.46 * min(panel_size.x, panel_size.y));
			float d = length(m - c);
			paint = step(r * 0.74, d) * step(d, r);
			vec2 glyph = vec2(r * 0.72, r * 1.08);
			paint = max(paint, numeral(6, (m - (c - glyph * 0.5)) / glyph));
			// A run of paint under the ring where the can stayed too long.
			float drip = step(abs(m.x - c.x - r * 0.42), 0.011) * step(c.y - r * 1.45, m.y) * step(m.y, c.y - r * 0.8);
			paint = max(paint, drip);
			paint *= step(0.08, grain);
		} else {
			float h = min(0.3, 0.8 * min(panel_size.y, panel_size.x * 0.6));
			vec2 glyph = vec2(h * 0.66, h);
			float gap = h * 0.18;
			vec2 start = c - vec2(glyph.x + gap * 0.5, h * 0.5);
			paint = max(numeral(6, (m - start) / glyph), numeral(7, (m - start - vec2(glyph.x + gap, 0.0)) / glyph));
			paint *= step(0.3, grain);
		}
		if (paint < 0.5) {
			discard;
		}
		ink = paint_color.rgb * (0.9 + grain * 0.1);
	} else if (style == 12) {
		// A board of pinned papers and a photograph or two: nobody stops to
		// read it, everybody knows what it is.
		ink = mix(green_color.rgb * 0.62, wood_color.rgb * 0.7, 0.35);
		vec2 m = vec2(p.x, panel_size.y - p.y);
		vec2 cell_size = vec2(0.42, 0.5);
		vec2 cell = floor(m / cell_size);
		vec2 local = m - cell * cell_size;
		float h1 = hash(cell + vec2(1.0, 2.0));
		float h2 = hash(cell + vec2(5.0, 9.0));
		vec2 offset = vec2(0.03 + h1 * 0.06, 0.03 + h2 * 0.07);
		vec2 sheet = vec2(0.3, 0.38) - vec2(h2, h1) * 0.06;
		float inside = box(local, offset, offset + sheet) * step(0.18, h1)
			* step(cell.x * cell_size.x + offset.x + sheet.x, panel_size.x - 0.05)
			* step(cell.y * cell_size.y + offset.y + sheet.y, panel_size.y - 0.05)
			* step(0.05, cell.x * cell_size.x + offset.x) * step(0.05, cell.y * cell_size.y + offset.y);
		vec2 s = local - offset;
		vec3 paper = mix(bone, vec3(0.86, 0.80, 0.62), step(0.6, h2)) * 0.95;
		if (h1 > 0.82) {
			// A photograph: a dark print with a pale figure, a white border.
			float print = box(s, vec2(0.03, 0.12), sheet - vec2(0.03, 0.03));
			float figure = step(length((s - vec2(sheet.x * 0.5, sheet.y * 0.62)) * vec2(1.0, 0.8)), 0.055)
				+ box(s, vec2(sheet.x * 0.5 - 0.07, 0.12), vec2(sheet.x * 0.5 + 0.07, sheet.y * 0.5));
			paper = mix(paper, mix(steel * 0.5, bone * 0.8, min(figure, 1.0)), print);
		} else {
			// Ruled handwriting, too small to read from where you stand.
			float rule = step(fract(s.y / 0.034), 0.34) * step(0.04, s.y) * step(s.y, sheet.y - 0.07);
			float length_left = sheet.x - 0.03 - hash(vec2(cell.x, floor(s.y / 0.034))) * 0.12;
			rule *= step(0.03, s.x) * step(s.x, length_left) * step(0.22, hash(floor(m * 48.0)));
			paper = mix(paper, dark * 1.6, rule * 0.55);
			// A heading bar, inked heavier.
			paper = mix(paper, dark, box(s, vec2(0.03, sheet.y - 0.06), vec2(sheet.x * 0.7, sheet.y - 0.035)) * 0.8);
		}
		float pin = box(s, vec2(sheet.x * 0.5 - 0.011, sheet.y - 0.03), vec2(sheet.x * 0.5 + 0.011, sheet.y - 0.008));
		paper = mix(paper, red_color.rgb, pin);
		ink = mix(ink, paper, inside);
		ink = mix(ink, wood_color.rgb * 0.8, frame);
	} else if (style == 13) {
		// A chalkboard written up in the morning: lines of chalk, a frame.
		ink = vec3(0.13, 0.16, 0.15);
		vec2 m = vec2(p.x, panel_size.y - p.y);
		float row = floor((panel_size.y - m.y - 0.08) / 0.085);
		float within = fract((panel_size.y - m.y - 0.08) / 0.085);
		float reach = 0.1 + (panel_size.x - 0.2) * (0.45 + 0.5 * hash(vec2(row, 3.0)));
		float word = step(0.16, fract(m.x / (0.13 + 0.05 * hash(vec2(row, 1.0)))));
		float chalk = step(within, 0.38) * step(0.1, m.x) * step(m.x, reach) * word
			* step(0.08, panel_size.y - m.y) * step(0.1, m.y) * step(0.35, hash(floor(m * 48.0)));
		ink = mix(ink, bone * 0.86, chalk);
		ink = mix(ink, wood_color.rgb, frame);
	} else if (style == 14) {
		// A service door's hazard plate: diagonal amber and ink, no words.
		float band = step(0.5, fract((p.x + p.y) / 0.14));
		ink = mix(dark, amber_color.rgb * 0.82, band);
		ink = mix(ink, steel, frame);
	} else if (style == 15) {
		// The Office's lift pictogram on its green plate: a barred car between
		// up and down arrows. The lift is the way on; no words are needed.
		ink = mix(green_color.rgb, steel, frame);
		vec2 m = vec2(p.x, panel_size.y - p.y) - panel_size * 0.5;
		float u = min(panel_size.y, panel_size.x * 0.5) * 0.5;
		vec2 q = m / u;
		float car = box(q, vec2(-0.42, -0.5), vec2(0.42, 0.5)) * (1.0 - box(q, vec2(-0.32, -0.4), vec2(0.32, 0.4)));
		float bars = box(q, vec2(-0.32, -0.4), vec2(0.32, 0.4)) * step(0.62, fract((q.x + 0.32) * 3.1));
		float up = step(abs(q.x - 1.05), (0.95 - q.y) * 0.5) * step(0.25, q.y) * step(q.y, 0.95);
		float down = step(abs(q.x - 1.05), (q.y + 0.95) * 0.5) * step(q.y, -0.25) * step(-0.95, q.y);
		ink = mix(ink, bone, max(max(car, bars), max(up, down)));
	} else if (style == 16) {
		// Free-side signwriting: painted planks, a painted border, no enamel.
		float plank = floor(p.y / 0.16);
		ink = wood_color.rgb * (0.82 + hash(vec2(plank, 4.0)) * 0.22);
		ink = mix(ink, wood_color.rgb * 0.45, 1.0 - step(0.012, fract(p.y / 0.16) * 0.16));
		float inset = min(0.05, min(panel_size.x, panel_size.y) * 0.1);
		float border = box(p, vec2(inset), panel_size - vec2(inset)) * (1.0 - box(p, vec2(inset + 0.022), panel_size - vec2(inset + 0.022)));
		ink = mix(ink, paint_color.rgb, border);
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
