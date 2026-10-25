shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

// Camera-facing atlas sprites lit by the room: smoke, trails and debris.
// Hard alpha and an ordered screen dither for fading, never blending, so the
// pixels stay pixels. Vertex red is how much the sprite also lights itself:
// a little for smoke, so it reads grey and not black in a dark room, and
// fully for a thrown ember. Vertex alpha is the dither density.
uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform float camera_clearance = 0.6;
uniform float emission_energy = 1.0;

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	// The actual render camera can move after CPU geometry was built.
	if (-VERTEX.z < camera_clearance) {
		discard;
	}
	vec4 texel = texture(sprite_texture, UV);
	if (texel.a < 0.5) {
		discard;
	}
	ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
	if (COLOR.a < (BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0) {
		discard;
	}
	ALBEDO = texel.rgb;
	EMISSION = texel.rgb * COLOR.r * emission_energy;
	ROUGHNESS = 1.0;
}
