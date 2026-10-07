extends SceneTree

const Metadata = preload("res://art/models/glb_metadata.gd")
const MODELS: Dictionary = {
	"boat": {"source": "island-fast-boat-v1-20261006-0.glb", "sha": "b75e51cd8a1d6b076ddd87189d77ef5d776179c6b2ca306e900e6ba3caf6fb86", "vertices": 17079, "triangles": 11884, "size": Vector3(4.8, 2.2, 2.2), "base": -0.6},
	"light_aircraft": {"source": "island-prop-aircraft-v1-20261006-0.glb", "sha": "7cf20a50892e827aef1084699cd0983cedfd72fc71afcd8eba6247ab3a9bc876", "vertices": 14820, "triangles": 11757, "size": Vector3(8.0, 2.75, 9.2), "base": 0.0},
}

func _initialize() -> void:
	set_meta("fragr_automated", true)
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		_fail("require reviewed source directory")
		return
	for kind: String in MODELS:
		if not _prepare(kind, args[0]):
			return
	print("prepare_transport_sources: PASS (inspected body geometry and repaired aircraft propeller; motion acceptance remains open)")
	quit(0)

func _prepare(kind: String, directory: String) -> bool:
	var spec: Dictionary = MODELS[kind]
	var source_path: String = directory.path_join(spec.source)
	if FileAccess.get_sha256(source_path) != spec.sha:
		return _fail("source hash changed: " + kind)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
	var metadata: Variant = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
	if not metadata is Dictionary or not metadata.get("asset") is Dictionary:
		return _fail("invalid source metadata")
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	if document.append_from_file(source_path, state) != OK:
		return _fail("source import failed")
	var original: Node3D = document.generate_scene(state)
	root.add_child(original)
	var meshes: Array[Node] = original.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1:
		return _fail("source mesh count changed")
	var source: MeshInstance3D = meshes[0] as MeshInstance3D
	var arrays: Array = source.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.size() != spec.vertices or indices.size() != int(spec.triangles) * 3:
		return _fail("source geometry changed")
	var bounds: AABB = source.global_transform * source.mesh.get_aabb()
	var pivot: Vector3 = Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var size: Vector3 = spec.size
	var shape: Basis = Basis(Vector3.UP, PI).scaled(size / bounds.size)
	var normal_basis: Basis = shape.inverse().transposed()
	var paint_material: StandardMaterial3D = source.get_active_material(0).duplicate() as StandardMaterial3D
	var paint: Image = paint_material.albedo_texture.get_image()
	if paint.is_compressed() and paint.decompress() != OK:
		return _fail("paint decode failed")
	paint.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	paint.convert(Image.FORMAT_RGBA8)
	for y: int in range(512):
		for x: int in range(512):
			var color: Color = paint.get_pixel(x, y)
			color.r = snappedf(color.r, 1.0 / 24.0)
			color.g = snappedf(color.g, 1.0 / 24.0)
			color.b = snappedf(color.b, 1.0 / 24.0)
			paint.set_pixel(x, y, color)
	paint_material.albedo_texture = ImageTexture.create_from_image(paint)
	paint_material.normal_enabled = false
	paint_material.normal_texture = null
	paint_material.metallic_texture = null
	paint_material.roughness_texture = null
	paint_material.metallic = 0.0
	paint_material.roughness = 1.0
	paint_material.metallic_specular = 0.0
	paint_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = Color(0.50, 0.66, 0.65, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 1.0
	glass.metallic_specular = 0.0
	var positions: PackedVector3Array = []
	for vertex: Vector3 in vertices:
		positions.append(shape * (source.global_transform * vertex - pivot) + Vector3(0, spec.base, 0))
	# The source propeller is fused into the body. Remove the entire forward tip
	# and replace it with a complete cowl and balanced rotor. A partial source
	# partition was inspected and rejected because blades remained on the body.
	var prop_hub: Vector3 = Vector3(3.78, 1.28, 0)
	var counts: Array[int] = [0, 0, 0]
	var surfaces: Array[SurfaceTool] = []
	for _index: int in range(3):
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces.append(surface)
	for triangle: int in range(0, indices.size(), 3):
		var a: Vector3 = positions[indices[triangle]]
		var b: Vector3 = positions[indices[triangle + 1]]
		var c: Vector3 = positions[indices[triangle + 2]]
		if kind == "light_aircraft" and maxf(a.x, maxf(b.x, c.x)) > 3.25:
			counts[1] += 1
			continue
		var center: Vector3 = (a + b + c) / 3.0
		var face: Vector3 = (b - a).cross(c - a).normalized()
		var window: bool = kind == "light_aircraft" and center.x > 1.53 and center.x < 2.13 and center.y > 1.68 and center.y < 2.11 and absf(center.z) < 0.49 and absf(face.x) > 0.30 and absf(face.y) > 0.35
		var slot: int = 2 if window else 0
		counts[slot] += 1
		for corner: int in range(3):
			var vertex_index: int = indices[triangle + corner]
			var at: Vector3 = positions[vertex_index]
			surfaces[slot].set_normal((normal_basis * source.global_basis * normals[vertex_index]).normalized())
			surfaces[slot].set_uv(uv[vertex_index])
			surfaces[slot].add_vertex(at)
	if kind == "light_aircraft" and (counts[1] < 200 or counts[1] > 1500):
		return _fail("aircraft nose repair outside inspected budget")
	var result: Node3D = Node3D.new()
	result.name = "IslandBoat" if kind == "boat" else "CourierAircraft"
	root.add_child(result)
	for index: int in [0, 2]:
		if counts[index] == 0:
			continue
		surfaces[index].index()
		surfaces[index].generate_tangents()
		var part: MeshInstance3D = MeshInstance3D.new()
		part.name = "Windscreen" if index == 2 else "Chassis"
		part.mesh = surfaces[index].commit()
		part.material_override = glass if index == 2 else paint_material
		result.add_child(part)
	var authored: int = 0
	if kind == "light_aircraft":
		authored = _aircraft_tip(result, prop_hub)
	var final_bounds: AABB = AABB()
	var first_part: bool = true
	for item: Node in result.find_children("*", "MeshInstance3D", true, false):
		var mesh_part: MeshInstance3D = item as MeshInstance3D
		var part_bounds: AABB = mesh_part.global_transform * mesh_part.mesh.get_aabb()
		final_bounds = part_bounds if first_part else final_bounds.merge(part_bounds)
		first_part = false
	var output: String = ProjectSettings.globalize_path("res://assets/vehicles")
	DirAccess.make_dir_recursive_absolute(output)
	var exporter: GLTFDocument = GLTFDocument.new()
	exporter.image_format = "PNG"
	var exported: GLTFState = GLTFState.new()
	var path: String = output.path_join(kind + ".glb")
	if exporter.append_from_scene(result, exported) != OK or exporter.write_to_filesystem(exported, path) != OK or not Metadata.clean(path, str(metadata.asset.get("copyright", ""))):
		return _fail("cannot export legal source")
	var receipt: FileAccess = FileAccess.open(output.path_join(kind + ".json"), FileAccess.WRITE)
	if receipt == null:
		return _fail("cannot write receipt")
	receipt.store_string(JSON.stringify({"schema": 1, "source_sha256": spec.sha, "prepared_sha256": FileAccess.get_sha256(path), "source_triangles": spec.triangles, "retained_triangles": counts[0] + counts[2], "glass_triangles": counts[2], "removed_triangles": counts[1], "authored_triangles": authored, "triangles": counts[0] + counts[2] + authored, "registered_bounds_m": {"size": [size.x, size.y, size.z], "base": spec.base}, "mesh_bounds_m": {"position": [final_bounds.position.x, final_bounds.position.y, final_bounds.position.z], "size": [final_bounds.size.x, final_bounds.size.y, final_bounds.size.z]}, "albedo_pixels": 512, "source_geometry_retained": kind == "boat", "repair": "complete balanced propeller, forward cowl and clear windscreen" if kind == "light_aircraft" else "none", "motion_acceptance": false}, "\t") + "\n")
	receipt.close()
	print(kind, " retained/removed ", counts, " authored ", authored)
	original.free()
	result.free()
	return true

func _aircraft_tip(parent: Node3D, hub: Vector3) -> int:
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color("424743")
	dark.roughness = 1.0
	dark.metallic_specular = 0.0
	var tip: StandardMaterial3D = dark.duplicate()
	tip.albedo_color = Color("c0a76b")
	var cowl: CylinderMesh = CylinderMesh.new()
	cowl.top_radius = 0.19
	cowl.bottom_radius = 0.46
	cowl.height = 0.86
	cowl.radial_segments = 12
	cowl.rings = 1
	var nose: MeshInstance3D = MeshInstance3D.new()
	nose.name = "RepairedCowl"
	nose.mesh = cowl
	nose.material_override = dark
	nose.position = Vector3(3.30, hub.y, 0)
	nose.rotation.z = -PI / 2
	nose.scale.z = 0.9
	parent.add_child(nose)
	var rotor: Node3D = Node3D.new()
	rotor.name = "Propeller"
	rotor.position = hub
	parent.add_child(rotor)
	var triangles: int = cowl.get_faces().size() / 3
	for side: float in [-1.0, 1.0]:
		for section: int in range(2):
			var blade: MeshInstance3D = MeshInstance3D.new()
			blade.name = "Blade%d%s" % [int(side), "Tip" if section else "Root"]
			var box: BoxMesh = BoxMesh.new()
			box.size = Vector3(0.045, 0.11 if section else 0.16, 0.16 if section else 0.63)
			blade.mesh = box
			blade.material_override = tip if section else dark
			blade.position = Vector3(0, 0, side * (0.855 if section else 0.46))
			rotor.add_child(blade)
			triangles += box.get_faces().size() / 3
	return triangles

func _fail(message: String) -> bool:
	push_error("prepare_transport_sources: " + message)
	quit(1)
	return false
