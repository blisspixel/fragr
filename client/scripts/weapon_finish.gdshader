shader_type canvas_item;
render_mode unshaded;

uniform vec3 paint_tint = vec3(1.0);

void fragment() {
	// Only neutral dark metal above the grip. Warm gloves, colored lights,
	// highlights, muzzle paint, alpha and the entire silhouette stay intact.
	float low = min(COLOR.r, min(COLOR.g, COLOR.b));
	float high = max(COLOR.r, max(COLOR.g, COLOR.b));
	if (UV.y < 0.73 && low > 0.07 && high < 0.55 && high - low < 0.13 * high) {
		vec3 painted = COLOR.rgb * paint_tint;
		vec3 weights = vec3(0.2126, 0.7152, 0.0722);
		painted *= dot(COLOR.rgb, weights) / max(dot(painted, weights), 0.0001);
		COLOR.rgb = painted;
	}
}
