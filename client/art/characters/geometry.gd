extends RefCounted

## Union issue, from docs/palette.json: black and dark steel with restrained
## red. Plates stay a step lighter than cloth so bodies never vanish indoors.
const PLATE: Color = Color8(86, 87, 94)
const CLOTH: Color = Color8(30, 30, 34)
const STEEL: Color = Color8(44, 45, 50)
const INK: Color = Color("171b1b")
const SKIN: Color = Color("b88965")
const RED: Color = Color8(140, 26, 30)
## Optics and visors: the only lit Union color, and every Union tell light.
const GLOW: Color = Color8(226, 52, 48)

var materials: Dictionary[Color, StandardMaterial3D] = {}

func material(color: Color) -> StandardMaterial3D:
	if not materials.has(color):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mat.roughness = 1.0
		mat.metallic_specular = 0.0
		materials[color] = mat
	return materials[color]

func triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	for point: Vector3 in [a, c, b]:
		surface.set_normal(normal)
		surface.add_vertex(point)

func bevel(size: Vector3, cut: float = 0.22, taper: float = 0.86) -> ArrayMesh:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for level: int in range(4):
		var y: float = [-0.5, -0.4, 0.4, 0.5][level] * size.y
		var inset: float = taper if level == 0 or level == 3 else 1.0
		var x: float = size.x * 0.5 * inset
		var z: float = size.z * 0.5 * inset
		var ring: PackedVector3Array = PackedVector3Array([
			Vector3(-x*(1-cut),y,-z), Vector3(x*(1-cut),y,-z),
			Vector3(x,y,-z*(1-cut)), Vector3(x,y,z*(1-cut)),
			Vector3(x*(1-cut),y,z), Vector3(-x*(1-cut),y,z),
			Vector3(-x,y,z*(1-cut)), Vector3(-x,y,-z*(1-cut))])
		rings.append(ring)
	for level: int in range(3):
		for side: int in range(8):
			var a: Vector3 = rings[level][side]
			var b: Vector3 = rings[level+1][side]
			var c: Vector3 = rings[level+1][(side+1)%8]
			var d: Vector3 = rings[level][(side+1)%8]
			var normal: Vector3 = (b-a).cross(c-a).normalized()
			triangle(surface,a,b,c,normal)
			triangle(surface,a,c,d,normal)
	for side: int in range(8):
		triangle(surface,Vector3(0,size.y*0.5,0),rings[3][(side+1)%8],rings[3][side],Vector3.UP)
		triangle(surface,Vector3(0,-size.y*0.5,0),rings[0][side],rings[0][(side+1)%8],Vector3.DOWN)
	return surface.commit()

func part(root: Node3D, at: Vector3, size: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = bevel(size)
	node.material_override = material(color)
	node.position = at
	node.rotation_degrees = rotation
	root.add_child(node)
	return node

func limb(root: Node3D, a: Vector3, b: Vector3, width: float, depth: float, color: Color) -> Node3D:
	var node: MeshInstance3D = part(root,(a+b)*0.5,Vector3(width,a.distance_to(b),depth),color)
	var axis: Vector3 = (a-b).normalized()
	node.quaternion = Quaternion(Vector3.UP,axis)
	return node

func joint(root: Node3D, at: Vector3, radius: float, color: Color) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	node.mesh = mesh
	node.material_override = material(color)
	node.position = at
	root.add_child(node)

func oval(root: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	node.mesh = mesh
	node.material_override = material(color)
	node.position = at
	node.scale = size
	root.add_child(node)
	return node

func sleeve(root: Node3D, a: Vector3, b: Vector3, width: float, depth: float, color: Color) -> Node3D:
	var node: MeshInstance3D = oval(root,(a+b)*0.5,Vector3(width,a.distance_to(b)*1.2,depth),color)
	node.quaternion = Quaternion(Vector3.UP,(a-b).normalized())
	return node

func helmet(root: Node3D) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous: PackedVector3Array = []
	for level: int in range(5):
		var ring: PackedVector3Array = []
		var radius: float = [1.0,1.0,0.90,0.62,0.05][level]
		for segment: int in range(12):
			var angle: float = TAU * float(segment)/12.0
			var height: float = [1.66,1.718,1.76,1.786,1.800][level]
			if level == 0:
				height += maxf(sin(angle),0.0)*0.072
			ring.append(Vector3(cos(angle)*0.149*radius,height,sin(angle)*0.137*radius-0.016))
		if level > 0:
			for segment: int in range(12):
				var a: Vector3 = previous[segment]
				var b: Vector3 = ring[segment]
				var c: Vector3 = ring[(segment+1)%12]
				var d: Vector3 = previous[(segment+1)%12]
				var normal: Vector3 = (b-a).cross(c-a).normalized()
				triangle(surface,a,b,c,normal)
				triangle(surface,a,c,d,normal)
		previous = ring
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = surface.commit()
	node.material_override = material(PLATE)
	root.add_child(node)
	part(root,Vector3(0,1.722,0.135),Vector3(0.258,0.024,0.078),PLATE,Vector3(-6,0,0))
	part(root,Vector3(0,1.705,-0.143),Vector3(0.145,0.085,0.018),CLOTH)

func gun(root: Node3D, at: Vector3, bot: bool, raise: float) -> void:
	var weapon: Node3D = Node3D.new()
	root.add_child(weapon)
	weapon.position = at
	# The pistol hangs, then points out past the shoulder. The rifle stays a horizontal bar.
	weapon.rotation_degrees.x = lerpf(72.0 if not bot else 6.0, 0.0, raise)
	if not bot:
		weapon.rotation_degrees.y = lerpf(0.0, 78.0, raise)
	if bot:
		part(weapon,Vector3(0,0.02,0.12),Vector3(0.12,0.10,0.40),STEEL)
		part(weapon,Vector3(0,0.07,0.08),Vector3(0.09,0.045,0.26),PLATE.darkened(0.12))
		part(weapon,Vector3(0,-0.04,-0.02),Vector3(0.08,0.12,0.10),INK)
		part(weapon,Vector3(0,0.02,0.32),Vector3(0.07,0.07,0.12),INK)
	else:
		part(weapon,Vector3(0,0,0.05),Vector3(0.07,0.09,0.16),STEEL)
		part(weapon,Vector3(0,-0.07,-0.02),Vector3(0.055,0.14,0.06),INK,Vector3(-12,0,0))
		part(weapon,Vector3(0,0.02,0.14),Vector3(0.045,0.045,0.08),INK)
	if bot:
		part(weapon,Vector3(0,-0.12,0.1),Vector3(0.074,0.20,0.13),STEEL,Vector3(-8,0,0))
		part(weapon,Vector3(0,0,-0.19),Vector3(0.095,0.10,0.17),CLOTH)
		for z: float in [0.07,0.12,0.17]:
			part(weapon,Vector3(0,0.048,z),Vector3(0.115,0.019,0.014),INK)
