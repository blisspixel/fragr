class_name ArchitectureMesh
extends RefCounted

const Workshop = preload("res://scripts/model_geometry.gd")

## Recessed wall bays remain inside the exact authoritative volume. Tops and
## end caps retain the original bounds; floors, steps and glass stay unchanged.
static func wall(size: Vector3) -> ArrayMesh:
	var g: RefCounted = Workshop.new()
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along_x: bool = size.x >= size.z
	var width: float = size.x if along_x else size.z
	var depth: float = size.z if along_x else size.x
	var count: int = clampi(ceili(width / 3.0), 1, 16)
	var y0: float = -size.y * 0.5
	var y1: float = size.y * 0.5
	for side: float in [-1.0, 1.0]:
		var face: Vector3 = Vector3(0, 0, side) if along_x else Vector3(side, 0, 0)
		var front: float = depth * 0.5 * side
		var inset: float = front - side * minf(0.18, depth * 0.3)
		for bay: int in range(count):
			var u0: float = -width * 0.5 + width * float(bay) / count
			var u1: float = -width * 0.5 + width * float(bay + 1) / count
			var border: float = minf(0.10, (u1 - u0) * 0.12)
			var outer: Array[Vector3] = [_point(u0, y0, front, along_x), _point(u1, y0, front, along_x),
				_point(u1, y1, front, along_x), _point(u0, y1, front, along_x)]
			var inner: Array[Vector3] = [_point(u0 + border, y0 + 0.17, inset, along_x),
				_point(u1 - border, y0 + 0.17, inset, along_x), _point(u1 - border, y1 - 0.13, inset, along_x),
				_point(u0 + border, y1 - 0.13, inset, along_x)]
			for edge: int in range(4):
				var next: int = (edge + 1) % 4
				var normal: Vector3 = (outer[next] - outer[edge]).cross(inner[next] - outer[edge]).normalized()
				if normal.dot(face) < 0.0:
					normal = -normal
				g.quad(tool, outer[edge], outer[next], inner[next], inner[edge], normal)
			g.quad(tool, inner[0], inner[1], inner[2], inner[3], face)
	for side: float in [-1.0, 1.0]:
		var u: float = side * width * 0.5
		g.quad(tool, _point(u, y0, -depth * 0.5, along_x), _point(u, y1, -depth * 0.5, along_x),
			_point(u, y1, depth * 0.5, along_x), _point(u, y0, depth * 0.5, along_x),
			Vector3(side, 0, 0) if along_x else Vector3(0, 0, side))
		var y: float = y1 if side > 0 else y0
		g.quad(tool, _point(-width * 0.5, y, -depth * 0.5, along_x), _point(width * 0.5, y, -depth * 0.5, along_x),
			_point(width * 0.5, y, depth * 0.5, along_x), _point(-width * 0.5, y, depth * 0.5, along_x), Vector3(0, side, 0))
	return tool.commit()

static func _point(u: float, y: float, depth: float, along_x: bool) -> Vector3:
	return Vector3(u, y, depth) if along_x else Vector3(depth, y, u)

## Recessed ceiling coffers keep the upper walking face flat and the entire
## visible structure inside the server's existing roof or floor slab.
static func ceiling(size: Vector3) -> ArrayMesh:
	var g: RefCounted = Workshop.new()
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0: float = -size.x * 0.5
	var x1: float = size.x * 0.5
	var z0: float = -size.z * 0.5
	var z1: float = size.z * 0.5
	var bottom: float = -size.y * 0.5
	var top: float = size.y * 0.5
	var recess: float = minf(0.22, size.y * 0.55)
	var columns: int = clampi(ceili(size.x / 2.4), 1, 16)
	var rows: int = clampi(ceili(size.z / 2.4), 1, 16)
	for column: int in range(columns):
		for row: int in range(rows):
			var left: float = lerpf(x0, x1, float(column) / columns)
			var right: float = lerpf(x0, x1, float(column + 1) / columns)
			var back: float = lerpf(z0, z1, float(row) / rows)
			var front: float = lerpf(z0, z1, float(row + 1) / rows)
			var outer: Array[Vector3] = [Vector3(left, bottom, back), Vector3(right, bottom, back), Vector3(right, bottom, front), Vector3(left, bottom, front)]
			var inner: Array[Vector3] = [Vector3(left + 0.12, bottom + recess, back + 0.12), Vector3(right - 0.12, bottom + recess, back + 0.12), Vector3(right - 0.12, bottom + recess, front - 0.12), Vector3(left + 0.12, bottom + recess, front - 0.12)]
			for edge: int in range(4):
				var next: int = (edge + 1) % 4
				var normal: Vector3 = (outer[next] - outer[edge]).cross(inner[next] - outer[edge]).normalized()
				if normal.y > 0:
					normal = -normal
				g.quad(tool, outer[edge], outer[next], inner[next], inner[edge], normal)
			g.quad(tool, inner[0], inner[1], inner[2], inner[3], Vector3.DOWN)
	g.quad(tool, Vector3(x0, top, z0), Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3(x0, top, z1), Vector3.UP)
	for side: float in [-1.0, 1.0]:
		var x: float = x1 if side > 0 else x0
		g.quad(tool, Vector3(x, bottom, z0), Vector3(x, top, z0), Vector3(x, top, z1), Vector3(x, bottom, z1), Vector3(side, 0, 0))
		var z: float = z1 if side > 0 else z0
		g.quad(tool, Vector3(x0, bottom, z), Vector3(x1, bottom, z), Vector3(x1, top, z), Vector3(x0, top, z), Vector3(0, 0, side))
	return tool.commit()
