shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float camera_clearance = 0.6;

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	// The actual render camera can move after CPU geometry was clipped.
	if (-VERTEX.z < camera_clearance) {
		discard;
	}
	// Vertex alpha fades a lingering beam through an ordered screen dither;
	// an opaque trace (alpha one) always draws.
	ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
	if (COLOR.a < (BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0) {
		discard;
	}
	// Vertex colours are authored as sRGB palette values; ALBEDO is linear.
	vec3 srgb = COLOR.rgb;
	ALBEDO = mix(pow((srgb + 0.055) / 1.055, vec3(2.4)), srgb / 12.92, vec3(lessThan(srgb, vec3(0.04045))));
}
