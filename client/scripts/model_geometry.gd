extends RefCounted

## Offline mesh authoring. Dimensions are metres; +Z is the stock end of a gun.
var _materials: Dictionary[String, StandardMaterial3D] = {}
var _textures: Dictionary[String, Texture2D] = {}

func material(key: String, tint: Color, metallic: float = 0.0, roughness: float = 0.72) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.resource_name = key
	result.albedo_color = tint
	result.metallic = metallic
	result.roughness = roughness
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	result.albedo_texture = _grain("wood" if key.contains("wood") else ("enamel" if key.contains("bone") else "metal"))
	_materials[key] = result
	return result

func _grain(kind: String) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	var path: String = "res://assets/models/finishes/" + kind + ".png"
	if ResourceLoader.exists(path):
		var reviewed: Resource = load(path)
		if reviewed is Texture2D:
			_textures[kind] = reviewed as Texture2D
			return _textures[kind]
	var image: Image = Image.create(128, 128, false, Image.FORMAT_RGB8)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 67043
	noise.frequency = 0.08
	for y: int in range(128):
		for x: int in range(128):
			var n: float = noise.get_noise_2d(x * 0.22 if kind == "wood" else x, y)
			var grain: float = sin(float(y) * 0.67 + n * 7.0) * 0.04 if kind == "wood" else 0.0
			var value: float = snappedf(clampf(0.91 + n * 0.11 + grain, 0.7, 1.0), 1.0 / 24.0)
			image.set_pixel(x, y, Color(value, value, value))
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	texture.resource_name = kind + "_grain"
	_textures[kind] = texture
	return texture

func triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var vertices: Array[Vector3] = [a, b, c]
	# Godot front faces use clockwise winding.
	if (b - a).cross(c - a).dot(normal) > 0.0:
		vertices = [a, c, b]
	for vertex: Vector3 in vertices:
		tool.set_normal(normal)
		var axis: Vector3 = normal.abs()
		var uv: Vector2 = Vector2(vertex.z, vertex.y) if axis.x > axis.y and axis.x > axis.z else (Vector2(vertex.x, vertex.z) if axis.y > axis.z else Vector2(vertex.x, vertex.y))
		tool.set_uv(uv * 5.0)
		tool.add_vertex(vertex)

func quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	triangle(tool, a, b, c, normal)
	triangle(tool, a, c, d, normal)

func instance(parent: Node3D, label: String, mesh: Mesh, finish: StandardMaterial3D, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = finish
	node.position = at
	parent.add_child(node)
	return node

## A shaped side outline in (Z,Y), with chamfered side faces across X.
func prism(parent: Node3D, label: String, outline: PackedVector2Array, width: float, finish: StandardMaterial3D, at: Vector3 = Vector3.ZERO, bevel: float = 0.12) -> MeshInstance3D:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center: Vector2 = Vector2.ZERO
	for point: Vector2 in outline:
		center += point
	center /= outline.size()
	var rings: Array[PackedVector3Array] = []
	for level: int in range(4):
		var x: float = [-0.5, -0.5 + bevel, 0.5 - bevel, 0.5][level] * width
		var inset: float = 0.96 if level in [0, 3] else 1.0
		var ring: PackedVector3Array = []
		for point: Vector2 in outline:
			var shaped: Vector2 = center + (point - center) * inset
			ring.append(Vector3(x, shaped.y, shaped.x))
		rings.append(ring)
	var clockwise: bool = Geometry2D.is_polygon_clockwise(outline)
	for level: int in range(3):
		for edge: int in range(outline.size()):
			var next: int = (edge + 1) % outline.size()
			var a: Vector3 = rings[level][edge]
			var b: Vector3 = rings[level + 1][edge]
			var c: Vector3 = rings[level + 1][next]
			var d: Vector3 = rings[level][next]
			var normal: Vector3 = (b - a).cross(c - a).normalized() * (-1.0 if clockwise else 1.0)
			quad(tool, a, b, c, d, normal)
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for edge: int in range(0, indices.size(), 3):
		for end: int in [0, 3]:
			triangle(tool, rings[end][indices[edge]], rings[end][indices[edge + 1]], rings[end][indices[edge + 2]], Vector3.LEFT if end == 0 else Vector3.RIGHT)
	return instance(parent, label, tool.commit(), finish, at)

func block(parent: Node3D, label: String, size: Vector3, finish: StandardMaterial3D, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var y: float = size.y * 0.5
	var z: float = size.z * 0.5
	var c: float = minf(y, z) * 0.16
	return prism(parent, label, PackedVector2Array([Vector2(-z + c, -y), Vector2(z - c, -y), Vector2(z, -y + c), Vector2(z, y - c), Vector2(z - c, y), Vector2(-z + c, y), Vector2(-z, y - c), Vector2(-z, -y + c)]), size.x, finish, at)

## Revolved cross-section around Z. A closed profile makes real hollow bores.
func lathe(parent: Node3D, label: String, profile: PackedVector2Array, finish: StandardMaterial3D, at: Vector3 = Vector3.ZERO, segments: int = 24) -> MeshInstance3D:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for band: int in range(profile.size()):
		var p: Vector2 = profile[band]
		var q: Vector2 = profile[(band + 1) % profile.size()]
		for side: int in range(segments):
			var angle: float = TAU * float(side) / segments
			var next_angle: float = TAU * float(side + 1) / segments
			var a: Vector3 = Vector3(cos(angle) * p.y, sin(angle) * p.y, p.x)
			var b: Vector3 = Vector3(cos(angle) * q.y, sin(angle) * q.y, q.x)
			var c: Vector3 = Vector3(cos(next_angle) * q.y, sin(next_angle) * q.y, q.x)
			var d: Vector3 = Vector3(cos(next_angle) * p.y, sin(next_angle) * p.y, p.x)
			var mid: float = (angle + next_angle) * 0.5
			var slope: Vector2 = q - p
			var normal: Vector3 = Vector3(cos(mid) * slope.x, sin(mid) * slope.x, -slope.y).normalized()
			quad(tool, a, b, c, d, normal)
	return instance(parent, label, tool.commit(), finish, at)

func cylinder(parent: Node3D, label: String, radius: float, length: float, finish: StandardMaterial3D, at: Vector3 = Vector3.ZERO, segments: int = 20) -> MeshInstance3D:
	return lathe(parent, label, PackedVector2Array([Vector2(-length * 0.5, 0.0), Vector2(-length * 0.5, radius * 0.94), Vector2(-length * 0.47, radius), Vector2(length * 0.47, radius), Vector2(length * 0.5, radius * 0.94), Vector2(length * 0.5, 0.0)]), finish, at, segments)

## Elliptical contour rings: (height, half width, half depth). This supplies
## tapered manufactured shells rather than scaled boxes or intersecting balls.
func hull(parent: Node3D, label: String, profile: PackedVector3Array, finish: StandardMaterial3D, at: Vector3 = Vector3.ZERO, segments: int = 16) -> MeshInstance3D:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for point: Vector3 in profile:
		var ring: PackedVector3Array = []
		for index: int in range(segments):
			var angle: float = TAU * float(index) / segments
			ring.append(Vector3(cos(angle) * point.y, point.x, sin(angle) * point.z))
		rings.append(ring)
	for band: int in range(rings.size() - 1):
		for index: int in range(segments):
			var next: int = (index + 1) % segments
			var a: Vector3 = rings[band][index]
			var b: Vector3 = rings[band + 1][index]
			var c: Vector3 = rings[band + 1][next]
			var d: Vector3 = rings[band][next]
			var normal: Vector3 = (b - a).cross(c - a).normalized()
			quad(tool, a, b, c, d, normal)
	for end: int in [0, rings.size() - 1]:
		for index: int in range(segments):
			triangle(tool, Vector3(0, profile[end].x, 0), rings[end][index], rings[end][(index + 1) % segments], Vector3.DOWN if end == 0 else Vector3.UP)
	return instance(parent, label, tool.commit(), finish, at)

func rod(parent: Node3D, label: String, a: Vector3, b: Vector3, radius: float, finish: StandardMaterial3D, segments: int = 12) -> MeshInstance3D:
	var node: MeshInstance3D = cylinder(parent, label, radius, a.distance_to(b), finish, (a + b) * 0.5, segments)
	node.quaternion = Quaternion(Vector3.BACK, (b - a).normalized())
	return node

func pipe(parent: Node3D, label: String, points: PackedVector3Array, radius: float, finish: StandardMaterial3D) -> MeshInstance3D:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for index: int in range(points.size()):
		var tangent: Vector3 = (points[mini(index + 1, points.size() - 1)] - points[maxi(0, index - 1)]).normalized()
		var basis_x: Vector3 = tangent.cross(Vector3.RIGHT if absf(tangent.dot(Vector3.UP)) > 0.9 else Vector3.UP).normalized()
		var basis_y: Vector3 = tangent.cross(basis_x).normalized()
		var ring: PackedVector3Array = []
		for side: int in range(12):
			var angle: float = TAU * float(side) / 12.0
			ring.append(points[index] + (basis_x * cos(angle) + basis_y * sin(angle)) * radius)
		rings.append(ring)
	for band: int in range(rings.size() - 1):
		for side: int in range(12):
			var next: int = (side + 1) % 12
			var normal: Vector3 = ((rings[band][side] + rings[band][next]) * 0.5 - points[band]).normalized()
			quad(tool, rings[band][side], rings[band + 1][side], rings[band + 1][next], rings[band][next], normal)
	return instance(parent, label, tool.commit(), finish)

func group(parent: Node3D, label: String, at: Vector3 = Vector3.ZERO) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = label
	node.position = at
	parent.add_child(node)
	return node

## Collapse static fixture pieces into one mesh with one surface per finish.
func merge(parent: Node3D) -> void:
	var surfaces: Dictionary[int, SurfaceTool] = {}
	var pieces: Array[MeshInstance3D] = []
	for child: Node in parent.get_children():
		if not child is MeshInstance3D:
			continue
		var piece: MeshInstance3D = child
		var finish: Material = piece.material_override
		var key: int = finish.get_instance_id()
		if not surfaces.has(key):
			var tool: SurfaceTool = SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.set_material(finish)
			surfaces[key] = tool
		for index: int in range(piece.mesh.get_surface_count()):
			surfaces[key].append_from(piece.mesh, index, piece.transform)
		pieces.append(piece)
	var mesh: ArrayMesh = ArrayMesh.new()
	for key: int in surfaces:
		surfaces[key].commit(mesh)
	for piece: MeshInstance3D in pieces:
		piece.free()
	instance(parent, "FixtureMesh", mesh, null)
