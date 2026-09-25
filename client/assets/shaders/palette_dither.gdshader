shader_type canvas_item;

// Ordered 4x4 Bayer dither onto the locked palette (docs/palette.json).
// It reads the upscaled 3D frame from a canvas layer below the HUD, so menus
// and HUD text stay native. The threshold matrix is indexed by the screen
// position divided by the world pixel size, which keeps the pattern on the
// low-resolution 3D grid instead of crawling across native pixels.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float pixel_size = 1.0;
// sRGB swatches, 0 to 1: the world subset of palette.json (render_quality.gd).
uniform vec3 palette[14];
uniform int palette_size = 14;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / max(pixel_size, 1.0));
	vec2 source_pixel = (cell + 0.5) * max(pixel_size, 1.0);
	vec3 color = textureLod(screen_texture, source_pixel * SCREEN_PIXEL_SIZE, 0.0).rgb;
	ivec2 b = ivec2(mod(cell, 4.0));
	float threshold = (BAYER[b.y * 4 + b.x] + 0.5) / 16.0;
	// The two nearest swatches, then place the colour along the segment
	// between them. The threshold picks which one this cell shows.
	int first = 0;
	int second = 0;
	float best = 1e9;
	float next = 1e9;
	for (int i = 0; i < min(palette_size, 14); i++) {
		vec3 d = color - palette[i];
		float distance = dot(d, d);
		if (distance < best) {
			next = best;
			second = first;
			best = distance;
			first = i;
		} else if (distance < next) {
			next = distance;
			second = i;
		}
	}
	vec3 a = palette[first];
	vec3 c = palette[second];
	vec3 segment = c - a;
	float along = clamp(dot(color - a, segment) / max(dot(segment, segment), 1e-5), 0.0, 1.0);
	COLOR = vec4(along > threshold ? c : a, 1.0);
}
