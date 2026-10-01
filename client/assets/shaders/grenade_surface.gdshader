shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 effect_color : source_color = vec4(1.0);
uniform float camera_clearance = 0.6;

void fragment() {
	if (-VERTEX.z < camera_clearance) {
		discard;
	}
	ALBEDO = effect_color.rgb;
}
