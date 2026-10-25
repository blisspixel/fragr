shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Refuge crowd clothing: one free citizen atlas worn by many different
// people. The human atlas's coat (saturated rust), its trousers and trim
// (slate blue) and its skin (light peach) are found by hue and value and
// recoloured per person, keeping every painted fold, seam and patch. The
// synthetic atlas's grey-green panels take the personal colour and its pale
// plates warm a step, so no free body reads as matte off-white. Presentation
// only; nothing here is identity or a faction mark.

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec3 coat : source_color = vec3(0.55, 0.32, 0.20);
uniform vec3 trousers : source_color = vec3(0.20, 0.24, 0.28);
uniform vec3 skin : source_color = vec3(1.0, 1.0, 1.0);
// Value lift: keeps a crowd in the mid range under night light.
uniform float lift = 1.0;
uniform bool synthetic = false;

vec3 hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-6)), d / (q.x + 1e-6), q.x);
}

// Forward+ and Mobile hand the painted atlas and the colours over in linear
// light and expect linear albedo. The Compatibility renderer hands both over
// as painted and shows albedo as given, so there the conversions are none;
// converting anyway left coats rust and turned shirts white.
vec3 to_srgb(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return max(c, vec3(0.0));
#else
	return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
#endif
}

vec3 to_linear(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return max(c, vec3(0.0));
#else
	return pow(max(c, vec3(0.0)), vec3(2.2));
#endif
}

// A new colour at the painted value: `reference` is the atlas's typical
// value for that region, so a fold keeps its shade in the new cloth.
vec3 recolour(vec3 colour, float value, float reference) {
	return to_linear(to_srgb(colour) * (value / reference));
}

void fragment() {
	vec3 texel = texture(albedo_texture, UV).rgb;
	vec3 h = hsv(to_srgb(texel));
	vec3 base = texel;
	if (synthetic) {
		float panel = step(0.16, h.x) * step(h.x, 0.5) * step(0.05, h.y) * step(0.12, h.z);
		float plate = step(0.62, h.z) * step(h.y, 0.22);
		base = mix(base, recolour(coat, h.z, 0.42), panel);
		base = mix(base, texel * skin, plate);
	} else {
		// Peach skin: warm hue, light and only moderately saturated.
		float skin_mask = step(0.015, h.x) * step(h.x, 0.12) * step(0.72, h.z) * step(h.y, 0.5);
		// Rust coat: the same warm hue, darker or more saturated than skin.
		float coat_mask = step(h.x, 0.12) * step(0.3, h.y) * step(0.12, h.z) * (1.0 - skin_mask);
		// Slate trousers, straps and trim: cool blue.
		float cloth_mask = step(0.45, h.x) * step(h.x, 0.72) * step(0.1, h.y) * step(0.08, h.z);
		base = mix(base, recolour(coat, h.z, 0.55), coat_mask);
		base = mix(base, recolour(trousers, h.z, 0.32), cloth_mask);
		base = mix(base, texel * skin, skin_mask);
	}
	ALBEDO = clamp(base * lift, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.95;
}
