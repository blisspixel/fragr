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
//
// Absorbed bots (Inheritance control) keep their Union chassis, paint and
// plates, but their red goes dead: red pixels drop to a dull unlit oxblood,
// and the brightest of them (optics, visor slits, tell lights) carry the
// Inheritance's muted cyan working glow instead.

uniform sampler2D sprite_texture : source_color, filter_nearest;
uniform sampler2D sprite_normals : filter_nearest;
uniform bool normals_enabled = false;
uniform vec3 charcoal : source_color = vec3(0.196, 0.196, 0.216); // a step above union_steel
uniform float body_lift = 0.5;
// Issued plate value for a sheet painted lighter than the issued black. The
// Heavy Sweeper's plates are baked about 3.7x brighter (linear) than a
// Clerk's cloth and it has no normal map, so its flat quad took the whole key
// and fill and read tan in daylight. Scaling only non-red body texels keeps
// the plate shading and leaves optics, visor, armbands and tells untouched.
uniform float body_value = 1.0;
uniform float red_glow = 1.6;
uniform vec3 rim_color : source_color = vec3(0.42, 0.44, 0.50);
uniform float rim_glow = 0.55;
// Redactor approach only: one texel of visible scan jitter, never invisibility.
uniform float shimmer = 0.0;
uniform float shimmer_tick = 0.0;
uniform float absorbed = 0.0;
uniform vec3 work_glow : source_color = vec3(0.290, 0.541, 0.573); // #4A8A92
uniform float work_energy = 1.1;

void vertex() {
	// Keep the scene camera basis during light-camera shadow draws as well.
	// This matches the engine's current BILLBOARD_FIXED_Y transform.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
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
	vec2 shimmer_uv = UV + vec2(floor(sin(floor(UV.y * float(textureSize(sprite_texture, 0).y) / 3.0) + shimmer_tick * 0.7) * 1.5) * shimmer / float(textureSize(sprite_texture, 0).x), 0.0);
	vec4 texel = texture(sprite_texture, shimmer_uv);
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
		float red = red_mask(texel.rgb);
		// Scale before the lift, so the darkest texels still reach charcoal.
		vec3 scaled = mix(texel.rgb * body_value, texel.rgb, red);
		vec3 body = mix(scaled, max(scaled, charcoal), body_lift * dark);
		// Dead optics: the red's own value, drained to an unlit oxblood.
		vec3 dead = vec3(texel.r * 0.22, texel.r * 0.07, texel.r * 0.06);
		vec3 albedo = mix(body, mix(body, dead, red), absorbed);
		ALBEDO = albedo * tint;
		if (normals_enabled) {
			NORMAL_MAP = texture(sprite_normals, UV).rgb;
			NORMAL_MAP_DEPTH = 1.0;
		}
		// Only the brightest red points were lights; only they take the glow.
		// Union optic red sits near 0.26 linear; painted red trim is darker.
		float lamp = red * smoothstep(0.13, 0.22, texel.r);
		// Above its resting level the attack tell adds saturated red, never
		// white: a lighter red pixel driven hard would otherwise clip to pink.
		float resting = min(red_glow, 1.6);
		vec3 union_light = texel.rgb * red * resting
			+ vec3(1.0, 0.07, 0.05) * red * texel.r * max(red_glow - resting, 0.0);
		vec3 working_light = work_glow * lamp * work_energy;
		EMISSION = mix(union_light, working_light, absorbed) * tint;
	}
	ROUGHNESS = 1.0;
}
