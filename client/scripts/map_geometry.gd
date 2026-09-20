extends RefCounted
class_name MapGeometry

## Wire bounds mirror movement::validate_geometry and the geometry contract.
const VERSION: int = 2
const MAX_HALF: float = 256.0
const MAX_SOLIDS: int = 2048

static func validation_error(info: Dictionary) -> String:
	var version: Variant = info.get("geometry_version", 1)
	if not _integer(version, 1, VERSION):
		return "Unsupported map geometry version. Update your client."
	if not _integer(info.get("map_id"), 1, 4294967295):
		return "Invalid map identity."
	var half: Variant = info.get("half_extent")
	if not _number(half) or half < 2.0 or half > MAX_HALF:
		return "Invalid map extent."
	var solids: Variant = info.get("solids")
	if not solids is Array or solids.size() > MAX_SOLIDS:
		return "Invalid map solid list."
	for entry: Variant in solids:
		if not entry is Dictionary:
			return "Invalid map solid."
		var solid: Dictionary = entry
		var bounds: Array = [solid.get("min_x"), solid.get("max_x"),
			solid.get("min_z"), solid.get("max_z"),
			solid.get("bottom", MoveStep.GROUND_Y), solid.get("top", MoveStep.WALL_TOP)]
		for value: Variant in bounds:
			if not _number(value) or absf(float(value)) > MAX_HALF * 2.0:
				return "Invalid map solid coordinate."
		if bounds[0] >= bounds[1] or bounds[2] >= bounds[3] or bounds[4] < 0.0 or bounds[4] >= bounds[5]:
			return "Invalid map solid bounds."
		if version < 2 and bounds[4] != 0.0:
			return "Raised solids require map geometry version 2."
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value) and value >= low and value <= high and float(value) == floorf(float(value))
