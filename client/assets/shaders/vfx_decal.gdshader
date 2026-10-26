shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

// A mark painted on a struck face: shot pocks and blast scorches. Lit like
// the wall it sits on. Vertex alpha fades it out through an ordered screen
// dither, never blending; vertex red is the scorch heat, which keeps ember
// pixels glowing amber for a moment and then cools them to rust.
uniform sampler2D decal_texture : source_color, filter_nearest;

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 texel = texture(decal_texture, UV);
	if (texel.a < 0.5) {
		discard;
	}
	ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
	if (COLOR.a < (BAYER[cell.y * 4 + cell.x] + 0.5) / 16.0) {
		discard;
	}
	// Ember pixels are the only warm ones in the atlas.
	float ember = step(0.15, texel.r - texel.b) * step(0.45, texel.r);
	vec3 cooled = vec3(0.24, 0.13, 0.09);
	ALBEDO = mix(texel.rgb, mix(cooled, texel.rgb, COLOR.r), ember);
	EMISSION = texel.rgb * ember * COLOR.r * 1.6;
	ROUGHNESS = 1.0;
}
