class_name MapDecoration
extends RefCounted

## Wire contract mirrored from protocol/decoration.rs. No resource paths in data.
const MAX_DETAILS: int = 128
const MAX_LIGHTS: int = 8
const KINDS: Array[String] = ["property_sign", "intake_sign", "records_sign",
	"maintenance_sign", "transfer_sign", "lift_sign", "complaint_notice",
	"union_seal", "lockers", "vent", "terminal", "strip_light"]
const FACES: Array[String] = ["west", "east", "down", "up", "north", "south"]
const OFFSET: float = 0.012

static func dimensions(solid: Dictionary, face: String) -> Vector2:
	var size: Vector3 = _size(solid)
	match face:
		"west", "east": return Vector2(size.z, size.y)
		"up", "down": return Vector2(size.x, size.z)
		_: return Vector2(size.x, size.y)

static func validation_error(value: Variant, solids: Array) -> String:
	const INVALID: String = "Invalid map surface decoration."
	if not value is Array or value.size() > MAX_DETAILS:
		return INVALID
	var lights: int = 0
	for entry: Variant in value:
		if not entry is Dictionary or entry.size() != 5:
			return INVALID
		if not EquipmentState.integer(entry.get("solid"), maxi(0, solids.size() - 1)) or solids.is_empty() \
			or not entry.get("face") is String or entry["face"] not in FACES \
			or not entry.get("kind") is String or entry["kind"] not in KINDS:
			return INVALID
		var center: Variant = entry.get("center")
		var size: Variant = entry.get("size")
		if not center is Array or center.size() != 2 or not size is Array or size.size() != 2:
			return INVALID
		var extent: Vector2 = dimensions(solids[int(entry["solid"])], entry["face"])
		for axis: int in range(2):
			if not is_finite(extent[axis]) or extent[axis] <= 0.0 \
				or not _number(center[axis]) or not _number(size[axis]) \
				or size[axis] < 0.125 or size[axis] > 16.0 \
				or absf(float(center[axis])) + float(size[axis]) * 0.5 > extent[axis] * 0.5:
				return INVALID
		if entry["kind"] == "strip_light":
			lights += 1
			if lights > MAX_LIGHTS:
				return INVALID
	return ""

## Each basis is right-handed, with local +Z pointing out of the host face.
## The same axes interpret authoring centre offsets and render the quad/label.
static func face_basis(face: String) -> Basis:
	match face:
		"west": return Basis(Vector3.BACK, Vector3.UP, Vector3.LEFT)
		"east": return Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT)
		"down": return Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
		"up": return Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
		"north": return Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD)
		_: return Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)

static func placement(solid: Dictionary, detail: Dictionary) -> Transform3D:
	var basis: Basis = face_basis(detail["face"])
	var size: Vector3 = _size(solid)
	var center: Vector3 = Vector3(solid.min_x, solid.get("bottom", MoveStep.GROUND_Y), solid.min_z) + size * 0.5
	var distance: float = absf(basis.z.dot(size)) * 0.5 + OFFSET
	return Transform3D(basis, center + basis.z * distance \
		+ basis.x * float(detail["center"][0]) + basis.y * float(detail["center"][1]))

static func _size(solid: Dictionary) -> Vector3:
	return Vector3(float(solid.max_x) - float(solid.min_x),
		float(solid.get("top", MoveStep.WALL_TOP)) - float(solid.get("bottom", MoveStep.GROUND_Y)),
		float(solid.max_z) - float(solid.min_z))

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
