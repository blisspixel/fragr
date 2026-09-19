shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec4 surface_color : source_color = vec4(0.32, 0.30, 0.27, 1.0);
uniform float panel_size = 2.0;
uniform bool floor_surface = false;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 face = n.y > 0.5 ? world_position.xz : (n.x > 0.5 ? world_position.zy : world_position.xy);
	vec2 cell = fract(face / panel_size);
	vec2 edge = min(cell, vec2(1.0) - cell);
	float seam = 1.0 - step(0.012, min(edge.x, edge.y));
	// Restrained large panels give distance and cover a readable scale.
	float alternate = mod(floor(face.x / panel_size) + floor(face.y / panel_size), 2.0);
	vec3 color = surface_color.rgb * (0.94 + alternate * 0.06);
	color *= 1.0 - seam * 0.28;
	if (!floor_surface && n.y < 0.5) {
		float trim = step(0.91, fract(world_position.y / 1.5));
		color = mix(color, surface_color.rgb * 1.28, trim * 0.6);
	}
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
