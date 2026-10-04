shader_type spatial;
render_mode diffuse_burley, cull_back, depth_draw_opaque;

uniform vec4 chassis_color : source_color;
uniform bool finish_enabled = false;
uniform sampler2D chassis_finish : source_color, filter_nearest, repeat_enable;
uniform float chassis_metallic = 0.3;
uniform float chassis_roughness = 0.85;
uniform bool normal_enabled = false;
uniform sampler2D chassis_normal : hint_normal, filter_nearest, repeat_enable;
uniform float normal_strength = 1.0;
uniform bool metallic_enabled = false;
uniform sampler2D chassis_metallic_map : filter_nearest, repeat_enable;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool roughness_enabled = false;
uniform sampler2D chassis_roughness_map : filter_nearest, repeat_enable;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec3 chassis_emission : source_color = vec3(0.0);
uniform vec3 chassis_origin = vec3(0.0);
uniform float chassis_center_height = 1.2;
uniform float near_hide_distance = 1.1;
uniform float near_full_distance = 1.35;

float ordered_threshold(vec2 pixel) {
	ivec2 cell = ivec2(mod(floor(pixel), 4.0));
	vec4 row = cell.y == 0 ? vec4(0.0, 8.0, 2.0, 10.0) :
		(cell.y == 1 ? vec4(12.0, 4.0, 14.0, 6.0) :
		(cell.y == 2 ? vec4(3.0, 11.0, 1.0, 9.0) : vec4(15.0, 7.0, 13.0, 5.0)));
	return (row[cell.x] + 0.5) / 16.0;
}

void fragment() {
	// All live chassis parts share one world anchor and the actual render eye.
	// A depth plane through individual faces exposes disconnected head facets.
	// Ordered coverage fades the complete figure without changing its geometry,
	// opaque depth behavior outside the short transition, or shadow silhouette.
	if (!IN_SHADOW_PASS) {
		vec3 centre = chassis_origin + vec3(0.0, chassis_center_height, 0.0);
		float visibility = smoothstep(near_hide_distance, near_full_distance,
			distance(INV_VIEW_MATRIX[3].xyz, centre));
		if (visibility < ordered_threshold(FRAGCOORD.xy)) {
			discard;
		}
	}
	ALBEDO = chassis_color.rgb * (finish_enabled ? texture(chassis_finish, UV).rgb : vec3(1.0));
	METALLIC = chassis_metallic * (metallic_enabled ? dot(texture(chassis_metallic_map, UV), metallic_channel) : 1.0);
	ROUGHNESS = chassis_roughness * (roughness_enabled ? dot(texture(chassis_roughness_map, UV), roughness_channel) : 1.0);
	if (normal_enabled) {
		NORMAL_MAP = texture(chassis_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
	EMISSION = chassis_emission;
}
