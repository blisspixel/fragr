extends RefCounted

## Art style trial only. Repaints the free synthetic body in one player-chosen
## personal scheme so the trial's free agent obeys the faction readability
## contract (docs/ART_STORY_BIBLE.md): a free body never wears a matte
## off-white dominant base, which is reserved for the Inheritance. The shipped
## source keeps its clean bone panels; Treatment S shows that divergence as
## shipped, and A, B and C wear this scheme.
##
## The repaint is value preserving: light, low-saturation panel texels take a
## worn mustard paint scaled by their own value, so the source's wear, seams
## and shading survive. Dark steel, rust and the screen face are untouched.

## Worn mustard: warm, individual, far from Union black and red, from the
## Inheritance's matte off-white and from the free human's leather jacket, so
## two free bodies never read as one uniform.
const PAINT: Color = Color(0.74, 0.56, 0.24)
const PANEL_MIN_VALUE: float = 0.52
const PANEL_MAX_SATURATION: float = 0.24
## Bone panels in the source sit near this value; it maps to full PAINT.
const PANEL_REFERENCE_VALUE: float = 0.86

static var _painted: Dictionary[int, ImageTexture] = {}

## Swaps every StandardMaterial3D albedo map under `node` for its painted copy.
static func apply(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var override: StandardMaterial3D = mesh_node.material_override as StandardMaterial3D
		if override != null:
			mesh_node.material_override = _painted_material(override)
		elif mesh_node.mesh != null:
			for surface: int in range(mesh_node.mesh.get_surface_count()):
				var original: StandardMaterial3D = mesh_node.get_active_material(surface) as StandardMaterial3D
				if original != null:
					mesh_node.set_surface_override_material(surface, _painted_material(original))
	for child: Node in node.get_children():
		apply(child)

static func _painted_material(original: StandardMaterial3D) -> StandardMaterial3D:
	if original.albedo_texture == null:
		return original
	var material: StandardMaterial3D = original.duplicate() as StandardMaterial3D
	material.albedo_texture = painted(original.albedo_texture)
	return material

static func painted(texture: Texture2D) -> ImageTexture:
	var key: int = texture.get_instance_id()
	if _painted.has(key):
		return _painted[key]
	var image: Image = texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = image.get_data()
	for at: int in range(0, data.size(), 4):
		var colour: Color = Color8(data[at], data[at + 1], data[at + 2])
		if colour.v < PANEL_MIN_VALUE or colour.s > PANEL_MAX_SATURATION:
			continue
		var paint: Color = PAINT * minf(1.0, colour.v / PANEL_REFERENCE_VALUE)
		data[at] = clampi(roundi(paint.r * 255.0), 0, 255)
		data[at + 1] = clampi(roundi(paint.g * 255.0), 0, 255)
		data[at + 2] = clampi(roundi(paint.b * 255.0), 0, 255)
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)
	var result: ImageTexture = ImageTexture.create_from_image(image)
	_painted[key] = result
	return result
