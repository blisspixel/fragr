shader_type spatial;
render_mode diffuse_burley, cull_back, depth_draw_opaque;

uniform vec4 chassis_color : source_color;
uniform float chassis_metallic = 0.3;
uniform float chassis_roughness = 0.85;
uniform vec3 chassis_emission : source_color = vec3(0.0);
uniform float camera_clearance = 0.7;

void fragment() {
	// Only the live companion opts in. Retain opaque, depth-tested geometry
	// outside the small eye clearance instead of moving or shrinking its body.
	if (!IN_SHADOW_PASS && -VERTEX.z < camera_clearance) {
		discard;
	}
	ALBEDO = chassis_color.rgb;
	METALLIC = chassis_metallic;
	ROUGHNESS = chassis_roughness;
	EMISSION = chassis_emission;
}
