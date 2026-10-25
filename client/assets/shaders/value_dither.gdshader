shader_type canvas_item;

// Ordered 4x4 Bayer dither in value steps over the 3D frame.
// It reads the upscaled 3D frame from a canvas layer below the HUD, so menus
// and HUD text stay native. The threshold matrix is indexed by the screen
// position divided by the world pixel size, which keeps the pattern on the
// low-resolution 3D grid instead of crawling across native pixels.
//
// Only value is stepped; each pixel keeps its own hue and saturation. The
// first version snapped every pixel to the fourteen world swatches of
// docs/palette.json, and in a lit scene that rewrote meaning: a Union seal's
// red dithered to orange, the Larak indigo sky to grey and brown, and bone
// enamel to orange blotches. Red stays the Union's tell and cyan the
// Inheritance's light, so the dither may shade a colour, never replace it.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float pixel_size = 1.0;
// Value steps between black and white. Fewer is coarser banding.
uniform float steps = 10.0;

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
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	float count = max(steps, 2.0);
	// The cell shows the step below or above its value, in proportion.
	float level = floor(luma * count + threshold) / count;
	vec3 shaded = luma > 0.0005 ? color * (level / luma) : vec3(level);
	COLOR = vec4(clamp(shaded, 0.0, 1.0), 1.0);
}
