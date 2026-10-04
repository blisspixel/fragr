extends RefCounted

const JOINT: AABB = AABB(Vector3(0.34, 0.070, -0.075), Vector3(0.205, 0.067, 0.150))
const HANDLE: AABB = AABB(Vector3(0.33, -0.006, -0.078), Vector3(0.095, 0.129, 0.053))
const OPTIC_FRONT: AABB = AABB(Vector3(0.055, 0.135, -0.027), Vector3(0.057, 0.090, 0.087))
const OPTIC_BACK: AABB = AABB(Vector3(0.416, 0.137, -0.025), Vector3(0.029, 0.088, 0.085))
const GRID: float = 4093.0

static func fingerprint(points: PackedVector3Array, uv: PackedVector2Array, uv_shift: Vector2 = Vector2.ZERO, reverse: bool = false) -> Dictionary:
	var signatures: Array[String] = signature_list(points, uv, uv_shift, reverse)
	return {"triangles":signatures.size(), "position_uv_winding_sha256":"\n".join(signatures).sha256_text(), "grid":GRID}

static func signature_list(points: PackedVector3Array, uv: PackedVector2Array, uv_shift: Vector2 = Vector2.ZERO, reverse: bool = false) -> Array[String]:
	var signatures: Array[String] = []
	for face: int in range(0, points.size(), 3):
		var box: AABB = AABB(points[face], Vector3.ZERO).expand(points[face + 1]).expand(points[face + 2])
		var replaced: bool = false
		for cut: AABB in [JOINT, HANDLE, OPTIC_FRONT, OPTIC_BACK]:
			replaced = replaced or cut.grow(0.00001).intersects(box.grow(0.00001))
		if replaced:
			continue
		var corners: Array[String] = []
		for offset: int in ([0, 2, 1] if reverse else [0, 1, 2]):
			var point: Vector3 = points[face + offset] * GRID
			var texel: Vector2 = (uv[face + offset] + uv_shift) * GRID
			corners.append("%d,%d,%d:%d,%d" % [roundi(point.x), roundi(point.y), roundi(point.z), roundi(texel.x), roundi(texel.y)])
		var rotations: Array[String] = [";".join(corners), "%s;%s;%s" % [corners[1], corners[2], corners[0]], "%s;%s;%s" % [corners[2], corners[0], corners[1]]]
		rotations.sort()
		signatures.append(rotations[0])
	signatures.sort()
	return signatures

static func match_retained(points: PackedVector3Array, uv: PackedVector2Array, hashes: Array[String], uv_shift: Vector2 = Vector2.ZERO, reverse: bool = false) -> Dictionary:
	var wanted: Dictionary[String, int] = {}
	for hash: String in hashes:
		wanted[hash] = wanted.get(hash, 0) + 1
	var retained: Array[String] = []
	for signature: String in signature_list(points, uv, uv_shift, reverse):
		var hash: String = signature.sha256_text()
		if wanted.get(hash, 0) > 0:
			retained.append(signature)
			wanted[hash] -= 1
	var missing: int = 0
	for hash: String in wanted:
		missing += wanted[hash]
	return {"triangles":retained.size(), "missing":missing, "position_uv_winding_sha256":"\n".join(retained).sha256_text(), "grid":GRID}
