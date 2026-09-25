shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, depth_draw_opaque;

// Union enemy billboard. Replaces the Sprite3D default material so a black
// and red body stays readable in fixture-lit rooms:
// - red optics, visors, armbands and tell lights are full-bright pixels,
//   emissive and independent of the light they stand in, as in the old
//   bright-pixel colormaps;
// - the darkest body values lift slightly toward charcoal, never to grey;
// - a one-texel silhouette line separates the body from any wall. It is a
//   dim cool value, so it reads as a rim on dark walls and an outline on
//   bright ones.
// Billboarding, nearest sampling, alpha cut and the hit-flash modulate
// (vertex colour) match the Sprite3D settings this replaces.

uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform vec3 charcoal : source_color = vec3(0.196, 0.196, 0.216); // a step above union_steel
uniform float body_lift = 0.5;
uniform float red_glow = 1.6;
uniform vec3 rim_color : source_color = vec3(0.42, 0.44, 0.50);
uniform float rim_glow = 0.55;

void vertex() {
	// BILLBOARD_FIXED_Y, the same transform the engine generates for Sprite3D.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float red_mask(vec3 c) {
	// Linear values: union_red is about (0.26, 0.01, 0.01).
	return step(0.12, c.r) * step(c.g * 3.0, c.r) * step(c.b * 3.0, c.r);
}

void fragment() {
	vec4 texel = texture(sprite_texture, UV);
	vec2 step_uv = 1.0 / vec2(textureSize(sprite_texture, 0));
	vec3 tint = COLOR.rgb;
	if (texel.a < 0.5) {
		float edge = max(
			max(texture(sprite_texture, UV + vec2(step_uv.x, 0.0)).a, texture(sprite_texture, UV - vec2(step_uv.x, 0.0)).a),
			max(texture(sprite_texture, UV + vec2(0.0, step_uv.y)).a, texture(sprite_texture, UV - vec2(0.0, step_uv.y)).a));
		if (edge < 0.5) {
			discard;
		}
		ALBEDO = vec3(0.0);
		EMISSION = rim_color * rim_glow;
	} else {
		float value = max(max(texel.r, texel.g), texel.b);
		float dark = 1.0 - smoothstep(0.0, 0.06, value);
		vec3 body = mix(texel.rgb, max(texel.rgb, charcoal), body_lift * dark);
		float red = red_mask(texel.rgb);
		ALBEDO = body * tint;
		EMISSION = texel.rgb * red * red_glow * tint;
	}
	ROUGHNESS = 1.0;
}
