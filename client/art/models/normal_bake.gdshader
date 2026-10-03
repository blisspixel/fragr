shader_type spatial;
render_mode unshaded;

vec3 to_linear(vec3 color) {
	return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), color));
}

void fragment() {
	// Encoded view normals survive the framebuffer's sRGB transfer unchanged.
	ALBEDO = to_linear(normalize(NORMAL) * 0.5 + 0.5);
}
