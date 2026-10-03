shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform float camera_clearance = 0.6;

void fragment() {
	// The actual render camera can move after CPU geometry was clipped.
	if (-VERTEX.z < camera_clearance) {
		discard;
	}
	vec4 texel = texture(sprite_texture, UV);
	if (texel.a < 0.5) {
		discard;
	}
	ALBEDO = texel.rgb;
}
