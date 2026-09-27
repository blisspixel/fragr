class_name NameplateLayout
extends RefCounted

## Keep the most useful readable nameplate when projected labels overlap.
## Entries have id, screen rect, priority (lower wins), and camera distance.
static func choose(entries: Array[Dictionary]) -> Array[String]:
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
