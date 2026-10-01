shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float camera_clearance = 0.6;

void fragment() {
	// The actual render camera can move after CPU geometry was clipped.
	if (-VERTEX.z < camera_clearance) {
		discard;
	}
	ALBEDO = COLOR.rgb;
}
