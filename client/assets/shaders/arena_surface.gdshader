shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 surface_color : source_color = vec4(0.32, 0.34, 0.35, 1.0);
uniform vec4 accent_color : source_color = vec4(0.48, 0.23, 0.13, 1.0);
uniform float panel_size = 2.0;
uniform int surface_kind = 1; // 0 floor, 1 wall, 2 cover, 3 walkable step
uniform int surface_style = 0; // 0 arcade, 1 concrete, 2 enamel, 3 service, 4 records, 5 lift
// Stepped light level per solid, the old sector trick: each box reads a little
// brighter or darker than its neighbour, so a run of identical panels stops
// looking like one repeated tile. Zero disables it.
uniform float sector_variation = 0.14;
// Deck heights repeat every three metres on the authored maps. Wall bases
// darken toward each deck, a contact shade that costs nothing on Performance.
uniform float deck_spacing = 3.0;
uniform float base_shade = 0.28;
// Union warning pinline under the enamel band, and the glow of steel strips.
uniform vec4 warning_color : source_color = vec4(0.545, 0.118, 0.118, 1.0);
uniform float trim_glow = 0.55;
varying vec3 world_position;
varying vec3 world_normal;

float grain(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float box_mask(vec2 p, vec2 low, vec2 high) {
	vec2 inside = step(low, p) * step(p, high);
	return inside.x * inside.y;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 face = n.y > 0.5 ? world_position.xz : (n.x > 0.5 ? world_position.zy : world_position.xy);
	// Every mark is registered to a 16-texel/metre grid, regardless of box size.
	vec2 pixel = floor(face * 16.0);
	vec2 uv = pixel / (16.0 * panel_size);
	vec2 cell = fract(uv);
	vec2 panel = floor(uv);
	vec2 edge = min(cell, 1.0 - cell);
	float wear = grain(floor(pixel / 4.0));
	float grit = grain(pixel);
	float variation = grain(panel);
	vec3 color = surface_color.rgb * (0.83 + floor(variation * 4.0) * 0.07);
	color *= 0.93 + floor(grit * 3.0) * 0.035;

	if (surface_style > 0) {
		// Restrained institutional surfaces separate public rooms from machinery.
		float joint = 1.0 - step(0.018, min(edge.x, edge.y));
		color *= 1.0 - joint * 0.32;
		if (surface_style == 1) {
			color *= 0.94 + floor(wear * 3.0) * 0.025;
		} else if (surface_style == 2) {
			float vertical = 1.0 - step(0.5, n.y);
			float level = world_position.y - floor(world_position.y / deck_spacing) * deck_spacing;
			float band = step(0.85, level) * step(level, 1.7);
			color = mix(color, accent_color.rgb, band * vertical);
			float pinline = step(0.75, level) * step(level, 0.8125) * vertical;
			color = mix(color, warning_color.rgb, pinline);
			EMISSION = warning_color.rgb * pinline * trim_glow;
		} else if (surface_style == 3) {
			float rib = 1.0 - step(0.08, min(cell.x, 1.0 - cell.x));
			color *= 1.0 - rib * 0.38;
			float plate = box_mask(cell, vec2(0.1, 0.40), vec2(0.9, 0.46));
			color = mix(color, accent_color.rgb, plate * 0.85);
			EMISSION = accent_color.rgb * plate * trim_glow * (1.0 - step(0.5, n.y));
		} else if (surface_style == 4) {
			vec2 tile = fract(face * 2.0);
			float grout = 1.0 - step(0.06, min(tile.x, tile.y));
			color = mix(color, accent_color.rgb * 0.65, grout);
		} else {
			float marker = box_mask(cell, vec2(0.25, 0.15), vec2(0.75, 0.25));
			color = mix(color, accent_color.rgb, marker);
			EMISSION = accent_color.rgb * marker * 0.25;
		}
	} else if (surface_kind == 0) {
		// Concrete slabs, inset drainage strips, and worn lane paint.
		float joint = 1.0 - step(0.018, min(edge.x, edge.y));
		color *= 1.0 - joint * 0.40;
		float drain = step(0.88, cell.x) * step(0.15, cell.y) * step(cell.y, 0.85);
		float bars = step(0.5, fract(pixel.y / 4.0));
		color = mix(color, surface_color.rgb * (0.35 + bars * 0.30), drain * step(0.78, variation));
		float lane = step(3.75, abs(world_position.x)) * step(abs(world_position.x), 4.0);
		float dash = step(0.28, fract(world_position.z / 4.0));
		color = mix(color, vec3(0.55, 0.43, 0.22), lane * dash * step(0.18, wear));
	} else {
		// Framed steel/enamel panels with two-tone bevels and recessed vents.
		float seam = 1.0 - step(0.035, min(edge.x, edge.y));
		float highlight = (1.0 - step(0.055, cell.x)) + step(0.945, cell.y);
		color *= 1.0 - seam * 0.60;
		color += surface_color.rgb * highlight * 0.08;
		float rib = 1.0 - step(0.10, min(cell.x, 1.0 - cell.x));
		color = mix(color, surface_color.rgb * 0.52, rib * 0.60);
		float vent = box_mask(cell, vec2(0.20, 0.56), vec2(0.80, 0.82)) * (1.0 - step(0.5, n.y));
		float slat = step(0.5, fract(pixel.y / 4.0));
		color = mix(color, surface_color.rgb * (0.22 + slat * 0.24), vent * step(0.35, variation));
		float bolt = box_mask(edge, vec2(0.062), vec2(0.105));
		color = mix(color, vec3(0.54, 0.51, 0.46), bolt);
		float rust = step(0.81, wear) * (1.0 - step(0.28, cell.y));
		color = mix(color, vec3(0.30, 0.12, 0.055), rust * 0.55);
		if (n.y < 0.5) {
			float band = step(0.70, world_position.y) * step(world_position.y, 1.05);
			float stripe = step(0.5, fract((pixel.x + pixel.y) / 16.0));
			vec3 hazard = mix(vec3(0.055), vec3(0.62, 0.43, 0.14), stripe);
			color = mix(color, hazard, band * step(0.12, wear));
			float paint = box_mask(cell, vec2(0.12, 0.20), vec2(0.88, 0.40));
			color = mix(color, accent_color.rgb * (0.70 + grit * 0.15), paint * step(0.12, wear));
		} else {
			// Lighter deck plates make walkable tops distinct from vertical cover.
			color *= 1.18;
		}
		if (surface_kind == 3) {
			color = mix(color, vec3(0.62, 0.56, 0.41), seam * 0.5);
		}
	}
	// Sector level from the solid's own centre, stable for the life of the map.
	float sector = grain(floor(NODE_POSITION_WORLD.xz / 4.0) + floor(NODE_POSITION_WORLD.y));
	color *= 1.0 - sector_variation + floor(sector * 4.0) / 3.0 * sector_variation;
	if (n.y < 0.5) {
		float above = world_position.y - floor(world_position.y / deck_spacing + 0.001) * deck_spacing;
		color *= 1.0 - base_shade * (1.0 - smoothstep(0.0, 0.55, above));
	}
	ALBEDO = color;
	ROUGHNESS = 0.94;
}
