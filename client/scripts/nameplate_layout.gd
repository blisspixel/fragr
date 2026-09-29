class_name NameplateLayout
extends RefCounted

## Keep the most useful readable nameplate when projected labels overlap.
## Entries have id, screen rect, priority (lower wins), and camera distance.
## Reserved rects, such as a flag cloth, are already occupied.
static func choose(entries: Array[Dictionary], reserved: Array = []) -> Array[String]:
	var ordered: Array[Dictionary] = entries.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) < int(b["priority"])
		var a_distance_cm: int = roundi(float(a["distance"]) * 100.0)
		var b_distance_cm: int = roundi(float(b["distance"]) * 100.0)
		if a_distance_cm != b_distance_cm:
			return a_distance_cm < b_distance_cm
		return str(a["id"]) < str(b["id"])
	)
	var visible: Array[String] = []
	var occupied: Array[Rect2] = []
	for area: Variant in reserved:
		if area is Rect2 and (area as Rect2).size != Vector2.ZERO:
			occupied.append(area)
	for entry: Dictionary in ordered:
		var area: Rect2 = entry["rect"]
		var overlaps: bool = false
		for prior: Rect2 in occupied:
			if prior.intersects(area):
				overlaps = true
				break
		if not overlaps:
			visible.append(str(entry["id"]))
			occupied.append(area)
	return visible


## Screen rect of a billboard label, grown slightly so neighbors do not touch it.
static func project_label(view: Camera3D, label: Label3D) -> Rect2:
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var text_size: Vector2 = Vector2(label.text.length() * label.font_size * 0.6, label.font_size)
	if font != null:
		text_size = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
	var width: float = (text_size.x + label.outline_size * 2.0 + 12.0) * label.pixel_size * label.scale.x
	var height: float = (text_size.y + label.outline_size + 8.0) * label.pixel_size * label.scale.y
	return project_span(view, label.global_position, width * 0.5, height * 0.5)


## Screen-aligned span around a world point. An empty rect means the point is behind the camera.
static func project_span(view: Camera3D, world_center: Vector3, half_width: float, half_height: float) -> Rect2:
	if view == null or view.is_position_behind(world_center) or half_width <= 0.0 or half_height <= 0.0:
		return Rect2()
	var right: Vector3 = view.global_transform.basis.x.normalized()
	var up: Vector3 = view.global_transform.basis.y.normalized()
	var left_px: Vector2 = view.unproject_position(world_center - right * half_width)
	var right_px: Vector2 = view.unproject_position(world_center + right * half_width)
	var top_px: Vector2 = view.unproject_position(world_center + up * half_height)
	var bottom_px: Vector2 = view.unproject_position(world_center - up * half_height)
	return Rect2(Vector2(minf(left_px.x, right_px.x), minf(top_px.y, bottom_px.y)),
		Vector2(absf(right_px.x - left_px.x), absf(bottom_px.y - top_px.y))).grow(4.0)
