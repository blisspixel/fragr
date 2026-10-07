class_name WaterRegions
extends RefCounted

static func validation_error(info: Dictionary) -> String:
	var regions: Variant = info.get("water_regions", [])
	if not regions is Array or regions.size() > 32:
		return "Invalid water region list."
	var half: float = float(info.get("half_extent", 0.0))
	for index: int in range(regions.size()):
		var region: Variant = regions[index]
		if not region is Dictionary or region.size() != 4:
			return "Invalid water region."
		for key: String in ["min", "max"]:
			var point: Variant = region.get(key)
			if not point is Array or point.size() != 2:
				return "Invalid water bounds."
			for value: Variant in point:
				if not MapGeometry._number(value) or absf(float(value)) > half:
					return "Invalid water coordinate."
		if not MapGeometry._number(region.get("level")) or not MapGeometry._number(region.get("depth")):
			return "Invalid water depth."
		if region["depth"] <= 0 or region["depth"] > 64 or region["level"] < region["depth"] or region["level"] > half * 2:
			return "Invalid water depth."
		if region["min"][0] >= region["max"][0] or region["min"][1] >= region["max"][1]:
			return "Invalid water bounds."
		for previous: int in range(index):
			var other: Dictionary = regions[previous]
			if region["min"][0] < other["max"][0] and region["max"][0] > other["min"][0] and region["min"][1] < other["max"][1] and region["max"][1] > other["min"][1]:
				return "Overlapping water regions."
	return ""
